#+build darwin
package main

import    "core:sys/posix"
import rl "vendor:raylib"

@(private = "file") g_objc:          posix.Symbol_Table
@(private = "file") g_msg_send:      rawptr
@(private = "file") g_sel_register:  proc "c" (name: cstring) -> rawptr

@(private = "file")
_objc_ready :: proc() -> bool {
    if g_msg_send != nil && g_sel_register != nil { return true }
    if g_objc == nil { g_objc = posix.dlopen("/usr/lib/libobjc.A.dylib", { .NOW }) }
    if g_objc == nil { return false }
    g_msg_send     = posix.dlsym(g_objc, "objc_msgSend")
    g_sel_register = auto_cast posix.dlsym(g_objc, "sel_registerName")
    return g_msg_send != nil && g_sel_register != nil
}

@(private = "file")
_sel :: proc(name: cstring) -> rawptr { return g_sel_register(name) }

@(private = "file")
_msg :: proc() -> rawptr { return g_msg_send }

@(private = "file") NS_FULLSCREEN_STYLE      :: u64(1) << 14
@(private = "file") NS_BEHAVIOR_FS_PRIMARY   :: u64(1) << 7
@(private = "file") NS_BEHAVIOR_FS_AUXILIARY :: u64(1) << 8
@(private = "file") NS_BEHAVIOR_FS_NONE      :: u64(1) << 9

@(private = "file") _send_u64      :: proc "c" (self, sel: rawptr) -> u64
@(private = "file") _send_set_u64  :: proc "c" (self, sel: rawptr, value: u64)
@(private = "file") _send_set_ptr  :: proc "c" (self, sel: rawptr, value: rawptr)

@(private = "file")
_window :: proc() -> rawptr {
    if !_objc_ready() { return nil }
    return rl.GetWindowHandle()
}

native_fullscreen_prepare :: proc() {
    win := _window()
    if win == nil { return }
    get := cast(_send_u64)_msg()
    set := cast(_send_set_u64)_msg()
    behavior := get(win, _sel("collectionBehavior"))
    behavior |= NS_BEHAVIOR_FS_PRIMARY
    behavior &~= NS_BEHAVIOR_FS_AUXILIARY | NS_BEHAVIOR_FS_NONE
    set(win, _sel("setCollectionBehavior:"), behavior)
}

native_is_fullscreen :: proc() -> bool {
    win := _window()
    if win == nil { return false }
    get := cast(_send_u64)_msg()
    return get(win, _sel("styleMask")) & NS_FULLSCREEN_STYLE != 0
}

native_toggle_fullscreen :: proc() {
    win := _window()
    if win == nil { return }
    send := cast(_send_set_ptr)_msg()
    send(win, _sel("toggleFullScreen:"), nil)
}
