const std = @import("std");
const Io = std.Io;

/// Wraps the std.Io monotonic clock for frame-delta and elapsed-time queries
/// in seconds. Zig master moved clock access behind an `Io` instance (see
/// std.Io.Clock) instead of the old std.time.Timer, so callers must hold an
/// `Io` (e.g. from `std.Io.Threaded.io()`) and pass it in at start().
pub const Timer = struct {
    io: Io,
    last: Io.Timestamp,
    start_time: Io.Timestamp,

    pub fn start(io: Io) Timer {
        const now = Io.Clock.awake.now(io);
        return .{ .io = io, .last = now, .start_time = now };
    }

    /// Seconds elapsed since the last call to tick() (or start()).
    pub fn tick(self: *Timer) f64 {
        const now = Io.Clock.awake.now(self.io);
        const dur = self.last.durationTo(now);
        self.last = now;
        return nsToSeconds(dur.nanoseconds);
    }

    /// Seconds elapsed since start(), without resetting the lap counter.
    pub fn elapsed(self: *Timer) f64 {
        const now = Io.Clock.awake.now(self.io);
        const dur = self.start_time.durationTo(now);
        return nsToSeconds(dur.nanoseconds);
    }
};

fn nsToSeconds(ns: i96) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, std.time.ns_per_s);
}

test "tick reports approximately the slept duration" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var timer = Timer.start(io);
    try Io.sleep(io, Io.Duration.fromMilliseconds(5), .awake);
    const dt = timer.tick();
    try std.testing.expect(dt >= 0.001);
    try std.testing.expect(dt < 0.5);
}

test "elapsed accumulates across multiple ticks" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var timer = Timer.start(io);
    try Io.sleep(io, Io.Duration.fromMilliseconds(2), .awake);
    _ = timer.tick();
    try Io.sleep(io, Io.Duration.fromMilliseconds(2), .awake);
    const total = timer.elapsed();
    try std.testing.expect(total >= 0.001);
}
