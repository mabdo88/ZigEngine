//! The single ECS↔Vulkan boundary. Owns all GPU state at module level: the
//! RenderSystem (per-entity GPU mesh map), the Vulkan context (via the renderer
//! module), and the bindless texture cache. No other system imports Vulkan.
//!
//! Frame flow (`update`): upload any pending CPU textures to the bindless heap
//! and write back `TextureComponent`, then read `CameraMatricesComponent` and
//! draw. Mesh GPU upload is lazy inside the renderer's draw pass.

const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const Entity = @import("../entity/entity.zig").Entity;
const components = @import("../components/components.zig");

const renderer = @import("../../../renderer/zvulkanSystem.zig");
const rs = @import("../../../renderer/renderSystem.zig");
const cs = @import("../../../renderer/cameraSystem.zig");
const window = @import("../../../platform/window.zig");

var g_render_system: rs.RenderSystem = undefined;
var g_allocator: std.mem.Allocator = undefined;
/// material_id -> bindless texture slot, valid for the current scene only.
var g_texture_cache: std.AutoHashMap(u32, u32) = undefined;

/// Initialize Vulkan + GPU state and register the entity-destroy hook (which
/// frees GPU mesh buffers). Called once from world.zig before any frame.
pub fn init(allocator: std.mem.Allocator, registry: *Registry, title: [:0]const u8, width: u16, height: u16) !void {
    g_allocator = allocator;
    g_texture_cache = std.AutoHashMap(u32, u32).init(allocator);
    try renderer.init(allocator, title, width, height, registry, &g_render_system);
}

pub fn deinit(registry: *Registry) void {
    renderer.deinit(registry, &g_render_system);
    g_texture_cache.deinit();
}

/// Clear the texture cache and reclaim bindless slots. Called by scene_system
/// at the start of an unload, before entities are destroyed.
pub fn onSceneUnload() void {
    renderer.resetTextures();
    g_texture_cache.clearRetainingCapacity();
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

/// The active window, for the input system to read key state.
pub fn windowPtr() *window.Window {
    return renderer.windowPtr();
}

pub fn update(registry: *Registry, dt: f32) anyerror!void {
    try uploadPendingTextures(registry);

    var cam_it = registry.Query(.{components.CameraMatricesComponent});
    const cam_entity = cam_it.next() orelse return;
    const m = registry.get(components.CameraMatricesComponent, cam_entity).?;
    const matrices = cs.CameraMatrices{ .view = m.view, .projection = m.proj };

    try renderer.render(matrices, registry, &g_render_system, dt);
}

/// Upload CPU texture data to the bindless heap (deduped by material_id), write
/// the resulting slot back as `TextureComponent`, and free the CPU pixels.
fn uploadPendingTextures(registry: *Registry) !void {
    var it = registry.Query(.{components.TextureDataComponent});
    while (it.next()) |entity| {
        const td = registry.get(components.TextureDataComponent, entity).?;

        var index: u32 = 0;
        if (g_texture_cache.get(td.material_id)) |cached| {
            index = cached;
        } else if (td.pixels.len > 0) {
            index = try renderer.uploadTexture(td.pixels, td.width, td.height);
            try g_texture_cache.put(td.material_id, index);
        } else {
            // No pixels and nothing cached yet: fall back to the default slot.
            index = 0;
        }

        try registry.set(entity, components.TextureComponent{ .textureIndex = index });

        // Free CPU pixels once uploaded; clear so the component's deinit is a no-op.
        if (td.pixels.len > 0) {
            g_allocator.free(td.pixels);
            td.pixels = &.{};
            td.width = 0;
            td.height = 0;
        }
    }
}
