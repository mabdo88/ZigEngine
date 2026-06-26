const std = @import("std");
const config_mod = @import("config.zig");
const Timer = @import("timer.zig").Timer;

pub const FIXED_DT: f64 = 1.0 / 60.0;
const MAX_STEPS_PER_FRAME: u32 = 5;

pub fn Engine(comptime WorldType: type) type {
    return struct {
        world: WorldType,
        allocator: std.mem.Allocator,
        io_threaded: std.Io.Threaded = undefined,
        timer: Timer = undefined,
        accumulator: f64 = 0,

        const Self = @This();

        pub fn init(self: *Self, allocator: std.mem.Allocator, config: config_mod.Config) !void {
            self.io_threaded = std.Io.Threaded.init(allocator, .{});
            try WorldType.init(&self.world, allocator, config);
            self.allocator = allocator;
            self.timer = Timer.start(self.io_threaded.io());
            self.accumulator = 0;
        }

        /// Runs the simulation at a fixed 1/60s tick, catching up by at most
        /// MAX_STEPS_PER_FRAME steps per real frame to avoid a death spiral
        /// if the app falls behind (e.g. a debugger pause or slow load).
        pub fn run(self: *Self) !void {
            while (!self.world.shouldClose()) {
                const frame_dt = self.timer.tick();
                self.accumulator = @min(self.accumulator + frame_dt, FIXED_DT * @as(f64, MAX_STEPS_PER_FRAME));

                var steps: u32 = 0;
                while (self.accumulator >= FIXED_DT and steps < MAX_STEPS_PER_FRAME) {
                    try self.world.update(@floatCast(FIXED_DT));
                    self.accumulator -= FIXED_DT;
                    steps += 1;
                }
            }
        }

        pub fn deinit(self: *Self) void {
            self.world.deinit();
            self.io_threaded.deinit();
        }
    };
}
