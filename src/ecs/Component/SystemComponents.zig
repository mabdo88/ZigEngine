const zvk = @import("../../glfw/zvkgl.zig");

pub const SystemComponent = union(enum) {
    window: WindowComponent,
    renderer: VulkanContextComponent,
};

pub const WindowComponent = struct {
    Window_width: u16 = 0,
    Window_height: u16 = 0,
    Window_title: ?[:0]const u8 = null,
};

pub const VulkanContextComponent = struct {};
