const std = @import("std");
const clip = @import("clip.zig");

/// One clip positioned on the 1D blend axis. `points` in a `BlendTree1D`
/// must be sorted ascending by `param` — callers build this once (e.g. at
/// spawn time) and reuse it every frame.
pub const BlendPoint = struct {
    param: f32,
    clip: *const clip.AnimationClip,
};

pub const BlendTree1D = struct {
    points: []const BlendPoint,
};

/// Finds the two points bracketing `param` (clamped to the first/last point
/// outside the tree's range) and returns their indices plus the blend
/// factor between them.
fn bracket(points: []const BlendPoint, param: f32) struct { i0: usize, i1: usize, t: f32 } {
    if (points.len == 1 or param <= points[0].param) return .{ .i0 = 0, .i1 = 0, .t = 0 };
    if (param >= points[points.len - 1].param) return .{ .i0 = points.len - 1, .i1 = points.len - 1, .t = 0 };
    var lo: usize = 0;
    var hi: usize = points.len - 1;
    while (hi - lo > 1) {
        const mid = (lo + hi) / 2;
        if (points[mid].param <= param) lo = mid else hi = mid;
    }
    const span = points[hi].param - points[lo].param;
    const t = if (span > 0) (param - points[lo].param) / span else 0;
    return .{ .i0 = lo, .i1 = hi, .t = t };
}

/// Samples the two clips bracketing `param` at `time` and blends them.
/// `scratch_a`/`scratch_b` are caller-provided buffers (joint_count each,
/// reused across calls to avoid per-frame allocation) that must already
/// hold the rest pose — same convention as `clip.sampleClip`.
pub fn sampleBlendTree1D(tree: BlendTree1D, param: f32, time: f32, scratch_a: []clip.JointPose, scratch_b: []clip.JointPose, out: []clip.JointPose) void {
    const br = bracket(tree.points, param);
    clip.sampleClip(tree.points[br.i0].clip, time, scratch_a);
    if (br.i0 == br.i1) {
        @memcpy(out, scratch_a);
        return;
    }
    clip.sampleClip(tree.points[br.i1].clip, time, scratch_b);
    clip.blendPoses(scratch_a, scratch_b, br.t, out);
}

fn makeClip(allocator: std.mem.Allocator, end_x: f32) !clip.AnimationClip {
    return clip.AnimationClip{
        .name = try allocator.dupe(u8, "test"),
        .duration = 1.0,
        .channels = try allocator.dupe(clip.Channel, &.{.{
            .joint_index = 0,
            .path = .translation,
            .times = try allocator.dupe(f32, &.{ 0.0, 1.0 }),
            .values = try allocator.dupe([4]f32, &.{ .{ 0, 0, 0, 0 }, .{ end_x, 0, 0, 0 } }),
        }}),
        .allocator = allocator,
    };
}

test "sampleBlendTree1D: param at an exact point samples only that clip" {
    const allocator = std.testing.allocator;
    var idle = try makeClip(allocator, 0); // stays at x=0 at t=1
    defer idle.deinit();
    var run = try makeClip(allocator, 10); // reaches x=10 at t=1
    defer run.deinit();

    const tree = BlendTree1D{ .points = &.{
        .{ .param = 0.0, .clip = &idle },
        .{ .param = 1.0, .clip = &run },
    } };

    var a = [_]clip.JointPose{.{}};
    var b = [_]clip.JointPose{.{}};
    var out = [_]clip.JointPose{.{}};

    sampleBlendTree1D(tree, 0.0, 1.0, &a, &b, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), out[0].translation[0], 1e-5);

    sampleBlendTree1D(tree, 1.0, 1.0, &a, &b, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), out[0].translation[0], 1e-5);
}

test "sampleBlendTree1D: param between two points blends them" {
    const allocator = std.testing.allocator;
    var idle = try makeClip(allocator, 0);
    defer idle.deinit();
    var run = try makeClip(allocator, 10);
    defer run.deinit();

    const tree = BlendTree1D{ .points = &.{
        .{ .param = 0.0, .clip = &idle },
        .{ .param = 1.0, .clip = &run },
    } };

    var a = [_]clip.JointPose{.{}};
    var b = [_]clip.JointPose{.{}};
    var out = [_]clip.JointPose{.{}};

    sampleBlendTree1D(tree, 0.5, 1.0, &a, &b, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), out[0].translation[0], 1e-5);
}

test "sampleBlendTree1D: param outside the range clamps to the nearest end point" {
    const allocator = std.testing.allocator;
    var idle = try makeClip(allocator, 0);
    defer idle.deinit();
    var run = try makeClip(allocator, 10);
    defer run.deinit();

    const tree = BlendTree1D{ .points = &.{
        .{ .param = 0.0, .clip = &idle },
        .{ .param = 1.0, .clip = &run },
    } };

    var a = [_]clip.JointPose{.{}};
    var b = [_]clip.JointPose{.{}};
    var out = [_]clip.JointPose{.{}};

    sampleBlendTree1D(tree, -5.0, 1.0, &a, &b, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), out[0].translation[0], 1e-5);

    sampleBlendTree1D(tree, 5.0, 1.0, &a, &b, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), out[0].translation[0], 1e-5);
}
