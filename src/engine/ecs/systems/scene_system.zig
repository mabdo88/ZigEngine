const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const Entity = @import("../entity/entity.zig").Entity;
const components = @import("../components/components.zig");
const meshLoader = @import("../../../resources/meshLoader.zig");
const window = @import("../../../platform/window.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;
const renderer = @import("../../../renderer/zvulkanSystem.zig");
const render_system = @import("render_system.zig");
const config_mod = @import("../../config.zig");
const MeshCache = @import("../../../resources/meshCache.zig").MeshCache;
const math = @import("../../math.zig");
const shared_state = @import("shared_state.zig");

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

const ScenePreloadState = struct {
    bg_loaded: std.atomic.Value(bool) = .init(false),
    gpu_uploaded: bool = false,
    gltf: ?meshLoader.GltfScene = null,
    mesh_ids: []u32 = &.{},
};

const BgLoadArgs = struct {
    allocator: std.mem.Allocator,
    path: [:0]const u8,
    mesh_cache: *MeshCache,
    preload_state: *ScenePreloadState,
};

fn bgLoadThread(args: *BgLoadArgs) void {
    var gltf = meshLoader.loadgltf(args.allocator, args.path) catch {
        std.log.err("bgLoad: failed to load '{s}'", .{args.path});
        args.preload_state.bg_loaded.store(true, .release);
        return;
    };

    const mesh_ids = args.allocator.alloc(u32, gltf.meshes.len) catch {
        gltf.deinit();
        args.preload_state.bg_loaded.store(true, .release);
        return;
    };

    for (gltf.meshes, 0..) |mesh, mi| {
        mesh_ids[mi] = args.mesh_cache.register(mesh.vertices, mesh.indices) catch {
            args.allocator.free(mesh_ids);
            gltf.deinit();
            args.preload_state.bg_loaded.store(true, .release);
            return;
        };
    }

    args.preload_state.mesh_ids = mesh_ids;
    args.preload_state.gltf = gltf;
    args.preload_state.bg_loaded.store(true, .release);
}

pub const SceneSystemState = struct {
    pending_load: ?PendingLoad = null,
    preloaded: []PreloadedScene = &.{},
    preload_states: []ScenePreloadState = &.{},
    bg_thread: ?std.Thread = null,
    bg_args: ?BgLoadArgs = null,
    bg_path: ?[:0]u8 = null,
    allocator: std.mem.Allocator = undefined,

    pub fn update(self: *SceneSystemState, registry: *Registry, dt: f32) anyerror!void {
        _ = dt;
        try self.checkBackgroundPreload(registry);
        try self.processPending(registry);
        try self.processLoading(registry);
    }

    fn checkBackgroundPreload(self: *SceneSystemState, registry: *Registry) !void {
        for (self.preload_states, 0..) |*ps, i| {
            if (i == 0) continue;
            if (!ps.bg_loaded.load(.acquire) or ps.gpu_uploaded) continue;

            if (ps.gltf) |*gltf| {
                const gpu = render_system.getGpuSystem();
                const allocator = self.allocator;

                const texture_indices = try allocator.alloc(u32, gltf.materials.len);
                errdefer allocator.free(texture_indices);

                var batch = try renderer.beginUploadBatch(allocator);
                errdefer batch.cancel();

                for (gltf.materials, 0..) |mat, mi| {
                    texture_indices[mi] = try renderer.uploadTextureBatched(&batch, mat.pixels, mat.width, mat.height);
                }

                for (ps.mesh_ids) |mesh_id| {
                    const mesh_data = registry.mesh_cache.get(mesh_id).?;
                    try gpu.preloadMeshBatched(&batch, mesh_id, mesh_data);
                }

                try batch.submit();

                const primitives = try allocator.dupe(meshLoader.ScenePrimitive, gltf.primitives);
                errdefer allocator.free(primitives);

                self.preloaded[i] = .{
                    .primitives = primitives,
                    .mesh_ids = ps.mesh_ids,
                    .texture_indices = texture_indices,
                    .allocator = allocator,
                };

                gltf.deinit();
                ps.gltf = null;
            }

            ps.gpu_uploaded = true;
            if (self.bg_thread) |t| {
                t.join();
                self.bg_thread = null;
            }
            std.log.info("scene_system: background preload complete for scene {d}", .{i});
        }
    }

    fn processPending(self: *SceneSystemState, registry: *Registry) !void {
        var pending_it = registry.Query(.{ components.SceneComponent, components.ScenePendingTag });
        const pending = pending_it.next() orelse return;
        const scene = registry.get(components.SceneComponent, pending).?.*;

        if (scene.index < self.preload_states.len and !self.preload_states[scene.index].gpu_uploaded) return;

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

            const dir = math.normalize(c.target - c.position);
            shared_state.fly_cam.yaw = std.math.atan2(dir[0], dir[2]);
            shared_state.fly_cam.pitch = std.math.asin(std.math.clamp(dir[1], -1.0, 1.0));
        }

        std.log.info("scene_system: spawned '{s}' ({d} primitives)", .{ scene.name, preloaded.primitives.len });
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *SceneSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const allocator = ctx.allocator;
    const registry = ctx.registry;
    const config = ctx.config;

    const state = try allocator.create(SceneSystemState);
    state.* = .{ .allocator = allocator };

    const n = config.scenes.len;
    state.preloaded = try allocator.alloc(PreloadedScene, n);
    for (state.preloaded) |*ps| {
        ps.* = .{ .primitives = &.{}, .mesh_ids = &.{}, .texture_indices = &.{}, .allocator = allocator };
    }
    state.preload_states = try allocator.alloc(ScenePreloadState, n);
    for (state.preload_states) |*ps| {
        ps.* = .{};
    }

    try preloadSceneSync(state, allocator, registry, &config.scenes[0], 0);

    try spawnScenes(registry, config.scenes);
    try spawnCamera(registry, config.camera);

    var scene_it = registry.Query(.{components.SceneComponent});
    if (scene_it.next()) |first_scene| {
        try registry.set(first_scene, components.ScenePendingTag{});
    }

    if (n > 1) {
        const path_dup = try allocator.dupeZ(u8, config.scenes[1].path);
        state.bg_path = path_dup;
        state.bg_args = .{
            .allocator = allocator,
            .path = path_dup,
            .mesh_cache = &registry.mesh_cache,
            .preload_state = &state.preload_states[1],
        };
        state.bg_thread = try std.Thread.spawn(.{}, bgLoadThread, .{&state.bg_args.?});
    }

    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *SceneSystemState = @ptrCast(@alignCast(ctx));

    if (state.bg_thread) |t| {
        t.join();
        state.bg_thread = null;
    }

    for (state.preload_states) |*ps| {
        if (ps.gltf) |*gltf| {
            gltf.deinit();
        }
        if (!ps.gpu_uploaded and ps.mesh_ids.len > 0) {
            state.allocator.free(ps.mesh_ids);
        }
    }
    if (state.preload_states.len > 0) {
        state.allocator.free(state.preload_states);
    }

    for (state.preloaded) |*ps| {
        if (ps.primitives.len > 0) {
            ps.deinit();
        }
    }
    if (state.preloaded.len > 0) {
        state.allocator.free(state.preloaded);
    }

    if (state.bg_path) |p| {
        state.allocator.free(p);
    }

    allocator.destroy(state);
}

fn preloadSceneSync(state: *SceneSystemState, allocator: std.mem.Allocator, registry: *Registry, sc: *const config_mod.Config.SceneConfig, index: usize) !void {
    const scene_start = window.getTime();

    var gltf = try meshLoader.loadgltf(allocator, sc.path);
    defer gltf.deinit();

    const mesh_ids = try allocator.alloc(u32, gltf.meshes.len);
    errdefer allocator.free(mesh_ids);
    for (gltf.meshes, 0..) |mesh, mi| {
        mesh_ids[mi] = try registry.mesh_cache.register(mesh.vertices, mesh.indices);
    }

    const texture_indices = try allocator.alloc(u32, gltf.materials.len);
    errdefer allocator.free(texture_indices);

    var batch = try renderer.beginUploadBatch(allocator);
    errdefer batch.cancel();

    for (gltf.materials, 0..) |mat, mi| {
        texture_indices[mi] = try renderer.uploadTextureBatched(&batch, mat.pixels, mat.width, mat.height);
    }

    const gpu = render_system.getGpuSystem();
    for (mesh_ids) |mesh_id| {
        const mesh_data = registry.mesh_cache.get(mesh_id).?;
        try gpu.preloadMeshBatched(&batch, mesh_id, mesh_data);
    }

    const gpu_start = window.getTime();
    try batch.submit();
    const gpu_end = window.getTime();

    const primitives = try allocator.dupe(meshLoader.ScenePrimitive, gltf.primitives);
    errdefer allocator.free(primitives);

    state.preloaded[index] = .{
        .primitives = primitives,
        .mesh_ids = mesh_ids,
        .texture_indices = texture_indices,
        .allocator = allocator,
    };
    state.preload_states[index].gpu_uploaded = true;

    const scene_end = window.getTime();
    std.log.info("preload: '{s}' CPU+GPU {d}ms, GPU submit {d}ms ({d} meshes, {d} textures, {d} primitives)", .{
        sc.name, @as(i64, @intFromFloat((scene_end - scene_start) * 1000)), @as(i64, @intFromFloat((gpu_end - gpu_start) * 1000)), mesh_ids.len, texture_indices.len, primitives.len,
    });
}

fn spawnScenes(registry: *Registry, scene_configs: []const config_mod.Config.SceneConfig) !void {
    for (scene_configs, 0..) |sc, i| {
        const entity = try registry.create();
        try registry.add(entity, components.SceneComponent{
            .name = sc.name,
            .path = sc.path,
            .index = @intCast(i),
            .camera_position = sc.camera_position,
            .camera_target = sc.camera_target,
            .offset = sc.offset,
            .rotates = sc.rotates,
        });
    }
}

fn spawnCamera(registry: *Registry, cam: config_mod.Config.CameraConfig) !void {
    const camera = try registry.create();
    try registry.add(camera, components.CameraComponent{
        .position = cam.position,
        .target = cam.target,
        .near = cam.near,
        .far = cam.far,
    });
}
