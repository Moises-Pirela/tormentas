package gfx

// Window and screen (docs/BACKEND_SWAP_PLAN.md §3.12).
//
// The API is deliberately only what sokol_app can do (decision D3): a resizable window plus a
// fullscreen toggle. There is no window resize/position, no minimum size and no monitor query, so
// the resolution presets, fit-to-monitor and centering that raylib allowed are gone.

Window_Desc :: struct {
    width, height: i32,
    title:         cstring,
    fullscreen:    bool,
}

window_init :: proc(desc: Window_Desc) {
    _b_window_init(desc.width, desc.height, desc.title, desc.fullscreen)
}

window_close :: proc() { _b_window_close() }

// True when the user asked to close the window (close button, Cmd+Q).
window_should_close :: proc() -> bool { return _b_window_should_close() }

window_is_fullscreen     :: proc() -> bool { return _b_window_is_fullscreen() }
window_toggle_fullscreen :: proc()         { _b_window_toggle_fullscreen() }

// True on a frame where the window changed size.
window_resized :: proc() -> bool { return _b_window_resized() }

// Window size in logical screen coordinates: the space mouse positions and UI layout use.
screen_width  :: proc() -> i32 { return _b_screen_width() }
screen_height :: proc() -> i32 { return _b_screen_height() }

// Framebuffer size in pixels. Equal to the screen size while high-DPI is off (decision D1).
render_width  :: proc() -> i32 { return _b_render_width() }
render_height :: proc() -> i32 { return _b_render_height() }

// Framebuffer pixels per screen coordinate.
dpi_scale :: proc() -> f32 { return _b_dpi_scale() }

// Sets the window icon from 8-bit RGBA pixels.
window_set_icon :: proc(img: Image) { _b_set_window_icon(img) }

// Writes the current frame to a PNG. The backend reads it back from the GPU.
screenshot :: proc(path: cstring) -> bool { return _b_screenshot(path) }

// Native window handle (NSWindow on macOS, HWND on Windows).
window_handle :: proc() -> rawptr { return _b_window_handle() }
