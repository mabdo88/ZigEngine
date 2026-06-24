# Vulkan Pipelines & Shaders Reference

## Pipeline Cache

Always use. Save to disk and reload to avoid cold-start shader compilation stutter.

```c
// Load from disk (or empty if first run)
VkPipelineCacheCreateInfo cache_info = {
    .sType           = VK_STRUCTURE_TYPE_PIPELINE_CACHE_CREATE_INFO,
    .initialDataSize = cached_size,  // 0 if no cache yet
    .pInitialData    = cached_data,  // NULL if no cache yet
};
vkCreatePipelineCache(device, &cache_info, NULL, &pipeline_cache);

// Pass to all pipeline creation calls:
vkCreateGraphicsPipelines(device, pipeline_cache, 1, &create_info, NULL, &pipeline);

// Save on shutdown:
size_t size; vkGetPipelineCacheData(device, pipeline_cache, &size, NULL);
void* data = malloc(size); vkGetPipelineCacheData(device, pipeline_cache, &size, data);
// write data to file
```

## Specialization Constants

Replace compile-time #defines and shader permutations. Baked into pipeline at creation time.

```c
uint32_t max_lights_val = 64;
VkSpecializationMapEntry entry = { .constantID = 0, .offset = 0, .size = sizeof(uint32_t) };
VkSpecializationInfo spec_info = {
    .mapEntryCount = 1,
    .pMapEntries   = &entry,
    .dataSize      = sizeof(uint32_t),
    .pData         = &max_lights_val,
};
// Attach to VkPipelineShaderStageCreateInfo::pSpecializationInfo
```

GLSL: `layout(constant_id = 0) const int MAX_LIGHTS = 8;`

## Dynamic State

Minimize dynamic state — each dynamic state disables certain HW optimizations. Essential ones:

```c
VkDynamicState dynamic_states[] = {
    VK_DYNAMIC_STATE_VIEWPORT,
    VK_DYNAMIC_STATE_SCISSOR,
    // Add only what you actually change at draw time
};
```

Avoid: `VK_DYNAMIC_STATE_VERTEX_INPUT_EXT` in hot paths, state that changes per-draw when it could be baked.

## Vertex Input

- Pack vertex attributes tightly. Avoid unnecessary alignment gaps.
- Separate position-only buffer from full vertex buffer for depth-only passes (better cache behavior).
- Interleaved layout (pos+normal+uv in one buffer) is generally better than separate arrays for rasterization.

## Pipeline Layout Compatibility

Two pipeline layouts are **compatible for push constants** if they have the same push constant range. Compatible for descriptor set N if sets 0..N-1 are identical. Bind descriptor sets once, change push constants per draw.

## Rules

- Create pipelines asynchronously (off main thread, or during a loading screen).
- Never create a pipeline during the render loop.
- Cache key: hash all state that defines a pipeline variant (shader, blend mode, vertex format, renderpass).
- Minimize `vkCmdBindPipeline` calls — sort draw calls by pipeline, then by descriptor set.
- Switching tessellation / geometry / task / mesh shader stages on/off is expensive: avoid frequent toggling.
- Depth test with `COMPARE_OP_LESS` + clear to 1.0 is standard. Do NOT change compare op per frame without understanding Z-cull implications.
- Use `VK_CULL_MODE_BACK_BIT` by default. Only override when needed.

## SPIR-V Pitfalls

- Stale SPIR-V (cached from an old build) is the #1 cause of push constant size validation errors.
- Always recompile shaders when push constant structs or descriptor layouts change.
- Slang / glslang output: verify with `spirv-cross --reflect` that the interface matches.
- `VkShaderModule` is created from SPIR-V bytes. Destroy it after pipeline creation — not needed afterward.
