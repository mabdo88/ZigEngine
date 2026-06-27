const std = @import("std");
const audio_device = @import("audio_device.zig");
const ma = audio_device.ma;

/// Which mix bus a sound belongs to. There is no `.master` variant — the
/// engine itself *is* the master bus (controlled via `ma_engine_set_volume`
/// on AudioEngine, not a fourth group), since every `ma_sound_group` here
/// attaches directly to the engine's endpoint.
pub const AudioBus = enum { ui, sfx, music };

/// Owns the three named mix buses (UI/SFX/Music → Master). Initialized in
/// place (`self: *AudioMixer`), same reasoning as AudioEngine.init/clipLoad:
/// `ma_sound_group_init` attaches the group's node to the engine's graph,
/// which stores the literal address of the group's embedded `ma_sound` —
/// it must never move in memory after this call (see audio_device.zig's
/// AudioEngine.init doc comment for the full story on why).
pub const AudioMixer = struct {
    ui: ma.ma_sound_group,
    sfx: ma.ma_sound_group,
    music: ma.ma_sound_group,

    pub fn init(self: *AudioMixer, engine: *audio_device.AudioEngine) !void {
        self.ui = std.mem.zeroes(ma.ma_sound_group);
        if (ma.ma_sound_group_init(&engine.engine, 0, null, &self.ui) != ma.MA_SUCCESS) {
            return error.AudioMixerInitFailed;
        }
        errdefer ma.ma_sound_group_uninit(&self.ui);

        self.sfx = std.mem.zeroes(ma.ma_sound_group);
        if (ma.ma_sound_group_init(&engine.engine, 0, null, &self.sfx) != ma.MA_SUCCESS) {
            return error.AudioMixerInitFailed;
        }
        errdefer ma.ma_sound_group_uninit(&self.sfx);

        self.music = std.mem.zeroes(ma.ma_sound_group);
        if (ma.ma_sound_group_init(&engine.engine, 0, null, &self.music) != ma.MA_SUCCESS) {
            return error.AudioMixerInitFailed;
        }
    }

    pub fn deinit(self: *AudioMixer) void {
        ma.ma_sound_group_uninit(&self.music);
        ma.ma_sound_group_uninit(&self.sfx);
        ma.ma_sound_group_uninit(&self.ui);
    }

    pub fn group(self: *AudioMixer, bus: AudioBus) *ma.ma_sound_group {
        return switch (bus) {
            .ui => &self.ui,
            .sfx => &self.sfx,
            .music => &self.music,
        };
    }

    pub fn setVolume(self: *AudioMixer, bus: AudioBus, volume: f32) void {
        ma.ma_sound_group_set_volume(self.group(bus), volume);
    }

    pub fn getVolume(self: *AudioMixer, bus: AudioBus) f32 {
        return ma.ma_sound_group_get_volume(self.group(bus));
    }
};

test "AudioMixer routes independent volume per bus" {
    var engine: audio_device.AudioEngine = undefined;
    try engine.initHeadless();
    defer engine.deinit();

    var mixer: AudioMixer = undefined;
    try mixer.init(&engine);
    defer mixer.deinit();

    mixer.setVolume(.ui, 0.25);
    mixer.setVolume(.sfx, 0.5);
    mixer.setVolume(.music, 0.75);

    try std.testing.expectApproxEqAbs(@as(f32, 0.25), mixer.getVolume(.ui), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), mixer.getVolume(.sfx), 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), mixer.getVolume(.music), 1e-5);
}

test "AudioMixer master volume is the engine's own volume" {
    var engine: audio_device.AudioEngine = undefined;
    try engine.initHeadless();
    defer engine.deinit();

    try std.testing.expect(ma.ma_engine_set_volume(&engine.engine, 0.6) == ma.MA_SUCCESS);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), ma.ma_engine_get_volume(&engine.engine), 1e-5);
}
