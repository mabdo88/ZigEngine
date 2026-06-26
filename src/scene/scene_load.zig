const std = @import("std");
const Io = std.Io;
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const components = @import("../engine/ecs/components/components.zig");
const fs = @import("../engine/fs.zig");
const prefab = @import("prefab.zig");
const Uuid = @import("../engine/uuid.zig").Uuid;
const log = @import("../engine/log.zig");

const SpawnerSave = struct {
    uuid: []const u8,
    prefab: []const u8,
    position: [3]f32,
    cooldown: f32,
    max_active: u32,
    active_count: u32,
};

const EntitySave = struct {
    uuid: []const u8,
    prefab: []const u8,
    position: [3]f32,
    rotation: [3]f32,
    scale: [3]f32,
    spawner_uuid: ?[]const u8 = null,
};

const SceneSaveFile = struct {
    scene_path: []const u8,
    camera_position: [3]f32,
    camera_target: [3]f32,
    spawners: []const SpawnerSave,
    entities: []const EntitySave,
};

/// Destroys every existing prefab instance and spawn point so loadScene
/// starts from a clean slate instead of stacking saved entities on top of
/// whatever is currently spawned. Static scene geometry is untouched here —
/// the scene_path activation below goes through the normal
/// unload-then-load path in scene_system.zig.
fn clearDynamicEntities(registry: *Registry) !void {
    const preg = prefab.global orelse return error.PrefabRegistryNotInitialized;
    const allocator = registry.registry_allocator;

    var roots: std.ArrayList(Entity) = .empty;
    defer roots.deinit(allocator);
    var it1 = registry.Query(.{components.PrefabInstanceComponent});
    while (it1.next()) |e| try roots.append(allocator, e);
    for (roots.items) |e| try preg.destroyInstance(registry, e);

    var spawners: std.ArrayList(Entity) = .empty;
    defer spawners.deinit(allocator);
    var it2 = registry.Query(.{components.SpawnPointComponent});
    while (it2.next()) |e| try spawners.append(allocator, e);
    for (spawners.items) |e| try registry.destroyEntity(e);
}

/// Reads a save file written by scene_save.saveScene and restores it: marks
/// the matching configured scene (by path) pending so scene_system.zig's
/// normal preload/activate pipeline reconstructs the static geometry, then
/// re-instantiates every saved spawn point and prefab instance with its
/// original UUID and transform.
pub fn loadScene(io: Io, allocator: std.mem.Allocator, registry: *Registry, path: []const u8) !void {
    const preg = prefab.global orelse return error.PrefabRegistryNotInitialized;

    const text = try fs.readFileAlloc(io, allocator, path);
    defer allocator.free(text);

    const parsed = try std.json.parseFromSlice(SceneSaveFile, allocator, text, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
    defer parsed.deinit();
    const data = parsed.value;

    try clearDynamicEntities(registry);

    {
        var it = registry.Query(.{components.SceneComponent});
        while (it.next()) |e| {
            const sc = registry.get(components.SceneComponent, e).?;
            if (std.mem.eql(u8, sc.path, data.scene_path)) {
                if (registry.get(components.SceneActiveTag, e) == null) {
                    try registry.set(e, components.ScenePendingTag{});
                }
                break;
            }
        }
    }

    {
        var it = registry.Query(.{components.CameraComponent});
        if (it.next()) |e| {
            const c = registry.get(components.CameraComponent, e).?;
            c.position = .{ data.camera_position[0], data.camera_position[1], data.camera_position[2] };
            c.target = .{ data.camera_target[0], data.camera_target[1], data.camera_target[2] };
        }
    }

    var uuid_to_entity = std.StringHashMap(Entity).init(allocator);
    defer uuid_to_entity.deinit();

    for (data.spawners) |sps| {
        const prefab_id = preg.idByName(sps.prefab) orelse {
            log.warn(@src(), "scene_load: unknown prefab '{s}' for spawn point, skipping", .{sps.prefab});
            continue;
        };
        const e = try registry.create();
        try registry.add(e, components.UuidComponent{ .id = try Uuid.parse(sps.uuid) });
        try registry.add(e, components.TransformComponent{
            .position = .{ sps.position[0], sps.position[1], sps.position[2] },
            .rotation = .{ 0, 0, 0 },
            .scale = .{ 1, 1, 1 },
        });
        try registry.add(e, components.SpawnPointComponent{
            .prefab_id = prefab_id,
            .cooldown = sps.cooldown,
            .max_active = sps.max_active,
            .active_count = sps.active_count,
        });
        try uuid_to_entity.put(sps.uuid, e);
    }

    for (data.entities) |es| {
        const prefab_id = preg.idByName(es.prefab) orelse {
            log.warn(@src(), "scene_load: unknown prefab '{s}' for entity, skipping", .{es.prefab});
            continue;
        };
        const transform = components.TransformComponent{
            .position = .{ es.position[0], es.position[1], es.position[2] },
            .rotation = .{ es.rotation[0], es.rotation[1], es.rotation[2] },
            .scale = .{ es.scale[0], es.scale[1], es.scale[2] },
        };
        const e = try preg.instantiate(registry, prefab_id, transform);
        try registry.set(e, components.UuidComponent{ .id = try Uuid.parse(es.uuid) });

        if (es.spawner_uuid) |su| {
            if (uuid_to_entity.get(su)) |spawner_e| {
                try registry.add(e, components.SpawnedByComponent{ .spawner = spawner_e });
            }
        }
    }
}
