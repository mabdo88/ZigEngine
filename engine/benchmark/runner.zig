// Zig 0.16.0 (tested against 0.17.0-dev)
//
// Benchmark runner — wires all six storage backends into a comptime list,
// runs the full equivalence suite, and produces a combined per-query
// latency table.
//
// Per CLAUDE.md §3.1: queries are backend-agnostic. The runner iterates
// over backends at comptime (inline for) since World(T) is a comptime
// generic — no vtable, no dynamic dispatch.
//
// The backend list is the single place where all backends are registered.
// Adding a new backend means appending one entry to `backends` — every
// test and table in this file picks it up automatically.

const std = @import("std");
const sb = @import("../ecs/storage/storage_backend.zig");
const aos = @import("../ecs/storage/backends/aos_storage.zig");
const soa = @import("../ecs/storage/backends/soa_storage.zig");
const timeseries = @import("../ecs/storage/backends/timeseries_storage.zig");
const columnar = @import("../ecs/storage/backends/columnar_storage.zig");
const hierarchical = @import("../ecs/storage/backends/hierarchical_storage.zig");
const ringbuffer = @import("../ecs/storage/backends/ringbuffer_storage.zig");
const World = @import("../ecs/world.zig").World;
const queries = @import("queries.zig");
const metrics = @import("../ecs/systems/metrics_system.zig");

// ---------------------------------------------------------------------------
// Backend registry — the canonical list of all storage backends.
// ---------------------------------------------------------------------------

pub const BackendEntry = struct { name: []const u8, T: type };

pub const backends = [_]BackendEntry{
    .{ .name = "AoS", .T = aos },
    .{ .name = "SoA", .T = soa },
    .{ .name = "TimeSeries", .T = timeseries },
    .{ .name = "Columnar", .T = columnar },
    .{ .name = "Hierarchical", .T = hierarchical },
    .{ .name = "RingBuffer", .T = ringbuffer },
};

// ---------------------------------------------------------------------------
// Dataset generation — deterministic, seeded PRNG, identical across runs.
// ---------------------------------------------------------------------------

const NUM_SENSORS: u32 = 10;
const READINGS_PER_SENSOR: u32 = 50;
const BASE_TIMESTAMP: i64 = 1_000_000;
const MS_PER_HOUR: i64 = 60 * 60 * 1000;

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

fn insertDataset(world: anytype, readings: []const sb.SensorReading) !void {
    for (readings) |r| try world.insert(r);
}

// ---------------------------------------------------------------------------
// Equivalence tests — every backend must return identical results for every
// implemented query on the same seeded dataset.
//
// RingBuffer: with 50 readings/sensor and 1000 capacity/sensor, all data
// fits in the buffer — no eviction occurs. RingBuffer is expected to agree
// on all queries. (Per its contract, it is excepted on queries that span
// evicted data, but that does not apply here.)
// ---------------------------------------------------------------------------

test "equivalence: query_avg_window across all six backends" {
    const dataset = try generateDataset(std.testing.allocator);
    defer std.testing.allocator.free(dataset);

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

    const tolerance: f32 = 1e-5;

    for (test_cases) |tc| {
        var results: [backends.len]f32 = undefined;

        inline for (0..backends.len) |i| {
            const b = backends[i];
            var world = try World(b.T).init(std.testing.allocator);
            defer world.deinit();
            try insertDataset(&world, dataset);
            results[i] = try queries.query_avg_window(&world, tc.sensor, tc.hours);
        }

        for (1..results.len) |i| {
            try std.testing.expectApproxEqAbs(results[0], results[i], tolerance);
        }
    }
}

test "equivalence: getLatestBySensor across all six backends" {
    const dataset = try generateDataset(std.testing.allocator);
    defer std.testing.allocator.free(dataset);

    for (0..NUM_SENSORS) |s| {
        const sensor: u32 = @intCast(s);
        var results: [backends.len]?sb.SensorReading = undefined;

        inline for (0..backends.len) |i| {
            const b = backends[i];
            var world = try World(b.T).init(std.testing.allocator);
            defer world.deinit();
            try insertDataset(&world, dataset);
            results[i] = world.getLatestBySensor(sensor);
        }

        const ref = results[0];
        for (1..results.len) |i| {
            if (ref) |r| {
                try std.testing.expect(results[i] != null);
                try std.testing.expectEqual(r.timestamp, results[i].?.timestamp);
                try std.testing.expectEqual(r.sensor_id, results[i].?.sensor_id);
                try std.testing.expectApproxEqAbs(r.value, results[i].?.value, 1e-5);
            } else {
                try std.testing.expect(results[i] == null);
            }
        }
    }
}

