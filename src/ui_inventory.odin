package main

// =============================================================================
// ui_inventory.odin — Clay-based equipment & backpack panel
//
// Replaces render.odin's draw_inventory + update_inventory.
// Input handling is merged into draw_inventory so that the draw phase is the
// single source of truth for the panel; update_inventory is no longer called
// from main.odin.
//
// Layout (Clay, floating right edge, full screen height):
//
//   ─── GOLD BAR (2 px) ───────────────────────────────────────────────────
//   E Q U I P M E N T
//   ─────────────────────────────────────────────────────────────────────────
//   ARMOR
//     [HEAD  ──── item name                                                ]
//     [CHEST ──── item name                                                ]
//     [BOOTS ──── item name                                                ]
//   WEAPONS
//     [  WEAPON I  ] [ OFFHAND MOD ]
//   ABILITIES
//     [ Q ][ E ][ F ][ G ]
//   B A C K P A C K
//     raw Raylib 10×4 cell grid (origin queried via clay.GetElementData)
//   ─────────────────────────────────────────────────────────────────────────
//   [I]  Close
//
// =============================================================================

import rl   "vendor:raylib"
import clay "../clay"
import cw   "clockwork"

// ── Drag-and-drop state ───────────────────────────────────────────────────
// These replace the @(private="file") globals that were in render.odin.

g_drag_item_id:      int          = -1
g_drag_origin_x:     int          = -1
g_drag_origin_y:     int          = -1
g_drag_from_equip:   bool         = false
g_drag_from_stash:   bool         = false
g_drag_origin_equip: cw.EquipSlot = {}
g_hover_item_id:     int          = cw.INVALID_ENTITY
g_inv_backpack_bb:   clay.BoundingBox

// Clay element IDs for each equip slot (indexed by cw.EquipSlot).
// Consumable (index 5) has an empty string → not shown in the panel.
@(private = "file")
_SLOT_CLAY_ID := [cw.EQUIP_SLOT_COUNT]string{
    "InvSlotHead",   // 0 .Head
    "InvSlotChest",  // 1 .Chest
    "InvSlotBoots",  // 2 .Boots
    "InvSlotWep1",   // 3 .WeaponPrimary
    "InvSlotWep2",   // 4 .WeaponOffhand
    "",              // 5 .Consumable  (not shown)
    "InvSlotAbil1",  // 6 .Ability1
    "InvSlotAbil2",  // 7 .Ability2
    "InvSlotAbil3",  // 8 .Ability3
    "InvSlotAbil4",  // 9 .Ability4
}

// ── Helpers ───────────────────────────────────────────────────────────────

@(private = "file")
_item_fits_slot :: proc(item_slot: cw.EquipSlot, target: cw.EquipSlot) -> bool {
    is_wep_item   := item_slot == .WeaponPrimary || item_slot == .WeaponOffhand
    is_wep_target := target   == .WeaponPrimary || target   == .WeaponOffhand
    if is_wep_item { return is_wep_target }

    is_ab_item   := item_slot == .Ability1 || item_slot == .Ability2 ||
                    item_slot == .Ability3 || item_slot == .Ability4
    is_ab_target := target   == .Ability1 || target   == .Ability2 ||
                    target   == .Ability3 || target   == .Ability4
    if is_ab_item { return is_ab_target }

    return item_slot == target
}

@(private = "file")
_inv_slot_name :: proc(w: ^cw.World, inv: ^cw.InventoryComp, slot: cw.EquipSlot) -> (cstring, bool) {
    if inv == nil { return t(.INV_UNEQUIPPED), false }
    eid := inv.equipped[int(slot)]
    if !cw.world_is_valid(w, eid) { return t(.INV_UNEQUIPPED), false }
    if cw.world_has_component(w, eid, .RenderConfig) {
        return loc_lookup(cw.render_config_name_cstr(cw.world_get_render_config(w, eid))), true
    }
    return "???", true
}

