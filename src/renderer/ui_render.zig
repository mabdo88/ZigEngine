const std = @import("std");
const zvkw = @import("zVulkanContext.zig");
const pipeline = @import("pipeline.zig");
const math = @import("../engine/math.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

const DrawCmd = struct {
    first_vertex: u32,
    vertex_count: u32,
    texture_index: u32,
};

/// Accumulates UI quads across one fixed step, batched by texture — adjacent
/// quads using the same texture extend the last DrawCmd instead of starting
/// a new one, mirroring debug.zig's per-step accumulate-then-drain pattern.
var verts: std.ArrayListUnmanaged(zvkw.UIVertex) = .empty;
var draws: std.ArrayListUnmanaged(DrawCmd) = .empty;
var alloc: std.mem.Allocator = undefined;

/// Emits one screen-space quad. `pos`/`size` are in pixels (top-left
/// origin), `uv_min`/`uv_max` select the texture region, `color` tints (use
/// {1,1,1,1} for an untinted image, an atlas glyph's color for text).
pub fn quad(pos: @Vector(2, f32), size: @Vector(2, f32), uv_min: @Vector(2, f32), uv_max: @Vector(2, f32), color: @Vector(4, f32), texture_index: u32) void {
    const first_vertex: u32 = @intCast(verts.items.len);
    const x0 = pos[0];
    const y0 = pos[1];
    const x1 = pos[0] + size[0];
    const y1 = pos[1] + size[1];
    const quad_verts = [6]zvkw.UIVertex{
        .{ .pos = .{ x0, y0 }, .uv = .{ uv_min[0], uv_min[1] }, .color = color },
        .{ .pos = .{ x1, y0 }, .uv = .{ uv_max[0], uv_min[1] }, .color = color },
        .{ .pos = .{ x1, y1 }, .uv = .{ uv_max[0], uv_max[1] }, .color = color },
        .{ .pos = .{ x0, y0 }, .uv = .{ uv_min[0], uv_min[1] }, .color = color },
        .{ .pos = .{ x1, y1 }, .uv = .{ uv_max[0], uv_max[1] }, .color = color },
        .{ .pos = .{ x0, y1 }, .uv = .{ uv_min[0], uv_max[1] }, .color = color },
    };
    verts.appendSlice(alloc, &quad_verts) catch return;

    if (draws.items.len > 0) {
        const last = &draws.items[draws.items.len - 1];
        if (last.texture_index == texture_index and last.first_vertex + last.vertex_count == first_vertex) {
            last.vertex_count += 6;
            return;
        }
    }
    draws.append(alloc, .{ .first_vertex = first_vertex, .vertex_count = 6, .texture_index = texture_index }) catch return;
}

pub fn createUIResources(ctx: *zvkw.VulkanContext, allocator: std.mem.Allocator) !void {
    alloc = allocator;
    try pipeline.createUIDescriptorSetLayout(ctx);
    try pipeline.createUIDescriptorSets(ctx);

    for (0..zvkw.max_frames_in_flight) |i| {
        const vertexBufferCI = zvkw.zvk.VkBufferCreateInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = zvkw.MAX_UI_VERTICES * @sizeOf(zvkw.UIVertex),
            .usage = zvkw.zvk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        };
        const hostAllocCI = zvkw.vma.VmaAllocationCreateInfo{
            .flags = zvkw.vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT |
                zvkw.vma.VMA_ALLOCATION_CREATE_MAPPED_BIT,
            .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
        };
        try check(zvkw.vma.vmaCreateBuffer(
            ctx.vmaAllocator,
            @ptrCast(&vertexBufferCI),
            &hostAllocCI,
            @ptrCast(&ctx.uiVertexBuffers[i].buffer),
            &ctx.uiVertexBuffers[i].allocation,
            &ctx.uiVertexBuffers[i].allocInfo,
        ));

        const projBufferCI = zvkw.zvk.VkBufferCreateInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = @sizeOf(zvkw.UIProjUBO),
            .usage = zvkw.zvk.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        };
        try check(zvkw.vma.vmaCreateBuffer(
            ctx.vmaAllocator,
            @ptrCast(&projBufferCI),
            &hostAllocCI,
            @ptrCast(&ctx.uiProjBuffers[i].buffer),
            &ctx.uiProjBuffers[i].allocation,
            &ctx.uiProjBuffers[i].allocInfo,
        ));

        const bufferInfo = zvkw.zvk.VkDescriptorBufferInfo{
            .buffer = ctx.uiProjBuffers[i].buffer,
            .offset = 0,
            .range = @sizeOf(zvkw.UIProjUBO),
        };
        const write = zvkw.zvk.VkWriteDescriptorSet{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = ctx.uiProjDescriptorSets[i],
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = zvkw.zvk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .pBufferInfo = &bufferInfo,
        };
        zvkw.zvk.vkUpdateDescriptorSets(ctx.m_Device, 1, &write, 0, null);
    }
}

pub fn destroyUIResources(ctx: *zvkw.VulkanContext) void {
    for (0..zvkw.max_frames_in_flight) |i| {
        zvkw.vma.vmaDestroyBuffer(ctx.vmaAllocator, @ptrCast(ctx.uiVertexBuffers[i].buffer), ctx.uiVertexBuffers[i].allocation);
        zvkw.vma.vmaDestroyBuffer(ctx.vmaAllocator, @ptrCast(ctx.uiProjBuffers[i].buffer), ctx.uiProjBuffers[i].allocation);
    }
    zvkw.zvk.vkDestroyDescriptorSetLayout(ctx.m_Device, ctx.uiProjDescriptorSetLayout, null);
    verts.deinit(alloc);
    draws.deinit(alloc);
}

