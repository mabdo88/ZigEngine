const std = @import("std");
const Io = std.Io;
const components = @import("../engine/ecs/components/components.zig");
const fs = @import("../engine/fs.zig");
const log = @import("../engine/log.zig");
const math = @import("../engine/math.zig");
const meshLoader = @import("meshLoader.zig");
const materialLoader = @import("materialLoader.zig");
const stbi = @import("stbimport");

/// Minimal Wavefront OBJ parser: v/vn/vt/f only (no materials, no groups,
/// no smoothing groups). Faces with >3 vertices are fan-triangulated, which
/// is only correct for convex polygons — fine for the simple/primitive OBJ
/// files this engine actually needs to import.
pub const ObjMesh = struct {
    vertices: []components.Vertex,
    indices: []u32,

    pub fn deinit(self: *ObjMesh, allocator: std.mem.Allocator) void {
        allocator.free(self.vertices);
        allocator.free(self.indices);
    }
};

const FaceVertexKey = struct {
    pos: i32,
    uv: i32,
    normal: i32,
};

fn resolveIndex(raw: i32, count: usize) !usize {
    if (raw > 0) {
        const idx: usize = @intCast(raw - 1);
        if (idx >= count) return error.ObjIndexOutOfRange;
        return idx;
    }
    if (raw < 0) {
        const back: usize = @intCast(-raw);
        if (back > count) return error.ObjIndexOutOfRange;
        return count - back;
    }
    return error.ObjIndexOutOfRange;
}

fn parseFaceVertex(token: []const u8) !FaceVertexKey {
    var parts = std.mem.splitScalar(u8, token, '/');
    const pos_str = parts.next() orelse return error.ObjMalformedFace;
    const pos = try std.fmt.parseInt(i32, pos_str, 10);

    var uv: i32 = 0;
    var normal: i32 = 0;
    if (parts.next()) |uv_str| {
        if (uv_str.len > 0) uv = try std.fmt.parseInt(i32, uv_str, 10);
    }
    if (parts.next()) |n_str| {
        if (n_str.len > 0) normal = try std.fmt.parseInt(i32, n_str, 10);
    }
    return .{ .pos = pos, .uv = uv, .normal = normal };
}

