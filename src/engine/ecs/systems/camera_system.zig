const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const math = @import("../../math.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;
const shared_state = @import("shared_state.zig");

const move_speed: f32 = 10.0;

pub const CameraSystemState = struct {
    aspect: f32 = 1.0,

    pub fn update(self: *CameraSystemState, registry: *Registry, dt: f32) anyerror!void {
        var it = registry.Query(.{components.CameraComponent});
        const cam_entity = it.next() orelse return;
        const camera = registry.get(components.CameraComponent, cam_entity).?;

        if (shared_state.window_ptr != null) {
            const fc = &shared_state.fly_cam;
            const forward = @Vector(3, f32){
                @cos(fc.pitch) * @sin(fc.yaw),
                @sin(fc.pitch),
                @cos(fc.pitch) * @cos(fc.yaw),
            };
            const right = math.normalize(math.cross(forward, camera.up));

            var move = forward * @as(@Vector(3, f32), @splat(fc.move_forward));
            move += right * @as(@Vector(3, f32), @splat(fc.move_right));

            const len_sq = @reduce(.Add, move * move);
            if (len_sq > 0.0) {
                move = math.normalize(move) * @as(@Vector(3, f32), @splat(move_speed * dt));
                camera.position += move;
            }

            camera.target = camera.position + forward;
        }

        const view = math.lookAt(camera.position, camera.target, camera.up);
        const projection = math.perspective(camera.fov, camera.near, camera.far, self.aspect);

        try registry.set(cam_entity, components.CameraMatricesComponent{
            .view = view,
            .proj = projection,
        });
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *CameraSystemState = @ptrCast(@alignCast(ctx));
    state.aspect = shared_state.aspect_ratio;
    try state.update(registry, dt);
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(CameraSystemState);
    state.* = .{ .aspect = shared_state.aspect_ratio };
    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *CameraSystemState = @ptrCast(@alignCast(ctx));
    allocator.destroy(state);
}

test "camera system produces view and projection matrices" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const cam_entity = try reg.create();
    try reg.add(cam_entity, components.CameraComponent{
        .position = .{ 0.0, 0.0, 5.0 },
        .target = .{ 0.0, 0.0, 0.0 },
        .up = .{ 0.0, 1.0, 0.0 },
        .fov = std.math.degreesToRadians(45.0),
        .near = 0.1,
        .far = 100.0,
    });

    var state = CameraSystemState{ .aspect = 16.0 / 9.0 };
    try state.update(&reg, 0.0);

    const matrices = reg.get(components.CameraMatricesComponent, cam_entity).?;
    const tol = 1e-5;

    // View matrix: looking down -Z from (0,0,5) to origin → identity rotation, -5 translation
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), matrices.view[0][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), matrices.view[1][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), matrices.view[2][2], tol);
    try std.testing.expectApproxEqAbs(@as(f32, -5.0), matrices.view[3][2], tol);

    // Projection matrix: perspective terms
    const tan_half = std.math.tan(std.math.degreesToRadians(45.0) / 2.0);
    try std.testing.expectApproxEqAbs(1.0 / ((16.0 / 9.0) * tan_half), matrices.proj[0][0], tol);
    try std.testing.expectApproxEqAbs(-1.0 / tan_half, matrices.proj[1][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), matrices.proj[2][3], tol);
}

test "camera system is no-op when no camera entity exists" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    var state = CameraSystemState{ .aspect = 1.0 };
    try state.update(&reg, 0.0);

    // No crash, no matrices component on any entity
    var it = reg.Query(.{components.CameraMatricesComponent});
    try std.testing.expect(it.next() == null);
}
