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


input_mode :: proc() -> InputMode { return g_input.mode }

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


input_released :: proc(key: rl.KeyboardKey, consume := true) -> bool {
    idx := int(key)
    if idx < 0 || idx >= _IM_KEY_CAP     { return false }
    if g_input.key_consumed[idx]          { return false }
    if !rl.IsKeyReleased(key)             { return false }
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


input_mouse_pressed :: proc(btn: rl.MouseButton, consume := true) -> bool {
    idx := int(btn)
    if idx < 0 || idx >= _IM_BTN_CAP     { return false }
    if g_input.btn_consumed[idx]          { return false }
    if !rl.IsMouseButtonPressed(btn)      { return false }
    if consume { g_input.btn_consumed[idx] = true }
    return true
}


input_mouse_released :: proc(btn: rl.MouseButton, consume := true) -> bool {
    idx := int(btn)
    if idx < 0 || idx >= _IM_BTN_CAP     { return false }
    if g_input.btn_consumed[idx]          { return false }
    if !rl.IsMouseButtonReleased(btn)     { return false }
    if consume { g_input.btn_consumed[idx] = true }
    return true
}


input_mouse_down :: proc(btn: rl.MouseButton, consume := false) -> bool {
    idx := int(btn)
    if idx < 0 || idx >= _IM_BTN_CAP     { return false }
    if g_input.btn_consumed[idx]          { return false }
    if !rl.IsMouseButtonDown(btn)         { return false }
    if consume { g_input.btn_consumed[idx] = true }
    return true
}


input_consume_mouse :: proc(btn: rl.MouseButton) {
    idx := int(btn)
    if idx >= 0 && idx < _IM_BTN_CAP {
        g_input.btn_consumed[idx] = true
    }
}
