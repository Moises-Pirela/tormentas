package main

import rl      "vendor:raylib"
import        "core:fmt"
import        "core:math"
import        "core:os"
import        "core:strings"
import json   "core:encoding/json"

g_vol_master:   f32 = 1.0
g_vol_sfx:      f32 = 1.0
g_vol_music:    f32 = 0.7
g_vol_ambience: f32 = 0.5
g_vol_voice:    f32 = 1.0

g_listener_pos: [3]f32

SPATIAL_FALLOFF_RADIUS :: f32(700)
PAN_HALF_WIDTH         :: f32(500)

set_audio_listener :: proc(pos: [3]f32) {
    g_listener_pos = pos
}

AUDIO_MANIFEST_PATH     :: "data/sounds/audio.json"
AUDIO_SOUND_DIR         :: "data/sounds/"
AUDIO_MAX_ALIASES_TOTAL :: 48

AudioBus     :: enum u8 { SFX, Music, Ambience, Voice, UI }
AudioSelect  :: enum u8 { First, Random, RoundRobin }
AudioRolloff :: enum u8 { Linear, Inverse, None }

MusicState   :: enum u8 { None, Menu, Hub, Explore, Combat, Boss, Tension }

AudioEventDef :: struct {
    name:          string,
    bus:           AudioBus,
    variants:      []string,
    select:        AudioSelect,
    gain:          f32,
    gain_var:      f32,
    pitch:         f32,
    pitch_var:     f32,
    max_instances: int,
    min_interval:  f32,
    priority:      int,
    spatial:       bool,
    rolloff:       AudioRolloff,
    inner:         f32,
    outer:         f32,
    preload:       bool,

    rr_index:      int,
    last_play_t:   f64,
}

@(private = "file")
AliasVoice :: struct {
    sound:    rl.Sound,
    priority: int,
    start_t:  f64,
}

@(private = "file")
AliasPool :: struct {
    source: rl.Sound,
    voices: [dynamic]AliasVoice,
}

@(private = "file")
CrossfadeStream :: struct {
    bus:      AudioBus,
    streams:  [2]rl.Music,
    loaded:   [2]bool,
    active:   int,
    cur_stem: string,
    fading:   bool,
    fade_t:   f32,
    fade_dur: f32,
}

@(private = "file") g_event_defs:  [dynamic]AudioEventDef
@(private = "file") g_event_index: map[string]int
@(private = "file") g_pools:       [dynamic]AliasPool
@(private = "file") g_pool_index:  map[string]int
@(private = "file") g_alias_total: int

@(private = "file") g_voice_cache: map[string]rl.Sound

@(private = "file") g_music_cf:     CrossfadeStream
@(private = "file") g_amb_cf:       CrossfadeStream
@(private = "file") g_amb_bed_cf:   CrossfadeStream
@(private = "file") g_music_state:  MusicState = .None
@(private = "file") g_music_states: map[string]string

@(private = "file") g_music_duck:    f32 = 1
@(private = "file") g_duck_hold:     f32
@(private = "file") g_duck_release:  f32 = 0.3

init_audio :: proc() {
    rl.InitAudioDevice()
    g_event_index  = make(map[string]int)
    g_pool_index   = make(map[string]int)
    g_voice_cache  = make(map[string]rl.Sound)
    g_music_states = make(map[string]string)
    g_music_cf.bus = .Music
    g_amb_cf.bus   = .Ambience
    g_amb_bed_cf.bus = .Ambience
    _audio_load_manifest()
    _audio_preload()
}

shutdown_audio :: proc() {
    for &p in g_pools {
        for v in p.voices { rl.UnloadSoundAlias(v.sound) }
        delete(p.voices)
        if p.source.frameCount > 0 { rl.UnloadSound(p.source) }
    }
    delete(g_pools)
    delete(g_pool_index)
    delete(g_event_defs)
    delete(g_event_index)

    for _, &s in g_voice_cache { rl.UnloadSound(s) }
    delete(g_voice_cache)

    _cf_unload(&g_music_cf)
    _cf_unload(&g_amb_cf)
    _cf_unload(&g_amb_bed_cf)
    delete(g_music_states)

    rl.CloseAudioDevice()
}

