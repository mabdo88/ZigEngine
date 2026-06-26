const std = @import("std");
const Io = std.Io;
const log = @import("log.zig");

/// Polls a set of file paths for mtime changes on a background thread and
/// debounces them before reporting, so a burst of writes (e.g. an editor
/// doing several small saves) only fires once after things settle.
///
/// Concurrency contract: call `watch()` only before `start()` (single
/// -threaded setup). After `start()`, the watcher thread owns `watched`
/// (mtime bookkeeping) and the caller only ever touches `changed` through
/// `pollChanged()`, which is lock-guarded — that's the only data shared
/// across the thread boundary.
pub const FileWatcher = struct {
    const WatchedFile = struct {
        path: []const u8, // owned
        last_mtime: Io.Timestamp,
        pending_mtime: ?Io.Timestamp = null,
        pending_since: ?Io.Timestamp = null,
    };

    allocator: std.mem.Allocator,
    watched: std.ArrayListUnmanaged(WatchedFile) = .empty,
    changed: std.ArrayListUnmanaged([]const u8) = .empty,
    lock: std.atomic.Mutex = .unlocked,
    running: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    poll_interval_ms: i64 = 100,
    debounce_ms: i64 = 300,

    pub fn init(allocator: std.mem.Allocator) FileWatcher {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *FileWatcher) void {
        self.stop();
        for (self.watched.items) |wf| self.allocator.free(wf.path);
        self.watched.deinit(self.allocator);
        for (self.changed.items) |p| self.allocator.free(p);
        self.changed.deinit(self.allocator);
    }

    pub fn watch(self: *FileWatcher, io: Io, path: []const u8) !void {
        const stat = try Io.Dir.cwd().statFile(io, path, .{});
        const owned = try self.allocator.dupe(u8, path);
        try self.watched.append(self.allocator, .{ .path = owned, .last_mtime = stat.mtime });
    }

    pub fn start(self: *FileWatcher) !void {
        if (self.thread != null) return;
        self.running.store(true, .release);
        self.thread = try std.Thread.spawn(.{}, watchLoop, .{self});
    }

    pub fn stop(self: *FileWatcher) void {
        if (self.thread == null) return;
        self.running.store(false, .release);
        self.thread.?.join();
        self.thread = null;
    }

    /// Drains and returns every path that changed (and settled past the
    /// debounce window) since the last call. Caller owns the returned
    /// slice and must free each path plus the slice itself.
    pub fn pollChanged(self: *FileWatcher) ![][]const u8 {
        self.lockQueue();
        defer self.lock.unlock();
        return self.changed.toOwnedSlice(self.allocator);
    }

    fn lockQueue(self: *FileWatcher) void {
        while (!self.lock.tryLock()) {}
    }

    fn watchLoop(self: *FileWatcher) void {
        var threaded = std.Io.Threaded.init(self.allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();

        while (self.running.load(.acquire)) {
            self.pollOnce(io) catch |err| {
                log.warn(@src(), "hotreload: poll failed: {s}", .{@errorName(err)});
            };
            Io.sleep(io, Io.Duration.fromMilliseconds(self.poll_interval_ms), .awake) catch {};
        }
    }

    fn pollOnce(self: *FileWatcher, io: Io) !void {
        const now = Io.Clock.awake.now(io);

        for (self.watched.items) |*wf| {
            const stat = Io.Dir.cwd().statFile(io, wf.path, .{}) catch continue;
            if (stat.mtime.nanoseconds == wf.last_mtime.nanoseconds) {
                wf.pending_mtime = null;
                wf.pending_since = null;
                continue;
            }

            if (wf.pending_mtime == null or wf.pending_mtime.?.nanoseconds != stat.mtime.nanoseconds) {
                wf.pending_mtime = stat.mtime;
                wf.pending_since = now;
                continue;
            }

            const elapsed_ms = @divTrunc(now.nanoseconds - wf.pending_since.?.nanoseconds, std.time.ns_per_ms);
            if (elapsed_ms >= self.debounce_ms) {
                wf.last_mtime = stat.mtime;
                wf.pending_mtime = null;
                wf.pending_since = null;
                try self.pushChanged(wf.path);
            }
        }
    }

    fn pushChanged(self: *FileWatcher, path: []const u8) !void {
        const owned = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned);
        self.lockQueue();
        defer self.lock.unlock();
        try self.changed.append(self.allocator, owned);
    }
};

