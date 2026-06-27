const std = @import("std");
const font_mod = @import("font.zig");
const render_system = @import("../engine/ecs/systems/render_system.zig");

/// Emits one screen-space line of text, baseline at `pos` (top-left origin,
/// y down — matches stb_truetype's baked-quad convention so glyph offsets
/// need no sign flip). Quads are emitted glyph-by-glyph in source order, so
/// they batch into a single texture-batched DrawCmd in ui_render.zig as
/// long as nothing else is emitted to a different texture in between.
pub fn drawText(font: *const font_mod.Font, text: []const u8, pos: @Vector(2, f32), color: @Vector(4, f32)) void {
    var pen = pos;
    for (text) |c| {
        const glyph = font.getGlyph(c) orelse {
            pen[0] += font.pixel_height * 0.5;
            continue;
        };
        if (glyph.size[0] > 0 and glyph.size[1] > 0) {
            render_system.uiQuad(
                pen + glyph.offset,
                glyph.size,
                glyph.uv_min,
                glyph.uv_max,
                color,
                font.texture_index,
            );
        }
        pen[0] += glyph.advance;
    }
}

/// Sums each glyph's advance — used by callers that need to right-align or
/// center text before drawing it (e.g. button.zig centering a label).
pub fn measureText(font: *const font_mod.Font, text: []const u8) @Vector(2, f32) {
    var width: f32 = 0;
    for (text) |c| {
        const glyph = font.getGlyph(c) orelse {
            width += font.pixel_height * 0.5;
            continue;
        };
        width += glyph.advance;
    }
    return .{ width, font.pixel_height };
}
