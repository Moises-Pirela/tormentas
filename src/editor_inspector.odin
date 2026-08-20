package main

import rl  "vendor:raylib"
import     "core:fmt"
import     "core:math"
import p2p "p2p"

EditorSelKind :: enum u8 {
    None       = 0,
    Switch     = 2,
    Container  = 3,
    LoreItem   = 4,
    Phonograph = 5,
    KeyPickup  = 6,
    NPC        = 9,
    Barrel     = 11,
}

EditorSelection :: struct {
    kind: EditorSelKind,
    tx:   i16,
    ty:   i16,
}

INSP_H     :: f32(206)
INSP_SPD   :: f32(14)
INSP_ROW_H :: f32(24)
INSP_PAD_X :: f32(10)
INSP_LBL_W :: f32(112)
INSP_VAL_W :: f32(52)
INSP_BTN_S :: f32(18)

@(private = "file") g_ed_sel:              EditorSelection
@(private = "file") g_ed_insp_anim:        f32
@(private = "file") g_ed_insp_text_active: bool
@(private = "file") g_ed_insp_text_fid:    u8

ed_insp_deselect :: proc() {
    g_ed_sel               = {}
    g_ed_insp_text_active  = false
}

ed_insp_is_text_active :: proc() -> bool {
    return g_ed_insp_text_active
}

ed_insp_has_selection :: proc() -> bool {
    return g_ed_sel.kind != .None
}

ed_insp_update_anim :: proc(dt: f32) {
    target := f32(1) if g_ed_sel.kind != .None else f32(0)
    g_ed_insp_anim += (target - g_ed_insp_anim) * min(dt * INSP_SPD, 1.0)
    if g_ed_insp_anim < 0.005 { g_ed_insp_anim = 0 }
}

ed_try_select_at :: proc(tx, ty: int) -> bool {
    itx, ity := i16(tx), i16(ty)
    for s  in g_level_data.switches    { if s.tx  == itx && s.ty  == ity { g_ed_sel = {.Switch,     itx, ity}; return true } }
    for c  in g_level_data.containers  { if c.tx  == itx && c.ty  == ity { g_ed_sel = {.Container,  itx, ity}; return true } }
    for li in g_level_data.lore_items  { if li.tx == itx && li.ty == ity { g_ed_sel = {.LoreItem,   itx, ity}; return true } }
    for ph in g_level_data.phonographs { if ph.tx == itx && ph.ty == ity { g_ed_sel = {.Phonograph, itx, ity}; return true } }
    for kp in g_level_data.key_pickups { if kp.tx == itx && kp.ty == ity { g_ed_sel = {.KeyPickup,  itx, ity}; return true } }
    for npc in g_level_data.npcs       { if npc.tx == itx && npc.ty == ity { g_ed_sel = {.NPC,      itx, ity}; return true } }
    for b  in g_level_data.barrels     { if b.tx  == itx && b.ty  == ity { g_ed_sel = {.Barrel,     itx, ity}; return true } }
    return false
}

ed_insp_validate :: proc() {
    if g_ed_sel.kind == .None { return }
    if !_insp_sel_exists() { g_ed_sel = {} }
}

ed_insp_over_ui :: proc() -> bool {
    if g_ed_insp_anim < 0.05 { return false }
    return rl.CheckCollisionPointRec(rl.GetMousePosition(), ed_insp_panel_rect())
}

ed_insp_panel_rect :: proc() -> rl.Rectangle {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    h  := uis(INSP_H) * g_ed_insp_anim
    return rl.Rectangle{
        x      = 0,
        y      = sh - h,
        width  = sw,
        height = h,
    }
}

