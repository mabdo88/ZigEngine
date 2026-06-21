const std = @import("std");
const wi = @import("world_interface.zig");
const InnerWorld = @import("world.zig").World;
const vkctx = @import("../renderer/zVulkanContext.zig");
const systems = @import("../renderer/systems.zig");
const component = @import("../components/components.zig");
const DuckDemo = @import("../examples/duck_demo.zig").DuckDemo;

/// A concrete World implementation: Vulkan renderer + ECS + duck demo scene.
/// Implements the WorldFactory interface — engine knows nothing about its internals.
pub const VulkanECSWorld = struct {
    inner: InnerWorld = .{},
    demo: DuckDemo = .{},
    allocator: std.mem.Allocator = undefined,
    last_time: f64 = 0,

    pub fn init(self: *VulkanECSWorld, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        try self.inner.init(allocator);
        try self.inner.initVulkan("ZVulkan Window", vkctx.default_window_width, vkctx.default_window_height);
        try self.demo.init(&self.inner, allocator);
        self.last_time = vkctx.zvk.vkGetTime();
        std.log.info("VulkanECSWorld: initialized", .{});
    }

    pub fn update(self: *VulkanECSWorld, _: f32) wi.WorldCommand {
        if (systems.renderer.shouldClose()) return .exit;
        systems.renderer.pollEvents();

        const now = vkctx.zvk.vkGetTime();
        const dt: f32 = @floatCast(now - self.last_time);
        self.last_time = now;

        self.demo.update(dt);

        const matrices = systems.camera.update(&self.inner.registry, systems.renderer.aspectRatio());
        systems.renderer.render(matrices.?, &self.inner.registry, &self.inner.render_system) catch |err| {
            std.log.err("VulkanECSWorld: render error: {s}", .{@errorName(err)});
            return .exit;
        };

        return .none;
    }

    pub fn shouldClose(_: *VulkanECSWorld) bool {
        return systems.renderer.shouldClose();
    }

    pub fn deinit(self: *VulkanECSWorld) void {
        _ = vkctx.zvk.vkDeviceWaitIdle(vkctx.ctx.m_Device);
        self.demo.deinit();
        self.inner.deinit();
        std.log.info("VulkanECSWorld: destroyed", .{});
    }

    /// Returns a WorldFactory for use with Engine.addWorld().
    pub fn factory() wi.WorldFactory {
        return wi.WorldFactory.init(VulkanECSWorld, "Vulkan ECS World (Duck)");
    }
};
