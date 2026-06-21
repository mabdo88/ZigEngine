const std = @import("std");

// Import the ECS registry which contains all the tests
comptime {
    _ = @import("engine/registry.zig");
}
