const std = @import("std");
const zvkw = @import("zVulkanContext.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub fn createSkinMatrixBuffer(ctx: *zvkw.VulkanContext) !void {
    const bufferCI = zvkw.zvk.VkBufferCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = @sizeOf([4][4]f32) * zvkw.SKIN_MATRICES_PER_FRAME * zvkw.max_frames_in_flight,
        .usage = zvkw.zvk.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
    };
    const allocCI = zvkw.vma.VmaAllocationCreateInfo{
        .flags = zvkw.vma.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT |
            zvkw.vma.VMA_ALLOCATION_CREATE_MAPPED_BIT,
        .usage = zvkw.vma.VMA_MEMORY_USAGE_AUTO,
    };
    var allocInfo: zvkw.vma.VmaAllocationInfo = undefined;
    try check(zvkw.vma.vmaCreateBuffer(ctx.vmaAllocator, @ptrCast(&bufferCI), &allocCI, @ptrCast(&ctx.skinMatrixBuffer), &ctx.skinMatrixBufferAllocation, &allocInfo));
    ctx.skinMatrixBufferMapped = @ptrCast(@alignCast(allocInfo.pMappedData.?));

    // SKIN_IDENTITY_SLOT in every frame's region is identity and never
    // written again — unskinned draws always point their push constant
    // here, so it must hold before the very first frame renders.
    const identity = [4][4]f32{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
    for (0..zvkw.max_frames_in_flight) |frame| {
        ctx.skinMatrixBufferMapped.?[frame * zvkw.SKIN_MATRICES_PER_FRAME + zvkw.SKIN_IDENTITY_SLOT] = identity;
    }
}

pub fn destroySkinMatrixBuffer(ctx: *zvkw.VulkanContext) void {
    zvkw.vma.vmaDestroyBuffer(ctx.vmaAllocator, @ptrCast(ctx.skinMatrixBuffer), ctx.skinMatrixBufferAllocation);
}

/// Base absolute index for the current frame's region — add a per-entity
/// relative offset (starting at 1, since SKIN_IDENTITY_SLOT reserves 0) to
/// get the index this draw's push-constant skinOffset should use.
pub fn frameBase(ctx: *const zvkw.VulkanContext) u32 {
    return ctx.frameIndex * zvkw.SKIN_MATRICES_PER_FRAME;
}
