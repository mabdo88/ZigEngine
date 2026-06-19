const std = @import("std");
const Registry = @import("Storage/registry.zig").Registry;
const Entity = @import("Entity/entity.zig").Entity;
const component = @import("Component/components.zig");
const scomponent = @import("../ecs/Component/SystemComponents.zig");
const systems = @import("System/systems.zig");
const mshLoader = @import("../meshLoader.zig");

pub const World = struct {
    entity: Entity = .{},
    camera: Entity = .{},
    duck: Entity = .{},
    registry: Registry = undefined,
    world_allocator: std.mem.Allocator = undefined,
    window: scomponent.WindowComponent = .{ .title = "ZVulkan Window", .width = 800, .height = 600 },
    renderer: scomponent.VulkanContextComponent = .{},
    pub fn init(self: *World, allocator: std.mem.Allocator) !void {
        std.log.info("Initializing World...", .{});
        self.world_allocator = allocator;
        self.registry.init(self.world_allocator);
        self.entity = self.registry.createEntity();
        std.log.info("Created World Entity: {d}", .{self.entity.index});
        std.log.info("World Created ", .{});
        try self.initVulkan(self.window.title, self.window.width, self.window.height);
        self.camera = self.registry.createEntity();
        try self.registry.attach(self.camera, component.CameraComponent{});
        self.duck = self.registry.createEntity();
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
        self.registry.destroyEntity(self.camera);
        self.registry.destroyEntity(self.duck);
        self.registry.destroyEntity(self.entity);
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
        while (!systems.renderer.shouldClose()) {
            systems.renderer.pollEvents();
            const matrices = systems.camera.update(&self.registry);
            try systems.renderer.render(matrices.?);
        }
    }
    //pub fn runTestCode(self: *World) void {}
};