update_audio :: proc() {
    dt := rl.GetFrameTime()
    _duck_update(dt)
    _cf_update(&g_music_cf, dt)
    _cf_update(&g_amb_cf, dt)
    _cf_update(&g_amb_bed_cf, dt)
}

apply_bus_volumes :: proc() {}

play_sfx :: proc(name: string) {
    _audio_play(name, false, {})
}

play_sfx_at :: proc(name: string, world_pos: [3]f32) {
    _audio_play(name, true, world_pos)
}

@(private = "file")
_audio_play :: proc(name: string, has_pos: bool, pos: [3]f32) {
    idx := _event_idx(name)
    def := &g_event_defs[idx]

    now := rl.GetTime()
    if def.min_interval > 0 && now - def.last_play_t < f64(def.min_interval) { return }
    if len(def.variants) == 0 { return }

    variant := _select_variant(def)
    pidx    := _get_or_make_pool(variant)
    if g_pools[pidx].source.frameCount == 0 { return }

    gain := def.gain
    if def.gain_var > 0 { gain += _rand_pm(def.gain_var) }

    dist_vol := f32(1)
    pan      := f32(0.5)
    if has_pos && def.spatial {
        dist_vol, pan = _spatial(def, pos)
        if dist_vol <= 0 { return }
    }

    vidx, ok := _acquire_voice(pidx, def.priority, def.max_instances)
    if !ok { return }

    pitch := def.pitch
    if def.pitch_var > 0 { pitch += _rand_pm(def.pitch_var) }

    v := &g_pools[pidx].voices[vidx]
    v.priority = def.priority
    v.start_t  = now
    rl.SetSoundVolume(v.sound, clamp(g_vol_master * _bus_volume(def.bus) * gain * dist_vol, 0, 1))
    rl.SetSoundPan(v.sound, pan)
    rl.SetSoundPitch(v.sound, max(pitch, 0.05))
    rl.PlaySound(v.sound)

    def.last_play_t = now
}

@(private = "file")
_bus_volume :: proc(bus: AudioBus) -> f32 {
    switch bus {
    case .Music:    return g_vol_music
    case .Ambience: return g_vol_ambience
    case .Voice:    return g_vol_voice
    case .SFX, .UI: return g_vol_sfx
    }
    return g_vol_sfx
}

@(private = "file")
_spatial :: proc(def: ^AudioEventDef, pos: [3]f32) -> (vol, pan: f32) {
    dx   := pos[0] - g_listener_pos[0]
    dy   := pos[1] - g_listener_pos[1]
    dist := math.sqrt(dx*dx + dy*dy)

    outer := def.outer if def.outer > 0 else SPATIAL_FALLOFF_RADIUS
    inner := def.inner

    switch def.rolloff {
    case .None:
        vol = 1
    case .Inverse:
        if dist <= inner { vol = 1 }
        else if dist >= outer { vol = 0 }
        else { vol = clamp((inner > 0 ? inner / dist : 1) * (1 - (dist - inner) / (outer - inner)), 0, 1) }
    case .Linear:
        if outer > inner { vol = clamp(1 - (dist - inner) / (outer - inner), 0, 1) }
        else { vol = dist < outer ? 1 : 0 }
    }

    pan = clamp(0.5 + (dx / PAN_HALF_WIDTH) * 0.45, 0.05, 0.95)
    return
}

@(private = "file")
_rand_pm :: proc(v: f32) -> f32 {
    return (f32(rl.GetRandomValue(-1000, 1000)) / 1000.0) * v
}

@(private = "file")
_select_variant :: proc(def: ^AudioEventDef) -> string {
    n := len(def.variants)
    if n == 1 { return def.variants[0] }
    switch def.select {
    case .First:
        return def.variants[0]
    case .Random:
        return def.variants[rl.GetRandomValue(0, i32(n) - 1)]
    case .RoundRobin:
        v := def.variants[def.rr_index % n]
        def.rr_index += 1
        return v
    }
    return def.variants[0]
}

@(private = "file")
_event_idx :: proc(name: string) -> int {
    if idx, ok := g_event_index[name]; ok { return idx }
    return _register_default_event(name)
}

@(private = "file")
_register_default_event :: proc(name: string) -> int {
    def := AudioEventDef{
        name          = strings.clone(name),
        bus           = .SFX,
        select        = .Random,
        gain          = 1,
        pitch         = 1,
        max_instances = 4,
        priority      = 1,
        spatial       = true,
        rolloff       = .Linear,
    }
    def.variants = make([]string, 1)
    def.variants[0] = strings.clone(fmt.tprintf("sfx/%s", name))
    return _add_event(def)
}

