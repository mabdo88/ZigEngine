const std = @import("std");
const config_mod = @import("config.zig");

pub fn Engine(comptime WorldType: type) type {
    return struct {
        world: WorldType,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(self: *Self, allocator: std.mem.Allocator, config: config_mod.Config) !void {
            try WorldType.init(&self.world, allocator, config);
            self.allocator = allocator;
        }

        pub fn run(self: *Self) !void {
            const fixed_dt: f32 = 1.0 / 60.0;
            var accumulator: f32 = 0.0;

            while (!self.world.shouldClose()) {
                var frame_dt = self.world.getRealDeltaTime();
                if (frame_dt > 0.25) frame_dt = 0.25;
                accumulator += frame_dt;

                while (accumulator >= fixed_dt) {
                    try self.world.fixedUpdate(fixed_dt);
                    accumulator -= fixed_dt;
                }

                try self.world.renderUpdate(accumulator / fixed_dt);
            }
        }

        pub fn deinit(self: *Self) void {
            self.world.deinit();
        }
    };
}
