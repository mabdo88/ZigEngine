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

fn noopUpdate(_: *Registry, _: *anyopaque, _: f32) anyerror!void {}
fn noopInit(_: *Registry, _: *anyopaque) anyerror!void {}
fn noopDeinit(_: *Registry, _: *anyopaque) void {}

const OrderTracker = struct {
    order: *std.ArrayList(u8),
    id: u8 = 0,
    fn update(_: *Registry, ctx: *anyopaque, _: f32) anyerror!void {
        const self: *OrderTracker = @ptrCast(@alignCast(ctx));
        try self.order.append(std.testing.allocator, self.id);
    }
};

test "addSystem sorts by priority ascending" {
    var runner = SystemRunner.init(std.testing.allocator);
    defer runner.deinit();

    var ctx: u8 = 0;
    try runner.addSystem(.{ .name = "low", .priority = 10, .update_fn = noopUpdate, .context = &ctx });
    try runner.addSystem(.{ .name = "high", .priority = -5, .update_fn = noopUpdate, .context = &ctx });
    try runner.addSystem(.{ .name = "mid", .priority = 0, .update_fn = noopUpdate, .context = &ctx });

    try std.testing.expectEqualStrings("high", runner.systems.items[0].name);
    try std.testing.expectEqualStrings("mid", runner.systems.items[1].name);
    try std.testing.expectEqualStrings("low", runner.systems.items[2].name);
}

test "update calls systems in priority order" {
    var runner = SystemRunner.init(std.testing.allocator);
    defer runner.deinit();

    var order: std.ArrayList(u8) = .empty;
    defer order.deinit(std.testing.allocator);

    var t1 = OrderTracker{ .order = &order, .id = 1 };
    var t2 = OrderTracker{ .order = &order, .id = 2 };
    var t3 = OrderTracker{ .order = &order, .id = 3 };

    try runner.addSystem(.{ .name = "c", .priority = 10, .update_fn = OrderTracker.update, .context = &t1 });
    try runner.addSystem(.{ .name = "a", .priority = -5, .update_fn = OrderTracker.update, .context = &t2 });
    try runner.addSystem(.{ .name = "b", .priority = 0, .update_fn = OrderTracker.update, .context = &t3 });

    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    try runner.update(&reg, 0.0);

    try std.testing.expectEqual(@as(usize, 3), order.items.len);
    try std.testing.expectEqual(@as(u8, 2), order.items[0]); // a (priority -5)
    try std.testing.expectEqual(@as(u8, 3), order.items[1]); // b (priority 0)
    try std.testing.expectEqual(@as(u8, 1), order.items[2]); // c (priority 10)
}

test "initAll calls init_fn for systems that have it" {
    var runner = SystemRunner.init(std.testing.allocator);
    defer runner.deinit();

    const InitTracker = struct {
        called: *bool,
        fn init(_: *Registry, ctx: *anyopaque) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.called.* = true;
        }
    };

    var called = false;
    var tracker = InitTracker{ .called = &called };
    var ctx: u8 = 0;

    try runner.addSystem(.{ .name = "with_init", .priority = 0, .update_fn = noopUpdate, .init_fn = InitTracker.init, .context = &tracker });
    try runner.addSystem(.{ .name = "without_init", .priority = 0, .update_fn = noopUpdate, .context = &ctx });

    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    try runner.initAll(&reg);
    try std.testing.expect(called);
}

test "deinitAll calls deinit_fn for systems that have it" {
    var runner = SystemRunner.init(std.testing.allocator);
    defer runner.deinit();

    const DeinitTracker = struct {
        called: *bool,
        fn deinit(_: *Registry, ctx: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.called.* = true;
        }
    };

    var called = false;
    var tracker = DeinitTracker{ .called = &called };
    var ctx: u8 = 0;

    try runner.addSystem(.{ .name = "with_deinit", .priority = 0, .update_fn = noopUpdate, .deinit_fn = DeinitTracker.deinit, .context = &tracker });
    try runner.addSystem(.{ .name = "without_deinit", .priority = 0, .update_fn = noopUpdate, .context = &ctx });

    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    runner.deinitAll(&reg);
    try std.testing.expect(called);
}
