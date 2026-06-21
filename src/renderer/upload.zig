const std = @import("std");
const zvkw = @import("zVulkanContext.zig");

/// Turns a VkResult into a Zig error so failed calls surface at the source.
fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub const StagingBuffer = struct {
    buffer: zvkw.zvk.VkBuffer,
    allocation: zvkw.vma.VmaAllocation,
    allocInfo: zvkw.vma.VmaAllocationInfo,

    pub fn destroy(self: StagingBuffer) void {
        zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(self.buffer), self.allocation);
    }
};

/// Creates a staging buffer with host-visible memory and maps it for writing.
/// Caller must call destroy() on the returned buffer when done.
pub fn createStagingBuffer(size: zvkw.zvk.VkDeviceSize) !StagingBuffer {
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
        zvkw.ctx.vmaAllocator,
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

/// Allocates and begins a one-time submit command buffer.
/// Returns the command buffer. Caller must free it after submission.
pub fn beginOneTimeCommandBuffer() !zvkw.zvk.VkCommandBuffer {
    const cbAllocInfo = zvkw.zvk.VkCommandBufferAllocateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = zvkw.ctx.commandPool,
        .level = zvkw.zvk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    var cmd: zvkw.zvk.VkCommandBuffer = null;
    try check(zvkw.zvk.vkAllocateCommandBuffers(zvkw.ctx.m_Device, &cbAllocInfo, &cmd));

    const beginInfo = zvkw.zvk.VkCommandBufferBeginInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = zvkw.zvk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try check(zvkw.zvk.vkBeginCommandBuffer(cmd, &beginInfo));

    return cmd;
}

/// Ends, submits, and waits for a command buffer. Frees the command buffer.
pub fn submitAndWait(cmd: zvkw.zvk.VkCommandBuffer) !void {
    defer zvkw.zvk.vkFreeCommandBuffers(zvkw.ctx.m_Device, zvkw.ctx.commandPool, 1, &cmd);
    const fenceCI = zvkw.zvk.VkFenceCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    };
    var fence: zvkw.zvk.VkFence = null;
    try check(zvkw.zvk.vkCreateFence(zvkw.ctx.m_Device, &fenceCI, null, &fence));
    defer zvkw.zvk.vkDestroyFence(zvkw.ctx.m_Device, fence, null);

    const submitInfo = zvkw.zvk.VkSubmitInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
    };
    try check(zvkw.zvk.vkQueueSubmit(zvkw.ctx.queue, 1, &submitInfo, fence));
    try check(zvkw.zvk.vkWaitForFences(zvkw.ctx.m_Device, 1, &fence, zvkw.zvk.VK_TRUE, std.math.maxInt(u64)));
}

/// A batch accumulates staging buffers and copy commands into a single
/// command buffer. Call begin(), record copies, then submit().
/// All staging buffers are freed automatically on submit().
pub const UploadBatch = struct {
    cmd: zvkw.zvk.VkCommandBuffer,
    stagings: std.ArrayListUnmanaged(StagingBuffer) = .empty,
    stagings_alloc: std.mem.Allocator,

    /// Begin a new upload batch.
    pub fn begin(allocator: std.mem.Allocator) !UploadBatch {
        return .{
            .cmd = try beginOneTimeCommandBuffer(),
            .stagings_alloc = allocator,
        };
    }

    /// Copy raw bytes into a device-local buffer. Creates the GPU buffer,
    /// records a vkCmdCopyBuffer into the batch command buffer.
    /// Returns the created GPU buffer and allocation — caller owns them.
    pub fn uploadBuffer(
        self: *UploadBatch,
        data: *const anyopaque,
        size: zvkw.zvk.VkDeviceSize,
        usage: zvkw.zvk.VkBufferUsageFlags,
        out_buffer: *zvkw.zvk.VkBuffer,
        out_allocation: *zvkw.vma.VmaAllocation,
    ) !void {
        const staging = try createStagingBuffer(size);
        try self.stagings.append(self.stagings_alloc, staging);

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
            zvkw.ctx.vmaAllocator,
            @ptrCast(&bufferCI),
            &bufferAllocCI,
            @ptrCast(out_buffer),
            out_allocation,
            null,
        ) != zvkw.zvk.VK_SUCCESS) return error.GpuBufferCreateFailed;

        const copy = zvkw.zvk.VkBufferCopy{ .size = size };
        zvkw.zvk.vkCmdCopyBuffer(self.cmd, @ptrCast(staging.buffer), out_buffer.*, 1, &copy);
    }

    /// Record an image copy from a staging buffer into a VkImage.
    /// The staging buffer is appended to the batch — freed on submit.
    pub fn uploadImage(
        self: *UploadBatch,
        pixels: []const u8,
        width: u32,
        height: u32,
        image: zvkw.zvk.VkImage,
    ) !void {
        const size: zvkw.zvk.VkDeviceSize = @intCast(pixels.len);
        const staging = try createStagingBuffer(size);
        try self.stagings.append(self.stagings_alloc, staging);

        @memcpy(
            @as([*]u8, @ptrCast(@alignCast(staging.allocInfo.pMappedData)))[0..pixels.len],
            pixels,
        );

        // Transition: undefined → transfer dst
        const barrier_to_dst = zvkw.zvk.VkImageMemoryBarrier{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = zvkw.zvk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = zvkw.zvk.VK_QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresourceRange = .{
                .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .srcAccessMask = 0,
            .dstAccessMask = zvkw.zvk.VK_ACCESS_TRANSFER_WRITE_BIT,
        };
        zvkw.zvk.vkCmdPipelineBarrier(
            self.cmd,
            zvkw.zvk.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            zvkw.zvk.VK_PIPELINE_STAGE_TRANSFER_BIT,
            0, 0, null, 0, null, 1, &barrier_to_dst,
        );

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
            self.cmd, @ptrCast(staging.buffer), image,
            zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region,
        );

        // Transition: transfer dst → shader read
        const barrier_to_read = zvkw.zvk.VkImageMemoryBarrier{
            .sType = zvkw.zvk.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .oldLayout = zvkw.zvk.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .newLayout = zvkw.zvk.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
            .srcQueueFamilyIndex = zvkw.zvk.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = zvkw.zvk.VK_QUEUE_FAMILY_IGNORED,
            .image = image,
            .subresourceRange = .{
                .aspectMask = zvkw.zvk.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
            .srcAccessMask = zvkw.zvk.VK_ACCESS_TRANSFER_WRITE_BIT,
            .dstAccessMask = zvkw.zvk.VK_ACCESS_SHADER_READ_BIT,
        };
        zvkw.zvk.vkCmdPipelineBarrier(
            self.cmd,
            zvkw.zvk.VK_PIPELINE_STAGE_TRANSFER_BIT,
            zvkw.zvk.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            0, 0, null, 0, null, 1, &barrier_to_read,
        );
    }

    /// End the batch: submits the command buffer, waits for completion,
    /// then destroys all staging buffers.
    pub fn submit(self: *UploadBatch) !void {
        try check(zvkw.zvk.vkEndCommandBuffer(self.cmd));
        try submitAndWait(self.cmd);
        for (self.stagings.items) |s| s.destroy();
        self.stagings.deinit(self.stagings_alloc);
    }
};
