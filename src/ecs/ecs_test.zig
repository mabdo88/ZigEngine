const std = @import("std");
// GPU-free test surface: pure ECS + math, no Vulkan linkage required.
comptime {
    _ = @import("Storage/registry.zig");
    _ = @import("System/cameraSystem.zig");
}
