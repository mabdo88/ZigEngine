# ZigEngine

A custom 3D game engine written in [Zig](https://ziglang.org/), built on a modern **Vulkan 1.3** renderer and a data-oriented **Entity-Component-System (ECS)**.

ZigEngine started life as a C++ project and was rewritten in Zig for its simplicity, explicit control over memory, and first-class C interop. It is the foundation for an in-development game with its own Game Design Document — the current focus is getting the core engine systems solid before gameplay work begins.

> **Status:** early / pre-alpha. The renderer can load a glTF model with a texture and draw it through the ECS. APIs change frequently and the build is currently Windows-only (see [Platform support](#platform-support)).

---

## Features

- **Vulkan 1.3 renderer** using dynamic rendering (`VK_KHR_dynamic_rendering`) — no render passes or framebuffers.
- **Sparse-set ECS** with generational entity handles, type-safe component storage, and a multi-component query iterator.
- **glTF model loading** via [`cgltf`](https://github.com/jkuhlmann/cgltf) (positions, normals, UVs, indices, PBR base-color textures).
- **Texture loading** via [`stb_image`](https://github.com/nothings/stb).
- **Bindless textures** — textures live in a single descriptor array indexed by a push-constant slot.
- **GPU memory management** through [Vulkan Memory Allocator (VMA)](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator).
- **Slang shaders** compiled to SPIR-V.
- **Depth buffering**, per-frame uniform buffers, and double-buffered frames in flight.
- **Leak-checked allocation** in debug builds via Zig's `DebugAllocator`, with Vulkan validation layers enabled automatically in debug mode.

## Architecture

The engine is organized around a small ECS core that the rendering and camera systems read from.

```
Engine                      owns the allocator + World, runs the main loop
└── World                   scene state: registry, window, entities
    ├── Registry            entity lifecycle + component storage (sparse set)
    │   └── ComponentStorage(T)   dense component arrays with sparse index map
    └── Systems
        ├── CameraSystem    builds view/projection matrices from CameraComponent
        └── RenderSystem    uploads meshes to the GPU and records draw calls
```

Components (`src/ecs/Component/components.zig`):

| Component            | Purpose                                  |
| -------------------- | ---------------------------------------- |
| `MeshComponent`      | CPU-side vertices + indices              |
| `TransformComponent` | position / rotation (Euler) / scale      |
| `CameraComponent`    | eye, target, up, fov, near/far planes    |
| `TextureComponent`   | index into the bindless texture heap     |

The Vulkan backend lives under `src/Vulkan/`: `zVulkanContext.zig` holds device/swapchain/pipeline state and `zvulkanSystem.zig` drives initialization, the per-frame render loop, and texture/buffer uploads.

## Project layout

```
src/
├── main.zig                 entry point
├── ecs/                     entity-component-system core
│   ├── Entity/              generational entity handles
│   ├── Component/           component & system-component definitions
│   ├── Storage/             registry + sparse-set component storage
│   └── System/              camera & render systems
├── Vulkan/                  Vulkan context + renderer (VMA integration)
├── glfw/                    windowing / Vulkan bindings
├── shaders/                 Slang shaders + compiled SPIR-V
├── meshLoader.zig           glTF + texture loading
└── cgltf.zig                generated cgltf bindings
vendor/                      vendored C single-header libs (cgltf, stb)
libs/                        GLFW, VMA, Vulkan link libraries
assets/                      sample models (e.g. the duck)
```

## Requirements

- **Zig 0.16.0** (see `minimum_zig_version` in `build.zig.zon`).
- **Vulkan SDK 1.4.341.1** with a GPU/driver supporting Vulkan 1.3.
- A Slang compiler (only needed if you change the shaders; precompiled SPIR-V is committed).

## Building

```sh
# Build the executable
zig build

# Build and run
zig build run

# Run the GPU-free ECS unit tests
zig build test-ecs

# Build with custom Vulkan SDK path
zig build -Dvulkan-sdk=/path/to/VulkanSDK/1.4.341.1
```

> **Heads up:** The Vulkan SDK path can be configured via:
> - The `--vulkan-sdk` build option: `zig build -Dvulkan-sdk=/path/to/VulkanSDK/1.4.341.1`
> - The `VULKAN_SDK` environment variable
> - Defaults to `../../../VulkanSDK/1.4.341.1/` if neither is set
>
> The build currently links Windows system libraries (`gdi32`, `user32`, `shell32`, `vulkan-1`). Making the link step fully OS-aware is on the roadmap.

## Platform support

| Platform | Status                                                              |
| -------- | ------------------------------------------------------------------ |
| Windows  | Supported (primary development target)                             |
| Linux    | Partial — `zig build test-ecs`, `zig fmt`, and `zig ast-check` work; the full graphical build needs the link/SDK config to be made cross-platform |
| macOS    | Not yet supported                                                  |

## Roadmap

Core-engine milestones being worked toward before gameplay:

- [ ] Cross-platform, SDK-path-agnostic build
- [ ] Swapchain recreation / window resize handling
- [ ] Refactor global Vulkan state into a passed context
- [ ] Material system beyond base-color textures
- [ ] Scene/asset management and a proper update loop with delta time
- [ ] Input system
- [ ] Lighting

## Acknowledgements

Built with [GLFW](https://www.glfw.org/), [Vulkan Memory Allocator](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator), [cgltf](https://github.com/jkuhlmann/cgltf), [stb](https://github.com/nothings/stb), and [Slang](https://github.com/shader-slang/slang). Sample "Duck" model from the [glTF Sample Models](https://github.com/KhronosGroup/glTF-Sample-Models).
