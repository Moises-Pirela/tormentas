#+build !darwin
package main

native_fullscreen_prepare :: proc() {}
native_is_fullscreen      :: proc() -> bool { return false }
native_toggle_fullscreen  :: proc() {}
