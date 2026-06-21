const std = @import("std");
pub const AllComponents = .{ MeshComponent, TransformComponent, CameraComponent, TextureComponent };
pub const MeshComponent = struct {
    /// Vertices slice - caller owns this memory and must free it with the same allocator
    /// used to allocate it. If this component is attached to an entity and the entity is
    /// destroyed via Registry.destroyEntity, the deinit function will be called automatically.
    vertices: []const Vertex,
    /// Indices slice - caller owns this memory and must free it with the same allocator
    /// used to allocate it. If this component is attached to an entity and the entity is
    /// destroyed via Registry.destroyEntity, the deinit function will be called automatically.
    indices: []const u32,
    /// If true, Registry.destroyEntity will free vertices and indices with the registry allocator.
    /// Set this to true only when the slices were heap-allocated and the entity should own them.
    /// Shared or stack-allocated data should leave this as false.
    owns_memory: bool = false,

    pub fn isValid(self: MeshComponent) bool {
        return self.vertices.len > 0 and self.indices.len > 0;
    }
    /// Frees the vertices and indices slices using the provided allocator if owns_memory is true.
    /// WARNING: This function takes self by value, not by pointer. If called on a moved value,
    /// the original slices will be lost. This is primarily called automatically by
    /// Registry.destroyEntity when an entity is destroyed.
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
    rotation: @Vector(3, f32), // Euler angles (pitch, yaw, roll) in degrees
    scale: @Vector(3, f32),
};
pub const CameraComponent = struct {
    position: @Vector(3, f32) = .{ 0.0, 0.0, 5.0 },
    target: @Vector(3, f32) = .{ 0.0, 0.0, 0.0 },
    up: @Vector(3, f32) = .{ 0.0, 1.0, 0.0 },
    fov: f32 = std.math.degreesToRadians(45.0),
    near: f32 = 0.1,
    far: f32 = 10000.0,
};
// components.zig
pub const TextureComponent = struct {
    textureIndex: u32, // slot in the bindless heap
};
