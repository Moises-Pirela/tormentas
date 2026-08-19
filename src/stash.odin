package main

import "core:math"
import "core:fmt"
import rl "vendor:raylib"

STASH_INTERACT_PROMPT_DIST :: f32(85)

g_stash_npc_id: int = INVALID_ENTITY
g_stash_grid_bb: rl.Rectangle

stash_has_room :: proc() -> bool {
    return local_stash().item_count < STASH_MAX_ITEMS
}

stash_index_of :: proc(item_id: int) -> int {
    for i in 0..<local_stash().item_count {
        if local_stash().item_ids[i] == item_id { return i }
    }
    return -1
}

stash_can_place :: proc(item: ^ItemComp, col, row: int, except_id := INVALID_ENTITY) -> bool {
    if item == nil { return false }
    if col < 0 || row < 0 { return false }
    if col + item.grid_w > STASH_COLS { return false }
    if row + item.grid_h > STASH_ROWS { return false }

    for dy in 0..<item.grid_h {
        for dx in 0..<item.grid_w {
            cell := local_stash().grid[(row + dy) * STASH_COLS + (col + dx)]
            if cell != INVALID_ENTITY && cell != except_id { return false }
        }
    }
    return true
}

stash_place_existing :: proc(item: ^ItemComp, item_id, col, row: int) {
    item.pack_x = col
    item.pack_y = row
    for dy in 0..<item.grid_h {
        for dx in 0..<item.grid_w {
            local_stash().grid[(row + dy) * STASH_COLS + (col + dx)] = item_id
        }
    }
}

stash_add_id :: proc(item_id: int) -> bool {
    if stash_index_of(item_id) >= 0 { return true }
    if !stash_has_room() { return false }
    local_stash().item_ids[local_stash().item_count] = item_id
    local_stash().item_count += 1
    return true
}

stash_remove_id :: proc(item_id: int) {
    idx := stash_index_of(item_id)
    if idx >= 0 {
        for i in idx..<(local_stash().item_count - 1) {
            local_stash().item_ids[i] = local_stash().item_ids[i + 1]
        }
        local_stash().item_count -= 1
        local_stash().item_ids[local_stash().item_count] = INVALID_ENTITY
    }

    for &cell in local_stash().grid {
        if cell == item_id { cell = INVALID_ENTITY }
    }
}

stash_find_free :: proc(item: ^ItemComp) -> (col, row: int, ok: bool) {
    for r in 0..<STASH_ROWS {
        for c in 0..<STASH_COLS {
            if stash_can_place(item, c, r) {
                return c, r, true
            }
        }
    }
    return 0, 0, false
}

stash_place_item :: proc(w: ^World, item_id, col, row: int) -> bool {
    if !world_is_valid(w, item_id)             { return false }
    if !world_has_component(w, item_id, .Item) { return false }
    item := comp_get(w, item_id, .Item, ItemComp)
    if !stash_can_place(item, col, row)           { return false }
    if !stash_add_id(item_id)                     { return false }
    stash_place_existing(item, item_id, col, row)
    if world_has_component(w, item_id, .GroundItem) {
        comp_rm(w, item_id, .GroundItem)
    }
    comp_rm(w, item_id, .Transform)
    return true
}

stash_mouse_to_cell :: proc(mx, my: f32) -> (col, row: int, ok: bool) {
    if g_stash_grid_bb.width <= 0 || g_stash_grid_bb.height <= 0 { return 0, 0, false }
    if !rl.CheckCollisionPointRec({mx, my}, g_stash_grid_bb) { return 0, 0, false }
    cs := f32(g_inv.cell_sz)
    col = int((mx - g_stash_grid_bb.x) / cs)
    row = int((my - g_stash_grid_bb.y) / cs)
    if col < 0 || col >= STASH_COLS || row < 0 || row >= STASH_ROWS { return 0, 0, false }
    return col, row, true
}

stash_place_dragged_at_mouse :: proc(w: ^World, item_id: int) -> bool {
    mp := rl.GetMousePosition()
    col, row, hit := stash_mouse_to_cell(mp.x, mp.y)
    if !hit { return false }
    if stash_place_item(w, item_id, col, row) {
        play_sfx("pickup")
        save_player(w, w.player_id)
        return true
    }
    play_sfx("ui_deny")
    return false
}

