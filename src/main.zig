const std = @import("std");
const Engine = @import("ecs/engine.zig").Engine;
const vma: type = @import("vmaimport");
pub fn main() !void {
    var engine: Engine = .{};
    try engine.init();
    defer engine.deinit();

    try engine.run();
}
