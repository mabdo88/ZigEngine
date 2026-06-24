const std = @import("std");

comptime {
    // Flecs wrapper
    _ = @import("engine/ecs/flecs.zig");
    // Components
    _ = @import("engine/ecs/components/components.zig");
    // Systems
    _ = @import("engine/ecs/systems/system.zig");
    _ = @import("engine/ecs/systems/camera_system.zig");
    _ = @import("engine/ecs/systems/movement_system.zig");
    _ = @import("engine/ecs/systems/input_system.zig");
    _ = @import("engine/ecs/systems/shared_state.zig");
    // Math
    _ = @import("engine/math.zig");
    // Resources
    _ = @import("resources/meshCache.zig");
}
