const std = @import("std");
const builtin = @import("builtin");
pub const vma = @import("vmaimport");
pub const zvk = @import("../platform/zvkgl.zig");
pub const win = @import("../platform/window.zig");

pub const enable_validation = builtin.mode == .Debug;
pub const max_frames_in_flight = 2;
pub const validationLayers = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
pub const TextureHandle: type = u32;
pub const MAX_TEXTURES: u32 = 1024;
pub const MaterialHandle: type = u32;
pub const MAX_MATERIALS: u32 = 1024;

pub const default_window_width: u16 = 800;
pub const default_window_height: u16 = 600;

pub const SHADOW_MAP_SIZE: u32 = 2048;
pub const SHADOW_MAP_FORMAT: zvk.VkFormat = zvk.VK_FORMAT_D32_SFLOAT;

pub const MAX_DEBUG_VERTICES: u32 = 65536;

/// Per-frame-in-flight region of the skin matrix buffer. Sized generously
/// for a handful of animated humanoid-scale skeletons (~20-128 joints each)
/// per frame; bump if a scene needs more animated entities at once.
pub const SKIN_MATRICES_PER_FRAME: u32 = 4096;
/// Relative offset within a frame's region that's always written as
/// identity each frame — unskinned draws point their push constant here
/// (frameIndex * SKIN_MATRICES_PER_FRAME + SKIN_IDENTITY_SLOT) so the same
/// shader path works for skinned and unskinned vertices alike.
pub const SKIN_IDENTITY_SLOT: u32 = 0;

pub const ShaderData = struct {
    projection: [4][4]f32,
    view: [4][4]f32,
    model: [4][4]f32,
};
pub const ShaderDataBuffer = struct {
    buffer: zvk.VkBuffer = null,
    allocation: vma.VmaAllocation = null,
    allocInfo: vma.VmaAllocationInfo = undefined,
    deviceAddress: zvk.VkDeviceAddress = 0,
};
/// Must stay byte-identical to engine.ecs.components.Vertex — renderSystem.zig
/// uploads that type's raw bytes straight into a buffer using this layout.
pub const Vertex = struct {
    pos: @Vector(3, f32),
    normal: @Vector(3, f32),
    uv: @Vector(2, f32),
    joints: @Vector(4, u32) = .{ 0, 0, 0, 0 },
    weights: @Vector(4, f32) = .{ 1, 0, 0, 0 },
};
pub const PushConstants = struct {
    model: [4][4]f32,
    materialIndex: u32,
    /// Absolute index into the skin matrix buffer for this draw's joint 0
    /// (frameIndex * SKIN_MATRICES_PER_FRAME + a relative offset); the
    /// shader adds each vertex's `joints` values to it. Always set
    /// explicitly per draw in renderSystem.zig — the 0 default here is only
    /// ever overwritten, never relied on (frame context isn't known at
    /// struct-definition time).
    skinOffset: u32 = 0,
    pad: [2]u32 = .{ 0, 0 },
};
pub const ShadowPushConstants = struct {
    mvp: [4][4]f32,
};
pub const FrameUBO = struct {
    projection: [4][4]f32,
    view: [4][4]f32,
    light_view_proj: [4][4]f32,
    light_dir: [4]f32, // xyz = direction, w unused
    light_color: [4]f32, // xyz = color, w = ambient
    camera_pos: [4]f32, // xyz = world-space camera position, for specular
};
pub const DebugVertex = struct {
    pos: @Vector(3, f32),
    color: @Vector(3, f32),
};
pub const MAX_UI_VERTICES: u32 = 65536;
pub const UIVertex = struct {
    pos: @Vector(2, f32),
    uv: @Vector(2, f32),
    color: @Vector(4, f32),
};
pub const UIProjUBO = struct {
    projection: [4][4]f32,
};
pub const TextureSlot = struct {
    image: zvk.VkImage = null,
    view: zvk.VkImageView = null,
    allocation: vma.VmaAllocation = null,
};

/// Mirrors the `MaterialData` struct in shader.slang — keep field order and
/// types in sync (std430-ish: no implicit padding needed since it's all
/// 4-byte scalars already aligned to 4).
pub const MaterialGpuData = extern struct {
    metallic: f32 = 0.0,
    roughness: f32 = 0.5,
    albedo_texture_index: u32 = 0,
    _pad: u32 = 0,
};

