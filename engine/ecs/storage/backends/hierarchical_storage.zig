// Zig 0.16.0 (tested against 0.17.0-dev)
//
// Hierarchical backend — data indexed by a zone tree
// (Building → Floor → Room → Sensor) via parent-child links.
//
// Models graph-db behaviour: readings are stored in per-sensor leaf
// nodes of a tree index. Spatial / zone-hierarchy queries traverse the
// tree to collect readings from subtrees (e.g. "all sensors on floor 2").
//
// The tree is an internal detail invisible to queries — the public
// surface is exactly the StorageBackend interface. The tree makes
// per-sensor lookups O(1) (hash map from sensor_id to leaf node) and
// enables efficient subtree scans for spatial queries when they are
// added to the interface.
//
// Zone assignment (deterministic, derived from sensor_id):
//   floor = sensor_id / 100
//   room  = sensor_id / 10
//   sensor = sensor_id (leaf)
//
// Iteration order: sorted by (timestamp asc, sensor_id asc).

const std = @import("std");
const sb = @import("../storage_backend.zig");

const SensorReading = sb.SensorReading;
const SensorType = sb.SensorType;
const RangeQuery = sb.RangeQuery;

const Self = @This();

// Tree node — represents a zone (Building, Floor, Room) or a Sensor leaf.
// Internal only; never exposed through the interface.
const Node = struct {
    parent: ?u32,
    children: std.ArrayList(u32),
    readings: ?std.ArrayList(SensorReading),
    sensor_id: ?u32,
    zone_key: u32,
};

allocator: std.mem.Allocator,
nodes: std.ArrayList(Node),
sensor_to_node: std.AutoHashMap(u32, u32),
root: u32,
total_count: usize,

pub fn init(allocator: std.mem.Allocator) !Self {
    var self = Self{
        .allocator = allocator,
        .nodes = .empty,
        .sensor_to_node = std.AutoHashMap(u32, u32).init(allocator),
        .root = 0,
        .total_count = 0,
    };
    try self.nodes.append(allocator, .{
        .parent = null,
        .children = .empty,
        .readings = null,
        .sensor_id = null,
        .zone_key = 0,
    });
    self.root = 0;
    return self;
}

pub fn deinit(self: *Self) void {
    for (self.nodes.items) |*node| {
        node.children.deinit(self.allocator);
        if (node.readings) |*r| {
            r.deinit(self.allocator);
        }
    }
    self.nodes.deinit(self.allocator);
    self.sensor_to_node.deinit();
    self.* = undefined;
}

pub fn insert(self: *Self, reading: SensorReading) !void {
    const leaf_idx = try self.ensureSensorPath(reading.sensor_id);
    const node = &self.nodes.items[leaf_idx];
    if (node.readings == null) {
        node.readings = .empty;
    }
    try node.readings.?.append(self.allocator, reading);
    self.total_count += 1;
}

pub fn count(self: *const Self) usize {
    return self.total_count;
}

pub fn memoryUsed(self: *const Self) usize {
    var total: usize = self.nodes.capacity * @sizeOf(Node);
    for (self.nodes.items) |node| {
        total += node.children.capacity * @sizeOf(u32);
        if (node.readings) |r| {
            total += r.capacity * @sizeOf(SensorReading);
        }
    }
    total += self.sensor_to_node.capacity() * (@sizeOf(u32) + @sizeOf(u32));
    return total;
}

/// Iteration order: sorted by (timestamp asc, sensor_id asc).
pub fn iterateAll(self: *const Self, allocator: std.mem.Allocator) ![]const SensorReading {
    var result: std.ArrayList(SensorReading) = .empty;
    defer result.deinit(allocator);

    for (self.nodes.items) |node| {
        if (node.readings) |r| {
            for (r.items) |reading| {
                try result.append(allocator, reading);
            }
        }
    }

    std.mem.sort(SensorReading, result.items, {}, struct {
        fn lt(_: void, lhs: SensorReading, rhs: SensorReading) bool {
            if (lhs.timestamp != rhs.timestamp) return lhs.timestamp < rhs.timestamp;
            return lhs.sensor_id < rhs.sensor_id;
        }
    }.lt);

    return result.toOwnedSlice(allocator);
}

