const std = @import("std");
const gltf = @import("cgltf.zig");
const stbi = @import("stbimport");

const components = @import("../engine/ecs/components/components.zig");
const math = @import("../engine/math.zig");
const log = @import("../engine/log.zig");
const skeleton = @import("../animation/skeleton.zig");
const clip = @import("../animation/clip.zig");

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

        const x = rq[0];
        const y = rq[1];
        const z = rq[2];
        const w = rq[3];
        const rot: [4][4]f32 = .{
            .{ 1 - 2 * (y * y + z * z), 2 * (x * y + w * z), 2 * (x * z - w * y), 0 },
            .{ 2 * (x * y - w * z), 1 - 2 * (x * x + z * z), 2 * (y * z + w * x), 0 },
            .{ 2 * (x * z + w * y), 2 * (y * z - w * x), 1 - 2 * (x * x + y * y), 0 },
            .{ 0, 0, 0, 1 },
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

const SkinResult = struct {
    skeleton: skeleton.Skeleton,
    /// Joint node pointers in the same topological order as the skeleton's
    /// arrays — kept only long enough to map animation channels' target
    /// nodes onto skeleton joint indices, then freed by the caller.
    joint_nodes: [][*c]gltf.cgltf_node,
};

/// Builds a runtime `Skeleton` from a cgltf skin: remaps joints into
/// topological order (parent_indices[i] < i for every i) so
/// `computeSkinMatrices` can do a single forward sweep, since cgltf doesn't
/// guarantee the skin's joint array is already in that order.
fn loadSkin(allocator: std.mem.Allocator, skin: *gltf.cgltf_skin) !SkinResult {
    const n = skin.joints_count;
    if (n == 0) return error.gltfEmptySkin;

    var node_to_index = std.AutoHashMap(usize, u32).init(allocator);
    defer node_to_index.deinit();
    for (0..n) |i| try node_to_index.put(@intFromPtr(skin.joints[i]), @intCast(i));

    const raw_parent = try allocator.alloc(i32, n);
    defer allocator.free(raw_parent);
    for (0..n) |i| {
        const parent_node = skin.joints[i].*.parent;
        raw_parent[i] = -1;
        if (parent_node != null) {
            if (node_to_index.get(@intFromPtr(parent_node))) |pidx| raw_parent[i] = @intCast(pidx);
        }
    }

    const visited = try allocator.alloc(bool, n);
    defer allocator.free(visited);
    @memset(visited, false);
    var order: std.ArrayListUnmanaged(u32) = .empty;
    defer order.deinit(allocator);
    for (0..n) |i| try visitJointTopo(@intCast(i), raw_parent, visited, &order, allocator);

    const new_index_of_old = try allocator.alloc(u32, n);
    defer allocator.free(new_index_of_old);
    for (order.items, 0..) |old_i, new_i| new_index_of_old[old_i] = @intCast(new_i);

    const parent_indices = try allocator.alloc(i32, n);
    errdefer allocator.free(parent_indices);
    const inverse_bind = try allocator.alloc([4][4]f32, n);
    errdefer allocator.free(inverse_bind);
    const rest_local = try allocator.alloc([4][4]f32, n);
    errdefer allocator.free(rest_local);
    const rest_poses = try allocator.alloc(clip.JointPose, n);
    errdefer allocator.free(rest_poses);
    const joint_nodes = try allocator.alloc([*c]gltf.cgltf_node, n);
    errdefer allocator.free(joint_nodes);

    for (order.items, 0..) |old_i, new_i| {
        const p_old = raw_parent[old_i];
        parent_indices[new_i] = if (p_old < 0) -1 else @intCast(new_index_of_old[@intCast(p_old)]);

        var ibm: [4][4]f32 = math.identityMatrix();
        if (skin.inverse_bind_matrices != null) {
            var flat: [16]f32 = undefined;
            _ = gltf.cgltf_accessor_read_float(skin.inverse_bind_matrices, old_i, &flat, 16);
            @memcpy(@as([*]f32, @ptrCast(&ibm)), &flat);
        }
        inverse_bind[new_i] = ibm;

        const node_ptr = skin.joints[old_i];
        joint_nodes[new_i] = node_ptr;
        const joint_view = NodeView{ .node = @ptrCast(node_ptr) };
        rest_local[new_i] = joint_view.localTransform();

        // Matrix-encoded joint nodes aren't decomposed into TRS — animation
        // channels can't target them correctly, so they're left at identity.
        // Every channel we've seen in practice (and Cesium Man specifically)
        // uses separate translation/rotation/scale, not has_matrix.
        var pose: clip.JointPose = .{};
        if (node_ptr.*.has_matrix == 0) {
            if (node_ptr.*.has_translation != 0) pose.translation = node_ptr.*.translation;
            if (node_ptr.*.has_rotation != 0) pose.rotation = node_ptr.*.rotation;
            if (node_ptr.*.has_scale != 0) pose.scale = node_ptr.*.scale;
        }
        rest_poses[new_i] = pose;
    }

    return SkinResult{
        .skeleton = skeleton.Skeleton{
            .joint_count = @intCast(n),
            .parent_indices = parent_indices,
            .inverse_bind_matrices = inverse_bind,
            .rest_local_transforms = rest_local,
            .rest_local_poses = rest_poses,
            .allocator = allocator,
        },
        .joint_nodes = joint_nodes,
    };
}

/// Maps a cgltf animation's channels onto skeleton joint indices via
/// `joint_node_to_index`. Returns null if none of the animation's channels
/// target a joint in this skeleton (e.g. a morph-target or camera
/// animation) — only LINEAR/STEP interpolation is supported (sufficient for
/// every glTF sample asset checked so far; CUBICSPLINE would need tangent
/// data this doesn't read).
fn loadAnimationClip(allocator: std.mem.Allocator, anim: *gltf.cgltf_animation, joint_node_to_index: *const std.AutoHashMap(usize, u32)) !?clip.AnimationClip {
    var channel_list: std.ArrayListUnmanaged(clip.Channel) = .empty;
    errdefer {
        for (channel_list.items) |c| {
            allocator.free(c.times);
            allocator.free(c.values);
        }
        channel_list.deinit(allocator);
    }

    var duration: f32 = 0;
    for (0..anim.channels_count) |ci| {
        const ch = anim.channels[ci];
        if (ch.target_node == null) continue;
        const joint_index = joint_node_to_index.get(@intFromPtr(ch.target_node)) orelse continue;
        if (ch.sampler.*.interpolation == gltf.cgltf_interpolation_type_cubic_spline) {
            log.warn(@src(), "loadAnimationClip: skipping CUBICSPLINE channel (unsupported)", .{});
            continue;
        }
        const path: clip.ChannelPath = switch (ch.target_path) {
            gltf.cgltf_animation_path_type_translation => .translation,
            gltf.cgltf_animation_path_type_rotation => .rotation,
            gltf.cgltf_animation_path_type_scale => .scale,
            else => continue,
        };
        const element_size: usize = if (path == .rotation) 4 else 3;

        const keyframe_count = ch.sampler.*.input.*.count;
        const times = try allocator.alloc(f32, keyframe_count);
        errdefer allocator.free(times);
        const values = try allocator.alloc([4]f32, keyframe_count);
        errdefer allocator.free(values);
        for (0..keyframe_count) |ki| {
            var t: f32 = 0;
            _ = gltf.cgltf_accessor_read_float(ch.sampler.*.input, ki, &t, 1);
            times[ki] = t;
            duration = @max(duration, t);

            var v: [4]f32 = .{ 0, 0, 0, 1 };
            _ = gltf.cgltf_accessor_read_float(ch.sampler.*.output, ki, &v, element_size);
            values[ki] = v;
        }
        try channel_list.append(allocator, .{ .joint_index = joint_index, .path = path, .times = times, .values = values });
    }

    if (channel_list.items.len == 0) {
        channel_list.deinit(allocator);
        return null;
    }

    const name = if (anim.name != null) try allocator.dupe(u8, std.mem.sliceTo(anim.name, 0)) else try allocator.dupe(u8, "");
    return clip.AnimationClip{
        .name = name,
        .duration = duration,
        .channels = try channel_list.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

fn visitJointTopo(i: u32, raw_parent: []const i32, visited: []bool, order: *std.ArrayListUnmanaged(u32), allocator: std.mem.Allocator) !void {
    if (visited[i]) return;
    const p = raw_parent[i];
    if (p >= 0) try visitJointTopo(@intCast(p), raw_parent, visited, order, allocator);
    visited[i] = true;
    try order.append(allocator, i);
}

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
                log.warn(@src(), "loadgltf: mesh[{d}] prim[{d}] missing attributes, skipping", .{ mi, pi });
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
                    log.warn(@src(), "loadgltf: stbi failed to load '{s}', using white fallback", .{img_path});
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
    for (0..data.*.skins_count) |si| {
        var skin_result = try loadSkin(allocator, @ptrCast(&data.*.skins[si]));
        errdefer skin_result.skeleton.deinit();
        defer allocator.free(skin_result.joint_nodes);
        try skel_list.append(allocator, skin_result.skeleton);

        if (si == 0) {
            var joint_node_to_index = std.AutoHashMap(usize, u32).init(allocator);
            defer joint_node_to_index.deinit();
            for (skin_result.joint_nodes, 0..) |node_ptr, idx| try joint_node_to_index.put(@intFromPtr(node_ptr), @intCast(idx));

            for (0..data.*.animations_count) |ai| {
                if (try loadAnimationClip(allocator, @ptrCast(&data.*.animations[ai]), &joint_node_to_index)) |c| {
                    try clip_list.append(allocator, c);
                }
            }
        }
    }

    log.info(@src(), "loadgltf: {d} mesh(es), {d} material(s), {d} primitive(s), {d} skeleton(s), {d} animation(s)", .{
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

test "loadgltf: a real skinned asset (Cesium Man) parses one topologically-sorted skeleton" {
    const allocator = std.testing.allocator;
    var scene = try loadgltf(allocator, "assets/Cesium_Man.glb");
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
    var view = NodeView{ .node = node };
    var local = view.localTransform();
    var p = view.parent();
    while (p) |pv| {
        local = math.matMul(pv.localTransform(), local);
        p = pv.parent();
    }
    return local;
}
