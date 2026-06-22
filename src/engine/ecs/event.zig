const std = @import("std");
const Entity = @import("entity/entity.zig").Entity;

pub const EventType = enum {
    entity_destroyed,
    scene_unloaded,
};

pub const EventPayload = union(EventType) {
    entity_destroyed: Entity,
    scene_unloaded: void,
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
