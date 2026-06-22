const std = @import("std");

/// The engine is comptime-generic over any World type. It owns the game loop and
/// knows nothing about ECS, scenes, or rendering — swap `VulkanWorld` for another
/// World implementation in main.zig with no changes here.
///
/// A World must provide: `init(allocator) !World`, `shouldClose() bool`,
/// `deltaTime() f32`, `update(dt) !void`, and `deinit() void`.
pub fn Engine(comptime WorldType: type) type {
    return struct {
        world: WorldType,
        allocator: std.mem.Allocator,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) !Self {
            return .{
                .world = try WorldType.init(allocator),
                .allocator = allocator,
            };
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