ed_insp_draw_selection_highlight :: proc() {
    if g_ed_sel.kind == .None { return }
    tx := int(g_ed_sel.tx)
    ty := int(g_ed_sel.ty)
    center, top, right, bottom, left := iso_tile_bounds(tx, ty)

    pulse := 0.5 + 0.5 * math.sin_f32(f32(rl.GetTime()) * 5.0)
    alpha := u8(130 + u8(90.0 * pulse))
    lw    := 2.2 / g_camera.zoom

    rl.DrawTriangle(top, right, center,    rl.Color{60, 160, 240, 20})
    rl.DrawTriangle(right, bottom, center, rl.Color{60, 160, 240, 20})
    rl.DrawTriangle(bottom, left, center,  rl.Color{60, 160, 240, 20})
    rl.DrawTriangle(left, top, center,     rl.Color{60, 160, 240, 20})

    col := rl.Color{80, 200, 255, alpha}
    rl.DrawLineEx(top,    right,  lw * 2.5, col)
    rl.DrawLineEx(right,  bottom, lw * 2.5, col)
    rl.DrawLineEx(bottom, left,   lw * 2.5, col)
    rl.DrawLineEx(left,   top,    lw * 2.5, col)
}

ed_insp_draw_panel :: proc() {
    if g_ed_insp_anim < 0.005 { return }

    r  := ed_insp_panel_rect()
    mp := rl.GetMousePosition()

    rl.DrawRectangleRec(r, rl.Color{10, 8, 7, 248})
    rl.DrawRectangle(i32(r.x), i32(r.y), i32(r.width), i32(uis(2)),
        rl.Color{70, 170, 220, 210})
    rl.DrawRectangleLinesEx(r, uis(1), rl.Color{50, 90, 130, 160})

    if g_ed_sel.kind == .None { return }

    kind_cs := _insp_kind_name(g_ed_sel.kind)
    rl.DrawTextEx(g_font, kind_cs,
        {r.x + uis(INSP_PAD_X), r.y + uis(5)},
        uis(11), 0.5, rl.Color{80, 200, 255, 255})

    tile_buf: [24]u8
    tile_s := fmt.bprintf(tile_buf[:23], "  [%d, %d]", g_ed_sel.tx, g_ed_sel.ty)
    tile_buf[len(tile_s)] = 0
    km_sz := rl.MeasureTextEx(g_font, kind_cs, uis(11), 0.5)
    rl.DrawTextEx(g_font, cstring(&tile_buf[0]),
        {r.x + uis(INSP_PAD_X) + km_sz.x, r.y + uis(7)},
        uis(9), 0.5, rl.Color{110, 140, 165, 200})

    close_sz := uis(20)
    close_r  := rl.Rectangle{r.x + r.width - close_sz - uis(5), r.y + uis(3), close_sz, close_sz}
    hov_x    := rl.CheckCollisionPointRec(mp, close_r)
    rl.DrawRectangleRec(close_r, rl.Color{90, 30, 30, 210} if hov_x else rl.Color{42, 16, 16, 170})
    rl.DrawRectangleLinesEx(close_r, uis(1), rl.Color{180, 55, 55, 200})
    xsz := rl.MeasureTextEx(g_font, "X", uis(9), 0.5)
    rl.DrawTextEx(g_font, "X",
        {close_r.x + close_r.width*0.5 - xsz.x*0.5, close_r.y + close_r.height*0.5 - xsz.y*0.5},
        uis(9), 0.5, rl.Color{220, 80, 80, 245})

    if rl.IsMouseButtonPressed(.LEFT) && hov_x {
        ed_insp_deselect()
        return
    }

    sep_y := r.y + uis(28)
    rl.DrawRectangle(i32(r.x + uis(INSP_PAD_X)), i32(sep_y),
        i32(r.width - uis(INSP_PAD_X) * 2), 1, rl.Color{55, 95, 125, 120})

    cont_y0 := sep_y + uis(4)
    cont_x  := r.x + uis(INSP_PAD_X)
    cont_w  := r.width - uis(INSP_PAD_X) * 2

    rl.BeginScissorMode(i32(r.x), i32(cont_y0), i32(r.width), i32(r.y + r.height - cont_y0))

    cy := cont_y0

    eid := _insp_find_entity_id(g_ed_sel.tx, g_ed_sel.ty)
    eid_buf: [24]u8
    if eid != INVALID_ENTITY {
        s := fmt.bprintf(eid_buf[:23], "Entity ID:  #%d", eid)
        eid_buf[len(s)] = 0
    } else {
        s := fmt.bprintf(eid_buf[:23], "Entity ID:  —")
        eid_buf[len(s)] = 0
    }
    rl.DrawTextEx(g_font, cstring(&eid_buf[0]),
        {cont_x, cy + uis(INSP_ROW_H) * 0.5 - uis(4.5)},
        uis(9), 0.5, rl.Color{80, 110, 90, 185})

    cy_sep := cy + uis(INSP_ROW_H) * 0.85
    rl.DrawRectangle(i32(cont_x), i32(cy_sep), i32(cont_w), 1,
        rl.Color{50, 70, 55, 80})
    cy += uis(INSP_ROW_H) + uis(2)

    switch g_ed_sel.kind {
    case .None:
    case .Switch:     _insp_switch(mp, cont_x, &cy, cont_w)
    case .Container:  _insp_container(mp, cont_x, &cy, cont_w)
    case .LoreItem:   _insp_lore_item(mp, cont_x, &cy, cont_w)
    case .Phonograph: _insp_phonograph(mp, cont_x, &cy, cont_w)
    case .KeyPickup:  _insp_key_pickup(mp, cont_x, &cy, cont_w)
    case .NPC:        _insp_npc(mp, cont_x, &cy, cont_w)
    case .Barrel:     _insp_barrel(mp, cont_x, &cy, cont_w)
    }

    rl.EndScissorMode()
}

