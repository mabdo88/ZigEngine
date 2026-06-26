//! Cross-system access to the single Jolt PhysicsWorld instance, mirroring
//! engine/ecs/systems/shared_state.zig's module-level-var pattern. Kept out of
//! shared_state.zig deliberately: shared_state.zig is pulled in by
//! src/ecs_test.zig's GPU-free `test-ecs` build step, which has no include path
//! for jolt_wrapper.h — anything that reaches physics_world.zig's @cImport
//! must stay off that import chain.
const physics_world = @import("physics_world.zig");

/// Owned by physics_sync_system.zig (create/destroy). raycast.zig,
/// character_controller.zig and trigger.zig all read through this rather than
/// owning their own JoltCtx — there's exactly one Jolt PhysicsSystem per World.
pub var world: ?*physics_world.PhysicsWorld = null;
