//! Reads keyboard input via the cross-platform window module and requests scene
//! changes by tagging a scene entity with ScenePendingTag. No renderer/Vulkan
//! involvement; the window handle is injected once via `init`.

const Registry = @import("../entity/registry.zig").Registry;
const components = @import("../components/components.zig");
const window = @import("../../../platform/window.zig");

var g_window: ?*window.Window = null;

/// Provide the window handle (called once from world.zig).
pub fn init(win: *window.Window) void {
    g_window = win;
}

pub fn update(registry: *Registry, dt: f32) anyerror!void {
    _ = dt;
    const win = g_window orelse return;

    const target: ?usize = if (win.getKey(window.Key.one))
        0
    else if (win.getKey(window.Key.two))
        1
    else
        null;

    const scene_index = target orelse return;
    try requestScene(registry, scene_index);
}

/// Tag the Nth scene entity as pending, unless it is already active or pending.
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
