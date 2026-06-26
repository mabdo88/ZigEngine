const std = @import("std");
const log = @import("log.zig");

fn hasDeinit(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, "deinit"),
        else => false,
    };
}

/// Generic handle/ref-counted async asset cache, deduped by path.
///
/// Concurrency contract: `request`/`release`/`get`/`getState` must only be
/// called from one thread (the "owner" — typically the main/game thread).
/// Background load threads only ever touch a slot's `state` (atomic) and
/// `value` (written once, before the state transition that publishes it) —
/// they never touch `ref_count`/`generation`/the free list, so there's no
/// data race between the owner thread's bookkeeping and the load thread's
/// single write-then-publish.
///
/// This spawns one std.Thread per in-flight load rather than using
/// jobs.zig's JobSystem: JobSystem's Io.Group.await blocks the calling
/// thread until the whole batch finishes, which is exactly wrong for
/// "kick off a load, poll for completion next frame without blocking" —
/// there's no non-blocking poll on an Io.Future in this Zig master's std.Io.
/// JobSystem remains the right tool for batch CPU work where blocking the
/// caller until the batch completes is actually fine.
pub fn AssetManager(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Handle = struct {
            index: u32 = 0,
            generation: u32 = 0,
        };

        pub const State = enum(u8) { unloaded, loading, ready, failed };
        pub const LoadFn = *const fn (std.mem.Allocator, []const u8) anyerror!T;

        const Slot = struct {
            value: T = undefined,
            generation: u32 = 0,
            ref_count: u32 = 0,
            state: std.atomic.Value(State) = .init(.unloaded),
            path_hash: u64 = 0,
            load_thread: ?std.Thread = null,
        };

        allocator: std.mem.Allocator,
        slots: std.ArrayList(Slot) = .empty,
        free_list: std.ArrayList(u32) = .empty,
        path_index: std.AutoHashMapUnmanaged(u64, u32) = .empty,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            for (self.slots.items) |*slot| {
                if (slot.load_thread) |t| t.join();
                if (slot.state.load(.acquire) == .ready) {
                    if (comptime hasDeinit(T)) slot.value.deinit(self.allocator);
                }
            }
            self.slots.deinit(self.allocator);
            self.free_list.deinit(self.allocator);
            self.path_index.deinit(self.allocator);
        }

        const LoadCtx = struct {
            slot: *Slot,
            allocator: std.mem.Allocator,
            path: []u8,
            loadFn: LoadFn,

            fn run(ctx: *LoadCtx) void {
                defer ctx.allocator.destroy(ctx);
                defer ctx.allocator.free(ctx.path);

                const result = ctx.loadFn(ctx.allocator, ctx.path) catch |err| {
                    log.err(@src(), "asset load failed for '{s}': {s}", .{ ctx.path, @errorName(err) });
                    ctx.slot.state.store(.failed, .release);
                    return;
                };
                ctx.slot.value = result;
                ctx.slot.state.store(.ready, .release);
            }
        };

        /// Requests an asset by path. If already requested (loading, ready,
        /// or failed) for this exact path, bumps the ref count and returns
        /// the existing handle immediately. Otherwise allocates a slot,
        /// spawns a background thread running `loadFn(allocator, path)`, and
        /// returns a handle with state == .loading.
        pub fn request(self: *Self, path: []const u8, loadFn: LoadFn) !Handle {
            const path_hash = std.hash.Wyhash.hash(0, path);
            if (self.path_index.get(path_hash)) |idx| {
                self.slots.items[idx].ref_count += 1;
                return .{ .index = idx, .generation = self.slots.items[idx].generation };
            }

            const index: u32 = if (self.free_list.pop()) |i| i else blk: {
                try self.slots.append(self.allocator, .{});
                break :blk @intCast(self.slots.items.len - 1);
            };
            const slot = &self.slots.items[index];
            const generation = slot.generation;
            slot.* = .{
                .generation = generation,
                .ref_count = 1,
                .path_hash = path_hash,
                .state = .init(.loading),
            };
            try self.path_index.put(self.allocator, path_hash, index);

            const ctx = try self.allocator.create(LoadCtx);
            errdefer self.allocator.destroy(ctx);
            const path_copy = try self.allocator.dupe(u8, path);
            errdefer self.allocator.free(path_copy);
            ctx.* = .{ .slot = slot, .allocator = self.allocator, .path = path_copy, .loadFn = loadFn };
            slot.load_thread = try std.Thread.spawn(.{}, LoadCtx.run, .{ctx});

            return .{ .index = index, .generation = generation };
        }

        /// Decrements the ref count; frees the slot (joining its load thread
        /// and calling T.deinit if present) once it reaches zero.
        pub fn release(self: *Self, handle: Handle) !void {
            if (handle.index >= self.slots.items.len) return;
            const slot = &self.slots.items[handle.index];
            if (slot.generation != handle.generation or slot.ref_count == 0) return;

            slot.ref_count -= 1;
            if (slot.ref_count > 0) return;

            if (slot.load_thread) |t| {
                t.join();
                slot.load_thread = null;
            }
            if (comptime hasDeinit(T)) {
                if (slot.state.load(.acquire) == .ready) {
                    slot.value.deinit(self.allocator);
                }
            }
            _ = self.path_index.remove(slot.path_hash);
            slot.generation += 1;
            slot.state.store(.unloaded, .release);
            try self.free_list.append(self.allocator, handle.index);
        }

        pub fn getState(self: *Self, handle: Handle) State {
            if (handle.index >= self.slots.items.len) return .unloaded;
            const slot = &self.slots.items[handle.index];
            if (slot.generation != handle.generation) return .unloaded;
            return slot.state.load(.acquire);
        }

        /// Returns the loaded value, or null if not ready (still loading,
        /// failed, or a stale/unloaded handle).
        pub fn get(self: *Self, handle: Handle) ?*T {
            if (handle.index >= self.slots.items.len) return null;
            const slot = &self.slots.items[handle.index];
            if (slot.generation != handle.generation) return null;
            if (slot.state.load(.acquire) != .ready) return null;
            return &slot.value;
        }
    };
}

