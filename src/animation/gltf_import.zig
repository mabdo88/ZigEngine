const std = @import("std");
const gltf = @import("../resources/cgltf.zig");
const math = @import("../engine/math.zig");
const log = @import("../engine/log.zig");
const skeleton = @import("skeleton.zig");
const clip = @import("clip.zig");

/// Thin wrapper over a cgltf node for traversal/local-transform decoding —
/// shared by mesh-node and skin-joint traversal, since both just walk the
/// same `cgltf_node` parent chain.
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

pub const SkinResult = struct {
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
pub fn loadSkin(allocator: std.mem.Allocator, skin: *gltf.cgltf_skin) !SkinResult {
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
pub fn loadAnimationClip(allocator: std.mem.Allocator, anim: *gltf.cgltf_animation, joint_node_to_index: *const std.AutoHashMap(usize, u32)) !?clip.AnimationClip {
    var channel_list: std.ArrayListUnmanaged(clip.Channel) = .empty;
    // Frees only whatever's actually in the list at failure time — no
    // per-iteration local errdefers below, since those would survive past a
    // successful append and double-free against this one on a later failure.
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
        const values = try allocator.alloc([4]f32, keyframe_count);
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
