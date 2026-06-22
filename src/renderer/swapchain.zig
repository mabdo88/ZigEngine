const std = @import("std");
const zvkw = @import("zVulkanContext.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub fn createSwapchain(ctx: *zvkw.VulkanContext) !void {
    const surfaceFormat = try pickSurfaceFormat(ctx);
    ctx.colorFormat = surfaceFormat.format;
    ctx.colorSpace = surfaceFormat.colorSpace;

    var surfaceCaps: zvkw.zvk.VkSurfaceCapabilitiesKHR = undefined;
    try check(zvkw.zvk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.m_physicalDevice, ctx.m_surface, &surfaceCaps));

    const swapchainExtent: zvkw.zvk.VkExtent2D = if (surfaceCaps.currentExtent.width == 0xFFFFFFFF)
        .{ .width = ctx.m_window.width, .height = ctx.m_window.height }
    else
        surfaceCaps.currentExtent;
    ctx.swapChainExtent = swapchainExtent;
    var desiredImageCount = surfaceCaps.minImageCount + 1;
    if (surfaceCaps.maxImageCount > 0 and desiredImageCount > surfaceCaps.maxImageCount) {
        desiredImageCount = surfaceCaps.maxImageCount;
    }
    const swapchainCI = zvkw.zvk.VkSwapchainCreateInfoKHR{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = ctx.m_surface,
        .minImageCount = desiredImageCount,
        .imageFormat = ctx.colorFormat,
        .imageColorSpace = ctx.colorSpace,
        .imageExtent = swapchainExtent,
        .imageArrayLayers = 1,
        .imageUsage = zvkw.zvk.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | zvkw.zvk.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .imageSharingMode = zvkw.zvk.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 1,
        .pQueueFamilyIndices = &ctx.queueFamilyIndex,
        .preTransform = surfaceCaps.currentTransform,
        .compositeAlpha = zvkw.zvk.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = zvkw.zvk.VK_PRESENT_MODE_FIFO_KHR,
        .clipped = zvkw.zvk.VK_TRUE,
        .oldSwapchain = ctx.swapChain,
    };
    var result = zvkw.zvk.vkCreateSwapchainKHR(ctx.m_Device, &swapchainCI, null, &ctx.swapChain);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateSwapchainFailed;

    var imageCount: u32 = 0;
    try check(zvkw.zvk.vkGetSwapchainImagesKHR(ctx.m_Device, ctx.swapChain, &imageCount, null));
    ctx.swapChainImages = try ctx.zallocator.alloc(zvkw.zvk.VkImage, imageCount);
    try check(zvkw.zvk.vkGetSwapchainImagesKHR(ctx.m_Device, ctx.swapChain, &imageCount, ctx.swapChainImages.ptr));

    ctx.swapChainImageViews = try ctx.zallocator.alloc(zvkw.zvk.VkImageView, imageCount);
    for (ctx.swapChainImages, 0..) |image, i| {
        const viewCI = zvkw.zvk.VkImageViewCreateInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = image,
            .viewType = zvkw.zvk.VK_IMAGE_VIEW_TYPE_2D,
            .format = ctx.colorFormat,
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
        result = zvkw.zvk.vkCreateImageView(ctx.m_Device, &viewCI, null, &ctx.swapChainImageViews[i]);
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateImageViewFailed;
    }
}

pub fn recreateSwapchain(ctx: *zvkw.VulkanContext) !void {
    var surfaceCaps: zvkw.zvk.VkSurfaceCapabilitiesKHR = undefined;
    try check(zvkw.zvk.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(ctx.m_physicalDevice, ctx.m_surface, &surfaceCaps));
    if (surfaceCaps.currentExtent.width == 0 or surfaceCaps.currentExtent.height == 0) return;

    try check(zvkw.zvk.vkDeviceWaitIdle(ctx.m_Device));

    for (ctx.swapChainImageViews) |view| {
        zvkw.zvk.vkDestroyImageView(ctx.m_Device, view, null);
    }
    ctx.zallocator.free(ctx.swapChainImageViews);
    ctx.swapChainImageViews = &.{};
    ctx.zallocator.free(ctx.swapChainImages);
    ctx.swapChainImages = &.{};
    zvkw.zvk.vkDestroyImageView(ctx.m_Device, ctx.depthImageView, null);
    ctx.depthImageView = null;
    zvkw.vma.vmaDestroyImage(ctx.vmaAllocator, @ptrCast(ctx.depthImage), ctx.depthImageAllocation);
    ctx.depthImage = null;
    for (ctx.renderCompleteSemaphores) |semaphore| {
        zvkw.zvk.vkDestroySemaphore(ctx.m_Device, semaphore, null);
    }
    ctx.zallocator.free(ctx.renderCompleteSemaphores);
    ctx.renderCompleteSemaphores = &.{};

    const oldSwapchain = ctx.swapChain;
    try createSwapchain(ctx);
    zvkw.zvk.vkDestroySwapchainKHR(ctx.m_Device, oldSwapchain, null);
    try createDepthImage(ctx);

    const semaphoreCI = zvkw.zvk.VkSemaphoreCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    ctx.renderCompleteSemaphores = try ctx.zallocator.alloc(zvkw.zvk.VkSemaphore, ctx.swapChainImages.len);
    for (0..ctx.swapChainImages.len) |i| {
        const result = zvkw.zvk.vkCreateSemaphore(ctx.m_Device, &semaphoreCI, null, &ctx.renderCompleteSemaphores[i]);
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateSemaphoreFailed;
    }
}

