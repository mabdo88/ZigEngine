const std = @import("std");
const components = @import("components.zig");

const deg_to_rad: f32 = std.math.pi / 180.0;

pub fn dot(a: components.Vec3, b: components.Vec3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

pub fn cross(a: components.Vec3, b: components.Vec3) components.Vec3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

pub fn normalize(v: components.Vec3) components.Vec3 {
    const len = @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
    if (len == 0) return .{};
    const inv = 1.0 / len;
    return .{ .x = v.x * inv, .y = v.y * inv, .z = v.z * inv };
}

pub fn lookAt(eye: components.Vec3, center: components.Vec3, up: components.Vec3) [4][4]f32 {
    const f = normalize(.{ .x = center.x - eye.x, .y = center.y - eye.y, .z = center.z - eye.z });
    const s = normalize(cross(f, up));
    const u = cross(s, f);
    return .{
        .{ s.x, u.x, -f.x, 0 },
        .{ s.y, u.y, -f.y, 0 },
        .{ s.z, u.z, -f.z, 0 },
        .{ -dot(s, eye), -dot(u, eye), dot(f, eye), 1 },
    };
}

pub fn perspective(fov_deg: f32, aspect: f32, near: f32, far: f32) [4][4]f32 {
    const f = 1.0 / @tan(fov_deg * deg_to_rad * 0.5);
    const range = far - near;
    return .{
        .{ f / aspect, 0, 0, 0 },
        .{ 0, -f, 0, 0 },
        .{ 0, 0, far / range, 1 },
        .{ 0, 0, -(far * near) / range, 0 },
    };
}
