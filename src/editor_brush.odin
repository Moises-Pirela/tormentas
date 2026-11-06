package main

import      "core:fmt"
import      "core:math"
import im   "../deps/imgui/imgui"
import rl   "vendor:raylib"

EdStrokeKind :: enum u8 { None, Paint, Erase, EraseObjects }

EdStroke :: struct {
    kind:      EdStrokeKind,
    button:    rl.MouseButton,
    has_last:  bool,
    last_cell: [2]int,
    cells:     map[[2]int]bool,
    tiles:     map[[2]int]bool,
    applied:   int,
}

g_ed_stroke: EdStroke

ed_stroke_active :: proc() -> bool { return g_ed_stroke.kind != .None }

ed_stroke_begin :: proc(kind: EdStrokeKind, button: rl.MouseButton) {
    s := &g_ed_stroke
    if s.cells == nil { s.cells = make(map[[2]int]bool) }
    if s.tiles == nil { s.tiles = make(map[[2]int]bool) }
    clear(&s.cells)
    clear(&s.tiles)
    s.kind     = kind
    s.button   = button
    s.has_last = false
    s.applied  = 0
}

ed_stroke_end :: proc() {
    g_ed_stroke.kind     = .None
    g_ed_stroke.has_last = false
}

ed_stroke_destroy :: proc() {
    delete(g_ed_stroke.cells)
    delete(g_ed_stroke.tiles)
    g_ed_stroke = {}
}

ed_brush_unit :: proc() -> int {
    return g_ed_cell_size if g_hub_active else TILE_SIZE
}

ed_mouse_cell :: proc() -> [2]int {
    wp := screen_to_world_cartesian(rl.GetMousePosition())
    u  := f32(ed_brush_unit())
    return { int(math.floor(wp.x / u)), int(math.floor(wp.y / u)) }
}

ed_tile_paint_is_noop :: proc(tx, ty: int, b: EditorBrush) -> bool {
    want_tile: TileType
    want_overlay := TileOverlay.None
    #partial switch b {
    case .Floor, .HubWalkable: want_tile = .Floor
    case .Wall, .HubCollision: want_tile = .Wall
    case .Water:   want_tile = .Water
    case .Pillar:  want_tile = .Pillar
    case .Floor1:  want_tile = .Floor1
    case .Floor2:  want_tile = .Floor2
    case .Floor3:  want_tile = .Floor3
    case .Floor4:  want_tile = .Floor4
    case .Wall1:   want_tile = .Wall1
    case .Wall2:   want_tile = .Wall2
    case .Wall3:   want_tile = .Wall3
    case .Pillar1: want_tile = .Pillar1
    case .Pillar2: want_tile = .Pillar2
    case .Oil:     want_tile = .Floor; want_overlay = .Oil
    case .Fire:    want_tile = .Floor; want_overlay = .Fire
    case:          return false
    }
    return tile_exists(tx, ty) && tile_at(tx, ty) == want_tile && overlay_at(tx, ty) == want_overlay
}

@(private = "file")
_stamp :: proc(cell: [2]int) {
    s := &g_ed_stroke
    unit := ed_brush_unit()
    fx, fy, n := ed_brush_footprint(cell[0], cell[1], unit, ed_paint_snap_held())
    for dy in 0..<n {
        for dx in 0..<n {
            c := [2]int{ fx + dx, fy + dy }
            if c in s.cells { continue }
            s.cells[c] = true
            s.applied += ed_stroke_apply_cell(c, s.kind, &s.tiles)
        }
    }
}

ed_stroke_update :: proc(cell: [2]int) {
    s := &g_ed_stroke
    if s.kind == .None { return }
    if !s.has_last {
        s.last_cell = cell
        s.has_last  = true
        _stamp(cell)
        return
    }
    if cell == s.last_cell { return }

    x0, y0 := s.last_cell[0], s.last_cell[1]
    x1, y1 := cell[0], cell[1]
    dx := abs(x1 - x0)
    dy := -abs(y1 - y0)
    sx := 1 if x0 < x1 else -1
    sy := 1 if y0 < y1 else -1
    err := dx + dy
    for steps := 0; steps < 4096; steps += 1 {
        if x0 == x1 && y0 == y1 { break }
        e2 := 2 * err
        if e2 >= dy { err += dy; x0 += sx }
        if e2 <= dx { err += dx; y0 += sy }
        _stamp({ x0, y0 })
    }
    s.last_cell = cell
}

ed_brush_display_color :: proc(c: rl.Color) -> rl.Color {
    lum := 0.3 * f32(c.r) + 0.59 * f32(c.g) + 0.11 * f32(c.b)
    if lum >= 150 { return c }
    k := clamp((170 - lum) / 170, 0, 1) * 0.85
    return {
        u8(f32(c.r) + (255 - f32(c.r)) * k), u8(f32(c.g) + (255 - f32(c.g)) * k),
        u8(f32(c.b) + (255 - f32(c.b)) * k), 255,
    }
}