@(private = "file")
_insp_spin_u8 :: proc(mp: rl.Vector2, x: f32, cy: ^f32, w: f32,
                      label: cstring, val: ^u8, lo, hi: u8,
                      mk: u8, mf: u8) {
    h  := uis(INSP_ROW_H)
    y  := cy^
    rx := x + w

    rl.DrawTextEx(g_font, label, {x, y + h * 0.5 - uis(4.5)},
        uis(9), 0.5, rl.Color{158, 155, 148, 215})

    bsz := uis(INSP_BTN_S)
    vsz := uis(INSP_VAL_W)

    pr := rl.Rectangle{rx - bsz,                       y + h*0.5 - bsz*0.5, bsz, bsz}
    mr := rl.Rectangle{rx - bsz*2 - vsz - uis(2),     y + h*0.5 - bsz*0.5, bsz, bsz}
    vr := rl.Rectangle{mr.x + bsz + uis(1),            y + h*0.5 - bsz*0.5, vsz, bsz}

    hm := rl.CheckCollisionPointRec(mp, mr)
    hp := rl.CheckCollisionPointRec(mp, pr)

    _insp_draw_btn(mr, "-", rl.Color{220, 140, 80, 240}, hm)
    _insp_draw_val_box(vr, fmt.tprintf("%d", val^))
    _insp_draw_btn(pr, "+", rl.Color{90, 220, 120, 240}, hp)

    if rl.IsMouseButtonPressed(.LEFT) {
        if hm && val^ > lo { val^ -= 1; _insp_mod(mk, mf, u32(val^)) }
        if hp && val^ < hi { val^ += 1; _insp_mod(mk, mf, u32(val^)) }
    }
    cy^ += h + uis(2)
}

