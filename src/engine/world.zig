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
    scratch_arena: std.heap.ArenaAllocator,

    pub fn init(self: *VulkanWorld, allocator: std.mem.Allocator, config: config_mod.Config) !void {
        self.* = VulkanWorld{
            .registry = Registry.init(allocator),
            .system_manager = undefined,
            .scratch_arena = std.heap.ArenaAllocator.init(allocator),
        };

        var create_ctx = SystemCreateCtx{
            .allocator = allocator,
            .registry = &self.registry,
            .config = &config,
            .scratch = &self.scratch_arena,
        };

        self.system_manager = try SystemManager.init(allocator, &all_systems, &create_ctx);
    }

    pub fn update(self: *VulkanWorld, dt: f32) !void {
        _ = self.scratch_arena.reset(.retain_capacity);
        window.pollEvents();
        try self.system_manager.update(&self.registry, dt);
    }

    pub fn shouldClose(self: *VulkanWorld) bool {
        _ = self;
        return render_system.RenderSystemState.shouldClose();
    }

    pub fn deinit(self: *VulkanWorld) void {
        self.system_manager.deinit(&self.registry);
        self.registry.deinit();
        self.scratch_arena.deinit();
    }
};
