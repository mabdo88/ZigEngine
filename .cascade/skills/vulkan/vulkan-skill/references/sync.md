# Vulkan Synchronization Reference

## Core Mental Model

A pipeline barrier defines a **dependency** between two sets of operations:
- **Execution dependency**: "all src-stage work before this barrier must complete before any dst-stage work after it begins"
- **Memory dependency** (via access masks): "flush src caches, invalidate dst caches" — required whenever one stage writes and another reads

Both are needed for correctness. Execution dependency alone does not make writes visible.

## Synchronization2 API (Prefer This)

```c
// Single barrier call — group all barriers here
VkBufferMemoryBarrier2 buf_barrier = {
    .sType         = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER_2,
    .srcStageMask  = VK_PIPELINE_STAGE_2_TRANSFER_BIT,
    .srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
    .dstStageMask  = VK_PIPELINE_STAGE_2_VERTEX_ATTRIBUTE_INPUT_BIT,
    .dstAccessMask = VK_ACCESS_2_VERTEX_ATTRIBUTE_READ_BIT,
    .buffer        = vertex_buffer,
    .offset        = 0,
    .size          = VK_WHOLE_SIZE,
};
VkDependencyInfo dep = {
    .sType                   = VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
    .bufferMemoryBarrierCount = 1,
    .pBufferMemoryBarriers    = &buf_barrier,
};
vkCmdPipelineBarrier2(cmd, &dep);
```

## Image Layout Transitions — Common Cases

| Use Case | oldLayout | newLayout | srcStage | srcAccess | dstStage | dstAccess |
|---|---|---|---|---|---|---|
| First upload (don't care about prior) | UNDEFINED | TRANSFER_DST_OPTIMAL | NONE | NONE | TRANSFER | TRANSFER_WRITE |
| After upload, sample in shader | TRANSFER_DST_OPTIMAL | SHADER_READ_ONLY_OPTIMAL | TRANSFER | TRANSFER_WRITE | FRAGMENT_SHADER | SHADER_READ |
| Color attachment → present | COLOR_ATTACHMENT_OPTIMAL | PRESENT_SRC_KHR | COLOR_ATTACHMENT_OUTPUT | COLOR_ATTACHMENT_WRITE | NONE | NONE |
| Present → color attachment | PRESENT_SRC_KHR | COLOR_ATTACHMENT_OPTIMAL | NONE | NONE | COLOR_ATTACHMENT_OUTPUT | COLOR_ATTACHMENT_WRITE |
| Depth write → depth sample | DEPTH_ATTACHMENT_OPTIMAL | DEPTH_READ_ONLY_OPTIMAL | EARLY/LATE_FRAGMENT_TESTS | DEPTH_STENCIL_ATTACHMENT_WRITE | FRAGMENT_SHADER | SHADER_READ |

**Never use `VK_IMAGE_LAYOUT_GENERAL` unless the spec requires it (storage images written and read in same pass, etc.).**

## Semaphores

- Binary semaphore: signal on queue A, wait on queue B. One signal per wait.
- Timeline semaphore (`VK_KHR_timeline_semaphore`, core 1.2): monotonically increasing counter. CPU can wait/signal too. Prefer for frame sync.
- Swapchain acquire returns a semaphore to wait on before writing the image.
- Present requires a semaphore signalled after rendering is complete.

```
Acquire image → signal acquire_semaphore
Submit render CB → wait acquire_semaphore (COLOR_ATTACHMENT_OUTPUT stage), signal render_semaphore
Present → wait render_semaphore
```

## Fences

- CPU-side sync primitive. Signal from `vkQueueSubmit`, wait via `vkWaitForFences`.
- **Must reset before reuse**: `vkResetFences` BEFORE calling `vkQueueSubmit` that will signal it.
- `vkWaitForFences` + `vkResetFences` is the correct frame-in-flight gating pattern.
- `VK_FENCE_CREATE_SIGNALED_BIT`: create pre-signaled for frame 0 so the wait doesn't stall before first submit.

## Events (VkEvent)

- Intra-queue async barrier. Set with `vkCmdSetEvent2`, wait with `vkCmdWaitEvents2`.
- Avoids the full pipeline bubble of a barrier if CPU needs to control the signal point.
- Rarely needed; use pipeline barriers for most cases.

## Subpass Dependencies

External dependencies (`VK_SUBPASS_EXTERNAL`) must be explicit for attachments transitioning in/out of a renderpass.

```c
// Transition swapchain image from UNDEFINED → COLOR_ATTACHMENT at renderpass begin
VkSubpassDependency dep = {
    .srcSubpass    = VK_SUBPASS_EXTERNAL,
    .dstSubpass    = 0,
    .srcStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    .dstStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    .srcAccessMask = VK_ACCESS_NONE,
    .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
};
```

## DO NOT

- `ALL_COMMANDS + ALL_MEMORY` as a lazy barrier — it serializes the entire GPU pipeline.
- Multiple single-barrier `vkCmdPipelineBarrier` calls — batch them.
- Assume any ordering without explicit sync (GPU executes out of order).
- Forget the memory dependency (access masks) when you set up execution dependency — writes won't be visible.
- Use `vkQueueWaitIdle` or `vkDeviceWaitIdle` in the render loop.
