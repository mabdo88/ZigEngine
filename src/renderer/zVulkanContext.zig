const std = @import("std");
const builtin = @import("builtin");
pub const vma = @import("vmaimport");
pub const zvk = @import("../platform/zvkgl.zig");

pub const enable_validation = builtin.mode == .Debug;
pub const max_frames_in_flight = 2;
pub const validationLayers = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
pub const TextureHandle: type = u32;
pub const MAX_TEXTURES: u32 = 1024;

/// Single source of truth for the initial window size. Used as the default
/// `WindowComponent` size and as the swapchain fallback when the surface does
/// not dictate an extent.
pub const default_window_width: u16 = 800;
pub const default_window_height: u16 = 600;

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
pub const Vertex = struct {
    pos: @Vector(3, f32),
    normal: @Vector(3, f32),
    uv: @Vector(2, f32),
};
pub const PushConstants = struct {
    model: [4][4]f32,
    textureIndex: u32,
    pad: [3]u32 = .{ 0, 0, 0 },
};
pub const FrameUBO = struct {
    projection: [4][4]f32,
    view: [4][4]f32,
};
pub const TextureSlot = struct {
    image: zvk.VkImage = null,
    view: zvk.VkImageView = null,
    allocation: vma.VmaAllocation = null,
};

/// All mutable Vulkan state grouped into a single context object.
/// A single instance (`ctx`) is shared today; passing `*VulkanContext` to the
/// renderer functions later turns this into full dependency injection.
pub const VulkanContext = struct {
    frame: f32 = 0.0,
    extensions: [3][*c]const u8 = undefined,
    imageIndex: u32 = 0,
    frameIndex: u32 = 0,
    queueFamilyIndex: u32 = 0,
    m_window: zvk.VkWindow = undefined,
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
};

/// Shared Vulkan context instance.
pub var ctx: VulkanContext = .{};