@(private = "file")
_add_event :: proc(def: AudioEventDef) -> int {
    append(&g_event_defs, def)
    idx := len(g_event_defs) - 1
    g_event_index[def.name] = idx
    return idx
}

@(private = "file")
_get_or_make_pool :: proc(variant: string) -> int {
    if idx, ok := g_pool_index[variant]; ok { return idx }
    src := _load_source(variant)
    append(&g_pools, AliasPool{ source = src })
    idx := len(g_pools) - 1
    g_pool_index[strings.clone(variant)] = idx
    return idx
}

@(private = "file")
_load_source :: proc(variant: string) -> rl.Sound {
    exts := [?]string{ ".ogg", ".wav", ".mp3" }
    for ext in exts {
        p   := strings.concatenate({ AUDIO_SOUND_DIR, variant, ext }, context.temp_allocator)
        pcs := strings.clone_to_cstring(p, context.temp_allocator)
        if rl.FileExists(pcs) {
            return rl.LoadSound(pcs)
        }
    }
    return rl.Sound{}
}

@(private = "file")
_acquire_voice :: proc(pidx: int, priority: int, max_instances: int) -> (int, bool) {
    for &v, i in g_pools[pidx].voices {
        if !rl.IsSoundPlaying(v.sound) { return i, true }
    }

    if len(g_pools[pidx].voices) < max(max_instances, 1) {
        if g_alias_total >= AUDIO_MAX_ALIASES_TOTAL {
            if !_reclaim_global_slot(priority) { return 0, false }
        }
        al := rl.LoadSoundAlias(g_pools[pidx].source)
        append(&g_pools[pidx].voices, AliasVoice{ sound = al })
        g_alias_total += 1
        return len(g_pools[pidx].voices) - 1, true
    }

    oldest    := -1
    oldest_t  := f64(0)
    for &v, i in g_pools[pidx].voices {
        if oldest < 0 || v.start_t < oldest_t { oldest = i; oldest_t = v.start_t }
    }
    if oldest >= 0 {
        rl.StopSound(g_pools[pidx].voices[oldest].sound)
        return oldest, true
    }
    return 0, false
}

@(private = "file")
_reclaim_global_slot :: proc(incoming_priority: int) -> bool {
    for &p in g_pools {
        for v, vi in p.voices {
            if !rl.IsSoundPlaying(v.sound) {
                rl.UnloadSoundAlias(v.sound)
                unordered_remove(&p.voices, vi)
                g_alias_total -= 1
                return true
            }
        }
    }

    found     := false
    low_pri   := 0
    low_t     := f64(0)
    vpool     := -1
    vidx      := -1
    for &p, pi in g_pools {
        for v, k in p.voices {
            if !found || v.priority < low_pri || (v.priority == low_pri && v.start_t < low_t) {
                found = true; low_pri = v.priority; low_t = v.start_t; vpool = pi; vidx = k
            }
        }
    }
    if found && low_pri < incoming_priority {
        s := g_pools[vpool].voices[vidx].sound
        rl.StopSound(s)
        rl.UnloadSoundAlias(s)
        unordered_remove(&g_pools[vpool].voices, vidx)
        g_alias_total -= 1
        return true
    }
    return false
}

audio_music_set_state :: proc(state: MusicState, fade_ms: f32 = 800) {
    if state == g_music_state { return }
    g_music_state = state
    stem := _music_state_stem(state)
    if stem == "" { _cf_stop(&g_music_cf, fade_ms) }
    else          { _cf_set(&g_music_cf, stem, fade_ms) }
}

audio_duck_music :: proc(amount, hold_ms, release_ms: f32) {
    g_music_duck   = clamp(1 - amount, 0, 1)
    g_duck_hold    = hold_ms / 1000.0
    g_duck_release = max(release_ms / 1000.0, 0.001)
}

