const std = @import("std");
const builtin = @import("builtin");
const rgstry = @import("../ecs/Storage/registry.zig");
const rs = @import("../ecs/System/renderSystem.zig").RenderSystem;
const cs = @import("../ecs/System/cameraSystem.zig");
const zvkw = @import("zVulkanContext.zig");

pub var renderSystem: rs = undefined;
pub var registry: *rgstry.Registry = undefined;

pub fn init(zig_allocator: std.mem.Allocator, title: ?[:0]const u8, WWidth: u16, WHeight: u16, reg: *rgstry.Registry) !void {
    zvkw.ctx.zallocator = zig_allocator;
    registry = reg;
    const windowCI = zvkw.zvk.VkWindowCreateInfo{
        .title = title.?,
        .width = WWidth,
        .height = WHeight,
        .resizable = false,
    };
    try zvkw.zvk.vkCreateWindow(windowCI, &zvkw.ctx.m_window);
    _ = zvkw.zvk.vkGetRequiredInstanceExtensions(&zvkw.ctx.extensions);

    const appCI = zvkw.zvk.VkApplicationInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "ECS Zig Engine",
        .applicationVersion = zvkw.zvk.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "ZAG Engine",
        .engineVersion = zvkw.zvk.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = zvkw.zvk.VK_API_VERSION_1_3,
    };
    const instanceCI = zvkw.zvk.VkInstanceCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &appCI,
        .enabledLayerCount = if (zvkw.enable_validation) 1 else 0,
        .ppEnabledLayerNames = if (zvkw.enable_validation) &zvkw.validationLayers else null,
        .enabledExtensionCount = @intCast(zvkw.ctx.extensions.len),
        .ppEnabledExtensionNames = &zvkw.ctx.extensions,
    };

    const result = zvkw.zvk.vkCreateInstance(&instanceCI, null, &zvkw.ctx.m_instance);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateInstanceFailed;
    zvkw.ctx.m_surface = try zvkw.zvk.vkCreateWindowSurface(&zvkw.ctx.m_window, zvkw.ctx.m_instance);
    setupDebugMessenger();
    try pickPhysicalDevice();
    try createLogicalDevice();
    try createAllocator();
    try createSwapchain();
    try createDepthImage();
    try createSyncObjects();
    try createCommandPool();
    try createDescriptorSetLayout();
    try createPipeline();
    try createDescriptorPool();
    try createDescriptorSets();
    try createShaderDataBuffers();
    try createSampler();
    try createDefaultTexture();
    renderSystem = rs.init();
}

pub fn deinit() void {
    _ = zvkw.zvk.vkDeviceWaitIdle(zvkw.ctx.m_Device);
    // destroy textures
    for (0..zvkw.ctx.textureCount) |i| {
        zvkw.zvk.vkDestroyImageView(zvkw.ctx.m_Device, zvkw.ctx.textureSlots[i].view, null);
        zvkw.vma.vmaDestroyImage(zvkw.ctx.vmaAllocator, @ptrCast(zvkw.ctx.textureSlots[i].image), zvkw.ctx.textureSlots[i].allocation);
    }
    zvkw.zvk.vkDestroySampler(zvkw.ctx.m_Device, zvkw.ctx.bindlessSampler, null);
    zvkw.zvk.vkDestroyDescriptorPool(zvkw.ctx.m_Device, zvkw.ctx.descriptorPool, null);
    zvkw.zvk.vkDestroyDescriptorSetLayout(zvkw.ctx.m_Device, zvkw.ctx.uboDescriptorSetLayout, null);
    zvkw.zvk.vkDestroyDescriptorSetLayout(zvkw.ctx.m_Device, zvkw.ctx.bindlessDescriptorSetLayout, null);
    zvkw.zvk.vkDestroyPipeline(zvkw.ctx.m_Device, zvkw.ctx.pipeline, null);
    zvkw.zvk.vkDestroyPipelineLayout(zvkw.ctx.m_Device, zvkw.ctx.pipelineLayout, null);
    for (zvkw.ctx.swapChainImageViews) |view| {
        zvkw.zvk.vkDestroyImageView(zvkw.ctx.m_Device, view, null);
    }
    zvkw.ctx.zallocator.free(zvkw.ctx.swapChainImageViews);
    zvkw.ctx.zallocator.free(zvkw.ctx.swapChainImages);
    zvkw.zvk.vkDestroySwapchainKHR(zvkw.ctx.m_Device, zvkw.ctx.swapChain, null);
    zvkw.zvk.vkDestroyImageView(zvkw.ctx.m_Device, zvkw.ctx.depthImageView, null);
    zvkw.vma.vmaDestroyImage(zvkw.ctx.vmaAllocator, @ptrCast(zvkw.ctx.depthImage), zvkw.ctx.depthImageAllocation);
    zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(zvkw.ctx.vBuffer), zvkw.ctx.vBufferAllocation);
    for (0..zvkw.max_frames_in_flight) |i| {
        zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(zvkw.ctx.shaderDataBuffers[i].buffer), zvkw.ctx.shaderDataBuffers[i].allocation);
    }
    renderSystem.deinit();
    zvkw.vma.vmaDestroyAllocator(zvkw.ctx.vmaAllocator);
    zvkw.zvk.vkDestroyCommandPool(zvkw.ctx.m_Device, zvkw.ctx.commandPool, null);
    for (0..zvkw.max_frames_in_flight) |i| {
        zvkw.zvk.vkDestroyFence(zvkw.ctx.m_Device, zvkw.ctx.fences[i], null);
        zvkw.zvk.vkDestroySemaphore(zvkw.ctx.m_Device, zvkw.ctx.imageAcquiredSemaphores[i], null);
    }
    for (zvkw.ctx.renderCompleteSemaphores) |semaphore| {
        zvkw.zvk.vkDestroySemaphore(zvkw.ctx.m_Device, semaphore, null);
    }
    zvkw.ctx.zallocator.free(zvkw.ctx.renderCompleteSemaphores);

    zvkw.zvk.vkDestroyDevice(zvkw.ctx.m_Device, null);
    zvkw.zvk.vkDestroySurfaceKHR(zvkw.ctx.m_instance, zvkw.ctx.m_surface, null);
    zvkw.ctx.zallocator = undefined;
    if (zvkw.enable_validation) {
        if (zvkw.ctx.vkDestroyDebugUtilsMessengerEXT) |destroyFn| {
            destroyFn(zvkw.ctx.m_instance, zvkw.ctx.m_debugMessenger, null);
        }
    }
    zvkw.zvk.vkDestroyInstance(zvkw.ctx.m_instance, null);
    zvkw.zvk.vkDestroyWindow(&zvkw.ctx.m_window);
}

