const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const Entity = @import("../entity/entity.zig").Entity;
const components = @import("../components/components.zig");
const meshLoader = @import("../../../resources/meshLoader.zig");

pub const SceneSystemState = struct {

    pub fn update(self: *SceneSystemState, registry: *Registry, dt: f32) anyerror!void {
        _ = dt;

        var pending_it = registry.Query(.{ components.SceneComponent, components.ScenePendingTag });
        const pending = pending_it.next() orelse return;
        const scene = registry.get(components.SceneComponent, pending).?.*;

        try self.unloadActiveScene(registry);
        try self.loadScene(registry, pending, scene);

        registry.remove(components.ScenePendingTag, pending);
        try registry.set(pending, components.SceneActiveTag{});
    }

    fn unloadActiveScene(self: *SceneSystemState, registry: *Registry) !void {
        _ = self;
        var active_it = registry.Query(.{ components.SceneComponent, components.SceneActiveTag });
        const active = active_it.next() orelse return;

        registry.events.emit(.{ .scene_unloaded = {} });

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

        registry.remove(components.SceneActiveTag, active);
    }

    fn loadScene(self: *SceneSystemState, registry: *Registry, scene_entity: Entity, scene: components.SceneComponent) !void {
        _ = self;
        const allocator = registry.registry_allocator;

        var gltf = try meshLoader.loadgltf(allocator, scene.path);
        defer gltf.deinit();

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

        var cam_it = registry.Query(.{components.CameraComponent});
        if (cam_it.next()) |cam| {
            const c = registry.get(components.CameraComponent, cam).?;
            c.position = scene.camera_position;
            c.target = scene.camera_target;
        }

        std.log.info("scene_system: loaded '{s}' ({d} primitives)", .{ scene.name, gltf.primitives.len });
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *SceneSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}
