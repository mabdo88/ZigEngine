const std = @import("std");
const gltf = @import("cgltf.zig");
const stbi = @cImport({
    @cInclude("../stb/stb_image.h");
});

const components = @import("ecs/Component/components.zig");

pub const GltfLoadResult = struct {
    mesh: components.MeshComponent,
    pixels: []u8,
    width: u32,
    height: u32,
};

pub fn loadgltf(allocator: std.mem.Allocator, path: [:0]const u8) !GltfLoadResult {
    var options = std.mem.zeroes(gltf.cgltf_options);
    var data: [*c]gltf.cgltf_data = null;

    var result = gltf.cgltf_parse_file(&options, path, &data);
    if (result != gltf.cgltf_result_success) return error.gltfParseFailed;
    defer gltf.cgltf_free(data);
    result = gltf.cgltf_load_buffers(&options, data.?, path);
    if (result != gltf.cgltf_result_success) return error.gltfLoadBuffersFailed;
    if (data.*.meshes_count == 0) return error.gltfNoMeshes;
    if (data.*.meshes[0].primitives_count == 0) return error.gltfNoPrimitives;
    const prim = data.*.meshes[0].primitives[0];
    var pos_accessor: ?*gltf.struct_cgltf_accessor = null;
    var normal_accessor: ?*gltf.struct_cgltf_accessor = null;
    var uv_accessor: ?*gltf.struct_cgltf_accessor = null;
    for (0..prim.attributes_count) |i| {
        const attr = prim.attributes[i];
        switch (attr.type) {
            gltf.cgltf_attribute_type_position => pos_accessor = attr.data,
            gltf.cgltf_attribute_type_normal => normal_accessor = attr.data,
            gltf.cgltf_attribute_type_texcoord => uv_accessor = attr.data,
            else => {},
        }
    }
    if (pos_accessor == null or normal_accessor == null or uv_accessor == null)
        return error.gltfAttributeMissing;
    const vertex_count = pos_accessor.?.count;
    const vertices = try allocator.alloc(components.Vertex, vertex_count);
    for (0..vertex_count) |i| {
        var pos: [3]f32 = .{ 0, 0, 0 };
        var normal: [3]f32 = .{ 0, 0, 0 };
        var uv: [2]f32 = .{ 0, 0 };
        _ = gltf.cgltf_accessor_read_float(pos_accessor.?, i, &pos, 3);
        _ = gltf.cgltf_accessor_read_float(normal_accessor.?, i, &normal, 3);
        _ = gltf.cgltf_accessor_read_float(uv_accessor.?, i, &uv, 2);
        vertices[i] = .{ .pos = .{ pos[0], pos[1], pos[2] }, .normal = .{ normal[0], normal[1], normal[2] }, .uv = .{ uv[0], uv[1] } };
    }
    if (prim.indices == null) return error.gltfNoIndices;
    const index_count = prim.indices.*.count;
    const indices = try allocator.alloc(u32, index_count);
    for (0..index_count) |i| {
        indices[i] = @intCast(gltf.cgltf_accessor_read_index(prim.indices, i));
    }
    var pixels: []u8 = undefined;
    var texWidth: u32 = 0;
    var texHeight: u32 = 0;

    if (prim.material != null and
        prim.material.*.has_pbr_metallic_roughness != 0 and
        prim.material.*.pbr_metallic_roughness.base_color_texture.texture != null)
    {
        const texture = prim.material.*.pbr_metallic_roughness.base_color_texture.texture;
        const image = texture.*.image;
        const uri = std.mem.sliceTo(image.*.uri, 0);
        const dir = std.fs.path.dirname(path) orelse ".";
        const imgPath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, uri });
        defer allocator.free(imgPath);
        var w: c_int = 0;
        var h: c_int = 0;
        var channels: c_int = 0;
        const decoded = stbi.stbi_load(imgPath.ptr, &w, &h, &channels, 4);
        if (decoded == null) return error.stbiLoadFailed;
        texWidth = @intCast(w);
        texHeight = @intCast(h);
        const size = texWidth * texHeight * 4;
        pixels = try allocator.alloc(u8, size);
        @memcpy(pixels, decoded[0..size]);
        stbi.stbi_image_free(decoded);
    } else {
        pixels = try allocator.alloc(u8, 4);
        pixels[0] = 255;
        pixels[1] = 255;
        pixels[2] = 255;
        pixels[3] = 255;
        texWidth = 1;
        texHeight = 1;
    }

    return GltfLoadResult{
        .mesh = components.MeshComponent{ .vertices = vertices, .indices = indices },
        .pixels = pixels,
        .width = texWidth,
        .height = texHeight,
    };
}
