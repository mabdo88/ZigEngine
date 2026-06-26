const std = @import("std");
const zvkw = @import("zVulkanContext.zig");
const pipeline = @import("pipeline.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub fn createShadowResources(ctx: *zvkw.VulkanContext) !void {
    const imageCI = zvkw.zvk.VkImageCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = zvkw.zvk.VK_IMAGE_TYPE_2D,
        .format = zvkw.SHADOW_MAP_FORMAT,
        .extent = .{ .width = zvkw.SHADOW_MAP_SIZE, .height = zvkw.SHADOW_MAP_SIZE, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = zvkw.zvk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = zvkw.zvk.VK_IMAGE_TILING_OPTIMAL,
        .usage = zvkw.zvk.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | zvkw.zvk.VK_IMAGE_USAGE_SAMPLED_BIT,
        .initialLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
    };
    const allocCI = zvkw.vma.VmaAllocationCreateInfo{
        .flags = zvkw.vma.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
        .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
    };
    try check(zvkw.vma.vmaCreateImage(ctx.vmaAllocator, @ptrCast(&imageCI), &allocCI, @ptrCast(&ctx.shadowImage), &ctx.shadowImageAllocation, null));
    ctx.shadowImageLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED;

    const viewCI = zvkw.zvk.VkImageViewCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = ctx.shadowImage,
        .viewType = zvkw.zvk.VK_IMAGE_VIEW_TYPE_2D,
        .format = zvkw.SHADOW_MAP_FORMAT,
        .subresourceRange = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_DEPTH_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    try check(zvkw.zvk.vkCreateImageView(ctx.m_Device, &viewCI, null, &ctx.shadowImageView));

    const samplerCI = zvkw.zvk.VkSamplerCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO,
        .magFilter = zvkw.zvk.VK_FILTER_NEAREST,
        .minFilter = zvkw.zvk.VK_FILTER_NEAREST,
        .mipmapMode = zvkw.zvk.VK_SAMPLER_MIPMAP_MODE_NEAREST,
        .addressModeU = zvkw.zvk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        .addressModeV = zvkw.zvk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        .addressModeW = zvkw.zvk.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        .borderColor = zvkw.zvk.VK_BORDER_COLOR_FLOAT_OPAQUE_WHITE,
        .compareEnable = zvkw.zvk.VK_FALSE,
        .minLod = 0.0,
        .maxLod = 0.0,
        .unnormalizedCoordinates = zvkw.zvk.VK_FALSE,
    };
    try check(zvkw.zvk.vkCreateSampler(ctx.m_Device, &samplerCI, null, &ctx.shadowSampler));
}

pub fn destroyShadowResources(ctx: *zvkw.VulkanContext) void {
    zvkw.zvk.vkDestroySampler(ctx.m_Device, ctx.shadowSampler, null);
    zvkw.zvk.vkDestroyImageView(ctx.m_Device, ctx.shadowImageView, null);
    zvkw.vma.vmaDestroyImage(ctx.vmaAllocator, @ptrCast(ctx.shadowImage), ctx.shadowImageAllocation);
}

pub fn createShadowPipeline(ctx: *zvkw.VulkanContext) !void {
    const spv = try pipeline.loadSpvAligned(ctx.zallocator, "src/shaders/shadow.spv");
    defer ctx.zallocator.free(spv);

    const shaderModuleCI = zvkw.zvk.VkShaderModuleCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = spv.len,
        .pCode = @ptrCast(@alignCast(spv)),
    };
    var shaderModule: zvkw.zvk.VkShaderModule = null;
    try check(zvkw.zvk.vkCreateShaderModule(ctx.m_Device, &shaderModuleCI, null, &shaderModule));
    defer zvkw.zvk.vkDestroyShaderModule(ctx.m_Device, shaderModule, null);

    const shaderStage = zvkw.zvk.VkPipelineShaderStageCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = zvkw.zvk.VK_SHADER_STAGE_VERTEX_BIT,
        .module = shaderModule,
        .pName = "vertMain",
    };

    const vertexBindingDesc = zvkw.zvk.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(zvkw.Vertex),
        .inputRate = zvkw.zvk.VK_VERTEX_INPUT_RATE_VERTEX,
    };
    const vertexAttribDesc = zvkw.zvk.VkVertexInputAttributeDescription{
        .location = 0,
        .binding = 0,
        .format = zvkw.zvk.VK_FORMAT_R32G32B32_SFLOAT,
        .offset = @offsetOf(zvkw.Vertex, "pos"),
    };
    const vertexInputCI = zvkw.zvk.VkPipelineVertexInputStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .vertexBindingDescriptionCount = 1,
        .pVertexBindingDescriptions = &vertexBindingDesc,
        .vertexAttributeDescriptionCount = 1,
        .pVertexAttributeDescriptions = &vertexAttribDesc,
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
    const colorBlendCI = zvkw.zvk.VkPipelineColorBlendStateCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .attachmentCount = 0,
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
        .stageFlags = zvkw.zvk.VK_SHADER_STAGE_VERTEX_BIT,
        .offset = 0,
        .size = @sizeOf(zvkw.ShadowPushConstants),
    };
    // Only build the layout once — see the matching comment in pipeline.zig's createPipeline.
    if (ctx.shadowPipelineLayout == null) {
        const pipelineLayoutCI = zvkw.zvk.VkPipelineLayoutCreateInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
            .pushConstantRangeCount = 1,
            .pPushConstantRanges = &pushConstantRange,
        };
        try check(zvkw.zvk.vkCreatePipelineLayout(ctx.m_Device, &pipelineLayoutCI, null, &ctx.shadowPipelineLayout));
    }

    const pipelineRenderingCI = zvkw.zvk.VkPipelineRenderingCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO,
        .colorAttachmentCount = 0,
        .depthAttachmentFormat = zvkw.SHADOW_MAP_FORMAT,
    };
    const pipelineCI = zvkw.zvk.VkGraphicsPipelineCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = &pipelineRenderingCI,
        .stageCount = 1,
        .pStages = &shaderStage,
        .pVertexInputState = &vertexInputCI,
        .pInputAssemblyState = &inputAssemblyCI,
        .pViewportState = &viewportStateCI,
        .pRasterizationState = &rasterizationCI,
        .pMultisampleState = &multisampleCI,
        .pDepthStencilState = &depthStencilCI,
        .pColorBlendState = &colorBlendCI,
        .pDynamicState = &dynamicStateCI,
        .layout = ctx.shadowPipelineLayout,
    };
    try check(zvkw.zvk.vkCreateGraphicsPipelines(ctx.m_Device, null, 1, &pipelineCI, null, &ctx.shadowPipeline));
}

pub fn destroyShadowPipeline(ctx: *zvkw.VulkanContext) void {
    zvkw.zvk.vkDestroyPipeline(ctx.m_Device, ctx.shadowPipeline, null);
    zvkw.zvk.vkDestroyPipelineLayout(ctx.m_Device, ctx.shadowPipelineLayout, null);
}
