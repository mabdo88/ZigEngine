const __root = @This();
pub const __builtin = @import("std").zig.c_translation.builtins;
pub const __helpers = @import("std").zig.c_translation.helpers;
pub const ptrdiff_t = c_longlong;
pub const wchar_t = c_ushort;
pub const max_align_t = extern struct {
    __aro_max_align_ll: c_longlong = 0,
    __aro_max_align_ld: c_longdouble = 0,
};
pub const int_least64_t = i64;
pub const uint_least64_t = u64;
pub const int_fast64_t = i64;
pub const uint_fast64_t = u64;
pub const int_least32_t = i32;
pub const uint_least32_t = u32;
pub const int_fast32_t = i32;
pub const uint_fast32_t = u32;
pub const int_least16_t = i16;
pub const uint_least16_t = u16;
pub const int_fast16_t = i16;
pub const uint_fast16_t = u16;
pub const int_least8_t = i8;
pub const uint_least8_t = u8;
pub const int_fast8_t = i8;
pub const uint_fast8_t = u8;
pub const intmax_t = c_longlong;
pub const uintmax_t = c_ulonglong;
pub const cgltf_size = usize;
pub const cgltf_ssize = c_longlong;
pub const cgltf_float = f32;
pub const cgltf_int = c_int;
pub const cgltf_uint = c_uint;
pub const cgltf_bool = c_int;
pub const cgltf_file_type_invalid: c_int = 0;
pub const cgltf_file_type_gltf: c_int = 1;
pub const cgltf_file_type_glb: c_int = 2;
pub const cgltf_file_type_max_enum: c_int = 3;
pub const enum_cgltf_file_type = c_uint;
pub const cgltf_file_type = enum_cgltf_file_type;
pub const cgltf_result_success: c_int = 0;
pub const cgltf_result_data_too_short: c_int = 1;
pub const cgltf_result_unknown_format: c_int = 2;
pub const cgltf_result_invalid_json: c_int = 3;
pub const cgltf_result_invalid_gltf: c_int = 4;
pub const cgltf_result_invalid_options: c_int = 5;
pub const cgltf_result_file_not_found: c_int = 6;
pub const cgltf_result_io_error: c_int = 7;
pub const cgltf_result_out_of_memory: c_int = 8;
pub const cgltf_result_legacy_gltf: c_int = 9;
pub const cgltf_result_max_enum: c_int = 10;
pub const enum_cgltf_result = c_uint;
pub const cgltf_result = enum_cgltf_result;
pub const struct_cgltf_memory_options = extern struct {
    alloc_func: ?*const fn (user: ?*anyopaque, size: cgltf_size) callconv(.c) ?*anyopaque = null,
    free_func: ?*const fn (user: ?*anyopaque, ptr: ?*anyopaque) callconv(.c) void = null,
    user_data: ?*anyopaque = null,
};
pub const cgltf_memory_options = struct_cgltf_memory_options;
pub const struct_cgltf_file_options = extern struct {
    read: ?*const fn (memory_options: [*c]const struct_cgltf_memory_options, file_options: [*c]const struct_cgltf_file_options, path: [*c]const u8, size: [*c]cgltf_size, data: [*c]?*anyopaque) callconv(.c) cgltf_result = null,
    release: ?*const fn (memory_options: [*c]const struct_cgltf_memory_options, file_options: [*c]const struct_cgltf_file_options, data: ?*anyopaque, size: cgltf_size) callconv(.c) void = null,
    user_data: ?*anyopaque = null,
};
pub const cgltf_file_options = struct_cgltf_file_options;
pub const struct_cgltf_options = extern struct {
    type: cgltf_file_type = @import("std").mem.zeroes(cgltf_file_type),
    json_token_count: cgltf_size = 0,
    memory: cgltf_memory_options = @import("std").mem.zeroes(cgltf_memory_options),
    file: cgltf_file_options = @import("std").mem.zeroes(cgltf_file_options),
    pub const cgltf_parse = __root.cgltf_parse;
    pub const cgltf_parse_file = __root.cgltf_parse_file;
    pub const cgltf_load_buffers = __root.cgltf_load_buffers;
    pub const cgltf_load_buffer_base64 = __root.cgltf_load_buffer_base64;
    pub const parse = __root.cgltf_parse;
    pub const buffers = __root.cgltf_load_buffers;
    pub const base64 = __root.cgltf_load_buffer_base64;
};
pub const cgltf_options = struct_cgltf_options;
pub const cgltf_buffer_view_type_invalid: c_int = 0;
pub const cgltf_buffer_view_type_indices: c_int = 1;
pub const cgltf_buffer_view_type_vertices: c_int = 2;
pub const cgltf_buffer_view_type_max_enum: c_int = 3;
pub const enum_cgltf_buffer_view_type = c_uint;
pub const cgltf_buffer_view_type = enum_cgltf_buffer_view_type;
pub const cgltf_attribute_type_invalid: c_int = 0;
pub const cgltf_attribute_type_position: c_int = 1;
pub const cgltf_attribute_type_normal: c_int = 2;
pub const cgltf_attribute_type_tangent: c_int = 3;
pub const cgltf_attribute_type_texcoord: c_int = 4;
pub const cgltf_attribute_type_color: c_int = 5;
pub const cgltf_attribute_type_joints: c_int = 6;
pub const cgltf_attribute_type_weights: c_int = 7;
pub const cgltf_attribute_type_custom: c_int = 8;
pub const cgltf_attribute_type_max_enum: c_int = 9;
pub const enum_cgltf_attribute_type = c_uint;
pub const cgltf_attribute_type = enum_cgltf_attribute_type;
pub const cgltf_component_type_invalid: c_int = 0;
pub const cgltf_component_type_r_8: c_int = 1;
pub const cgltf_component_type_r_8u: c_int = 2;
pub const cgltf_component_type_r_16: c_int = 3;
pub const cgltf_component_type_r_16u: c_int = 4;
pub const cgltf_component_type_r_32u: c_int = 5;
pub const cgltf_component_type_r_32f: c_int = 6;
pub const cgltf_component_type_max_enum: c_int = 7;
pub const enum_cgltf_component_type = c_uint;
pub const cgltf_component_type = enum_cgltf_component_type;
pub const cgltf_type_invalid: c_int = 0;
pub const cgltf_type_scalar: c_int = 1;
pub const cgltf_type_vec2: c_int = 2;
pub const cgltf_type_vec3: c_int = 3;
pub const cgltf_type_vec4: c_int = 4;
pub const cgltf_type_mat2: c_int = 5;
pub const cgltf_type_mat3: c_int = 6;
pub const cgltf_type_mat4: c_int = 7;
pub const cgltf_type_max_enum: c_int = 8;
pub const enum_cgltf_type = c_uint;
pub const cgltf_type = enum_cgltf_type;
pub const cgltf_primitive_type_invalid: c_int = 0;
pub const cgltf_primitive_type_points: c_int = 1;
pub const cgltf_primitive_type_lines: c_int = 2;
pub const cgltf_primitive_type_line_loop: c_int = 3;
pub const cgltf_primitive_type_line_strip: c_int = 4;
pub const cgltf_primitive_type_triangles: c_int = 5;
pub const cgltf_primitive_type_triangle_strip: c_int = 6;
pub const cgltf_primitive_type_triangle_fan: c_int = 7;
pub const cgltf_primitive_type_max_enum: c_int = 8;
pub const enum_cgltf_primitive_type = c_uint;
pub const cgltf_primitive_type = enum_cgltf_primitive_type;
pub const cgltf_alpha_mode_opaque: c_int = 0;
pub const cgltf_alpha_mode_mask: c_int = 1;
pub const cgltf_alpha_mode_blend: c_int = 2;
pub const cgltf_alpha_mode_max_enum: c_int = 3;
pub const enum_cgltf_alpha_mode = c_uint;
pub const cgltf_alpha_mode = enum_cgltf_alpha_mode;
pub const cgltf_animation_path_type_invalid: c_int = 0;
pub const cgltf_animation_path_type_translation: c_int = 1;
pub const cgltf_animation_path_type_rotation: c_int = 2;
pub const cgltf_animation_path_type_scale: c_int = 3;
pub const cgltf_animation_path_type_weights: c_int = 4;
pub const cgltf_animation_path_type_max_enum: c_int = 5;
pub const enum_cgltf_animation_path_type = c_uint;
pub const cgltf_animation_path_type = enum_cgltf_animation_path_type;
pub const cgltf_interpolation_type_linear: c_int = 0;
pub const cgltf_interpolation_type_step: c_int = 1;
pub const cgltf_interpolation_type_cubic_spline: c_int = 2;
pub const cgltf_interpolation_type_max_enum: c_int = 3;
pub const enum_cgltf_interpolation_type = c_uint;
pub const cgltf_interpolation_type = enum_cgltf_interpolation_type;
pub const cgltf_camera_type_invalid: c_int = 0;
pub const cgltf_camera_type_perspective: c_int = 1;
pub const cgltf_camera_type_orthographic: c_int = 2;
pub const cgltf_camera_type_max_enum: c_int = 3;
pub const enum_cgltf_camera_type = c_uint;
pub const cgltf_camera_type = enum_cgltf_camera_type;
pub const cgltf_light_type_invalid: c_int = 0;
pub const cgltf_light_type_directional: c_int = 1;
pub const cgltf_light_type_point: c_int = 2;
pub const cgltf_light_type_spot: c_int = 3;
pub const cgltf_light_type_max_enum: c_int = 4;
pub const enum_cgltf_light_type = c_uint;
pub const cgltf_light_type = enum_cgltf_light_type;
pub const cgltf_data_free_method_none: c_int = 0;
pub const cgltf_data_free_method_file_release: c_int = 1;
pub const cgltf_data_free_method_memory_free: c_int = 2;
pub const cgltf_data_free_method_max_enum: c_int = 3;
pub const enum_cgltf_data_free_method = c_uint;
pub const cgltf_data_free_method = enum_cgltf_data_free_method;
pub const struct_cgltf_extras = extern struct {
    start_offset: cgltf_size = 0,
    end_offset: cgltf_size = 0,
    data: [*c]u8 = null,
};
pub const cgltf_extras = struct_cgltf_extras;
pub const struct_cgltf_extension = extern struct {
    name: [*c]u8 = null,
    data: [*c]u8 = null,
};
pub const cgltf_extension = struct_cgltf_extension;
pub const struct_cgltf_buffer = extern struct {
    name: [*c]u8 = null,
    size: cgltf_size = 0,
    uri: [*c]u8 = null,
    data: ?*anyopaque = null,
    data_free_method: cgltf_data_free_method = @import("std").mem.zeroes(cgltf_data_free_method),
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_buffer = struct_cgltf_buffer;
pub const cgltf_meshopt_compression_mode_invalid: c_int = 0;
pub const cgltf_meshopt_compression_mode_attributes: c_int = 1;
pub const cgltf_meshopt_compression_mode_triangles: c_int = 2;
pub const cgltf_meshopt_compression_mode_indices: c_int = 3;
pub const cgltf_meshopt_compression_mode_max_enum: c_int = 4;
pub const enum_cgltf_meshopt_compression_mode = c_uint;
pub const cgltf_meshopt_compression_mode = enum_cgltf_meshopt_compression_mode;
pub const cgltf_meshopt_compression_filter_none: c_int = 0;
pub const cgltf_meshopt_compression_filter_octahedral: c_int = 1;
pub const cgltf_meshopt_compression_filter_quaternion: c_int = 2;
pub const cgltf_meshopt_compression_filter_exponential: c_int = 3;
pub const cgltf_meshopt_compression_filter_color: c_int = 4;
pub const cgltf_meshopt_compression_filter_max_enum: c_int = 5;
pub const enum_cgltf_meshopt_compression_filter = c_uint;
pub const cgltf_meshopt_compression_filter = enum_cgltf_meshopt_compression_filter;
pub const struct_cgltf_meshopt_compression = extern struct {
    buffer: [*c]cgltf_buffer = null,
    offset: cgltf_size = 0,
    size: cgltf_size = 0,
    stride: cgltf_size = 0,
    count: cgltf_size = 0,
    mode: cgltf_meshopt_compression_mode = @import("std").mem.zeroes(cgltf_meshopt_compression_mode),
    filter: cgltf_meshopt_compression_filter = @import("std").mem.zeroes(cgltf_meshopt_compression_filter),
    is_khr: cgltf_bool = 0,
};
pub const cgltf_meshopt_compression = struct_cgltf_meshopt_compression;
pub const struct_cgltf_buffer_view = extern struct {
    name: [*c]u8 = null,
    buffer: [*c]cgltf_buffer = null,
    offset: cgltf_size = 0,
    size: cgltf_size = 0,
    stride: cgltf_size = 0,
    type: cgltf_buffer_view_type = @import("std").mem.zeroes(cgltf_buffer_view_type),
    data: ?*anyopaque = null,
    has_meshopt_compression: cgltf_bool = 0,
    meshopt_compression: cgltf_meshopt_compression = @import("std").mem.zeroes(cgltf_meshopt_compression),
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
    pub const cgltf_buffer_view_data = __root.cgltf_buffer_view_data;
};
pub const cgltf_buffer_view = struct_cgltf_buffer_view;
pub const struct_cgltf_accessor_sparse = extern struct {
    count: cgltf_size = 0,
    indices_buffer_view: [*c]cgltf_buffer_view = null,
    indices_byte_offset: cgltf_size = 0,
    indices_component_type: cgltf_component_type = @import("std").mem.zeroes(cgltf_component_type),
    values_buffer_view: [*c]cgltf_buffer_view = null,
    values_byte_offset: cgltf_size = 0,
};
pub const cgltf_accessor_sparse = struct_cgltf_accessor_sparse;
pub const struct_cgltf_accessor = extern struct {
    name: [*c]u8 = null,
    component_type: cgltf_component_type = @import("std").mem.zeroes(cgltf_component_type),
    normalized: cgltf_bool = 0,
    type: cgltf_type = @import("std").mem.zeroes(cgltf_type),
    offset: cgltf_size = 0,
    count: cgltf_size = 0,
    stride: cgltf_size = 0,
    buffer_view: [*c]cgltf_buffer_view = null,
    has_min: cgltf_bool = 0,
    min: [16]cgltf_float = @import("std").mem.zeroes([16]cgltf_float),
    has_max: cgltf_bool = 0,
    max: [16]cgltf_float = @import("std").mem.zeroes([16]cgltf_float),
    is_sparse: cgltf_bool = 0,
    sparse: cgltf_accessor_sparse = @import("std").mem.zeroes(cgltf_accessor_sparse),
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
    pub const cgltf_accessor_read_float = __root.cgltf_accessor_read_float;
    pub const cgltf_accessor_read_uint = __root.cgltf_accessor_read_uint;
    pub const cgltf_accessor_read_index = __root.cgltf_accessor_read_index;
    pub const cgltf_accessor_unpack_floats = __root.cgltf_accessor_unpack_floats;
    pub const cgltf_accessor_unpack_indices = __root.cgltf_accessor_unpack_indices;
    pub const read_float = __root.cgltf_accessor_read_float;
    pub const read_uint = __root.cgltf_accessor_read_uint;
    pub const read_index = __root.cgltf_accessor_read_index;
    pub const unpack_floats = __root.cgltf_accessor_unpack_floats;
    pub const unpack_indices = __root.cgltf_accessor_unpack_indices;
};
pub const cgltf_accessor = struct_cgltf_accessor;
pub const struct_cgltf_attribute = extern struct {
    name: [*c]u8 = null,
    type: cgltf_attribute_type = @import("std").mem.zeroes(cgltf_attribute_type),
    index: cgltf_int = 0,
    data: [*c]cgltf_accessor = null,
};
pub const cgltf_attribute = struct_cgltf_attribute;
pub const struct_cgltf_image = extern struct {
    name: [*c]u8 = null,
    uri: [*c]u8 = null,
    buffer_view: [*c]cgltf_buffer_view = null,
    mime_type: [*c]u8 = null,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_image = struct_cgltf_image;
pub const cgltf_filter_type_undefined: c_int = 0;
pub const cgltf_filter_type_nearest: c_int = 9728;
pub const cgltf_filter_type_linear: c_int = 9729;
pub const cgltf_filter_type_nearest_mipmap_nearest: c_int = 9984;
pub const cgltf_filter_type_linear_mipmap_nearest: c_int = 9985;
pub const cgltf_filter_type_nearest_mipmap_linear: c_int = 9986;
pub const cgltf_filter_type_linear_mipmap_linear: c_int = 9987;
pub const enum_cgltf_filter_type = c_uint;
pub const cgltf_filter_type = enum_cgltf_filter_type;
pub const cgltf_wrap_mode_clamp_to_edge: c_int = 33071;
pub const cgltf_wrap_mode_mirrored_repeat: c_int = 33648;
pub const cgltf_wrap_mode_repeat: c_int = 10497;
pub const enum_cgltf_wrap_mode = c_uint;
pub const cgltf_wrap_mode = enum_cgltf_wrap_mode;
pub const struct_cgltf_sampler = extern struct {
    name: [*c]u8 = null,
    mag_filter: cgltf_filter_type = @import("std").mem.zeroes(cgltf_filter_type),
    min_filter: cgltf_filter_type = @import("std").mem.zeroes(cgltf_filter_type),
    wrap_s: cgltf_wrap_mode = @import("std").mem.zeroes(cgltf_wrap_mode),
    wrap_t: cgltf_wrap_mode = @import("std").mem.zeroes(cgltf_wrap_mode),
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_sampler = struct_cgltf_sampler;
pub const struct_cgltf_texture = extern struct {
    name: [*c]u8 = null,
    image: [*c]cgltf_image = null,
    sampler: [*c]cgltf_sampler = null,
    has_basisu: cgltf_bool = 0,
    basisu_image: [*c]cgltf_image = null,
    has_webp: cgltf_bool = 0,
    webp_image: [*c]cgltf_image = null,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_texture = struct_cgltf_texture;
pub const struct_cgltf_texture_transform = extern struct {
    offset: [2]cgltf_float = @import("std").mem.zeroes([2]cgltf_float),
    rotation: cgltf_float = 0,
    scale: [2]cgltf_float = @import("std").mem.zeroes([2]cgltf_float),
    has_texcoord: cgltf_bool = 0,
    texcoord: cgltf_int = 0,
};
pub const cgltf_texture_transform = struct_cgltf_texture_transform;
pub const struct_cgltf_texture_view = extern struct {
    texture: [*c]cgltf_texture = null,
    texcoord: cgltf_int = 0,
    scale: cgltf_float = 0,
    has_transform: cgltf_bool = 0,
    transform: cgltf_texture_transform = @import("std").mem.zeroes(cgltf_texture_transform),
};
pub const cgltf_texture_view = struct_cgltf_texture_view;
pub const struct_cgltf_pbr_metallic_roughness = extern struct {
    base_color_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    metallic_roughness_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    base_color_factor: [4]cgltf_float = @import("std").mem.zeroes([4]cgltf_float),
    metallic_factor: cgltf_float = 0,
    roughness_factor: cgltf_float = 0,
};
pub const cgltf_pbr_metallic_roughness = struct_cgltf_pbr_metallic_roughness;
pub const struct_cgltf_pbr_specular_glossiness = extern struct {
    diffuse_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    specular_glossiness_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    diffuse_factor: [4]cgltf_float = @import("std").mem.zeroes([4]cgltf_float),
    specular_factor: [3]cgltf_float = @import("std").mem.zeroes([3]cgltf_float),
    glossiness_factor: cgltf_float = 0,
};
pub const cgltf_pbr_specular_glossiness = struct_cgltf_pbr_specular_glossiness;
pub const struct_cgltf_clearcoat = extern struct {
    clearcoat_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    clearcoat_roughness_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    clearcoat_normal_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    clearcoat_factor: cgltf_float = 0,
    clearcoat_roughness_factor: cgltf_float = 0,
};
pub const cgltf_clearcoat = struct_cgltf_clearcoat;
pub const struct_cgltf_transmission = extern struct {
    transmission_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    transmission_factor: cgltf_float = 0,
};
pub const cgltf_transmission = struct_cgltf_transmission;
pub const struct_cgltf_ior = extern struct {
    ior: cgltf_float = 0,
};
pub const cgltf_ior = struct_cgltf_ior;
pub const struct_cgltf_specular = extern struct {
    specular_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    specular_color_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    specular_color_factor: [3]cgltf_float = @import("std").mem.zeroes([3]cgltf_float),
    specular_factor: cgltf_float = 0,
};
pub const cgltf_specular = struct_cgltf_specular;
pub const struct_cgltf_volume = extern struct {
    thickness_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    thickness_factor: cgltf_float = 0,
    attenuation_color: [3]cgltf_float = @import("std").mem.zeroes([3]cgltf_float),
    attenuation_distance: cgltf_float = 0,
};
pub const cgltf_volume = struct_cgltf_volume;
pub const struct_cgltf_sheen = extern struct {
    sheen_color_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    sheen_color_factor: [3]cgltf_float = @import("std").mem.zeroes([3]cgltf_float),
    sheen_roughness_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    sheen_roughness_factor: cgltf_float = 0,
};
pub const cgltf_sheen = struct_cgltf_sheen;
pub const struct_cgltf_emissive_strength = extern struct {
    emissive_strength: cgltf_float = 0,
};
pub const cgltf_emissive_strength = struct_cgltf_emissive_strength;
pub const struct_cgltf_iridescence = extern struct {
    iridescence_factor: cgltf_float = 0,
    iridescence_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    iridescence_ior: cgltf_float = 0,
    iridescence_thickness_min: cgltf_float = 0,
    iridescence_thickness_max: cgltf_float = 0,
    iridescence_thickness_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
};
pub const cgltf_iridescence = struct_cgltf_iridescence;
pub const struct_cgltf_diffuse_transmission = extern struct {
    diffuse_transmission_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    diffuse_transmission_factor: cgltf_float = 0,
    diffuse_transmission_color_factor: [3]cgltf_float = @import("std").mem.zeroes([3]cgltf_float),
    diffuse_transmission_color_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
};
pub const cgltf_diffuse_transmission = struct_cgltf_diffuse_transmission;
pub const struct_cgltf_anisotropy = extern struct {
    anisotropy_strength: cgltf_float = 0,
    anisotropy_rotation: cgltf_float = 0,
    anisotropy_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
};
pub const cgltf_anisotropy = struct_cgltf_anisotropy;
pub const struct_cgltf_dispersion = extern struct {
    dispersion: cgltf_float = 0,
};
pub const cgltf_dispersion = struct_cgltf_dispersion;
pub const struct_cgltf_material = extern struct {
    name: [*c]u8 = null,
    has_pbr_metallic_roughness: cgltf_bool = 0,
    has_pbr_specular_glossiness: cgltf_bool = 0,
    has_clearcoat: cgltf_bool = 0,
    has_transmission: cgltf_bool = 0,
    has_volume: cgltf_bool = 0,
    has_ior: cgltf_bool = 0,
    has_specular: cgltf_bool = 0,
    has_sheen: cgltf_bool = 0,
    has_emissive_strength: cgltf_bool = 0,
    has_iridescence: cgltf_bool = 0,
    has_diffuse_transmission: cgltf_bool = 0,
    has_anisotropy: cgltf_bool = 0,
    has_dispersion: cgltf_bool = 0,
    pbr_metallic_roughness: cgltf_pbr_metallic_roughness = @import("std").mem.zeroes(cgltf_pbr_metallic_roughness),
    pbr_specular_glossiness: cgltf_pbr_specular_glossiness = @import("std").mem.zeroes(cgltf_pbr_specular_glossiness),
    clearcoat: cgltf_clearcoat = @import("std").mem.zeroes(cgltf_clearcoat),
    ior: cgltf_ior = @import("std").mem.zeroes(cgltf_ior),
    specular: cgltf_specular = @import("std").mem.zeroes(cgltf_specular),
    sheen: cgltf_sheen = @import("std").mem.zeroes(cgltf_sheen),
    transmission: cgltf_transmission = @import("std").mem.zeroes(cgltf_transmission),
    volume: cgltf_volume = @import("std").mem.zeroes(cgltf_volume),
    emissive_strength: cgltf_emissive_strength = @import("std").mem.zeroes(cgltf_emissive_strength),
    iridescence: cgltf_iridescence = @import("std").mem.zeroes(cgltf_iridescence),
    diffuse_transmission: cgltf_diffuse_transmission = @import("std").mem.zeroes(cgltf_diffuse_transmission),
    anisotropy: cgltf_anisotropy = @import("std").mem.zeroes(cgltf_anisotropy),
    dispersion: cgltf_dispersion = @import("std").mem.zeroes(cgltf_dispersion),
    normal_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    occlusion_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    emissive_texture: cgltf_texture_view = @import("std").mem.zeroes(cgltf_texture_view),
    emissive_factor: [3]cgltf_float = @import("std").mem.zeroes([3]cgltf_float),
    alpha_mode: cgltf_alpha_mode = @import("std").mem.zeroes(cgltf_alpha_mode),
    alpha_cutoff: cgltf_float = 0,
    double_sided: cgltf_bool = 0,
    unlit: cgltf_bool = 0,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_material = struct_cgltf_material;
pub const struct_cgltf_material_mapping = extern struct {
    variant: cgltf_size = 0,
    material: [*c]cgltf_material = null,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
};
pub const cgltf_material_mapping = struct_cgltf_material_mapping;
pub const struct_cgltf_morph_target = extern struct {
    attributes: [*c]cgltf_attribute = null,
    attributes_count: cgltf_size = 0,
};
pub const cgltf_morph_target = struct_cgltf_morph_target;
pub const struct_cgltf_draco_mesh_compression = extern struct {
    buffer_view: [*c]cgltf_buffer_view = null,
    attributes: [*c]cgltf_attribute = null,
    attributes_count: cgltf_size = 0,
};
pub const cgltf_draco_mesh_compression = struct_cgltf_draco_mesh_compression;
pub const struct_cgltf_mesh_gpu_instancing = extern struct {
    attributes: [*c]cgltf_attribute = null,
    attributes_count: cgltf_size = 0,
};
pub const cgltf_mesh_gpu_instancing = struct_cgltf_mesh_gpu_instancing;
pub const struct_cgltf_primitive = extern struct {
    type: cgltf_primitive_type = @import("std").mem.zeroes(cgltf_primitive_type),
    indices: [*c]cgltf_accessor = null,
    material: [*c]cgltf_material = null,
    attributes: [*c]cgltf_attribute = null,
    attributes_count: cgltf_size = 0,
    targets: [*c]cgltf_morph_target = null,
    targets_count: cgltf_size = 0,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    has_draco_mesh_compression: cgltf_bool = 0,
    draco_mesh_compression: cgltf_draco_mesh_compression = @import("std").mem.zeroes(cgltf_draco_mesh_compression),
    mappings: [*c]cgltf_material_mapping = null,
    mappings_count: cgltf_size = 0,
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
    pub const cgltf_find_accessor = __root.cgltf_find_accessor;
    pub const accessor = __root.cgltf_find_accessor;
};
pub const cgltf_primitive = struct_cgltf_primitive;
pub const struct_cgltf_mesh = extern struct {
    name: [*c]u8 = null,
    primitives: [*c]cgltf_primitive = null,
    primitives_count: cgltf_size = 0,
    weights: [*c]cgltf_float = null,
    weights_count: cgltf_size = 0,
    target_names: [*c][*c]u8 = null,
    target_names_count: cgltf_size = 0,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_mesh = struct_cgltf_mesh;
pub const cgltf_node = struct_cgltf_node;
pub const struct_cgltf_skin = extern struct {
    name: [*c]u8 = null,
    joints: [*c][*c]cgltf_node = null,
    joints_count: cgltf_size = 0,
    skeleton: [*c]cgltf_node = null,
    inverse_bind_matrices: [*c]cgltf_accessor = null,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_skin = struct_cgltf_skin;
pub const struct_cgltf_camera_perspective = extern struct {
    has_aspect_ratio: cgltf_bool = 0,
    aspect_ratio: cgltf_float = 0,
    yfov: cgltf_float = 0,
    has_zfar: cgltf_bool = 0,
    zfar: cgltf_float = 0,
    znear: cgltf_float = 0,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
};
pub const cgltf_camera_perspective = struct_cgltf_camera_perspective;
pub const struct_cgltf_camera_orthographic = extern struct {
    xmag: cgltf_float = 0,
    ymag: cgltf_float = 0,
    zfar: cgltf_float = 0,
    znear: cgltf_float = 0,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
};
pub const cgltf_camera_orthographic = struct_cgltf_camera_orthographic;
const union_unnamed_1 = extern union {
    perspective: cgltf_camera_perspective,
    orthographic: cgltf_camera_orthographic,
};
pub const struct_cgltf_camera = extern struct {
    name: [*c]u8 = null,
    type: cgltf_camera_type = @import("std").mem.zeroes(cgltf_camera_type),
    data: union_unnamed_1 = @import("std").mem.zeroes(union_unnamed_1),
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_camera = struct_cgltf_camera;
pub const struct_cgltf_light = extern struct {
    name: [*c]u8 = null,
    color: [3]cgltf_float = @import("std").mem.zeroes([3]cgltf_float),
    intensity: cgltf_float = 0,
    type: cgltf_light_type = @import("std").mem.zeroes(cgltf_light_type),
    range: cgltf_float = 0,
    spot_inner_cone_angle: cgltf_float = 0,
    spot_outer_cone_angle: cgltf_float = 0,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
};
pub const cgltf_light = struct_cgltf_light;
pub const struct_cgltf_node = extern struct {
    name: [*c]u8 = null,
    parent: [*c]cgltf_node = null,
    children: [*c][*c]cgltf_node = null,
    children_count: cgltf_size = 0,
    skin: [*c]cgltf_skin = null,
    mesh: [*c]cgltf_mesh = null,
    camera: [*c]cgltf_camera = null,
    light: [*c]cgltf_light = null,
    weights: [*c]cgltf_float = null,
    weights_count: cgltf_size = 0,
    has_translation: cgltf_bool = 0,
    has_rotation: cgltf_bool = 0,
    has_scale: cgltf_bool = 0,
    has_matrix: cgltf_bool = 0,
    translation: [3]cgltf_float = @import("std").mem.zeroes([3]cgltf_float),
    rotation: [4]cgltf_float = @import("std").mem.zeroes([4]cgltf_float),
    scale: [3]cgltf_float = @import("std").mem.zeroes([3]cgltf_float),
    matrix: [16]cgltf_float = @import("std").mem.zeroes([16]cgltf_float),
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    has_mesh_gpu_instancing: cgltf_bool = 0,
    mesh_gpu_instancing: cgltf_mesh_gpu_instancing = @import("std").mem.zeroes(cgltf_mesh_gpu_instancing),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
    pub const cgltf_node_transform_local = __root.cgltf_node_transform_local;
    pub const cgltf_node_transform_world = __root.cgltf_node_transform_world;
    pub const transform_local = __root.cgltf_node_transform_local;
    pub const transform_world = __root.cgltf_node_transform_world;
};
pub const struct_cgltf_scene = extern struct {
    name: [*c]u8 = null,
    nodes: [*c][*c]cgltf_node = null,
    nodes_count: cgltf_size = 0,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_scene = struct_cgltf_scene;
pub const struct_cgltf_animation_sampler = extern struct {
    input: [*c]cgltf_accessor = null,
    output: [*c]cgltf_accessor = null,
    interpolation: cgltf_interpolation_type = @import("std").mem.zeroes(cgltf_interpolation_type),
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_animation_sampler = struct_cgltf_animation_sampler;
pub const struct_cgltf_animation_channel = extern struct {
    sampler: [*c]cgltf_animation_sampler = null,
    target_node: [*c]cgltf_node = null,
    target_path: cgltf_animation_path_type = @import("std").mem.zeroes(cgltf_animation_path_type),
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_animation_channel = struct_cgltf_animation_channel;
pub const struct_cgltf_animation = extern struct {
    name: [*c]u8 = null,
    samplers: [*c]cgltf_animation_sampler = null,
    samplers_count: cgltf_size = 0,
    channels: [*c]cgltf_animation_channel = null,
    channels_count: cgltf_size = 0,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
    pub const cgltf_animation_sampler_index = __root.cgltf_animation_sampler_index;
    pub const cgltf_animation_channel_index = __root.cgltf_animation_channel_index;
    pub const sampler_index = __root.cgltf_animation_sampler_index;
    pub const channel_index = __root.cgltf_animation_channel_index;
};
pub const cgltf_animation = struct_cgltf_animation;
pub const struct_cgltf_material_variant = extern struct {
    name: [*c]u8 = null,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
};
pub const cgltf_material_variant = struct_cgltf_material_variant;
pub const struct_cgltf_asset = extern struct {
    copyright: [*c]u8 = null,
    generator: [*c]u8 = null,
    version: [*c]u8 = null,
    min_version: [*c]u8 = null,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    extensions_count: cgltf_size = 0,
    extensions: [*c]cgltf_extension = null,
};
pub const cgltf_asset = struct_cgltf_asset;
pub const struct_cgltf_data = extern struct {
    file_type: cgltf_file_type = @import("std").mem.zeroes(cgltf_file_type),
    file_data: ?*anyopaque = null,
    file_size: cgltf_size = 0,
    asset: cgltf_asset = @import("std").mem.zeroes(cgltf_asset),
    meshes: [*c]cgltf_mesh = null,
    meshes_count: cgltf_size = 0,
    materials: [*c]cgltf_material = null,
    materials_count: cgltf_size = 0,
    accessors: [*c]cgltf_accessor = null,
    accessors_count: cgltf_size = 0,
    buffer_views: [*c]cgltf_buffer_view = null,
    buffer_views_count: cgltf_size = 0,
    buffers: [*c]cgltf_buffer = null,
    buffers_count: cgltf_size = 0,
    images: [*c]cgltf_image = null,
    images_count: cgltf_size = 0,
    textures: [*c]cgltf_texture = null,
    textures_count: cgltf_size = 0,
    samplers: [*c]cgltf_sampler = null,
    samplers_count: cgltf_size = 0,
    skins: [*c]cgltf_skin = null,
    skins_count: cgltf_size = 0,
    cameras: [*c]cgltf_camera = null,
    cameras_count: cgltf_size = 0,
    lights: [*c]cgltf_light = null,
    lights_count: cgltf_size = 0,
    nodes: [*c]cgltf_node = null,
    nodes_count: cgltf_size = 0,
    scenes: [*c]cgltf_scene = null,
    scenes_count: cgltf_size = 0,
    scene: [*c]cgltf_scene = null,
    animations: [*c]cgltf_animation = null,
    animations_count: cgltf_size = 0,
    variants: [*c]cgltf_material_variant = null,
    variants_count: cgltf_size = 0,
    extras: cgltf_extras = @import("std").mem.zeroes(cgltf_extras),
    data_extensions_count: cgltf_size = 0,
    data_extensions: [*c]cgltf_extension = null,
    extensions_used: [*c][*c]u8 = null,
    extensions_used_count: cgltf_size = 0,
    extensions_required: [*c][*c]u8 = null,
    extensions_required_count: cgltf_size = 0,
    json: [*c]const u8 = null,
    json_size: cgltf_size = 0,
    bin: ?*const anyopaque = null,
    bin_size: cgltf_size = 0,
    memory: cgltf_memory_options = @import("std").mem.zeroes(cgltf_memory_options),
    file: cgltf_file_options = @import("std").mem.zeroes(cgltf_file_options),
    pub const cgltf_validate = __root.cgltf_validate;
    pub const cgltf_free = __root.cgltf_free;
    pub const cgltf_copy_extras_json = __root.cgltf_copy_extras_json;
    pub const cgltf_mesh_index = __root.cgltf_mesh_index;
    pub const cgltf_material_index = __root.cgltf_material_index;
    pub const cgltf_accessor_index = __root.cgltf_accessor_index;
    pub const cgltf_buffer_view_index = __root.cgltf_buffer_view_index;
    pub const cgltf_buffer_index = __root.cgltf_buffer_index;
    pub const cgltf_image_index = __root.cgltf_image_index;
    pub const cgltf_texture_index = __root.cgltf_texture_index;
    pub const cgltf_sampler_index = __root.cgltf_sampler_index;
    pub const cgltf_skin_index = __root.cgltf_skin_index;
    pub const cgltf_camera_index = __root.cgltf_camera_index;
    pub const cgltf_light_index = __root.cgltf_light_index;
    pub const cgltf_node_index = __root.cgltf_node_index;
    pub const cgltf_scene_index = __root.cgltf_scene_index;
    pub const cgltf_animation_index = __root.cgltf_animation_index;
    pub const validate = __root.cgltf_validate;
    pub const free = __root.cgltf_free;
    pub const index = __root.cgltf_mesh_index;
};
pub const cgltf_data = struct_cgltf_data;
pub extern fn cgltf_parse(options: [*c]const cgltf_options, data: ?*const anyopaque, size: cgltf_size, out_data: [*c][*c]cgltf_data) cgltf_result;
pub extern fn cgltf_parse_file(options: [*c]const cgltf_options, path: [*c]const u8, out_data: [*c][*c]cgltf_data) cgltf_result;
pub extern fn cgltf_load_buffers(options: [*c]const cgltf_options, data: [*c]cgltf_data, gltf_path: [*c]const u8) cgltf_result;
pub extern fn cgltf_load_buffer_base64(options: [*c]const cgltf_options, size: cgltf_size, base64: [*c]const u8, out_data: [*c]?*anyopaque) cgltf_result;
pub extern fn cgltf_decode_string(string: [*c]u8) cgltf_size;
pub extern fn cgltf_decode_uri(uri: [*c]u8) cgltf_size;
pub extern fn cgltf_validate(data: [*c]cgltf_data) cgltf_result;
pub extern fn cgltf_free(data: [*c]cgltf_data) void;
pub extern fn cgltf_node_transform_local(node: [*c]const cgltf_node, out_matrix: [*c]cgltf_float) void;
pub extern fn cgltf_node_transform_world(node: [*c]const cgltf_node, out_matrix: [*c]cgltf_float) void;
pub extern fn cgltf_buffer_view_data(view: [*c]const cgltf_buffer_view) [*c]const u8;
pub extern fn cgltf_find_accessor(prim: [*c]const cgltf_primitive, @"type": cgltf_attribute_type, index: cgltf_int) [*c]const cgltf_accessor;
pub extern fn cgltf_accessor_read_float(accessor: [*c]const cgltf_accessor, index: cgltf_size, out: [*c]cgltf_float, element_size: cgltf_size) cgltf_bool;
pub extern fn cgltf_accessor_read_uint(accessor: [*c]const cgltf_accessor, index: cgltf_size, out: [*c]cgltf_uint, element_size: cgltf_size) cgltf_bool;
pub extern fn cgltf_accessor_read_index(accessor: [*c]const cgltf_accessor, index: cgltf_size) cgltf_size;
pub extern fn cgltf_num_components(@"type": cgltf_type) cgltf_size;
pub extern fn cgltf_component_size(component_type: cgltf_component_type) cgltf_size;
pub extern fn cgltf_calc_size(@"type": cgltf_type, component_type: cgltf_component_type) cgltf_size;
pub extern fn cgltf_accessor_unpack_floats(accessor: [*c]const cgltf_accessor, out: [*c]cgltf_float, float_count: cgltf_size) cgltf_size;
pub extern fn cgltf_accessor_unpack_indices(accessor: [*c]const cgltf_accessor, out: ?*anyopaque, out_component_size: cgltf_size, index_count: cgltf_size) cgltf_size;
pub extern fn cgltf_copy_extras_json(data: [*c]const cgltf_data, extras: [*c]const cgltf_extras, dest: [*c]u8, dest_size: [*c]cgltf_size) cgltf_result;
pub extern fn cgltf_mesh_index(data: [*c]const cgltf_data, object: [*c]const cgltf_mesh) cgltf_size;
pub extern fn cgltf_material_index(data: [*c]const cgltf_data, object: [*c]const cgltf_material) cgltf_size;
pub extern fn cgltf_accessor_index(data: [*c]const cgltf_data, object: [*c]const cgltf_accessor) cgltf_size;
pub extern fn cgltf_buffer_view_index(data: [*c]const cgltf_data, object: [*c]const cgltf_buffer_view) cgltf_size;
pub extern fn cgltf_buffer_index(data: [*c]const cgltf_data, object: [*c]const cgltf_buffer) cgltf_size;
pub extern fn cgltf_image_index(data: [*c]const cgltf_data, object: [*c]const cgltf_image) cgltf_size;
pub extern fn cgltf_texture_index(data: [*c]const cgltf_data, object: [*c]const cgltf_texture) cgltf_size;
pub extern fn cgltf_sampler_index(data: [*c]const cgltf_data, object: [*c]const cgltf_sampler) cgltf_size;
pub extern fn cgltf_skin_index(data: [*c]const cgltf_data, object: [*c]const cgltf_skin) cgltf_size;
pub extern fn cgltf_camera_index(data: [*c]const cgltf_data, object: [*c]const cgltf_camera) cgltf_size;
pub extern fn cgltf_light_index(data: [*c]const cgltf_data, object: [*c]const cgltf_light) cgltf_size;
pub extern fn cgltf_node_index(data: [*c]const cgltf_data, object: [*c]const cgltf_node) cgltf_size;
pub extern fn cgltf_scene_index(data: [*c]const cgltf_data, object: [*c]const cgltf_scene) cgltf_size;
pub extern fn cgltf_animation_index(data: [*c]const cgltf_data, object: [*c]const cgltf_animation) cgltf_size;
pub extern fn cgltf_animation_sampler_index(animation: [*c]const cgltf_animation, object: [*c]const cgltf_animation_sampler) cgltf_size;
pub extern fn cgltf_animation_channel_index(animation: [*c]const cgltf_animation, object: [*c]const cgltf_animation_channel) cgltf_size;

pub const __VERSION__ = "Aro aro-zig";
pub const __Aro__ = "";
pub const __STDC__ = @as(c_int, 1);
pub const __STDC_HOSTED__ = @as(c_int, 1);
pub const __STDC_UTF_16__ = @as(c_int, 1);
pub const __STDC_UTF_32__ = @as(c_int, 1);
pub const __STDC_EMBED_NOT_FOUND__ = @as(c_int, 0);
pub const __STDC_EMBED_FOUND__ = @as(c_int, 1);
pub const __STDC_EMBED_EMPTY__ = @as(c_int, 2);
pub const __STDC_VERSION__ = @as(c_long, 201710);
pub const __GNUC__ = @as(c_int, 7);
pub const __GNUC_MINOR__ = @as(c_int, 1);
pub const __GNUC_PATCHLEVEL__ = @as(c_int, 0);
pub const __ARO_EMULATE_NO__ = @as(c_int, 0);
pub const __ARO_EMULATE_CLANG__ = @as(c_int, 1);
pub const __ARO_EMULATE_GCC__ = @as(c_int, 2);
pub const __ARO_EMULATE_MSVC__ = @as(c_int, 3);
pub const __ARO_EMULATE__ = __ARO_EMULATE_GCC__;
pub inline fn __building_module(x: anytype) @TypeOf(@as(c_int, 0)) {
    _ = &x;
    return @as(c_int, 0);
}
pub const _WIN32 = @as(c_int, 1);
pub const _WIN64 = @as(c_int, 1);
pub const WIN32 = @as(c_int, 1);
pub const __WIN32 = @as(c_int, 1);
pub const __WIN32__ = @as(c_int, 1);
pub const WINNT = @as(c_int, 1);
pub const __WINNT = @as(c_int, 1);
pub const __WINNT__ = @as(c_int, 1);
pub const WIN64 = @as(c_int, 1);
pub const __WIN64 = @as(c_int, 1);
pub const __WIN64__ = @as(c_int, 1);
pub const __MINGW64__ = @as(c_int, 1);
pub const __MSVCRT__ = @as(c_int, 1);
pub const __MINGW32__ = @as(c_int, 1);
pub const __declspec = @compileError("unable to translate C expr: unexpected token '__attribute__'"); // <builtin>:34:9
pub const _cdecl = @compileError("unable to translate macro: undefined identifier `__cdecl__`"); // <builtin>:35:9
pub const __cdecl = @compileError("unable to translate macro: undefined identifier `__cdecl__`"); // <builtin>:36:9
pub const _stdcall = @compileError("unable to translate macro: undefined identifier `__stdcall__`"); // <builtin>:37:9
pub const __stdcall = @compileError("unable to translate macro: undefined identifier `__stdcall__`"); // <builtin>:38:9
pub const _fastcall = @compileError("unable to translate macro: undefined identifier `__fastcall__`"); // <builtin>:39:9
pub const __fastcall = @compileError("unable to translate macro: undefined identifier `__fastcall__`"); // <builtin>:40:9
pub const _thiscall = @compileError("unable to translate macro: undefined identifier `__thiscall__`"); // <builtin>:41:9
pub const __thiscall = @compileError("unable to translate macro: undefined identifier `__thiscall__`"); // <builtin>:42:9
pub const unix = @as(c_int, 1);
pub const __unix = @as(c_int, 1);
pub const __unix__ = @as(c_int, 1);
pub const __code_model_small__ = @as(c_int, 1);
pub const __amd64__ = @as(c_int, 1);
pub const __amd64 = @as(c_int, 1);
pub const __x86_64__ = @as(c_int, 1);
pub const __x86_64 = @as(c_int, 1);
pub const __SEG_GS = @as(c_int, 1);
pub const __SEG_FS = @as(c_int, 1);
pub const __seg_gs = @compileError("unable to translate macro: undefined identifier `address_space`"); // <builtin>:53:9
pub const __seg_fs = @compileError("unable to translate macro: undefined identifier `address_space`"); // <builtin>:54:9
pub const __LAHF_SAHF__ = @as(c_int, 1);
pub const __AES__ = @as(c_int, 1);
pub const __PCLMUL__ = @as(c_int, 1);
pub const __LZCNT__ = @as(c_int, 1);
pub const __RDRND__ = @as(c_int, 1);
pub const __FSGSBASE__ = @as(c_int, 1);
pub const __BMI__ = @as(c_int, 1);
pub const __BMI2__ = @as(c_int, 1);
pub const __POPCNT__ = @as(c_int, 1);
pub const __PRFCHW__ = @as(c_int, 1);
pub const __RDSEED__ = @as(c_int, 1);
pub const __ADX__ = @as(c_int, 1);
pub const __MOVBE__ = @as(c_int, 1);
pub const __FMA__ = @as(c_int, 1);
pub const __F16C__ = @as(c_int, 1);
pub const __FXSR__ = @as(c_int, 1);
pub const __XSAVE__ = @as(c_int, 1);
pub const __XSAVEOPT__ = @as(c_int, 1);
pub const __XSAVEC__ = @as(c_int, 1);
pub const __XSAVES__ = @as(c_int, 1);
pub const __CLFLUSHOPT__ = @as(c_int, 1);
pub const __SGX__ = @as(c_int, 1);
pub const __INVPCID__ = @as(c_int, 1);
pub const __CRC32__ = @as(c_int, 1);
pub const __AVX2__ = @as(c_int, 1);
pub const __AVX__ = @as(c_int, 1);
pub const __SSE4_2__ = @as(c_int, 1);
pub const __SSE4_1__ = @as(c_int, 1);
pub const __SSSE3__ = @as(c_int, 1);
pub const __SSE3__ = @as(c_int, 1);
pub const __SSE2__ = @as(c_int, 1);
pub const __SSE__ = @as(c_int, 1);
pub const __SSE_MATH__ = @as(c_int, 1);
pub const __MMX__ = @as(c_int, 1);
pub const __GCC_HAVE_SYNC_COMPARE_AND_SWAP_8 = @as(c_int, 1);
pub const __ORDER_LITTLE_ENDIAN__ = @as(c_int, 1234);
pub const __ORDER_BIG_ENDIAN__ = @as(c_int, 4321);
pub const __ORDER_PDP_ENDIAN__ = @as(c_int, 3412);
pub const __BYTE_ORDER__ = __ORDER_LITTLE_ENDIAN__;
pub const __LITTLE_ENDIAN__ = @as(c_int, 1);
pub const __ATOMIC_RELAXED = @as(c_int, 0);
pub const __ATOMIC_CONSUME = @as(c_int, 1);
pub const __ATOMIC_ACQUIRE = @as(c_int, 2);
pub const __ATOMIC_RELEASE = @as(c_int, 3);
pub const __ATOMIC_ACQ_REL = @as(c_int, 4);
pub const __ATOMIC_SEQ_CST = @as(c_int, 5);
pub const __ATOMIC_BOOL_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR16_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_CHAR32_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_WCHAR_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_WINT_T_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_SHORT_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_INT_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_LONG_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_LLONG_LOCK_FREE = @as(c_int, 1);
pub const __ATOMIC_POINTER_LOCK_FREE = @as(c_int, 1);
pub const __WCHAR_UNSIGNED__ = @as(c_int, 1);
pub const __WINT_UNSIGNED__ = @as(c_int, 1);
pub const __CHAR_BIT__ = @as(c_int, 8);
pub const __BOOL_WIDTH__ = @as(c_int, 8);
pub const __SCHAR_MAX__ = @as(c_int, 127);
pub const __SCHAR_WIDTH__ = @as(c_int, 8);
pub const __SHRT_MAX__ = @as(c_int, 32767);
pub const __SHRT_WIDTH__ = @as(c_int, 16);
pub const __INT_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_WIDTH__ = @as(c_int, 32);
pub const __LONG_MAX__ = @as(c_long, 2147483647);
pub const __LONG_WIDTH__ = @as(c_int, 32);
pub const __LONG_LONG_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __LONG_LONG_WIDTH__ = @as(c_int, 64);
pub const __WCHAR_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __WCHAR_WIDTH__ = @as(c_int, 16);
pub const __WINT_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __WINT_WIDTH__ = @as(c_int, 16);
pub const __INTMAX_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __INTMAX_WIDTH__ = @as(c_int, 64);
pub const __SIZE_MAX__ = @as(c_ulonglong, 18446744073709551615);
pub const __SIZE_WIDTH__ = @as(c_int, 64);
pub const __UINTMAX_MAX__ = @as(c_ulonglong, 18446744073709551615);
pub const __UINTMAX_WIDTH__ = @as(c_int, 64);
pub const __PTRDIFF_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __PTRDIFF_WIDTH__ = @as(c_int, 64);
pub const __INTPTR_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __INTPTR_WIDTH__ = @as(c_int, 64);
pub const __UINTPTR_MAX__ = @as(c_ulonglong, 18446744073709551615);
pub const __UINTPTR_WIDTH__ = @as(c_int, 64);
pub const __SIG_ATOMIC_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __SIG_ATOMIC_WIDTH__ = @as(c_int, 32);
pub const __BITINT_MAXWIDTH__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __SIZEOF_FLOAT__ = @as(c_int, 4);
pub const __SIZEOF_DOUBLE__ = @as(c_int, 8);
pub const __SIZEOF_LONG_DOUBLE__ = @as(c_int, 10);
pub const __SIZEOF_SHORT__ = @as(c_int, 2);
pub const __SIZEOF_INT__ = @as(c_int, 4);
pub const __SIZEOF_LONG__ = @as(c_int, 4);
pub const __SIZEOF_LONG_LONG__ = @as(c_int, 8);
pub const __SIZEOF_POINTER__ = @as(c_int, 8);
pub const __SIZEOF_PTRDIFF_T__ = @as(c_int, 8);
pub const __SIZEOF_SIZE_T__ = @as(c_int, 8);
pub const __SIZEOF_WCHAR_T__ = @as(c_int, 2);
pub const __SIZEOF_WINT_T__ = @as(c_int, 2);
pub const __SIZEOF_INT128__ = @as(c_int, 16);
pub const __INTPTR_TYPE__ = c_longlong;
pub const __UINTPTR_TYPE__ = c_ulonglong;
pub const __INTMAX_TYPE__ = c_longlong;
pub const __INTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `LL`"); // <builtin>:162:9
pub const __INTMAX_C = __helpers.LL_SUFFIX;
pub const __UINTMAX_TYPE__ = c_ulonglong;
pub const __UINTMAX_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `ULL`"); // <builtin>:165:9
pub const __UINTMAX_C = __helpers.ULL_SUFFIX;
pub const __PTRDIFF_TYPE__ = c_longlong;
pub const __SIZE_TYPE__ = c_ulonglong;
pub const __WCHAR_TYPE__ = c_ushort;
pub const __WINT_TYPE__ = c_ushort;
pub const __CHAR16_TYPE__ = c_ushort;
pub const __CHAR32_TYPE__ = c_uint;
pub const __INT8_TYPE__ = i8;
pub const __INT8_FMTd__ = "hhd";
pub const __INT8_FMTi__ = "hhi";
pub const __INT8_C_SUFFIX__ = "";
pub inline fn __INT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT16_TYPE__ = c_short;
pub const __INT16_FMTd__ = "hd";
pub const __INT16_FMTi__ = "hi";
pub const __INT16_C_SUFFIX__ = "";
pub inline fn __INT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT32_TYPE__ = c_int;
pub const __INT32_FMTd__ = "d";
pub const __INT32_FMTi__ = "i";
pub const __INT32_C_SUFFIX__ = "";
pub inline fn __INT32_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __INT64_TYPE__ = c_longlong;
pub const __INT64_FMTd__ = "lld";
pub const __INT64_FMTi__ = "lli";
pub const __INT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `LL`"); // <builtin>:191:9
pub const __INT64_C = __helpers.LL_SUFFIX;
pub const __UINT8_TYPE__ = u8;
pub const __UINT8_FMTo__ = "hho";
pub const __UINT8_FMTu__ = "hhu";
pub const __UINT8_FMTx__ = "hhx";
pub const __UINT8_FMTX__ = "hhX";
pub const __UINT8_C_SUFFIX__ = "";
pub inline fn __UINT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __UINT8_MAX__ = @as(c_int, 255);
pub const __INT8_MAX__ = @as(c_int, 127);
pub const __UINT16_TYPE__ = c_ushort;
pub const __UINT16_FMTo__ = "ho";
pub const __UINT16_FMTu__ = "hu";
pub const __UINT16_FMTx__ = "hx";
pub const __UINT16_FMTX__ = "hX";
pub const __UINT16_C_SUFFIX__ = "";
pub inline fn __UINT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const __UINT16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const __INT16_MAX__ = @as(c_int, 32767);
pub const __UINT32_TYPE__ = c_uint;
pub const __UINT32_FMTo__ = "o";
pub const __UINT32_FMTu__ = "u";
pub const __UINT32_FMTx__ = "x";
pub const __UINT32_FMTX__ = "X";
pub const __UINT32_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `U`"); // <builtin>:216:9
pub const __UINT32_C = __helpers.U_SUFFIX;
pub const __UINT32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const __INT32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __UINT64_TYPE__ = c_ulonglong;
pub const __UINT64_FMTo__ = "llo";
pub const __UINT64_FMTu__ = "llu";
pub const __UINT64_FMTx__ = "llx";
pub const __UINT64_FMTX__ = "llX";
pub const __UINT64_C_SUFFIX__ = @compileError("unable to translate macro: undefined identifier `ULL`"); // <builtin>:225:9
pub const __UINT64_C = __helpers.ULL_SUFFIX;
pub const __UINT64_MAX__ = @as(c_ulonglong, 18446744073709551615);
pub const __INT64_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __INT_LEAST8_TYPE__ = i8;
pub const __INT_LEAST8_MAX__ = @as(c_int, 127);
pub const __INT_LEAST8_WIDTH__ = @as(c_int, 8);
pub const INT_LEAST8_FMTd__ = "hhd";
pub const INT_LEAST8_FMTi__ = "hhi";
pub const __UINT_LEAST8_TYPE__ = u8;
pub const __UINT_LEAST8_MAX__ = @as(c_int, 255);
pub const UINT_LEAST8_FMTo__ = "hho";
pub const UINT_LEAST8_FMTu__ = "hhu";
pub const UINT_LEAST8_FMTx__ = "hhx";
pub const UINT_LEAST8_FMTX__ = "hhX";
pub const __INT_FAST8_TYPE__ = i8;
pub const __INT_FAST8_MAX__ = @as(c_int, 127);
pub const __INT_FAST8_WIDTH__ = @as(c_int, 8);
pub const INT_FAST8_FMTd__ = "hhd";
pub const INT_FAST8_FMTi__ = "hhi";
pub const __UINT_FAST8_TYPE__ = u8;
pub const __UINT_FAST8_MAX__ = @as(c_int, 255);
pub const UINT_FAST8_FMTo__ = "hho";
pub const UINT_FAST8_FMTu__ = "hhu";
pub const UINT_FAST8_FMTx__ = "hhx";
pub const UINT_FAST8_FMTX__ = "hhX";
pub const __INT_LEAST16_TYPE__ = c_short;
pub const __INT_LEAST16_MAX__ = @as(c_int, 32767);
pub const __INT_LEAST16_WIDTH__ = @as(c_int, 16);
pub const INT_LEAST16_FMTd__ = "hd";
pub const INT_LEAST16_FMTi__ = "hi";
pub const __UINT_LEAST16_TYPE__ = c_ushort;
pub const __UINT_LEAST16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_LEAST16_FMTo__ = "ho";
pub const UINT_LEAST16_FMTu__ = "hu";
pub const UINT_LEAST16_FMTx__ = "hx";
pub const UINT_LEAST16_FMTX__ = "hX";
pub const __INT_FAST16_TYPE__ = c_short;
pub const __INT_FAST16_MAX__ = @as(c_int, 32767);
pub const __INT_FAST16_WIDTH__ = @as(c_int, 16);
pub const INT_FAST16_FMTd__ = "hd";
pub const INT_FAST16_FMTi__ = "hi";
pub const __UINT_FAST16_TYPE__ = c_ushort;
pub const __UINT_FAST16_MAX__ = __helpers.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_FAST16_FMTo__ = "ho";
pub const UINT_FAST16_FMTu__ = "hu";
pub const UINT_FAST16_FMTx__ = "hx";
pub const UINT_FAST16_FMTX__ = "hX";
pub const __INT_LEAST32_TYPE__ = c_int;
pub const __INT_LEAST32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_LEAST32_WIDTH__ = @as(c_int, 32);
pub const INT_LEAST32_FMTd__ = "d";
pub const INT_LEAST32_FMTi__ = "i";
pub const __UINT_LEAST32_TYPE__ = c_uint;
pub const __UINT_LEAST32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_LEAST32_FMTo__ = "o";
pub const UINT_LEAST32_FMTu__ = "u";
pub const UINT_LEAST32_FMTx__ = "x";
pub const UINT_LEAST32_FMTX__ = "X";
pub const __INT_FAST32_TYPE__ = c_int;
pub const __INT_FAST32_MAX__ = __helpers.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const __INT_FAST32_WIDTH__ = @as(c_int, 32);
pub const INT_FAST32_FMTd__ = "d";
pub const INT_FAST32_FMTi__ = "i";
pub const __UINT_FAST32_TYPE__ = c_uint;
pub const __UINT_FAST32_MAX__ = __helpers.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_FAST32_FMTo__ = "o";
pub const UINT_FAST32_FMTu__ = "u";
pub const UINT_FAST32_FMTx__ = "x";
pub const UINT_FAST32_FMTX__ = "X";
pub const __INT_LEAST64_TYPE__ = c_longlong;
pub const __INT_LEAST64_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __INT_LEAST64_WIDTH__ = @as(c_int, 64);
pub const INT_LEAST64_FMTd__ = "lld";
pub const INT_LEAST64_FMTi__ = "lli";
pub const __UINT_LEAST64_TYPE__ = c_ulonglong;
pub const __UINT_LEAST64_MAX__ = @as(c_ulonglong, 18446744073709551615);
pub const UINT_LEAST64_FMTo__ = "llo";
pub const UINT_LEAST64_FMTu__ = "llu";
pub const UINT_LEAST64_FMTx__ = "llx";
pub const UINT_LEAST64_FMTX__ = "llX";
pub const __INT_FAST64_TYPE__ = c_longlong;
pub const __INT_FAST64_MAX__ = @as(c_longlong, 9223372036854775807);
pub const __INT_FAST64_WIDTH__ = @as(c_int, 64);
pub const INT_FAST64_FMTd__ = "lld";
pub const INT_FAST64_FMTi__ = "lli";
pub const __UINT_FAST64_TYPE__ = c_ulonglong;
pub const __UINT_FAST64_MAX__ = @as(c_ulonglong, 18446744073709551615);
pub const UINT_FAST64_FMTo__ = "llo";
pub const UINT_FAST64_FMTu__ = "llu";
pub const UINT_FAST64_FMTx__ = "llx";
pub const UINT_FAST64_FMTX__ = "llX";
pub const __FLT16_DENORM_MIN__ = @as(f16, 5.9604644775390625e-8);
pub const __FLT16_HAS_DENORM__ = "";
pub const __FLT16_DIG__ = @as(c_int, 3);
pub const __FLT16_DECIMAL_DIG__ = @as(c_int, 5);
pub const __FLT16_EPSILON__ = @as(f16, 9.765625e-4);
pub const __FLT16_HAS_INFINITY__ = "";
pub const __FLT16_HAS_QUIET_NAN__ = "";
pub const __FLT16_MANT_DIG__ = @as(c_int, 11);
pub const __FLT16_MAX_10_EXP__ = @as(c_int, 4);
pub const __FLT16_MAX_EXP__ = @as(c_int, 16);
pub const __FLT16_MAX__ = @as(f16, 6.5504e+4);
pub const __FLT16_MIN_10_EXP__ = -@as(c_int, 4);
pub const __FLT16_MIN_EXP__ = -@as(c_int, 13);
pub const __FLT16_MIN__ = @as(f16, 6.103515625e-5);
pub const __FLT_DENORM_MIN__ = @as(f32, 1.40129846e-45);
pub const __FLT_HAS_DENORM__ = "";
pub const __FLT_DIG__ = @as(c_int, 6);
pub const __FLT_DECIMAL_DIG__ = @as(c_int, 9);
pub const __FLT_EPSILON__ = @as(f32, 1.19209290e-7);
pub const __FLT_HAS_INFINITY__ = "";
pub const __FLT_HAS_QUIET_NAN__ = "";
pub const __FLT_MANT_DIG__ = @as(c_int, 24);
pub const __FLT_MAX_10_EXP__ = @as(c_int, 38);
pub const __FLT_MAX_EXP__ = @as(c_int, 128);
pub const __FLT_MAX__ = @as(f32, 3.40282347e+38);
pub const __FLT_MIN_10_EXP__ = -@as(c_int, 37);
pub const __FLT_MIN_EXP__ = -@as(c_int, 125);
pub const __FLT_MIN__ = @as(f32, 1.17549435e-38);
pub const __DBL_DENORM_MIN__ = @as(f64, 4.9406564584124654e-324);
pub const __DBL_HAS_DENORM__ = "";
pub const __DBL_DIG__ = @as(c_int, 15);
pub const __DBL_DECIMAL_DIG__ = @as(c_int, 17);
pub const __DBL_EPSILON__ = @as(f64, 2.2204460492503131e-16);
pub const __DBL_HAS_INFINITY__ = "";
pub const __DBL_HAS_QUIET_NAN__ = "";
pub const __DBL_MANT_DIG__ = @as(c_int, 53);
pub const __DBL_MAX_10_EXP__ = @as(c_int, 308);
pub const __DBL_MAX_EXP__ = @as(c_int, 1024);
pub const __DBL_MAX__ = @as(f64, 1.7976931348623157e+308);
pub const __DBL_MIN_10_EXP__ = -@as(c_int, 307);
pub const __DBL_MIN_EXP__ = -@as(c_int, 1021);
pub const __DBL_MIN__ = @as(f64, 2.2250738585072014e-308);
pub const __LDBL_DENORM_MIN__ = @as(c_longdouble, 3.64519953188247460253e-4951);
pub const __LDBL_HAS_DENORM__ = "";
pub const __LDBL_DIG__ = @as(c_int, 18);
pub const __LDBL_DECIMAL_DIG__ = @as(c_int, 21);
pub const __LDBL_EPSILON__ = @as(c_longdouble, 1.08420217248550443401e-19);
pub const __LDBL_HAS_INFINITY__ = "";
pub const __LDBL_HAS_QUIET_NAN__ = "";
pub const __LDBL_MANT_DIG__ = @as(c_int, 64);
pub const __LDBL_MAX_10_EXP__ = @as(c_int, 4932);
pub const __LDBL_MAX_EXP__ = @as(c_int, 16384);
pub const __LDBL_MAX__ = @as(c_longdouble, 1.18973149535723176502e+4932);
pub const __LDBL_MIN_10_EXP__ = -@as(c_int, 4931);
pub const __LDBL_MIN_EXP__ = -@as(c_int, 16381);
pub const __LDBL_MIN__ = @as(c_longdouble, 3.36210314311209350626e-4932);
pub const __FLT_EVAL_METHOD__ = @as(c_int, 0);
pub const __FLT_RADIX__ = @as(c_int, 2);
pub const __DECIMAL_DIG__ = __LDBL_DECIMAL_DIG__;
pub const __pic__ = @as(c_int, 2);
pub const __PIC__ = @as(c_int, 2);
pub const CGLTF_H_INCLUDED__ = "";
pub const __STDC_VERSION_STDDEF_H__ = @as(c_long, 202311);
pub const NULL = __helpers.cast(?*anyopaque, @as(c_int, 0));
pub const offsetof = @compileError("unable to translate macro: undefined identifier `__builtin_offsetof`"); // C:\Users\it\.zvm\0.16.0\lib\compiler\aro\include\stddef.h:18:9
pub const __CLANG_STDINT_H = "";
pub const __int_least64_t = i64;
pub const __uint_least64_t = u64;
pub const __uint32_t_defined = "";
pub const __int_least32_t = i32;
pub const __uint_least32_t = u32;
pub const __int_least16_t = i16;
pub const __uint_least16_t = u16;
pub const __int_least8_t = i8;
pub const __uint_least8_t = u8;
pub const __int8_t_defined = "";
pub const __stdint_join3 = @compileError("unable to translate C expr: unexpected token '##'"); // C:\Users\it\.zvm\0.16.0\lib\include\stdint.h:291:9
pub const __intptr_t_defined = "";
pub const _INTPTR_T = "";
pub const _UINTPTR_T = "";
pub inline fn INT64_C(v: anytype) @TypeOf(__INT64_C(v)) {
    _ = &v;
    return __INT64_C(v);
}
pub inline fn UINT64_C(v: anytype) @TypeOf(__UINT64_C(v)) {
    _ = &v;
    return __UINT64_C(v);
}
pub inline fn INT32_C(v: anytype) @TypeOf(__INT32_C(v)) {
    _ = &v;
    return __INT32_C(v);
}
pub inline fn UINT32_C(v: anytype) @TypeOf(__UINT32_C(v)) {
    _ = &v;
    return __UINT32_C(v);
}
pub inline fn INT16_C(v: anytype) @TypeOf(__INT16_C(v)) {
    _ = &v;
    return __INT16_C(v);
}
pub inline fn UINT16_C(v: anytype) @TypeOf(__UINT16_C(v)) {
    _ = &v;
    return __UINT16_C(v);
}
pub inline fn INT8_C(v: anytype) @TypeOf(__INT8_C(v)) {
    _ = &v;
    return __INT8_C(v);
}
pub inline fn UINT8_C(v: anytype) @TypeOf(__UINT8_C(v)) {
    _ = &v;
    return __UINT8_C(v);
}
pub const INT64_MAX = INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const INT64_MIN = -INT64_C(__helpers.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const UINT64_MAX = UINT64_C(__helpers.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const __INT_LEAST64_MIN = INT64_MIN;
pub const __INT_LEAST64_MAX = INT64_MAX;
pub const __UINT_LEAST64_MAX = UINT64_MAX;
pub const INT_LEAST64_MIN = __INT_LEAST64_MIN;
pub const INT_LEAST64_MAX = __INT_LEAST64_MAX;
pub const UINT_LEAST64_MAX = __UINT_LEAST64_MAX;
pub const INT_FAST64_MIN = __INT_LEAST64_MIN;
pub const INT_FAST64_MAX = __INT_LEAST64_MAX;
pub const UINT_FAST64_MAX = __UINT_LEAST64_MAX;
pub const INT32_MAX = INT32_C(__helpers.promoteIntLiteral(c_int, 2147483647, .decimal));
pub const INT32_MIN = -INT32_C(__helpers.promoteIntLiteral(c_int, 2147483647, .decimal)) - @as(c_int, 1);
pub const UINT32_MAX = UINT32_C(__helpers.promoteIntLiteral(c_int, 4294967295, .decimal));
pub const __INT_LEAST32_MIN = INT32_MIN;
pub const __INT_LEAST32_MAX = INT32_MAX;
pub const __UINT_LEAST32_MAX = UINT32_MAX;
pub const INT_LEAST32_MIN = __INT_LEAST32_MIN;
pub const INT_LEAST32_MAX = __INT_LEAST32_MAX;
pub const UINT_LEAST32_MAX = __UINT_LEAST32_MAX;
pub const INT_FAST32_MIN = __INT_LEAST32_MIN;
pub const INT_FAST32_MAX = __INT_LEAST32_MAX;
pub const UINT_FAST32_MAX = __UINT_LEAST32_MAX;
pub const INT16_MAX = INT16_C(@as(c_int, 32767));
pub const INT16_MIN = -INT16_C(@as(c_int, 32767)) - @as(c_int, 1);
pub const UINT16_MAX = UINT16_C(__helpers.promoteIntLiteral(c_int, 65535, .decimal));
pub const __INT_LEAST16_MIN = INT16_MIN;
pub const __INT_LEAST16_MAX = INT16_MAX;
pub const __UINT_LEAST16_MAX = UINT16_MAX;
pub const INT_LEAST16_MIN = __INT_LEAST16_MIN;
pub const INT_LEAST16_MAX = __INT_LEAST16_MAX;
pub const UINT_LEAST16_MAX = __UINT_LEAST16_MAX;
pub const INT_FAST16_MIN = __INT_LEAST16_MIN;
pub const INT_FAST16_MAX = __INT_LEAST16_MAX;
pub const UINT_FAST16_MAX = __UINT_LEAST16_MAX;
pub const INT8_MAX = INT8_C(@as(c_int, 127));
pub const INT8_MIN = -INT8_C(@as(c_int, 127)) - @as(c_int, 1);
pub const UINT8_MAX = UINT8_C(@as(c_int, 255));
pub const __INT_LEAST8_MIN = INT8_MIN;
pub const __INT_LEAST8_MAX = INT8_MAX;
pub const __UINT_LEAST8_MAX = UINT8_MAX;
pub const INT_LEAST8_MIN = __INT_LEAST8_MIN;
pub const INT_LEAST8_MAX = __INT_LEAST8_MAX;
pub const UINT_LEAST8_MAX = __UINT_LEAST8_MAX;
pub const INT_FAST8_MIN = __INT_LEAST8_MIN;
pub const INT_FAST8_MAX = __INT_LEAST8_MAX;
pub const UINT_FAST8_MAX = __UINT_LEAST8_MAX;
pub const __INTN_MIN = @compileError("unable to translate macro: undefined identifier `INT`"); // C:\Users\it\.zvm\0.16.0\lib\include\stdint.h:764:10
pub const __INTN_MAX = @compileError("unable to translate macro: undefined identifier `INT`"); // C:\Users\it\.zvm\0.16.0\lib\include\stdint.h:765:10
pub const __UINTN_MAX = @compileError("unable to translate macro: undefined identifier `UINT`"); // C:\Users\it\.zvm\0.16.0\lib\include\stdint.h:766:9
pub const __INTN_C = @compileError("unable to translate macro: undefined identifier `INT`"); // C:\Users\it\.zvm\0.16.0\lib\include\stdint.h:767:10
pub const __UINTN_C = @compileError("unable to translate macro: undefined identifier `UINT`"); // C:\Users\it\.zvm\0.16.0\lib\include\stdint.h:768:9
pub const INTPTR_MIN = -__INTPTR_MAX__ - @as(c_int, 1);
pub const INTPTR_MAX = __INTPTR_MAX__;
pub const UINTPTR_MAX = __UINTPTR_MAX__;
pub const PTRDIFF_MIN = -__PTRDIFF_MAX__ - @as(c_int, 1);
pub const PTRDIFF_MAX = __PTRDIFF_MAX__;
pub const SIZE_MAX = __SIZE_MAX__;
pub const INTMAX_MIN = -__INTMAX_MAX__ - @as(c_int, 1);
pub const INTMAX_MAX = __INTMAX_MAX__;
pub const UINTMAX_MAX = __UINTMAX_MAX__;
pub const SIG_ATOMIC_MIN = __INTN_MIN(__SIG_ATOMIC_WIDTH__);
pub const SIG_ATOMIC_MAX = __INTN_MAX(__SIG_ATOMIC_WIDTH__);
pub const WINT_MIN = __UINTN_C(__WINT_WIDTH__, @as(c_int, 0));
pub const WINT_MAX = __UINTN_MAX(__WINT_WIDTH__);
pub const WCHAR_MAX = __WCHAR_MAX__;
pub const WCHAR_MIN = __UINTN_C(__WCHAR_WIDTH__, @as(c_int, 0));
pub inline fn INTMAX_C(v: anytype) @TypeOf(__INTMAX_C(v)) {
    _ = &v;
    return __INTMAX_C(v);
}
pub inline fn UINTMAX_C(v: anytype) @TypeOf(__UINTMAX_C(v)) {
    _ = &v;
    return __UINTMAX_C(v);
}
