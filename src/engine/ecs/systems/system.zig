const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;

pub const System = struct {
    name: []const u8,
    priority: i32 = 0,
    update_fn: *const fn (*Registry, *anyopaque, f32) anyerror!void,
    init_fn: ?*const fn (*Registry, *anyopaque) anyerror!void = null,
    deinit_fn: ?*const fn (*Registry, *anyopaque) void = null,
    context: *anyopaque,
};

pub const SystemRunner = struct {
    systems: std.ArrayList(System) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SystemRunner {
        return .{ .systems = .empty, .allocator = allocator };
    }

    pub fn deinit(self: *SystemRunner) void {
        self.systems.deinit(self.allocator);
    }

    pub fn addSystem(self: *SystemRunner, system: System) !void {
        try self.systems.append(self.allocator, system);
        std.mem.sort(System, self.systems.items, {}, struct {
            fn lessThan(_: void, a: System, b: System) bool {
                return a.priority < b.priority;
            }
        }.lessThan);
    }

    pub fn initAll(self: *SystemRunner, registry: *Registry) !void {
        for (self.systems.items) |system| {
            if (system.init_fn) |f| try f(registry, system.context);
        }
    }

    pub fn deinitAll(self: *SystemRunner, registry: *Registry) void {
        for (self.systems.items) |system| {
            if (system.deinit_fn) |f| f(registry, system.context);
        }
    }

    pub fn update(self: *SystemRunner, registry: *Registry, dt: f32) !void {
        for (self.systems.items) |system| {
            try system.update_fn(registry, system.context, dt);
        }
    }
};
