const std = @import("std");
const stbtt = @import("stbttimport");
const fs = @import("../engine/fs.zig");

pub const ATLAS_SIZE: u32 = 1024;
pub const FIRST_CHAR: i32 = 32; // ' '
pub const NUM_CHARS: u32 = 95; // ASCII 32..126

pub const GlyphInfo = struct {
    uv_min: @Vector(2, f32),
    uv_max: @Vector(2, f32),
    /// Pixel offset from the pen position to this glyph's top-left corner,
    /// y increasing downward (stb_truetype's baked-quad convention).
    offset: @Vector(2, f32),
    size: @Vector(2, f32),
    advance: f32,
};

pub const Font = struct {
    glyphs: [NUM_CHARS]GlyphInfo = undefined,
    texture_index: u32 = 0,
    pixel_height: f32 = 0,

    pub fn getGlyph(self: *const Font, codepoint: u21) ?GlyphInfo {
        const c: i32 = @intCast(codepoint);
        if (c < FIRST_CHAR or c >= FIRST_CHAR + @as(i32, @intCast(NUM_CHARS))) return null;
        return self.glyphs[@intCast(c - FIRST_CHAR)];
    }
};

/// Bakes `ttf_path` into a single-pass ATLAS_SIZE x ATLAS_SIZE bitmap via
/// stb_truetype's classic (non-rect-pack) baker, then uploads it as a
/// regular RGBA8 texture through `upload_fn` (white RGB, glyph coverage in
/// alpha) — reuses the engine's existing R8G8B8A8_SRGB texture pipeline
/// rather than adding a second single-channel image format/sampler path
/// just for fonts.
pub fn load(
    allocator: std.mem.Allocator,
    ttf_path: []const u8,
    pixel_height: f32,
    upload_fn: *const fn (pixels: []const u8, width: u32, height: u32) anyerror!u32,
) !Font {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const ttf_data = try fs.readFileAlloc(io, allocator, ttf_path);
    defer allocator.free(ttf_data);

    const alpha_bitmap = try allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE);
    defer allocator.free(alpha_bitmap);
    @memset(alpha_bitmap, 0);

    var bakedchars: [NUM_CHARS]stbtt.stbtt_bakedchar = undefined;
    const bake_result = stbtt.stbtt_BakeFontBitmap(
        ttf_data.ptr,
        0,
        pixel_height,
        alpha_bitmap.ptr,
        @intCast(ATLAS_SIZE),
        @intCast(ATLAS_SIZE),
        FIRST_CHAR,
        @intCast(NUM_CHARS),
        &bakedchars,
    );
    if (bake_result <= 0) return error.FontBakeFailed;

    const rgba = try allocator.alloc(u8, ATLAS_SIZE * ATLAS_SIZE * 4);
    defer allocator.free(rgba);
    for (alpha_bitmap, 0..) |a, i| {
        rgba[i * 4 + 0] = 255;
        rgba[i * 4 + 1] = 255;
        rgba[i * 4 + 2] = 255;
        rgba[i * 4 + 3] = a;
    }

    var font = Font{ .pixel_height = pixel_height };
    font.texture_index = try upload_fn(rgba, ATLAS_SIZE, ATLAS_SIZE);

    const inv_atlas: f32 = 1.0 / @as(f32, @floatFromInt(ATLAS_SIZE));
    for (bakedchars, 0..) |bc, i| {
        font.glyphs[i] = .{
            .uv_min = .{ @as(f32, @floatFromInt(bc.x0)) * inv_atlas, @as(f32, @floatFromInt(bc.y0)) * inv_atlas },
            .uv_max = .{ @as(f32, @floatFromInt(bc.x1)) * inv_atlas, @as(f32, @floatFromInt(bc.y1)) * inv_atlas },
            .offset = .{ bc.xoff, bc.yoff },
            .size = .{ @floatFromInt(bc.x1 - bc.x0), @floatFromInt(bc.y1 - bc.y0) },
            .advance = bc.xadvance,
        };
    }
    return font;
}