play_music :: proc(stem: string) {
    _cf_set(&g_music_cf, fmt.tprintf("music/%s", stem), 600)
}
stop_music :: proc() {
    _cf_stop(&g_music_cf, 400)
}
play_ambience :: proc(stem: string) {
    _cf_set(&g_amb_cf, fmt.tprintf("ambience/%s", stem), 800)
}
stop_ambience :: proc() {
    _cf_stop(&g_amb_cf, 600)
    _cf_stop(&g_amb_bed_cf, 600)
}

play_ambience_bed :: proc(stem: string) {
    _cf_set(&g_amb_bed_cf, fmt.tprintf("ambience/%s", stem), 1200)
}

@(private = "file")
_music_state_stem :: proc(state: MusicState) -> string {
    key := _music_state_key(state)
    if key == "" { return "" }
    if s, ok := g_music_states[key]; ok { return s }
    return fmt.tprintf("music/%s", key)
}

@(private = "file")
_music_state_key :: proc(state: MusicState) -> string {
    switch state {
    case .Menu:    return "menu"
    case .Hub:     return "hub"
    case .Explore: return "explore"
    case .Combat:  return "combat"
    case .Boss:    return "boss"
    case .Tension: return "tension"
    case .None:    return ""
    }
    return ""
}

@(private = "file")
_duck_update :: proc(dt: f32) {
    if g_music_duck >= 1 { return }
    if g_duck_hold > 0 { g_duck_hold -= dt; return }
    g_music_duck = min(g_music_duck + dt / g_duck_release, 1)
}

@(private = "file")
_cf_set :: proc(cf: ^CrossfadeStream, stem: string, fade_ms: f32) {
    if cf.cur_stem == stem && cf.loaded[cf.active] { return }

    incoming := 1 - cf.active
    if cf.loaded[incoming] {
        rl.StopMusicStream(cf.streams[incoming])
        rl.UnloadMusicStream(cf.streams[incoming])
        cf.loaded[incoming] = false
    }
    if pcs, ok := _resolve_stream_path(stem); ok {
        m := rl.LoadMusicStream(pcs)
        m.looping = true
        if m.frameCount > 0 {
            cf.streams[incoming] = m
            cf.loaded[incoming]  = true
            rl.SetMusicVolume(m, 0)
            rl.PlayMusicStream(m)
        }
    }

    cf.active = incoming
    if len(cf.cur_stem) > 0 { delete(cf.cur_stem) }
    cf.cur_stem = strings.clone(stem)
    cf.fading   = true
    cf.fade_t   = 0
    cf.fade_dur = max(fade_ms / 1000.0, 0.001)
}

@(private = "file")
_cf_stop :: proc(cf: ^CrossfadeStream, fade_ms: f32) {
    if !cf.loaded[cf.active] && !cf.fading { return }

    incoming := 1 - cf.active
    if cf.loaded[incoming] {
        rl.StopMusicStream(cf.streams[incoming])
        rl.UnloadMusicStream(cf.streams[incoming])
        cf.loaded[incoming] = false
    }
    cf.active = incoming
    if len(cf.cur_stem) > 0 { delete(cf.cur_stem) }
    cf.cur_stem = ""
    cf.fading   = true
    cf.fade_t   = 0
    cf.fade_dur = max(fade_ms / 1000.0, 0.001)
}

@(private = "file")
_cf_update :: proc(cf: ^CrossfadeStream, dt: f32) {
    base := clamp(g_vol_master * _bus_volume(cf.bus), 0, 1)
    if cf.bus == .Music { base *= g_music_duck }

    for i in 0..<2 {
        if cf.loaded[i] && rl.IsMusicStreamPlaying(cf.streams[i]) {
            rl.UpdateMusicStream(cf.streams[i])
        }
    }

    if cf.fading {
        cf.fade_t += dt / cf.fade_dur
        done := cf.fade_t >= 1
        if done { cf.fade_t = 1 }

        in_i  := cf.active
        out_i := 1 - cf.active
        if cf.loaded[in_i]  { rl.SetMusicVolume(cf.streams[in_i],  base * cf.fade_t) }
        if cf.loaded[out_i] { rl.SetMusicVolume(cf.streams[out_i], base * (1 - cf.fade_t)) }

        if done {
            cf.fading = false
            if cf.loaded[out_i] {
                rl.StopMusicStream(cf.streams[out_i])
                rl.UnloadMusicStream(cf.streams[out_i])
                cf.loaded[out_i] = false
            }
        }
    } else if cf.loaded[cf.active] {
        rl.SetMusicVolume(cf.streams[cf.active], base)
    }
}

