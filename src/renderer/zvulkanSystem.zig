const std = @import("std");
const builtin = @import("builtin");
const rgstry = @import("../engine/registry.zig");
const rs = @import("renderSystem.zig").RenderSystem;
const cs = @import("cameraSystem.zig");
const zvkw = @import("zVulkanContext.zig");
const upload = @import("upload.zig");
const device = @import("device.zig");
const swapchain = @import("swapchain.zig");
const pipeline = @import("pipeline.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub fn init(zig_allocator: std.mem.Allocator, title: ?[:0]const u8, WWidth: u16, WHeight: u16, reg: *rgstry.Registry, render_system: *rs) !void {
    zvkw.ctx.zallocator = zig_allocator;
    render_system.* = rs.init(zig_allocator);
    const windowCI = zvkw.zvk.VkWindowCreateInfo{
        .title = title.?,
        .width = WWidth,
        .height = WHeight,
        .resizable = true,
    };
    try zvkw.zvk.vkCreateWindow(windowCI, &zvkw.ctx.m_window);
    zvkw.ctx.extensions = try zvkw.zvk.vkGetRequiredInstanceExtensions(zig_allocator);

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
        .ppEnabledExtensionNames = zvkw.ctx.extensions.ptr,
    };

    const result = zvkw.zvk.vkCreateInstance(&instanceCI, null, &zvkw.ctx.m_instance);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateInstanceFailed;
    zvkw.ctx.m_surface = try zvkw.zvk.vkCreateWindowSurface(&zvkw.ctx.m_window, zvkw.ctx.m_instance);
    device.setupDebugMessenger();
    try device.pickPhysicalDevice();
    try device.createLogicalDevice();
    try device.createAllocator();
    try swapchain.createSwapchain();
    try swapchain.createDepthImage();
    try swapchain.createSyncObjects();
    try swapchain.createCommandPool();
    try pipeline.createDescriptorSetLayout();
    try pipeline.createPipeline();
    try pipeline.createDescriptorPool();
    try pipeline.createDescriptorSets();
    try pipeline.createShaderDataBuffers();
    try pipeline.createSampler();
    try pipeline.createDefaultTexture();
    reg.setDestroyHook(@ptrCast(render_system), rs.onEntityDestroyed);
}

pub fn deinit(reg: *rgstry.Registry, render_system: *rs) void {
    _ = zvkw.zvk.vkDeviceWaitIdle(zvkw.ctx.m_Device);
    // Free extensions array
    zvkw.ctx.zallocator.free(zvkw.ctx.extensions);
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
    // Drop the destroy hook before tearing down the GPU mesh map and allocator,
    // so any later destroyEntity (e.g. in World.deinit) can't touch freed state.
    reg.clearDestroyHook();
    // Wait for all in-flight frames to complete before destroying mesh buffers
    for (0..zvkw.max_frames_in_flight) |i| {
        _ = zvkw.zvk.vkWaitForFences(zvkw.ctx.m_Device, 1, &zvkw.ctx.fences[i], zvkw.zvk.VK_TRUE, std.math.maxInt(u64));
    }
    render_system.deinit();
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

pub fn render(matrices: cs.CameraMatrices, reg: *rgstry.Registry, render_system: *rs) !void {
    try check(zvkw.zvk.vkWaitForFences(zvkw.ctx.m_Device, 1, &zvkw.ctx.fences[zvkw.ctx.frameIndex], zvkw.zvk.VK_TRUE, std.math.maxInt(u64)));

    // Window-driven resize: not all WSI platforms report VK_ERROR_OUT_OF_DATE_KHR
    // on resize, so rebuild eagerly when the window reported a size change.
    if (zvkw.zvk.vkWindowResized(&zvkw.ctx.m_window)) {
        zvkw.zvk.vkResetWindowResizedFlag(&zvkw.ctx.m_window);
        try swapchain.recreateSwapchain();
    }

    const acquireResult = zvkw.zvk.vkAcquireNextImageKHR(zvkw.ctx.m_Device, zvkw.ctx.swapChain, std.math.maxInt(u64), zvkw.ctx.imageAcquiredSemaphores[zvkw.ctx.frameIndex], null, &zvkw.ctx.imageIndex);
    if (acquireResult == zvkw.zvk.VK_ERROR_OUT_OF_DATE_KHR) {
        // Surface changed (resize/display change). Rebuild and skip this frame.
        try swapchain.recreateSwapchain();
        return;
    } else if (acquireResult != zvkw.zvk.VK_SUCCESS and acquireResult != zvkw.zvk.VK_SUBOPTIMAL_KHR) {
        return error.AcquireImageFailed;
    }
    // Only reset the fence once we know we'll submit work that signals it,
    // otherwise an early return above would leave it unsignaled and deadlock.
    try check(zvkw.zvk.vkResetFences(zvkw.ctx.m_Device, 1, &zvkw.ctx.fences[zvkw.ctx.frameIndex]));

    const uboData = zvkw.FrameUBO{
        .projection = matrices.projection,
        .view = matrices.view,
    };
    @memcpy(@as([*]u8, @ptrCast(zvkw.ctx.shaderDataBuffers[zvkw.ctx.frameIndex].allocInfo.pMappedData.?))[0..@sizeOf(zvkw.FrameUBO)], std.mem.asBytes(&uboData));
    const cb = zvkw.ctx.commandBuffers[zvkw.ctx.frameIndex];
    try check(zvkw.zvk.vkResetCommandBuffer(cb, 0));

    const cbBI = zvkw.zvk.VkCommandBufferBeginInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = zvkw.zvk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try check(zvkw.zvk.vkBeginCommandBuffer(cb, &cbBI));

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
    try render_system.update(reg, cb);
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
    try check(zvkw.zvk.vkEndCommandBuffer(cb));

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
    try check(zvkw.zvk.vkQueueSubmit(zvkw.ctx.queue, 1, &submitInfo, zvkw.ctx.fences[zvkw.ctx.frameIndex]));

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
        try swapchain.recreateSwapchain();
    } else if (presentResult != zvkw.zvk.VK_SUCCESS) {
        return error.PresentImageFailed;
    }
    zvkw.ctx.frameIndex = (zvkw.ctx.frameIndex + 1) % zvkw.max_frames_in_flight;
}

/// Delegates to pipeline.uploadTextureBatched — kept here for callers that import zvulkanSystem.
pub fn uploadTextureBatched(batch: *upload.UploadBatch, pixels: []const u8, width: u32, height: u32) !zvkw.TextureHandle {
    return pipeline.uploadTextureBatched(batch, pixels, width, height);
}

/// Delegates to pipeline.uploadTexture — kept here for callers that import zvulkanSystem.
pub fn uploadTexture(pixels: []const u8, width: u32, height: u32) !zvkw.TextureHandle {
    return pipeline.uploadTexture(pixels, width, height);
}

pub fn shouldClose() bool {
    return zvkw.zvk.vkWindowShouldClose(&zvkw.ctx.m_window);
}

pub fn pollEvents() void {
    zvkw.zvk.vkPollEvents();
}

/// Current swapchain aspect ratio (width / height), so the camera projection
/// stays correct as the window is resized.
pub fn aspectRatio() f32 {
    const h = zvkw.ctx.swapChainExtent.height;
    if (h == 0) return 1.0;
    return @as(f32, @floatFromInt(zvkw.ctx.swapChainExtent.width)) / @as(f32, @floatFromInt(h));
}
