const std = @import("std");
const flecs = @import("../flecs.zig");
const components = @import("../components/components.zig");
const math = @import("../../math.zig");
const SharedContext = @import("system.zig").SharedContext;

pub fn run(it: [*c]flecs.c.ecs_iter_t) callconv(.c) void {
    const it_ptr: *flecs.c.ecs_iter_t = @ptrCast(it);
    const ctx: *SharedContext = @ptrCast(@alignCast(it_ptr.ctx.?));
    const ids = ctx.component_ids;
    const world = ctx.world;

    var root_q = world.query(&.{ ids.Transform, ids.WorldTransform, ids.Root });
    defer root_q.deinit();
    var root_it = root_q.iter();
    while (root_it.next()) {
        const root_transforms = root_it.field(components.TransformComponent, 0);
        const world_transforms = root_it.field(components.WorldTransformComponent, 1);
        var row: i32 = 0;
        while (row < root_it.count()) : (row += 1) {
            const root_entity = root_it.entity(row);
            const root_world_mat = math.transformToMatrix(&root_transforms[@intCast(row)]);
            world_transforms[@intCast(row)].matrix = root_world_mat;
            propagateChildren(world, root_entity, root_world_mat, ids);
        }
    }
}

fn propagateChildren(
    world: *flecs.World,
    parent: flecs.Entity,
    parent_world: [4][4]f32,
    ids: components.ComponentIds,
) void {
    var child_it = world.children(parent);
    defer child_it.fini();
    while (child_it.next()) {
        var row: i32 = 0;
        while (row < child_it.count()) : (row += 1) {
            const child = child_it.entity(row);

            if (!world.has(child, ids.Transform) or !world.has(child, ids.WorldTransform)) continue;

            const child_transform = world.get(child, components.TransformComponent, ids.Transform) orelse continue;
            const child_world_mat = math.matMul(parent_world, math.transformToMatrix(child_transform));

            if (world.getMut(child, components.WorldTransformComponent, ids.WorldTransform)) |wt| {
                wt.matrix = child_world_mat;
            }

            propagateChildren(world, child, child_world_mat, ids);
        }
    }
}
