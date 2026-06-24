const std = @import("std");
const flecs = @import("../flecs.zig");
const components = @import("../components/components.zig");
const math = @import("../../math.zig");
const shared_state = @import("shared_state.zig");
const SharedContext = @import("system.zig").SharedContext;

const move_speed: f32 = 10.0;
const look_speed: f32 = 1.5;

pub fn run(it: [*c]flecs.c.ecs_iter_t) callconv(.c) void {
    const it_ptr: *flecs.c.ecs_iter_t = @ptrCast(it);
    const ctx: *SharedContext = @ptrCast(@alignCast(it_ptr.ctx.?));
    const ids = ctx.component_ids;
    const dt: f32 = it_ptr.delta_time;

    const input = ctx.world.getSingleton(components.InputStateComponent, ids.InputState) orelse return;

    var q = ctx.world.query(&.{ids.Camera});
    defer q.deinit();
    var qit = q.iter();
    if (!qit.next()) return;
    const cam_entity = qit.entity(0);
    const cameras = qit.field(components.CameraComponent, 0);
    const cam = &cameras[0];

    // Apply look left/right as smooth yaw rotation.
    if (input.held[@intFromEnum(components.Action.look_left)]) cam.yaw += look_speed * dt;
    if (input.held[@intFromEnum(components.Action.look_right)]) cam.yaw -= look_speed * dt;

    // Read movement actions.
    var move_forward: f32 = 0.0;
    var move_right: f32 = 0.0;
    var move_up: f32 = 0.0;
    if (input.held[@intFromEnum(components.Action.move_forward)]) move_forward += 1.0;
    if (input.held[@intFromEnum(components.Action.move_back)]) move_forward -= 1.0;
    if (input.held[@intFromEnum(components.Action.move_right)]) move_right += 1.0;
    if (input.held[@intFromEnum(components.Action.move_left)]) move_right -= 1.0;
    // K (skill_3) = up, J (skill_2) = down.
    if (input.held[@intFromEnum(components.Action.skill_3)]) move_up += 1.0;
    if (input.held[@intFromEnum(components.Action.skill_2)]) move_up -= 1.0;

    const forward = @Vector(3, f32){
        @cos(cam.pitch) * @sin(cam.yaw),
        @sin(cam.pitch),
        @cos(cam.pitch) * @cos(cam.yaw),
    };
    const right = math.normalize(math.cross(forward, cam.up));

    var move = forward * @as(@Vector(3, f32), @splat(move_forward));
    move += right * @as(@Vector(3, f32), @splat(move_right));
    move += cam.up * @as(@Vector(3, f32), @splat(move_up));

    const len_sq = @reduce(.Add, move * move);
    if (len_sq > 0.0) {
        move = math.normalize(move) * @as(@Vector(3, f32), @splat(move_speed * dt));
        cam.position += move;
    }

    cam.target = cam.position + forward;

    const view = math.lookAt(cam.position, cam.target, cam.up);
    const aspect = shared_state.aspect_ratio;
    const projection = math.perspective(cam.fov, cam.near, cam.far, aspect);

    ctx.world.set(cam_entity, components.CameraMatricesComponent, ids.CameraMatrices, .{
        .view = view,
        .proj = projection,
    });
}
