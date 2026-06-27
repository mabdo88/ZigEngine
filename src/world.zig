const std = @import("std");
const flecs = @import("flecs.zig");
const platform = @import("platform/window.zig");
const components = @import("components.zig");
const math = @import("math.zig");
const gpu = @import("gpu.zig");
const zvkw = @import("renderer/zVulkanContext.zig");

pub const TransformComponent = components.TransformComponent;
pub const CameraComponent = components.CameraComponent;
pub const FrameState = components.FrameState;
pub const InputState = components.InputState;
pub const ViewProjComponent = components.ViewProjComponent;
pub const MeshComponent = components.MeshComponent;

const EcsIn: i16 = 4;
const EcsOut: i16 = 5;
const EcsInOut: i16 = 3;

fn inputSystem(it: [*c]flecs.c.ecs_iter_t) callconv(.c) void {
    const input: *components.InputState = @ptrCast(@alignCast(flecs.c.ecs_field_w_size(it, @sizeOf(components.InputState), 0)));
    for (0..512) |i| {
        input.keys[i] = platform.getKeyState(@intCast(i));
    }
}

fn cameraSystem(it: [*c]flecs.c.ecs_iter_t) callconv(.c) void {
    const input: *components.InputState = @ptrCast(@alignCast(flecs.c.ecs_field_w_size(it, @sizeOf(components.InputState), 0)));
    const cam: *components.CameraComponent = @ptrCast(@alignCast(flecs.c.ecs_field_w_size(it, @sizeOf(components.CameraComponent), 1)));
    const fs: *components.FrameState = @ptrCast(@alignCast(flecs.c.ecs_field_w_size(it, @sizeOf(components.FrameState), 2)));
    const vp: *components.ViewProjComponent = @ptrCast(@alignCast(flecs.c.ecs_field_w_size(it, @sizeOf(components.ViewProjComponent), 3)));

    const dt = fs.delta_t;

    const yaw_rad = cam.yaw * (std.math.pi / 180.0);
    const pitch_rad = cam.pitch * (std.math.pi / 180.0);

    const forward = components.Vec3{
        .x = @cos(yaw_rad) * @cos(pitch_rad),
        .y = @sin(pitch_rad),
        .z = @sin(yaw_rad) * @cos(pitch_rad),
    };
    const right = math.normalize(math.cross(forward, .{ .x = 0, .y = 1, .z = 0 }));

    const key_w = platform.Key.w;
    const key_a = platform.Key.a;
    const key_s = platform.Key.s;
    const key_d = platform.Key.d;

    if (input.keys[@intCast(key_w)]) {
        cam.position.x += forward.x * cam.speed * dt;
        cam.position.y += forward.y * cam.speed * dt;
        cam.position.z += forward.z * cam.speed * dt;
    }
    if (input.keys[@intCast(key_s)]) {
        cam.position.x -= forward.x * cam.speed * dt;
        cam.position.y -= forward.y * cam.speed * dt;
        cam.position.z -= forward.z * cam.speed * dt;
    }
    if (input.keys[@intCast(key_d)]) {
        cam.position.x += right.x * cam.speed * dt;
        cam.position.y += right.y * cam.speed * dt;
        cam.position.z += right.z * cam.speed * dt;
    }
    if (input.keys[@intCast(key_a)]) {
        cam.position.x -= right.x * cam.speed * dt;
        cam.position.y -= right.y * cam.speed * dt;
        cam.position.z -= right.z * cam.speed * dt;
    }

    const center = components.Vec3{
        .x = cam.position.x + forward.x,
        .y = cam.position.y + forward.y,
        .z = cam.position.z + forward.z,
    };

    const aspect: f32 = @as(f32, @floatFromInt(fs.extent_width)) / @as(f32, @floatFromInt(fs.extent_height));
    const view = math.lookAt(cam.position, center, .{ .x = 0, .y = 1, .z = 0 });
    const proj = math.perspective(cam.fov, aspect, cam.near, cam.far);

    vp.view = @bitCast(view);
    vp.proj = @bitCast(proj);
}

pub const World = struct {
    world: flecs.World,
    allocator: std.mem.Allocator,
    frame_state_id: flecs.Entity,
    input_state_id: flecs.Entity,
    transform_id: flecs.Entity,
    camera_id: flecs.Entity,
    viewproj_id: flecs.Entity,
    mesh_id: flecs.Entity,
    render_system_id: flecs.Entity,
    render_system_ctx: gpu.RenderSystemCtx,

    pub fn init(allocator: std.mem.Allocator) !World {
        var w = flecs.World.init();
        errdefer w.deinit();

        const fs_id = w.registerComponent(components.FrameState);
        w.setSingleton(components.FrameState, fs_id, .{});

        const input_id = w.registerComponent(components.InputState);
        w.setSingleton(components.InputState, input_id, .{});

        const tf_id = w.registerComponent(TransformComponent);

        const cam_id = w.registerComponent(CameraComponent);
        w.setSingleton(CameraComponent, cam_id, .{});

        const vp_id = w.registerComponent(components.ViewProjComponent);
        w.setSingleton(components.ViewProjComponent, vp_id, .{});

        const mesh_id = w.registerComponent(components.MeshComponent);

        _ = w.systemWithTerms("InputSystem", flecs.preUpdate(), &.{
            .{ .id = input_id, .inout = EcsOut, .is_singleton = true },
        }, inputSystem, null);

        _ = w.systemWithTerms("CameraSystem", flecs.onUpdate(), &.{
            .{ .id = input_id, .inout = EcsIn, .is_singleton = true },
            .{ .id = cam_id, .inout = EcsInOut, .is_singleton = true },
            .{ .id = fs_id, .inout = EcsIn, .is_singleton = true },
            .{ .id = vp_id, .inout = EcsOut, .is_singleton = true },
        }, cameraSystem, null);

        platform.installKeyCallback();

        var self: World = .{
            .world = w,
            .allocator = allocator,
            .frame_state_id = fs_id,
            .input_state_id = input_id,
            .transform_id = tf_id,
            .camera_id = cam_id,
            .viewproj_id = vp_id,
            .mesh_id = mesh_id,
            .render_system_id = 0,
            .render_system_ctx = .{ .vk_ctx = undefined },
        };

        _ = self.spawnEntity();

        return self;
    }

    pub fn registerRenderSystem(self: *World, vk_ctx: *zvkw.VulkanContext) void {
        self.render_system_ctx = .{ .vk_ctx = vk_ctx };
        self.render_system_id = gpu.registerRenderSystem(&self.world, &self.render_system_ctx, self.viewproj_id);
    }

    pub fn spawnEntity(self: *World) flecs.Entity {
        const e = self.world.newEntity();
        self.world.set(e, TransformComponent, self.transform_id, .{});
        return e;
    }

    pub fn fixedUpdate(self: *World, dt: f32, extent_width: u32, extent_height: u32) !void {
        if (self.world.getSingleton(components.FrameState, self.frame_state_id)) |fs| {
            fs.delta_t = dt;
            fs.frame_index += 1;
            fs.extent_width = extent_width;
            fs.extent_height = extent_height;
        }
        _ = self.world.progress(dt);
    }

    pub fn renderUpdate(self: *World, alpha: f32) !void {
        if (self.world.getSingleton(components.FrameState, self.frame_state_id)) |fs| {
            fs.interpolation_alpha = alpha;
        }
    }

    pub fn deinit(self: *World) void {
        self.world.deinit();
    }
};
