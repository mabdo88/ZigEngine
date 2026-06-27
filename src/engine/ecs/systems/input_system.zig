const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const window = @import("../../../platform/window.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;
const shared_state = @import("shared_state.zig");
const InputState = @import("../../input.zig").InputState;

pub const InputSystemState = struct {
    win: *window.Window,
    input: InputState = .{},

    pub fn update(self: *InputSystemState, registry: *Registry, dt: f32) anyerror!void {
        _ = dt;
        self.input.update(self.win);

        const target: ?usize = if (self.input.justPressed(window.Key.one))
            0
        else if (self.input.justPressed(window.Key.two))
            1
        else
            null;

        if (target) |scene_index| {
            try requestScene(registry, scene_index);
        }

        const fc = &shared_state.fly_cam;
        const rmb = self.win.getMouseButton(window.MouseButton.right);
        const cur = self.win.getCursorPos();

        if (rmb) {
            if (!fc.looking) {
                fc.last_x = cur.x;
                fc.last_y = cur.y;
                fc.looking = true;
                self.win.setCursorMode(.disabled);
            } else {
                const dx: f32 = @floatCast(cur.x - fc.last_x);
                const dy: f32 = @floatCast(cur.y - fc.last_y);
                fc.last_x = cur.x;
                fc.last_y = cur.y;

                const sensitivity: f32 = 0.002;
                fc.yaw -= dx * sensitivity;
                fc.pitch -= dy * sensitivity;

                const max_pitch = std.math.pi / 2.0 - 0.01;
                fc.pitch = std.math.clamp(fc.pitch, -max_pitch, max_pitch);
            }
        } else {
            if (fc.looking) {
                fc.looking = false;
                self.win.setCursorMode(.normal);
            }
        }

        fc.move_forward = 0.0;
        fc.move_right = 0.0;
        if (self.input.isDown(window.Key.w)) fc.move_forward += 1.0;
        if (self.input.isDown(window.Key.s)) fc.move_forward -= 1.0;
        if (self.input.isDown(window.Key.d)) fc.move_right += 1.0;
        if (self.input.isDown(window.Key.a)) fc.move_right -= 1.0;

        shared_state.player_input = .{
            .move_forward = fc.move_forward,
            .move_right = fc.move_right,
            .sprint = self.input.isDown(window.Key.left_shift),
            .jump_pressed = self.input.justPressed(window.Key.space),
        };

        if (self.input.justPressed(window.Key.f5)) shared_state.save_request.quicksave = true;
        if (self.input.justPressed(window.Key.f9)) shared_state.save_request.quickload = true;
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