fn setupDebugMessenger() void {
    if (zvkw.enable_validation) {
        zvkw.ctx.vkCreateDebugUtilsMessengerEXT = @ptrCast(zvkw.zvk.vkGetInstanceProcAddr(zvkw.ctx.m_instance, "vkCreateDebugUtilsMessengerEXT"));
        zvkw.ctx.vkDestroyDebugUtilsMessengerEXT = @ptrCast(zvkw.zvk.vkGetInstanceProcAddr(zvkw.ctx.m_instance, "vkDestroyDebugUtilsMessengerEXT"));
        const debugCI = zvkw.zvk.VkDebugUtilsMessengerCreateInfoEXT{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
            .messageSeverity = zvkw.zvk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
                zvkw.zvk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
                zvkw.zvk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
            .messageType = zvkw.zvk.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
                zvkw.zvk.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                zvkw.zvk.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
            .pfnUserCallback = debugCallback,
        };
        const result = zvkw.ctx.vkCreateDebugUtilsMessengerEXT.?(zvkw.ctx.m_instance, &debugCI, null, &zvkw.ctx.m_debugMessenger);
        if (result != zvkw.zvk.VK_SUCCESS) {
            std.log.err("Failed to set up debug messenger", .{});
        } else {
            std.log.info("Debug messenger set up", .{});
        }
    }
}
fn pickPhysicalDevice() !void {
    var deviceCount: u32 = 0;
    _ = zvkw.zvk.vkEnumeratePhysicalDevices(zvkw.ctx.m_instance, &deviceCount, null);
    if (deviceCount == 0) return error.NoVulkanGPU;

    const devices = try zvkw.ctx.zallocator.alloc(zvkw.zvk.VkPhysicalDevice, deviceCount);
    defer zvkw.ctx.zallocator.free(devices);
    _ = zvkw.zvk.vkEnumeratePhysicalDevices(zvkw.ctx.m_instance, &deviceCount, devices.ptr);

    var bestScore: u32 = 0;
    var bestDevice: zvkw.zvk.VkPhysicalDevice = null;

    for (devices) |device| {
        // must support swapchain
        var extCount: u32 = 0;
        _ = zvkw.zvk.vkEnumerateDeviceExtensionProperties(device, null, &extCount, null);
        const exts = try zvkw.ctx.zallocator.alloc(zvkw.zvk.VkExtensionProperties, extCount);
        defer zvkw.ctx.zallocator.free(exts);
        _ = zvkw.zvk.vkEnumerateDeviceExtensionProperties(device, null, &extCount, exts.ptr);
        var hasSwapchain = false;
        for (exts) |ext| {
            if (std.mem.eql(u8, std.mem.sliceTo(&ext.extensionName, 0), "VK_KHR_swapchain")) {
                hasSwapchain = true;
                break;
            }
        }
        if (!hasSwapchain) {
            std.log.info("Device filtered: no swapchain support", .{});
            continue;
        }
        // must support presenting to our surface
        var presentSupport: zvkw.zvk.VkBool32 = zvkw.zvk.VK_FALSE;
        _ = zvkw.zvk.vkGetPhysicalDeviceSurfaceSupportKHR(device, 0, zvkw.ctx.m_surface, &presentSupport);
        if (presentSupport == zvkw.zvk.VK_FALSE) {
            std.log.info("Device filtered: no present support", .{});
            continue;
        }

        var props: zvkw.zvk.VkPhysicalDeviceProperties = undefined;
        zvkw.zvk.vkGetPhysicalDeviceProperties(device, &props);

        var score: u32 = 0;
        score += switch (props.deviceType) {
            zvkw.zvk.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU => 10000,
            zvkw.zvk.VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU => 10,
            zvkw.zvk.VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU => 1,
            else => 1,
        };
        score += @min(props.limits.maxImageDimension2D, 500);

        var features: zvkw.zvk.VkPhysicalDeviceFeatures = undefined;
        zvkw.zvk.vkGetPhysicalDeviceFeatures(device, &features);
        if (features.geometryShader == zvkw.zvk.VK_TRUE) score += 50;
        if (features.samplerAnisotropy == zvkw.zvk.VK_TRUE) score += 50;

        std.log.info("Device: {s} | type: {} | score: {}", .{ props.deviceName, props.deviceType, score });

        if (score > bestScore) {
            bestScore = score;
            bestDevice = device;
        }
    }

    if (bestDevice == null) return error.NoSuitableGPU;
    zvkw.ctx.m_physicalDevice = bestDevice;

    var props: zvkw.zvk.VkPhysicalDeviceProperties = undefined;
    zvkw.zvk.vkGetPhysicalDeviceProperties(zvkw.ctx.m_physicalDevice, &props);
    std.log.info("Selected GPU: {s}", .{props.deviceName});
}
fn createLogicalDevice() !void {
    var queueFamilyCount: u32 = 0;
    zvkw.zvk.vkGetPhysicalDeviceQueueFamilyProperties(zvkw.ctx.m_physicalDevice, &queueFamilyCount, null);

    const queueFamilies = try zvkw.ctx.zallocator.alloc(zvkw.zvk.VkQueueFamilyProperties, queueFamilyCount);
    defer zvkw.ctx.zallocator.free(queueFamilies);
    zvkw.zvk.vkGetPhysicalDeviceQueueFamilyProperties(zvkw.ctx.m_physicalDevice, &queueFamilyCount, queueFamilies.ptr);

    for (queueFamilies, 0..) |fam, i| {
        if (fam.queueFlags & zvkw.zvk.VK_QUEUE_GRAPHICS_BIT != 0) {
            zvkw.ctx.queueFamilyIndex = @intCast(i);
            break;
        }
    }

    const priority: f32 = 1.0;
    const queueCI = zvkw.zvk.VkDeviceQueueCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = zvkw.ctx.queueFamilyIndex,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    };
    var vk11Features = zvkw.zvk.VkPhysicalDeviceVulkan11Features{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
        .shaderDrawParameters = zvkw.zvk.VK_TRUE,
    };

    var vk12Features = zvkw.zvk.VkPhysicalDeviceVulkan12Features{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
        .pNext = &vk11Features,
        .descriptorBindingPartiallyBound = zvkw.zvk.VK_TRUE,
        .descriptorBindingSampledImageUpdateAfterBind = zvkw.zvk.VK_TRUE,
        .descriptorIndexing = zvkw.zvk.VK_TRUE,
        .shaderSampledImageArrayNonUniformIndexing = zvkw.zvk.VK_TRUE,
        .descriptorBindingVariableDescriptorCount = zvkw.zvk.VK_TRUE,
        .runtimeDescriptorArray = zvkw.zvk.VK_TRUE,
        .bufferDeviceAddress = zvkw.zvk.VK_TRUE,
    };

    var vk13Features = zvkw.zvk.VkPhysicalDeviceVulkan13Features{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES,
        .pNext = &vk12Features,
        .synchronization2 = zvkw.zvk.VK_TRUE,
        .dynamicRendering = zvkw.zvk.VK_TRUE,
    };

    const vk10Features = zvkw.zvk.VkPhysicalDeviceFeatures{
        .samplerAnisotropy = zvkw.zvk.VK_TRUE,
    };

    const deviceExtensions = [_][*c]const u8{zvkw.zvk.VK_KHR_SWAPCHAIN_EXTENSION_NAME.ptr};

    const deviceCI = zvkw.zvk.VkDeviceCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &vk13Features,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queueCI,
        .enabledExtensionCount = deviceExtensions.len,
        .ppEnabledExtensionNames = &deviceExtensions,
        .pEnabledFeatures = &vk10Features,
    };

    const result = zvkw.zvk.vkCreateDevice(zvkw.ctx.m_physicalDevice, &deviceCI, null, &zvkw.ctx.m_Device);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateDeviceFailed;

    zvkw.zvk.vkGetDeviceQueue(zvkw.ctx.m_Device, zvkw.ctx.queueFamilyIndex, 0, &zvkw.ctx.queue);
}

