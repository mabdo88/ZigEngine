const image_renderer = @import("image_renderer.zig");

/// Projects a world-space point through a combined view*projection matrix
/// into screen pixels. Returns null if the point is behind the camera
/// (clip.w <= 0) — callers should skip drawing rather than plot garbage.
/// `view_proj` is column-major (m[col][row]), matching the rest of the
/// engine's Mat4 convention.
pub fn worldToScreen(view_proj: [4][4]f32, world_pos: @Vector(3, f32), screen_width: f32, screen_height: f32) ?@Vector(2, f32) {
    const wp = [4]f32{ world_pos[0], world_pos[1], world_pos[2], 1.0 };
    var clip: [4]f32 = .{ 0, 0, 0, 0 };
    for (0..4) |row| {
        var sum: f32 = 0;
        for (0..4) |col| sum += view_proj[col][row] * wp[col];
        clip[row] = sum;
    }
    if (clip[3] <= 0.0001) return null;

    const ndc_x = clip[0] / clip[3];
    const ndc_y = clip[1] / clip[3];
    return .{
        (ndc_x * 0.5 + 0.5) * screen_width,
        (ndc_y * 0.5 + 0.5) * screen_height,
    };
}

/// Draws a background + fill bar centered above `world_pos`, color
/// lerped red->green by health percentage. Hides entirely at full HP (a
/// permanently-full bar over every healthy entity is just visual noise).
pub fn draw(
    view_proj: [4][4]f32,
    world_pos: @Vector(3, f32),
    screen_width: f32,
    screen_height: f32,
    current: f32,
    max: f32,
    bar_size: @Vector(2, f32),
) void {
    if (max <= 0 or current >= max) return;
    const center = worldToScreen(view_proj, world_pos, screen_width, screen_height) orelse return;
    const pos = center - @Vector(2, f32){ bar_size[0] * 0.5, bar_size[1] };

    const pct = std_clamp(current / max);
    image_renderer.drawRect(pos, bar_size, .{ 0.1, 0.1, 0.1, 0.8 });
    const fill_color = @Vector(4, f32){ 1.0 - pct, pct, 0.0, 1.0 };
    image_renderer.drawRect(pos, .{ bar_size[0] * pct, bar_size[1] }, fill_color);
}

fn std_clamp(v: f32) f32 {
    return @max(0.0, @min(1.0, v));
}
