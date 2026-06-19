const std = @import("std");
pub const AllComponents = .{ MeshComponent, TransformComponent, CameraComponent, TextureComponent };
pub const MeshComponent = struct {
    vertices: []const Vertex,
    indices: []const u32,

    pub fn isValid(self: MeshComponent) bool {
        return self.vertices.len > 0 and self.indices.len > 0;
    }
    pub fn deinit(self: MeshComponent, allocator: std.mem.Allocator) void {
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
    rotation: @Vector(3, f32), //Quaternion
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