stash_return_dragged_to_origin :: proc(w: ^World, item_id: int) -> bool {
    if !world_is_valid(w, item_id) || !world_has_component(w, item_id, .Item) { return false }
    item := comp_get(w, item_id, .Item, ItemComp)
    if stash_place_item(w, item_id, g_drag_origin_x, g_drag_origin_y) { return true }
    c, r, ok := stash_find_free(item)
    if ok { return stash_place_item(w, item_id, c, r) }
    return false
}

stash_deposit_item :: proc(w: ^World, item_id: int) -> bool {
    pid := w.player_id
    if !world_is_valid(w, pid)                     { return false }
    if !world_has_component(w, pid, .Inventory)    { return false }
    if !world_is_valid(w, item_id)                 { return false }
    if !world_has_component(w, item_id, .Item)     { return false }

    inv  := comp_get(w, pid, .Inventory, InventoryComp)
    item := comp_get(w, item_id, .Item, ItemComp)
    col, row, ok := stash_find_free(item)
    if !ok || !stash_has_room() {
        play_sfx("ui_deny")
        return false
    }

    backpack_remove(inv, item)
    for &slot in inv.equipped {
        if slot == item_id { slot = INVALID_ENTITY }
    }

    if !stash_place_item(w, item_id, col, row) {
        play_sfx("ui_deny")
        return false
    }

    play_sfx("pickup")
    ui_mark_dirty(.Stash)
    ui_mark_dirty(.Inventory)
    save_player(w, pid)
    return true
}

stash_deposit_all_carried :: proc(w: ^World) -> int {
    pid := w.player_id
    if !world_is_valid(w, pid)                  { return 0 }
    if !world_has_component(w, pid, .Inventory) { return 0 }

    inv := comp_get(w, pid, .Inventory, InventoryComp)
    ids: [EQUIP_SLOT_COUNT + BACKPACK_COLS * BACKPACK_ROWS]int
    count := 0

    for eid in inv.equipped {
        if eid == INVALID_ENTITY { continue }
        exists := false
        for i in 0..<count {
            if ids[i] == eid { exists = true; break }
        }
        if !exists { ids[count] = eid; count += 1 }
    }

    for eid in inv.backpack {
        if eid == INVALID_ENTITY { continue }
        exists := false
        for i in 0..<count {
            if ids[i] == eid { exists = true; break }
        }
        if !exists { ids[count] = eid; count += 1 }
    }

    deposited := 0
    for i in 0..<count {
        if stash_deposit_item(w, ids[i]) { deposited += 1 }
    }
    return deposited
}

find_nearby_stash :: proc(w: ^World) -> (id: int, pos: [3]f32, ok: bool) {
    if !world_is_valid(w, w.player_id) { return }
    if !world_has_component(w, w.player_id, .Transform) { return }

    player_pos := comp_get(w, w.player_id, .Transform, TransformComp).position
    npc_ids := world_query(w, query_mask(.NPC, .Transform))
    defer delete(npc_ids)

    best_dist_sq := f32(1e30)
    for nid in npc_ids {
        npc := comp_get(w, nid, .NPC, NPCComp)
        if npc.npc_type != .Stash { continue }
        nt := comp_get(w, nid, .Transform, TransformComp)
        dx := nt.position[0] - player_pos[0]
        dy := nt.position[1] - player_pos[1]
        dist_sq := dx*dx + dy*dy
        if dist_sq > npc.interact_radius * npc.interact_radius { continue }
        if dist_sq < best_dist_sq {
            best_dist_sq = dist_sq
            id  = nid
            pos = nt.position
            ok  = true
        }
    }
    return
}

update_stash :: proc(w: ^World) {
    if g_playing_state != .Gameplay && g_playing_state != .Hub { return }
    id, _, ok := find_nearby_stash(w)
    if ok && input_pressed(rl.KeyboardKey(g_binds.gameplay.interact)) {
        g_stash_npc_id = id
        ui_open(.Stash)
    }
}

draw_stash_world :: proc(w: ^World) {
    if ui_has(.Stash) { return }
    _, pos, ok := find_nearby_stash(w)
    if !ok { return }

    prompt := t(.STASH_INTERACT)
    fs := f32(10)
    sz := rl.MeasureTextEx(g_font_body, prompt, fs, 0.5)
    pulse := u8(185 + i32((0.5 + 0.5 * math.sin(rl.GetTime() * 4.0)) * 45))
    p := world_to_iso_xy(pos[0], pos[1])
    rl.DrawTextEx(g_font_body, prompt,
        { p.x - sz.x * 0.5, p.y - 48 },
        fs, 0.5, rl.Color{ 230, 190, 120, pulse })
}

