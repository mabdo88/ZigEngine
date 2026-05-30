const std = @import("std");
pub const AllComponents = .{ MeshComponent, TransformComponent, CameraComponent };
pub const MeshComponent = struct {
    vertices: []const Vertex,
    indices: []const u32,

    pub fn isValid(self: MeshComponent) bool {
        return self.vertices.len > 0 and self.indices.len > 0;
    }
};
pub const Vertex = struct {
    pos: @Vector(3, f32),
    color: @Vector(3, f32),
};
pub const TransformComponent = struct {
    position: @Vector(3, f32),
    rotation: @Vector(4, f32), //Quaternion
    scale: @Vector(3, f32),
};
pub const CameraComponent = struct {
    position: @Vector(3, f32) = .{ 0.0, 0.0, 5.0 },
    target: @Vector(3, f32) = .{ 0.0, 0.0, 0.0 },
    up: @Vector(3, f32) = .{ 0.0, 1.0, 0.0 },
    fov: f32 = std.math.degreesToRadians(45.0),
    near: f32 = 0.1,
    far: f32 = 100.0,
};
