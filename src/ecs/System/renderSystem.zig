const std = @import("std");
const zvkw = @import("../../Vulkan/zVulkanContext.zig");
const components = @import("../Component/components.zig");
const Registry = @import("../Storage/registry.zig").Registry;
const Entity = @import("../Entity/entity.zig").Entity;
const cs = @import("../System/cameraSystem.zig");

/// Turns a VkResult into a Zig error so failed calls surface at the source.
fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub const GpuMesh = struct {
    vertexBuffer: zvkw.zvk.VkBuffer,
    vertexAllocation: zvkw.vma.VmaAllocation,
    indexBuffer: zvkw.zvk.VkBuffer,
    indexAllocation: zvkw.vma.VmaAllocation,
    indexCount: u32,
};

fn uploadToGpu(
    data: *const anyopaque,
    size: zvkw.zvk.VkDeviceSize,
    usage: zvkw.zvk.VkBufferUsageFlags,
    out_buffer: *zvkw.zvk.VkBuffer,
    out_allocation: *zvkw.vma.VmaAllocation,
) !void {
    // --- Staging buffer (CPU writable) ---
    const stagingCI = zvkw.zvk.VkBufferCreateInfo{
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
        @ptrCast(&stagingCI),
        &stagingAllocCI,
        @ptrCast(&stagingBuffer),
        &stagingAllocation,
        &stagingInfo,
    ) != zvkw.zvk.VK_SUCCESS) return error.StagingBufferCreateFailed;
    errdefer zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, stagingBuffer, stagingAllocation);

    @memcpy(@as([*]u8, @ptrCast(@alignCast(stagingInfo.pMappedData)))[0..size], @as([*]const u8, @ptrCast(data))[0..size]);

    // --- Device-local GPU buffer ---
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
    errdefer zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(out_buffer.*), out_allocation.*);

    // --- One-time command buffer ---
    const cbAllocInfo = zvkw.zvk.VkCommandBufferAllocateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = zvkw.ctx.commandPool,
        .level = zvkw.zvk.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    var cmd: zvkw.zvk.VkCommandBuffer = null;
    try check(zvkw.zvk.vkAllocateCommandBuffers(zvkw.ctx.m_Device, &cbAllocInfo, &cmd));
    errdefer zvkw.zvk.vkFreeCommandBuffers(zvkw.ctx.m_Device, zvkw.ctx.commandPool, 1, &cmd);

    const beginInfo = zvkw.zvk.VkCommandBufferBeginInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = zvkw.zvk.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    try check(zvkw.zvk.vkBeginCommandBuffer(cmd, &beginInfo));

    const copy = zvkw.zvk.VkBufferCopy{ .size = size };
    zvkw.zvk.vkCmdCopyBuffer(cmd, @ptrCast(stagingBuffer), out_buffer.*, 1, &copy);

    try check(zvkw.zvk.vkEndCommandBuffer(cmd));

    // --- Submit and stall ---
    const fenceCI = zvkw.zvk.VkFenceCreateInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
    };
    var fence: zvkw.zvk.VkFence = null;
    try check(zvkw.zvk.vkCreateFence(zvkw.ctx.m_Device, &fenceCI, null, &fence));
    errdefer zvkw.zvk.vkDestroyFence(zvkw.ctx.m_Device, fence, null);

    const submitInfo = zvkw.zvk.VkSubmitInfo{
        .sType = zvkw.zvk.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &cmd,
    };
    try check(zvkw.zvk.vkQueueSubmit(zvkw.ctx.queue, 1, &submitInfo, fence));
    try check(zvkw.zvk.vkWaitForFences(zvkw.ctx.m_Device, 1, &fence, zvkw.zvk.VK_TRUE, std.math.maxInt(u64)));

    // --- Cleanup ---
    zvkw.zvk.vkDestroyFence(zvkw.ctx.m_Device, fence, null);
    zvkw.zvk.vkFreeCommandBuffers(zvkw.ctx.m_Device, zvkw.ctx.commandPool, 1, &cmd);
    zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, stagingBuffer, stagingAllocation);
}
fn uploadMesh(mesh: *const components.MeshComponent) !GpuMesh {
    var gpuMesh: GpuMesh = undefined;
    try uploadToGpu(
        mesh.vertices.ptr,
        @sizeOf(components.Vertex) * mesh.vertices.len,
        zvkw.zvk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        &gpuMesh.vertexBuffer,
        &gpuMesh.vertexAllocation,
    );
    try uploadToGpu(
        mesh.indices.ptr,
        @sizeOf(u32) * mesh.indices.len,
        zvkw.zvk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        &gpuMesh.indexBuffer,
        &gpuMesh.indexAllocation,
    );
    gpuMesh.indexCount = @intCast(mesh.indices.len);
    return gpuMesh;
}
pub const RenderSystem = struct {
    gpu_meshes: std.AutoHashMap(Entity, GpuMesh),

    pub fn init() RenderSystem {
        return .{
            .gpu_meshes = std.AutoHashMap(Entity, GpuMesh).init(zvkw.ctx.zallocator),
        };
    }
    /// Registry destroy hook: frees the GPU buffers for an entity the moment it
    /// is destroyed, keyed by (index, generation) so a recycled index can't
    /// collide with the previous owner's mesh.
    pub fn onEntityDestroyed(ctx: *anyopaque, entity: Entity) void {
        const self: *RenderSystem = @ptrCast(@alignCast(ctx));
        if (self.gpu_meshes.fetchRemove(entity)) |kv| {
            zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(kv.value.vertexBuffer), kv.value.vertexAllocation);
            zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(kv.value.indexBuffer), kv.value.indexAllocation);
        }
    }
    pub fn update(self: *RenderSystem, registry: *Registry, cb: zvkw.zvk.VkCommandBuffer) !void {
        zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, zvkw.ctx.pipelineLayout, 0, 1, &zvkw.ctx.uboDescriptorSets[zvkw.ctx.frameIndex], 0, null);
        zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, zvkw.ctx.pipelineLayout, 1, 1, &zvkw.ctx.bindlessDescriptorSet, 0, null);
        var it = registry.Query(.{ components.MeshComponent, components.TransformComponent });
        while (it.next()) |entity| {
            const mesh = registry.get(components.MeshComponent, entity.index).?;
            const transform = registry.get(components.TransformComponent, entity.index).?;
            if (!mesh.isValid()) continue;
            if (!self.gpu_meshes.contains(entity)) {
                const gpu_mesh = try uploadMesh(mesh);
                try self.gpu_meshes.put(entity, gpu_mesh);
                std.log.info("RenderSystem: uploaded mesh for entity {}", .{entity.index});
            }

            const gpu_mesh = self.gpu_meshes.get(entity).?;
            const offset: zvkw.zvk.VkDeviceSize = 0;
            zvkw.zvk.vkCmdBindVertexBuffers(cb, 0, 1, &gpu_mesh.vertexBuffer, &offset);
            zvkw.zvk.vkCmdBindIndexBuffer(cb, gpu_mesh.indexBuffer, 0, zvkw.zvk.VK_INDEX_TYPE_UINT32);
            const pc = zvkw.PushConstants{
                .model = transformToMatrix(transform),
                .textureIndex = if (registry.get(components.TextureComponent, entity.index)) |tc| tc.textureIndex else 0,
            };

            zvkw.zvk.vkCmdPushConstants(cb, zvkw.ctx.pipelineLayout, zvkw.zvk.VK_SHADER_STAGE_VERTEX_BIT | zvkw.zvk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(zvkw.PushConstants), @ptrCast(&pc));
            zvkw.zvk.vkCmdDrawIndexed(cb, gpu_mesh.indexCount, 1, 0, 0, 0);
        }
    }
    pub fn deinit(self: *RenderSystem) void {
        var it = self.gpu_meshes.iterator();
        while (it.next()) |entry| {
            zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(entry.value_ptr.vertexBuffer), entry.value_ptr.vertexAllocation);
            zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(entry.value_ptr.indexBuffer), entry.value_ptr.indexAllocation);
        }
        self.gpu_meshes.deinit();
    }
};
fn transformToMatrix(transform: *const components.TransformComponent) [4][4]f32 {
    const toRad = std.math.pi / 180.0;
    const pitch = transform.rotation[0] * toRad;
    const yaw = transform.rotation[1] * toRad;
    const roll = transform.rotation[2] * toRad;

    const cx = @cos(pitch);
    const sx = @sin(pitch);
    const cy = @cos(yaw);
    const sy = @sin(yaw);
    const cz = @cos(roll);
    const sz = @sin(roll);

    const sx_s = transform.scale[0];
    const sy_s = transform.scale[1];
    const sz_s = transform.scale[2];

    return [4][4]f32{
        .{ sx_s * (cy * cz), sy_s * (cy * sz), sz_s * (-sy), 0.0 },
        .{ sx_s * (sx * sy * cz - cx * sz), sy_s * (sx * sy * sz + cx * cz), sz_s * (sx * cy), 0.0 },
        .{ sx_s * (cx * sy * cz + sx * sz), sy_s * (cx * sy * sz - sx * cz), sz_s * (cx * cy), 0.0 },
        .{ transform.position[0], transform.position[1], transform.position[2], 1.0 },
    };
}

test "transformToMatrix: identity rotation/scale gives translation-only matrix" {
    const t = components.TransformComponent{
        .position = .{ 1.0, 2.0, 3.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    };
    const m = transformToMatrix(&t);
    const tol = 1e-5;
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[0][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[1][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[2][2], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), m[1][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), m[0][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), m[3][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), m[3][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), m[3][2], tol);
}

test "transformToMatrix: 90-degree yaw maps +X column onto -Z" {
    const t = components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 90.0, 0.0 },
        .scale = .{ 1.0, 1.0, 1.0 },
    };
    const m = transformToMatrix(&t);
    const tol = 1e-5;
    // yaw=90: first column (X axis) rotates to -Z, so m[0][0]~0 and m[0][2]~-1.
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), m[0][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), m[0][2], tol);
}

test "transformToMatrix: scale appears on the diagonal" {
    const t = components.TransformComponent{
        .position = .{ 0.0, 0.0, 0.0 },
        .rotation = .{ 0.0, 0.0, 0.0 },
        .scale = .{ 2.0, 3.0, 4.0 },
    };
    const m = transformToMatrix(&t);
    const tol = 1e-5;
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), m[0][0], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), m[1][1], tol);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), m[2][2], tol);
}
