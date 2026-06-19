const std = @import("std");
const Entity = @import("../Entity/entity.zig").Entity;
const compstrg = @import("componentStorage.zig");
const components = @import("../Component/components.zig");
fn StorageType() type {
    var types: [components.AllComponents.len]type = undefined;
    inline for (components.AllComponents, 0..) |C, i| {
        types[i] = compstrg.ComponentStorage(C);
    }
    return std.meta.Tuple(&types);
}
pub const Registry = struct {
    freeList: std.ArrayList(u32) = .empty,
    generations: std.ArrayList(u32) = .empty,
    nextEntityIndex: u32 = 0,
    registry_allocator: std.mem.Allocator = undefined,
    MAX_ENTITIES: u32 = 0, // 2^24 entities
    storage: StorageType() = undefined,
    pub fn aliveCount(self: *Registry) usize {
        return self.nextEntityIndex - self.freeList.items.len;
    }
    pub fn init(self: *Registry, allocator: std.mem.Allocator) void {
        std.log.info("Initializing Registry", .{});
        self.freeList = .empty;
        self.generations = .empty;
        self.registry_allocator = allocator;
        self.nextEntityIndex = 0;
        self.MAX_ENTITIES = 1_000_000; // 2^24 entities
        std.log.info("Registry Online", .{});
        inline for (0..self.storage.len) |i| {
            self.storage[i] = .{};
        }
    }
    pub fn deinit(self: *Registry) void {
        inline for (0..self.storage.len) |i| {
            self.storage[i].deinit(self.registry_allocator);
        }
        self.freeList.deinit(self.registry_allocator);
        self.generations.deinit(self.registry_allocator);

        std.log.info("Registry Offline", .{});
    }
    pub fn createEntity(self: *Registry) Entity {
        var entityIndex: u32 = 0;
        if (self.freeList.items.len > 0) {
            entityIndex = self.freeList.pop().?; // Reuse index from free list
        } else {
            entityIndex = self.nextEntityIndex;
            self.nextEntityIndex += 1;
            if (entityIndex >= self.MAX_ENTITIES) {
                std.debug.panic("Maximum number of entities reached", .{});
            }
            self.generations.append(self.registry_allocator, 0) catch unreachable; // Initialize generation for new entity
        }
        const generation = self.generations.items[entityIndex];
        return Entity.make(entityIndex, generation);
    }
    pub fn destroyEntity(self: *Registry, entity: Entity) void {
        const index = entity.index;
        if (index >= self.generations.items.len) {
            std.debug.panic("Invalid entity index", .{});
        }
        self.generations.items[index] += 1; // Increment generation to invalidate old references
        self.freeList.append(self.registry_allocator, index) catch unreachable; // Add index back to free list
        inline for (0..self.storage.len) |i| {
            const C = @TypeOf(self.storage[i]).ComponentType;
            if (@hasDecl(C, "deinit")) {
                if (self.storage[i].get(entity)) |component| {
                    component.deinit(self.registry_allocator);
                }
            }
            self.storage[i].remove(entity) catch {};
        }
    }
    pub fn isAlive(self: *Registry, entity: Entity) bool {
        const index = entity.index;
        if (index >= self.generations.items.len) {
            return false; // Out of bounds index means entity is not alive
        }
        const generation = self.generations.items[index];
        //return generation == Entity.getGeneration(entity); // Check if generation matches
        return generation == entity.generation; // Check if generation matches
    }
    pub fn attach(self: *Registry, entity: Entity, component: anytype) !void {
        if (!self.isAlive(entity)) return error.EntityIsDead;
        const T = @TypeOf(component);
        inline for (0..self.storage.len) |i| {
            if (T == @TypeOf(self.storage[i]).ComponentType) {
                try self.storage[i].attachComponent(self.registry_allocator, entity, component);
                return;
            }
        }
    }
    fn indexOfType(comptime T: type) comptime_int {
        inline for (components.AllComponents, 0..) |C, i| {
            if (C == T) return i;
        }
        @compileError("Unregistered component type");
    }
    pub fn QueryIterator(comptime Types: anytype) type {
        return struct {
            registry: *Registry,
            current: usize = 0,
            pub fn next(self: *@This()) ?u32 {
                const primary = &self.registry.storage[indexOfType(Types[0])];
                while (self.current < primary.wardrobe.items.len) {
                    const entity_id = primary.idLabel.items[self.current];
                    self.current += 1;
                    var found = true;
                    inline for (1..Types.len) |i| {
                        if (self.registry.storage[indexOfType(Types[i])].getByIndex(entity_id) == null) {
                            found = false;
                        }
                    }
                    if (found) return entity_id;
                }
                return null;
            }
        };
    }
    pub fn Query(self: *Registry, comptime Types: anytype) QueryIterator(Types) {
        return QueryIterator(Types){ .registry = self };
    }
    pub fn get(self: *Registry, comptime T: type, entity_id: u32) ?*T {
        return self.storage[indexOfType(T)].getByIndex(entity_id);
    }
};

