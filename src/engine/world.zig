const std = @import("std");
const Registry = @import("registry.zig").Registry;
const Entity = @import("entity.zig").Entity;
const scomponent = @import("../components/SystemComponents.zig");
const systems = @import("../renderer/systems.zig");
const vkctx = @import("../renderer/zVulkanContext.zig");
const RenderSystem = @import("../renderer/renderSystem.zig").RenderSystem;

pub const World = struct {
    registry: Registry = undefined,
    render_system: RenderSystem = undefined,
    world_allocator: std.mem.Allocator = undefined,
    window: scomponent.WindowComponent = .{ .title = "ZVulkan Window", .width = vkctx.default_window_width, .height = vkctx.default_window_height },

    pub fn init(self: *World, allocator: std.mem.Allocator) !void {
        std.log.info("Initializing World...", .{});
        self.world_allocator = allocator;
        self.registry.init(self.world_allocator);
        std.log.info("World Created", .{});
    }

    pub fn deinit(self: *World) void {
        systems.renderer.deinit(&self.registry, &self.render_system);
        std.log.info("World running with {d} entities before shutdown", .{self.registry.aliveCount()});
        self.registry.deinit();
        self.world_allocator = undefined;
        std.log.info("World Destroyed", .{});
    }

    pub fn initVulkan(self: *World, title: ?[:0]const u8, width: u16, height: u16) !void {
        _ = try systems.renderer.init(self.world_allocator, title, width, height, &self.registry, &self.render_system);
    }

    pub fn run(self: *World, context: anytype, updateFn: anytype) !void {
        std.log.info("World running with {d} entities", .{self.registry.aliveCount()});
        var last_time = vkctx.zvk.vkGetTime();
        while (!systems.renderer.shouldClose()) {
            systems.renderer.pollEvents();
            const now = vkctx.zvk.vkGetTime();
            const dt: f32 = @floatCast(now - last_time);
            last_time = now;

            // Call user-provided update function with context and delta time
            updateFn(context, dt);

            const matrices = systems.camera.update(&self.registry, systems.renderer.aspectRatio());
            try systems.renderer.render(matrices.?, &self.registry, &self.render_system);
        }
        // Wait for GPU to finish last frame before cleanup
        _ = vkctx.zvk.vkDeviceWaitIdle(vkctx.ctx.m_Device);
    }

    pub fn uploadTexture(self: *World, pixels: []const u8, width: u32, height: u32) !vkctx.TextureHandle {
        _ = self;
        return systems.renderer.uploadTexture(pixels, width, height);
    }

    pub fn registryPtr(self: *World) *Registry {
        return &self.registry;
    }
};
