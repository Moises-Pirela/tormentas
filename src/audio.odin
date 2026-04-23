package main

import rl   "vendor:raylib"
import      "core:fmt"
import      "core:math"

g_vol_master:   f32 = 1.0
g_vol_sfx:      f32 = 1.0
g_vol_music:    f32 = 0.7
g_vol_ambience: f32 = 0.5
g_vol_voice:    f32 = 1.0


g_listener_pos: [3]f32

SPATIAL_FALLOFF_RADIUS :: f32(700)

PAN_HALF_WIDTH :: f32(500)

set_audio_listener :: proc(pos: [3]f32) {
    g_listener_pos = pos
}

@(private = "file") g_sfx_cache:      map[string]rl.Sound  // stem → Sound
@(private = "file") g_voice_cache:    map[string]rl.Sound  // stem → Sound
@(private = "file") g_music_stream:   rl.Music
@(private = "file") g_music_loaded:   bool
@(private = "file") g_amb_stream:     rl.Music
@(private = "file") g_amb_loaded:     bool


init_audio :: proc() {
    rl.InitAudioDevice()
    g_sfx_cache   = make(map[string]rl.Sound)
    g_voice_cache = make(map[string]rl.Sound)
}

shutdown_audio :: proc() {
    for _, &s in g_sfx_cache   { rl.UnloadSound(s) }
    for _, &s in g_voice_cache { rl.UnloadSound(s) }
    if g_music_loaded { rl.UnloadMusicStream(g_music_stream) }
    if g_amb_loaded   { rl.UnloadMusicStream(g_amb_stream)   }
    delete(g_sfx_cache)
    delete(g_voice_cache)
    rl.CloseAudioDevice()
}

update_audio :: proc() {
    if g_music_loaded && rl.IsMusicStreamPlaying(g_music_stream) {
        rl.UpdateMusicStream(g_music_stream)
    }
    if g_amb_loaded && rl.IsMusicStreamPlaying(g_amb_stream) {
        rl.UpdateMusicStream(g_amb_stream)
    }
}

apply_bus_volumes :: proc() {
    if g_music_loaded {
        rl.SetMusicVolume(g_music_stream, clamp(g_vol_master * g_vol_music,    0, 1))
    }
    if g_amb_loaded {
        rl.SetMusicVolume(g_amb_stream,   clamp(g_vol_master * g_vol_ambience, 0, 1))
    }
}


//data/sounds/sfx/<stem>.wav
play_sfx :: proc(stem: string) {
    s, cached := g_sfx_cache[stem]
    if !cached {
        path_buf: [128]u8
        path := fmt.bprintf(path_buf[:127], "data/sounds/sfx/%s.mp3", stem)
        path_buf[len(path)] = 0
        s = rl.LoadSound(cstring(&path_buf[0]))
        g_sfx_cache[stem] = s
    }
    if s.frameCount == 0 { return }  
    rl.SetSoundPan(s, 0.5)           
    rl.SetSoundVolume(s, clamp(g_vol_master * g_vol_sfx, 0, 1))
    rl.PlaySound(s)
}

play_sfx_at :: proc(stem: string, world_pos: [3]f32) {
    s, cached := g_sfx_cache[stem]
    if !cached {
        path_buf: [128]u8
        path := fmt.bprintf(path_buf[:127], "data/sounds/sfx/%s.mp3", stem)
        path_buf[len(path)] = 0
        s = rl.LoadSound(cstring(&path_buf[0]))
        g_sfx_cache[stem] = s
    }
    if s.frameCount == 0 { return }

    dx   := world_pos[0] - g_listener_pos[0]
    dy   := world_pos[1] - g_listener_pos[1]
    dist := math.sqrt(dx*dx + dy*dy)

    dist_vol := clamp(1.0 - dist / SPATIAL_FALLOFF_RADIUS, 0, 1)
    if dist_vol <= 0 { return }

    pan := clamp(0.5 + (dx / PAN_HALF_WIDTH) * 0.45, 0.05, 0.95)

    rl.SetSoundPan(s, pan)
    rl.SetSoundVolume(s, clamp(g_vol_master * g_vol_sfx * dist_vol, 0, 1))
    rl.PlaySound(s)
}

// data/sounds/music/<stem>.ogg
play_music :: proc(stem: string) {
    if g_music_loaded {
        rl.StopMusicStream(g_music_stream)
        rl.UnloadMusicStream(g_music_stream)
        g_music_loaded = false
    }
    path_buf: [128]u8
    path := fmt.bprintf(path_buf[:127], "data/sounds/music/%s.mp3", stem)
    path_buf[len(path)] = 0
    g_music_stream        = rl.LoadMusicStream(cstring(&path_buf[0]))
    g_music_stream.looping = true
    g_music_loaded         = g_music_stream.frameCount > 0
    if g_music_loaded {
        rl.SetMusicVolume(g_music_stream, clamp(g_vol_master * g_vol_music, 0, 1))
        rl.PlayMusicStream(g_music_stream)
    }
}

stop_music :: proc() {
    if g_music_loaded { rl.StopMusicStream(g_music_stream) }
}

//data/sounds/ambience/<stem>.ogg
play_ambience :: proc(stem: string) {
    if g_amb_loaded {
        rl.StopMusicStream(g_amb_stream)
        rl.UnloadMusicStream(g_amb_stream)
        g_amb_loaded = false
    }
    path_buf: [128]u8
    path := fmt.bprintf(path_buf[:127], "data/sounds/ambience/%s.mp3", stem)
    path_buf[len(path)] = 0
    g_amb_stream        = rl.LoadMusicStream(cstring(&path_buf[0]))
    g_amb_stream.looping = true
    g_amb_loaded         = g_amb_stream.frameCount > 0
    if g_amb_loaded {
        rl.SetMusicVolume(g_amb_stream, clamp(g_vol_master * g_vol_ambience, 0, 1))
        rl.PlayMusicStream(g_amb_stream)
    }
}

stop_ambience :: proc() {
    if g_amb_loaded { rl.StopMusicStream(g_amb_stream) }
}

//data/sounds/voice/<stem>.wav
play_voice :: proc(stem: string) {
    s, cached := g_voice_cache[stem]
    if !cached {
        path_buf: [128]u8
        path := fmt.bprintf(path_buf[:127], "data/sounds/voice/%s.wav", stem)
        path_buf[len(path)] = 0
        s = rl.LoadSound(cstring(&path_buf[0]))
        g_voice_cache[stem] = s
    }
    if s.frameCount == 0 { return }
    rl.SetSoundVolume(s, clamp(g_vol_master * g_vol_voice, 0, 1))
    rl.PlaySound(s)
}