@(private = "file")
_insp_spin_u16 :: proc(mp: rl.Vector2, x: f32, cy: ^f32, w: f32,
                       label: cstring, val: ^u16, lo, hi: u16,
                       mk: u8, mf: u8) {
    h  := uis(INSP_ROW_H)
    y  := cy^
    rx := x + w
    bsz := uis(INSP_BTN_S)
    vsz := uis(INSP_VAL_W)

    rl.DrawTextEx(g_font, label, {x, y + h * 0.5 - uis(4.5)},
        uis(9), 0.5, rl.Color{158, 155, 148, 215})

    pr := rl.Rectangle{rx - bsz,                   y + h*0.5 - bsz*0.5, bsz, bsz}
    mr := rl.Rectangle{rx - bsz*2 - vsz - uis(2),  y + h*0.5 - bsz*0.5, bsz, bsz}
    vr := rl.Rectangle{mr.x + bsz + uis(1),         y + h*0.5 - bsz*0.5, vsz, bsz}

    hm := rl.CheckCollisionPointRec(mp, mr)
    hp := rl.CheckCollisionPointRec(mp, pr)

    _insp_draw_btn(mr, "-", rl.Color{220, 140, 80, 240}, hm)
    _insp_draw_val_box(vr, fmt.tprintf("%d", val^))
    _insp_draw_btn(pr, "+", rl.Color{90, 220, 120, 240}, hp)

    if rl.IsMouseButtonPressed(.LEFT) {
        if hm && val^ > lo { val^ -= 1; _insp_mod(mk, mf, u32(val^)) }
        if hp && val^ < hi { val^ += 1; _insp_mod(mk, mf, u32(val^)) }
    }
    cy^ += h + uis(2)
}


@(private = "file")
_insp_dropdown :: proc(mp: rl.Vector2, x: f32, cy: ^f32, w: f32,
                       label: cstring, val: ^u8, names: []cstring,
                       lo, hi: u8, mk: u8, mf: u8) {
    h  := uis(INSP_ROW_H)
    y  := cy^
    rx := x + w
    bsz := uis(INSP_BTN_S)

    rl.DrawTextEx(g_font, label, {x, y + h * 0.5 - uis(4.5)},
        uis(9), 0.5, rl.Color{158, 155, 148, 215})

    val_w := w - uis(INSP_LBL_W) - bsz * 2 - uis(6)
    pr  := rl.Rectangle{rx - bsz,                      y + h*0.5 - bsz*0.5, bsz, bsz}
    plr := rl.Rectangle{rx - bsz*2 - val_w - uis(2),   y + h*0.5 - bsz*0.5, bsz, bsz}
    vr  := rl.Rectangle{plr.x + bsz + uis(1),           y + h*0.5 - bsz*0.5, val_w, bsz}

    hpl := rl.CheckCollisionPointRec(mp, plr)
    hpr := rl.CheckCollisionPointRec(mp, pr)

    _insp_draw_btn(plr, "<", rl.Color{220, 140, 80, 240}, hpl)

    name_idx := clamp(int(val^) - int(lo), 0, len(names) - 1)
    name_cs  := names[name_idx] if name_idx >= 0 && name_idx < len(names) else cstring("?")
    _insp_draw_val_box(vr, string(name_cs))

    _insp_draw_btn(pr, ">", rl.Color{90, 220, 120, 240}, hpr)

    if rl.IsMouseButtonPressed(.LEFT) {
        if hpl && val^ > lo { val^ -= 1; _insp_mod(mk, mf, u32(val^)) }
        if hpr && val^ < hi { val^ += 1; _insp_mod(mk, mf, u32(val^)) }
    }
    cy^ += h + uis(2)
}

