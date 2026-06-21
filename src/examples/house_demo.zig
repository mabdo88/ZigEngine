//! House demo: loads a multi-primitive glTF house scene
const std = @import("std");
const World = @import("../engine/world.zig").World;
const Entity = @import("../engine/entity.zig").Entity;
const component = @import("../components/components.zig");

// TODO: Resolve asset paths relative to executable directory.
// For now, the engine must be run from the project root directory.
const GLTF_PATH = "assets/House/hillside_retreat__concrete_house_concept/scene.gltf";

pub const HouseDemo = struct {
    camera: Entity = .{},
    /// One entity per primitive — owned by HouseDemo, freed in deinit.
    entities: []Entity = &.{},
    world: *World = undefined,
    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *HouseDemo, world: *World, allocator: std.mem.Allocator) !void {
        std.log.info("Initializing House Demo...", .{});
        self.world = world;
        self.allocator = allocator;
        const registry = world.registryPtr();

        // Create camera
        self.camera = try registry.createEntity();
        try registry.attach(self.camera, component.CameraComponent{});

        // loadScene handles: background thread CPU load, batched GPU upload, ECS population
        self.entities = try world.loadScene(allocator, GLTF_PATH);
    }

    pub fn update(self: *HouseDemo, dt: f32) void {
        _ = self;
        _ = dt;
    }

    pub fn deinit(self: *HouseDemo) void {
        const registry = self.world.registryPtr();
        registry.destroyEntity(self.camera) catch |err| std.log.err("destroyEntity(camera) failed: {s}", .{@errorName(err)});
        for (self.entities) |entity| {
            registry.destroyEntity(entity) catch |err| std.log.err("destroyEntity(house prim) failed: {s}", .{@errorName(err)});
        }
        self.allocator.free(self.entities);
    }
};
