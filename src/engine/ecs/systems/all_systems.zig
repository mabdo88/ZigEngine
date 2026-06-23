const SystemDesc = @import("system.zig").SystemDesc;

const input_system = @import("input_system.zig");
const scene_system = @import("scene_system.zig");
const movement_system = @import("movement_system.zig");
const camera_system = @import("camera_system.zig");
const render_system = @import("render_system.zig");

pub const all_systems = [_]SystemDesc{
    .{ .name = "Input", .priority = -100, .create_fn = input_system.create, .update_fn = input_system.update, .destroy_fn = input_system.destroy },
    .{ .name = "Scene", .priority = 0, .create_fn = scene_system.create, .update_fn = scene_system.update, .destroy_fn = scene_system.destroy },
    .{ .name = "Movement", .priority = 1, .create_fn = movement_system.create, .update_fn = movement_system.update, .destroy_fn = movement_system.destroy },
    .{ .name = "Camera", .priority = 2, .create_fn = camera_system.create, .update_fn = camera_system.update, .destroy_fn = camera_system.destroy },
    .{ .name = "Render", .priority = 100, .create_fn = render_system.create, .update_fn = render_system.update, .destroy_fn = render_system.destroy },
};
