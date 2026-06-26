const std = @import("std");
const components = @import("ecs/components/components.zig");

pub const CameraMatrices = struct {
    view: [4][4]f32,
    projection: [4][4]f32,
    position: @Vector(3, f32),
};

pub const SceneLight = struct {
    direction: @Vector(3, f32),
    color: @Vector(3, f32),
    ambient: f32,
    shadow_half_extent: f32,
    shadow_distance: f32,
    shadow_near: f32,
    shadow_far: f32,
};

/// Light-space view-projection for a directional light, framing a fixed box around the world origin.
pub fn directionalLightViewProj(light: SceneLight) [4][4]f32 {
    const up: @Vector(3, f32) = if (@abs(light.direction[1]) > 0.99) .{ 0.0, 0.0, 1.0 } else .{ 0.0, 1.0, 0.0 };
    const target: @Vector(3, f32) = .{ 0.0, 0.0, 0.0 };
    const eye = target - light.direction * @as(@Vector(3, f32), @splat(light.shadow_distance));
    const view = lookAt(eye, target, up);
    const proj = orthographicSymmetric(light.shadow_half_extent, light.shadow_near, light.shadow_far);
    return matMul(proj, view);
}

pub fn identityMatrix() [4][4]f32 {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn matMul(a: [4][4]f32, b: [4][4]f32) [4][4]f32 {
    var r: [4][4]f32 = std.mem.zeroes([4][4]f32);
    for (0..4) |row| {
        for (0..4) |col| {
            for (0..4) |k| {
                r[col][row] += a[k][row] * b[col][k];
            }
        }
    }
    return r;
}

pub fn transformToMatrix(transform: *const components.TransformComponent) [4][4]f32 {
    const toRad = std.math.pi / 180.0;
    const pitch = transform.rotation[0] * toRad;
    const yaw = transform.rotation[1] * toRad;
    const roll = transform.rotation[2] * toRad;

    const cx = @cos(pitch);
    const sx = @sin(pitch);
    const cy = @cos(yaw);
    const sy = @sin(yaw);
    const cz = @cos(roll);
    const sz = @sin(roll);

    const sx_s = transform.scale[0];
    const sy_s = transform.scale[1];
    const sz_s = transform.scale[2];

    return [4][4]f32{
        .{ sx_s * (cy * cz), sy_s * (cy * sz), sz_s * (-sy), 0.0 },
        .{ sx_s * (sx * sy * cz - cx * sz), sy_s * (sx * sy * sz + cx * cz), sz_s * (sx * cy), 0.0 },
        .{ sx_s * (cx * sy * cz + sx * sz), sy_s * (cx * sy * sz - sx * cz), sz_s * (cx * cy), 0.0 },
        .{ transform.position[0], transform.position[1], transform.position[2], 1.0 },
    };
}

pub fn lookAt(eye: @Vector(3, f32), target: @Vector(3, f32), up: @Vector(3, f32)) [4][4]f32 {
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

pub fn perspective(fov: f32, near: f32, far: f32, aspect: f32) [4][4]f32 {
    const tanHalfFov = std.math.tan(fov / 2.0);
    return [4][4]f32{
        .{ 1.0 / (aspect * tanHalfFov), 0.0, 0.0, 0.0 },
        .{ 0.0, -1.0 / tanHalfFov, 0.0, 0.0 },
        .{ 0.0, 0.0, far / (near - far), -1.0 },
        .{ 0.0, 0.0, -(far * near) / (far - near), 0.0 },
    };
}

/// Symmetric orthographic projection: x/y in [-half_extent, half_extent], Vulkan depth [0,1], Y-flipped to match perspective().
pub fn orthographicSymmetric(half_extent: f32, near: f32, far: f32) [4][4]f32 {
    return [4][4]f32{
        .{ 1.0 / half_extent, 0.0, 0.0, 0.0 },
        .{ 0.0, -1.0 / half_extent, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0 / (near - far), 0.0 },
        .{ 0.0, 0.0, near / (near - far), 1.0 },
    };
}

pub fn normalize(v: @Vector(3, f32)) @Vector(3, f32) {
    return v / @as(@Vector(3, f32), @splat(@sqrt(@reduce(.Add, v * v))));
}

pub fn cross(a: @Vector(3, f32), b: @Vector(3, f32)) @Vector(3, f32) {
    return @Vector(3, f32){
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

pub fn dot(a: @Vector(3, f32), b: @Vector(3, f32)) f32 {
    return @reduce(.Add, a * b);
}

test "transformToMatrix: identity rotation/scale gives translation-only matrix" {
    const t = components.TransformComponent{
        .position = .{ 1.0, 2.0, 3.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    };
    const m = transformToMatrix(&t);
    const tol = 1e-5;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[0][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[1][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[2][2], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), m[1][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), m[0][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[3][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), m[3][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), m[3][2], tol);
}

test "transformToMatrix: 90-degree yaw maps +X column onto -Z" {
    const t = components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 90.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    };
    const m = transformToMatrix(&t);
    const tol = 1e-5;
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), m[0][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), m[0][2], tol);
}

test "transformToMatrix: scale appears on the diagonal" {
    const t = components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 2.0, 3.0, 4.0 },
    };
    const m = transformToMatrix(&t);
    const tol = 1e-5;
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), m[0][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), m[1][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), m[2][2], tol);
}

