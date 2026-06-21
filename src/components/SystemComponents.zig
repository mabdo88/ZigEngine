const zvk = @import("../platform/zvkgl.zig");

pub const SystemComponent = union(enum) {
    window: WindowComponent,
    renderer: VulkanContextComponent,
};

pub const WindowComponent = struct {
    width: u16 = 0,
    height: u16 = 0,
    title: ?[:0]const u8 = null,
};

pub const VulkanContextComponent = struct {};
