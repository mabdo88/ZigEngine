//! HealthComponent + DamageEvent, per CLAUDE.md M9. Damage/heal is applied
//! through registry.events (this codebase's EventBus, not Flecs observers —
//! same substitution M4/M5 already made for anim/trigger events): callers
//! emit a .damage_event, HealthSystem applies it to the target's
//! HealthComponent and emits .death_event exactly once when current crosses
//! from >0 to 0 (invincible entities ignore incoming damage entirely, not
//! just death).
const std = @import("std");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const components = @import("../engine/ecs/components/components.zig");
const event = @import("../engine/ecs/event.zig");
const SystemCreateCtx = @import("../engine/ecs/systems/system.zig").SystemCreateCtx;

pub fn update(registry: *Registry, _: *anyopaque, dt: f32) anyerror!void {
    var it = registry.Query(.{components.HealthComponent});
    while (it.next()) |e| {
        const h = registry.get(components.HealthComponent, e).?;
        if (h.regen_per_sec != 0 and h.current > 0 and h.current < h.max) {
            h.current = @min(h.max, h.current + h.regen_per_sec * dt);
        }
        if (h.invincible_timer > 0) {
            h.invincible_timer = @max(0, h.invincible_timer - dt);
        }
    }
}

fn onDamage(ctx: *anyopaque, payload: event.EventPayload) void {
    const registry: *Registry = @ptrCast(@alignCast(ctx));
    const dmg = payload.damage_event;

    const h = registry.get(components.HealthComponent, dmg.target) orelse return;
    if (h.invincible or h.invincible_timer > 0) return;
    if (h.current <= 0) return;

    const was_alive = h.current > 0;
    h.current = @max(0, h.current - dmg.amount);

    registry.events.emit(.{ .hit_reaction_event = .{ .entity = dmg.target, .source = dmg.source } });

    if (was_alive and h.current <= 0) {
        registry.events.emit(.{ .death_event = .{ .entity = dmg.target, .source = dmg.source } });
    } else if (h.iframe_duration > 0) {
        h.invincible_timer = h.iframe_duration;
    }
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    try ctx.registry.events.subscribe(.damage_event, ctx.registry, onDamage);
    const slot = try ctx.allocator.create(u8);
    slot.* = 0;
    return @ptrCast(slot);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const slot: *u8 = @ptrCast(@alignCast(ctx));
    allocator.destroy(slot);
}

test "damage reduces current health" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    try reg.events.subscribe(.damage_event, &reg, onDamage);

    const e = try reg.create();
    try reg.add(e, components.HealthComponent{ .current = 100, .max = 100 });

    reg.events.emit(.{ .damage_event = .{ .target = e, .amount = 30, .source = null } });

    const h = reg.get(components.HealthComponent, e).?;
    try std.testing.expectEqual(@as(f32, 70), h.current);
}

test "damage that drops health to zero or below emits death_event exactly once" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    try reg.events.subscribe(.damage_event, &reg, onDamage);

    const e = try reg.create();
    try reg.add(e, components.HealthComponent{ .current = 10, .max = 100 });

    var death_count: u32 = 0;
    const Counter = struct {
        count: *u32,
        fn cb(c: *anyopaque, _: event.EventPayload) void {
            const self: *@This() = @ptrCast(@alignCast(c));
            self.count.* += 1;
        }
    };
    var counter = Counter{ .count = &death_count };
    try reg.events.subscribe(.death_event, &counter, Counter.cb);

    reg.events.emit(.{ .damage_event = .{ .target = e, .amount = 999, .source = null } });
    reg.events.emit(.{ .damage_event = .{ .target = e, .amount = 999, .source = null } });

    try std.testing.expectEqual(@as(u32, 1), death_count);
    try std.testing.expectEqual(@as(f32, 0), reg.get(components.HealthComponent, e).?.current);
}

test "invincible entities ignore damage" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    try reg.events.subscribe(.damage_event, &reg, onDamage);

    const e = try reg.create();
    try reg.add(e, components.HealthComponent{ .current = 50, .max = 100, .invincible = true });

    reg.events.emit(.{ .damage_event = .{ .target = e, .amount = 50, .source = null } });

    try std.testing.expectEqual(@as(f32, 50), reg.get(components.HealthComponent, e).?.current);
}

