const std = @import("std");
const zvkw = @import("zVulkanContext.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub fn mipLevelsForSize(width: u32, height: u32) u32 {
    const largest = @max(@max(width, height), 1);
    return @as(u32, std.math.log2_int(u32, largest)) + 1;
}

/// Generates mip levels [1, mip_levels) by repeatedly blitting from the
/// previous level, assuming mip 0 is already populated and currently in
/// TRANSFER_DST_OPTIMAL (i.e. called right after the base-level upload, in
/// the same command buffer). Leaves every mip level in
/// SHADER_READ_ONLY_OPTIMAL. A 1x1 (mip_levels == 1) texture just gets the
/// final transition with no blits.
pub fn generateMipmaps(cmd: zvkw.zvk.VkCommandBuffer, image: zvkw.zvk.VkImage, width: u32, height: u32, mip_levels: u32) void {
    var mip_w: i32 = @intCast(width);
    var mip_h: i32 = @intCast(height);

    var level: u32 = 1;
    while (level < mip_levels) : (level += 1) {
        const pre_barriers = [2]zvkw.zvk.VkImageMemoryBarrier2{
            .{
                .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
                .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COPY_BIT | zvkw.zvk.VK_PIPELINE_STAGE_2_BLIT_BIT,
                .srcAccessMask = zvkw.zvk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
                .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_BLIT_BIT,
                .dstAccessMask = zvkw.zvk.VK_ACCESS_2_TRANSFER_READ_BIT,
                .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                .image = image,
                .subresourceRange = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = level - 1, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
            },
            .{
                // Destination mip has never been touched (still UNDEFINED from image creation) — transition it for the blit write.
                .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
                .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_NONE,
                .srcAccessMask = zvkw.zvk.VK_ACCESS_2_NONE,
                .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_BLIT_BIT,
                .dstAccessMask = zvkw.zvk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
                .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
                .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                .image = image,
                .subresourceRange = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = level, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
            },
        };
        const pre_dep = zvkw.zvk.VkDependencyInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .imageMemoryBarrierCount = 2,
            .pImageMemoryBarriers = &pre_barriers,
        };
        zvkw.zvk.vkCmdPipelineBarrier2(cmd, &pre_dep);

        const next_w = @max(@divTrunc(mip_w, 2), 1);
        const next_h = @max(@divTrunc(mip_h, 2), 1);
        const blit = zvkw.zvk.VkImageBlit{
            .srcSubresource = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = level - 1, .baseArrayLayer = 0, .layerCount = 1 },
            .srcOffsets = .{ .{ .x = 0, .y = 0, .z = 0 }, .{ .x = mip_w, .y = mip_h, .z = 1 } },
            .dstSubresource = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = level, .baseArrayLayer = 0, .layerCount = 1 },
            .dstOffsets = .{ .{ .x = 0, .y = 0, .z = 0 }, .{ .x = next_w, .y = next_h, .z = 1 } },
        };
        zvkw.zvk.vkCmdBlitImage(cmd, image, zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, image, zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, zvkw.zvk.VK_FILTER_LINEAR);

        mip_w = next_w;
        mip_h = next_h;
    }

    // Mips [0, mip_levels-2] are now in TRANSFER_SRC_OPTIMAL (read from during blits);
    // the last mip is still in TRANSFER_DST_OPTIMAL (written, never read from). Both
    // need to land in SHADER_READ_ONLY_OPTIMAL for the fragment shader to sample them.
    var final_barriers: [2]zvkw.zvk.VkImageMemoryBarrier2 = undefined;
    var barrier_count: u32 = 0;
    if (mip_levels > 1) {
        final_barriers[barrier_count] = .{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_BLIT_BIT,
            .srcAccessMask = zvkw.zvk.VK_ACCESS_2_TRANSFER_READ_BIT,
            .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
            .dstAccessMask = zvkw.zvk.VK_ACCESS_2_SHADER_READ_BIT,
            .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .image = image,
            .subresourceRange = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = mip_levels - 1, .baseArrayLayer = 0, .layerCount = 1 },
        };
        barrier_count += 1;
    }
    final_barriers[barrier_count] = .{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
        .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COPY_BIT | zvkw.zvk.VK_PIPELINE_STAGE_2_BLIT_BIT,
        .srcAccessMask = zvkw.zvk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
        .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
        .dstAccessMask = zvkw.zvk.VK_ACCESS_2_SHADER_READ_BIT,
        .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
        .image = image,
        .subresourceRange = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = mip_levels - 1, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
    };
    barrier_count += 1;

    const final_dep = zvkw.zvk.VkDependencyInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
        .imageMemoryBarrierCount = barrier_count,
        .pImageMemoryBarriers = &final_barriers,
    };
    zvkw.zvk.vkCmdPipelineBarrier2(cmd, &final_dep);
}

