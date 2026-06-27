//! Thin Zig-facing owner of the Jolt physics system. Mirrors how
//! Registry.mesh_cache/skeleton_cache/clip_cache own their respective
//! native/asset state — Registry.physics follows the same convention so any
//! system (PhysicsSyncSystem, raycast.zig, character_controller.zig,
//! trigger.zig) can reach the same JoltCtx and body<->entity map.
const std = @import("std");
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const components = @import("../engine/ecs/components/components.zig");
const layers = @import("collision_layers.zig");

// Generated via `zig translate-c -I deps/jolt -I src/physics src/physics/jolt_wrapper.h`
// — this codebase pre-generates C bindings as committed .zig files (see
// src/resources/cgltf.zig, src/platform/glfw3.zig) rather than using @cImport
// at comptime, since @cImport isn't available outside the addTranslateC build
// graph in this Zig master. Regenerate if jolt_wrapper.h changes.
pub const jolt = @import("jolt_wrapper.zig");

pub const PhysicsWorld = struct {
    ctx: *jolt.JoltCtx,
    /// Resolves a Jolt BodyID (packed index+sequence, see BodyID in
    /// jolt_wrapper.cpp) back to the owning entity — needed by raycasts and
    /// trigger events, which only get a body_id from Jolt.
    body_to_entity: std.AutoHashMapUnmanaged(u32, Entity) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PhysicsWorld {
        return .{ .ctx = jolt.jolt_init().?, .allocator = allocator };
    }

    pub fn deinit(self: *PhysicsWorld) void {
        self.body_to_entity.deinit(self.allocator);
        jolt.jolt_deinit(self.ctx);
    }

    pub fn step(self: *PhysicsWorld, dt: f32) void {
        jolt.jolt_step(self.ctx, dt, 1);
    }

    pub fn entityForBody(self: *const PhysicsWorld, body_id: u32) ?Entity {
        return self.body_to_entity.get(body_id);
    }

    pub fn registerBody(self: *PhysicsWorld, body_id: u32, entity: Entity) !void {
        try self.body_to_entity.put(self.allocator, body_id, entity);
    }

    pub fn unregisterBody(self: *PhysicsWorld, body_id: u32) void {
        _ = self.body_to_entity.remove(body_id);
    }

    /// Sphere overlap query (melee hitboxes) — resolves every overlapping
    /// body back to an entity via body_to_entity, silently skipping bodies
    /// with no mapping (shouldn't happen, every body goes through
    /// spawnBoxBody, same defensive skip raycast.zig already does). Caps at
    /// a 32-entry stack buffer regardless of out_entities' size, matching
    /// raycastAll's fixed-cap reasoning — current gameplay-scale melee hits
    /// never need more.
    pub fn overlapSphere(self: *PhysicsWorld, center: @Vector(3, f32), radius: f32, out_entities: []Entity) usize {
        var body_ids: [32]u32 = undefined;
        const max_hits: c_int = @intCast(@min(body_ids.len, out_entities.len));
        const n = jolt.jolt_overlap_sphere(self.ctx, center[0], center[1], center[2], radius, &body_ids, max_hits);

        var count: usize = 0;
        for (body_ids[0..@intCast(n)]) |body_id| {
            const entity = self.entityForBody(body_id) orelse continue;
            out_entities[count] = entity;
            count += 1;
        }
        return count;
    }

    pub fn applyImpulse(self: *PhysicsWorld, body_id: u32, impulse: @Vector(3, f32)) void {
        jolt.jolt_apply_impulse(self.ctx, body_id, impulse[0], impulse[1], impulse[2]);
    }
};

/// Creates a box body in Jolt, attaches PhysicsBodyComponent, and registers
/// the body<->entity mapping raycasts/triggers rely on to resolve hits back
/// to an entity.
pub fn spawnBoxBody(
    registry: *Registry,
    world: *PhysicsWorld,
    entity: Entity,
    half_extents: @Vector(3, f32),
    mass: f32,
    position: @Vector(3, f32),
    layer: layers.ObjectLayer,
    is_static: bool,
    is_sensor: bool,
) !u32 {
    const body_id = jolt.jolt_add_box(
        world.ctx,
        half_extents[0],
        half_extents[1],
        half_extents[2],
        mass,
        position[0],
        position[1],
        position[2],
        @intFromEnum(layer),
        is_static,
        is_sensor,
    );
    try registry.add(entity, components.PhysicsBodyComponent{ .body_id = body_id, .is_static = is_static });
    try world.registerBody(body_id, entity);
    return body_id;
}

/// Removes a body from Jolt and clears its ECS-side bookkeeping. Does not
/// destroy the entity itself.
pub fn despawnBody(registry: *Registry, world: *PhysicsWorld, entity: Entity) void {
    const body = registry.get(components.PhysicsBodyComponent, entity) orelse return;
    jolt.jolt_remove_body(world.ctx, body.body_id);
    world.unregisterBody(body.body_id);
    registry.remove(components.PhysicsBodyComponent, entity);
}

/// Quaternion (Jolt, xyzw) -> the engine's Euler-angle TransformComponent.rotation.
/// The engine has no Quat type in TransformComponent (see CLAUDE.md's Math
/// section) so physics-driven rotation has to be down-converted here; this
/// loses nothing CharacterVirtual/box bodies need (no continuous spin through
/// a gimbal-locked axis in normal gameplay use) but isn't a general-purpose
/// quat<->euler utility — keep it local to physics sync, not engine/math.zig.
pub fn quatToEuler(x: f32, y: f32, z: f32, w: f32) @Vector(3, f32) {
    const sinr_cosp = 2.0 * (w * x + y * z);
    const cosr_cosp = 1.0 - 2.0 * (x * x + y * y);
    const roll = std.math.atan2(sinr_cosp, cosr_cosp);

    const sinp = 2.0 * (w * y - z * x);
    const pitch = if (@abs(sinp) >= 1.0)
        std.math.copysign(@as(f32, std.math.pi / 2.0), sinp)
    else
        std.math.asin(sinp);

    const siny_cosp = 2.0 * (w * z + x * y);
    const cosy_cosp = 1.0 - 2.0 * (y * y + z * z);
    const yaw = std.math.atan2(siny_cosp, cosy_cosp);

    return .{ roll, pitch, yaw };
}

test "quatToEuler identity is zero" {
    const e = quatToEuler(0, 0, 0, 1);
    try std.testing.expectApproxEqAbs(@as(f32, 0), e[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), e[1], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), e[2], 1e-5);
}
