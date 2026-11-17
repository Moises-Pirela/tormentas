package gfx

// Window, monitors and screenshots (docs/BUILD_PLAN.md, P1a step 4). Step 7 reimplements this on
// sokol_app, which has no window resize/position or monitor queries: the window-mode decision
// (resizable window + fullscreen toggle) is what makes that possible.

import "core:c"
import rl "vendor:raylib"

ConfigFlags :: rl.ConfigFlags
ConfigFlag  :: rl.ConfigFlag
Key_Null    :: Key.KEY_NULL

window_init        :: proc(#any_int w, h: c.int, title: cstring) { rl.InitWindow(w, h, title) }
window_close       :: proc()                                     { rl.CloseWindow() }
window_set_flags   :: proc(flags: ConfigFlags)                   { rl.SetConfigFlags(flags) }
window_set_fps     :: proc(#any_int fps: c.int)                  { rl.SetTargetFPS(fps) }
window_set_exit_key :: proc(k: Key)                              { rl.SetExitKey(k) }
window_set_icon    :: proc(img: Image)                           { rl.SetWindowIcon(img) }

window_set_size     :: proc(#any_int w, h: c.int) { rl.SetWindowSize(w, h) }
window_set_position :: proc(#any_int x, y: c.int) { rl.SetWindowPosition(x, y) }
window_set_min_size :: proc(#any_int w, h: c.int) { rl.SetWindowMinSize(w, h) }

window_is_state      :: proc(flags: ConfigFlags) -> bool { return rl.IsWindowState(flags) }
window_is_resized    :: proc() -> bool                   { return rl.IsWindowResized() }
window_is_fullscreen :: proc() -> bool                   { return rl.IsWindowFullscreen() }

// Borderless fullscreen on this backend. Under sokol_app (step 7) the toggle is borderless on
// Windows and native fullscreen on macOS, which is the decided behaviour.
window_toggle_fullscreen :: proc() { rl.ToggleBorderlessWindowed() }

window_handle    :: proc() -> rawptr { return rl.GetWindowHandle() }
window_scale_dpi :: proc() -> Vec2   { return rl.GetWindowScaleDPI() }

// Framebuffer size in pixels; differs from screen_width/height on a high-DPI display.
render_width  :: proc() -> i32 { return i32(rl.GetRenderWidth()) }
render_height :: proc() -> i32 { return i32(rl.GetRenderHeight()) }

monitor_current  :: proc() -> i32                      { return i32(rl.GetCurrentMonitor()) }
monitor_width    :: proc(#any_int m: c.int) -> i32     { return i32(rl.GetMonitorWidth(m)) }
monitor_height   :: proc(#any_int m: c.int) -> i32     { return i32(rl.GetMonitorHeight(m)) }
monitor_position :: proc(#any_int m: c.int) -> Vec2    { return rl.GetMonitorPosition(m) }

// Grabs the window and writes it to a PNG. sokol_gfx has no readback, so step 7 needs the native
// helper the spike proved out (src/spike/native/capture_metal.m, src/spike/capture_windows.odin).
screenshot :: proc(path: cstring) -> bool {
    img := rl.LoadImageFromScreen()
    defer rl.UnloadImage(img)
    return rl.ExportImage(img, path)
}
