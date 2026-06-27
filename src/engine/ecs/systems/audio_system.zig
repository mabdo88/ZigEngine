//! Owns the single AudioEngine + AudioClipCache for the World (mirrors
//! PhysicsSyncSystem owning the single PhysicsWorld), publishing both
//! through audio_shared.zig for other code (gameplay, future Audio3DSystem)
//! to read. Each frame, plays any AudioSourceComponent with auto_play set
//! that hasn't been played yet.
const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;
const audio_device = @import("../../../audio/audio_device.zig");
const audio_cache = @import("../../../audio/audio_cache.zig");
const audio_shared = @import("../../../audio/audio_shared.zig");

pub const AudioSystemState = struct {
    engine: audio_device.AudioEngine,
    clips: audio_cache.AudioClipCache,

    pub fn update(self: *AudioSystemState, registry: *Registry, _: f32) anyerror!void {
        var it = registry.Query(.{components.AudioSourceComponent});
        while (it.next()) |entity| {
            const src = registry.get(components.AudioSourceComponent, entity).?;
            if (!src.auto_play or src.playing) continue;

            const clip = self.clips.get(src.clip_id) orelse continue;
            audio_device.ma.ma_sound_set_volume(&clip.sound, src.volume);
            try audio_device.clipPlay(clip);
            src.playing = true;
        }
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *AudioSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(AudioSystemState);
    // engine is initialized in place (not via a returned-by-value AudioEngine
    // assigned into this struct literal) — see AudioEngine.init's doc comment
    // for why a by-value copy after ma_engine_init corrupts the engine.
    try state.engine.init();
    state.clips = audio_cache.AudioClipCache.init(ctx.allocator);
    audio_shared.engine = &state.engine;
    audio_shared.clip_cache = &state.clips;
    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *AudioSystemState = @ptrCast(@alignCast(ctx));
    audio_shared.engine = null;
    audio_shared.clip_cache = null;
    state.clips.deinit();
    state.engine.deinit();
    allocator.destroy(state);
}

test "AudioSystem plays an auto_play source exactly once" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    // Headless engine (no real playback device) so this test can't hang or
    // fail on a machine/CI runner with no audio hardware — see
    // AudioEngine.initHeadless's doc comment. Initialized in place (not
    // returned by value) for the same reason create() does above.
    var state: AudioSystemState = undefined;
    try state.engine.initHeadless();
    state.clips = audio_cache.AudioClipCache.init(allocator);
    defer {
        state.clips.deinit();
        state.engine.deinit();
    }
    const ctx: *anyopaque = @ptrCast(&state);

    const clip_id = try state.clips.register(&state.engine, "assets/audio/test.wav");

    const e = try reg.create();
    try reg.add(e, components.AudioSourceComponent{ .clip_id = clip_id, .auto_play = true });

    try update(&reg, ctx, 1.0 / 60.0);
    try std.testing.expect(reg.get(components.AudioSourceComponent, e).?.playing);

    try update(&reg, ctx, 1.0 / 60.0);
    try std.testing.expect(reg.get(components.AudioSourceComponent, e).?.playing);
}
