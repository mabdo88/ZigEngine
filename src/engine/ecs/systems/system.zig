const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const Config = @import("../../config.zig").Config;

pub const SystemCreateCtx = struct {
    allocator: std.mem.Allocator,
    registry: *Registry,
    config: *const Config,
};

pub const SystemDesc = struct {
    name: []const u8,
    priority: i32,
    create_fn: *const fn (ctx: *SystemCreateCtx) anyerror!*anyopaque,
    update_fn: *const fn (registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void,
    destroy_fn: *const fn (allocator: std.mem.Allocator, registry: *Registry, ctx: *anyopaque) void,
};

pub const SystemManager = struct {
    descs: []const SystemDesc,
    contexts: []*anyopaque,
    create_order: []usize,
    update_order: []usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, descs: []const SystemDesc, create_ctx: *SystemCreateCtx) !SystemManager {
        const n = descs.len;
        var contexts = try allocator.alloc(*anyopaque, n);
        errdefer allocator.free(contexts);

        var create_order = try allocator.alloc(usize, n);
        errdefer allocator.free(create_order);
        var update_order = try allocator.alloc(usize, n);
        errdefer allocator.free(update_order);

        for (0..n) |i| {
            create_order[i] = i;
            update_order[i] = i;
        }

        // Create order: descending priority (Render first)
        std.mem.sort(usize, create_order, descs, struct {
            fn lessThan(d: []const SystemDesc, a: usize, b: usize) bool {
                return d[a].priority > d[b].priority;
            }
        }.lessThan);

        // Update order: ascending priority (Input first)
        std.mem.sort(usize, update_order, descs, struct {
            fn lessThan(d: []const SystemDesc, a: usize, b: usize) bool {
                return d[a].priority < d[b].priority;
            }
        }.lessThan);

        // Call create_fn in descending priority order
        for (create_order) |idx| {
            contexts[idx] = try descs[idx].create_fn(create_ctx);
        }

        return .{
            .descs = descs,
            .contexts = contexts,
            .create_order = create_order,
            .update_order = update_order,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SystemManager, registry: *Registry) void {
        // Destroy in reverse create order
        var i = self.create_order.len;
        while (i > 0) {
            i -= 1;
            const idx = self.create_order[i];
            self.descs[idx].destroy_fn(self.allocator, registry, self.contexts[idx]);
        }
        self.allocator.free(self.contexts);
        self.allocator.free(self.create_order);
        self.allocator.free(self.update_order);
    }

    pub fn update(self: *SystemManager, registry: *Registry, dt: f32) !void {
        for (self.update_order) |idx| {
            try self.descs[idx].update_fn(registry, self.contexts[idx], dt);
        }
    }
};

fn noopUpdate(_: *Registry, _: *anyopaque, _: f32) anyerror!void {}

fn noopCreate(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const slot = try ctx.allocator.create(u8);
    slot.* = 0;
    return @ptrCast(slot);
}

fn noopDestroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const slot: *u8 = @ptrCast(@alignCast(ctx));
    allocator.destroy(slot);
}

fn noopDestroyFree(_: std.mem.Allocator, _: *Registry, _: *anyopaque) void {}

const OrderTracker = struct {
    order: *std.ArrayList(u8),
    id: u8 = 0,
    fn update(_: *Registry, ctx: *anyopaque, _: f32) anyerror!void {
        const self: *OrderTracker = @ptrCast(@alignCast(ctx));
        try self.order.append(std.testing.allocator, self.id);
    }
};

