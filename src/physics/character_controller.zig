//! Thin Zig wrapper over Jolt's CharacterVirtual (a kinematic controller, not
//! a rigid body — no PhysicsBodyComponent, no BodyID). CharacterControllerSystem
//! (engine/ecs/systems/character_controller_system.zig) drives gravity + jump
//! and writeback into TransformComponent each frame; this module is just the
//! per-handle primitives gameplay code calls to steer a character.
const std = @import("std");
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const components = @import("../engine/ecs/components/components.zig");
const physics_world = @import("physics_world.zig");

pub const default_gravity_y: f32 = -9.81;

/// Creates a Jolt CharacterVirtual (capsule of the given radius/height) and
/// attaches CharacterControllerComponent to the entity.
pub fn spawnCharacter(
    registry: *Registry,
    world: *physics_world.PhysicsWorld,
    entity: Entity,
    radius: f32,
    height: f32,
    position: @Vector(3, f32),
) !void {
    const handle = physics_world.jolt.jolt_character_create(world.ctx, radius, height, position[0], position[1], position[2]).?;
    try registry.add(entity, components.CharacterControllerComponent{ .handle = @ptrCast(handle) });
}

pub fn despawnCharacter(registry: *Registry, world: *physics_world.PhysicsWorld, entity: Entity) void {
    const comp = registry.get(components.CharacterControllerComponent, entity) orelse return;
    physics_world.jolt.jolt_character_destroy(world.ctx, @ptrCast(comp.handle));
    registry.remove(components.CharacterControllerComponent, entity);
}

fn asJoltCharacter(handle: *anyopaque) *physics_world.jolt.JoltCharacter {
    return @ptrCast(handle);
}

/// Sets the character's full 3D velocity (horizontal movement + whatever
/// vertical speed gameplay wants going into the next update() — gravity
/// integration happens inside update(), not here).
pub fn setVelocity(handle: *anyopaque, velocity: @Vector(3, f32)) void {
    physics_world.jolt.jolt_character_set_velocity(asJoltCharacter(handle), velocity[0], velocity[1], velocity[2]);
}

pub fn getVelocity(handle: *anyopaque) @Vector(3, f32) {
    var v: [3]f32 = undefined;
    physics_world.jolt.jolt_character_get_velocity(asJoltCharacter(handle), &v);
    return .{ v[0], v[1], v[2] };
}

/// Resolves collisions/stairs/slopes and integrates position by dt.
///
/// Jolt's CharacterVirtual::Update does *not* integrate gravity into velocity
/// itself — it only uses the gravity argument to push down on whatever body
/// the character is currently standing on (see CharacterVirtual.cpp's
/// Update(), which applies an impulse to mGroundBodyID and otherwise just
/// moves the shape by the velocity already set via SetLinearVelocity). Actual
/// "falling" therefore has to be done by the caller — this matches Jolt's own
/// CharacterVirtual sample usage pattern (accumulate gravity into vertical
/// velocity while airborne, zero it on landing so it doesn't keep building up
/// while grounded).
pub fn update(world: *physics_world.PhysicsWorld, handle: *anyopaque, dt: f32, gravity_y: f32) void {
    const jh = asJoltCharacter(handle);
    var v = getVelocity(handle);
    // Only zero out a *non-positive* vertical velocity while grounded — a
    // positive one means gameplay just called jump() this tick, and
    // isGrounded() here is still reporting last frame's contact state (it
    // isn't refreshed until jolt_character_update's Update() call below), so
    // clobbering it unconditionally would kill the jump before it starts.
    if (isGrounded(handle) and v[1] <= 0) {
        v[1] = 0;
    } else {
        v[1] += gravity_y * dt;
    }
    setVelocity(handle, v);
    physics_world.jolt.jolt_character_update(world.ctx, jh, dt, gravity_y);
}

pub fn getPosition(handle: *anyopaque) @Vector(3, f32) {
    var p: [3]f32 = undefined;
    physics_world.jolt.jolt_character_get_position(asJoltCharacter(handle), &p);
    return .{ p[0], p[1], p[2] };
}

pub fn isGrounded(handle: *anyopaque) bool {
    return physics_world.jolt.jolt_character_is_grounded(asJoltCharacter(handle));
}

/// Sets vertical velocity to jump_speed if (and only if) currently grounded —
/// calling this while airborne is a no-op, matching the usual "no double
/// jump" expectation without CharacterSystem needing its own ground-state
/// bookkeeping.
pub fn jump(handle: *anyopaque, jump_speed: f32) void {
    if (!isGrounded(handle)) return;
    const v = getVelocity(handle);
    setVelocity(handle, .{ v[0], jump_speed, v[2] });
}
