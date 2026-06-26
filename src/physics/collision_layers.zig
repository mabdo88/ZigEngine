//! Object layers and the pair-collision matrix. The matrix itself is enforced on the C++
//! side (jolt_wrapper.cpp's makeObjectLayerPairFilter, built from Jolt's
//! ObjectLayerPairFilterTable) — this file is the Zig-facing mirror of that fixed layout,
//! kept in sync by hand since the two sides can't share a single source of truth across
//! the language boundary.

/// Must match JOLT_LAYER_* in jolt_wrapper.h exactly (same order, same count).
pub const ObjectLayer = enum(u8) {
    static = 0,
    player = 1,
    enemy = 2,
    projectile = 3,
    trigger = 4,
};

pub const layer_count = 5;

/// Collision matrix (symmetric). A 1 means the pair generates contacts/overlaps.
///
/// |            | static | player | enemy | projectile | trigger |
/// |------------|--------|--------|-------|------------|---------|
/// | static     |   -    |   x    |   x   |     x      |         |
/// | player     |        |        |   x   |     x      |    x    |
/// | enemy      |        |        |       |     x      |    x    |
/// | projectile |        |        |       |            |    x    |
/// | trigger    |        |        |       |            |         |
///
/// Notes: projectile doesn't collide with itself; trigger (sensor) volumes never fire
/// against static geometry or other triggers, only against the dynamic gameplay layers.
pub const CollisionLayer = struct {
    layer: ObjectLayer,
};
