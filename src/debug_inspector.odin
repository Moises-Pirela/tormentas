package main

import ecs  "cw:clockwork"
import cwui "cw:ui/microui"
import p2p  "p2p"
import mu   "vendor:microui"
import rl   "vendor:raylib"

@(private = "file") g_dbg_insp:      ecs.Inspector
@(private = "file") g_dbg_ui:        cwui.UiState
@(private = "file") g_dbg_authority: ecs.Sim
@(private = "file") g_dbg_ready:     bool

g_dbg_insp_open: bool

dbg_inspector_toggle :: proc() {
    if !g_sim_alive {
        g_dbg_insp_open = false
        return
    }
    if !g_dbg_ready {
        g_dbg_insp = ecs.inspector_make()
        g_dbg_ready = true
    }
    g_dbg_insp_open = !g_dbg_insp_open
}

dbg_inspector_shutdown :: proc() {
    g_dbg_ready = false
    g_dbg_insp_open = false
}

dbg_inspector_windows :: proc() {
    if !g_dbg_insp_open || !g_dbg_ready { return }
    if !g_sim_alive {
        g_dbg_insp_open = false
        return
    }

    ctx := imui_ctx()
    w   := &g_sim.world.base

    g_dbg_authority.role = p2p.session_is_online(&g_session) ? ecs.SimRole.Client : ecs.SimRole.Host

    cwui.inspector_window(
        ctx, &g_dbg_ui, &g_dbg_insp, w, &g_dbg_authority,
        mu.Rect{16, 16, 400, i32(rl.GetScreenHeight()) - 32},
    )
    cwui.stats_window(ctx, w, nil, mu.Rect{432, 16, 300, 200})
}
