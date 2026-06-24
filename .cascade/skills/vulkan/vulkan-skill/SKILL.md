---
name: vulkan
description: >
  Comprehensive Vulkan API skill covering spec-correct usage, architecture patterns, synchronization, 
  memory management, descriptors, render passes, pipelines, and engine integration. ALWAYS trigger 
  this skill whenever the user mentions: Vulkan, vk*, VkBuffer, VkImage, VkPipeline, VkRenderPass, 
  VkCommandBuffer, VkDescriptorSet, VkSemaphore, VkFence, vkQueueSubmit, swapchain, SPIR-V, 
  VMA, barriers, image layouts, bindless, push constants, dynamic rendering, synchronization2, 
  glTF loading with Vulkan, ECS rendering, GPU upload, staging buffers, descriptor indexing, 
  or any low-level GPU/graphics programming topic in context of this engine. Also trigger for 
  architectural questions about render systems, pipeline layouts, frame-in-flight patterns, or 
  Zig+Vulkan integration. Do not skip this skill even if the question seems simple — correctness 
  and spec-compliance are non-negotiable in Vulkan code.
---

# Vulkan Skill

Before answering ANY Vulkan question, use this skill to check correctness against the spec and best practices. Vulkan is unforgiving — undefined behavior is silent on some drivers and catastrophic on others.

## Quick-Reference Rules (Always Apply)

### Init Order (non-negotiable)
```
createInstance → selectPhysicalDevice → createLogicalDevice
→ createSwapchain → createRenderPass / setup dynamic rendering
→ createDescriptorSetLayout → createPipelineLayout → createPipeline
→ createDescriptorPool → allocateDescriptorSets → updateDescriptorSets
→ createCommandPool → allocateCommandBuffers → createSyncObjects
```
**Layouts must exist before pipelines. Descriptor sets must be allocated before they are written.**

### The Golden Sync Rules
1. Never assume ordering without an explicit dependency (barrier, semaphore, fence, subpass dependency).
2. Use `VK_KHR_synchronization2` (core in 1.3). Prefer `vkCmdPipelineBarrier2` over the old API.
3. Batch barriers: one `vkCmdPipelineBarrier2` call with multiple barriers > multiple calls.
4. Use the **minimum** stage/access mask that is correct. Never use `ALL_COMMANDS` / `ALL_MEMORY` as a shortcut.
5. `VK_IMAGE_LAYOUT_UNDEFINED` as `oldLayout` is valid and correct when prior content is not needed (clears, first-use).
6. Fences synchronize CPU↔GPU. Semaphores synchronize GPU queue→queue. Events are for within-queue async barriers.
7. Every `vkQueueSubmit` that signals a semaphore must have a corresponding wait (or the semaphore leaks).

### Memory Rules
- Never call `vkAllocateMemory` per resource. Use VMA or a suballocator.
- Use `VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT` for render targets and large images.
- Staging pattern: `HOST_VISIBLE + HOST_COHERENT` staging → `vkCmdCopyBuffer` → `DEVICE_LOCAL` target, barrier with `TRANSFER_BIT` src stage.
- Use `VK_EXT_memory_budget` to stay under VRAM budget (target ≤80%).
- Persistent-map staging buffers for per-frame uniform data; do NOT map/unmap each frame.

### Descriptor Rules
- Descriptor set layout must be created before `VkPipelineLayout`.
- Do NOT update a descriptor set while it is in use on the GPU without `UPDATE_AFTER_BIND`.
- One descriptor pool per frame-in-flight avoids synchronization headaches; reset via `vkResetDescriptorPool`.
- Bindless: requires `VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT | VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT` and a pool with `VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT`.
- Push constants: fastest path for per-draw scalars/indices. Total size ≤128 bytes is safe everywhere; check `maxPushConstantsSize`.
- Minimize gaps between bindings in a descriptor set layout — gaps waste GPU memory.

### Pipeline Rules
- Always use a pipeline cache (`VkPipelineCache`). Save/restore across runs.
- Create pipelines asynchronously, never on the hot path.
- Minimize `vkCmdBindPipeline` calls — sort draw calls by pipeline.
- Use specialization constants instead of shader permutation source files.
- Do NOT change tessellation/geom/task/mesh shader on/off frequently — expensive state change.
- `VK_IMAGE_LAYOUT_GENERAL` is a correctness crutch; avoid it in production paths.

### Command Buffer Rules
- Pool formula: `L * T + N` (L=frames-in-flight, T=recording threads, N=secondary CB pools).
- Reuse command pools; never destroy/recreate per frame.
- `ONE_TIME_SUBMIT_BIT` for single-use CBs (e.g. upload). `SIMULTANEOUS_USE_BIT` only when truly needed.
- Do NOT submit tiny command buffers with only a few draw calls each — driver overhead dominates.
- Per-frame: reset the command pool (`vkResetCommandPool`), not individual command buffers.