pub const StagingBuffer = struct {
    buffer: zvkw.zvk.VkBuffer,
    allocation: zvkw.vma.VmaAllocation,
    allocInfo: zvkw.vma.VmaAllocationInfo,

    pub fn destroy(self: StagingBuffer, ctx: *zvkw.VulkanContext) void {
        zvkw.vma.vmaDestroyBuffer(ctx.vmaAllocator, @ptrCast(self.buffer), self.allocation);
    }
};

pub fn createStagingBuffer(ctx: *zvkw.VulkanContext, size: zvkw.zvk.VkDeviceSize) !StagingBuffer {
    const stagingBufferCI = zvkw.zvk.VkBufferCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = zvkw.zvk.VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
    };
    const stagingAllocCI = zvkw.vma.VmaAllocationCreateInfo{
        .flags = zvkw.vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT |
            zvkw.vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_ALLOW_TRANSFER_INSTEAD_BIT |
            zvkw.vma.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
    };

    var stagingBuffer: zvkw.vma.VkBuffer = null;
    var stagingAllocation: zvkw.vma.VmaAllocation = null;
    var stagingInfo: zvkw.vma.VmaAllocationInfo = undefined;

    if (zvkw.vma.vmaCreateBuffer(
        ctx.vmaAllocator,
        @ptrCast(&stagingBufferCI),
        &stagingAllocCI,
        @ptrCast(&stagingBuffer),
        &stagingAllocation,
        &stagingInfo,
    ) != zvkw.zvk.VK_SUCCESS) return error.StagingBufferCreateFailed;

    return .{
        .buffer = @ptrCast(stagingBuffer),
        .allocation = stagingAllocation,
        .allocInfo = stagingInfo,
    };
}

pub fn beginOneTimeCommandBuffer(ctx: *zvkw.VulkanContext) !zvkw.zvk.VkCommandBuffer {
    const cbAllocInfo = zvkw.zvk.VkCommandBufferAllocateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = ctx.commandPool,
        .level = zvkw.zvk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    var cmd: zvkw.zvk.VkCommandBuffer = null;
    try check(zvkw.zvk.vkAllocateCommandBuffers(ctx.m_Device, &cbAllocInfo, &cmd));

    const beginInfo = zvkw.zvk.VkCommandBufferBeginInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = zvkw.zvk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try check(zvkw.zvk.vkBeginCommandBuffer(cmd, &beginInfo));

    return cmd;
}

pub fn submitAndWait(ctx: *zvkw.VulkanContext, cmd: zvkw.zvk.VkCommandBuffer) !void {
    defer zvkw.zvk.vkFreeCommandBuffers(ctx.m_Device, ctx.commandPool, 1, &cmd);
    const fenceCI = zvkw.zvk.VkFenceCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    };
    var fence: zvkw.zvk.VkFence = null;
    try check(zvkw.zvk.vkCreateFence(ctx.m_Device, &fenceCI, null, &fence));
    defer zvkw.zvk.vkDestroyFence(ctx.m_Device, fence, null);

    const submitInfo = zvkw.zvk.VkSubmitInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
    };
    try check(zvkw.zvk.vkQueueSubmit(ctx.queue, 1, &submitInfo, fence));
    try check(zvkw.zvk.vkWaitForFences(ctx.m_Device, 1, &fence, zvkw.zvk.VK_TRUE, std.math.maxInt(u64)));
}

