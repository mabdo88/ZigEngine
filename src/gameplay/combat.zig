//! Melee combat over jolt_overlap_sphere, per CLAUDE.md M9. Gameplay code
//! requests an attack by setting MeleeAttackComponent.trigger = true (a one-
//! shot request, not a held button); MeleeAttackSystem clears it the instant
//! it actually fires, applies cooldown, and resolves the hitbox. Invincibility
//! frames on hit live in HealthComponent/health.zig (iframe_duration ->
//! invincible_timer), not here — this system only emits the damage event,
//! same separation Health Component already established for death.
const std = @import("std");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const components = @import("../engine/ecs/components/components.zig");
const SystemCreateCtx = @import("../engine/ecs/systems/system.zig").SystemCreateCtx;
const physics_shared = @import("../physics/physics_shared.zig");

pub fn update(registry: *Registry, _: *anyopaque, dt: f32) anyerror!void {
    const world = physics_shared.world orelse return;

    var it = registry.Query(.{ components.MeleeAttackComponent, components.TransformComponent });
    while (it.next()) |attacker| {
        const atk = registry.get(components.MeleeAttackComponent, attacker).?;
        if (atk.cooldown_timer > 0) atk.cooldown_timer = @max(0, atk.cooldown_timer - dt);
        if (!atk.trigger) continue;

        atk.trigger = false;
        if (atk.cooldown_timer > 0) continue;
        atk.cooldown_timer = atk.cooldown;

        const transform = registry.get(components.TransformComponent, attacker).?;
        const yaw_rad = transform.rotation[1] * (std.math.pi / 180.0);
        const forward = @Vector(3, f32){ @sin(yaw_rad), 0, @cos(yaw_rad) };
        const center = transform.position + forward * @as(@Vector(3, f32), @splat(atk.range));

        var hits: [16]Entity = undefined;
        const n = world.overlapSphere(center, atk.radius, &hits);
        for (hits[0..n]) |target| {
            if (target.index == attacker.index and target.generation == attacker.generation) continue;
            if (registry.get(components.HealthComponent, target) == null) continue;

            registry.events.emit(.{ .damage_event = .{ .target = target, .amount = atk.damage, .source = attacker } });

            if (registry.get(components.PhysicsBodyComponent, target)) |body| {
                if (!body.is_static) {
                    world.applyImpulse(body.body_id, forward * @as(@Vector(3, f32), @splat(atk.impulse)));
                }
            }
        }
    }
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const slot = try ctx.allocator.create(u8);
    slot.* = 0;
    return @ptrCast(slot);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const slot: *u8 = @ptrCast(@alignCast(ctx));
    allocator.destroy(slot);
}

const physics_world = @import("../physics/physics_world.zig");
const event = @import("../engine/ecs/event.zig");

