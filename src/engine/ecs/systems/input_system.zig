const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const window = @import("../../../platform/window.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;
const shared_state = @import("shared_state.zig");

pub const InputSystemState = struct {
    win: *window.Window,

    pub fn update(self: *InputSystemState, registry: *Registry, dt: f32) anyerror!void {
        _ = dt;
        const target: ?usize = if (self.win.getKey(window.Key.one))
            0
        else if (self.win.getKey(window.Key.two))
            1
        else
            null;

        const scene_index = target orelse return;
        try requestScene(registry, scene_index);
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *InputSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(InputSystemState);
    state.* = .{ .win = shared_state.window_ptr.? };
    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *InputSystemState = @ptrCast(@alignCast(ctx));
    allocator.destroy(state);
}

pub fn requestScene(registry: *Registry, scene_index: usize) !void {
    var it = registry.Query(.{components.SceneComponent});
    var i: usize = 0;
    while (it.next()) |scene_entity| : (i += 1) {
        if (i != scene_index) continue;
        if (registry.get(components.SceneActiveTag, scene_entity) != null) return;
        if (registry.get(components.ScenePendingTag, scene_entity) != null) return;
        try registry.set(scene_entity, components.ScenePendingTag{});
        return;
    }
}

test "requestScene adds ScenePendingTag to target scene" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const scene1 = try reg.create();
    try reg.add(scene1, components.SceneComponent{ .name = "A", .path = "" });
    const scene2 = try reg.create();
    try reg.add(scene2, components.SceneComponent{ .name = "B", .path = "" });

    try requestScene(&reg, 1);

    try std.testing.expect(reg.get(components.ScenePendingTag, scene2) != null);
    try std.testing.expect(reg.get(components.ScenePendingTag, scene1) == null);
}

test "requestScene skips already-active scene" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const scene1 = try reg.create();
    try reg.add(scene1, components.SceneComponent{ .name = "A", .path = "" });
    try reg.add(scene1, components.SceneActiveTag{});

    try requestScene(&reg, 0);

    // Should NOT have pending tag (already active)
    try std.testing.expect(reg.get(components.ScenePendingTag, scene1) == null);
}

test "requestScene skips already-pending scene" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const scene1 = try reg.create();
    try reg.add(scene1, components.SceneComponent{ .name = "A", .path = "" });
    try reg.add(scene1, components.ScenePendingTag{});

    try requestScene(&reg, 0);

    // Should still have exactly one pending tag (not duplicated, not reset)
    try std.testing.expect(reg.get(components.ScenePendingTag, scene1) != null);
}

test "requestScene ignores out-of-range index" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const scene1 = try reg.create();
    try reg.add(scene1, components.SceneComponent{ .name = "A", .path = "" });

    try requestScene(&reg, 5);

    try std.testing.expect(reg.get(components.ScenePendingTag, scene1) == null);
}
