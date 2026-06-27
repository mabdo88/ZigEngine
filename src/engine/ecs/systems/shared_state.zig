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

/// Gameplay-side WASD/sprint/jump, populated by input_system.zig each frame
/// from the same raw key polls as FlyCamInput — separate from fly_cam since
/// that struct drives the free-fly debug camera, not a real player entity.
/// movement.zig's PlayerMovementSystem reads this rather than polling the
/// window directly, same decoupling reason FlyCamInput exists.
pub const PlayerInput = struct {
    move_forward: f32 = 0.0,
    move_right: f32 = 0.0,
    sprint: bool = false,
    jump_pressed: bool = false,
};

pub var player_input: PlayerInput = .{};

/// One-shot quicksave/quickload intent, set by input_system.zig on
/// F5/F9 justPressed — same "engine sets intent, gameplay code acts on it"
/// boundary PlayerInput already draws, since input_system.zig (engine/ecs)
/// shouldn't reach into gameplay/save_system.zig's file IO directly.
/// gameplay/save_system.zig's SaveSystem consumes and clears both fields the
/// instant it reads them.
pub const SaveRequest = struct {
    quicksave: bool = false,
    quickload: bool = false,
};

pub var save_request: SaveRequest = .{};