ed_brush_label_full :: proc() -> (name: string, col: rl.Color) {
    if g_ed_stroke.kind == .EraseObjects { return "Erase objects", rl.Color{ 235, 85, 75, 255 } }
    if g_ed_tool == .Erase || g_ed_stroke.kind == .Erase { return "Erase", rl.Color{ 235, 85, 75, 255 } }
    _, raw := ed_brush_colors(g_ed_brush)
    brd := ed_brush_display_color(raw)
    if g_ed_brush == .Module {
        if module_count() > 0 { return fmt.tprintf("Module: %s", module_name(g_ed_module_idx)), brd }
        return "Module (none loaded)", brd
    }
    return ed_brush_label(g_ed_brush), brd
}

@(private = "file")
_iso_quad :: proc(x0, y0, x1, y1: f32) -> [4]rl.Vector2 {
    return { world_to_iso_xy(x0, y0), world_to_iso_xy(x1, y0), world_to_iso_xy(x1, y1), world_to_iso_xy(x0, y1) }
}

@(private = "file")
_fill_quad :: proc(q: [4]rl.Vector2, col: rl.Color) {
    rl.DrawTriangle(q[0], q[2], q[1], col)
    rl.DrawTriangle(q[0], q[3], q[2], col)
}

@(private = "file")
_outline_quad :: proc(q: [4]rl.Vector2, thick: f32, col: rl.Color) {
    for i in 0..<4 { rl.DrawLineEx(q[i], q[(i + 1) % 4], thick, col) }
}

ed_brush_cursor_visible :: proc() -> bool {
    if !g_editor_mode || devui_wants_mouse() { return false }
    return g_ed_tool == .Paint || g_ed_tool == .Erase
}

draw_editor_brush_world :: proc() {
    if !ed_brush_cursor_visible() { return }
    lw   := 1.0 / g_camera.zoom
    unit := ed_brush_unit()
    u    := f32(unit)
    cell := ed_mouse_cell()

    if g_ed_brush == .Module && g_ed_tool == .Paint && !g_hub_active {
        if module_count() > 0 { module_draw_ghost(g_ed_module_idx, cell[0], cell[1]) }
        q := _iso_quad(f32(cell[0]) * u, f32(cell[1]) * u, f32(cell[0] + 1) * u, f32(cell[1] + 1) * u)
        _outline_quad(q, lw * 2, rl.Color{ 90, 150, 230, 230 })
        return
    }

    fx, fy, n := ed_brush_footprint(cell[0], cell[1], unit, ed_paint_snap_held())
    _, col := ed_brush_label_full()
    active := ed_stroke_active()
    pulse  := 0.5 + 0.5 * math.sin(f32(rl.GetTime()) * 6)
    fill_a := u8(70 + 50 * pulse) if !active else u8(140)
    q := _iso_quad(f32(fx) * u, f32(fy) * u, f32(fx + n) * u, f32(fy + n) * u)
    _fill_quad(q, rl.Color{ col.r, col.g, col.b, fill_a })

    if n > 1 && f32(unit) * g_camera.zoom >= 6 {
        inner := rl.Color{ 0, 0, 0, 90 }
        for i in 1..<n {
            a := world_to_iso_xy(f32(fx + i) * u, f32(fy) * u)
            b := world_to_iso_xy(f32(fx + i) * u, f32(fy + n) * u)
            rl.DrawLineEx(a, b, lw, inner)
            c := world_to_iso_xy(f32(fx) * u, f32(fy + i) * u)
            d := world_to_iso_xy(f32(fx + n) * u, f32(fy + i) * u)
            rl.DrawLineEx(c, d, lw, inner)
        }
    }
    halo := _iso_quad(f32(fx) * u - 1.5 * lw, f32(fy) * u - 1.5 * lw, f32(fx + n) * u + 1.5 * lw, f32(fy + n) * u + 1.5 * lw)
    _outline_quad(halo, lw * 4.5, rl.Color{ 0, 0, 0, 140 })
    _outline_quad(q, lw * (3.0 if active else 2.2), rl.Color{ col.r, col.g, col.b, 255 })
}

@(private = "file")
_u32 :: proc(c: rl.Color) -> u32 {
    return u32(c.r) | u32(c.g) << 8 | u32(c.b) << 16 | u32(c.a) << 24
}

