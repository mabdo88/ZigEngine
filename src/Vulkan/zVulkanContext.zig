const std = @import("std");
const builtin = @import("builtin");
pub const vma = @import("vmaimport");
pub const zvk = @import("../glfw/zvkgl.zig");

pub var frame: f32 = 0.0;
pub const enable_validation = builtin.mode == .Debug;
pub const max_frames_in_flight = 2;
pub var extensions: [3][*c]const u8 = undefined;
pub var imageIndex: u32 = 0;
pub var frameIndex: u32 = 0;
pub var queueFamilyIndex: u32 = 0;
pub const validationLayers = [_][*c]const u8{"VK_LAYER_KHRONOS_validation"};
pub var m_window: zvk.VkWindow = undefined;
pub var m_instance: zvk.VkInstance = null;
pub var m_Device: zvk.VkDevice = null;
pub var queue: zvk.VkQueue = null;
pub var m_physicalDevice: zvk.VkPhysicalDevice = null;
pub var m_surface: zvk.VkSurfaceKHR = null;
pub var m_debugMessenger: zvk.VkDebugUtilsMessengerEXT = null;
pub var vkCreateDebugUtilsMessengerEXT: zvk.PFN_vkCreateDebugUtilsMessengerEXT = null;
pub var vkDestroyDebugUtilsMessengerEXT: zvk.PFN_vkDestroyDebugUtilsMessengerEXT = null;
pub var swapChain: zvk.VkSwapchainKHR = null;
pub var swapChainExtent: zvk.VkExtent2D = undefined;
pub var swapChainImages: []zvk.VkImage = undefined;
pub var swapChainImageViews: []zvk.VkImageView = undefined;
pub var commandPool: zvk.VkCommandPool = null;
pub var pipeline: zvk.VkPipeline = null;
pub var pipelineLayout: zvk.VkPipelineLayout = null;
pub var colorFormat: zvk.VkFormat = zvk.VK_FORMAT_B8G8R8A8_SRGB;
pub var colorSpace: zvk.VkColorSpaceKHR = zvk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
pub var depthFormat: zvk.VkFormat = zvk.VK_FORMAT_UNDEFINED;
pub var depthImage: zvk.VkImage = null;
pub var depthImageView: zvk.VkImageView = null;
pub var updateSwapchain: bool = false;
pub var depthImageAllocation: vma.VmaAllocation = null;
pub var vmaAllocator: vma.VmaAllocator = null;
pub var zallocator: std.mem.Allocator = undefined;
pub var commandBuffers: [max_frames_in_flight]zvk.VkCommandBuffer = undefined;
pub var fences: [max_frames_in_flight]zvk.VkFence = undefined;
pub var imageAcquiredSemaphores: [max_frames_in_flight]zvk.VkSemaphore = undefined;
pub var renderCompleteSemaphores: []zvk.VkSemaphore = undefined;
pub var vBufferAllocation: vma.VmaAllocation = null;
pub var vBuffer: zvk.VkBuffer = null;
pub var bindlessDescriptorSetLayout: zvk.VkDescriptorSetLayout = null;
pub var bindlessDescriptorSet: zvk.VkDescriptorSet = null;
pub var uboDescriptorSetLayout: zvk.VkDescriptorSetLayout = null;
pub var uboDescriptorSets: [max_frames_in_flight]zvk.VkDescriptorSet = undefined;
pub var bindlessSampler: zvk.VkSampler = null;
pub var descriptorPool: zvk.VkDescriptorPool = null;
pub const TextureHandle: type = u32;
pub const MAX_TEXTURES: u32 = 1024;
pub const ShaderData = struct {
    projection: [4][4]f32,
    view: [4][4]f32,
    model: [4][4]f32,
    //lightPos: @Vector(4, f32) = @Vector(4, f32){ 0.0, -10.0, 10.0, 0.0 },
    //selected: u32 = 1,
};
pub const ShaderDataBuffer = struct {
    buffer: zvk.VkBuffer = null,
    allocation: vma.VmaAllocation = null,
    allocInfo: vma.VmaAllocationInfo = undefined,
    deviceAddress: zvk.VkDeviceAddress = 0,
    //image: zvk.VkImage = null,
};
pub var shaderDataBuffers: [max_frames_in_flight]ShaderDataBuffer = undefined;
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
pub var textureSlots: [MAX_TEXTURES]TextureSlot = undefined;
pub var textureCount: u32 = 0;
