const std = @import("std");
const zvkw = @import("zVulkanContext.zig");
const components = @import("../components/components.zig");
const Registry = @import("../engine/registry.zig").Registry;
const Entity = @import("../engine/entity.zig").Entity;
const cs = @import("cameraSystem.zig");
const upload = @import("upload.zig");

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

/// Upload a single mesh immediately (one submit). Used for late/lazy uploads during render.
fn uploadMesh(mesh: *const components.MeshComponent) !GpuMesh {
    var batch = try upload.UploadBatch.begin(zvkw.ctx.zallocator);
    var gpuMesh: GpuMesh = undefined;
    try batch.uploadBuffer(
        mesh.vertices.ptr,
        @sizeOf(components.Vertex) * mesh.vertices.len,
        zvkw.zvk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        &gpuMesh.vertexBuffer,
        &gpuMesh.vertexAllocation,
    );
    try batch.uploadBuffer(
        mesh.indices.ptr,
        @sizeOf(u32) * mesh.indices.len,
        zvkw.zvk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        &gpuMesh.indexBuffer,
        &gpuMesh.indexAllocation,
    );
    gpuMesh.indexCount = @intCast(mesh.indices.len);
    try batch.submit();
    return gpuMesh;
}

/// Record a mesh upload into an existing UploadBatch (no submit — caller submits).
pub fn recordMeshUpload(batch: *upload.UploadBatch, mesh: *const components.MeshComponent, out: *GpuMesh) !void {
    try batch.uploadBuffer(
        mesh.vertices.ptr,
        @sizeOf(components.Vertex) * mesh.vertices.len,
        zvkw.zvk.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT,
        &out.vertexBuffer,
        &out.vertexAllocation,
    );
    try batch.uploadBuffer(
        mesh.indices.ptr,
        @sizeOf(u32) * mesh.indices.len,
        zvkw.zvk.VK_BUFFER_USAGE_INDEX_BUFFER_BIT,
        &out.indexBuffer,
        &out.indexAllocation,
    );
    out.indexCount = @intCast(mesh.indices.len);
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
/// Converts a TransformComponent to a 4x4 column-major model matrix.
/// Rotation order is YXZ (yaw-pitch-roll intrinsic), which is:
///   - yaw (Y-axis) first
///   - pitch (X-axis) second
///   - roll (Z-axis) third
/// This order avoids gimbal lock for typical camera/object rotations where
/// yaw is the primary horizontal rotation. For full 3D rotations with all
/// three axes active, consider using quaternions instead.
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
