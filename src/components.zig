pub const Vec3 = struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };
pub const Quat = struct { x: f32 = 0, y: f32 = 0, z: f32 = 0, w: f32 = 1 };

pub const TransformComponent = struct {
    position: Vec3 = .{},
    rotation: Quat = .{},
    scale: Vec3 = .{ .x = 1, .y = 1, .z = 1 },
};

pub const CameraComponent = struct {
    position: Vec3 = .{ .x = 0, .y = 0, .z = 3 },
    yaw: f32 = -90.0,
    pitch: f32 = 0.0,
    fov: f32 = 60.0,
    near: f32 = 0.1,
    far: f32 = 1000.0,
    speed: f32 = 5.0,
    sensitivity: f32 = 0.1,
};

pub const FrameState = struct {
    frame_index: u32 = 0,
    delta_t: f32 = 0.0,
    fixed_accumulator: f32 = 0.0,
    interpolation_alpha: f32 = 0.0,
    extent_width: u32 = 0,
    extent_height: u32 = 0,
};

pub const InputState = struct {
    keys: [512]bool = [_]bool{false} ** 512,
};

pub const ViewProjComponent = struct {
    view: [16]f32 = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },
    proj: [16]f32 = .{
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    },
};

pub const MeshComponent = struct {
    vertex_offset: u32 = 0,
    index_offset: u32 = 0,
    index_count: u32 = 0,
};