pub fn loadObj(io: Io, allocator: std.mem.Allocator, path: []const u8) !ObjMesh {
    const text = try fs.readFileAlloc(io, allocator, path);
    defer allocator.free(text);

    var positions: std.ArrayListUnmanaged(@Vector(3, f32)) = .empty;
    defer positions.deinit(allocator);
    var normals: std.ArrayListUnmanaged(@Vector(3, f32)) = .empty;
    defer normals.deinit(allocator);
    var uvs: std.ArrayListUnmanaged(@Vector(2, f32)) = .empty;
    defer uvs.deinit(allocator);

    var vertices: std.ArrayListUnmanaged(components.Vertex) = .empty;
    errdefer vertices.deinit(allocator);
    var indices: std.ArrayListUnmanaged(u32) = .empty;
    errdefer indices.deinit(allocator);

    var dedup: std.AutoHashMapUnmanaged(FaceVertexKey, u32) = .empty;
    defer dedup.deinit(allocator);

    var lines = std.mem.splitScalar(u8, text, '\n');
    var line_no: usize = 0;
    while (lines.next()) |raw_line| {
        line_no += 1;
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        const tag = tokens.next() orelse continue;

        if (std.mem.eql(u8, tag, "v")) {
            const x = try std.fmt.parseFloat(f32, tokens.next() orelse return error.ObjMalformedVertex);
            const y = try std.fmt.parseFloat(f32, tokens.next() orelse return error.ObjMalformedVertex);
            const z = try std.fmt.parseFloat(f32, tokens.next() orelse return error.ObjMalformedVertex);
            try positions.append(allocator, .{ x, y, z });
        } else if (std.mem.eql(u8, tag, "vn")) {
            const x = try std.fmt.parseFloat(f32, tokens.next() orelse return error.ObjMalformedNormal);
            const y = try std.fmt.parseFloat(f32, tokens.next() orelse return error.ObjMalformedNormal);
            const z = try std.fmt.parseFloat(f32, tokens.next() orelse return error.ObjMalformedNormal);
            try normals.append(allocator, .{ x, y, z });
        } else if (std.mem.eql(u8, tag, "vt")) {
            const u = try std.fmt.parseFloat(f32, tokens.next() orelse return error.ObjMalformedUv);
            const v = try std.fmt.parseFloat(f32, tokens.next() orelse return error.ObjMalformedUv);
            try uvs.append(allocator, .{ u, v });
        } else if (std.mem.eql(u8, tag, "f")) {
            var face_keys: [32]FaceVertexKey = undefined;
            var face_count: usize = 0;
            while (tokens.next()) |tok| {
                if (face_count >= face_keys.len) return error.ObjFaceTooLarge;
                face_keys[face_count] = try parseFaceVertex(tok);
                face_count += 1;
            }
            if (face_count < 3) return error.ObjMalformedFace;

            var resolved: [32]u32 = undefined;
            for (face_keys[0..face_count], 0..) |key, i| {
                if (dedup.get(key)) |existing| {
                    resolved[i] = existing;
                    continue;
                }
                const pos_idx = try resolveIndex(key.pos, positions.items.len);
                const normal: @Vector(3, f32) = if (key.normal != 0)
                    normals.items[try resolveIndex(key.normal, normals.items.len)]
                else
                    .{ 0.0, 0.0, 1.0 };
                const uv: @Vector(2, f32) = if (key.uv != 0)
                    uvs.items[try resolveIndex(key.uv, uvs.items.len)]
                else
                    .{ 0.0, 0.0 };

                const out_idx: u32 = @intCast(vertices.items.len);
                try vertices.append(allocator, .{ .pos = positions.items[pos_idx], .normal = normal, .uv = uv });
                try dedup.put(allocator, key, out_idx);
                resolved[i] = out_idx;
            }

            // Fan-triangulate: (0, i, i+1) for i in [1, face_count-2].
            for (1..face_count - 1) |i| {
                try indices.append(allocator, resolved[0]);
                try indices.append(allocator, resolved[i]);
                try indices.append(allocator, resolved[i + 1]);
            }
        }
        // Anything else (o, g, s, mtllib, usemtl, vp, ...) is intentionally ignored.
    }

    if (vertices.items.len == 0) return error.ObjNoVertices;

    log.info(@src(), "loadObj: '{s}' -> {d} vertices, {d} indices", .{ path, vertices.items.len, indices.items.len });

    return .{
        .vertices = try vertices.toOwnedSlice(allocator),
        .indices = try indices.toOwnedSlice(allocator),
    };
}

/// Wraps a single OBJ mesh as a one-mesh/one-material/one-primitive
/// GltfScene, so scene_system.zig's existing glTF-shaped pipeline (mesh
/// upload, material/texture slot, node transform) can spawn it unchanged.
/// OBJ has no material/texture info, so the primitive gets a 1x1 white
/// fallback texture and an identity transform.
pub fn loadObjScene(io: Io, allocator: std.mem.Allocator, path: []const u8) !meshLoader.GltfScene {
    const mesh = try loadObj(io, allocator, path);

    const meshes = try allocator.alloc(meshLoader.MeshData, 1);
    meshes[0] = .{ .vertices = mesh.vertices, .indices = mesh.indices };

    const materials = try allocator.alloc(meshLoader.MaterialData, 1);
    materials[0] = try loadSiblingMaterial(io, allocator, path);

    const primitives = try allocator.alloc(meshLoader.ScenePrimitive, 1);
    primitives[0] = .{ .mesh_idx = 0, .material_idx = 0, .transform = math.identityMatrix() };

    return .{ .meshes = meshes, .materials = materials, .primitives = primitives, .allocator = allocator };
}

fn whiteFallback(allocator: std.mem.Allocator, metallic: f32, roughness: f32) !meshLoader.MaterialData {
    const white = try allocator.alloc(u8, 4);
    @memset(white, 255);
    return .{ .pixels = white, .width = 1, .height = 1, .metallic = metallic, .roughness = roughness };
}