@(private = "file")
_insp_toggle :: proc(mp: rl.Vector2, x: f32, cy: ^f32, w: f32,
                     label: cstring, flags: ^u8, bit: u8,
                     mk: u8, mf: u8) {
    h  := uis(INSP_ROW_H)
    y  := cy^
    rx := x + w

    rl.DrawTextEx(g_font, label, {x, y + h * 0.5 - uis(4.5)},
        uis(9), 0.5, rl.Color{158, 155, 148, 215})

    on    := (flags^ & bit) != 0
    bsz   := uis(INSP_BTN_S)
    btn_r := rl.Rectangle{rx - bsz * 3.2, y + h*0.5 - bsz*0.5, bsz * 3.2, bsz}
    hov   := rl.CheckCollisionPointRec(mp, btn_r)

    bg  := rl.Color{22, 80, 42, 210} if on  else rl.Color{68, 22, 22, 185}
    brd := rl.Color{55, 180, 80, 200} if on  else rl.Color{155, 48, 48, 180}
    fg  := rl.Color{120, 230, 140, 245} if on else rl.Color{220, 100, 100, 240}
    if hov { bg.a = bg.a + 20 }

    rl.DrawRectangleRec(btn_r, bg)
    rl.DrawRectangleLinesEx(btn_r, uis(1), brd)
    lbl := cstring("ON") if on else cstring("OFF")
    lsz := rl.MeasureTextEx(g_font, lbl, uis(8), 0.5)
    rl.DrawTextEx(g_font, lbl,
        {btn_r.x + btn_r.width*0.5 - lsz.x*0.5, btn_r.y + btn_r.height*0.5 - lsz.y*0.5},
        uis(8), 0.5, fg)

    if rl.IsMouseButtonPressed(.LEFT) && hov {
        flags^ ~= bit
        _insp_mod(mk, mf, u32(flags^))
    }
    cy^ += h + uis(2)
}

@(private = "file")
_insp_draw_btn :: proc(r: rl.Rectangle, label: cstring, fg: rl.Color, hov: bool) {
    bg  := rl.Color{38, 32, 26, 190} if !hov else rl.Color{55, 46, 36, 210}
    brd := rl.Color{90, 78, 55, 160}
    rl.DrawRectangleRec(r, bg)
    rl.DrawRectangleLinesEx(r, uis(1), brd)
    lsz := rl.MeasureTextEx(g_font, label, uis(10), 0.5)
    rl.DrawTextEx(g_font, label,
        {r.x + r.width*0.5 - lsz.x*0.5, r.y + r.height*0.5 - lsz.y*0.5},
        uis(10), 0.5, fg)
}

@(private = "file")
_insp_draw_val_box :: proc(r: rl.Rectangle, val: string) {
    rl.DrawRectangleRec(r, rl.Color{18, 14, 10, 225})
    rl.DrawRectangleLinesEx(r, uis(1), rl.Color{72, 64, 46, 160})
    val_cs := fmt.ctprintf("%s", val)
    vsz := rl.MeasureTextEx(g_font, val_cs, uis(9), 0.5)
    rl.DrawTextEx(g_font, val_cs,
        {r.x + r.width*0.5 - vsz.x*0.5, r.y + r.height*0.5 - vsz.y*0.5},
        uis(9), 0.5, rl.Color{215, 195, 150, 240})
}

@(private = "file")
_insp_mod :: proc(kind: u8, field: u8, value: u32) {
    op := p2p.EditorModOp{
        tx    = g_ed_sel.tx,
        ty    = g_ed_sel.ty,
        kind  = kind,
        field = field,
        value = value,
    }
    p2p.session_send_editor_mod_op(&g_session, op)
}

