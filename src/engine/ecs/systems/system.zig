const std = @import("std");
const flecs = @import("../flecs.zig");
const components = @import("../components/components.zig");
const MeshCache = @import("../../../resources/meshCache.zig").MeshCache;
const Config = @import("../../config.zig").Config;

pub const SharedContext = struct {
    world: *flecs.World,
    mesh_cache: *MeshCache,
    config: *const Config,
    allocator: std.mem.Allocator,
    component_ids: components.ComponentIds,
};
