const builtin = @import("builtin");

pub const Config = struct {
    window_title: [:0]const u8 = "ZVulkan Window",
    window_width: u16 = 800,
    window_height: u16 = 600,
    max_frames_in_flight: u32 = 2,
    max_textures: u32 = 1024,
    enable_validation: bool = true,
    vsync: bool = true,
    hot_reload_shaders: bool = builtin.mode == .Debug,

    camera: CameraConfig = .{ .position = .{ 0.0, 1.4, 3.2 }, .target = .{ 0.0, 0.85, 0.0 } },
    lighting: LightingConfig = .{ .color = .{ 0.65, 0.65, 0.6 }, .ambient = 0.08 },
    audio: AudioConfig = .{},
    scenes: []const SceneConfig = &.{
        .{
            .name = "Duck Pond",
            .path = "assets/duck/scene.gltf",
            .camera_position = .{ 0.0, 1.4, 3.2 },
            .camera_target = .{ 0.0, 0.85, 0.0 },
            .offset = .{ 0.0, 0.0, 0.0 },
            .rotates = true,
            .audio_clip_path = "assets/audio/Duck/mac-quack.mp3",
            .audio_min_distance = 0.5,
            .audio_max_distance = 15.0,
        },
    },

    pub const CameraConfig = struct {
        position: @Vector(3, f32) = .{ 0.0, 0.5, 3.0 },
        target: @Vector(3, f32) = .{ 0.0, 0.5, 0.0 },
        near: f32 = 0.01,
        far: f32 = 1000.0,
    };

    pub const LightingConfig = struct {
        direction: @Vector(3, f32) = .{ -0.4, -1.0, -0.3 },
        color: @Vector(3, f32) = .{ 1.0, 1.0, 0.95 },
        ambient: f32 = 0.12,

        // Bounds of the orthographic shadow frustum, centered on the world origin.
        shadow_half_extent: f32 = 20.0,
        shadow_distance: f32 = 40.0,
        shadow_near: f32 = 0.5,
        shadow_far: f32 = 100.0,
    };

    pub const AudioConfig = struct {
        master_volume: f32 = 1.0,
        ui_volume: f32 = 1.0,
        sfx_volume: f32 = 1.0,
        music_volume: f32 = 1.0,
    };

    pub const SceneConfig = struct {
        name: []const u8,
        path: [:0]const u8,
        camera_position: @Vector(3, f32),
        camera_target: @Vector(3, f32),
        offset: @Vector(3, f32),
        rotates: bool = false,

        /// Attached, spatialized, as an AudioSourceComponent on the scene's
        /// first spawned primitive when set — null plays no scene audio.
        audio_clip_path: ?[]const u8 = null,
        audio_min_distance: f32 = 1.0,
        audio_max_distance: f32 = 1000.0,
    };
};

pub const default = Config{};
