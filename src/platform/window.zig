//! Cross-platform windowing + input backed by GLFW.
//!
//! This is the single place the engine talks to the OS windowing system. It is
//! deliberately backend-agnostic at the call site: the renderer asks it for the
//! required Vulkan instance extensions and a `VkSurfaceKHR`, and the input
//! system asks it for key state. Swapping GLFW for another backend (SDL, native)
//! only requires reimplementing this file.
//!
//! Platform support: Windows is built/verified. Linux/macOS use system GLFW and
//! are best-effort (macOS additionally needs MoltenVK + the portability
//! enumeration instance extension, added in `requiredInstanceExtensions`).

const std = @import("std");
const builtin = @import("builtin");
const c = @import("zvkgl.zig");

/// Key codes the engine cares about, re-exported so callers never import the
/// raw GLFW constants directly.
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
};

/// Set by the framebuffer-resize callback; polled by the renderer to rebuild the
/// swapchain. Module-level because GLFW callbacks are C function pointers.
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

    /// True while `key` is held down. `key` is one of the `Key` constants.
    pub fn getKey(self: *const Window, key: c_int) bool {
        return c.glfwGetKey(self.handle, key) == c.GLFW_PRESS;
    }

    pub const Size = struct { width: u32, height: u32 };

    /// Pixel size of the framebuffer (may differ from window size on HiDPI).
    /// Used for the swapchain extent.
    pub fn framebufferSize(self: *const Window) Size {
        var w: c_int = 0;
        var h: c_int = 0;
        c.glfwGetFramebufferSize(self.handle, &w, &h);
        return .{ .width = @intCast(@max(w, 0)), .height = @intCast(@max(h, 0)) };
    }

    /// Create the Vulkan surface for this window. Caller owns it and must
    /// destroy it with `vkDestroySurfaceKHR`.
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

/// Initialize GLFW and verify Vulkan is available. Call once before `create`.
pub fn init() !void {
    if (c.glfwInit() == 0) return error.GlfwInitFailed;
    if (c.glfwVulkanSupported() == 0) {
        c.glfwTerminate();
        return error.VulkanNotSupported;
    }
}

/// Tear down GLFW. Call once after all windows are destroyed.
pub fn terminate() void {
    c.glfwTerminate();
}

pub fn pollEvents() void {
    c.glfwPollEvents();
}

/// Monotonic time in seconds since `init`, used for frame timing.
pub fn getTime() f64 {
    return c.glfwGetTime();
}

/// Whether a resize happened since the last `clearResized`.
pub fn wasResized() bool {
    return g_resized;
}

pub fn clearResized() void {
    g_resized = false;
}

/// Create a Vulkan-capable window (no GL context).
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

/// Returns the Vulkan instance extensions required to present to a window,
/// plus `VK_EXT_debug_utils` in Debug builds and the portability enumeration
/// extension on macOS. Caller owns the returned slice and must free it.
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
