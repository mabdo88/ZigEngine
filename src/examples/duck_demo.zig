//! Duck demo: loads and animates a glTF duck model
const std = @import("std");
const World = @import("../engine/world.zig").World;
const Entity = @import("../engine/entity.zig").Entity;
const component = @import("../components/components.zig");

// TODO: Resolve asset paths relative to executable directory.
// For now, the engine must be run from the project root directory.
const GLTF_PATH = "assets/duck/scene.gltf";

const duck_spin_dps: f32 = 60.0;

pub const DuckDemo = struct {
    camera: Entity = .{},
    /// One entity per primitive — owned by DuckDemo, freed in deinit.
    duck_entities: []Entity = &.{},
    world: *World = undefined,
    allocator: std.mem.Allocator = undefined,

    /// Initialize the demo scene with camera and duck entities
    pub fn init(self: *DuckDemo, world: *World, allocator: std.mem.Allocator) !void {
        std.log.info("Initializing Duck Demo...", .{});
        self.world = world;
        self.allocator = allocator;
        const registry = world.registryPtr();

        // Create camera
        self.camera = try registry.createEntity();
        try registry.attach(self.camera, component.CameraComponent{
            .position = .{ 0.0, 1.0, 3.0 },
            .target = .{ 0.0, 0.5, 0.0 },
            .near = 0.01,
            .far = 1000.0,
        });

        // loadScene handles: background thread CPU load, batched GPU upload, ECS population
        self.duck_entities = try world.loadScene(allocator, GLTF_PATH);

        // Duck is centimeter-scale — scale it down to meter scale
        for (self.duck_entities) |entity| {
            if (registry.get(component.TransformComponent, entity.index)) |transform| {
                transform.position = .{ 0.0, -0.3, 0.0 };
                transform.scale = .{ 0.01, 0.01, 0.01 };
            }
        }

        std.log.info("Duck Demo initialized with {d} primitive(s)", .{self.duck_entities.len});
    }

    /// Update demo logic (duck spinning animation)
    pub fn update(self: *DuckDemo, dt: f32) void {
        const registry = self.world.registryPtr();
        for (self.duck_entities) |entity| {
            if (registry.get(component.TransformComponent, entity.index)) |transform| {
                transform.rotation[1] = @mod(transform.rotation[1] + duck_spin_dps * dt, 360.0);
            }
        }
    }

    /// Cleanup demo entities
    pub fn deinit(self: *DuckDemo) void {
        const registry = self.world.registryPtr();
        registry.destroyEntity(self.camera) catch |err| std.log.err("destroyEntity(camera) failed: {s}", .{@errorName(err)});
        for (self.duck_entities) |entity| {
            registry.destroyEntity(entity) catch |err| std.log.err("destroyEntity(duck) failed: {s}", .{@errorName(err)});
        }
        self.allocator.free(self.duck_entities);
    }
};
