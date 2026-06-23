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
            while (!self.world.shouldClose()) {
                const dt = self.world.deltaTime();
                try self.world.update(dt);
            }
        }

        pub fn deinit(self: *Self) void {
            self.world.deinit();
        }
    };
}
