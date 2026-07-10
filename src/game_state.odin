package main

import rl  "vendor:raylib"
import cw  "clockwork"

AppState :: enum {
    MainMenu,
    Connecting,
    Playing,
}


PlayingSubstate :: enum {
    Gameplay,
    Hub,
    Editor,
    DeathScreen,
    ExtractScreen,
}

g_playing_state: PlayingSubstate

g_hub_active: bool

g_current_raid_level: int


g_pending_raid_start: int


// ---------------------------------------------------------------------------
// Music state resolution (maps game state -> engine MusicState each frame)
// ---------------------------------------------------------------------------

COMBAT_MUSIC_HOLD :: f32(5.0)   // seconds of "combat" music after the last hit
g_combat_timer: f32

// Called from combat code (damage involving the local player) to keep combat music up.
mark_combat :: proc() { g_combat_timer = COMBAT_MUSIC_HOLD }

// Resolves the desired music state from app/playing state, boss presence, and recent
// combat, then hands it to the crossfading music system (which no-ops if unchanged).
update_music_state :: proc(w: ^cw.World) {
    dt := rl.GetFrameTime()
    if g_combat_timer > 0 { g_combat_timer = max(g_combat_timer - dt, 0) }

    state := MusicState.None
    switch g_app_state {
    case .MainMenu, .Connecting:
        state = .Menu
    case .Playing:
        switch g_playing_state {
        case .Hub, .ExtractScreen:
            state = .Hub
        case .DeathScreen, .Editor:
            state = .None
        case .Gameplay:
            if g_boss_id != cw.INVALID_ENTITY && cw.world_is_valid(w, g_boss_id) {
                state = .Boss
            } else if g_combat_timer > 0 {
                state = .Combat
            } else {
                state = .Explore
            }
        }
    }
    audio_music_set_state(state)
}


STASH_MAX_ITEMS :: 64
STASH_COLS :: 12
STASH_ROWS :: 8

Stash :: struct {
    gold:   int,
    serums: int,
    item_count: int,
    item_ids:   [STASH_MAX_ITEMS]int,
    grid:       [STASH_COLS * STASH_ROWS]int,
}

g_stash: [2]Stash

local_stash :: proc() -> ^Stash { return &g_stash[g_session.local_slot] }

g_hub_remote_spawned: bool
g_hub_remote_loaded:  bool

stash_make_empty :: proc() -> Stash {
    s := Stash{}
    for &id in s.item_ids { id = cw.INVALID_ENTITY }
    for &cell in s.grid { cell = cw.INVALID_ENTITY }
    return s
}

raid_result_gold:   int
raid_result_serums: int


g_raid_serums_start: int

g_paused: bool

set_playing_state :: proc(next: PlayingSubstate) {
    g_playing_state = next
    g_editor_mode   = (next == .Editor)
}


playing_collects_input :: proc() -> bool {
    return (g_playing_state == .Gameplay || g_playing_state == .Hub) &&
           input_is_gameplay()
}

g_app_state: AppState = .MainMenu

g_is_host: bool


PLAYER_NAME_MAX :: 24
g_player_name:  [PLAYER_NAME_MAX + 1]u8
g_player_names: [4][PLAYER_NAME_MAX + 1]u8


g_disconnect_msg_timer: f32
DISCONNECT_MSG_DURATION :: f32(4.0)

g_should_exit: bool


g_loot_filter_rarity: cw.ItemRarity = .Normal

g_selected_class_idx: int = 0


FADE_SPEED :: f32(2.5)

FadePhase :: enum { Idle, FadingOut, Black, FadingIn }

g_fade_phase:    FadePhase
g_fade_alpha:    f32
g_fade_callback: proc()

fade_to_black :: proc(on_black: proc()) {
    if g_fade_phase == .FadingOut || g_fade_phase == .Black { return }
    g_fade_callback = on_black
    g_fade_phase    = .FadingOut
}

fade_from_black :: proc() {
    g_fade_phase = .FadingIn
}

update_fade :: proc(dt: f32) {
    switch g_fade_phase {
    case .Idle:
    case .FadingOut:
        g_fade_alpha = min(g_fade_alpha + dt * FADE_SPEED, 1)
        if g_fade_alpha >= 1 {
            g_fade_phase = .Black
            cb := g_fade_callback
            g_fade_callback = nil
            if cb != nil { cb() }
        }
    case .Black:
    case .FadingIn:
        g_fade_alpha = max(g_fade_alpha - dt * FADE_SPEED, 0)
        if g_fade_alpha <= 0 { g_fade_phase = .Idle }
    }
}

draw_fade :: proc() {
    if g_fade_alpha <= 0 { return }
    a := u8(g_fade_alpha * 255)
    rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(),
        rl.Color{0, 0, 0, a})
}
