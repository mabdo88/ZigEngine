const std = @import("std");
const gltf = @import("cgltf.zig");
const stbi = @import("stbimport");

const components = @import("../engine/ecs/components/components.zig");
const math = @import("../engine/math.zig");
const log = @import("../engine/log.zig");
const skeleton = @import("../animation/skeleton.zig");
const clip = @import("../animation/clip.zig");
const gltf_import = @import("../animation/gltf_import.zig");

pub const MeshData = struct {
    vertices: []components.Vertex,
    indices: []u32,
};

pub const MaterialData = struct {
    pixels: []u8,
    width: u32,
    height: u32,
    metallic: f32 = 0.0,
    roughness: f32 = 0.5,
};

pub const ScenePrimitive = struct {
    mesh_idx: u32,
    material_idx: u32,
    transform: [4][4]f32,
};

pub const GltfScene = struct {
    meshes: []MeshData,
    materials: []MaterialData,
    primitives: []ScenePrimitive,
    skeletons: []skeleton.Skeleton = &.{},
    /// Clips found while parsing `skeletons[0]`'s skin — there's no
    /// per-skeleton association yet since every asset checked so far has at
    /// most one skin; revisit if a multi-skin asset needs it.
    animation_clips: []clip.AnimationClip = &.{},
    allocator: std.mem.Allocator,

    pub fn deinit(self: *GltfScene) void {
        for (self.meshes) |m| {
            self.allocator.free(m.vertices);
            self.allocator.free(m.indices);
        }
        self.allocator.free(self.meshes);
        for (self.materials) |mat| {
            self.allocator.free(mat.pixels);
        }
        self.allocator.free(self.materials);
        self.allocator.free(self.primitives);
        for (self.skeletons) |*sk| sk.deinit();
        self.allocator.free(self.skeletons);
        for (self.animation_clips) |*c| c.deinit();
        self.allocator.free(self.animation_clips);
    }
};