test "attach and get component" {
    var reg: Registry = .{};
    reg.init(std.testing.allocator);
    defer reg.deinit();

    const entity = reg.createEntity();
    const verts = [_]components.Vertex{
        .{ .pos = .{ 0.0, -0.5, 0.0 }, .color = .{ 1.0, 0.0, 0.0 } },
        .{ .pos = .{ 0.5, 0.5, 0.0 }, .color = .{ 0.0, 1.0, 0.0 } },
        .{ .pos = .{ -0.5, 0.5, 0.0 }, .color = .{ 0.0, 0.0, 1.0 } },
    };
    const idx = [_]u32{ 0, 1, 2 };

    try reg.attach(entity, components.MeshComponent{ .vertices = &verts, .indices = &idx });
    try std.testing.expect(reg.storage[0].has(entity));

    const mesh = reg.storage[0].get(entity).?;
    try std.testing.expectEqual(@as(usize, 3), mesh.vertices.len);
}

test "attach and destroy cleans storage" {
    var reg: Registry = .{};
    reg.init(std.testing.allocator);
    defer reg.deinit();

    const entity = reg.createEntity();
    const verts = [_]components.Vertex{
        .{ .pos = .{ 0.0, 0.0, 0.0 }, .color = .{ 1.0, 1.0, 1.0 } },
    };
    const idx = [_]u32{0};

    try reg.attach(entity, components.MeshComponent{ .vertices = &verts, .indices = &idx });
    try std.testing.expect(reg.storage[0].has(entity));

    reg.destroyEntity(entity);
    try std.testing.expect(!reg.storage[0].has(entity));
    try std.testing.expect(!reg.isAlive(entity));
}

