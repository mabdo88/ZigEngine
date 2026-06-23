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
        .root_source_file = b.path("deps/vma/vk_mem_alloc.h"),
        .target = target,
        .optimize = optimize,
    });
    if (os_tag == .windows) {
        const vulkan_include = b.fmt("{s}/Include/", .{vulkan_sdk_path});
        vma_translate.addIncludePath(.{ .cwd_relative = vulkan_include });
    } else {
        vma_translate.addIncludePath(.{ .cwd_relative = "/usr/include" });
    }
    vma_translate.addIncludePath(b.path("deps/vma/"));
    // Add C++ VMA implementation
    exe.root_module.addCSourceFile(.{
        .file = b.path("src/renderer/vma_impl.cpp"),
        .flags = &[_][]const u8{"-std=c++17"},
        .language = .cpp,
    });

    exe.is_linking_libcpp = true;
    b.installArtifact(exe);
    exe.root_module.addCSourceFile(.{ .file = b.path("src/native/cgltf_impl.c") });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/native/stb_image_impl.c") });
    exe.root_module.addIncludePath(b.path("deps/cgltf/"));
    exe.root_module.addIncludePath(b.path("deps/stb/"));
    exe.root_module.addIncludePath(b.path("deps/vma/"));
    if (os_tag == .windows) {
        // Windows: vendored Vulkan SDK headers + Win32 + the Windows loader (vulkan-1).
        const vulkan_include = b.fmt("{s}/Include/", .{vulkan_sdk_path});
        exe.root_module.addIncludePath(.{ .cwd_relative = vulkan_include });
        exe.root_module.addLibraryPath(b.path("deps/glfw/lib/"));
        exe.root_module.addLibraryPath(b.path("deps/vulkan/"));
        exe.root_module.linkSystemLibrary("glfw3", .{});
        exe.root_module.linkSystemLibrary("gdi32", .{});
        exe.root_module.linkSystemLibrary("user32", .{});
        exe.root_module.linkSystemLibrary("shell32", .{});
        exe.root_module.linkSystemLibrary("vulkan-1", .{});
        // glfw3.lib is an import library; ship glfw3.dll next to the exe.
        const install_glfw_dll = b.addInstallBinFile(b.path("deps/glfw/lib/glfw3.dll"), "glfw3.dll");
        b.getInstallStep().dependOn(&install_glfw_dll.step);
    } else if (os_tag == .macos) {
        // macOS: system GLFW + Vulkan via MoltenVK + required frameworks.
        // Best-effort/untested: assumes GLFW + Vulkan SDK (MoltenVK) installed
        // (e.g. via Homebrew / the LunarG SDK).
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/local/include" });
        exe.root_module.addIncludePath(.{ .cwd_relative = "/opt/homebrew/include" });
        exe.root_module.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
        exe.root_module.addLibraryPath(.{ .cwd_relative = "/opt/homebrew/lib" });
        exe.root_module.linkSystemLibrary("glfw", .{});
        exe.root_module.linkSystemLibrary("vulkan", .{});
        exe.root_module.linkFramework("Cocoa", .{});
        exe.root_module.linkFramework("IOKit", .{});
        exe.root_module.linkFramework("QuartzCore", .{});
        exe.root_module.linkFramework("Metal", .{});
    } else {
        // Linux: system GLFW (pulls in the windowing system) + Vulkan loader.
        exe.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
        exe.root_module.linkSystemLibrary("glfw", .{});
        exe.root_module.linkSystemLibrary("vulkan", .{});
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
    // ECS tests - GPU-free, minimal module
    // Use zig test directly to avoid --listen flag issues
    const ecs_test_cmd = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "test",
        "src/ecs_test.zig",
        "-ODebug",
        "--cache-dir",
        ".zig-cache",
        "--global-cache-dir",
        b.graph.global_cache_root.path orelse "",
    });
    const ecs_test_step = b.step("test-ecs", "Run ECS tests");
    ecs_test_step.dependOn(&ecs_test_cmd.step);
    test_step.dependOn(&ecs_test_cmd.step);
}
