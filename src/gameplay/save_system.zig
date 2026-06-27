//! SaveData { health, pos, rot, inventory, relics, flags[] } to
//! saves/slot_N.json, per CLAUDE.md M9. F5/F9 quicksave/quickload are
//! engine-side key polls (input_system.zig) setting shared_state.save_request
//! flags — this file is what actually performs the IO, keeping engine code
//! from reaching into gameplay's file-IO concerns directly. "The player" is
//! identified the same way AI's targeting does: the one entity with both
//! PlayerMovementComponent and TransformComponent, since there's still no
//! dedicated PlayerTag.
const std = @import("std");
const Io = std.Io;
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const components = @import("../engine/ecs/components/components.zig");
const SystemCreateCtx = @import("../engine/ecs/systems/system.zig").SystemCreateCtx;
const shared_state = @import("../engine/ecs/systems/shared_state.zig");
const fs = @import("../engine/fs.zig");
const log = @import("../engine/log.zig");
const item = @import("item.zig");

pub const quicksave_slot: u32 = 0;
pub const autosave_slot: u32 = 255;
pub const autosave_interval_secs: f32 = 60.0;

pub fn slotPath(buf: []u8, slot: u32) ![]const u8 {
    return std.fmt.bufPrint(buf, "saves/slot_{d}.json", .{slot});
}

/// Persistent set of named progression/quest flags — not per-entity (no ECS
/// component makes sense for "has the player talked to this NPC ever"),
/// so it's owned by SaveSystemState the same way PrefabRegistry/ItemRegistry
/// own their own allocator-backed maps. Keys are duped on insert and freed
/// on remove/clear/deinit, same ownership rule those registries follow.
pub const FlagSet = struct {
    allocator: std.mem.Allocator,
    set: std.StringHashMapUnmanaged(void) = .{},

    pub fn init(allocator: std.mem.Allocator) FlagSet {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *FlagSet) void {
        self.clearAll();
        self.set.deinit(self.allocator);
    }

    pub fn setFlag(self: *FlagSet, name: []const u8) !void {
        if (self.set.contains(name)) return;
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);
        try self.set.put(self.allocator, owned, {});
    }

    pub fn clearFlag(self: *FlagSet, name: []const u8) void {
        if (self.set.fetchRemove(name)) |kv| self.allocator.free(kv.key);
    }

    pub fn hasFlag(self: *FlagSet, name: []const u8) bool {
        return self.set.contains(name);
    }

    pub fn clearAll(self: *FlagSet) void {
        var it = self.set.keyIterator();
        while (it.next()) |k| self.allocator.free(k.*);
        self.set.clearAndFree(self.allocator);
    }
};

/// Owned by SaveSystemState (create/destroy) — pointed to here so gameplay
/// code elsewhere (e.g. a future quest/dialogue system) can check flags
/// without threading a FlagSet pointer through every call site, same
/// module-level-global pattern prefab.global/item.global/ability.global use.
pub var global: ?*FlagSet = null;

const ItemStackSave = struct {
    item: ?[]const u8 = null,
    count: u32 = 0,
};

const SaveData = struct {
    health: f32 = 0,
    max_health: f32 = 0,
    position: [3]f32 = .{ 0, 0, 0 },
    rotation: [3]f32 = .{ 0, 0, 0 },
    inventory: []const ItemStackSave = &.{},
    relics: []const ?[]const u8 = &.{},
    flags: []const []const u8 = &.{},
};

fn findPlayer(registry: *Registry) ?@import("../engine/ecs/entity/entity.zig").Entity {
    var it = registry.Query(.{ components.PlayerMovementComponent, components.TransformComponent });
    return it.next();
}

/// Writes the player entity's health/transform/inventory/relics plus every
/// currently-set flag to `path` as JSON. Items/relics are saved by *name*,
/// not id (same reason scene_save.zig saves prefabs by name — registry ids
/// aren't guaranteed stable across a process restart if items load in a
/// different order).
pub fn saveGame(io: Io, allocator: std.mem.Allocator, registry: *Registry, flags: *FlagSet, path: []const u8) !void {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const a = arena_state.allocator();

    const pe = findPlayer(registry) orelse return error.NoPlayerEntity;
    const transform = registry.get(components.TransformComponent, pe).?;

    var health: f32 = 0;
    var max_health: f32 = 0;
    if (registry.get(components.HealthComponent, pe)) |h| {
        health = h.current;
        max_health = h.max;
    }

    var inv_save = try a.alloc(ItemStackSave, 0);
    var relics_save = try a.alloc(?[]const u8, 0);
    if (registry.get(components.InventoryComponent, pe)) |inv| {
        inv_save = try a.alloc(ItemStackSave, inv.items.len);
        for (inv.items, 0..) |stack, i| {
            inv_save[i] = .{};
            if (stack.item_id == components.invalid_item_id) continue;
            const name = if (item.global) |ir| ir.nameById(stack.item_id) else null;
            if (name) |n| inv_save[i] = .{ .item = n, .count = stack.count };
        }

        relics_save = try a.alloc(?[]const u8, inv.relics.len);
        for (inv.relics, 0..) |rid, i| {
            relics_save[i] = null;
            if (rid == components.invalid_item_id) continue;
            relics_save[i] = if (item.global) |ir| ir.nameById(rid) else null;
        }
    }

    var flags_list: std.ArrayList([]const u8) = .empty;
    var fit = flags.set.keyIterator();
    while (fit.next()) |k| try flags_list.append(a, k.*);

    const data = SaveData{
        .health = health,
        .max_health = max_health,
        .position = .{ transform.position[0], transform.position[1], transform.position[2] },
        .rotation = .{ transform.rotation[0], transform.rotation[1], transform.rotation[2] },
        .inventory = inv_save,
        .relics = relics_save,
        .flags = flags_list.items,
    };

    try fs.makeDirs(io, "saves");
    const json = try std.json.Stringify.valueAlloc(a, data, .{ .whitespace = .indent_2 });
    try fs.writeFile(io, path, json);
}

