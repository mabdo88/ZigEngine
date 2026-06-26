const std = @import("std");
const builtin = @import("builtin");
const log = @import("log.zig");

/// Checks an internal invariant. Compiled out entirely outside Debug builds
/// (zero-cost in release) — use std.debug.assert instead for checks that
/// must still fail loudly in release.
pub fn strife_assert(cond: bool, comptime msg: []const u8, src: std.builtin.SourceLocation) void {
    if (comptime builtin.mode != .Debug) return;
    if (!cond) {
        log.err(src, "ASSERTION FAILED: {s}", .{msg});
        @breakpoint();
    }
}

test "strife_assert does not trip on a true condition" {
    strife_assert(1 + 1 == 2, "math should still work", @src());
}
