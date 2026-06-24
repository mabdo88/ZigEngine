const std = @import("std");
const flecs = @import("../flecs.zig");
const components = @import("../components/components.zig");
const SharedContext = @import("system.zig").SharedContext;

const renderer = @import("../../../renderer/zvulkanSystem.zig");
const rs = @import("../../../renderer/renderSystem.zig");
const window = @import("../../../platform/window.zig");
const math = @import("../../math.zig");
const shared_state = @import("shared_state.zig");

var render_state_ptr: ?*RenderSystemState = null;

pub const RenderSystemState = struct {
    gpu_system: rs.RenderSystem = undefined,
    allocator: std.mem.Allocator = undefined,
    texture_cache: std.AutoHashMap(u32, u32) = undefined,

    pub fn init(self: *RenderSystemState, allocator: std.mem.Allocator, world: *flecs.World, ids: components.ComponentIds, title: [:0]const u8, width: u16, height: u16) !void {
        self.allocator = allocator;
        self.texture_cache = std.AutoHashMap(u32, u32).init(allocator);
        try self.texture_cache.ensureTotalCapacity(@intCast(16));
        try renderer.init(allocator, title, width, height, world, ids, &self.gpu_system);
    }

    pub fn deinit(self: *RenderSystemState) void {
        renderer.deinit(&self.gpu_system);
        self.texture_cache.deinit();
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
};

pub fn run(it: [*c]flecs.c.ecs_iter_t) callconv(.c) void {
    const it_ptr: *flecs.c.ecs_iter_t = @ptrCast(it);
    const ctx: *SharedContext = @ptrCast(@alignCast(it_ptr.ctx.?));
    const state = render_state_ptr orelse return;
    const dt: f32 = it_ptr.delta_time;

    shared_state.aspect_ratio = renderer.aspectRatio();
    uploadPendingTextures(ctx, state) catch |err| {
        std.log.err("render_system: uploadPendingTextures failed: {}", .{err});
    };

    var q = ctx.world.query(&.{ctx.component_ids.CameraMatrices});
    defer q.deinit();
    var qit = q.iter();
    if (!qit.next()) return;
    const m = qit.fieldPtr(components.CameraMatricesComponent, 0).?;
    const matrices = math.CameraMatrices{ .view = m.view, .projection = m.proj };

    renderer.render(matrices, ctx.world, ctx.component_ids, ctx.mesh_cache, &state.gpu_system, dt) catch |err| {
        std.log.err("render_system: renderer.render failed: {}", .{err});
    };
}

fn uploadPendingTextures(ctx: *SharedContext, state: *RenderSystemState) !void {
    const ids = ctx.component_ids;
    var q = ctx.world.query(&.{ids.TextureData});
    defer q.deinit();
    var it = q.iter();
    while (it.next()) {
        const td_arr = it.field(components.TextureDataComponent, 0);
        var row: i32 = 0;
        while (row < it.count()) : (row += 1) {
            const entity = it.entity(row);
            const td = &td_arr[@intCast(row)];

            var index: u32 = 0;
            var resolved = false;
            if (state.texture_cache.get(td.material_id)) |cached| {
                index = cached;
                resolved = true;
            } else if (td.pixels.len > 0) {
                index = try renderer.uploadTexture(td.pixels, td.width, td.height);
                try state.texture_cache.put(td.material_id, index);
                resolved = true;
                state.allocator.free(td.pixels);
                td.pixels = &.{};
                td.width = 0;
                td.height = 0;
            }

            if (resolved) {
                ctx.world.set(entity, components.TextureComponent, ids.Texture, .{ .textureIndex = index });
                ctx.world.remove(entity, ids.TextureData);
            }
        }
    }
}

pub fn create(ctx: *SharedContext) !void {
    const state = try ctx.allocator.create(RenderSystemState);
    try state.init(ctx.allocator, ctx.world, ctx.component_ids, ctx.config.window_title, ctx.config.window_width, ctx.config.window_height);
    render_state_ptr = state;
    shared_state.aspect_ratio = renderer.aspectRatio();
}

pub fn destroy(ctx: *SharedContext) void {
    const state = render_state_ptr orelse return;
    state.deinit();
    render_state_ptr = null;
    ctx.allocator.destroy(state);
}

pub fn getGpuSystem() *rs.RenderSystem {
    return &render_state_ptr.?.gpu_system;
}
