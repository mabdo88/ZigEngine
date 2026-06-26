const std = @import("std");
const builtin = @import("builtin");
const rgstry = @import("../engine/ecs/entity/registry.zig");
const rs = @import("renderSystem.zig").RenderSystem;
const zvkw = @import("zVulkanContext.zig");
const upload = @import("upload.zig");
const device = @import("device.zig");
const swapchain = @import("swapchain.zig");
const pipeline = @import("pipeline.zig");
const material = @import("material.zig");
const shadow = @import("shadow.zig");
const event = @import("../engine/ecs/event.zig");
const math = @import("../engine/math.zig");
const hotreload = @import("../engine/hotreload.zig");
const log = @import("../engine/log.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

var shader_watcher: ?hotreload.FileWatcher = null;

fn startShaderWatcher(allocator: std.mem.Allocator) void {
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var watcher = hotreload.FileWatcher.init(allocator);
    var any_watched = false;
    for ([_][]const u8{ "src/shaders/slang.spv", "src/shaders/shadow.spv" }) |path| {
        watcher.watch(io, path) catch |e| {
            log.warn(@src(), "hotreload: couldn't watch '{s}': {s}", .{ path, @errorName(e) });
            continue;
        };
        any_watched = true;
    }
    if (!any_watched) {
        watcher.deinit();
        return;
    }
    // Move into the persistent global before start() — the spawned thread
    // captures `&shader_watcher.?`, which must outlive this function's stack
    // frame; starting on the local `watcher` would leave it holding a
    // dangling pointer the moment this function returns.
    shader_watcher = watcher;
    shader_watcher.?.start() catch |e| {
        log.warn(@src(), "hotreload: failed to start watcher thread: {s}", .{@errorName(e)});
        shader_watcher.?.deinit();
        shader_watcher = null;
        return;
    };
}

fn checkShaderHotReload() !void {
    const watcher = if (shader_watcher) |*w| w else return;
    const changed = try watcher.pollChanged();
    defer {
        for (changed) |p| watcher.allocator.free(p);
        watcher.allocator.free(changed);
    }
    if (changed.len == 0) return;

    _ = zvkw.zvk.vkDeviceWaitIdle(zvkw.ctx.m_Device);
    zvkw.zvk.vkDestroyPipeline(zvkw.ctx.m_Device, zvkw.ctx.pipeline, null);
    zvkw.zvk.vkDestroyPipeline(zvkw.ctx.m_Device, zvkw.ctx.shadowPipeline, null);
    try pipeline.createPipeline(&zvkw.ctx);
    try shadow.createShadowPipeline(&zvkw.ctx);
    log.info(@src(), "hotreload: recreated render pipelines", .{});
}

pub fn init(zig_allocator: std.mem.Allocator, title: ?[:0]const u8, WWidth: u16, WHeight: u16, vsync: bool, hot_reload_shaders: bool, reg: *rgstry.Registry, render_system: *rs) !void {
    zvkw.ctx.zallocator = zig_allocator;
    zvkw.ctx.vsync = vsync;
    render_system.* = try rs.initCapacity(&zvkw.ctx, zig_allocator, 256, 64);
    try zvkw.win.init();
    errdefer zvkw.win.terminate();
    zvkw.ctx.m_window = try zvkw.win.create(title.?, WWidth, WHeight, true);
    errdefer zvkw.ctx.m_window.destroy();
    zvkw.ctx.extensions = try zvkw.win.requiredInstanceExtensions(zig_allocator);
    errdefer zig_allocator.free(zvkw.ctx.extensions);

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
        .flags = if (builtin.os.tag == .macos) zvkw.zvk.VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR else 0,
        .pApplicationInfo = &appCI,
        .enabledLayerCount = if (zvkw.enable_validation) 1 else 0,
        .ppEnabledLayerNames = if (zvkw.enable_validation) &zvkw.validationLayers else null,
        .enabledExtensionCount = @intCast(zvkw.ctx.extensions.len),
        .ppEnabledExtensionNames = zvkw.ctx.extensions.ptr,
    };

    const result = zvkw.zvk.vkCreateInstance(&instanceCI, null, &zvkw.ctx.m_instance);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateInstanceFailed;
    errdefer zvkw.zvk.vkDestroyInstance(zvkw.ctx.m_instance, null);

    zvkw.ctx.m_surface = try zvkw.ctx.m_window.createSurface(zvkw.ctx.m_instance);
    errdefer zvkw.zvk.vkDestroySurfaceKHR(zvkw.ctx.m_instance, zvkw.ctx.m_surface, null);

    device.setupDebugMessenger(&zvkw.ctx);
    errdefer if (zvkw.enable_validation) {
        if (zvkw.ctx.vkDestroyDebugUtilsMessengerEXT) |destroyFn| {
            destroyFn(zvkw.ctx.m_instance, zvkw.ctx.m_debugMessenger, null);
        }
    };

    try device.pickPhysicalDevice(&zvkw.ctx);
    try device.createLogicalDevice(&zvkw.ctx);
    errdefer zvkw.zvk.vkDestroyDevice(zvkw.ctx.m_Device, null);

    try device.createAllocator(&zvkw.ctx);
    errdefer zvkw.vma.vmaDestroyAllocator(zvkw.ctx.vmaAllocator);

    try swapchain.createSwapchain(&zvkw.ctx);
    errdefer {
        for (zvkw.ctx.swapChainImageViews) |view| {
            zvkw.zvk.vkDestroyImageView(zvkw.ctx.m_Device, view, null);
        }
        zvkw.ctx.zallocator.free(zvkw.ctx.swapChainImageViews);
        zvkw.ctx.zallocator.free(zvkw.ctx.swapChainImages);
        zvkw.zvk.vkDestroySwapchainKHR(zvkw.ctx.m_Device, zvkw.ctx.swapChain, null);
    }

    try swapchain.createDepthImage(&zvkw.ctx);
    errdefer {
        zvkw.zvk.vkDestroyImageView(zvkw.ctx.m_Device, zvkw.ctx.depthImageView, null);
        zvkw.vma.vmaDestroyImage(zvkw.ctx.vmaAllocator, @ptrCast(zvkw.ctx.depthImage), zvkw.ctx.depthImageAllocation);
    }

    try swapchain.createSyncObjects(&zvkw.ctx);
    errdefer {
        for (0..zvkw.max_frames_in_flight) |i| {
            zvkw.zvk.vkDestroyFence(zvkw.ctx.m_Device, zvkw.ctx.fences[i], null);
            zvkw.zvk.vkDestroySemaphore(zvkw.ctx.m_Device, zvkw.ctx.imageAcquiredSemaphores[i], null);
        }
        for (zvkw.ctx.renderCompleteSemaphores) |semaphore| {
            zvkw.zvk.vkDestroySemaphore(zvkw.ctx.m_Device, semaphore, null);
        }
        zvkw.ctx.zallocator.free(zvkw.ctx.renderCompleteSemaphores);
    }

    try swapchain.createCommandPool(&zvkw.ctx);
    errdefer zvkw.zvk.vkDestroyCommandPool(zvkw.ctx.m_Device, zvkw.ctx.commandPool, null);

    try pipeline.createDescriptorSetLayout(&zvkw.ctx);
    errdefer {
        zvkw.zvk.vkDestroyDescriptorSetLayout(zvkw.ctx.m_Device, zvkw.ctx.bindlessDescriptorSetLayout, null);
        zvkw.zvk.vkDestroyDescriptorSetLayout(zvkw.ctx.m_Device, zvkw.ctx.uboDescriptorSetLayout, null);
    }

    try pipeline.createPipeline(&zvkw.ctx);
    errdefer {
        zvkw.zvk.vkDestroyPipeline(zvkw.ctx.m_Device, zvkw.ctx.pipeline, null);
        zvkw.zvk.vkDestroyPipelineLayout(zvkw.ctx.m_Device, zvkw.ctx.pipelineLayout, null);
    }

    try pipeline.createDescriptorPool(&zvkw.ctx);
    errdefer zvkw.zvk.vkDestroyDescriptorPool(zvkw.ctx.m_Device, zvkw.ctx.descriptorPool, null);

    try pipeline.createDescriptorSets(&zvkw.ctx);
    try pipeline.createShaderDataBuffers(&zvkw.ctx);
    errdefer {
        for (0..zvkw.max_frames_in_flight) |i| {
            zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(zvkw.ctx.shaderDataBuffers[i].buffer), zvkw.ctx.shaderDataBuffers[i].allocation);
        }
    }

    try pipeline.createSampler(&zvkw.ctx);
    errdefer zvkw.zvk.vkDestroySampler(zvkw.ctx.m_Device, zvkw.ctx.bindlessSampler, null);

    try material.createDefaultTexture(&zvkw.ctx);
    errdefer {
        if (zvkw.ctx.textureCount > 0) {
            zvkw.zvk.vkDestroyImageView(zvkw.ctx.m_Device, zvkw.ctx.textureSlots[0].view, null);
            zvkw.vma.vmaDestroyImage(zvkw.ctx.vmaAllocator, @ptrCast(zvkw.ctx.textureSlots[0].image), zvkw.ctx.textureSlots[0].allocation);
        }
    }

    try material.createMaterialBuffer(&zvkw.ctx);
    errdefer material.destroyMaterialBuffer(&zvkw.ctx);
    pipeline.writeMaterialDescriptor(&zvkw.ctx);

    try shadow.createShadowResources(&zvkw.ctx);
    errdefer shadow.destroyShadowResources(&zvkw.ctx);

    try shadow.createShadowPipeline(&zvkw.ctx);
    errdefer shadow.destroyShadowPipeline(&zvkw.ctx);

    pipeline.writeShadowDescriptor(&zvkw.ctx);

    if (hot_reload_shaders) startShaderWatcher(zig_allocator);

    try reg.events.subscribe(.entity_destroyed, @ptrCast(render_system), rs.onEntityDestroyed);
}

