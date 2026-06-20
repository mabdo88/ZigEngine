const std = @import("std");
const Registry = @import("Storage/registry.zig").Registry;
const Entity = @import("Entity/entity.zig").Entity;
const component = @import("Component/components.zig");
const scomponent = @import("../ecs/Component/SystemComponents.zig");
const systems = @import("System/systems.zig");
const mshLoader = @import("../meshLoader.zig");
const vkctx = @import("../Vulkan/zVulkanContext.zig");

/// Duck spin speed in degrees per second.
const duck_spin_dps: f32 = 60.0;

pub const World = struct {
    entity: Entity = .{},
    camera: Entity = .{},
    duck: Entity = .{},
    registry: Registry = undefined,
    world_allocator: std.mem.Allocator = undefined,
    window: scomponent.WindowComponent = .{ .title = "ZVulkan Window", .width = vkctx.default_window_width, .height = vkctx.default_window_height },
    renderer: scomponent.VulkanContextComponent = .{},
    pub fn init(self: *World, allocator: std.mem.Allocator) !void {
        std.log.info("Initializing World...", .{});
        self.world_allocator = allocator;
        self.registry.init(self.world_allocator);
        self.entity = try self.registry.createEntity();
        std.log.info("Created World Entity: {d}", .{self.entity.index});
        std.log.info("World Created ", .{});
        try self.initVulkan(self.window.title, self.window.width, self.window.height);
        self.camera = try self.registry.createEntity();
        try self.registry.attach(self.camera, component.CameraComponent{});
        self.duck = try self.registry.createEntity();
        const gltfResult = try mshLoader.loadgltf(self.world_allocator, "assets/duck/scene.gltf");
        const textureIndex = try systems.renderer.uploadTexture(gltfResult.pixels, gltfResult.width, gltfResult.height);
        self.world_allocator.free(gltfResult.pixels);
        try self.registry.attach(self.duck, gltfResult.mesh);
        try self.registry.attach(self.duck, component.TransformComponent{
            .position = .{ 0.0, -100.0, -550.0 },
            .rotation = .{ 0.0, -120.0, 0.0 },
            .scale = .{ 1.0, 1.0, 1.0 },
        });
        try self.registry.attach(self.duck, component.TextureComponent{ .textureIndex = textureIndex });
    }
    pub fn deinit(self: *World) void {
        systems.renderer.deinit();
        // Teardown can't propagate errors; an invalid index here is a bug, so log it.
        self.registry.destroyEntity(self.camera) catch |err| std.log.err("destroyEntity(camera) failed: {s}", .{@errorName(err)});
        self.registry.destroyEntity(self.duck) catch |err| std.log.err("destroyEntity(duck) failed: {s}", .{@errorName(err)});
        self.registry.destroyEntity(self.entity) catch |err| std.log.err("destroyEntity(entity) failed: {s}", .{@errorName(err)});
        std.log.info("World Destroyed", .{});
        std.log.info("Engine running with {d} entities before shutdown", .{self.registry.aliveCount()});
        self.registry.deinit();
        self.world_allocator = undefined;
    }
    pub fn initVulkan(self: *World, t: ?[:0]const u8, w: u16, h: u16) !void {
        _ = try systems.renderer.init(self.world_allocator, t, w, h, &self.registry);
    }
    pub fn run(self: *World) !void {
        std.log.info("World running with {d} entities", .{self.registry.aliveCount()});
        var last_time = vkctx.zvk.vkGetTime();
        while (!systems.renderer.shouldClose()) {
            systems.renderer.pollEvents();
            const now = vkctx.zvk.vkGetTime();
            const dt: f32 = @floatCast(now - last_time);
            last_time = now;
            self.spinDuck(dt);
            const matrices = systems.camera.update(&self.registry, systems.renderer.aspectRatio());
            try systems.renderer.render(matrices.?);
        }
    }
    fn spinDuck(self: *World, dt: f32) void {
        if (self.registry.get(component.TransformComponent, self.duck.index)) |transform| {
            transform.rotation[1] = @mod(transform.rotation[1] + duck_spin_dps * dt, 360.0);
        }
    }
};