fn createAllocator() !void {
    const vkfunctions = zvkw.vma.VmaVulkanFunctions{
        .vkGetInstanceProcAddr = @ptrCast(&zvkw.zvk.vkGetInstanceProcAddr),
        .vkGetDeviceProcAddr = @ptrCast(&zvkw.zvk.vkGetDeviceProcAddr),
        .vkCreateImage = @ptrCast(&zvkw.zvk.vkCreateImage),
    };
    const allocatorCI = zvkw.vma.VmaAllocatorCreateInfo{
        .flags = zvkw.vma.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
        .physicalDevice = @ptrCast(zvkw.ctx.m_physicalDevice),
        .device = @ptrCast(zvkw.ctx.m_Device),
        .pVulkanFunctions = &vkfunctions,
        .instance = @ptrCast(zvkw.ctx.m_instance),
    };
    const result = zvkw.vma.vmaCreateAllocator(&allocatorCI, &zvkw.ctx.vmaAllocator);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateAllocatorFailed;
}
fn debugCallback(
    severity: zvkw.zvk.VkDebugUtilsMessageSeverityFlagBitsEXT,
    msgType: zvkw.zvk.VkDebugUtilsMessageTypeFlagBitsEXT,
    pCallbackData: ?*const zvkw.zvk.VkDebugUtilsMessengerCallbackDataEXT,
    pUserData: ?*anyopaque,
) callconv(.c) zvkw.zvk.VkBool32 {
    _ = msgType;
    _ = pUserData;
    if (pCallbackData) |data| {
        if (severity >= zvkw.zvk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) {
            std.log.err("Validation Layer: {s}", .{data.pMessage});
        } else if (severity >= zvkw.zvk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
            std.log.warn("Validation Layer: {s}", .{data.pMessage});
        } else if (severity >= zvkw.zvk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT) {
            std.log.info("Validation Layer: {s}", .{data.pMessage});
        }
    }
    return zvkw.zvk.VK_FALSE;
}
pub fn createSwapchain() !void {
    const surfaceFormat = pickSurfaceFormat();
    zvkw.ctx.colorFormat = surfaceFormat.format;
    zvkw.ctx.colorSpace = surfaceFormat.colorSpace;

    //if (surfaceCaps.currentExtent.width == 0 or surfaceCaps.currentExtent.height == 0) return; // TODO : handle this case properly, maybe by waiting for resize event and recreating swapchain then
    var surfaceCaps: zvkw.zvk.VkSurfaceCapabilitiesKHR = undefined;
    _ = zvkw.zvk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(zvkw.ctx.m_physicalDevice, zvkw.ctx.m_surface, &surfaceCaps);

    const swapchainExtent: zvkw.zvk.VkExtent2D = if (surfaceCaps.currentExtent.width == 0xFFFFFFFF)
        .{ .width = 800, .height = 600 }
    else
        surfaceCaps.currentExtent;
    zvkw.ctx.swapChainExtent = swapchainExtent;
    // maxImageCount == 0 means "no upper limit", so only clamp when it is set.
    var desiredImageCount = surfaceCaps.minImageCount + 1;
    if (surfaceCaps.maxImageCount > 0 and desiredImageCount > surfaceCaps.maxImageCount) {
        desiredImageCount = surfaceCaps.maxImageCount;
    }
    const swapchainCI = zvkw.zvk.VkSwapchainCreateInfoKHR{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = zvkw.ctx.m_surface,
        .minImageCount = desiredImageCount,
        .imageFormat = zvkw.ctx.colorFormat,
        .imageColorSpace = zvkw.ctx.colorSpace,
        .imageExtent = swapchainExtent,
        .imageArrayLayers = 1,
        .imageUsage = zvkw.zvk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | zvkw.zvk.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .imageSharingMode = zvkw.zvk.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 1,
        .pQueueFamilyIndices = &zvkw.ctx.queueFamilyIndex,
        .preTransform = surfaceCaps.currentTransform,
        .compositeAlpha = zvkw.zvk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = zvkw.zvk.VK_PRESENT_MODE_FIFO_KHR,
        .clipped = zvkw.zvk.VK_TRUE,
    };
    var result = zvkw.zvk.vkCreateSwapchainKHR(zvkw.ctx.m_Device, &swapchainCI, null, &zvkw.ctx.swapChain);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateSwapchainFailed;

    var imageCount: u32 = 0;
    _ = zvkw.zvk.vkGetSwapchainImagesKHR(zvkw.ctx.m_Device, zvkw.ctx.swapChain, &imageCount, null);
    zvkw.ctx.swapChainImages = try zvkw.ctx.zallocator.alloc(zvkw.zvk.VkImage, imageCount);
    _ = zvkw.zvk.vkGetSwapchainImagesKHR(zvkw.ctx.m_Device, zvkw.ctx.swapChain, &imageCount, zvkw.ctx.swapChainImages.ptr);

    zvkw.ctx.swapChainImageViews = try zvkw.ctx.zallocator.alloc(zvkw.zvk.VkImageView, imageCount);
    for (zvkw.ctx.swapChainImages, 0..) |image, i| {
        const viewCI = zvkw.zvk.VkImageViewCreateInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = zvkw.zvk.VK_IMAGE_VIEW_TYPE_2D,
            .format = zvkw.ctx.colorFormat,
            .components = .{
                .r = zvkw.zvk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = zvkw.zvk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = zvkw.zvk.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = zvkw.zvk.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        result = zvkw.zvk.vkCreateImageView(zvkw.ctx.m_Device, &viewCI, null, &zvkw.ctx.swapChainImageViews[i]);
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateImageViewFailed;
    }
}
/// Rebuilds the swapchain and everything sized to it (image views, depth image,
/// per-image render-complete semaphores). Called when acquire/present report the
/// surface is out of date (resize, minimize/restore, display change).
fn recreateSwapchain() !void {
    // A zero-area surface (e.g. minimized window) can't have a swapchain; skip
    // until it has a real size again.
    var surfaceCaps: zvkw.zvk.VkSurfaceCapabilitiesKHR = undefined;
    _ = zvkw.zvk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(zvkw.ctx.m_physicalDevice, zvkw.ctx.m_surface, &surfaceCaps);
    if (surfaceCaps.currentExtent.width == 0 or surfaceCaps.currentExtent.height == 0) return;

    _ = zvkw.zvk.vkDeviceWaitIdle(zvkw.ctx.m_Device);

    // Tear down the old swapchain-dependent resources.
    for (zvkw.ctx.swapChainImageViews) |view| {
        zvkw.zvk.vkDestroyImageView(zvkw.ctx.m_Device, view, null);
    }
    zvkw.ctx.zallocator.free(zvkw.ctx.swapChainImageViews);
    zvkw.ctx.zallocator.free(zvkw.ctx.swapChainImages);
    zvkw.zvk.vkDestroyImageView(zvkw.ctx.m_Device, zvkw.ctx.depthImageView, null);
    zvkw.vma.vmaDestroyImage(zvkw.ctx.vmaAllocator, @ptrCast(zvkw.ctx.depthImage), zvkw.ctx.depthImageAllocation);
    for (zvkw.ctx.renderCompleteSemaphores) |semaphore| {
        zvkw.zvk.vkDestroySemaphore(zvkw.ctx.m_Device, semaphore, null);
    }
    zvkw.ctx.zallocator.free(zvkw.ctx.renderCompleteSemaphores);

    const oldSwapchain = zvkw.ctx.swapChain;
    try createSwapchain();
    zvkw.zvk.vkDestroySwapchainKHR(zvkw.ctx.m_Device, oldSwapchain, null);
    try createDepthImage();

    // The swapchain image count can change, so recreate the per-image semaphores.
    const semaphoreCI = zvkw.zvk.VkSemaphoreCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    zvkw.ctx.renderCompleteSemaphores = try zvkw.ctx.zallocator.alloc(zvkw.zvk.VkSemaphore, zvkw.ctx.swapChainImages.len);
    for (0..zvkw.ctx.swapChainImages.len) |i| {
        const result = zvkw.zvk.vkCreateSemaphore(zvkw.ctx.m_Device, &semaphoreCI, null, &zvkw.ctx.renderCompleteSemaphores[i]);
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateSemaphoreFailed;
    }
}
fn pickSurfaceFormat() zvkw.zvk.VkSurfaceFormatKHR {
    var formatCount: u32 = 0;
    _ = zvkw.zvk.vkGetPhysicalDeviceSurfaceFormatsKHR(zvkw.ctx.m_physicalDevice, zvkw.ctx.m_surface, &formatCount, null);
    const formats = zvkw.ctx.zallocator.alloc(zvkw.zvk.VkSurfaceFormatKHR, formatCount) catch unreachable;
    defer zvkw.ctx.zallocator.free(formats);
    _ = zvkw.zvk.vkGetPhysicalDeviceSurfaceFormatsKHR(zvkw.ctx.m_physicalDevice, zvkw.ctx.m_surface, &formatCount, formats.ptr);

    for (formats) |format| {
        if (format.format == zvkw.zvk.VK_FORMAT_R8G8B8A8_SRGB and
            format.colorSpace == zvkw.zvk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        {
            return format;
        }
    }
    return formats[0];
}
fn createDepthImage() !void {
    const depthFormatList = [_]zvkw.zvk.VkFormat{
        zvkw.zvk.VK_FORMAT_D32_SFLOAT_S8_UINT,
        zvkw.zvk.VK_FORMAT_D24_UNORM_S8_UINT,
    };
    for (depthFormatList) |format| {
        var formatProperties = zvkw.zvk.VkFormatProperties2{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2,
        };
        zvkw.zvk.vkGetPhysicalDeviceFormatProperties2(zvkw.ctx.m_physicalDevice, format, &formatProperties);
        if (formatProperties.formatProperties.optimalTilingFeatures & zvkw.zvk.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT != 0) {
            zvkw.ctx.depthFormat = format;
            break;
        }
    }
    if (zvkw.ctx.depthFormat == zvkw.zvk.VK_FORMAT_UNDEFINED) return error.NoSuitableDepthFormat;

    const depthImageCI = zvkw.zvk.VkImageCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = zvkw.zvk.VK_IMAGE_TYPE_2D,
        .format = zvkw.ctx.depthFormat,
        .extent = .{ .width = zvkw.ctx.swapChainExtent.width, .height = zvkw.ctx.swapChainExtent.height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = zvkw.zvk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = zvkw.zvk.VK_IMAGE_TILING_OPTIMAL,
        .usage = zvkw.zvk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
        .initialLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
    };
    const allocCI = zvkw.vma.VmaAllocationCreateInfo{
        .flags = zvkw.vma.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
        .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
    };
    const result = zvkw.vma.vmaCreateImage(zvkw.ctx.vmaAllocator, @ptrCast(&depthImageCI), &allocCI, @ptrCast(&zvkw.ctx.depthImage), &zvkw.ctx.depthImageAllocation, null);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateDepthImageFailed;

    const depthViewCI = zvkw.zvk.VkImageViewCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = zvkw.ctx.depthImage,
        .viewType = zvkw.zvk.VK_IMAGE_VIEW_TYPE_2D,
        .format = zvkw.ctx.depthFormat,
        .subresourceRange = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    const result2 = zvkw.zvk.vkCreateImageView(zvkw.ctx.m_Device, &depthViewCI, null, &zvkw.ctx.depthImageView);
    if (result2 != zvkw.zvk.VK_SUCCESS) return error.CreateDepthImageViewFailed;
}
fn createSyncObjects() !void {
    const semaphoreCI = zvkw.zvk.VkSemaphoreCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    const fenceCI = zvkw.zvk.VkFenceCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = zvkw.zvk.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    for (0..zvkw.max_frames_in_flight) |i| {
        var result = zvkw.zvk.vkCreateFence(zvkw.ctx.m_Device, &fenceCI, null, &zvkw.ctx.fences[i]);
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateFenceFailed;
        result = zvkw.zvk.vkCreateSemaphore(zvkw.ctx.m_Device, &semaphoreCI, null, &zvkw.ctx.imageAcquiredSemaphores[i]);
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateSemaphoreFailed;
    }
    zvkw.ctx.renderCompleteSemaphores = try zvkw.ctx.zallocator.alloc(zvkw.zvk.VkSemaphore, zvkw.ctx.swapChainImages.len);
    for (0..zvkw.ctx.swapChainImages.len) |i| {
        const result = zvkw.zvk.vkCreateSemaphore(zvkw.ctx.m_Device, &semaphoreCI, null, &zvkw.ctx.renderCompleteSemaphores[i]);
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateSemaphoreFailed;
    }
}
fn createCommandPool() !void {
    const commandPoolCI = zvkw.zvk.VkCommandPoolCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = zvkw.zvk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = zvkw.ctx.queueFamilyIndex,
    };
    var result = zvkw.zvk.vkCreateCommandPool(zvkw.ctx.m_Device, &commandPoolCI, null, &zvkw.ctx.commandPool);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateCommandPoolFailed;

    const cbAllocCI = zvkw.zvk.VkCommandBufferAllocateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = zvkw.ctx.commandPool,
        .level = zvkw.zvk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = zvkw.max_frames_in_flight,
    };
    result = zvkw.zvk.vkAllocateCommandBuffers(zvkw.ctx.m_Device, &cbAllocCI, &zvkw.ctx.commandBuffers);
    if (result != zvkw.zvk.VK_SUCCESS) return error.AllocateCommandBuffersFailed;
}
pub fn render(matrices: cs.CameraMatrices) !void {
    _ = zvkw.zvk.vkWaitForFences(zvkw.ctx.m_Device, 1, &zvkw.ctx.fences[zvkw.ctx.frameIndex], zvkw.zvk.VK_TRUE, std.math.maxInt(u64));

    const acquireResult = zvkw.zvk.vkAcquireNextImageKHR(zvkw.ctx.m_Device, zvkw.ctx.swapChain, std.math.maxInt(u64), zvkw.ctx.imageAcquiredSemaphores[zvkw.ctx.frameIndex], null, &zvkw.ctx.imageIndex);
    if (acquireResult == zvkw.zvk.VK_ERROR_OUT_OF_DATE_KHR) {
        // Surface changed (resize/display change). Rebuild and skip this frame.
        try recreateSwapchain();
        return;
    } else if (acquireResult != zvkw.zvk.VK_SUCCESS and acquireResult != zvkw.zvk.VK_SUBOPTIMAL_KHR) {
        return error.AcquireImageFailed;
    }
    // Only reset the fence once we know we'll submit work that signals it,
    // otherwise an early return above would leave it unsignaled and deadlock.
    _ = zvkw.zvk.vkResetFences(zvkw.ctx.m_Device, 1, &zvkw.ctx.fences[zvkw.ctx.frameIndex]);

    const uboData = zvkw.FrameUBO{
        .projection = matrices.projection,
        .view = matrices.view,
    };
    @memcpy(@as([*]u8, @ptrCast(zvkw.ctx.shaderDataBuffers[zvkw.ctx.frameIndex].allocInfo.pMappedData.?))[0..@sizeOf(zvkw.FrameUBO)], std.mem.asBytes(&uboData));
    const cb = zvkw.ctx.commandBuffers[zvkw.ctx.frameIndex];
    _ = zvkw.zvk.vkResetCommandBuffer(cb, 0);

    const cbBI = zvkw.zvk.VkCommandBufferBeginInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = zvkw.zvk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    _ = zvkw.zvk.vkBeginCommandBuffer(cb, &cbBI);

    const outputBarriers = [2]zvkw.zvk.VkImageMemoryBarrier2{
        .{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = zvkw.zvk.VK_ACCESS_2_NONE,
            .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = zvkw.zvk.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
            .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
            .image = zvkw.ctx.swapChainImages[zvkw.ctx.imageIndex],
            .subresourceRange = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
        },
        .{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
            .srcAccessMask = zvkw.zvk.VK_ACCESS_2_NONE,
            .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
            .dstAccessMask = zvkw.zvk.VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
            .image = zvkw.ctx.depthImage,
            .subresourceRange = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_DEPTH_BIT | zvkw.zvk.VK_IMAGE_ASPECT_STENCIL_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
        },
    };
    const barrierDependencyInfo = zvkw.zvk.VkDependencyInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 2,
        .pImageMemoryBarriers = &outputBarriers,
    };
    zvkw.zvk.vkCmdPipelineBarrier2(cb, &barrierDependencyInfo);

    const colorAttachmentInfo = zvkw.zvk.VkRenderingAttachmentInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = zvkw.ctx.swapChainImageViews[zvkw.ctx.imageIndex],
        .imageLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        .loadOp = zvkw.zvk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = zvkw.zvk.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } },
    };
    const depthAttachmentInfo = zvkw.zvk.VkRenderingAttachmentInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = zvkw.ctx.depthImageView,
        .imageLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        .loadOp = zvkw.zvk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = zvkw.zvk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .clearValue = .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
    };
    const renderingInfo = zvkw.zvk.VkRenderingInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = zvkw.ctx.swapChainExtent },
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorAttachmentInfo,
        .pDepthAttachment = &depthAttachmentInfo,
    };
    zvkw.zvk.vkCmdBeginRendering(cb, &renderingInfo);
    const vp = zvkw.zvk.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(zvkw.ctx.swapChainExtent.width),
        .height = @floatFromInt(zvkw.ctx.swapChainExtent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    zvkw.zvk.vkCmdSetViewport(cb, 0, 1, &vp);

    const scissor = zvkw.zvk.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = zvkw.ctx.swapChainExtent,
    };
    zvkw.zvk.vkCmdSetScissor(cb, 0, 1, &scissor);
    zvkw.zvk.vkCmdBindPipeline(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, zvkw.ctx.pipeline);
    try renderSystem.update(registry, cb);
    zvkw.zvk.vkCmdEndRendering(cb);

    const barrierPresent = zvkw.zvk.VkImageMemoryBarrier2{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = zvkw.zvk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = 0,
        .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .image = zvkw.ctx.swapChainImages[zvkw.ctx.imageIndex],
        .subresourceRange = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
    };
    const barrierPresentDependencyInfo = zvkw.zvk.VkDependencyInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &barrierPresent,
    };
    zvkw.zvk.vkCmdPipelineBarrier2(cb, &barrierPresentDependencyInfo);
    _ = zvkw.zvk.vkEndCommandBuffer(cb);

    const waitStages: zvkw.zvk.VkPipelineStageFlags = zvkw.zvk.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    const submitInfo = zvkw.zvk.VkSubmitInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &zvkw.ctx.imageAcquiredSemaphores[zvkw.ctx.frameIndex],
        .pWaitDstStageMask = &waitStages,
        .commandBufferCount = 1,
        .pCommandBuffers = &cb,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &zvkw.ctx.renderCompleteSemaphores[zvkw.ctx.imageIndex],
    };
    _ = zvkw.zvk.vkQueueSubmit(zvkw.ctx.queue, 1, &submitInfo, zvkw.ctx.fences[zvkw.ctx.frameIndex]);

    const presentInfo = zvkw.zvk.VkPresentInfoKHR{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &zvkw.ctx.renderCompleteSemaphores[zvkw.ctx.imageIndex],
        .swapchainCount = 1,
        .pSwapchains = &zvkw.ctx.swapChain,
        .pImageIndices = &zvkw.ctx.imageIndex,
    };
    const presentResult = zvkw.zvk.vkQueuePresentKHR(zvkw.ctx.queue, &presentInfo);
    if (presentResult == zvkw.zvk.VK_ERROR_OUT_OF_DATE_KHR or presentResult == zvkw.zvk.VK_SUBOPTIMAL_KHR) {
        try recreateSwapchain();
    } else if (presentResult != zvkw.zvk.VK_SUCCESS) {
        return error.PresentImageFailed;
    }
    zvkw.ctx.frameIndex = (zvkw.ctx.frameIndex + 1) % zvkw.max_frames_in_flight;
}

