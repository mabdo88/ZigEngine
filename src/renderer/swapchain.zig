const std = @import("std");
const zvkw = @import("zVulkanContext.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub fn createSwapchain() !void {
    const surfaceFormat = pickSurfaceFormat();
    zvkw.ctx.colorFormat = surfaceFormat.format;
    zvkw.ctx.colorSpace = surfaceFormat.colorSpace;

    var surfaceCaps: zvkw.zvk.VkSurfaceCapabilitiesKHR = undefined;
    _ = zvkw.zvk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(zvkw.ctx.m_physicalDevice, zvkw.ctx.m_surface, &surfaceCaps);

    const swapchainExtent: zvkw.zvk.VkExtent2D = if (surfaceCaps.currentExtent.width == 0xFFFFFFFF)
        .{ .width = zvkw.ctx.m_window.width, .height = zvkw.ctx.m_window.height }
    else
        surfaceCaps.currentExtent;
    zvkw.ctx.swapChainExtent = swapchainExtent;
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
        .oldSwapchain = zvkw.ctx.swapChain,
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
pub fn recreateSwapchain() !void {
    var surfaceCaps: zvkw.zvk.VkSurfaceCapabilitiesKHR = undefined;
    _ = zvkw.zvk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(zvkw.ctx.m_physicalDevice, zvkw.ctx.m_surface, &surfaceCaps);
    if (surfaceCaps.currentExtent.width == 0 or surfaceCaps.currentExtent.height == 0) return;

    try check(zvkw.zvk.vkDeviceWaitIdle(zvkw.ctx.m_Device));

    for (zvkw.ctx.swapChainImageViews) |view| {
        zvkw.zvk.vkDestroyImageView(zvkw.ctx.m_Device, view, null);
    }
    zvkw.ctx.zallocator.free(zvkw.ctx.swapChainImageViews);
    zvkw.ctx.swapChainImageViews = &.{};
    zvkw.ctx.zallocator.free(zvkw.ctx.swapChainImages);
    zvkw.ctx.swapChainImages = &.{};
    zvkw.zvk.vkDestroyImageView(zvkw.ctx.m_Device, zvkw.ctx.depthImageView, null);
    zvkw.ctx.depthImageView = null;
    zvkw.vma.vmaDestroyImage(zvkw.ctx.vmaAllocator, @ptrCast(zvkw.ctx.depthImage), zvkw.ctx.depthImageAllocation);
    zvkw.ctx.depthImage = null;
    for (zvkw.ctx.renderCompleteSemaphores) |semaphore| {
        zvkw.zvk.vkDestroySemaphore(zvkw.ctx.m_Device, semaphore, null);
    }
    zvkw.ctx.zallocator.free(zvkw.ctx.renderCompleteSemaphores);
    zvkw.ctx.renderCompleteSemaphores = &.{};

    const oldSwapchain = zvkw.ctx.swapChain;
    try createSwapchain();
    zvkw.zvk.vkDestroySwapchainKHR(zvkw.ctx.m_Device, oldSwapchain, null);
    try createDepthImage();

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

pub fn createDepthImage() !void {
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

pub fn createSyncObjects() !void {
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

pub fn createCommandPool() !void {
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
