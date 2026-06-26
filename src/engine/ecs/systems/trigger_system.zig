//! Drains Jolt's trigger-event queue (populated by ContactListener during
//! PhysicsSyncSystem's jolt_step call, see jolt_wrapper.cpp's TriggerListener)
//! and re-emits each as a TriggerEvent through the ECS EventBus, resolving
//! Jolt body IDs back to entities via PhysicsWorld.body_to_entity. Must run
//! after PhysicsSyncSystem (higher priority number) so each frame's events
//! are drained after that frame's jolt_step actually produced them.
const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;
const physics_world = @import("../../../physics/physics_world.zig");
const physics_shared = @import("../../../physics/physics_shared.zig");

pub fn update(registry: *Registry, _: *anyopaque, _: f32) anyerror!void {
    const world = physics_shared.world orelse return;

    var event: physics_world.jolt.JoltTriggerEvent = undefined;
    while (physics_world.jolt.jolt_poll_trigger_event(world.ctx, &event)) {
        const trigger_ent = world.entityForBody(event.trigger_body) orelse continue;
        const other_ent = world.entityForBody(event.other_body) orelse continue;
        registry.events.emit(.{ .trigger_event = .{
            .trigger_ent = trigger_ent,
            .other_ent = other_ent,
            .is_enter = event.is_enter,
        } });
    }
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const slot = try ctx.allocator.create(u8);
    slot.* = 0;
    return @ptrCast(slot);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const slot: *u8 = @ptrCast(@alignCast(ctx));
    allocator.destroy(slot);
}
