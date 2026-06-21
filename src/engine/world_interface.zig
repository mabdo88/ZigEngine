const std = @import("std");

/// Returned by a world's update() each frame to signal intent to the engine.
/// The engine acts on the command after the frame completes — never mid-frame.
pub const WorldCommand = union(enum) {
    /// Keep running this world next frame.
    none,
    /// Switch to the world at the given index (0-based, registration order).
    /// The current world is deinit'd, the target world is lazily init'd.
    switchTo: usize,
    /// Cleanly exit the engine after this frame.
    exit,
};

/// Function table for a world implementation.
/// Generated once per world type via WorldHandle.init(T).
pub const WorldVTable = struct {
    init:        *const fn (ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!void,
    update:      *const fn (ptr: *anyopaque, dt: f32) WorldCommand,
    shouldClose: *const fn (ptr: *anyopaque) bool,
    deinit:      *const fn (ptr: *anyopaque) void,
};

/// A type-erased, runtime-dispatchable handle to a world instance.
/// Construct with WorldHandle.init(T, instance_ptr).
pub const WorldHandle = struct {
    ptr:    *anyopaque,
    vtable: *const WorldVTable,

    /// Bind a concrete world type T to its vtable.
    /// T must have: init, update, shouldClose, deinit with matching signatures.
    pub fn init(comptime T: type, instance: *T) WorldHandle {
        const vtable = comptime makeVTable(T);
        return .{ .ptr = instance, .vtable = vtable };
    }

    pub fn worldInit(self: WorldHandle, allocator: std.mem.Allocator) !void {
        return self.vtable.init(self.ptr, allocator);
    }
    pub fn update(self: WorldHandle, dt: f32) WorldCommand {
        return self.vtable.update(self.ptr, dt);
    }
    pub fn shouldClose(self: WorldHandle) bool {
        return self.vtable.shouldClose(self.ptr);
    }
    pub fn deinit(self: WorldHandle) void {
        self.vtable.deinit(self.ptr);
    }
};

/// Factory: creates and owns a world instance on demand.
/// The engine calls create() on switch-in and destroy() on switch-out.
/// This keeps worlds unallocated until they are actually needed.
pub const WorldFactory = struct {
    /// Allocates and initialises a new world instance.
    create:  *const fn (allocator: std.mem.Allocator) anyerror!WorldHandle,
    /// Deinits and frees the world instance returned by create().
    destroy: *const fn (handle: WorldHandle, allocator: std.mem.Allocator) void,
    /// Human-readable name for debugging / ImGui menus.
    name: []const u8,

    /// Generate a WorldFactory for a concrete type T.
    /// T must have: init, update, shouldClose, deinit, and be heap-allocatable.
    pub fn init(comptime T: type, comptime name: []const u8) WorldFactory {
        return .{
            .name = name,
            .create = struct {
                fn create(allocator: std.mem.Allocator) anyerror!WorldHandle {
                    const instance = try allocator.create(T);
                    instance.* = .{};
                    errdefer allocator.destroy(instance);
                    try instance.init(allocator);
                    return WorldHandle.init(T, instance);
                }
            }.create,
            .destroy = struct {
                fn destroy(handle: WorldHandle, allocator: std.mem.Allocator) void {
                    const instance: *T = @ptrCast(@alignCast(handle.ptr));
                    instance.deinit();
                    allocator.destroy(instance);
                }
            }.destroy,
        };
    }
};

/// Generates a comptime WorldVTable for type T by wrapping its methods.
fn makeVTable(comptime T: type) *const WorldVTable {
    return &.{
        .init = struct {
            fn init(ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!void {
                return @as(*T, @ptrCast(@alignCast(ptr))).init(allocator);
            }
        }.init,
        .update = struct {
            fn update(ptr: *anyopaque, dt: f32) WorldCommand {
                return @as(*T, @ptrCast(@alignCast(ptr))).update(dt);
            }
        }.update,
        .shouldClose = struct {
            fn shouldClose(ptr: *anyopaque) bool {
                return @as(*T, @ptrCast(@alignCast(ptr))).shouldClose();
            }
        }.shouldClose,
        .deinit = struct {
            fn deinit(ptr: *anyopaque) void {
                @as(*T, @ptrCast(@alignCast(ptr))).deinit();
            }
        }.deinit,
    };
}
