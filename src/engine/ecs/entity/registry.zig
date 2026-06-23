const std = @import("std");
const Entity = @import("entity.zig").Entity;
const compstrg = @import("componentStorage.zig");
const components = @import("../components/components.zig");
const event = @import("../event.zig");
const meshCache = @import("../../../resources/meshCache.zig");

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
    component_masks: std.ArrayList(u64) = .empty,
    nextEntityIndex: u32 = 0,
    registry_allocator: std.mem.Allocator = undefined,
    MAX_ENTITIES: u32 = 0,
    storage: StorageType() = undefined,
    events: event.EventBus = undefined,
    mesh_cache: meshCache.MeshCache = undefined,

    pub fn init(allocator: std.mem.Allocator) Registry {
        std.log.info("Initializing Registry", .{});
        var self = Registry{};
        self.registry_allocator = allocator;
        self.MAX_ENTITIES = 1_000_000;
        self.events = event.EventBus.init(allocator);
        self.mesh_cache = meshCache.MeshCache.init(allocator);
        inline for (0..self.storage.len) |i| {
            self.storage[i] = .{};
        }
        std.log.info("Registry Online", .{});
        return self;
    }

    pub fn aliveCount(self: *Registry) usize {
        return self.nextEntityIndex - self.freeList.items.len;
    }
    pub fn deinit(self: *Registry) void {
        inline for (0..self.storage.len) |i| {
            const C = @TypeOf(self.storage[i]).ComponentType;
            if (@hasDecl(C, "deinit")) {
                for (self.storage[i].dense.items) |*comp| {
                    comp.deinit(self.registry_allocator);
                }
            }
            self.storage[i].deinit(self.registry_allocator);
        }
        self.freeList.deinit(self.registry_allocator);
        self.generations.deinit(self.registry_allocator);
        self.component_masks.deinit(self.registry_allocator);
        self.events.deinit();
        self.mesh_cache.deinit();

        std.log.info("Registry Offline", .{});
    }

    pub fn createEntity(self: *Registry) !Entity {
        var entityIndex: u32 = 0;
        if (self.freeList.items.len > 0) {
            entityIndex = self.freeList.pop().?;
        } else {
            entityIndex = self.nextEntityIndex;
            if (entityIndex >= self.MAX_ENTITIES) {
                return error.MaxEntitiesReached;
            }
            try self.generations.append(self.registry_allocator, 0);
            try self.component_masks.append(self.registry_allocator, 0);
            self.nextEntityIndex += 1;
        }
        const generation = self.generations.items[entityIndex];
        return Entity.make(entityIndex, generation);
    }
    pub fn create(self: *Registry) !Entity {
        return self.createEntity();
    }

    pub fn destroyEntity(self: *Registry, entity: Entity) !void {
        if (!self.isAlive(entity)) return error.EntityIsDead;
        const index = entity.index;
        self.events.emit(.{ .entity_destroyed = entity });
        if (self.generations.items[index] == std.math.maxInt(u32)) {
            self.component_masks.items[index] = 0;
        } else {
            self.generations.items[index] += 1;
            self.component_masks.items[index] = 0;
            try self.freeList.append(self.registry_allocator, index);
        }
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
            return false;
        }
        return self.generations.items[index] == entity.generation;
    }
    pub fn attach(self: *Registry, entity: Entity, component: anytype) !void {
        if (!self.isAlive(entity)) return error.EntityIsDead;
        const T = @TypeOf(component);
        const idx = comptime components.ComponentIndex(T);
        try self.storage[idx].attachComponent(self.registry_allocator, entity, component);
        const bit: u64 = comptime components.ComponentBit(T);
        self.component_masks.items[entity.index] |= bit;
    }
    pub fn add(self: *Registry, entity: Entity, component: anytype) !void {
        return self.attach(entity, component);
    }
    pub fn set(self: *Registry, entity: Entity, component: anytype) !void {
        if (!self.isAlive(entity)) return error.EntityIsDead;
        const T = @TypeOf(component);
        const idx = comptime components.ComponentIndex(T);
        if (@hasDecl(T, "deinit")) {
            if (self.storage[idx].get(entity)) |old| {
                old.deinit(self.registry_allocator);
            }
        }
        try self.storage[idx].attachComponent(self.registry_allocator, entity, component);
        const bit: u64 = comptime components.ComponentBit(T);
        self.component_masks.items[entity.index] |= bit;
    }
    pub fn remove(self: *Registry, comptime T: type, entity: Entity) void {
        if (!self.isAlive(entity)) return;
        const idx = comptime components.ComponentIndex(T);
        if (@hasDecl(T, "deinit")) {
            if (self.storage[idx].get(entity)) |component| {
                component.deinit(self.registry_allocator);
            }
        }
        self.storage[idx].remove(entity) catch {};
        const bit: u64 = comptime components.ComponentBit(T);
        self.component_masks.items[entity.index] &= ~bit;
    }
    pub fn QueryIterator(comptime Types: anytype) type {
        return struct {
            registry: *Registry,
            current: usize = 0,
            mask: u64 = undefined,
            primary_entities: []u32 = &.{},

            pub fn init(registry: *Registry) @This() {
                var mask: u64 = 0;
                inline for (Types) |T| {
                    mask |= comptime components.ComponentBit(T);
                }
                var primary_entities: []u32 = &.{};
                var best_len: usize = std.math.maxInt(usize);
                inline for (Types, 0..) |T, i| {
                    _ = i;
                    const storage = &registry.storage[components.ComponentIndex(T)];
                    if (storage.dense.items.len < best_len) {
                        best_len = storage.dense.items.len;
                        primary_entities = storage.entities.items;
                    }
                }
                return .{ .registry = registry, .mask = mask, .primary_entities = primary_entities };
            }

            pub fn next(self: *@This()) ?Entity {
                while (self.current < self.primary_entities.len) {
                    const entity_id = self.primary_entities[self.current];
                    self.current += 1;
                    if (entity_id < self.registry.component_masks.items.len) {
                        const entity_mask = self.registry.component_masks.items[entity_id];
                        if ((entity_mask & self.mask) == self.mask) {
                            return Entity.make(entity_id, self.registry.generations.items[entity_id]);
                        }
                    }
                }
                return null;
            }
        };
    }
    pub fn Query(self: *Registry, comptime Types: anytype) QueryIterator(Types) {
        return QueryIterator(Types).init(self);
    }
    pub fn get(self: *Registry, comptime T: type, entity: Entity) ?*T {
        if (!self.isAlive(entity)) return null;
        return self.storage[components.ComponentIndex(T)].getByIndex(entity.index);
    }
};

