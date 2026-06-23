const std = @import("std");
const gltf = @import("cgltf.zig");
const stbi = @cImport({
    @cInclude("../../deps/stb/stb_image.h");
});

const components = @import("../engine/ecs/components/components.zig");
const math = @import("../engine/math.zig");

pub const MeshData = struct {
    vertices: []components.Vertex,
    indices: []u32,
};

pub const NodeView = struct {
    node: *gltf.cgltf_node,

    pub fn localTransform(self: NodeView) [4][4]f32 {
        const node = self.node;
        if (node.has_matrix != 0) {
            var m: [4][4]f32 = undefined;
            @memcpy(@as([*]f32, @ptrCast(&m)), node.matrix[0..16]);
            return m;
        }
        const tx = if (node.has_translation != 0) node.translation else [3]f32{ 0, 0, 0 };
        const rq = if (node.has_rotation != 0) node.rotation else [4]f32{ 0, 0, 0, 1 };
        const sc = if (node.has_scale != 0) node.scale else [3]f32{ 1, 1, 1 };

        const x = rq[0]; const y = rq[1]; const z = rq[2]; const w = rq[3];
        const rot: [4][4]f32 = .{
            .{ 1 - 2*(y*y + z*z),   2*(x*y + w*z),     2*(x*z - w*y), 0 },
            .{   2*(x*y - w*z), 1 - 2*(x*x + z*z),     2*(y*z + w*x), 0 },
            .{   2*(x*z + w*y),     2*(y*z - w*x), 1 - 2*(x*x + y*y), 0 },
            .{               0,                 0,                   0, 1 },
        };

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

    pub fn parent(self: NodeView) ?NodeView {
        if (self.node.parent == null) return null;
        return NodeView{ .node = @ptrCast(self.node.parent) };
    }
};

pub const MaterialData = struct {
    pixels: []u8,
    width: u32,
    height: u32,
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

pub fn loadgltf(allocator: std.mem.Allocator, path: [:0]const u8) !GltfScene {
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

fn nodeWorldTransform(node: *gltf.cgltf_node) [4][4]f32 {
    var view = NodeView{ .node = node };
    var local = view.localTransform();
    var p = view.parent();
    while (p) |pv| {
        local = math.matMul(pv.localTransform(), local);
        p = pv.parent();
    }
    return local;
}
