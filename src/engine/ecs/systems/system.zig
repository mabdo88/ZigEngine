const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;

/// A system is a named, prioritized update function over the registry.
/// Lower priority runs first (Input < Scene < Camera < Render).
pub const System = struct {
    name: []const u8,
    priority: i32 = 0,
    update_fn: *const fn (*Registry, f32) anyerror!void,
};

/// Owns the registered systems and runs them each frame in priority order.
pub const SystemRunner = struct {
    systems: std.ArrayList(System) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SystemRunner {
        return .{ .systems = .empty, .allocator = allocator };
    }

    pub fn deinit(self: *SystemRunner) void {
        self.systems.deinit(self.allocator);
    }

    /// Register a system and keep the list sorted by ascending priority.
    pub fn addSystem(self: *SystemRunner, system: System) !void {
        try self.systems.append(self.allocator, system);
        std.mem.sort(System, self.systems.items, {}, struct {
            fn lessThan(_: void, a: System, b: System) bool {
                return a.priority < b.priority;
            }
        }.lessThan);
    }

    pub fn update(self: *SystemRunner, registry: *Registry, dt: f32) !void {
        for (self.systems.items) |system| {
            try system.update_fn(registry, dt);
        }
    }
};
