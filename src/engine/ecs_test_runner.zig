const std = @import("std");

// Import registry which contains the ECS tests
comptime {
    _ = @import("registry.zig");
}