### Render Pass / Dynamic Rendering
- Prefer `VK_KHR_dynamic_rendering` (core in 1.3) for new code. Avoids renderpass/framebuffer boilerplate.
- Use `LOAD_OP_CLEAR` instead of `vkCmdClearAttachments` — lets the driver skip loading unnecessary data.
- Use `LOAD_OP_DONT_CARE` for any attachment whose prior content is irrelevant (depth-only passes, first frame).
- Use `STORE_OP_DONT_CARE` for depth/stencil that doesn't need to persist past the renderpass.
- `VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT` for MSAA resolve attachments and transient depth buffers (mobile/TBDR).
- Subpass dependencies must be explicit; implicit external dependencies are not reliable.

---

## Detailed Reference Files

Load these when the question is deep in one area:

| Topic | File | When to Load |
|---|---|---|
| Synchronization deep-dive | `references/sync.md` | barriers, image layouts, semaphores, events, timeline semaphores |
| Memory & VMA | `references/memory.md` | allocation strategy, staging, budget, ReBAR, dedicated allocs |
| Descriptors & Bindless | `references/descriptors.md` | descriptor indexing, bindless heap, push descriptors, descriptor buffers |
| Render Pass & Dynamic Rendering | `references/renderpass.md` | load/store ops, subpass deps, MSAA, dynamic rendering |
| Pipelines & Shaders | `references/pipeline.md` | cache, specialization, layout, vertex input, SPIR-V |
| Command Buffers & Queues | `references/commands.md` | pools, submission, secondary CBs, async compute |
| Swapchain & Presentation | `references/swapchain.md` | present modes, image acquisition, resize handling |
| Engine Architecture (zvulkan/Zig) | `references/engine_arch.md` | ECS integration, system registration, Zig-specific patterns |

---

## Common Pitfalls (Catch These First)

**Sync bugs (silent on some GPUs, crash on others):**
- Writing to a buffer/image without a barrier before reading in the next command.
- Using `vkCmdCopyBuffer` then drawing without a `TRANSFER_WRITE → VERTEX_ATTRIBUTE_READ` barrier.
- Image layout mismatch (writing as `COLOR_ATTACHMENT_OPTIMAL`, sampling as `SHADER_READ_ONLY_OPTIMAL` without transition).
- Fence not reset before re-submitting (must call `vkResetFences` before `vkQueueSubmit`).
- Missing `VK_SUBPASS_EXTERNAL` dependency on the write side of a renderpass attachment.

**Correctness violations:**
- Calling any Vulkan API after `VK_ERROR_DEVICE_LOST` (undefined, use `VK_EXT_device_fault` to query reason).
- Updating a descriptor set while in-flight GPU work references it (without `UPDATE_AFTER_BIND`).
- Destroying a resource while still referenced in a pending command buffer.
- `cgltf_parse_file` without calling `cgltf_load_buffers` after — buffer data will be null.
- Push constant size in pipeline layout ≠ size in `vkCmdPushConstants` range or shader — validation error.

**Performance traps:**
- `vkDeviceWaitIdle` / `vkQueueWaitIdle` in the render loop — serializes CPU and GPU.
- Mapping/unmapping memory every frame instead of persistent map.
- `VK_IMAGE_LAYOUT_GENERAL` on everything.
- One `vkAllocateMemory` per resource.
- Redundant barriers with overly broad stage masks (e.g. `ALL_COMMANDS` when only `FRAGMENT_SHADER` needed).
- Not batching barriers into a single `vkCmdPipelineBarrier2` call.
- Re-recording entire command buffers when only uniform data changed — update the uniform buffer instead.

---

## Zig-Specific Notes (zvulkan)

- Zig translate-c produces C-compatible bindings; prefer the `vk.zig` or translated `vulkan.h` approach already in place.
- `@hasDecl` comptime check for component `deinit` is the correct pattern for ECS cleanup of GPU resources.
- Slang shader → SPIR-V: ensure push constant block size matches `VkPushConstantRange.size` exactly; stale SPIR-V is a common source of validation errors.
- Row-vector math (zvulkan convention): glTF is column-major — convert on load. `transformToMatrix` convention must be consistent across `renderSystem.zig` and `sceneLoader.zig`.
- `VmaAllocator` must be created after `VkDevice`; pass it through context, not global state.
- One-time submit pattern: `vkBeginCommandBuffer(ONE_TIME_SUBMIT_BIT)` → record → `vkEndCommandBuffer` → `vkQueueSubmit` → `vkWaitForFences` → `vkFreeCommandBuffers`.

---

## Validation Layer Policy

**Always recommend validation layers during development.** Key layers:
- `VK_LAYER_KHRONOS_validation` — catches spec violations, sync hazards (with sync validation enabled), best practices.
- Enable sync validation: `VkValidationFeaturesEXT` with `VK_VALIDATION_FEATURE_ENABLE_SYNCHRONIZATION_VALIDATION_EXT`.
- Enable best practices: `VK_VALIDATION_FEATURE_ENABLE_BEST_PRACTICES_EXT`.
- `VK_EXT_debug_utils`: use `vkSetDebugUtilsObjectNameEXT` to name all handles — invaluable in validation output.

Never ship validation layers enabled. Never ignore validation errors — they indicate undefined behavior.
