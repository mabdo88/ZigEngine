const std = @import("std");

/// GLFW's key codes top out around 348 (GLFW_KEY_LAST).
pub const max_keys: usize = 350;

/// Per-frame edge detection on top of a raw "is this key down right now"
/// poll. Takes the key source as `anytype` (just needs `.getKey(c_int) bool`)
/// instead of importing platform/window.zig directly, so this stays
/// GPU/GLFW-free and unit-testable with a plain fake.
pub const InputState = struct {
    current: [max_keys]bool = @splat(false),
    previous: [max_keys]bool = @splat(false),

    pub fn update(self: *InputState, win: anytype) void {
        self.previous = self.current;
        for (0..max_keys) |i| {
            self.current[i] = win.getKey(@as(c_int, @intCast(i)));
        }
    }

    pub fn isDown(self: *const InputState, key: c_int) bool {
        return self.current[@intCast(key)];
    }

    pub fn justPressed(self: *const InputState, key: c_int) bool {
        const k: usize = @intCast(key);
        return self.current[k] and !self.previous[k];
    }

    pub fn justReleased(self: *const InputState, key: c_int) bool {
        const k: usize = @intCast(key);
        return !self.current[k] and self.previous[k];
    }
};

const FakeWindow = struct {
    down: std.AutoHashMapUnmanaged(c_int, void) = .empty,

    fn getKey(self: *const FakeWindow, key: c_int) bool {
        return self.down.contains(key);
    }

    fn press(self: *FakeWindow, allocator: std.mem.Allocator, key: c_int) !void {
        try self.down.put(allocator, key, {});
    }

    fn release(self: *FakeWindow, key: c_int) void {
        _ = self.down.remove(key);
    }

    fn deinit(self: *FakeWindow, allocator: std.mem.Allocator) void {
        self.down.deinit(allocator);
    }
};

test "isDown reflects the current poll" {
    var win = FakeWindow{};
    defer win.deinit(std.testing.allocator);
    try win.press(std.testing.allocator, 65);

    var input = InputState{};
    input.update(&win);

    try std.testing.expect(input.isDown(65));
    try std.testing.expect(!input.isDown(66));
}

test "justPressed fires only on the frame a key transitions down" {
    var win = FakeWindow{};
    defer win.deinit(std.testing.allocator);

    var input = InputState{};
    input.update(&win); // frame 1: nothing down
    try std.testing.expect(!input.justPressed(65));

    try win.press(std.testing.allocator, 65);
    input.update(&win); // frame 2: just went down
    try std.testing.expect(input.justPressed(65));

    input.update(&win); // frame 3: still held, not "just" anymore
    try std.testing.expect(!input.justPressed(65));
}

test "justReleased fires only on the frame a key transitions up" {
    var win = FakeWindow{};
    defer win.deinit(std.testing.allocator);
    try win.press(std.testing.allocator, 65);

    var input = InputState{};
    input.update(&win); // frame 1: held
    try std.testing.expect(!input.justReleased(65));

    win.release(65);
    input.update(&win); // frame 2: just released
    try std.testing.expect(input.justReleased(65));

    input.update(&win); // frame 3: still up, not "just" anymore
    try std.testing.expect(!input.justReleased(65));
}
