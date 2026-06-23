const std = @import("std");
const components = @import("../engine/ecs/components/components.zig");

pub const MeshData = struct {
    vertices: []components.Vertex,
    indices: []u32,
};

pub const MeshCache = struct {
    meshes: std.ArrayList(MeshData) = .empty,
    hash_to_id: std.AutoHashMap(u64, u32) = undefined,
    allocator: std.mem.Allocator = undefined,

    pub fn init(allocator: std.mem.Allocator) MeshCache {
        return .{
            .hash_to_id = std.AutoHashMap(u64, u32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MeshCache) void {
        for (self.meshes.items) |m| {
            self.allocator.free(m.vertices);
            self.allocator.free(m.indices);
        }
        self.meshes.deinit(self.allocator);
        self.hash_to_id.deinit();
    }

    fn hashMesh(vertices: []const components.Vertex, indices: []const u32) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.sliceAsBytes(vertices));
        hasher.update(std.mem.sliceAsBytes(indices));
        return hasher.final();
    }

    pub fn register(self: *MeshCache, vertices: []const components.Vertex, indices: []const u32) !u32 {
        const hash = hashMesh(vertices, indices);
        if (self.hash_to_id.get(hash)) |id| return id;

        const id: u32 = @intCast(self.meshes.items.len);
        const owned_verts = try self.allocator.dupe(components.Vertex, vertices);
        const owned_inds = try self.allocator.dupe(u32, indices);
        try self.meshes.append(self.allocator, .{ .vertices = owned_verts, .indices = owned_inds });
        try self.hash_to_id.put(hash, id);
        return id;
    }

    pub fn get(self: *MeshCache, mesh_id: u32) ?MeshData {
        if (mesh_id >= self.meshes.items.len) return null;
        return self.meshes.items[mesh_id];
    }
};

test "register deduplicates identical meshes" {
    var cache = MeshCache.init(std.testing.allocator);
    defer cache.deinit();

    const verts = [_]components.Vertex{
        .{ .pos = .{ 0.0, 0.0, 0.0 }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 0.0, 0.0 } },
        .{ .pos = .{ 1.0, 0.0, 0.0 }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 1.0, 0.0 } },
    };
    const idx = [_]u32{ 0, 1, 0 };

    const id1 = try cache.register(&verts, &idx);
    const id2 = try cache.register(&verts, &idx);
    try std.testing.expectEqual(id1, id2);
    try std.testing.expectEqual(@as(usize, 1), cache.meshes.items.len);
}

test "register assigns different ids for different meshes" {
    var cache = MeshCache.init(std.testing.allocator);
    defer cache.deinit();

    const verts = [_]components.Vertex{
        .{ .pos = .{ 0.0, 0.0, 0.0 }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 0.0, 0.0 } },
    };
    const idx = [_]u32{0};

    const id1 = try cache.register(&verts, &idx);

    const verts2 = [_]components.Vertex{
        .{ .pos = .{ 1.0, 1.0, 1.0 }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 0.0, 0.0 } },
    };
    const id2 = try cache.register(&verts2, &idx);
    try std.testing.expect(id1 != id2);
    try std.testing.expectEqual(@as(usize, 2), cache.meshes.items.len);
}

test "get returns registered mesh data" {
    var cache = MeshCache.init(std.testing.allocator);
    defer cache.deinit();

    const verts = [_]components.Vertex{
        .{ .pos = .{ 0.0, 0.0, 0.0 }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 0.0, 0.0 } },
    };
    const idx = [_]u32{0};

    const id = try cache.register(&verts, &idx);
    const data = cache.get(id).?;
    try std.testing.expectEqual(@as(usize, 1), data.vertices.len);
    try std.testing.expectEqual(@as(usize, 1), data.indices.len);
}

test "get returns null for invalid id" {
    var cache = MeshCache.init(std.testing.allocator);
    defer cache.deinit();

    try std.testing.expect(cache.get(999) == null);
}
