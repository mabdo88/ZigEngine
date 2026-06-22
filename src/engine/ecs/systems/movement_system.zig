const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");

pub const MovementSystemState = struct {
    pub fn update(self: *MovementSystemState, registry: *Registry, dt: f32) anyerror!void {
        _ = self;
        var active_it = registry.Query(.{ components.SceneComponent, components.SceneActiveTag });
        const active = active_it.next() orelse return;
        const scene = registry.get(components.SceneComponent, active).?;
        if (!std.mem.eql(u8, scene.name, "Duck")) return;

        var it = registry.Query(.{ components.TransformComponent, components.SceneOwnedComponent });
        while (it.next()) |entity| {
            const owned = registry.get(components.SceneOwnedComponent, entity).?;
            if (owned.owner.index != active.index) continue;
            const transform = registry.get(components.TransformComponent, entity).?;
            transform.rotation[1] += 90.0 * dt;
            if (transform.rotation[1] > 360.0) transform.rotation[1] -= 360.0;
        }
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *MovementSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}
