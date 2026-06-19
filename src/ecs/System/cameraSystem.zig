const std = @import("std");
const registry = @import("../Storage/registry.zig");
const CameraComponent = @import("../Component/components.zig").CameraComponent;

pub const CameraMatrices = struct {
    view: [4][4]f32,
    projection: [4][4]f32,
};

pub fn update(reg: *registry.Registry, aspect: f32) ?CameraMatrices {
    var it = reg.Query(.{CameraComponent});
    while (it.next()) |entity_id| {
        const camera = reg.get(CameraComponent, entity_id).?;
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
