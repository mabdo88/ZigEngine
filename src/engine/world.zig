const std = @import("std");
const Registry = @import("registry.zig").Registry;
const Entity = @import("entity.zig").Entity;
const scomponent = @import("../components/SystemComponents.zig");
const systems = @import("../renderer/systems.zig");
const vkctx = @import("../renderer/zVulkanContext.zig");
const RenderSystem = @import("../renderer/renderSystem.zig").RenderSystem;
const rs = @import("../renderer/renderSystem.zig");
const upload = @import("../renderer/upload.zig");
const meshLoader = @import("../resources/meshLoader.zig");
const component = @import("../components/components.zig");

pub const World = struct {
    registry: Registry = undefined,
    render_system: RenderSystem = undefined,
    world_allocator: std.mem.Allocator = undefined,
    window: scomponent.WindowComponent = .{ .title = "ZVulkan Window", .width = vkctx.default_window_width, .height = vkctx.default_window_height },

    pub fn init(self: *World, allocator: std.mem.Allocator) !void {
        std.log.info("Initializing World...", .{});
        self.world_allocator = allocator;
        self.registry.init(self.world_allocator);
        std.log.info("World Created", .{});
    }

    pub fn deinit(self: *World) void {
        systems.renderer.deinit(&self.registry, &self.render_system);
        std.log.info("World running with {d} entities before shutdown", .{self.registry.aliveCount()});
        self.registry.deinit();
        self.world_allocator = undefined;
        std.log.info("World Destroyed", .{});
    }

    pub fn initVulkan(self: *World, title: ?[:0]const u8, width: u16, height: u16) !void {
        _ = try systems.renderer.init(self.world_allocator, title, width, height, &self.registry, &self.render_system);
    }

    pub fn run(self: *World, context: anytype, updateFn: anytype) !void {
        std.log.info("World running with {d} entities", .{self.registry.aliveCount()});
        var last_time = vkctx.zvk.vkGetTime();
        while (!systems.renderer.shouldClose()) {
            systems.renderer.pollEvents();
            const now = vkctx.zvk.vkGetTime();
            const dt: f32 = @floatCast(now - last_time);
            last_time = now;

            // Call user-provided update function with context and delta time
            updateFn(context, dt);

            const matrices = systems.camera.update(&self.registry, systems.renderer.aspectRatio());
            try systems.renderer.render(matrices.?, &self.registry, &self.render_system);
        }
        // Wait for GPU to finish last frame before cleanup
        _ = vkctx.zvk.vkDeviceWaitIdle(vkctx.ctx.m_Device);
    }

    pub fn uploadTexture(self: *World, pixels: []const u8, width: u32, height: u32) !vkctx.TextureHandle {
        _ = self;
        return systems.renderer.uploadTexture(pixels, width, height);
    }

    pub fn registryPtr(self: *World) *Registry {
        return &self.registry;
    }

    /// Loads a glTF scene file and populates the ECS world with entities.
    /// CPU parsing and image decoding run on a background thread.
    /// GPU uploads are batched into a single command buffer on the main thread.
    /// Returns a slice of created entities — caller owns it and must free with allocator.
    /// Call Registry.destroyEntity on each entity in deinit.
    pub fn loadScene(self: *World, allocator: std.mem.Allocator, path: [:0]const u8) ![]Entity {
        // --- Phase 1: CPU load on background thread ---
        const LoadCtx = struct {
            allocator: std.mem.Allocator,
            path: [:0]const u8,
            scene: meshLoader.GltfScene = undefined,
            err: ?anyerror = null,

            fn run(ctx: *@This()) void {
                ctx.scene = meshLoader.loadgltf(ctx.allocator, ctx.path) catch |e| {
                    ctx.err = e;
                    return;
                };
            }
        };
        var load_ctx = LoadCtx{ .allocator = allocator, .path = path };
        const t0 = vkctx.zvk.vkGetTime();
        const thread = try std.Thread.spawn(.{}, LoadCtx.run, .{&load_ctx});
        thread.join();
        if (load_ctx.err) |e| return e;
        var scene = load_ctx.scene;
        defer scene.deinit();
        std.log.info("loadScene phase1 (CPU parse+decode): {d:.0}ms", .{(vkctx.zvk.vkGetTime() - t0) * 1000.0});

        // --- Phase 2: GPU uploads batched into one command buffer ---
        const t1 = vkctx.zvk.vkGetTime();
        var batch = try upload.UploadBatch.begin(allocator);

        // Upload all unique textures
        const tex_handles = try allocator.alloc(vkctx.TextureHandle, scene.materials.len);
        defer allocator.free(tex_handles);
        for (scene.materials, 0..) |mat, mi| {
            tex_handles[mi] = try systems.renderer.uploadTextureBatched(&batch, mat.pixels, mat.width, mat.height);
        }

        // Upload all unique meshes
        const gpu_meshes = try allocator.alloc(rs.GpuMesh, scene.meshes.len);
        defer allocator.free(gpu_meshes);
        for (scene.meshes, 0..) |mesh, mi| {
            const mesh_comp = component.MeshComponent{
                .vertices = mesh.vertices,
                .indices = mesh.indices,
                .owns_memory = false,
            };
            try rs.recordMeshUpload(&batch, &mesh_comp, &gpu_meshes[mi]);
        }

        try batch.submit();
        std.log.info("loadScene phase2 (GPU batch upload): {d:.0}ms", .{(vkctx.zvk.vkGetTime() - t1) * 1000.0});

        // --- Phase 3: Create ECS entities ---
        const entities = try allocator.alloc(Entity, scene.primitives.len);
        for (scene.primitives, 0..) |prim, i| {
            const entity = try self.registry.createEntity();
            const mesh = scene.meshes[prim.mesh_idx];
            const mesh_comp = component.MeshComponent{
                .vertices = mesh.vertices,
                .indices = mesh.indices,
                .owns_memory = false,
            };
            try self.registry.attach(entity, mesh_comp);
            try self.registry.attach(entity, component.TextureComponent{
                .textureIndex = tex_handles[prim.material_idx],
            });
            // Store node transform directly into the gpu_meshes map so the
            // render system can draw with the correct world matrix
            try self.render_system.gpu_meshes.put(entity, gpu_meshes[prim.mesh_idx]);
            // Attach transform from scene graph
            const t = prim.transform;
            try self.registry.attach(entity, component.TransformComponent{
                .position = .{ t[3][0], t[3][1], t[3][2] },
                .rotation = .{ 0, 0, 0 },
                .scale = .{ 1, 1, 1 },
            });
            entities[i] = entity;
        }

        std.log.info("loadScene '{s}': {d} entities created", .{ path, entities.len });
        return entities;
    }
};