fn uniqueTestPath(io: Io, buf: []u8) []const u8 {
    var rand_bytes: [8]u8 = undefined;
    Io.random(io, &rand_bytes);
    const n = std.mem.readInt(u64, &rand_bytes, .little);
    return std.fmt.bufPrint(buf, "hotreload_test_{x}.txt", .{n}) catch unreachable;
}

fn freeChanged(allocator: std.mem.Allocator, changed: [][]const u8) void {
    for (changed) |p| allocator.free(p);
    allocator.free(changed);
}

test "an unmodified watched file reports no changes" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [64]u8 = undefined;
    const path = uniqueTestPath(io, &buf);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "v1" });
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    var watcher = FileWatcher.init(std.testing.allocator);
    defer watcher.deinit();
    try watcher.watch(io, path);
    try watcher.pollOnce(io);

    const changed = try watcher.pollChanged();
    defer freeChanged(std.testing.allocator, changed);
    try std.testing.expectEqual(@as(usize, 0), changed.len);
}

test "a modified file is reported once it settles past the debounce window" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [64]u8 = undefined;
    const path = uniqueTestPath(io, &buf);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "v1" });
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    var watcher = FileWatcher.init(std.testing.allocator);
    defer watcher.deinit();
    watcher.debounce_ms = 20;
    try watcher.watch(io, path);

    try Io.sleep(io, Io.Duration.fromMilliseconds(5), .awake);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "v2 - longer content to bump mtime" });

    try watcher.pollOnce(io); // detects the change, starts the debounce window
    var changed = try watcher.pollChanged();
    freeChanged(std.testing.allocator, changed);

    try Io.sleep(io, Io.Duration.fromMilliseconds(30), .awake);
    try watcher.pollOnce(io); // debounce window elapsed, should fire now

    changed = try watcher.pollChanged();
    defer freeChanged(std.testing.allocator, changed);
    try std.testing.expectEqual(@as(usize, 1), changed.len);
    try std.testing.expectEqualStrings(path, changed[0]);
}

test "rapid rewrites before the debounce window elapses only fire once" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [64]u8 = undefined;
    const path = uniqueTestPath(io, &buf);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "v1" });
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    var watcher = FileWatcher.init(std.testing.allocator);
    defer watcher.deinit();
    watcher.debounce_ms = 30;
    try watcher.watch(io, path);

    try Io.sleep(io, Io.Duration.fromMilliseconds(5), .awake);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "v2" });
    try watcher.pollOnce(io);

    try Io.sleep(io, Io.Duration.fromMilliseconds(5), .awake);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "v3 - different again" });
    try watcher.pollOnce(io); // new mtime resets the debounce window

    try Io.sleep(io, Io.Duration.fromMilliseconds(40), .awake);
    try watcher.pollOnce(io); // now settled

    const changed = try watcher.pollChanged();
    defer freeChanged(std.testing.allocator, changed);
    try std.testing.expectEqual(@as(usize, 1), changed.len);
}

test "start/stop lifecycle spawns and cleanly joins the background thread" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [64]u8 = undefined;
    const path = uniqueTestPath(io, &buf);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "v1" });
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    var watcher = FileWatcher.init(std.testing.allocator);
    defer watcher.deinit();
    watcher.poll_interval_ms = 10;
    watcher.debounce_ms = 10;
    try watcher.watch(io, path);
    try watcher.start();
    defer watcher.stop();

    try Io.sleep(io, Io.Duration.fromMilliseconds(15), .awake);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "v2 - changed while running" });
    try Io.sleep(io, Io.Duration.fromMilliseconds(80), .awake);

    const changed = try watcher.pollChanged();
    defer freeChanged(std.testing.allocator, changed);
    try std.testing.expectEqual(@as(usize, 1), changed.len);
}
