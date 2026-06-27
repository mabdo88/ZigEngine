//! Ability defs loaded from JSON (assets/abilities/*.json), per CLAUDE.md M9.
//! AbilityRegistry mirrors scene/prefab.zig's PrefabRegistry shape (id-by-
//! index defs, name_to_id map, auto-load on create()) but without prefab's
//! GPU-asset half — abilities are pure data, nothing to upload. AbilitySystem
//! (registered as the same "Ability" entry — one system covers both registry
//! lifecycle and per-frame cast resolution, unlike Prefab/Spawner's split,
//! since nothing here needs a separate event-subscription lifetime) advances
//! AbilitySlotsComponent's cast state and resolves AbilityEffects.
const std = @import("std");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const components = @import("../engine/ecs/components/components.zig");
const SystemCreateCtx = @import("../engine/ecs/systems/system.zig").SystemCreateCtx;
const fs = @import("../engine/fs.zig");
const log = @import("../engine/log.zig");
const physics_shared = @import("../physics/physics_shared.zig");

pub var global: ?*AbilityRegistry = null;

pub const AbilityEffect = union(enum) {
    damage: f32,
    heal: f32,
    knockback: f32,
};

/// On-disk shape: `{ "name": "fireball", "cooldown": 5.0, "resource_cost":
/// 20.0, "cast_time": 0.5, "effects": [{"kind": "damage", "amount": 30.0}] }`.
/// `kind` is a string rather than a JSON-tagged union since std.json doesn't
/// deserialize unions directly — loadDefFile converts kind strings into real
/// AbilityEffect values after parsing, skipping (with a warning) any
/// unrecognized kind, same "skip unsupported, don't error" rule
/// animation/clip.zig's CUBICSPLINE handling already established.
const AbilityEffectFile = struct {
    kind: []const u8,
    amount: f32 = 0,
};

const AbilityDefFile = struct {
    name: []const u8,
    cooldown: f32 = 0,
    resource_cost: f32 = 0,
    cast_time: f32 = 0,
    effects: []AbilityEffectFile = &.{},
};

const AbilityDef = struct {
    name: [:0]const u8,
    cooldown: f32,
    resource_cost: f32,
    cast_time: f32,
    effects: []AbilityEffect,
};

