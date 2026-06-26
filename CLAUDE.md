# Strife Engine — Claude Code Reference

> **Read this file before touching any code.**
> This is the authoritative reference for the Strife game engine. Follow it exactly.

---

## ⚠️ Zig Master — Always Fetch Docs First

This project uses **Zig master (nightly)**. APIs change between builds.

**Before writing or modifying any Zig code:**

```
Language ref  → https://ziglang.org/documentation/master/
Stdlib ref    → https://ziglang.org/documentation/master/std/
Devlog        → https://ziglang.org/devlog/2026/
```

Known breaking-change areas to always verify:
- `build.zig` API (changes almost every release)
- `std.io.Writer` / `std.io.Reader` (redesigned in 0.15–0.16)
- `CallingConvention` — tagged union since 0.14
- `std.ArrayList`, `std.HashMap` — allocator pattern stable, but verify method names
- `@as`, `@intCast`, `@floatCast`, `@ptrCast` — semantics shifting; verify cast syntax
- **`std.Io` overhaul (large, easy to miss):** `std.time.Timer`, `std.fs.cwd()`/`std.fs.File`/`std.fs.Dir`, `std.Thread.sleep`, `std.crypto.random`, and `std.Thread.Mutex`/`Condition` are **all gone** — replaced by `std.Io.Clock`, `std.Io.Dir`/`std.Io.File`, `std.Io.sleep`, `std.Io.random`, and `std.Io.Mutex`/`Condition`/`Group`, every one of which takes an `Io` instance (get one via `std.Io.Threaded.init(allocator, .{}).io()`). `std.Io.Group.concurrent()`/`.await()` is the idiomatic replacement for a hand-rolled thread pool — `std.Io.Threaded` already defaults its worker count to `cpu_count - 1`. See `src/engine/timer.zig`, `fs.zig`, `jobs.zig`, `uuid.zig` for working examples on this exact codebase.

**Never write Zig code from memory alone. Always fetch the master docs first.**

---

## Project Identity

| Field | Value |
|-------|-------|
| Engine name | **Strife** |
| Language | Zig master (nightly) |
| Renderer | Vulkan 1.3, dynamic rendering (no VkRenderPass) |
| ECS | **Hand-rolled** sparse-set ECS (`src/engine/ecs/`) — not Flecs |
| Memory | VMA (Vulkan Memory Allocator) |
| Physics | Jolt Physics via thin C++ wrapper |
| Audio | miniaudio (single-header C) |
| Mesh/anim | cgltf (C binding) |
| Texture | stb_image, stb_truetype (C bindings) |
| Platform targets | Windows, Linux, macOS |
| Platform style | **GLFW** (`src/platform/glfw3.zig` C bindings) — not a custom Win32/X11/Cocoa layer |
| Build | `zig build` — see build commands below |

**The goal:** Complete engine milestones M0–M9, then stop engine work and build Strife gameplay only.

---

## Source Tree

