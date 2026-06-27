const std = @import("std");
const Entity = @import("entity/entity.zig").Entity;

pub const EventType = enum {
    entity_destroyed,
    scene_unloaded,
    anim_event,
    trigger_event,
    damage_event,
    death_event,
    footstep_event,
    hit_reaction_event,
};

pub const AnimEventPayload = struct {
    entity: Entity,
    /// Points into the clip's own owned event name (Registry.clip_cache
    /// outlives any single frame) — valid for the duration of this emit
    /// call, not guaranteed to outlive it.
    name: []const u8,
};

pub const TriggerEventPayload = struct {
    trigger_ent: Entity,
    other_ent: Entity,
    is_enter: bool,
};

pub const DamageType = enum {
    physical,
    fire,
    poison,
    true_damage,
};

pub const DamageEventPayload = struct {
    target: Entity,
    amount: f32,
    dtype: DamageType = .physical,
    /// null for environmental/scripted damage with no attacking entity.
    source: ?Entity = null,
};

pub const DeathEventPayload = struct {
    entity: Entity,
    source: ?Entity = null,
};

/// Emitted by gameplay/movement.zig's PlayerMovementSystem whenever the
/// entity's accumulated ground-movement distance crosses footstep_interval.
/// No audio is wired to this yet — see PlayerMovementComponent's doc comment
/// and CLAUDE.md's M9 Movement entry for the same "infrastructure verified
/// in isolation, not yet wired end-to-end" caveat Health Component left.
pub const FootstepEventPayload = struct {
    entity: Entity,
};

/// Emitted by gameplay/health.zig's onDamage whenever damage actually lands
/// (i.e. not blocked by invincible/invincible_timer) — generic to every
/// damage source, not melee-specific, since any hit should be able to drive
/// a hit-reaction. No animation system subscribes to this yet: the only
/// rigged asset in the project (Cesium_Man.glb) has a single walk clip, no
/// hit-react clip to play — same "infrastructure verified in isolation"
/// caveat already on FootstepEventPayload, left for whenever a real
/// hit-react clip exists to drive blend_tree.zig/state_machine.zig with.
pub const HitReactionEventPayload = struct {
    entity: Entity,
    source: ?Entity = null,
};

pub const EventPayload = union(EventType) {
    entity_destroyed: Entity,
    scene_unloaded: void,
    anim_event: AnimEventPayload,
    trigger_event: TriggerEventPayload,
    damage_event: DamageEventPayload,
    death_event: DeathEventPayload,
    footstep_event: FootstepEventPayload,
    hit_reaction_event: HitReactionEventPayload,
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
