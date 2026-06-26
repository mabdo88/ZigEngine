const std = @import("std");
const zvkw = @import("zVulkanContext.zig");
const pipeline = @import("pipeline.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

/// Accumulates debug-draw vertices across one fixed step. Systems append to
/// this (priority < 100) before RenderSystem (priority 100) drains it into
/// the per-frame-in-flight GPU buffer and clears it for the next step.
var verts: std.ArrayListUnmanaged(zvkw.DebugVertex) = .empty;
var verts_allocator: std.mem.Allocator = undefined;

pub fn line(a: @Vector(3, f32), b: @Vector(3, f32), color: @Vector(3, f32)) void {
    verts.append(verts_allocator, .{ .pos = a, .color = color }) catch return;
    verts.append(verts_allocator, .{ .pos = b, .color = color }) catch return;
}

pub fn axes(origin: @Vector(3, f32), scale: f32) void {
    const s: @Vector(3, f32) = @splat(scale);
    line(origin, origin + @Vector(3, f32){ 1, 0, 0 } * s, .{ 1, 0, 0 });
    line(origin, origin + @Vector(3, f32){ 0, 1, 0 } * s, .{ 0, 1, 0 });
    line(origin, origin + @Vector(3, f32){ 0, 0, 1 } * s, .{ 0, 0, 1 });
}

pub fn box(min: @Vector(3, f32), max: @Vector(3, f32), color: @Vector(3, f32)) void {
    const corners = [8]@Vector(3, f32){
        .{ min[0], min[1], min[2] }, .{ max[0], min[1], min[2] },
        .{ max[0], max[1], min[2] }, .{ min[0], max[1], min[2] },
        .{ min[0], min[1], max[2] }, .{ max[0], min[1], max[2] },
        .{ max[0], max[1], max[2] }, .{ min[0], max[1], max[2] },
    };
    const edges = [12][2]u8{
        .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 0 },
        .{ 4, 5 }, .{ 5, 6 }, .{ 6, 7 }, .{ 7, 4 },
        .{ 0, 4 }, .{ 1, 5 }, .{ 2, 6 }, .{ 3, 7 },
    };
    for (edges) |e| line(corners[e[0]], corners[e[1]], color);
}

pub fn sphere(center: @Vector(3, f32), radius: f32, segments: u32, color: @Vector(3, f32)) void {
    const n = @max(segments, 3);
    const two_pi = std.math.pi * 2.0;
    ringLoop(center, radius, n, two_pi, color, .{ 1, 0, 0 }, .{ 0, 1, 0 }); // XY ring
    ringLoop(center, radius, n, two_pi, color, .{ 1, 0, 0 }, .{ 0, 0, 1 }); // XZ ring
    ringLoop(center, radius, n, two_pi, color, .{ 0, 1, 0 }, .{ 0, 0, 1 }); // YZ ring
}

fn ringLoop(center: @Vector(3, f32), radius: f32, n: u32, two_pi: f32, color: @Vector(3, f32), axis_a: @Vector(3, f32), axis_b: @Vector(3, f32)) void {
    var i: u32 = 0;
    var prev = center + axis_a * @as(@Vector(3, f32), @splat(radius));
    while (i < n) : (i += 1) {
        const t = two_pi * @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(n));
        const cur = center + (axis_a * @as(@Vector(3, f32), @splat(radius * @cos(t)))) + (axis_b * @as(@Vector(3, f32), @splat(radius * @sin(t))));
        line(prev, cur, color);
        prev = cur;
    }
}

pub fn createDebugResources(ctx: *zvkw.VulkanContext, allocator: std.mem.Allocator) !void {
    verts_allocator = allocator;
    for (0..zvkw.max_frames_in_flight) |i| {
        const bufferCI = zvkw.zvk.VkBufferCreateInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = zvkw.MAX_DEBUG_VERTICES * @sizeOf(zvkw.DebugVertex),
            .usage = zvkw.zvk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        };
        const allocCI = zvkw.vma.VmaAllocationCreateInfo{
            .flags = zvkw.vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT |
                zvkw.vma.VMA_ALLOCATION_CREATE_MAPPED_BIT,
            .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
        };
        const result = zvkw.vma.vmaCreateBuffer(
            ctx.vmaAllocator,
            @ptrCast(&bufferCI),
            &allocCI,
            @ptrCast(&ctx.debugVertexBuffers[i].buffer),
            &ctx.debugVertexBuffers[i].allocation,
            &ctx.debugVertexBuffers[i].allocInfo,
        );
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateDebugVertexBufferFailed;
    }
}

pub fn destroyDebugResources(ctx: *zvkw.VulkanContext) void {
    for (0..zvkw.max_frames_in_flight) |i| {
        zvkw.vma.vmaDestroyBuffer(ctx.vmaAllocator, @ptrCast(ctx.debugVertexBuffers[i].buffer), ctx.debugVertexBuffers[i].allocation);
    }
    verts.deinit(verts_allocator);
}

