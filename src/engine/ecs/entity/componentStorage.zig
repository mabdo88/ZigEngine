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
            // If the entity already has this component, overwrite in place (upsert).
            const existing = self.sparse.items[entity.index];
            if (existing != EMPTY) {
                self.dense.items[existing] = component;
                return;
            }
            const dense_index: u32 = @intCast(self.dense.items.len);
            self.sparse.items[entity.index] = dense_index;
            try self.dense.append(allocator, component);
            try self.entities.append(allocator, entity.index);
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
