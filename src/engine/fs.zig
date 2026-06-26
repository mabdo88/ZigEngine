const std = @import("std");
const Io = std.Io;

/// Filesystem helpers built on std.Io.Dir/File (Zig master moved file I/O
/// behind an Io instance — see std.Io.Dir — replacing the old std.fs.cwd()
/// style API).
/// Reads an entire file into an allocator-owned buffer.
pub fn readFileAlloc(io: Io, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
}

/// Overwrites (or creates) a file with the given contents.
pub fn writeFile(io: Io, path: []const u8, data: []const u8) !void {
    return Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

/// True if path exists and is accessible.
pub fn fileExists(io: Io, path: []const u8) bool {
    Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

/// Recursively creates path and any missing parent directories. A no-op for
/// components that already exist.
pub fn makeDirs(io: Io, path: []const u8) !void {
    return Io.Dir.cwd().createDirPath(io, path);
}

/// Returns the extension including the leading dot, or "" if none (e.g. "tar.gz" -> ".gz", "noext" -> "").
pub fn pathExt(path: []const u8) []const u8 {
    return std.fs.path.extension(path);
}

/// Returns the filename without its extension, e.g. "a/b/file.gltf" -> "file".
pub fn pathStem(path: []const u8) []const u8 {
    return std.fs.path.stem(path);
}

/// Joins path components with the platform separator.
pub fn pathJoin(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return std.fs.path.join(allocator, parts);
}

test "pathExt extracts the extension" {
    try std.testing.expectEqualStrings(".gltf", pathExt("assets/duck/scene.gltf"));
    try std.testing.expectEqualStrings("", pathExt("noext"));
}

test "pathStem strips directory and extension" {
    try std.testing.expectEqualStrings("scene", pathStem("assets/duck/scene.gltf"));
}

test "pathJoin combines components" {
    const allocator = std.testing.allocator;
    const joined = try pathJoin(allocator, &.{ "assets", "duck", "scene.gltf" });
    defer allocator.free(joined);
    try std.testing.expectEqualStrings("assets" ++ std.fs.path.sep_str ++ "duck" ++ std.fs.path.sep_str ++ "scene.gltf", joined);
}

fn uniqueTestName(io: Io, comptime prefix: []const u8, buf: []u8) []const u8 {
    var rand_bytes: [8]u8 = undefined;
    Io.random(io, &rand_bytes);
    const n = std.mem.readInt(u64, &rand_bytes, .little);
    return std.fmt.bufPrint(buf, prefix ++ "_{x}", .{n}) catch unreachable;
}

test "writeFile then readFileAlloc round-trips contents, fileExists reflects state" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [64]u8 = undefined;
    const path = uniqueTestName(io, "fs_test_tmp", &buf);
    try std.testing.expect(!fileExists(io, path));

    try writeFile(io, path, "hello engine");
    defer Io.Dir.cwd().deleteFile(io, path) catch {};
    try std.testing.expect(fileExists(io, path));

    const contents = try readFileAlloc(io, std.testing.allocator, path);
    defer std.testing.allocator.free(contents);
    try std.testing.expectEqualStrings("hello engine", contents);
}

test "makeDirs creates nested directories idempotently" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [64]u8 = undefined;
    const dir_name = uniqueTestName(io, "fs_test_dir", &buf);
    var dir_path_buf: [80]u8 = undefined;
    const dir_path = std.fmt.bufPrint(&dir_path_buf, "{s}/nested", .{dir_name}) catch unreachable;

    try makeDirs(io, dir_path);
    try makeDirs(io, dir_path); // idempotent
    try std.testing.expect(fileExists(io, dir_path));
    Io.Dir.cwd().deleteDir(io, dir_path) catch {};
    Io.Dir.cwd().deleteDir(io, dir_name) catch {};
}
