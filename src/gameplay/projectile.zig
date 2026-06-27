//! Per-frame raycast-sweep projectiles, per CLAUDE.md M9. Each tick casts a
//! ray along velocity*dt from the projectile's current position rather than
//! relying on a real (tiny, fast-moving) Jolt rigid body — a fast projectile
//! would tunnel through thin colliders between physics steps otherwise, the
//! same reasoning Jolt's own raycast-based "continuous collision" approach
//! uses for small fast shapes.
const std = @import("std");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const components = @import("../engine/ecs/components/components.zig");
const SystemCreateCtx = @import("../engine/ecs/systems/system.zig").SystemCreateCtx;
const physics_world = @import("../physics/physics_world.zig");
const physics_shared = @import("../physics/physics_shared.zig");
const raycast = @import("../physics/raycast.zig");
const prefab = @import("../scene/prefab.zig");
const log = @import("../engine/log.zig");

fn sameEntity(a: Entity, b: Entity) bool {
    return a.index == b.index and a.generation == b.generation;
}

/// Applies damage/impulse/impact-VFX for a confirmed hit. `impact_prefab_id`
/// spawning is best-effort — a missing/uninitialized PrefabRegistry (or a
/// failed instantiate, e.g. a bad asset path) is logged and skipped rather
/// than propagated, since a cosmetic VFX failure shouldn't be allowed to
/// break the actual hit resolution that already happened above it.
fn onHit(registry: *Registry, world: *physics_world.PhysicsWorld, proj: *const components.ProjectileComponent, hit: raycast.RaycastHit) void {
    if (registry.get(components.HealthComponent, hit.entity) != null) {
        registry.events.emit(.{ .damage_event = .{ .target = hit.entity, .amount = proj.damage, .source = proj.owner } });
    }

    if (proj.impulse > 0) {
        if (registry.get(components.PhysicsBodyComponent, hit.entity)) |body| {
            if (!body.is_static) {
                const speed_sq = @reduce(.Add, proj.velocity * proj.velocity);
                if (speed_sq > 1e-10) {
                    const dir = proj.velocity / @as(@Vector(3, f32), @splat(@sqrt(speed_sq)));
                    world.applyImpulse(body.body_id, dir * @as(@Vector(3, f32), @splat(proj.impulse)));
                }
            }
        }
    }

    if (proj.impact_prefab_id) |pid| {
        const preg = prefab.global orelse return;
        _ = preg.instantiate(registry, pid, .{ .position = hit.point, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } }) catch |err| {
            log.warn(@src(), "projectile: failed to spawn impact VFX (prefab {d}): {s}", .{ pid, @errorName(err) });
        };
    }
}

