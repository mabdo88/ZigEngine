const std = @import("std");
const Registry = @import("../entity/registry.zig").Registry;
const Entity = @import("../entity/entity.zig").Entity;
const components = @import("../components/components.zig");
const math = @import("../../math.zig");
const log = @import("../../log.zig");
const SystemCreateCtx = @import("system.zig").SystemCreateCtx;

pub fn setParent(registry: *Registry, child: Entity, parent: Entity) !void {
    try registry.set(child, components.ParentComponent{ .parent = parent });
}

pub fn clearParent(registry: *Registry, child: Entity) void {
    registry.remove(components.ParentComponent, child);
}

/// Concatenates FinalTransformComponent under each entity's parent chain.
/// TransformSystem has already written FinalTransformComponent = baked*local
/// for every entity (treating it as a world matrix); for entities with a
/// ParentComponent, that value is actually their local-to-parent matrix, and
/// this resolves it into a true world matrix by walking up to the root.
///
/// Uses `scratch` for per-frame bookkeeping (visited/in-progress sets) —
/// pass the per-frame arena allocator, not a long-lived one.
pub fn updateHierarchy(registry: *Registry, scratch: std.mem.Allocator) !void {
    var resolved = std.AutoHashMapUnmanaged(Entity, void){};
    var visiting = std.AutoHashMapUnmanaged(Entity, void){};

    var it = registry.Query(.{components.ParentComponent});
    while (it.next()) |entity| {
        try resolveWorld(registry, entity, &resolved, &visiting, scratch);
    }
}

fn resolveWorld(
    registry: *Registry,
    entity: Entity,
    resolved: *std.AutoHashMapUnmanaged(Entity, void),
    visiting: *std.AutoHashMapUnmanaged(Entity, void),
    scratch: std.mem.Allocator,
) !void {
    if (resolved.contains(entity)) return;

    const parent_comp = registry.get(components.ParentComponent, entity) orelse {
        // Root: FinalTransformComponent is already a correct world matrix.
        try resolved.put(scratch, entity, {});
        return;
    };
    const parent = parent_comp.parent;

    if (!registry.isAlive(parent)) {
        // Parent went away since this was set; fall back to treating the
        // entity as a root rather than leaving it permanently unresolved.
        clearParent(registry, entity);
        try resolved.put(scratch, entity, {});
        return;
    }

    if (visiting.contains(entity)) {
        log.err(@src(), "hierarchy: cycle detected at entity index {d}, breaking by treating it as a root this frame", .{entity.index});
        try resolved.put(scratch, entity, {});
        return;
    }
    try visiting.put(scratch, entity, {});
    try resolveWorld(registry, parent, resolved, visiting, scratch);
    _ = visiting.remove(entity);

    const parent_final = registry.get(components.FinalTransformComponent, parent).?.matrix;
    const local = registry.get(components.FinalTransformComponent, entity).?.matrix;
    try registry.set(entity, components.FinalTransformComponent{ .matrix = math.matMul(parent_final, local) });
    try resolved.put(scratch, entity, {});
}

pub const HierarchySystemState = struct {
    scratch: *std.heap.ArenaAllocator,
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    _ = dt;
    const state: *HierarchySystemState = @ptrCast(@alignCast(ctx));
    try updateHierarchy(registry, state.scratch.allocator());
}

pub fn create(ctx: *SystemCreateCtx) anyerror!*anyopaque {
    const state = try ctx.allocator.create(HierarchySystemState);
    state.* = .{ .scratch = ctx.scratch };
    return @ptrCast(state);
}

pub fn destroy(allocator: std.mem.Allocator, _: *Registry, ctx: *anyopaque) void {
    const state: *HierarchySystemState = @ptrCast(@alignCast(ctx));
    allocator.destroy(state);
}

fn identityFinal(reg: *Registry, e: Entity) !void {
    try reg.add(e, components.FinalTransformComponent{ .matrix = math.identityMatrix() });
}

test "child's final transform is parent's final times its own local" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const parent = try reg.create();
    try reg.add(parent, components.FinalTransformComponent{ .matrix = math.identityMatrix() });
    var parent_t = math.identityMatrix();
    parent_t[3][0] = 10.0; // parent translated +10 on X
    try reg.set(parent, components.FinalTransformComponent{ .matrix = parent_t });

    const child = try reg.create();
    var child_local = math.identityMatrix();
    child_local[3][0] = 1.0; // child offset +1 on X relative to parent
    try reg.add(child, components.FinalTransformComponent{ .matrix = child_local });
    try setParent(&reg, child, parent);

    try updateHierarchy(&reg, arena.allocator());

    const final = reg.get(components.FinalTransformComponent, child).?.matrix;
    try std.testing.expectApproxEqAbs(@as(f32, 11.0), final[3][0], 1e-5);
}

test "multi-level chain composes through grandparent -> parent -> child" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const grandparent = try reg.create();
    var gp_t = math.identityMatrix();
    gp_t[3][0] = 100.0;
    try reg.add(grandparent, components.FinalTransformComponent{ .matrix = gp_t });

    const parent = try reg.create();
    var p_t = math.identityMatrix();
    p_t[3][0] = 10.0;
    try reg.add(parent, components.FinalTransformComponent{ .matrix = p_t });
    try setParent(&reg, parent, grandparent);

    const child = try reg.create();
    var c_t = math.identityMatrix();
    c_t[3][0] = 1.0;
    try reg.add(child, components.FinalTransformComponent{ .matrix = c_t });
    try setParent(&reg, child, parent);

    // Query order shouldn't matter — resolveWorld recurses up as needed.
    try updateHierarchy(&reg, arena.allocator());

    try std.testing.expectApproxEqAbs(@as(f32, 110.0), reg.get(components.FinalTransformComponent, parent).?.matrix[3][0], 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 111.0), reg.get(components.FinalTransformComponent, child).?.matrix[3][0], 1e-5);
}

test "destroyed parent orphans the child back to its local matrix" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const parent = try reg.create();
    try identityFinal(&reg, parent);

    const child = try reg.create();
    var c_t = math.identityMatrix();
    c_t[3][1] = 5.0;
    try reg.add(child, components.FinalTransformComponent{ .matrix = c_t });
    try setParent(&reg, child, parent);

    try reg.destroyEntity(parent);
    try updateHierarchy(&reg, arena.allocator());

    try std.testing.expect(reg.get(components.ParentComponent, child) == null);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), reg.get(components.FinalTransformComponent, child).?.matrix[3][1], 1e-5);
}

test "a parent cycle is broken instead of infinite-looping" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const a = try reg.create();
    try identityFinal(&reg, a);
    const b = try reg.create();
    try identityFinal(&reg, b);

    try setParent(&reg, a, b);
    try setParent(&reg, b, a);

    try updateHierarchy(&reg, arena.allocator()); // must return, not hang
}

test "roots without a ParentComponent are left untouched by the hierarchy pass" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const root = try reg.create();
    var t = math.identityMatrix();
    t[3][2] = 3.0;
    try reg.add(root, components.FinalTransformComponent{ .matrix = t });

    try updateHierarchy(&reg, arena.allocator());

    try std.testing.expectApproxEqAbs(@as(f32, 3.0), reg.get(components.FinalTransformComponent, root).?.matrix[3][2], 1e-5);
}

test "clearParent removes the relationship" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const parent = try reg.create();
    const child = try reg.create();
    try setParent(&reg, child, parent);
    try std.testing.expect(reg.get(components.ParentComponent, child) != null);

    clearParent(&reg, child);
    try std.testing.expect(reg.get(components.ParentComponent, child) == null);
}
