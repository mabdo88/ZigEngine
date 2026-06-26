const std = @import("std");

/// Decomposed local transform for one joint. Kept separate from the
/// rest-pose matrices in `Skeleton` because animation channels overwrite
/// individual TRS components independently — a matrix can't be partially
/// overwritten the way a translation-only channel needs to be.
pub const JointPose = struct {
    translation: [3]f32 = .{ 0, 0, 0 },
    rotation: [4]f32 = .{ 0, 0, 0, 1 }, // x, y, z, w
    scale: [3]f32 = .{ 1, 1, 1 },

    pub fn toMatrix(self: JointPose) [4][4]f32 {
        const x = self.rotation[0];
        const y = self.rotation[1];
        const z = self.rotation[2];
        const w = self.rotation[3];
        const sc = self.scale;
        var m: [4][4]f32 = .{
            .{ 1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y), 0 },
            .{ 2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x), 0 },
            .{ 2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y), 0 },
            .{ 0, 0, 0, 1 },
        };
        for (0..3) |c| {
            m[c][0] *= sc[0];
            m[c][1] *= sc[1];
            m[c][2] *= sc[2];
        }
        m[3][0] = self.translation[0];
        m[3][1] = self.translation[1];
        m[3][2] = self.translation[2];
        return m;
    }
};

pub const ChannelPath = enum { translation, rotation, scale };

/// `values` is always 4-wide regardless of path — translation/scale only use
/// .xyz — so every channel shares one storage shape and one keyframe-bracket
/// search regardless of which TRS component it drives.
pub const Channel = struct {
    joint_index: u32,
    path: ChannelPath,
    times: []f32,
    values: [][4]f32,
};

/// A named marker at a fixed point in a clip (footstep, hit frame, etc.).
/// glTF has no native concept of this — clips loaded from glTF always have
/// `events = &.{}`; gameplay code authors these programmatically.
pub const AnimEvent = struct {
    time: f32,
    name: []u8,
};

pub const AnimationClip = struct {
    name: []u8,
    duration: f32,
    channels: []Channel,
    events: []AnimEvent = &.{},
    allocator: std.mem.Allocator,

    pub fn deinit(self: *AnimationClip) void {
        for (self.channels) |c| {
            self.allocator.free(c.times);
            self.allocator.free(c.values);
        }
        self.allocator.free(self.channels);
        for (self.events) |e| self.allocator.free(e.name);
        self.allocator.free(self.events);
        self.allocator.free(self.name);
    }
};

/// Invokes `callback(ctx, event)` for every event with `last_time < event.time
/// <= new_time`. Handles one loop wraparound (new_time < last_time, as
/// produced by `@mod`-wrapping playback time): fires events in
/// `(last_time, duration]` then `[0, new_time]`. Does not handle more than
/// one wraparound per call — fine at a fixed 1/60s step and reasonable
/// playback speeds, where multiple full loops in a single frame won't happen.
pub fn forEachFiredEvent(clip: *const AnimationClip, last_time: f32, new_time: f32, ctx: anytype, comptime callback: fn (@TypeOf(ctx), *const AnimEvent) void) void {
    if (new_time < last_time) {
        for (clip.events) |*e| {
            if (e.time > last_time and e.time <= clip.duration) callback(ctx, e);
        }
        for (clip.events) |*e| {
            if (e.time >= 0 and e.time <= new_time) callback(ctx, e);
        }
        return;
    }
    for (clip.events) |*e| {
        if (e.time > last_time and e.time <= new_time) callback(ctx, e);
    }
}

/// Blends two already-sampled poses (e.g. for a 1D blend tree or an ASM
/// transition) — lerp for translation/scale, slerp for rotation, joint by
/// joint. `a`, `b`, and `out` must all be the same length.
pub fn blendPoses(a: []const JointPose, b: []const JointPose, alpha: f32, out: []JointPose) void {
    for (a, b, out) |pa, pb, *po| {
        po.translation = lerpVec3(.{ pa.translation[0], pa.translation[1], pa.translation[2], 0 }, .{ pb.translation[0], pb.translation[1], pb.translation[2], 0 }, alpha);
        po.rotation = slerpQuat(pa.rotation, pb.rotation, alpha);
        po.scale = lerpVec3(.{ pa.scale[0], pa.scale[1], pa.scale[2], 0 }, .{ pb.scale[0], pb.scale[1], pb.scale[2], 0 }, alpha);
    }
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn lerpVec3(a: [4]f32, b: [4]f32, t: f32) [3]f32 {
    return .{ lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t) };
}

