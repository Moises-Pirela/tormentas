package main

import "core:fmt"
import rl   "vendor:raylib"
import clay "../clay"

g_drag_item_id:      int          = -1
g_drag_origin_x:     int          = -1
g_drag_origin_y:     int          = -1
g_drag_from_equip:   bool         = false
g_drag_from_stash:   bool         = false
g_drag_origin_equip: EquipSlot = {}
g_hover_item_id:     int          = INVALID_ENTITY
g_inv_backpack_bb:   clay.BoundingBox

@(private = "file")
_SLOT_CLAY_ID := [EQUIP_SLOT_COUNT]string{
    "InvSlotHead",
    "InvSlotChest",
    "InvSlotBoots",
    "InvSlotWep1",
    "InvSlotWep2",
    "",
    "InvSlotAbil1",
    "InvSlotAbil2",
    "InvSlotAbil3",
    "InvSlotAbil4",
    "InvSlotFlask1",
    "InvSlotFlask2",
}

@(private = "file")
_item_fits_slot :: proc(item_slot: EquipSlot, target: EquipSlot) -> bool {
    is_wep_item   := item_slot == .WeaponPrimary || item_slot == .WeaponOffhand
    is_wep_target := target   == .WeaponPrimary
    if is_wep_item { return is_wep_target }

    is_ab_item   := item_slot == .Ability1 || item_slot == .Ability2 ||
                    item_slot == .Ability3 || item_slot == .Ability4
    is_ab_target := target   == .Ability1 || target   == .Ability2 ||
                    target   == .Ability3 || target   == .Ability4
    if is_ab_item { return is_ab_target }

    is_flask_item   := item_slot == .Flask1 || item_slot == .Flask2
    is_flask_target := target   == .Flask1 || target   == .Flask2
    if is_flask_item { return item_slot == target }
    if is_flask_target { return false }

    return item_slot == target
}

@(private = "file")
_flask_name_buf: [48]u8

_inv_slot_name :: proc(w: ^World, inv: ^InventoryComp, slot: EquipSlot) -> (cstring, bool) {
    if inv == nil { return t(.INV_UNEQUIPPED), false }
    eid := inv.equipped[int(slot)]
    if !world_is_valid(w, eid) { return t(.INV_UNEQUIPPED), false }
    if world_has_component(w, eid, .RenderConfig) {
        return loc_lookup(render_config_name_cstr(comp_get(w, eid, .RenderConfig, RenderConfigComp))), true
    }

    if world_has_component(w, eid, .Flask) {
        fc := comp_get(w, eid, .Flask, FlaskComp)
        size_names := [FlaskSize]string{ .Small="Small", .Medium="Medium", .Large="Large" }
        kind_names := [FlaskKind]string{ .Health="Health", .Energy="Energy" }
        s := fmt.bprintf(_flask_name_buf[:47], "%s %s Flask",
            size_names[fc.size], kind_names[fc.kind])
        _flask_name_buf[len(s)] = 0
        return cstring(&_flask_name_buf[0]), true
    }
    return "???", true
}

@(private = "file")
_inv_is_target :: proc(inv: ^InventoryComp, drag_slot: EquipSlot, target: EquipSlot) -> bool {
    if inv == nil || g_drag_item_id == -1 { return false }
    return _item_fits_slot(drag_slot, target)
}

@(private = "file")
_inv_mouse_to_cell :: proc(grid_bb: clay.BoundingBox, mx, my: f32) -> (col, row: int, ok: bool) {
    if grid_bb.width == 0 { return 0, 0, false }
    c := int(mx - grid_bb.x) / int(g_inv.cell_sz)
    r := int(my - grid_bb.y) / int(g_inv.cell_sz)
    if c < 0 || c >= BACKPACK_COLS { return 0, 0, false }
    if r < 0 || r >= BACKPACK_ROWS { return 0, 0, false }
    return c, r, true
}