fn createPipeline() !void {
    const spv = @embedFile("../shaders/slang.spv");

    const shaderModuleCI = zvkw.zvk.VkShaderModuleCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = spv.len,
        .pCode = @ptrCast(@alignCast(spv)),
    };

    var shaderModule: zvkw.zvk.VkShaderModule = null;
    const result = zvkw.zvk.vkCreateShaderModule(zvkw.ctx.m_Device, &shaderModuleCI, null, &shaderModule);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateShaderModuleFailed;
    defer zvkw.zvk.vkDestroyShaderModule(zvkw.ctx.m_Device, shaderModule, null);

    const shaderStages = [2]zvkw.zvk.VkPipelineShaderStageCreateInfo{
        .{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = zvkw.zvk.VK_SHADER_STAGE_VERTEX_BIT,
            .module = shaderModule,
            .pName = "vertMain",
        },
        .{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
            .stage = zvkw.zvk.VK_SHADER_STAGE_FRAGMENT_BIT,
            .module = shaderModule,
            .pName = "fragMain",
        },
    };
    const vertexBindingDesc = zvkw.zvk.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(zvkw.Vertex),
        .inputRate = zvkw.zvk.VK_VERTEX_INPUT_RATE_VERTEX,
    };
    const vertexAttribDescs = [3]zvkw.zvk.VkVertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = zvkw.zvk.VK_FORMAT_R32G32B32_SFLOAT, .offset = @offsetOf(zvkw.Vertex, "pos") },
        .{ .location = 1, .binding = 0, .format = zvkw.zvk.VK_FORMAT_R32G32B32_SFLOAT, .offset = @offsetOf(zvkw.Vertex, "normal") },
        .{ .location = 2, .binding = 0, .format = zvkw.zvk.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(zvkw.Vertex, "uv") },
    };
    const vertexInputCI = zvkw.zvk.VkPipelineVertexInputStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &vertexBindingDesc,
        .vertexAttributeDescriptionCount = 3,
        .pVertexAttributeDescriptions = &vertexAttribDescs,
    };
    const inputAssemblyCI = zvkw.zvk.VkPipelineInputAssemblyStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = zvkw.zvk.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    };
    const viewportStateCI = zvkw.zvk.VkPipelineViewportStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .viewportCount = 1,
        .scissorCount = 1,
    };
    const rasterizationCI = zvkw.zvk.VkPipelineRasterizationStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .polygonMode = zvkw.zvk.VK_POLYGON_MODE_FILL,
        .cullMode = zvkw.zvk.VK_CULL_MODE_NONE,
        .frontFace = zvkw.zvk.VK_FRONT_FACE_CLOCKWISE,
        .lineWidth = 1.0,
    };
    const multisampleCI = zvkw.zvk.VkPipelineMultisampleStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .rasterizationSamples = zvkw.zvk.VK_SAMPLE_COUNT_1_BIT,
    };
    const depthStencilCI = zvkw.zvk.VkPipelineDepthStencilStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = zvkw.zvk.VK_TRUE,
        .depthWriteEnable = zvkw.zvk.VK_TRUE,
        .depthCompareOp = zvkw.zvk.VK_COMPARE_OP_LESS_OR_EQUAL,
    };
    const colorBlendAttachment = zvkw.zvk.VkPipelineColorBlendAttachmentState{
        .colorWriteMask = zvkw.zvk.VK_COLOR_COMPONENT_R_BIT | zvkw.zvk.VK_COLOR_COMPONENT_G_BIT |
            zvkw.zvk.VK_COLOR_COMPONENT_B_BIT | zvkw.zvk.VK_COLOR_COMPONENT_A_BIT,
    };
    const colorBlendCI = zvkw.zvk.VkPipelineColorBlendStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 1,
        .pAttachments = &colorBlendAttachment,
    };
    const dynamicStates = [_]zvkw.zvk.VkDynamicState{
        zvkw.zvk.VK_DYNAMIC_STATE_VIEWPORT,
        zvkw.zvk.VK_DYNAMIC_STATE_SCISSOR,
    };
    const dynamicStateCI = zvkw.zvk.VkPipelineDynamicStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .dynamicStateCount = dynamicStates.len,
        .pDynamicStates = &dynamicStates,
    };
    const pushConstantRange = zvkw.zvk.VkPushConstantRange{
        .stageFlags = zvkw.zvk.VK_SHADER_STAGE_VERTEX_BIT | zvkw.zvk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .offset = 0,
        .size = @sizeOf(zvkw.PushConstants), // VkDeviceAddress
    };
    const setLayouts = [2]zvkw.zvk.VkDescriptorSetLayout{
        zvkw.ctx.uboDescriptorSetLayout,
        zvkw.ctx.bindlessDescriptorSetLayout,
    };
    const pipelineLayoutCI = zvkw.zvk.VkPipelineLayoutCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 2,
        .pSetLayouts = &setLayouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &pushConstantRange,
    };
    var result2 = zvkw.zvk.vkCreatePipelineLayout(zvkw.ctx.m_Device, &pipelineLayoutCI, null, &zvkw.ctx.pipelineLayout);
    if (result2 != zvkw.zvk.VK_SUCCESS) return error.CreatePipelineLayoutFailed;

    const pipelineRenderingCI = zvkw.zvk.VkPipelineRenderingCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = @ptrCast(&zvkw.ctx.colorFormat),
        .depthAttachmentFormat = zvkw.ctx.depthFormat,
    };
    const pipelineCI = zvkw.zvk.VkGraphicsPipelineCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = &pipelineRenderingCI,
        .stageCount = 2,
        .pStages = &shaderStages,
        .pVertexInputState = &vertexInputCI,
        .pInputAssemblyState = &inputAssemblyCI,
        .pViewportState = &viewportStateCI,
        .pRasterizationState = &rasterizationCI,
        .pMultisampleState = &multisampleCI,
        .pDepthStencilState = &depthStencilCI,
        .pColorBlendState = &colorBlendCI,
        .pDynamicState = &dynamicStateCI,
        .layout = zvkw.ctx.pipelineLayout,
    };
    result2 = zvkw.zvk.vkCreateGraphicsPipelines(zvkw.ctx.m_Device, null, 1, &pipelineCI, null, &zvkw.ctx.pipeline);
    if (result2 != zvkw.zvk.VK_SUCCESS) return error.CreatePipelineFailed;
}

