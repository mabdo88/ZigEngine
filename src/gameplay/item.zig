//! Item defs loaded from JSON (assets/items/*.json), per CLAUDE.md M9.
//! ItemRegistry mirrors gameplay/ability.zig's AbilityRegistry shape exactly
//! (id-by-index defs, name_to_id map, auto-load on create()) — an item's
//! "on_use" behavior is the same flat AbilityEffect list an ability's is,
//! reusing ability.applyEffects rather than a real function pointer (`on_use
//! fn` in the roadmap's literal wording), since data-driven effects already
//! cover heal/damage/knockback without needing actual native callbacks.
//! ItemSystem covers both on-use resolution and PickupComponent pickup —
//! one system, like Ability's registry+resolution merge, since neither
//! needs its own event-subscription lifetime.
const std = @import("std");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const components = @import("../engine/ecs/components/components.zig");
const event = @import("../engine/ecs/event.zig");
const SystemCreateCtx = @import("../engine/ecs/systems/system.zig").SystemCreateCtx;
const fs = @import("../engine/fs.zig");
const log = @import("../engine/log.zig");
const ability = @import("ability.zig");
const physics_world = @import("../physics/physics_world.zig");
const physics_shared = @import("../physics/physics_shared.zig");

pub var global: ?*ItemRegistry = null;

const ItemEffectFile = struct {
    kind: []const u8,
    amount: f32 = 0,
};

const ItemDefFile = struct {
    name: []const u8,
    max_stack: u32 = 1,
    consumable: bool = true,
    effects: []ItemEffectFile = &.{},
};

const ItemDef = struct {
    name: [:0]const u8,
    max_stack: u32,
    consumable: bool,
    effects: []ability.AbilityEffect,
};