fn slerpQuat(a: [4]f32, b: [4]f32, t: f32) [4]f32 {
    var bv = b;
    var cos_half_theta = a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3];
    if (cos_half_theta < 0.0) {
        bv = .{ -b[0], -b[1], -b[2], -b[3] };
        cos_half_theta = -cos_half_theta;
    }
    if (cos_half_theta > 0.9995) {
        // Nearly identical rotations: linear interpolation avoids a divide-by-near-zero in sin(theta).
        const r: [4]f32 = .{ lerp(a[0], bv[0], t), lerp(a[1], bv[1], t), lerp(a[2], bv[2], t), lerp(a[3], bv[3], t) };
        return normalizeQuat(r);
    }
    const half_theta = std.math.acos(cos_half_theta);
    const sin_half_theta = @sqrt(1.0 - cos_half_theta * cos_half_theta);
    const ratio_a = @sin((1.0 - t) * half_theta) / sin_half_theta;
    const ratio_b = @sin(t * half_theta) / sin_half_theta;
    return .{
        a[0] * ratio_a + bv[0] * ratio_b,
        a[1] * ratio_a + bv[1] * ratio_b,
        a[2] * ratio_a + bv[2] * ratio_b,
        a[3] * ratio_a + bv[3] * ratio_b,
    };
}

fn normalizeQuat(q: [4]f32) [4]f32 {
    const len = @sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]);
    return .{ q[0] / len, q[1] / len, q[2] / len, q[3] / len };
}

/// Finds the keyframe pair bracketing `time` and the interpolation factor
/// between them. Assumes `times` is sorted ascending (true for every glTF
/// animation sampler input accessor). Clamps to the first/last keyframe
/// outside the clip's time range instead of extrapolating.
fn bracket(times: []const f32, time: f32) struct { i0: usize, i1: usize, t: f32 } {
    if (times.len == 1 or time <= times[0]) return .{ .i0 = 0, .i1 = 0, .t = 0 };
    if (time >= times[times.len - 1]) return .{ .i0 = times.len - 1, .i1 = times.len - 1, .t = 0 };
    var lo: usize = 0;
    var hi: usize = times.len - 1;
    while (hi - lo > 1) {
        const mid = (lo + hi) / 2;
        if (times[mid] <= time) lo = mid else hi = mid;
    }
    const span = times[hi] - times[lo];
    const t = if (span > 0) (time - times[lo]) / span else 0;
    return .{ .i0 = lo, .i1 = hi, .t = t };
}

/// Samples `clip` at `time` into `out_poses`, which must start as a copy of
/// the skeleton's rest pose — channels only overwrite the joints/components
/// they actually animate, leaving everything else at rest.
pub fn sampleClip(clip: *const AnimationClip, time: f32, out_poses: []JointPose) void {
    for (clip.channels) |ch| {
        if (ch.joint_index >= out_poses.len) continue;
        const br = bracket(ch.times, time);
        const a = ch.values[br.i0];
        const b = ch.values[br.i1];
        switch (ch.path) {
            .translation => out_poses[ch.joint_index].translation = lerpVec3(a, b, br.t),
            .scale => out_poses[ch.joint_index].scale = lerpVec3(a, b, br.t),
            .rotation => out_poses[ch.joint_index].rotation = slerpQuat(a, b, br.t),
        }
    }
}

test "sampleClip: translation channel lerps between two keyframes" {
    const allocator = std.testing.allocator;
    const times = try allocator.dupe(f32, &.{ 0.0, 1.0 });
    const values = try allocator.dupe([4]f32, &.{ .{ 0, 0, 0, 0 }, .{ 10, 0, 0, 0 } });
    const channels = try allocator.dupe(Channel, &.{.{ .joint_index = 0, .path = .translation, .times = times, .values = values }});
    var clip = AnimationClip{ .name = try allocator.dupe(u8, "test"), .duration = 1.0, .channels = channels, .allocator = allocator };
    defer clip.deinit();

    var poses = [_]JointPose{.{}};
    sampleClip(&clip, 0.5, &poses);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), poses[0].translation[0], 1e-5);

    sampleClip(&clip, 0.0, &poses);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), poses[0].translation[0], 1e-5);

    sampleClip(&clip, 1.0, &poses);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), poses[0].translation[0], 1e-5);
}

test "sampleClip: time before/after the clip clamps to the first/last keyframe" {
    const allocator = std.testing.allocator;
    const times = try allocator.dupe(f32, &.{ 1.0, 2.0 });
    const values = try allocator.dupe([4]f32, &.{ .{ 1, 0, 0, 0 }, .{ 9, 0, 0, 0 } });
    const channels = try allocator.dupe(Channel, &.{.{ .joint_index = 0, .path = .translation, .times = times, .values = values }});
    var clip = AnimationClip{ .name = try allocator.dupe(u8, "test"), .duration = 2.0, .channels = channels, .allocator = allocator };
    defer clip.deinit();

    var poses = [_]JointPose{.{}};
    sampleClip(&clip, -1.0, &poses);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), poses[0].translation[0], 1e-5);

    sampleClip(&clip, 5.0, &poses);
    try std.testing.expectApproxEqAbs(@as(f32, 9.0), poses[0].translation[0], 1e-5);
}