draw_item_glyph :: proc(slot: EquipSlot, x, y, sz: i32, tint: rl.Color) {
    cx  := f32(x) + f32(sz) * 0.5
    cy  := f32(y) + f32(sz) * 0.5
    col := rl.Color{ tint.r, tint.g, tint.b, 200 }
    dim := rl.Color{ tint.r / 2, tint.g / 2, tint.b / 2, 180 }
    r   := f32(sz) * 0.5

    switch slot {
    case .Head:
        rl.DrawCircleV({ cx, cy - r * 0.1 }, r * 0.42, dim)
        rl.DrawCircleV({ cx, cy - r * 0.1 }, r * 0.28, col)
        rl.DrawRectangle(x + sz/4, y + sz*3/4 - 2, sz/2, sz/8 + 1, col)

    case .Chest:
        bw := i32(r * 0.9)
        bh := i32(r * 1.1)
        bx := x + (sz - bw) / 2
        by := y + (sz - bh) / 2 + 2
        rl.DrawRectangle(bx, by, bw, bh, dim)
        rl.DrawRectangle(bx + 2, by + 2, bw - 4, bh - 4, col)
        nub := i32(r * 0.25)
        rl.DrawRectangle(bx - nub, by, nub, nub * 2, col)
        rl.DrawRectangle(bx + bw, by, nub, nub * 2, col)

    case .Boots:
        bw    := i32(r * 0.38)
        bh    := i32(r * 0.7)
        gap   := i32(r * 0.1)
        total := bw * 2 + gap
        lx    := x + (sz - total) / 2
        by    := y + (sz - bh) / 2 + i32(r * 0.15)
        rl.DrawRectangle(lx,            by, bw, bh, col)
        rl.DrawRectangle(lx + bw + gap, by, bw, bh, col)
        rl.DrawRectangle(lx,            by, bw, bh / 4, dim)
        rl.DrawRectangle(lx + bw + gap, by, bw, bh / 4, dim)

    case .WeaponPrimary:
        blen  := i32(r * 0.9)
        bx    := x + (sz - blen) / 2
        by    := y + sz / 2 - 3
        rl.DrawRectangle(bx, by, blen, 5, col)
        grip_x := bx + blen / 2
        rl.DrawRectangle(grip_x, by + 5, 6, i32(r * 0.5), dim)

    case .WeaponOffhand:
        sw := i32(r * 0.7)
        sh := i32(r * 0.9)
        sx := x + (sz - sw) / 2
        sy := y + (sz - sh) / 2
        rl.DrawRectangle(sx, sy, sw, sh, dim)
        rl.DrawRectangle(sx + 2, sy + 2, sw - 4, sh - 4, col)
        rl.DrawRectangle(sx + sw/2 - 1, sy + 4, 2, sh - 8, dim)
        rl.DrawRectangle(sx + 4, sy + sh/3, sw - 8, 2, dim)

    case .Consumable:
        rl.DrawCircleV({ cx, cy }, r * 0.38, dim)
        rl.DrawCircleV({ cx, cy }, r * 0.26, col)

    case .Ability1, .Ability2, .Ability3, .Ability4:
        hw := i32(r * 0.28)
        rl.DrawRectangle(x + sz/2 - hw/2, y + sz/4,    hw, i32(r * 0.6), col)
        rl.DrawRectangle(x + sz/2,        y + sz/2 - 2, hw, i32(r * 0.6), dim)

    case .Flask1, .Flask2:

        neck_w := i32(r * 0.22)
        body_w := i32(r * 0.54)
        neck_h := i32(r * 0.30)
        body_h := i32(r * 0.70)
        nx := x + (sz - neck_w) / 2
        ny := y + i32(r * 0.14)
        bx := x + (sz - body_w) / 2
        by := ny + neck_h
        rl.DrawRectangle(nx, ny, neck_w, neck_h, col)
        rl.DrawRectangle(bx, by, body_w, body_h, dim)
        rl.DrawRectangle(bx + 2, by + 2, body_w - 4, body_h - 4, col)

        rl.DrawRectangle(nx - 2, ny - i32(r * 0.12), neck_w + 4, i32(r * 0.12), col)
    }
}

