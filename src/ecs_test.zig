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
    // Math
    _ = @import("engine/math.zig");
    // Resources
    _ = @import("resources/meshCache.zig");
}
