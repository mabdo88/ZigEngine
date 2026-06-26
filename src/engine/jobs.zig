const std = @import("std");
const Io = std.Io;

/// Job system built on std.Io's structured concurrency (Io.Group) rather
/// than a hand-rolled std.Thread+Mutex+Condition pool: Zig master moved
/// Mutex/Condition behind an Io instance too (see std.Io.Mutex), and the
/// idiomatic replacement for "pool of N=cpu_count-1 workers" is
/// std.Io.Threaded, which defaults its concurrency limit to exactly that.
/// submit() schedules work; waitAll() is the wait_all() barrier.
pub const JobSystem = struct {
    io: Io,
    group: Io.Group = Io.Group.init,

    pub fn init(io: Io) JobSystem {
        return .{ .io = io };
    }

    /// Submits `function(args...)` to run concurrently. `function` must
    /// return a type coercible to `Io.Cancelable!void`. Any captured state
    /// in `args` must outlive the job until waitAll() returns.
    pub fn submit(self: *JobSystem, comptime function: anytype, args: std.meta.ArgsTuple(@TypeOf(function))) !void {
        try self.group.concurrent(self.io, function, args);
    }

    /// Blocks until every job submitted since the last waitAll() has finished.
    pub fn waitAll(self: *JobSystem) !void {
        try self.group.await(self.io);
    }
};

fn incrementJob(counter: *std.atomic.Value(u32)) Io.Cancelable!void {
    _ = counter.fetchAdd(1, .monotonic);
}

test "submit + waitAll runs all jobs to completion" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var jobs = JobSystem.init(io);
    var counter = std.atomic.Value(u32).init(0);

    const n: u32 = 32;
    for (0..n) |_| try jobs.submit(incrementJob, .{&counter});
    try jobs.waitAll();

    try std.testing.expectEqual(n, counter.load(.monotonic));
}

test "waitAll with no submitted jobs returns immediately" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var jobs = JobSystem.init(io);
    try jobs.waitAll();
}

test "a JobSystem can be reused for multiple submit/waitAll rounds" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var jobs = JobSystem.init(io);
    var counter = std.atomic.Value(u32).init(0);

    for (0..3) |_| {
        for (0..10) |_| try jobs.submit(incrementJob, .{&counter});
        try jobs.waitAll();
    }

    try std.testing.expectEqual(@as(u32, 30), counter.load(.monotonic));
}
