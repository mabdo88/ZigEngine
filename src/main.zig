const std = @import("std");
const Engine = @import("engine/engine.zig").Engine;
const VulkanWorld = @import("engine/world.zig").VulkanWorld;
const config = @import("engine/config.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var engine: Engine(VulkanWorld) = undefined;
    try engine.init(gpa.allocator(), config.default);
    defer engine.deinit();
    try engine.run();
}
