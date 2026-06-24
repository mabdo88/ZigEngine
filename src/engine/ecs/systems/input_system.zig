const std = @import("std");
const flecs = @import("../flecs.zig");
const components = @import("../components/components.zig");
const window = @import("../../../platform/window.zig");
const renderer = @import("../../../renderer/zvulkanSystem.zig");
const SharedContext = @import("system.zig").SharedContext;

pub const Binding = union(enum) {
    key: c_int,
    mouse: c_int,
};

pub const bindings = [_]Binding{
    .{ .key = window.Key.w }, // move_forward
    .{ .key = window.Key.s }, // move_back
    .{ .key = window.Key.a }, // move_left
    .{ .key = window.Key.d }, // move_right
    .{ .key = window.Key.g }, // look_left
    .{ .key = window.Key.semicolon }, // look_right
    .{ .key = window.Key.h }, // skill_1
    .{ .key = window.Key.j }, // skill_2
    .{ .key = window.Key.k }, // skill_3
    .{ .key = window.Key.l }, // skill_4
    .{ .key = window.Key.y }, // skill_5
    .{ .key = window.Key.u }, // skill_6
    .{ .key = window.Key.i }, // skill_7
    .{ .key = window.Key.o }, // skill_8
    .{ .key = window.Key.b }, // skill_9
    .{ .key = window.Key.n }, // skill_10
    .{ .key = window.Key.m }, // skill_11
    .{ .key = window.Key.e }, // interact
    .{ .key = window.Key.one }, // scene_next
    .{ .key = window.Key.two }, // scene_prev
    .{ .mouse = window.MouseButton.left }, // ui_select
    .{ .mouse = window.MouseButton.right }, // ui_context
};

pub fn run(it: [*c]flecs.c.ecs_iter_t) callconv(.c) void {
    const it_ptr: *flecs.c.ecs_iter_t = @ptrCast(it);
    const ctx: *SharedContext = @ptrCast(@alignCast(it_ptr.ctx.?));
    const ids = ctx.component_ids;

    const input = ctx.world.getSingleton(components.InputStateComponent, ids.InputState) orelse return;
    // TODO: windowPtr should live on SharedContext to remove this implicit
    // renderer dependency from the input system.
    const win = renderer.windowPtr();
    const now = window.getTime();

    // Clear just-pressed and just-released from previous frame.
    for (&input.just_pressed) |*jp| jp.* = false;
    for (&input.just_released) |*jr| jr.* = false;

    // Poll each mapped action.
    for (bindings, 0..) |binding, i| {
        const is_held = switch (binding) {
            .key => |k| win.getKey(k),
            .mouse => |b| win.getMouseButton(b),
        };
        const was_held = input.held[i];

        if (is_held and !was_held) {
            // Transition: not held -> held (pressed this frame).
            input.held[i] = true;
            input.just_pressed[i] = true;
            input.press_times[i] = now;
            input.events.push(.{
                .action = @enumFromInt(@as(u8, @intCast(i))),
                .kind = .pressed,
                .held_ms = 0,
            });
        } else if (!is_held and was_held) {
            // Transition: held -> not held (released this frame).
            input.held[i] = false;
            input.just_released[i] = true;
            const held_seconds = now - input.press_times[i];
            const held_ms: u32 = @intFromFloat(held_seconds * 1000.0);
            input.events.push(.{
                .action = @enumFromInt(@as(u8, @intCast(i))),
                .kind = .released,
                .held_ms = held_ms,
            });
        }
    }
}

// --- Tests ---

const testing = std.testing;

test "bindings array matches Action enum order" {
    try testing.expectEqual(components.action_count, bindings.len);

    const expected_keys = [_]c_int{
        window.Key.w, // move_forward
        window.Key.s, // move_back
        window.Key.a, // move_left
        window.Key.d, // move_right
        window.Key.g, // look_left
        window.Key.semicolon, // look_right
        window.Key.h, // skill_1
        window.Key.j, // skill_2
        window.Key.k, // skill_3
        window.Key.l, // skill_4
        window.Key.y, // skill_5
        window.Key.u, // skill_6
        window.Key.i, // skill_7
        window.Key.o, // skill_8
        window.Key.b, // skill_9
        window.Key.n, // skill_10
        window.Key.m, // skill_11
        window.Key.e, // interact
        window.Key.one, // scene_next
        window.Key.two, // scene_prev
    };

    for (expected_keys, 0..) |key, i| {
        const action: components.Action = @enumFromInt(@as(u8, @intCast(i)));
        try testing.expectEqual(key, bindings[i].key);
        // Verify the enum index maps back correctly.
        try testing.expectEqual(@as(u8, @intCast(i)), @intFromEnum(action));
    }

    // Mouse bindings: ui_select (index 20) = left, ui_context (index 21) = right.
    try testing.expectEqual(window.MouseButton.left, bindings[20].mouse);
    try testing.expectEqual(window.MouseButton.right, bindings[21].mouse);
}

test "RingBuffer push and contents" {
    var buf = components.RingBuffer(u32, 4){};

    buf.push(10);
    buf.push(20);
    buf.push(30);

    var out: [4]u32 = undefined;
    const n = buf.contents(&out);
    try testing.expectEqual(@as(usize, 3), n);
    try testing.expectEqual(@as(u32, 10), out[0]);
    try testing.expectEqual(@as(u32, 20), out[1]);
    try testing.expectEqual(@as(u32, 30), out[2]);
}

test "RingBuffer overwrites oldest on overflow" {
    var buf = components.RingBuffer(u32, 3){};

    buf.push(1);
    buf.push(2);
    buf.push(3);
    buf.push(4); // overwrites 1

    var out: [3]u32 = undefined;
    const n = buf.contents(&out);
    try testing.expectEqual(@as(usize, 3), n);
    try testing.expectEqual(@as(u32, 2), out[0]);
    try testing.expectEqual(@as(u32, 3), out[1]);
    try testing.expectEqual(@as(u32, 4), out[2]);
}

test "InputStateComponent defaults are all false/zero" {
    const state = components.InputStateComponent{};
    for (state.held) |h| try testing.expect(!h);
    for (state.just_pressed) |jp| try testing.expect(!jp);
    for (state.just_released) |jr| try testing.expect(!jr);
    try testing.expectEqual(@as(usize, 0), state.events.count);
}

test "InputEvent pressed has zero held_ms" {
    const evt = components.InputEvent{ .action = .move_forward, .kind = .pressed };
    try testing.expectEqual(@as(u32, 0), evt.held_ms);
    try testing.expectEqual(components.Action.move_forward, evt.action);
    try testing.expectEqual(components.EventKind.pressed, evt.kind);
}
