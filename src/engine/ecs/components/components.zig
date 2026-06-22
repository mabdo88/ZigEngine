const std = @import("std");
const Entity = @import("../entity/entity.zig").Entity;

pub const AllComponents = .{
    MeshComponent,
    TransformComponent,
    WorldTransformComponent,
    CameraComponent,
    TextureComponent,
    SceneComponent,
    SceneActiveTag,
    ScenePendingTag,
    SceneOwnedComponent,
    CameraMatricesComponent,
    TextureDataComponent,
};

pub const MeshComponent = struct {
    /// Vertices slice. If `owns_memory` is true, Registry.destroyEntity frees it.
    vertices: []const Vertex,
    /// Indices slice. If `owns_memory` is true, Registry.destroyEntity frees it.
    indices: []const u32,
    /// When true, the registry frees vertices/indices on destroy. Set this only
    /// when the slices were heap-allocated and the entity should own them.
    owns_memory: bool = false,

    pub fn isValid(self: MeshComponent) bool {
        return self.vertices.len > 0 and self.indices.len > 0;
    }
    pub fn deinit(self: MeshComponent, allocator: std.mem.Allocator) void {
        if (!self.owns_memory) return;
        allocator.free(self.vertices);
        allocator.free(self.indices);
    }
};

pub const Vertex = struct {
    pos: @Vector(3, f32),
    normal: @Vector(3, f32),
    uv: @Vector(2, f32),
};

pub const TransformComponent = struct {
    position: @Vector(3, f32),
    rotation: @Vector(3, f32), // Euler (pitch, yaw, roll) in degrees
    scale: @Vector(3, f32),
};

/// World-space transform as a full 4x4 column-major matrix.
pub const WorldTransformComponent = struct {
    matrix: [4][4]f32,
};

pub const CameraComponent = struct {
    position: @Vector(3, f32) = .{ 0.0, 0.0, 5.0 },
    target: @Vector(3, f32) = .{ 0.0, 0.0, 0.0 },
    up: @Vector(3, f32) = .{ 0.0, 1.0, 0.0 },
    fov: f32 = std.math.degreesToRadians(45.0),
    near: f32 = 0.1,
    far: f32 = 10000.0,
};

/// GPU-side texture handle: the bindless slot index. Written by render_system
/// after it uploads the corresponding TextureDataComponent. Read by the draw
/// path (push constant).
pub const TextureComponent = struct {
    textureIndex: u32, // slot in the bindless heap
};

// ─── Scene components ───────────────────────────────────────────────────────

/// A registered scene. Created up front (one entity per scene). Loaded lazily
/// when tagged with ScenePendingTag.
pub const SceneComponent = struct {
    name: []const u8,
    path: [:0]const u8,
    camera_position: @Vector(3, f32) = .{ 0.0, 0.5, 3.0 },
    camera_target: @Vector(3, f32) = .{ 0.0, 0.5, 0.0 },
    offset: @Vector(3, f32) = .{ 0.0, 0.0, 0.0 },
};

/// Marks the currently loaded scene entity.
pub const SceneActiveTag = struct {};

/// Marks a scene requested to load on the next scene_system pass.
pub const ScenePendingTag = struct {};

/// Tags an entity as belonging to a scene, so unloading destroys exactly the
/// entities that scene spawned.
pub const SceneOwnedComponent = struct {
    owner: Entity,
};

/// Camera matrices computed by camera_system and consumed by render_system.
pub const CameraMatricesComponent = struct {
    view: [4][4]f32,
    proj: [4][4]f32,
};

/// CPU-side texture data written by scene_system and uploaded lazily by
/// render_system. To avoid double-freeing shared material pixels, only the
/// first entity of a given material carries non-empty `pixels`; the rest carry
/// just `material_id` (empty pixels). render_system frees pixels after upload.
pub const TextureDataComponent = struct {
    material_id: u32,
    pixels: []u8 = &.{},
    width: u32 = 0,
    height: u32 = 0,

    pub fn deinit(self: TextureDataComponent, allocator: std.mem.Allocator) void {
        if (self.pixels.len > 0) allocator.free(self.pixels);
    }
};
