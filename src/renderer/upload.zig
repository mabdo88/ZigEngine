const std = @import("std");
const zvkw = @import("zVulkanContext.zig");

/// Turns a VkResult into a Zig error so failed calls surface at the source.
fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

/// Creates a staging buffer with host-visible memory and maps it for writing.
/// Returns the buffer, allocation, and allocation info. Caller must destroy the buffer.
pub fn createStagingBuffer(size: zvkw.zvk.VkDeviceSize) !struct {
    buffer: zvkw.zvk.VkBuffer,
    allocation: zvkw.vma.VmaAllocation,
    allocInfo: zvkw.vma.VmaAllocationInfo,
} {
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

/// Submits a command buffer and waits for completion using a fence.
/// Creates and destroys the fence automatically.
pub fn submitAndWait(cmd: zvkw.zvk.VkCommandBuffer) !void {
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
