package main

import im  "../deps/imgui/imgui"
import rl  "vendor:raylib"
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

@(private = "file") g_ed_sel: EditorSelection

ed_insp_deselect :: proc() {
    g_ed_sel = {}
}

ed_insp_has_selection :: proc() -> bool {
    return g_ed_sel.kind != .None
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

ed_insp_object_ui :: proc() {
    if g_ed_sel.kind == .None { return }
    ui_text_col(DEVUI_GOLD, "%s", _insp_kind_name(g_ed_sel.kind))
    im.SameLine()
    ui_hint("tile %d, %d", g_ed_sel.tx, g_ed_sel.ty)
    if eid := _insp_find_entity_id(g_ed_sel.tx, g_ed_sel.ty); eid != INVALID_ENTITY {
        ui_hint("live entity #%d", eid)
    } else {
        ui_hint("no live entity")
    }
    im.Separator()

    tx, ty := g_ed_sel.tx, g_ed_sel.ty
    switch g_ed_sel.kind {
    case .None:
    case .Switch:
        for &sw in g_level_data.switches {
            if sw.tx != tx || sw.ty != ty { continue }
            if ui_input_u8("Link ID (door)", &sw.link_id, 0, 99) { _insp_mod(u8(EditorSelKind.Switch), 0, u32(sw.link_id)) }
            if ui_toggle_bit("Toggle mode", &sw.flags, 0x01)     { _insp_mod(u8(EditorSelKind.Switch), 1, u32(sw.flags)) }
            if ui_toggle_bit("Pressure plate", &sw.flags, 0x02)  { _insp_mod(u8(EditorSelKind.Switch), 1, u32(sw.flags)) }
            break
        }
    case .Container:
        for &c in g_level_data.containers {
            if c.tx != tx || c.ty != ty { continue }
            kind := u8(c.kind)
            if ui_combo_u8("Kind", &kind, { "Chest", "Crate", "Locker", "Cabinet" }) {
                c.kind = ContainerKind(kind)
                _insp_mod(u8(EditorSelKind.Container), 0, u32(kind))
            }
            if ui_input_u8("Loot table", &c.loot_table_id, 0, 255) { _insp_mod(u8(EditorSelKind.Container), 1, u32(c.loot_table_id)) }
            if ui_input_u16("Gold min", &c.gold_min, 0, 9999)      { _insp_mod(u8(EditorSelKind.Container), 2, u32(c.gold_min)) }
            if ui_input_u16("Gold max", &c.gold_max, 0, 9999)      { _insp_mod(u8(EditorSelKind.Container), 3, u32(c.gold_max)) }
            if c.gold_max < c.gold_min { ui_text_col(DEVUI_RED, "Gold max is below gold min.") }
            break
        }
    case .LoreItem:
        for &li in g_level_data.lore_items {
            if li.tx != tx || li.ty != ty { continue }
            if ui_input_u8("Lore ID", &li.lore_id, 1, 255) { _insp_mod(u8(EditorSelKind.LoreItem), 0, u32(li.lore_id)) }
            break
        }
    case .Phonograph:
        for &ph in g_level_data.phonographs {
            if ph.tx != tx || ph.ty != ty { continue }
            if ui_input_u8("Recording ID", &ph.recording_id, 1, 255) { _insp_mod(u8(EditorSelKind.Phonograph), 0, u32(ph.recording_id)) }
            break
        }
    case .KeyPickup:
        for &kp in g_level_data.key_pickups {
            if kp.tx != tx || kp.ty != ty { continue }
            if ui_input_u8("Key ID", &kp.key_id, 1, 63) { _insp_mod(u8(EditorSelKind.KeyPickup), 0, u32(kp.key_id)) }
            break
        }
    case .NPC:
        for &npc in g_level_data.npcs {
            if npc.tx != tx || npc.ty != ty { continue }
            nt := u8(npc.npc_type)
            if ui_combo_u8("NPC type", &nt, { "Shopkeeper", "Mutator", "Stash", "Ability vendor" }) {
                npc.npc_type = NPCType(nt)
                _insp_mod(u8(EditorSelKind.NPC), 0, u32(nt))
            }
            break
        }
    case .Barrel:
        for &b in g_level_data.barrels {
            if b.tx != tx || b.ty != ty { continue }
            if ui_combo_u8("Barrel type", &b.btype, { "Fire", "Water" }) { _insp_mod(u8(EditorSelKind.Barrel), 0, u32(b.btype)) }
            break
        }
    }

    im.Spacing()
    if im.Button("Deselect") { ed_insp_deselect() }
    ui_tooltip("Escape")
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
_insp_kind_name :: proc(k: EditorSelKind) -> string {
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