pub fn getLatestBySensor(self: *const Self, sensor_id: u32) ?SensorReading {
    const node_idx = self.sensor_to_node.get(sensor_id) orelse return null;
    const node = &self.nodes.items[node_idx];
    const readings = node.readings orelse return null;

    var best: ?SensorReading = null;
    for (readings.items) |r| {
        if (best == null or r.timestamp > best.?.timestamp) {
            best = r;
        }
    }
    return best;
}

/// Results ordered by timestamp ascending, ties broken by sensor_id ascending.
pub fn rangeByTime(self: *const Self, allocator: std.mem.Allocator, q: RangeQuery) ![]const SensorReading {
    var result: std.ArrayList(SensorReading) = .empty;
    defer result.deinit(allocator);

    if (q.sensor_id) |sid| {
        const node_idx = self.sensor_to_node.get(sid) orelse return &.{};
        const node = &self.nodes.items[node_idx];
        const readings = node.readings orelse return &.{};
        for (readings.items) |r| {
            if (r.timestamp >= q.start_time and r.timestamp <= q.end_time) {
                try result.append(allocator, r);
            }
        }
    } else {
        for (self.nodes.items) |node| {
            if (node.readings) |r| {
                for (r.items) |reading| {
                    if (reading.timestamp >= q.start_time and reading.timestamp <= q.end_time) {
                        try result.append(allocator, reading);
                    }
                }
            }
        }
    }

    std.mem.sort(SensorReading, result.items, {}, struct {
        fn lt(_: void, lhs: SensorReading, rhs: SensorReading) bool {
            if (lhs.timestamp != rhs.timestamp) return lhs.timestamp < rhs.timestamp;
            return lhs.sensor_id < rhs.sensor_id;
        }
    }.lt);

    return result.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------------------
// Internal — tree path management
// ---------------------------------------------------------------------------

fn ensureSensorPath(self: *Self, sensor_id: u32) !u32 {
    if (self.sensor_to_node.get(sensor_id)) |idx| return idx;

    const floor_key = sensor_id / 100;
    const room_key = sensor_id / 10;

    const floor_idx = try self.ensureChild(self.root, floor_key);
    const room_idx = try self.ensureChild(floor_idx, room_key);
    const leaf_idx = try self.createLeaf(room_idx, sensor_id);

    try self.sensor_to_node.put(sensor_id, leaf_idx);
    return leaf_idx;
}

fn ensureChild(self: *Self, parent_idx: u32, zone_key: u32) !u32 {
    for (self.nodes.items[parent_idx].children.items) |child_idx| {
        if (self.nodes.items[child_idx].zone_key == zone_key) {
            return child_idx;
        }
    }
    const idx: u32 = @intCast(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{
        .parent = parent_idx,
        .children = .empty,
        .readings = null,
        .sensor_id = null,
        .zone_key = zone_key,
    });
    // Access parent after append — append may reallocate nodes.items
    try self.nodes.items[parent_idx].children.append(self.allocator, idx);
    return idx;
}

fn createLeaf(self: *Self, parent_idx: u32, sensor_id: u32) !u32 {
    const idx: u32 = @intCast(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{
        .parent = parent_idx,
        .children = .empty,
        .readings = null,
        .sensor_id = sensor_id,
        .zone_key = sensor_id,
    });
    // Access parent after append — append may reallocate nodes.items
    try self.nodes.items[parent_idx].children.append(self.allocator, idx);
    return idx;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "Hierarchical: assertImplements" {
    sb.assertImplements(Self);
}

test "Hierarchical: insert N readings and read them back" {
    const N: usize = 100;
    var backend = try Self.init(std.testing.allocator);
    defer backend.deinit();

    for (0..N) |i| {
        try backend.insert(.{
            .sensor_id = @intCast(i % 10),
            .timestamp = @intCast(i),
            .value = @floatFromInt(i),
            .sensor_type = .temperature,
        });
    }

    try std.testing.expectEqual(N, backend.count());

    const all = try backend.iterateAll(std.testing.allocator);
    defer std.testing.allocator.free(all);

    try std.testing.expectEqual(N, all.len);
    for (0..N) |i| {
        try std.testing.expectEqual(@as(i64, @intCast(i)), all[i].timestamp);
    }
}

test "Hierarchical: getLatestBySensor" {
    var backend = try Self.init(std.testing.allocator);
    defer backend.deinit();

    try backend.insert(.{ .sensor_id = 1, .timestamp = 100, .value = 10.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 1, .timestamp = 300, .value = 30.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 1, .timestamp = 200, .value = 20.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 2, .timestamp = 500, .value = 50.0, .sensor_type = .humidity });

    const latest = backend.getLatestBySensor(1).?;
    try std.testing.expectEqual(@as(i64, 300), latest.timestamp);
    try std.testing.expectEqual(@as(f32, 30.0), latest.value);

    try std.testing.expect(backend.getLatestBySensor(999) == null);
}

test "Hierarchical: rangeByTime filters and sorts" {
    var backend = try Self.init(std.testing.allocator);
    defer backend.deinit();

    try backend.insert(.{ .sensor_id = 3, .timestamp = 50, .value = 1.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 1, .timestamp = 10, .value = 2.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 2, .timestamp = 30, .value = 3.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 1, .timestamp = 10, .value = 4.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 5, .timestamp = 200, .value = 5.0, .sensor_type = .temperature });

    const result = try backend.rangeByTime(std.testing.allocator, .{ .start_time = 0, .end_time = 100 });
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqual(@as(u32, 1), result[0].sensor_id);
    try std.testing.expectEqual(@as(i64, 10), result[0].timestamp);
    try std.testing.expectEqual(@as(u32, 1), result[1].sensor_id);
    try std.testing.expectEqual(@as(i64, 10), result[1].timestamp);
    try std.testing.expectEqual(@as(u32, 2), result[2].sensor_id);
    try std.testing.expectEqual(@as(i64, 30), result[2].timestamp);
    try std.testing.expectEqual(@as(u32, 3), result[3].sensor_id);
    try std.testing.expectEqual(@as(i64, 50), result[3].timestamp);
}

test "Hierarchical: rangeByTime with sensor filter" {
    var backend = try Self.init(std.testing.allocator);
    defer backend.deinit();

    try backend.insert(.{ .sensor_id = 1, .timestamp = 10, .value = 1.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 2, .timestamp = 20, .value = 2.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 1, .timestamp = 30, .value = 3.0, .sensor_type = .temperature });

    const result = try backend.rangeByTime(std.testing.allocator, .{
        .sensor_id = 1,
        .start_time = 0,
        .end_time = 100,
    });
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqual(@as(u32, 1), result[0].sensor_id);
    try std.testing.expectEqual(@as(u32, 1), result[1].sensor_id);
}

test "Hierarchical: empty backend" {
    var backend = try Self.init(std.testing.allocator);
    defer backend.deinit();

    try std.testing.expectEqual(@as(usize, 0), backend.count());
    try std.testing.expect(backend.getLatestBySensor(0) == null);

    const all = try backend.iterateAll(std.testing.allocator);
    defer std.testing.allocator.free(all);
    try std.testing.expectEqual(@as(usize, 0), all.len);

    const rng = try backend.rangeByTime(std.testing.allocator, .{ .start_time = 0, .end_time = 100 });
    defer std.testing.allocator.free(rng);
    try std.testing.expectEqual(@as(usize, 0), rng.len);
}

test "Hierarchical: out-of-order inserts handled correctly" {
    var backend = try Self.init(std.testing.allocator);
    defer backend.deinit();

    try backend.insert(.{ .sensor_id = 1, .timestamp = 300, .value = 3.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 1, .timestamp = 100, .value = 1.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 1, .timestamp = 200, .value = 2.0, .sensor_type = .temperature });

    const latest = backend.getLatestBySensor(1).?;
    try std.testing.expectEqual(@as(i64, 300), latest.timestamp);

    const all = try backend.iterateAll(std.testing.allocator);
    defer std.testing.allocator.free(all);
    try std.testing.expectEqual(@as(i64, 100), all[0].timestamp);
    try std.testing.expectEqual(@as(i64, 200), all[1].timestamp);
    try std.testing.expectEqual(@as(i64, 300), all[2].timestamp);
}

test "Hierarchical: tree structure creates correct zone hierarchy" {
    var backend = try Self.init(std.testing.allocator);
    defer backend.deinit();

    // sensor 0 → floor 0, room 0
    // sensor 5 → floor 0, room 0
    // sensor 10 → floor 0, room 1
    // sensor 150 → floor 1, room 15
    try backend.insert(.{ .sensor_id = 0, .timestamp = 100, .value = 1.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 5, .timestamp = 100, .value = 2.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 10, .timestamp = 100, .value = 3.0, .sensor_type = .temperature });
    try backend.insert(.{ .sensor_id = 150, .timestamp = 100, .value = 4.0, .sensor_type = .temperature });

    // Root + floor0 + room0 + sensor0 + sensor5 + room1 + sensor10 + floor1 + room15 + sensor150
    // = 10 nodes
    try std.testing.expectEqual(@as(usize, 10), backend.nodes.items.len);
    try std.testing.expectEqual(@as(u32, 0), backend.root);

    // Root has 2 children (floor 0, floor 1)
    try std.testing.expectEqual(@as(usize, 2), backend.nodes.items[0].children.items.len);

    // All 4 sensors are leaf nodes with readings
    try std.testing.expectEqual(@as(usize, 4), backend.count());
}

test "Hierarchical and TimeSeries produce identical query results" {
    var hier = try Self.init(std.testing.allocator);
    defer hier.deinit();
    var ts = try @import("timeseries_storage.zig").init(std.testing.allocator);
    defer ts.deinit();

    const readings = [_]SensorReading{
        .{ .sensor_id = 5, .timestamp = 100, .value = 1.5, .sensor_type = .temperature },
        .{ .sensor_id = 2, .timestamp = 300, .value = 2.5, .sensor_type = .humidity },
        .{ .sensor_id = 5, .timestamp = 200, .value = 3.5, .sensor_type = .co2 },
        .{ .sensor_id = 1, .timestamp = 200, .value = 4.5, .sensor_type = .occupancy },
    };

    for (readings) |r| {
        try hier.insert(r);
        try ts.insert(r);
    }

    try std.testing.expectEqual(ts.count(), hier.count());

    // rangeByTime — both must return same sorted results
    const hier_rng = try hier.rangeByTime(std.testing.allocator, .{ .start_time = 150, .end_time = 250 });
    defer std.testing.allocator.free(hier_rng);
    const ts_rng = try ts.rangeByTime(std.testing.allocator, .{ .start_time = 150, .end_time = 250 });
    defer std.testing.allocator.free(ts_rng);

    try std.testing.expectEqual(ts_rng.len, hier_rng.len);
    for (0..ts_rng.len) |i| {
        try std.testing.expectEqual(ts_rng[i].sensor_id, hier_rng[i].sensor_id);
        try std.testing.expectEqual(ts_rng[i].timestamp, hier_rng[i].timestamp);
        try std.testing.expectEqual(ts_rng[i].value, hier_rng[i].value);
        try std.testing.expectEqual(ts_rng[i].sensor_type, hier_rng[i].sensor_type);
    }

    // getLatestBySensor — both must agree
    for (0..6) |sid| {
        const hier_latest = hier.getLatestBySensor(@intCast(sid));
        const ts_latest = ts.getLatestBySensor(@intCast(sid));
        if (ts_latest) |t| {
            try std.testing.expect(hier_latest != null);
            try std.testing.expectEqual(t.timestamp, hier_latest.?.timestamp);
            try std.testing.expectEqual(t.sensor_id, hier_latest.?.sensor_id);
            try std.testing.expectEqual(t.value, hier_latest.?.value);
        } else {
            try std.testing.expect(hier_latest == null);
        }
    }

    // iterateAll — both must return same sorted results
    const hier_all = try hier.iterateAll(std.testing.allocator);
    defer std.testing.allocator.free(hier_all);
    const ts_all = try ts.iterateAll(std.testing.allocator);
    defer std.testing.allocator.free(ts_all);

    try std.testing.expectEqual(ts_all.len, hier_all.len);
    for (0..ts_all.len) |i| {
        try std.testing.expectEqual(ts_all[i].sensor_id, hier_all[i].sensor_id);
        try std.testing.expectEqual(ts_all[i].timestamp, hier_all[i].timestamp);
        try std.testing.expectEqual(ts_all[i].value, hier_all[i].value);
        try std.testing.expectEqual(ts_all[i].sensor_type, hier_all[i].sensor_type);
    }
}