fn waitUntilLoaded(comptime T: type, mgr: *AssetManager(T), handle: AssetManager(T).Handle) AssetManager(T).State {
    while (true) {
        const s = mgr.getState(handle);
        if (s != .loading) return s;
        std.Thread.yield() catch {};
    }
}

fn loadOk(allocator: std.mem.Allocator, path: []const u8) anyerror!u32 {
    _ = allocator;
    return @intCast(path.len);
}

fn loadFails(allocator: std.mem.Allocator, path: []const u8) anyerror!u32 {
    _ = allocator;
    _ = path;
    return error.SimulatedLoadFailure;
}

const DeinitTracker = struct {
    value: u32,
    freed: *bool,

    fn deinit(self: DeinitTracker, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.freed.* = true;
    }
};

var deinit_tracker_freed_storage: bool = false;

fn loadDeinitTracker(allocator: std.mem.Allocator, path: []const u8) anyerror!DeinitTracker {
    _ = allocator;
    _ = path;
    deinit_tracker_freed_storage = false;
    return .{ .value = 1, .freed = &deinit_tracker_freed_storage };
}

test "request loads asynchronously and get() returns the value once ready" {
    var mgr = AssetManager(u32).init(std.testing.allocator);
    defer mgr.deinit();

    const handle = try mgr.request("abcde", loadOk);
    const final_state = waitUntilLoaded(u32, &mgr, handle);

    try std.testing.expectEqual(AssetManager(u32).State.ready, final_state);
    try std.testing.expectEqual(@as(u32, 5), mgr.get(handle).?.*);
}

test "a failed load reports .failed and get() returns null" {
    var mgr = AssetManager(u32).init(std.testing.allocator);
    defer mgr.deinit();

    const handle = try mgr.request("anything", loadFails);
    const final_state = waitUntilLoaded(u32, &mgr, handle);

    try std.testing.expectEqual(AssetManager(u32).State.failed, final_state);
    try std.testing.expect(mgr.get(handle) == null);
}

test "requesting the same path twice dedups to the same handle and ref-counts" {
    var mgr = AssetManager(u32).init(std.testing.allocator);
    defer mgr.deinit();

    const h1 = try mgr.request("shared/path", loadOk);
    const h2 = try mgr.request("shared/path", loadOk);
    try std.testing.expectEqual(h1.index, h2.index);
    try std.testing.expectEqual(h1.generation, h2.generation);
    _ = waitUntilLoaded(u32, &mgr, h1);

    // One release shouldn't free it — the other caller still holds a ref.
    try mgr.release(h1);
    try std.testing.expect(mgr.get(h2) != null);

    try mgr.release(h2);
    try std.testing.expect(mgr.get(h2) == null);
}

test "release to zero calls T.deinit" {
    var mgr = AssetManager(DeinitTracker).init(std.testing.allocator);
    defer mgr.deinit();

    const handle = try mgr.request("tracked", loadDeinitTracker);
    _ = waitUntilLoaded(DeinitTracker, &mgr, handle);
    try std.testing.expect(!deinit_tracker_freed_storage);

    try mgr.release(handle);
    try std.testing.expect(deinit_tracker_freed_storage);
}

test "a stale handle after release is rejected by get()/getState()" {
    var mgr = AssetManager(u32).init(std.testing.allocator);
    defer mgr.deinit();

    const handle = try mgr.request("stale-test", loadOk);
    _ = waitUntilLoaded(u32, &mgr, handle);
    try mgr.release(handle);

    try std.testing.expectEqual(AssetManager(u32).State.unloaded, mgr.getState(handle));
    try std.testing.expect(mgr.get(handle) == null);
}

test "a freed slot is reused with a bumped generation, invalidating old handles" {
    var mgr = AssetManager(u32).init(std.testing.allocator);
    defer mgr.deinit();

    const h1 = try mgr.request("first", loadOk);
    _ = waitUntilLoaded(u32, &mgr, h1);
    try mgr.release(h1);

    const h2 = try mgr.request("second", loadOk);
    _ = waitUntilLoaded(u32, &mgr, h2);

    try std.testing.expectEqual(h1.index, h2.index); // slot reused
    try std.testing.expect(h1.generation != h2.generation);
    try std.testing.expect(mgr.get(h1) == null); // old handle still rejected
    try std.testing.expect(mgr.get(h2) != null);
}

test "releasing and re-requesting the same path loads fresh rather than reusing a freed slot" {
    var mgr = AssetManager(u32).init(std.testing.allocator);
    defer mgr.deinit();

    const h1 = try mgr.request("reload/path", loadOk);
    _ = waitUntilLoaded(u32, &mgr, h1);
    try mgr.release(h1);

    const h2 = try mgr.request("reload/path", loadOk);
    _ = waitUntilLoaded(u32, &mgr, h2);
    try std.testing.expect(mgr.get(h2) != null);
}
