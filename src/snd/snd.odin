package snd

// Audio API (docs/BUILD_PLAN.md, P1a). raylib's audio is miniaudio underneath, and step 7 swaps
// in miniaudio directly (Odin ships it in vendor:), so these handles and calls map across.

import rl "vendor:raylib"

Sound :: rl.Sound
Music :: rl.Music

device_init  :: proc()         { rl.InitAudioDevice() }
device_close :: proc()         { rl.CloseAudioDevice() }
device_ready :: proc() -> bool { return rl.IsAudioDeviceReady() }

load_sound        :: proc(path: cstring) -> Sound  { return rl.LoadSound(path) }
load_sound_alias  :: proc(src: Sound) -> Sound     { return rl.LoadSoundAlias(src) }
unload_sound      :: proc(s: Sound)                { rl.UnloadSound(s) }
unload_sound_alias :: proc(s: Sound)               { rl.UnloadSoundAlias(s) }

play_sound       :: proc(s: Sound)           { rl.PlaySound(s) }
stop_sound       :: proc(s: Sound)           { rl.StopSound(s) }
sound_playing    :: proc(s: Sound) -> bool   { return rl.IsSoundPlaying(s) }
sound_set_volume :: proc(s: Sound, v: f32)   { rl.SetSoundVolume(s, v) }
sound_set_pitch  :: proc(s: Sound, v: f32)   { rl.SetSoundPitch(s, v) }
sound_set_pan    :: proc(s: Sound, v: f32)   { rl.SetSoundPan(s, v) }

load_music       :: proc(path: cstring) -> Music { return rl.LoadMusicStream(path) }
unload_music     :: proc(m: Music)               { rl.UnloadMusicStream(m) }
play_music       :: proc(m: Music)               { rl.PlayMusicStream(m) }
stop_music       :: proc(m: Music)               { rl.StopMusicStream(m) }
update_music     :: proc(m: Music)               { rl.UpdateMusicStream(m) }
music_playing    :: proc(m: Music) -> bool       { return rl.IsMusicStreamPlaying(m) }
music_set_volume :: proc(m: Music, v: f32)       { rl.SetMusicVolume(m, v) }
