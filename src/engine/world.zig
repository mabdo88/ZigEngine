const std = @import("std");
const flecs = @import("ecs/flecs.zig");
const components = @import("ecs/components/components.zig");
const all_systems = @import("ecs/systems/all_systems.zig");
const SharedContext = @import("ecs/systems/system.zig").SharedContext;
const config_mod = @import("config.zig");
const window = @import("../platform/window.zig");
const render_system = @import("ecs/systems/render_system.zig");
const MeshCache = @import("../resources/meshCache.zig").MeshCache;

pub const VulkanWorld = struct {
    world: flecs.World,
    mesh_cache: MeshCache,
    shared_ctx: SharedContext = undefined,
    system_handles: all_systems.SystemHandles = .{},
    config: config_mod.Config = undefined,
    last_time: f64,
    interp_alpha: f32 = 0.0,

    pub fn init(self: *VulkanWorld, allocator: std.mem.Allocator, config: config_mod.Config) !void {
        self.* = VulkanWorld{
            .world = flecs.World.init(),
            .mesh_cache = MeshCache.init(allocator),
            .config = config,
            .last_time = 0,
        };

        const ids = components.registerAll(&self.world);

        self.shared_ctx = .{
            .world = &self.world,
            .mesh_cache = &self.mesh_cache,
            .config = &self.config,
            .allocator = allocator,
            .component_ids = ids,
        };

        self.system_handles = try all_systems.registerAll(&self.world, &self.shared_ctx);

        self.last_time = window.getTime();
    }

    pub fn fixedUpdate(self: *VulkanWorld, dt: f32) !void {
        _ = self.world.progress(dt);
    }

    pub fn renderUpdate(self: *VulkanWorld, alpha: f32) !void {
        self.interp_alpha = alpha;
    }

    pub fn shouldClose(self: *VulkanWorld) bool {
        _ = self;
        return render_system.RenderSystemState.shouldClose();
    }

    pub fn getRealDeltaTime(self: *VulkanWorld) f32 {
        window.pollEvents();
        const now = window.getTime();
        const dt: f32 = @floatCast(now - self.last_time);
        self.last_time = now;
        return dt;
    }

    pub fn deinit(self: *VulkanWorld) void {
        self.world.deinit();
        all_systems.destroyAll(&self.shared_ctx, self.system_handles);
        self.mesh_cache.deinit();
    }
};
