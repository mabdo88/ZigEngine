const std = @import("std");
const gltf = @import("cgltf.zig");
const stbi = @cImport({
    @cInclude("../../deps/stb/stb_image.h");
});

const components = @import("../components/components.zig");

/// Raw CPU-side mesh data. Owned by GltfScene — do not free individually.
pub const MeshData = struct {
    vertices: []components.Vertex,
    indices: []u32,
};

/// Raw CPU-side material data (base color texture). Owned by GltfScene.
/// Free pixels with the allocator passed to loadgltf after GPU upload.
pub const MaterialData = struct {
    pixels: []u8,
    width: u32,
    height: u32,
};

/// A single renderable primitive: references into GltfScene.meshes and
/// GltfScene.materials, plus the node-space transform from the scene graph.
pub const ScenePrimitive = struct {
    mesh_idx: u32,
    material_idx: u32,
    /// Column-major 4x4 transform extracted from the glTF node hierarchy.
    transform: [4][4]f32,
};

/// The result of loading a glTF file. Caller owns this and must call deinit.
/// GPU uploads should happen before deinit so pixels/vertices/indices can be freed.
pub const GltfScene = struct {
    meshes: []MeshData,
    materials: []MaterialData,
    primitives: []ScenePrimitive,
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
    }
};

/// Loads a glTF file into a GltfScene entirely on the calling thread (CPU only).
/// Caller must call scene.deinit() after GPU uploads are complete.
pub fn loadgltf(allocator: std.mem.Allocator, path: [:0]const u8) !GltfScene {
    var options = std.mem.zeroes(gltf.cgltf_options);
    var data: [*c]gltf.cgltf_data = null;

    var result = gltf.cgltf_parse_file(&options, path, &data);
    if (result != gltf.cgltf_result_success) return error.gltfParseFailed;
    defer gltf.cgltf_free(data);
    result = gltf.cgltf_load_buffers(&options, data.?, path);
    if (result != gltf.cgltf_result_success) return error.gltfLoadBuffersFailed;
    if (data.*.meshes_count == 0) return error.gltfNoMeshes;

    // --- Pass 1: load unique meshes (one per cgltf mesh primitive) ---
    // Map: cgltf_primitive pointer → mesh index in output array
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
                std.log.warn("loadgltf: mesh[{d}] prim[{d}] missing attributes, skipping", .{ mi, pi });
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

    // --- Pass 2: load unique materials (deduplicated by cgltf_material pointer) ---
    const MatMap = std.AutoHashMap(usize, u32);
    var mat_map = MatMap.init(allocator);
    defer mat_map.deinit();

    var mat_list: std.ArrayListUnmanaged(MaterialData) = .empty;
    errdefer {
        for (mat_list.items) |m| allocator.free(m.pixels);
        mat_list.deinit(allocator);
    }

    // Walk all primitives to collect materials
    for (0..data.*.meshes_count) |mi| {
        const cgltf_mesh = data.*.meshes[mi];
        for (0..cgltf_mesh.primitives_count) |pi| {
            const prim = cgltf_mesh.primitives[pi];
            const mat_key: usize = if (prim.material != null) @intFromPtr(prim.material) else 0;
            if (mat_map.contains(mat_key)) continue;

            var pixels: []u8 = undefined;
            var tw: u32 = 1;
            var th: u32 = 1;

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
                    std.log.warn("loadgltf: stbi failed to load '{s}', using white fallback", .{img_path});
                    pixels = try allocator.alloc(u8, 4);
                    pixels[0] = 255; pixels[1] = 255; pixels[2] = 255; pixels[3] = 255;
                }
            } else {
                pixels = try allocator.alloc(u8, 4);
                pixels[0] = 255; pixels[1] = 255; pixels[2] = 255; pixels[3] = 255;
            }

            const mat_idx: u32 = @intCast(mat_list.items.len);
            try mat_list.append(allocator, .{ .pixels = pixels, .width = tw, .height = th });
            try mat_map.put(mat_key, mat_idx);
        }
    }

    // --- Pass 3: build ScenePrimitive list by walking the node hierarchy ---
    var prim_list: std.ArrayListUnmanaged(ScenePrimitive) = .empty;
    errdefer prim_list.deinit(allocator);

    const identity = identityMatrix();
    for (0..data.*.nodes_count) |ni| {
        const node_raw = &data.*.nodes[ni];
        if (node_raw.mesh == null) continue;
        const cgltf_mesh = node_raw.mesh;
        const node_transform = nodeWorldTransform(node_raw);

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

    // Fallback: if no nodes reference meshes, emit one primitive per mesh at identity
    if (prim_list.items.len == 0) {
        for (0..mesh_list.items.len) |mesh_idx| {
            try prim_list.append(allocator, .{
                .mesh_idx = @intCast(mesh_idx),
                .material_idx = 0,
                .transform = identity,
            });
        }
    }

    std.log.info("loadgltf: {d} mesh(es), {d} material(s), {d} primitive(s)", .{
        mesh_list.items.len, mat_list.items.len, prim_list.items.len,
    });

    return GltfScene{
        .meshes = try mesh_list.toOwnedSlice(allocator),
        .materials = try mat_list.toOwnedSlice(allocator),
        .primitives = try prim_list.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

fn identityMatrix() [4][4]f32 {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

/// Multiplies two column-major 4x4 matrices: result = a * b
fn matMul(a: [4][4]f32, b: [4][4]f32) [4][4]f32 {
    var r: [4][4]f32 = std.mem.zeroes([4][4]f32);
    for (0..4) |row| {
        for (0..4) |col| {
            for (0..4) |k| {
                r[col][row] += a[k][row] * b[col][k];
            }
        }
    }
    return r;
}

/// Extracts the local transform of a node as a 4x4 column-major matrix.
fn nodeLocalTransform(node: anytype) [4][4]f32 {
    if (node.has_matrix != 0) {
        var m: [4][4]f32 = undefined;
        @memcpy(@as([*]f32, @ptrCast(&m)), node.matrix[0..16]);
        return m;
    }
    const tx = if (node.has_translation != 0) node.translation else [3]f32{ 0, 0, 0 };
    const rq = if (node.has_rotation != 0) node.rotation else [4]f32{ 0, 0, 0, 1 };
    const sc = if (node.has_scale != 0) node.scale else [3]f32{ 1, 1, 1 };

    // Quaternion to rotation matrix
    const x = rq[0]; const y = rq[1]; const z = rq[2]; const w = rq[3];
    const rot: [4][4]f32 = .{
        .{ 1 - 2*(y*y + z*z),   2*(x*y + w*z),     2*(x*z - w*y), 0 },
        .{   2*(x*y - w*z), 1 - 2*(x*x + z*z),     2*(y*z + w*x), 0 },
        .{   2*(x*z + w*y),     2*(y*z - w*x), 1 - 2*(x*x + y*y), 0 },
        .{               0,                 0,                   0, 1 },
    };

    // Scale then rotate then translate (TRS)
    var m = rot;
    for (0..3) |c| {
        m[c][0] *= sc[0];
        m[c][1] *= sc[1];
        m[c][2] *= sc[2];
    }
    m[3][0] = tx[0];
    m[3][1] = tx[1];
    m[3][2] = tx[2];
    return m;
}

/// Walks the parent chain to compute the world-space transform for a node.
/// Accepts an allowzero pointer from cgltf's C arrays.
fn nodeWorldTransform(node: anytype) [4][4]f32 {
    var local = nodeLocalTransform(node);
    var parent: ?*gltf.cgltf_node = if (node.parent != null) @ptrCast(node.parent) else null;
    while (parent) |p| {
        local = matMul(nodeLocalTransform(p), local);
        parent = if (p.parent != null) @ptrCast(p.parent) else null;
    }
    return local;
}
