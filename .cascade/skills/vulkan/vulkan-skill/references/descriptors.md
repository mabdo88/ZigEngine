# Vulkan Descriptors & Bindless Reference

## Descriptor Set Layout Creation Order

```
vkCreateDescriptorSetLayout  (before pipeline layout)
    ↓
vkCreatePipelineLayout       (needs layout handles)
    ↓
vkCreateGraphicsPipeline     (needs pipeline layout)
    ↓
vkCreateDescriptorPool
    ↓
vkAllocateDescriptorSets
    ↓
vkUpdateDescriptorSets
```

## Bindless Setup (descriptor_indexing / VK_EXT_descriptor_indexing, core 1.2)

### Layout
```c
VkDescriptorBindingFlags flags =
    VK_DESCRIPTOR_BINDING_PARTIALLY_BOUND_BIT |
    VK_DESCRIPTOR_BINDING_UPDATE_AFTER_BIND_BIT;

VkDescriptorSetLayoutBindingFlagsCreateInfo flags_info = {
    .sType         = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
    .bindingCount  = 1,
    .pBindingFlags = &flags,
};
VkDescriptorSetLayoutBinding binding = {
    .binding         = 0,
    .descriptorType  = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    .descriptorCount = 1024,  // bindless heap size
    .stageFlags      = VK_SHADER_STAGE_FRAGMENT_BIT,
};
VkDescriptorSetLayoutCreateInfo layout_info = {
    .sType        = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    .pNext        = &flags_info,
    .flags        = VK_DESCRIPTOR_SET_LAYOUT_CREATE_UPDATE_AFTER_BIND_POOL_BIT,
    .bindingCount = 1,
    .pBindings    = &binding,
};
```

### Pool
```c
VkDescriptorPoolCreateInfo pool_info = {
    .flags   = VK_DESCRIPTOR_POOL_CREATE_UPDATE_AFTER_BIND_BIT,
    .maxSets = 1,
    ...
};
```

### Shader side (GLSL)
```glsl
layout(set = 1, binding = 0) uniform sampler2D textures[];
// index comes from push constant or per-draw data
vec4 color = texture(textures[push.tex_index], uv);
```

### Writing a slot
```c
VkDescriptorImageInfo img_info = {
    .sampler     = sampler,
    .imageView   = view,
    .imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
};
VkWriteDescriptorSet write = {
    .dstSet          = bindless_set,
    .dstBinding      = 0,
    .dstArrayElement = slot_index,   // index into bindless heap
    .descriptorCount = 1,
    .descriptorType  = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
    .pImageInfo      = &img_info,
};
vkUpdateDescriptorSets(device, 1, &write, 0, NULL);
```

## Push Constants

- Fastest per-draw data path. No descriptor overhead.
- `maxPushConstantsSize` is guaranteed ≥128 bytes by spec; most hardware supports 256.
- Declare in pipeline layout:
```c
VkPushConstantRange range = {
    .stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
    .offset     = 0,
    .size       = sizeof(PushConstants),  // must match shader + range exactly
};
```
- Update per draw: `vkCmdPushConstants(cmd, layout, stages, 0, sizeof(PushConstants), &push_data)`
- **Push constant size mismatch between pipeline layout and shader is a validation error / crash.**
- Common pattern: `{ mat4 model; u32 tex_index; }` or `{ u32 entity_id; u32 tex_index; vec2 uv_offset; }`

## Descriptor Pool Per Frame

```c
// One pool per frame-in-flight — reset after fence signals
vkResetDescriptorPool(device, frame_pools[current_frame], 0);
// Re-allocate fresh sets for the new frame — no per-set free overhead
```

## Rules

- Do NOT free individual descriptor sets unless pool was created with `FREE_DESCRIPTOR_SET_BIT` (slow, fragmented).
- Do NOT update a descriptor set that is referenced by an in-flight command buffer (without `UPDATE_AFTER_BIND`).
- Gaps between binding numbers waste GPU memory in the set — keep bindings dense.
- Minimize bound descriptor sets per pipeline layout (fewer = faster bind cost).
- Use dynamic uniform buffers (`VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC`) for per-draw offsets into a shared UBO instead of one descriptor set per draw.
- Push descriptors (`VK_KHR_push_descriptor`) are an alternative to per-frame pool reset for small descriptor counts.
