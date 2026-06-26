//! Trigger (sensor) volume helpers. The actual event plumbing lives in
//! jolt_wrapper.cpp's TriggerListener (a Jolt ContactListener that queues
//! enter/exit pairs whenever either body in a contact is a registered
//! sensor) and engine/ecs/systems/trigger_system.zig (drains that queue each
//! frame and re-emits through the ECS EventBus as .trigger_event). This file
//! is just the spawn-side convenience wrapper.
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const components = @import("../engine/ecs/components/components.zig");
const physics_world = @import("physics_world.zig");
const layers = @import("collision_layers.zig");

/// Spawns a box-shaped sensor volume. Static (sensors don't need to move to
/// detect overlaps — a moving sensor works too, but the common case, e.g. a
/// doorway trigger, doesn't need a dynamic body underneath it).
pub fn spawnBoxTrigger(
    registry: *Registry,
    world: *physics_world.PhysicsWorld,
    entity: Entity,
    half_extents: @Vector(3, f32),
    position: @Vector(3, f32),
) !void {
    _ = try physics_world.spawnBoxBody(registry, world, entity, half_extents, 0, position, layers.ObjectLayer.trigger, true, true);
    try registry.add(entity, components.TriggerWatcherComponent{});
}
