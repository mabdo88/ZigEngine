# Graph Report - c:\zigEngine\ZigEngine  (2026-06-23)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 3502 nodes · 5956 edges · 72 communities (58 shown, 14 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 5 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `d2abc5af`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_GLFW Window Management|GLFW Window Management]]
- [[_COMMUNITY_GLFW Context Management|GLFW Context Management]]
- [[_COMMUNITY_cgltf Accessor Utilities|cgltf Accessor Utilities]]
- [[_COMMUNITY_VMA Block Management|VMA Block Management]]
- [[_COMMUNITY_stb_image BMP Parsing|stb_image BMP Parsing]]
- [[_COMMUNITY_Vulkan Memory Allocator API|Vulkan Memory Allocator API]]
- [[_COMMUNITY_stb_image Core Utilities|stb_image Core Utilities]]
- [[_COMMUNITY_VMA Memory Allocation|VMA Memory Allocation]]
- [[_COMMUNITY_cgltf Buffer and Camera|cgltf Buffer and Camera]]
- [[_COMMUNITY_cgltf JSON Parsing|cgltf JSON Parsing]]
- [[_COMMUNITY_cgltf Animation and Accessors|cgltf Animation and Accessors]]
- [[_COMMUNITY_cgltf Material Properties|cgltf Material Properties]]
- [[_COMMUNITY_stb_image JPEG Decoding|stb_image JPEG Decoding]]
- [[_COMMUNITY_Vulkan Resource Binding|Vulkan Resource Binding]]
- [[_COMMUNITY_Vulkan Win32 Interop|Vulkan Win32 Interop]]
- [[_COMMUNITY_VMA Statistics Formatting|VMA Statistics Formatting]]
- [[_COMMUNITY_VMA Pool Management|VMA Pool Management]]
- [[_COMMUNITY_VMA Validation and Callbacks|VMA Validation and Callbacks]]
- [[_COMMUNITY_stb_image Image Processing|stb_image Image Processing]]
- [[_COMMUNITY_stb_image Zlib Compression|stb_image Zlib Compression]]
- [[_COMMUNITY_VMA Statistics Calculation|VMA Statistics Calculation]]
- [[_COMMUNITY_ECS Entity Registry|ECS Entity Registry]]
- [[_COMMUNITY_Windowing System API|Windowing System API]]
- [[_COMMUNITY_OS Window Creation|OS Window Creation]]
- [[_COMMUNITY_ECS Scene Components|ECS Scene Components]]
- [[_COMMUNITY_VMA Virtual Blocks|VMA Virtual Blocks]]
- [[_COMMUNITY_ECS System Manager|ECS System Manager]]
- [[_COMMUNITY_Mesh Rendering System|Mesh Rendering System]]
- [[_COMMUNITY_Vulkan GPU Uploads|Vulkan GPU Uploads]]
- [[_COMMUNITY_Vulkan Context and Shaders|Vulkan Context and Shaders]]
- [[_COMMUNITY_Vulkan System Integration|Vulkan System Integration]]
- [[_COMMUNITY_Render System Lifecycle|Render System Lifecycle]]
- [[_COMMUNITY_glTF Mesh Loading|glTF Mesh Loading]]
- [[_COMMUNITY_System Interface Definitions|System Interface Definitions]]
- [[_COMMUNITY_Linear Algebra Math|Linear Algebra Math]]
- [[_COMMUNITY_Event Payload Definitions|Event Payload Definitions]]
- [[_COMMUNITY_Vulkan World Management|Vulkan World Management]]
- [[_COMMUNITY_cgltf Sparse Accessors|cgltf Sparse Accessors]]
- [[_COMMUNITY_cgltf Primitive Attributes|cgltf Primitive Attributes]]
- [[_COMMUNITY_Vulkan Swapchain Management|Vulkan Swapchain Management]]
- [[_COMMUNITY_Mesh Data Caching|Mesh Data Caching]]
- [[_COMMUNITY_Vulkan Device Initialization|Vulkan Device Initialization]]
- [[_COMMUNITY_OS Event Polling|OS Event Polling]]
- [[_COMMUNITY_Vulkan Material Management|Vulkan Material Management]]
- [[_COMMUNITY_Scene Management System|Scene Management System]]
- [[_COMMUNITY_Event Bus Pattern|Event Bus Pattern]]
- [[_COMMUNITY_stb_image SIMD and JPEG|stb_image SIMD and JPEG]]
- [[_COMMUNITY_Input Handling System|Input Handling System]]
- [[_COMMUNITY_VMA Binary Search|VMA Binary Search]]
- [[_COMMUNITY_Scene Asset Loading|Scene Asset Loading]]
- [[_COMMUNITY_Engine Configuration|Engine Configuration]]
- [[_COMMUNITY_Engine Entry Point|Engine Entry Point]]
- [[_COMMUNITY_Window Destruction|Window Destruction]]
- [[_COMMUNITY_Camera Update System|Camera Update System]]
- [[_COMMUNITY_Movement Update System|Movement Update System]]
- [[_COMMUNITY_ECS Component Storage|ECS Component Storage]]
- [[_COMMUNITY_ECS Entity Definition|ECS Entity Definition]]
- [[_COMMUNITY_Windows Message Loop|Windows Message Loop]]
- [[_COMMUNITY_High Resolution Timing|High Resolution Timing]]
- [[_COMMUNITY_Vulkan Surface Creation|Vulkan Surface Creation]]
- [[_COMMUNITY_Water Texture Asset|Water Texture Asset]]

