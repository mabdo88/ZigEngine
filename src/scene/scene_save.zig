const std = @import("std");
const Io = std.Io;
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const components = @import("../engine/ecs/components/components.zig");
const fs = @import("../engine/fs.zig");
const prefab = @import("prefab.zig");

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

fn uuidStr(a: std.mem.Allocator, id: @import("../engine/uuid.zig").Uuid) ![]const u8 {
    var buf: [36]u8 = undefined;
    return a.dupe(u8, id.toBuf(&buf));
}

/// Writes the active scene's path/camera plus every UUID-tagged spawn point
/// and prefab instance to `path` as JSON. Static glTF/OBJ scene geometry
/// (anything owned via SceneOwnedComponent) is deliberately not serialized —
/// it's fully reconstructed from `scene_path` by the existing scene-load
/// pipeline on the way back in, so there's nothing to save there.
pub fn saveScene(io: Io, allocator: std.mem.Allocator, registry: *Registry, path: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const preg = prefab.global orelse return error.PrefabRegistryNotInitialized;

    var scene_path: []const u8 = "";
    {
        var it = registry.Query(.{ components.SceneComponent, components.SceneActiveTag });
        if (it.next()) |e| scene_path = registry.get(components.SceneComponent, e).?.path;
    }

    var camera_position: [3]f32 = .{ 0, 0, 0 };
    var camera_target: [3]f32 = .{ 0, 0, 0 };
    {
        var it = registry.Query(.{components.CameraComponent});
        if (it.next()) |e| {
            const c = registry.get(components.CameraComponent, e).?;
            camera_position = .{ c.position[0], c.position[1], c.position[2] };
            camera_target = .{ c.target[0], c.target[1], c.target[2] };
        }
    }

    var spawners: std.ArrayList(SpawnerSave) = .empty;
    {
        var it = registry.Query(.{ components.SpawnPointComponent, components.UuidComponent, components.TransformComponent });
        while (it.next()) |e| {
            const sp = registry.get(components.SpawnPointComponent, e).?;
            const uid = registry.get(components.UuidComponent, e).?;
            const tr = registry.get(components.TransformComponent, e).?;
            const name = preg.nameById(sp.prefab_id) orelse continue;
            try spawners.append(a, .{
                .uuid = try uuidStr(a, uid.id),
                .prefab = name,
                .position = .{ tr.position[0], tr.position[1], tr.position[2] },
                .cooldown = sp.cooldown,
                .max_active = sp.max_active,
                .active_count = sp.active_count,
            });
        }
    }

    var entities: std.ArrayList(EntitySave) = .empty;
    {
        var it = registry.Query(.{ components.PrefabInstanceComponent, components.UuidComponent, components.TransformComponent });
        while (it.next()) |e| {
            if (registry.get(components.SpawnPointComponent, e) != null) continue;

            const pi = registry.get(components.PrefabInstanceComponent, e).?;
            const uid = registry.get(components.UuidComponent, e).?;
            const tr = registry.get(components.TransformComponent, e).?;
            const name = preg.nameById(pi.prefab_id) orelse continue;

            var spawner_uuid: ?[]const u8 = null;
            if (registry.get(components.SpawnedByComponent, e)) |sb| {
                if (registry.get(components.UuidComponent, sb.spawner)) |su| {
                    spawner_uuid = try uuidStr(a, su.id);
                }
            }

            try entities.append(a, .{
                .uuid = try uuidStr(a, uid.id),
                .prefab = name,
                .position = .{ tr.position[0], tr.position[1], tr.position[2] },
                .rotation = .{ tr.rotation[0], tr.rotation[1], tr.rotation[2] },
                .scale = .{ tr.scale[0], tr.scale[1], tr.scale[2] },
                .spawner_uuid = spawner_uuid,
            });
        }
    }

    const save_data = SceneSaveFile{
        .scene_path = scene_path,
        .camera_position = camera_position,
        .camera_target = camera_target,
        .spawners = spawners.items,
        .entities = entities.items,
    };

    const json = try std.json.Stringify.valueAlloc(a, save_data, .{ .whitespace = .indent_2 });
    try fs.writeFile(io, path, json);
}

test "saveScene writes spawn points and prefab instances with resolved prefab names" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var preg = prefab.PrefabRegistry.init(std.testing.allocator);
    defer preg.deinit();
    const goblin_id = try preg.register("goblin", "assets/goblin.glb");
    prefab.global = &preg;
    defer prefab.global = null;

    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const spawner_e = try reg.create();
    const spawner_uuid = @import("../engine/uuid.zig").Uuid.v4(io);
    try reg.add(spawner_e, components.UuidComponent{ .id = spawner_uuid });
    try reg.add(spawner_e, components.TransformComponent{ .position = .{ 1, 2, 3 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(spawner_e, components.SpawnPointComponent{ .prefab_id = goblin_id, .cooldown = 2.0, .max_active = 3, .active_count = 1 });

    const instance_e = try reg.create();
    try reg.add(instance_e, components.UuidComponent{ .id = @import("../engine/uuid.zig").Uuid.v4(io) });
    try reg.add(instance_e, components.PrefabInstanceComponent{ .prefab_id = goblin_id });
    try reg.add(instance_e, components.TransformComponent{ .position = .{ 4, 5, 6 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(instance_e, components.SpawnedByComponent{ .spawner = spawner_e });

    const path = "scene_save_test_tmp.json";
    try saveScene(io, std.testing.allocator, &reg, path);
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    const text = try fs.readFileAlloc(io, std.testing.allocator, path);
    defer std.testing.allocator.free(text);

    const parsed = try std.json.parseFromSlice(SceneSaveFile, std.testing.allocator, text, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 1), parsed.value.spawners.len);
    try std.testing.expectEqualStrings("goblin", parsed.value.spawners[0].prefab);
    try std.testing.expectEqual(@as(f32, 1.0), parsed.value.spawners[0].position[0]);

    try std.testing.expectEqual(@as(usize, 1), parsed.value.entities.len);
    try std.testing.expectEqualStrings("goblin", parsed.value.entities[0].prefab);
    try std.testing.expect(parsed.value.entities[0].spawner_uuid != null);
}
