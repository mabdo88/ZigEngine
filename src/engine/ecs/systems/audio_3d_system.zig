//! Positions the listener at the camera and spatializes any
//! AudioSourceComponent marked `spatialized`, using the entity's
//! FinalTransformComponent (falling back to TransformComponent if it has
//! neither) for world position. Priority 61 — after CameraSystem (3, so this
//! frame's camera position/target are current) and after Hierarchy (60, so
//! FinalTransformComponent already reflects this frame's parent-chain
//! concatenation rather than lagging a frame behind).
const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;
const math = @import("../../math.zig");
const audio_device = @import("../../../audio/audio_device.zig");
const audio_shared = @import("../../../audio/audio_shared.zig");

pub fn update(registry: *Registry, _: *anyopaque, _: f32) anyerror!void {
    const ma = audio_device.ma;
    const engine = audio_shared.engine orelse return;

    var cam_it = registry.Query(.{components.CameraComponent});
    if (cam_it.next()) |cam_entity| {
        const camera = registry.get(components.CameraComponent, cam_entity).?;
        const dir = math.normalize(camera.target - camera.position);
        ma.ma_engine_listener_set_position(&engine.engine, 0, mirrorX(camera.position[0]), camera.position[1], camera.position[2]);
        ma.ma_engine_listener_set_direction(&engine.engine, 0, mirrorX(dir[0]), dir[1], dir[2]);
        ma.ma_engine_listener_set_world_up(&engine.engine, 0, mirrorX(camera.up[0]), camera.up[1], camera.up[2]);
    }

    const clips = audio_shared.clip_cache orelse return;
    var it = registry.Query(.{components.AudioSourceComponent});
    while (it.next()) |entity| {
        const src = registry.get(components.AudioSourceComponent, entity).?;
        const clip = clips.get(src.clip_id) orelse continue;

        ma.ma_sound_set_spatialization_enabled(&clip.sound, if (src.spatialized) ma.MA_TRUE else ma.MA_FALSE);
        if (!src.spatialized) continue;

        ma.ma_sound_set_rolloff(&clip.sound, src.rolloff);
        ma.ma_sound_set_min_distance(&clip.sound, src.min_distance);
        ma.ma_sound_set_max_distance(&clip.sound, src.max_distance);

        if (registry.get(components.FinalTransformComponent, entity)) |ft| {
            const m = ft.matrix;
            ma.ma_sound_set_position(&clip.sound, mirrorX(m[3][0]), m[3][1], m[3][2]);
        } else if (registry.get(components.TransformComponent, entity)) |t| {
            ma.ma_sound_set_position(&clip.sound, mirrorX(t.position[0]), t.position[1], t.position[2]);
        }
    }
}

/// miniaudio's spatializer pans a sound's *world-space* +X as the right
/// channel (see g_maChannelDirections in miniaudio.h: FRONT_RIGHT is
/// {+0.7071, 0, -0.7071}), which on real hardware was confirmed to come out
/// mirrored against our renderer's own +X-is-screen-right convention (the
/// same `cross(forward, up)` math camera_system.zig already uses for
/// strafing) — verified by ear: a source placed at the engine's "RIGHT"
/// position played from the left speaker. There's no public engine-level
/// setter for `ma_spatializer_listener_config.handedness` (the field that
/// exists for exactly this kind of convention mismatch) to flip this for us,
/// so we negate every X coordinate handed to miniaudio ourselves instead —
/// equivalent to setting that handedness flag, just done at the call site.
/// Every vector we pass in (listener position, direction, world up, and
/// sound position) needs this for the math to stay internally consistent,
/// not just the sound position.
fn mirrorX(x: f32) f32 {
    return -x;
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const slot = try ctx.allocator.create(u8);
    slot.* = 0;
    return @ptrCast(slot);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const slot: *u8 = @ptrCast(@alignCast(ctx));
    allocator.destroy(slot);
}

test "Audio3DSystem positions the listener at the camera" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var engine: audio_device.AudioEngine = undefined;
    try engine.initHeadless();
    defer engine.deinit();
    var clips = @import("../../../audio/audio_cache.zig").AudioClipCache.init(allocator);
    defer clips.deinit();
    audio_shared.engine = &engine;
    audio_shared.clip_cache = &clips;
    defer {
        audio_shared.engine = null;
        audio_shared.clip_cache = null;
    }

    const cam_entity = try reg.create();
    try reg.add(cam_entity, components.CameraComponent{
        .position = .{ 1.0, 2.0, 3.0 },
        .target = .{ 1.0, 2.0, 4.0 },
        .up = .{ 0.0, 1.0, 0.0 },
    });

    var ctx_slot: u8 = 0;
    try update(&reg, @ptrCast(&ctx_slot), 0.0);

    const ma = audio_device.ma;
    const pos = ma.ma_engine_listener_get_position(&engine.engine, 0);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), pos.x, 1e-5); // mirrored, see mirrorX's doc comment
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), pos.y, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), pos.z, 1e-5);
}

test "Audio3DSystem disables spatialization for non-spatialized sources and positions spatialized ones" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var engine: audio_device.AudioEngine = undefined;
    try engine.initHeadless();
    defer engine.deinit();
    var clips = @import("../../../audio/audio_cache.zig").AudioClipCache.init(allocator);
    defer clips.deinit();
    audio_shared.engine = &engine;
    audio_shared.clip_cache = &clips;
    defer {
        audio_shared.engine = null;
        audio_shared.clip_cache = null;
    }

    // Two distinct clips (sharing one clip_id would mean sharing one
    // underlying ma_sound, which can't simultaneously be both spatialized
    // and not) — registered from different files so the cache doesn't dedup
    // them to the same id.
    const spatial_clip_id = try clips.register(&engine, "assets/audio/test.wav");
    const flat_clip_id = try clips.register(&engine, "assets/audio/ultrakill-glassbreak.mp3");

    const spatial_e = try reg.create();
    try reg.add(spatial_e, components.AudioSourceComponent{ .clip_id = spatial_clip_id, .spatialized = true });
    try reg.add(spatial_e, components.TransformComponent{ .position = .{ 5.0, 0.0, 0.0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });

    const flat_e = try reg.create();
    try reg.add(flat_e, components.AudioSourceComponent{ .clip_id = flat_clip_id, .spatialized = false });

    var ctx_slot: u8 = 0;
    try update(&reg, @ptrCast(&ctx_slot), 0.0);

    const ma = audio_device.ma;
    const spatial_clip = clips.get(spatial_clip_id).?;
    try std.testing.expect(ma.ma_sound_is_spatialization_enabled(&spatial_clip.sound) != 0);
    const pos = ma.ma_sound_get_position(&spatial_clip.sound);
    try std.testing.expectApproxEqAbs(@as(f32, -5.0), pos.x, 1e-5); // mirrored, see mirrorX's doc comment

    const flat_clip = clips.get(flat_clip_id).?;
    try std.testing.expect(ma.ma_sound_is_spatialization_enabled(&flat_clip.sound) == 0);
}
