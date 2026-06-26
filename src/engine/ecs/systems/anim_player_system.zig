const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;
const clip_mod = @import("../../../animation/clip.zig");
const skeleton_mod = @import("../../../animation/skeleton.zig");
const math = @import("../../math.zig");

pub const AnimPlayerSystemState = struct {
    pub fn update(self: *AnimPlayerSystemState, registry: *Registry, dt: f32) anyerror!void {
        _ = self;
        var it = registry.Query(.{ components.AnimPlayerComponent, components.SkeletonComponent, components.PoseBufferComponent });
        while (it.next()) |entity| {
            const player = registry.get(components.AnimPlayerComponent, entity).?;
            const skel_comp = registry.get(components.SkeletonComponent, entity).?;
            const pose_comp = registry.get(components.PoseBufferComponent, entity).?;

            const sk = registry.skeleton_cache.get(skel_comp.skeleton_id) orelse continue;
            const c = registry.clip_cache.get(player.clip_id) orelse continue;

            player.time += dt * player.speed;
            if (c.duration > 0) {
                if (player.loop) {
                    player.time = @mod(player.time, c.duration);
                } else {
                    player.time = @min(player.time, c.duration);
                }
            }

            @memcpy(pose_comp.poses, sk.rest_local_poses);
            clip_mod.sampleClip(c, player.time, pose_comp.poses);

            const world_comp = registry.get(components.JointWorldComponent, entity);
            const palette_comp = registry.get(components.SkinPaletteComponent, entity);
            if (world_comp != null or palette_comp != null) {
                var local_mats: [skeleton_mod.MAX_JOINTS][4][4]f32 = undefined;
                for (pose_comp.poses, 0..) |p, i| local_mats[i] = p.toMatrix();

                var world_buf: [skeleton_mod.MAX_JOINTS][4][4]f32 = undefined;
                const world = if (world_comp) |wc| wc.matrices else world_buf[0..sk.joint_count];
                skeleton_mod.computeWorldTransforms(sk, local_mats[0..sk.joint_count], world);

                if (palette_comp) |pc| {
                    for (0..sk.joint_count) |i| pc.matrices[i] = math.matMul(world[i], sk.inverse_bind_matrices[i]);
                }
            }
        }
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *AnimPlayerSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(AnimPlayerSystemState);
    state.* = .{};
    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *AnimPlayerSystemState = @ptrCast(@alignCast(ctx));
    allocator.destroy(state);
}

test "AnimPlayer advances time, loops, and writes a sampled pose + world transforms" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var sk = skeleton_mod.Skeleton{
        .joint_count = 1,
        .parent_indices = try allocator.dupe(i32, &.{-1}),
        .inverse_bind_matrices = try allocator.dupe([4][4]f32, &.{math.identityMatrix()}),
        .rest_local_transforms = try allocator.dupe([4][4]f32, &.{math.identityMatrix()}),
        .rest_local_poses = try allocator.dupe(clip_mod.JointPose, &.{.{}}),
        .allocator = allocator,
    };
    const skeleton_id = try reg.skeleton_cache.register(&sk);
    sk.deinit();

    var c = clip_mod.AnimationClip{
        .name = try allocator.dupe(u8, "test"),
        .duration = 2.0,
        .channels = try allocator.dupe(clip_mod.Channel, &.{.{
            .joint_index = 0,
            .path = .translation,
            .times = try allocator.dupe(f32, &.{ 0.0, 2.0 }),
            .values = try allocator.dupe([4]f32, &.{ .{ 0, 0, 0, 0 }, .{ 10, 0, 0, 0 } }),
        }}),
        .allocator = allocator,
    };
    const clip_id = try reg.clip_cache.register(&c);
    c.deinit();

    const entity = try reg.create();
    try reg.add(entity, components.SkeletonComponent{ .skeleton_id = skeleton_id });
    try reg.add(entity, components.AnimPlayerComponent{ .clip_id = clip_id, .loop = true });
    try reg.add(entity, components.PoseBufferComponent{ .poses = try allocator.alloc(clip_mod.JointPose, 1) });
    try reg.add(entity, components.JointWorldComponent{ .matrices = try allocator.alloc([4][4]f32, 1) });
    try reg.add(entity, components.SkinPaletteComponent{ .matrices = try allocator.alloc([4][4]f32, 1) });

    var state = AnimPlayerSystemState{};
    try state.update(&reg, 1.0); // time = 1.0 -> halfway

    const pose = reg.get(components.PoseBufferComponent, entity).?;
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), pose.poses[0].translation[0], 1e-5);

    const world = reg.get(components.JointWorldComponent, entity).?;
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), world.matrices[0][3][0], 1e-5);

    // inverse_bind_matrices is identity in this synthetic skeleton, so the
    // palette (world * inverse_bind) should equal world exactly.
    const palette = reg.get(components.SkinPaletteComponent, entity).?;
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), palette.matrices[0][3][0], 1e-5);

    try state.update(&reg, 1.5); // time = 2.5 -> wraps to 0.5 -> quarter
    try std.testing.expectApproxEqAbs(@as(f32, 2.5), pose.poses[0].translation[0], 1e-5);
}