fn pickSurfaceFormat(ctx: *zvkw.VulkanContext) !zvkw.zvk.VkSurfaceFormatKHR {
    var formatCount: u32 = 0;
    try check(zvkw.zvk.vkGetPhysicalDeviceSurfaceFormatsKHR(ctx.m_physicalDevice, ctx.m_surface, &formatCount, null));
    const formats = try ctx.zallocator.alloc(zvkw.zvk.VkSurfaceFormatKHR, formatCount);
    defer ctx.zallocator.free(formats);
    try check(zvkw.zvk.vkGetPhysicalDeviceSurfaceFormatsKHR(ctx.m_physicalDevice, ctx.m_surface, &formatCount, formats.ptr));

    for (formats) |format| {
        if (format.format == zvkw.zvk.VK_FORMAT_R8G8B8A8_SRGB and
            format.colorSpace == zvkw.zvk.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        {
            return format;
        }
    }
    return formats[0];
}

pub fn createDepthImage(ctx: *zvkw.VulkanContext) !void {
    const depthFormatList = [_]zvkw.zvk.VkFormat{
        zvkw.zvk.VK_FORMAT_D32_SFLOAT_S8_UINT,
        zvkw.zvk.VK_FORMAT_D24_UNORM_S8_UINT,
    };
    for (depthFormatList) |format| {
        var formatProperties = zvkw.zvk.VkFormatProperties2{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2,
        };
        zvkw.zvk.vkGetPhysicalDeviceFormatProperties2(ctx.m_physicalDevice, format, &formatProperties);
        if (formatProperties.formatProperties.optimalTilingFeatures & zvkw.zvk.VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT != 0) {
            ctx.depthFormat = format;
            break;
        }
    }
    if (ctx.depthFormat == zvkw.zvk.VK_FORMAT_UNDEFINED) return error.NoSuitableDepthFormat;

    const depthImageCI = zvkw.zvk.VkImageCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = zvkw.zvk.VK_IMAGE_TYPE_2D,
        .format = ctx.depthFormat,
        .extent = .{ .width = ctx.swapChainExtent.width, .height = ctx.swapChainExtent.height, .depth = 1 },
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
    const result = zvkw.vma.vmaCreateImage(ctx.vmaAllocator, @ptrCast(&depthImageCI), &allocCI, @ptrCast(&ctx.depthImage), &ctx.depthImageAllocation, null);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateDepthImageFailed;

    const depthViewCI = zvkw.zvk.VkImageViewCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = ctx.depthImage,
        .viewType = zvkw.zvk.VK_IMAGE_VIEW_TYPE_2D,
        .format = ctx.depthFormat,
        .subresourceRange = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    const result2 = zvkw.zvk.vkCreateImageView(ctx.m_Device, &depthViewCI, null, &ctx.depthImageView);
    if (result2 != zvkw.zvk.VK_SUCCESS) return error.CreateDepthImageViewFailed;
}

pub fn createSyncObjects(ctx: *zvkw.VulkanContext) !void {
    const semaphoreCI = zvkw.zvk.VkSemaphoreCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
    };
    const fenceCI = zvkw.zvk.VkFenceCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = zvkw.zvk.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    for (0..zvkw.max_frames_in_flight) |i| {
        var result = zvkw.zvk.vkCreateFence(ctx.m_Device, &fenceCI, null, &ctx.fences[i]);
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateFenceFailed;
        result = zvkw.zvk.vkCreateSemaphore(ctx.m_Device, &semaphoreCI, null, &ctx.imageAcquiredSemaphores[i]);
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateSemaphoreFailed;
    }
    ctx.renderCompleteSemaphores = try ctx.zallocator.alloc(zvkw.zvk.VkSemaphore, ctx.swapChainImages.len);
    for (0..ctx.swapChainImages.len) |i| {
        const result = zvkw.zvk.vkCreateSemaphore(ctx.m_Device, &semaphoreCI, null, &ctx.renderCompleteSemaphores[i]);
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateSemaphoreFailed;
    }
}

pub fn createCommandPool(ctx: *zvkw.VulkanContext) !void {
    const commandPoolCI = zvkw.zvk.VkCommandPoolCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = zvkw.zvk.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = ctx.queueFamilyIndex,
    };
    var result = zvkw.zvk.vkCreateCommandPool(ctx.m_Device, &commandPoolCI, null, &ctx.commandPool);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateCommandPoolFailed;

    const cbAllocCI = zvkw.zvk.VkCommandBufferAllocateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = ctx.commandPool,
        .level = zvkw.zvk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = zvkw.max_frames_in_flight,
    };
    result = zvkw.zvk.vkAllocateCommandBuffers(ctx.m_Device, &cbAllocCI, &ctx.commandBuffers);
    if (result != zvkw.zvk.VK_SUCCESS) return error.AllocateCommandBuffersFailed;
}