/// Restores health/transform/inventory/relics/flags from `path` onto the
/// existing player entity (the entity must already exist — same assumption
/// scene_load.zig's loadScene makes about the scene already being active).
/// An item/relic name with no matching ItemRegistry entry is logged and
/// left empty rather than erroring the whole load.
pub fn loadGame(io: Io, allocator: std.mem.Allocator, registry: *Registry, flags: *FlagSet, path: []const u8) !void {
    const text = try fs.readFileAlloc(io, allocator, path);
    defer allocator.free(text);

    const parsed = try std.json.parseFromSlice(SaveData, allocator, text, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
    defer parsed.deinit();
    const data = parsed.value;

    const pe = findPlayer(registry) orelse return error.NoPlayerEntity;
    const transform = registry.get(components.TransformComponent, pe).?;
    transform.position = .{ data.position[0], data.position[1], data.position[2] };
    transform.rotation = .{ data.rotation[0], data.rotation[1], data.rotation[2] };

    if (registry.get(components.HealthComponent, pe)) |h| {
        h.current = data.health;
        h.max = data.max_health;
    }

    if (registry.get(components.InventoryComponent, pe)) |inv| {
        for (data.inventory, 0..) |s, i| {
            if (i >= inv.items.len) break;
            inv.items[i] = .{};
            const name = s.item orelse continue;
            const id = if (item.global) |ir| ir.idByName(name) else null;
            if (id) |found| {
                inv.items[i] = .{ .item_id = found, .count = s.count };
            } else {
                log.warn(@src(), "save_system: unknown item '{s}' in slot {d}, leaving empty", .{ name, i });
            }
        }

        for (data.relics, 0..) |r, i| {
            if (i >= inv.relics.len) break;
            inv.relics[i] = components.invalid_item_id;
            const name = r orelse continue;
            const id = if (item.global) |ir| ir.idByName(name) else null;
            if (id) |found| {
                inv.relics[i] = found;
            } else {
                log.warn(@src(), "save_system: unknown relic '{s}' in slot {d}, leaving empty", .{ name, i });
            }
        }
    }

    flags.clearAll();
    for (data.flags) |f| try flags.setFlag(f);
}

pub const SaveSystemState = struct {
    allocator: std.mem.Allocator,
    io_threaded: std.Io.Threaded,
    flags: FlagSet,
    autosave_timer: f32 = 0,
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *SaveSystemState = @ptrCast(@alignCast(ctx));
    const io = state.io_threaded.io();
    var buf: [64]u8 = undefined;

    if (shared_state.save_request.quicksave) {
        shared_state.save_request.quicksave = false;
        const path = slotPath(&buf, quicksave_slot) catch unreachable;
        saveGame(io, state.allocator, registry, &state.flags, path) catch |err| {
            log.warn(@src(), "save_system: quicksave failed: {s}", .{@errorName(err)});
        };
    }

    if (shared_state.save_request.quickload) {
        shared_state.save_request.quickload = false;
        const path = slotPath(&buf, quicksave_slot) catch unreachable;
        loadGame(io, state.allocator, registry, &state.flags, path) catch |err| {
            log.warn(@src(), "save_system: quickload failed: {s}", .{@errorName(err)});
        };
    }

    state.autosave_timer += dt;
    if (state.autosave_timer >= autosave_interval_secs) {
        state.autosave_timer = 0;
        const path = slotPath(&buf, autosave_slot) catch unreachable;
        saveGame(io, state.allocator, registry, &state.flags, path) catch |err| {
            log.warn(@src(), "save_system: autosave failed: {s}", .{@errorName(err)});
        };
    }
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(SaveSystemState);
    state.* = .{
        .allocator = ctx.allocator,
        .io_threaded = std.Io.Threaded.init(ctx.allocator, .{}),
        .flags = FlagSet.init(ctx.allocator),
    };
    global = &state.flags;
    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *SaveSystemState = @ptrCast(@alignCast(ctx));
    global = null;
    state.flags.deinit();
    state.io_threaded.deinit();
    allocator.destroy(state);
}

test "FlagSet set/has/clear round-trip and dedupe" {
    var flags = FlagSet.init(std.testing.allocator);
    defer flags.deinit();

    try std.testing.expect(!flags.hasFlag("met_npc"));
    try flags.setFlag("met_npc");
    try flags.setFlag("met_npc");
    try std.testing.expect(flags.hasFlag("met_npc"));

    flags.clearFlag("met_npc");
    try std.testing.expect(!flags.hasFlag("met_npc"));
}

test "slotPath formats quicksave and autosave slots" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("saves/slot_0.json", try slotPath(&buf, quicksave_slot));
    try std.testing.expectEqualStrings("saves/slot_255.json", try slotPath(&buf, autosave_slot));
}

