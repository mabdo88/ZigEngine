// Zig 0.16.0 (tested against 0.17.0-dev)
//
// Benchmark query functions — pure functions over World(T) queries.
//
// Per CLAUDE.md §3.1: these functions accept any World(T) via `anytype` and
// never branch on the concrete backend type. The same function compiles and
// runs unchanged whether T is AoSStorage, SoAStorage, or any future backend.
//
// This file is the canonical home for the 12 query patterns across 5
// families (real-time, aggregation, historical, spatial, anomaly).
// query_avg_window is the first: an aggregation query that computes the
// average value of a specific sensor over a trailing time window.

const std = @import("std");
const sb = @import("../ecs/storage/storage_backend.zig");

/// Average value for a specific sensor over the trailing `hours` window
/// ending at the most recent reading's timestamp for that sensor.
///
/// Returns 0.0 when the sensor has no readings.
///
/// Pure: calls only world.rangeByTime and world.getLatestBySensor — no
/// backend-specific code, no branching on backend type.
pub fn query_avg_window(world: anytype, sensor_id: u32, hours: u32) !f32 {
    const latest = world.getLatestBySensor(sensor_id) orelse return 0.0;

    const ms_per_hour: i64 = 60 * 60 * 1000;
    const window_ms: i64 = @as(i64, hours) * ms_per_hour;
    const start_time: i64 = latest.timestamp - window_ms;

    const results = try world.rangeByTime(.{
        .sensor_id = sensor_id,
        .start_time = start_time,
        .end_time = latest.timestamp,
    });
    defer world.allocator.free(results);

    if (results.len == 0) return 0.0;

    var sum: f64 = 0;
    for (results) |r| sum += @as(f64, r.value);
    return @as(f32, @floatCast(sum / @as(f64, @floatFromInt(results.len))));
}

// ---------------------------------------------------------------------------
// Golden-result equivalence test
//
// This is the TEMPLATE for every future backend-equivalence test:
//   1. Seed a deterministic PRNG with a fixed seed.
//   2. Generate the SAME synthetic dataset once.
//   3. Insert it into World(AoS) and World(SoA) independently.
//   4. Run the query on both worlds.
//   5. Assert results agree within a documented float tolerance.
//
// The tolerance is 1e-5 (absolute). This is generous for f32 summation of
// a few hundred values — the real goal is catching logic divergences
// between backends, not numerical noise from different iteration orders.
// ---------------------------------------------------------------------------

const aos = @import("../ecs/storage/backends/aos_storage.zig");
const soa = @import("../ecs/storage/backends/soa_storage.zig");
const timeseries = @import("../ecs/storage/backends/timeseries_storage.zig");
const columnar = @import("../ecs/storage/backends/columnar_storage.zig");
const hierarchical = @import("../ecs/storage/backends/hierarchical_storage.zig");
const ringbuffer = @import("../ecs/storage/backends/ringbuffer_storage.zig");
const World = @import("../ecs/world.zig").World;

const NUM_SENSORS: u32 = 10;
const READINGS_PER_SENSOR: u32 = 50;
const BASE_TIMESTAMP: i64 = 1_000_000;
const MS_PER_HOUR: i64 = 60 * 60 * 1000;

/// Generate a deterministic dataset using a seeded PRNG.
/// Returns a slice of SensorReading owned by the caller.
fn generateDataset(allocator: std.mem.Allocator) ![]sb.SensorReading {
    var prng = std.Random.DefaultPrng.init(42);
    const rand = prng.random();

    const total = NUM_SENSORS * READINGS_PER_SENSOR;
    const readings = try allocator.alloc(sb.SensorReading, total);

    var idx: usize = 0;
    var sensor: u32 = 0;
    while (sensor < NUM_SENSORS) : (sensor += 1) {
        var reading: u32 = 0;
        while (reading < READINGS_PER_SENSOR) : (reading += 1) {
            const ts = BASE_TIMESTAMP + @as(i64, reading) * MS_PER_HOUR;
            const val: f32 = @floatCast(10.0 + 5.0 * rand.float(f32) + @as(f32, @floatFromInt(sensor)));
            readings[idx] = .{
                .sensor_id = sensor,
                .timestamp = ts,
                .value = val,
                .sensor_type = .temperature,
            };
            idx += 1;
        }
    }

    return readings;
}