```
strife/
├── build.zig                # Build script — always check master docs before editing
├── build.zig.zon            # Dependencies manifest
├── CLAUDE.md                # This file
├── ROADMAP.md               # Human-readable progress (mirror of HTML roadmap)
├── strife.ini               # Engine config (window size, vsync, etc.)
│
├── src/                     # ⚠️ Below this point: IMPLEMENTED layout, not aspirational
│   ├── main.zig             # Entry point — builds Config.default, runs Engine(VulkanWorld)
│   ├── root.zig             # VMA module export
│   │
│   ├── platform/            # GLFW wrapper (not a custom Win32/X11/Cocoa backend)
│   │   ├── window.zig       # Window create/destroy, input polling, surface creation
│   │   ├── glfw3.zig        # @cImport-generated GLFW bindings
│   │   └── zvkgl.zig        # @cImport-generated Vulkan bindings
│   │
│   ├── engine/
│   │   ├── engine.zig       # Generic Engine(WorldT) — init/run/deinit loop
│   │   ├── world.zig        # VulkanWorld — owns Vulkan context + Registry + systems
│   │   ├── config.zig       # Config struct (window, camera, scenes) — see main.zig
│   │   ├── math.zig         # Vec2/3/4, Mat4 (column-major), Quat — has unit tests
│   │   └── ecs/             # Hand-rolled sparse-set ECS (see "ECS Usage Pattern" below)
│   │       ├── entity/
│   │       │   ├── entity.zig          # Entity{ index, generation }
│   │       │   ├── componentStorage.zig # ComponentStorage(T) sparse set
│   │       │   └── registry.zig         # Registry — world/entity/component/query API
│   │       ├── event.zig    # EventBus — typed payload pub/sub
│   │       ├── components/components.zig # All component structs + AllComponents tuple
│   │       └── systems/
│   │           ├── system.zig         # System registration interface
│   │           ├── all_systems.zig    # Explicit system registration/order
│   │           ├── camera_system.zig
│   │           ├── input_system.zig
│   │           ├── movement_system.zig # fly camera (WASD + mouse look)
│   │           ├── render_system.zig
│   │           ├── scene_system.zig    # scene load + background preload thread
│   │           └── shared_state.zig
│   │
│   ├── renderer/            # Vulkan 1.3, dynamic rendering
│   │   ├── zVulkanContext.zig # VkInstance/device/queues/VMA
│   │   ├── zvulkanSystem.zig  # high-level per-frame orchestration over renderSystem
│   │   ├── renderSystem.zig   # low-level GPU draw/command submission
│   │   ├── swapchain.zig
│   │   ├── device.zig
│   │   ├── pipeline.zig
│   │   ├── material.zig
│   │   └── upload.zig         # staging-buffer uploads
│   │
│   ├── resources/           # Asset pipeline (mesh/texture import, not yet split out further)
│   │   ├── meshLoader.zig   # glTF (cgltf) → mesh + texture loading
│   │   ├── meshCache.zig    # dedup/cache of uploaded meshes, owned by Registry
│   │   └── cgltf.zig        # @cImport-generated cgltf bindings
│   │
│   ├── shaders/             # Slang source + compiled .spv, embedded via @embedFile (NOT assets/shaders/)
│   │   ├── shader.slang     # main lit pass: Blinn-Phong diffuse + 3x3 PCF shadow sampling
│   │   ├── shadow.slang     # depth-only vertex shader for the shadow map pass
│   │   └── compile.bat      # manual slangc invocation — no build.zig shader step exists yet
│   │
│   │
│   │   # ↓↓↓ NOT YET IMPLEMENTED — target layout for future milestones (M4+) ↓↓↓
│   │
│   ├── animation/
│   │   ├── skeleton.zig     # Skeleton asset + SkinMatrices computation
│   │   ├── anim_player.zig  # AnimPlayer component + sampling system
│   │   ├── blend_tree.zig   # 1D blend space
│   │   ├── state_machine.zig # ASM with transition blending
│   │   └── anim_events.zig  # Keyframe callbacks → Flecs events
│   │
│   ├── physics/
│   │   ├── physics_world.zig      # Jolt init via C++ wrapper
│   │   ├── jolt_wrapper.cpp       # extern "C" Jolt API surface
│   │   ├── jolt_wrapper.h
│   │   ├── raycast.zig
│   │   ├── character_controller.zig
│   │   ├── trigger.zig
│   │   └── collision_layers.zig
│   │
│   ├── scene/
│   │   ├── scene_save.zig   # Flecs world → JSON
│   │   ├── scene_load.zig   # JSON → Flecs world
│   │   ├── prefab.zig       # Flecs EcsIsA prefab system
│   │   └── spawner.zig      # SpawnPoint component + SpawnSystem
│   │
│   ├── audio/
│   │   ├── audio_device.zig # ma_engine init + AudioClip
│   │   ├── audio_3d.zig     # Spatial audio + listener tracking
│   │   └── audio_mixer.zig  # ma_sound_group bus hierarchy
│   │
│   ├── ui/
│   │   ├── font.zig         # stb_truetype → glyph atlas → GpuTexture
│   │   ├── text_renderer.zig
│   │   ├── image_renderer.zig
│   │   ├── button.zig
│   │   └── health_bar.zig
│   │
│   └── gameplay/
│       ├── health.zig
│       ├── movement.zig
│       ├── combat.zig
│       ├── ability_system.zig
│       ├── inventory.zig
│       ├── ai.zig
│       ├── projectile.zig
│       └── save_system.zig
│
├── assets/
│   ├── textures/
│   ├── meshes/
│   ├── materials/           # JSON material definitions
│   ├── prefabs/             # JSON prefab definitions
│   ├── abilities/           # JSON ability definitions
│   └── audio/
│
└── deps/                    # Vendored C libraries
    ├── flecs/
    ├── vma/
    ├── cgltf/
    ├── stb/
    └── miniaudio/
```

---

## Build Commands

```bash
# Build (debug)
zig build

# Build (release)
zig build -Doptimize=ReleaseFast

# Run
zig build run

# Compile shaders — manual step, NOT wired into build.zig yet
cd src/shaders && ./compile.bat
# runs slangc per .slang file, outputs .spv next to the source; pipeline.zig/shadow.zig
# pull the result in via @embedFile("../shaders/whatever.spv")
```

Shaders live in `src/shaders/` (Slang source `.slang` + compiled `.spv`), not `assets/shaders/` — there is no `assets/shaders/` directory. There's no `build.zig` shader step yet: `.spv` files are compiled by hand via `slangc` (see `src/shaders/compile.bat`) and checked in. If `build.zig` ever gains a shader-compile step, it should target `src/shaders/*.slang` and call `slangc`, not `glslc` — the engine writes shaders in Slang, not GLSL.

---

## Architecture Decisions

These are fixed — do not deviate without explicit approval.

### Math
- **Mat4 is column-major**: `m[col][row]` — matches GLSL `layout(column_major)`
- **`perspective_vk`** MUST negate Y (`result[1][1] *= -1`) and use depth range `[0, 1]` (not `[-1, 1]`)
- Quaternion: `{ x, y, z, w: f32 }` — w is the scalar component

### Vulkan
- **Dynamic rendering** only — no `VkRenderPass`, no `VkFramebuffer`
- Attach `VkPipelineRenderingCreateInfoKHR` to pipeline `pNext`
- **`FRAMES_IN_FLIGHT = 2`** (double-buffered submission)
- Use `vkCmdPipelineBarrier2` (sync2, core in 1.3) — not the deprecated single-stage version
- VMA for all buffer/image memory — no raw `vkAllocateMemory`
- Staging buffer pattern for all uploads (CPU → staging → GPU device-local)
- Shader push constant at offset 0: `{ model: Mat4 }` — 64 bytes, VERTEX stage
- Descriptor set layout: set 0 = camera + lights UBO, set 1 = material (UBO + albedo sampler)

