package main

import ecs  "cw:clockwork"
import cwui "../ui/microui"
import "core:fmt"
import "core:strings"
import mu "vendor:microui"
import rl "vendor:raylib"

EditorMode :: enum u8 {
    Edit,
    Live,
}

g_ed_mode: EditorMode = .Edit

ed_set_mode :: proc(m: EditorMode) {
    if m == g_ed_mode { return }
    g_ed_mode = m

    if !g_sim_alive { return }
    w := &g_sim.world

    switch m {
    case .Live:
        g_sim.state = .Running

    case .Edit:
        fire_system_reset()
        level_clear(w)
        director_init()
        level_apply(w)
        door_init_blockers(w)
        if g_hub_active { hub_apply(w) }
        spawn_players(w)
        g_sim.state = .Paused
    }
}

ed_mode_enter_editor :: proc() {
    g_ed_mode = .Live
    ed_set_mode(.Edit)
}

ed_mode_exit_editor :: proc() {
    g_ed_mode = .Live
    if g_sim_alive { g_sim.state = .Running }
}

editor_imui_windows :: proc() {
    if !g_editor_mode { return }

    ctx := imui_ctx()
    sw  := i32(rl.GetScreenWidth())

    if !mu.begin_window(ctx, "Editor", mu.Rect{sw - 260, ed_top(), 244, 208}) { return }
    defer mu.end_window(ctx)

    mu.layout_row(ctx, {-1}, 0)
    mu.label(ctx, g_ed_mode == .Edit ? "MODE: EDIT (sim paused)" : "MODE: LIVE (playtest)")

    mu.layout_row(ctx, {-1}, 0)
    if .SUBMIT in mu.button(ctx, g_ed_mode == .Edit ? "Enter Live  [F5]" : "Back to Edit  [F5]") {
        ed_set_mode(g_ed_mode == .Edit ? EditorMode.Live : EditorMode.Edit)
    }

    if g_ed_mode == .Live {
        mu.layout_row(ctx, {-1}, 0)
        mu.text(ctx, "Edits made while live are discarded on return.")
    }

    mu.layout_row(ctx, {-1}, 0)
    mu.label(ctx, fmt.tprintf("level %d   entities %d", g_ed_level, world_entity_count(&g_sim.world)))

    if .ACTIVE in mu.header(ctx, "level", {.EXPANDED}) {
        mu.layout_row(ctx, {-1}, 0)
        if .SUBMIT in mu.button(ctx, "Save") {
            level_save(g_ed_level)
            g_ed_save_msg = 2.0
        }
        mu.layout_row(ctx, {-1}, 0)
        if .SUBMIT in mu.button(ctx, "Reload") {
            fire_system_reset()
            level_clear(&g_sim.world)
            director_init()
            level_load(g_ed_level)
            level_apply(&g_sim.world)
            door_init_blockers(&g_sim.world)
            if g_hub_active { hub_apply(&g_sim.world) }
            spawn_players(&g_sim.world)
        }
    }
}

@(private = "file") g_ed_insp:           ecs.Inspector
@(private = "file") g_ed_insp_ui:        cwui.UiState
@(private = "file") g_ed_insp_authority: ecs.Sim
@(private = "file") g_ed_def_filter:   [48]u8
@(private = "file") g_ed_def_filter_n: int

editor_entity_windows :: proc() {
    if !g_editor_mode { return }
    ctx := imui_ctx()
    sw  := i32(rl.GetScreenWidth())
    sh  := i32(rl.GetScreenHeight())

    ed_entity_validate()

    if mu.begin_window(ctx, "Tools", mu.Rect{sw - 260, ed_top() + 216, 244, 300}) {
        mu.layout_row(ctx, {-1}, 0)
        mu.label(ctx, "tool")
        mu.layout_row(ctx, {59, 59, 59, -1}, 0)
        for t in EditorTool {
            label := fmt.tprintf("%v", t)
            if .SUBMIT in mu.button(ctx, g_ed_tool == t ? fmt.tprintf("[%s]", label) : label) {
                g_ed_tool = t
            }
        }

        mu.layout_row(ctx, {-1}, 0)
        mu.checkbox(ctx, "snap to tile grid", &g_ed_snap)

        mu.layout_row(ctx, {56, -1}, 0)
        mu.label(ctx, "filter")
        mu.textbox(ctx, g_ed_def_filter[:], &g_ed_def_filter_n)

        filter := strings.to_lower(string(g_ed_def_filter[:g_ed_def_filter_n]), context.temp_allocator)

        if .ACTIVE in mu.header(ctx, "entity defs", {.EXPANDED}) {
            for def, i in g_entity_defs {
                if filter != "" && !strings.contains(strings.to_lower(def.name, context.temp_allocator), filter) {
                    continue
                }
                mu.push_id(ctx, uintptr(i) + 0x4000)
                mu.layout_row(ctx, {-1}, 0)
                mark := i == g_ed_def_idx ? ">" : " "
                if .SUBMIT in mu.button(ctx, fmt.tprintf("%s %s", mark, def.name)) {
                    g_ed_def_idx = i
                    g_ed_tool    = .Place
                }
                mu.pop_id(ctx)
            }
        }
        mu.end_window(ctx)
    }

    sel := ed_entity_selected()
    if sel == nil { return }

    if mu.begin_window(ctx, "Selected", mu.Rect{506, ed_top(), 300, 400}) {
        mu.layout_row(ctx, {-1}, 0)
        mu.label(ctx, fmt.tprintf("%s  #%d", sel.def, g_ed_sel_entity))
        mu.label(ctx, fmt.tprintf("pos  %.0f, %.0f", sel.position[0], sel.position[1]))
        mu.label(ctx, fmt.tprintf("overrides  %d", len(sel.overrides)))

        mu.layout_row(ctx, {-1}, 0)
        if .SUBMIT in mu.button(ctx, "delete") {
            ed_entity_delete_selected()
            mu.end_window(ctx)
            return
        }
        mu.layout_row(ctx, {-1}, 0)
        if .SUBMIT in mu.button(ctx, "capture overrides") {
            ed_entity_capture()
        }
        mu.layout_row(ctx, {-1}, 0)
        if .SUBMIT in mu.button(ctx, "reset overrides") {
            level_entity_clear_overrides(g_ed_sel_entity)
            ed_entity_respawn_world()
        }

        if len(sel.overrides) > 0 {
            if .ACTIVE in mu.header(ctx, "authored overrides") {
                for o in sel.overrides {
                    mu.layout_row(ctx, {-1}, 0)
                    mu.label(ctx, fmt.tprintf("%v.%s = %s", o.component, o.path, o.value))
                }
            }
        }
        mu.end_window(ctx)
    }

    if g_sim_alive && world_is_valid(&g_sim.world, sel.live_id) {
        g_ed_insp_authority.role = .Host
        ecs.inspector_select(&g_ed_insp, &g_sim.world.base, sel.live_id)
        cwui.inspector_window(
            ctx, &g_ed_insp_ui, &g_ed_insp, &g_sim.world.base, &g_ed_insp_authority,
            mu.Rect{822, ed_top(), 380, sh - ed_top() - 16},
        )
    }
}
