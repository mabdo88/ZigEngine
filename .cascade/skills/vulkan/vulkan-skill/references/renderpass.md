# Vulkan Render Pass & Dynamic Rendering Reference

## Dynamic Rendering (Prefer for New Code — Core in 1.3)

```c
VkRenderingAttachmentInfo color_att = {
    .sType       = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
    .imageView   = swapchain_views[image_index],
    .imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    .loadOp      = VK_ATTACHMENT_LOAD_OP_CLEAR,
    .storeOp     = VK_ATTACHMENT_STORE_OP_STORE,
    .clearValue  = { .color = { 0.0f, 0.0f, 0.0f, 1.0f } },
};
VkRenderingAttachmentInfo depth_att = {
    .sType       = VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
    .imageView   = depth_view,
    .imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
    .loadOp      = VK_ATTACHMENT_LOAD_OP_CLEAR,
    .storeOp     = VK_ATTACHMENT_STORE_OP_DONT_CARE,  // don't persist depth
    .clearValue  = { .depthStencil = { 1.0f, 0 } },
};
VkRenderingInfo rendering_info = {
    .sType                = VK_STRUCTURE_TYPE_RENDERING_INFO,
    .renderArea           = { {0,0}, extent },
    .layerCount           = 1,
    .colorAttachmentCount = 1,
    .pColorAttachments    = &color_att,
    .pDepthAttachment     = &depth_att,
};
// Image must be in COLOR_ATTACHMENT_OPTIMAL before this call (barrier needed)
vkCmdBeginRendering(cmd, &rendering_info);
// ... draw calls ...
vkCmdEndRendering(cmd);
// Transition to PRESENT_SRC_KHR after (barrier needed for swapchain image)
```

## Load/Store Op Rules

| Situation | loadOp | storeOp |
|---|---|---|
| Clear before drawing | CLEAR | STORE |
| Don't need prior content (first use, will be fully covered) | DONT_CARE | STORE |
| Depth/stencil used only within this pass | CLEAR | DONT_CARE |
| Reading back result after pass | any | STORE |
| MSAA color (resolved, original discarded) | CLEAR | DONT_CARE |

- **LOAD_OP_CLEAR is faster than vkCmdClearAttachments** — prefer it.
- **STORE_OP_DONT_CARE** on depth saves bandwidth (especially on tile-based mobile GPUs).
- Never use LOAD_OP_LOAD if you don't actually need the prior contents — wastes memory bandwidth.

## Classic Render Pass — Subpass Dependencies

Always declare explicit external subpass dependencies. Implicit ones are not reliable cross-vendor.

```c
VkSubpassDependency deps[2] = {
    // External → subpass 0: wait for prior frame's color output before writing
    {
        .srcSubpass    = VK_SUBPASS_EXTERNAL,
        .dstSubpass    = 0,
        .srcStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = VK_ACCESS_NONE,
        .dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
    },
    // Subpass 0 → external: color write done before present
    {
        .srcSubpass    = 0,
        .dstSubpass    = VK_SUBPASS_EXTERNAL,
        .srcStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask  = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
        .srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dstAccessMask = VK_ACCESS_NONE,
    },
};
```

## MSAA

- MSAA attachment: `STORE_OP_DONT_CARE`, resolve attachment: `STORE_OP_STORE`.
- Use `VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT` for MSAA color/depth on mobile (never written to system memory).
- Use `VK_RESOLVE_MODE_AVERAGE_BIT` for color resolve, `VK_RESOLVE_MODE_MIN_BIT` or `MAX` for depth.

## Rules

- LOAD_OP_CLEAR before a renderpass, not vkCmdClearColorImage inside it (unless outside pass).
- For deferred rendering: use subpasses (classic renderpass) or multiple dynamic rendering passes with proper barriers between them.
- `VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL` (sync2 alias) is cleaner than separate COLOR/DEPTH_ATTACHMENT_OPTIMAL in modern code.
- `VK_IMAGE_LAYOUT_READ_ONLY_OPTIMAL` (sync2) replaces SHADER_READ_ONLY_OPTIMAL + DEPTH_STENCIL_READ_ONLY_OPTIMAL.
