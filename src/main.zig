const std = @import("std");
const Engine = @import("engine/engine.zig").Engine;
const DuckDemo = @import("examples/duck_demo.zig").DuckDemo;
const vkctx = @import("renderer/zVulkanContext.zig");

pub fn main() !void {
    var engine: Engine = .{};
    try engine.init();
    defer engine.deinit();

    // Initialize Vulkan renderer
    try engine.initVulkan("ZVulkan Window", vkctx.default_window_width, vkctx.default_window_height);

    // Initialize duck demo
    var demo = DuckDemo{};
    try demo.init(engine.registry().registryPtr(), engine.gpa.allocator());
    defer demo.deinit();

    // Run engine with demo update function
    try engine.run(&demo, DuckDemo.update);
}
