const std = @import("std");
const win = @import("platform/window.zig");
const gpu = @import("gpu.zig");
const world = @import("world.zig");

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .{};
    defer _ = debug_allocator.deinit();
    const allocator = debug_allocator.allocator();

    try win.init();
    defer win.terminate();

    var window = try win.create("ZigEngine", 800, 600, true);
    defer window.destroy();

    var vk_ctx = try gpu.init(allocator, &window);
    defer gpu.deinit(&vk_ctx);

    var w = try world.World.init(allocator);
    defer w.deinit();

    w.registerRenderSystem(&vk_ctx);

    const fixed_dt: f32 = 1.0 / 60.0;
    var accumulator: f32 = 0.0;
    var last_time: f64 = win.getTime();

    while (!window.shouldClose()) {
        win.pollEvents();

        const now = win.getTime();
        var frame_dt: f32 = @floatCast(now - last_time);
        last_time = now;
        if (frame_dt > 0.25) frame_dt = 0.25;
        accumulator += frame_dt;

        while (accumulator >= fixed_dt) {
            try w.fixedUpdate(fixed_dt, vk_ctx.swapChainExtent.width, vk_ctx.swapChainExtent.height);
            accumulator -= fixed_dt;
        }

        const alpha = accumulator / fixed_dt;
        try w.renderUpdate(alpha);
        try gpu.frame(&vk_ctx, &w.world, w.render_system_id);
    }
}
