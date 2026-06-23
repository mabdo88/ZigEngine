const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const Entity = @import("../entity/entity.zig").Entity;
const components = @import("../components/components.zig");
const event = @import("../event.zig");

const renderer = @import("../../../renderer/zvulkanSystem.zig");
const rs = @import("../../../renderer/renderSystem.zig");
const window = @import("../../../platform/window.zig");
const math = @import("../../math.zig");

pub const RenderSystemState = struct {
    gpu_system: rs.RenderSystem = undefined,
    allocator: std.mem.Allocator = undefined,
    texture_cache: std.AutoHashMap(u32, u32) = undefined,

    pub fn init(self: *RenderSystemState, allocator: std.mem.Allocator, registry: *Registry, title: [:0]const u8, width: u16, height: u16) !void {
        self.allocator = allocator;
        self.texture_cache = std.AutoHashMap(u32, u32).init(allocator);
        try self.texture_cache.ensureTotalCapacity(@intCast(16));
        try renderer.init(allocator, title, width, height, registry, &self.gpu_system);
    }

    pub fn deinit(self: *RenderSystemState, registry: *Registry) void {
        renderer.deinit(registry, &self.gpu_system);
        self.texture_cache.deinit();
    }

    pub fn onSceneUnloaded(ctx: *anyopaque, payload: event.EventPayload) void {
        _ = payload;
        const self: *RenderSystemState = @ptrCast(@alignCast(ctx));
        renderer.resetTextures();
        self.texture_cache.clearRetainingCapacity();
    }

    pub fn pollEvents() void {
        renderer.pollEvents();
    }

    pub fn shouldClose() bool {
        return renderer.shouldClose();
    }

    pub fn aspectRatio() f32 {
        return renderer.aspectRatio();
    }

    pub fn windowPtr() *window.Window {
        return renderer.windowPtr();
    }

    pub fn update(self: *RenderSystemState, registry: *Registry, dt: f32) !void {
        try self.uploadPendingTextures(registry);

        var cam_it = registry.Query(.{components.CameraMatricesComponent});
        const cam_entity = cam_it.next() orelse return;
        const m = registry.get(components.CameraMatricesComponent, cam_entity).?;
        const matrices = math.CameraMatrices{ .view = m.view, .projection = m.proj };

        try renderer.render(matrices, registry, &self.gpu_system, dt);
    }

    fn uploadPendingTextures(self: *RenderSystemState, registry: *Registry) !void {
        var it = registry.Query(.{components.TextureDataComponent});
        while (it.next()) |entity| {
            const td = registry.get(components.TextureDataComponent, entity).?;

            var index: u32 = 0;
            if (self.texture_cache.get(td.material_id)) |cached| {
                index = cached;
            } else if (td.pixels.len > 0) {
                index = try renderer.uploadTexture(td.pixels, td.width, td.height);
                try self.texture_cache.put(td.material_id, index);
            } else {
                index = 0;
            }

            try registry.set(entity, components.TextureComponent{ .textureIndex = index });

            if (td.pixels.len > 0) {
                self.allocator.free(td.pixels);
                td.pixels = &.{};
                td.width = 0;
                td.height = 0;
            }
        }
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *RenderSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}