@(private = "file")
_draw_backpack_raw :: proc(w: ^World, inv: ^InventoryComp, grid_bb: clay.BoundingBox) {
    if grid_bb.width == 0 { return }
    gx := i32(grid_bb.x)
    gy := i32(grid_bb.y)
    cs := g_inv.cell_sz

    for r in 0..<i32(BACKPACK_ROWS) {
        for c in 0..<i32(BACKPACK_COLS) {
            cx := gx + c * cs
            cy := gy + r * cs
            rl.DrawRectangle(cx, cy, cs, cs, rl.Color{ 8, 6, 4, 255 })
            rl.DrawRectangle(cx + 1, cy + 1, cs - 2, cs - 2, rl.Color{ 18, 14, 10, 255 })
            rl.DrawLineEx({ f32(cx + 1), f32(cy + 1) }, { f32(cx + cs - 1), f32(cy + 1) },
                1, rl.Color{ 0, 0, 0, 80 })
            rl.DrawLineEx({ f32(cx + 1), f32(cy + 1) }, { f32(cx + 1), f32(cy + cs - 1) },
                1, rl.Color{ 0, 0, 0, 80 })
        }
    }

    grid_w := i32(BACKPACK_COLS) * cs
    grid_h := i32(BACKPACK_ROWS) * cs
    for c in 0..=i32(BACKPACK_COLS) {
        lx := f32(gx + c * cs)
        rl.DrawLineEx({ lx, f32(gy) }, { lx, f32(gy + grid_h) }, 1, COL_RULE)
    }
    for r in 0..=i32(BACKPACK_ROWS) {
        ly := f32(gy + r * cs)
        rl.DrawLineEx({ f32(gx), ly }, { f32(gx + grid_w), ly }, 1, COL_RULE)
    }

    if inv == nil { return }

    if g_drag_item_id != -1 && world_is_valid(w, g_drag_item_id) {
        mp            := rl.GetMousePosition()
        drag_item     := comp_get(w, g_drag_item_id, .Item, ItemComp)
        col, row, hit := _inv_mouse_to_cell(grid_bb, mp.x, mp.y)
        if hit {
            can    := backpack_can_place(inv, drag_item, col, row)
            hi_col := rl.Color{ 60, 180, 60, 80 } if can else rl.Color{ 180, 40, 40, 80 }
            for dy in 0..<drag_item.grid_h {
                for dx in 0..<drag_item.grid_w {
                    if col+dx < BACKPACK_COLS && row+dy < BACKPACK_ROWS {
                        rl.DrawRectangle(
                            gx + i32(col+dx) * cs,
                            gy + i32(row+dy) * cs,
                            cs, cs, hi_col)
                    }
                }
            }
        }
    }

    for row in 0..<BACKPACK_ROWS {
        for col in 0..<BACKPACK_COLS {
            cell_id := inv.backpack[row * BACKPACK_COLS + col]
            if cell_id == INVALID_ENTITY  { continue }
            if cell_id == g_drag_item_id     { continue }
            if !world_is_valid(w, cell_id){ continue }
            item := comp_get(w, cell_id, .Item, ItemComp)
            if item.pack_x != col || item.pack_y != row { continue }

            rc := rarity_color(item.rarity)
            ix := gx + i32(col) * cs + 2
            iy := gy + i32(row) * cs + 2
            iw := i32(item.grid_w) * cs - 4
            ih := i32(item.grid_h) * cs - 4

            rl.DrawRectangle(ix, iy, iw, ih,
                rl.Color{ rc.r / 5, rc.g / 5, rc.b / 5, 230 })
            rl.DrawRectangleLinesEx({ f32(ix), f32(iy), f32(iw), f32(ih) }, 1,
                rl.Color{ rc.r, rc.g, rc.b, 220 })

            icon_margin :: i32(3)
            icon_sz      := min(iw, ih) - icon_margin * 2
            icon_drawn   := false

            if world_has_component(w, cell_id, .RenderConfig) {
                rcc := comp_get(w, cell_id, .RenderConfig, RenderConfigComp)
                if rcc.icon_len > 0 {
                    tex, ok := get_or_load_icon(render_config_icon_cstr(rcc))
                    if ok {
                        iicon_x := ix + (iw - icon_sz) / 2
                        iicon_y := iy + icon_margin
                        src := rl.Rectangle{ 0, 0, f32(tex.width), f32(tex.height) }
                        dst := rl.Rectangle{ f32(iicon_x), f32(iicon_y),
                                             f32(icon_sz), f32(icon_sz) }
                        rl.DrawTexturePro(tex, src, dst, {0, 0}, 0,
                            rl.Color{ rc.r, rc.g, rc.b, 210 })
                        icon_drawn = true
                    }
                }
            }
            if !icon_drawn {
                draw_item_glyph(item.slot,
                    ix + (iw - icon_sz) / 2, iy + icon_margin, icon_sz, rc)
            }

            if world_has_component(w, cell_id, .RenderConfig) {
                rcc  := comp_get(w, cell_id, .RenderConfig, RenderConfigComp)
                name := loc_lookup(render_config_name_cstr(rcc))
                rl.DrawTextEx(g_font_body, name,
                    { f32(ix) + uis(3), f32(iy + icon_margin + icon_sz + 2) },
                    uis(11), 0.4, rl.Color{ rc.r, rc.g, rc.b, 200 })
            }
        }
    }
}

