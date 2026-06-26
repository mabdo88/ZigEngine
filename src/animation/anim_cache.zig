const std = @import("std");
const skeleton = @import("skeleton.zig");
const clip = @import("clip.zig");

/// Long-lived storage for parsed Skeleton assets, indexed by id. Mirrors
/// resources/meshCache.zig's MeshCache: `register` duplicates the source's
/// owned slices into newly allocated memory, so the cache's copy outlives
/// the GltfScene it was parsed from (which frees its own original via
/// GltfScene.deinit() as usual — no ownership transfer, no double free).
pub const SkeletonCache = struct {
    skeletons: std.ArrayList(skeleton.Skeleton) = .empty,
    allocator: std.mem.Allocator = undefined,
    mutex: std.atomic.Mutex = .unlocked,

    pub fn init(allocator: std.mem.Allocator) SkeletonCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SkeletonCache) void {
        for (self.skeletons.items) |*sk| sk.deinit();
        self.skeletons.deinit(self.allocator);
    }

    pub fn register(self: *SkeletonCache, sk: *const skeleton.Skeleton) !u32 {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();

        const parent_indices = try self.allocator.dupe(i32, sk.parent_indices);
        errdefer self.allocator.free(parent_indices);
        const inverse_bind = try self.allocator.dupe([4][4]f32, sk.inverse_bind_matrices);
        errdefer self.allocator.free(inverse_bind);
        const rest_local = try self.allocator.dupe([4][4]f32, sk.rest_local_transforms);
        errdefer self.allocator.free(rest_local);
        const rest_poses = try self.allocator.dupe(clip.JointPose, sk.rest_local_poses);
        errdefer self.allocator.free(rest_poses);

        const id: u32 = @intCast(self.skeletons.items.len);
        try self.skeletons.append(self.allocator, .{
            .joint_count = sk.joint_count,
            .parent_indices = parent_indices,
            .inverse_bind_matrices = inverse_bind,
            .rest_local_transforms = rest_local,
            .rest_local_poses = rest_poses,
            .allocator = self.allocator,
        });
        return id;
    }

    pub fn get(self: *SkeletonCache, id: u32) ?*const skeleton.Skeleton {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        if (id >= self.skeletons.items.len) return null;
        return &self.skeletons.items[id];
    }
};

/// Long-lived storage for parsed AnimationClip assets. Same duplicate-don't-
/// move ownership model as SkeletonCache.
pub const ClipCache = struct {
    clips: std.ArrayList(clip.AnimationClip) = .empty,
    allocator: std.mem.Allocator = undefined,
    mutex: std.atomic.Mutex = .unlocked,

    pub fn init(allocator: std.mem.Allocator) ClipCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ClipCache) void {
        for (self.clips.items) |*c| c.deinit();
        self.clips.deinit(self.allocator);
    }

    pub fn register(self: *ClipCache, c: *const clip.AnimationClip) !u32 {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();

        const channels = try self.allocator.alloc(clip.Channel, c.channels.len);
        var filled: usize = 0;
        errdefer {
            for (channels[0..filled]) |ch| {
                self.allocator.free(ch.times);
                self.allocator.free(ch.values);
            }
            self.allocator.free(channels);
        }
        for (c.channels, 0..) |ch, i| {
            const times = try self.allocator.dupe(f32, ch.times);
            errdefer self.allocator.free(times);
            const values = try self.allocator.dupe([4]f32, ch.values);
            channels[i] = .{ .joint_index = ch.joint_index, .path = ch.path, .times = times, .values = values };
            filled = i + 1;
        }

        const events = try self.allocator.alloc(clip.AnimEvent, c.events.len);
        var events_filled: usize = 0;
        errdefer {
            for (events[0..events_filled]) |e| self.allocator.free(e.name);
            self.allocator.free(events);
        }
        for (c.events, 0..) |e, i| {
            events[i] = .{ .time = e.time, .name = try self.allocator.dupe(u8, e.name) };
            events_filled = i + 1;
        }

        const name = try self.allocator.dupe(u8, c.name);
        errdefer self.allocator.free(name);

        const id: u32 = @intCast(self.clips.items.len);
        try self.clips.append(self.allocator, .{
            .name = name,
            .duration = c.duration,
            .channels = channels,
            .events = events,
            .allocator = self.allocator,
        });
        return id;
    }

    pub fn get(self: *ClipCache, id: u32) ?*const clip.AnimationClip {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        if (id >= self.clips.items.len) return null;
        return &self.clips.items[id];
    }
};

test "SkeletonCache.register duplicates owned slices independent of the source" {
    const allocator = std.testing.allocator;
    var cache = SkeletonCache.init(allocator);
    defer cache.deinit();

    var source = skeleton.Skeleton{
        .joint_count = 1,
        .parent_indices = try allocator.dupe(i32, &.{-1}),
        .inverse_bind_matrices = try allocator.dupe([4][4]f32, &.{undefined}),
        .rest_local_transforms = try allocator.dupe([4][4]f32, &.{undefined}),
        .rest_local_poses = try allocator.dupe(clip.JointPose, &.{.{}}),
        .allocator = allocator,
    };

    const id = try cache.register(&source);
    source.deinit(); // source freed; cache's copy must still be valid

    const cached = cache.get(id).?;
    try std.testing.expectEqual(@as(u32, 1), cached.joint_count);
    try std.testing.expectEqual(@as(i32, -1), cached.parent_indices[0]);
}

test "ClipCache.register duplicates channels independent of the source" {
    const allocator = std.testing.allocator;
    var cache = ClipCache.init(allocator);
    defer cache.deinit();

    var source = clip.AnimationClip{
        .name = try allocator.dupe(u8, "walk"),
        .duration = 1.5,
        .channels = try allocator.dupe(clip.Channel, &.{.{
            .joint_index = 0,
            .path = .translation,
            .times = try allocator.dupe(f32, &.{ 0.0, 1.0 }),
            .values = try allocator.dupe([4]f32, &.{ .{ 0, 0, 0, 0 }, .{ 1, 0, 0, 0 } }),
        }}),
        .allocator = allocator,
    };

    const id = try cache.register(&source);
    source.deinit();

    const cached = cache.get(id).?;
    try std.testing.expectEqualStrings("walk", cached.name);
    try std.testing.expectEqual(@as(f32, 1.5), cached.duration);
    try std.testing.expectEqual(@as(usize, 1), cached.channels.len);
}

test "ClipCache.register duplicates events independent of the source" {
    const allocator = std.testing.allocator;
    var cache = ClipCache.init(allocator);
    defer cache.deinit();

    var source = clip.AnimationClip{
        .name = try allocator.dupe(u8, "walk"),
        .duration = 1.0,
        .channels = &.{},
        .events = try allocator.dupe(clip.AnimEvent, &.{.{ .time = 0.5, .name = try allocator.dupe(u8, "footstep") }}),
        .allocator = allocator,
    };

    const id = try cache.register(&source);
    source.deinit();

    const cached = cache.get(id).?;
    try std.testing.expectEqual(@as(usize, 1), cached.events.len);
    try std.testing.expectEqualStrings("footstep", cached.events[0].name);
}

test "get returns null for an out-of-range id" {
    const allocator = std.testing.allocator;
    var skel_cache = SkeletonCache.init(allocator);
    defer skel_cache.deinit();
    try std.testing.expect(skel_cache.get(999) == null);

    var clip_cache = ClipCache.init(allocator);
    defer clip_cache.deinit();
    try std.testing.expect(clip_cache.get(999) == null);
}
