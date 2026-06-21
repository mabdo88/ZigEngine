const std = @import("std");

// Build function: mutates build graph for external runner
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const os_tag = target.result.os.tag;

    // Vulkan SDK path configuration
    const vulkan_sdk_path = b.option(
        []const u8,
        "vulkan-sdk",
        "Path to Vulkan SDK (defaults to VULKAN_SDK env var or ../../../VulkanSDK/1.4.341.1)",
    ) orelse b.graph.environ_map.get("VULKAN_SDK") orelse "../../../VulkanSDK/1.4.341.1";
    // Library module for consumers
    const mod = b.addModule("zvulkan", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zvulkan",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zvulkan", .module = mod },
            },
        }),
    });
    const vma_translate = b.addTranslateC(.{
        .root_source_file = b.path("libs/vma/vk_mem_alloc.h"),
        .target = target,
        .optimize = optimize,
    });
    if (os_tag == .windows) {
        const vulkan_include = b.fmt("{s}/Include/", .{vulkan_sdk_path});
        vma_translate.addIncludePath(.{ .cwd_relative = vulkan_include });
    } else {
        vma_translate.addIncludePath(.{ .cwd_relative = "/usr/include" });
    }
    vma_translate.addIncludePath(b.path("libs/vma/"));
    // Add C++ VMA implementation
    exe.root_module.addCSourceFile(.{
        .file = b.path("src/Vulkan/vma_impl.cpp"),
        .flags = &[_][]const u8{"-std=c++17"},
        .language = .cpp,
    });

    exe.is_linking_libcpp = true;
    b.installArtifact(exe);
    exe.root_module.addCSourceFile(.{ .file = b.path("src/cgltf_impl.c") });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/stb_image_impl.c") });
    exe.root_module.addIncludePath(b.path("vendor/cgltf/"));
    exe.root_module.addIncludePath(b.path("vendor/stb/"));
    exe.root_module.addIncludePath(b.path("libs/vma/"));
    if (os_tag == .windows) {
        // Windows: vendored Vulkan SDK headers + Win32 + the Windows loader (vulkan-1).
        const vulkan_include = b.fmt("{s}/Include/", .{vulkan_sdk_path});
        exe.root_module.addIncludePath(.{ .cwd_relative = vulkan_include });
        exe.root_module.addLibraryPath(b.path("libs/glfw/lib/"));
        exe.root_module.addLibraryPath(b.path("libs/vulkan/"));
        exe.root_module.linkSystemLibrary("glfw3", .{});
        exe.root_module.linkSystemLibrary("gdi32", .{});
        exe.root_module.linkSystemLibrary("user32", .{});
        exe.root_module.linkSystemLibrary("shell32", .{});
        exe.root_module.linkSystemLibrary("vulkan-1", .{});
    } else {
        // Linux: system Vulkan headers/loader + native Xlib windowing.
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
        exe.root_module.linkSystemLibrary("vulkan", .{});
        exe.root_module.linkSystemLibrary("X11", .{});
    }

    const vma_module = vma_translate.createModule();
    b.modules.put(b.allocator, "vmaimport", vma_module) catch unreachable;
    mod.addImport("vmaimport", vma_module);
    exe.root_module.addImport("vmaimport", vma_module);

    // Run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    // Uncomment to pass CLI args: `zig build run -- arg1 arg2`
    //if (b.args) |args| run_cmd.addArgs(args);

    // Module tests
    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Executable tests (needs C++ runtime for VMA)
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    exe_tests.is_linking_libcpp = true;
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // Test step (runs in parallel)
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    const ecs_module = b.createModule(.{
        .root_source_file = b.path("src/ecs/ecs_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ecs_tests = b.addTest(.{
        .root_module = ecs_module,
    });
    const run_ecs_tests = b.addRunArtifact(ecs_tests);
    const ecs_test_step = b.step("test-ecs", "Run ECS tests");
    ecs_test_step.dependOn(&run_ecs_tests.step);
    test_step.dependOn(&run_ecs_tests.step);
}
