const std = @import("std");
const flecs = @import("../flecs.zig");
const components = @import("../components/components.zig");
const SharedContext = @import("system.zig").SharedContext;

const input_system = @import("input_system.zig");
const scene_system = @import("scene_system.zig");
const movement_system = @import("movement_system.zig");
const camera_system = @import("camera_system.zig");
const transform_system = @import("transform_system.zig");
const render_system = @import("render_system.zig");

pub const SystemHandles = struct {
    input: flecs.Entity = 0,
    scene: flecs.Entity = 0,
    movement: flecs.Entity = 0,
    transform: flecs.Entity = 0,
    camera: flecs.Entity = 0,
    render: flecs.Entity = 0,
    scene_ctx: ?*scene_system.SceneSystemCtx = null,
};

pub fn registerAll(world: *flecs.World, ctx: *SharedContext) !SystemHandles {
    var handles: SystemHandles = .{};

    render_system.create(ctx) catch |err| {
        std.log.err("Failed to create render system: {}", .{err});
        return err;
    };
    errdefer render_system.destroy(ctx);

    const scene_state = try scene_system.create(ctx);
    errdefer scene_system.destroy(ctx, scene_state);

    const scene_ctx = try ctx.allocator.create(scene_system.SceneSystemCtx);
    scene_ctx.* = .{ .shared = ctx, .state = scene_state };
    errdefer ctx.allocator.destroy(scene_ctx);

    handles.scene_ctx = scene_ctx;

    // Register InputState singleton before any system that reads it.
    world.setSingleton(components.InputStateComponent, ctx.component_ids.InputState, .{});

    handles.input = world.systemRun("InputSystem", flecs.preUpdate(), input_system.run, @ptrCast(ctx));
    handles.scene = world.systemRun("SceneSystem", flecs.onUpdate(), scene_system.run, @ptrCast(scene_ctx));
    handles.movement = world.systemRun("MovementSystem", flecs.postUpdate(), movement_system.run, @ptrCast(ctx));
    handles.transform = world.systemRun("TransformSystem", flecs.postUpdate(), transform_system.run, @ptrCast(ctx));
    handles.camera = world.systemRun("CameraSystem", flecs.postUpdate(), camera_system.run, @ptrCast(ctx));
    handles.render = world.systemRun("RenderSystem", flecs.onStore(), render_system.run, @ptrCast(ctx));

    return handles;
}

pub fn destroyAll(ctx: *SharedContext, handles: SystemHandles) void {
    if (handles.scene_ctx) |scene_ctx| {
        scene_system.destroy(ctx, scene_ctx.state);
        ctx.allocator.destroy(scene_ctx);
    }
    render_system.destroy(ctx);
}
