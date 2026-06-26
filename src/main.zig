const std = @import("std");
const Engine = @import("engine/engine.zig").Engine;
const VulkanWorld = @import("engine/world.zig").VulkanWorld;
const config = @import("engine/config.zig");
const ini = @import("engine/ini.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var ini_io_threaded = std.Io.Threaded.init(gpa.allocator(), .{});
    const loaded_config = try ini.loadFromIni(ini_io_threaded.io(), gpa.allocator(), "strife.ini", config.default);
    ini_io_threaded.deinit();

    var engine: Engine(VulkanWorld) = undefined;
    try engine.init(gpa.allocator(), loaded_config);
    defer engine.deinit();
    try engine.run();
}

// Forces test discovery for files only reached through the runtime call
// graph (scene_system.zig -> meshLoader.zig, etc.) — `zig build test`'s
// exe_tests otherwise finds 0 tests here, same reason ecs_test.zig exists
// as an explicit aggregator for the GPU-free test target.
comptime {
    _ = @import("resources/meshLoader.zig");
}