pub const UploadBatch = struct {
    cmd: zvkw.zvk.VkCommandBuffer,
    ctx: *zvkw.VulkanContext,
    stagings: std.ArrayListUnmanaged(StagingBuffer) = .empty,
    stagings_alloc: std.mem.Allocator,

    pub fn begin(ctx: *zvkw.VulkanContext, allocator: std.mem.Allocator) !UploadBatch {
        return .{
            .cmd = try beginOneTimeCommandBuffer(ctx),
            .ctx = ctx,
            .stagings_alloc = allocator,
        };
    }

    pub fn uploadBuffer(
        self: *UploadBatch,
        data: *const anyopaque,
        size: zvkw.zvk.VkDeviceSize,
        usage: zvkw.zvk.VkBufferUsageFlags,
        out_buffer: *zvkw.zvk.VkBuffer,
        out_allocation: *zvkw.vma.VmaAllocation,
    ) !void {
        const staging = try createStagingBuffer(self.ctx, size);
        errdefer staging.destroy(self.ctx);
        try self.stagings.append(self.stagings_alloc, staging);
        errdefer _ = self.stagings.pop();

        @memcpy(
            @as([*]u8, @ptrCast(@alignCast(staging.allocInfo.pMappedData)))[0..size],
            @as([*]const u8, @ptrCast(data))[0..size],
        );

        const bufferCI = zvkw.zvk.VkBufferCreateInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .size = size,
            .usage = @as(u32, @bitCast(zvkw.zvk.VK_BUFFER_USAGE_TRANSFER_DST_BIT)) | usage,
        };
        const bufferAllocCI = zvkw.vma.VmaAllocationCreateInfo{
            .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
        };
        if (zvkw.vma.vmaCreateBuffer(
            self.ctx.vmaAllocator,
            @ptrCast(&bufferCI),
            &bufferAllocCI,
            @ptrCast(out_buffer),
            out_allocation,
            null,
        ) != zvkw.zvk.VK_SUCCESS) return error.GpuBufferCreateFailed;

        const copy = zvkw.zvk.VkBufferCopy{ .size = size };
        zvkw.zvk.vkCmdCopyBuffer(self.cmd, @ptrCast(staging.buffer), out_buffer.*, 1, &copy);
    }

    pub fn uploadImage(
        self: *UploadBatch,
        pixels: []const u8,
        width: u32,
        height: u32,
        image: zvkw.zvk.VkImage,
    ) !void {
        const size: zvkw.zvk.VkDeviceSize = @intCast(pixels.len);
        const staging = try createStagingBuffer(self.ctx, size);
        errdefer staging.destroy(self.ctx);
        try self.stagings.append(self.stagings_alloc, staging);
        errdefer _ = self.stagings.pop();

        @memcpy(
            @as([*]u8, @ptrCast(@alignCast(staging.allocInfo.pMappedData)))[0..pixels.len],
            pixels,
        );

        const to_dst_barrier = zvkw.zvk.VkImageMemoryBarrier2{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .srcStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_NONE,
            .srcAccessMask = zvkw.zvk.VK_ACCESS_2_NONE,
            .dstStageMask = zvkw.zvk.VK_PIPELINE_STAGE_2_COPY_BIT,
            .dstAccessMask = zvkw.zvk.VK_ACCESS_2_TRANSFER_WRITE_BIT,
            .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .image = image,
            .subresourceRange = .{ .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
        };
        const to_dst_dep = zvkw.zvk.VkDependencyInfo{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .imageMemoryBarrierCount = 1,
            .pImageMemoryBarriers = &to_dst_barrier,
        };
        zvkw.zvk.vkCmdPipelineBarrier2(self.cmd, &to_dst_dep);

        const region = zvkw.zvk.VkBufferImageCopy{
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
        zvkw.zvk.vkCmdCopyBufferToImage(
            self.cmd,
            @ptrCast(staging.buffer),
            image,
            zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            1,
            &region,
        );

        generateMipmaps(self.cmd, image, width, height, mipLevelsForSize(width, height));
    }

    pub fn submit(self: *UploadBatch) !void {
        try check(zvkw.zvk.vkEndCommandBuffer(self.cmd));
        try submitAndWait(self.ctx, self.cmd);
        for (self.stagings.items) |s| s.destroy(self.ctx);
        self.stagings.deinit(self.stagings_alloc);
    }

    pub fn cancel(self: *UploadBatch) void {
        for (self.stagings.items) |s| s.destroy(self.ctx);
        self.stagings.deinit(self.stagings_alloc);
        zvkw.zvk.vkFreeCommandBuffers(self.ctx.m_Device, self.ctx.commandPool, 1, &self.cmd);
    }
};
