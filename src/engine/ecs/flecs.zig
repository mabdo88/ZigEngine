const std = @import("std");
const flecs = @import("flecs_c");

pub const c = flecs;

pub const Entity = flecs.ecs_entity_t;
pub const Id = flecs.ecs_id_t;

pub const World = struct {
    world: *flecs.ecs_world_t,

    pub fn init() World {
        const w = flecs.ecs_init() orelse @panic("ecs_init failed");
        return .{ .world = w };
    }

    pub fn deinit(self: *World) void {
        _ = flecs.ecs_fini(self.world);
    }

    pub fn progress(self: *World, delta_time: f32) bool {
        return flecs.ecs_progress(self.world, delta_time);
    }

    pub fn quit(self: *World) void {
        flecs.ecs_quit(self.world);
    }

    pub fn shouldQuit(self: *World) bool {
        return flecs.ecs_should_quit(self.world);
    }

    pub fn newEntity(self: *World) Entity {
        return flecs.ecs_new(self.world);
    }

    pub fn deleteEntity(self: *World, entity: Entity) void {
        flecs.ecs_delete(self.world, entity);
    }

    pub fn isAlive(self: *World, entity: Entity) bool {
        return flecs.ecs_is_alive(self.world, entity);
    }

    pub fn isValid(self: *World, entity: Entity) bool {
        return flecs.ecs_is_valid(self.world, entity);
    }

    pub fn lookup(self: *World, name: [*:0]const u8) Entity {
        return flecs.ecs_lookup(self.world, name);
    }

    pub fn setName(self: *World, entity: Entity, name: [*:0]const u8) Entity {
        return flecs.ecs_set_name(self.world, entity, name);
    }

    // --- Component registration ---

    pub fn registerComponent(self: *World, comptime T: type) Entity {
        var desc = std.mem.zeroes(flecs.ecs_component_desc_t);
        var edesc = std.mem.zeroes(flecs.ecs_entity_desc_t);
        edesc.name = @typeName(T);
        edesc.use_low_id = true;
        desc.entity = flecs.ecs_entity_init(self.world, &edesc);
        desc.type.size = @intCast(@sizeOf(T));
        desc.type.alignment = @intCast(@alignOf(T));
        const id = flecs.ecs_component_init(self.world, &desc);
        return id;
    }

    pub fn registerTag(self: *World, comptime T: type) Entity {
        var edesc = std.mem.zeroes(flecs.ecs_entity_desc_t);
        edesc.name = @typeName(T);
        edesc.use_low_id = true;
        return flecs.ecs_entity_init(self.world, &edesc);
    }

    // --- Entity component operations ---

    pub fn add(self: *World, entity: Entity, component_id: Entity) void {
        flecs.ecs_add_id(self.world, entity, component_id);
    }

    pub fn remove(self: *World, entity: Entity, component_id: Entity) void {
        flecs.ecs_remove_id(self.world, entity, component_id);
    }

    pub fn has(self: *World, entity: Entity, component_id: Entity) bool {
        return flecs.ecs_has_id(self.world, entity, component_id);
    }

    pub fn set(self: *World, entity: Entity, comptime T: type, component_id: Entity, value: T) void {
        flecs.ecs_set_id(self.world, entity, component_id, @sizeOf(T), @ptrCast(&value));
    }

    pub fn get(self: *World, entity: Entity, comptime T: type, component_id: Entity) ?*T {
        const ptr = flecs.ecs_get_id(self.world, entity, component_id);
        if (ptr == null) return null;
        return @ptrCast(@alignCast(@constCast(ptr)));
    }

    pub fn getMut(self: *World, entity: Entity, comptime T: type, component_id: Entity) ?*T {
        const ptr = flecs.ecs_get_mut_id(self.world, entity, component_id);
        if (ptr == null) return null;
        return @ptrCast(@alignCast(ptr));
    }

    // --- Singleton ---

    pub fn setSingleton(self: *World, comptime T: type, component_id: Entity, value: T) void {
        flecs.ecs_set_id(self.world, component_id, component_id, @sizeOf(T), @ptrCast(&value));
    }

    // NOTE: Returns a mutable pointer via @constCast, but does not call
    // ecs_modified. on_set observers will NOT fire on mutations through this
    // pointer. If observer hooks are ever added to InputStateComponent (or any
    // singleton accessed this way), switch to getMut + ecs_modified.
    pub fn getSingleton(self: *World, comptime T: type, component_id: Entity) ?*T {
        const ptr = flecs.ecs_get_id(self.world, component_id, component_id);
        if (ptr == null) return null;
        return @ptrCast(@alignCast(@constCast(ptr)));
    }

    // --- Queries ---

    pub fn query(self: *World, component_ids: []const Entity) Query {
        var desc = std.mem.zeroes(flecs.ecs_query_desc_t);
        for (component_ids, 0..) |cid, i| {
            if (i >= 32) break;
            desc.terms[i].id = cid;
            desc.terms[i].first.id = cid;
        }
        const q = flecs.ecs_query_init(self.world, &desc) orelse @panic("ecs_query_init failed");
        return .{ .query = q, .world = self.world };
    }

    pub fn queryExpr(self: *World, expr: [*:0]const u8) Query {
        var desc = std.mem.zeroes(flecs.ecs_query_desc_t);
        desc.expr = expr;
        const q = flecs.ecs_query_init(self.world, &desc) orelse @panic("ecs_query_init failed");
        return .{ .query = q, .world = self.world };
    }

    // --- Systems ---

    pub fn system(
        self: *World,
        name: [*:0]const u8,
        phase: Entity,
        component_ids: []const Entity,
        callback: flecs.ecs_iter_action_t,
        ctx: ?*anyopaque,
    ) Entity {
        var edesc = std.mem.zeroes(flecs.ecs_entity_desc_t);
        edesc.name = name;
        const ent = flecs.ecs_entity_init(self.world, &edesc);

        var desc = std.mem.zeroes(flecs.ecs_system_desc_t);
        desc.entity = ent;
        desc.phase = phase;
        desc.callback = callback;
        if (ctx) |ctx_val| desc.ctx = ctx_val;
        for (component_ids, 0..) |cid, i| {
            if (i >= 32) break;
            desc.query.terms[i].id = cid;
            desc.query.terms[i].first.id = cid;
        }
        return flecs.ecs_system_init(self.world, &desc);
    }

    pub fn systemRun(
        self: *World,
        name: [*:0]const u8,
        phase: Entity,
        run: flecs.ecs_run_action_t,
        ctx: ?*anyopaque,
    ) Entity {
        var edesc = std.mem.zeroes(flecs.ecs_entity_desc_t);
        edesc.name = name;
        const ent = flecs.ecs_entity_init(self.world, &edesc);

        var desc = std.mem.zeroes(flecs.ecs_system_desc_t);
        desc.entity = ent;
        desc.phase = phase;
        desc.run = run;
        if (ctx) |ctx_val| desc.ctx = ctx_val;
        return flecs.ecs_system_init(self.world, &desc);
    }

    pub fn systemExpr(
        self: *World,
        name: [*:0]const u8,
        phase: Entity,
        expr: [*:0]const u8,
        callback: flecs.ecs_iter_action_t,
        ctx: ?*anyopaque,
    ) Entity {
        var edesc = std.mem.zeroes(flecs.ecs_entity_desc_t);
        edesc.name = name;
        const ent = flecs.ecs_entity_init(self.world, &edesc);

        var desc = std.mem.zeroes(flecs.ecs_system_desc_t);
        desc.entity = ent;
        desc.phase = phase;
        desc.callback = callback;
        if (ctx) |ctx_val| desc.ctx = ctx_val;
        desc.query.expr = expr;
        return flecs.ecs_system_init(self.world, &desc);
    }

    // --- Children iteration ---

    pub fn children(self: *World, parent: Entity) ChildrenIter {
        const pair_id: Id = (@as(u64, 1) << 63) | (flecs.EcsChildOf << 32) | (parent & 0xFFFFFFFF);
        return .{ .it = flecs.ecs_each_id(self.world, pair_id) };
    }

    // --- Observers ---

    pub fn observer(
        self: *World,
        component_ids: []const Entity,
        events: []const Entity,
        callback: flecs.ecs_iter_action_t,
        ctx: ?*anyopaque,
    ) Entity {
        var desc = std.mem.zeroes(flecs.ecs_observer_desc_t);
        for (component_ids, 0..) |cid, i| {
            if (i >= 32) break;
            desc.query.terms[i].id = cid;
            desc.query.terms[i].first.id = cid;
        }
        for (events, 0..) |evt, i| {
            if (i >= 8) break;
            desc.events[i] = evt;
        }
        desc.callback = callback;
        if (ctx) |ctx_val| desc.ctx = ctx_val;
        return flecs.ecs_observer_init(self.world, &desc);
    }
};

