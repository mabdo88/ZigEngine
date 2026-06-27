const SystemDesc = @import("system.zig").SystemDesc;

const input_system = @import("input_system.zig");
const prefab_system = @import("../../../scene/prefab.zig");
const spawner_system = @import("../../../scene/spawner.zig");
const scene_system = @import("scene_system.zig");
const movement_system = @import("movement_system.zig");
const camera_system = @import("camera_system.zig");
const anim_player_system = @import("anim_player_system.zig");
const physics_sync_system = @import("physics_sync_system.zig");
const character_controller_system = @import("character_controller_system.zig");
const trigger_system = @import("trigger_system.zig");
const transform_system = @import("transform_system.zig");
const hierarchy_system = @import("hierarchy_system.zig");
const render_system = @import("render_system.zig");
const audio_system = @import("audio_system.zig");
const audio_3d_system = @import("audio_3d_system.zig");
const health_system = @import("../../../gameplay/health.zig");
const player_movement_system = @import("../../../gameplay/movement.zig");
const combat_system = @import("../../../gameplay/combat.zig");
const ability_system = @import("../../../gameplay/ability.zig");
const item_system = @import("../../../gameplay/item.zig");
const ai_system = @import("../../../gameplay/ai.zig");
const projectile_system = @import("../../../gameplay/projectile.zig");
const save_system = @import("../../../gameplay/save_system.zig");

pub const all_systems = [_]SystemDesc{
    .{ .name = "Input", .priority = -100, .create_fn = input_system.create, .update_fn = input_system.update, .destroy_fn = input_system.destroy },
    .{ .name = "Prefab", .priority = -10, .create_fn = prefab_system.create, .update_fn = prefab_system.update, .destroy_fn = prefab_system.destroy },
    .{ .name = "Scene", .priority = 0, .create_fn = scene_system.create, .update_fn = scene_system.update, .destroy_fn = scene_system.destroy },
    .{ .name = "Spawner", .priority = 1, .create_fn = spawner_system.create, .update_fn = spawner_system.update, .destroy_fn = spawner_system.destroy },
    .{ .name = "Movement", .priority = 2, .create_fn = movement_system.create, .update_fn = movement_system.update, .destroy_fn = movement_system.destroy },
    .{ .name = "Camera", .priority = 3, .create_fn = camera_system.create, .update_fn = camera_system.update, .destroy_fn = camera_system.destroy },
    .{ .name = "AnimPlayer", .priority = 10, .create_fn = anim_player_system.create, .update_fn = anim_player_system.update, .destroy_fn = anim_player_system.destroy },
    .{ .name = "PhysicsSync", .priority = 20, .create_fn = physics_sync_system.create, .update_fn = physics_sync_system.update, .destroy_fn = physics_sync_system.destroy },
    .{ .name = "CharacterController", .priority = 21, .create_fn = character_controller_system.create, .update_fn = character_controller_system.update, .destroy_fn = character_controller_system.destroy },
    .{ .name = "Trigger", .priority = 22, .create_fn = trigger_system.create, .update_fn = trigger_system.update, .destroy_fn = trigger_system.destroy },
    .{ .name = "Combat", .priority = 23, .create_fn = combat_system.create, .update_fn = combat_system.update, .destroy_fn = combat_system.destroy },
    .{ .name = "Ability", .priority = 24, .create_fn = ability_system.create, .update_fn = ability_system.update, .destroy_fn = ability_system.destroy },
    .{ .name = "Item", .priority = 25, .create_fn = item_system.create, .update_fn = item_system.update, .destroy_fn = item_system.destroy },
    .{ .name = "Projectile", .priority = 26, .create_fn = projectile_system.create, .update_fn = projectile_system.update, .destroy_fn = projectile_system.destroy },
    .{ .name = "Save", .priority = 27, .create_fn = save_system.create, .update_fn = save_system.update, .destroy_fn = save_system.destroy },
    .{ .name = "Transform", .priority = 50, .create_fn = transform_system.create, .update_fn = transform_system.update, .destroy_fn = transform_system.destroy },
    .{ .name = "Hierarchy", .priority = 60, .create_fn = hierarchy_system.create, .update_fn = hierarchy_system.update, .destroy_fn = hierarchy_system.destroy },
    .{ .name = "Render", .priority = 100, .create_fn = render_system.create, .update_fn = render_system.update, .destroy_fn = render_system.destroy },
    .{ .name = "Audio", .priority = 4, .create_fn = audio_system.create, .update_fn = audio_system.update, .destroy_fn = audio_system.destroy },
    .{ .name = "Audio3D", .priority = 61, .create_fn = audio_3d_system.create, .update_fn = audio_3d_system.update, .destroy_fn = audio_3d_system.destroy },
    .{ .name = "Health", .priority = 5, .create_fn = health_system.create, .update_fn = health_system.update, .destroy_fn = health_system.destroy },
    .{ .name = "PlayerMovement", .priority = 15, .create_fn = player_movement_system.create, .update_fn = player_movement_system.update, .destroy_fn = player_movement_system.destroy },
    .{ .name = "AI", .priority = 18, .create_fn = ai_system.create, .update_fn = ai_system.update, .destroy_fn = ai_system.destroy },
};
