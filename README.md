# ZigEngine

A custom 3D game engine written in [Zig](https://ziglang.org/), built on a modern **Vulkan 1.3** renderer and a data-oriented **Entity-Component-System (ECS)**.

ZigEngine started life as a C++ project and was rewritten in Zig for its simplicity, explicit control over memory, and first-class C interop. It is the foundation for an in-development game with its own Game Design Document — the current focus is getting the core engine systems solid before gameplay work begins.

> **Status:** early / pre-alpha. The renderer loads glTF models with PBR base-color textures, scenes can be hot-swapped at runtime, and the ECS drives a priority-ordered system pipeline with delta-time updates. APIs change frequently (see [Platform support](#platform-support)).

---

## Features

- **Vulkan 1.3 renderer** using dynamic rendering (`VK_KHR_dynamic_rendering`) — no render passes or framebuffers.
- **Sparse-set ECS** with generational entity handles, type-safe component storage, and a multi-component query iterator.
- **Priority-ordered system pipeline** — systems register with a priority value and run in order each frame via `SystemRunner`.
- **Scene management** — scenes are config-driven entities; press `1` / `2` at runtime to hot-swap between the Duck and House scenes. Active scene unload/load is handled by `SceneSystem` with `SceneActiveTag` / `ScenePendingTag` markers.
- **Event bus** — decoupled pub/sub for `entity_destroyed` and `scene_unloaded` events, used by the render system to clean up GPU resources.
- **Input system** — GLFW keyboard input polled each frame; currently drives scene switching.
- **Movement system** — delta-time-based animation (e.g. rotating the duck model).
- **Config-driven initialization** — window properties, camera defaults, and scene list are declared in `config.zig`.
- **Delta-time update loop** — `Engine.run` computes frame delta time and passes it to `World.update`.
- **glTF model loading** via [`cgltf`](https://github.com/jkuhlmann/cgltf) (positions, normals, UVs, indices, PBR base-color textures, node transforms).
- **Texture loading** via [`stb_image`](https://github.com/nothings/stb).
- **Bindless textures** — textures live in a single descriptor array indexed by a push-constant slot.
- **Texture caching & deduplication** — `RenderSystem` caches uploaded textures by material ID; GPU textures are reset on scene unload.
- **Batched GPU uploads** — `UploadBatch` in `upload.zig` records multiple buffer/image transfers into a single command buffer submission.
- **GPU memory management** through [Vulkan Memory Allocator (VMA)](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator).
- **Modular renderer** — device selection, swapchain, pipeline, upload, and material/texture management are split into separate files under `src/renderer/`.
- **Slang shaders** compiled to SPIR-V.
- **Depth buffering**, per-frame uniform buffers, and double-buffered frames in flight.
- **Leak-checked allocation** in debug builds via Zig's `DebugAllocator`, with Vulkan validation layers enabled automatically in debug mode.

## Architecture

The engine is organized around an ECS core with a priority-ordered system pipeline. `Engine` is generic over a `WorldType` (currently `VulkanWorld`), owning the allocator and running the main loop.

```
Engine(WorldType)           generic engine shell — owns allocator, runs main loop
└── VulkanWorld             scene state: registry, system runner, per-system state
    ├── Registry            entity lifecycle + component storage (sparse set)
    │   ├── ComponentStorage(T)  dense component arrays with sparse index map
    │   └── EventBus        pub/sub for entity_destroyed, scene_unloaded
    ├── SystemRunner        priority-sorted list of systems, calls update(dt) each frame
    └── Systems (registered by priority)
        ├── InputSystem     polls GLFW keys, requests scene switches        (priority -100)
        ├── SceneSystem     loads/unloads scenes, spawns mesh entities       (priority 0)
        ├── MovementSystem  delta-time animation (e.g. duck rotation)         (priority 1)
        ├── CameraSystem    builds view/projection matrices from CameraComponent (priority 2)
        └── RenderSystem    uploads meshes/textures, records draw calls       (priority 100)
```

Components (`src/engine/ecs/components/components.zig`):

| Component                 | Purpose                                                |
| ------------------------- | ------------------------------------------------------ |
| `MeshComponent`           | CPU-side vertices + indices (optional ownership)       |
| `TransformComponent`      | position / rotation (Euler) / scale                    |
| `WorldTransformComponent` | full 4×4 transform matrix from glTF                    |
| `CameraComponent`         | eye, target, up, fov, near/far planes                  |
| `CameraMatricesComponent` | computed view + projection matrices (written by CameraSystem) |
| `TextureComponent`        | index into the bindless texture heap                   |
| `TextureDataComponent`    | raw pixel data + material ID (consumed by RenderSystem) |
| `SceneComponent`          | scene name, glTF path, camera position/target, offset  |
| `SceneActiveTag`          | marks the currently active scene                       |
| `ScenePendingTag`         | marks a scene requested for loading                     |
| `SceneOwnedComponent`     | links spawned entities to their owning scene           |

The Vulkan backend lives under `src/renderer/`:

| File                  | Responsibility                                              |
| --------------------- | ----------------------------------------------------------- |
| `zVulkanContext.zig`  | Vulkan context struct (device, swapchain, pipeline, descriptors) |
| `zvulkanSystem.zig`   | High-level init/deinit, per-frame render loop, texture upload |
| `device.zig`          | Physical/logical device selection, debug messenger, VMA allocator |
| `swapchain.zig`       | Swapchain creation, surface format picking, depth image     |
| `pipeline.zig`        | Graphics pipeline + shader loading (embedded SPIR-V)        |
| `upload.zig`          | Staging buffers, batched buffer/image transfers             |
| `material.zig`        | Texture upload, bindless descriptor management, texture reset |
| `renderSystem.zig`    | `RenderSystem` struct: GPU mesh upload, refcounting, draw recording |
| `vma_impl.cpp`        | VMA C++ implementation stub                                 |

## Recent Improvements

- **Scene management system**: Config-driven scene entities with runtime hot-swapping. `SceneSystem` handles loading glTF scenes, spawning mesh entities with `SceneOwnedComponent`, and unloading the previous scene's entities. Press `1` / `2` to switch between Duck and House scenes.
- **Event bus**: Added `EventBus` with `subscribe` / `emit` for decoupled communication. The render system subscribes to `scene_unloaded` to reset textures, and `entity_destroyed` triggers GPU mesh cleanup.
- **Input system**: `InputSystem` polls GLFW keyboard state each frame and requests scene switches by tagging scene entities with `ScenePendingTag`.
- **Movement system**: Delta-time-based `MovementSystem` rotates the duck model's `TransformComponent` yaw at 90°/second.
- **Config-driven initialization**: Engine config (window title/size, camera defaults, scene list) is declared in `config.zig` and consumed by `VulkanWorld.init`.
- **Delta-time update loop**: `Engine.run` computes frame delta time via GLFW and passes it through `SystemRunner.update` to all systems.
- **Renderer modularization**: Split the monolithic renderer into `device.zig`, `swapchain.zig`, `pipeline.zig`, `upload.zig`, and `material.zig`.
- **Batched GPU uploads**: `UploadBatch` records multiple buffer/image transfers into a single command buffer for fewer submission stalls.
- **Texture caching & deduplication**: `RenderSystem` caches uploaded textures by material ID to avoid re-uploading shared textures. GPU textures are reset on scene unload via the event bus.
- **Transform system overhaul**: `WorldTransformComponent` preserves full glTF transforms while `TransformComponent` provides local overrides. The renderer combines both (world × local) for the final model matrix.
- **GPU mesh refcounting**: `RenderSystem.attachMesh` with reference-counted `GpuMesh` pointers prevents double-free when multiple entities share the same mesh.
- **Type-safe glTF node access**: `NodeView` adapter struct replaces `anytype`-based C pointer access in the glTF loader.

## Project layout

```
src/
├── main.zig                      entry point
├── root.zig                      library root (re-exports VMA module)
├── ecs_test.zig                  ECS test entry point
├── engine/                       core engine
│   ├── engine.zig                generic Engine(WorldType) shell
│   ├── world.zig                 VulkanWorld: registry, system runner, system state
│   ├── config.zig                engine config (window, camera, scenes)
│   ├── math.zig                  4×4 matrix math (lookAt, perspective, transformToMatrix)
│   └── ecs/                      entity-component-system
│       ├── event.zig             EventBus (pub/sub)
│       ├── components/
│       │   └── components.zig    all component definitions
│       ├── entity/
│       │   ├── entity.zig        Entity handle + ComponentBit/ComponentIndex
│       │   ├── registry.zig      Registry: create/destroy, attach/get, Query
│       │   └── componentStorage.zig  sparse-set ComponentStorage(T)
│       └── systems/
│           ├── system.zig        System + SystemRunner (priority-sorted)
│           ├── input_system.zig  keyboard input → scene switching
│           ├── scene_system.zig  scene load/unload, entity spawning
│           ├── movement_system.zig  delta-time animation
│           ├── camera_system.zig view/projection matrix computation
│           └── render_system.zig ECS render system (delegates to renderer)
├── renderer/                     Vulkan renderer
│   ├── zVulkanContext.zig        VulkanContext struct + constants
│   ├── zvulkanSystem.zig         init/deinit, per-frame render loop
│   ├── device.zig                physical/logical device, debug messenger, VMA
│   ├── swapchain.zig             swapchain + depth image creation
│   ├── pipeline.zig              graphics pipeline + SPIR-V loading
│   ├── upload.zig                staging buffers, batched uploads
│   ├── material.zig              texture upload, bindless descriptors
│   ├── renderSystem.zig          GPU mesh upload/refcount, draw recording
│   ├── vma_impl.cpp              VMA C++ implementation stub
│   └── vmaimport.h               VMA include header
├── platform/                     platform abstraction
│   ├── window.zig                GLFW window management + input keys
│   ├── glfw3.zig                 GLFW bindings
│   ├── glfwimport.h              GLFW include header
│   └── zvkgl.zig                 Vulkan + GLFW C bindings
├── resources/                    resource loading
│   ├── meshLoader.zig            glTF loader (NodeView, primitives, materials)
│   └── cgltf.zig                 cgltf C bindings
├── shaders/                      Slang shaders + compiled SPIR-V
│   ├── shader.slang              main vertex/fragment shader
│   ├── triangle.slang            triangle test shader
│   ├── TorusKnot.slang           torus knot shader
│   ├── slang.spv                 compiled SPIR-V (embedded by pipeline)
│   ├── Torus.spv                 compiled torus SPIR-V
│   └── compile.bat               shader compilation script
└── native/                       C implementation files
    ├── cgltf_impl.c              cgltf implementation
    └── stb_image_impl.c          stb_image implementation
deps/                             third-party dependencies
│   ├── glfw/                     GLFW library + headers
│   ├── vma/                      Vulkan Memory Allocator
│   ├── vulkan/                   Vulkan loader library (vulkan-1.lib)
│   ├── cgltf/                    cgltf header
│   └── stb/                      stb_image header
assets/                           game assets
    ├── duck/                     duck glTF model + textures
    ├── House/                    hillside retreat house model
    └── shaders/                  shader sources + compiled SPIR-V
docs/                             documentation
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

# Run all tests (module + executable + ECS)
zig build test

# Run the GPU-free ECS unit tests only
zig build test-ecs

# Build with custom Vulkan SDK path
zig build -Dvulkan-sdk=/path/to/VulkanSDK/1.4.341.1
```

> **Heads up:** The Vulkan SDK path can be configured via:
> - The `--vulkan-sdk` build option: `zig build -Dvulkan-sdk=/path/to/VulkanSDK/1.4.341.1`
> - The `VULKAN_SDK` environment variable
> - Defaults to `../../../VulkanSDK/1.4.341.1/` if neither is set
>
> The build links OS-specific libraries: Windows uses vendored GLFW + Win32 libs (`gdi32`, `user32`, `shell32`, `vulkan-1`); Linux uses system GLFW + Vulkan loader; macOS uses system GLFW + Vulkan (MoltenVK) + Cocoa/IOKit/QuartzCore/Metal frameworks.

## Platform support

| Platform | Status                                                              |
| -------- | ------------------------------------------------------------------ |
| Windows  | Supported (primary development target)                             |
| Linux    | Partial — `zig build test-ecs`, `zig fmt`, and `zig ast-check` work; the full graphical build links against system GLFW + Vulkan loader |
| macOS    | Best-effort — build.zig includes GLFW + Vulkan (MoltenVK) + framework linking; untested |

## Roadmap

Core-engine milestones being worked toward before gameplay:

- [ ] Swapchain recreation / window resize handling
- [ ] Refactor global Vulkan state into a passed context
- [ ] Material system beyond base-color textures
- [ ] Lighting
- [x] ~~Scene/asset management and a proper update loop with delta time~~
- [x] ~~Input system~~
- [x] ~~Cross-platform build (Windows/Linux/macOS link steps)~~

## Acknowledgements

Built with [GLFW](https://www.glfw.org/), [Vulkan Memory Allocator](https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator), [cgltf](https://github.com/jkuhlmann/cgltf), [stb](https://github.com/nothings/stb), and [Slang](https://github.com/shader-slang/slang). Sample "Duck" model from the [glTF Sample Models](https://github.com/KhronosGroup/glTF-Sample-Models).