test "equivalence: rangeByTime across all six backends" {
    const dataset = try generateDataset(std.testing.allocator);
    defer std.testing.allocator.free(dataset);

    const test_cases = [_]struct { sensor: ?u32, start: i64, end: i64 }{
        .{ .sensor = null, .start = BASE_TIMESTAMP, .end = BASE_TIMESTAMP + 10 * MS_PER_HOUR },
        .{ .sensor = 0, .start = BASE_TIMESTAMP, .end = BASE_TIMESTAMP + 24 * MS_PER_HOUR },
        .{ .sensor = 5, .start = BASE_TIMESTAMP, .end = BASE_TIMESTAMP + 50 * MS_PER_HOUR },
        .{ .sensor = null, .start = BASE_TIMESTAMP + 20 * MS_PER_HOUR, .end = BASE_TIMESTAMP + 30 * MS_PER_HOUR },
    };

    for (test_cases) |tc| {
        var lengths: [backends.len]usize = undefined;
        var first_vals: [backends.len]f32 = undefined;
        var last_vals: [backends.len]f32 = undefined;
        var sums: [backends.len]f64 = undefined;

        inline for (0..backends.len) |i| {
            const b = backends[i];
            var world = try World(b.T).init(std.testing.allocator);
            defer world.deinit();
            try insertDataset(&world, dataset);
            const result = try world.rangeByTime(.{
                .sensor_id = tc.sensor,
                .start_time = tc.start,
                .end_time = tc.end,
            });
            defer std.testing.allocator.free(result);

            lengths[i] = result.len;
            if (result.len > 0) {
                first_vals[i] = result[0].value;
                last_vals[i] = result[result.len - 1].value;
                var sum: f64 = 0;
                for (result) |r| sum += @as(f64, r.value);
                sums[i] = sum;
            }
        }

        for (1..backends.len) |i| {
            try std.testing.expectEqual(lengths[0], lengths[i]);
            if (lengths[0] > 0) {
                try std.testing.expectApproxEqAbs(first_vals[0], first_vals[i], 1e-5);
                try std.testing.expectApproxEqAbs(last_vals[0], last_vals[i], 1e-5);
                try std.testing.expectApproxEqAbs(sums[0], sums[i], 1e-3);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Latency table — times every implemented query on every backend and prints
// a combined table.
// ---------------------------------------------------------------------------

test "latency table: query_avg_window across all six backends" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const dataset = try generateDataset(std.testing.allocator);
    defer std.testing.allocator.free(dataset);

    const iterations: u32 = 1000;

    std.debug.print("\n", .{});
    std.debug.print("=== Combined Per-Query Latency Table ===\n", .{});
    std.debug.print("Dataset: {d} sensors x {d} readings = {d} total readings\n", .{
        NUM_SENSORS, READINGS_PER_SENSOR, NUM_SENSORS * READINGS_PER_SENSOR,
    });
    std.debug.print("Iterations per measurement: {d}\n", .{iterations});
    std.debug.print("\n", .{});
    std.debug.print("{s:<20} {s:<15} {s:>12} {s:>10} {s:>12} {s:>10} {s:>12} {s:>10} {s:>12} {s:>10} {s:>14}\n", .{
        "Query",    "Backend",
        "median_ns", "med_µs",
        "p95_ns",   "p95_µs",
        "p99_ns",   "p99_µs",
        "mean_ns",  "mean_µs",
        "throughput",
    });
    std.debug.print("{s:->140}\n", .{""});

    inline for (backends) |b| {
        var world = try World(b.T).init(std.testing.allocator);
        defer world.deinit();
        try insertDataset(&world, dataset);

        const stats = try metrics.timeQuery(
            std.testing.allocator,
            io,
            iterations,
            queries.query_avg_window,
            .{ &world, @as(u32, 0), @as(u32, 24) },
        );

        std.debug.print("{s:<20} {s:<15} {d:>12} {d:>10.1} {d:>12} {d:>10.1} {d:>12} {d:>10.1} {d:>12} {d:>10.1} {d:>12.0}ops/s\n", .{
            "query_avg_window",
            b.name,
            stats.median_ns,
            @as(f64, @floatFromInt(stats.median_ns)) / 1000.0,
            stats.p95_ns,
            @as(f64, @floatFromInt(stats.p95_ns)) / 1000.0,
            stats.p99_ns,
            @as(f64, @floatFromInt(stats.p99_ns)) / 1000.0,
            stats.mean_ns,
            @as(f64, @floatFromInt(stats.mean_ns)) / 1000.0,
            stats.throughputOpsPerSec(),
        });
    }

    std.debug.print("{s:->140}\n", .{""});
    std.debug.print("=== end table ===\n", .{});
}
