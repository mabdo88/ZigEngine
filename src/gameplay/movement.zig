//! Camera-relative player movement over a Jolt CharacterController, per
//! CLAUDE.md M9. Reads shared_state.player_input (populated by
//! input_system.zig from the same raw WASD/shift/space polls FlyCamInput
//! uses) and the world's CameraComponent for look direction, accel/friction
//! lerps PlayerMovementComponent.velocity toward a sprint-scaled target each
//! frame, then hands the result to character_controller.setVelocity —
//! CharacterControllerSystem (priority 21, after this system's priority 15)
//! is what actually steps Jolt and writes TransformComponent. Also tracks
//! ground-distance traveled and emits .footstep_event through the EventBus
//! when it crosses footstep_interval (no audio wired to that yet, see
//! event.zig's FootstepEventPayload doc comment).
const std = @import("std");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const components = @import("../engine/ecs/components/components.zig");
const SystemCreateCtx = @import("../engine/ecs/systems/system.zig").SystemCreateCtx;
const shared_state = @import("../engine/ecs/systems/shared_state.zig");
const math = @import("../engine/math.zig");
const character_controller = @import("../physics/character_controller.zig");

const min_move_speed_for_footsteps: f32 = 0.5;

fn moveToward(current: @Vector(3, f32), target: @Vector(3, f32), max_delta: f32) @Vector(3, f32) {
    const diff = target - current;
    const dist = @sqrt(@reduce(.Add, diff * diff));
    if (dist <= max_delta or dist == 0) return target;
    return current + diff * @as(@Vector(3, f32), @splat(max_delta / dist));
}

pub fn update(registry: *Registry, _: *anyopaque, dt: f32) anyerror!void {
    var cam_it = registry.Query(.{components.CameraComponent});
    const cam_entity = cam_it.next() orelse return;
    const camera = registry.get(components.CameraComponent, cam_entity).?;

    const look = camera.target - camera.position;
    var forward = @Vector(3, f32){ look[0], 0, look[2] };
    const forward_len_sq = @reduce(.Add, forward * forward);
    forward = if (forward_len_sq > 1e-10) math.normalize(forward) else @Vector(3, f32){ 0, 0, 1 };
    const right = math.normalize(math.cross(forward, @Vector(3, f32){ 0, 1, 0 }));

    const in = shared_state.player_input;

    var it = registry.Query(.{ components.PlayerMovementComponent, components.CharacterControllerComponent });
    while (it.next()) |entity| {
        const pmc = registry.get(components.PlayerMovementComponent, entity).?;
        const ch = registry.get(components.CharacterControllerComponent, entity).?;

        var wish = forward * @as(@Vector(3, f32), @splat(in.move_forward)) +
            right * @as(@Vector(3, f32), @splat(in.move_right));
        const wish_len_sq = @reduce(.Add, wish * wish);
        const is_moving = wish_len_sq > 1e-10;
        if (is_moving) wish = math.normalize(wish);

        const target_speed = pmc.walk_speed * (if (in.sprint) pmc.sprint_multiplier else 1.0);
        const target_velocity = wish * @as(@Vector(3, f32), @splat(target_speed));
        const rate = if (is_moving) pmc.acceleration else pmc.friction;
        pmc.velocity = moveToward(pmc.velocity, target_velocity, rate * dt);

        const current_v = character_controller.getVelocity(ch.handle);
        character_controller.setVelocity(ch.handle, .{ pmc.velocity[0], current_v[1], pmc.velocity[2] });

        const grounded = character_controller.isGrounded(ch.handle);
        if (in.jump_pressed and grounded) {
            character_controller.jump(ch.handle, pmc.jump_speed);
        }

        const speed = @sqrt(@reduce(.Add, pmc.velocity * pmc.velocity));
        if (grounded and speed >= min_move_speed_for_footsteps) {
            pmc.footstep_distance += speed * dt;
            if (pmc.footstep_distance >= pmc.footstep_interval) {
                pmc.footstep_distance -= pmc.footstep_interval;
                registry.events.emit(.{ .footstep_event = .{ .entity = entity } });
            }
        } else {
            pmc.footstep_distance = 0;
        }
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

const physics_world = @import("../physics/physics_world.zig");

test "moving forward accelerates velocity toward target speed" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();

    const floor = try reg.create();
    _ = try physics_world.spawnBoxBody(&reg, &world, floor, .{ 50, 1, 50 }, 0, .{ 0, -1, 0 }, .static, true, false);

    const cam = try reg.create();
    try reg.add(cam, components.CameraComponent{ .position = .{ 0, 0, 0 }, .target = .{ 0, 0, 1 } });

    const player = try reg.create();
    try character_controller.spawnCharacter(&reg, &world, player, 0.5, 1.8, .{ 0, 0.05, 0 });
    defer character_controller.despawnCharacter(&reg, &world, player);
    try reg.add(player, components.PlayerMovementComponent{ .walk_speed = 4.0, .acceleration = 20.0 });

    shared_state.player_input = .{ .move_forward = 1.0 };
    defer shared_state.player_input = .{};

    try update(&reg, undefined, 1.0 / 60.0);

    const pmc = reg.get(components.PlayerMovementComponent, player).?;
    try std.testing.expect(pmc.velocity[2] > 0);
    try std.testing.expect(pmc.velocity[2] <= 4.0);
}

test "sprint multiplier raises the target speed velocity accelerates toward" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();

    const cam = try reg.create();
    try reg.add(cam, components.CameraComponent{ .position = .{ 0, 0, 0 }, .target = .{ 0, 0, 1 } });

    const player = try reg.create();
    try character_controller.spawnCharacter(&reg, &world, player, 0.5, 1.8, .{ 0, 0.05, 0 });
    defer character_controller.despawnCharacter(&reg, &world, player);
    try reg.add(player, components.PlayerMovementComponent{ .walk_speed = 4.0, .sprint_multiplier = 2.0, .acceleration = 1000.0 });

    shared_state.player_input = .{ .move_forward = 1.0, .sprint = true };
    defer shared_state.player_input = .{};

    try update(&reg, undefined, 1.0 / 60.0);

    const pmc = reg.get(components.PlayerMovementComponent, player).?;
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), pmc.velocity[2], 0.01);
}

