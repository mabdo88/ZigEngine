const std = @import("std");
const builtin = @import("builtin");
const zvkw = @import("renderer/zVulkanContext.zig");
const device = @import("renderer/device.zig");
const swapchain = @import("renderer/swapchain.zig");
const pipeline = @import("renderer/pipeline.zig");
const win = @import("platform/window.zig");
const flecs = @import("flecs.zig");
const components = @import("components.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub fn init(allocator: std.mem.Allocator, window: *win.Window) !zvkw.VulkanContext {
    var ctx: zvkw.VulkanContext = .{};
    ctx.zallocator = allocator;
    ctx.m_window = window.*;

    ctx.extensions = try win.requiredInstanceExtensions(allocator);
    errdefer allocator.free(ctx.extensions);

    const appCI = zvkw.zvk.VkApplicationInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "ZigEngine",
        .applicationVersion = zvkw.zvk.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "ZigEngine",
        .engineVersion = zvkw.zvk.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = zvkw.zvk.VK_API_VERSION_1_3,
    };
    const instanceCI = zvkw.zvk.VkInstanceCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .flags = if (builtin.os.tag == .macos) zvkw.zvk.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR else 0,
        .pApplicationInfo = &appCI,
        .enabledLayerCount = if (zvkw.enable_validation) 1 else 0,
        .ppEnabledLayerNames = if (zvkw.enable_validation) &zvkw.validationLayers else null,
        .enabledExtensionCount = @intCast(ctx.extensions.len),
        .ppEnabledExtensionNames = ctx.extensions.ptr,
    };

    try check(zvkw.zvk.vkCreateInstance(&instanceCI, null, &ctx.m_instance));
    errdefer zvkw.zvk.vkDestroyInstance(ctx.m_instance, null);

    ctx.m_surface = try ctx.m_window.createSurface(ctx.m_instance);
    errdefer zvkw.zvk.vkDestroySurfaceKHR(ctx.m_instance, ctx.m_surface, null);

    device.setupDebugMessenger(&ctx);
    errdefer if (zvkw.enable_validation) {
        if (ctx.vkDestroyDebugUtilsMessengerEXT) |destroyFn| {
            destroyFn(ctx.m_instance, ctx.m_debugMessenger, null);
        }
    };

    try device.pickPhysicalDevice(&ctx);
    try device.createLogicalDevice(&ctx);
    errdefer zvkw.zvk.vkDestroyDevice(ctx.m_Device, null);

    try device.createAllocator(&ctx);
    errdefer zvkw.vma.vmaDestroyAllocator(ctx.vmaAllocator);

    try swapchain.createSwapchain(&ctx);
    errdefer {
        for (ctx.swapChainImageViews) |view| {
            zvkw.zvk.vkDestroyImageView(ctx.m_Device, view, null);
        }
        ctx.zallocator.free(ctx.swapChainImageViews);
        ctx.zallocator.free(ctx.swapChainImages);
        zvkw.zvk.vkDestroySwapchainKHR(ctx.m_Device, ctx.swapChain, null);
    }

    try swapchain.createDepthImage(&ctx);
    errdefer {
        zvkw.zvk.vkDestroyImageView(ctx.m_Device, ctx.depthImageView, null);
        zvkw.vma.vmaDestroyImage(ctx.vmaAllocator, @ptrCast(ctx.depthImage), ctx.depthImageAllocation);
    }

    try swapchain.createSyncObjects(&ctx);
    errdefer {
        for (0..zvkw.max_frames_in_flight) |i| {
            zvkw.zvk.vkDestroyFence(ctx.m_Device, ctx.fences[i], null);
            zvkw.zvk.vkDestroySemaphore(ctx.m_Device, ctx.imageAcquiredSemaphores[i], null);
        }
        for (ctx.renderCompleteSemaphores) |semaphore| {
            zvkw.zvk.vkDestroySemaphore(ctx.m_Device, semaphore, null);
        }
        ctx.zallocator.free(ctx.renderCompleteSemaphores);
    }

    try swapchain.createCommandPool(&ctx);
    errdefer zvkw.zvk.vkDestroyCommandPool(ctx.m_Device, ctx.commandPool, null);

    try pipeline.createDescriptorSetLayout(&ctx);
    errdefer {
        zvkw.zvk.vkDestroyDescriptorSetLayout(ctx.m_Device, ctx.bindlessDescriptorSetLayout, null);
        zvkw.zvk.vkDestroyDescriptorSetLayout(ctx.m_Device, ctx.uboDescriptorSetLayout, null);
    }

    try pipeline.createPipeline(&ctx);
    errdefer {
        zvkw.zvk.vkDestroyPipeline(ctx.m_Device, ctx.pipeline, null);
        zvkw.zvk.vkDestroyPipelineLayout(ctx.m_Device, ctx.pipelineLayout, null);
    }

    try pipeline.createDescriptorPool(&ctx);
    errdefer zvkw.zvk.vkDestroyDescriptorPool(ctx.m_Device, ctx.descriptorPool, null);

    try pipeline.createDescriptorSets(&ctx);
    try pipeline.createShaderDataBuffers(&ctx);
    errdefer {
        for (0..zvkw.max_frames_in_flight) |i| {
            zvkw.vma.vmaDestroyBuffer(ctx.vmaAllocator, @ptrCast(ctx.shaderDataBuffers[i].buffer), ctx.shaderDataBuffers[i].allocation);
        }
    }

    try pipeline.createSampler(&ctx);
    errdefer zvkw.zvk.vkDestroySampler(ctx.m_Device, ctx.bindlessSampler, null);

    return ctx;
}

