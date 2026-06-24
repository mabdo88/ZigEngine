const std = @import("std");
const flecs = @import("../flecs.zig");
const components = @import("../components/components.zig");
const SharedContext = @import("system.zig").SharedContext;

pub fn run(it: [*c]flecs.c.ecs_iter_t) callconv(.c) void {
    const it_ptr: *flecs.c.ecs_iter_t = @ptrCast(it);
    const ctx: *SharedContext = @ptrCast(@alignCast(it_ptr.ctx.?));
    const ids = ctx.component_ids;
    const dt: f32 = it_ptr.delta_time;

    var active_q = ctx.world.query(&.{ ids.Scene, ids.SceneActive });
    defer active_q.deinit();
    var active_it = active_q.iter();
    if (!active_it.next()) return;
    const active_entity = active_it.entity(0);
    const scenes = active_it.field(components.SceneComponent, 0);
    if (!scenes[0].rotates) return;

    var owned_q = ctx.world.query(&.{ ids.Transform, ids.SceneOwned });
    defer owned_q.deinit();
    var owned_it = owned_q.iter();
    while (owned_it.next()) {
        const transforms = owned_it.field(components.TransformComponent, 0);
        const owned = owned_it.field(components.SceneOwnedComponent, 1);
        var row: i32 = 0;
        while (row < owned_it.count()) : (row += 1) {
            if (owned[@intCast(row)].owner != active_entity) continue;
            transforms[@intCast(row)].rotation[1] += 90.0 * dt;
            if (transforms[@intCast(row)].rotation[1] > 360.0)
                transforms[@intCast(row)].rotation[1] -= 360.0;
        }
    }
}
