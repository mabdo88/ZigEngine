const std = @import("std");
const audio_device = @import("audio_device.zig");

/// Dedups loaded clips by path, mirroring resources/meshCache.zig's pattern.
/// id = index into `clips`, referenced by AudioSourceComponent.clip_id.
///
/// Stores `*AudioClip` (individually heap-allocated), not `AudioClip` by
/// value: a sound's underlying ma_sound holds a pointer to its own address
/// once attached to the engine's node graph (see audio_device.zig's
/// clipLoad doc comment), so growing this list must never move an
/// already-loaded clip's storage — only the pointers in the list move.
pub const AudioClipCache = struct {
    clips: std.ArrayList(*audio_device.AudioClip) = .empty,
    path_to_id: std.StringHashMap(u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AudioClipCache {
        return .{ .path_to_id = std.StringHashMap(u32).init(allocator), .allocator = allocator };
    }

    pub fn deinit(self: *AudioClipCache) void {
        for (self.clips.items) |clip| {
            audio_device.clipUnload(clip);
            self.allocator.destroy(clip);
        }
        self.clips.deinit(self.allocator);
        var it = self.path_to_id.keyIterator();
        while (it.next()) |key| self.allocator.free(key.*);
        self.path_to_id.deinit();
    }

    /// `group` routes the clip to a mix bus (see audio_mixer.zig's
    /// AudioMixer.group) instead of the engine's master endpoint directly —
    /// pass `null` for clips that don't need bus routing. Only applies the
    /// first time a given path is registered: since clips are deduped by
    /// path, a second `register()` call for an already-loaded path returns
    /// the existing id (and its existing bus) regardless of what `group` is
    /// passed this time — see audio_3d_system.zig's CLAUDE.md note on the
    /// same one-clip-one-instance limitation for spatialization.
    pub fn register(self: *AudioClipCache, engine: *audio_device.AudioEngine, path: []const u8, group: ?*audio_device.ma.ma_sound_group) !u32 {
        if (self.path_to_id.get(path)) |id| return id;

        const path_z = try self.allocator.allocSentinel(u8, path.len, 0);
        defer self.allocator.free(path_z);
        @memcpy(path_z, path);

        const clip = try self.allocator.create(audio_device.AudioClip);
        errdefer self.allocator.destroy(clip);
        try audio_device.clipLoad(engine, path_z, group, clip);
        errdefer audio_device.clipUnload(clip);

        const id: u32 = @intCast(self.clips.items.len);
        try self.clips.append(self.allocator, clip);
        const owned_path = try self.allocator.dupe(u8, path);
        try self.path_to_id.put(owned_path, id);
        return id;
    }

    pub fn get(self: *AudioClipCache, clip_id: u32) ?*audio_device.AudioClip {
        if (clip_id >= self.clips.items.len) return null;
        return self.clips.items[clip_id];
    }
};