ed_apply_mod_op :: proc(op: p2p.EditorModOp) {
    tx, ty := op.tx, op.ty
    switch EditorSelKind(op.kind) {
    case .None:
    case .Switch:
        for &s in g_level_data.switches {
            if s.tx == tx && s.ty == ty {
                switch op.field { case 0: s.link_id = u8(op.value); case 1: s.flags = u8(op.value) }
                return
            }
        }
    case .Container:
        for &c in g_level_data.containers {
            if c.tx == tx && c.ty == ty {
                switch op.field {
                case 0: c.kind          = ContainerKind(op.value)
                case 1: c.loot_table_id = u8(op.value)
                case 2: c.gold_min      = u16(op.value)
                case 3: c.gold_max      = u16(op.value)
                }
                return
            }
        }
    case .LoreItem:
        for &li in g_level_data.lore_items {
            if li.tx == tx && li.ty == ty { if op.field == 0 { li.lore_id = u8(op.value) }; return }
        }
    case .Phonograph:
        for &ph in g_level_data.phonographs {
            if ph.tx == tx && ph.ty == ty { if op.field == 0 { ph.recording_id = u8(op.value) }; return }
        }
    case .KeyPickup:
        for &kp in g_level_data.key_pickups {
            if kp.tx == tx && kp.ty == ty { if op.field == 0 { kp.key_id = u8(op.value) }; return }
        }
    case .NPC:
        for &npc in g_level_data.npcs {
            if npc.tx == tx && npc.ty == ty {
                if op.field == 0 { npc.npc_type = NPCType(op.value) }
                return
            }
        }
    case .Barrel:
        for &b in g_level_data.barrels {
            if b.tx == tx && b.ty == ty { if op.field == 0 { b.btype = u8(op.value) }; return }
        }
    }
}

@(private = "file")
_insp_switch :: proc(mp: rl.Vector2, x: f32, cy: ^f32, w: f32) {
    for &s in g_level_data.switches {
        if s.tx == g_ed_sel.tx && s.ty == g_ed_sel.ty {
            _insp_spin_u8(mp, x, cy, w, "Link ID (door)", &s.link_id, 0, 99, u8(EditorSelKind.Switch), 0)
            _insp_toggle(mp, x, cy, w, "Toggle mode",     &s.flags, 0x01,     u8(EditorSelKind.Switch), 1)
            _insp_toggle(mp, x, cy, w, "Pressure plate",  &s.flags, 0x02,     u8(EditorSelKind.Switch), 1)
            return
        }
    }
}

@(private = "file")
_insp_container :: proc(mp: rl.Vector2, x: f32, cy: ^f32, w: f32) {
    for &c in g_level_data.containers {
        if c.tx == g_ed_sel.tx && c.ty == g_ed_sel.ty {
            kind_val   := u8(c.kind)
            kind_names := []cstring{"Chest", "Crate", "Locker", "Cabinet"}
            _insp_dropdown(mp, x, cy, w, "Kind",       &kind_val, kind_names, 0, 3, u8(EditorSelKind.Container), 0)
            c.kind = ContainerKind(kind_val)

            _insp_spin_u8( mp, x, cy, w, "Loot Table",  &c.loot_table_id, 0, 255, u8(EditorSelKind.Container), 1)
            _insp_spin_u16(mp, x, cy, w, "Gold Min",    &c.gold_min,      0, 9999, u8(EditorSelKind.Container), 2)
            _insp_spin_u16(mp, x, cy, w, "Gold Max",    &c.gold_max,      0, 9999, u8(EditorSelKind.Container), 3)
            return
        }
    }
}

@(private = "file")
_insp_lore_item :: proc(mp: rl.Vector2, x: f32, cy: ^f32, w: f32) {
    for &li in g_level_data.lore_items {
        if li.tx == g_ed_sel.tx && li.ty == g_ed_sel.ty {
            _insp_spin_u8(mp, x, cy, w, "Lore ID", &li.lore_id, 1, 255, u8(EditorSelKind.LoreItem), 0)
            return
        }
    }
}

@(private = "file")
_insp_phonograph :: proc(mp: rl.Vector2, x: f32, cy: ^f32, w: f32) {
    for &ph in g_level_data.phonographs {
        if ph.tx == g_ed_sel.tx && ph.ty == g_ed_sel.ty {
            _insp_spin_u8(mp, x, cy, w, "Recording ID", &ph.recording_id, 1, 255, u8(EditorSelKind.Phonograph), 0)
            return
        }
    }
}

