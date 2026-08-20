package main

import "core:fmt"
import mu  "vendor:microui"
import rl  "vendor:raylib"
import p2p "p2p"

ED_BRUSHES := [?]EditorBrush{ .HubCollision, .HubWalkable, .Oil, .Fire, .Module, .Erase }

@(private = "file")
ed_brush_label :: proc(b: EditorBrush) -> string {
    #partial switch b {
    case .HubCollision: return "collision"
    case .HubWalkable:  return "walkable"
    case .Oil:          return "oil"
    case .Fire:         return "fire"
    case .Module:       return "module"
    case .Erase:        return "erase"
    }
    return "?"
}

editor_paint_window :: proc() {
    ctx := imui_ctx()

    if !mu.begin_window(ctx, "Paint", mu.Rect{16, ed_top(), 214, 372}) { return }
    defer mu.end_window(ctx)

    mu.layout_row(ctx, {-1}, 0)
    mu.label(ctx, "brush")

    for b, i in ED_BRUSHES {
        mu.layout_row(ctx, {-1}, 0)
        mark := g_ed_brush == b ? ">" : " "
        if .SUBMIT in mu.button(ctx, fmt.tprintf("%s %s   [%d]", mark, ed_brush_label(b), i + 1)) {
            g_ed_brush = b
            g_ed_tool  = .Paint
        }
    }

    if g_ed_brush == .Module {
        if .ACTIVE in mu.header(ctx, "module", {.EXPANDED}) {
            mu.layout_row(ctx, {-1}, 0)
            mu.label(ctx, module_count() > 0 ? module_name(g_ed_module_idx) : "(no modules loaded)")
            mu.layout_row(ctx, {95, -1}, 0)
            if .SUBMIT in mu.button(ctx, "prev  [,]") { ed_cycle_module(-1) }
            if .SUBMIT in mu.button(ctx, "next  [.]") { ed_cycle_module(+1) }
        }
    }

    step := g_hub_active ? g_ed_cell_size : TILE_SIZE
    mu.layout_row(ctx, {74, 26, 26, -1}, 0)
    mu.label(ctx, "brush size")
    if .SUBMIT in mu.button(ctx, "-") { g_ed_brush_size = max(step, g_ed_brush_size - step) }
    if .SUBMIT in mu.button(ctx, "+") { g_ed_brush_size = min(512, g_ed_brush_size + step) }
    mu.label(ctx, fmt.tprintf("%d", g_ed_brush_size))

    mu.layout_row(ctx, {-1}, 34)
    mu.text(ctx, g_ed_tool == .Paint || g_ed_tool == .Erase ? "LMB paints, RMB erases." : "Painting is off: the Paint tool is not selected.")
}

@(private = "file") g_ed_grid_cols_f: mu.Real
@(private = "file") g_ed_grid_rows_f: mu.Real

editor_grid_window :: proc() {
    ctx := imui_ctx()

    if !mu.begin_window(ctx, "Grid & Camera", mu.Rect{16, ed_top() + 380, 214, 300}) { return }
    defer mu.end_window(ctx)

    mu.layout_row(ctx, {-1}, 0)
    mu.checkbox(ctx, "show grid  [G]", &g_ed_grid_visible)

    mu.layout_row(ctx, {74, 26, 26, -1}, 0)
    mu.label(ctx, "cell size")
    if .SUBMIT in mu.button(ctx, "-") { ed_set_cell_size(g_ed_cell_size - 16) }
    if .SUBMIT in mu.button(ctx, "+") { ed_set_cell_size(g_ed_cell_size + 16) }
    mu.label(ctx, fmt.tprintf("%d", g_ed_cell_size))

    g_ed_grid_cols_f = mu.Real(g_ed_grid_cols)
    g_ed_grid_rows_f = mu.Real(g_ed_grid_rows)

    mu.layout_row(ctx, {50, -1}, 0)
    mu.label(ctx, "grid X")
    if .CHANGE in mu.slider(ctx, &g_ed_grid_cols_f, 1, 200, 1, "%.0f") {
        g_ed_grid_cols = int(g_ed_grid_cols_f)
    }
    mu.label(ctx, "grid Y")
    if .CHANGE in mu.slider(ctx, &g_ed_grid_rows_f, 1, 200, 1, "%.0f") {
        g_ed_grid_rows = int(g_ed_grid_rows_f)
    }

    mu.layout_row(ctx, {-1}, 0)
    if .SUBMIT in mu.button(ctx, "reset grid (all walkable)") {
        ed_reset_grid_walkable()
    }

    mu.layout_row(ctx, {-1}, 26)
    mu.text(ctx, "Hold Shift while painting to snap the brush to the grid.")

    if .ACTIVE in mu.header(ctx, "camera bounds", {.EXPANDED}) {
        CAM_RANGE :: mu.Real(8192)
        mu.layout_row(ctx, {50, -1}, 0)
        mu.label(ctx, "min X"); mu.slider(ctx, &g_level_data.cam_lims[0], -CAM_RANGE, CAM_RANGE, 1, "%.0f")
        mu.label(ctx, "max X"); mu.slider(ctx, &g_level_data.cam_lims[1], -CAM_RANGE, CAM_RANGE, 1, "%.0f")
        mu.label(ctx, "min Y"); mu.slider(ctx, &g_level_data.cam_lims[2], -CAM_RANGE, CAM_RANGE, 1, "%.0f")
        mu.label(ctx, "max Y"); mu.slider(ctx, &g_level_data.cam_lims[3], -CAM_RANGE, CAM_RANGE, 1, "%.0f")

        mu.layout_row(ctx, {-1}, 0)
        if .SUBMIT in mu.button(ctx, "reset to level defaults") {
            g_level_data.cam_lims = {}
        }
    }

    mu.layout_row(ctx, {-1}, 0)
    mu.label(ctx, fmt.tprintf("zoom %.2fx   tiles %d", g_ed_zoom, len(g_tilemap)))
}

