const std = @import("std");

comptime {
    // Core ECS
    _ = @import("engine/ecs/entity/registry.zig");
    _ = @import("engine/ecs/entity/componentStorage.zig");
    _ = @import("engine/ecs/event.zig");
    // Systems
    _ = @import("engine/ecs/systems/system.zig");
    _ = @import("engine/ecs/systems/camera_system.zig");
    _ = @import("engine/ecs/systems/movement_system.zig");
    _ = @import("engine/ecs/systems/input_system.zig");
    _ = @import("engine/ecs/systems/shared_state.zig");
    _ = @import("engine/ecs/systems/transform_system.zig");
    _ = @import("engine/ecs/systems/hierarchy_system.zig");
    // Math
    _ = @import("engine/math.zig");
    // Timer
    _ = @import("engine/timer.zig");
    // Logging
    _ = @import("engine/log.zig");
    // Assertions
    _ = @import("engine/assert.zig");
    // Filesystem
    _ = @import("engine/fs.zig");
    // Pool allocator
    _ = @import("engine/pool.zig");
    // Generic async asset manager
    _ = @import("engine/assets.zig");
    // OBJ mesh import
    _ = @import("resources/objLoader.zig");
    // JSON material loader
    _ = @import("resources/materialLoader.zig");
    // Hot reload file watcher
    _ = @import("engine/hotreload.zig");
    // Job system
    _ = @import("engine/jobs.zig");
    // INI config loader
    _ = @import("engine/ini.zig");
    // UUID
    _ = @import("engine/uuid.zig");
    // Input edge detection
    _ = @import("engine/input.zig");
    // Resources
    _ = @import("resources/meshCache.zig");
    // Skeletal animation
    _ = @import("animation/skeleton.zig");
    _ = @import("animation/clip.zig");
    _ = @import("animation/anim_cache.zig");
    _ = @import("animation/blend_tree.zig");
    _ = @import("animation/state_machine.zig");
    _ = @import("engine/ecs/systems/anim_player_system.zig");
}
