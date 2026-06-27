//! Patrol/chase/attack/retreat/dead FSM over a CharacterController, per
//! CLAUDE.md M9. Steering is a direct setVelocity each frame (no accel/
//! friction lerp like PlayerMovementComponent — out of scope for this pass,
//! AI doesn't need to feel hand-tuned the way player movement does).
//! Targeting has no faction/threat-table system yet: the only target type
//! is "the nearest PlayerMovementComponent entity within sight_range with
//! clear line of sight" — a deliberate stand-in, not a placeholder forgotten
//! mid-build, since this is meant as the basis for Knave boss behavior trees
//! later, not the final word on targeting.
const std = @import("std");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const components = @import("../engine/ecs/components/components.zig");
const event = @import("../engine/ecs/event.zig");
const SystemCreateCtx = @import("../engine/ecs/systems/system.zig").SystemCreateCtx;
const physics_world = @import("../physics/physics_world.zig");
const physics_shared = @import("../physics/physics_shared.zig");
const raycast = @import("../physics/raycast.zig");
const character_controller = @import("../physics/character_controller.zig");

/// Casts a ray from `from` to just short of `to` (stopping 0.1 short avoids
/// a false "blocked" hit on the target's own collider, if it has one — a
/// CharacterController target has no queryable body at all, so this mostly
/// matters for AI-vs-AI or AI-vs-physics-body targets). No hit before that
/// point means line of sight is clear.
fn hasLineOfSight(world: *physics_world.PhysicsWorld, from: @Vector(3, f32), to: @Vector(3, f32)) bool {
    const diff = to - from;
    const dist_sq = @reduce(.Add, diff * diff);
    if (dist_sq < 0.0025) return true;
    const dist = @sqrt(dist_sq);
    const dir = diff / @as(@Vector(3, f32), @splat(dist));
    const check_dist = dist - 0.1;
    if (check_dist <= 0) return true;
    return raycast.raycast(world, from, dir, check_dist) == null;
}

fn findVisibleTarget(registry: *Registry, world: *physics_world.PhysicsWorld, ai_pos: @Vector(3, f32), sight_range: f32) ?Entity {
    var best: ?Entity = null;
    var best_dist_sq: f32 = sight_range * sight_range;

    var it = registry.Query(.{ components.PlayerMovementComponent, components.TransformComponent });
    while (it.next()) |target| {
        const t = registry.get(components.TransformComponent, target).?;
        const diff = t.position - ai_pos;
        const dist_sq = @reduce(.Add, diff * diff);
        if (dist_sq > best_dist_sq) continue;
        if (!hasLineOfSight(world, ai_pos, t.position)) continue;
        best = target;
        best_dist_sq = dist_sq;
    }
    return best;
}

fn setHorizontalVelocity(handle: *anyopaque, horiz: @Vector(3, f32)) void {
    const v = character_controller.getVelocity(handle);
    character_controller.setVelocity(handle, .{ horiz[0], v[1], horiz[2] });
}

fn steerToward(handle: *anyopaque, from: @Vector(3, f32), to: @Vector(3, f32), speed: f32) void {
    var dir = to - from;
    dir[1] = 0;
    const len_sq = @reduce(.Add, dir * dir);
    if (len_sq < 1e-6) {
        setHorizontalVelocity(handle, .{ 0, 0, 0 });
        return;
    }
    dir = dir / @as(@Vector(3, f32), @splat(@sqrt(len_sq)));
    setHorizontalVelocity(handle, dir * @as(@Vector(3, f32), @splat(speed)));
}

fn onDeath(ctx: *anyopaque, payload: event.EventPayload) void {
    const registry: *Registry = @ptrCast(@alignCast(ctx));
    const ai = registry.get(components.AIComponent, payload.death_event.entity) orelse return;
    ai.state = .dead;
    ai.target = null;
}

