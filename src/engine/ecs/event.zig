const std = @import("std");
const Entity = @import("entity/entity.zig").Entity;

pub const EventType = enum {
    entity_destroyed,
    scene_unloaded,
    anim_event,
};

pub const AnimEventPayload = struct {
    entity: Entity,
    /// Points into the clip's own owned event name (Registry.clip_cache
    /// outlives any single frame) — valid for the duration of this emit
    /// call, not guaranteed to outlive it.
    name: []const u8,
};

pub const EventPayload = union(EventType) {
    entity_destroyed: Entity,
    scene_unloaded: void,
    anim_event: AnimEventPayload,
};

pub const Handler = struct {
    event_type: EventType,
    callback: *const fn (*anyopaque, EventPayload) void,
    context: *anyopaque,
};

pub const EventBus = struct {
    handlers: std.ArrayList(Handler) = .empty,
    allocator: std.mem.Allocator = undefined,

    pub fn init(allocator: std.mem.Allocator) EventBus {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *EventBus) void {
        self.handlers.deinit(self.allocator);
    }

    pub fn subscribe(self: *EventBus, event_type: EventType, context: *anyopaque, callback: *const fn (*anyopaque, EventPayload) void) !void {
        try self.handlers.append(self.allocator, .{
            .event_type = event_type,
            .callback = callback,
            .context = context,
        });
    }

    pub fn emit(self: *EventBus, event: EventPayload) void {
        const et: EventType = event;
        for (self.handlers.items) |h| {
            if (h.event_type == et) {
                h.callback(h.context, event);
            }
        }
    }
};

test "subscribe and emit receives event" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    const Counter = struct {
        count: *u32,
        fn cb(ctx: *anyopaque, _: EventPayload) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.count.* += 1;
        }
    };
    var count: u32 = 0;
    var counter = Counter{ .count = &count };
    try bus.subscribe(.entity_destroyed, &counter, Counter.cb);

    bus.emit(.{ .entity_destroyed = Entity.make(0, 0) });
    try std.testing.expectEqual(@as(u32, 1), count);
}

test "multiple handlers for same event type all fire" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    const Counter = struct {
        count: *u32,
        fn cb(ctx: *anyopaque, _: EventPayload) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.count.* += 1;
        }
    };

    var c1: u32 = 0;
    var c2: u32 = 0;
    var counter1 = Counter{ .count = &c1 };
    var counter2 = Counter{ .count = &c2 };
    try bus.subscribe(.scene_unloaded, &counter1, Counter.cb);
    try bus.subscribe(.scene_unloaded, &counter2, Counter.cb);

    bus.emit(.{ .scene_unloaded = {} });
    try std.testing.expectEqual(@as(u32, 1), c1);
    try std.testing.expectEqual(@as(u32, 1), c2);
}

test "handler only receives matching event type" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    const Counter = struct {
        count: *u32,
        fn cb(ctx: *anyopaque, _: EventPayload) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.count.* += 1;
        }
    };

    var destroyed_count: u32 = 0;
    var unloaded_count: u32 = 0;
    var dc = Counter{ .count = &destroyed_count };
    var uc = Counter{ .count = &unloaded_count };
    try bus.subscribe(.entity_destroyed, &dc, Counter.cb);
    try bus.subscribe(.scene_unloaded, &uc, Counter.cb);

    bus.emit(.{ .entity_destroyed = Entity.make(0, 0) });
    try std.testing.expectEqual(@as(u32, 1), destroyed_count);
    try std.testing.expectEqual(@as(u32, 0), unloaded_count);

    bus.emit(.{ .scene_unloaded = {} });
    try std.testing.expectEqual(@as(u32, 1), destroyed_count);
    try std.testing.expectEqual(@as(u32, 1), unloaded_count);
}

test "emit with no handlers is safe" {
    var bus = EventBus.init(std.testing.allocator);
    defer bus.deinit();

    bus.emit(.{ .entity_destroyed = Entity.make(0, 0) });
    bus.emit(.{ .scene_unloaded = {} });
}
