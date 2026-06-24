# Engine Architecture Reference (zvulkan / Zig)

## Architectural Invariants

- Components are **pure data**. No Vulkan calls inside component structs.
- Systems are **functions** (or structs with vtable). State lives in the system struct, not in World.
- `VulkanWorld` orchestrates systems; it does not own system state directly.
- Vulkan globals (instance, device, queues, allocator) live in `zvulkanContext.zig` — passed through, not global.
- Everything comptime-knowable should be comptime.

## System Registration Pattern (SystemDesc + SystemManager/Runner split)

```zig
// SystemDesc: describes a system's lifecycle
pub const SystemDesc = struct {
    name: []const u8,
    init: *const fn (world: *World) anyerror!void,
    update: *const fn (world: *World, dt: f32) anyerror!void,
    deinit: *const fn (world: *World) void,
};

// SystemManager: owns system state and lifecycle
// SystemRunner: owns the update loop and ordering
// Registration point: all_systems.zig
```

## ECS Upload Pattern

One-time GPU upload per mesh, keyed by entity ID:
```zig
// uploadMesh: staging → device-local, one-time command buffer, fence stall
// GpuMesh cached in AutoHashMap(u32, GpuMesh) by entity ID
// Pointer-compare caching: only re-upload if vertex data pointer changed
// Component cleanup: @hasDecl(T, "deinit") check in destroyEntity — call deinit on GPU resources
```

## Row-Vector Math Convention

- zvulkan uses **row-vector** math (consistent with renderSystem.zig's `transformToMatrix`).
- glTF stores matrices in **column-major** — convert on load in `sceneLoader.zig`.
- Conversion: transpose the 4x4 on import, or read columns as rows.
- Parent-world matrix accumulation: `child_world = parent_world * local_transform` (row-vector order).

## glTF Loading Pattern

```
cgltf_parse_file(...)
cgltf_load_buffers(...)  ← MUST call this or buffer data is null (segfault)
Walk nodes recursively, accumulate world matrix
Per primitive: extract material, imageIndex (null → white fallback slot)
Return gltfLoadResult { MeshData[], ImageData[] }
```

## Bindless Texture Pattern

```
set=0: per-frame FrameUBO (proj + view matrices)
set=1, binding=0: bindless COMBINED_IMAGE_SAMPLER[1024]
Push constants: model matrix (mat4) + texture index (u32) = 68 bytes
TextureComponent: holds u32 slot index into bindless heap
White fallback: slot 0 always = 1x1 white texture
```

## Init Order (zvulkan specific)

```
createDescriptorSetLayout()
    ↓
createPipeline()         ← needs layout
    ↓
createDescriptorPool()
    ↓
createSampler()
    ↓
renderSystem = rs.init()  ← needs pool, layout, sampler
```

## Zig-Specific Patterns

- `translate-c` on `vulkan.h` / `cgltf.h`: check for name collisions and missing `@import`.
- `cgltf` via `@cInclude`: remember `cgltf_load_buffers` is separate from `cgltf_parse_file`.
- stb_image: manual `stbi.zig` binding + `stb_image_impl.c` C source (define `STB_IMAGE_IMPLEMENTATION` once in the C file).
- VMA: link as C library, wrap in `vma.zig` thin bindings.
- `std.AutoHashMap(u32, GpuMesh)` for per-entity GPU resource cache.
- Vertex struct: `{ pos: [3]f32, normal: [3]f32, uv: [2]f32 }` — match pipeline vertex input attributes exactly.
- Sparse-set ECS: `ComponentStorage(T)` with freelist recycling and generation counters — dynamic add/remove is the reason sparse sets were chosen over archetypes.

## Devin Prompt Guidelines

When writing prompts for Devin to implement Vulkan code in this engine:
- Plain language only — no inline code in the prompt.
- Leave implementation details to Devin; specify goals and constraints.
- Reference file names and struct names from the existing codebase.
- Specify validation requirements: "must pass Vulkan validation layers with sync validation enabled".
- Specify the init order constraint explicitly when relevant.