## God Nodes (most connected - your core abstractions)
1. `jsmntok_t` - 77 edges
2. `VmaAllocator` - 77 edges
3. `stbi__context` - 70 edges
4. `VkDeviceSize` - 66 edges
5. `cgltf_options` - 65 edges
6. `VMA_CALL_POST` - 65 edges
7. `VmaAllocation` - 53 edges
8. `cgltf_size` - 47 edges
9. `cgltf_skip_json()` - 45 edges
10. `stbi_uc` - 44 edges

## Surprising Connections (you probably didn't know these)
- `glTF Mesh Loader` --references--> `Duck Base Color Texture`  [INFERRED]
  src/resources/meshLoader.zig → assets/duck/textures/blinn3-fx_baseColor.png
- `glTF Mesh Loader` --references--> `House Concrete Texture`  [INFERRED]
  src/resources/meshLoader.zig → assets/House/hillside_retreat__concrete_house_concept/textures/Concrete_baseColor.jpeg
- `SystemRunner` --calls--> `RenderSystem`  [EXTRACTED]
  src/engine/ecs/systems/system.zig → src/engine/ecs/systems/render_system.zig
- `SystemRunner` --calls--> `SceneSystem`  [EXTRACTED]
  src/engine/ecs/systems/system.zig → src/engine/ecs/systems/scene_system.zig
- `main()` --calls--> `Engine()`  [INFERRED]
  src/main.zig → src/engine/engine.zig

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **ECS System Pipeline** — input_system, scene_system, movement_system, camera_system, render_system [EXTRACTED 1.00]
- **Vulkan Renderer Backend** — vulkan_context, vulkan_device, vulkan_swapchain, vulkan_pipeline, vulkan_upload, vulkan_material [EXTRACTED 1.00]

## Communities (72 total, 14 thin omitted)

### Community 0 - "GLFW Window Management"
Cohesion: 0.00
Nodes (1277): max_align_t, MSG, struct_GLFWallocator, struct_GLFWgamepadstate, struct_GLFWgammaramp, struct_GLFWimage, struct_GLFWvidmode, struct_StdVideoAV1CDEF (+1269 more)

### Community 1 - "GLFW Context Management"
Cohesion: 0.01
Nodes (6): max_align_t, struct_GLFWallocator, struct_GLFWgamepadstate, struct_GLFWgammaramp, struct_GLFWimage, struct_GLFWvidmode

### Community 2 - "cgltf Accessor Utilities"
Cohesion: 0.02
Nodes (51): max_align_t, struct_cgltf_accessor, struct_cgltf_accessor_sparse, struct_cgltf_animation, struct_cgltf_animation_channel, struct_cgltf_animation_sampler, struct_cgltf_anisotropy, struct_cgltf_asset (+43 more)

### Community 3 - "VMA Block Management"
Cohesion: 0.06
Nodes (42): class, ItemType, AccessNext(), AccessPrev(), AllocatePage(), Back(), BlockAllocUnmap(), CalcMaxBlockSize() (+34 more)

