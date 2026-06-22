const std = @import("std");
const zvkw = @import("zVulkanContext.zig");
const components = @import("../engine/ecs/components/components.zig");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
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
    /// Number of entities referencing this GPU mesh. Shared geometry (e.g.
    /// Sketchfab-style glTF models) reuses the same buffer; free only when
    /// the count reaches zero.
    refcount: u32 = 1,
};

const MeshKey = struct {
    vertexBuffer: zvkw.zvk.VkBuffer,
    indexBuffer: zvkw.zvk.VkBuffer,
};

/// Upload a single mesh immediately (one submit). Used for late/lazy uploads during render.
/// Returns a heap-allocated GpuMesh with refcount = 1.
fn uploadMesh(allocator: std.mem.Allocator, mesh: *const components.MeshComponent) !*GpuMesh {
    var batch = try upload.UploadBatch.begin(allocator);
    var gpuMesh = try allocator.create(GpuMesh);
    errdefer allocator.destroy(gpuMesh);
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
    gpuMesh.refcount = 1;
    try batch.submit();
    return gpuMesh;
}

/// Record a mesh upload into an existing UploadBatch (no submit — caller submits).
/// The caller owns `out` and must allocate it before calling.
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
    allocator: std.mem.Allocator,
    /// Per-entity reference to a shared GpuMesh.
    gpu_meshes: std.AutoHashMap(Entity, *GpuMesh),
    /// Shared mesh registry keyed by buffer handles. Each entry is allocated once
    /// and referenced by every entity that uses the same geometry.
    shared_meshes: std.AutoHashMap(MeshKey, *GpuMesh),

    pub fn init(allocator: std.mem.Allocator) RenderSystem {
        return .{
            .allocator = allocator,
            .gpu_meshes = std.AutoHashMap(Entity, *GpuMesh).init(allocator),
            .shared_meshes = std.AutoHashMap(MeshKey, *GpuMesh).init(allocator),
        };
    }

    /// Registry destroy hook: drops the entity's reference. If the shared mesh
    /// has no remaining references, its GPU buffers are destroyed.
    pub fn onEntityDestroyed(ctx: *anyopaque, entity: Entity) void {
        const self: *RenderSystem = @ptrCast(@alignCast(ctx));
        if (self.gpu_meshes.fetchRemove(entity)) |kv| {
            const shared = kv.value;
            shared.refcount -= 1;
            if (shared.refcount == 0) {
                _ = self.shared_meshes.remove(.{
                    .vertexBuffer = shared.vertexBuffer,
                    .indexBuffer = shared.indexBuffer,
                });
                zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(shared.vertexBuffer), shared.vertexAllocation);
                zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(shared.indexBuffer), shared.indexAllocation);
                self.allocator.destroy(shared);
            }
        }
    }

    /// Associate a GPU mesh with an entity. If the same buffer pair is already
    /// registered, the existing shared object is reused and its refcount is
    /// incremented; otherwise the provided `gpu_mesh` is registered as shared.
    pub fn attachMesh(self: *RenderSystem, entity: Entity, gpu_mesh: *GpuMesh) !void {
        // Drop any existing reference this entity holds.
        if (self.gpu_meshes.fetchRemove(entity)) |kv| {
            const old = kv.value;
            old.refcount -= 1;
            if (old.refcount == 0) {
                _ = self.shared_meshes.remove(.{
                    .vertexBuffer = old.vertexBuffer,
                    .indexBuffer = old.indexBuffer,
                });
                zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(old.vertexBuffer), old.vertexAllocation);
                zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(old.indexBuffer), old.indexAllocation);
                self.allocator.destroy(old);
            }
        }

        const key = MeshKey{
            .vertexBuffer = gpu_mesh.vertexBuffer,
            .indexBuffer = gpu_mesh.indexBuffer,
        };
        if (self.shared_meshes.get(key)) |shared| {
            // Reuse existing shared object; discard the caller's copy.
            shared.refcount += 1;
            try self.gpu_meshes.put(entity, shared);
            self.allocator.destroy(gpu_mesh);
            return;
        }

        // Register the provided mesh as the canonical shared object.
        gpu_mesh.refcount = 1;
        try self.shared_meshes.put(key, gpu_mesh);
        try self.gpu_meshes.put(entity, gpu_mesh);
    }

    pub fn update(self: *RenderSystem, registry: *Registry, cb: zvkw.zvk.VkCommandBuffer, dt: f32) !void {
        zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, zvkw.ctx.pipelineLayout, 0, 1, &zvkw.ctx.uboDescriptorSets[zvkw.ctx.frameIndex], 0, null);
        zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, zvkw.ctx.pipelineLayout, 1, 1, &zvkw.ctx.bindlessDescriptorSet, 0, null);
        var it = registry.Query(.{components.MeshComponent});
        while (it.next()) |entity| {
            const mesh = registry.get(components.MeshComponent, entity).?;
            if (!mesh.isValid()) continue;
            if (!self.gpu_meshes.contains(entity)) {
                const gpu_mesh = try uploadMesh(self.allocator, mesh);
                try self.attachMesh(entity, gpu_mesh);
                std.log.info("RenderSystem: uploaded mesh for entity {}", .{entity.index});
            }

            if (registry.get(components.TransformComponent, entity)) |transform| {
                if (registry.get(components.SceneOwnedComponent, entity)) |owned| {
                    var active_it = registry.Query(.{ components.SceneComponent, components.SceneActiveTag });
                    if (active_it.next()) |active| {
                        const scene = registry.get(components.SceneComponent, active).?;
                        if (std.mem.eql(u8, scene.name, "Duck") and owned.owner.index == active.index) {
                            transform.rotation[1] += 90.0 * dt;
                            if (transform.rotation[1] > 360.0) transform.rotation[1] -= 360.0;
                        }
                    }
                }
            }

            const model_matrix = blk: {
                const world = if (registry.get(components.WorldTransformComponent, entity)) |wt| wt.matrix else identityMatrix();
                const local = if (registry.get(components.TransformComponent, entity)) |transform| transformToMatrix(transform) else identityMatrix();
                break :blk matMul(world, local);
            };

            const gpu_mesh = self.gpu_meshes.get(entity).?;
            const offset: zvkw.zvk.VkDeviceSize = 0;
            zvkw.zvk.vkCmdBindVertexBuffers(cb, 0, 1, &gpu_mesh.vertexBuffer, &offset);
            zvkw.zvk.vkCmdBindIndexBuffer(cb, gpu_mesh.indexBuffer, 0, zvkw.zvk.VK_INDEX_TYPE_UINT32);
            const pc = zvkw.PushConstants{
                .model = model_matrix,
                .textureIndex = if (registry.get(components.TextureComponent, entity)) |tc| tc.textureIndex else 0,
            };

            zvkw.zvk.vkCmdPushConstants(cb, zvkw.ctx.pipelineLayout, zvkw.zvk.VK_SHADER_STAGE_VERTEX_BIT | zvkw.zvk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(zvkw.PushConstants), @ptrCast(&pc));
            zvkw.zvk.vkCmdDrawIndexed(cb, gpu_mesh.indexCount, 1, 0, 0, 0);
        }
    }

    pub fn deinit(self: *RenderSystem) void {
        var it = self.shared_meshes.valueIterator();
        while (it.next()) |shared_ptr| {
            const shared = shared_ptr.*;
            zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(shared.vertexBuffer), shared.vertexAllocation);
            zvkw.vma.vmaDestroyBuffer(zvkw.ctx.vmaAllocator, @ptrCast(shared.indexBuffer), shared.indexAllocation);
            self.allocator.destroy(shared);
        }
        self.gpu_meshes.deinit();
        self.shared_meshes.deinit();
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
fn identityMatrix() [4][4]f32 {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

fn matMul(a: [4][4]f32, b: [4][4]f32) [4][4]f32 {
    var r: [4][4]f32 = std.mem.zeroes([4][4]f32);
    for (0..4) |row| {
        for (0..4) |col| {
            for (0..4) |k| {
                r[col][row] += a[k][row] * b[col][k];
            }
        }
    }
    return r;
}

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