pub const ItemRegistry = struct {
    allocator: std.mem.Allocator,
    io_threaded: std.Io.Threaded,
    defs: std.ArrayList(ItemDef) = .empty,
    name_to_id: std.StringHashMap(u32),

    pub fn init(allocator: std.mem.Allocator) ItemRegistry {
        return .{
            .allocator = allocator,
            .io_threaded = std.Io.Threaded.init(allocator, .{}),
            .name_to_id = std.StringHashMap(u32).init(allocator),
        };
    }

    pub fn deinit(self: *ItemRegistry) void {
        for (self.defs.items) |d| {
            self.allocator.free(d.name);
            self.allocator.free(d.effects);
        }
        self.defs.deinit(self.allocator);
        self.name_to_id.deinit();
        self.io_threaded.deinit();
    }

    /// Registers an item directly (dups name and effects). Returns
    /// error.DuplicateItem if `name` is already registered.
    pub fn register(self: *ItemRegistry, name: []const u8, max_stack: u32, consumable: bool, effects: []const ability.AbilityEffect) !u32 {
        if (self.name_to_id.contains(name)) return error.DuplicateItem;

        const owned_name = try dupeZ(self.allocator, name);
        errdefer self.allocator.free(owned_name);
        const owned_effects = try self.allocator.dupe(ability.AbilityEffect, effects);
        errdefer self.allocator.free(owned_effects);

        const id: u32 = @intCast(self.defs.items.len);
        try self.defs.append(self.allocator, .{
            .name = owned_name,
            .max_stack = max_stack,
            .consumable = consumable,
            .effects = owned_effects,
        });
        try self.name_to_id.put(owned_name, id);
        return id;
    }

    /// Parses an ItemDefFile-shaped JSON file and registers it.
    pub fn loadDefFile(self: *ItemRegistry, path: []const u8) !u32 {
        const io = self.io_threaded.io();
        const text = try fs.readFileAlloc(io, self.allocator, path);
        defer self.allocator.free(text);

        const parsed = try std.json.parseFromSlice(ItemDefFile, self.allocator, text, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        defer parsed.deinit();

        var effects: std.ArrayList(ability.AbilityEffect) = .empty;
        defer effects.deinit(self.allocator);
        for (parsed.value.effects) |ef| {
            const effect: ability.AbilityEffect = if (std.mem.eql(u8, ef.kind, "damage"))
                .{ .damage = ef.amount }
            else if (std.mem.eql(u8, ef.kind, "heal"))
                .{ .heal = ef.amount }
            else if (std.mem.eql(u8, ef.kind, "knockback"))
                .{ .knockback = ef.amount }
            else {
                log.warn(@src(), "item: '{s}' has unrecognized effect kind '{s}', skipping", .{ path, ef.kind });
                continue;
            };
            try effects.append(self.allocator, effect);
        }

        return self.register(parsed.value.name, parsed.value.max_stack, parsed.value.consumable, effects.items);
    }

    pub fn idByName(self: *ItemRegistry, name: []const u8) ?u32 {
        return self.name_to_id.get(name);
    }

    pub fn nameById(self: *ItemRegistry, id: u32) ?[]const u8 {
        if (id >= self.defs.items.len) return null;
        return self.defs.items[id].name;
    }

    pub fn get(self: *ItemRegistry, id: u32) ?*const ItemDef {
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

/// Fills existing same-item stacks with room first, then empty slots.
/// Returns true if every unit of `count` found a home; on a full inventory
/// it stops partway and returns false, leaving whatever did fit in place
/// (a partial pickup, not an all-or-nothing one).
pub fn addItem(ireg: *ItemRegistry, inv: *components.InventoryComponent, item_id: u32, count: u32) bool {
    const def = ireg.get(item_id) orelse return false;
    var remaining = count;

    for (&inv.items) |*stack| {
        if (remaining == 0) break;
        if (stack.item_id != item_id or stack.count >= def.max_stack) continue;
        const room = def.max_stack - stack.count;
        const add = @min(room, remaining);
        stack.count += add;
        remaining -= add;
    }

    for (&inv.items) |*stack| {
        if (remaining == 0) break;
        if (stack.item_id != components.invalid_item_id) continue;
        const add = @min(def.max_stack, remaining);
        stack.item_id = item_id;
        stack.count = add;
        remaining -= add;
    }

    return remaining == 0;
}

fn onTriggerEvent(ctx: *anyopaque, payload: event.EventPayload) void {
    const registry: *Registry = @ptrCast(@alignCast(ctx));
    const te = payload.trigger_event;
    if (!te.is_enter) return;

    const ireg = global orelse return;
    const pickup = registry.get(components.PickupComponent, te.trigger_ent) orelse return;
    const inv = registry.get(components.InventoryComponent, te.other_ent) orelse return;

    if (!addItem(ireg, inv, pickup.item_id, pickup.count)) return;

    if (physics_shared.world) |world| {
        if (registry.get(components.PhysicsBodyComponent, te.trigger_ent) != null) {
            physics_world.despawnBody(registry, world, te.trigger_ent);
        }
    }
    registry.destroyEntity(te.trigger_ent) catch {};
}

pub fn update(registry: *Registry, _: *anyopaque, _: f32) anyerror!void {
    const ireg = global orelse return;

    var it = registry.Query(.{components.InventoryComponent});
    while (it.next()) |user| {
        const inv = registry.get(components.InventoryComponent, user).?;
        const slot_idx = inv.request_use_slot orelse continue;
        inv.request_use_slot = null;
        if (slot_idx >= inv.items.len) continue;

        const stack = &inv.items[slot_idx];
        if (stack.item_id == components.invalid_item_id or stack.count == 0) continue;
        const def = ireg.get(stack.item_id) orelse continue;

        ability.applyEffects(registry, def.effects, user, user);

        if (def.consumable) {
            stack.count -= 1;
            if (stack.count == 0) stack.item_id = components.invalid_item_id;
        }
    }
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(ItemRegistry);
    state.* = ItemRegistry.init(ctx.allocator);
    global = state;

    try ctx.registry.events.subscribe(.trigger_event, ctx.registry, onTriggerEvent);

    const io = state.io_threaded.io();
    if (fs.fileExists(io, "assets/items")) {
        var dir = try std.Io.Dir.cwd().openDir(io, "assets/items", .{ .iterate = true });
        defer dir.close(io);
        var dir_it = dir.iterate();
        while (try dir_it.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".json")) continue;
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "assets/items/{s}", .{entry.name}) catch continue;
            _ = state.loadDefFile(path) catch |err| {
                log.warn(@src(), "item: failed to load '{s}': {s}", .{ path, @errorName(err) });
                continue;
            };
        }
    }

    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *ItemRegistry = @ptrCast(@alignCast(ctx));
    state.deinit();
    global = null;
    allocator.destroy(state);
}

test "register assigns sequential ids and idByName/nameById round-trip" {
    var ireg = ItemRegistry.init(std.testing.allocator);
    defer ireg.deinit();

    const potion_id = try ireg.register("potion", 10, true, &.{.{ .heal = 25.0 }});
    const sword_id = try ireg.register("sword", 1, false, &.{});

    try std.testing.expectEqual(@as(u32, 0), potion_id);
    try std.testing.expectEqual(@as(u32, 1), sword_id);
    try std.testing.expectEqual(potion_id, ireg.idByName("potion").?);
    try std.testing.expectEqualStrings("sword", ireg.nameById(sword_id).?);
}

test "register rejects a duplicate name" {
    var ireg = ItemRegistry.init(std.testing.allocator);
    defer ireg.deinit();

    _ = try ireg.register("potion", 10, true, &.{});
    try std.testing.expectError(error.DuplicateItem, ireg.register("potion", 1, false, &.{}));
}

test "loadDefFile parses effects and converts kind strings" {
    var ireg = ItemRegistry.init(std.testing.allocator);
    defer ireg.deinit();

    const io = ireg.io_threaded.io();
    try fs.writeFile(io,
        "item_test_tmp.json",
        "{\"name\": \"potion\", \"max_stack\": 10, \"consumable\": true, \"effects\": [{\"kind\": \"heal\", \"amount\": 25.0}]}",
    );
    defer std.Io.Dir.cwd().deleteFile(io, "item_test_tmp.json") catch {};

    const id = try ireg.loadDefFile("item_test_tmp.json");
    const def = ireg.get(id).?;
    try std.testing.expectEqualStrings("potion", def.name);
    try std.testing.expectEqual(@as(u32, 10), def.max_stack);
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), def.effects[0].heal, 1e-6);
}

