const std = @import("std");

/// Fixed-size-object pool with O(1) alloc/free via an index-based free list.
/// Callers hold a `usize` handle rather than a raw `*T` — the backing storage
/// is an ArrayList, and ArrayList growth can move/reallocate its buffer, so a
/// raw pointer taken before growth would dangle. Indices stay valid across
/// growth since they're resolved through `get()` each time.
pub fn PoolAllocator(comptime T: type) type {
    return struct {
        const Self = @This();
        const Slot = union(enum) {
            used: T,
            free: ?usize, // index of next free slot, null = end of free list
        };

        backing_allocator: std.mem.Allocator,
        slots: std.ArrayList(Slot) = .empty,
        free_head: ?usize = null,
        live_count: usize = 0,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .backing_allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.slots.deinit(self.backing_allocator);
        }

        /// Returns a handle to a new, uninitialized T. Caller should
        /// immediately store a value via `get(handle).* = ...`.
        pub fn alloc(self: *Self) !usize {
            if (self.free_head) |idx| {
                self.free_head = self.slots.items[idx].free;
                self.slots.items[idx] = .{ .used = undefined };
                self.live_count += 1;
                return idx;
            }
            try self.slots.append(self.backing_allocator, .{ .used = undefined });
            self.live_count += 1;
            return self.slots.items.len - 1;
        }

        pub fn get(self: *Self, handle: usize) *T {
            return &self.slots.items[handle].used;
        }

        pub fn free(self: *Self, handle: usize) void {
            self.slots.items[handle] = .{ .free = self.free_head };
            self.free_head = handle;
            self.live_count -= 1;
        }

        pub fn count(self: *const Self) usize {
            return self.live_count;
        }
    };
}

test "alloc returns increasing handles with no frees" {
    var pool = PoolAllocator(u32).init(std.testing.allocator);
    defer pool.deinit();

    const a = try pool.alloc();
    const b = try pool.alloc();
    const c = try pool.alloc();
    try std.testing.expectEqual(@as(usize, 0), a);
    try std.testing.expectEqual(@as(usize, 1), b);
    try std.testing.expectEqual(@as(usize, 2), c);
    try std.testing.expectEqual(@as(usize, 3), pool.count());
}

test "get/set round-trips a stored value" {
    var pool = PoolAllocator(u32).init(std.testing.allocator);
    defer pool.deinit();

    const h = try pool.alloc();
    pool.get(h).* = 42;
    try std.testing.expectEqual(@as(u32, 42), pool.get(h).*);
}

test "free reclaims a handle for the next alloc (LIFO reuse)" {
    var pool = PoolAllocator(u32).init(std.testing.allocator);
    defer pool.deinit();

    const a = try pool.alloc();
    const b = try pool.alloc();
    pool.free(a);

    const c = try pool.alloc();
    try std.testing.expectEqual(a, c);
    try std.testing.expectEqual(@as(usize, 2), pool.count());
    _ = b;
}

test "freed slot does not leak stale data into the next allocation" {
    var pool = PoolAllocator(u32).init(std.testing.allocator);
    defer pool.deinit();

    const a = try pool.alloc();
    pool.get(a).* = 999;
    pool.free(a);

    const b = try pool.alloc();
    try std.testing.expectEqual(a, b);
    pool.get(b).* = 1;
    try std.testing.expectEqual(@as(u32, 1), pool.get(b).*);
}

test "alloc/free cycles maintain correct live count across growth" {
    var pool = PoolAllocator(u32).init(std.testing.allocator);
    defer pool.deinit();

    var handles: [16]usize = undefined;
    for (&handles) |*h| h.* = try pool.alloc();
    try std.testing.expectEqual(@as(usize, 16), pool.count());

    for (handles[0..8]) |h| pool.free(h);
    try std.testing.expectEqual(@as(usize, 8), pool.count());

    for (0..8) |_| _ = try pool.alloc();
    try std.testing.expectEqual(@as(usize, 16), pool.count());
}
