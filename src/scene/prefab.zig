const std = @import("std");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const components = @import("../engine/ecs/components/components.zig");
const Uuid = @import("../engine/uuid.zig").Uuid;
const meshLoader = @import("../resources/meshLoader.zig");
const objLoader = @import("../resources/objLoader.zig");
const renderer = @import("../renderer/zvulkanSystem.zig");
const render_system = @import("../engine/ecs/systems/render_system.zig");
const fs = @import("../engine/fs.zig");
const log = @import("../engine/log.zig");

/// Cross-system access to the single PrefabRegistry instance, mirroring
/// physics_shared.zig's module-level-var pattern. Owned/created by this
/// file's own create()/destroy() system hooks (registered in all_systems.zig
/// at a priority before Scene/Spawner so it's ready before anything needs it).
pub var global: ?*PrefabRegistry = null;

/// On-disk prefab definition: `{ "name": "goblin", "mesh_path": "assets/goblin.glb" }`.
pub const PrefabDefFile = struct {
    name: []const u8,
    mesh_path: []const u8,
};

const PrefabDef = struct {
    name: [:0]const u8,
    mesh_path: [:0]const u8,
};

/// The GPU-resident result of loading a prefab's source asset — one mesh_id
/// and material_index per primitive, exactly mirroring scene_system.zig's
/// PreloadedScene. Cached by mesh_path so instantiating the same prefab many
/// times (e.g. from a SpawnPointComponent) only loads/uploads once.
const PrefabAsset = struct {
    primitives: []meshLoader.ScenePrimitive,
    mesh_ids: []u32,
    material_indices: []u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *PrefabAsset) void {
        self.allocator.free(self.primitives);
        self.allocator.free(self.mesh_ids);
        self.allocator.free(self.material_indices);
    }
};

/// Dispatches by extension, same rule scene_system.zig's loadSceneFile uses:
/// .obj goes through the OBJ parser wrapped as a one-mesh GltfScene, anything
/// else goes through cgltf.
fn loadAssetFile(allocator: std.mem.Allocator, path: [:0]const u8) !meshLoader.GltfScene {
    if (std.ascii.eqlIgnoreCase(std.fs.path.extension(path), ".obj")) {
        var threaded = std.Io.Threaded.init(allocator, .{});
        defer threaded.deinit();
        return objLoader.loadObjScene(threaded.io(), allocator, path);
    }
    return meshLoader.loadGltf(allocator, path);
}

