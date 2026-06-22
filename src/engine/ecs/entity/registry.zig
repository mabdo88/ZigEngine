const std = @import("std");
const Entity = @import("entity.zig").Entity;
const compstrg = @import("componentStorage.zig");
const components = @import("../components/components.zig");
fn StorageType() type {
    var types: [components.AllComponents.len]type = undefined;
    inline for (components.AllComponents, 0..) |C, i| {
        types[i] = compstrg.ComponentStorage(C);
    }
    return std.meta.Tuple(&types);
}
/// Called when an entity is destroyed, so external owners of per-entity
/// resources (e.g. the renderer's GPU buffers) can release them. `ctx` is the
/// opaque pointer registered via `setDestroyHook`.
pub const EntityDestroyedFn = *const fn (ctx: *anyopaque, entity: Entity) void;
pub const Registry = struct {
    freeList: std.ArrayList(u32) = .empty,
    generations: std.ArrayList(u32) = .empty,
    component_masks: std.ArrayList(u64) = .empty,
    nextEntityIndex: u32 = 0,
    registry_allocator: std.mem.Allocator = undefined,
    MAX_ENTITIES: u32 = 0,
    storage: StorageType() = undefined,
    destroy_ctx: ?*anyopaque = null,
    destroy_fn: ?EntityDestroyedFn = null,

    /// Construct an initialized registry. Caller owns it and must call deinit.
    pub fn init(allocator: std.mem.Allocator) Registry {
        std.log.info("Initializing Registry", .{});
        var self = Registry{};
        self.registry_allocator = allocator;
        self.MAX_ENTITIES = 1_000_000;
        inline for (0..self.storage.len) |i| {
            self.storage[i] = .{};
        }
        std.log.info("Registry Online", .{});
        return self;
    }

    pub fn setDestroyHook(self: *Registry, ctx: *anyopaque, func: EntityDestroyedFn) void {
        self.destroy_ctx = ctx;
        self.destroy_fn = func;
    }
    pub fn clearDestroyHook(self: *Registry) void {
        self.destroy_ctx = null;
        self.destroy_fn = null;
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

        std.log.info("Registry Offline", .{});
    }

    /// Allocate a new entity handle (recycling a freed index when possible).
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
    /// Alias matching the new ECS API.
    pub fn create(self: *Registry) !Entity {
        return self.createEntity();
    }

    pub fn destroyEntity(self: *Registry, entity: Entity) !void {
        const index = entity.index;
        if (index >= self.generations.items.len) {
            return error.InvalidEntityIndex;
        }
        if (self.destroy_fn) |func| func(self.destroy_ctx.?, entity);
        if (self.generations.items[index] == std.math.maxInt(u32)) {
            self.generations.items[index] += 1; // wraps to 0, retiring the index
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
        const idx = comptime indexOfType(T);
        try self.storage[idx].attachComponent(self.registry_allocator, entity, component);
        const bit: u64 = @intFromEnum(comptime componentBit(T));
        self.component_masks.items[entity.index] |= bit;
    }
    /// Alias matching the new ECS API.
    pub fn add(self: *Registry, entity: Entity, component: anytype) !void {
        return self.attach(entity, component);
    }
    /// Upsert a component (attach or overwrite in place).
    pub fn set(self: *Registry, entity: Entity, component: anytype) !void {
        return self.attach(entity, component);
    }
    /// Remove a component of type T from the entity if present.
    pub fn remove(self: *Registry, comptime T: type, entity: Entity) void {
        if (entity.index >= self.component_masks.items.len) return;
        const idx = comptime indexOfType(T);
        // Run the component's deinit if it owns resources.
        if (@hasDecl(T, "deinit")) {
            if (self.storage[idx].get(entity)) |component| {
                component.deinit(self.registry_allocator);
            }
        }
        self.storage[idx].remove(entity) catch {};
        const bit: u64 = @intFromEnum(comptime componentBit(T));
        self.component_masks.items[entity.index] &= ~bit;
    }
    fn componentBit(comptime T: type) @import("entity.zig").ComponentBits {
        if (T == components.MeshComponent) return .Mesh;
        if (T == components.TransformComponent) return .Transform;
        if (T == components.WorldTransformComponent) return .WorldTransform;
        if (T == components.CameraComponent) return .Camera;
        if (T == components.TextureComponent) return .Texture;
        if (T == components.SceneComponent) return .Scene;
        if (T == components.SceneActiveTag) return .SceneActive;
        if (T == components.ScenePendingTag) return .ScenePending;
        if (T == components.SceneOwnedComponent) return .SceneOwned;
        if (T == components.CameraMatricesComponent) return .CameraMatrices;
        if (T == components.TextureDataComponent) return .TextureData;
        @compileError("Unknown component type");
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
            mask: u64 = undefined,

            pub fn init(registry: *Registry) @This() {
                var mask: u64 = 0;
                inline for (Types) |T| {
                    mask |= @intFromEnum(comptime componentBit(T));
                }
                return .{ .registry = registry, .mask = mask };
            }

            pub fn next(self: *@This()) ?Entity {
                const primary = &self.registry.storage[indexOfType(Types[0])];
                while (self.current < primary.dense.items.len) {
                    const entity_id = primary.entities.items[self.current];
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
    /// Fetch a mutable pointer to the entity's component of type T, or null.
    pub fn get(self: *Registry, comptime T: type, entity: Entity) ?*T {
        return self.storage[indexOfType(T)].getByIndex(entity.index);
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

    try reg.add(entity, components.MeshComponent{ .vertices = &verts, .indices = &idx });
    try std.testing.expect(reg.get(components.MeshComponent, entity) != null);

    const mesh = reg.get(components.MeshComponent, entity).?;
    try std.testing.expectEqual(@as(usize, 3), mesh.vertices.len);
}

test "attach and destroy cleans storage" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = try reg.create();
    const verts = try std.testing.allocator.alloc(components.Vertex, 1);
    verts[0] = .{ .pos = .{ 0.0, 0.0, 0.0 }, .normal = .{ 0.0, 0.0, 1.0 }, .uv = .{ 0.0, 0.0 } };
    const idx = try std.testing.allocator.alloc(u32, 1);
    idx[0] = 0;

    try reg.add(entity, components.MeshComponent{ .vertices = verts, .indices = idx, .owns_memory = true });
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

    try reg.add(entity1, components.MeshComponent{ .vertices = &verts, .indices = &idx });
    try reg.add(entity1, components.TransformComponent{
        .position = .{ 1.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    });

    try reg.add(entity2, components.MeshComponent{ .vertices = &verts, .indices = &idx });

    var it = reg.Query(.{ components.MeshComponent, components.TransformComponent });
    var count: u32 = 0;
    while (it.next()) |entity| {
        count += 1;
        try std.testing.expectEqual(entity1.index, entity.index);
    }
    try std.testing.expectEqual(@as(u32, 1), count);
}
