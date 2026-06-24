# Vulkan Swapchain & Presentation Reference

## Present Mode Selection

| Mode | Behavior | Use When |
|---|---|---|
| `FIFO` | VSync, always supported, lowest power | Default/mobile |
| `FIFO_RELAXED` | VSync, but tears if late | Desktop with rare glitches OK |
| `MAILBOX` | Triple buffer, lowest latency, high power | Desktop, latency-critical |
| `IMMEDIATE` | No VSync, tears | Benchmarks, tool windows |

**Mobile default: `FIFO` with `minImageCount=3`.**  
`MAILBOX` on mobile = wasted battery (renders frames that may not be shown).

## minImageCount

- Query `VkSurfaceCapabilitiesKHR::minImageCount` and `maxImageCount`.
- Use `max(minImageCount + 1, 3)` clamped to maxImageCount.
- More images = more GPU latency tolerance. 2 is minimum for non-FIFO; 3 for triple buffering.

## Resize Handling

`vkQueuePresentKHR` returns `VK_ERROR_OUT_OF_DATE_KHR` or `VK_SUBOPTIMAL_KHR` on resize.  
`vkAcquireNextImageKHR` can also return `OUT_OF_DATE_KHR`.

```
if result == OUT_OF_DATE or SUBOPTIMAL:
    wait_idle()
    destroy_swapchain_dependents()  // image views, framebuffers/depth buffer
    recreate_swapchain()
    recreate_dependents()
```

Never call `vkDestroySwapchainKHR` while images are in use. Wait idle first, or use old swapchain chaining (`oldSwapchain` field in `VkSwapchainCreateInfoKHR`).

## Image Acquisition

```c
uint32_t image_index;
VkResult result = vkAcquireNextImageKHR(device, swapchain, UINT64_MAX, acquire_semaphore, VK_NULL_HANDLE, &image_index);
// Handle OUT_OF_DATE here before proceeding
```

- Swapchain image starts in `VK_IMAGE_LAYOUT_UNDEFINED` after acquisition (content is garbage).
- Transition to `COLOR_ATTACHMENT_OPTIMAL` before writing (barrier in the render command buffer).
- Transition to `PRESENT_SRC_KHR` before presenting.

## Rules

- Never access swapchain images without waiting for acquire_semaphore.
- Always handle `VK_ERROR_OUT_OF_DATE_KHR` and `VK_SUBOPTIMAL_KHR` gracefully.
- Swapchain image count may differ from requested — use the actual count returned by `vkGetSwapchainImagesKHR`.
- Create one depth buffer per swapchain image (or one shared with per-frame sync) — not one total.
- Present must happen after the signal semaphore from the corresponding submit is reached.
