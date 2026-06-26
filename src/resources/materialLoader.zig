const std = @import("std");
const Io = std.Io;
const fs = @import("../engine/fs.zig");

/// On-disk material definition: `{ "albedo": "path/to/texture.png", "metallic": 0.0, "roughness": 0.5 }`.
/// All fields are optional; missing ones fall back to these defaults.
pub const MaterialDef = struct {
    albedo: []const u8 = "",
    metallic: f32 = 0.0,
    roughness: f32 = 0.5,
};

pub fn loadMaterialJson(io: Io, allocator: std.mem.Allocator, path: []const u8) !std.json.Parsed(MaterialDef) {
    const text = try fs.readFileAlloc(io, allocator, path);
    defer allocator.free(text);
    return std.json.parseFromSlice(MaterialDef, allocator, text, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
}

fn uniqueTestPath(io: Io, buf: []u8) []const u8 {
    var rand_bytes: [8]u8 = undefined;
    Io.random(io, &rand_bytes);
    const n = std.mem.readInt(u64, &rand_bytes, .little);
    return std.fmt.bufPrint(buf, "material_test_{x}.json", .{n}) catch unreachable;
}

test "parses all fields" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [64]u8 = undefined;
    const path = uniqueTestPath(io, &buf);
    try fs.writeFile(io, path, "{\"albedo\": \"tex.png\", \"metallic\": 0.8, \"roughness\": 0.2}");
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    const parsed = try loadMaterialJson(io, std.testing.allocator, path);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("tex.png", parsed.value.albedo);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), parsed.value.metallic, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), parsed.value.roughness, 1e-6);
}

test "missing fields fall back to defaults" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [64]u8 = undefined;
    const path = uniqueTestPath(io, &buf);
    try fs.writeFile(io, path, "{\"albedo\": \"tex.png\"}");
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    const parsed = try loadMaterialJson(io, std.testing.allocator, path);
    defer parsed.deinit();

    try std.testing.expectApproxEqAbs(@as(f32, 0.0), parsed.value.metallic, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), parsed.value.roughness, 1e-6);
}

test "unknown fields are ignored rather than erroring" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [64]u8 = undefined;
    const path = uniqueTestPath(io, &buf);
    try fs.writeFile(io, path, "{\"albedo\": \"tex.png\", \"shader\": \"unused\", \"extra\": 1}");
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    const parsed = try loadMaterialJson(io, std.testing.allocator, path);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("tex.png", parsed.value.albedo);
}

test "malformed JSON returns an error" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [64]u8 = undefined;
    const path = uniqueTestPath(io, &buf);
    try fs.writeFile(io, path, "{ this is not json");
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    try std.testing.expectError(error.SyntaxError, loadMaterialJson(io, std.testing.allocator, path));
}
