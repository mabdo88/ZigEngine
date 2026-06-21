const std = @import("std");
const World = @import("world.zig").World;
const LOG = std.log;

const Error = error{
    InitializationFailed,
};

pub const Engine = struct {
    gpa: std.heap.DebugAllocator(.{}) = .{},
    world: World = .{},

    pub fn init(self: *Engine) !void {
        LOG.info("Initializing ECS Engine...", .{});
        try self.world.init(self.gpa.allocator());
    }

    pub fn initVulkan(self: *Engine, title: ?[:0]const u8, width: u16, height: u16) !void {
        try self.world.initVulkan(title, width, height);
    }

    pub fn deinit(self: *Engine) void {
        self.world.deinit();
        const check = self.gpa.deinit();
        if (check == .leak) {
            LOG.warn("Memory leak detected during engine deinitialization", .{});
        } else {
            LOG.info("No memory leaks detected during engine deinitialization...Shutdown complete.", .{});
        }
    }

    pub fn run(self: *Engine, context: anytype, updateFn: anytype) !void {
        try self.world.run(context, updateFn);
    }

    pub fn registry(self: *Engine) *World {
        return &self.world;
    }
};