@(private = "file")
_cf_unload :: proc(cf: ^CrossfadeStream) {
    for i in 0..<2 {
        if cf.loaded[i] { rl.UnloadMusicStream(cf.streams[i]); cf.loaded[i] = false }
    }
    if len(cf.cur_stem) > 0 { delete(cf.cur_stem); cf.cur_stem = "" }
}

@(private = "file")
_resolve_stream_path :: proc(stem: string) -> (cstring, bool) {
    if len(stem) == 0 { return nil, false }
    exts := [?]string{ ".ogg", ".mp3" }
    for ext in exts {
        p   := strings.concatenate({ AUDIO_SOUND_DIR, stem, ext }, context.temp_allocator)
        pcs := strings.clone_to_cstring(p, context.temp_allocator)
        if rl.FileExists(pcs) { return pcs, true }
    }
    return nil, false
}

@(private = "file")
_audio_load_manifest :: proc() {
    data, ok := os.read_entire_file(AUDIO_MANIFEST_PATH)
    if !ok { return }
    defer delete(data)

    root, err := json.parse(data)
    if err != .None {
        fmt.eprintfln("[audio] failed to parse %s: %v", AUDIO_MANIFEST_PATH, err)
        return
    }
    defer json.destroy_value(root)

    obj, obj_ok := root.(json.Object)
    if !obj_ok { return }

    if events, ev_ok := obj["events"].(json.Object); ev_ok {
        for name, val in events {
            _add_event(_parse_event(name, val))
        }
    }

    if music, m_ok := obj["music"].(json.Object); m_ok {
        for key, val in music {
            #partial switch s in val {
            case string:
                g_music_states[strings.clone(key)] = strings.clone(s)
            }
        }
    }
}

@(private = "file")
_audio_preload :: proc() {
    for &def in g_event_defs {
        if !def.preload { continue }
        for v in def.variants { _get_or_make_pool(v) }
    }
}

audio_reload :: proc() {
    _audio_clear_events()
    _audio_load_manifest()
    _audio_preload()
}

@(private = "file")
_audio_clear_events :: proc() {
    for &def in g_event_defs {
        for v in def.variants { delete(v) }
        delete(def.variants)
        delete(def.name)
    }
    clear(&g_event_defs)
    clear(&g_event_index)
    for k, v in g_music_states { delete(k); delete(v) }
    clear(&g_music_states)
}

audio_debug_event_names :: proc(allocator := context.temp_allocator) -> []string {
    out := make([]string, len(g_event_defs), allocator)
    for def, i in g_event_defs { out[i] = def.name }
    return out
}

audio_music_set_state_named :: proc(name: string) -> bool {
    st, ok := _music_state_from_key(name)
    if !ok { return false }
    audio_music_set_state(st)
    return true
}

@(private = "file")
_music_state_from_key :: proc(name: string) -> (MusicState, bool) {
    switch name {
    case "none":    return .None,    true
    case "menu":    return .Menu,    true
    case "hub":     return .Hub,     true
    case "explore": return .Explore, true
    case "combat":  return .Combat,  true
    case "boss":    return .Boss,    true
    case "tension": return .Tension, true
    }
    return .None, false
}

@(private = "file")
_parse_event :: proc(name: string, val: json.Value) -> AudioEventDef {
    def := AudioEventDef{
        name          = strings.clone(name),
        bus           = .SFX,
        select        = .Random,
        gain          = 1,
        pitch         = 1,
        max_instances = 4,
        priority      = 1,
        rolloff       = .Linear,
    }

    if o, ok := val.(json.Object); ok {
        def.bus           = _parse_bus(_jstr(o, "bus", "sfx"))
        def.select        = _parse_select(_jstr(o, "select", "random"))
        def.gain          = _jf32(o, "gain", 1)
        def.gain_var      = _jf32(o, "gain_var", 0)
        def.pitch         = _jf32(o, "pitch", 1)
        def.pitch_var     = _jf32(o, "pitch_var", 0)
        def.max_instances = _jint(o, "max_instances", 4)
        def.min_interval  = _jf32(o, "min_interval_ms", 0) / 1000.0
        def.priority      = _jint(o, "priority", 1)
        def.spatial       = _jbool(o, "spatial", false)
        def.rolloff       = _parse_rolloff(_jstr(o, "rolloff", "linear"))
        def.inner         = _jf32(o, "inner", 0)
        def.outer         = _jf32(o, "outer", 0)
        def.preload       = _jbool(o, "preload", false)
        def.variants      = _jstr_array(o, "variants")
    }

    if len(def.variants) == 0 {
        def.variants = make([]string, 1)
        def.variants[0] = strings.clone(fmt.tprintf("sfx/%s", name))
    }
    return def
}