test "saveGame then loadGame round-trips health, transform, and flags" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var reg = Registry.init(allocator);
    defer reg.deinit();

    const player = try reg.create();
    try reg.add(player, components.PlayerMovementComponent{});
    try reg.add(player, components.TransformComponent{ .position = .{ 1, 2, 3 }, .rotation = .{ 0, 90, 0 }, .scale = .{ 1, 1, 1 } });
    try reg.add(player, components.HealthComponent{ .current = 42, .max = 100 });

    var flags = FlagSet.init(allocator);
    defer flags.deinit();
    try flags.setFlag("door_unlocked");

    const path = "save_test_tmp.json";
    try saveGame(io, allocator, &reg, &flags, path);
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    const t = reg.get(components.TransformComponent, player).?;
    t.position = .{ 0, 0, 0 };
    t.rotation = .{ 0, 0, 0 };
    reg.get(components.HealthComponent, player).?.current = 1;
    flags.clearAll();

    try loadGame(io, allocator, &reg, &flags, path);

    const loaded_t = reg.get(components.TransformComponent, player).?;
    try std.testing.expectApproxEqAbs(@as(f32, 1), loaded_t.position[0], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 2), loaded_t.position[1], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 3), loaded_t.position[2], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 90), loaded_t.rotation[1], 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 42), reg.get(components.HealthComponent, player).?.current, 1e-6);
    try std.testing.expect(flags.hasFlag("door_unlocked"));
}

test "saveGame then loadGame round-trips inventory and relics by item name" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var ireg = item.ItemRegistry.init(allocator);
    defer ireg.deinit();
    item.global = &ireg;
    defer item.global = null;
    const potion_id = try ireg.register("potion", 10, true, &.{});
    const relic_id = try ireg.register("ring_of_power", 1, false, &.{});

    var reg = Registry.init(allocator);
    defer reg.deinit();

    const player = try reg.create();
    try reg.add(player, components.PlayerMovementComponent{});
    try reg.add(player, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    var inv = components.InventoryComponent{};
    inv.items[0] = .{ .item_id = potion_id, .count = 4 };
    inv.relics[0] = relic_id;
    try reg.add(player, inv);

    var flags = FlagSet.init(allocator);
    defer flags.deinit();

    const path = "save_test_tmp2.json";
    try saveGame(io, allocator, &reg, &flags, path);
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    try reg.set(player, components.InventoryComponent{});

    try loadGame(io, allocator, &reg, &flags, path);

    const loaded_inv = reg.get(components.InventoryComponent, player).?;
    try std.testing.expectEqual(potion_id, loaded_inv.items[0].item_id);
    try std.testing.expectEqual(@as(u32, 4), loaded_inv.items[0].count);
    try std.testing.expectEqual(relic_id, loaded_inv.relics[0]);
}

test "loadGame leaves a slot empty and warns when the saved item name is unknown" {
    const allocator = std.testing.allocator;
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    item.global = null;

    var reg = Registry.init(allocator);
    defer reg.deinit();

    const player = try reg.create();
    try reg.add(player, components.PlayerMovementComponent{});
    try reg.add(player, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
    var inv = components.InventoryComponent{};
    inv.items[0] = .{ .item_id = 0, .count = 1 };
    try reg.add(player, inv);

    var flags = FlagSet.init(allocator);
    defer flags.deinit();

    try fs.writeFile(io, "save_test_tmp3.json", "{\"inventory\": [{\"item\": \"nonexistent\", \"count\": 5}]}");
    defer Io.Dir.cwd().deleteFile(io, "save_test_tmp3.json") catch {};

    try loadGame(io, allocator, &reg, &flags, "save_test_tmp3.json");

    const loaded_inv = reg.get(components.InventoryComponent, player).?;
    try std.testing.expectEqual(components.invalid_item_id, loaded_inv.items[0].item_id);
}