fn createDescriptorSetLayout() !void {
    const uboBinding = zvkw.zvk.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = zvkw.zvk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        .descriptorCount = 1,
        .stageFlags = zvkw.zvk.VK_SHADER_STAGE_VERTEX_BIT,
    };
    const uboLayoutCI = zvkw.zvk.VkDescriptorSetLayoutCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1,
        .pBindings = &uboBinding,
    };
    var result = zvkw.zvk.vkCreateDescriptorSetLayout(zvkw.ctx.m_Device, &uboLayoutCI, null, &zvkw.ctx.uboDescriptorSetLayout);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateDescriptorSetLayoutFailed;

    const textureBinding = zvkw.zvk.VkDescriptorSetLayoutBinding{
        .binding = 0,
        .descriptorType = zvkw.zvk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .descriptorCount = zvkw.MAX_TEXTURES,
        .stageFlags = zvkw.zvk.VK_SHADER_STAGE_FRAGMENT_BIT,
    };
    const bindingFlags: u32 = zvkw.zvk.VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT |
        zvkw.zvk.VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT;
    const bindingFlagsCI = zvkw.zvk.VkDescriptorSetLayoutBindingFlagsCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
        .bindingCount = 1,
        .pBindingFlags = &bindingFlags,
    };
    const bindlessLayoutCI = zvkw.zvk.VkDescriptorSetLayoutCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .flags = zvkw.zvk.VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT,
        .pNext = &bindingFlagsCI,
        .bindingCount = 1,
        .pBindings = &textureBinding,
    };
    result = zvkw.zvk.vkCreateDescriptorSetLayout(zvkw.ctx.m_Device, &bindlessLayoutCI, null, &zvkw.ctx.bindlessDescriptorSetLayout);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateDescriptorSetLayoutFailed;
}
fn createDescriptorPool() !void {
    const poolSize = [2]zvkw.zvk.VkDescriptorPoolSize{
        .{
            .type = zvkw.zvk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .descriptorCount = zvkw.max_frames_in_flight,
        },
        .{
            .type = zvkw.zvk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
            .descriptorCount = zvkw.MAX_TEXTURES,
        },
    };
    const poolCI = zvkw.zvk.VkDescriptorPoolCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .flags = zvkw.zvk.VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT,
        .maxSets = zvkw.max_frames_in_flight + 1,
        .poolSizeCount = 2,
        .pPoolSizes = &poolSize,
    };
    const result = zvkw.zvk.vkCreateDescriptorPool(zvkw.ctx.m_Device, &poolCI, null, &zvkw.ctx.descriptorPool);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateDescriptorPoolFailed;
}
fn createSampler() !void {
    const samplerCI = zvkw.zvk.VkSamplerCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = zvkw.zvk.VK_FILTER_LINEAR,
        .minFilter = zvkw.zvk.VK_FILTER_LINEAR,
        .mipmapMode = zvkw.zvk.VK_SAMPLER_MIPMAP_MODE_LINEAR,
        .addressModeU = zvkw.zvk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeV = zvkw.zvk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .addressModeW = zvkw.zvk.VK_SAMPLER_ADDRESS_MODE_REPEAT,
        .mipLodBias = 0.0,
        .anisotropyEnable = zvkw.zvk.VK_TRUE,
        .maxAnisotropy = 16.0,
        .compareEnable = zvkw.zvk.VK_FALSE,
        .minLod = 0.0,
        .maxLod = zvkw.zvk.VK_LOD_CLAMP_NONE,
        .unnormalizedCoordinates = zvkw.zvk.VK_FALSE,
    };
    const result = zvkw.zvk.vkCreateSampler(zvkw.ctx.m_Device, &samplerCI, null, &zvkw.ctx.bindlessSampler);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateSamplerFailed;
}
pub fn uploadTexture(pixels: []const u8, width: u32, height: u32) !zvkw.TextureHandle {
    const slot = zvkw.ctx.textureCount;
    if (slot >= zvkw.MAX_TEXTURES) return error.TextureHeapFull;
    const imageSize: zvkw.zvk.VkDeviceSize = width * height * 4;
    var stagingBuffer: zvkw.zvk.VkBuffer = null;
    var stagingAllocation: zvkw.vma.VmaAllocation = null;
    const stagingBufferCI = zvkw.zvk.VkBufferCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = imageSize,
        .usage = zvkw.zvk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
    };
    const stagingAllocCI = zvkw.vma.VmaAllocationCreateInfo{
        .flags = zvkw.vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT |
            zvkw.vma.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
    };
    var stagingAllocInfo: zvkw.vma.VmaAllocationInfo = undefined;
    _ = zvkw.vma.vmaCreateBuffer(zvkw.ctx.vmaAllocator, @ptrCast(&stagingBufferCI), &stagingAllocCI, @ptrCast(&stagingBuffer), &stagingAllocation, &stagingAllocInfo);
    defer zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(stagingBuffer), stagingAllocation);
    const dst: [*]u8 = @ptrCast(stagingAllocInfo.pMappedData.?);
    @memcpy(dst[0..imageSize], pixels[0..imageSize]);
    const imageCI = zvkw.zvk.VkImageCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = zvkw.zvk.VK_IMAGE_TYPE_2D,
        .format = zvkw.zvk.VK_FORMAT_R8G8B8A8_SRGB,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = zvkw.zvk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = zvkw.zvk.VK_IMAGE_TILING_OPTIMAL,
        .usage = zvkw.zvk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | zvkw.zvk.VK_IMAGE_USAGE_SAMPLED_BIT,
        .initialLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
    };
    const imageAllocCI = zvkw.vma.VmaAllocationCreateInfo{
        .flags = zvkw.vma.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
        .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
    };
    _ = zvkw.vma.vmaCreateImage(zvkw.ctx.vmaAllocator, @ptrCast(&imageCI), &imageAllocCI, @ptrCast(&zvkw.ctx.textureSlots[slot].image), &zvkw.ctx.textureSlots[slot].allocation, null);
    var cb: zvkw.zvk.VkCommandBuffer = null;
    const cbAllocCI = zvkw.zvk.VkCommandBufferAllocateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = zvkw.ctx.commandPool,
        .level = zvkw.zvk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    _ = zvkw.zvk.vkAllocateCommandBuffers(zvkw.ctx.m_Device, &cbAllocCI, &cb);
    defer zvkw.zvk.vkFreeCommandBuffers(zvkw.ctx.m_Device, zvkw.ctx.commandPool, 1, &cb);
    const beginInfo = zvkw.zvk.VkCommandBufferBeginInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = zvkw.zvk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    _ = zvkw.zvk.vkBeginCommandBuffer(cb, &beginInfo);
    const toTransferBarrier = zvkw.zvk.VkImageMemoryBarrier2{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_NONE,
        .srcAccessMask = zvkw.zvk.VK_ACCESS_2_NONE,
        .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COPY_BIT,
        .dstAccessMask = zvkw.zvk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
        .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .image = zvkw.ctx.textureSlots[slot].image,
        .subresourceRange = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    const toTransferDep = zvkw.zvk.VkDependencyInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &toTransferBarrier,
    };
    zvkw.zvk.vkCmdPipelineBarrier2(cb, &toTransferDep);
    const copyRegion = zvkw.zvk.VkBufferImageCopy{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = width, .height = height, .depth = 1 },
    };
    zvkw.zvk.vkCmdCopyBufferToImage(cb, stagingBuffer, zvkw.ctx.textureSlots[slot].image, zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copyRegion);
    const toShaderBarrier = zvkw.zvk.VkImageMemoryBarrier2{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COPY_BIT,
        .srcAccessMask = zvkw.zvk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
        .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
        .dstAccessMask = zvkw.zvk.VK_ACCESS_2_SHADER_READ_BIT,
        .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .image = zvkw.ctx.textureSlots[slot].image,
        .subresourceRange = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    const toShaderDep = zvkw.zvk.VkDependencyInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &toShaderBarrier,
    };
    zvkw.zvk.vkCmdPipelineBarrier2(cb, &toShaderDep);
    _ = zvkw.zvk.vkEndCommandBuffer(cb);
    const submitInfo = zvkw.zvk.VkSubmitInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cb,
    };
    _ = zvkw.zvk.vkQueueSubmit(zvkw.ctx.queue, 1, &submitInfo, null);
    _ = zvkw.zvk.vkQueueWaitIdle(zvkw.ctx.queue);
    const viewCI = zvkw.zvk.VkImageViewCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = zvkw.ctx.textureSlots[slot].image,
        .viewType = zvkw.zvk.VK_IMAGE_VIEW_TYPE_2D,
        .format = zvkw.zvk.VK_FORMAT_R8G8B8A8_SRGB,
        .subresourceRange = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    _ = zvkw.zvk.vkCreateImageView(zvkw.ctx.m_Device, &viewCI, null, &zvkw.ctx.textureSlots[slot].view);
    const imageInfo = zvkw.zvk.VkDescriptorImageInfo{
        .sampler = zvkw.ctx.bindlessSampler,
        .imageView = zvkw.ctx.textureSlots[slot].view,
        .imageLayout = zvkw.zvk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    };
    const write = zvkw.zvk.VkWriteDescriptorSet{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = zvkw.ctx.bindlessDescriptorSet,
        .dstBinding = 0,
        .dstArrayElement = slot,
        .descriptorCount = 1,
        .descriptorType = zvkw.zvk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &imageInfo,
    };
    zvkw.zvk.vkUpdateDescriptorSets(zvkw.ctx.m_Device, 1, &write, 0, null);
    zvkw.ctx.textureCount += 1;
    return slot;
}
fn createDefaultTexture() !void {
    const white = [4]u8{ 255, 255, 255, 255 };
    _ = try uploadTexture(&white, 1, 1);
}
fn createDescriptorSets() !void {
    const uboLayouts = [zvkw.max_frames_in_flight]zvkw.zvk.VkDescriptorSetLayout{
        zvkw.ctx.uboDescriptorSetLayout,
        zvkw.ctx.uboDescriptorSetLayout,
    };
    const uboAllocInfo = zvkw.zvk.VkDescriptorSetAllocateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = zvkw.ctx.descriptorPool,
        .descriptorSetCount = zvkw.max_frames_in_flight,
        .pSetLayouts = &uboLayouts,
    };
    var result = zvkw.zvk.vkAllocateDescriptorSets(zvkw.ctx.m_Device, &uboAllocInfo, &zvkw.ctx.uboDescriptorSets);
    if (result != zvkw.zvk.VK_SUCCESS) return error.AllocateDescriptorSetsFailed;

    const bindlessAllocInfo = zvkw.zvk.VkDescriptorSetAllocateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = zvkw.ctx.descriptorPool,
        .descriptorSetCount = 1,
        .pSetLayouts = &zvkw.ctx.bindlessDescriptorSetLayout,
    };
    result = zvkw.zvk.vkAllocateDescriptorSets(zvkw.ctx.m_Device, &bindlessAllocInfo, &zvkw.ctx.bindlessDescriptorSet);
    if (result != zvkw.zvk.VK_SUCCESS) return error.AllocateDescriptorSetsFailed;
}