pub fn deinit(ctx: *zvkw.VulkanContext) void {
    _ = zvkw.zvk.vkDeviceWaitIdle(ctx.m_Device);
    ctx.zallocator.free(ctx.extensions);

    for (0..ctx.textureCount) |i| {
        zvkw.zvk.vkDestroyImageView(ctx.m_Device, ctx.textureSlots[i].view, null);
        zvkw.vma.vmaDestroyImage(ctx.vmaAllocator, @ptrCast(ctx.textureSlots[i].image), ctx.textureSlots[i].allocation);
    }

    zvkw.zvk.vkDestroySampler(ctx.m_Device, ctx.bindlessSampler, null);
    zvkw.zvk.vkDestroyDescriptorPool(ctx.m_Device, ctx.descriptorPool, null);
    zvkw.zvk.vkDestroyDescriptorSetLayout(ctx.m_Device, ctx.uboDescriptorSetLayout, null);
    zvkw.zvk.vkDestroyDescriptorSetLayout(ctx.m_Device, ctx.bindlessDescriptorSetLayout, null);
    zvkw.zvk.vkDestroyPipeline(ctx.m_Device, ctx.pipeline, null);
    zvkw.zvk.vkDestroyPipelineLayout(ctx.m_Device, ctx.pipelineLayout, null);

    for (ctx.swapChainImageViews) |view| {
        zvkw.zvk.vkDestroyImageView(ctx.m_Device, view, null);
    }
    ctx.zallocator.free(ctx.swapChainImageViews);
    ctx.zallocator.free(ctx.swapChainImages);
    zvkw.zvk.vkDestroySwapchainKHR(ctx.m_Device, ctx.swapChain, null);

    zvkw.zvk.vkDestroyImageView(ctx.m_Device, ctx.depthImageView, null);
    zvkw.vma.vmaDestroyImage(ctx.vmaAllocator, @ptrCast(ctx.depthImage), ctx.depthImageAllocation);

    for (0..zvkw.max_frames_in_flight) |i| {
        zvkw.vma.vmaDestroyBuffer(ctx.vmaAllocator, @ptrCast(ctx.shaderDataBuffers[i].buffer), ctx.shaderDataBuffers[i].allocation);
    }

    zvkw.vma.vmaDestroyAllocator(ctx.vmaAllocator);
    zvkw.zvk.vkDestroyCommandPool(ctx.m_Device, ctx.commandPool, null);

    for (0..zvkw.max_frames_in_flight) |i| {
        zvkw.zvk.vkDestroyFence(ctx.m_Device, ctx.fences[i], null);
        zvkw.zvk.vkDestroySemaphore(ctx.m_Device, ctx.imageAcquiredSemaphores[i], null);
    }
    for (ctx.renderCompleteSemaphores) |semaphore| {
        zvkw.zvk.vkDestroySemaphore(ctx.m_Device, semaphore, null);
    }
    ctx.zallocator.free(ctx.renderCompleteSemaphores);

    zvkw.zvk.vkDestroyDevice(ctx.m_Device, null);
    zvkw.zvk.vkDestroySurfaceKHR(ctx.m_instance, ctx.m_surface, null);

    if (zvkw.enable_validation) {
        if (ctx.vkDestroyDebugUtilsMessengerEXT) |destroyFn| {
            destroyFn(ctx.m_instance, ctx.m_debugMessenger, null);
        }
    }

    zvkw.zvk.vkDestroyInstance(ctx.m_instance, null);
}

pub const RenderSystemCtx = struct {
    vk_ctx: *zvkw.VulkanContext,
};

fn renderSystem(it: [*c]flecs.c.ecs_iter_t) callconv(.c) void {
    const rctx: *RenderSystemCtx = @ptrCast(@alignCast(it.*.ctx));
    const vp: *components.ViewProjComponent = @ptrCast(@alignCast(flecs.c.ecs_field_w_size(it, @sizeOf(components.ViewProjComponent), 0)));

    const uboData = zvkw.FrameUBO{
        .projection = @bitCast(vp.proj),
        .view = @bitCast(vp.view),
    };
    const dst = @as([*]u8, @ptrCast(rctx.vk_ctx.shaderDataBuffers[rctx.vk_ctx.frameIndex].allocInfo.pMappedData.?))[0..@sizeOf(zvkw.FrameUBO)];
    @memcpy(dst, std.mem.asBytes(&uboData));
}