test "invincible_timer blocks damage until it expires" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    try reg.events.subscribe(.damage_event, &reg, onDamage);

    const e = try reg.create();
    try reg.add(e, components.HealthComponent{ .current = 50, .max = 100, .invincible_timer = 0.5 });

    reg.events.emit(.{ .damage_event = .{ .target = e, .amount = 50, .source = null } });
    try std.testing.expectEqual(@as(f32, 50), reg.get(components.HealthComponent, e).?.current);

    try update(&reg, undefined, 0.6);
    reg.events.emit(.{ .damage_event = .{ .target = e, .amount = 50, .source = null } });
    try std.testing.expectEqual(@as(f32, 0), reg.get(components.HealthComponent, e).?.current);
}

test "a surviving hit with iframe_duration grants invincible_timer" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    try reg.events.subscribe(.damage_event, &reg, onDamage);

    const e = try reg.create();
    try reg.add(e, components.HealthComponent{ .current = 100, .max = 100, .iframe_duration = 0.5 });

    reg.events.emit(.{ .damage_event = .{ .target = e, .amount = 30, .source = null } });

    const h = reg.get(components.HealthComponent, e).?;
    try std.testing.expectEqual(@as(f32, 70), h.current);
    try std.testing.expectEqual(@as(f32, 0.5), h.invincible_timer);
}

test "a killing hit does not grant invincible_timer even with iframe_duration set" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    try reg.events.subscribe(.damage_event, &reg, onDamage);

    const e = try reg.create();
    try reg.add(e, components.HealthComponent{ .current = 10, .max = 100, .iframe_duration = 0.5 });

    reg.events.emit(.{ .damage_event = .{ .target = e, .amount = 999, .source = null } });

    try std.testing.expectEqual(@as(f32, 0), reg.get(components.HealthComponent, e).?.invincible_timer);
}

test "hit_reaction_event fires whenever damage actually lands" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    try reg.events.subscribe(.damage_event, &reg, onDamage);

    const e = try reg.create();
    try reg.add(e, components.HealthComponent{ .current = 100, .max = 100 });

    var hit_count: u32 = 0;
    const Counter = struct {
        count: *u32,
        fn cb(c: *anyopaque, _: event.EventPayload) void {
            const self: *@This() = @ptrCast(@alignCast(c));
            self.count.* += 1;
        }
    };
    var counter = Counter{ .count = &hit_count };
    try reg.events.subscribe(.hit_reaction_event, &counter, Counter.cb);

    reg.events.emit(.{ .damage_event = .{ .target = e, .amount = 10, .source = null } });
    try std.testing.expectEqual(@as(u32, 1), hit_count);
}

test "hit_reaction_event does not fire when damage is blocked by invincibility" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    try reg.events.subscribe(.damage_event, &reg, onDamage);

    const e = try reg.create();
    try reg.add(e, components.HealthComponent{ .current = 100, .max = 100, .invincible = true });

    var hit_count: u32 = 0;
    const Counter = struct {
        count: *u32,
        fn cb(c: *anyopaque, _: event.EventPayload) void {
            const self: *@This() = @ptrCast(@alignCast(c));
            self.count.* += 1;
        }
    };
    var counter = Counter{ .count = &hit_count };
    try reg.events.subscribe(.hit_reaction_event, &counter, Counter.cb);

    reg.events.emit(.{ .damage_event = .{ .target = e, .amount = 10, .source = null } });
    try std.testing.expectEqual(@as(u32, 0), hit_count);
}

test "regen_per_sec heals over time but never exceeds max" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const e = try reg.create();
    try reg.add(e, components.HealthComponent{ .current = 90, .max = 100, .regen_per_sec = 50 });

    try update(&reg, undefined, 1.0);
    try std.testing.expectEqual(@as(f32, 100), reg.get(components.HealthComponent, e).?.current);
}
