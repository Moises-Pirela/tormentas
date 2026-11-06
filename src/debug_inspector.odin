package main

import ecs  "cw:clockwork"
import im   "../deps/imgui/imgui"
import p2p  "p2p"

@(private = "file") g_dbg_state: DevInspectorState

g_dbg_insp_open: bool

dbg_inspector_toggle :: proc() {
    if !g_sim_alive {
        g_dbg_insp_open = false
        return
    }
    devui_inspector_init(&g_dbg_state)
    g_dbg_insp_open = !g_dbg_insp_open
}

dbg_inspector_shutdown :: proc() {
    g_dbg_state     = {}
    g_dbg_insp_open = false
}

dbg_inspector_ui :: proc() {
    if !g_dbg_insp_open { return }
    if !g_sim_alive {
        g_dbg_insp_open = false
        return
    }
    w := &g_sim.world.base

    is_client := p2p.session_is_online(&g_session) && g_session.local_slot != 0
    g_dbg_state.authority.role = ecs.SimRole.Client if is_client else ecs.SimRole.Host

    im.SetNextWindowSize({ 560, 520 }, .FirstUseEver)
    defer im.End()
    if !im.Begin("ECS Inspector", &g_dbg_insp_open) { return }

    ui_hint("entities %d   tick %d", ecs.world_entity_count(w), w.tick)
    if im.BeginTable("##dbgsplit", 2, im.TableFlags_Resizable | im.TableFlags_BordersInnerV) {
        im.TableSetupColumn("entities", { .WidthFixed }, 140)
        im.TableSetupColumn("fields", { .WidthStretch })
        im.TableNextRow()
        im.TableNextColumn()
        devui_entity_list(&g_dbg_state, w)
        im.TableNextColumn()
        if im.BeginChild("##dbgfields") {
            devui_entity_fields(&g_dbg_state, w, &g_dbg_state.authority)
        }
        im.EndChild()
        im.EndTable()
    }
}