pub const AbilityRegistry = struct {
    allocator: std.mem.Allocator,
    io_threaded: std.Io.Threaded,
    defs: std.ArrayList(AbilityDef) = .empty,
    name_to_id: std.StringHashMap(u32),

    pub fn init(allocator: std.mem.Allocator) AbilityRegistry {
        return .{
            .allocator = allocator,
            .io_threaded = std.Io.Threaded.init(allocator, .{}),
            .name_to_id = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *AbilityRegistry) void {
        for (self.defs.items) |d| {
            self.allocator.free(d.name);
            self.allocator.free(d.effects);
        }
        self.defs.deinit(self.allocator);
        self.name_to_id.deinit();
        self.io_threaded.deinit();
    }

    /// Registers an ability directly (dups name and effects). Returns
    /// error.DuplicateAbility if `name` is already registered.
    pub fn register(self: *AbilityRegistry, name: []const u8, cooldown: f32, resource_cost: f32, cast_time: f32, effects: []const AbilityEffect) !u32 {
        if (self.name_to_id.contains(name)) return error.DuplicateAbility;

        const owned_name = try dupeZ(self.allocator, name);
        errdefer self.allocator.free(owned_name);
        const owned_effects = try self.allocator.dupe(AbilityEffect, effects);
        errdefer self.allocator.free(owned_effects);

        const id: u32 = @intCast(self.defs.items.len);
        try self.defs.append(self.allocator, .{
            .name = owned_name,
            .cooldown = cooldown,
            .resource_cost = resource_cost,
            .cast_time = cast_time,
            .effects = owned_effects,
        });
        try self.name_to_id.put(owned_name, id);
        return id;
    }

    /// Parses an AbilityDefFile-shaped JSON file and registers it.
    pub fn loadDefFile(self: *AbilityRegistry, path: []const u8) !u32 {
        const io = self.io_threaded.io();
        const text = try fs.readFileAlloc(io, self.allocator, path);
        defer self.allocator.free(text);

        const parsed = try std.json.parseFromSlice(AbilityDefFile, self.allocator, text, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        defer parsed.deinit();

        var effects: std.ArrayList(AbilityEffect) = .empty;
        defer effects.deinit(self.allocator);
        for (parsed.value.effects) |ef| {
            const effect: AbilityEffect = if (std.mem.eql(u8, ef.kind, "damage"))
                .{ .damage = ef.amount }
            else if (std.mem.eql(u8, ef.kind, "heal"))
                .{ .heal = ef.amount }
            else if (std.mem.eql(u8, ef.kind, "knockback"))
                .{ .knockback = ef.amount }
            else {
                log.warn(@src(), "ability: '{s}' has unrecognized effect kind '{s}', skipping", .{ path, ef.kind });
                continue;
            };
            try effects.append(self.allocator, effect);
        }

        return self.register(parsed.value.name, parsed.value.cooldown, parsed.value.resource_cost, parsed.value.cast_time, effects.items);
    }

    pub fn idByName(self: *AbilityRegistry, name: []const u8) ?u32 {
        return self.name_to_id.get(name);
    }

    pub fn nameById(self: *AbilityRegistry, id: u32) ?[]const u8 {
        if (id >= self.defs.items.len) return null;
        return self.defs.items[id].name;
    }

    pub fn get(self: *AbilityRegistry, id: u32) ?*const AbilityDef {
        if (id >= self.defs.items.len) return null;
        return &self.defs.items[id];
    }
};

fn dupeZ(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const buf = try allocator.alloc(u8, s.len + 1);
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return buf[0..s.len :0];
}

fn resolveEffects(registry: *Registry, def: *const AbilityDef, caster: Entity, target: Entity) void {
    applyEffects(registry, def.effects, caster, target);
}

/// Applies a list of AbilityEffects against `target` (caused by `source`) —
/// exposed so gameplay/item.zig's on-use resolution can reuse this exact
/// switch instead of duplicating it; an item's "on_use" is just a flat
/// effects list too, same shape as an ability's.
pub fn applyEffects(registry: *Registry, effects: []const AbilityEffect, caster: Entity, target: Entity) void {
    for (effects) |effect| {
        switch (effect) {
            .damage => |amount| registry.events.emit(.{ .damage_event = .{ .target = target, .amount = amount, .source = caster } }),
            .heal => |amount| {
                const h = registry.get(components.HealthComponent, target) orelse continue;
                h.current = @min(h.max, h.current + amount);
            },
            .knockback => |amount| {
                const world = physics_shared.world orelse continue;
                const body = registry.get(components.PhysicsBodyComponent, target) orelse continue;
                if (body.is_static) continue;
                const caster_t = registry.get(components.TransformComponent, caster) orelse continue;
                const target_t = registry.get(components.TransformComponent, target) orelse continue;
                var dir = target_t.position - caster_t.position;
                const len_sq = @reduce(.Add, dir * dir);
                if (len_sq < 1e-10) continue;
                dir = dir / @as(@Vector(3, f32), @splat(@sqrt(len_sq)));
                world.applyImpulse(body.body_id, dir * @as(@Vector(3, f32), @splat(amount)));
            },
        }
    }
}

pub fn update(registry: *Registry, _: *anyopaque, dt: f32) anyerror!void {
    const areg = global orelse return;

    var it = registry.Query(.{components.AbilitySlotsComponent});
    while (it.next()) |caster| {
        const sc = registry.get(components.AbilitySlotsComponent, caster).?;

        for (&sc.slots) |*slot| {
            if (slot.cooldown_timer > 0) slot.cooldown_timer = @max(0, slot.cooldown_timer - dt);
        }

        if (sc.casting_slot) |idx| {
            sc.cast_timer -= dt;
            if (sc.cast_timer <= 0) {
                const slot = &sc.slots[idx];
                if (areg.get(slot.ability_id)) |def| {
                    resolveEffects(registry, def, caster, sc.casting_target orelse caster);
                    slot.cooldown_timer = def.cooldown;
                }
                sc.casting_slot = null;
                sc.casting_target = null;
            }
            continue;
        }

        const req_idx = sc.request_cast orelse continue;
        const req_target = sc.request_target;
        sc.request_cast = null;
        sc.request_target = null;
        if (req_idx >= sc.slots.len) continue;

        const slot = &sc.slots[req_idx];
        if (slot.cooldown_timer > 0) continue;
        const def = areg.get(slot.ability_id) orelse continue;
        if (sc.resource < def.resource_cost) continue;

        sc.resource -= def.resource_cost;
        if (def.cast_time <= 0) {
            resolveEffects(registry, def, caster, req_target orelse caster);
            slot.cooldown_timer = def.cooldown;
        } else {
            sc.casting_slot = req_idx;
            sc.casting_target = req_target;
            sc.cast_timer = def.cast_time;
        }
    }
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(AbilityRegistry);
    state.* = AbilityRegistry.init(ctx.allocator);
    global = state;

    const io = state.io_threaded.io();
    if (fs.fileExists(io, "assets/abilities")) {
        var dir = try std.Io.Dir.cwd().openDir(io, "assets/abilities", .{ .iterate = true });
        defer dir.close(io);
        var dir_it = dir.iterate();
        while (try dir_it.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".json")) continue;
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "assets/abilities/{s}", .{entry.name}) catch continue;
            _ = state.loadDefFile(path) catch |err| {
                log.warn(@src(), "ability: failed to load '{s}': {s}", .{ path, @errorName(err) });
                continue;
            };
        }
    }

    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *AbilityRegistry = @ptrCast(@alignCast(ctx));
    state.deinit();
    global = null;
    allocator.destroy(state);
}

