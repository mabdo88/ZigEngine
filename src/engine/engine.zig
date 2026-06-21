const std = @import("std");
const wi = @import("world_interface.zig");
pub const WorldFactory = wi.WorldFactory;
pub const WorldCommand = wi.WorldCommand;

const MAX_WORLDS = 16;

pub const Engine = struct {
    gpa: std.heap.DebugAllocator(.{}) = .{},
    factories: [MAX_WORLDS]?wi.WorldFactory = [_]?wi.WorldFactory{null} ** MAX_WORLDS,
    factory_count: usize = 0,

    pub fn init(self: *Engine) void {
        std.log.info("Initializing ECS Engine...", .{});
        _ = self;
    }

    /// Register a world factory. Worlds are created lazily on first use.
    /// Registration order determines the index passed to switchTo.
    pub fn addWorld(self: *Engine, factory: wi.WorldFactory) void {
        std.debug.assert(self.factory_count < MAX_WORLDS);
        self.factories[self.factory_count] = factory;
        self.factory_count += 1;
        std.log.info("Engine: registered world '{s}' at index {d}", .{ factory.name, self.factory_count - 1 });
    }

    /// Start the engine with the world at start_index.
    /// Worlds drive switching via WorldCommand returned from update().
    pub fn run(self: *Engine, start_index: usize) !void {
        const allocator = self.gpa.allocator();
        var current_idx = start_index;

        while (true) {
            const factory = self.factories[current_idx] orelse {
                std.log.err("Engine: no world registered at index {d}", .{current_idx});
                return error.WorldNotFound;
            };

            std.log.info("Engine: starting world '{s}'", .{factory.name});
            var handle = try factory.create(allocator);

            var next_idx: ?usize = null;
            var should_exit = false;

            // Frame loop for the active world
            while (!handle.shouldClose() and !should_exit and next_idx == null) {
                const cmd = handle.update(0.016); // dt placeholder — world owns its own timer
                switch (cmd) {
                    .none => {},
                    .switchTo => |idx| next_idx = idx,
                    .exit => should_exit = true,
                }
            }

            std.log.info("Engine: stopping world '{s}'", .{factory.name});
            factory.destroy(handle, allocator);

            if (should_exit or next_idx == null) break;
            current_idx = next_idx.?;
        }
    }

    pub fn deinit(self: *Engine) void {
        const check = self.gpa.deinit();
        if (check == .leak) {
            std.log.warn("Memory leak detected during engine deinitialization", .{});
        } else {
            std.log.info("No memory leaks detected...Shutdown complete.", .{});
        }
    }
};
