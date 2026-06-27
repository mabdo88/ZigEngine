const image_renderer = @import("image_renderer.zig");
const text_renderer = @import("text_renderer.zig");
const font_mod = @import("font.zig");
const render_system = @import("../engine/ecs/systems/render_system.zig");
const window = @import("../platform/window.zig");

pub const State = enum { normal, hover, pressed };

pub const ButtonWidget = struct {
    pos: @Vector(2, f32),
    size: @Vector(2, f32),
    label: []const u8,
    state: State = .normal,
    on_click: ?*const fn () void = null,

    /// True while the cursor is over the button's screen-space rect.
    fn containsPoint(self: *const ButtonWidget, point: @Vector(2, f32)) bool {
        return point[0] >= self.pos[0] and point[0] <= self.pos[0] + self.size[0] and
            point[1] >= self.pos[1] and point[1] <= self.pos[1] + self.size[1];
    }

    /// Polls the mouse directly (same pattern movement_system.zig uses for
    /// the fly-cam) rather than routing through InputState's edge-detected
    /// keyboard polling — buttons only care about "down right now" plus a
    /// release-while-still-hovering edge to fire the click.
    pub fn update(self: *ButtonWidget) void {
        const win = render_system.windowPtr();
        const cursor = win.getCursorPos();
        const point = @Vector(2, f32){ @floatCast(cursor.x), @floatCast(cursor.y) };
        const hovered = self.containsPoint(point);
        const down = win.getMouseButton(window.MouseButton.left);

        const was_pressed = self.state == .pressed;
        if (!hovered) {
            self.state = .normal;
        } else if (down) {
            self.state = .pressed;
        } else {
            if (was_pressed) {
                if (self.on_click) |cb| cb();
            }
            self.state = .hover;
        }
    }

    pub fn draw(self: *const ButtonWidget, font: *const font_mod.Font) void {
        const color: @Vector(4, f32) = switch (self.state) {
            .normal => .{ 0.25, 0.25, 0.25, 1.0 },
            .hover => .{ 0.35, 0.35, 0.35, 1.0 },
            .pressed => .{ 0.15, 0.15, 0.15, 1.0 },
        };
        image_renderer.drawRect(self.pos, self.size, color);

        const text_size = text_renderer.measureText(font, self.label);
        const label_pos = self.pos + (self.size - text_size) * @as(@Vector(2, f32), @splat(0.5));
        text_renderer.drawText(font, self.label, label_pos, .{ 1, 1, 1, 1 });
    }
};