test "register assigns sequential ids and idByName/nameById round-trip" {
    var areg = AbilityRegistry.init(std.testing.allocator);
    defer areg.deinit();

    const fireball_id = try areg.register("fireball", 5.0, 20.0, 0.5, &.{.{ .damage = 30.0 }});
    const heal_id = try areg.register("heal", 8.0, 15.0, 0.0, &.{.{ .heal = 25.0 }});

    try std.testing.expectEqual(@as(u32, 0), fireball_id);
    try std.testing.expectEqual(@as(u32, 1), heal_id);
    try std.testing.expectEqual(fireball_id, areg.idByName("fireball").?);
    try std.testing.expectEqualStrings("heal", areg.nameById(heal_id).?);
}

test "register rejects a duplicate name" {
    var areg = AbilityRegistry.init(std.testing.allocator);
    defer areg.deinit();

    _ = try areg.register("fireball", 5.0, 20.0, 0.5, &.{.{ .damage = 30.0 }});
    try std.testing.expectError(error.DuplicateAbility, areg.register("fireball", 1.0, 0.0, 0.0, &.{}));
}

test "loadDefFile parses effects and converts kind strings to AbilityEffect" {
    var areg = AbilityRegistry.init(std.testing.allocator);
    defer areg.deinit();

    const io = areg.io_threaded.io();
    try fs.writeFile(io,
        "ability_test_tmp.json",
        "{\"name\": \"fireball\", \"cooldown\": 5.0, \"resource_cost\": 20.0, \"cast_time\": 0.5, \"effects\": [{\"kind\": \"damage\", \"amount\": 30.0}, {\"kind\": \"knockback\", \"amount\": 8.0}]}",
    );
    defer std.Io.Dir.cwd().deleteFile(io, "ability_test_tmp.json") catch {};

    const id = try areg.loadDefFile("ability_test_tmp.json");
    const def = areg.get(id).?;
    try std.testing.expectEqualStrings("fireball", def.name);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), def.cooldown, 1e-6);
    try std.testing.expectEqual(@as(usize, 2), def.effects.len);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), def.effects[0].damage, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), def.effects[1].knockback, 1e-6);
}

test "loadDefFile skips an unrecognized effect kind instead of erroring" {
    var areg = AbilityRegistry.init(std.testing.allocator);
    defer areg.deinit();

    const io = areg.io_threaded.io();
    try fs.writeFile(io,
        "ability_test_tmp2.json",
        "{\"name\": \"mystery\", \"effects\": [{\"kind\": \"frobnicate\", \"amount\": 1.0}, {\"kind\": \"heal\", \"amount\": 10.0}]}",
    );
    defer std.Io.Dir.cwd().deleteFile(io, "ability_test_tmp2.json") catch {};

    const id = try areg.loadDefFile("ability_test_tmp2.json");
    const def = areg.get(id).?;
    try std.testing.expectEqual(@as(usize, 1), def.effects.len);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), def.effects[0].heal, 1e-6);
}

const event = @import("../engine/ecs/event.zig");

test "an instant ability (cast_time = 0) resolves immediately and deducts resource" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var areg = AbilityRegistry.init(allocator);
    defer areg.deinit();
    global = &areg;
    defer global = null;

    const ability_id = try areg.register("zap", 5.0, 10.0, 0.0, &.{.{ .damage = 15.0 }});

    const caster = try reg.create();
    var sc = components.AbilitySlotsComponent{};
    sc.slots[0] = .{ .ability_id = ability_id };
    try reg.add(caster, sc);

    const target = try reg.create();
    try reg.add(target, components.HealthComponent{ .current = 100, .max = 100 });

    var damage_amount: f32 = 0;
    try reg.events.subscribe(.damage_event, &damage_amount, struct {
        fn cb(ctx: *anyopaque, payload: event.EventPayload) void {
            const amt: *f32 = @ptrCast(@alignCast(ctx));
            amt.* = payload.damage_event.amount;
        }
    }.cb);

    reg.get(components.AbilitySlotsComponent, caster).?.request_cast = 0;
    reg.get(components.AbilitySlotsComponent, caster).?.request_target = target;
    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectApproxEqAbs(@as(f32, 15.0), damage_amount, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 90.0), reg.get(components.AbilitySlotsComponent, caster).?.resource, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), reg.get(components.AbilitySlotsComponent, caster).?.slots[0].cooldown_timer, 1e-6);
}

