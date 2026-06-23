const std = @import("std");
const e = @import("entity.zig").Entity;

pub fn ComponentStorage(comptime T: type) type {
    return struct {
        pub const ComponentType = T;
        dense: std.ArrayList(T) = .empty,
        sparse: std.ArrayList(u32) = .empty,
        entities: std.ArrayList(u32) = .empty,

        const EMPTY: u32 = std.math.maxInt(u32);
        const Self = @This();

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.dense.deinit(allocator);
            self.sparse.deinit(allocator);
            self.entities.deinit(allocator);
        }
        pub fn attachComponent(self: *Self, allocator: std.mem.Allocator, entity: e, component: T) !void {
            while (self.sparse.items.len <= entity.index) {
                try self.sparse.append(allocator, EMPTY);
            }
            const existing = self.sparse.items[entity.index];
            if (existing != EMPTY) {
                self.dense.items[existing] = component;
                return;
            }
            const dense_index: u32 = @intCast(self.dense.items.len);
            try self.dense.append(allocator, component);
            errdefer self.dense.shrinkRetainingCapacity(self.dense.items.len - 1);
            try self.entities.append(allocator, entity.index);
            self.sparse.items[entity.index] = dense_index;
        }
        pub fn remove(self: *Self, entity: e) !void {
            if (entity.index >= self.sparse.items.len) return;
            const dense_deleted_position = self.sparse.items[entity.index];
            if (dense_deleted_position == EMPTY) return;
            if (self.dense.items.len == 0) return;
            const last_index = self.dense.items.len - 1;
            const last_entity = self.entities.items[last_index];
            self.dense.items[dense_deleted_position] = self.dense.items[last_index];
            self.entities.items[dense_deleted_position] = last_entity;
            self.sparse.items[last_entity] = dense_deleted_position;
            self.sparse.items[entity.index] = EMPTY;
            _ = self.dense.pop();
            _ = self.entities.pop();
        }
        pub fn getByIndex(self: *Self, entity_id: u32) ?*T {
            if (entity_id >= self.sparse.items.len) return null;
            const dense_position = self.sparse.items[entity_id];
            if (dense_position == EMPTY) return null;
            return &self.dense.items[dense_position];
        }

        pub fn get(self: *Self, entity: e) ?*T {
            return self.getByIndex(entity.index);
        }
        pub fn has(self: *Self, entity: e) bool {
            if (entity.index >= self.sparse.items.len) return false;
            return self.sparse.items[entity.index] != EMPTY;
        }
    };
}

test "attach and get component" {
    const TestComp = struct { value: u32 };
    var storage = ComponentStorage(TestComp){};
    defer storage.deinit(std.testing.allocator);

    const entity = e.make(0, 0);
    try storage.attachComponent(std.testing.allocator, entity, .{ .value = 42 });

    const comp = storage.get(entity).?;
    try std.testing.expectEqual(@as(u32, 42), comp.value);
}

test "remove component" {
    const TestComp = struct { value: u32 };
    var storage = ComponentStorage(TestComp){};
    defer storage.deinit(std.testing.allocator);

    const entity = e.make(0, 0);
    try storage.attachComponent(std.testing.allocator, entity, .{ .value = 42 });
    try storage.remove(entity);

    try std.testing.expect(storage.get(entity) == null);
    try std.testing.expect(!storage.has(entity));
}

test "has component check" {
    const TestComp = struct { value: u32 };
    var storage = ComponentStorage(TestComp){};
    defer storage.deinit(std.testing.allocator);

    const entity = e.make(0, 0);
    try std.testing.expect(!storage.has(entity));
    try storage.attachComponent(std.testing.allocator, entity, .{ .value = 1 });
    try std.testing.expect(storage.has(entity));
}

test "attach overwrites existing component" {
    const TestComp = struct { value: u32 };
    var storage = ComponentStorage(TestComp){};
    defer storage.deinit(std.testing.allocator);

    const entity = e.make(0, 0);
    try storage.attachComponent(std.testing.allocator, entity, .{ .value = 10 });
    try storage.attachComponent(std.testing.allocator, entity, .{ .value = 99 });

    const comp = storage.get(entity).?;
    try std.testing.expectEqual(@as(u32, 99), comp.value);
    try std.testing.expectEqual(@as(usize, 1), storage.dense.items.len);
}

test "get returns null for non-existent entity" {
    const TestComp = struct { value: u32 };
    var storage = ComponentStorage(TestComp){};
    defer storage.deinit(std.testing.allocator);

    const entity = e.make(0, 0);
    try std.testing.expect(storage.get(entity) == null);

    try storage.attachComponent(std.testing.allocator, entity, .{ .value = 1 });
    const other = e.make(1, 0);
    try std.testing.expect(storage.get(other) == null);
}

