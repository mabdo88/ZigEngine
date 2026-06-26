const std = @import("std");
const math = @import("../engine/math.zig");
const clip = @import("clip.zig");

/// Joint hierarchy + bind-pose data for one skinned mesh. `parent_indices[i]`
/// is always < i (the loader topologically sorts joints on import) so
/// `computeSkinMatrices` can do a single forward sweep instead of recursing.
pub const Skeleton = struct {
    joint_count: u32,
    parent_indices: []i32, // -1 = root
    inverse_bind_matrices: [][4][4]f32,
    rest_local_transforms: [][4][4]f32,
    /// Same rest pose as `rest_local_transforms`, decomposed into TRS so
    /// AnimPlayer can overwrite individual components (a matrix can't be
    /// partially overwritten the way a translation-only channel needs).
    rest_local_poses: []clip.JointPose = &.{},
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Skeleton) void {
        self.allocator.free(self.parent_indices);
        self.allocator.free(self.inverse_bind_matrices);
        self.allocator.free(self.rest_local_transforms);
        self.allocator.free(self.rest_local_poses);
    }

    /// A fresh local-pose buffer initialized to the skeleton's rest pose —
    /// the correct default for PoseBuffer, since identity transforms would
    /// not reproduce the bind pose (rest_local_transforms already encode it).
    pub fn bindPose(self: *const Skeleton, allocator: std.mem.Allocator) ![][4][4]f32 {
        return allocator.dupe([4][4]f32, self.rest_local_transforms);
    }

    /// TRS variant of `bindPose`, for use as the starting buffer passed to
    /// `clip.sampleClip`.
    pub fn bindPoseTRS(self: *const Skeleton, allocator: std.mem.Allocator) ![]clip.JointPose {
        return allocator.dupe(clip.JointPose, self.rest_local_poses);
    }
};

/// Forward kinematics pass: world[i] = world[parent(i)] * local[i] (root:
/// world[i] = local[i]). `out_world` must have at least `skeleton.joint_count`
/// entries. Exposed on its own (not just inlined into computeSkinMatrices) so
/// callers that only need joint positions — e.g. debug-drawing the skeleton —
/// don't have to compute skin matrices they won't use.
pub fn computeWorldTransforms(skeleton: *const Skeleton, local_poses: []const [4][4]f32, out_world: [][4][4]f32) void {
    for (0..skeleton.joint_count) |i| {
        const parent = skeleton.parent_indices[i];
        out_world[i] = if (parent < 0) local_poses[i] else math.matMul(out_world[@intCast(parent)], local_poses[i]);
    }
}

/// skin[i] = world[i] * inverse_bind[i]. `world_scratch` and `out_skin` must
/// each have at least `skeleton.joint_count` entries.
pub fn computeSkinMatrices(skeleton: *const Skeleton, local_poses: []const [4][4]f32, world_scratch: [][4][4]f32, out_skin: [][4][4]f32) void {
    computeWorldTransforms(skeleton, local_poses, world_scratch);
    for (0..skeleton.joint_count) |i| {
        out_skin[i] = math.matMul(world_scratch[i], skeleton.inverse_bind_matrices[i]);
    }
}

fn translation(x: f32, y: f32, z: f32) [4][4]f32 {
    var m = math.identityMatrix();
    m[3][0] = x;
    m[3][1] = y;
    m[3][2] = z;
    return m;
}

test "computeSkinMatrices: bind pose with matching inverse binds yields identity skin matrices" {
    // root -> child, both translated; inverse_bind exactly undoes each joint's world transform.
    const allocator = std.testing.allocator;
    const root_world = translation(1, 0, 0);
    const child_world = math.matMul(root_world, translation(0, 2, 0));

    var skeleton = Skeleton{
        .joint_count = 2,
        .parent_indices = try allocator.dupe(i32, &.{ -1, 0 }),
        .inverse_bind_matrices = try allocator.dupe([4][4]f32, &.{ invertTranslation(root_world), invertTranslation(child_world) }),
        .rest_local_transforms = try allocator.dupe([4][4]f32, &.{ root_world, translation(0, 2, 0) }),
        .allocator = allocator,
    };
    defer skeleton.deinit();

    const pose = try skeleton.bindPose(allocator);
    defer allocator.free(pose);

    var world_scratch: [2][4][4]f32 = undefined;
    var skin: [2][4][4]f32 = undefined;
    computeSkinMatrices(&skeleton, pose, &world_scratch, &skin);

    const tol = 1e-5;
    for (0..2) |i| {
        for (0..4) |c| {
            for (0..4) |r| {
                const expected: f32 = if (c == r) 1.0 else 0.0;
                try std.testing.expectApproxEqAbs(expected, skin[i][c][r], tol);
            }
        }
    }
}

test "computeSkinMatrices: a posed child joint offsets its skin matrix from identity" {
    const allocator = std.testing.allocator;
    const root_world = math.identityMatrix();

    var skeleton = Skeleton{
        .joint_count = 2,
        .parent_indices = try allocator.dupe(i32, &.{ -1, 0 }),
        .inverse_bind_matrices = try allocator.dupe([4][4]f32, &.{ math.identityMatrix(), math.identityMatrix() }),
        .rest_local_transforms = try allocator.dupe([4][4]f32, &.{ root_world, math.identityMatrix() }),
        .allocator = allocator,
    };
    defer skeleton.deinit();

    // Pose the child joint with a translation away from rest.
    var pose = try skeleton.bindPose(allocator);
    defer allocator.free(pose);
    pose[1] = translation(0, 5, 0);

    var world_scratch: [2][4][4]f32 = undefined;
    var skin: [2][4][4]f32 = undefined;
    computeSkinMatrices(&skeleton, pose, &world_scratch, &skin);

    const tol = 1e-5;
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), skin[0][3][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), skin[1][3][1], tol);
}

fn invertTranslation(m: [4][4]f32) [4][4]f32 {
    var r = math.identityMatrix();
    r[3][0] = -m[3][0];
    r[3][1] = -m[3][1];
    r[3][2] = -m[3][2];
    return r;
}