pub const PrefabRegistry = struct {
    allocator: std.mem.Allocator,
    io_threaded: std.Io.Threaded,
    defs: std.ArrayList(PrefabDef) = .empty,
    name_to_id: std.StringHashMap(u32),
    assets: std.StringHashMap(PrefabAsset),

    pub fn init(allocator: std.mem.Allocator) PrefabRegistry {
        return .{
            .allocator = allocator,
            .io_threaded = std.Io.Threaded.init(allocator, .{}),
            .name_to_id = std.StringHashMap(u32).init(allocator),
            .assets = std.StringHashMap(PrefabAsset).init(allocator),
        };
    }

    pub fn deinit(self: *PrefabRegistry) void {
        for (self.defs.items) |d| {
            self.allocator.free(d.name);
            self.allocator.free(d.mesh_path);
        }
        self.defs.deinit(self.allocator);
        self.name_to_id.deinit();

        var it = self.assets.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.assets.deinit();

        self.io_threaded.deinit();
    }

    /// Registers a prefab definition directly (dups both strings). Returns
    /// error.DuplicatePrefab if `name` is already registered.
    pub fn register(self: *PrefabRegistry, name: []const u8, mesh_path: []const u8) !u32 {
        if (self.name_to_id.contains(name)) return error.DuplicatePrefab;

        const owned_name = try dupeZ(self.allocator, name);
        errdefer self.allocator.free(owned_name);
        const owned_path = try dupeZ(self.allocator, mesh_path);
        errdefer self.allocator.free(owned_path);

        const id: u32 = @intCast(self.defs.items.len);
        try self.defs.append(self.allocator, .{ .name = owned_name, .mesh_path = owned_path });
        try self.name_to_id.put(owned_name, id);
        return id;
    }

    /// Parses a `PrefabDefFile`-shaped JSON file and registers it.
    pub fn loadDefFile(self: *PrefabRegistry, path: []const u8) !u32 {
        const io = self.io_threaded.io();
        const text = try fs.readFileAlloc(io, self.allocator, path);
        defer self.allocator.free(text);

        const parsed = try std.json.parseFromSlice(PrefabDefFile, self.allocator, text, .{ .ignore_unknown_fields = true, .allocate = .alloc_always });
        defer parsed.deinit();

        return self.register(parsed.value.name, parsed.value.mesh_path);
    }

    pub fn idByName(self: *PrefabRegistry, name: []const u8) ?u32 {
        return self.name_to_id.get(name);
    }

    pub fn nameById(self: *PrefabRegistry, id: u32) ?[]const u8 {
        if (id >= self.defs.items.len) return null;
        return self.defs.items[id].name;
    }

    /// Loads (or returns the cached) GPU-resident asset for a prefab's
    /// mesh_path — same upload pattern as scene_system.zig's
    /// preloadSceneSync, just for one prefab's asset instead of a whole
    /// configured scene.
    fn getOrLoadAsset(self: *PrefabRegistry, registry: *Registry, prefab_id: u32) !*PrefabAsset {
        const def = self.defs.items[prefab_id];
        if (self.assets.getPtr(def.mesh_path)) |existing| return existing;

        var gltf = try loadAssetFile(self.allocator, def.mesh_path);
        defer gltf.deinit();

        const mesh_ids = try self.allocator.alloc(u32, gltf.meshes.len);
        errdefer self.allocator.free(mesh_ids);
        for (gltf.meshes, 0..) |mesh, mi| {
            mesh_ids[mi] = try registry.mesh_cache.register(mesh.vertices, mesh.indices);
        }

        const material_indices = try self.allocator.alloc(u32, gltf.materials.len);
        errdefer self.allocator.free(material_indices);

        var batch = try renderer.beginUploadBatch(self.allocator);
        errdefer batch.cancel();

        for (gltf.materials, 0..) |mat, mi| {
            const texture_index = try renderer.uploadTextureBatched(&batch, mat.pixels, mat.width, mat.height);
            material_indices[mi] = try renderer.registerMaterial(mat.metallic, mat.roughness, texture_index);
        }

        const gpu = render_system.getGpuSystem();
        for (mesh_ids) |mesh_id| {
            const mesh_data = registry.mesh_cache.get(mesh_id).?;
            try gpu.preloadMeshBatched(&batch, mesh_id, mesh_data);
        }
        try batch.submit();

        const primitives = try self.allocator.dupe(meshLoader.ScenePrimitive, gltf.primitives);
        errdefer self.allocator.free(primitives);

        try self.assets.put(def.mesh_path, .{
            .primitives = primitives,
            .mesh_ids = mesh_ids,
            .material_indices = material_indices,
            .allocator = self.allocator,
        });
        return self.assets.getPtr(def.mesh_path).?;
    }

    /// Spawns a prefab instance at `transform`. A single-primitive asset
    /// becomes one entity carrying Mesh/Material/Transform directly; a
    /// multi-primitive asset spawns a root (Uuid+PrefabInstance+Transform
    /// only) with one child per primitive parented to it via
    /// ParentComponent, so HierarchySystem positions them correctly without
    /// this code needing its own matrix math. Returns the root entity —
    /// destroyInstance() must be used to tear the whole thing back down.
    pub fn instantiate(self: *PrefabRegistry, registry: *Registry, prefab_id: u32, transform: components.TransformComponent) !Entity {
        const asset = try self.getOrLoadAsset(registry, prefab_id);
        const io = self.io_threaded.io();

        const root = try registry.create();
        try registry.add(root, components.UuidComponent{ .id = Uuid.v4(io) });
        try registry.add(root, components.PrefabInstanceComponent{ .prefab_id = prefab_id });
        try registry.add(root, components.TransformComponent{ .position = transform.position, .rotation = transform.rotation, .scale = transform.scale });

        if (asset.primitives.len == 1) {
            const prim = asset.primitives[0];
            try registry.add(root, components.MeshComponent{ .mesh_id = asset.mesh_ids[prim.mesh_idx] });
            try registry.add(root, components.MaterialComponent{ .material_index = asset.material_indices[prim.material_idx] });
            try registry.add(root, components.BakedTransformComponent{ .matrix = prim.transform });
            return root;
        }

        try registry.add(root, components.BakedTransformComponent{ .matrix = identityMatrix() });
        for (asset.primitives) |prim| {
            const child = try registry.create();
            try registry.add(child, components.MeshComponent{ .mesh_id = asset.mesh_ids[prim.mesh_idx] });
            try registry.add(child, components.MaterialComponent{ .material_index = asset.material_indices[prim.material_idx] });
            try registry.add(child, components.BakedTransformComponent{ .matrix = prim.transform });
            try registry.add(child, components.TransformComponent{ .position = .{ 0, 0, 0 }, .rotation = .{ 0, 0, 0 }, .scale = .{ 1, 1, 1 } });
            try registry.add(child, components.ParentComponent{ .parent = root });
        }
        return root;
    }

    /// Tears down a prefab instance spawned by instantiate(): the root plus
    /// every direct child parented to it (prefab assets are never nested
    /// deeper than one level, see instantiate()).
    pub fn destroyInstance(self: *PrefabRegistry, registry: *Registry, root: Entity) !void {
        _ = self;
        var to_destroy: std.ArrayList(Entity) = .empty;
        defer to_destroy.deinit(registry.registry_allocator);

        var it = registry.Query(.{components.ParentComponent});
        while (it.next()) |e| {
            const p = registry.get(components.ParentComponent, e).?;
            if (p.parent.index == root.index) try to_destroy.append(registry.registry_allocator, e);
        }
        for (to_destroy.items) |e| try registry.destroyEntity(e);
        try registry.destroyEntity(root);
    }
};

