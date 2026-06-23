# AGENTS.md

Guidance for AI coding agents working in this repository. Human contributors may
also find it useful, but the canonical project overview is [`README.md`](README.md).

## Project overview

ZigEngine is a custom 3D game engine written in [Zig](https://ziglang.org/), built
on a **Vulkan 1.3** renderer (dynamic rendering, no render passes) and a
data-oriented **Entity-Component-System (ECS)** with a priority-ordered system
pipeline. It is early / pre-alpha — APIs change frequently. Windows is the primary
development target; Linux is partially supported (ECS tests, formatting, and the
graphical build against the system Vulkan loader); macOS is best-effort.

## Setup

- **Zig:** requires `minimum_zig_version = 0.16.0` (see `build.zig.zon`). Use that
  version or newer.
- **Dependencies:** all C/C++ deps (GLFW, VMA, cgltf, stb) are vendored under
  `deps/` and built from source by `build.zig`. There are no `zig fetch`
  dependencies (`.dependencies = .{}`).
- **Vulkan SDK** is needed only for the full graphical build. `build.zig` locates
  it via the `-Dvulkan-sdk=<path>` build option, falling back to the `VULKAN_SDK`
  environment variable and then to `../../../VulkanSDK/1.4.341.1/`. On Linux the
  build uses the system Vulkan loader and system GLFW instead of the vendored SDK.

## Build / test / run commands

Run these from the repo root.

| Task | Command |
| ---- | ------- |
| Format code (do this before committing) | `zig fmt src/` |
| Syntax/semantic check without building | `zig ast-check src/main.zig` |
| GPU-free ECS tests (works headless / on Linux) | `zig build test-ecs` |
| Full test suite (`mod` + `exe` + ECS tests) | `zig build test` |
| Build the engine | `zig build` |
| Build and run the app | `zig build run` |

**Prefer `zig build test-ecs` for verifying changes** — it does not require a GPU,
a display, or the Vulkan SDK, so it runs anywhere. The full graphical build and
`zig build run` require Vulkan and a window system.

Running the produced binary headless on a Linux box with software Vulkan
(Mesa lavapipe), no GPU required:

```sh
export DISPLAY=:0 XDG_RUNTIME_DIR=/tmp/xdg-runtime
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
./zig-out/bin/zvulkan
```

At runtime, press `1` / `2` to hot-swap between the Duck and House scenes.

## Project layout

```
src/
├── main.zig                     entry point
├── root.zig                     library root
├── ecs_test.zig                 GPU-free ECS tests (run via `zig build test-ecs`)
├── engine/
│   ├── engine.zig               generic Engine(WorldType): owns allocator, main loop
│   ├── world.zig                VulkanWorld: registry, system runner, per-system state
│   ├── config.zig               window/camera/scene-list configuration
│   ├── math.zig                 vector/matrix math
│   └── ecs/components/          component definitions
├── renderer/                    Vulkan backend (see table below)
├── platform/                    GLFW + window/surface glue
├── resources/                   glTF (cgltf) + mesh/texture (stb) loading
├── shaders/                     Slang shaders compiled to SPIR-V
└── native/                      C/C++ implementation stubs (cgltf, stb_image)
```

Vulkan backend files under `src/renderer/`:

| File | Responsibility |
| ---- | -------------- |
| `zVulkanContext.zig` | Vulkan context struct (device, swapchain, pipeline, descriptors) |
| `zvulkanSystem.zig`  | High-level init/deinit, per-frame render loop, texture upload |
| `device.zig`         | Physical/logical device selection, debug messenger, VMA allocator |
| `swapchain.zig`      | Swapchain creation, surface format picking, depth image |
| `pipeline.zig`       | Graphics pipeline + shader loading (embedded SPIR-V) |
| `upload.zig`         | Staging buffers, batched buffer/image transfers |
| `material.zig`       | Texture upload, bindless descriptor management, texture reset |
| `renderSystem.zig`   | `RenderSystem`: GPU mesh upload, refcounting, draw recording |
| `vma_impl.cpp`       | VMA C++ implementation stub |

## Architecture notes

- `Engine` is generic over a `WorldType` (currently `VulkanWorld`) and owns the
  allocator and main loop.
- `VulkanWorld` holds the `Registry` (entity lifecycle + sparse-set component
  storage), an `EventBus` (pub/sub for `entity_destroyed` and `scene_unloaded`),
  and a `SystemRunner` that calls `update(dt)` on systems in priority order each
  frame.
- System priorities: `InputSystem` (-100) → `SceneSystem` (0) → `MovementSystem`
  (1) → `CameraSystem` (2) → `RenderSystem` (100).
- Textures are bindless: a single descriptor array indexed by a push-constant
  slot. `RenderSystem` caches uploaded textures by material ID and resets GPU
  textures on scene unload via the event bus.

## Conventions for agents

- **Always run `zig fmt src/` before committing.** CI / reviewers expect formatted
  code.
- **Validate changes with `zig build test-ecs`** (and `zig build test` when a GPU
  and Vulkan are available). Don't claim a change builds graphically unless you
  actually ran the Vulkan build.
- Keep edits minimal and idiomatic — match the surrounding Zig style; prefer
  explicit memory handling and avoid hidden allocations.
- Vendored C/C++ deps in `deps/` are upstream code — do not hand-edit them.
- Generated/build artifacts (`zig-out/`, `.zig-cache/`, `zig-pkg/`, `docs/`,
  `*.exe`, `*.pdb`) are git-ignored; never commit them.
- Branch off `dev` for engine work unless told otherwise, and open a PR rather
  than pushing to `main`.
