//! Advances every CharacterControllerComponent each fixed tick: integrates
//! gravity/collision via Jolt's CharacterVirtual::Update (see
//! character_controller.zig), then writes the resulting position back into
//! TransformComponent. Gameplay code calls character_controller.setVelocity/
//! jump on the same handle from elsewhere (e.g. an input system) before this
//! runs — this system only owns the per-frame physics step + writeback.
const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;
const physics_shared = @import("../../../physics/physics_shared.zig");
const character_controller = @import("../../../physics/character_controller.zig");

pub fn update(registry: *Registry, _: *anyopaque, dt: f32) anyerror!void {
    const world = physics_shared.world orelse return;

    var it = registry.Query(.{ components.CharacterControllerComponent, components.TransformComponent });
    while (it.next()) |entity| {
        const ch = registry.get(components.CharacterControllerComponent, entity).?;
        character_controller.update(world, ch.handle, dt, character_controller.default_gravity_y);

        const transform = registry.get(components.TransformComponent, entity).?;
        transform.position = character_controller.getPosition(ch.handle);
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