### Community 4 - "stb_image BMP Parsing"
Cohesion: 0.10
Nodes (70): stbi__at_eof(), stbi__bitcount(), stbi__bmp_info(), stbi__bmp_load(), stbi__bmp_parse_header(), stbi__bmp_set_mask_defaults(), stbi__bmp_test(), stbi__bmp_test_raw() (+62 more)

### Community 5 - "Vulkan Memory Allocator API"
Cohesion: 0.08
Nodes (62): VkMemoryPropertyFlags, VkPhysicalDeviceMemoryProperties, VkPhysicalDeviceProperties, VMA_CACHE_OPERATION, VMA_CALL_POST, CheckCorruption(), CheckPoolCorruption(), CopyAllocationToMemory() (+54 more)

### Community 6 - "stb_image Core Utilities"
Cohesion: 0.06
Nodes (79): FILE, resample_row_1(), stbi__clamp(), stbi__convert_8_to_16(), stbi_convert_iphone_png_to_rgb(), stbi_convert_iphone_png_to_rgb_thread(), stbi_convert_wchar_to_utf8(), stbi__do_zlib() (+71 more)

### Community 7 - "VMA Memory Allocation"
Cohesion: 0.08
Nodes (62): Block, RegionInfo, StateBalanced, VkDeviceMemory, VkDeviceSize, VkMappedMemoryRange, Alloc(), allocate() (+54 more)

### Community 8 - "cgltf Buffer and Camera"
Cohesion: 0.07
Nodes (54): cgltf_buffer, cgltf_camera, cgltf_buffer_index(), cgltf_camera_index(), cgltf_combine_paths(), cgltf_copy_extras_json(), cgltf_decode_string(), cgltf_decode_uri() (+46 more)

### Community 9 - "cgltf JSON Parsing"
Cohesion: 0.18
Nodes (50): cgltf_asset, cgltf_attribute, cgltf_calloc(), cgltf_json_to_int(), cgltf_json_to_primitive_type(), cgltf_parse_json_accessors(), cgltf_parse_json_animation(), cgltf_parse_json_animation_channel() (+42 more)

### Community 10 - "cgltf Animation and Accessors"
Cohesion: 0.15
Nodes (35): cgltf_accessor, cgltf_animation, cgltf_animation_channel, cgltf_animation_sampler, cgltf_bool, cgltf_buffer_view, cgltf_accessor_index(), cgltf_accessor_read_float() (+27 more)

### Community 11 - "cgltf Material Properties"
Cohesion: 0.15
Nodes (39): cgltf_anisotropy, cgltf_fill_float_array(), cgltf_json_strcmp(), cgltf_json_to_float(), cgltf_parse_json_anisotropy(), cgltf_parse_json_clearcoat(), cgltf_parse_json_diffuse_transmission(), cgltf_parse_json_dispersion() (+31 more)

### Community 12 - "stb_image JPEG Decoding"
Cohesion: 0.18
Nodes (28): stbi__addints_valid(), stbi__bitreverse16(), stbi__build_fast_ac(), stbi__build_huffman(), stbi__decode_jpeg_header(), stbi__decode_jpeg_image(), stbi__extend_receive(), stbi__get_marker() (+20 more)

### Community 13 - "Vulkan Resource Binding"
Cohesion: 0.14
Nodes (42): VkBuffer, VkBufferCreateInfo, VkImage, VkImageCreateInfo, VkMemoryRequirements, AllocateMemory(), AllocateMemoryOfType(), BindBufferMemory() (+34 more)

### Community 14 - "Vulkan Win32 Interop"
Cohesion: 0.10
Nodes (28): FindT, HANDLE, MainT, NewT, PFN_vkGetMemoryWin32HandleKHR, VkExternalMemoryHandleTypeFlagsKHR, VkMemoryAllocateInfo, VkResult (+20 more)

### Community 15 - "VMA Statistics Formatting"
Cohesion: 0.20
Nodes (32): VkBool32, Add(), AddNumber(), AddPointer(), BeginArray(), BeginObject(), BeginString(), BeginValue() (+24 more)

### Community 16 - "VMA Pool Management"
Cohesion: 0.12
Nodes (29): BaseType, iterator, AllocateDedicatedMemory(), begin(), clear(), Contains(), data(), DebugLogAllAllocations() (+21 more)