// --- Query iterator wrapper ---

pub const Query = struct {
    query: *flecs.ecs_query_t,
    world: *flecs.ecs_world_t,

    pub fn iter(self: *Query) Iter {
        return .{ .it = flecs.ecs_query_iter(self.world, self.query) };
    }

    pub fn deinit(self: *Query) void {
        flecs.ecs_query_fini(self.query);
    }
};

pub const Iter = struct {
    it: flecs.ecs_iter_t,

    pub fn next(self: *Iter) bool {
        return flecs.ecs_query_next(&self.it);
    }

    pub fn count(self: *Iter) i32 {
        return self.it.count;
    }

    pub fn entity(self: *Iter, row: i32) Entity {
        return self.it.entities[@intCast(row)];
    }

    pub fn field(self: *Iter, comptime T: type, index: i32) [*]T {
        const ptr = flecs.ecs_field_w_size(&self.it, @sizeOf(T), @intCast(index));
        return @ptrCast(@alignCast(ptr));
    }

    pub fn fieldPtr(self: *Iter, comptime T: type, index: i32) ?*T {
        const ptr = flecs.ecs_field_w_size(&self.it, @sizeOf(T), @intCast(index));
        if (ptr == null) return null;
        return @ptrCast(@alignCast(@constCast(ptr)));
    }

    pub fn fini(self: *Iter) void {
        flecs.ecs_iter_fini(&self.it);
    }
};

