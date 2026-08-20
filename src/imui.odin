package main

import cwrl "cw:ui/raylib"
import mu   "vendor:microui"

@(private = "file") g_imui_ctx:     ^mu.Context
@(private = "file") g_imui_backend: cwrl.Backend
@(private = "file") g_imui_ready:   bool
@(private = "file") g_imui_open:    bool

imui_init :: proc() {
    if g_imui_ready { return }
    g_imui_ctx = new(mu.Context)
    cwrl.init(&g_imui_backend, g_imui_ctx)
    g_imui_ready = true
}

imui_shutdown :: proc() {
    if !g_imui_ready { return }
    cwrl.shutdown(&g_imui_backend)
    free(g_imui_ctx)
    g_imui_ctx = nil
    g_imui_ready = false
    g_imui_open = false
}

imui_ctx :: proc() -> ^mu.Context {
    imui_init()
    return g_imui_ctx
}

imui_begin :: proc() {
    imui_init()
    cwrl.input(&g_imui_backend, g_imui_ctx)
    mu.begin(g_imui_ctx)
    g_imui_open = true
}

imui_end :: proc() {
    if !g_imui_ready || !g_imui_open { return }
    mu.end(g_imui_ctx)
    g_imui_open = false
    cwrl.render(&g_imui_backend, g_imui_ctx)
}

imui_wants_mouse :: proc() -> bool {
    if !g_imui_ready { return false }
    return g_imui_ctx.hover_root != nil
}

imui_wants_keys :: proc() -> bool {
    if !g_imui_ready { return false }
    return g_imui_ctx.focus_id != 0
}
