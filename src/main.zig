const std = @import("std");
const Engine = @import("engine/engine.zig").Engine;
const VulkanWorld = @import("engine/world.zig").VulkanWorld;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var engine = try Engine(VulkanWorld).init(gpa.allocator());
    defer engine.deinit();
    try engine.run();
}