ed_screen_label :: proc(dl: ^im.DrawList, pos: im.Vec2, text: cstring, col: rl.Color, swatch := false) {
    ts  := im.CalcTextSize(text)
    pad := im.Vec2{ 6, 3 }
    sw  := f32(10) if swatch else 0
    bx  := pos.x
    by  := pos.y
    bw  := ts.x + pad.x * 2 + (sw + 5 if swatch else 0)
    im.DrawList_AddRectFilled(dl, { bx, by }, { bx + bw, by + ts.y + pad.y * 2 }, 0xd8_0e_0c_0a, 3)
    im.DrawList_AddRect(dl, { bx, by }, { bx + bw, by + ts.y + pad.y * 2 }, _u32({ col.r, col.g, col.b, 200 }), 3, 1)
    tx := bx + pad.x
    if swatch {
        cy := by + pad.y + ts.y * 0.5
        im.DrawList_AddRectFilled(dl, { tx, cy - sw * 0.5 }, { tx + sw, cy + sw * 0.5 }, _u32(col), 2)
        tx += sw + 5
    }
    im.DrawList_AddText(dl, { tx, by + pad.y }, 0xff_e6_ee_f2, text)
}

ed_world_to_screen :: proc(wx, wy: f32) -> im.Vec2 {
    p := rl.GetWorldToScreen2D(world_to_iso_xy(wx, wy), g_camera^)
    return { p.x, p.y }
}

draw_editor_overlay_screen :: proc() {
    if !g_editor_mode { return }
    dl := im.GetBackgroundDrawList()
    mp := rl.GetMousePosition()
    over_ui := devui_wants_mouse()

    ed_gizmo_draw(dl)

    if over_ui { return }
    at := im.Vec2{ mp.x + 18, mp.y + 14 }

    switch g_ed_tool {
    case .Paint, .Erase:
        name, col := ed_brush_label_full()
        unit := ed_brush_unit()
        _, _, n := ed_brush_footprint(0, 0, unit, ed_paint_snap_held())
        what := "cells" if g_hub_active else "tiles"
        snap := "  snap" if ed_paint_snap_held() else ""
        text := fmt.ctprintf("%s   %dx%d %s%s", name, n, n, what, snap)
        if g_ed_brush == .Module && g_ed_tool == .Paint && !g_hub_active { text = fmt.ctprintf("%s", name) }
        ed_screen_label(dl, at, text, col, true)
        if ed_stroke_active() && g_ed_stroke.applied > 0 {
            ui_c := fmt.ctprintf("%d changed", g_ed_stroke.applied)
            ed_screen_label(dl, { at.x, at.y + 24 }, ui_c, col)
        }
    case .Place:
        if len(g_entity_defs) > 0 {
            idx := clamp(g_ed_def_idx, 0, len(g_entity_defs) - 1)
            ed_place_preview(dl)
            ed_screen_label(dl, at, fmt.ctprintf("Place  %s%s", g_entity_defs[idx].name, "  snap" if g_ed_snap else ""), rl.Color{ 120, 200, 255, 255 })
        }
    case .Select:
        if !ed_gizmo_dragging() && ed_gizmo_hover() == .None {
            if hi := ed_entity_pick(mp); hi >= 0 && hi != g_ed_sel_entity {
                e  := &g_level_data.entities[hi]
                sp := ed_world_to_screen(e.position[0], e.position[1])
                im.DrawList_AddCircle(dl, sp, ENTITY_PICK_R, 0xc0_ff_d8_80, 32, 2)
                ed_screen_label(dl, { sp.x + 16, sp.y - 34 }, fmt.ctprintf("%s", e.def), rl.Color{ 255, 216, 128, 255 })
                im.SetMouseCursor(.Hand)
            }
        }
    }
}

ed_place_preview :: proc(dl: ^im.DrawList) {
    wp  := screen_to_world_cartesian(rl.GetMousePosition())
    pos := [2]f32{ wp.x, wp.y }
    if g_ed_snap {
        pos[0] = math.round(wp.x / f32(TILE_SIZE)) * f32(TILE_SIZE)
        pos[1] = math.round(wp.y / f32(TILE_SIZE)) * f32(TILE_SIZE)
    }
    h  := f32(TILE_SIZE) * 0.5
    pts := [4]im.Vec2{
        ed_world_to_screen(pos[0] - h, pos[1] - h), ed_world_to_screen(pos[0] + h, pos[1] - h),
        ed_world_to_screen(pos[0] + h, pos[1] + h), ed_world_to_screen(pos[0] - h, pos[1] + h),
    }
    im.DrawList_AddQuadFilled(dl, pts[0], pts[1], pts[2], pts[3], 0x40_ff_c8_78)
    for i in 0..<4 { im.DrawList_AddLine(dl, pts[i], pts[(i + 1) % 4], 0xe0_ff_c8_78, 2) }
    c := ed_world_to_screen(pos[0], pos[1])
    im.DrawList_AddCircleFilled(dl, c, 4, 0xff_ff_e0_a0)
}