pub fn registerRenderSystem(ecs_world: *flecs.World, rctx: *RenderSystemCtx, viewproj_id: flecs.Entity) flecs.Entity {
    return ecs_world.systemWithTerms("RenderSystem", flecs.onStore(), &.{
        .{ .id = viewproj_id, .inout = 4, .is_singleton = true },
    }, renderSystem, rctx);
}

pub fn frame(ctx: *zvkw.VulkanContext, ecs_world: *flecs.World, render_system_id: flecs.Entity) !void {
    _ = flecs.c.ecs_run(ecs_world.world, render_system_id, 0, null);

    try check(zvkw.zvk.vkWaitForFences(ctx.m_Device, 1, &ctx.fences[ctx.frameIndex], zvkw.zvk.VK_TRUE, std.math.maxInt(u64)));

    if (win.wasResized()) {
        win.clearResized();
        const fb = ctx.m_window.framebufferSize();
        ctx.m_window.width = fb.width;
        ctx.m_window.height = fb.height;
        try swapchain.recreateSwapchain(ctx);
    }

    const acquireResult = zvkw.zvk.vkAcquireNextImageKHR(ctx.m_Device, ctx.swapChain, std.math.maxInt(u64), ctx.imageAcquiredSemaphores[ctx.frameIndex], null, &ctx.imageIndex);
    if (acquireResult == zvkw.zvk.VK_ERROR_OUT_OF_DATE_KHR) {
        try swapchain.recreateSwapchain(ctx);
        return;
    } else if (acquireResult != zvkw.zvk.VK_SUCCESS and acquireResult != zvkw.zvk.VK_SUBOPTIMAL_KHR) {
        return error.AcquireImageFailed;
    }
    try check(zvkw.zvk.vkResetFences(ctx.m_Device, 1, &ctx.fences[ctx.frameIndex]));

    const cb = ctx.commandBuffers[ctx.frameIndex];
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
            .image = ctx.swapChainImages[ctx.imageIndex],
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
            .image = ctx.depthImage,
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
        .imageView = ctx.swapChainImageViews[ctx.imageIndex],
        .imageLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        .loadOp = zvkw.zvk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = zvkw.zvk.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{ .color = .{ .float32 = .{ 0.0, 0.0, 0.0, 1.0 } } },
    };
    const depthAttachmentInfo = zvkw.zvk.VkRenderingAttachmentInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = ctx.depthImageView,
        .imageLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        .loadOp = zvkw.zvk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = zvkw.zvk.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .clearValue = .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
    };
    const renderingInfo = zvkw.zvk.VkRenderingInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = ctx.swapChainExtent },
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &colorAttachmentInfo,
        .pDepthAttachment = &depthAttachmentInfo,
    };
    zvkw.zvk.vkCmdBeginRendering(cb, &renderingInfo);

    const vp = zvkw.zvk.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(ctx.swapChainExtent.width),
        .height = @floatFromInt(ctx.swapChainExtent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    zvkw.zvk.vkCmdSetViewport(cb, 0, 1, &vp);

    const scissor = zvkw.zvk.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = ctx.swapChainExtent,
    };
    zvkw.zvk.vkCmdSetScissor(cb, 0, 1, &scissor);

    zvkw.zvk.vkCmdBindPipeline(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.pipeline);
    zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.pipelineLayout, 0, 1, &ctx.uboDescriptorSets[ctx.frameIndex], 0, null);
    zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.pipelineLayout, 1, 1, &ctx.bindlessDescriptorSet, 0, null);

    zvkw.zvk.vkCmdEndRendering(cb);

    const barrierPresent = zvkw.zvk.VkImageMemoryBarrier2{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = zvkw.zvk.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstAccessMask = 0,
        .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .image = ctx.swapChainImages[ctx.imageIndex],
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
        .pWaitSemaphores = &ctx.imageAcquiredSemaphores[ctx.frameIndex],
        .pWaitDstStageMask = &waitStages,
        .commandBufferCount = 1,
        .pCommandBuffers = &cb,
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &ctx.renderCompleteSemaphores[ctx.imageIndex],
    };
    try check(zvkw.zvk.vkQueueSubmit(ctx.queue, 1, &submitInfo, ctx.fences[ctx.frameIndex]));

    const presentInfo = zvkw.zvk.VkPresentInfoKHR{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &ctx.renderCompleteSemaphores[ctx.imageIndex],
        .swapchainCount = 1,
        .pSwapchains = &ctx.swapChain,
        .pImageIndices = &ctx.imageIndex,
    };
    const presentResult = zvkw.zvk.vkQueuePresentKHR(ctx.queue, &presentInfo);
    if (presentResult == zvkw.zvk.VK_ERROR_OUT_OF_DATE_KHR or presentResult == zvkw.zvk.VK_SUBOPTIMAL_KHR) {
        try swapchain.recreateSwapchain(ctx);
    } else if (presentResult != zvkw.zvk.VK_SUCCESS) {
        return error.PresentImageFailed;
    }

    ctx.frameIndex = (ctx.frameIndex + 1) % zvkw.max_frames_in_flight;
}
