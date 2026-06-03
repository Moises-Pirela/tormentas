package main

import rl "vendor:raylib"
import cw "clockwork"

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

g_stash: Stash

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
