package main

import rl "vendor:raylib"

InputMode :: enum {
    Gameplay,
    UI,
}

_IM_KEY_CAP :: 512

_IM_BTN_CAP :: 8

InputManager :: struct {
    mode:         InputMode,
    key_consumed: [_IM_KEY_CAP]bool,
    btn_consumed: [_IM_BTN_CAP]bool,
}

g_input: InputManager

input_begin_frame :: proc() {
    g_input.key_consumed = {}
    g_input.btn_consumed = {}
    g_input.mode = .UI if ui_any() else .Gameplay
}

input_is_gameplay :: proc() -> bool { return g_input.mode == .Gameplay }
input_is_ui       :: proc() -> bool { return g_input.mode == .UI       }

input_pressed :: proc(key: rl.KeyboardKey, consume := true) -> bool {
    idx := int(key)
    if idx < 0 || idx >= _IM_KEY_CAP     { return false }
    if g_input.key_consumed[idx]          { return false }
    if !rl.IsKeyPressed(key)              { return false }
    if consume { g_input.key_consumed[idx] = true }
    return true
}

input_down :: proc(key: rl.KeyboardKey, consume := false) -> bool {
    idx := int(key)
    if idx < 0 || idx >= _IM_KEY_CAP     { return false }
    if g_input.key_consumed[idx]          { return false }
    if !rl.IsKeyDown(key)                 { return false }
    if consume { g_input.key_consumed[idx] = true }
    return true
}

input_consume_key :: proc(key: rl.KeyboardKey) {
    idx := int(key)
    if idx >= 0 && idx < _IM_KEY_CAP {
        g_input.key_consumed[idx] = true
    }
}
