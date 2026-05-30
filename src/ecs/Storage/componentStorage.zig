const std = @import("std");
const e = @import("../Entity/entity.zig").Entity;

pub fn ComponentStorage(comptime T: type) type {
    return struct {
        pub const ComponentType = T;
        wardrobe: std.ArrayList(T) = .empty,
        slot: std.ArrayList(u32) = .empty,
        idLabel: std.ArrayList(u32) = .empty,

        const EMPTY: u32 = std.math.maxInt(u32);
        const Self = @This();

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.wardrobe.deinit(allocator);
            self.slot.deinit(allocator);
            self.idLabel.deinit(allocator);
        }
        pub fn attachComponent(self: *Self, allocator: std.mem.Allocator, entity: e, component: T) !void {
            while (self.slot.items.len <= entity.index) {
                try self.slot.append(allocator, EMPTY);
            }
            const wardrobe_index: u32 = @intCast(self.wardrobe.items.len);
            self.slot.items[entity.index] = wardrobe_index;
            try self.wardrobe.append(allocator, component);
            try self.idLabel.append(allocator, entity.index);
        }
        pub fn remove(self: *Self, entity: e) !void {
            if (entity.index >= self.slot.items.len) return;
            const wardrobe_deleted_position = self.slot.items[entity.index];
            if (wardrobe_deleted_position == EMPTY) return;
            if (self.wardrobe.items.len == 0) return;
            const last_slot = self.wardrobe.items.len - 1;
            const last_idLabel = self.idLabel.items[last_slot];
            self.wardrobe.items[wardrobe_deleted_position] = self.wardrobe.items[last_slot];
            self.idLabel.items[wardrobe_deleted_position] = last_idLabel;
            self.slot.items[last_idLabel] = wardrobe_deleted_position;
            self.slot.items[entity.index] = EMPTY;
            _ = self.wardrobe.pop();
            _ = self.idLabel.pop();
        }
        pub fn getByIndex(self: *Self, entity_id: u32) ?*T {
            if (entity_id >= self.slot.items.len) return null;
            const wardrobe_position = self.slot.items[entity_id];
            if (wardrobe_position == EMPTY) return null;
            return &self.wardrobe.items[wardrobe_position];
        }

        pub fn get(self: *Self, entity: e) ?*T {
            return self.getByIndex(entity.index);
        }
        pub fn has(self: *Self, entity: e) bool {
            if (entity.index >= self.slot.items.len) return false;
            return self.slot.items[entity.index] != EMPTY;
        }
    };
}