_draw_drag_item :: proc(w: ^World) {
    if g_drag_item_id == -1 || !world_is_valid(w, g_drag_item_id) { return }
    mp   := rl.GetMousePosition()
    item := comp_get(w, g_drag_item_id, .Item, ItemComp)
    cs   := g_inv.cell_sz

    iw := i32(item.grid_w) * cs - 4
    ih := i32(item.grid_h) * cs - 4
    fx := i32(mp.x) - iw / 2
    fy := i32(mp.y) - ih / 2

    rc := rarity_color(item.rarity)
    rl.DrawRectangle(fx, fy, iw, ih,
        rl.Color{ rc.r / 5, rc.g / 5, rc.b / 5, 230 })
    rl.DrawRectangleLinesEx({ f32(fx), f32(fy), f32(iw), f32(ih) }, 1,
        rl.Color{ rc.r, rc.g, rc.b, 240 })

    drag_icon_sz    := min(iw, ih) - 6
    drag_icon_x     := fx + (iw - drag_icon_sz) / 2
    drag_icon_y     := fy + (ih - drag_icon_sz) / 2
    drag_icon_drawn := false

    if world_has_component(w, g_drag_item_id, .RenderConfig) {
        rcc := comp_get(w, g_drag_item_id, .RenderConfig, RenderConfigComp)
        if rcc.icon_len > 0 {
            tex, ok := get_or_load_icon(render_config_icon_cstr(rcc))
            if ok {
                src := rl.Rectangle{ 0, 0, f32(tex.width), f32(tex.height) }
                dst := rl.Rectangle{
                    f32(drag_icon_x), f32(drag_icon_y),
                    f32(drag_icon_sz), f32(drag_icon_sz) }
                rl.DrawTexturePro(tex, src, dst, {0, 0}, 0,
                    rl.Color{ rc.r, rc.g, rc.b, 210 })
                drag_icon_drawn = true
            }
        }
    }
    if !drag_icon_drawn {
        draw_item_glyph(item.slot, drag_icon_x, drag_icon_y, drag_icon_sz, rc)
    }
}

