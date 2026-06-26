const std = @import("std");
const builtin = @import("builtin");

pub const Level = enum {
    debug,
    info,
    warn,
    err,

    fn label(self: Level) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
        };
    }

    fn colorCode(self: Level) []const u8 {
        return switch (self) {
            .debug => "\x1b[90m", // gray
            .info => "\x1b[36m", // cyan
            .warn => "\x1b[33m", // yellow
            .err => "\x1b[31m", // red
        };
    }
};

const color_reset = "\x1b[0m";

/// Debug-level logs are compiled out entirely outside Debug builds.
pub fn isEnabledFor(level: Level, mode: std.builtin.OptimizeMode) bool {
    return level != .debug or mode == .Debug;
}

fn write(comptime level: Level, src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (comptime !isEnabledFor(level, builtin.mode)) return;
    std.debug.print(
        comptime level.colorCode() ++ "[" ++ level.label() ++ "]" ++ color_reset ++ " {s}:{d}: " ++ fmt ++ "\n",
        .{ src.file, src.line } ++ args,
    );
}

pub fn debug(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    write(.debug, src, fmt, args);
}

pub fn info(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    write(.info, src, fmt, args);
}

pub fn warn(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    write(.warn, src, fmt, args);
}

pub fn err(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    write(.err, src, fmt, args);
}

test "isEnabledFor strips debug level outside Debug builds" {
    try std.testing.expect(isEnabledFor(.debug, .Debug));
    try std.testing.expect(!isEnabledFor(.debug, .ReleaseFast));
    try std.testing.expect(!isEnabledFor(.debug, .ReleaseSafe));
    try std.testing.expect(!isEnabledFor(.debug, .ReleaseSmall));
}

test "isEnabledFor always allows info/warn/err" {
    inline for (.{ .info, .warn, .err }) |level| {
        try std.testing.expect(isEnabledFor(level, .Debug));
        try std.testing.expect(isEnabledFor(level, .ReleaseFast));
    }
}

test "debug/info/warn/err compile and run without crashing" {
    debug(@src(), "test debug {d}", .{1});
    info(@src(), "test info {d}", .{2});
    warn(@src(), "test warn {d}", .{3});
    err(@src(), "test err {d}", .{4});
}