test "attach and get component" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = try reg.create();
    const verts = [_]components.Vertex{
        .{ .pos = .{ 0.0, -0.5, 0.0 }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 0.0, 0.0 } },
        .{ .pos = .{ 0.5, 0.5, 0.0 }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 1.0, 0.0 } },
        .{ .pos = .{ -0.5, 0.5, 0.0 }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 0.0, 1.0 } },
    };
    const idx = [_]u32{ 0, 1, 2 };
    const mesh_id = try reg.mesh_cache.register(&verts, &idx);

    try reg.add(entity, components.MeshComponent{ .mesh_id = mesh_id });
    try std.testing.expect(reg.get(components.MeshComponent, entity) != null);

    const mesh = reg.get(components.MeshComponent, entity).?;
    try std.testing.expectEqual(mesh_id, mesh.mesh_id);
}

test "attach and destroy cleans storage" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = try reg.create();
    const verts = [_]components.Vertex{
        .{ .pos = .{ 0.0, 0.0, 0.0 }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 0.0, 0.0 } },
    };
    const idx = [_]u32{0};
    const mesh_id = try reg.mesh_cache.register(&verts, &idx);

    try reg.add(entity, components.MeshComponent{ .mesh_id = mesh_id });
    try std.testing.expect(reg.get(components.MeshComponent, entity) != null);

    try reg.destroyEntity(entity);
    try std.testing.expect(reg.get(components.MeshComponent, entity) == null);
    try std.testing.expect(!reg.isAlive(entity));
}