// _inv_is_target returns true when: a drag is active, the dragged item fits
// 'slot', and the slot is currently empty.  This is used to highlight all
// valid drop targets during a drag (same UX as the original raw-Raylib code).
@(private = "file")
_inv_is_target :: proc(inv: ^cw.InventoryComp, drag_slot: cw.EquipSlot, target: cw.EquipSlot) -> bool {
    if inv == nil || g_drag_item_id == -1 { return false }
    if !_item_fits_slot(drag_slot, target)           { return false }
    return inv.equipped[int(target)] == cw.INVALID_ENTITY
}

// _inv_mouse_to_cell converts a mouse position to a backpack grid cell using
// the bounding box reported by Clay after layout.
@(private = "file")
_inv_mouse_to_cell :: proc(grid_bb: clay.BoundingBox, mx, my: f32) -> (col, row: int, ok: bool) {
    if grid_bb.width == 0 { return 0, 0, false }
    c := int(mx - grid_bb.x) / int(g_inv.cell_sz)
    r := int(my - grid_bb.y) / int(g_inv.cell_sz)
    if c < 0 || c >= cw.BACKPACK_COLS { return 0, 0, false }
    if r < 0 || r >= cw.BACKPACK_ROWS { return 0, 0, false }
    return c, r, true
}

// ── Backpack grid drawing ─────────────────────────────────────────────────

// draw_item_glyph is package-level (not private) so draw_item_tooltip in
// render.odin can call it for the icon displayed inside tooltips.
draw_item_glyph :: proc(slot: cw.EquipSlot, x, y, sz: i32, tint: rl.Color) {
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
    }
}

