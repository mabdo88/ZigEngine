const std = @import("std");
const Registry = @import("ecs/entity/registry.zig").Registry;
const sysmod = @import("ecs/systems/system.zig");
const System = sysmod.System;
const SystemRunner = sysmod.SystemRunner;
const components = @import("ecs/components/components.zig");
const window = @import("../platform/window.zig");
const config_mod = @import("config.zig");

const input_system = @import("ecs/systems/input_system.zig");
const scene_system = @import("ecs/systems/scene_system.zig");
const camera_system = @import("ecs/systems/camera_system.zig");
const render_system = @import("ecs/systems/render_system.zig");
const movement_system = @import("ecs/systems/movement_system.zig");

const meshLoader = @import("../resources/meshLoader.zig");
const renderer = @import("../renderer/zvulkanSystem.zig");

pub const VulkanWorld = struct {
    registry: Registry,
    system_runner: SystemRunner,
    allocator: std.mem.Allocator,
    last_time: f64,

    render_state: render_system.RenderSystemState,
    input_state: input_system.InputSystemState,
    camera_state: camera_system.CameraSystemState,
    scene_state: scene_system.SceneSystemState,
    movement_state: movement_system.MovementSystemState,

    pub fn init(self: *VulkanWorld, allocator: std.mem.Allocator, config: config_mod.Config) !void {
        self.* = VulkanWorld{
            .registry = Registry.init(allocator),
            .system_runner = SystemRunner.init(allocator),
            .allocator = allocator,
            .last_time = 0,
            .render_state = undefined,
            .input_state = undefined,
            .camera_state = undefined,
            .scene_state = undefined,
            .movement_state = undefined,
        };

        try self.render_state.init(
            allocator,
            &self.registry,
            config.window_title,
            config.window_width,
            config.window_height,
        );

        self.input_state = .{ .win = render_system.RenderSystemState.windowPtr() };
        self.camera_state = .{ .aspect = render_system.RenderSystemState.aspectRatio() };
        self.scene_state = .{};
        self.movement_state = .{};

        try self.registry.events.subscribe(.scene_unloaded, @ptrCast(&self.render_state), render_system.RenderSystemState.onSceneUnloaded);

        const preloaded = try self.preloadScenes(config.scenes);
        self.scene_state.preloaded = preloaded;

        try self.spawnScenes(config.scenes);
        try self.spawnCamera(config.camera);
        try self.registerSystems();

        var scene_it = self.registry.Query(.{components.SceneComponent});
        if (scene_it.next()) |first_scene| {
            try self.registry.set(first_scene, components.ScenePendingTag{});
        }

        self.last_time = window.getTime();
    }

    fn preloadScenes(self: *VulkanWorld, scene_configs: []const config_mod.Config.SceneConfig) ![]scene_system.PreloadedScene {
        const allocator = self.allocator;
        const preloaded = try allocator.alloc(scene_system.PreloadedScene, scene_configs.len);
        errdefer {
            for (preloaded, 0..) |*ps, fi| {
                if (fi < scene_configs.len) ps.deinit();
            }
            allocator.free(preloaded);
        }

        const total_start = window.getTime();

        for (scene_configs, 0..) |sc, i| {
            const scene_start = window.getTime();

            var gltf = try meshLoader.loadgltf(allocator, sc.path);
            defer gltf.deinit();

            const mesh_ids = try allocator.alloc(u32, gltf.meshes.len);
            errdefer allocator.free(mesh_ids);
            for (gltf.meshes, 0..) |mesh, mi| {
                mesh_ids[mi] = try self.registry.mesh_cache.register(mesh.vertices, mesh.indices);
            }

            const texture_indices = try allocator.alloc(u32, gltf.materials.len);
            errdefer allocator.free(texture_indices);

            var batch = try renderer.beginUploadBatch(allocator);
            errdefer batch.cancel();

            for (gltf.materials, 0..) |mat, mi| {
                texture_indices[mi] = try renderer.uploadTextureBatched(&batch, mat.pixels, mat.width, mat.height);
            }

            for (mesh_ids) |mesh_id| {
                const mesh_data = self.registry.mesh_cache.get(mesh_id).?;
                try self.render_state.gpu_system.preloadMeshBatched(&batch, mesh_id, mesh_data);
            }

            const gpu_start = window.getTime();
            try batch.submit();
            const gpu_end = window.getTime();

            const primitives = try allocator.dupe(meshLoader.ScenePrimitive, gltf.primitives);
            errdefer allocator.free(primitives);

            preloaded[i] = .{
                .primitives = primitives,
                .mesh_ids = mesh_ids,
                .texture_indices = texture_indices,
                .allocator = allocator,
            };

            const scene_end = window.getTime();
            std.log.info("preload: '{s}' CPU+GPU {d}ms, GPU submit {d}ms ({d} meshes, {d} textures, {d} primitives)", .{
                sc.name, @as(i64, @intFromFloat((scene_end - scene_start) * 1000)), @as(i64, @intFromFloat((gpu_end - gpu_start) * 1000)), mesh_ids.len, texture_indices.len, primitives.len,
            });
        }

        const total_end = window.getTime();
        std.log.info("preload: total preload time {d}ms", .{@as(i64, @intFromFloat((total_end - total_start) * 1000))});

        return preloaded;
    }

    fn spawnScenes(self: *VulkanWorld, scene_configs: []const config_mod.Config.SceneConfig) !void {
        for (scene_configs, 0..) |sc, i| {
            const entity = try self.registry.create();
            try self.registry.add(entity, components.SceneComponent{
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

    fn spawnCamera(self: *VulkanWorld, cam: config_mod.Config.CameraConfig) !void {
        const camera = try self.registry.create();
        try self.registry.add(camera, components.CameraComponent{
            .position = cam.position,
            .target = cam.target,
            .near = cam.near,
            .far = cam.far,
        });
    }

    fn registerSystems(self: *VulkanWorld) !void {
        const systems = [_]System{
            .{ .name = "Input", .priority = -100, .update_fn = input_system.update, .context = @ptrCast(&self.input_state) },
            .{ .name = "Scene", .priority = 0, .update_fn = scene_system.update, .context = @ptrCast(&self.scene_state) },
            .{ .name = "Movement", .priority = 1, .update_fn = movement_system.update, .context = @ptrCast(&self.movement_state) },
            .{ .name = "Camera", .priority = 2, .update_fn = camera_system.update, .context = @ptrCast(&self.camera_state) },
            .{ .name = "Render", .priority = 100, .update_fn = render_system.update, .context = @ptrCast(&self.render_state) },
        };
        for (systems) |s| try self.system_runner.addSystem(s);
    }

    pub fn update(self: *VulkanWorld, dt: f32) !void {
        window.pollEvents();
        self.camera_state.aspect = render_system.RenderSystemState.aspectRatio();
        try self.system_runner.update(&self.registry, dt);
    }

    pub fn shouldClose(self: *VulkanWorld) bool {
        _ = self;
        return render_system.RenderSystemState.shouldClose();
    }

    pub fn deltaTime(self: *VulkanWorld) f32 {
        const now = window.getTime();
        const dt: f32 = @floatCast(now - self.last_time);
        self.last_time = now;
        return dt;
    }

    pub fn deinit(self: *VulkanWorld) void {
        self.scene_state.deinit();
        for (self.scene_state.preloaded) |*ps| ps.deinit();
        if (self.scene_state.preloaded.len > 0) {
            self.allocator.free(self.scene_state.preloaded);
        }
        self.render_state.deinit(&self.registry);
        self.system_runner.deinit();
        self.registry.deinit();
    }
};