pub fn deinit(reg: *rgstry.Registry, render_system: *rs) void {
    _ = reg;
    if (shader_watcher) |*w| {
        w.deinit();
        shader_watcher = null;
    }
    _ = zvkw.zvk.vkDeviceWaitIdle(zvkw.ctx.m_Device);
    shadow.destroyShadowPipeline(&zvkw.ctx);
    shadow.destroyShadowResources(&zvkw.ctx);
    material.destroyMaterialBuffer(&zvkw.ctx);
    zvkw.ctx.zallocator.free(zvkw.ctx.extensions);
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
    zvkw.ctx.m_window.destroy();
    zvkw.win.terminate();
}

pub fn render(matrices: math.CameraMatrices, light: math.SceneLight, reg: *rgstry.Registry, render_system: *rs, dt: f32) !void {
    try checkShaderHotReload();

    try check(zvkw.zvk.vkWaitForFences(zvkw.ctx.m_Device, 1, &zvkw.ctx.fences[zvkw.ctx.frameIndex], zvkw.zvk.VK_TRUE, std.math.maxInt(u64)));

    if (zvkw.win.wasResized()) {
        zvkw.win.clearResized();
        const fb = zvkw.ctx.m_window.framebufferSize();
        zvkw.ctx.m_window.width = fb.width;
        zvkw.ctx.m_window.height = fb.height;
        try swapchain.recreateSwapchain(&zvkw.ctx);
    }

    const acquireResult = zvkw.zvk.vkAcquireNextImageKHR(zvkw.ctx.m_Device, zvkw.ctx.swapChain, std.math.maxInt(u64), zvkw.ctx.imageAcquiredSemaphores[zvkw.ctx.frameIndex], null, &zvkw.ctx.imageIndex);
    if (acquireResult == zvkw.zvk.VK_ERROR_OUT_OF_DATE_KHR) {
        try swapchain.recreateSwapchain(&zvkw.ctx);
        return;
    } else if (acquireResult != zvkw.zvk.VK_SUCCESS and acquireResult != zvkw.zvk.VK_SUBOPTIMAL_KHR) {
        return error.AcquireImageFailed;
    }
    try check(zvkw.zvk.vkResetFences(zvkw.ctx.m_Device, 1, &zvkw.ctx.fences[zvkw.ctx.frameIndex]));

    const light_view_proj = math.directionalLightViewProj(light);
    const uboData = zvkw.FrameUBO{
        .projection = matrices.projection,
        .view = matrices.view,
        .light_view_proj = light_view_proj,
        .light_dir = .{ light.direction[0], light.direction[1], light.direction[2], 0.0 },
        .light_color = .{ light.color[0], light.color[1], light.color[2], light.ambient },
        .camera_pos = .{ matrices.position[0], matrices.position[1], matrices.position[2], 0.0 },
    };
    @memcpy(@as([*]u8, @ptrCast(zvkw.ctx.shaderDataBuffers[zvkw.ctx.frameIndex].allocInfo.pMappedData.?))[0..@sizeOf(zvkw.FrameUBO)], std.mem.asBytes(&uboData));
    const cb = zvkw.ctx.commandBuffers[zvkw.ctx.frameIndex];
    try check(zvkw.zvk.vkResetCommandBuffer(cb, 0));

    const cbBI = zvkw.zvk.VkCommandBufferBeginInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = zvkw.zvk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try check(zvkw.zvk.vkBeginCommandBuffer(cb, &cbBI));

    const shadowToAttachmentBarrier = zvkw.zvk.VkImageMemoryBarrier2{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
        .srcAccessMask = zvkw.zvk.VK_ACCESS_2_SHADER_READ_BIT,
        .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT,
        .dstAccessMask = zvkw.zvk.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        .oldLayout = zvkw.ctx.shadowImageLayout,
        .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        .image = zvkw.ctx.shadowImage,
        .subresourceRange = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_DEPTH_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
    };
    const shadowToAttachmentDep = zvkw.zvk.VkDependencyInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &shadowToAttachmentBarrier,
    };
    zvkw.zvk.vkCmdPipelineBarrier2(cb, &shadowToAttachmentDep);
    zvkw.ctx.shadowImageLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL;

    const shadowAttachmentInfo = zvkw.zvk.VkRenderingAttachmentInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = zvkw.ctx.shadowImageView,
        .imageLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        .loadOp = zvkw.zvk.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = zvkw.zvk.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = .{ .depthStencil = .{ .depth = 1.0, .stencil = 0 } },
    };
    const shadowRenderingInfo = zvkw.zvk.VkRenderingInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = zvkw.SHADOW_MAP_SIZE, .height = zvkw.SHADOW_MAP_SIZE } },
        .layerCount = 1,
        .colorAttachmentCount = 0,
        .pDepthAttachment = &shadowAttachmentInfo,
    };
    zvkw.zvk.vkCmdBeginRendering(cb, &shadowRenderingInfo);
    const shadowVp = zvkw.zvk.VkViewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(zvkw.SHADOW_MAP_SIZE),
        .height = @floatFromInt(zvkw.SHADOW_MAP_SIZE),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    zvkw.zvk.vkCmdSetViewport(cb, 0, 1, &shadowVp);
    const shadowScissor = zvkw.zvk.VkRect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{ .width = zvkw.SHADOW_MAP_SIZE, .height = zvkw.SHADOW_MAP_SIZE },
    };
    zvkw.zvk.vkCmdSetScissor(cb, 0, 1, &shadowScissor);
    zvkw.zvk.vkCmdBindPipeline(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, zvkw.ctx.shadowPipeline);
    try render_system.updateShadow(reg, cb, light_view_proj);
    zvkw.zvk.vkCmdEndRendering(cb);

    const shadowToReadBarrier = zvkw.zvk.VkImageMemoryBarrier2{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT,
        .srcAccessMask = zvkw.zvk.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
        .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
        .dstAccessMask = zvkw.zvk.VK_ACCESS_2_SHADER_READ_BIT,
        .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL,
        .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .image = zvkw.ctx.shadowImage,
        .subresourceRange = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_DEPTH_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
    };
    const shadowToReadDep = zvkw.zvk.VkDependencyInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &shadowToReadBarrier,
    };
    zvkw.zvk.vkCmdPipelineBarrier2(cb, &shadowToReadDep);
    zvkw.ctx.shadowImageLayout = zvkw.zvk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

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
    try render_system.update(reg, cb, dt);
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
        try swapchain.recreateSwapchain(&zvkw.ctx);
    } else if (presentResult != zvkw.zvk.VK_SUCCESS) {
        return error.PresentImageFailed;
    }
    zvkw.ctx.frameIndex = (zvkw.ctx.frameIndex + 1) % zvkw.max_frames_in_flight;
}

