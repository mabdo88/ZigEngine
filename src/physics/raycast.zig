//! Entity-facing raycast wrappers over jolt_raycast/jolt_raycast_all. Resolves
//! Jolt's body_id results back to entities via PhysicsWorld.body_to_entity —
//! a hit on a body with no matching entity (shouldn't happen since every body
//! is created through physics_world.spawnBoxBody, which registers the
//! mapping) is silently skipped rather than surfaced as an error.
const std = @import("std");
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const physics_world = @import("physics_world.zig");

pub const RaycastHit = struct {
    entity: Entity,
    point: @Vector(3, f32),
    normal: @Vector(3, f32),
    fraction: f32,
};

/// Closest-hit cast. dir need not be normalized length 1 — max_dist scales it
/// (jolt_raycast multiplies dir by max_dist on the C++ side), but passing a
/// normalized direction makes max_dist read as an actual world-space distance.
pub fn raycast(world: *physics_world.PhysicsWorld, origin: @Vector(3, f32), dir: @Vector(3, f32), max_dist: f32) ?RaycastHit {
    var hit: physics_world.jolt.JoltRayHit = undefined;
    const found = physics_world.jolt.jolt_raycast(
        world.ctx,
        origin[0], origin[1], origin[2],
        dir[0], dir[1], dir[2],
        max_dist,
        &hit,
    );
    if (!found) return null;

    const entity = world.entityForBody(hit.body_id) orelse return null;
    return .{
        .entity = entity,
        .point = .{ hit.point[0], hit.point[1], hit.point[2] },
        .normal = .{ hit.normal[0], hit.normal[1], hit.normal[2] },
        .fraction = hit.fraction,
    };
}

/// Multi-hit cast. Writes resolved hits into out_hits (sized by the caller)
/// and returns the count actually written — may be fewer than Jolt found if
/// some hit bodies have no entity mapping.
pub fn raycastAll(world: *physics_world.PhysicsWorld, origin: @Vector(3, f32), dir: @Vector(3, f32), max_dist: f32, out_hits: []RaycastHit) usize {
    var raw: [64]physics_world.jolt.JoltRayHit = undefined;
    const max_raw = @min(raw.len, out_hits.len);
    const n = physics_world.jolt.jolt_raycast_all(
        world.ctx,
        origin[0], origin[1], origin[2],
        dir[0], dir[1], dir[2],
        max_dist,
        &raw,
        @intCast(max_raw),
    );

    var written: usize = 0;
    for (raw[0..@intCast(n)]) |hit| {
        const entity = world.entityForBody(hit.body_id) orelse continue;
        out_hits[written] = .{
            .entity = entity,
            .point = .{ hit.point[0], hit.point[1], hit.point[2] },
            .normal = .{ hit.normal[0], hit.normal[1], hit.normal[2] },
            .fraction = hit.fraction,
        };
        written += 1;
    }
    return written;
}
