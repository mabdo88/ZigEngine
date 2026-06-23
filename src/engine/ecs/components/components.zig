const std = @import("std");
const Entity = @import("../entity/entity.zig").Entity;

pub fn ComponentBit(comptime T: type) u64 {
    inline for (AllComponents, 0..) |C, i| {
        if (C == T) return @as(u64, 1) << @intCast(i);
    }
    @compileError("Unregistered component type: " ++ @typeName(T));
}

pub fn ComponentIndex(comptime T: type) comptime_int {
    inline for (AllComponents, 0..) |C, i| {
        if (C == T) return i;
    }
    @compileError("Unregistered component type: " ++ @typeName(T));
}

pub const AllComponents = .{
    MeshComponent,
    TransformComponent,
    WorldTransformComponent,
    CameraComponent,
    TextureComponent,
    SceneComponent,
    SceneActiveTag,
    ScenePendingTag,
    SceneLoadingTag,
    SceneOwnedComponent,
    CameraMatricesComponent,
    TextureDataComponent,
};

pub const MeshComponent = struct {
    mesh_id: u32,

    pub fn isValid(_: MeshComponent) bool {
        return true;
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
    index: u32 = 0,
    camera_position: @Vector(3, f32) = .{ 0.0, 0.5, 3.0 },
    camera_target: @Vector(3, f32) = .{ 0.0, 0.5, 0.0 },
    offset: @Vector(3, f32) = .{ 0.0, 0.0, 0.0 },
    rotates: bool = false,
};

pub const SceneActiveTag = struct {};

pub const ScenePendingTag = struct {};

pub const SceneLoadingTag = struct {};

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
