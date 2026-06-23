const std = @import("std");
const zvkw = @import("zVulkanContext.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub fn createPipeline(ctx: *zvkw.VulkanContext) !void {
    const spv = @embedFile("../shaders/slang.spv");

    const shaderModuleCI = zvkw.zvk.VkShaderModuleCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = spv.len,
        .pCode = @ptrCast(@alignCast(spv)),
    };

    var shaderModule: zvkw.zvk.VkShaderModule = null;
    const result = zvkw.zvk.vkCreateShaderModule(ctx.m_Device, &shaderModuleCI, null, &shaderModule);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateShaderModuleFailed;
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
        .size = @sizeOf(zvkw.PushConstants),
    };
    const setLayouts = [2]zvkw.zvk.VkDescriptorSetLayout{
        ctx.uboDescriptorSetLayout,
        ctx.bindlessDescriptorSetLayout,
    };
    const pipelineLayoutCI = zvkw.zvk.VkPipelineLayoutCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 2,
        .pSetLayouts = &setLayouts,
        .pushConstantRangeCount = 1,
        .pPushConstantRanges = &pushConstantRange,
    };
    var result2 = zvkw.zvk.vkCreatePipelineLayout(ctx.m_Device, &pipelineLayoutCI, null, &ctx.pipelineLayout);
    if (result2 != zvkw.zvk.VK_SUCCESS) return error.CreatePipelineLayoutFailed;

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
        .layout = ctx.pipelineLayout,
    };
    result2 = zvkw.zvk.vkCreateGraphicsPipelines(ctx.m_Device, null, 1, &pipelineCI, null, &ctx.pipeline);
    if (result2 != zvkw.zvk.VK_SUCCESS) return error.CreatePipelineFailed;
}

pub fn createDescriptorSetLayout(ctx: *zvkw.VulkanContext) !void {
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
    var result = zvkw.zvk.vkCreateDescriptorSetLayout(ctx.m_Device, &uboLayoutCI, null, &ctx.uboDescriptorSetLayout);
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
    result = zvkw.zvk.vkCreateDescriptorSetLayout(ctx.m_Device, &bindlessLayoutCI, null, &ctx.bindlessDescriptorSetLayout);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateDescriptorSetLayoutFailed;
}

pub fn createDescriptorPool(ctx: *zvkw.VulkanContext) !void {
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
    const result = zvkw.zvk.vkCreateDescriptorPool(ctx.m_Device, &poolCI, null, &ctx.descriptorPool);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateDescriptorPoolFailed;
}

pub fn createSampler(ctx: *zvkw.VulkanContext) !void {
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
    const result = zvkw.zvk.vkCreateSampler(ctx.m_Device, &samplerCI, null, &ctx.bindlessSampler);
    if (result != zvkw.zvk.VK_SUCCESS) return error.CreateSamplerFailed;
}

pub fn createDescriptorSets(ctx: *zvkw.VulkanContext) !void {
    const uboLayouts = [zvkw.max_frames_in_flight]zvkw.zvk.VkDescriptorSetLayout{
        ctx.uboDescriptorSetLayout,
        ctx.uboDescriptorSetLayout,
    };
    const uboAllocInfo = zvkw.zvk.VkDescriptorSetAllocateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = ctx.descriptorPool,
        .descriptorSetCount = zvkw.max_frames_in_flight,
        .pSetLayouts = &uboLayouts,
    };
    var result = zvkw.zvk.vkAllocateDescriptorSets(ctx.m_Device, &uboAllocInfo, &ctx.uboDescriptorSets);
    if (result != zvkw.zvk.VK_SUCCESS) return error.AllocateDescriptorSetsFailed;

    const bindlessAllocInfo = zvkw.zvk.VkDescriptorSetAllocateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = ctx.descriptorPool,
        .descriptorSetCount = 1,
        .pSetLayouts = &ctx.bindlessDescriptorSetLayout,
    };
    result = zvkw.zvk.vkAllocateDescriptorSets(ctx.m_Device, &bindlessAllocInfo, &ctx.bindlessDescriptorSet);
    if (result != zvkw.zvk.VK_SUCCESS) return error.AllocateDescriptorSetsFailed;
}

pub fn createShaderDataBuffers(ctx: *zvkw.VulkanContext) !void {
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
            ctx.vmaAllocator,
            @ptrCast(&bufferCI),
            &allocCI,
            @ptrCast(&ctx.shaderDataBuffers[i].buffer),
            &ctx.shaderDataBuffers[i].allocation,
            &ctx.shaderDataBuffers[i].allocInfo,
        );
        if (result != zvkw.zvk.VK_SUCCESS) return error.CreateShaderDataBufferFailed;

        const bufferInfo = zvkw.zvk.VkDescriptorBufferInfo{
            .buffer = ctx.shaderDataBuffers[i].buffer,
            .offset = 0,
            .range = @sizeOf(zvkw.FrameUBO),
        };
        const write = zvkw.zvk.VkWriteDescriptorSet{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = ctx.uboDescriptorSets[i],
            .dstBinding = 0,
            .dstArrayElement = 0,
            .descriptorCount = 1,
            .descriptorType = zvkw.zvk.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
            .pBufferInfo = &bufferInfo,
        };
        zvkw.zvk.vkUpdateDescriptorSets(ctx.m_Device, 1, &write, 0, null);
    }
}
