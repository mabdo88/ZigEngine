const std = @import("std");
const zvkw = @import("zVulkanContext.zig");
const components = @import("../engine/ecs/components/components.zig");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const upload = @import("upload.zig");
const math = @import("../engine/math.zig");
const event = @import("../engine/ecs/event.zig");

fn check(result: zvkw.zvk.VkResult) !void {
    if (result != zvkw.zvk.VK_SUCCESS) return error.VulkanCallFailed;
}

pub const GpuMesh = struct {
    vertexBuffer: zvkw.zvk.VkBuffer,
    vertexAllocation: zvkw.vma.VmaAllocation,
    indexBuffer: zvkw.zvk.VkBuffer,
    indexAllocation: zvkw.vma.VmaAllocation,
    indexCount: u32,
    refcount: u32 = 1,
};

const MeshKey = struct {
    vertexBuffer: zvkw.zvk.VkBuffer,
    indexBuffer: zvkw.zvk.VkBuffer,
};

fn uploadMesh(allocator: std.mem.Allocator, mesh: *const components.MeshComponent) !*GpuMesh {
    var batch = try upload.UploadBatch.begin(&zvkw.ctx, allocator);
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
    gpu_meshes: std.AutoHashMap(Entity, *GpuMesh),
    shared_meshes: std.AutoHashMap(MeshKey, *GpuMesh),

    pub fn init(allocator: std.mem.Allocator) RenderSystem {
        return .{
            .allocator = allocator,
            .gpu_meshes = std.AutoHashMap(Entity, *GpuMesh).init(allocator),
            .shared_meshes = std.AutoHashMap(MeshKey, *GpuMesh).init(allocator),
        };
    }

    pub fn initCapacity(allocator: std.mem.Allocator, mesh_capacity: u32, shared_capacity: u32) !RenderSystem {
        var self = RenderSystem.init(allocator);
        try self.gpu_meshes.ensureTotalCapacity(mesh_capacity);
        try self.shared_meshes.ensureTotalCapacity(shared_capacity);
        return self;
    }

    pub fn onEntityDestroyed(ctx: *anyopaque, payload: event.EventPayload) void {
        const self: *RenderSystem = @ptrCast(@alignCast(ctx));
        const entity = payload.entity_destroyed;
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

    pub fn attachMesh(self: *RenderSystem, entity: Entity, gpu_mesh: *GpuMesh) !void {
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
            shared.refcount += 1;
            try self.gpu_meshes.put(entity, shared);
            self.allocator.destroy(gpu_mesh);
            return;
        }

        gpu_mesh.refcount = 1;
        try self.shared_meshes.put(key, gpu_mesh);
        try self.gpu_meshes.put(entity, gpu_mesh);
    }

    pub fn update(self: *RenderSystem, registry: *Registry, cb: zvkw.zvk.VkCommandBuffer, dt: f32) !void {
        _ = dt;
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

            const model_matrix = blk: {
                const world = if (registry.get(components.WorldTransformComponent, entity)) |wt| wt.matrix else math.identityMatrix();
                const local = if (registry.get(components.TransformComponent, entity)) |transform| math.transformToMatrix(transform) else math.identityMatrix();
                break :blk math.matMul(world, local);
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