@(private = "file")
_inv_handle_input :: proc(w: ^World, slot_bbs: []clay.BoundingBox, grid_bb: clay.BoundingBox) {
    if !world_is_valid(w, w.player_id) { return }
    if !world_has_component(w, w.player_id, .Inventory) { return }

    inv := comp_get(w, w.player_id, .Inventory, InventoryComp)
    mp  := rl.GetMousePosition()

    if (ui_has(.Shop) || ui_has(.Stash)) && rl.IsMouseButtonPressed(.RIGHT) && g_drag_item_id == -1 {
        col, row, hit := _inv_mouse_to_cell(grid_bb, mp.x, mp.y)
        if hit {
            cell_id := inv.backpack[row * BACKPACK_COLS + col]
            if cell_id != INVALID_ENTITY {
                if ui_has(.Shop) {
                    g_sell_item_id = cell_id
                } else if ui_has(.Stash) {
                    stash_deposit_item(w, cell_id)
                }
                return
            }
        }
        if ui_has(.Stash) {
            for i in 0..<EQUIP_SLOT_COUNT {
                eid := inv.equipped[i]
                if eid == INVALID_ENTITY { continue }
                bb := slot_bbs[i]
                if bb.width == 0 { continue }
                if rl.CheckCollisionPointRec(mp, { bb.x, bb.y, bb.width, bb.height }) {
                    stash_deposit_item(w, eid)
                    return
                }
            }
        }
    }

    if rl.IsMouseButtonPressed(.LEFT) && g_drag_item_id == -1 {
        col, row, hit := _inv_mouse_to_cell(grid_bb, mp.x, mp.y)
        if hit {
            cell_id := inv.backpack[row * BACKPACK_COLS + col]
            if cell_id != INVALID_ENTITY {
                item             := comp_get(w, cell_id, .Item, ItemComp)
                g_drag_origin_x   = item.pack_x
                g_drag_origin_y   = item.pack_y
                g_drag_from_equip = false
                backpack_remove(inv, item)
                g_drag_item_id    = cell_id
            }
        }

        if g_drag_item_id == -1 {
            for i in 0..<EQUIP_SLOT_COUNT {
                eid  := inv.equipped[i]
                if eid == INVALID_ENTITY                       { continue }
                if !world_has_component(w, eid, .Item)         { continue }
                bb   := slot_bbs[i]
                if bb.width == 0                                  { continue }
                if !rl.CheckCollisionPointRec(mp, { bb.x, bb.y, bb.width, bb.height }) { continue }
                inv.equipped[i]     = INVALID_ENTITY
                g_drag_item_id      = eid
                g_drag_from_equip   = true
                g_drag_origin_equip = EquipSlot(i)
                break
            }
        }
    }

    if rl.IsMouseButtonReleased(.LEFT) && g_drag_item_id != -1 {
        item   := comp_get(w, g_drag_item_id, .Item, ItemComp)
        placed := false

        for i in 0..<EQUIP_SLOT_COUNT {
            slot := EquipSlot(i)
            if !_item_fits_slot(item.slot, slot) { continue }
            bb := slot_bbs[i]
            if bb.width == 0                     { continue }
            if !rl.CheckCollisionPointRec(mp, { bb.x, bb.y, bb.width, bb.height }) { continue }

            if slot == .WeaponPrimary && item.weapon_archetype != player_class_archetype() { break }

            if world_has_component(w, w.player_id, .Stats) {
                st := comp_get(w, w.player_id, .Stats, StatsComp)
                if item.req_str > 0 && st.strength  < int(item.req_str) { break }
                if item.req_dex > 0 && st.dexterity < int(item.req_dex) { break }
                if item.req_sci > 0 && st.science   < int(item.req_sci) { break }
            }

            if slot == .WeaponPrimary && item.is_two_handed {
                if inv.equipped[int(EquipSlot.WeaponOffhand)] != INVALID_ENTITY { break }
            }
            if slot == .WeaponOffhand {
                prim_id := inv.equipped[int(EquipSlot.WeaponPrimary)]
                if prim_id != INVALID_ENTITY &&
                   world_has_component(w, prim_id, .Item) &&
                   comp_get(w, prim_id, .Item, ItemComp).is_two_handed { break }
            }

            if inv.equipped[i] != INVALID_ENTITY {
                displaced    := inv.equipped[i]
                dis_item     := comp_get(w, displaced, .Item, ItemComp)
                dc, dr, dfit := backpack_find_free(inv, dis_item)
                if !dfit { break }
                backpack_place(inv, dis_item, displaced, dc, dr)
            }

            inv.equipped[i] = g_drag_item_id
            item.pack_x     = -1
            item.pack_y     = -1
            placed = true
            play_sfx("equip")
            break
        }

        if !placed {
            col, row, hit := _inv_mouse_to_cell(grid_bb, mp.x, mp.y)
            if hit && backpack_can_place(inv, item, col, row) {
                backpack_place(inv, item, g_drag_item_id, col, row)
                placed = true
            }
        }

        if !placed && ui_has(.Stash) {
            if stash_place_dragged_at_mouse(w, g_drag_item_id) {
                placed = true
            }
        }

        if !placed {
            if g_drag_from_stash {
                if stash_return_dragged_to_origin(w, g_drag_item_id) {
                    placed = true
                }
            } else if g_drag_from_equip && inv.equipped[int(g_drag_origin_equip)] == INVALID_ENTITY {
                inv.equipped[int(g_drag_origin_equip)] = g_drag_item_id
                item.pack_x = -1
                item.pack_y = -1
                placed = true
            } else if backpack_can_place(inv, item, g_drag_origin_x, g_drag_origin_y) {
                backpack_place(inv, item, g_drag_item_id, g_drag_origin_x, g_drag_origin_y)
                placed = true
            }
        }
        if !placed && !g_drag_from_stash {
            c, r, ok := backpack_find_free(inv, item)
            if ok { backpack_place(inv, item, g_drag_item_id, c, r) }
        }

        if placed && ui_has(.Stash) {
            save_player(w, w.player_id)
        }

        g_drag_item_id    = -1
        g_drag_origin_x   = -1
        g_drag_origin_y   = -1
        g_drag_from_equip = false
        g_drag_from_stash = false
    }

    if g_drag_item_id == -1 {
        col, row, hit := _inv_mouse_to_cell(grid_bb, mp.x, mp.y)
        if hit {
            g_hover_item_id = inv.backpack[row * BACKPACK_COLS + col]
        } else {
            g_hover_item_id = INVALID_ENTITY
            for i in 0..<EQUIP_SLOT_COUNT {
                eid := inv.equipped[i]
                if eid == INVALID_ENTITY { continue }
                bb  := slot_bbs[i]
                if bb.width == 0 { continue }
                if rl.CheckCollisionPointRec(mp, { bb.x, bb.y, bb.width, bb.height }) {
                    g_hover_item_id = eid
                    break
                }
            }
        }
    } else {
        g_hover_item_id = INVALID_ENTITY
    }
}