test "SystemManager sorts create_order descending and update_order ascending" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const descs = [_]SystemDesc{
        .{ .name = "low", .priority = 10, .create_fn = noopCreate, .update_fn = noopUpdate, .destroy_fn = noopDestroy },
        .{ .name = "high", .priority = -5, .create_fn = noopCreate, .update_fn = noopUpdate, .destroy_fn = noopDestroy },
        .{ .name = "mid", .priority = 0, .create_fn = noopCreate, .update_fn = noopUpdate, .destroy_fn = noopDestroy },
    };

    var config = Config{};
    var create_ctx = SystemCreateCtx{
        .allocator = std.testing.allocator,
        .registry = &reg,
        .config = &config,
    };

    var manager = try SystemManager.init(std.testing.allocator, &descs, &create_ctx);
    defer manager.deinit(&reg);

    // create_order: descending → low(10), mid(0), high(-5)
    try std.testing.expectEqualStrings("low", manager.descs[manager.create_order[0]].name);
    try std.testing.expectEqualStrings("mid", manager.descs[manager.create_order[1]].name);
    try std.testing.expectEqualStrings("high", manager.descs[manager.create_order[2]].name);

    // update_order: ascending → high(-5), mid(0), low(10)
    try std.testing.expectEqualStrings("high", manager.descs[manager.update_order[0]].name);
    try std.testing.expectEqualStrings("mid", manager.descs[manager.update_order[1]].name);
    try std.testing.expectEqualStrings("low", manager.descs[manager.update_order[2]].name);
}

test "update calls systems in ascending priority order" {
    var order: std.ArrayList(u8) = .empty;
    defer order.deinit(std.testing.allocator);

    var t1 = OrderTracker{ .order = &order, .id = 1 };
    var t2 = OrderTracker{ .order = &order, .id = 2 };
    var t3 = OrderTracker{ .order = &order, .id = 3 };

    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const descs = [_]SystemDesc{
        .{ .name = "c", .priority = 10, .create_fn = noopCreate, .update_fn = OrderTracker.update, .destroy_fn = noopDestroyFree },
        .{ .name = "a", .priority = -5, .create_fn = noopCreate, .update_fn = OrderTracker.update, .destroy_fn = noopDestroyFree },
        .{ .name = "b", .priority = 0, .create_fn = noopCreate, .update_fn = OrderTracker.update, .destroy_fn = noopDestroyFree },
    };

    var config = Config{};
    var create_ctx = SystemCreateCtx{
        .allocator = std.testing.allocator,
        .registry = &reg,
        .config = &config,
    };

    var manager = try SystemManager.init(std.testing.allocator, &descs, &create_ctx);
    defer manager.deinit(&reg);

    // Free the noopCreate'd contexts, then override with our trackers
    for (manager.contexts) |c| {
        const slot: *u8 = @ptrCast(@alignCast(c));
        std.testing.allocator.destroy(slot);
    }
    manager.contexts[0] = @ptrCast(&t1);
    manager.contexts[1] = @ptrCast(&t2);
    manager.contexts[2] = @ptrCast(&t3);

    try manager.update(&reg, 0.0);

    try std.testing.expectEqual(@as(usize, 3), order.items.len);
    try std.testing.expectEqual(@as(u8, 2), order.items[0]); // a (priority -5)
    try std.testing.expectEqual(@as(u8, 3), order.items[1]); // b (priority 0)
    try std.testing.expectEqual(@as(u8, 1), order.items[2]); // c (priority 10)
}

test "deinit calls destroy_fn in reverse create order" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const DestroyTracker = struct {
        called: *bool,
        fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
            const self = try ctx.allocator.create(@This());
            return @ptrCast(self);
        }
        fn destroy(allocator: std.mem.Allocator, _: *Registry, c: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(c));
            self.called.* = true;
            allocator.destroy(self);
        }
        fn update(_: *Registry, _: *anyopaque, _: f32) anyerror!void {}
    };

    var called = false;

    const descs = [_]SystemDesc{
        .{ .name = "test", .priority = 0, .create_fn = DestroyTracker.create, .update_fn = DestroyTracker.update, .destroy_fn = DestroyTracker.destroy },
    };

    var config = Config{};
    var create_ctx = SystemCreateCtx{
        .allocator = std.testing.allocator,
        .registry = &reg,
        .config = &config,
    };

    var manager = try SystemManager.init(std.testing.allocator, &descs, &create_ctx);
    {
        const tracker: *DestroyTracker = @ptrCast(@alignCast(manager.contexts[0]));
        tracker.called = &called;
    }
    manager.deinit(&reg);

    try std.testing.expect(called);
}