pub fn createDebugPipeline(ctx: *zvkw.VulkanContext) !void {
    const spv = try pipeline.loadSpvAligned(ctx.zallocator, "src/shaders/debug.spv");
    defer ctx.zallocator.free(spv);

    const shaderModuleCI = zvkw.zvk.VkShaderModuleCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = spv.len,
        .pCode = @ptrCast(@alignCast(spv)),
    };
    var shaderModule: zvkw.zvk.VkShaderModule = null;
    try check(zvkw.zvk.vkCreateShaderModule(ctx.m_Device, &shaderModuleCI, null, &shaderModule));
    defer zvkw.zvk.vkDestroyShaderModule(ctx.m_Device, shaderModule, null);

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
        .stride = @sizeOf(zvkw.DebugVertex),
        .inputRate = zvkw.zvk.VK_VERTEX_INPUT_RATE_VERTEX,
    };
    const vertexAttribDescs = [2]zvkw.zvk.VkVertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = zvkw.zvk.VK_FORMAT_R32G32B32_SFLOAT, .offset = @offsetOf(zvkw.DebugVertex, "pos") },
        .{ .location = 1, .binding = 0, .format = zvkw.zvk.VK_FORMAT_R32G32B32_SFLOAT, .offset = @offsetOf(zvkw.DebugVertex, "color") },
    };
    const vertexInputCI = zvkw.zvk.VkPipelineVertexInputStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &vertexBindingDesc,
        .vertexAttributeDescriptionCount = 2,
        .pVertexAttributeDescriptions = &vertexAttribDescs,
    };
    const inputAssemblyCI = zvkw.zvk.VkPipelineInputAssemblyStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .topology = zvkw.zvk.VK_PRIMITIVE_TOPOLOGY_LINE_LIST,
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
    // Test against scene depth so lines occlude correctly, but never write
    // depth — debug geometry shouldn't affect the real depth buffer.
    const depthStencilCI = zvkw.zvk.VkPipelineDepthStencilStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = zvkw.zvk.VK_TRUE,
        .depthWriteEnable = zvkw.zvk.VK_FALSE,
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
    // Reuses the main pass's camera UBO descriptor set (set 0, binding 0 =
    // FrameUBO) — debug draw only needs projection/view out of it, no push
    // constants or material/texture sets required.
    if (ctx.debugPipelineLayout == null) {
        const setLayouts = [1]zvkw.zvk.VkDescriptorSetLayout{ctx.uboDescriptorSetLayout};
        const pipelineLayoutCI = zvkw.zvk.VkPipelineLayoutCreateInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 1,
            .pSetLayouts = &setLayouts,
        };
        try check(zvkw.zvk.vkCreatePipelineLayout(ctx.m_Device, &pipelineLayoutCI, null, &ctx.debugPipelineLayout));
    }

    const pipelineRenderingCI = zvkw.zvk.VkPipelineRenderingCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .colorAttachmentCount = 1,
        .pColorAttachmentFormats = @ptrCast(&ctx.colorFormat),
        .depthAttachmentFormat = ctx.depthFormat,
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
        .layout = ctx.debugPipelineLayout,
    };
    try check(zvkw.zvk.vkCreateGraphicsPipelines(ctx.m_Device, null, 1, &pipelineCI, null, &ctx.debugPipeline));
}

pub fn destroyDebugPipeline(ctx: *zvkw.VulkanContext) void {
    zvkw.zvk.vkDestroyPipeline(ctx.m_Device, ctx.debugPipeline, null);
    zvkw.zvk.vkDestroyPipelineLayout(ctx.m_Device, ctx.debugPipelineLayout, null);
}

/// Called once per frame from the main render pass, after the scene draw.
/// Copies this step's accumulated vertices into the GPU buffer for the
/// current frame-in-flight, draws them, then clears the list so the next
/// fixed step starts empty.
pub fn draw(ctx: *zvkw.VulkanContext, cb: zvkw.zvk.VkCommandBuffer) void {
    defer verts.clearRetainingCapacity();
    if (verts.items.len == 0) return;

    const count = @min(@as(u32, @intCast(verts.items.len)), zvkw.MAX_DEBUG_VERTICES);
    const dst = ctx.debugVertexBuffers[ctx.frameIndex].allocInfo.pMappedData.?;
    @memcpy(@as([*]u8, @ptrCast(dst))[0 .. count * @sizeOf(zvkw.DebugVertex)], std.mem.sliceAsBytes(verts.items[0..count]));

    zvkw.zvk.vkCmdBindPipeline(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.debugPipeline);
    zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.debugPipelineLayout, 0, 1, &ctx.uboDescriptorSets[ctx.frameIndex], 0, null);
    const buf = ctx.debugVertexBuffers[ctx.frameIndex].buffer;
    const offset: zvkw.zvk.VkDeviceSize = 0;
    zvkw.zvk.vkCmdBindVertexBuffers(cb, 0, 1, &buf, &offset);
    zvkw.zvk.vkCmdDraw(cb, count, 1, 0, 0);
}