### ECS (hand-rolled)
- `src/engine/ecs/entity/registry.zig` is the world: generational `Entity{ index, generation }` handles, sparse-set `ComponentStorage(T)` per component type (swap-remove on delete), `u64` component bitmask per entity index for queries
- Components are POD Zig structs — no heap allocations inside component data (a few legacy components own buffers and free them via an optional `deinit`, called by `Registry.set`/`remove`/`destroyEntity`/`deinit`)
- `Registry.Query(.{ComponentA, ComponentB})` builds a mask and iterates the smallest matching storage, mask-filtering the rest — no per-frame allocation
- Entity recycling: destroyed indices go on a free list and get incremented generations; a generation that hits `maxInt(u32)` is retired permanently instead of wrapping (prevents stale-handle collisions)
- Events are a small in-process `EventBus` (`src/engine/ecs/event.zig`) with typed payloads and `subscribe(event, ctx, callback)` — not Flecs observers
- Systems are plain Zig structs/functions registered through `src/engine/ecs/systems/system.zig` + `all_systems.zig`, not C callbacks; no Flecs phases — ordering is explicit in `all_systems.zig`
- If real archetype-relationship features (prefabs, `EcsIsA`, hierarchy queries) are ever needed beyond what the hand-rolled registry supports, that's the trigger to reconsider Flecs — not before

### Platform (GLFW)
- `src/platform/window.zig` wraps GLFW (`glfw3.zig`/`zvkgl.zig` C bindings) — engine code should go through `window.zig`, not call `glfwXxx` directly
- `Window.framebufferSize`, `createSurface`, `setCursorMode`, `getKey`/`getMouseButton`/`getCursorPos` cover current needs; resize is tracked via a module-level flag set by GLFW's framebuffer-size callback (`wasResized`/`clearResized`)
- `pollEvents()` is non-blocking, called once per frame from the main loop
- No custom Win32/X11/Cocoa backend exists or is planned unless GLFW becomes an actual blocker (e.g. licensing, missing platform feature)

### Memory
- `ArenaAllocator` for per-frame scratch — reset at frame start, never free individually
- `PoolAllocator(T)` for fixed-size ECS-adjacent objects
- `GPA` (GeneralPurposeAllocator) must be **heap-allocated, never stack-copied** — self-pointer stability
- All assets are heap-allocated through the `AssetManager` — never owned by ECS components directly

---

## Code Conventions

```zig
// Naming
snake_case            // functions, variables, fields
PascalCase            // types, structs, enums
SCREAMING_SNAKE       // comptime constants
m_prefix              // NEVER — this is Zig, not C++

// Error handling
fn foo() !T           // always propagate with try; no bare catch unless intentional
strife_assert(cond, msg, @src())  // use for internal invariants

// C interop
@ptrCast              // required for GLFW/Vulkan/cgltf/stb opaque types — always document why
[:0]const u8          // null-terminated strings for C APIs (window titles, file paths to C libs)

// Comptime
if (builtin.mode != .Debug) return;  // compile-time strip for debug-only code

// Components
// POD only — no allocator fields, no pointers to heap inside component structs
// If you need a reference, use AssetHandle(T) or an entity ID
```

---

## Vulkan Barrier Pattern

Always use sync2 (`VkImageMemoryBarrier2` + `vkCmdPipelineBarrier2`):

```zig
// CORRECT (sync2, Vulkan 1.3 core)
const barrier = VkImageMemoryBarrier2 {
    .srcStageMask  = VK_PIPELINE_STAGE_2_TRANSFER_BIT,
    .srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
    .dstStageMask  = VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
    .dstAccessMask = VK_ACCESS_2_SHADER_READ_BIT,
    .oldLayout     = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    .newLayout     = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    ...
};
vkCmdPipelineBarrier2(cmd, &dep_info);

// WRONG — deprecated single-stage version
// vkCmdPipelineBarrier(cmd, srcStage, dstStage, ...)
```

---

## ECS Usage Pattern

```zig
const Registry = @import("engine/ecs/entity/registry.zig").Registry;
const components = @import("engine/ecs/components/components.zig");

// Create entity + attach components
const e = try registry.create();
try registry.add(e, components.TransformComponent{ .position = .{0,0,0}, .rotation = .{0,0,0}, .scale = .{1,1,1} });
try registry.add(e, components.MeshComponent{ .mesh_id = mesh_id });

// Read/write a component
if (registry.get(components.TransformComponent, e)) |t| {
    t.position[1] += 1.0;
}

// Overwrite (deinits the old value first if the component owns memory)
try registry.set(e, components.TransformComponent{ ... });

// Query — iterates the smallest matching storage, mask-filters the rest
var it = registry.Query(.{ components.MeshComponent, components.TransformComponent });
while (it.next()) |entity| {
    const t = registry.get(components.TransformComponent, entity).?;
    // ...
}

// Destroy (frees owned component memory, emits .entity_destroyed)
try registry.destroyEntity(e);
```

Adding a new component type: add the struct to `components.zig`, add it to `AllComponents`/the bit-index table there — the registry's `StorageType()` picks it up automatically via the comptime tuple.

---

## Jolt C++ Wrapper Pattern

Jolt is C++ — always access it via `src/physics/jolt_wrapper.cpp`:

```cpp
// jolt_wrapper.cpp — export only what Zig needs
#include <Jolt/Jolt.h>
// ... Jolt includes ...

extern "C" {
    struct JoltCtx; // opaque
    JoltCtx* jolt_init();
    void     jolt_deinit(JoltCtx*);
    void     jolt_step(JoltCtx*, float dt, int substeps);
    uint32_t jolt_add_box(JoltCtx*, float hw, float hh, float hd, float mass, float px, float py, float pz);
    // ... etc
}
```

```zig
// In Zig — @cImport the header, never touch Jolt types directly
const jolt = @cImport({ @cInclude("jolt_wrapper.h"); });
```

---

## Roadmap

