//! Computes view/projection matrices from the (single) camera entity and writes
//! them to its CameraMatricesComponent for render_system to consume. Pure ECS:
//! reads CameraComponent, writes CameraMatricesComponent.

const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const cs = @import("../../../renderer/cameraSystem.zig");
const render_system = @import("render_system.zig");

pub fn update(registry: *Registry, dt: f32) anyerror!void {
    _ = dt;
    const aspect = render_system.aspectRatio();
    const matrices = cs.update(registry, aspect) orelse return;

    var it = registry.Query(.{components.CameraComponent});
    const cam = it.next() orelse return;
    try registry.set(cam, components.CameraMatricesComponent{
        .view = matrices.view,
        .proj = matrices.projection,
    });
}
