package gfx

// Input and time (docs/BACKEND_SWAP_PLAN.md §3.10, §3.13).
//
// Under sokol_app input arrives as events; these procedures read the per-frame state those events
// build. `pressed` always means a fresh press, never an auto-repeat.

// ---- synthetic input -------------------------------------------------------------------------

// Synthetic input for scripted runs (the tools probe). While it is on, all real keyboard and mouse
// input is ignored: keys and buttons read as up, the wheel and text input as empty, and the pointer
// sits where the script put it. devui forwards the same state to ImGui.
@(private) _synthetic:     bool
@(private) _pointer:       Vec2
@(private) _pointer_prev:  Vec2

set_synthetic_pointer :: proc(p: Vec2) {
    if !_synthetic { _pointer_prev = p }
    _pointer, _synthetic = p, true
}

clear_synthetic_input :: proc() { _synthetic = false }

// False while synthetic input is on: real input must not reach the game or ImGui.
real_input_enabled :: proc() -> bool { return !_synthetic }

// True when a scripted run wants deterministic timing (fixed frame duration).
synthetic_timing :: proc() -> bool { return _synthetic }

// ---- keyboard --------------------------------------------------------------------------------

key_pressed  :: proc(k: Key) -> bool { return !_synthetic && _b_key_pressed(k) }
key_down     :: proc(k: Key) -> bool { return !_synthetic && _b_key_down(k) }
key_released :: proc(k: Key) -> bool { return !_synthetic && _b_key_released(k) }

// Next key pressed this frame, or .KEY_NULL when the queue is empty (for key rebinding).
key_pressed_any :: proc() -> Key { return .KEY_NULL if _synthetic else _b_key_queue() }

// Next character typed this frame, or 0 when the queue is empty. The game and ImGui share one
// queue, so whoever reads first consumes it.
char_pressed :: proc() -> rune { return 0 if _synthetic else _b_char_queue() }

// ---- mouse -----------------------------------------------------------------------------------

mouse_position :: proc() -> Vec2 { return _pointer if _synthetic else _b_mouse_pos() }
mouse_delta    :: proc() -> Vec2 { return _pointer - _pointer_prev if _synthetic else _b_mouse_delta() }

mouse_pressed  :: proc(b: MouseButton) -> bool { return !_synthetic && _b_mouse_pressed(b) }
mouse_down     :: proc(b: MouseButton) -> bool { return !_synthetic && _b_mouse_down(b) }
mouse_released :: proc(b: MouseButton) -> bool { return !_synthetic && _b_mouse_released(b) }

// Vertical wheel movement this frame.
mouse_wheel :: proc() -> f32 { return 0 if _synthetic else _b_mouse_wheel() }

// ---- frame -----------------------------------------------------------------------------------

// Call once per frame, after input has been read.
end_input_frame :: proc() { _pointer_prev = _pointer }

// ---- time ------------------------------------------------------------------------------------

// Seconds since the window opened.
time :: proc() -> f64 { return _b_time() }

// Duration of the last frame in seconds. Scripted runs get a fixed 1/60 so frame-numbered scripts
// behave the same at any refresh rate.
frame_time :: proc() -> f32 {
    if _synthetic { return 1.0 / 60.0 }
    return _b_frame_time()
}

// Caps the frame rate. 0 means uncapped (vsync still applies).
set_target_fps :: proc(#any_int fps: i32) { _b_set_fps(fps) }