stash_draw_grid :: proc(w: ^World, grid_r: rl.Rectangle) {
    cs := i32(g_inv.cell_sz)
    gx := i32(grid_r.x)
    gy := i32(grid_r.y)

    for r in 0..<STASH_ROWS {
        for c in 0..<STASH_COLS {
            cx := gx + i32(c) * cs
            cy := gy + i32(r) * cs
            rl.DrawRectangle(cx, cy, cs, cs, rl.Color{ 8, 6, 4, 255 })
            rl.DrawRectangle(cx + 1, cy + 1, cs - 2, cs - 2, rl.Color{ 18, 14, 10, 255 })
        }
    }
    for c in 0..=STASH_COLS {
        lx := f32(gx + i32(c) * cs)
        rl.DrawLineEx({ lx, f32(gy) }, { lx, f32(gy + STASH_ROWS * cs) }, 1, COL_RULE)
    }
    for r in 0..=STASH_ROWS {
        ly := f32(gy + i32(r) * cs)
        rl.DrawLineEx({ f32(gx), ly }, { f32(gx + STASH_COLS * cs), ly }, 1, COL_RULE)
    }

    if g_drag_item_id != -1 && world_is_valid(w, g_drag_item_id) {
        mp := rl.GetMousePosition()
        drag_item := comp_get(w, g_drag_item_id, .Item, ItemComp)
        col, row, hit := stash_mouse_to_cell(mp.x, mp.y)
        if hit {
            can := stash_can_place(drag_item, col, row)
            hi_col := rl.Color{ 60, 180, 60, 80 } if can else rl.Color{ 180, 40, 40, 80 }
            for dy in 0..<drag_item.grid_h {
                for dx in 0..<drag_item.grid_w {
                    if col+dx < STASH_COLS && row+dy < STASH_ROWS {
                        rl.DrawRectangle(gx + i32(col+dx) * cs, gy + i32(row+dy) * cs, cs, cs, hi_col)
                    }
                }
            }
        }
    }

    for row in 0..<STASH_ROWS {
        for col in 0..<STASH_COLS {
            cell_id := local_stash().grid[row * STASH_COLS + col]
            if cell_id == INVALID_ENTITY || cell_id == g_drag_item_id { continue }
            if !world_is_valid(w, cell_id) || !world_has_component(w, cell_id, .Item) { continue }
            item := comp_get(w, cell_id, .Item, ItemComp)
            if item.pack_x != col || item.pack_y != row { continue }

            rc := rarity_color(item.rarity)
            ix := gx + i32(col) * cs + 2
            iy := gy + i32(row) * cs + 2
            iw := i32(item.grid_w) * cs - 4
            ih := i32(item.grid_h) * cs - 4
            rl.DrawRectangle(ix, iy, iw, ih, rl.Color{ rc.r / 5, rc.g / 5, rc.b / 5, 230 })
            rl.DrawRectangleLinesEx({ f32(ix), f32(iy), f32(iw), f32(ih) }, 1, rl.Color{ rc.r, rc.g, rc.b, 220 })

            icon_sz := min(iw, ih) - 6
            draw_item_glyph(item.slot, ix + (iw - icon_sz) / 2, iy + 3, icon_sz, rc)
            if world_has_component(w, cell_id, .RenderConfig) {
                name := loc_lookup(render_config_name_cstr(comp_get(w, cell_id, .RenderConfig, RenderConfigComp)))
                rl.DrawTextEx(g_font_body, name, { f32(ix) + uis(3), f32(iy + icon_sz + 6) },
                    uis(10), 0.4, rl.Color{ rc.r, rc.g, rc.b, 200 })
            }
        }
    }
}

