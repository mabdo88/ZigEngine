//! VulkanWorld: a concrete World. It only spawns entities with components and
//! registers systems — no scene logic, no rendering logic. Scene logic lives in
//! scene_system; all Vulkan lives behind render_system. To target a different
//! renderer, copy this file and swap the render_system import + init call.

const std = @import("std");
const Registry = @import("ecs/entity/registry.zig").Registry;
const sysmod = @import("ecs/systems/system.zig");
const System = sysmod.System;
const SystemRunner = sysmod.SystemRunner;
const components = @import("ecs/components/components.zig");
const window = @import("../platform/window.zig");
const vkctx = @import("../renderer/zVulkanContext.zig");

const input_system = @import("ecs/systems/input_system.zig");
const scene_system = @import("ecs/systems/scene_system.zig");
const camera_system = @import("ecs/systems/camera_system.zig");
const render_system = @import("ecs/systems/render_system.zig");

pub const VulkanWorld = struct {
    registry: Registry,
    system_runner: SystemRunner,
    allocator: std.mem.Allocator,
    last_time: f64,

    pub fn init(allocator: std.mem.Allocator) !VulkanWorld {
        var self = VulkanWorld{
            .registry = Registry.init(allocator),
            .system_runner = SystemRunner.init(allocator),
            .allocator = allocator,
            .last_time = 0,
        };

        // Initialize Vulkan + GPU (creates the window). No scene/upload happens
        // here — the first scene loads on frame 1 via scene_system.
        try render_system.init(
            allocator,
            &self.registry,
            "ZVulkan Window",
            vkctx.default_window_width,
            vkctx.default_window_height,
        );
        // Hand the window to the input system for key reads.
        input_system.init(render_system.windowPtr());

        try self.spawnScenes();
        try self.spawnCamera();
        try self.registerSystems();

        // Tag the first scene to load on frame 1.
        var scene_it = self.registry.Query(.{components.SceneComponent});
        if (scene_it.next()) |first_scene| {
            try self.registry.set(first_scene, components.ScenePendingTag{});
        }

        self.last_time = window.getTime();
        return self;
    }

    /// Spawn one entity per registered scene (loop over an array — no one-by-one).
    fn spawnScenes(self: *VulkanWorld) !void {
        const scenes = [_]components.SceneComponent{
            .{
                .name = "Duck",
                .path = "assets/duck/scene.gltf",
                .camera_position = .{ 0.0, 0.5, 3.0 },
                .camera_target = .{ 0.0, 0.5, 0.0 },
                .offset = .{ 0.0, -25.0, -100.0 },
            },
            .{
                .name = "House",
                .path = "assets/House/hillside_retreat__concrete_house_concept/scene.gltf",
                .camera_position = .{ 0.0, 0.5, 3.0 },
                .camera_target = .{ 0.0, 0.5, 0.0 },
                .offset = .{ 0.0, -3.0, -40.0 },
            },
        };
        for (scenes) |scene| {
            const entity = try self.registry.create();
            try self.registry.add(entity, scene);
        }
    }

    /// Spawn the single persistent camera entity. Never destroyed on scene swap.
    fn spawnCamera(self: *VulkanWorld) !void {
        const camera = try self.registry.create();
        try self.registry.add(camera, components.CameraComponent{
            .position = .{ 0.0, 0.5, 3.0 },
            .target = .{ 0.0, 0.5, 0.0 },
            .near = 0.01,
            .far = 1000.0,
        });
    }

    /// Register systems (loop over an array). Priority order: Input < Scene < Camera < Render.
    fn registerSystems(self: *VulkanWorld) !void {
        const systems = [_]System{
            .{ .name = "Input", .priority = -100, .update_fn = input_system.update },
            .{ .name = "Scene", .priority = 0, .update_fn = scene_system.update },
            .{ .name = "Camera", .priority = 1, .update_fn = camera_system.update },
            .{ .name = "Render", .priority = 100, .update_fn = render_system.update },
        };
        for (systems) |s| try self.system_runner.addSystem(s);
    }

    pub fn update(self: *VulkanWorld, dt: f32) !void {
        window.pollEvents();
        try self.system_runner.update(&self.registry, dt);
    }

    pub fn shouldClose(self: *VulkanWorld) bool {
        _ = self;
        return render_system.shouldClose();
    }

    pub fn deltaTime(self: *VulkanWorld) f32 {
        const now = window.getTime();
        const dt: f32 = @floatCast(now - self.last_time);
        self.last_time = now;
        return dt;
    }

    pub fn deinit(self: *VulkanWorld) void {
        render_system.deinit(&self.registry);
        self.system_runner.deinit();
        self.registry.deinit();
    }
};
