const std = @import("std");
const zvkw = @import("zVulkanContext.zig");
const upload = @import("upload.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub fn createDefaultTexture(ctx: *zvkw.VulkanContext) !void {
    const white = [4]u8{ 255, 255, 255, 255 };
    _ = try uploadTexture(ctx, &white, 1, 1);
}

pub fn resetTextures(ctx: *zvkw.VulkanContext) void {
    _ = zvkw.zvk.vkDeviceWaitIdle(ctx.m_Device);
    var i: u32 = 1;
    while (i < ctx.textureCount) : (i += 1) {
        zvkw.zvk.vkDestroyImageView(ctx.m_Device, ctx.textureSlots[i].view, null);
        zvkw.vma.vmaDestroyImage(ctx.vmaAllocator, @ptrCast(ctx.textureSlots[i].image), ctx.textureSlots[i].allocation);
        ctx.textureSlots[i] = .{};
    }
    ctx.textureCount = if (ctx.textureCount > 0) 1 else 0;
}

pub fn uploadTextureBatched(ctx: *zvkw.VulkanContext, batch: *upload.UploadBatch, pixels: []const u8, width: u32, height: u32) !zvkw.TextureHandle {
    const slot = ctx.textureCount;
    if (slot >= zvkw.MAX_TEXTURES) return error.TextureHeapFull;

    const imageCI = zvkw.zvk.VkImageCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = zvkw.zvk.VK_IMAGE_TYPE_2D,
        .format = zvkw.zvk.VK_FORMAT_R8G8B8A8_SRGB,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = zvkw.zvk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = zvkw.zvk.VK_IMAGE_TILING_OPTIMAL,
        .usage = zvkw.zvk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | zvkw.zvk.VK_IMAGE_USAGE_SAMPLED_BIT,
        .initialLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
    };
    const imageAllocCI = zvkw.vma.VmaAllocationCreateInfo{
        .flags = zvkw.vma.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
        .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
    };
    try check(zvkw.vma.vmaCreateImage(ctx.vmaAllocator, @ptrCast(&imageCI), &imageAllocCI,
        @ptrCast(&ctx.textureSlots[slot].image), &ctx.textureSlots[slot].allocation, null));

    try batch.uploadImage(pixels, width, height, ctx.textureSlots[slot].image);

    const viewCI = zvkw.zvk.VkImageViewCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = ctx.textureSlots[slot].image,
        .viewType = zvkw.zvk.VK_IMAGE_VIEW_TYPE_2D,
        .format = zvkw.zvk.VK_FORMAT_R8G8B8A8_SRGB,
        .subresourceRange = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0, .levelCount = 1,
            .baseArrayLayer = 0, .layerCount = 1,
        },
    };
    try check(zvkw.zvk.vkCreateImageView(ctx.m_Device, &viewCI, null, &ctx.textureSlots[slot].view));
    const imageInfo = zvkw.zvk.VkDescriptorImageInfo{
        .sampler = ctx.bindlessSampler,
        .imageView = ctx.textureSlots[slot].view,
        .imageLayout = zvkw.zvk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    };
    const write = zvkw.zvk.VkWriteDescriptorSet{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = ctx.bindlessDescriptorSet,
        .dstBinding = 0,
        .dstArrayElement = slot,
        .descriptorCount = 1,
        .descriptorType = zvkw.zvk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &imageInfo,
    };
    zvkw.zvk.vkUpdateDescriptorSets(ctx.m_Device, 1, &write, 0, null);
    ctx.textureCount += 1;
    return slot;
}

