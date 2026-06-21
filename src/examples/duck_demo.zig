//! Duck demo: loads and animates a glTF duck model
const std = @import("std");
const Registry = @import("../ecs/Storage/registry.zig").Registry;
const Entity = @import("../ecs/Entity/entity.zig").Entity;
const component = @import("../ecs/Component/components.zig");
const systems = @import("../ecs/System/systems.zig");
const mshLoader = @import("../meshLoader.zig");
const vkctx = @import("../Vulkan/zVulkanContext.zig");

const duck_spin_dps: f32 = 60.0;

pub const DuckDemo = struct {
    camera: Entity = .{},
    duck: Entity = .{},
    registry: *Registry = undefined,

    /// Initialize the demo scene with camera and duck entities
    pub fn init(self: *DuckDemo, registry: *Registry, allocator: std.mem.Allocator) !void {
        std.log.info("Initializing Duck Demo...", .{});
        self.registry = registry;

        // Create camera
        self.camera = try registry.createEntity();
        try registry.attach(self.camera, component.CameraComponent{});

        // Create duck entity
        self.duck = try registry.createEntity();
        const gltfResult = try mshLoader.loadgltf(allocator, "assets/duck/scene.gltf");
        const textureIndex = try systems.renderer.uploadTexture(gltfResult.pixels, gltfResult.width, gltfResult.height);
        allocator.free(gltfResult.pixels);

        try registry.attach(self.duck, gltfResult.mesh);
        try registry.attach(self.duck, component.TransformComponent{
            .position = .{ 0.0, -100.0, -550.0 },
            .rotation = .{ 0.0, -120.0, 0.0 },
            .scale = .{ 1.0, 1.0, 1.0 },
        });
        try registry.attach(self.duck, component.TextureComponent{ .textureIndex = textureIndex });

        std.log.info("Duck Demo initialized", .{});
    }

    /// Update demo logic (duck spinning animation)
    pub fn update(self: *DuckDemo, dt: f32) void {
        if (self.registry.get(component.TransformComponent, self.duck.index)) |transform| {
            transform.rotation[1] = @mod(transform.rotation[1] + duck_spin_dps * dt, 360.0);
        }
    }

    /// Cleanup demo entities
    pub fn deinit(self: *DuckDemo) void {
        self.registry.destroyEntity(self.camera) catch |err| std.log.err("destroyEntity(camera) failed: {s}", .{@errorName(err)});
        self.registry.destroyEntity(self.duck) catch |err| std.log.err("destroyEntity(duck) failed: {s}", .{@errorName(err)});
    }
};
