const window = @import("../../../platform/window.zig");
const config = @import("../../config.zig");

pub var window_ptr: ?*window.Window = null;
pub var aspect_ratio: f32 = 1.0;
pub var light: config.Config.LightingConfig = .{};

pub const FlyCamInput = struct {
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    last_x: f64 = 0.0,
    last_y: f64 = 0.0,
    looking: bool = false,
    move_forward: f32 = 0.0,
    move_right: f32 = 0.0,
};

pub var fly_cam: FlyCamInput = .{};
