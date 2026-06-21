const std = @import("std");
const builtin = @import("builtin");
const zglfw = @import("zvkgl.zig");

const enable_validation = builtin.mode == .Debug;
const glfwWindow_width = 800;
const glfwWindow_height = 600;
const glfwWindow_title = "ECS Zig World";

var extensionBuffer: [16][*c]const u8 = undefined;

pub fn init() !*anyopaque {
    if (zglfw.glfwInit() == 0) return error.GlfwInitFailed;
    if (zglfw.glfwVulkanSupported() == 0) return error.GlfwVulkanNotSupported;

    zglfw.glfwWindowHint(zglfw.GLFW_CLIENT_API, zglfw.GLFW_NO_API);
    zglfw.glfwWindowHint(zglfw.GLFW_RESIZABLE, zglfw.GLFW_FALSE);
    //zglfw.glfwWindowHint(zglfw.GLFW_COCOA_MENUBAR, zglfw.GLFW_TRUE);
    const handle =
        zglfw.glfwCreateWindow(glfwWindow_width, glfwWindow_height, glfwWindow_title, null, null);
    if (handle == null) return error.GlfwWindowCreateFailed;
    return @ptrCast(handle.?);
}
pub fn deinit(handle: *anyopaque) void {
    zglfw.glfwDestroyWindow(@ptrCast(handle));
    zglfw.glfwTerminate();
}
pub fn shouldClose(handle: *anyopaque) c_int {
    return zglfw.glfwWindowShouldClose(@ptrCast(handle));
}
pub fn pollEvents() void {
    zglfw.glfwPollEvents();
}
pub fn createSurface(handle: *anyopaque, instance: zglfw.VkInstance) !zglfw.VkSurfaceKHR {
    var surface: zglfw.VkSurfaceKHR = undefined;
    const result = zglfw.glfwCreateWindowSurface(instance, @ptrCast(handle), null, &surface);
    if (result != zglfw.VK_SUCCESS) return error.CreateSurfaceFailed;
    return surface;
}
pub fn getRequiredExtensions() [][*c]const u8 {
    var count: u32 = 0;
    const glfwExtensions = zglfw.glfwGetRequiredInstanceExtensions(&count);
    @memcpy(extensionBuffer[0..count], glfwExtensions[0..count]);
    if (enable_validation) {
        extensionBuffer[count] = "VK_EXT_debug_utils";
        return extensionBuffer[0 .. count + 1];
    }
    return extensionBuffer[0..count];
}
