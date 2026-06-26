const SystemDesc = @import("system.zig").SystemDesc;

const input_system = @import("input_system.zig");
const scene_system = @import("scene_system.zig");
const movement_system = @import("movement_system.zig");
const camera_system = @import("camera_system.zig");
const transform_system = @import("transform_system.zig");
const hierarchy_system = @import("hierarchy_system.zig");
const render_system = @import("render_system.zig");

pub const all_systems = [_]SystemDesc{
    .{ .name = "Input", .priority = -100, .create_fn = input_system.create, .update_fn = input_system.update, .destroy_fn = input_system.destroy },
    .{ .name = "Scene", .priority = 0, .create_fn = scene_system.create, .update_fn = scene_system.update, .destroy_fn = scene_system.destroy },
    .{ .name = "Movement", .priority = 1, .create_fn = movement_system.create, .update_fn = movement_system.update, .destroy_fn = movement_system.destroy },
    .{ .name = "Camera", .priority = 2, .create_fn = camera_system.create, .update_fn = camera_system.update, .destroy_fn = camera_system.destroy },
    .{ .name = "Transform", .priority = 50, .create_fn = transform_system.create, .update_fn = transform_system.update, .destroy_fn = transform_system.destroy },
    .{ .name = "Hierarchy", .priority = 60, .create_fn = hierarchy_system.create, .update_fn = hierarchy_system.update, .destroy_fn = hierarchy_system.destroy },
    .{ .name = "Render", .priority = 100, .create_fn = render_system.create, .update_fn = render_system.update, .destroy_fn = render_system.destroy },
};