pub fn createUIPipeline(ctx: *zvkw.VulkanContext) !void {
    const spv = try pipeline.loadSpvAligned(ctx.zallocator, "src/shaders/ui.spv");
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
        .stride = @sizeOf(zvkw.UIVertex),
        .inputRate = zvkw.zvk.VK_VERTEX_INPUT_RATE_VERTEX,
    };
    const vertexAttribDescs = [3]zvkw.zvk.VkVertexInputAttributeDescription{
        .{ .location = 0, .binding = 0, .format = zvkw.zvk.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(zvkw.UIVertex, "pos") },
        .{ .location = 1, .binding = 0, .format = zvkw.zvk.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(zvkw.UIVertex, "uv") },
        .{ .location = 2, .binding = 0, .format = zvkw.zvk.VK_FORMAT_R32G32B32A32_SFLOAT, .offset = @offsetOf(zvkw.UIVertex, "color") },
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
    // UI is a flat 2D overlay drawn last — no depth test/write against the
    // scene's real depth buffer.
    const depthStencilCI = zvkw.zvk.VkPipelineDepthStencilStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        .depthTestEnable = zvkw.zvk.VK_FALSE,
        .depthWriteEnable = zvkw.zvk.VK_FALSE,
    };
    const colorBlendAttachment = zvkw.zvk.VkPipelineColorBlendAttachmentState{
        .blendEnable = zvkw.zvk.VK_TRUE,
        .srcColorBlendFactor = zvkw.zvk.VK_BLEND_FACTOR_SRC_ALPHA,
        .dstColorBlendFactor = zvkw.zvk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .colorBlendOp = zvkw.zvk.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = zvkw.zvk.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = zvkw.zvk.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        .alphaBlendOp = zvkw.zvk.VK_BLEND_OP_ADD,
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
        .stageFlags = zvkw.zvk.VK_SHADER_STAGE_FRAGMENT_BIT,
        .offset = 0,
        .size = @sizeOf(u32),
    };
    if (ctx.uiPipelineLayout == null) {
        // set 0 = UI's own ortho-projection UBO; set 1 = the main pass's
        // bindless texture array (reused as-is — UI never writes to
        // bindings 1/2 of that set, only samples binding 0).
        const setLayouts = [2]zvkw.zvk.VkDescriptorSetLayout{
            ctx.uiProjDescriptorSetLayout,
            ctx.bindlessDescriptorSetLayout,
        };
        const pipelineLayoutCI = zvkw.zvk.VkPipelineLayoutCreateInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .setLayoutCount = 2,
            .pSetLayouts = &setLayouts,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &pushConstantRange,
        };
        try check(zvkw.zvk.vkCreatePipelineLayout(ctx.m_Device, &pipelineLayoutCI, null, &ctx.uiPipelineLayout));
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
        .layout = ctx.uiPipelineLayout,
    };
    try check(zvkw.zvk.vkCreateGraphicsPipelines(ctx.m_Device, null, 1, &pipelineCI, null, &ctx.uiPipeline));
}

pub fn destroyUIPipeline(ctx: *zvkw.VulkanContext) void {
    zvkw.zvk.vkDestroyPipeline(ctx.m_Device, ctx.uiPipeline, null);
    zvkw.zvk.vkDestroyPipelineLayout(ctx.m_Device, ctx.uiPipelineLayout, null);
}

/// Called once per frame from the main render pass, after the 3D scene (and
/// debug draw) so UI always overlays on top. Copies this step's accumulated
/// quads into the current frame-in-flight's GPU buffer, issues one draw per
/// texture-batched DrawCmd, then clears both lists for the next step.
pub fn draw(ctx: *zvkw.VulkanContext, cb: zvkw.zvk.VkCommandBuffer) void {
    defer {
        verts.clearRetainingCapacity();
        draws.clearRetainingCapacity();
    }
    if (draws.items.len == 0) return;

    const count = @min(@as(u32, @intCast(verts.items.len)), zvkw.MAX_UI_VERTICES);
    const vertDst = ctx.uiVertexBuffers[ctx.frameIndex].allocInfo.pMappedData.?;
    @memcpy(@as([*]u8, @ptrCast(vertDst))[0 .. count * @sizeOf(zvkw.UIVertex)], std.mem.sliceAsBytes(verts.items[0..count]));

    const projData = zvkw.UIProjUBO{
        .projection = math.orthoUIScreen(
            @floatFromInt(ctx.swapChainExtent.width),
            @floatFromInt(ctx.swapChainExtent.height),
        ),
    };
    const projDst = ctx.uiProjBuffers[ctx.frameIndex].allocInfo.pMappedData.?;
    @memcpy(@as([*]u8, @ptrCast(projDst))[0..@sizeOf(zvkw.UIProjUBO)], std.mem.asBytes(&projData));

    zvkw.zvk.vkCmdBindPipeline(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.uiPipeline);
    const sets = [2]zvkw.zvk.VkDescriptorSet{ ctx.uiProjDescriptorSets[ctx.frameIndex], ctx.bindlessDescriptorSet };
    zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, ctx.uiPipelineLayout, 0, 2, &sets, 0, null);
    const buf = ctx.uiVertexBuffers[ctx.frameIndex].buffer;
    const offset: zvkw.zvk.VkDeviceSize = 0;
    zvkw.zvk.vkCmdBindVertexBuffers(cb, 0, 1, &buf, &offset);

    for (draws.items) |d| {
        if (d.first_vertex >= count) continue;
        const vc = @min(d.vertex_count, count - d.first_vertex);
        const texIndex = d.texture_index;
        zvkw.zvk.vkCmdPushConstants(cb, ctx.uiPipelineLayout, zvkw.zvk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(u32), &texIndex);
        zvkw.zvk.vkCmdDraw(cb, vc, 1, d.first_vertex, 0);
    }
}