/// Insert a dataset into a world. The world receives readings in the same
/// order for both backends — deterministic insertion is critical for
/// equivalence testing.
fn insertDataset(world: anytype, readings: []const sb.SensorReading) !void {
    for (readings) |r| try world.insert(r);
}

test "query_avg_window: AoS, SoA, TimeSeries, Columnar, and Hierarchical agree on same seeded dataset" {
    const dataset = try generateDataset(std.testing.allocator);
    defer std.testing.allocator.free(dataset);

    var world_aos = try World(aos).init(std.testing.allocator);
    defer world_aos.deinit();
    var world_soa = try World(soa).init(std.testing.allocator);
    defer world_soa.deinit();
    var world_ts = try World(timeseries).init(std.testing.allocator);
    defer world_ts.deinit();
    var world_col = try World(columnar).init(std.testing.allocator);
    defer world_col.deinit();
    var world_hier = try World(hierarchical).init(std.testing.allocator);
    defer world_hier.deinit();
    var world_rb = try World(ringbuffer).init(std.testing.allocator);
    defer world_rb.deinit();

    try insertDataset(&world_aos, dataset);
    try insertDataset(&world_soa, dataset);
    try insertDataset(&world_ts, dataset);
    try insertDataset(&world_col, dataset);
    try insertDataset(&world_hier, dataset);
    try insertDataset(&world_rb, dataset);

    // Test several sensors and window sizes
    const test_cases = [_]struct { sensor: u32, hours: u32 }{
        .{ .sensor = 0, .hours = 1 },
        .{ .sensor = 0, .hours = 6 },
        .{ .sensor = 0, .hours = 24 },
        .{ .sensor = 0, .hours = 50 },
        .{ .sensor = 3, .hours = 1 },
        .{ .sensor = 3, .hours = 12 },
        .{ .sensor = 3, .hours = 50 },
        .{ .sensor = 9, .hours = 1 },
        .{ .sensor = 9, .hours = 24 },
        .{ .sensor = 9, .hours = 50 },
    };

    // Tolerance: 1e-5 absolute. All backends iterate the same sorted
    // result set and sum f32s in the same order, so they should agree
    // to within float rounding noise. 1e-5 is generous for ~50 values.
    const tolerance: f32 = 1e-5;

    for (test_cases) |tc| {
        const avg_aos = try query_avg_window(&world_aos, tc.sensor, tc.hours);
        const avg_soa = try query_avg_window(&world_soa, tc.sensor, tc.hours);
        const avg_ts = try query_avg_window(&world_ts, tc.sensor, tc.hours);
        const avg_col = try query_avg_window(&world_col, tc.sensor, tc.hours);
        const avg_hier = try query_avg_window(&world_hier, tc.sensor, tc.hours);
        const avg_rb = try query_avg_window(&world_rb, tc.sensor, tc.hours);

        try std.testing.expectApproxEqAbs(avg_aos, avg_soa, tolerance);
        try std.testing.expectApproxEqAbs(avg_aos, avg_ts, tolerance);
        try std.testing.expectApproxEqAbs(avg_aos, avg_col, tolerance);
        try std.testing.expectApproxEqAbs(avg_aos, avg_hier, tolerance);
        try std.testing.expectApproxEqAbs(avg_aos, avg_rb, tolerance);
    }
}

test "query_avg_window: returns 0.0 for nonexistent sensor" {
    var world = try World(aos).init(std.testing.allocator);
    defer world.deinit();

    const dataset = try generateDataset(std.testing.allocator);
    defer std.testing.allocator.free(dataset);
    try insertDataset(&world, dataset);

    const result = try query_avg_window(&world, 999, 24);
    try std.testing.expectEqual(@as(f32, 0.0), result);
}

test "query_avg_window: returns 0.0 for empty world" {
    var world = try World(aos).init(std.testing.allocator);
    defer world.deinit();

    const result = try query_avg_window(&world, 0, 24);
    try std.testing.expectEqual(@as(f32, 0.0), result);
}

test "query_avg_window: single reading returns that reading's value" {
    var world = try World(soa).init(std.testing.allocator);
    defer world.deinit();

    try world.insert(.{
        .sensor_id = 5,
        .timestamp = 1_000_000,
        .value = 42.0,
        .sensor_type = .temperature,
    });

    const result = try query_avg_window(&world, 5, 24);
    try std.testing.expectApproxEqAbs(@as(f32, 42.0), result, 1e-5);
}
