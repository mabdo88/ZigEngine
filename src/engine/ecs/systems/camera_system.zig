const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const math = @import("../../math.zig");

pub const CameraSystemState = struct {
    aspect: f32 = 1.0,

    pub fn update(self: *CameraSystemState, registry: *Registry, dt: f32) anyerror!void {
        _ = dt;
        var it = registry.Query(.{components.CameraComponent});
        const cam_entity = it.next() orelse return;
        const camera = registry.get(components.CameraComponent, cam_entity).?;

        const view = math.lookAt(camera.position, camera.target, camera.up);
        const projection = math.perspective(camera.fov, camera.near, camera.far, self.aspect);

        try registry.set(cam_entity, components.CameraMatricesComponent{
            .view = view,
            .proj = projection,
        });
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *CameraSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}
