# Vulkan Command Buffers & Queues Reference

## Command Pool Formula

```
L * T + N
L = frames in flight (typically 2–3)
T = threads that record command buffers
N = extra pools for secondary command buffers
```

One command pool per thread per frame. Reset the pool, not individual command buffers:
```c
vkResetCommandPool(device, pool, 0);  // resets all CBs allocated from it
```

## One-Time Submit Pattern (uploads, transitions)

```c
VkCommandBufferBeginInfo begin = {
    .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
};
vkBeginCommandBuffer(cmd, &begin);
// ... record transfer/transition commands ...
vkEndCommandBuffer(cmd);

VkSubmitInfo submit = {
    .sType              = VK_STRUCTURE_TYPE_SUBMIT_INFO,
    .commandBufferCount = 1,
    .pCommandBuffers    = &cmd,
};
vkQueueSubmit(queue, 1, &submit, fence);
vkWaitForFences(device, 1, &fence, VK_TRUE, UINT64_MAX);
vkResetFences(device, 1, &fence);
vkFreeCommandBuffers(device, pool, 1, &cmd);
```

## Frame-in-Flight Pattern

```
Frame N:
  vkWaitForFences(frame_fence[N % MAX_FRAMES_IN_FLIGHT])
  vkResetFences(frame_fence[...])
  vkAcquireNextImageKHR → image_index, signals acquire_semaphore
  vkResetCommandPool(...)
  record command buffer
  vkQueueSubmit: wait acquire_semaphore, signal render_semaphore, signal frame_fence
  vkQueuePresentKHR: wait render_semaphore
```

**Create frame_fence with `VK_FENCE_CREATE_SIGNALED_BIT` so frame 0 doesn't stall.**

## Queue Submission Rules

- Minimize `vkQueueSubmit` calls — each has significant CPU overhead. Batch multiple CBs per submit.
- Don't submit tiny CBs with only a few draw calls each.
- Never wait for submission to finish before preparing the next frame.
- Async compute: use a separate queue family (`VK_QUEUE_COMPUTE_BIT` without `GRAPHICS`). Synchronize with semaphores, not barriers (different queues).
- Transfer queue: for background streaming. Use timeline semaphores to signal completion.

## Secondary Command Buffers

Use sparingly. Benefits: parallel recording of complex scenes. Cost: `vkCmdExecuteCommands` overhead.
- Allocate from `VK_COMMAND_BUFFER_LEVEL_SECONDARY`.
- Must specify `VK_COMMAND_BUFFER_USAGE_RENDER_PASS_CONTINUE_BIT` when recorded within a renderpass.
- Benchmark first — the overhead can exceed the parallelism benefit for modest scene complexity.

## Rules

- NEVER destroy and recreate command pools each frame — reuse them.
- `SIMULTANEOUS_USE_BIT`: only when a CB will be submitted multiple times before completion. Rare. May hurt GPU performance.
- For async resource upload: use a dedicated transfer queue + staging buffer + timeline semaphore. Signal the graphics queue when upload is complete.
- Thread safety: `vkQueueSubmit` requires external synchronization on the queue object. One thread submits to one queue.