fn dupeZ(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const buf = try allocator.alloc(u8, s.len + 1);
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    return buf[0..s.len :0];
}

fn identityMatrix() [4][4]f32 {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

pub fn create(ctx: *@import("../engine/ecs/systems/system.zig").SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(PrefabRegistry);
    state.* = PrefabRegistry.init(ctx.allocator);
    global = state;

    const io = state.io_threaded.io();
    if (fs.fileExists(io, "assets/prefabs")) {
        var dir = try std.Io.Dir.cwd().openDir(io, "assets/prefabs", .{ .iterate = true });
        defer dir.close(io);
        var it = dir.iterate();
        while (try it.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".json")) continue;
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const path = std.fmt.bufPrint(&path_buf, "assets/prefabs/{s}", .{entry.name}) catch continue;
            _ = state.loadDefFile(path) catch |err| {
                log.warn(@src(), "prefab: failed to load '{s}': {s}", .{ path, @errorName(err) });
                continue;
            };
        }
    }

    return @ptrCast(state);
}

pub fn update(_: *Registry, _: *anyopaque, _: f32) anyerror!void {}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *PrefabRegistry = @ptrCast(@alignCast(ctx));
    state.deinit();
    global = null;
    allocator.destroy(state);
}

test "register assigns sequential ids and idByName/nameById round-trip" {
    var preg = PrefabRegistry.init(std.testing.allocator);
    defer preg.deinit();

    const goblin_id = try preg.register("goblin", "assets/goblin.glb");
    const barrel_id = try preg.register("barrel", "assets/barrel.glb");

    try std.testing.expectEqual(@as(u32, 0), goblin_id);
    try std.testing.expectEqual(@as(u32, 1), barrel_id);
    try std.testing.expectEqual(goblin_id, preg.idByName("goblin").?);
    try std.testing.expectEqualStrings("barrel", preg.nameById(barrel_id).?);
}

test "register rejects a duplicate name" {
    var preg = PrefabRegistry.init(std.testing.allocator);
    defer preg.deinit();

    _ = try preg.register("goblin", "assets/goblin.glb");
    try std.testing.expectError(error.DuplicatePrefab, preg.register("goblin", "assets/other.glb"));
}

test "idByName/nameById return null for unknown lookups" {
    var preg = PrefabRegistry.init(std.testing.allocator);
    defer preg.deinit();

    try std.testing.expect(preg.idByName("nope") == null);
    try std.testing.expect(preg.nameById(0) == null);
}

test "loadDefFile parses a prefab def JSON and registers it" {
    var preg = PrefabRegistry.init(std.testing.allocator);
    defer preg.deinit();

    const io = preg.io_threaded.io();
    try fs.writeFile(io, "prefab_test_tmp.json", "{\"name\": \"crate\", \"mesh_path\": \"assets/crate.glb\"}");
    defer std.Io.Dir.cwd().deleteFile(io, "prefab_test_tmp.json") catch {};

    const id = try preg.loadDefFile("prefab_test_tmp.json");
    try std.testing.expectEqualStrings("crate", preg.nameById(id).?);
    try std.testing.expectEqualStrings("assets/crate.glb", preg.defs.items[id].mesh_path);
}