@(private = "file")
_insp_key_pickup :: proc(mp: rl.Vector2, x: f32, cy: ^f32, w: f32) {
    for &kp in g_level_data.key_pickups {
        if kp.tx == g_ed_sel.tx && kp.ty == g_ed_sel.ty {
            _insp_spin_u8(mp, x, cy, w, "Key ID", &kp.key_id, 1, 63, u8(EditorSelKind.KeyPickup), 0)
            return
        }
    }
}

@(private = "file")
_insp_npc :: proc(mp: rl.Vector2, x: f32, cy: ^f32, w: f32) {
    for &npc in g_level_data.npcs {
        if npc.tx == g_ed_sel.tx && npc.ty == g_ed_sel.ty {
            nt_val   := u8(npc.npc_type)
            nt_names := []cstring{"Shopkeeper", "Mutator", "Stash", "AbilityVendor"}
            _insp_dropdown(mp, x, cy, w, "NPC Type", &nt_val, nt_names, 0, 3, u8(EditorSelKind.NPC), 0)
            npc.npc_type = NPCType(nt_val)
            return
        }
    }
}

@(private = "file")
_insp_barrel :: proc(mp: rl.Vector2, x: f32, cy: ^f32, w: f32) {
    for &b in g_level_data.barrels {
        if b.tx == g_ed_sel.tx && b.ty == g_ed_sel.ty {
            bt_val   := b.btype
            bt_names := []cstring{"Fire", "Water"}
            _insp_dropdown(mp, x, cy, w, "Barrel Type", &bt_val, bt_names, 0, 1, u8(EditorSelKind.Barrel), 0)
            b.btype = bt_val
            return
        }
    }
}

@(private = "file")
_insp_find_entity_id :: proc(tx, ty: i16) -> int {
    if !g_sim_alive { return INVALID_ENTITY }
    w  := &g_sim.world
    wx := f32(int(tx) * TILE_SIZE + TILE_SIZE / 2)
    wy := f32(int(ty) * TILE_SIZE + TILE_SIZE / 2)
    for &e in w.entities {
        if !entity_is_active(e) { continue }
        if !world_has_component(w, e.id, .Transform) { continue }
        tr := comp_get(w, e.id, .Transform, TransformComp)
        if abs(tr.position.x - wx) < 0.5 && abs(tr.position.y - wy) < 0.5 {
            return e.id
        }
    }
    return INVALID_ENTITY
}

@(private = "file")
_insp_sel_exists :: proc() -> bool {
    tx, ty := g_ed_sel.tx, g_ed_sel.ty
    switch g_ed_sel.kind {
    case .None:      return false
    case .Switch:    for s  in g_level_data.switches    { if s.tx  == tx && s.ty  == ty { return true } }
    case .Container: for c  in g_level_data.containers  { if c.tx  == tx && c.ty  == ty { return true } }
    case .LoreItem:  for li in g_level_data.lore_items  { if li.tx == tx && li.ty == ty { return true } }
    case .Phonograph:for ph in g_level_data.phonographs { if ph.tx == tx && ph.ty == ty { return true } }
    case .KeyPickup: for kp in g_level_data.key_pickups { if kp.tx == tx && kp.ty == ty { return true } }
    case .NPC:       for npc in g_level_data.npcs       { if npc.tx == tx && npc.ty == ty { return true } }
    case .Barrel:    for b  in g_level_data.barrels     { if b.tx  == tx && b.ty  == ty { return true } }
    }
    return false
}

@(private = "file")
_insp_kind_name :: proc(k: EditorSelKind) -> cstring {
    switch k {
    case .None:       return "None"
    case .Switch:     return "Lever / Switch"
    case .Container:  return "Container"
    case .LoreItem:   return "Lore Item"
    case .Phonograph: return "Phonograph"
    case .KeyPickup:  return "Key Pickup"
    case .NPC:        return "NPC"
    case .Barrel:     return "Barrel"
    }
    return "?"
}
