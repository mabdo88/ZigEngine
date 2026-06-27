const std = @import("std");
const builtin = @import("builtin");
const c = @import("zvkgl.zig");

pub const Key = struct {
    pub const one = c.GLFW_KEY_1;
    pub const two = c.GLFW_KEY_2;
    pub const three = c.GLFW_KEY_3;
    pub const four = c.GLFW_KEY_4;
    pub const five = c.GLFW_KEY_5;
    pub const six = c.GLFW_KEY_6;
    pub const seven = c.GLFW_KEY_7;
    pub const eight = c.GLFW_KEY_8;
    pub const nine = c.GLFW_KEY_9;
    pub const escape = c.GLFW_KEY_ESCAPE;
    pub const w = c.GLFW_KEY_W;
    pub const a = c.GLFW_KEY_A;
    pub const s = c.GLFW_KEY_S;
    pub const d = c.GLFW_KEY_D;
    pub const space = c.GLFW_KEY_SPACE;
    pub const left_shift = c.GLFW_KEY_LEFT_SHIFT;
    pub const f5 = c.GLFW_KEY_F5;
    pub const f9 = c.GLFW_KEY_F9;
};

pub const MouseButton = struct {
    pub const left = c.GLFW_MOUSE_BUTTON_LEFT;
    pub const right = c.GLFW_MOUSE_BUTTON_RIGHT;
};

var g_resized: bool = false;

fn framebufferResizeCallback(win: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    _ = win;
    _ = width;
    _ = height;
    g_resized = true;
}

pub const Window = struct {
    handle: *c.GLFWwindow,
    width: u32,
    height: u32,

    pub fn shouldClose(self: *const Window) bool {
        return c.glfwWindowShouldClose(self.handle) != 0;
    }

    pub fn getKey(self: *const Window, key: c_int) bool {
        return c.glfwGetKey(self.handle, key) == c.GLFW_PRESS;
    }

    pub fn getMouseButton(self: *const Window, button: c_int) bool {
        return c.glfwGetMouseButton(self.handle, button) == c.GLFW_PRESS;
    }

    pub const CursorPos = struct { x: f64, y: f64 };

    pub fn getCursorPos(self: *const Window) CursorPos {
        var x: f64 = 0;
        var y: f64 = 0;
        c.glfwGetCursorPos(self.handle, &x, &y);
        return .{ .x = x, .y = y };
    }

    pub const CursorMode = enum(c_int) {
        normal = c.GLFW_CURSOR_NORMAL,
        disabled = c.GLFW_CURSOR_DISABLED,
    };

    pub fn setCursorMode(self: *const Window, mode: CursorMode) void {
        c.glfwSetInputMode(self.handle, c.GLFW_CURSOR, @intFromEnum(mode));
    }

    pub const Size = struct { width: u32, height: u32 };

    pub fn framebufferSize(self: *const Window) Size {
        var w: c_int = 0;
        var h: c_int = 0;
        c.glfwGetFramebufferSize(self.handle, &w, &h);
        return .{ .width = @intCast(@max(w, 0)), .height = @intCast(@max(h, 0)) };
    }

    pub fn createSurface(self: *const Window, instance: c.VkInstance) !c.VkSurfaceKHR {
        var surface: c.VkSurfaceKHR = null;
        if (c.glfwCreateWindowSurface(instance, self.handle, null, &surface) != c.VK_SUCCESS) {
            return error.SurfaceCreateFailed;
        }
        return surface;
    }

    pub fn destroy(self: *Window) void {
        c.glfwDestroyWindow(self.handle);
        self.handle = undefined;
    }
};

pub fn init() !void {
    if (c.glfwInit() == 0) return error.GlfwInitFailed;
    if (c.glfwVulkanSupported() == 0) {
        c.glfwTerminate();
        return error.VulkanNotSupported;
    }
}

pub fn terminate() void {
    c.glfwTerminate();
}

pub fn pollEvents() void {
    c.glfwPollEvents();
}

pub fn getTime() f64 {
    return c.glfwGetTime();
}

pub fn wasResized() bool {
    return g_resized;
}

pub fn clearResized() void {
    g_resized = false;
}

pub fn create(title: [:0]const u8, width: u32, height: u32, resizable: bool) !Window {
    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, if (resizable) 1 else 0);
    const handle = c.glfwCreateWindow(
        @intCast(width),
        @intCast(height),
        title.ptr,
        null,
        null,
    ) orelse return error.WindowCreateFailed;
    _ = c.glfwSetFramebufferSizeCallback(handle, framebufferResizeCallback);
    return .{ .handle = handle, .width = width, .height = height };
}

pub fn requiredInstanceExtensions(allocator: std.mem.Allocator) ![]const [*c]const u8 {
    var count: u32 = 0;
    const glfw_exts = c.glfwGetRequiredInstanceExtensions(&count);
    if (glfw_exts == null) return error.NoVulkanInstanceExtensions;

    const debug_extra: u32 = if (builtin.mode == .Debug) 1 else 0;
    const mac_extra: u32 = if (builtin.os.tag == .macos) 1 else 0;
    const total: usize = @as(usize, count) + debug_extra + mac_extra;

    const list = try allocator.alloc([*c]const u8, total);
    var i: usize = 0;
    while (i < count) : (i += 1) list[i] = glfw_exts[i];
    if (builtin.os.tag == .macos) {
        list[i] = "VK_KHR_portability_enumeration";
        i += 1;
    }
    if (builtin.mode == .Debug) {
        list[i] = "VK_EXT_debug_utils";
        i += 1;
    }
    return list;
}
