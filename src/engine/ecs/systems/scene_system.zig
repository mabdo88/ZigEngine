//! CPU-only scene management. Parses glTF into raw vertices/indices/pixels and
//! writes components; never touches Vulkan directly. GPU upload happens lazily
//! in render_system. The only renderer call is `render_system.onSceneUnload()`
//! to reclaim bindless texture slots in a deterministic order.

const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const Entity = @import("../entity/entity.zig").Entity;
const components = @import("../components/components.zig");
const meshLoader = @import("../../../resources/meshLoader.zig");
const render_system = @import("render_system.zig");

pub fn update(registry: *Registry, dt: f32) anyerror!void {
    _ = dt;

    // 1. Find the pending scene; nothing to do if none requested.
    var pending_it = registry.Query(.{ components.SceneComponent, components.ScenePendingTag });
    const pending = pending_it.next() orelse return;
    // Copy by value: the SceneComponent storage is stable across the unload, but
    // copying keeps us safe regardless of storage reshuffles.
    const scene = registry.get(components.SceneComponent, pending).?.*;

    // 2. Unload the active scene (deterministic order).
    try unloadActiveScene(registry);

    // 3. Load the pending scene from CPU.
    try loadScene(registry, pending, scene);

    // 4. Swap tags: pending -> active.
    registry.remove(components.ScenePendingTag, pending);
    try registry.set(pending, components.SceneActiveTag{});
}

/// Deterministic unload: (1) reclaim GPU textures, (2) destroy owned entities
/// (frees GPU meshes via the destroy hook), (3) clear the active tag.
fn unloadActiveScene(registry: *Registry) !void {
    var active_it = registry.Query(.{ components.SceneComponent, components.SceneActiveTag });
    const active = active_it.next() orelse return; // first load: nothing active yet

    // (1) texture cache + bindless slots
    render_system.onSceneUnload();

    // (2) destroy all entities owned by the active scene. Collect first to avoid
    // mutating storage while iterating.
    const allocator = registry.registry_allocator;
    var owned: std.ArrayList(Entity) = .empty;
    defer owned.deinit(allocator);

    var owned_it = registry.Query(.{components.SceneOwnedComponent});
    while (owned_it.next()) |entity| {
        const owned_comp = registry.get(components.SceneOwnedComponent, entity).?;
        if (owned_comp.owner.index == active.index) {
            try owned.append(allocator, entity);
        }
    }
    for (owned.items) |entity| try registry.destroyEntity(entity);

    // (3) clear active tag
    registry.remove(components.SceneActiveTag, active);
}

/// CPU parse + spawn one entity per primitive. Vertices/indices are duped into
/// entity-owned memory (`owns_memory = true`); the loader's copies are freed by
/// `gltf.deinit`. Textures are attached as CPU data for render_system to upload.
fn loadScene(registry: *Registry, scene_entity: Entity, scene: components.SceneComponent) !void {
    const allocator = registry.registry_allocator;

    var gltf = try meshLoader.loadgltf(allocator, scene.path);
    defer gltf.deinit();

    // First entity of each material carries the pixels; the rest reference the
    // material by id only (so pixels are uploaded/freed exactly once).
    const mat_seen = try allocator.alloc(bool, gltf.materials.len);
    defer allocator.free(mat_seen);
    @memset(mat_seen, false);

    for (gltf.primitives) |prim| {
        const entity = try registry.create();

        const mesh = gltf.meshes[prim.mesh_idx];
        const verts = try allocator.dupe(components.Vertex, mesh.vertices);
        const inds = try allocator.dupe(u32, mesh.indices);
        try registry.add(entity, components.MeshComponent{
            .vertices = verts,
            .indices = inds,
            .owns_memory = true,
        });

        // World transform from the glTF node graph, plus a local transform that
        // applies the scene offset (rendered as world * local, matching the demos).
        try registry.add(entity, components.WorldTransformComponent{ .matrix = prim.transform });
        try registry.add(entity, components.TransformComponent{
            .position = scene.offset,
            .rotation = .{ 0.0, 0.0, 0.0 },
            .scale = .{ 1.0, 1.0, 1.0 },
        });

        var td = components.TextureDataComponent{ .material_id = prim.material_idx };
        if (prim.material_idx < gltf.materials.len and !mat_seen[prim.material_idx]) {
            const mat = gltf.materials[prim.material_idx];
            td.pixels = try allocator.dupe(u8, mat.pixels);
            td.width = mat.width;
            td.height = mat.height;
            mat_seen[prim.material_idx] = true;
        }
        try registry.add(entity, td);

        try registry.add(entity, components.SceneOwnedComponent{ .owner = scene_entity });
    }

    // Update the persistent camera for this scene.
    var cam_it = registry.Query(.{components.CameraComponent});
    if (cam_it.next()) |cam| {
        const c = registry.get(components.CameraComponent, cam).?;
        c.position = scene.camera_position;
        c.target = scene.camera_target;
    }

    std.log.info("scene_system: loaded '{s}' ({d} primitives)", .{ scene.name, gltf.primitives.len });
}
