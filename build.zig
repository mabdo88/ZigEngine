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

    const stb_translate = b.addTranslateC(.{
        .root_source_file = b.path("deps/stb/stb_image.h"),
        .target = target,
        .optimize = optimize,
    });
    stb_translate.addIncludePath(b.path("deps/stb/"));

    const miniaudio_translate = b.addTranslateC(.{
        .root_source_file = b.path("deps/miniaudio/miniaudio.h"),
        .target = target,
        .optimize = optimize,
    });
    miniaudio_translate.addIncludePath(b.path("deps/miniaudio/"));
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
    exe.root_module.addCSourceFile(.{ .file = b.path("src/native/miniaudio_impl.c") });
    exe.root_module.addIncludePath(b.path("deps/cgltf/"));
    exe.root_module.addIncludePath(b.path("deps/stb/"));
    exe.root_module.addIncludePath(b.path("deps/vma/"));
    exe.root_module.addIncludePath(b.path("deps/miniaudio/"));

    // Jolt Physics (deps/jolt, git submodule pinned to v5.5.0) — compiled directly
    // from source, no CMake involved. We collect every Jolt/*.cpp ourselves since
    // there's no Zig-native equivalent of Jolt.cmake's source list; files gated by
    // undefined macros (e.g. Renderer/DebugRenderer*.cpp under JPH_DEBUG_RENDERER)
    // compile to empty translation units when the macro is off, so including them
    // unconditionally is harmless.
    // Jolt always compiles ReleaseFast regardless of the overall build's
    // optimize mode: Jolt's own assertions/asserts are extremely hot-path
    // (per-contact-pair), and Debug-mode Jolt is unusably slow for any real
    // physics test; -DNDEBUG also disables Jolt's internal JPH_ASSERT.
    const jolt_cpp_flags = &[_][]const u8{ "-std=c++17", "-O3", "-DNDEBUG" };
    {
        const io = b.graph.io;
        var dir = std.Io.Dir.cwd().openDir(io, "deps/jolt/Jolt", .{ .iterate = true }) catch @panic("deps/jolt submodule not found — run `git submodule update --init`");
        defer dir.close(io);
        var walker = dir.walk(b.allocator) catch @panic("OOM");
        defer walker.deinit();
        while (walker.next(io) catch @panic("walk failed")) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.basename, ".cpp")) continue;
            const rel = b.fmt("deps/jolt/Jolt/{s}", .{entry.path});
            exe.root_module.addCSourceFile(.{ .file = b.path(rel), .flags = jolt_cpp_flags, .language = .cpp });
        }
    }
    exe.root_module.addCSourceFile(.{
        .file = b.path("src/physics/jolt_wrapper.cpp"),
        .flags = jolt_cpp_flags,
        .language = .cpp,
    });
    exe.root_module.addIncludePath(b.path("deps/jolt/"));
    exe.root_module.addIncludePath(b.path("src/physics/"));
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

    // Shader compilation — the engine writes shaders in Slang (not GLSL), so
    // this runs slangc rather than glslc. Outputs land at the same fixed
    // src/shaders/*.spv paths the renderer's @embedFile calls already
    // expect, so no change is needed on that side. Always reruns (slangc is
    // fast enough that build-cache tracking isn't worth the complexity).
    const slangc_exe = if (os_tag == .windows) "slangc.exe" else "slangc";
    const slangc_path = b.fmt("{s}/bin/{s}", .{ vulkan_sdk_path, slangc_exe });

    const ShaderSpec = struct {
        src: []const u8,
        out: []const u8,
        entries: []const []const u8,
    };
    const shader_specs = [_]ShaderSpec{
        .{ .src = "src/shaders/shader.slang", .out = "src/shaders/slang.spv", .entries = &.{ "vertMain", "fragMain" } },
        .{ .src = "src/shaders/shadow.slang", .out = "src/shaders/shadow.spv", .entries = &.{"vertMain"} },
        .{ .src = "src/shaders/debug.slang", .out = "src/shaders/debug.spv", .entries = &.{ "vertMain", "fragMain" } },
    };

    const shaders_step = b.step("shaders", "Compile .slang shaders to .spv via slangc");
    for (shader_specs) |spec| {
        const cmd = b.addSystemCommand(&.{ slangc_path, spec.src, "-target", "spirv", "-profile", "spirv_1_4", "-emit-spirv-directly", "-fvk-use-entrypoint-name" });
        for (spec.entries) |entry| cmd.addArgs(&.{ "-entry", entry });
        cmd.addArgs(&.{ "-o", spec.out });
        shaders_step.dependOn(&cmd.step);
        exe.step.dependOn(&cmd.step);
    }

    const vma_module = vma_translate.createModule();
    b.modules.put(b.allocator, "vmaimport", vma_module) catch unreachable;
    mod.addImport("vmaimport", vma_module);
    exe.root_module.addImport("vmaimport", vma_module);

    const stb_module = stb_translate.createModule();
    b.modules.put(b.allocator, "stbimport", stb_module) catch unreachable;
    mod.addImport("stbimport", stb_module);
    exe.root_module.addImport("stbimport", stb_module);

    const miniaudio_module = miniaudio_translate.createModule();
    b.modules.put(b.allocator, "miniaudioimport", miniaudio_module) catch unreachable;
    mod.addImport("miniaudioimport", miniaudio_module);
    exe.root_module.addImport("miniaudioimport", miniaudio_module);

    // Fast-iteration test target for the audio module only (no Jolt/VMA/cgltf
    // compile) — mirrors the test-ecs step's purpose for the audio module.
    {
        const audio_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/audio/audio_device.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        audio_test.root_module.addImport("miniaudioimport", miniaudio_module);
        audio_test.root_module.addCSourceFile(.{ .file = b.path("src/native/miniaudio_impl.c") });
        audio_test.root_module.addIncludePath(b.path("deps/miniaudio/"));
        const run_audio_test = b.addRunArtifact(audio_test);
        const audio_test_step = b.step("test-audio", "Run audio module tests only (fast iteration)");
        audio_test_step.dependOn(&run_audio_test.step);
    }

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
    exe_tests.step.dependOn(shaders_step);
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
    });
    const ecs_test_step = b.step("test-ecs", "Run ECS tests");
    ecs_test_step.dependOn(&ecs_test_cmd.step);
    test_step.dependOn(&ecs_test_cmd.step);

    // Digital Twin platform (headless storage benchmarking — no Vulkan)
    const dt_test_cmd = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "test",
        "engine/ecs/storage/storage_backend.zig",
        "-ODebug",
        "--cache-dir",
        ".zig-cache",
    });
    const dt_test_step = b.step("test-dt", "Run digital twin platform tests");
    dt_test_step.dependOn(&dt_test_cmd.step);
    test_step.dependOn(&dt_test_cmd.step);

    // Digital Twin storage backends (AoS, SoA — headless, no Vulkan)
    const dt_backends_test_cmd = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "test",
        "engine/ecs/storage/backends_test.zig",
        "-ODebug",
        "--cache-dir",
        ".zig-cache",
    });
    const dt_backends_test_step = b.step("test-dt-backends", "Run digital twin storage backend tests");
    dt_backends_test_step.dependOn(&dt_backends_test_cmd.step);
    test_step.dependOn(&dt_backends_test_cmd.step);

    // Digital Twin World(T) — generic ECS world over storage backends (headless)
    const dt_world_test_cmd = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "test",
        "engine/ecs/world.zig",
        "-ODebug",
        "--cache-dir",
        ".zig-cache",
    });
    const dt_world_test_step = b.step("test-dt-world", "Run digital twin World(T) tests");
    dt_world_test_step.dependOn(&dt_world_test_cmd.step);
    test_step.dependOn(&dt_world_test_cmd.step);

    // Digital Twin benchmark queries — golden-result equivalence tests (headless)
    const dt_queries_test_cmd = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "test",
        "engine/benchmark_test.zig",
        "-ODebug",
        "--cache-dir",
        ".zig-cache",
    });
    const dt_queries_test_step = b.step("test-dt-queries", "Run digital twin benchmark query tests");
    dt_queries_test_step.dependOn(&dt_queries_test_cmd.step);
    test_step.dependOn(&dt_queries_test_cmd.step);

    // Digital Twin metrics system — latency/throughput/memory recording (headless)
    const dt_metrics_test_cmd = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "test",
        "engine/metrics_test.zig",
        "-ODebug",
        "--cache-dir",
        ".zig-cache",
    });
    const dt_metrics_test_step = b.step("test-dt-metrics", "Run digital twin metrics system tests");
    dt_metrics_test_step.dependOn(&dt_metrics_test_cmd.step);
    test_step.dependOn(&dt_metrics_test_cmd.step);
}