test "a triggered attack damages a body in range and clears trigger" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const attacker = try reg.create();
    try reg.add(attacker, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(attacker, components.MeleeAttackComponent{ .range = 1.5, .radius = 0.6, .damage = 25, .trigger = true });

    const target = try reg.create();
    try reg.add(target, components.TransformComponent{ .position = .{ 0, 0, 1.5 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    _ = try physics_world.spawnBoxBody(&reg, &world, target, .{ 0.4, 0.4, 0.4 }, 1.0, .{ 0, 0, 1.5 }, .enemy, false, false);
    try reg.add(target, components.HealthComponent{ .current = 100, .max = 100 });
    try reg.events.subscribe(.damage_event, &reg, struct {
        fn cb(ctx: *anyopaque, payload: event.EventPayload) void {
            const r: *Registry = @ptrCast(@alignCast(ctx));
            const h = r.get(components.HealthComponent, payload.damage_event.target).?;
            h.current -= payload.damage_event.amount;
        }
    }.cb);

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectEqual(@as(f32, 75), reg.get(components.HealthComponent, target).?.current);
    try std.testing.expectEqual(false, reg.get(components.MeleeAttackComponent, attacker).?.trigger);
}

test "an attack does not damage a target out of range" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const attacker = try reg.create();
    try reg.add(attacker, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(attacker, components.MeleeAttackComponent{ .range = 1.5, .radius = 0.6, .damage = 25, .trigger = true });

    const target = try reg.create();
    try reg.add(target, components.TransformComponent{ .position = .{ 0, 0, 20 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    _ = try physics_world.spawnBoxBody(&reg, &world, target, .{ 0.4, 0.4, 0.4 }, 1.0, .{ 0, 0, 20 }, .enemy, false, false);
    try reg.add(target, components.HealthComponent{ .current = 100, .max = 100 });

    var damage_count: u32 = 0;
    const Counter = struct {
        count: *u32,
        fn cb(c: *anyopaque, _: event.EventPayload) void {
            const self: *@This() = @ptrCast(@alignCast(c));
            self.count.* += 1;
        }
    };
    var counter = Counter{ .count = &damage_count };
    try reg.events.subscribe(.damage_event, &counter, Counter.cb);

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectEqual(@as(u32, 0), damage_count);
}

test "an attack never hits the attacker itself" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const attacker = try reg.create();
    try reg.add(attacker, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(attacker, components.MeleeAttackComponent{ .range = 0.0, .radius = 2.0, .damage = 25, .trigger = true });
    _ = try physics_world.spawnBoxBody(&reg, &world, attacker, .{ 0.4, 0.4, 0.4 }, 1.0, .{ 0, 0, 0 }, .player, false, false);
    try reg.add(attacker, components.HealthComponent{ .current = 100, .max = 100 });

    var damage_count: u32 = 0;
    const Counter = struct {
        count: *u32,
        fn cb(c: *anyopaque, _: event.EventPayload) void {
            const self: *@This() = @ptrCast(@alignCast(c));
            self.count.* += 1;
        }
    };
    var counter = Counter{ .count = &damage_count };
    try reg.events.subscribe(.damage_event, &counter, Counter.cb);

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectEqual(@as(u32, 0), damage_count);
}

test "attack respects cooldown — retriggering immediately is a no-op until cooldown elapses" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const attacker = try reg.create();
    try reg.add(attacker, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(attacker, components.MeleeAttackComponent{ .range = 1.5, .radius = 0.6, .damage = 25, .cooldown = 1.0, .trigger = true });

    const target = try reg.create();
    try reg.add(target, components.TransformComponent{ .position = .{ 0, 0, 1.5 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    _ = try physics_world.spawnBoxBody(&reg, &world, target, .{ 0.4, 0.4, 0.4 }, 1.0, .{ 0, 0, 1.5 }, .enemy, false, false);
    try reg.add(target, components.HealthComponent{ .current = 100, .max = 100 });

    var damage_count: u32 = 0;
    const Counter = struct {
        count: *u32,
        fn cb(c: *anyopaque, _: event.EventPayload) void {
            const self: *@This() = @ptrCast(@alignCast(c));
            self.count.* += 1;
        }
    };
    var counter = Counter{ .count = &damage_count };
    try reg.events.subscribe(.damage_event, &counter, Counter.cb);

    try update(&reg, undefined, 1.0 / 60.0);
    try std.testing.expectEqual(@as(u32, 1), damage_count);

    registry_set_trigger(&reg, attacker);
    try update(&reg, undefined, 1.0 / 60.0);
    try std.testing.expectEqual(@as(u32, 1), damage_count);

    var i: usize = 0;
    while (i < 60) : (i += 1) try update(&reg, undefined, 1.0 / 60.0);
    registry_set_trigger(&reg, attacker);
    try update(&reg, undefined, 1.0 / 60.0);
    try std.testing.expectEqual(@as(u32, 2), damage_count);
}

fn registry_set_trigger(reg: *Registry, attacker: Entity) void {
    reg.get(components.MeleeAttackComponent, attacker).?.trigger = true;
}