test "lookAt produces identity rotation with -eye translation when looking down -Z" {
    const m = lookAt(.{ 0.0, 0.0, 5.0 }, .{ 0.0, 0.0, 0.0 }, .{ 0.0, 1.0, 0.0 });
    const tol = 1e-5;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[0][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[1][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[2][2], tol);
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
    try std.testing.expectApproxEqAbs(aspect, m[1][1] / m[0][0] * -1.0, tol);
}

test "matMul: identity times any matrix equals that matrix" {
    const a = identityMatrix();
    const b: [4][4]f32 = .{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    };
    const r = matMul(a, b);
    const tol = 1e-5;
    for (0..4) |row| {
        for (0..4) |col| {
            try std.testing.expectApproxEqAbs(b[col][row], r[col][row], tol);
        }
    }
}

test "matMul: two matrices compose correctly" {
    const a: [4][4]f32 = .{
        .{ 2, 0, 0, 0 },
        .{ 0, 2, 0, 0 },
        .{ 0, 0, 2, 0 },
        .{ 0, 0, 0, 1 },
    };
    const b: [4][4]f32 = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 5, 6, 7, 1 },
    };
    const r = matMul(a, b);
    const tol = 1e-5;
    // Scale * translate → scaled translation
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), r[0][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), r[1][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), r[2][2], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), r[3][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), r[3][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 14.0), r[3][2], tol);
}

test "normalize: unit vector stays unit" {
    const v: @Vector(3, f32) = .{ 1.0, 0.0, 0.0 };
    const n = normalize(v);
    const tol = 1e-5;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), n[0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), n[1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), n[2], tol);
}

test "normalize: non-unit vector becomes unit" {
    const v: @Vector(3, f32) = .{ 3.0, 4.0, 0.0 };
    const n = normalize(v);
    const tol = 1e-5;
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), n[0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), n[1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), n[2], tol);
}

test "cross: X cross Y equals Z" {
    const x: @Vector(3, f32) = .{ 1.0, 0.0, 0.0 };
    const y: @Vector(3, f32) = .{ 0.0, 1.0, 0.0 };
    const z = cross(x, y);
    const tol = 1e-5;
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), z[0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), z[1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), z[2], tol);
}

test "cross: Y cross X equals -Z" {
    const x: @Vector(3, f32) = .{ 1.0, 0.0, 0.0 };
    const y: @Vector(3, f32) = .{ 0.0, 1.0, 0.0 };
    const z = cross(y, x);
    const tol = 1e-5;
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), z[0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), z[1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), z[2], tol);
}

test "dot: orthogonal vectors give zero" {
    const a: @Vector(3, f32) = .{ 1.0, 0.0, 0.0 };
    const b: @Vector(3, f32) = .{ 0.0, 1.0, 0.0 };
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), dot(a, b), 1e-5);
}

test "dot: parallel vectors give product of magnitudes" {
    const a: @Vector(3, f32) = .{ 2.0, 0.0, 0.0 };
    const b: @Vector(3, f32) = .{ 3.0, 0.0, 0.0 };
    try std.testing.expectApproxEqAbs(@as(f32, 6.0), dot(a, b), 1e-5);
}