fn createShaderDataBuffers() !void {
    for (0..zvkw.max_frames_in_flight) |i| {
        const bufferCI = zvkw.zvk.VkBufferCreateInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = @sizeOf(zvkw.FrameUBO),
            .usage = zvkw.zvk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        };
        const allocCI = zvkw.vma.VmaAllocationCreateInfo{
            .flags = zvkw.vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT |
                zvkw.vma.VMA_ALLOCATION_CREATE_MAPPED_BIT,
            .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
        };
        const result = zvkw.vma.vmaCreateBuffer(
            zvkw.ctx.vmaAllocator,
            @ptrCast(&bufferCI),
            &allocCI,
            @ptrCast(&zvkw.ctx.shaderDataBuffers[i].buffer),
            &zvkw.ctx.shaderDataBuffers[i].allocation,
            &zvkw.ctx.shaderDataBuffers[i].allocInfo,
        );
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateShaderDataBufferFailed;

        const bufferInfo = zvkw.zvk.VkDescriptorBufferInfo{
            .buffer = zvkw.ctx.shaderDataBuffers[i].buffer,
            .offset = 0,
            .range = @sizeOf(zvkw.FrameUBO),
        };
        const write = zvkw.zvk.VkWriteDescriptorSet{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = zvkw.ctx.uboDescriptorSets[i],
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = zvkw.zvk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .pBufferInfo = &bufferInfo,
        };
        zvkw.zvk.vkUpdateDescriptorSets(zvkw.ctx.m_Device, 1, &write, 0, null);
    }
}
pub fn shouldClose() bool {
    return zvkw.zvk.vkWindowShouldClose(&zvkw.ctx.m_window);
}

pub fn pollEvents() void {
    zvkw.zvk.vkPollEvents();
}
