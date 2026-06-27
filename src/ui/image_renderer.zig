const render_system = @import("../engine/ecs/systems/render_system.zig");

/// Slot 0 is always the engine's default 1x1 white texture (created by
/// material.createDefaultTexture at startup, before any user asset loads),
/// so solid-color rects reuse it instead of needing a dedicated UI white
/// texture — same texture heap as 3D materials, just sampled flat.
pub const WHITE_TEXTURE: u32 = 0;

pub fn drawImage(pos: @Vector(2, f32), size: @Vector(2, f32), texture_index: u32, color: @Vector(4, f32)) void {
    render_system.uiQuad(pos, size, .{ 0, 0 }, .{ 1, 1 }, color, texture_index);
}

pub fn drawImageUV(pos: @Vector(2, f32), size: @Vector(2, f32), uv_min: @Vector(2, f32), uv_max: @Vector(2, f32), texture_index: u32, color: @Vector(4, f32)) void {
    render_system.uiQuad(pos, size, uv_min, uv_max, color, texture_index);
}

pub fn drawRect(pos: @Vector(2, f32), size: @Vector(2, f32), color: @Vector(4, f32)) void {
    drawImage(pos, size, WHITE_TEXTURE, color);
}
