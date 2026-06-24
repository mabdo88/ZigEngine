# Vulkan Memory Management Reference

## Memory Type Selection

| Usage | VMA Flag | Memory Properties |
|---|---|---|
| GPU-only resources (VB, IB, textures) | `VMA_MEMORY_USAGE_AUTO` | `DEVICE_LOCAL` |
| Staging buffer (CPU→GPU upload) | `VMA_MEMORY_USAGE_AUTO` + `HOST_ACCESS_SEQUENTIAL_WRITE` | `HOST_VISIBLE + HOST_COHERENT` |
| Readback buffer (GPU→CPU) | `VMA_MEMORY_USAGE_AUTO` + `HOST_ACCESS_RANDOM` | `HOST_VISIBLE + HOST_CACHED` |
| Per-frame uniforms (small, frequent) | Persistent-mapped staging or BAR | `HOST_VISIBLE + DEVICE_LOCAL` if available (ReBAR) |

## VMA Patterns

### Device-local upload (staging pattern)
```c
// 1. Create staging buffer
VmaAllocationCreateInfo staging_info = {
    .flags = VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT | VMA_ALLOCATION_CREATE_MAPPED_BIT,
    .usage = VMA_MEMORY_USAGE_AUTO,
};
vmaCreateBuffer(allocator, &buf_info, &staging_info, &staging, &staging_alloc, &staging_alloc_info);
memcpy(staging_alloc_info.pMappedData, data, size);

// 2. Create device-local target
VmaAllocationCreateInfo gpu_info = { .usage = VMA_MEMORY_USAGE_AUTO };
vmaCreateBuffer(allocator, &buf_info, &gpu_info, &gpu_buf, &gpu_alloc, NULL);

// 3. Copy via command buffer, then barrier
vkCmdCopyBuffer(cmd, staging, gpu_buf, 1, &region);
// TRANSFER_WRITE → VERTEX_ATTRIBUTE_READ barrier here

// 4. Destroy staging after fence signals
```

### Persistent-mapped uniforms
```c
VmaAllocationCreateInfo info = {
    .flags = VMA_ALLOCATION_CREATE_MAPPED_BIT | VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
    .usage = VMA_MEMORY_USAGE_AUTO_PREFER_HOST, // or AUTO with HOST_ALLOW_TRANSFER_INSTEAD
};
// pMappedData stays valid for lifetime of allocation — write directly each frame
memcpy(alloc_info.pMappedData, &ubo_data, sizeof(ubo_data));
// No unmap needed. Flush if memory is not HOST_COHERENT:
// vmaFlushAllocation(allocator, alloc, 0, VK_WHOLE_SIZE);
```

## Rules

- Recommended heap allocation size: **256 MB** per heap. Sub-allocate from there.
- Use `VK_EXT_memory_budget`: stay at ≤80% of reported budget to avoid eviction stutter.
- Render targets & large images: use `VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT`.
- MSAA resolve attachments and transient depth buffers: use `VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT` (saves bandwidth on TBDR/mobile).
- ReBAR (256 MB BAR is default; ReBAR = full VRAM as BAR): use `HOST_ACCESS_ALLOW_TRANSFER_INSTEAD` flag, check if allocation ended up HOST_VISIBLE.
- Do NOT call `vkAllocateMemory` or `vkMapMemory` per resource or per frame — both are expensive.
- Do NOT create/destroy staging buffers per upload if uploads are frequent — pool them.
- Use `VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT` only for readback (GPU→CPU), never for upload paths.

## Priority

Use `VmaAllocationCreateInfo::priority` (0.0–1.0) for `VK_EXT_pageable_device_local_memory`:
- Render targets, framebuffers: 1.0
- Textures: 0.5
- Vertex/index buffers: 0.25 (can be re-uploaded if evicted)
- Staging buffers: irrelevant (system memory anyway)
