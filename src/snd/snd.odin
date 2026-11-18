package snd

// Audio on miniaudio's high-level engine.
//
// This is the interim runtime from docs/AUDIO_PLAN.md §7: it replaces raylib's audio (which was
// miniaudio underneath anyway) so raylib can be removed, and keeps today's behaviour exactly.
// docs/AUDIO_PLAN.md stage A2 replaces it with the immersive-audio runtime behind this same API.

import "core:strings"
import ma "vendor:miniaudio"

// Handles stay small and copyable, as the game passes them by value. The miniaudio objects behind
// them are heap-allocated, because miniaudio keeps pointers to them.
Sound :: struct {
    handle: ^ma.sound,
}

Music :: struct {
    handle: ^ma.sound,
}

@(private) g_engine: ma.engine
@(private) g_ready:  bool

device_init :: proc() {
    if g_ready { return }
    if ma.engine_init(nil, &g_engine) == .SUCCESS {
        g_ready = true
    }
}

device_close :: proc() {
    if !g_ready { return }
    ma.engine_uninit(&g_engine)
    g_ready = false
}

device_ready :: proc() -> bool { return g_ready }

@(private)
_new_sound :: proc(path: cstring, flags: ma.sound_flags) -> ^ma.sound {
    if !g_ready { return nil }
    s := new(ma.sound)
    if ma.sound_init_from_file(&g_engine, path, flags, nil, nil, s) != .SUCCESS {
        free(s)
        return nil
    }
    return s
}

load_sound :: proc(path: cstring) -> Sound {
    return { handle = _new_sound(path, {}) }
}

// A second voice of an already loaded sound. miniaudio shares the decoded data between copies.
load_sound_alias :: proc(src: Sound) -> Sound {
    if !g_ready || src.handle == nil { return {} }
    s := new(ma.sound)
    if ma.sound_init_copy(&g_engine, src.handle, {}, nil, s) != .SUCCESS {
        free(s)
        return {}
    }
    return { handle = s }
}

unload_sound :: proc(s: Sound) {
    if s.handle == nil { return }
    ma.sound_uninit(s.handle)
    free(s.handle)
}

unload_sound_alias :: proc(s: Sound) { unload_sound(s) }

// Restarts from the beginning, like raylib's PlaySound.
play_sound :: proc(s: Sound) {
    if s.handle == nil { return }
    ma.sound_seek_to_pcm_frame(s.handle, 0)
    ma.sound_start(s.handle)
}

stop_sound :: proc(s: Sound) {
    if s.handle == nil { return }
    ma.sound_stop(s.handle)
    ma.sound_seek_to_pcm_frame(s.handle, 0)
}

sound_playing :: proc(s: Sound) -> bool {
    return s.handle != nil && bool(ma.sound_is_playing(s.handle))
}

sound_set_volume :: proc(s: Sound, v: f32) { if s.handle != nil { ma.sound_set_volume(s.handle, v) } }
sound_set_pitch  :: proc(s: Sound, v: f32) { if s.handle != nil { ma.sound_set_pitch(s.handle, v) } }

// raylib took 0..1 with 0.5 centred; miniaudio takes -1..1.
sound_set_pan :: proc(s: Sound, v: f32) {
    if s.handle == nil { return }
    ma.sound_set_pan(s.handle, clamp(v * 2 - 1, -1, 1))
}

// Music streams from disk instead of being decoded up front.
load_music :: proc(path: cstring) -> Music {
    return { handle = _new_sound(path, { .STREAM }) }
}

unload_music :: proc(m: Music) {
    if m.handle == nil { return }
    ma.sound_uninit(m.handle)
    free(m.handle)
}

play_music :: proc(m: Music) {
    if m.handle == nil { return }
    ma.sound_seek_to_pcm_frame(m.handle, 0)
    ma.sound_start(m.handle)
}

stop_music :: proc(m: Music) {
    if m.handle == nil { return }
    ma.sound_stop(m.handle)
    ma.sound_seek_to_pcm_frame(m.handle, 0)
}

// raylib needed a per-frame pump; miniaudio streams on its own thread.
update_music :: proc(m: Music) {}

music_playing :: proc(m: Music) -> bool {
    return m.handle != nil && bool(ma.sound_is_playing(m.handle))
}

// True when the stream loaded.
music_valid :: proc(m: Music) -> bool { return m.handle != nil }

// True when the sound loaded.
sound_valid :: proc(s: Sound) -> bool { return s.handle != nil }

music_set_volume :: proc(m: Music, v: f32) { if m.handle != nil { ma.sound_set_volume(m.handle, v) } }

// Music loops; the crossfade logic in audio.odin expects it to keep playing.
music_set_looping :: proc(m: Music, looping: bool) {
    if m.handle != nil { ma.sound_set_looping(m.handle, b32(looping)) }
}

_ :: strings
