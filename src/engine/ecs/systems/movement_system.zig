const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;

pub const MovementSystemState = struct {
    pub fn update(self: *MovementSystemState, registry: *Registry, dt: f32) anyerror!void {
        _ = self;
        var active_it = registry.Query(.{ components.SceneComponent, components.SceneActiveTag });
        const active = active_it.next() orelse return;
        const scene = registry.get(components.SceneComponent, active).?;
        if (!scene.rotates) return;

        var it = registry.Query(.{ components.TransformComponent, components.SceneOwnedComponent });
        while (it.next()) |entity| {
            const owned = registry.get(components.SceneOwnedComponent, entity).?;
            if (owned.owner.index != active.index) continue;
            const transform = registry.get(components.TransformComponent, entity).?;
            transform.rotation[1] += 90.0 * dt;
            if (transform.rotation[1] > 360.0) transform.rotation[1] -= 360.0;
        }
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *MovementSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(MovementSystemState);
    state.* = .{};
    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *MovementSystemState = @ptrCast(@alignCast(ctx));
    allocator.destroy(state);
}

test "movement rotates owned entities when scene.rotates is true" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const scene_entity = try reg.create();
    try reg.add(scene_entity, components.SceneComponent{
        .name = "Test",
        .path = "",
        .rotates = true,
    });
    try reg.add(scene_entity, components.SceneActiveTag{});

    const child = try reg.create();
    try reg.add(child, components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    try reg.add(child, components.SceneOwnedComponent{ .owner = scene_entity });

    var state = MovementSystemState{};
    try state.update(&reg, 1.0);

    const transform = reg.get(components.TransformComponent, child).?;
    try std.testing.expectApproxEqAbs(@as(f32, 90.0), transform.rotation[1], 1e-5);
}

test "movement does not rotate when scene.rotates is false" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const scene_entity = try reg.create();
    try reg.add(scene_entity, components.SceneComponent{
        .name = "Static",
        .path = "",
        .rotates = false,
    });
    try reg.add(scene_entity, components.SceneActiveTag{});

    const child = try reg.create();
    try reg.add(child, components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 45.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    try reg.add(child, components.SceneOwnedComponent{ .owner = scene_entity });

    var state = MovementSystemState{};
    try state.update(&reg, 1.0);

    const transform = reg.get(components.TransformComponent, child).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), transform.rotation[1], 1e-5);
}

test "movement only rotates entities owned by active scene" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const active_scene = try reg.create();
    try reg.add(active_scene, components.SceneComponent{
        .name = "Active",
        .path = "",
        .rotates = true,
    });
    try reg.add(active_scene, components.SceneActiveTag{});

    const other_scene = try reg.create();
    try reg.add(other_scene, components.SceneComponent{
        .name = "Other",
        .path = "",
        .rotates = true,
    });

    const active_child = try reg.create();
    try reg.add(active_child, components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    try reg.add(active_child, components.SceneOwnedComponent{ .owner = active_scene });

    const other_child = try reg.create();
    try reg.add(other_child, components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    try reg.add(other_child, components.SceneOwnedComponent{ .owner = other_scene });

    var state = MovementSystemState{};
    try state.update(&reg, 1.0);

    const active_t = reg.get(components.TransformComponent, active_child).?;
    try std.testing.expectApproxEqAbs(@as(f32, 90.0), active_t.rotation[1], 1e-5);

    const other_t = reg.get(components.TransformComponent, other_child).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), other_t.rotation[1], 1e-5);
}

test "movement rotation wraps at 360 degrees" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const scene_entity = try reg.create();
    try reg.add(scene_entity, components.SceneComponent{
        .name = "Wrap",
        .path = "",
        .rotates = true,
    });
    try reg.add(scene_entity, components.SceneActiveTag{});

    const child = try reg.create();
    try reg.add(child, components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 350.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    try reg.add(child, components.SceneOwnedComponent{ .owner = scene_entity });

    var state = MovementSystemState{};
    try state.update(&reg, 1.0); // 350 + 90 = 440 → 440 - 360 = 80

    const transform = reg.get(components.TransformComponent, child).?;
    try std.testing.expectApproxEqAbs(@as(f32, 80.0), transform.rotation[1], 1e-5);
}

test "movement is no-op when no active scene" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const child = try reg.create();
    try reg.add(child, components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 42.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });

    var state = MovementSystemState{};
    try state.update(&reg, 1.0);

    const transform = reg.get(components.TransformComponent, child).?;
    try std.testing.expectApproxEqAbs(@as(f32, 42.0), transform.rotation[1], 1e-5);
}