/// OBJ has no material info of its own, so this looks for a sibling
/// `<name>.json` material definition next to the OBJ file (e.g.
/// cube.obj -> cube.json, see materialLoader.zig for the format). Falls
/// back to a 1x1 white default (metallic 0, roughness 0.5) if none exists,
/// fails to parse, or doesn't name an albedo texture.
fn loadSiblingMaterial(io: Io, allocator: std.mem.Allocator, obj_path: []const u8) !meshLoader.MaterialData {
    const stem_len = obj_path.len - std.fs.path.extension(obj_path).len;
    const json_path = try std.fmt.allocPrint(allocator, "{s}.json", .{obj_path[0..stem_len]});
    defer allocator.free(json_path);

    const parsed = materialLoader.loadMaterialJson(io, allocator, json_path) catch {
        return whiteFallback(allocator, 0.0, 0.5);
    };
    defer parsed.deinit();

    if (parsed.value.albedo.len == 0) {
        return whiteFallback(allocator, parsed.value.metallic, parsed.value.roughness);
    }

    const dir = std.fs.path.dirname(obj_path) orelse ".";
    const img_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, parsed.value.albedo });
    defer allocator.free(img_path);

    var w: c_int = 0;
    var h: c_int = 0;
    var ch: c_int = 0;
    const decoded = stbi.stbi_load(img_path.ptr, &w, &h, &ch, 4);
    if (decoded == null) {
        log.warn(@src(), "loadObjScene: stbi failed to load '{s}', using white fallback", .{img_path});
        return whiteFallback(allocator, parsed.value.metallic, parsed.value.roughness);
    }
    const tw: u32 = @intCast(w);
    const th: u32 = @intCast(h);
    const pixels = try allocator.alloc(u8, tw * th * 4);
    @memcpy(pixels, decoded[0 .. tw * th * 4]);
    stbi.stbi_image_free(decoded);

    return .{ .pixels = pixels, .width = tw, .height = th, .metallic = parsed.value.metallic, .roughness = parsed.value.roughness };
}

fn uniqueTestPath(io: Io, buf: []u8) []const u8 {
    var rand_bytes: [8]u8 = undefined;
    Io.random(io, &rand_bytes);
    const n = std.mem.readInt(u64, &rand_bytes, .little);
    return std.fmt.bufPrint(buf, "obj_test_{x}.obj", .{n}) catch unreachable;
}

fn withTempObj(io: Io, content: []const u8, comptime testFn: fn (Io, []const u8) anyerror!void) !void {
    var buf: [64]u8 = undefined;
    const path = uniqueTestPath(io, &buf);
    try fs.writeFile(io, path, content);
    defer Io.Dir.cwd().deleteFile(io, path) catch {};
    try testFn(io, path);
}

test "a triangle with only positions defaults normal/uv" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    try withTempObj(io,
        \\v 0.0 0.0 0.0
        \\v 1.0 0.0 0.0
        \\v 0.0 1.0 0.0
        \\f 1 2 3
    , struct {
        fn run(io2: Io, path: []const u8) anyerror!void {
            var mesh = try loadObj(io2, std.testing.allocator, path);
            defer mesh.deinit(std.testing.allocator);

            try std.testing.expectEqual(@as(usize, 3), mesh.vertices.len);
            try std.testing.expectEqual(@as(usize, 3), mesh.indices.len);
            try std.testing.expectEqual(@Vector(3, f32){ 0.0, 0.0, 1.0 }, mesh.vertices[0].normal);
            try std.testing.expectEqual(@Vector(2, f32){ 0.0, 0.0 }, mesh.vertices[0].uv);
            try std.testing.expectEqual(@Vector(3, f32){ 1.0, 0.0, 0.0 }, mesh.vertices[1].pos);
        }
    }.run);
}

