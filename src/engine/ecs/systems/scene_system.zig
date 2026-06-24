const std = @import("std");
const flecs = @import("../flecs.zig");
const components = @import("../components/components.zig");
const meshLoader = @import("../../../resources/meshLoader.zig");
const window = @import("../../../platform/window.zig");
const SharedContext = @import("system.zig").SharedContext;
const renderer = @import("../../../renderer/zvulkanSystem.zig");
const render_system = @import("render_system.zig");
const config_mod = @import("../../config.zig");
const MeshCache = @import("../../../resources/meshCache.zig").MeshCache;
const math = @import("../../math.zig");

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
    scene_entity: flecs.Entity,
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

const SavedCamera = struct {
    position: @Vector(3, f32) = .{ 0, 0, 0 },
    target: @Vector(3, f32) = .{ 0, 0, 0 },
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    initialized: bool = false,
};

pub const SceneSystemState = struct {
    pending_load: ?PendingLoad = null,
    preloaded: []PreloadedScene = &.{},
    preload_states: []ScenePreloadState = &.{},
    saved_cameras: []SavedCamera = &.{},
    bg_thread: ?std.Thread = null,
    bg_args: ?BgLoadArgs = null,
    bg_path: ?[:0]u8 = null,
    allocator: std.mem.Allocator = undefined,

    pub fn update(self: *SceneSystemState, ctx: *SharedContext) !void {
        try self.checkSceneSwitch(ctx);
        try self.checkBackgroundPreload(ctx);
        try self.processPending(ctx);
        try self.processLoading(ctx);
    }

    fn checkSceneSwitch(self: *SceneSystemState, ctx: *SharedContext) !void {
        _ = self;
        const ids = ctx.component_ids;
        const input = ctx.world.getSingleton(components.InputStateComponent, ids.InputState) orelse return;

        if (input.just_pressed[@intFromEnum(components.Action.scene_next)]) {
            requestScene(ctx, 0);
        }
        if (input.just_pressed[@intFromEnum(components.Action.scene_prev)]) {
            requestScene(ctx, 1);
        }
    }

    fn checkBackgroundPreload(self: *SceneSystemState, ctx: *SharedContext) !void {
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
                    const mesh_data = ctx.mesh_cache.get(mesh_id).?;
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

    fn processPending(self: *SceneSystemState, ctx: *SharedContext) !void {
        const ids = ctx.component_ids;
        var q = ctx.world.query(&.{ ids.Scene, ids.ScenePending });
        defer q.deinit();
        var it = q.iter();
        if (!it.next()) return;
        const scenes = it.field(components.SceneComponent, 0);
        const scene = scenes[0];
        const pending_entity = it.entity(0);

        if (scene.index < self.preload_states.len and !self.preload_states[scene.index].gpu_uploaded) return;

        try self.unloadActiveScene(ctx);

        self.pending_load = .{
            .scene_entity = pending_entity,
            .scene = scene,
            .preloaded = &self.preloaded[scene.index],
        };

        ctx.world.remove(pending_entity, ids.ScenePending);
        ctx.world.add(pending_entity, ids.SceneLoading);

        std.log.info("scene_system: activating '{s}'", .{scene.name});
    }

    fn processLoading(self: *SceneSystemState, ctx: *SharedContext) !void {
        if (self.pending_load == null) return;
        const pl = self.pending_load.?;
        self.pending_load = null;

        const switch_start = window.getTime();

        try self.spawnSceneEntities(ctx, pl.scene_entity, pl.scene, pl.preloaded);

        ctx.world.remove(pl.scene_entity, ctx.component_ids.SceneLoading);
        ctx.world.add(pl.scene_entity, ctx.component_ids.SceneActive);

        const switch_end = window.getTime();
        std.log.info("scene_system: scene '{s}' ready in {d}ms", .{ pl.scene.name, @as(i64, @intFromFloat((switch_end - switch_start) * 1000)) });
    }

    fn unloadActiveScene(self: *SceneSystemState, ctx: *SharedContext) !void {
        const ids = ctx.component_ids;
        var active_q = ctx.world.query(&.{ ids.Scene, ids.SceneActive });
        defer active_q.deinit();
        var active_it = active_q.iter();
        if (!active_it.next()) return;
        const active_entity = active_it.entity(0);
        const active_scenes = active_it.field(components.SceneComponent, 0);
        const active_scene_index = active_scenes[0].index;

        self.saveCameraState(ctx, active_scene_index);

        const allocator = ctx.allocator;
        var owned: std.ArrayList(flecs.Entity) = .empty;
        defer owned.deinit(allocator);

        var owned_q = ctx.world.query(&.{ids.SceneOwned});
        defer owned_q.deinit();
        var owned_it = owned_q.iter();
        while (owned_it.next()) {
            const owned_arr = owned_it.field(components.SceneOwnedComponent, 0);
            var row: i32 = 0;
            while (row < owned_it.count()) : (row += 1) {
                if (owned_arr[@intCast(row)].owner == active_entity) {
                    try owned.append(allocator, owned_it.entity(row));
                }
            }
        }
        for (owned.items) |entity| ctx.world.deleteEntity(entity);

        ctx.world.remove(active_entity, ids.SceneActive);
    }

    fn saveCameraState(self: *SceneSystemState, ctx: *SharedContext, scene_index: u32) void {
        if (scene_index >= self.saved_cameras.len) return;
        const ids = ctx.component_ids;
        var cam_q = ctx.world.query(&.{ids.Camera});
        defer cam_q.deinit();
        var cam_it = cam_q.iter();
        if (!cam_it.next()) return;
        const cams = cam_it.fieldPtr(components.CameraComponent, 0).?;
        self.saved_cameras[scene_index] = .{
            .position = cams.position,
            .target = cams.target,
            .yaw = cams.yaw,
            .pitch = cams.pitch,
            .initialized = true,
        };
    }

    fn restoreCameraState(self: *SceneSystemState, ctx: *SharedContext, scene: components.SceneComponent) void {
        if (scene.index >= self.saved_cameras.len) return;
        const ids = ctx.component_ids;
        var cam_q = ctx.world.query(&.{ids.Camera});
        defer cam_q.deinit();
        var cam_it = cam_q.iter();
        if (!cam_it.next()) return;
        const cams = cam_it.fieldPtr(components.CameraComponent, 0).?;

        const saved = &self.saved_cameras[scene.index];
        if (saved.initialized) {
            cams.position = saved.position;
            cams.target = saved.target;
            cams.yaw = saved.yaw;
            cams.pitch = saved.pitch;
        } else {
            cams.position = scene.camera_position;
            cams.target = scene.camera_target;
            const dir = math.normalize(cams.target - cams.position);
            cams.yaw = std.math.atan2(dir[0], dir[2]);
            cams.pitch = std.math.asin(std.math.clamp(dir[1], -1.0, 1.0));
            saved.initialized = true;
            saved.position = cams.position;
            saved.target = cams.target;
            saved.yaw = cams.yaw;
            saved.pitch = cams.pitch;
        }
    }

    fn spawnSceneEntities(self: *SceneSystemState, ctx: *SharedContext, scene_entity: flecs.Entity, scene: components.SceneComponent, preloaded: *const PreloadedScene) !void {
        const ids = ctx.component_ids;
        const world = ctx.world;

        for (preloaded.primitives) |prim| {
            const entity = world.newEntity();

            const mesh_id = preloaded.mesh_ids[prim.mesh_idx];
            world.set(entity, components.MeshComponent, ids.Mesh, .{ .mesh_id = mesh_id });

            world.set(entity, components.WorldTransformComponent, ids.WorldTransform, .{ .matrix = prim.transform });
            world.set(entity, components.TransformComponent, ids.Transform, .{
                .position = scene.offset,
                .rotation = .{ 0.0, 0.0, 0.0 },
                .scale = .{ 1.0, 1.0, 1.0 },
            });

            const texture_index = preloaded.texture_indices[prim.material_idx];
            world.set(entity, components.TextureComponent, ids.Texture, .{ .textureIndex = texture_index });

            world.set(entity, components.SceneOwnedComponent, ids.SceneOwned, .{ .owner = scene_entity });
        }

        self.restoreCameraState(ctx, scene);

        std.log.info("scene_system: spawned '{s}' ({d} primitives)", .{ scene.name, preloaded.primitives.len });
    }
};

pub const SceneSystemCtx = struct {
    shared: *SharedContext,
    state: *SceneSystemState,
};

fn requestScene(ctx: *SharedContext, scene_index: u32) void {
    const ids = ctx.component_ids;
    var q = ctx.world.query(&.{ids.Scene});
    defer q.deinit();
    var it = q.iter();
    while (it.next()) {
        const scenes = it.field(components.SceneComponent, 0);
        var row: i32 = 0;
        while (row < it.count()) : (row += 1) {
            if (scenes[@intCast(row)].index == scene_index) {
                const e = it.entity(row);
                if (!ctx.world.has(e, ids.SceneActive) and !ctx.world.has(e, ids.ScenePending)) {
                    ctx.world.add(e, ids.ScenePending);
                }
                return;
            }
        }
    }
}

pub fn run(it: [*c]flecs.c.ecs_iter_t) callconv(.c) void {
    const it_ptr: *flecs.c.ecs_iter_t = @ptrCast(it);
    const sys_ctx: *SceneSystemCtx = @ptrCast(@alignCast(it_ptr.ctx.?));
    sys_ctx.state.update(sys_ctx.shared) catch |err| {
        std.log.err("scene_system: update failed: {}", .{err});
    };
}

pub fn create(ctx: *SharedContext) !*SceneSystemState {
    const allocator = ctx.allocator;
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
    state.saved_cameras = try allocator.alloc(SavedCamera, n);
    for (state.saved_cameras) |*sc| {
        sc.* = .{};
    }

    try preloadSceneSync(state, allocator, ctx, &config.scenes[0], 0);

    try spawnScenes(ctx, config.scenes);
    try spawnCamera(ctx, config.camera);

    const ids = ctx.component_ids;
    var scene_q = ctx.world.query(&.{ids.Scene});
    defer scene_q.deinit();
    var scene_it = scene_q.iter();
    while (scene_it.next()) {
        const scenes = scene_it.field(components.SceneComponent, 0);
        var row: i32 = 0;
        while (row < scene_it.count()) : (row += 1) {
            if (scenes[@intCast(row)].index == 0) {
                ctx.world.add(scene_it.entity(row), ids.ScenePending);
                break;
            }
        }
    }

    if (n > 1) {
        const path_dup = try allocator.dupeZ(u8, config.scenes[1].path);
        state.bg_path = path_dup;
        state.bg_args = .{
            .allocator = allocator,
            .path = path_dup,
            .mesh_cache = ctx.mesh_cache,
            .preload_state = &state.preload_states[1],
        };
        state.bg_thread = try std.Thread.spawn(.{}, bgLoadThread, .{&state.bg_args.?});
    }

    return state;
}

pub fn destroy(ctx: *SharedContext, state: *SceneSystemState) void {
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
    if (state.saved_cameras.len > 0) {
        state.allocator.free(state.saved_cameras);
    }

    if (state.bg_path) |p| {
        state.allocator.free(p);
    }

    ctx.allocator.destroy(state);
}

fn preloadSceneSync(state: *SceneSystemState, allocator: std.mem.Allocator, ctx: *SharedContext, sc: *const config_mod.Config.SceneConfig, index: usize) !void {
    const scene_start = window.getTime();

    var gltf = try meshLoader.loadgltf(allocator, sc.path);
    defer gltf.deinit();

    const mesh_ids = try allocator.alloc(u32, gltf.meshes.len);
    errdefer allocator.free(mesh_ids);
    for (gltf.meshes, 0..) |mesh, mi| {
        mesh_ids[mi] = try ctx.mesh_cache.register(mesh.vertices, mesh.indices);
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
        const mesh_data = ctx.mesh_cache.get(mesh_id).?;
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

fn spawnScenes(ctx: *SharedContext, scene_configs: []const config_mod.Config.SceneConfig) !void {
    const ids = ctx.component_ids;
    for (scene_configs, 0..) |sc, i| {
        const entity = ctx.world.newEntity();
        ctx.world.set(entity, components.SceneComponent, ids.Scene, .{
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

fn spawnCamera(ctx: *SharedContext, cam: config_mod.Config.CameraConfig) !void {
    const entity = ctx.world.newEntity();
    ctx.world.set(entity, components.CameraComponent, ctx.component_ids.Camera, .{
        .position = cam.position,
        .target = cam.target,
        .near = cam.near,
        .far = cam.far,
    });
}