test "a cast_time > 0 ability does not resolve until the cast timer elapses" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var areg = AbilityRegistry.init(allocator);
    defer areg.deinit();
    global = &areg;
    defer global = null;

    const ability_id = try areg.register("fireball", 5.0, 20.0, 0.5, &.{.{ .damage = 30.0 }});

    const caster = try reg.create();
    var sc = components.AbilitySlotsComponent{};
    sc.slots[0] = .{ .ability_id = ability_id };
    try reg.add(caster, sc);

    const target = try reg.create();
    try reg.add(target, components.HealthComponent{ .current = 100, .max = 100 });

    var damage_count: u32 = 0;
    try reg.events.subscribe(.damage_event, &damage_count, struct {
        fn cb(ctx: *anyopaque, _: event.EventPayload) void {
            const c: *u32 = @ptrCast(@alignCast(ctx));
            c.* += 1;
        }
    }.cb);

    reg.get(components.AbilitySlotsComponent, caster).?.request_cast = 0;
    reg.get(components.AbilitySlotsComponent, caster).?.request_target = target;

    try update(&reg, undefined, 0.2);
    try std.testing.expectEqual(@as(u32, 0), damage_count);
    try std.testing.expect(reg.get(components.AbilitySlotsComponent, caster).?.casting_slot != null);

    try update(&reg, undefined, 0.5);
    try std.testing.expectEqual(@as(u32, 1), damage_count);
    try std.testing.expect(reg.get(components.AbilitySlotsComponent, caster).?.casting_slot == null);
}

test "casting is blocked when resource is insufficient" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var areg = AbilityRegistry.init(allocator);
    defer areg.deinit();
    global = &areg;
    defer global = null;

    const ability_id = try areg.register("fireball", 5.0, 50.0, 0.0, &.{.{ .damage = 30.0 }});

    const caster = try reg.create();
    var sc = components.AbilitySlotsComponent{ .resource = 10.0 };
    sc.slots[0] = .{ .ability_id = ability_id };
    sc.request_cast = 0;
    try reg.add(caster, sc);

    var damage_count: u32 = 0;
    try reg.events.subscribe(.damage_event, &damage_count, struct {
        fn cb(ctx: *anyopaque, _: event.EventPayload) void {
            const c: *u32 = @ptrCast(@alignCast(ctx));
            c.* += 1;
        }
    }.cb);

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectEqual(@as(u32, 0), damage_count);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), reg.get(components.AbilitySlotsComponent, caster).?.resource, 1e-6);
}

test "casting is blocked while the slot is on cooldown" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var areg = AbilityRegistry.init(allocator);
    defer areg.deinit();
    global = &areg;
    defer global = null;

    const ability_id = try areg.register("zap", 5.0, 10.0, 0.0, &.{.{ .damage = 15.0 }});

    const caster = try reg.create();
    var sc = components.AbilitySlotsComponent{};
    sc.slots[0] = .{ .ability_id = ability_id, .cooldown_timer = 2.0 };
    sc.request_cast = 0;
    try reg.add(caster, sc);

    var damage_count: u32 = 0;
    try reg.events.subscribe(.damage_event, &damage_count, struct {
        fn cb(ctx: *anyopaque, _: event.EventPayload) void {
            const c: *u32 = @ptrCast(@alignCast(ctx));
            c.* += 1;
        }
    }.cb);

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectEqual(@as(u32, 0), damage_count);
}

test "a heal effect with no explicit target heals the caster, clamped to max" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var areg = AbilityRegistry.init(allocator);
    defer areg.deinit();
    global = &areg;
    defer global = null;

    const ability_id = try areg.register("heal", 1.0, 0.0, 0.0, &.{.{ .heal = 50.0 }});

    const caster = try reg.create();
    var sc = components.AbilitySlotsComponent{};
    sc.slots[0] = .{ .ability_id = ability_id };
    sc.request_cast = 0;
    try reg.add(caster, sc);
    try reg.add(caster, components.HealthComponent{ .current = 80, .max = 100 });

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectApproxEqAbs(@as(f32, 100.0), reg.get(components.HealthComponent, caster).?.current, 1e-6);
}