test "sampleClip: a rotation channel slerps and leaves an unanimated joint at rest" {
    const allocator = std.testing.allocator;
    const times = try allocator.dupe(f32, &.{ 0.0, 1.0 });
    // 0deg -> 180deg around Z
    const values = try allocator.dupe([4]f32, &.{ .{ 0, 0, 0, 1 }, .{ 0, 0, 1, 0 } });
    const channels = try allocator.dupe(Channel, &.{.{ .joint_index = 0, .path = .rotation, .times = times, .values = values }});
    var clip = AnimationClip{ .name = try allocator.dupe(u8, "test"), .duration = 1.0, .channels = channels, .allocator = allocator };
    defer clip.deinit();

    var poses = [_]JointPose{ .{}, .{ .translation = .{ 7, 8, 9 } } };
    sampleClip(&clip, 0.5, &poses);
    // Halfway through a 0->180deg slerp around Z is 90deg: (x,y,z,w) ~= (0,0,0.707,0.707).
    try std.testing.expectApproxEqAbs(@as(f32, 0.70710678), poses[0].rotation[2], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.70710678), poses[0].rotation[3], 1e-4);
    // Joint 1 has no channel targeting it — must remain exactly at the rest pose passed in.
    try std.testing.expectEqual(@as(f32, 7.0), poses[1].translation[0]);
}

fn makeEventClip(allocator: std.mem.Allocator) !AnimationClip {
    var events = try allocator.alloc(AnimEvent, 2);
    events[0] = .{ .time = 0.25, .name = try allocator.dupe(u8, "footstep_l") };
    events[1] = .{ .time = 0.75, .name = try allocator.dupe(u8, "footstep_r") };
    return AnimationClip{ .name = try allocator.dupe(u8, "walk"), .duration = 1.0, .channels = &.{}, .events = events, .allocator = allocator };
}

test "forEachFiredEvent: fires events strictly within (last_time, new_time]" {
    const allocator = std.testing.allocator;
    var clip = try makeEventClip(allocator);
    defer clip.deinit();

    var fired: std.ArrayListUnmanaged([]const u8) = .empty;
    defer fired.deinit(allocator);
    forEachFiredEvent(&clip, 0.0, 0.5, &fired, struct {
        fn cb(ctx: *std.ArrayListUnmanaged([]const u8), e: *const AnimEvent) void {
            ctx.append(std.testing.allocator, e.name) catch {};
        }
    }.cb);

    try std.testing.expectEqual(@as(usize, 1), fired.items.len);
    try std.testing.expectEqualStrings("footstep_l", fired.items[0]);
}

test "forEachFiredEvent: an event exactly at last_time does not refire" {
    const allocator = std.testing.allocator;
    var clip = try makeEventClip(allocator);
    defer clip.deinit();

    var fired: std.ArrayListUnmanaged([]const u8) = .empty;
    defer fired.deinit(allocator);
    forEachFiredEvent(&clip, 0.25, 0.6, &fired, struct {
        fn cb(ctx: *std.ArrayListUnmanaged([]const u8), e: *const AnimEvent) void {
            ctx.append(std.testing.allocator, e.name) catch {};
        }
    }.cb);

    try std.testing.expectEqual(@as(usize, 0), fired.items.len);
}

test "forEachFiredEvent: handles loop wraparound, firing the tail then the head" {
    const allocator = std.testing.allocator;
    var clip = try makeEventClip(allocator);
    defer clip.deinit();

    var fired: std.ArrayListUnmanaged([]const u8) = .empty;
    defer fired.deinit(allocator);
    // last_time=0.6 (past footstep_r at 0.75? no, 0.6 < 0.75) wraps to new_time=0.3:
    // fires footstep_r (0.75, in the tail) then footstep_l (0.25, in the head).
    forEachFiredEvent(&clip, 0.6, 0.3, &fired, struct {
        fn cb(ctx: *std.ArrayListUnmanaged([]const u8), e: *const AnimEvent) void {
            ctx.append(std.testing.allocator, e.name) catch {};
        }
    }.cb);

    try std.testing.expectEqual(@as(usize, 2), fired.items.len);
    try std.testing.expectEqualStrings("footstep_r", fired.items[0]);
    try std.testing.expectEqualStrings("footstep_l", fired.items[1]);
}

test "blendPoses: lerps translation and slerps rotation between two poses" {
    const a = [_]JointPose{.{ .translation = .{ 0, 0, 0 } }};
    const b = [_]JointPose{.{ .translation = .{ 10, 0, 0 }, .rotation = .{ 0, 0, 1, 0 } }};
    var out = [_]JointPose{.{}};

    blendPoses(&a, &b, 0.5, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), out[0].translation[0], 1e-5);
    // Halfway through a 0->180deg slerp around Z is 90deg.
    try std.testing.expectApproxEqAbs(@as(f32, 0.70710678), out[0].rotation[2], 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.70710678), out[0].rotation[3], 1e-4);

    blendPoses(&a, &b, 0.0, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), out[0].translation[0], 1e-5);
    blendPoses(&a, &b, 1.0, &out);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), out[0].translation[0], 1e-5);
}