test "releasing input decelerates velocity toward zero via friction" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();

    const cam = try reg.create();
    try reg.add(cam, components.CameraComponent{ .position = .{ 0, 0, 0 }, .target = .{ 0, 0, 1 } });

    const player = try reg.create();
    try character_controller.spawnCharacter(&reg, &world, player, 0.5, 1.8, .{ 0, 0.05, 0 });
    defer character_controller.despawnCharacter(&reg, &world, player);
    try reg.add(player, components.PlayerMovementComponent{ .friction = 1000.0, .velocity = .{ 0, 0, 4.0 } });

    shared_state.player_input = .{};

    try update(&reg, undefined, 1.0 / 60.0);

    const pmc = reg.get(components.PlayerMovementComponent, player).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), pmc.velocity[2], 0.01);
}

test "jump only applies vertical velocity while grounded" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();

    const floor = try reg.create();
    _ = try physics_world.spawnBoxBody(&reg, &world, floor, .{ 50, 1, 50 }, 0, .{ 0, -1, 0 }, .static, true, false);

    const cam = try reg.create();
    try reg.add(cam, components.CameraComponent{ .position = .{ 0, 0, 0 }, .target = .{ 0, 0, 1 } });

    const player = try reg.create();
    try character_controller.spawnCharacter(&reg, &world, player, 0.5, 1.8, .{ 0, 0.05, 0 });
    defer character_controller.despawnCharacter(&reg, &world, player);
    try reg.add(player, components.PlayerMovementComponent{ .jump_speed = 5.0 });
    const handle = reg.get(components.CharacterControllerComponent, player).?.handle;

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        world.step(1.0 / 60.0);
        character_controller.update(&world, handle, 1.0 / 60.0, character_controller.default_gravity_y);
    }
    try std.testing.expect(character_controller.isGrounded(handle));

    shared_state.player_input = .{ .jump_pressed = true };
    defer shared_state.player_input = .{};

    try update(&reg, undefined, 1.0 / 60.0);

    const v = character_controller.getVelocity(handle);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), v[1], 0.01);
}

test "footstep_event fires once per footstep_interval while grounded and moving" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();

    const floor = try reg.create();
    _ = try physics_world.spawnBoxBody(&reg, &world, floor, .{ 50, 1, 50 }, 0, .{ 0, -1, 0 }, .static, true, false);

    const cam = try reg.create();
    try reg.add(cam, components.CameraComponent{ .position = .{ 0, 0, 0 }, .target = .{ 0, 0, 1 } });

    const player = try reg.create();
    try character_controller.spawnCharacter(&reg, &world, player, 0.5, 1.8, .{ 0, 0.05, 0 });
    defer character_controller.despawnCharacter(&reg, &world, player);
    try reg.add(player, components.PlayerMovementComponent{
        .velocity = .{ 0, 0, 2.0 },
        .footstep_interval = 1.0,
        .footstep_distance = 0.99,
    });
    const handle = reg.get(components.CharacterControllerComponent, player).?.handle;

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        world.step(1.0 / 60.0);
        character_controller.update(&world, handle, 1.0 / 60.0, character_controller.default_gravity_y);
    }

    var footstep_count: u32 = 0;
    const Counter = struct {
        count: *u32,
        fn cb(ctx: *anyopaque, _: @import("../engine/ecs/event.zig").EventPayload) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.count.* += 1;
        }
    };
    var counter = Counter{ .count = &footstep_count };
    try reg.events.subscribe(.footstep_event, &counter, Counter.cb);

    shared_state.player_input = .{ .move_forward = 1.0 };
    defer shared_state.player_input = .{};

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectEqual(@as(u32, 1), footstep_count);
}

test "footstep_distance resets when not moving" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var world = physics_world.PhysicsWorld.init(allocator);
    defer world.deinit();

    const cam = try reg.create();
    try reg.add(cam, components.CameraComponent{ .position = .{ 0, 0, 0 }, .target = .{ 0, 0, 1 } });

    const player = try reg.create();
    try character_controller.spawnCharacter(&reg, &world, player, 0.5, 1.8, .{ 0, 0.05, 0 });
    defer character_controller.despawnCharacter(&reg, &world, player);
    try reg.add(player, components.PlayerMovementComponent{ .footstep_distance = 0.9 });

    shared_state.player_input = .{};
    defer shared_state.player_input = .{};

    try update(&reg, undefined, 1.0 / 60.0);

    const pmc = reg.get(components.PlayerMovementComponent, player).?;
    try std.testing.expectEqual(@as(f32, 0.0), pmc.footstep_distance);
}
