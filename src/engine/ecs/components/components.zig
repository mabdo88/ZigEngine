const std = @import("std");
const Entity = @import("../entity/entity.zig").Entity;
const clip_mod = @import("../../../animation/clip.zig");

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
    BakedTransformComponent,
    CameraComponent,
    MaterialComponent,
    SceneComponent,
    SceneActiveTag,
    ScenePendingTag,
    SceneLoadingTag,
    SceneOwnedComponent,
    CameraMatricesComponent,
    TextureDataComponent,
    FinalTransformComponent,
    ParentComponent,
    SkeletonComponent,
    AnimPlayerComponent,
    PoseBufferComponent,
    SkinMatricesComponent,
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

pub const BakedTransformComponent = struct {
    matrix: [4][4]f32,
};

/// world = BakedTransformComponent.matrix * transformToMatrix(TransformComponent),
/// recomputed every frame by TransformSystem. Renderers (and any future
/// system) read this instead of redoing the matMul themselves.
pub const FinalTransformComponent = struct {
    matrix: [4][4]f32,
};

/// Presence means this entity's FinalTransformComponent should be
/// concatenated under `parent`'s, by HierarchySystem. Absence means the
/// entity is a root — its FinalTransformComponent is already a world matrix.
pub const ParentComponent = struct {
    parent: Entity,
};

pub const CameraComponent = struct {
    position: @Vector(3, f32) = .{ 0.0, 0.0, 5.0 },
    target: @Vector(3, f32) = .{ 0.0, 0.0, 0.0 },
    up: @Vector(3, f32) = .{ 0.0, 1.0, 0.0 },
    fov: f32 = std.math.degreesToRadians(45.0),
    near: f32 = 0.1,
    far: f32 = 10000.0,
};

pub const MaterialComponent = struct {
    material_index: u32,
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

/// Index into Registry.skeleton_cache — the skeleton itself is asset data
/// shared across instances, not owned per-entity.
pub const SkeletonComponent = struct {
    skeleton_id: u32,
};

/// Index into Registry.clip_cache, plus per-entity playback state.
pub const AnimPlayerComponent = struct {
    clip_id: u32,
    time: f32 = 0,
    speed: f32 = 1.0,
    loop: bool = true,
};

/// Per-entity local joint pose, sampled from the clip each frame by
/// AnimPlayerSystem. Sized to the skeleton's joint_count at spawn time.
pub const PoseBufferComponent = struct {
    poses: []clip_mod.JointPose,

    pub fn deinit(self: PoseBufferComponent, allocator: std.mem.Allocator) void {
        allocator.free(self.poses);
    }
};

/// Per-entity world-space joint transforms, recomputed each frame by
/// AnimPlayerSystem from PoseBufferComponent. Named for its eventual GPU
/// skinning role (skin[i] = world[i] * inverse_bind[i]) — for now it holds
/// plain world transforms, since nothing samples inverse_bind into it yet.
pub const SkinMatricesComponent = struct {
    matrices: [][4][4]f32,

    pub fn deinit(self: SkinMatricesComponent, allocator: std.mem.Allocator) void {
        allocator.free(self.matrices);
    }
};
