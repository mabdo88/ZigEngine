const std = @import("std");
const zvkw = @import("zVulkanContext.zig");
const components = @import("../engine/ecs/components/components.zig");
const flecs = @import("../engine/ecs/flecs.zig");
const upload = @import("upload.zig");
const math = @import("../engine/math.zig");
const meshCache = @import("../resources/meshCache.zig");

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

fn uploadMesh(ctx: *zvkw.VulkanContext, allocator: std.mem.Allocator, mesh: meshCache.MeshData) !*GpuMesh {
    var batch = try upload.UploadBatch.begin(ctx, allocator);
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

pub fn recordMeshUpload(batch: *upload.UploadBatch, mesh: meshCache.MeshData, out: *GpuMesh) !void {
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
    ctx: *zvkw.VulkanContext,
    allocator: std.mem.Allocator,
    gpu_meshes: std.AutoHashMap(u32, *GpuMesh),
    entity_meshes: std.AutoHashMap(flecs.Entity, u32),

    pub fn preloadMeshBatched(self: *RenderSystem, batch: *upload.UploadBatch, mesh_id: u32, mesh_data: meshCache.MeshData) !void {
        if (self.gpu_meshes.contains(mesh_id)) return;
        const gpu_mesh = try self.allocator.create(GpuMesh);
        try recordMeshUpload(batch, mesh_data, gpu_mesh);
        gpu_mesh.refcount = 1;
        try self.gpu_meshes.put(mesh_id, gpu_mesh);
    }

    pub fn init(ctx: *zvkw.VulkanContext, allocator: std.mem.Allocator) RenderSystem {
        return .{
            .ctx = ctx,
            .allocator = allocator,
            .gpu_meshes = std.AutoHashMap(u32, *GpuMesh).init(allocator),
            .entity_meshes = std.AutoHashMap(flecs.Entity, u32).init(allocator),
        };
    }

    pub fn initCapacity(ctx: *zvkw.VulkanContext, allocator: std.mem.Allocator, mesh_capacity: u32, shared_capacity: u32) !RenderSystem {
        var self = RenderSystem.init(ctx, allocator);
        try self.gpu_meshes.ensureTotalCapacity(mesh_capacity);
        try self.entity_meshes.ensureTotalCapacity(shared_capacity);
        return self;
    }

    pub fn onMeshRemoved(it: [*c]flecs.c.ecs_iter_t) callconv(.c) void {
        const it_ptr: *flecs.c.ecs_iter_t = @ptrCast(it);
        const self: *RenderSystem = @ptrCast(@alignCast(it_ptr.ctx.?));
        var i: i32 = 0;
        while (i < it_ptr.count) : (i += 1) {
            const entity = it_ptr.entities[@intCast(i)];
            if (self.entity_meshes.fetchRemove(entity)) |kv| {
                const mesh_id = kv.value;
                if (self.gpu_meshes.get(mesh_id)) |gpu_mesh| {
                    gpu_mesh.refcount -= 1;
                    if (gpu_mesh.refcount == 0) {
                        _ = self.gpu_meshes.remove(mesh_id);
                        zvkw.vma.vmaDestroyBuffer(self.ctx.vmaAllocator, @ptrCast(gpu_mesh.vertexBuffer), gpu_mesh.vertexAllocation);
                        zvkw.vma.vmaDestroyBuffer(self.ctx.vmaAllocator, @ptrCast(gpu_mesh.indexBuffer), gpu_mesh.indexAllocation);
                        self.allocator.destroy(gpu_mesh);
                    }
                }
            }
        }
    }

    pub fn attachMesh(self: *RenderSystem, entity: flecs.Entity, mesh_id: u32, gpu_mesh: *GpuMesh) !void {
        if (self.entity_meshes.fetchRemove(entity)) |kv| {
            const old_mesh_id = kv.value;
            if (self.gpu_meshes.get(old_mesh_id)) |old| {
                old.refcount -= 1;
                if (old.refcount == 0) {
                    _ = self.gpu_meshes.remove(old_mesh_id);
                    zvkw.vma.vmaDestroyBuffer(self.ctx.vmaAllocator, @ptrCast(old.vertexBuffer), old.vertexAllocation);
                    zvkw.vma.vmaDestroyBuffer(self.ctx.vmaAllocator, @ptrCast(old.indexBuffer), old.indexAllocation);
                    self.allocator.destroy(old);
                }
            }
        }

        if (self.gpu_meshes.get(mesh_id)) |shared| {
            shared.refcount += 1;
            try self.entity_meshes.put(entity, mesh_id);
            zvkw.vma.vmaDestroyBuffer(self.ctx.vmaAllocator, @ptrCast(gpu_mesh.vertexBuffer), gpu_mesh.vertexAllocation);
            zvkw.vma.vmaDestroyBuffer(self.ctx.vmaAllocator, @ptrCast(gpu_mesh.indexBuffer), gpu_mesh.indexAllocation);
            self.allocator.destroy(gpu_mesh);
            return;
        }

        gpu_mesh.refcount = 1;
        try self.gpu_meshes.put(mesh_id, gpu_mesh);
        try self.entity_meshes.put(entity, mesh_id);
    }

    pub fn update(self: *RenderSystem, world: *flecs.World, ids: components.ComponentIds, mesh_cache: *meshCache.MeshCache, cb: zvkw.zvk.VkCommandBuffer, dt: f32) !void {
        _ = dt;
        zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.ctx.pipelineLayout, 0, 1, &self.ctx.uboDescriptorSets[self.ctx.frameIndex], 0, null);
        zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.ctx.pipelineLayout, 1, 1, &self.ctx.bindlessDescriptorSet, 0, null);
        var q = world.query(&.{ids.Mesh});
        defer q.deinit();
        var it = q.iter();
        while (it.next()) {
            const meshes = it.field(components.MeshComponent, 0);
            var row: i32 = 0;
            while (row < it.count()) : (row += 1) {
                const entity = it.entity(row);
                const mesh = &meshes[@intCast(row)];
                if (!mesh.isValid()) continue;
                const mesh_id = mesh.mesh_id;
                if (!self.entity_meshes.contains(entity)) {
                    if (self.gpu_meshes.get(mesh_id)) |shared| {
                        shared.refcount += 1;
                        try self.entity_meshes.put(entity, mesh_id);
                    } else {
                        const mesh_data = mesh_cache.get(mesh_id) orelse continue;
                        const gpu_mesh = try uploadMesh(self.ctx, self.allocator, mesh_data);
                        try self.attachMesh(entity, mesh_id, gpu_mesh);
                        std.log.info("RenderSystem: uploaded mesh_id {d} for entity {d}", .{ mesh_id, entity });
                    }
                }

                const model_matrix = blk: {
                    const world_mat = if (world.get(entity, components.WorldTransformComponent, ids.WorldTransform)) |wt| wt.matrix else math.identityMatrix();
                    const local = if (world.get(entity, components.TransformComponent, ids.Transform)) |transform| math.transformToMatrix(transform) else math.identityMatrix();
                    break :blk math.matMul(world_mat, local);
                };

                const gpu_mesh = self.gpu_meshes.get(mesh_id).?;
                const offset: zvkw.zvk.VkDeviceSize = 0;
                zvkw.zvk.vkCmdBindVertexBuffers(cb, 0, 1, &gpu_mesh.vertexBuffer, &offset);
                zvkw.zvk.vkCmdBindIndexBuffer(cb, gpu_mesh.indexBuffer, 0, zvkw.zvk.VK_INDEX_TYPE_UINT32);
                const pc = zvkw.PushConstants{
                    .model = model_matrix,
                    .textureIndex = if (world.get(entity, components.TextureComponent, ids.Texture)) |tc| tc.textureIndex else 0,
                };

                zvkw.zvk.vkCmdPushConstants(cb, self.ctx.pipelineLayout, zvkw.zvk.VK_SHADER_STAGE_VERTEX_BIT | zvkw.zvk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(zvkw.PushConstants), @ptrCast(&pc));
                zvkw.zvk.vkCmdDrawIndexed(cb, gpu_mesh.indexCount, 1, 0, 0, 0);
            }
        }
    }

    pub fn deinit(self: *RenderSystem) void {
        var it = self.gpu_meshes.valueIterator();
        while (it.next()) |gpu_mesh_ptr| {
            const gpu_mesh = gpu_mesh_ptr.*;
            zvkw.vma.vmaDestroyBuffer(self.ctx.vmaAllocator, @ptrCast(gpu_mesh.vertexBuffer), gpu_mesh.vertexAllocation);
            zvkw.vma.vmaDestroyBuffer(self.ctx.vmaAllocator, @ptrCast(gpu_mesh.indexBuffer), gpu_mesh.indexAllocation);
            self.allocator.destroy(gpu_mesh);
        }
        self.gpu_meshes.deinit();
        self.entity_meshes.deinit();
    }
};
