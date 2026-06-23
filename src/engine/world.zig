const std = @import("std");
const Registry = @import("ecs/entity/registry.zig").Registry;
const SystemManager = @import("ecs/systems/system.zig").SystemManager;
const SystemCreateCtx = @import("ecs/systems/system.zig").SystemCreateCtx;
const all_systems = @import("ecs/systems/all_systems.zig").all_systems;
const config_mod = @import("config.zig");
const window = @import("../platform/window.zig");
const render_system = @import("ecs/systems/render_system.zig");

pub const VulkanWorld = struct {
    registry: Registry,
    system_manager: SystemManager,
    last_time: f64,

    pub fn init(self: *VulkanWorld, allocator: std.mem.Allocator, config: config_mod.Config) !void {
        self.* = VulkanWorld{
            .registry = Registry.init(allocator),
            .system_manager = undefined,
            .last_time = 0,
        };

        var create_ctx = SystemCreateCtx{
            .allocator = allocator,
            .registry = &self.registry,
            .config = &config,
        };

        self.system_manager = try SystemManager.init(allocator, &all_systems, &create_ctx);

        self.last_time = window.getTime();
    }

    pub fn update(self: *VulkanWorld, dt: f32) !void {
        window.pollEvents();
        try self.system_manager.update(&self.registry, dt);
    }

    pub fn shouldClose(self: *VulkanWorld) bool {
        _ = self;
        return render_system.RenderSystemState.shouldClose();
    }

    pub fn deltaTime(self: *VulkanWorld) f32 {
        const now = window.getTime();
        const dt: f32 = @floatCast(now - self.last_time);
        self.last_time = now;
        return dt;
    }

    pub fn deinit(self: *VulkanWorld) void {
        self.system_manager.deinit(&self.registry);
        self.registry.deinit();
    }
};