### Community 18 - "VMA Validation and Callbacks"
Cohesion: 0.10
Nodes (27): AllocatorT, AtomicT, explicit, T, ValidationContext, VkAllocationCallbacks, deallocate(), FinishValidation() (+19 more)

### Community 19 - "stb_image Image Processing"
Cohesion: 0.12
Nodes (28): load_jpeg_image(), stbi__addsizes_valid(), stbi__blinn_8x8(), stbi__cleanup_jpeg(), stbi__compute_transparency(), stbi__compute_transparency16(), stbi__compute_y(), stbi__create_png_alpha_expand8() (+20 more)

### Community 20 - "stb_image Zlib Compression"
Cohesion: 0.34
Nodes (17): stbi__bit_reverse(), stbi__compute_huffman_codes(), stbi__err(), stbi__fill_bits(), stbi__parse_huffman_block(), stbi__parse_uncompressed_block(), stbi__parse_zlib(), stbi__parse_zlib_header() (+9 more)

### Community 21 - "VMA Statistics Calculation"
Cohesion: 0.20
Nodes (20): AddDetailedStatistics(), AddStatistics(), CalculateDetailedStatistics(), CalculatePoolStatistics(), CalculateStatistics(), GetNext(), GetPoolStatistics(), GetStatistics() (+12 more)

### Community 23 - "Windowing System API"
Cohesion: 0.11
Nodes (3): Key, Size, Window

### Community 24 - "OS Window Creation"
Cohesion: 0.11
Nodes (18): CreateWindowExW(), GetModuleHandleW(), LoadCursorW(), RegisterClassExW(), vkCreateWindow(), XBlackPixel(), XCreateSimpleWindow(), XDefaultRootWindow() (+10 more)

### Community 25 - "ECS Scene Components"
Cohesion: 0.12
Nodes (12): CameraComponent, CameraMatricesComponent, MeshComponent, SceneActiveTag, SceneComponent, SceneOwnedComponent, ScenePendingTag, TextureComponent (+4 more)

### Community 26 - "VMA Virtual Blocks"
Cohesion: 0.19
Nodes (14): SetAllocationUserData(), vmaClearVirtualBlock(), vmaCreateVirtualBlock(), vmaDestroyVirtualBlock(), vmaGetVirtualAllocationInfo(), vmaIsVirtualBlockEmpty(), vmaSetVirtualAllocationUserData(), vmaVirtualAllocate() (+6 more)

### Community 27 - "ECS System Manager"
Cohesion: 0.22
Nodes (5): CameraSystem, ECS Registry, InputSystem, MovementSystem, SystemRunner

### Community 28 - "Mesh Rendering System"
Cohesion: 0.21
Nodes (3): GpuMesh, RenderSystem, uploadMesh()

### Community 29 - "Vulkan GPU Uploads"
Cohesion: 0.29
Nodes (6): beginOneTimeCommandBuffer(), check(), createStagingBuffer(), StagingBuffer, submitAndWait(), UploadBatch

### Community 30 - "Vulkan Context and Shaders"
Cohesion: 0.17
Nodes (11): FrameUBO, PushConstants, ShaderData, ShaderDataBuffer, TextureSlot, Vertex, VulkanContext, Vulkan Device (+3 more)

### Community 33 - "glTF Mesh Loading"
Cohesion: 0.25
Nodes (7): GltfScene, loadgltf(), MaterialData, MeshData, NodeView, nodeWorldTransform(), ScenePrimitive

### Community 34 - "System Interface Definitions"
Cohesion: 0.18
Nodes (4): DeinitTracker, InitTracker, OrderTracker, System

### Community 35 - "Linear Algebra Math"
Cohesion: 0.27
Nodes (5): CameraMatrices, cross(), dot(), lookAt(), normalize()

### Community 36 - "Event Payload Definitions"
Cohesion: 0.22
Nodes (7): Counter, EventPayload, EventType, Handler, RenderSystem, Vulkan Material, Vulkan Upload

### Community 38 - "cgltf Sparse Accessors"
Cohesion: 0.32
Nodes (8): cgltf_accessor_sparse, cgltf_json_to_bool(), cgltf_json_to_component_type(), cgltf_json_to_size(), cgltf_parse_json_accessor(), cgltf_parse_json_accessor_sparse(), cgltf_parse_json_meshopt_compression(), cgltf_meshopt_compression

