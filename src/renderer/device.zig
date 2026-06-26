const std = @import("std");
const zvkw = @import("zVulkanContext.zig");
const log = @import("../engine/log.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub fn setupDebugMessenger(ctx: *zvkw.VulkanContext) void {
    if (zvkw.enable_validation) {
        ctx.vkCreateDebugUtilsMessengerEXT = @ptrCast(zvkw.zvk.vkGetInstanceProcAddr(ctx.m_instance, "vkCreateDebugUtilsMessengerEXT"));
        ctx.vkDestroyDebugUtilsMessengerEXT = @ptrCast(zvkw.zvk.vkGetInstanceProcAddr(ctx.m_instance, "vkDestroyDebugUtilsMessengerEXT"));
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
        const result = ctx.vkCreateDebugUtilsMessengerEXT.?(ctx.m_instance, &debugCI, null, &ctx.m_debugMessenger);
        if (result != zvkw.zvk.VK_SUCCESS) {
            log.err(@src(), "Failed to set up debug messenger", .{});
        } else {
            log.info(@src(), "Debug messenger set up", .{});
        }
    }
}

pub fn pickPhysicalDevice(ctx: *zvkw.VulkanContext) !void {
    var deviceCount: u32 = 0;
    try check(zvkw.zvk.vkEnumeratePhysicalDevices(ctx.m_instance, &deviceCount, null));
    if (deviceCount == 0) return error.NoVulkanGPU;

    const devices = try ctx.zallocator.alloc(zvkw.zvk.VkPhysicalDevice, deviceCount);
    defer ctx.zallocator.free(devices);
    try check(zvkw.zvk.vkEnumeratePhysicalDevices(ctx.m_instance, &deviceCount, devices.ptr));

    var bestScore: u32 = 0;
    var bestDevice: zvkw.zvk.VkPhysicalDevice = null;
    var bestQueueFamily: u32 = 0;

    for (devices) |device| {
        var extCount: u32 = 0;
        try check(zvkw.zvk.vkEnumerateDeviceExtensionProperties(device, null, &extCount, null));
        const exts = try ctx.zallocator.alloc(zvkw.zvk.VkExtensionProperties, extCount);
        defer ctx.zallocator.free(exts);
        try check(zvkw.zvk.vkEnumerateDeviceExtensionProperties(device, null, &extCount, exts.ptr));
        var hasSwapchain = false;
        for (exts) |ext| {
            if (std.mem.eql(u8, std.mem.sliceTo(&ext.extensionName, 0), "VK_KHR_swapchain")) {
                hasSwapchain = true;
                break;
            }
        }
        if (!hasSwapchain) {
            log.info(@src(), "Device filtered: no swapchain support", .{});
            continue;
        }
        var qfCount: u32 = 0;
        zvkw.zvk.vkGetPhysicalDeviceQueueFamilyProperties(device, &qfCount, null);
        const qfams = try ctx.zallocator.alloc(zvkw.zvk.VkQueueFamilyProperties, qfCount);
        defer ctx.zallocator.free(qfams);
        zvkw.zvk.vkGetPhysicalDeviceQueueFamilyProperties(device, &qfCount, qfams.ptr);
        var graphicsPresentFamily: ?u32 = null;
        for (qfams, 0..) |fam, qi| {
            const hasGraphics = fam.queueFlags & zvkw.zvk.VK_QUEUE_GRAPHICS_BIT != 0;
            var presentSupport: zvkw.zvk.VkBool32 = zvkw.zvk.VK_FALSE;
            try check(zvkw.zvk.vkGetPhysicalDeviceSurfaceSupportKHR(device, @intCast(qi), ctx.m_surface, &presentSupport));
            if (hasGraphics and presentSupport == zvkw.zvk.VK_TRUE) {
                graphicsPresentFamily = @intCast(qi);
                break;
            }
        }
        if (graphicsPresentFamily == null) {
            log.info(@src(), "Device filtered: no graphics+present queue family", .{});
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

        log.info(@src(), "Device: {s} | type: {} | score: {}", .{ props.deviceName, props.deviceType, score });

        if (score > bestScore) {
            bestScore = score;
            bestDevice = device;
            bestQueueFamily = graphicsPresentFamily.?;
        }
    }

    if (bestDevice == null) return error.NoSuitableGPU;
    ctx.m_physicalDevice = bestDevice;
    ctx.queueFamilyIndex = bestQueueFamily;

    var props: zvkw.zvk.VkPhysicalDeviceProperties = undefined;
    zvkw.zvk.vkGetPhysicalDeviceProperties(ctx.m_physicalDevice, &props);
    log.info(@src(), "Selected GPU: {s}", .{props.deviceName});
}

pub fn createLogicalDevice(ctx: *zvkw.VulkanContext) !void {
    const priority: f32 = 1.0;
    const queueCI = zvkw.zvk.VkDeviceQueueCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = ctx.queueFamilyIndex,
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
    const result = zvkw.zvk.vkCreateDevice(ctx.m_physicalDevice, &deviceCI, null, &ctx.m_Device);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateDeviceFailed;
    zvkw.zvk.vkGetDeviceQueue(ctx.m_Device, ctx.queueFamilyIndex, 0, &ctx.queue);
}

pub fn createAllocator(ctx: *zvkw.VulkanContext) !void {
    const vkfunctions = zvkw.vma.VmaVulkanFunctions{
        .vkGetInstanceProcAddr = @ptrCast(&zvkw.zvk.vkGetInstanceProcAddr),
        .vkGetDeviceProcAddr = @ptrCast(&zvkw.zvk.vkGetDeviceProcAddr),
        .vkCreateImage = @ptrCast(&zvkw.zvk.vkCreateImage),
    };
    const allocatorCI = zvkw.vma.VmaAllocatorCreateInfo{
        .flags = zvkw.vma.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT,
        .physicalDevice = @ptrCast(ctx.m_physicalDevice),
        .device = @ptrCast(ctx.m_Device),
        .pVulkanFunctions = &vkfunctions,
        .instance = @ptrCast(ctx.m_instance),
    };
    const result = zvkw.vma.vmaCreateAllocator(&allocatorCI, &ctx.vmaAllocator);
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
            log.err(@src(), "Validation Layer: {s}", .{data.pMessage});
        } else if (severity >= zvkw.zvk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
            log.warn(@src(), "Validation Layer: {s}", .{data.pMessage});
        } else if (severity >= zvkw.zvk.VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT) {
            log.info(@src(), "Validation Layer: {s}", .{data.pMessage});
        }
    }
    return zvkw.zvk.VK_FALSE;
}