test "attach transform component" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = try reg.create();
    try reg.add(entity, components.TransformComponent{
        .position = .{ 1.0, 2.0, 3.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    try std.testing.expect(reg.get(components.TransformComponent, entity) != null);

    const transform = reg.get(components.TransformComponent, entity).?;
    try std.testing.expectEqual(@as(f32, 1.0), transform.position[0]);
}

test "remove component clears the bit" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = try reg.create();
    try reg.add(entity, components.ScenePendingTag{});
    try std.testing.expect(reg.get(components.ScenePendingTag, entity) != null);
    reg.remove(components.ScenePendingTag, entity);
    try std.testing.expect(reg.get(components.ScenePendingTag, entity) == null);

    var it = reg.Query(.{components.ScenePendingTag});
    try std.testing.expect(it.next() == null);
}

test "creation and destruction of entities one by one" {
    var test_registry = Registry.init(std.testing.allocator);
    defer test_registry.deinit();
    const entity1 = try test_registry.create();
    try std.testing.expect(test_registry.aliveCount() == 1);
    const entity2 = try test_registry.create();
    try std.testing.expect(test_registry.isAlive(entity1) == true);
    try std.testing.expect(test_registry.isAlive(entity2) == true);
    try test_registry.destroyEntity(entity1);
    try std.testing.expect(test_registry.isAlive(entity1) == false);
    try std.testing.expect(test_registry.aliveCount() == 1);
    const entity3 = try test_registry.create();
    try std.testing.expect(test_registry.isAlive(entity3) == true);
    try std.testing.expect(test_registry.aliveCount() == 2);
}

test "query entities with mesh and transform" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity1 = try reg.create();
    const entity2 = try reg.create();

    const verts = [_]components.Vertex{
        .{ .pos = .{ 0.0, 0.0, 0.0 }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 0.0, 0.0 } },
    };
    const idx = [_]u32{0};
    const mesh_id = try reg.mesh_cache.register(&verts, &idx);

    try reg.add(entity1, components.MeshComponent{ .mesh_id = mesh_id });
    try reg.add(entity1, components.TransformComponent{
        .position = .{ 1.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });

    try reg.add(entity2, components.MeshComponent{ .mesh_id = mesh_id });

    var it = reg.Query(.{ components.MeshComponent, components.TransformComponent });
    var count: u32 = 0;
    while (it.next()) |entity| {
        count += 1;
        try std.testing.expectEqual(entity1.index, entity.index);
    }
    try std.testing.expectEqual(@as(u32, 1), count);
}

test "entity recycling increments generation" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const e1 = try reg.create();
    try reg.destroyEntity(e1);
    const e2 = try reg.create();

    // Same index, different generation
    try std.testing.expectEqual(e1.index, e2.index);
    try std.testing.expect(e1.generation < e2.generation);
    try std.testing.expect(!reg.isAlive(e1));
    try std.testing.expect(reg.isAlive(e2));
}

test "stale handle cannot access or destroy recycled entity" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const e1 = try reg.create();
    try reg.add(e1, components.TransformComponent{
        .position = .{ 1.0, 2.0, 3.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    try reg.destroyEntity(e1);

    // Recycle the index — e2 has the same index but a new generation.
    const e2 = try reg.create();
    try std.testing.expectEqual(e1.index, e2.index);
    try std.testing.expect(reg.isAlive(e2));

    // Stale handle e1 must not see e2's (empty) components.
    try std.testing.expect(reg.get(components.TransformComponent, e1) == null);

    // Stale handle e1 must not destroy e2.
    const result = reg.destroyEntity(e1);
    try std.testing.expectError(error.EntityIsDead, result);
    try std.testing.expect(reg.isAlive(e2));

    // Stale handle e1 must not remove components from e2.
    reg.remove(components.TransformComponent, e1);
    try std.testing.expect(reg.isAlive(e2));
}

test "re-add component to recycled entity works" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const e1 = try reg.create();
    try reg.add(e1, components.TransformComponent{
        .position = .{ 1.0, 2.0, 3.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    try reg.destroyEntity(e1);

    const e2 = try reg.create();
    try std.testing.expectEqual(e1.index, e2.index);
    try std.testing.expect(reg.get(components.TransformComponent, e2) == null);

    try reg.add(e2, components.TransformComponent{
        .position = .{ 4.0, 5.0, 6.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    const transform = reg.get(components.TransformComponent, e2).?;
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), transform.position[0], 1e-5);
}

test "query with tag components" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const scene1 = try reg.create();
    try reg.add(scene1, components.SceneComponent{ .name = "A", .path = "" });
    try reg.add(scene1, components.SceneActiveTag{});

    const scene2 = try reg.create();
    try reg.add(scene2, components.SceneComponent{ .name = "B", .path = "" });

    var active_it = reg.Query(.{ components.SceneComponent, components.SceneActiveTag });
    const active = active_it.next().?;
    try std.testing.expectEqual(scene1.index, active.index);
    try std.testing.expect(active_it.next() == null);
}

test "attach to dead entity fails" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = try reg.create();
    try reg.destroyEntity(entity);

    const result = reg.add(entity, components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    try std.testing.expectError(error.EntityIsDead, result);
}

test "destroy emits entity_destroyed event" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const Counter = struct {
        count: *u32,
        fn cb(ctx: *anyopaque, payload: event.EventPayload) void {
            _ = payload;
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.count.* += 1;
        }
    };

    var count: u32 = 0;
    var counter = Counter{ .count = &count };
    try reg.events.subscribe(.entity_destroyed, &counter, Counter.cb);

    const entity = try reg.create();
    try reg.destroyEntity(entity);

    try std.testing.expectEqual(@as(u32, 1), count);
}

test "overwrite component via set" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = try reg.create();
    try reg.add(entity, components.TransformComponent{
        .position = .{ 1.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });
    try reg.set(entity, components.TransformComponent{
        .position = .{ 9.0, 8.0, 7.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });

    const transform = reg.get(components.TransformComponent, entity).?;
    try std.testing.expectApproxEqAbs(@as(f32, 9.0), transform.position[0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), transform.position[1], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 7.0), transform.position[2], 1e-5);
}

test "set deinit old owned component before overwrite" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = try reg.create();
    const pixels1 = try std.testing.allocator.alloc(u8, 4);
    pixels1[0] = 255;
    pixels1[1] = 0;
    pixels1[2] = 0;
    pixels1[3] = 255;

    try reg.add(entity, components.TextureDataComponent{ .material_id = 1, .pixels = pixels1, .width = 1, .height = 1 });

    const pixels2 = try std.testing.allocator.alloc(u8, 4);
    pixels2[0] = 0;
    pixels2[1] = 255;
    pixels2[2] = 0;
    pixels2[3] = 255;

    // set should deinit the old TextureDataComponent (freeing pixels1) before overwriting.
    try reg.set(entity, components.TextureDataComponent{ .material_id = 1, .pixels = pixels2, .width = 1, .height = 1 });

    const td = reg.get(components.TextureDataComponent, entity).?;
    try std.testing.expectEqual(@as(u8, 0), td.pixels[0]);
}

test "query returns empty when no entities match" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    var it = reg.Query(.{components.CameraComponent});
    try std.testing.expect(it.next() == null);
}

test "multiple entities with same component all found by query" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    var entities: [5]Entity = undefined;
    for (&entities) |*e| {
        e.* = try reg.create();
        try reg.add(e.*, components.TransformComponent{
            .position = .{ 0.0, 0.0, 0.0 },
            .rotation = .{ 0.0, 0.0, 0.0 },
            .scale = .{ 1.0, 1.0, 1.0 },
        });
    }

    var it = reg.Query(.{components.TransformComponent});
    var count: u32 = 0;
    while (it.next()) |_| count += 1;
    try std.testing.expectEqual(@as(u32, 5), count);
}

