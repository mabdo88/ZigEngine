const std = @import("std");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const components = @import("../engine/ecs/components/components.zig");
const event = @import("../engine/ecs/event.zig");
const SystemCreateCtx = @import("../engine/ecs/systems/system.zig").SystemCreateCtx;
const prefab = @import("prefab.zig");

pub const SpawnerSystemState = struct {
    registry: *Registry,
};

/// registry.destroyEntity emits entity_destroyed before it strips
/// components, so SpawnedByComponent/SpawnPointComponent are still readable
/// here — this is what lets active_count self-correct without ever scanning
/// the registry to recount.
fn onEntityDestroyed(ctx: *anyopaque, payload: event.EventPayload) void {
    const state: *SpawnerSystemState = @ptrCast(@alignCast(ctx));
    const dead = payload.entity_destroyed;

    const sb = state.registry.get(components.SpawnedByComponent, dead) orelse return;
    const sp = state.registry.get(components.SpawnPointComponent, sb.spawner) orelse return;
    if (sp.active_count > 0) sp.active_count -= 1;
}

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    _ = ctx;
    const preg = prefab.global orelse return;

    var it = registry.Query(.{ components.SpawnPointComponent, components.TransformComponent });
    while (it.next()) |spawner_e| {
        const sp = registry.get(components.SpawnPointComponent, spawner_e).?;
        if (sp.active_count >= sp.max_active) continue;

        sp.timer += dt;
        if (sp.timer < sp.cooldown) continue;
        sp.timer = 0;

        const tr = registry.get(components.TransformComponent, spawner_e).?.*;
        const instance = try preg.instantiate(registry, sp.prefab_id, tr);
        try registry.add(instance, components.SpawnedByComponent{ .spawner = spawner_e });
        sp.active_count += 1;
    }
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(SpawnerSystemState);
    state.* = .{ .registry = ctx.registry };
    try ctx.registry.events.subscribe(.entity_destroyed, state, onEntityDestroyed);
    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *SpawnerSystemState = @ptrCast(@alignCast(ctx));
    allocator.destroy(state);
}

test "destroying a spawned instance decrements its spawner's active_count" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    var state = SpawnerSystemState{ .registry = &reg };
    try reg.events.subscribe(.entity_destroyed, &state, onEntityDestroyed);

    const spawner_e = try reg.create();
    try reg.add(spawner_e, components.SpawnPointComponent{ .prefab_id = 0, .cooldown = 1.0, .max_active = 2, .active_count = 1 });

    const instance = try reg.create();
    try reg.add(instance, components.SpawnedByComponent{ .spawner = spawner_e });

    try reg.destroyEntity(instance);

    const sp = reg.get(components.SpawnPointComponent, spawner_e).?;
    try std.testing.expectEqual(@as(u32, 0), sp.active_count);
}

test "destroying an entity with no SpawnedByComponent is a no-op for every spawner" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    var state = SpawnerSystemState{ .registry = &reg };
    try reg.events.subscribe(.entity_destroyed, &state, onEntityDestroyed);

    const spawner_e = try reg.create();
    try reg.add(spawner_e, components.SpawnPointComponent{ .prefab_id = 0, .cooldown = 1.0, .max_active = 2, .active_count = 1 });

    const unrelated = try reg.create();
    try reg.destroyEntity(unrelated);

    const sp = reg.get(components.SpawnPointComponent, spawner_e).?;
    try std.testing.expectEqual(@as(u32, 1), sp.active_count);
}

test "active_count never underflows below zero" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    var state = SpawnerSystemState{ .registry = &reg };
    try reg.events.subscribe(.entity_destroyed, &state, onEntityDestroyed);

    const spawner_e = try reg.create();
    try reg.add(spawner_e, components.SpawnPointComponent{ .prefab_id = 0, .cooldown = 1.0, .max_active = 2, .active_count = 0 });

    const instance = try reg.create();
    try reg.add(instance, components.SpawnedByComponent{ .spawner = spawner_e });
    try reg.destroyEntity(instance);

    const sp = reg.get(components.SpawnPointComponent, spawner_e).?;
    try std.testing.expectEqual(@as(u32, 0), sp.active_count);
}