test "remove preserves other entities via swap" {
    const TestComp = struct { value: u32 };
    var storage = ComponentStorage(TestComp){};
    defer storage.deinit(std.testing.allocator);

    const e0 = e.make(0, 0);
    const e1 = e.make(1, 0);
    try storage.attachComponent(std.testing.allocator, e0, .{ .value = 100 });
    try storage.attachComponent(std.testing.allocator, e1, .{ .value = 200 });

    try storage.remove(e0);

    try std.testing.expect(storage.get(e0) == null);
    const comp = storage.get(e1).?;
    try std.testing.expectEqual(@as(u32, 200), comp.value);
}

const FailingAllocator = struct {
    backing: std.mem.Allocator,
    fail_after: usize,
    n_allocs: usize = 0,

    fn init(backing: std.mem.Allocator, fail_after: usize) FailingAllocator {
        return .{ .backing = backing, .fail_after = fail_after };
    }

    fn allocator(self: *FailingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = allocFn,
                .resize = resizeFn,
                .remap = remapFn,
                .free = freeFn,
            },
        };
    }

    fn allocFn(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self: *FailingAllocator = @ptrCast(@alignCast(ctx));
        self.n_allocs += 1;
        if (self.n_allocs > self.fail_after) return null;
        return self.backing.rawAlloc(len, alignment, ra);
    }

    fn resizeFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) bool {
        const self: *FailingAllocator = @ptrCast(@alignCast(ctx));
        return self.backing.rawResize(memory, alignment, new_len, ra);
    }

    fn remapFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
        const self: *FailingAllocator = @ptrCast(@alignCast(ctx));
        return self.backing.rawRemap(memory, alignment, new_len, ra);
    }

    fn freeFn(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self: *FailingAllocator = @ptrCast(@alignCast(ctx));
        self.backing.rawFree(memory, alignment, ra);
    }
};

test "attachComponent does not corrupt sparse when dense.append fails" {
    const TestComp = struct { value: u32 };
    var fail_alloc = FailingAllocator.init(std.testing.allocator, 1);
    const alloc = fail_alloc.allocator();

    var storage = ComponentStorage(TestComp){};
    defer storage.deinit(std.testing.allocator);

    const entity = e.make(0, 0);
    const result = storage.attachComponent(alloc, entity, .{ .value = 42 });
    try std.testing.expectError(error.OutOfMemory, result);

    try std.testing.expect(!storage.has(entity));
    try std.testing.expect(storage.get(entity) == null);
}

test "attachComponent does not corrupt sparse when entities.append fails" {
    const TestComp = struct { value: u32 };
    var fail_alloc = FailingAllocator.init(std.testing.allocator, 2);
    const alloc = fail_alloc.allocator();

    var storage = ComponentStorage(TestComp){};
    defer storage.deinit(std.testing.allocator);

    const entity = e.make(0, 0);
    const result = storage.attachComponent(alloc, entity, .{ .value = 42 });
    try std.testing.expectError(error.OutOfMemory, result);

    try std.testing.expect(!storage.has(entity));
    try std.testing.expect(storage.get(entity) == null);
    try std.testing.expectEqual(@as(usize, 0), storage.dense.items.len);
}

test "attachComponent succeeds after prior failure" {
    const TestComp = struct { value: u32 };
    var fail_alloc = FailingAllocator.init(std.testing.allocator, 1);
    const alloc = fail_alloc.allocator();

    var storage = ComponentStorage(TestComp){};
    defer storage.deinit(std.testing.allocator);

    const entity = e.make(0, 0);
    const result = storage.attachComponent(alloc, entity, .{ .value = 42 });
    try std.testing.expectError(error.OutOfMemory, result);

    try storage.attachComponent(std.testing.allocator, entity, .{ .value = 99 });
    try std.testing.expect(storage.has(entity));
    try std.testing.expectEqual(@as(u32, 99), storage.get(entity).?.value);
}

test "attachComponent failure does not affect other entities" {
    const TestComp = struct { value: u32 };
    var storage = ComponentStorage(TestComp){};
    defer storage.deinit(std.testing.allocator);

    const e0 = e.make(0, 0);
    const e1 = e.make(100, 0);
    try storage.attachComponent(std.testing.allocator, e0, .{ .value = 100 });

    var fail_alloc = FailingAllocator.init(std.testing.allocator, 0);
    const alloc = fail_alloc.allocator();
    const result = storage.attachComponent(alloc, e1, .{ .value = 200 });
    try std.testing.expectError(error.OutOfMemory, result);

    try std.testing.expect(storage.has(e0));
    try std.testing.expectEqual(@as(u32, 100), storage.get(e0).?.value);
    try std.testing.expect(!storage.has(e1));
}

test "re-attach after remove works" {
    const TestComp = struct { value: u32 };
    var storage = ComponentStorage(TestComp){};
    defer storage.deinit(std.testing.allocator);

    const entity = e.make(5, 0);
    try storage.attachComponent(std.testing.allocator, entity, .{ .value = 10 });
    try storage.remove(entity);
    try std.testing.expect(!storage.has(entity));

    try storage.attachComponent(std.testing.allocator, entity, .{ .value = 20 });
    try std.testing.expect(storage.has(entity));
    try std.testing.expectEqual(@as(u32, 20), storage.get(entity).?.value);
}