pub fn uploadTexture(ctx: *zvkw.VulkanContext, pixels: []const u8, width: u32, height: u32) !zvkw.TextureHandle {
    const slot = ctx.textureCount;
    if (slot >= zvkw.MAX_TEXTURES) return error.TextureHeapFull;
    const imageSize: zvkw.zvk.VkDeviceSize = width * height * 4;

    const staging = try upload.createStagingBuffer(ctx, imageSize);
    defer zvkw.vma.vmaDestroyBuffer(ctx.vmaAllocator, @ptrCast(staging.buffer), staging.allocation);

    const dst: [*]u8 = @ptrCast(staging.allocInfo.pMappedData.?);
    @memcpy(dst[0..imageSize], pixels[0..imageSize]);
    const imageCI = zvkw.zvk.VkImageCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = zvkw.zvk.VK_IMAGE_TYPE_2D,
        .format = zvkw.zvk.VK_FORMAT_R8G8B8A8_SRGB,
        .extent = .{ .width = width, .height = height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = zvkw.zvk.VK_SAMPLE_COUNT_1_BIT,
        .tiling = zvkw.zvk.VK_IMAGE_TILING_OPTIMAL,
        .usage = zvkw.zvk.VK_IMAGE_USAGE_TRANSFER_DST_BIT | zvkw.zvk.VK_IMAGE_USAGE_SAMPLED_BIT,
        .initialLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
    };
    const imageAllocCI = zvkw.vma.VmaAllocationCreateInfo{
        .flags = zvkw.vma.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
        .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
    };
    try check(zvkw.vma.vmaCreateImage(ctx.vmaAllocator, @ptrCast(&imageCI), &imageAllocCI, @ptrCast(&ctx.textureSlots[slot].image), &ctx.textureSlots[slot].allocation, null));

    const cb = try upload.beginOneTimeCommandBuffer(ctx);
    defer zvkw.zvk.vkFreeCommandBuffers(ctx.m_Device, ctx.commandPool, 1, &cb);
    const toTransferBarrier = zvkw.zvk.VkImageMemoryBarrier2{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_NONE,
        .srcAccessMask = zvkw.zvk.VK_ACCESS_2_NONE,
        .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COPY_BIT,
        .dstAccessMask = zvkw.zvk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
        .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
        .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .image = ctx.textureSlots[slot].image,
        .subresourceRange = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0, .levelCount = 1,
            .baseArrayLayer = 0, .layerCount = 1,
        },
    };
    const toTransferDep = zvkw.zvk.VkDependencyInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &toTransferBarrier,
    };
    zvkw.zvk.vkCmdPipelineBarrier2(cb, &toTransferDep);
    const copyRegion = zvkw.zvk.VkBufferImageCopy{
        .bufferOffset = 0,
        .bufferRowLength = 0,
        .bufferImageHeight = 0,
        .imageSubresource = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
            .mipLevel = 0,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
        .imageOffset = .{ .x = 0, .y = 0, .z = 0 },
        .imageExtent = .{ .width = width, .height = height, .depth = 1 },
    };
    zvkw.zvk.vkCmdCopyBufferToImage(cb, @ptrCast(staging.buffer), ctx.textureSlots[slot].image, zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copyRegion);
    const toShaderBarrier = zvkw.zvk.VkImageMemoryBarrier2{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COPY_BIT,
        .srcAccessMask = zvkw.zvk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
        .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
        .dstAccessMask = zvkw.zvk.VK_ACCESS_2_SHADER_READ_BIT,
        .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .image = ctx.textureSlots[slot].image,
        .subresourceRange = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0, .levelCount = 1,
            .baseArrayLayer = 0, .layerCount = 1,
        },
    };
    const toShaderDep = zvkw.zvk.VkDependencyInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = 1,
        .pImageMemoryBarriers = &toShaderBarrier,
    };
    zvkw.zvk.vkCmdPipelineBarrier2(cb, &toShaderDep);
    try check(zvkw.zvk.vkEndCommandBuffer(cb));

    const submitInfo = zvkw.zvk.VkSubmitInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cb,
    };
    try check(zvkw.zvk.vkQueueSubmit(ctx.queue, 1, &submitInfo, null));
    try check(zvkw.zvk.vkQueueWaitIdle(ctx.queue));
    const viewCI = zvkw.zvk.VkImageViewCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = ctx.textureSlots[slot].image,
        .viewType = zvkw.zvk.VK_IMAGE_VIEW_TYPE_2D,
        .format = zvkw.zvk.VK_FORMAT_R8G8B8A8_SRGB,
        .subresourceRange = .{
            .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0, .levelCount = 1,
            .baseArrayLayer = 0, .layerCount = 1,
        },
    };
    try check(zvkw.zvk.vkCreateImageView(ctx.m_Device, &viewCI, null, &ctx.textureSlots[slot].view));
    const imageInfo = zvkw.zvk.VkDescriptorImageInfo{
        .sampler = ctx.bindlessSampler,
        .imageView = ctx.textureSlots[slot].view,
        .imageLayout = zvkw.zvk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    };
    const write = zvkw.zvk.VkWriteDescriptorSet{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .dstSet = ctx.bindlessDescriptorSet,
        .dstBinding = 0,
        .dstArrayElement = slot,
        .descriptorCount = 1,
        .descriptorType = zvkw.zvk.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        .pImageInfo = &imageInfo,
    };
    zvkw.zvk.vkUpdateDescriptorSets(ctx.m_Device, 1, &write, 0, null);
    ctx.textureCount += 1;
    return slot;
}
