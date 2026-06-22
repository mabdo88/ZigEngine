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
    vertices: []const Vertex,
    indices: []const u32,
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
    rotation: @Vector(3, f32),
    scale: @Vector(3, f32),
};

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

pub const TextureComponent = struct {
    textureIndex: u32,
};

pub const SceneComponent = struct {
    name: []const u8,
    path: [:0]const u8,
    camera_position: @Vector(3, f32) = .{ 0.0, 0.5, 3.0 },
    camera_target: @Vector(3, f32) = .{ 0.0, 0.5, 0.0 },
    offset: @Vector(3, f32) = .{ 0.0, 0.0, 0.0 },
};

pub const SceneActiveTag = struct {};

pub const ScenePendingTag = struct {};

pub const SceneOwnedComponent = struct {
    owner: Entity,
};

pub const CameraMatricesComponent = struct {
    view: [4][4]f32,
    proj: [4][4]f32,
};

pub const TextureDataComponent = struct {
    material_id: u32,
    pixels: []u8 = &.{},
    width: u32 = 0,
    height: u32 = 0,

    pub fn deinit(self: TextureDataComponent, allocator: std.mem.Allocator) void {
        if (self.pixels.len > 0) allocator.free(self.pixels);
    }
};