draw_inventory :: proc(w: ^World) {
    if !world_is_valid(w, w.player_id) { return }

    var_inv: ^InventoryComp
    if world_has_component(w, w.player_id, .Inventory) {
        var_inv = comp_get(w, w.player_id, .Inventory, InventoryComp)
    }

    drag_item_slot: EquipSlot
    has_drag := g_drag_item_id != -1 && world_is_valid(w, g_drag_item_id)
    if has_drag && world_has_component(w, g_drag_item_id, .Item) {
        drag_item_slot = comp_get(w, g_drag_item_id, .Item, ItemComp).slot
    }

    offhand_blocked := false
    if var_inv != nil {
        prim_id := var_inv.equipped[int(EquipSlot.WeaponPrimary)]
        if prim_id != INVALID_ENTITY && world_has_component(w, prim_id, .Item) {
            offhand_blocked = comp_get(w, prim_id, .Item, ItemComp).is_two_handed
        }
    }

    HPAD      := u16(g_inv.pad)
    VPAD      := u16(uis(8))
    VGAP      := u16(uis(6))
    SLOT_H    := f32(g_inv.slot_h)
    WEP_H     := f32(g_inv.wep_h)
    ABIL_H    := f32(g_inv.ability_h)
    WGAP      := u16(g_inv.col_gap)
    GRID_W    := f32(BACKPACK_COLS) * f32(g_inv.cell_sz)
    GRID_H    := f32(BACKPACK_ROWS) * f32(g_inv.cell_sz)
    PANEL_W   := f32(g_inv.panel_w)
    PANEL_H   := f32(rl.GetScreenHeight())

    ui_frame_reset()
    clay.BeginLayout()

    if clay.UI(clay.ID("InvPanel"))({
        layout = {
            layoutDirection = .TopToBottom,
            sizing = { clay.SizingFixed(PANEL_W), clay.SizingFixed(PANEL_H) },
        },
        floating = {
            offset     = { 0, 0 },
            attachment = { element = .RightTop, parent = .RightTop },
            attachTo   = .Root,
        },
        backgroundColor = { 10, 7, 5, 252 },
        border          = { color = { 90, 68, 28, 210 }, width = { 0, 0, 0, 2, 0 } },
    }) {
        if clay.UI(clay.ID("InvGoldBar"))({
            layout          = { sizing = { clay.SizingGrow(), clay.SizingFixed(uis(2)) } },
            backgroundColor = ui_clay_color(COL_BRASS),
        }) {}

        if clay.UI(clay.ID("InvContent"))({
            layout = {
                layoutDirection = .TopToBottom,
                childGap        = VGAP,
                childAlignment  = { x = .Center },
                padding         = { left = HPAD, right = HPAD,
                                    top  = VPAD, bottom = VPAD },
                sizing          = { clay.SizingGrow(), clay.SizingGrow() },
            },
        }) {
            if clay.UI(clay.ID("InvTitle"))({
                layout = {
                    sizing         = { clay.SizingGrow(), clay.SizingFit() },
                    childAlignment = { x = .Center },
                },
            }) {
                clay.TextDynamic(string(t(.INV_TITLE)), clay.TextConfig({
                    fontSize      = u16(uis(20)),
                    textColor     = ui_clay_color(COL_PARCH),
                    letterSpacing = 10,
                }))
            }

            ui_divider("InvDiv0")
            ui_section("InvSecArmor", string(t(.INV_ARMOR)))

            armor_slots  := [3]EquipSlot{ .Head, .Chest, .Boots }
            armor_labels := [3]cstring{ t(.INV_SLOT_HEAD), t(.INV_SLOT_CHEST), t(.INV_SLOT_BOOTS) }
            for i in 0..<3 {
                slot  := armor_slots[i]
                n, has := _inv_slot_name(w, var_inv, slot)
                d := UICustomData{ kind = .InvSlot }
                d.inv_slot.has_item  = has
                d.inv_slot.is_target = _inv_is_target(var_inv, drag_item_slot, slot)
                lbl_bytes := transmute([]u8)string(armor_labels[i])
                n_copy    := min(len(lbl_bytes), 7)
                copy(d.inv_slot.label[:], lbl_bytes[:n_copy])
                d.inv_slot.label[n_copy] = 0
                n_bytes   := transmute([]u8)string(n)
                nc        := min(len(n_bytes), 23)
                copy(d.inv_slot.item_name[:], n_bytes[:nc])
                d.inv_slot.item_name[nc] = 0

                if clay.UI(clay.ID(_SLOT_CLAY_ID[int(slot)]))({
                    layout = { sizing = { clay.SizingGrow(), clay.SizingFixed(SLOT_H) } },
                    custom = { customData = ui_push_custom(d) },
                }) {}
            }

            ui_divider("InvDiv1")
            ui_section("InvSecWep", string(t(.INV_WEAPONS)))

            if clay.UI(clay.ID("InvWepRow"))({
                layout = {
                    layoutDirection = .LeftToRight,
                    childGap        = WGAP,
                    sizing          = { clay.SizingGrow(), clay.SizingFit() },
                },
            }) {
                wep_slots  := [1]EquipSlot{ .WeaponPrimary }
                wep_types  := [1]cstring{ t(.INV_SLOT_WEAPON) }

                wep_label1_buf: [12]u8
                wep_label1 := string(t(.INV_SLOT_WEAPON))
                if world_has_component(w, w.player_id, .Equipment) {
                    eq := comp_get(w, w.player_id, .Equipment, EquipmentComp)
                    if world_is_valid(w, eq.weapon_entity_id) &&
                       world_has_component(w, eq.weapon_entity_id, .RenderConfig) {
                        rc_name := loc_lookup(render_config_name_cstr(
                            comp_get(w, eq.weapon_entity_id, .RenderConfig, RenderConfigComp)))
                        wep_label1 = string(rc_name)
                    }
                }
                _ = wep_label1_buf

                for i in 0..<1 {
                    slot  := wep_slots[i]
                    n, has := _inv_slot_name(w, var_inv, slot)
                    blocked := slot == .WeaponOffhand && offhand_blocked

                    d := UICustomData{ kind = .WeaponSlot }
                    d.wep_slot.has_item   = has
                    d.wep_slot.is_blocked = blocked
                    d.wep_slot.is_target  = !blocked && _inv_is_target(var_inv, drag_item_slot, slot)

                    tl_src := string(wep_types[i])
                    if i == 0 { tl_src = wep_label1 }
                    tl_bytes := transmute([]u8)tl_src
                    tl_n     := min(len(tl_bytes), 11)
                    copy(d.wep_slot.type_label[:], tl_bytes[:tl_n])
                    d.wep_slot.type_label[tl_n] = 0

                    n_bytes := transmute([]u8)string(n)
                    nc      := min(len(n_bytes), 23)
                    copy(d.wep_slot.item_name[:], n_bytes[:nc])
                    d.wep_slot.item_name[nc] = 0

                    if clay.UI(clay.ID(_SLOT_CLAY_ID[int(slot)]))({
                        layout = { sizing = { clay.SizingGrow(), clay.SizingFixed(WEP_H) } },
                        custom = { customData = ui_push_custom(d) },
                    }) {}
                }
            }

            ui_divider("InvDiv2")
            ui_section("InvSecAbil", string(t(.INV_ABILITIES)))

            if clay.UI(clay.ID("InvAbilRow"))({
                layout = {
                    layoutDirection = .LeftToRight,
                    childGap        = WGAP,
                    sizing          = { clay.SizingGrow(), clay.SizingFit() },
                },
            }) {
                ab_slots  := [4]EquipSlot{ .Ability1, .Ability2, .Ability3, .Ability4 }
                ab_keys   := [4]string{ "Q", "E", "F", "G" }

                for i in 0..<4 {
                    slot   := ab_slots[i]
                    n, has := _inv_slot_name(w, var_inv, slot)

                    d := UICustomData{ kind = .InvAbility }
                    d.inv_abil.has_item  = has
                    d.inv_abil.is_target = _inv_is_target(var_inv, drag_item_slot, slot)

                    kl_bytes := transmute([]u8)ab_keys[i]
                    copy(d.inv_abil.key_label[:min(len(kl_bytes), 3)], kl_bytes[:min(len(kl_bytes), 3)])
                    d.inv_abil.key_label[min(len(kl_bytes), 3)] = 0

                    if has && var_inv != nil {
                        eid := var_inv.equipped[int(slot)]
                        if world_is_valid(w, eid) && world_has_component(w, eid, .Item) {
                            aitem := comp_get(w, eid, .Item, ItemComp)
                            d.inv_abil.rarity_col = rarity_color(aitem.rarity)
                            d.inv_abil.level      = max(1, aitem.ability_level)
                            if aitem.ability_type != .None &&
                               int(aitem.ability_type) < len(ABILITY_DEFS) {
                                def := &ABILITY_DEFS[aitem.ability_type]
                                d.inv_abil.trait_col  = ability_trait_color(def.trait)
                            }
                        }
                    }
                    if has {
                        n_bytes := transmute([]u8)string(n)
                        nc      := min(len(n_bytes), 23)
                        copy(d.inv_abil.name[:], n_bytes[:nc])
                        d.inv_abil.name[nc] = 0
                    }

                    if clay.UI(clay.ID(_SLOT_CLAY_ID[int(slot)]))({
                        layout = { sizing = { clay.SizingGrow(), clay.SizingFixed(ABIL_H) } },
                        custom = { customData = ui_push_custom(d) },
                    }) {}
                }
            }

            ui_divider("InvDiv3")
            ui_section("InvSecFlask", "FLASKS")

            flask_slots    := [2]EquipSlot{ .Flask1, .Flask2 }
            flask_labels   := [2]string{ "[1] Health", "[2] Energy" }
            FLASK_H        := uis(34)

            for fi in 0..<2 {
                slot := flask_slots[fi]
                n, has := _inv_slot_name(w, var_inv, slot)
                d := UICustomData{ kind = .InvSlot }
                d.inv_slot.has_item  = has
                d.inv_slot.is_target = _inv_is_target(var_inv, drag_item_slot, slot)
                lbl_bytes := transmute([]u8)flask_labels[fi]
                lbl_n     := min(len(lbl_bytes), 7)
                copy(d.inv_slot.label[:], lbl_bytes[:lbl_n])
                d.inv_slot.label[lbl_n] = 0
                n_bytes := transmute([]u8)string(n)
                nc      := min(len(n_bytes), 23)
                copy(d.inv_slot.item_name[:], n_bytes[:nc])
                d.inv_slot.item_name[nc] = 0

                if has && var_inv != nil {
                    fid := var_inv.equipped[int(slot)]
                    if world_is_valid(w, fid) && world_has_component(w, fid, .Flask) {
                        fc    := comp_get(w, fid, .Flask, FlaskComp)
                        chg_s := fmt.bprintf(_flask_name_buf[:47], "%d/%d charges",
                            fc.charges, fc.max_charges)
                        _flask_name_buf[len(chg_s)] = 0

                        suffix  := fmt.tprintf("  (%d/%d)", fc.charges, fc.max_charges)
                        sb := transmute([]u8)suffix
                        sb_n := min(len(sb), 23 - nc)
                        copy(d.inv_slot.item_name[nc:], sb[:sb_n])
                        d.inv_slot.item_name[nc + sb_n] = 0
                    }
                }

                if clay.UI(clay.ID(_SLOT_CLAY_ID[int(slot)]))({
                    layout = { sizing = { clay.SizingGrow(), clay.SizingFixed(FLASK_H) } },
                    custom = { customData = ui_push_custom(d) },
                }) {}
            }

            ui_divider("InvDiv4")
            ui_section("InvSecBag", string(t(.INV_BACKPACK)))

            if clay.UI(clay.ID("InvBackpackGrid"))({
                layout = {
                    sizing = { clay.SizingFixed(GRID_W), clay.SizingFixed(GRID_H) },
                },
            }) {}

            if clay.UI(clay.ID("InvSpacer"))({
                layout = { sizing = { clay.SizingGrow(), clay.SizingGrow() } },
            }) {}

            if clay.UI(clay.ID("InvCloseHint"))({
                layout = {
                    sizing         = { clay.SizingGrow(), clay.SizingFit() },
                    childAlignment = { x = .Center },
                },
            }) {
                clay.TextDynamic(string(t(.INV_BTN_CLOSE)), clay.TextConfig({
                    fontSize      = u16(uis(15)),
                    textColor     = ui_clay_color(COL_MUTED),
                    letterSpacing = 8,
                }))
            }
        }
    }

    cmds := clay.EndLayout()

    slot_bbs: [EQUIP_SLOT_COUNT]clay.BoundingBox
    for i in 0..<EQUIP_SLOT_COUNT {
        id_str := _SLOT_CLAY_ID[i]
        if len(id_str) == 0 { continue }
        el := clay.GetElementData(clay.ID(id_str))
        if el.found { slot_bbs[i] = el.boundingBox }
    }
    grid_el := clay.GetElementData(clay.ID("InvBackpackGrid"))
    grid_bb : clay.BoundingBox
    if grid_el.found { grid_bb = grid_el.boundingBox }
    g_inv_backpack_bb = grid_bb

    _inv_handle_input(w, slot_bbs[:], grid_bb)

    clay_raylib_render(&cmds)

    _draw_backpack_raw(w, var_inv, grid_bb)

    _draw_drag_item(w)

    if g_hover_item_id != INVALID_ENTITY && g_drag_item_id == -1 {
        mp2 := rl.GetMousePosition()
        draw_item_tooltip_or_compare(w, g_hover_item_id, mp2.x, mp2.y)
    }
}
