const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const Entity = @import("../entity/entity.zig").Entity;
const components = @import("../components/components.zig");
const meshLoader = @import("../../../resources/meshLoader.zig");
const window = @import("../../../platform/window.zig");

pub const PreloadedScene = struct {
    primitives: []meshLoader.ScenePrimitive,
    mesh_ids: []u32,
    texture_indices: []u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *PreloadedScene) void {
        self.allocator.free(self.primitives);
        self.allocator.free(self.mesh_ids);
        self.allocator.free(self.texture_indices);
    }
};

const PendingLoad = struct {
    scene_entity: Entity,
    scene: components.SceneComponent,
    preloaded: *const PreloadedScene,
};

pub const SceneSystemState = struct {
    pending_load: ?PendingLoad = null,
    preloaded: []PreloadedScene = &.{},

    pub fn deinit(self: *SceneSystemState) void {
        self.pending_load = null;
    }

    pub fn update(self: *SceneSystemState, registry: *Registry, dt: f32) anyerror!void {
        _ = dt;
        try self.processPending(registry);
        try self.processLoading(registry);
    }

    fn processPending(self: *SceneSystemState, registry: *Registry) !void {
        var pending_it = registry.Query(.{ components.SceneComponent, components.ScenePendingTag });
        const pending = pending_it.next() orelse return;
        const scene = registry.get(components.SceneComponent, pending).?.*;

        try self.unloadActiveScene(registry);

        self.pending_load = .{
            .scene_entity = pending,
            .scene = scene,
            .preloaded = &self.preloaded[scene.index],
        };

        registry.remove(components.ScenePendingTag, pending);
        try registry.set(pending, components.SceneLoadingTag{});

        std.log.info("scene_system: activating '{s}'", .{scene.name});
    }

    fn processLoading(self: *SceneSystemState, registry: *Registry) !void {
        if (self.pending_load == null) return;
        const pl = self.pending_load.?;
        self.pending_load = null;

        const switch_start = window.getTime();

        try self.spawnSceneEntities(registry, pl.scene_entity, pl.scene, pl.preloaded);

        registry.remove(components.SceneLoadingTag, pl.scene_entity);
        try registry.set(pl.scene_entity, components.SceneActiveTag{});

        const switch_end = window.getTime();
        std.log.info("scene_system: scene '{s}' ready in {d}ms", .{ pl.scene.name, @as(i64, @intFromFloat((switch_end - switch_start) * 1000)) });
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

    fn spawnSceneEntities(self: *SceneSystemState, registry: *Registry, scene_entity: Entity, scene: components.SceneComponent, preloaded: *const PreloadedScene) !void {
        _ = self;

        for (preloaded.primitives) |prim| {
            const entity = try registry.create();

            const mesh_id = preloaded.mesh_ids[prim.mesh_idx];
            try registry.add(entity, components.MeshComponent{ .mesh_id = mesh_id });

            try registry.add(entity, components.WorldTransformComponent{ .matrix = prim.transform });
            try registry.add(entity, components.TransformComponent{
                .position = scene.offset,
                .rotation = .{ 0.0, 0.0, 0.0 },
                .scale = .{ 1.0, 1.0, 1.0 },
            });

            const texture_index = preloaded.texture_indices[prim.material_idx];
            try registry.add(entity, components.TextureComponent{ .textureIndex = texture_index });

            try registry.add(entity, components.SceneOwnedComponent{ .owner = scene_entity });
        }

        var cam_it = registry.Query(.{components.CameraComponent});
        if (cam_it.next()) |cam| {
            const c = registry.get(components.CameraComponent, cam).?;
            c.position = scene.camera_position;
            c.target = scene.camera_target;
        }

        std.log.info("scene_system: spawned '{s}' ({d} primitives)", .{ scene.name, preloaded.primitives.len });
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *SceneSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}