pub const VulkanContext = struct {
    frame: f32 = 0.0,
    extensions: []const [*c]const u8 = undefined,
    imageIndex: u32 = 0,
    frameIndex: u32 = 0,
    queueFamilyIndex: u32 = 0,
    m_window: win.Window = undefined,
    m_instance: zvk.VkInstance = null,
    m_Device: zvk.VkDevice = null,
    queue: zvk.VkQueue = null,
    m_physicalDevice: zvk.VkPhysicalDevice = null,
    m_surface: zvk.VkSurfaceKHR = null,
    m_debugMessenger: zvk.VkDebugUtilsMessengerEXT = null,
    vkCreateDebugUtilsMessengerEXT: zvk.PFN_vkCreateDebugUtilsMessengerEXT = null,
    vkDestroyDebugUtilsMessengerEXT: zvk.PFN_vkDestroyDebugUtilsMessengerEXT = null,
    swapChain: zvk.VkSwapchainKHR = null,
    swapChainExtent: zvk.VkExtent2D = undefined,
    swapChainImages: []zvk.VkImage = undefined,
    swapChainImageViews: []zvk.VkImageView = undefined,
    commandPool: zvk.VkCommandPool = null,
    pipeline: zvk.VkPipeline = null,
    pipelineLayout: zvk.VkPipelineLayout = null,
    colorFormat: zvk.VkFormat = zvk.VK_FORMAT_B8G8R8A8_SRGB,
    colorSpace: zvk.VkColorSpaceKHR = zvk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
    depthFormat: zvk.VkFormat = zvk.VK_FORMAT_UNDEFINED,
    depthImage: zvk.VkImage = null,
    depthImageView: zvk.VkImageView = null,
    updateSwapchain: bool = false,
    depthImageAllocation: vma.VmaAllocation = null,
    vmaAllocator: vma.VmaAllocator = null,
    zallocator: std.mem.Allocator = undefined,
    commandBuffers: [max_frames_in_flight]zvk.VkCommandBuffer = undefined,
    fences: [max_frames_in_flight]zvk.VkFence = undefined,
    imageAcquiredSemaphores: [max_frames_in_flight]zvk.VkSemaphore = undefined,
    renderCompleteSemaphores: []zvk.VkSemaphore = undefined,
    vBufferAllocation: vma.VmaAllocation = null,
    vBuffer: zvk.VkBuffer = null,
    bindlessDescriptorSetLayout: zvk.VkDescriptorSetLayout = null,
    bindlessDescriptorSet: zvk.VkDescriptorSet = null,
    uboDescriptorSetLayout: zvk.VkDescriptorSetLayout = null,
    uboDescriptorSets: [max_frames_in_flight]zvk.VkDescriptorSet = undefined,
    bindlessSampler: zvk.VkSampler = null,
    descriptorPool: zvk.VkDescriptorPool = null,
    shaderDataBuffers: [max_frames_in_flight]ShaderDataBuffer = undefined,
    textureSlots: [MAX_TEXTURES]TextureSlot = undefined,
    textureCount: u32 = 0,

    materialBuffer: zvk.VkBuffer = null,
    materialBufferAllocation: vma.VmaAllocation = null,
    materialBufferMapped: ?[*]MaterialGpuData = null,
    materialCount: u32 = 0,

    shadowImage: zvk.VkImage = null,
    shadowImageView: zvk.VkImageView = null,
    shadowImageAllocation: vma.VmaAllocation = null,
    shadowImageLayout: zvk.VkImageLayout = zvk.VK_IMAGE_LAYOUT_UNDEFINED,
    shadowSampler: zvk.VkSampler = null,
    shadowPipeline: zvk.VkPipeline = null,
    shadowPipelineLayout: zvk.VkPipelineLayout = null,

    debugPipeline: zvk.VkPipeline = null,
    debugPipelineLayout: zvk.VkPipelineLayout = null,
    debugVertexBuffers: [max_frames_in_flight]ShaderDataBuffer = undefined,

    uiPipeline: zvk.VkPipeline = null,
    uiPipelineLayout: zvk.VkPipelineLayout = null,
    uiProjDescriptorSetLayout: zvk.VkDescriptorSetLayout = null,
    uiProjDescriptorSets: [max_frames_in_flight]zvk.VkDescriptorSet = undefined,
    uiProjBuffers: [max_frames_in_flight]ShaderDataBuffer = undefined,
    uiVertexBuffers: [max_frames_in_flight]ShaderDataBuffer = undefined,

    // Single buffer split into max_frames_in_flight regions of
    // SKIN_MATRICES_PER_FRAME mat4s each, rather than one buffer per frame —
    // lets the bindless descriptor binding stay static (whole-buffer range)
    // since draws address it via an already frame-relative push-constant
    // offset instead of needing the binding repointed every frame.
    skinMatrixBuffer: zvk.VkBuffer = null,
    skinMatrixBufferAllocation: vma.VmaAllocation = null,
    skinMatrixBufferMapped: ?[*][4][4]f32 = null,

    vsync: bool = true,
};

pub var ctx: VulkanContext = .{};