**Status key:** ` ` = todo · `~` = in progress · `x` = done

Update this section as tasks complete. The HTML roadmap (`Strife_Engine_Roadmap.html`) is the
canonical UI for progress tracking — keep both in sync.

---

### M0 — Foundation
- [x] **Window** — GLFW (`src/platform/window.zig`), not custom Win32/X11/Cocoa backends (deliberate divergence — see "Platform (GLFW)" above); Vulkan surface creation via `glfwCreateWindowSurface`
- [x] **Main Loop** — Fixed-timestep accumulator in `src/engine/engine.zig` (`FIXED_DT = 1/60`, capped at `MAX_STEPS_PER_FRAME = 5` to avoid a death spiral); render currently runs once per fixed step (not decoupled with an interpolation alpha — would need render pulled out of the system list first; flagged as a follow-up, not faked)
- [x] **Input** — `src/engine/input.zig` `InputState` with `isDown`/`justPressed`/`justReleased`, diffed each frame against a raw per-key poll (`anytype` key source, so it's GLFW-decoupled and unit-testable); no `InputEvent` queue — direct polling was already the established pattern here, edge detection layers on top of it rather than replacing it with an event model
- [x] **Timer** — `src/engine/timer.zig` `Timer.tick()/elapsed() -> f64`; built on `std.Io.Clock`, not `std.time.Timer` (removed in this Zig master — clock access moved behind an `Io` instance)
- [x] **Logging** — `src/engine/log.zig`: `Level` enum, `@src()` file:line, ANSI color, debug-level calls compiled out entirely outside `.Debug` via `comptime`
- [x] **Assertions** — `src/engine/assert.zig` `strife_assert(cond, msg, @src())`; `@breakpoint()` in Debug; the whole check (not just the breakpoint) compiles out in non-Debug builds
- [x] **Filesystem** — `src/engine/fs.zig`: `readFileAlloc`, `writeFile`, `fileExists`, `makeDirs`, `pathExt`, `pathStem`, `pathJoin`; built on `std.Io.Dir`, not `std.fs.cwd()` (also moved behind `Io` in this Zig master)
- [x] **Math** — `Vec2/3/4` (as `@Vector`), `Mat4` (column-major), quaternion-free Euler rotation in `transformToMatrix`; `perspective`/`orthographicSymmetric` (Y-flip, depth [0,1]); `lookAt`; no `Quat` or `AABB3` type yet — add when animation/physics actually need them
- [x] **Memory** — `VulkanWorld.scratch_arena` (per-frame `ArenaAllocator`, reset every fixed step, reachable from systems via `SystemCreateCtx.scratch`); `src/engine/pool.zig` `PoolAllocator(T)` (index-handle free-list, O(1) alloc/free — deliberately handle-based rather than raw-pointer, since ArrayList growth can move its buffer); GPA in `main.zig` is heap-pinned via the existing `var gpa = ...` + `defer gpa.deinit()` pattern
- [x] **Job System** — `src/engine/jobs.zig` `JobSystem.submit()/waitAll()`; built on `std.Io.Group` (`concurrent`/`await`), not hand-rolled `std.Thread`+`Mutex`+`Condition` — those primitives also moved behind `Io` in this Zig master, and `std.Io.Threaded` already defaults its worker count to `cpu_count - 1`, matching the spec directly
- [x] **Config** — `src/engine/ini.zig` `Ini.parse`/`getInt`/`getFloat`/`getBool`/`getStr` with defaults; `loadFromIni()` overlays `strife.ini` (repo root) onto `Config.default` — currently wires `window.width/height`, `window.vsync` (also threaded into real present-mode selection in `swapchain.zig`), and `engine.enable_validation`; extend the overlay as more fields need INI control
- [x] **UUID** — `src/engine/uuid.zig` `Uuid.v4()` via `std.Io.random` (not `std.crypto.random`, also moved behind `Io`); correct version/variant bits; `toBuf() -> [36]u8` hyphenated hex; `parse([]const u8) !Uuid`

---

### M1 — ECS
- [x] **Entity** — Not Flecs: `Registry.create/createEntity/destroyEntity/isAlive` in `src/engine/ecs/entity/registry.zig`, generational `{index, generation}` handles with retire-on-overflow
- [x] **Component Storage** — `Registry.add/set/get/remove`, backed by `ComponentStorage(T)` sparse sets; type→index/bit resolved at comptime via `components.ComponentIndex`/`ComponentBit`
- [x] **Sparse Set** — Swap-remove, fail-safety under allocator failure, all tested; 10k-entity create+attach+query+destroy benchmark in `registry.zig` (~2.2ms/0.13ms/0.9ms in a Debug build); strategy documented in `src/engine/ecs/README.md`
- [x] **Queries** — `Registry.Query(.{Types...})` — mask-built at comptime, iterates the smallest matching storage, mask-filters the rest
- [x] **Scheduler** — `SystemManager` in `system.zig`: explicit `priority`-ordered create/update/destroy, not Flecs phases or `ecs_defer_begin/end` — structural changes (add/remove) are just direct calls, no deferral needed since there's no archetype migration to protect against
- [x] **Events** — `EventBus` in `event.zig`: typed payloads, `subscribe(event, ctx, callback)`, not Flecs observers
- [x] **Transform** — `transform_system.zig` (priority 50, runs after Movement/Camera and before Render) recomputes `FinalTransformComponent = BakedTransformComponent * TransformComponent` every frame; `renderSystem.zig`'s main and shadow draw loops just read `FinalTransformComponent` now instead of each doing their own `matMul`
- [x] **Hierarchy** — `hierarchy_system.zig`: `setParent`/`clearParent`, `ParentComponent`; `HierarchySystem` (priority 60, after Transform/50, before Render/100) recursively concatenates `FinalTransformComponent` up the parent chain using the per-frame scratch arena for cycle/visited tracking; orphans (dead parent) and cycles both degrade gracefully to treating the entity as a root rather than crashing or hanging

---

### M2 — Assets
- [x] **Asset Manager** — `src/engine/assets.zig`: generic `AssetManager(T)` with `Handle{index, generation}`, `State{unloaded, loading, ready, failed}`, ref counting, path dedup, and async loading. Deviates from spec on one point deliberately: loads run on one `std.Thread` per in-flight request rather than `jobs.zig`'s `JobSystem` — `Io.Group.await` blocks the calling thread until the whole batch finishes, which is wrong for "kick off a load, poll next frame without blocking"; there's no non-blocking `Io.Future` poll in this Zig master. `JobSystem` stays the right tool for batch work where blocking the caller until done is fine. Not yet wired into the concrete mesh/texture pipeline — `MeshCache`/`RenderSystem.gpu_meshes` still do their own narrower dedup/refcounting; migrating those is a separate follow-up, not required for this item
- [x] **Mesh Import** — cgltf glTF loading + VMA staging upload + `GpuMesh{vertexBuffer, indexBuffer, indexCount}` (`meshLoader.zig`, `renderSystem.zig`); `src/resources/objLoader.zig` adds a v/vn/vt/f OBJ parser (fan-triangulated faces, attribute-triple dedup, negative-index support), wrapped as a one-mesh `GltfScene` so `scene_system.zig` dispatches `.obj` paths through the same pipeline as glTF — see `assets/cube.obj` for a working example
- [x] **Texture Import** — stb_image decode + upload (`material.zig`), `VK_FORMAT_R8G8B8A8_SRGB`. `upload.zig`'s `mipLevelsForSize`/`generateMipmaps` build a full mip chain via `vkCmdBlitImage` (sync2 barriers throughout — also modernized `UploadBatch.uploadImage`'s sync1 barriers to sync2 while touching this), used by both `uploadTexture` and `uploadTextureBatched`; image/view/usage flags updated accordingly. Verified with validation layers enabled against the real Duck texture — no errors
- [x] **Shader Import** — `build.zig` now has a `shaders` step (also wired into the exe and exe-test build steps) that runs `slangc` automatically — `compile.bat` is kept only as a manual fallback. Still Slang, not GLSL — that's a deliberate divergence, not a gap (see "Platform/Renderer" notes above). No `ShaderCache`: each `.slang` file maps to exactly one pipeline today, so there's no module-reuse case yet to cache against — add one if/when a second pipeline needs to share a shader module
- [x] **Material Assets** — `src/resources/materialLoader.zig` parses JSON `{ albedo, metallic, roughness }` (no `shader` field yet — only one pipeline exists, see Shader Import notes); `MaterialGpuData` (`zVulkanContext.zig`) is a bindless `StructuredBuffer<MaterialData>` (set1 binding1, parallel to the binding0 texture array), indexed via push constant `materialIndex` (renamed from `textureIndex`) — `material.zig`'s `registerMaterial`/`createMaterialBuffer` write it, `pipeline.zig` allocates/writes the descriptor. glTF materials now actually read `pbr_metallic_roughness.metallic_factor`/`roughness_factor` (previously ignored entirely); OBJ (which has no material info of its own) looks for a sibling `<name>.json` next to the `.obj` (see `assets/cube.obj` + `assets/cube.json`). The shader gained a real Blinn-Phong specular term modulated by metallic/roughness so this data isn't inert — verified against both paths with validation layers enabled, no errors. `TextureComponent` was removed (fully superseded by `MaterialComponent`). `resetTextures`/`resetMaterials` were flagged as a possible "leak on scene unload" and then removed entirely on closer inspection: `scene_system.zig` preloads every configured scene exactly once and keeps them all GPU-resident forever (by design — that's what makes switching instant), so calling either reset function on scene unload would have destroyed a different, still-needed scene's slots rather than freed anything genuinely unused. Total texture/material count is bounded by `Config.scenes.len`'s material count, not unbounded, so there was nothing to actually fix — the two functions were dead and dangerous-if-wired-up, not a missing call site
- [x] **Animation Assets** — Folded into M4's Skeletons task: `meshLoader.zig`'s `loadSkin` parses `cgltf_skin` data (joint nodes, inverse bind matrices, rest-pose local transforms) into a `Skeleton`, collected per-`GltfScene` alongside meshes/materials/primitives. Verified against a real skinned asset (`assets/Cesium_Man.glb`, Khronos sample) — see Skeletons below. Not yet wired into `scene_system.zig` entity spawning — that integration waits for M4's Animation Player task, where there's an actual pose to drive
- [x] **Hot Reload** — `src/engine/hotreload.zig`'s `FileWatcher`: background-thread mtime polling (default 100ms) with 300ms debounce (settles before firing, so a burst of editor saves only triggers once), generic over any watched path. Wired to shader reload specifically (`zvulkanSystem.zig`): `pipeline.zig`/`shadow.zig` now read `.spv` from disk at runtime instead of `@embedFile` (gated by `Config.hot_reload_shaders`, default on in Debug only), and a per-frame check destroys+recreates both pipelines when `slang.spv`/`shadow.spv` change. Texture/mesh reload aren't wired — out of scope for now, same reasoning as the Animation Assets deferral: each needs its own GPU-resource-recreation path. Verified live: edited `shader.slang`, recompiled, watched the running app hot-swap the pipeline with a log line, no restart. Caught and fixed two real bugs in the process: an alignment-mismatch-on-free bug (`@alignCast` doesn't change the underlying allocation's real alignment — switched to `readFileAllocOptions` with genuine 4-byte alignment) and a dangling-pointer bug (watcher thread started before the watcher was moved into its persistent storage). Also fixed a latent leak where `createPipeline`/`createShadowPipeline` always recreated the `VkPipelineLayout` rather than reusing it across reloads

---

### M3 — Renderer
- [x] **Swapchain** — Resize/recreate on `OUT_OF_DATE`/`SUBOPTIMAL` works; double-buffered (`max_frames_in_flight = 2`) is the correct minimum sync pattern for this engine's needs, not a gap — triple-buffering is a perf knob to revisit only if profiling ever calls for it; present mode is configurable (`pickPresentMode` in `swapchain.zig` — FIFO when `vsync=true`, MAILBOX-with-FIFO-fallback when `vsync=false`, driven by `strife.ini`)
- [x] **Pipelines** — `pipeline.zig`/`shadow.zig`/`debug.zig` build pipelines with `VkPipelineRenderingCreateInfo` (no renderpass), depth/cull/blend configured per pipeline; no on-disk `VkPipelineCache` yet (saves ~100ms cold-start at most) — deliberately deferred since dev-build startup time isn't a current pain point, not a missing capability; revisit post-M9 if shipping cold-start ever matters
- [x] **Command Buffers** — One pool, `vkResetCommandBuffer` per frame, one-shot upload helper (`upload.zig`), sync2 barriers (`VkImageMemoryBarrier2`/`vkCmdPipelineBarrier2`) throughout including the shadow and debug-draw passes
- [x] **Meshes** — Push-constant model matrix + `vkCmdDrawIndexed` works; no explicit `RenderCommand`/`RenderQueue` indirection — correct call, not a gap: the engine is single-threaded and GPU-bound, so `RenderSystem.update` querying and drawing directly from the ECS each frame avoids pointless per-frame allocation. Revisit only if entity counts explode or multi-threaded command recording becomes necessary
- [x] **Materials** — Binding 0 = UBO, binding 1 = bindless combined-sampler array; materials are a single bindless `StructuredBuffer<MaterialData>` indexed by push constant rather than one descriptor set per material — this is *better* than the original one-sampler-per-material spec (cheaper, hot-patchable, no per-material descriptor allocation), not a shortfall. UBO is persistently mapped
- [x] **Camera** — `CameraComponent`/`CameraMatricesComponent`, persistently-mapped UBO, `math.perspective` (the `perspective_vk` equivalent), fly-cam (WASD + right-mouse-drag look) in `movement_system.zig`/`input_system.zig`
- [x] **Lighting** — `Config.LightingConfig`, `FrameUBO.light_dir/light_color`, Blinn-Phong diffuse + ambient in `shader.slang`'s `fragMain`
- [x] **Shadows** — 2048×2048 `D32_SFLOAT` shadow map, orthographic light-space matrix (`math.directionalLightViewProj`), depth-only `shadowPipeline`, 3×3 PCF with 0.005 bias in `shader.slang`
- [x] **Debug Draw** — `src/renderer/debug.zig`: line-list pipeline (`debug.slang`) reusing the main pass's set-0 camera UBO (no push constants, no bindless set needed), depth-tested but not depth-writing so lines occlude correctly without corrupting the real depth buffer. Accumulates `DebugVertex{pos, color}` into a per-step `ArrayListUnmanaged` (any system with priority < 100 can call `ddLine`/`ddAxes`/`ddBox`/`ddSphere` via `render_system.zig`'s wrappers, which forward to `zvulkanSystem.zig`'s `ddLine`/`ddAxes`/`ddBox`/`ddSphere`, which forward to `debug.zig`); `RenderSystemState.update` (priority 100, runs last each fixed step) drains the list into the current frame-in-flight's persistently-mapped vertex buffer, draws it, and clears it for the next step. Wired into shader hot reload alongside the main/shadow pipelines. `RenderSystemState.update` draws world-origin axes every frame as a standing sanity check — verified live with validation layers enabled, no errors

---

### M4 — Animation
- [x] **Skeletons** — `src/animation/skeleton.zig`: `Skeleton{ joint_count, parent_indices, inverse_bind_matrices, rest_local_transforms }` (joints topologically sorted at load time so `parent_indices[i] < i` always holds, letting `computeSkinMatrices` do one forward sweep instead of recursing); `bindPose()` returns the rest-pose local transforms as the default `PoseBuffer` (identity transforms would *not* reproduce bind pose — only the actual rest-pose locals do). `src/animation/gltf_import.zig`'s `loadSkin` parses real `cgltf_skin` data into this type, verified end-to-end against `assets/Cesium_Man.glb` (Khronos sample, one skin/one animation) — `meshLoader.zig`'s `loadGltf` correctly reports 1 skeleton with a topologically valid joint order. Caught and fixed a real pre-existing gap while wiring this up: `zig build test`'s `exe_tests`/`mod_tests` were silently running 0 tests (Zig's lazy analysis never reaches `test` blocks in files only touched through the ordinary runtime call graph — the same reason `ecs_test.zig` exists as an explicit aggregator); fixed by adding a `comptime { _ = @import("resources/meshLoader.zig"); }` force-include in `main.zig`, which also surfaced math/log/skeleton tests transitively and brought `exe_tests` from 0 to 19 passing. A later pass split `loadSkin`/`loadAnimationClip`/`NodeView` out of `meshLoader.zig` into the dedicated `gltf_import.zig` (pure cgltf-to-animation-types glue, no mesh/material logic), renamed `loadgltf` → `loadGltf` for naming consistency, and fixed two real double-free bugs: per-iteration `errdefer`s on `skin_result.skeleton`/`times`/`values` inside loops that survive past a successful list-append, which would double-free against the outer list-iterating `errdefer` if a *later* iteration failed — removed in favor of relying solely on the outer one, matching the pattern the original mesh/material loading code already used correctly. `SkeletonComponent` (index into `Registry.skeleton_cache`, a long-lived cache parsed assets are duplicated into — see `src/animation/anim_cache.zig`) is now spawned by `scene_system.zig` for any primitive whose source asset has a skin. GPU skinning: `Vertex` gained `joints`/`weights` (`@Vector(4,u32)`/`@Vector(4,f32)`, defaulting to `(0,0,0,0)`/`(1,0,0,0)` so unskinned vertices route through a single always-identity buffer slot — `SKIN_IDENTITY_SLOT` — rather than needing a separate shader/pipeline path); `meshLoader.zig` reads `JOINTS_0`/`WEIGHTS_0` via `cgltf_accessor_read_uint`/`read_float` and remaps each vertex's joint indices through the same topological-sort table `loadSkin` builds (`SkinResult.old_to_new`) — vertex attributes reference the skin's *original* joint order, not the resorted skeleton, so skipping this remap would have silently bound vertices to the wrong joints. A single `skinMatrixBuffer` (bindless storage buffer, set 1 binding 2, `SKIN_MATRICES_PER_FRAME * max_frames_in_flight` capacity, addressed via an already frame-relative push-constant `skinOffset` so the descriptor binding itself never needs repointing) holds the palette; `shader.slang`'s `vertMain` blends up to 4 joint matrices per vertex by weight before the model matrix. `JointWorldComponent` (debug-draw world transforms) and the new `SkinPaletteComponent` (`world * inverse_bind`, what the GPU actually reads) are computed together each frame by `anim_player_system.zig` from one shared `computeWorldTransforms` call — they were the same component before this split, which would have been a real bug (debug-draw needs joint *positions*, the shader needs bind-pose-cancelling *skin* matrices, and those aren't the same data). Verified live: `Cesium_Man.glb`'s rendered mesh visibly deforms into a walking pose (arms down, leg mid-stride) instead of staying in the T-pose bind pose, and two screenshots a second apart show different poses — confirming the deformation tracks the animation, not a single static pose. Known gap: the shadow pass doesn't skin (no descriptor sets on `shadowPipelineLayout` to read the skin buffer from) — an animated mesh's shadow will show its bind-pose silhouette rather than the current pose
- [x] **Animation Player** — `src/animation/clip.zig`: `AnimationClip{ name, duration, channels[]Channel }`, `Channel{ joint_index, path: translation|rotation|scale, times[], values[][4]f32 }`, `JointPose{ translation, rotation, scale }` (decomposed TRS, not a matrix — channels overwrite one TRS component at a time, which a matrix can't represent). `sampleClip(clip, time, out_poses)` does a binary-search keyframe bracket per channel, `lerp` for translation/scale and a proper `slerp` for rotation (with the standard short-path dot-product flip and a linear fallback near `cos_half_theta ~= 1` to avoid a near-zero divide), clamping outside `[0, duration]` instead of extrapolating. `meshLoader.zig`'s `loadAnimationClip` parses real `cgltf_animation` channels, mapping `target_node` onto skeleton joint indices via the same topological remap `loadSkin` already builds; only LINEAR/STEP interpolation is read (verified `assets/Cesium_Man.glb` only uses LINEAR — CUBICSPLINE tangents aren't supported, channel is skipped with a warning if encountered). ECS wiring: `AnimPlayerComponent{ clip_id, time, speed, loop }` (index into `Registry.clip_cache`) plus `PoseBufferComponent`/`SkinMatricesComponent` (owned per-entity buffers, freed via the registry's generic component-`deinit` hook), driven each fixed step by `anim_player_system.zig` (priority 10, runs after Camera/before Transform) — `scene_system.zig` attaches all four components automatically whenever a spawned primitive's asset has a skin+clip. `render_system.zig`'s `drawSkeletons` debug-draws every animated entity's joint hierarchy as yellow lines every frame (a permanent, generic feature now, not asset-specific). Verified end-to-end three ways: a unit test confirming real `Cesium_Man.glb` data samples to different poses at different times, an `AnimPlayerSystem` unit test confirming time advances/loops and writes both the pose and world transforms correctly, and a temporary scene wired into `main.zig` (since reverted) showing the debug-drawn skeleton visibly change shape between two screenshots taken 2 seconds apart — proving the full spawn → sample → draw pipeline works through real ECS components, not test-only code paths. Still missing: GPU skinning (see Skeletons above) — the debug-draw overlay is the only visible proof the animation plays; the rendered mesh itself stays in bind pose until vertex skinning lands
- [ ] **Blend Tree** — `blend_poses(a, b, alpha, out)`; `BlendTree1D { points[]BlendPoint, param }`; find bracket + blend between adjacent clips
- [ ] **State Machine** — `ASMState`; `ASMTransition { condition fn, duration }`; snapshot prev_pose on transition; blend over `blend_dur` seconds
- [ ] **Animation Events** — `AnimEvent { time, name }` in clip; fire in `[last_time, new_time]` range; loop wraparound handled; Flecs emit → observer

---

### M5 — Physics
- [ ] **Collision** — Jolt init via `jolt_wrapper.cpp`; `PhysicsBody { body_id, is_static }`; `PhysicsSyncSystem` writes Jolt pos/rot to Transform each frame
- [ ] **Raycast** — `jolt_raycast` in wrapper; `body_to_entity HashMap`; `RaycastHit { entity, point, normal, fraction }`; `raycast_all` multi-hit variant
- [ ] **Character Controller** — Jolt `CharacterVirtual` via wrapper; `set_velocity`/`update`/`get_position`/`is_grounded`; gravity + jump in `CharacterSystem`
- [ ] **Triggers** — Sensor bodies (`mIsSensor=true`); `ContactListener` queue; `TriggerSystem` drains → emits `TriggerEvent { enter/exit, trigger_ent, other_ent }`
- [ ] **Collision Layers** — `ObjectLayer` enum (Static/Player/Enemy/Projectile/Trigger); `ObjectLayerPairFilterTable`; `CollisionLayer` ECS component; documented matrix

---

### M6 — Scene
- [ ] **Scene Save** — `SerializerRegistry { type_name → SerializeFn }`; query entities with `UUIDComponent`; JSON output; asset refs as UUID strings
- [ ] **Scene Load** — `DeserializerRegistry`; create entities with stored UUIDs; asset ref → `load_asset_by_uuid`; post-load physics recreation
- [ ] **Prefabs** — `ecs_add_id(EcsPrefab)`; `ecs_add_pair(EcsIsA, prefab)`; component override on instance; `PrefabRegistry { name → entity }`; load from JSON
- [ ] **Spawner** — `SpawnPoint { prefab_name, cooldown, max_active, active_count }`; `SpawnedBy` component; `DeathObserver` decrements active_count

---

### M7 — Audio
- [ ] **Audio Device** — `ma_engine_init`; `AudioClip { ma_sound }`; `clip_load/unload/play`; `AudioSource` ECS component; `auto_play` flag
- [ ] **3D Audio** — `ma_engine_listener_set_position/direction`; `ma_sound_set_position/rolloff/min_max_distance`; `Audio3DSystem` after CameraSystem
- [ ] **Mixer** — `ma_sound_group` bus chain (UI/SFX/Music → Master); `mixer_set_volume(bus, v)`; `AudioSettings` persisted to `strife.ini`

---

### M8 — UI
- [ ] **Text** — stb_truetype glyph atlas (1024×1024 R8); `GlyphInfo { uv_min/max, offset, advance }`; quad batch per frame; ortho projection; alpha blend
- [ ] **Images** — `UIVertex { pos, uv, color }`; quad emit; batched by texture; 1×1 white tex for solid rects; shares ortho UBO with text
- [ ] **Buttons** — `ButtonWidget { rect, label, state, on_click }`; `rect_contains` hit test; normal/hover/pressed state machine; draw via image+text renderer
- [ ] **Health Bars** — World-space pos → NDC → screen projection; background + fill rect; color lerp red→green by pct; hide at full HP

---

### M9 — Gameplay Ready
- [ ] **Health Component** — `Health { current, max, regen_per_sec, invincible }`; `DamageEvent { amount, dtype, source }`; `DeathObserver`; invincibility frames
- [ ] **Movement** — Camera-relative WASD via `CharacterController`; accel/friction lerp; sprint multiplier; `FootstepSystem`
- [ ] **Combat** — `jolt_overlap_sphere` melee hitbox; `damage_entity + apply_impulse`; attack cooldown; hit-reaction animation; invincibility frames on hit
- [ ] **Abilities** — `AbilityEffect` union; `AbilityDef { cooldown, resource_cost, cast_time, effects[] }`; `AbilitySlot[6]`; cast timer; load from JSON
- [ ] **Inventory** — `ItemStack[20]` slots; `ItemDef { on_use fn }`; `RelicInventory[3]`; `PickupSystem` on TriggerEnter; persist to save
- [ ] **AI** — FSM (patrol/chase/attack/retreat/dead); `check_sight` via raycast; steer via CharacterController velocity; basis for Knave boss behavior trees
- [ ] **Projectiles** — `Projectile { velocity, damage, owner, lifetime }`; per-frame raycast sweep; `on_hit` callback; impact VFX via `prefab_instantiate`
- [ ] **Save/Load** — `SaveData { health, pos, rot, inventory, relic_ids, flags[] }`; JSON to `saves/slot_N.json`; F5 quicksave / F9 quickload; autosave slot 255

---

### M10 — STOP ENGINE ⛔

> **After M9 is complete: stop all engine work. Build Strife gameplay only.**

---

## How Claude Code Should Work on This Project

1. **Always read docs before writing Zig** — fetch `https://ziglang.org/documentation/master/` for any API you're unsure about.
2. **Check the roadmap** — implement the current lowest-numbered incomplete task unless instructed otherwise.
3. **One file at a time** — implement a task fully and test it before moving to the next.
4. **Follow the architecture decisions** — no deviations from the column-major Mat4, dynamic rendering, sync2 barriers, or ECS patterns above.
5. **Never add a dependency without asking** — the dep list is fixed.
6. **No cross-cutting** — don't reach into the renderer from ECS code; don't reach into gameplay from the platform layer.
7. **Mark tasks done** — update the `[ ]` checkboxes in this file when a task is complete.
8. **Component data is POD** — if a component needs a heap-allocated resource, store an `AssetHandle(T)` or an entity ID, not a raw pointer.
9. **Zig master API is not stable** — if a compile error suggests an API changed, fetch master docs and fix it; don't guess.
10. **Debug draw is your friend** — use `dd_axes`, `dd_box`, `dd_sphere` to visualize new systems before the UI is ready.
