const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const window = @import("../../../platform/window.zig");

pub const InputSystemState = struct {
    win: *window.Window,

    pub fn update(self: *InputSystemState, registry: *Registry, dt: f32) anyerror!void {
        _ = dt;
        const target: ?usize = if (self.win.getKey(window.Key.one))
            0
        else if (self.win.getKey(window.Key.two))
            1
        else
            null;

        const scene_index = target orelse return;
        try requestScene(registry, scene_index);
    }
};

pub fn update(registry: *Registry, ctx: *anyopaque, dt: f32) anyerror!void {
    const state: *InputSystemState = @ptrCast(@alignCast(ctx));
    try state.update(registry, dt);
}

fn requestScene(registry: *Registry, scene_index: usize) !void {
    var it = registry.Query(.{components.SceneComponent});
    var i: usize = 0;
    while (it.next()) |scene_entity| : (i += 1) {
        if (i != scene_index) continue;
        if (registry.get(components.SceneActiveTag, scene_entity) != null) return;
        if (registry.get(components.ScenePendingTag, scene_entity) != null) return;
        try registry.set(scene_entity, components.ScenePendingTag{});
        return;
    }
}