stash_handle_grid_input :: proc(w: ^World) {
    mp := rl.GetMousePosition()

    if rl.IsMouseButtonPressed(.LEFT) && g_drag_item_id == -1 {
        col, row, hit := stash_mouse_to_cell(mp.x, mp.y)
        if hit {
            cell_id := local_stash().grid[row * STASH_COLS + col]
            if cell_id != INVALID_ENTITY && world_is_valid(w, cell_id) && world_has_component(w, cell_id, .Item) {
                item := comp_get(w, cell_id, .Item, ItemComp)
                g_drag_origin_x   = item.pack_x
                g_drag_origin_y   = item.pack_y
                g_drag_from_equip = false
                g_drag_from_stash = true
                stash_remove_id(cell_id)
                item.pack_x = -1
                item.pack_y = -1
                g_drag_item_id = cell_id
            }
        }
    }

    if g_drag_item_id == -1 {
        col, row, hit := stash_mouse_to_cell(mp.x, mp.y)
        if hit {
            g_hover_item_id = local_stash().grid[row * STASH_COLS + col]
        }
    }
}

draw_stash_hud :: proc(w: ^World) {
    if !ui_has(.Stash) { return }
    if g_stash_npc_id != INVALID_ENTITY && !world_is_valid(w, g_stash_npc_id) {
        ui_close_top()
        return
    }

    PW := i32(uis(500))
    PH := i32(uis(440))
    px := i32(uis(18))
    py := i32((f32(rl.GetScreenHeight()) - f32(PH)) * 0.5)
    cs := g_inv.cell_sz

    rl.DrawRectangle(px, py, PW, PH, rl.Color{ 8, 6, 4, 252 })
    rl.DrawRectangle(px, py, PW, i32(uis(3)), COL_BRASS)
    rl.DrawRectangleLinesEx({ f32(px), f32(py), f32(PW), f32(PH) }, 2, COL_RULE)

    title := t(.STASH_TITLE)
    title_fs := uis(17)
    tsz := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title, { f32(px) + f32(PW)*0.5 - tsz.x*0.5, f32(py) + uis(14) }, title_fs, 1, COL_PARCH)

    count_buf: [48]u8
    count_s := fmt.bprintf(count_buf[:47], "%d / %d items", local_stash().item_count, STASH_MAX_ITEMS)
    count_buf[len(count_s)] = 0
    count_fs := uis(11)
    count_sz := rl.MeasureTextEx(g_font_body, cstring(&count_buf[0]), count_fs, 0.5)
    rl.DrawTextEx(g_font_body, cstring(&count_buf[0]), { f32(px) + f32(PW)*0.5 - count_sz.x*0.5, f32(py) + uis(42) },
        count_fs, 0.5, COL_MUTED)

    grid_w := STASH_COLS * cs
    grid_h := STASH_ROWS * cs
    g_stash_grid_bb = rl.Rectangle{
        f32(px) + (f32(PW) - f32(grid_w)) * 0.5,
        f32(py) + uis(76),
        f32(grid_w),
        f32(grid_h),
    }

    stash_handle_grid_input(w)
    stash_draw_grid(w, g_stash_grid_bb)

    mp := rl.GetMousePosition()
    btn_r := rl.Rectangle{ f32(px) + uis(16), f32(py + PH) - uis(54), f32(PW) - uis(32), uis(34) }
    hot := rl.CheckCollisionPointRec(mp, btn_r)
    rl.DrawRectangleRec(btn_r, rl.Color{ 74, 54, 18, 245 } if hot else rl.Color{ 42, 31, 14, 235 })
    rl.DrawRectangleLinesEx(btn_r, 1, COL_BRASS if hot else COL_RULE)
    btn_lbl := t(.STASH_DEPOSIT_ALL)
    btn_fs := uis(11)
    btn_sz := rl.MeasureTextEx(g_font_body, btn_lbl, btn_fs, 0.5)
    rl.DrawTextEx(g_font_body, btn_lbl, { btn_r.x + (btn_r.width - btn_sz.x) * 0.5, btn_r.y + (btn_r.height - btn_fs) * 0.5 },
        btn_fs, 0.5, COL_BRASS if hot else COL_PARCH)
    if hot && rl.IsMouseButtonPressed(.LEFT) && g_drag_item_id == -1 {
        if stash_deposit_all_carried(w) == 0 { play_sfx("ui_deny") }
    }

    _draw_drag_item(w)
    if g_hover_item_id != INVALID_ENTITY && g_drag_item_id == -1 {
        draw_item_tooltip_or_compare(w, g_hover_item_id, mp.x, mp.y)
    }
}
