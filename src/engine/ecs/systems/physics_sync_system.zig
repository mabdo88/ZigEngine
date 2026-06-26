//! Steps Jolt each fixed tick and writes resulting positions/rotations back
//! into TransformComponent for every dynamic PhysicsBodyComponent. Static
//! bodies never move so they're skipped — also avoids calling into Jolt for
//! entities that don't need it every frame.
const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;
const physics_world = @import("../../../physics/physics_world.zig");
const physics_shared = @import("../../../physics/physics_shared.zig");

pub const PhysicsSyncSystemState = struct {
    world: physics_world.PhysicsWorld,

    pub fn update(self: *PhysicsSyncSystemState, registry: *Registry, dt: f32) anyerror!void {
        self.world.step(dt);

        var it = registry.Query(.{ components.PhysicsBodyComponent, components.TransformComponent });
        while (it.next()) |entity| {
            const body = registry.get(components.PhysicsBodyComponent, entity).?;
            if (body.is_static) continue;

            const transform = registry.get(components.TransformComponent, entity).?;
            var pos: [3]f32 = undefined;
            physics_world.jolt.jolt_get_position(self.world.ctx, body.body_id, &pos);
            transform.position = .{ pos[0], pos[1], pos[2] };

            var rot: [4]f32 = undefined;
            physics_world.jolt.jolt_get_rotation(self.world.ctx, body.body_id, &rot);
            transform.rotation = physics_world.quatToEuler(rot[0], rot[1], rot[2], rot[3]);
        }
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *PhysicsSyncSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(PhysicsSyncSystemState);
    state.* = .{ .world = physics_world.PhysicsWorld.init(ctx.allocator) };
    physics_shared.world = &state.world;
    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *PhysicsSyncSystemState = @ptrCast(@alignCast(ctx));
    physics_shared.world = null;
    state.world.deinit();
    allocator.destroy(state);
}

const collision_layers = @import("../../../physics/collision_layers.zig");
const raycast = @import("../../../physics/raycast.zig");
const character_controller = @import("../../../physics/character_controller.zig");

test "a dynamic box falls under gravity and comes to rest on a static floor" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var state = PhysicsSyncSystemState{ .world = physics_world.PhysicsWorld.init(allocator) };
    defer state.world.deinit();

    const floor = try reg.create();
    try reg.add(floor, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    _ = try physics_world.spawnBoxBody(&reg, &state.world, floor, .{ 50, 1, 50 }, 0, .{ 0, -1, 0 }, .static, true, false);

    const box = try reg.create();
    try reg.add(box, components.TransformComponent{ .position = .{ 0, 5, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    _ = try physics_world.spawnBoxBody(&reg, &state.world, box, .{ 0.5, 0.5, 0.5 }, 1.0, .{ 0, 5, 0 }, .player, false, false);

    var i: usize = 0;
    while (i < 120) : (i += 1) {
        try state.update(&reg, 1.0 / 60.0);
    }

    const transform = reg.get(components.TransformComponent, box).?;
    // Box half-height 0.5 resting on floor top at y=0 settles around y=0.5.
    try std.testing.expect(transform.position[1] > 0.3 and transform.position[1] < 0.7);
}

test "raycast straight down hits the static floor and resolves back to its entity" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();

    const floor = try reg.create();
    _ = try physics_world.spawnBoxBody(&reg, &world, floor, .{ 50, 1, 50 }, 0, .{ 0, -1, 0 }, .static, true, false);
    world.step(1.0 / 60.0); // let the broadphase register the new body

    const hit = raycast.raycast(&world, .{ 0, 10, 0 }, .{ 0, -1, 0 }, 100.0);
    try std.testing.expect(hit != null);
    try std.testing.expectEqual(floor, hit.?.entity);
}

test "a dynamic body passing through a sensor fires enter then exit" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    const trigger_mod = @import("../../../physics/trigger.zig");

    var state = PhysicsSyncSystemState{ .world = physics_world.PhysicsWorld.init(allocator) };
    defer state.world.deinit();

    const sensor = try reg.create();
    try trigger_mod.spawnBoxTrigger(&reg, &state.world, sensor, .{ 2, 2, 2 }, .{ 0, 0, 0 });

    const falling = try reg.create();
    try reg.add(falling, components.TransformComponent{ .position = .{ 0, 10, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    _ = try physics_world.spawnBoxBody(&reg, &state.world, falling, .{ 0.2, 0.2, 0.2 }, 1.0, .{ 0, 10, 0 }, .player, false, false);
    physics_world.jolt.jolt_set_linear_velocity(state.world.ctx, reg.get(components.PhysicsBodyComponent, falling).?.body_id, 0, -20, 0);

    var saw_enter = false;
    var saw_exit = false;
    var i: usize = 0;
    while (i < 90) : (i += 1) {
        try state.update(&reg, 1.0 / 60.0);
        var event: physics_world.jolt.JoltTriggerEvent = undefined;
        while (physics_world.jolt.jolt_poll_trigger_event(state.world.ctx, &event)) {
            if (event.is_enter) saw_enter = true else saw_exit = true;
        }
    }

    try std.testing.expect(saw_enter);
    try std.testing.expect(saw_exit);
}

test "character controller falls under gravity and lands on the ground" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();

    const floor = try reg.create();
    _ = try physics_world.spawnBoxBody(&reg, &world, floor, .{ 50, 1, 50 }, 0, .{ 0, -1, 0 }, .static, true, false);

    const player = try reg.create();
    try character_controller.spawnCharacter(&reg, &world, player, 0.5, 1.8, .{ 0, 5, 0 });
    const handle = reg.get(components.CharacterControllerComponent, player).?.handle;
    defer character_controller.despawnCharacter(&reg, &world, player);

    var i: usize = 0;
    while (i < 120) : (i += 1) {
        world.step(1.0 / 60.0);
        character_controller.update(&world, handle, 1.0 / 60.0, character_controller.default_gravity_y);
    }

    try std.testing.expect(character_controller.isGrounded(handle));
}
