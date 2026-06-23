# AGENTS.md

Guidance for AI coding agents working in this repository. Human contributors may
also find it useful, but the canonical project overview is [`README.md`](README.md).

## Project Identity

This repository is a Zig game engine and game project built on a **Vulkan 1.3**
renderer (dynamic rendering, no render passes) and an **ECS**-structured,
data-oriented design. It is early / pre-alpha — APIs change frequently. Windows is
the primary development target; Linux is partially supported (ECS tests,
formatting, and the graphical build against the system Vulkan loader); macOS is
best-effort.

## Prime Directive

Before writing code, preserve the architecture:

- Data-oriented design first.
- ECS systems operate over dense component data.
- Avoid object-oriented entity hierarchies.
- Avoid hidden allocations in hot paths.
- Prefer explicit ownership, stable handles, and cache-friendly storage.
- Renderer code must respect Vulkan lifetime, synchronization, descriptor,
  pipeline, and command buffer rules.

## Zig Version

Target **Zig 0.16.0** stable (`minimum_zig_version = "0.16.0"` in `build.zig.zon`)
unless explicitly asked to test against Zig master / 0.17-dev. When upgrading Zig,
read the official release notes first and produce a migration report before
editing.

## Zig documentation lookup (read before writing Zig)

**Before writing, fixing, migrating, or reviewing any Zig code, always consult
[`zig-docs/SKILL.md`](zig-docs/SKILL.md) and fetch the relevant live documentation
first.** Zig breaks compatibility nearly every release, so do not write Zig from
memory — resolve the target version, fetch the matching language ref / stdlib /
release notes (and confirm against the installed toolchain's stdlib source when
present), then use exact signatures. Structural templates are in
[`zig-docs/references/patterns.md`](zig-docs/references/patterns.md).

## ECS research lookup (read before any ECS work)

**Before implementing any ECS feature, making an ECS architectural decision, or
adding a new engine system in Strife, always consult
[`ecs-research/SKILL.md`](ecs-research/SKILL.md) and fetch the relevant Flecs and
EnTT documentation first.** Do not design ECS from memory. Name the problem,
fetch the Flecs docs first (we use Flecs), cross-reference EnTT for the
sparse-set tradeoff, then adapt to Strife — watching for archetype move cost,
deferred-operation semantics at frame boundaries, and singleton candidates
(e.g. the Contiguity scale). Pre-digested patterns are in
[`ecs-research/references/flecs-patterns.md`](ecs-research/references/flecs-patterns.md)
(Flecs C API) and
[`ecs-research/references/other-ecs.md`](ecs-research/references/other-ecs.md)
(EnTT, Bevy, Unity DOTS, Unreal Mass Entity).

## Setup

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

## Engine Architecture

Core layers:

- platform
- memory
- ecs
- assets
- renderer_vulkan
- gameplay
- tools/editor

ECS rules:

- Entity IDs are handles, not objects.
- Components are plain data.
- Systems contain behavior.
- Systems should process batches / archetypes / sparse sets, not individual heap
  objects.
- Avoid per-frame allocations.
- Any new feature must document which components, systems, resources, and events
  it adds.

How this maps onto the current code:

- `Engine` (`src/engine/engine.zig`) is generic over a `WorldType` (currently
  `VulkanWorld`) and owns the allocator and main loop.
- `VulkanWorld` (`src/engine/world.zig`) holds the `Registry`
  (`src/engine/ecs/entity/registry.zig` — entity lifecycle + sparse-set component
  storage) and a `SystemRunner` (`src/engine/ecs/systems/system.zig`) that calls
  each system's `update(dt)` in ascending-priority order every frame.
- `EventBus` (`src/engine/ecs/event.zig`) is pub/sub for the `entity_destroyed`
  and `scene_unloaded` events; the render system subscribes to clean up GPU
  resources.
- System priorities (lower runs first): `input_system` (-100) → `scene_system`
  (0) → `movement_system` (1) → `camera_system` (2) → `render_system` (100), all
  under `src/engine/ecs/systems/`.
- Textures are bindless: a single descriptor array indexed by a push-constant
  slot. The render system caches uploaded textures by material ID and resets GPU
  textures on scene unload via the event bus.

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
│   └── ecs/
│       ├── components/          component definitions (components.zig)
│       ├── entity/              entity handle, registry, sparse-set storage
│       ├── systems/             input/scene/movement/camera/render + SystemRunner
│       └── event.zig            EventBus (entity_destroyed, scene_unloaded)
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

## Verification

Before proposing completion:

- Run formatting (`zig fmt src/`).
- Run the Zig build/tests — at minimum `zig build test-ecs` (GPU-free); also
  `zig build test` and `zig build` when a GPU and Vulkan are available.
- Run relevant rendering or gameplay smoke tests if available (e.g. the headless
  lavapipe run above).
- Mention any skipped checks.

## Conventions for agents

- Don't claim a change builds graphically unless you actually ran the Vulkan
  build.
- Keep edits minimal and idiomatic — match the surrounding Zig style; prefer
  explicit memory handling and avoid hidden allocations.
- Vendored C/C++ deps in `deps/` are upstream code — do not hand-edit them.
- Generated/build artifacts (`zig-out/`, `.zig-cache/`, `zig-pkg/`, `docs/`,
  `*.exe`, `*.pdb`) are git-ignored; never commit them.
- `main` is the default, up-to-date branch. Do work on a feature branch and open a
  PR rather than pushing directly to `main`.