pub fn loadGltf(allocator: std.mem.Allocator, path: [:0]const u8) !GltfScene {
    var options = std.mem.zeroes(gltf.cgltf_options);
    var data: [*c]gltf.cgltf_data = null;

    var result = gltf.cgltf_parse_file(&options, path, &data);
    if (result != gltf.cgltf_result_success) return error.gltfParseFailed;
    defer gltf.cgltf_free(data);
    result = gltf.cgltf_load_buffers(&options, data.?, path);
    if (result != gltf.cgltf_result_success) return error.gltfLoadBuffersFailed;
    if (data.*.meshes_count == 0) return error.gltfNoMeshes;

    const PrimMeshMap = std.AutoHashMap(usize, u32);
    var prim_to_mesh = PrimMeshMap.init(allocator);
    defer prim_to_mesh.deinit();

    var mesh_list: std.ArrayListUnmanaged(MeshData) = .empty;
    errdefer {
        for (mesh_list.items) |m| {
            allocator.free(m.vertices);
            allocator.free(m.indices);
        }
        mesh_list.deinit(allocator);
    }

    for (0..data.*.meshes_count) |mi| {
        const cgltf_mesh = data.*.meshes[mi];
        for (0..cgltf_mesh.primitives_count) |pi| {
            const prim = cgltf_mesh.primitives[pi];
            const key: usize = @intFromPtr(&cgltf_mesh.primitives[pi]);

            var pos_acc: ?*gltf.struct_cgltf_accessor = null;
            var nrm_acc: ?*gltf.struct_cgltf_accessor = null;
            var uv_acc: ?*gltf.struct_cgltf_accessor = null;
            for (0..prim.attributes_count) |ai| {
                const attr = prim.attributes[ai];
                switch (attr.type) {
                    gltf.cgltf_attribute_type_position => pos_acc = attr.data,
                    gltf.cgltf_attribute_type_normal => nrm_acc = attr.data,
                    gltf.cgltf_attribute_type_texcoord => uv_acc = attr.data,
                    else => {},
                }
            }
            if (pos_acc == null or nrm_acc == null or uv_acc == null or prim.indices == null) {
                log.warn(@src(), "loadGltf: mesh[{d}] prim[{d}] missing attributes, skipping", .{ mi, pi });
                continue;
            }

            const vertex_count = pos_acc.?.count;
            const vertices = try allocator.alloc(components.Vertex, vertex_count);
            for (0..vertex_count) |i| {
                var pos: [3]f32 = .{ 0, 0, 0 };
                var nrm: [3]f32 = .{ 0, 0, 0 };
                var uv: [2]f32 = .{ 0, 0 };
                _ = gltf.cgltf_accessor_read_float(pos_acc.?, i, &pos, 3);
                _ = gltf.cgltf_accessor_read_float(nrm_acc.?, i, &nrm, 3);
                _ = gltf.cgltf_accessor_read_float(uv_acc.?, i, &uv, 2);
                vertices[i] = .{
                    .pos = .{ pos[0], pos[1], pos[2] },
                    .normal = .{ nrm[0], nrm[1], nrm[2] },
                    .uv = .{ uv[0], uv[1] },
                };
            }

            const index_count = prim.indices.*.count;
            const indices = try allocator.alloc(u32, index_count);
            for (0..index_count) |i| {
                indices[i] = @intCast(gltf.cgltf_accessor_read_index(prim.indices, i));
            }

            const mesh_idx: u32 = @intCast(mesh_list.items.len);
            try mesh_list.append(allocator, .{ .vertices = vertices, .indices = indices });
            try prim_to_mesh.put(key, mesh_idx);
        }
    }
    if (mesh_list.items.len == 0) return error.gltfNoPrimitives;

    const MatMap = std.AutoHashMap(usize, u32);
    var mat_map = MatMap.init(allocator);
    defer mat_map.deinit();

    var mat_list: std.ArrayListUnmanaged(MaterialData) = .empty;
    errdefer {
        for (mat_list.items) |m| allocator.free(m.pixels);
        mat_list.deinit(allocator);
    }

    for (0..data.*.meshes_count) |mi| {
        const cgltf_mesh = data.*.meshes[mi];
        for (0..cgltf_mesh.primitives_count) |pi| {
            const prim = cgltf_mesh.primitives[pi];
            const mat_key: usize = if (prim.material != null) @intFromPtr(prim.material) else 0;
            if (mat_map.contains(mat_key)) continue;

            var pixels: []u8 = undefined;
            var tw: u32 = 1;
            var th: u32 = 1;
            var metallic: f32 = 0.0;
            var roughness: f32 = 0.5;
            if (prim.material != null and prim.material.*.has_pbr_metallic_roughness != 0) {
                metallic = prim.material.*.pbr_metallic_roughness.metallic_factor;
                roughness = prim.material.*.pbr_metallic_roughness.roughness_factor;
            }

            if (prim.material != null and
                prim.material.*.has_pbr_metallic_roughness != 0 and
                prim.material.*.pbr_metallic_roughness.base_color_texture.texture != null and
                prim.material.*.pbr_metallic_roughness.base_color_texture.texture.*.image != null and
                prim.material.*.pbr_metallic_roughness.base_color_texture.texture.*.image.*.uri != null)
            {
                const tex = prim.material.*.pbr_metallic_roughness.base_color_texture.texture;
                const uri = std.mem.sliceTo(tex.*.image.*.uri, 0);
                const dir = std.fs.path.dirname(path) orelse ".";
                const img_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, uri });
                defer allocator.free(img_path);
                var w: c_int = 0;
                var h: c_int = 0;
                var ch: c_int = 0;
                const decoded = stbi.stbi_load(img_path.ptr, &w, &h, &ch, 4);
                if (decoded != null) {
                    tw = @intCast(w);
                    th = @intCast(h);
                    pixels = try allocator.alloc(u8, tw * th * 4);
                    @memcpy(pixels, decoded[0 .. tw * th * 4]);
                    stbi.stbi_image_free(decoded);
                } else {
                    log.warn(@src(), "loadGltf: stbi failed to load '{s}', using white fallback", .{img_path});
                    pixels = try allocator.alloc(u8, 4);
                    pixels[0] = 255;
                    pixels[1] = 255;
                    pixels[2] = 255;
                    pixels[3] = 255;
                }
            } else {
                pixels = try allocator.alloc(u8, 4);
                pixels[0] = 255;
                pixels[1] = 255;
                pixels[2] = 255;
                pixels[3] = 255;
            }

            const mat_idx: u32 = @intCast(mat_list.items.len);
            try mat_list.append(allocator, .{ .pixels = pixels, .width = tw, .height = th, .metallic = metallic, .roughness = roughness });
            try mat_map.put(mat_key, mat_idx);
        }
    }

    var prim_list: std.ArrayListUnmanaged(ScenePrimitive) = .empty;
    errdefer prim_list.deinit(allocator);

    const identity = math.identityMatrix();
    for (0..data.*.nodes_count) |ni| {
        const node_raw = &data.*.nodes[ni];
        if (node_raw.mesh == null) continue;
        const cgltf_mesh = node_raw.mesh;
        const node_transform = nodeWorldTransform(@ptrCast(node_raw));

        for (0..cgltf_mesh.*.primitives_count) |pi| {
            const key: usize = @intFromPtr(&cgltf_mesh.*.primitives[pi]);
            const mesh_idx = prim_to_mesh.get(key) orelse continue;
            const prim = cgltf_mesh.*.primitives[pi];
            const mat_key: usize = if (prim.material != null) @intFromPtr(prim.material) else 0;
            const mat_idx = mat_map.get(mat_key) orelse 0;
            try prim_list.append(allocator, .{
                .mesh_idx = mesh_idx,
                .material_idx = mat_idx,
                .transform = node_transform,
            });
        }
    }

    if (prim_list.items.len == 0) {
        for (0..mesh_list.items.len) |mesh_idx| {
            try prim_list.append(allocator, .{
                .mesh_idx = @intCast(mesh_idx),
                .material_idx = 0,
                .transform = identity,
            });
        }
    }

    var skel_list: std.ArrayListUnmanaged(skeleton.Skeleton) = .empty;
    errdefer {
        for (skel_list.items) |*sk| sk.deinit();
        skel_list.deinit(allocator);
    }
    var clip_list: std.ArrayListUnmanaged(clip.AnimationClip) = .empty;
    errdefer {
        for (clip_list.items) |*c| c.deinit();
        clip_list.deinit(allocator);
    }
    // Note: no per-iteration errdefer on skin_result.skeleton here — once
    // appended below it's also owned by skel_list, and an errdefer
    // registered inside a loop body outlives that iteration (it's only
    // cleared on function return), so it would double-free against the
    // errdefer above if a later iteration failed. The list-iterating
    // errdefer above is sufficient on its own.
    for (0..data.*.skins_count) |si| {
        const skin_result = try gltf_import.loadSkin(allocator, @ptrCast(&data.*.skins[si]));
        defer allocator.free(skin_result.joint_nodes);
        try skel_list.append(allocator, skin_result.skeleton);

        if (si == 0) {
            var joint_node_to_index = std.AutoHashMap(usize, u32).init(allocator);
            defer joint_node_to_index.deinit();
            for (skin_result.joint_nodes, 0..) |node_ptr, idx| try joint_node_to_index.put(@intFromPtr(node_ptr), @intCast(idx));

            for (0..data.*.animations_count) |ai| {
                if (try gltf_import.loadAnimationClip(allocator, @ptrCast(&data.*.animations[ai]), &joint_node_to_index)) |c| {
                    try clip_list.append(allocator, c);
                }
            }
        }
    }

    log.info(@src(), "loadGltf: {d} mesh(es), {d} material(s), {d} primitive(s), {d} skeleton(s), {d} animation(s)", .{
        mesh_list.items.len, mat_list.items.len, prim_list.items.len, skel_list.items.len, clip_list.items.len,
    });

    return GltfScene{
        .meshes = try mesh_list.toOwnedSlice(allocator),
        .materials = try mat_list.toOwnedSlice(allocator),
        .primitives = try prim_list.toOwnedSlice(allocator),
        .skeletons = try skel_list.toOwnedSlice(allocator),
        .animation_clips = try clip_list.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

test "loadGltf: a real skinned asset (Cesium Man) parses one topologically-sorted skeleton" {
    const allocator = std.testing.allocator;
    var scene = try loadGltf(allocator, "assets/Cesium_Man.glb");
    defer scene.deinit();

    try std.testing.expectEqual(@as(usize, 1), scene.skeletons.len);
    const sk = scene.skeletons[0];
    try std.testing.expect(sk.joint_count > 1);
    try std.testing.expectEqual(@as(i32, -1), sk.parent_indices[0]);
    for (1..sk.joint_count) |i| {
        try std.testing.expect(sk.parent_indices[i] >= 0);
        try std.testing.expect(sk.parent_indices[i] < @as(i32, @intCast(i)));
    }

    try std.testing.expectEqual(@as(usize, 1), scene.animation_clips.len);
    const c = scene.animation_clips[0];
    try std.testing.expect(c.duration > 0);
    try std.testing.expect(c.channels.len > 0);

    const allocator2 = std.testing.allocator;
    const pose_start = try sk.bindPoseTRS(allocator2);
    defer allocator2.free(pose_start);
    const pose_mid = try sk.bindPoseTRS(allocator2);
    defer allocator2.free(pose_mid);
    clip.sampleClip(&c, 0.0, pose_start);
    clip.sampleClip(&c, c.duration / 2.0, pose_mid);

    var any_different = false;
    for (pose_start, pose_mid) |a, b| {
        if (!std.meta.eql(a, b)) any_different = true;
    }
    try std.testing.expect(any_different);
}

fn nodeWorldTransform(node: *gltf.cgltf_node) [4][4]f32 {
    var view = gltf_import.NodeView{ .node = node };
    var local = view.localTransform();
    var p = view.parent();
    while (p) |pv| {
        local = math.matMul(pv.localTransform(), local);
        p = pv.parent();
    }
    return local;
}
