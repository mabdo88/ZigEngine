const std = @import("std");
const zvkw = @import("zVulkanContext.zig");
const components = @import("../engine/ecs/components/components.zig");
const Registry = @import("../engine/ecs/entity/registry.zig").Registry;
const Entity = @import("../engine/ecs/entity/entity.zig").Entity;
const upload = @import("upload.zig");
const math = @import("../engine/math.zig");
const event = @import("../engine/ecs/event.zig");
const meshCache = @import("../resources/meshCache.zig");
const log = @import("../engine/log.zig");

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
    entity_meshes: std.AutoHashMap(Entity, u32),

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
            .entity_meshes = std.AutoHashMap(Entity, u32).init(allocator),
        };
    }

    pub fn initCapacity(ctx: *zvkw.VulkanContext, allocator: std.mem.Allocator, mesh_capacity: u32, shared_capacity: u32) !RenderSystem {
        var self = RenderSystem.init(ctx, allocator);
        try self.gpu_meshes.ensureTotalCapacity(mesh_capacity);
        try self.entity_meshes.ensureTotalCapacity(shared_capacity);
        return self;
    }

    pub fn onEntityDestroyed(ctx: *anyopaque, payload: event.EventPayload) void {
        const self: *RenderSystem = @ptrCast(@alignCast(ctx));
        const entity = payload.entity_destroyed;
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

    pub fn attachMesh(self: *RenderSystem, entity: Entity, mesh_id: u32, gpu_mesh: *GpuMesh) !void {
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

    pub fn update(self: *RenderSystem, registry: *Registry, cb: zvkw.zvk.VkCommandBuffer, dt: f32) !void {
        _ = dt;
        zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.ctx.pipelineLayout, 0, 1, &self.ctx.uboDescriptorSets[self.ctx.frameIndex], 0, null);
        zvkw.zvk.vkCmdBindDescriptorSets(cb, zvkw.zvk.VK_PIPELINE_BIND_POINT_GRAPHICS, self.ctx.pipelineLayout, 1, 1, &self.ctx.bindlessDescriptorSet, 0, null);

        const frame_base = self.ctx.frameIndex * zvkw.SKIN_MATRICES_PER_FRAME;
        var next_skin_slot: u32 = zvkw.SKIN_IDENTITY_SLOT + 1;

        var it = registry.Query(.{components.MeshComponent});
        while (it.next()) |entity| {
            const mesh = registry.get(components.MeshComponent, entity).?;
            if (!mesh.isValid()) continue;
            const mesh_id = mesh.mesh_id;
            if (!self.entity_meshes.contains(entity)) {
                if (self.gpu_meshes.get(mesh_id)) |shared| {
                    shared.refcount += 1;
                    try self.entity_meshes.put(entity, mesh_id);
                } else {
                    const mesh_data = registry.mesh_cache.get(mesh_id) orelse continue;
                    const gpu_mesh = try uploadMesh(self.ctx, self.allocator, mesh_data);
                    try self.attachMesh(entity, mesh_id, gpu_mesh);
                    log.info(@src(), "RenderSystem: uploaded mesh_id {d} for entity {}", .{ mesh_id, entity.index });
                }
            }

            const model_matrix = if (registry.get(components.FinalTransformComponent, entity)) |ft| ft.matrix else math.identityMatrix();

            // Writes this entity's skin matrices (world * inverse_bind, from
            // SkinPaletteComponent — distinct from JointWorldComponent, which
            // is debug-draw-only world transforms) into the current frame's
            // region of the skin matrix buffer and points the push constant
            // at them; falls back to SKIN_IDENTITY_SLOT (a no-op
            // vertex.joints lookup, see Vertex's doc comment) if there's no
            // skin, or if this frame's region is already full.
            var skin_offset = frame_base + zvkw.SKIN_IDENTITY_SLOT;
            if (registry.get(components.SkinPaletteComponent, entity)) |skin_comp| {
                const count: u32 = @intCast(skin_comp.matrices.len);
                if (next_skin_slot + count <= zvkw.SKIN_MATRICES_PER_FRAME) {
                    const dst = self.ctx.skinMatrixBufferMapped.?[frame_base + next_skin_slot ..][0..count];
                    @memcpy(dst, skin_comp.matrices);
                    skin_offset = frame_base + next_skin_slot;
                    next_skin_slot += count;
                } else {
                    log.warn(@src(), "RenderSystem: skin matrix buffer full this frame, entity {} renders unskinned", .{entity.index});
                }
            }

            const gpu_mesh = self.gpu_meshes.get(mesh_id).?;
            const offset: zvkw.zvk.VkDeviceSize = 0;
            zvkw.zvk.vkCmdBindVertexBuffers(cb, 0, 1, &gpu_mesh.vertexBuffer, &offset);
            zvkw.zvk.vkCmdBindIndexBuffer(cb, gpu_mesh.indexBuffer, 0, zvkw.zvk.VK_INDEX_TYPE_UINT32);
            const pc = zvkw.PushConstants{
                .model = model_matrix,
                .materialIndex = if (registry.get(components.MaterialComponent, entity)) |mc| mc.material_index else 0,
                .skinOffset = skin_offset,
            };

            zvkw.zvk.vkCmdPushConstants(cb, self.ctx.pipelineLayout, zvkw.zvk.VK_SHADER_STAGE_VERTEX_BIT | zvkw.zvk.VK_SHADER_STAGE_FRAGMENT_BIT, 0, @sizeOf(zvkw.PushConstants), @ptrCast(&pc));
            zvkw.zvk.vkCmdDrawIndexed(cb, gpu_mesh.indexCount, 1, 0, 0, 0);
        }
    }

    pub fn updateShadow(self: *RenderSystem, registry: *Registry, cb: zvkw.zvk.VkCommandBuffer, light_view_proj: [4][4]f32) !void {
        var it = registry.Query(.{components.MeshComponent});
        while (it.next()) |entity| {
            const mesh = registry.get(components.MeshComponent, entity).?;
            if (!mesh.isValid()) continue;
            const gpu_mesh = self.gpu_meshes.get(mesh.mesh_id) orelse continue;

            const model_matrix = if (registry.get(components.FinalTransformComponent, entity)) |ft| ft.matrix else math.identityMatrix();

            const offset: zvkw.zvk.VkDeviceSize = 0;
            zvkw.zvk.vkCmdBindVertexBuffers(cb, 0, 1, &gpu_mesh.vertexBuffer, &offset);
            zvkw.zvk.vkCmdBindIndexBuffer(cb, gpu_mesh.indexBuffer, 0, zvkw.zvk.VK_INDEX_TYPE_UINT32);
            const pc = zvkw.ShadowPushConstants{ .mvp = math.matMul(light_view_proj, model_matrix) };
            zvkw.zvk.vkCmdPushConstants(cb, self.ctx.shadowPipelineLayout, zvkw.zvk.VK_SHADER_STAGE_VERTEX_BIT, 0, @sizeOf(zvkw.ShadowPushConstants), @ptrCast(&pc));
            zvkw.zvk.vkCmdDrawIndexed(cb, gpu_mesh.indexCount, 1, 0, 0, 0);
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