@(private = "file")
_parse_bus :: proc(s: string) -> AudioBus {
    switch s {
    case "music":    return .Music
    case "ambience": return .Ambience
    case "voice":    return .Voice
    case "ui":       return .UI
    }
    return .SFX
}

@(private = "file")
_parse_select :: proc(s: string) -> AudioSelect {
    switch s {
    case "first":       return .First
    case "round_robin": return .RoundRobin
    }
    return .Random
}

@(private = "file")
_parse_rolloff :: proc(s: string) -> AudioRolloff {
    switch s {
    case "inverse": return .Inverse
    case "none":    return .None
    }
    return .Linear
}

@(private = "file")
_jf32 :: proc(o: json.Object, key: string, d: f32) -> f32 {
    v, ok := o[key]
    if !ok { return d }
    #partial switch n in v {
    case json.Float:   return f32(n)
    case json.Integer: return f32(n)
    }
    return d
}

@(private = "file")
_jint :: proc(o: json.Object, key: string, d: int) -> int {
    v, ok := o[key]
    if !ok { return d }
    #partial switch n in v {
    case json.Integer: return int(n)
    case json.Float:   return int(n)
    }
    return d
}

@(private = "file")
_jbool :: proc(o: json.Object, key: string, d: bool) -> bool {
    v, ok := o[key]
    if !ok { return d }
    #partial switch n in v {
    case bool: return n
    }
    return d
}

@(private = "file")
_jstr :: proc(o: json.Object, key: string, d: string) -> string {
    v, ok := o[key]
    if !ok { return d }
    #partial switch n in v {
    case string: return n
    }
    return d
}

@(private = "file")
_jstr_array :: proc(o: json.Object, key: string) -> []string {
    v, ok := o[key]
    if !ok { return nil }
    arr, aok := v.(json.Array)
    if !aok { return nil }
    out := make([]string, len(arr))
    n := 0
    for e in arr {
        #partial switch s in e {
        case string:
            out[n] = strings.clone(s)
            n += 1
        }
    }
    return out[:n]
}

FOOTSTEP_DISTANCE  :: f32(120.0)
FOOTSTEP_MIN_SPEED :: ANIM_WALK_SPEED_THRESH

@(private = "file") g_step_accum:    f32
@(private = "file") g_step_last_pos: [2]f32
@(private = "file") g_step_primed:   bool

tick_footsteps :: proc(w: ^World, dt: f32) {
    pid := w.player_id
    if !world_is_valid(w, pid) || !world_has_component(w, pid, .Transform) {
        g_step_primed = false
        return
    }

    if world_has_component(w, pid, .DodgeState) && comp_get(w, pid, .DodgeState, DodgeComp).active {
        g_step_primed = false
        return
    }
    if world_has_component(w, pid, .Respawn) && comp_get(w, pid, .Respawn, RespawnComp).timer > 0 {
        g_step_primed = false
        return
    }

    p := comp_get(w, pid, .Transform, TransformComp).position
    iso := world_to_iso_xy(p[0], p[1])
    cur := [2]f32{ iso.x, iso.y }

    if !g_step_primed {
        g_step_last_pos = cur
        g_step_accum    = 0
        g_step_primed   = true
        return
    }

    d := [2]f32{ cur[0] - g_step_last_pos[0], cur[1] - g_step_last_pos[1] }
    g_step_last_pos = cur

    moved := math.sqrt(d[0]*d[0] + d[1]*d[1])
    if dt > 0 && moved / dt < FOOTSTEP_MIN_SPEED {
        g_step_accum = max(g_step_accum - moved, 0)
        return
    }

    g_step_accum += moved
    for g_step_accum >= FOOTSTEP_DISTANCE {
        g_step_accum -= FOOTSTEP_DISTANCE
        play_sfx("step")
    }
}
