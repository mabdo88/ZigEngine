//! Cross-system access to the single AudioEngine/AudioClipCache instance,
//! mirroring physics/physics_shared.zig's module-level-var pattern. Kept out
//! of engine/ecs/systems/shared_state.zig deliberately: shared_state.zig is
//! pulled in by src/ecs_test.zig's GPU-free `test-ecs` build step, which has
//! no include path for miniaudio.h — anything that reaches audio_device.zig's
//! @import("miniaudioimport") must stay off that import chain.
const audio_device = @import("audio_device.zig");
const audio_cache = @import("audio_cache.zig");

/// Owned by audio_system.zig (create/destroy).
pub var engine: ?*audio_device.AudioEngine = null;
pub var clip_cache: ?*audio_cache.AudioClipCache = null;