pub fn update(registry: *Registry, _: *anyopaque, dt: f32) anyerror!void {
    const world = physics_shared.world orelse return;

    var to_destroy: std.ArrayList(Entity) = .empty;
    defer to_destroy.deinit(registry.registry_allocator);

    var it = registry.Query(.{ components.ProjectileComponent, components.TransformComponent });
    while (it.next()) |e| {
        const proj = registry.get(components.ProjectileComponent, e).?;
        proj.lifetime -= dt;
        if (proj.lifetime <= 0) {
            try to_destroy.append(registry.registry_allocator, e);
            continue;
        }

        const transform = registry.get(components.TransformComponent, e).?;
        const delta = proj.velocity * @as(@Vector(3, f32), @splat(dt));
        const dist_sq = @reduce(.Add, delta * delta);

        if (dist_sq > 1e-12) {
            const dist = @sqrt(dist_sq);
            const dir = delta / @as(@Vector(3, f32), @splat(dist));
            if (raycast.raycast(world, transform.position, dir, dist)) |hit| {
                if (proj.owner == null or !sameEntity(hit.entity, proj.owner.?)) {
                    transform.position = hit.point;
                    onHit(registry, world, proj, hit);
                    try to_destroy.append(registry.registry_allocator, e);
                    continue;
                }
            }
        }

        transform.position += delta;
    }

    for (to_destroy.items) |e| registry.destroyEntity(e) catch {};
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

test "a projectile with nothing in its path moves by velocity*dt" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const e = try reg.create();
    try reg.add(e, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(e, components.ProjectileComponent{ .velocity = .{ 10, 0, 0 } });

    try update(&reg, undefined, 1.0 / 60.0);

    const t = reg.get(components.TransformComponent, e).?;
    try std.testing.expectApproxEqAbs(@as(f32, 10.0 / 60.0), t.position[0], 1e-5);
}

test "lifetime reaching zero destroys the projectile" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const e = try reg.create();
    try reg.add(e, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(e, components.ProjectileComponent{ .velocity = .{ 1, 0, 0 }, .lifetime = 0.01 });

    try update(&reg, undefined, 1.0);

    try std.testing.expect(!reg.isAlive(e));
}

test "a projectile hitting a target with HealthComponent damages it and self-destructs" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const target = try reg.create();
    try reg.add(target, components.HealthComponent{ .current = 100, .max = 100 });
    _ = try physics_world.spawnBoxBody(&reg, &world, target, .{ 0.5, 0.5, 0.5 }, 1.0, .{ 5, 0, 0 }, .enemy, false, false);
    world.step(1.0 / 60.0);

    var damage_amount: f32 = 0;
    try reg.events.subscribe(.damage_event, &damage_amount, struct {
        fn cb(ctx: *anyopaque, payload: @import("../engine/ecs/event.zig").EventPayload) void {
            const amt: *f32 = @ptrCast(@alignCast(ctx));
            amt.* = payload.damage_event.amount;
        }
    }.cb);

    const projectile = try reg.create();
    try reg.add(projectile, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(projectile, components.ProjectileComponent{ .velocity = .{ 600, 0, 0 }, .damage = 40 });

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectApproxEqAbs(@as(f32, 40.0), damage_amount, 1e-6);
    try std.testing.expect(!reg.isAlive(projectile));
}

test "a projectile ignores a hit on its own owner and keeps flying" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const owner = try reg.create();
    _ = try physics_world.spawnBoxBody(&reg, &world, owner, .{ 0.5, 0.5, 0.5 }, 1.0, .{ 1, 0, 0 }, .player, false, false);
    world.step(1.0 / 60.0);

    const projectile = try reg.create();
    try reg.add(projectile, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(projectile, components.ProjectileComponent{ .velocity = .{ 60, 0, 0 }, .damage = 40, .owner = owner });

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expect(reg.isAlive(projectile));
    const t = reg.get(components.TransformComponent, projectile).?;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), t.position[0], 1e-5);
}

test "impulse knocks back a non-static physics body on hit" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const target = try reg.create();
    _ = try physics_world.spawnBoxBody(&reg, &world, target, .{ 0.5, 0.5, 0.5 }, 1.0, .{ 5, 0, 0 }, .enemy, false, false);
    world.step(1.0 / 60.0);

    const projectile = try reg.create();
    try reg.add(projectile, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(projectile, components.ProjectileComponent{ .velocity = .{ 600, 0, 0 }, .damage = 10, .impulse = 20 });

    try update(&reg, undefined, 1.0 / 60.0);

    var v: [3]f32 = undefined;
    physics_world.jolt.jolt_get_linear_velocity(world.ctx, reg.get(components.PhysicsBodyComponent, target).?.body_id, &v);
    try std.testing.expect(v[0] > 0);
}

test "an impact_prefab_id with no PrefabRegistry initialized is skipped without crashing" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;
    prefab.global = null;

    const target = try reg.create();
    _ = try physics_world.spawnBoxBody(&reg, &world, target, .{ 0.5, 0.5, 0.5 }, 1.0, .{ 5, 0, 0 }, .enemy, false, false);
    world.step(1.0 / 60.0);

    const projectile = try reg.create();
    try reg.add(projectile, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(projectile, components.ProjectileComponent{ .velocity = .{ 600, 0, 0 }, .damage = 10, .impact_prefab_id = 0 });

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expect(!reg.isAlive(projectile));
}
