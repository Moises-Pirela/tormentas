package gfx

// Platform layer: input, screen size and time (docs/BUILD_PLAN.md, P1a step 3).
//
// Game code asks these procedures, never raylib. For now they forward to raylib, which still owns
// the window. Step 7 reimplements them on sokol_app, whose input is event-driven: events will fill
// per-frame key/mouse state that these same procedures read, so call sites don't change.

import rl "vendor:raylib"

// Keyboard key. Values are GLFW's, and raylib and sokol_app share them (all 93 common names verified
// equal, 2026-11-17), so key codes saved as integers in config stay valid across the backend swap.
Key :: rl.KeyboardKey

// Mouse button: LEFT = 0, RIGHT = 1, MIDDLE = 2 in both raylib and sokol_app.
MouseButton :: rl.MouseButton

// ---- synthetic input -------------------------------------------------------------------------

// Synthetic input for scripted runs (the tools probe). While it is on, *all* real keyboard and
// mouse input is ignored: keys and buttons read as up, the wheel and text input as empty, and the
// pointer sits where the script put it. Scripts act by calling game procedures directly, so a run
// no longer depends on the real cursor or on anyone clicking or typing while it plays.
// devui forwards the same state to ImGui.
@(private = "file") _synthetic:     bool
@(private = "file") _pointer:       Vec2
@(private = "file") _pointer_prev:  Vec2

set_synthetic_pointer :: proc(p: Vec2) {
    if !_synthetic { _pointer_prev = p }
    _pointer, _synthetic = p, true
}

clear_synthetic_input :: proc() { _synthetic = false }

// False while synthetic input is on: real input must not reach the game or ImGui.
real_input_enabled :: proc() -> bool { return !_synthetic }

// ---- keyboard --------------------------------------------------------------------------------

key_pressed  :: proc(k: Key) -> bool { return !_synthetic && rl.IsKeyPressed(k) }
key_down     :: proc(k: Key) -> bool { return !_synthetic && rl.IsKeyDown(k) }
key_released :: proc(k: Key) -> bool { return !_synthetic && rl.IsKeyReleased(k) }

// Next key pressed this frame, or .KEY_NULL when the queue is empty (for key rebinding).
key_pressed_any :: proc() -> Key { return .KEY_NULL if _synthetic else rl.GetKeyPressed() }

// Next character typed this frame, or 0 when the queue is empty.
char_pressed :: proc() -> rune { return 0 if _synthetic else rl.GetCharPressed() }

// ---- mouse -----------------------------------------------------------------------------------

mouse_position :: proc() -> Vec2 { return _pointer if _synthetic else rl.GetMousePosition() }
mouse_delta    :: proc() -> Vec2 { return _pointer - _pointer_prev if _synthetic else rl.GetMouseDelta() }

mouse_pressed  :: proc(b: MouseButton) -> bool { return !_synthetic && rl.IsMouseButtonPressed(b) }
mouse_down     :: proc(b: MouseButton) -> bool { return !_synthetic && rl.IsMouseButtonDown(b) }
mouse_released :: proc(b: MouseButton) -> bool { return !_synthetic && rl.IsMouseButtonReleased(b) }

// Vertical wheel movement this frame (the larger axis, as raylib reports it).
mouse_wheel :: proc() -> f32 { return 0 if _synthetic else rl.GetMouseWheelMove() }

// ---- frame -----------------------------------------------------------------------------------

// Call once per frame, after input has been read: ends this frame's synthetic pointer delta.
end_input_frame :: proc() { _pointer_prev = _pointer }

// ---- screen and time -------------------------------------------------------------------------

// Window size in screen coordinates (the space mouse positions are reported in).
screen_width  :: proc() -> i32 { return rl.GetScreenWidth() }
screen_height :: proc() -> i32 { return rl.GetScreenHeight() }

// Seconds since the window opened.
time :: proc() -> f64 { return rl.GetTime() }

// Duration of the last frame, in seconds.
frame_time :: proc() -> f32 { return rl.GetFrameTime() }

window_should_close :: proc() -> bool { return rl.WindowShouldClose() }