test "attach transform component" {
    var reg: Registry = .{};
    reg.init(std.testing.allocator);
    defer reg.deinit();

    const entity = reg.createEntity();
    try reg.attach(entity, components.TransformComponent{
        .position = .{ 1.0, 2.0, 3.0 },
        .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    try std.testing.expect(reg.storage[1].has(entity));

    const transform = reg.storage[1].get(entity).?;
    try std.testing.expectEqual(@as(f32, 1.0), transform.position[0]);
}
test "creation and destruction of entities one by one" {
    var test_registry: Registry = .{};
    test_registry.init(std.testing.allocator);
    defer test_registry.deinit();
    const entity1 = test_registry.createEntity();
    std.debug.print("Entity1 Index: {d}, Generation: {d}\n", .{ entity1.index, entity1.generation });
    try std.testing.expect(test_registry.aliveCount() == 1);
    const entity2 = test_registry.createEntity();
    std.debug.print("Entity2 Index: {d}, Generation: {d}\n", .{ entity2.index, entity2.generation });
    try std.testing.expect(test_registry.isAlive(entity1) == true);
    try std.testing.expect(test_registry.isAlive(entity2) == true);
    test_registry.destroyEntity(entity1);
    try std.testing.expect(test_registry.isAlive(entity1) == false);
    try std.testing.expect(test_registry.aliveCount() == 1);
    std.debug.print("Entity1 Index: {d}, Generation: {d}\n", .{ entity1.index, entity1.generation });
    std.debug.print("Entity2 Index: {d}, Generation: {d}\n", .{ entity2.index, entity2.generation });
    const entity3 = test_registry.createEntity();
    std.debug.print("Entity3 Index: {d}, Generation: {d}\n", .{ entity3.index, entity3.generation });
    try std.testing.expect(test_registry.isAlive(entity3) == true);
    try std.testing.expect(test_registry.aliveCount() == 2);
}

test "batch creation and destruction of entities" {
    var test_registry: Registry = .{};
    test_registry.init(std.testing.allocator);
    defer test_registry.deinit();

    var entities: [10]Entity = undefined;
    for (0..10) |i| {
        entities[i] = test_registry.createEntity();
        std.debug.print("Created Entity Index: {d}, Generation: {d}\n", .{ entities[i].index, entities[i].generation });
    }
    try std.testing.expect(test_registry.aliveCount() == 10);

    for (3..8) |i| {
        test_registry.destroyEntity(entities[i]);
        std.debug.print("Destroyed Entity Index: {d}, Generation: {d}\n", .{ entities[i].index, entities[i].generation });
    }
    try std.testing.expect(test_registry.aliveCount() == 5);

    var recycled: [5]Entity = undefined;
    for (0..5) |i| {
        recycled[i] = test_registry.createEntity();
        std.debug.print("Recycled Entity Index: {d}, Generation: {d}\n", .{ recycled[i].index, recycled[i].generation });
    }
    try std.testing.expect(test_registry.aliveCount() == 10);
    for (3..8) |i| {
        try std.testing.expect(test_registry.isAlive(entities[i]) == false);
        std.debug.print("Old Entity Index: {d}, Generation: {d}, Alive: {}\n", .{ entities[i].index, entities[i].generation, test_registry.isAlive(entities[i]) });
    }
}
test "query entities with mesh and transform" {
    var reg: Registry = .{};
    reg.init(std.testing.allocator);
    defer reg.deinit();

    const entity1 = reg.createEntity();
    const entity2 = reg.createEntity();

    const verts = [_]components.Vertex{
        .{ .pos = .{ 0.0, 0.0, 0.0 }, .color = .{ 1.0, 0.0, 0.0 } },
    };
    const idx = [_]u32{0};

    // entity1 gets both Mesh and Transform
    try reg.attach(entity1, components.MeshComponent{ .vertices = &verts, .indices = &idx });
    try reg.attach(entity1, components.TransformComponent{
        .position = .{ 1.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });

    // entity2 gets only Mesh
    try reg.attach(entity2, components.MeshComponent{ .vertices = &verts, .indices = &idx });

    var it = reg.Query(.{ components.MeshComponent, components.TransformComponent });
    var count: u32 = 0;
    while (it.next()) |entity_id| {
        count += 1;
        try std.testing.expectEqual(entity1.index, entity_id);
    }
    try std.testing.expectEqual(@as(u32, 1), count);
}
test "entity recycling produces different mesh pointers" {
    var reg: Registry = .{};
    reg.init(std.testing.allocator);
    defer reg.deinit();

    const vertsA = [_]components.Vertex{
        .{ .pos = .{ 0.0, -0.5, 0.0 }, .color = .{ 1.0, 0.0, 0.0 } },
    };
    const vertsB = [_]components.Vertex{
        .{ .pos = .{ 0.0, -0.5, 0.0 }, .color = .{ 0.0, 1.0, 0.0 } },
    };
    const idx = [_]u32{0};

    const e1 = reg.createEntity();
    try reg.attach(e1, components.MeshComponent{ .vertices = &vertsA, .indices = &idx });

    const mesh1 = reg.get(components.MeshComponent, e1.index).?;
    const ptr1 = mesh1.vertices.ptr;

    reg.destroyEntity(e1);

    const e2 = reg.createEntity();
    try std.testing.expectEqual(e1.index, e2.index); // same index, recycled
    try std.testing.expect(e1.generation != e2.generation); // different generation

    try reg.attach(e2, components.MeshComponent{ .vertices = &vertsB, .indices = &idx });

    const mesh2 = reg.get(components.MeshComponent, e2.index).?;
    const ptr2 = mesh2.vertices.ptr;

    try std.testing.expect(ptr1 != ptr2); // different mesh data -> different pointer
}
