@echo off
REM Shaders are now compiled automatically by build.zig's "shaders" step
REM (runs on every `zig build`, or standalone via `zig build shaders`).
REM This file is kept only as a manual fallback if you need to invoke
REM slangc directly without going through the Zig build.
C:/VulkanSDK/1.4.341.1/bin/slangc.exe shader.slang -target spirv -profile spirv_1_4 -emit-spirv-directly -fvk-use-entrypoint-name -entry vertMain -entry fragMain -o slang.spv
C:/VulkanSDK/1.4.341.1/bin/slangc.exe shadow.slang -target spirv -profile spirv_1_4 -emit-spirv-directly -fvk-use-entrypoint-name -entry vertMain -o shadow.spv
