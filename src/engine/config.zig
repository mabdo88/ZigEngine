const components = @import("ecs/components/components.zig");

pub const Config = struct {
    window_title: [:0]const u8 = "ZVulkan Window",
    window_width: u16 = 800,
    window_height: u16 = 600,
    max_frames_in_flight: u32 = 2,
    max_textures: u32 = 1024,
    enable_validation: bool = true,

    camera: CameraConfig = .{},
    scenes: []const SceneConfig = &default_scenes,

    pub const CameraConfig = struct {
        position: @Vector(3, f32) = .{ 0.0, 0.5, 3.0 },
        target: @Vector(3, f32) = .{ 0.0, 0.5, 0.0 },
        near: f32 = 0.01,
        far: f32 = 1000.0,
    };

    pub const SceneConfig = struct {
        name: []const u8,
        path: [:0]const u8,
        camera_position: @Vector(3, f32),
        camera_target: @Vector(3, f32),
        offset: @Vector(3, f32),
    };
};

pub const default_scenes = [_]Config.SceneConfig{
    .{
        .name = "Duck",
        .path = "assets/duck/scene.gltf",
        .camera_position = .{ 0.0, 0.5, 3.0 },
        .camera_target = .{ 0.0, 0.5, 0.0 },
        .offset = .{ 0.0, -25.0, -100.0 },
    },
    .{
        .name = "House",
        .path = "assets/House/hillside_retreat__concrete_house_concept/scene.gltf",
        .camera_position = .{ 0.0, 0.5, 3.0 },
        .camera_target = .{ 0.0, 0.5, 0.0 },
        .offset = .{ 0.0, -3.0, -40.0 },
    },
};

pub const default = Config{};
