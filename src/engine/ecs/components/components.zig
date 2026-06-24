const std = @import("std");
const flecs = @import("../flecs.zig");

pub const Entity = flecs.Entity;

pub const ComponentIds = struct {
    Mesh: flecs.Entity = 0,
    Transform: flecs.Entity = 0,
    WorldTransform: flecs.Entity = 0,
    Camera: flecs.Entity = 0,
    Texture: flecs.Entity = 0,
    Scene: flecs.Entity = 0,
    SceneActive: flecs.Entity = 0,
    ScenePending: flecs.Entity = 0,
    SceneLoading: flecs.Entity = 0,
    SceneOwned: flecs.Entity = 0,
    CameraMatrices: flecs.Entity = 0,
    TextureData: flecs.Entity = 0,
    InputState: flecs.Entity = 0,
    Root: flecs.Entity = 0,
};

pub fn registerAll(world: *flecs.World) ComponentIds {
    return .{
        .Mesh = world.registerComponent(MeshComponent),
        .Transform = world.registerComponent(TransformComponent),
        .WorldTransform = world.registerComponent(WorldTransformComponent),
        .Camera = world.registerComponent(CameraComponent),
        .Texture = world.registerComponent(TextureComponent),
        .Scene = world.registerComponent(SceneComponent),
        .SceneActive = world.registerTag(SceneActiveTag),
        .ScenePending = world.registerTag(ScenePendingTag),
        .SceneLoading = world.registerTag(SceneLoadingTag),
        .SceneOwned = world.registerComponent(SceneOwnedComponent),
        .CameraMatrices = world.registerComponent(CameraMatricesComponent),
        .TextureData = world.registerComponent(TextureDataComponent),
        .InputState = world.registerComponent(InputStateComponent),
        .Root = world.registerTag(RootTag),
    };
}

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
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
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

pub const RootTag = struct {};

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

pub const Action = enum(u8) {
    move_forward,
    move_back,
    move_left,
    move_right,
    look_left,
    look_right,
    skill_1,
    skill_2,
    skill_3,
    skill_4,
    skill_5,
    skill_6,
    skill_7,
    skill_8,
    skill_9,
    skill_10,
    skill_11,
    interact,
    scene_next,
    scene_prev,
    ui_select,
    ui_context,
};

pub const action_count: usize = @typeInfo(Action).@"enum".fields.len;

pub const EventKind = enum(u8) {
    pressed,
    released,
};

pub const InputEvent = struct {
    action: Action,
    kind: EventKind,
    held_ms: u32 = 0,
};

pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        const Self = @This();

        data: [capacity]T = undefined,
        head: usize = 0,
        tail: usize = 0,
        count: usize = 0,

        pub fn push(self: *Self, value: T) void {
            self.data[self.head] = value;
            self.head = (self.head + 1) % capacity;
            if (self.count < capacity) {
                self.count += 1;
            } else {
                self.tail = (self.tail + 1) % capacity;
            }
        }

        pub fn contents(self: *const Self, buf: []T) usize {
            const n = @min(buf.len, self.count);
            var idx = self.tail;
            for (0..n) |i| {
                buf[i] = self.data[idx];
                idx = (idx + 1) % capacity;
            }
            return n;
        }

        pub fn clear(self: *Self) void {
            self.head = 0;
            self.tail = 0;
            self.count = 0;
        }
    };
}

pub const InputStateComponent = struct {
    held: [action_count]bool = [_]bool{false} ** action_count,
    just_pressed: [action_count]bool = [_]bool{false} ** action_count,
    just_released: [action_count]bool = [_]bool{false} ** action_count,
    events: RingBuffer(InputEvent, 64) = .{},
    press_times: [action_count]f64 = [_]f64{0.0} ** action_count,
};