test "addItem fills an existing stack before using a new slot" {
    var ireg = ItemRegistry.init(std.testing.allocator);
    defer ireg.deinit();
    const potion_id = try ireg.register("potion", 10, true, &.{});

    var inv = components.InventoryComponent{};
    inv.items[0] = .{ .item_id = potion_id, .count = 8 };

    try std.testing.expect(addItem(&ireg, &inv, potion_id, 5));
    try std.testing.expectEqual(@as(u32, 10), inv.items[0].count);
    try std.testing.expectEqual(potion_id, inv.items[1].item_id);
    try std.testing.expectEqual(@as(u32, 3), inv.items[1].count);
}

test "addItem returns false and stops partway when the inventory is full" {
    var ireg = ItemRegistry.init(std.testing.allocator);
    defer ireg.deinit();
    const rock_id = try ireg.register("rock", 1, true, &.{});

    var inv = components.InventoryComponent{};
    for (&inv.items) |*s| s.* = .{ .item_id = rock_id, .count = 1 };

    try std.testing.expect(!addItem(&ireg, &inv, rock_id, 5));
}

test "trigger enter grants the pickup's item and destroys the pickup entity" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var ireg = ItemRegistry.init(allocator);
    defer ireg.deinit();
    global = &ireg;
    defer global = null;

    const potion_id = try ireg.register("potion", 10, true, &.{});

    try reg.events.subscribe(.trigger_event, &reg, onTriggerEvent);

    const pickup_ent = try reg.create();
    try reg.add(pickup_ent, components.PickupComponent{ .item_id = potion_id, .count = 3 });

    const player = try reg.create();
    try reg.add(player, components.InventoryComponent{});

    reg.events.emit(.{ .trigger_event = .{ .trigger_ent = pickup_ent, .other_ent = player, .is_enter = true } });

    try std.testing.expectEqual(potion_id, reg.get(components.InventoryComponent, player).?.items[0].item_id);
    try std.testing.expectEqual(@as(u32, 3), reg.get(components.InventoryComponent, player).?.items[0].count);
    try std.testing.expect(!reg.isAlive(pickup_ent));
}

test "using a consumable item applies its effects and decrements the stack" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var ireg = ItemRegistry.init(allocator);
    defer ireg.deinit();
    global = &ireg;
    defer global = null;

    const potion_id = try ireg.register("potion", 10, true, &.{.{ .heal = 25.0 }});

    const user = try reg.create();
    try reg.add(user, components.HealthComponent{ .current = 50, .max = 100 });
    var inv = components.InventoryComponent{};
    inv.items[0] = .{ .item_id = potion_id, .count = 3 };
    inv.request_use_slot = 0;
    try reg.add(user, inv);

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectApproxEqAbs(@as(f32, 75.0), reg.get(components.HealthComponent, user).?.current, 1e-6);
    try std.testing.expectEqual(@as(u32, 2), reg.get(components.InventoryComponent, user).?.items[0].count);
}

test "using the last unit of a consumable clears the slot back to empty" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var ireg = ItemRegistry.init(allocator);
    defer ireg.deinit();
    global = &ireg;
    defer global = null;

    const potion_id = try ireg.register("potion", 10, true, &.{.{ .heal = 25.0 }});

    const user = try reg.create();
    try reg.add(user, components.HealthComponent{ .current = 50, .max = 100 });
    var inv = components.InventoryComponent{};
    inv.items[0] = .{ .item_id = potion_id, .count = 1 };
    inv.request_use_slot = 0;
    try reg.add(user, inv);

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectEqual(components.invalid_item_id, reg.get(components.InventoryComponent, user).?.items[0].item_id);
    try std.testing.expectEqual(@as(u32, 0), reg.get(components.InventoryComponent, user).?.items[0].count);
}

test "using a non-consumable item applies effects but does not decrement the stack" {
    const allocator = std.testing.allocator;
    var reg = Registry.init(allocator);
    defer reg.deinit();

    var ireg = ItemRegistry.init(allocator);
    defer ireg.deinit();
    global = &ireg;
    defer global = null;

    const charm_id = try ireg.register("charm", 1, false, &.{.{ .heal = 10.0 }});

    const user = try reg.create();
    try reg.add(user, components.HealthComponent{ .current = 50, .max = 100 });
    var inv = components.InventoryComponent{};
    inv.items[0] = .{ .item_id = charm_id, .count = 1 };
    inv.request_use_slot = 0;
    try reg.add(user, inv);

    try update(&reg, undefined, 1.0 / 60.0);

    try std.testing.expectApproxEqAbs(@as(f32, 60.0), reg.get(components.HealthComponent, user).?.current, 1e-6);
    try std.testing.expectEqual(@as(u32, 1), reg.get(components.InventoryComponent, user).?.items[0].count);
}