pub const ChildrenIter = struct {
    it: flecs.ecs_iter_t,

    pub fn next(self: *ChildrenIter) bool {
        return flecs.ecs_each_next(&self.it);
    }

    pub fn count(self: *ChildrenIter) i32 {
        return self.it.count;
    }

    pub fn entity(self: *ChildrenIter, row: i32) Entity {
        return self.it.entities[@intCast(row)];
    }

    pub fn fini(self: *ChildrenIter) void {
        flecs.ecs_iter_fini(&self.it);
    }
};

// --- Built-in event/phase constants ---

pub fn onAdd() Entity {
    return flecs.EcsOnAdd;
}

pub fn onRemove() Entity {
    return flecs.EcsOnRemove;
}

pub fn onSet() Entity {
    return flecs.EcsOnSet;
}

pub fn onLoad() Entity {
    return flecs.EcsOnLoad;
}

pub fn postLoad() Entity {
    return flecs.EcsPostLoad;
}

pub fn preUpdate() Entity {
    return flecs.EcsPreUpdate;
}

pub fn onUpdate() Entity {
    return flecs.EcsOnUpdate;
}

pub fn postUpdate() Entity {
    return flecs.EcsPostUpdate;
}

pub fn preStore() Entity {
    return flecs.EcsPreStore;
}

pub fn onStore() Entity {
    return flecs.EcsOnStore;
}

// --- Tests ---

test "flecs world init/deinit" {
    var world = World.init();
    defer world.deinit();
}

test "flecs create and delete entity" {
    var world = World.init();
    defer world.deinit();

    const e = world.newEntity();
    try std.testing.expect(world.isAlive(e));

    world.deleteEntity(e);
    try std.testing.expect(!world.isAlive(e));
}

const TestPos = struct { x: f32, y: f32 };

test "flecs component register and set/get" {
    var world = World.init();
    defer world.deinit();

    const pos_id = world.registerComponent(TestPos);
    const e = world.newEntity();
    world.add(e, pos_id);
    try std.testing.expect(world.has(e, pos_id));

    world.set(e, TestPos, pos_id, .{ .x = 1.0, .y = 2.0 });
    const pos = world.get(e, TestPos, pos_id).?;
    try std.testing.expectEqual(@as(f32, 1.0), pos.x);
    try std.testing.expectEqual(@as(f32, 2.0), pos.y);

    world.deleteEntity(e);
}

test "flecs query" {
    var world = World.init();
    defer world.deinit();

    const pos_id = world.registerComponent(TestPos);
    const e1 = world.newEntity();
    world.set(e1, TestPos, pos_id, .{ .x = 10.0, .y = 20.0 });
    const e2 = world.newEntity();
    world.set(e2, TestPos, pos_id, .{ .x = 30.0, .y = 40.0 });

    var q = world.query(&.{pos_id});
    defer q.deinit();

    var it = q.iter();
    var found: u32 = 0;
    while (it.next()) {
        const positions = it.field(TestPos, 0);
        var i: i32 = 0;
        while (i < it.count()) : (i += 1) {
            found += 1;
            _ = positions[@intCast(i)];
        }
    }
    try std.testing.expectEqual(@as(u32, 2), found);
}