@(private = "file") g_ed_name_buf: [ED_NAME_LEN]u8
@(private = "file") g_ed_name_n:   int
@(private = "file") g_ed_name_for: int = -1

editor_levels_window :: proc() {
    ctx := imui_ctx()
    sh  := i32(rl.GetScreenHeight())

    if !mu.begin_window(ctx, "Levels", mu.Rect{240, ed_top(), 250, min(470, sh - ed_top() - 16)}) { return }
    defer mu.end_window(ctx)

    if g_ed_name_for != g_ed_level {
        g_ed_name_for = g_ed_level
        g_ed_name_n   = 0
        nm := &g_ed_level_names[g_ed_level]
        for g_ed_name_n < ED_NAME_LEN - 1 && nm[g_ed_name_n] != 0 {
            g_ed_name_buf[g_ed_name_n] = nm[g_ed_name_n]
            g_ed_name_n += 1
        }
    }

    mu.layout_row(ctx, {40, -1}, 0)
    mu.label(ctx, "name")
    if .CHANGE in mu.textbox(ctx, g_ed_name_buf[:], &g_ed_name_n) {
        nm := &g_ed_level_names[g_ed_level]
        nm^ = {}
        copy(nm[:ED_NAME_LEN - 1], g_ed_name_buf[:g_ed_name_n])
        ed_meta_save()
    }

    mu.layout_row(ctx, {103, -1}, 0)
    if .SUBMIT in mu.button(ctx, "save") {
        level_save(g_ed_level)
        ed_refresh_exists()
        g_ed_save_msg = 2.0
    }
    if .SUBMIT in mu.button(ctx, "load") {
        level_load(g_ed_level)
        p2p.session_send_level_load(&g_session, g_ed_level)
    }

    mu.layout_row(ctx, {-1}, 0)
    if .SUBMIT in mu.button(ctx, "clear level") { ed_clear_all() }

    mu.layout_row(ctx, {-1}, 0)
    if .SUBMIT in mu.button(ctx, "new level") {
        for i in 1..=ED_MAX_LEVELS {
            if g_ed_level_exists[i] { continue }
            g_ed_level = i
            ed_clear_all()
            level_save(g_ed_level)
            ed_refresh_exists()
            ed_rebuild_filtered()
            g_ed_save_msg = 2.0
            break
        }
    }

    if .ACTIVE in mu.header(ctx, fmt.tprintf("levels (%d)", g_ed_filtered_count), {.EXPANDED}) {
        for fi in 0..<g_ed_filtered_count {
            idx := g_ed_filtered[fi]
            mu.push_id(ctx, uintptr(idx) + 0x8000)
            mu.layout_row(ctx, {-1}, 0)
            mark := idx == g_ed_level ? ">" : " "
            if .SUBMIT in mu.button(ctx, fmt.tprintf("%s %02d  %s", mark, idx, ed_level_name(idx))) {
                g_ed_level = idx
                ed_rebuild_filtered()
                level_load(g_ed_level)
                p2p.session_send_level_load(&g_session, g_ed_level)
            }
            mu.pop_id(ctx)
        }
    }
}

@(private = "file")
ed_level_name :: proc(idx: int) -> string {
    nm := &g_ed_level_names[idx]
    n  := 0
    for n < ED_NAME_LEN && nm[n] != 0 { n += 1 }
    return n == 0 ? "(unnamed)" : string(nm[:n])
}

ed_top :: proc() -> i32 { return i32(uis(ED_BANNER_H)) + 8 }
