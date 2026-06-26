const std = @import("std");
const clip = @import("clip.zig");

pub const ASMState = struct {
    name: []const u8,
    clip: *const clip.AnimationClip,
};

/// `condition` is checked every `update` while the machine is in `from`
/// (or any state, if `from` is null) — first transition whose condition
/// returns true wins. `ctx` is opaque, passed straight through to
/// `condition` (gameplay code's blackboard/input state, etc.).
pub const ASMTransition = struct {
    from: ?usize,
    to: usize,
    condition: *const fn (ctx: *anyopaque) bool,
    duration: f32,
};

pub const StateMachineDesc = struct {
    states: []const ASMState,
    transitions: []const ASMTransition,
};

/// Per-entity runtime state for one `StateMachineDesc`. `update` advances
/// `current`'s clip time, checks transitions, and writes the resulting pose
/// (blended with the outgoing state's pose over `duration` seconds, if
/// transitioning) into `out_poses`.
pub const StateMachine = struct {
    desc: StateMachineDesc,
    current: usize,
    time: f32 = 0,

    // Transition-in-progress state. `prev_pose` is a snapshot of the
    // outgoing state's pose taken the instant the transition started — not
    // re-sampled, so the blend is from exactly where the entity actually
    // was, not from some idealized resting point.
    transitioning: bool = false,
    prev_state: usize = 0,
    prev_pose: []clip.JointPose,
    transition_time: f32 = 0,
    transition_duration: f32 = 0,

    pub fn init(desc: StateMachineDesc, initial_state: usize, prev_pose_scratch: []clip.JointPose) StateMachine {
        return .{ .desc = desc, .current = initial_state, .prev_pose = prev_pose_scratch };
    }

    /// `rest_poses` is the skeleton's rest pose, used as the starting buffer
    /// for `clip.sampleClip` (same convention as everywhere else in this
    /// module). `out_poses`/`blend_scratch` must be joint_count each.
    pub fn update(self: *StateMachine, dt: f32, ctx: *anyopaque, rest_poses: []const clip.JointPose, out_poses: []clip.JointPose, blend_scratch: []clip.JointPose) void {
        self.time += dt;

        for (self.desc.transitions) |t| {
            if (t.from != null and t.from.? != self.current) continue;
            if (t.to == self.current) continue;
            if (!t.condition(ctx)) continue;

            // Snapshot the outgoing pose before switching state — sample it
            // now, at its actual current time, not some future re-derivation.
            @memcpy(self.prev_pose, rest_poses);
            clip.sampleClip(self.desc.states[self.current].clip, self.time, self.prev_pose);

            self.prev_state = self.current;
            self.current = t.to;
            self.time = 0;
            self.transitioning = true;
            self.transition_time = 0;
            self.transition_duration = t.duration;
            break;
        }

        @memcpy(out_poses, rest_poses);
        clip.sampleClip(self.desc.states[self.current].clip, self.time, out_poses);

        if (self.transitioning) {
            self.transition_time += dt;
            if (self.transition_time >= self.transition_duration or self.transition_duration <= 0) {
                self.transitioning = false;
            } else {
                const alpha = self.transition_time / self.transition_duration;
                @memcpy(blend_scratch, out_poses);
                clip.blendPoses(self.prev_pose, blend_scratch, alpha, out_poses);
            }
        }
    }
};

fn makeClip(allocator: std.mem.Allocator, x: f32) !clip.AnimationClip {
    return clip.AnimationClip{
        .name = try allocator.dupe(u8, "test"),
        .duration = 1000.0, // long enough that tests never wrap
        .channels = try allocator.dupe(clip.Channel, &.{.{
            .joint_index = 0,
            .path = .translation,
            .times = try allocator.dupe(f32, &.{ 0.0, 1000.0 }),
            .values = try allocator.dupe([4]f32, &.{ .{ x, 0, 0, 0 }, .{ x, 0, 0, 0 } }),
        }}),
        .allocator = allocator,
    };
}

fn alwaysTrue(_: *anyopaque) bool {
    return true;
}
fn alwaysFalse(_: *anyopaque) bool {
    return false;
}

test "StateMachine: stays in the initial state when no transition fires" {
    const allocator = std.testing.allocator;
    var idle = try makeClip(allocator, 0);
    defer idle.deinit();
    var run = try makeClip(allocator, 10);
    defer run.deinit();

    const desc = StateMachineDesc{
        .states = &.{ .{ .name = "idle", .clip = &idle }, .{ .name = "run", .clip = &run } },
        .transitions = &.{.{ .from = 0, .to = 1, .condition = alwaysFalse, .duration = 0.2 }},
    };
    var prev_pose = [_]clip.JointPose{.{}};
    var sm = StateMachine.init(desc, 0, &prev_pose);

    var dummy: u8 = 0;
    const rest = [_]clip.JointPose{.{}};
    var out = [_]clip.JointPose{.{}};
    var scratch = [_]clip.JointPose{.{}};
    sm.update(0.1, @ptrCast(&dummy), &rest, &out, &scratch);

    try std.testing.expectEqual(@as(usize, 0), sm.current);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), out[0].translation[0], 1e-5);
}

test "StateMachine: an immediate transition blends from the snapshot toward the new state over duration" {
    const allocator = std.testing.allocator;
    var idle = try makeClip(allocator, 0);
    defer idle.deinit();
    var run = try makeClip(allocator, 10);
    defer run.deinit();

    const desc = StateMachineDesc{
        .states = &.{ .{ .name = "idle", .clip = &idle }, .{ .name = "run", .clip = &run } },
        .transitions = &.{.{ .from = 0, .to = 1, .condition = alwaysTrue, .duration = 1.0 }},
    };
    var prev_pose = [_]clip.JointPose{.{}};
    var sm = StateMachine.init(desc, 0, &prev_pose);

    var dummy: u8 = 0;
    const rest = [_]clip.JointPose{.{}};
    var out = [_]clip.JointPose{.{}};
    var scratch = [_]clip.JointPose{.{}};

    // First update triggers the transition; 0s into a 1s blend -> still idle's pose (x=0).
    sm.update(0.0, @ptrCast(&dummy), &rest, &out, &scratch);
    try std.testing.expectEqual(@as(usize, 1), sm.current);
    try std.testing.expect(sm.transitioning);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), out[0].translation[0], 1e-4);

    // Halfway through the 1s blend -> halfway between idle (0) and run (10).
    sm.update(0.5, @ptrCast(&dummy), &rest, &out, &scratch);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), out[0].translation[0], 1e-4);

    // Past the blend duration -> fully run (10), transitioning cleared.
    sm.update(0.6, @ptrCast(&dummy), &rest, &out, &scratch);
    try std.testing.expect(!sm.transitioning);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), out[0].translation[0], 1e-4);
}

test "StateMachine: a transition out of the current state never fires when to == current" {
    const allocator = std.testing.allocator;
    var idle = try makeClip(allocator, 0);
    defer idle.deinit();

    const desc = StateMachineDesc{
        .states = &.{.{ .name = "idle", .clip = &idle }},
        .transitions = &.{.{ .from = 0, .to = 0, .condition = alwaysTrue, .duration = 0.2 }},
    };
    var prev_pose = [_]clip.JointPose{.{}};
    var sm = StateMachine.init(desc, 0, &prev_pose);

    var dummy: u8 = 0;
    const rest = [_]clip.JointPose{.{}};
    var out = [_]clip.JointPose{.{}};
    var scratch = [_]clip.JointPose{.{}};
    sm.update(0.1, @ptrCast(&dummy), &rest, &out, &scratch);

    try std.testing.expect(!sm.transitioning);
}
