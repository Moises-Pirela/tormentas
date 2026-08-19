package main

import ecs  "cw:clockwork"
import cwui "cw:ui/microui"
import cwrl "cw:ui/raylib"
import mu   "vendor:microui"
import p2p  "p2p"
import rl   "vendor:raylib"

@(private = "file") g_dbg_ctx:       ^mu.Context
@(private = "file") g_dbg_backend:   cwrl.Backend
@(private = "file") g_dbg_insp:      ecs.Inspector
@(private = "file") g_dbg_ui:        cwui.UiState
@(private = "file") g_dbg_authority: ecs.Sim
@(private = "file") g_dbg_ready:     bool

g_dbg_insp_open: bool

dbg_inspector_init :: proc() {
    if g_dbg_ready {return}
    g_dbg_ctx = new(mu.Context)
    cwrl.init(&g_dbg_backend, g_dbg_ctx)
    g_dbg_insp = ecs.inspector_make()
    g_dbg_ready = true
}

dbg_inspector_shutdown :: proc() {
    if !g_dbg_ready {return}
    cwrl.shutdown(&g_dbg_backend)
    free(g_dbg_ctx)
    g_dbg_ctx = nil
    g_dbg_ready = false
}

dbg_inspector_wants_mouse :: proc() -> bool {
    if !g_dbg_insp_open || !g_dbg_ready {return false}
    return g_dbg_ctx.hover_root != nil
}

dbg_inspector_wants_keys :: proc() -> bool {
    if !g_dbg_insp_open || !g_dbg_ready {return false}
    return g_dbg_ctx.focus_id != 0
}

dbg_inspector_toggle :: proc() {
    if !g_sim_alive {
        g_dbg_insp_open = false
        return
    }
    dbg_inspector_init()
    g_dbg_insp_open = !g_dbg_insp_open
}

dbg_inspector_draw :: proc() {
    if !g_dbg_insp_open || !g_dbg_ready {return}
    if !g_sim_alive {
        g_dbg_insp_open = false
        return
    }

    w := &g_sim.world.base

    g_dbg_authority.role = p2p.session_is_online(&g_session) ? ecs.SimRole.Client : ecs.SimRole.Host

    cwrl.input(&g_dbg_backend, g_dbg_ctx)

    mu.begin(g_dbg_ctx)
    cwui.inspector_window(
        g_dbg_ctx,
        &g_dbg_ui,
        &g_dbg_insp,
        w,
        &g_dbg_authority,
        mu.Rect{16, 16, 400, i32(rl.GetScreenHeight()) - 32},
    )
    cwui.stats_window(g_dbg_ctx, w, nil, mu.Rect{432, 16, 300, 200})
    mu.end(g_dbg_ctx)

    cwrl.render(&g_dbg_backend, g_dbg_ctx)

}
