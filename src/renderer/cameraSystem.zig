const std = @import("std");
const registry = @import("../engine/ecs/entity/registry.zig");
const CameraComponent = @import("../engine/ecs/components/components.zig").CameraComponent;

pub const CameraMatrices = struct {
    view: [4][4]f32,
    projection: [4][4]f32,
};

pub fn update(reg: *registry.Registry, aspect: f32) ?CameraMatrices {
    var it = reg.Query(.{CameraComponent});
    while (it.next()) |entity| {
        const camera = reg.get(CameraComponent, entity).?;
        return CameraMatrices{
            .view = lookAt(camera.position, camera.target, camera.up),
            .projection = perspective(camera.fov, camera.near, camera.far, aspect),
        };
    }
    return null;
}

fn lookAt(eye: @Vector(3, f32), target: @Vector(3, f32), up: @Vector(3, f32)) [4][4]f32 {
    const f = normalize(target - eye);
    const r = normalize(cross(f, up));
    const u = cross(r, f);

    return [4][4]f32{
        .{ r[0], u[0], -f[0], 0.0 },
        .{ r[1], u[1], -f[1], 0.0 },
        .{ r[2], u[2], -f[2], 0.0 },
        .{ -dot(r, eye), -dot(u, eye), dot(f, eye), 1.0 },
    };
}

fn perspective(fov: f32, near: f32, far: f32, aspect: f32) [4][4]f32 {
    const tanHalfFov = std.math.tan(fov / 2.0);
    return [4][4]f32{
        .{ 1.0 / (aspect * tanHalfFov), 0.0, 0.0, 0.0 },
        .{ 0.0, -1.0 / tanHalfFov, 0.0, 0.0 },
        .{ 0.0, 0.0, far / (near - far), -1.0 },
        .{ 0.0, 0.0, -(far * near) / (far - near), 0.0 },
    };
}

fn normalize(v: @Vector(3, f32)) @Vector(3, f32) {
    return v / @as(@Vector(3, f32), @splat(@sqrt(@reduce(.Add, v * v))));
}

fn cross(a: @Vector(3, f32), b: @Vector(3, f32)) @Vector(3, f32) {
    return @Vector(3, f32){
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

fn dot(a: @Vector(3, f32), b: @Vector(3, f32)) f32 {
    return @reduce(.Add, a * b);
}

test "lookAt produces identity rotation with -eye translation when looking down -Z" {
    const m = lookAt(.{ 0.0, 0.0, 5.0 }, .{ 0.0, 0.0, 0.0 }, .{ 0.0, 1.0, 0.0 });
    const tol = 1e-5;
    // Basis is the identity (camera already axis-aligned).
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[0][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[1][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[2][2], tol);
    // Translation row encodes -eye in view space: z = -5.
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), m[3][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), m[3][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, -5.0), m[3][2], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[3][3], tol);
}

test "perspective matches the analytic projection terms" {
    const fov = std.math.degreesToRadians(90.0);
    const near: f32 = 0.5;
    const far: f32 = 100.0;
    const aspect: f32 = 16.0 / 9.0;
    const m = perspective(fov, near, far, aspect);
    const tol = 1e-5;
    const tanHalf = std.math.tan(fov / 2.0);
    try std.testing.expectApproxEqAbs(1.0 / (aspect * tanHalf), m[0][0], tol);
    try std.testing.expectApproxEqAbs(-1.0 / tanHalf, m[1][1], tol);
    try std.testing.expectApproxEqAbs(far / (near - far), m[2][2], tol);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), m[2][3], tol);
    try std.testing.expectApproxEqAbs(-(far * near) / (far - near), m[3][2], tol);
    // Aspect widens X relative to Y by exactly the aspect ratio.
    try std.testing.expectApproxEqAbs(aspect, m[1][1] / m[0][0] * -1.0, tol);
}