test "full v/vt/vn face maps attributes correctly" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    try withTempObj(io,
        \\v 0.0 0.0 0.0
        \\v 1.0 0.0 0.0
        \\v 0.0 1.0 0.0
        \\vt 0.0 0.0
        \\vt 1.0 0.0
        \\vt 0.0 1.0
        \\vn 0.0 0.0 1.0
        \\f 1/1/1 2/2/1 3/3/1
    , struct {
        fn run(io2: Io, path: []const u8) anyerror!void {
            var mesh = try loadObj(io2, std.testing.allocator, path);
            defer mesh.deinit(std.testing.allocator);

            try std.testing.expectEqual(@as(usize, 3), mesh.vertices.len);
            try std.testing.expectEqual(@Vector(2, f32){ 1.0, 0.0 }, mesh.vertices[1].uv);
            try std.testing.expectEqual(@Vector(3, f32){ 0.0, 0.0, 1.0 }, mesh.vertices[2].normal);
        }
    }.run);
}

test "a quad face is fan-triangulated into two triangles" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    try withTempObj(io,
        \\v 0.0 0.0 0.0
        \\v 1.0 0.0 0.0
        \\v 1.0 1.0 0.0
        \\v 0.0 1.0 0.0
        \\f 1 2 3 4
    , struct {
        fn run(io2: Io, path: []const u8) anyerror!void {
            var mesh = try loadObj(io2, std.testing.allocator, path);
            defer mesh.deinit(std.testing.allocator);

            try std.testing.expectEqual(@as(usize, 4), mesh.vertices.len);
            try std.testing.expectEqual(@as(usize, 6), mesh.indices.len); // 2 triangles
            try std.testing.expectEqualSlices(u32, &.{ 0, 1, 2, 0, 2, 3 }, mesh.indices);
        }
    }.run);
}

test "negative relative indices resolve from the end of the list" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    try withTempObj(io,
        \\v 0.0 0.0 0.0
        \\v 1.0 0.0 0.0
        \\v 0.0 1.0 0.0
        \\f -3 -2 -1
    , struct {
        fn run(io2: Io, path: []const u8) anyerror!void {
            var mesh = try loadObj(io2, std.testing.allocator, path);
            defer mesh.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), mesh.vertices.len);
            try std.testing.expectEqual(@Vector(3, f32){ 0.0, 0.0, 0.0 }, mesh.vertices[0].pos);
        }
    }.run);
}

test "comments and blank lines are ignored" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    try withTempObj(io,
        \\# a comment
        \\
        \\v 0.0 0.0 0.0
        \\v 1.0 0.0 0.0
        \\v 0.0 1.0 0.0
        \\
        \\# another comment
        \\f 1 2 3
    , struct {
        fn run(io2: Io, path: []const u8) anyerror!void {
            var mesh = try loadObj(io2, std.testing.allocator, path);
            defer mesh.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), mesh.vertices.len);
        }
    }.run);
}

test "vertices reused across faces with the same attribute triple are deduplicated" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    try withTempObj(io,
        \\v 0.0 0.0 0.0
        \\v 1.0 0.0 0.0
        \\v 0.0 1.0 0.0
        \\v 1.0 1.0 0.0
        \\f 1 2 3
        \\f 1 3 4
    , struct {
        fn run(io2: Io, path: []const u8) anyerror!void {
            var mesh = try loadObj(io2, std.testing.allocator, path);
            defer mesh.deinit(std.testing.allocator);
            // vertex 1 and 3 are shared between both faces and should not be duplicated.
            try std.testing.expectEqual(@as(usize, 4), mesh.vertices.len);
            try std.testing.expectEqual(@as(usize, 6), mesh.indices.len);
        }
    }.run);
}

test "a malformed face line returns an error instead of garbage data" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    try withTempObj(io,
        \\v 0.0 0.0 0.0
        \\v 1.0 0.0 0.0
        \\v 0.0 1.0 0.0
        \\f 1 2
    , struct {
        fn run(io2: Io, path: []const u8) anyerror!void {
            try std.testing.expectError(error.ObjMalformedFace, loadObj(io2, std.testing.allocator, path));
        }
    }.run);
}
