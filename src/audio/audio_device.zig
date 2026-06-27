//! Thin wrapper around miniaudio's ma_engine/ma_sound, mirroring the
//! Jolt wrapper pattern (src/physics/jolt_wrapper.zig): Zig code only
//! ever touches the translate-c'd C struct through these functions, never
//! ma_* directly outside this file.
const std = @import("std");
pub const ma = @import("miniaudioimport");

pub const AudioEngine = struct {
    engine: ma.ma_engine,

    /// init()/initHeadless() take `self: *AudioEngine` and initialize in
    /// place rather than returning AudioEngine by value. This matters:
    /// ma_engine_init wires up internal self-referential state inside the
    /// embedded ma_engine/ma_node_graph (observed directly — after
    /// AudioEngine.init() used to construct a local value and `return` it,
    /// ma_engine_get_channels read back as 0 once that returned value had
    /// been copied into its caller's final storage, even though the engine
    /// reported the correct channel count immediately after ma_engine_init
    /// returned, before the copy). miniaudio's own C API never returns these
    /// structs by value for the same reason — callers always pass a stable
    /// `pEngine` pointer in. Returning a fresh Zig value and letting the
    /// caller copy it elsewhere recreates exactly the bug class the C API's
    /// pointer-out convention exists to avoid.
    ///
    /// Must zero the struct before passing it to ma_engine_init: miniaudio's
    /// embedded node-graph nodes (ma_engine.nodeGraph.{base,endpoint}) are
    /// stack/struct-resident rather than heap-allocated, and their internal
    /// spinlocks are only explicitly zeroed for nodes ma_node_init allocates
    /// through ma_malloc — it relies on the caller having zeroed the rest.
    /// Leaving this as `undefined` works by accident in plain C (a
    /// freshly-touched stack page is often zero) but Zig's debug builds
    /// poison `undefined` memory with 0xAA, which corrupts those spinlocks
    /// and makes ma_engine_uninit's node teardown spin forever.
    pub fn init(self: *AudioEngine) !void {
        var config = ma.ma_engine_config_init();
        config.channels = 2;
        config.sampleRate = 48000;
        self.engine = std.mem.zeroes(ma.ma_engine);
        const result = ma.ma_engine_init(&config, &self.engine);
        if (result != ma.MA_SUCCESS) return error.AudioEngineInitFailed;
    }

    /// Mixes without opening a real playback device — used by unit tests
    /// (and any offline/headless run) so init can't block or fail on a
    /// machine with no audio hardware, e.g. a CI runner or sandbox.
    pub fn initHeadless(self: *AudioEngine) !void {
        var config = ma.ma_engine_config_init();
        config.noDevice = ma.MA_TRUE;
        config.channels = 2;
        config.sampleRate = 48000;
        self.engine = std.mem.zeroes(ma.ma_engine);
        const result = ma.ma_engine_init(&config, &self.engine);
        if (result != ma.MA_SUCCESS) return error.AudioEngineInitFailed;
    }

    pub fn deinit(self: *AudioEngine) void {
        ma.ma_engine_uninit(&self.engine);
    }
};

pub const AudioClip = struct {
    sound: ma.ma_sound,
};

/// path must be a valid path for the lifetime of this call only — miniaudio
/// copies/opens the file synchronously here, it doesn't retain the pointer.
///
/// Takes `out: *AudioClip` and initializes in place rather than returning
/// AudioClip by value — same reasoning as AudioEngine.init: attaching a
/// sound to the engine's node graph (ma_sound_init_from_file does this
/// internally via ma_node_attach_output_bus) stores the literal address of
/// the sound's embedded node in the graph's linked list, so the AudioClip
/// must never move in memory again after this call. Callers (see
/// audio_cache.zig's AudioClipCache.register) must heap-allocate the
/// AudioClip's storage themselves before calling this, for the same reason —
/// an ArrayList(AudioClip) would silently corrupt every previously-loaded
/// clip's node-graph linkage the next time it grows and moves its elements.
pub fn clipLoad(engine: *AudioEngine, path: [:0]const u8, out: *AudioClip) !void {
    // Zeroed for the same reason as AudioEngine.engine above — ma_sound also
    // embeds node-graph state that needs pre-zeroed memory.
    out.sound = std.mem.zeroes(ma.ma_sound);
    // MA_SOUND_FLAG_DECODE forces a full synchronous decode up front rather
    // than going through the resource manager's streaming path — miniaudio's
    // own documented recommendation for short SFX like ours, instead of
    // paying streaming overhead for clips that are tiny anyway.
    const result = ma.ma_sound_init_from_file(&engine.engine, path.ptr, ma.MA_SOUND_FLAG_DECODE, null, null, &out.sound);
    if (result != ma.MA_SUCCESS) return error.AudioClipLoadFailed;
}

pub fn clipUnload(clip: *AudioClip) void {
    ma.ma_sound_uninit(&clip.sound);
}

/// Restarts playback from the beginning, matching the spec's "play" verb
/// rather than miniaudio's resume-in-place ma_sound_start semantics.
pub fn clipPlay(clip: *AudioClip) !void {
    _ = ma.ma_sound_seek_to_pcm_frame(&clip.sound, 0);
    const result = ma.ma_sound_start(&clip.sound);
    if (result != ma.MA_SUCCESS) return error.AudioClipPlayFailed;
}

pub fn clipIsPlaying(clip: *AudioClip) bool {
    return ma.ma_sound_is_playing(&clip.sound) != 0;
}

test "AudioEngine init/deinit succeeds" {
    var engine: AudioEngine = undefined;
    try engine.initHeadless();
    defer engine.deinit();
}
