package main

// =============================================================================
// input_manager.odin — Global input mode switch + per-frame key consumption
//
// Two input modes exist at any given time:
//
//   Gameplay  — the sim and world systems receive keyboard/mouse input.
//               Player movement, shooting, interact, loot-filter, etc.
//
//   UI        — at least one UIManager panel is open.  Panel code owns the
//               keyboard; the sim gets no input this frame.
//
// The mode is auto-derived each frame from ui_any() in input_begin_frame().
//
// All systems that want to read "was key X pressed this frame?" should call
// input_pressed() / input_mouse_pressed() instead of rl.IsKeyPressed() /
// rl.IsMouseButtonPressed() directly.  The wrappers mark keys consumed on
// first read so presses cannot leak from one consumer to another in the same
// frame (e.g. ESC closing an inventory panel must not also open PauseMenu).
//
// Usage
//   input_begin_frame()                  // once per frame before update
//   input_pressed(.E)                    // true once, then consumed
//   input_pressed(.E, consume=false)     // peek without consuming
//   input_consume_key(.SPACE)            // explicit consume
//   input_mode()                         // .Gameplay or .UI
//   input_is_gameplay()                  // shorthand
// =============================================================================

import rl "vendor:raylib"

// ---------------------------------------------------------------------------
// Mode
// ---------------------------------------------------------------------------

InputMode :: enum {
    Gameplay,  // sim receives input; world-level shortcuts active
    UI,        // overlay panels own input; sim gets no keyboard input
}

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

// rl.KeyboardKey max value is KEY_KB_MENU = 348; 512 covers all future values.
_IM_KEY_CAP :: 512
// rl.MouseButton has 7 named values.
_IM_BTN_CAP :: 8

InputManager :: struct {
    mode:         InputMode,
    key_consumed: [_IM_KEY_CAP]bool,
    btn_consumed: [_IM_BTN_CAP]bool,
}

g_input: InputManager

// ---------------------------------------------------------------------------
// Frame lifecycle
// ---------------------------------------------------------------------------

// input_begin_frame resets all consumed flags and derives the current mode
// from whether any UI panel is open.  Call exactly once per frame, after
// update_clay_input() and before any update proc reads input.
input_begin_frame :: proc() {
    g_input.key_consumed = {}
    g_input.btn_consumed = {}
    g_input.mode = .UI if ui_any() else .Gameplay
}

// ---------------------------------------------------------------------------
// Mode queries
// ---------------------------------------------------------------------------

input_mode :: proc() -> InputMode { return g_input.mode }

input_is_gameplay :: proc() -> bool { return g_input.mode == .Gameplay }
input_is_ui       :: proc() -> bool { return g_input.mode == .UI       }

// ---------------------------------------------------------------------------
// Keyboard
// ---------------------------------------------------------------------------

// input_pressed returns true if the key was pressed this frame and has not
// yet been consumed by another system.  Marks the key consumed by default.
input_pressed :: proc(key: rl.KeyboardKey, consume := true) -> bool {
    idx := int(key)
    if idx < 0 || idx >= _IM_KEY_CAP     { return false }
    if g_input.key_consumed[idx]          { return false }
    if !rl.IsKeyPressed(key)              { return false }
    if consume { g_input.key_consumed[idx] = true }
    return true
}

// input_released returns true if the key went up this frame and has not
// yet been consumed.
input_released :: proc(key: rl.KeyboardKey, consume := true) -> bool {
    idx := int(key)
    if idx < 0 || idx >= _IM_KEY_CAP     { return false }
    if g_input.key_consumed[idx]          { return false }
    if !rl.IsKeyReleased(key)             { return false }
    if consume { g_input.key_consumed[idx] = true }
    return true
}

// input_down returns true if the key is currently held and has not been
// consumed.  Does NOT consume by default (held-state is typically polled
// continuously rather than edge-triggered).
input_down :: proc(key: rl.KeyboardKey, consume := false) -> bool {
    idx := int(key)
    if idx < 0 || idx >= _IM_KEY_CAP     { return false }
    if g_input.key_consumed[idx]          { return false }
    if !rl.IsKeyDown(key)                 { return false }
    if consume { g_input.key_consumed[idx] = true }
    return true
}

// input_consume_key marks a key as consumed without testing it.
input_consume_key :: proc(key: rl.KeyboardKey) {
    idx := int(key)
    if idx >= 0 && idx < _IM_KEY_CAP {
        g_input.key_consumed[idx] = true
    }
}

// ---------------------------------------------------------------------------
// Mouse buttons
// ---------------------------------------------------------------------------

// input_mouse_pressed returns true if the button was pressed this frame and
// not yet consumed.  Marks the button consumed by default.
input_mouse_pressed :: proc(btn: rl.MouseButton, consume := true) -> bool {
    idx := int(btn)
    if idx < 0 || idx >= _IM_BTN_CAP     { return false }
    if g_input.btn_consumed[idx]          { return false }
    if !rl.IsMouseButtonPressed(btn)      { return false }
    if consume { g_input.btn_consumed[idx] = true }
    return true
}

// input_mouse_released returns true if the button went up this frame and
// not yet consumed.
input_mouse_released :: proc(btn: rl.MouseButton, consume := true) -> bool {
    idx := int(btn)
    if idx < 0 || idx >= _IM_BTN_CAP     { return false }
    if g_input.btn_consumed[idx]          { return false }
    if !rl.IsMouseButtonReleased(btn)     { return false }
    if consume { g_input.btn_consumed[idx] = true }
    return true
}

// input_mouse_down returns true if the button is currently held and not
// consumed.  Does NOT consume by default.
input_mouse_down :: proc(btn: rl.MouseButton, consume := false) -> bool {
    idx := int(btn)
    if idx < 0 || idx >= _IM_BTN_CAP     { return false }
    if g_input.btn_consumed[idx]          { return false }
    if !rl.IsMouseButtonDown(btn)         { return false }
    if consume { g_input.btn_consumed[idx] = true }
    return true
}

// input_consume_mouse marks a mouse button as consumed without testing it.
input_consume_mouse :: proc(btn: rl.MouseButton) {
    idx := int(btn)
    if idx >= 0 && idx < _IM_BTN_CAP {
        g_input.btn_consumed[idx] = true
    }
}