pub const UploadBatch = upload.UploadBatch;

pub fn beginUploadBatch(allocator: std.mem.Allocator) !UploadBatch {
    return upload.UploadBatch.begin(&zvkw.ctx, allocator);
}

pub fn uploadTextureBatched(batch: *upload.UploadBatch, pixels: []const u8, width: u32, height: u32) !zvkw.TextureHandle {
    return material.uploadTextureBatched(&zvkw.ctx, batch, pixels, width, height);
}

pub fn uploadTexture(pixels: []const u8, width: u32, height: u32) !zvkw.TextureHandle {
    return material.uploadTexture(&zvkw.ctx, pixels, width, height);
}

pub fn registerMaterial(metallic: f32, roughness: f32, albedo_texture_index: zvkw.TextureHandle) !zvkw.MaterialHandle {
    return material.registerMaterial(&zvkw.ctx, metallic, roughness, albedo_texture_index);
}

pub fn shouldClose() bool {
    return zvkw.ctx.m_window.shouldClose();
}

pub fn pollEvents() void {
    zvkw.win.pollEvents();
}

pub fn windowPtr() *zvkw.win.Window {
    return &zvkw.ctx.m_window;
}

pub fn aspectRatio() f32 {
    const h = zvkw.ctx.swapChainExtent.height;
    if (h == 0) return 1.0;
    return @as(f32, @floatFromInt(zvkw.ctx.swapChainExtent.width)) / @as(f32, @floatFromInt(h));
}