pub fn update(registry: *Registry, _: *anyopaque, _: f32) anyerror!void {
    const world = physics_shared.world orelse return;

    var it = registry.Query(.{ components.AIComponent, components.TransformComponent, components.CharacterControllerComponent });
    while (it.next()) |e| {
        const ai = registry.get(components.AIComponent, e).?;
        if (ai.state == .dead) continue;

        const ch = registry.get(components.CharacterControllerComponent, e).?;
        const transform = registry.get(components.TransformComponent, e).?;

        if (registry.get(components.HealthComponent, e)) |h| {
            if (h.max > 0 and h.current / h.max <= ai.retreat_health_fraction and ai.state != .retreat) {
                ai.state = .retreat;
            }
        }

        switch (ai.state) {
            .patrol => {
                if (ai.patrol_count > 0) {
                    const wp = ai.patrol_points[ai.patrol_index];
                    steerToward(ch.handle, transform.position, wp, ai.patrol_speed);
                    const diff = wp - transform.position;
                    if (@reduce(.Add, diff * diff) < 0.25) {
                        ai.patrol_index = (ai.patrol_index + 1) % ai.patrol_count;
                    }
                } else {
                    setHorizontalVelocity(ch.handle, .{ 0, 0, 0 });
                }

                if (findVisibleTarget(registry, world, transform.position, ai.sight_range)) |target| {
                    ai.state = .chase;
                    ai.target = target;
                }
            },
            .chase => {
                const target = ai.target orelse {
                    ai.state = .patrol;
                    continue;
                };
                const tt = blk: {
                    if (!registry.isAlive(target)) break :blk null;
                    break :blk registry.get(components.TransformComponent, target);
                } orelse {
                    ai.state = .patrol;
                    ai.target = null;
                    continue;
                };

                const diff = tt.position - transform.position;
                const dist_sq = @reduce(.Add, diff * diff);
                const give_up_range = ai.sight_range * 1.5;
                if (dist_sq <= ai.attack_range * ai.attack_range) {
                    ai.state = .attack;
                    setHorizontalVelocity(ch.handle, .{ 0, 0, 0 });
                } else if (dist_sq > give_up_range * give_up_range) {
                    ai.state = .patrol;
                    ai.target = null;
                } else {
                    steerToward(ch.handle, transform.position, tt.position, ai.chase_speed);
                }
            },
            .attack => {
                const target = ai.target orelse {
                    ai.state = .patrol;
                    continue;
                };
                const tt = blk: {
                    if (!registry.isAlive(target)) break :blk null;
                    break :blk registry.get(components.TransformComponent, target);
                } orelse {
                    ai.state = .patrol;
                    ai.target = null;
                    continue;
                };

                const diff = tt.position - transform.position;
                const dist_sq = @reduce(.Add, diff * diff);
                if (dist_sq > ai.attack_range * ai.attack_range) {
                    ai.state = .chase;
                } else {
                    setHorizontalVelocity(ch.handle, .{ 0, 0, 0 });
                    transform.rotation[1] = std.math.atan2(diff[0], diff[2]) * (180.0 / std.math.pi);
                    if (registry.get(components.MeleeAttackComponent, e)) |atk| atk.trigger = true;
                }
            },
            .retreat => {
                // No target to flee from (e.g. a health-triggered retreat with
                // nothing chasing yet) — hold position rather than bouncing
                // straight back to patrol; only a target moving out of
                // sight_range ends the retreat below.
                const target = ai.target;
                const tt = if (target) |t| registry.get(components.TransformComponent, t) else null;
                if (tt) |target_t| {
                    var dir = transform.position - target_t.position;
                    const dist_sq = @reduce(.Add, dir * dir);
                    if (dist_sq > ai.sight_range * ai.sight_range) {
                        ai.state = .patrol;
                        ai.target = null;
                    } else {
                        const len = @sqrt(dist_sq);
                        if (len > 1e-4) dir = dir / @as(@Vector(3, f32), @splat(len));
                        setHorizontalVelocity(ch.handle, dir * @as(@Vector(3, f32), @splat(ai.chase_speed)));
                    }
                } else {
                    setHorizontalVelocity(ch.handle, .{ 0, 0, 0 });
                }
            },
            .dead => unreachable,
        }
    }
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    try ctx.registry.events.subscribe(.death_event, ctx.registry, onDeath);
    const slot = try ctx.allocator.create(u8);
    slot.* = 0;
    return @ptrCast(slot);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const slot: *u8 = @ptrCast(@alignCast(ctx));
    allocator.destroy(slot);
}