@(private = "file")
_draw_backpack_raw :: proc(w: ^cw.World, inv: ^cw.InventoryComp, grid_bb: clay.BoundingBox) {
    if grid_bb.width == 0 { return }
    gx := i32(grid_bb.x)
    gy := i32(grid_bb.y)
    cs := g_inv.cell_sz

    // Cell background grid
    for r in 0..<i32(cw.BACKPACK_ROWS) {
        for c in 0..<i32(cw.BACKPACK_COLS) {
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

    // Grid lines
    grid_w := i32(cw.BACKPACK_COLS) * cs
    grid_h := i32(cw.BACKPACK_ROWS) * cs
    for c in 0..=i32(cw.BACKPACK_COLS) {
        lx := f32(gx + c * cs)
        rl.DrawLineEx({ lx, f32(gy) }, { lx, f32(gy + grid_h) }, 1, COL_RULE)
    }
    for r in 0..=i32(cw.BACKPACK_ROWS) {
        ly := f32(gy + r * cs)
        rl.DrawLineEx({ f32(gx), ly }, { f32(gx + grid_w), ly }, 1, COL_RULE)
    }

    if inv == nil { return }

    // Place drag highlight
    if g_drag_item_id != -1 && cw.world_is_valid(w, g_drag_item_id) {
        mp            := rl.GetMousePosition()
        drag_item     := cw.world_get_item(w, g_drag_item_id)
        col, row, hit := _inv_mouse_to_cell(grid_bb, mp.x, mp.y)
        if hit {
            can    := backpack_can_place(inv, drag_item, col, row)
            hi_col := rl.Color{ 60, 180, 60, 80 } if can else rl.Color{ 180, 40, 40, 80 }
            for dy in 0..<drag_item.grid_h {
                for dx in 0..<drag_item.grid_w {
                    if col+dx < cw.BACKPACK_COLS && row+dy < cw.BACKPACK_ROWS {
                        rl.DrawRectangle(
                            gx + i32(col+dx) * cs,
                            gy + i32(row+dy) * cs,
                            cs, cs, hi_col)
                    }
                }
            }
        }
    }

    // Draw items in backpack
    for row in 0..<cw.BACKPACK_ROWS {
        for col in 0..<cw.BACKPACK_COLS {
            cell_id := inv.backpack[row * cw.BACKPACK_COLS + col]
            if cell_id == cw.INVALID_ENTITY  { continue }
            if cell_id == g_drag_item_id     { continue }
            if !cw.world_is_valid(w, cell_id){ continue }
            item := cw.world_get_item(w, cell_id)
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

            if cw.world_has_component(w, cell_id, .RenderConfig) {
                rcc := cw.world_get_render_config(w, cell_id)
                if rcc.icon_len > 0 {
                    tex, ok := get_or_load_icon(cw.render_config_icon_cstr(rcc))
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

            if cw.world_has_component(w, cell_id, .RenderConfig) {
                rcc  := cw.world_get_render_config(w, cell_id)
                name := loc_lookup(cw.render_config_name_cstr(rcc))
                rl.DrawTextEx(g_font, name,
                    { f32(ix) + uis(3), f32(iy + icon_margin + icon_sz + 2) },
                    uis(11), 0.4, rl.Color{ rc.r, rc.g, rc.b, 200 })
            }
        }
    }
}

_draw_drag_item :: proc(w: ^cw.World) {
    if g_drag_item_id == -1 || !cw.world_is_valid(w, g_drag_item_id) { return }
    mp   := rl.GetMousePosition()
    item := cw.world_get_item(w, g_drag_item_id)
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

    if cw.world_has_component(w, g_drag_item_id, .RenderConfig) {
        rcc := cw.world_get_render_config(w, g_drag_item_id)
        if rcc.icon_len > 0 {
            tex, ok := get_or_load_icon(cw.render_config_icon_cstr(rcc))
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

// ── Input handling ────────────────────────────────────────────────────────

@(private = "file")
_inv_handle_input :: proc(w: ^cw.World, slot_bbs: []clay.BoundingBox, grid_bb: clay.BoundingBox) {
    if !cw.world_is_valid(w, w.player_id) { return }
    if !cw.world_has_component(w, w.player_id, .Inventory) { return }

    inv := cw.world_get_inventory(w, w.player_id)
    mp  := rl.GetMousePosition()

    // Right-click in shop/stash: sell or deposit carried items.
    if (ui_has(.Shop) || ui_has(.Stash)) && rl.IsMouseButtonPressed(.RIGHT) && g_drag_item_id == -1 {
        col, row, hit := _inv_mouse_to_cell(grid_bb, mp.x, mp.y)
        if hit {
            cell_id := inv.backpack[row * cw.BACKPACK_COLS + col]
            if cell_id != cw.INVALID_ENTITY {
                if ui_has(.Shop) {
                    g_sell_item_id = cell_id
                } else if ui_has(.Stash) {
                    stash_deposit_item(w, cell_id)
                }
                return
            }
        }
        if ui_has(.Stash) {
            for i in 0..<cw.EQUIP_SLOT_COUNT {
                eid := inv.equipped[i]
                if eid == cw.INVALID_ENTITY { continue }
                bb := slot_bbs[i]
                if bb.width == 0 { continue }
                if rl.CheckCollisionPointRec(mp, { bb.x, bb.y, bb.width, bb.height }) {
                    stash_deposit_item(w, eid)
                    return
                }
            }
        }
    }

    // Left-click: pick up item (start drag)
    if rl.IsMouseButtonPressed(.LEFT) && g_drag_item_id == -1 {
        // Try backpack first
        col, row, hit := _inv_mouse_to_cell(grid_bb, mp.x, mp.y)
        if hit {
            cell_id := inv.backpack[row * cw.BACKPACK_COLS + col]
            if cell_id != cw.INVALID_ENTITY {
                item             := cw.world_get_item(w, cell_id)
                g_drag_origin_x   = item.pack_x
                g_drag_origin_y   = item.pack_y
                g_drag_from_equip = false
                backpack_remove(inv, item)
                g_drag_item_id    = cell_id
            }
        }
        // Try equip slots
        if g_drag_item_id == -1 {
            for i in 0..<cw.EQUIP_SLOT_COUNT {
                eid  := inv.equipped[i]
                if eid == cw.INVALID_ENTITY                       { continue }
                if !cw.world_has_component(w, eid, .Item)         { continue }
                bb   := slot_bbs[i]
                if bb.width == 0                                  { continue }
                if !rl.CheckCollisionPointRec(mp, { bb.x, bb.y, bb.width, bb.height }) { continue }
                inv.equipped[i]     = cw.INVALID_ENTITY
                g_drag_item_id      = eid
                g_drag_from_equip   = true
                g_drag_origin_equip = cw.EquipSlot(i)
                break
            }
        }
    }

    // Left-release: place dragged item
    if rl.IsMouseButtonReleased(.LEFT) && g_drag_item_id != -1 {
        item   := cw.world_get_item(w, g_drag_item_id)
        placed := false

        // Try equip slots
        for i in 0..<cw.EQUIP_SLOT_COUNT {
            slot := cw.EquipSlot(i)
            if !_item_fits_slot(item.slot, slot)     { continue }
            if inv.equipped[i] != cw.INVALID_ENTITY  { continue }
            bb := slot_bbs[i]
            if bb.width == 0                         { continue }
            if !rl.CheckCollisionPointRec(mp, { bb.x, bb.y, bb.width, bb.height }) { continue }
            // Stat requirement check
            if cw.world_has_component(w, w.player_id, .Stats) {
                st := cw.world_get_stats(w, w.player_id)
                if item.req_str > 0 && st.strength  < int(item.req_str) { break }
                if item.req_dex > 0 && st.dexterity < int(item.req_dex) { break }
                if item.req_sci > 0 && st.science   < int(item.req_sci) { break }
            }
            // Two-handed blocking
            if slot == .WeaponPrimary && item.is_two_handed {
                if inv.equipped[int(cw.EquipSlot.WeaponOffhand)] != cw.INVALID_ENTITY { break }
            }
            if slot == .WeaponOffhand {
                prim_id := inv.equipped[int(cw.EquipSlot.WeaponPrimary)]
                if prim_id != cw.INVALID_ENTITY &&
                   cw.world_has_component(w, prim_id, .Item) &&
                   cw.world_get_item(w, prim_id).is_two_handed { break }
            }
            inv.equipped[i] = g_drag_item_id
            item.pack_x     = -1
            item.pack_y     = -1
            placed = true
            play_sfx("equip")
            break
        }

        // Try backpack
        if !placed {
            col, row, hit := _inv_mouse_to_cell(grid_bb, mp.x, mp.y)
            if hit && backpack_can_place(inv, item, col, row) {
                backpack_place(inv, item, g_drag_item_id, col, row)
                placed = true
            }
        }

        // Try stash grid
        if !placed && ui_has(.Stash) {
            if stash_place_dragged_at_mouse(w, g_drag_item_id) {
                placed = true
            }
        }

        // Fallback: return to origin
        if !placed {
            if g_drag_from_stash {
                if stash_return_dragged_to_origin(w, g_drag_item_id) {
                    placed = true
                }
            } else if g_drag_from_equip && inv.equipped[int(g_drag_origin_equip)] == cw.INVALID_ENTITY {
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

    // Hover detection (for tooltip)
    if g_drag_item_id == -1 {
        col, row, hit := _inv_mouse_to_cell(grid_bb, mp.x, mp.y)
        if hit {
            g_hover_item_id = inv.backpack[row * cw.BACKPACK_COLS + col]
        } else {
            g_hover_item_id = cw.INVALID_ENTITY
            for i in 0..<cw.EQUIP_SLOT_COUNT {
                eid := inv.equipped[i]
                if eid == cw.INVALID_ENTITY { continue }
                bb  := slot_bbs[i]
                if bb.width == 0 { continue }
                if rl.CheckCollisionPointRec(mp, { bb.x, bb.y, bb.width, bb.height }) {
                    g_hover_item_id = eid
                    break
                }
            }
        }
    } else {
        g_hover_item_id = cw.INVALID_ENTITY
    }
}

// ── Main draw entry point ─────────────────────────────────────────────────

draw_inventory :: proc(w: ^cw.World) {
    if !cw.world_is_valid(w, w.player_id) { return }

    var_inv: ^cw.InventoryComp
    if cw.world_has_component(w, w.player_id, .Inventory) {
        var_inv = cw.world_get_inventory(w, w.player_id)
    }

    // Drag item slot type (used for is_target checks)
    drag_item_slot: cw.EquipSlot
    has_drag := g_drag_item_id != -1 && cw.world_is_valid(w, g_drag_item_id)
    if has_drag && cw.world_has_component(w, g_drag_item_id, .Item) {
        drag_item_slot = cw.world_get_item(w, g_drag_item_id).slot
    }

    // Two-handed check: offhand slot blocked?
    offhand_blocked := false
    if var_inv != nil {
        prim_id := var_inv.equipped[int(cw.EquipSlot.WeaponPrimary)]
        if prim_id != cw.INVALID_ENTITY && cw.world_has_component(w, prim_id, .Item) {
            offhand_blocked = cw.world_get_item(w, prim_id).is_two_handed
        }
    }

    // ── Layout constants ──────────────────────────────────────────────────
    // g_inv values are already pre-scaled by uis() in update_clay_input.
    // Do NOT apply uis() again here — that would double-scale at non-720p.
    // Raw uis() is only correct for constants that are NOT in g_inv.
    HPAD      := u16(g_inv.pad)                                  // pre-scaled
    VPAD      := u16(uis(8))                                     // raw constant
    VGAP      := u16(uis(6))                                     // raw constant
    SLOT_H    := f32(g_inv.slot_h)                               // pre-scaled
    WEP_H     := f32(g_inv.wep_h)                               // pre-scaled
    ABIL_H    := f32(g_inv.ability_h)                            // pre-scaled
    WGAP      := u16(g_inv.col_gap)                              // pre-scaled
    GRID_W    := f32(cw.BACKPACK_COLS) * f32(g_inv.cell_sz)      // pre-scaled
    GRID_H    := f32(cw.BACKPACK_ROWS) * f32(g_inv.cell_sz)      // pre-scaled
    PANEL_W   := f32(g_inv.panel_w)                              // pre-scaled
    PANEL_H   := f32(rl.GetScreenHeight())

    // ── Build Clay layout ─────────────────────────────────────────────────
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

        // Gold top bar
        if clay.UI(clay.ID("InvGoldBar"))({
            layout          = { sizing = { clay.SizingGrow(), clay.SizingFixed(uis(2)) } },
            backgroundColor = ui_clay_color(COL_BRASS),
        }) {}

        // Content area with padding
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

            // Title
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

            // Armor slots
            armor_slots  := [3]cw.EquipSlot{ .Head, .Chest, .Boots }
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

            // Weapon row
            if clay.UI(clay.ID("InvWepRow"))({
                layout = {
                    layoutDirection = .LeftToRight,
                    childGap        = WGAP,
                    sizing          = { clay.SizingGrow(), clay.SizingFit() },
                },
            }) {
                wep_slots  := [2]cw.EquipSlot{ .WeaponPrimary, .WeaponOffhand }
                wep_types  := [2]cstring{ t(.INV_SLOT_WEAPON), t(.INV_SLOT_OFFHAND) }

                // Primary weapon label: use actual equipped weapon name if any
                wep_label1_buf: [12]u8
                wep_label1 := string(t(.INV_SLOT_WEAPON))
                if cw.world_has_component(w, w.player_id, .Equipment) {
                    eq := cw.world_get_equipment(w, w.player_id)
                    if cw.world_is_valid(w, eq.weapon_entity_id) &&
                       cw.world_has_component(w, eq.weapon_entity_id, .RenderConfig) {
                        rc_name := loc_lookup(cw.render_config_name_cstr(
                            cw.world_get_render_config(w, eq.weapon_entity_id)))
                        wep_label1 = string(rc_name)
                    }
                }
                _ = wep_label1_buf // suppress unused warning

                for i in 0..<2 {
                    slot  := wep_slots[i]
                    n, has := _inv_slot_name(w, var_inv, slot)
                    blocked := slot == .WeaponOffhand && offhand_blocked

                    d := UICustomData{ kind = .WeaponSlot }
                    d.wep_slot.has_item   = has
                    d.wep_slot.is_blocked = blocked
                    d.wep_slot.is_target  = !blocked && _inv_is_target(var_inv, drag_item_slot, slot)

                    // Type label
                    tl_src := string(wep_types[i])
                    if i == 0 { tl_src = wep_label1 }
                    tl_bytes := transmute([]u8)tl_src
                    tl_n     := min(len(tl_bytes), 11)
                    copy(d.wep_slot.type_label[:], tl_bytes[:tl_n])
                    d.wep_slot.type_label[tl_n] = 0
                    // Item name
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

            // Ability row
            if clay.UI(clay.ID("InvAbilRow"))({
                layout = {
                    layoutDirection = .LeftToRight,
                    childGap        = WGAP,
                    sizing          = { clay.SizingGrow(), clay.SizingFit() },
                },
            }) {
                ab_slots  := [4]cw.EquipSlot{ .Ability1, .Ability2, .Ability3, .Ability4 }
                ab_keys   := [4]string{ "Q", "E", "F", "G" }

                for i in 0..<4 {
                    slot   := ab_slots[i]
                    n, has := _inv_slot_name(w, var_inv, slot)

                    d := UICustomData{ kind = .InvAbility }
                    d.inv_abil.has_item  = has
                    d.inv_abil.is_target = _inv_is_target(var_inv, drag_item_slot, slot)

                    // Key label
                    kl_bytes := transmute([]u8)ab_keys[i]
                    copy(d.inv_abil.key_label[:min(len(kl_bytes), 3)], kl_bytes[:min(len(kl_bytes), 3)])
                    d.inv_abil.key_label[min(len(kl_bytes), 3)] = 0

                    // Ability name + rarity + passive flag
                    if has && var_inv != nil {
                        eid := var_inv.equipped[int(slot)]
                        if cw.world_is_valid(w, eid) && cw.world_has_component(w, eid, .Item) {
                            aitem := cw.world_get_item(w, eid)
                            d.inv_abil.rarity_col = rarity_color(aitem.rarity)
                            if aitem.ability_type != .None {
                                def := &ABILITY_DEFS[aitem.ability_type]
                                d.inv_abil.is_passive = def.is_passive
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
            ui_section("InvSecBag", string(t(.INV_BACKPACK)))

            // Backpack grid placeholder — actual drawing happens via raw Raylib
            if clay.UI(clay.ID("InvBackpackGrid"))({
                layout = {
                    sizing = { clay.SizingFixed(GRID_W), clay.SizingFixed(GRID_H) },
                },
            }) {}

            // Push close hint to bottom of panel
            if clay.UI(clay.ID("InvSpacer"))({
                layout = { sizing = { clay.SizingGrow(), clay.SizingGrow() } },
            }) {}

            // Close hint
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

        } // InvContent
    } // InvPanel

    cmds := clay.EndLayout()

    // ── Query element positions after layout ──────────────────────────────
    slot_bbs: [cw.EQUIP_SLOT_COUNT]clay.BoundingBox
    for i in 0..<cw.EQUIP_SLOT_COUNT {
        id_str := _SLOT_CLAY_ID[i]
        if len(id_str) == 0 { continue }
        el := clay.GetElementData(clay.ID(id_str))
        if el.found { slot_bbs[i] = el.boundingBox }
    }
    grid_el := clay.GetElementData(clay.ID("InvBackpackGrid"))
    grid_bb : clay.BoundingBox
    if grid_el.found { grid_bb = grid_el.boundingBox }
    g_inv_backpack_bb = grid_bb

    // ── Input (merged from update_inventory) ─────────────────────────────
    _inv_handle_input(w, slot_bbs[:], grid_bb)

    // ── Render Clay layout ────────────────────────────────────────────────
    clay_raylib_render(&cmds)

    // ── Raw Raylib overlay: backpack grid + items ─────────────────────────
    _draw_backpack_raw(w, var_inv, grid_bb)

    // Drag item ghost
    _draw_drag_item(w)

    // Tooltip
    if g_hover_item_id != cw.INVALID_ENTITY && g_drag_item_id == -1 {
        mp2 := rl.GetMousePosition()
        draw_item_tooltip_or_compare(w, g_hover_item_id, mp2.x, mp2.y)
    }
}
