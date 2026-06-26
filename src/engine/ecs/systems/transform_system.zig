const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const math = @import("../../math.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;

/// Recomputes FinalTransformComponent = BakedTransformComponent * TransformComponent
/// for every entity with a TransformComponent, every frame. Runs after
/// Movement (which mutates TransformComponent) and before Render (which only
/// reads FinalTransformComponent) — see all_systems.zig for the ordering.
pub fn updateTransforms(registry: *Registry) !void {
    var it = registry.Query(.{components.TransformComponent});
    while (it.next()) |entity| {
        const transform = registry.get(components.TransformComponent, entity).?;
        const local = math.transformToMatrix(transform);
        const world = if (registry.get(components.BakedTransformComponent, entity)) |wt| wt.matrix else math.identityMatrix();
        try registry.set(entity, components.FinalTransformComponent{ .matrix = math.matMul(world, local) });
    }
}

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    _ = ctx;
    _ = dt;
    try updateTransforms(registry);
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    _ = ctx;
    return @as(*anyopaque, @ptrFromInt(1));
}

pub fn destroy(allocator: std.mem.Allocator, registry: *Registry, ctx: *anyopaque) void {
    _ = allocator;
    _ = registry;
    _ = ctx;
}

test "updateTransforms combines world offset and local transform" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const e = try reg.create();
    try reg.add(e, components.BakedTransformComponent{ .matrix = math.identityMatrix() });
    try reg.add(e, components.TransformComponent{
        .position = .{ 1.0, 2.0, 3.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });

    try updateTransforms(&reg);

    const final = reg.get(components.FinalTransformComponent, e).?;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), final.matrix[3][0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), final.matrix[3][1], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), final.matrix[3][2], 1e-5);
}

test "updateTransforms reflects a TransformComponent mutated since the last frame" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const e = try reg.create();
    try reg.add(e, components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });

    try updateTransforms(&reg);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), reg.get(components.FinalTransformComponent, e).?.matrix[3][0], 1e-5);

    const transform = reg.get(components.TransformComponent, e).?;
    transform.position[0] = 5.0;
    try updateTransforms(&reg);

    try std.testing.expectApproxEqAbs(@as(f32, 5.0), reg.get(components.FinalTransformComponent, e).?.matrix[3][0], 1e-5);
}

test "entities without a BakedTransformComponent default to identity world offset" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const e = try reg.create();
    try reg.add(e, components.TransformComponent{
        .position = .{ 7.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });

    try updateTransforms(&reg);
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), reg.get(components.FinalTransformComponent, e).?.matrix[3][0], 1e-5);
}

test "entities without a TransformComponent are skipped" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const e = try reg.create();
    try updateTransforms(&reg);
    try std.testing.expect(reg.get(components.FinalTransformComponent, e) == null);
}