test "get returns null for unregistered component type on entity" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = try reg.create();
    try std.testing.expect(reg.get(components.CameraComponent, entity) == null);
}

// P3: At max generation, destroyEntity increments (wraps to 0 in wrapping mode,
// traps in safe mode). The slot should be retired without wrapping or trapping.
test "generation overflow retires slot without wrapping" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = try reg.create();
    // Simulate generation reaching max by setting both the slot and the handle
    reg.generations.items[entity.index] = std.math.maxInt(u32);
    const max_gen_entity = Entity.make(entity.index, std.math.maxInt(u32));

    // This must not trap (safe mode) or wrap to 0
    try reg.destroyEntity(max_gen_entity);

    // Slot must not be recycled — a new entity should get a different index
    const new_entity = try reg.create();
    try std.testing.expect(new_entity.index != entity.index);
}

// Edge case: Multiple entities created after a retired slot should all skip it.
test "retired slot is permanently skipped by create" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const e0 = try reg.create();
    _ = try reg.create();

    // Set e0's generation to max BEFORE destroying, then destroy
    reg.generations.items[e0.index] = std.math.maxInt(u32);
    const max_e0 = Entity.make(e0.index, std.math.maxInt(u32));
    try reg.destroyEntity(max_e0);

    // Create several more entities — none should reuse e0's index
    for (0..5) |_| {
        const new_e = try reg.create();
        try std.testing.expect(new_e.index != e0.index);
    }
}

// Edge case: Normal entity recycling still works alongside a retired slot.
test "normal recycling works alongside retired slot" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const e0 = try reg.create();
    const e1 = try reg.create();
    const e2 = try reg.create();

    // Retire e1's slot
    reg.generations.items[e1.index] = std.math.maxInt(u32);
    const max_e1 = Entity.make(e1.index, std.math.maxInt(u32));
    try reg.destroyEntity(max_e1);

    // Destroy e0 and e2 normally — they should be recycled
    try reg.destroyEntity(e0);
    try reg.destroyEntity(e2);

    // Next create should reuse e0 or e2 (not e1)
    const new_e = try reg.create();
    try std.testing.expect(new_e.index == e0.index or new_e.index == e2.index);
    try std.testing.expect(new_e.index != e1.index);
    try std.testing.expect(new_e.generation > 0);
}