### Community 39 - "cgltf Primitive Attributes"
Cohesion: 0.25
Nodes (8): cgltf_attribute_type, cgltf_find_accessor(), cgltf_parse_attribute_type(), cgltf_parse_json_material_mapping_data(), cgltf_parse_json_material_mappings(), cgltf_int, cgltf_material_mapping, cgltf_primitive

### Community 41 - "Vulkan Swapchain Management"
Cohesion: 0.46
Nodes (5): check(), createDepthImage(), createSwapchain(), pickSurfaceFormat(), recreateSwapchain()

### Community 44 - "OS Event Polling"
Cohesion: 0.33
Nodes (6): DispatchMessageW(), PeekMessageW(), TranslateMessage(), vkPollEvents(), XNextEvent(), XPending()

### Community 45 - "Vulkan Material Management"
Cohesion: 0.53
Nodes (4): check(), createDefaultTexture(), uploadTexture(), uploadTextureBatched()

### Community 48 - "stb_image SIMD and JPEG"
Cohesion: 0.19
Nodes (13): stbi__compute_y_16(), stbi__convert_16_to_8(), stbi__convert_format16(), stbi__cpuid3(), stbi__jpeg_load(), stbi__jpeg_test(), stbi__ldr_to_hdr(), stbi__malloc() (+5 more)

### Community 49 - "Input Handling System"
Cohesion: 0.60
Nodes (3): InputSystemState, requestScene(), update()

### Community 50 - "VMA Binary Search"
Cohesion: 0.50
Nodes (4): CmpLess, IterT, KeyT, VmaBinaryFindFirstNotLess()

### Community 51 - "Scene Asset Loading"
Cohesion: 0.50
Nodes (4): Duck Base Color Texture, House Concrete Texture, glTF Mesh Loader, SceneSystem

### Community 52 - "Engine Configuration"
Cohesion: 0.50
Nodes (3): CameraConfig, Config, SceneConfig

### Community 54 - "Window Destruction"
Cohesion: 0.50
Nodes (4): DestroyWindow(), vkDestroyWindow(), XCloseDisplay(), XDestroyWindow()

### Community 59 - "Windows Message Loop"
Cohesion: 0.67
Nodes (3): DefWindowProcW(), PostQuitMessage(), wndProc()

### Community 60 - "High Resolution Timing"
Cohesion: 0.67
Nodes (3): QueryPerformanceCounter(), QueryPerformanceFrequency(), vkGetTime()

### Community 61 - "Vulkan Surface Creation"
Cohesion: 0.67
Nodes (3): vkCreateWin32SurfaceKHR(), vkCreateWindowSurface(), vkCreateXlibSurfaceKHR()

## Knowledge Gaps
- **1424 isolated node(s):** `cgltf_ssize`, `cgltf_int`, `cgltf_attribute`, `cgltf_draco_mesh_compression`, `cgltf_mesh_gpu_instancing` (+1419 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `jsmntok_t` connect `cgltf JSON Parsing` to `cgltf Buffer and Camera`, `cgltf Material Properties`, `cgltf Sparse Accessors`, `cgltf Primitive Attributes`?**
  _High betweenness centrality (0.000) - this node is a cross-community bridge._
- **Why does `stbi__context` connect `stb_image BMP Parsing` to `stb_image SIMD and JPEG`, `stb_image Image Processing`, `stb_image JPEG Decoding`, `stb_image Core Utilities`?**
  _High betweenness centrality (0.000) - this node is a cross-community bridge._
- **Why does `cgltf_parse_json_extras()` connect `cgltf JSON Parsing` to `cgltf Buffer and Camera`, `cgltf Material Properties`, `cgltf Sparse Accessors`, `cgltf Primitive Attributes`?**
  _High betweenness centrality (0.000) - this node is a cross-community bridge._
- **What connects `cgltf_ssize`, `cgltf_int`, `cgltf_attribute` to the rest of the system?**
  _1424 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `GLFW Window Management` be split into smaller, more focused modules?**
  _Cohesion score 0.0009319664492078285 - nodes in this community are weakly interconnected._
- **Should `GLFW Context Management` be split into smaller, more focused modules?**
  _Cohesion score 0.014492753623188406 - nodes in this community are weakly interconnected._
- **Should `cgltf Accessor Utilities` be split into smaller, more focused modules?**
  _Cohesion score 0.02 - nodes in this community are weakly interconnected._