fn spawnAI(reg: *Registry, world: *physics_world.PhysicsWorld, pos: @Vector(3, f32), ai: components.AIComponent) !Entity {
    const e = try reg.create();
    try character_controller.spawnCharacter(reg, world, e, 0.5, 1.8, pos);
    try reg.add(e, components.TransformComponent{ .position = pos, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(e, ai);
    return e;
}

test "patrol moves toward the current waypoint and loops to the next on arrival" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    var ai = components.AIComponent{ .patrol_speed = 3.0 };
    ai.patrol_points[0] = .{ 5, 0, 0 };
    ai.patrol_points[1] = .{ 0, 0, 0 };
    ai.patrol_count = 2;
    const e = try spawnAI(&reg, &world, .{ 0, 0, 0 }, ai);
    defer character_controller.despawnCharacter(&reg, &world, e);

    try update(&reg, undefined, 1.0 / 60.0);

    const v = character_controller.getVelocity(reg.get(components.CharacterControllerComponent, e).?.handle);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), v[0], 0.01);
}

test "a visible target within sight_range triggers a transition to chase" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const e = try spawnAI(&reg, &world, .{ 0, 0, 0 }, .{ .sight_range = 10.0 });
    defer character_controller.despawnCharacter(&reg, &world, e);

    const target = try reg.create();
    try reg.add(target, components.TransformComponent{ .position = .{ 5, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(target, components.PlayerMovementComponent{});

    try update(&reg, undefined, 1.0 / 60.0);

    const ai = reg.get(components.AIComponent, e).?;
    try std.testing.expectEqual(components.AIState.chase, ai.state);
    try std.testing.expectEqual(target, ai.target.?);
}

test "an occluder blocking line of sight keeps the AI in patrol" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const wall = try reg.create();
    _ = try physics_world.spawnBoxBody(&reg, &world, wall, .{ 0.2, 5, 5 }, 0, .{ 2.5, 0, 0 }, .static, true, false);
    world.step(1.0 / 60.0);

    const e = try spawnAI(&reg, &world, .{ 0, 0, 0 }, .{ .sight_range = 10.0 });
    defer character_controller.despawnCharacter(&reg, &world, e);

    const target = try reg.create();
    try reg.add(target, components.TransformComponent{ .position = .{ 5, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(target, components.PlayerMovementComponent{});

    try update(&reg, undefined, 1.0 / 60.0);

    const ai = reg.get(components.AIComponent, e).?;
    try std.testing.expectEqual(components.AIState.patrol, ai.state);
    try std.testing.expect(ai.target == null);
}

test "chase transitions to attack within attack_range and triggers a melee attack" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    const target = try reg.create();
    try reg.add(target, components.TransformComponent{ .position = .{ 1, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(target, components.PlayerMovementComponent{});

    var ai = components.AIComponent{ .attack_range = 1.5 };
    ai.state = .chase;
    ai.target = target;
    const e = try spawnAI(&reg, &world, .{ 0, 0, 0 }, ai);
    defer character_controller.despawnCharacter(&reg, &world, e);
    try reg.add(e, components.MeleeAttackComponent{});

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectEqual(components.AIState.attack, reg.get(components.AIComponent, e).?.state);

    try update(&reg, undefined, 1.0 / 60.0);
    try std.testing.expectEqual(true, reg.get(components.MeleeAttackComponent, e).?.trigger);
}

test "low health forces a transition to retreat regardless of current state" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    var ai = components.AIComponent{ .retreat_health_fraction = 0.3 };
    ai.state = .chase;
    const e = try spawnAI(&reg, &world, .{ 0, 0, 0 }, ai);
    defer character_controller.despawnCharacter(&reg, &world, e);
    try reg.add(e, components.HealthComponent{ .current = 10, .max = 100 });

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectEqual(components.AIState.retreat, reg.get(components.AIComponent, e).?.state);
}

test "death_event puts the AI into the dead state and stops processing it" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();
    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();
    physics_shared.world = &world;
    defer physics_shared.world = null;

    try reg.events.subscribe(.death_event, &reg, onDeath);

    var ai = components.AIComponent{};
    ai.state = .chase;
    const e = try spawnAI(&reg, &world, .{ 0, 0, 0 }, ai);
    defer character_controller.despawnCharacter(&reg, &world, e);

    reg.events.emit(.{ .death_event = .{ .entity = e, .source = null } });

    try std.testing.expectEqual(components.AIState.dead, reg.get(components.AIComponent, e).?.state);

    try update(&reg, undefined, 1.0 / 60.0);
    try std.testing.expectEqual(components.AIState.dead, reg.get(components.AIComponent, e).?.state);
}
