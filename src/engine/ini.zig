const std = @import("std");
const Io = std.Io;
const fs = @import("fs.zig");
const config_mod = @import("config.zig");

/// Minimal `[section]\nkey = value` INI parser. All strings are owned by an
/// internal arena, so the parsed Ini outlives individual get*() calls
/// without per-string lifetime tracking.
pub const Ini = struct {
    arena: std.heap.ArenaAllocator,
    sections: std.StringHashMapUnmanaged(std.StringHashMapUnmanaged([]const u8)) = .empty,

    const default_section = "";

    pub fn parse(backing_allocator: std.mem.Allocator, text: []const u8) !Ini {
        var self = Ini{ .arena = std.heap.ArenaAllocator.init(backing_allocator) };
        const allocator = self.arena.allocator();

        var current_section: []const u8 = default_section;
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (line.len == 0 or line[0] == ';' or line[0] == '#') continue;

            if (line[0] == '[' and line[line.len - 1] == ']') {
                current_section = try allocator.dupe(u8, line[1 .. line.len - 1]);
                continue;
            }

            const eq_index = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = std.mem.trim(u8, line[0..eq_index], " \t");
            const value = std.mem.trim(u8, line[eq_index + 1 ..], " \t");
            if (key.len == 0) continue;

            const section_map = blk: {
                const existing = self.sections.getPtr(current_section);
                if (existing) |s| break :blk s;
                const owned_section = try allocator.dupe(u8, current_section);
                try self.sections.put(allocator, owned_section, .empty);
                break :blk self.sections.getPtr(owned_section).?;
            };
            try section_map.put(allocator, try allocator.dupe(u8, key), try allocator.dupe(u8, value));
        }

        return self;
    }

    pub fn deinit(self: *Ini) void {
        self.arena.deinit();
    }

    fn raw(self: *const Ini, section: []const u8, key: []const u8) ?[]const u8 {
        const section_map = self.sections.get(section) orelse return null;
        return section_map.get(key);
    }

    pub fn getStr(self: *const Ini, section: []const u8, key: []const u8, default: []const u8) []const u8 {
        return self.raw(section, key) orelse default;
    }

    pub fn getInt(self: *const Ini, comptime T: type, section: []const u8, key: []const u8, default: T) T {
        const v = self.raw(section, key) orelse return default;
        return std.fmt.parseInt(T, v, 10) catch default;
    }

    pub fn getFloat(self: *const Ini, comptime T: type, section: []const u8, key: []const u8, default: T) T {
        const v = self.raw(section, key) orelse return default;
        return std.fmt.parseFloat(T, v) catch default;
    }

    pub fn getBool(self: *const Ini, section: []const u8, key: []const u8, default: bool) bool {
        const v = self.raw(section, key) orelse return default;
        if (std.ascii.eqlIgnoreCase(v, "true") or std.mem.eql(u8, v, "1")) return true;
        if (std.ascii.eqlIgnoreCase(v, "false") or std.mem.eql(u8, v, "0")) return false;
        return default;
    }
};

/// Starts from `base` and overlays any fields present in the INI file at
/// `path`. Missing keys/sections, or a missing file entirely, just leave
/// `base`'s defaults in place.
pub fn loadFromIni(io: Io, allocator: std.mem.Allocator, path: []const u8, base: config_mod.Config) !config_mod.Config {
    const text = fs.readFileAlloc(io, allocator, path) catch |e| switch (e) {
        error.FileNotFound => return base,
        else => return e,
    };
    defer allocator.free(text);

    var ini = try Ini.parse(allocator, text);
    defer ini.deinit();

    var config = base;
    config.window_width = ini.getInt(u16, "window", "width", config.window_width);
    config.window_height = ini.getInt(u16, "window", "height", config.window_height);
    config.vsync = ini.getBool("window", "vsync", config.vsync);
    config.enable_validation = ini.getBool("engine", "enable_validation", config.enable_validation);
    return config;
}

test "parse reads keys under their section" {
    const text =
        \\[window]
        \\width = 1280
        \\height = 720
        \\vsync = false
        \\
        \\[engine]
        \\enable_validation = true
    ;
    var ini = try Ini.parse(std.testing.allocator, text);
    defer ini.deinit();

    try std.testing.expectEqual(@as(u16, 1280), ini.getInt(u16, "window", "width", 0));
    try std.testing.expectEqual(@as(u16, 720), ini.getInt(u16, "window", "height", 0));
    try std.testing.expectEqual(false, ini.getBool("window", "vsync", true));
    try std.testing.expectEqual(true, ini.getBool("engine", "enable_validation", false));
}

test "missing keys and sections fall back to the provided default" {
    var ini = try Ini.parse(std.testing.allocator, "[window]\nwidth = 800\n");
    defer ini.deinit();

    try std.testing.expectEqual(@as(u16, 800), ini.getInt(u16, "window", "width", 0));
    try std.testing.expectEqual(@as(u16, 42), ini.getInt(u16, "window", "missing_key", 42));
    try std.testing.expectEqual(@as(u16, 99), ini.getInt(u16, "missing_section", "width", 99));
}

test "comments and blank lines are ignored" {
    const text =
        \\; this is a comment
        \\# so is this
        \\
        \\[window]
        \\width = 640
    ;
    var ini = try Ini.parse(std.testing.allocator, text);
    defer ini.deinit();
    try std.testing.expectEqual(@as(u16, 640), ini.getInt(u16, "window", "width", 0));
}

test "getStr and getFloat read typed values" {
    var ini = try Ini.parse(std.testing.allocator, "[camera]\nfov = 1.5\nname = main\n");
    defer ini.deinit();

    try std.testing.expectEqualStrings("main", ini.getStr("camera", "name", "fallback"));
    try std.testing.expectApproxEqAbs(@as(f32, 1.5), ini.getFloat(f32, "camera", "fov", 0.0), 1e-6);
}

test "keys before any [section] header land in the default section" {
    var ini = try Ini.parse(std.testing.allocator, "loose_key = loose_value\n[window]\nwidth = 800\n");
    defer ini.deinit();
    try std.testing.expectEqualStrings("loose_value", ini.getStr("", "loose_key", "missing"));
}

test "loadFromIni overlays only the fields present in the file" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var rand_bytes: [8]u8 = undefined;
    Io.random(io, &rand_bytes);
    const n = std.mem.readInt(u64, &rand_bytes, .little);
    var buf: [64]u8 = undefined;
    const path = std.fmt.bufPrint(&buf, "ini_test_tmp_{x}.ini", .{n}) catch unreachable;
    try fs.writeFile(io, path, "[window]\nwidth = 1920\n");
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    const base = config_mod.Config{};
    const loaded = try loadFromIni(io, std.testing.allocator, path, base);

    try std.testing.expectEqual(@as(u16, 1920), loaded.window_width);
    try std.testing.expectEqual(base.window_height, loaded.window_height); // untouched, keeps default
}

test "loadFromIni returns base config unchanged when the file does not exist" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const base = config_mod.Config{};
    const loaded = try loadFromIni(io, std.testing.allocator, "does_not_exist.ini", base);
    try std.testing.expectEqual(base.window_width, loaded.window_width);
}
