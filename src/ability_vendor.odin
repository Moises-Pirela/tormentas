package main


import "core:math/rand"
import "core:fmt"
import rl  "vendor:raylib"
import cw  "clockwork"


MAX_ABILITY_VENDOR_STOCK  :: 4
ABILITY_VENDOR_SERUM_COST :: 2

ABILITY_VENDOR_PROMPT_DIST :: f32(85)


AVSlot :: struct {
    item_entity: int,
}

g_av_stock:     [MAX_NPC_ENTITIES][MAX_ABILITY_VENDOR_STOCK]AVSlot
g_av_stk_count: [MAX_NPC_ENTITIES]int


g_ability_vendor_npc_id: int = cw.INVALID_ENTITY


ability_vendor_roll_stock :: proc(w: ^cw.World, npc_id: int, level_num: int) {
    slot_idx := npc_id % MAX_NPC_ENTITIES
    g_av_stk_count[slot_idx] = 0

    seed   := loot_seed(u64(level_num), npc_id) ~ 0xdeadbeefcafebabe
    rstate := rand.create(seed)
    context.random_generator = rand.default_random_generator(&rstate)

    pool := ABILITY_DROP_POOL
    n    := min(MAX_ABILITY_VENDOR_STOCK, len(pool))


    indices: [len(ABILITY_DROP_POOL)]int
    for i in 0..<len(pool) { indices[i] = i }
    for i in 0..<n {
        j          := i + rand.int_max(len(pool) - i)
        indices[i], indices[j] = indices[j], indices[i]
    }

    for i in 0..<n {
        at      := pool[indices[i]]
        item_id := create_ability_item(w, at)
        if item_id == cw.INVALID_ENTITY { continue }

        g_av_stock[slot_idx][i] = AVSlot{ item_entity = item_id }
        g_av_stk_count[slot_idx] += 1
    }
}


ability_vendor_clear_stock :: proc(w: ^cw.World, npc_id: int) {
    slot_idx := npc_id % MAX_NPC_ENTITIES
    n := g_av_stk_count[slot_idx]
    for i in 0..<n {
        eid := g_av_stock[slot_idx][i].item_entity
        if cw.world_is_valid(w, eid) {
            cw.world_destroy_entity(w, eid)
        }
        g_av_stock[slot_idx][i] = {}
    }
    g_av_stk_count[slot_idx] = 0
}


update_ability_vendor :: proc(w: ^cw.World) {
    pid := w.player_id
    if !cw.world_is_valid(w, pid) { return }
    if !cw.world_has_component(w, pid, .Transform) { return }

    if ui_has(.AbilityVendor) {

        return
    }

    if g_playing_state != .Gameplay && g_playing_state != .Hub { return }

    player_pos := cw.world_get_transform(w, pid).position

    npc_ids := cw.world_query(w, cw.query_mask(.NPC, .Transform))
    defer delete(npc_ids)
    for nid in npc_ids {
        npc := cw.world_get_npc(w, nid)
        if npc.npc_type != .AbilityVendor { continue }
        nt  := cw.world_get_transform(w, nid)
        dx  := nt.position[0] - player_pos[0]
        dy  := nt.position[1] - player_pos[1]
        if dx*dx + dy*dy <= npc.interact_radius * npc.interact_radius {
            if input_pressed(rl.KeyboardKey(g_binds.gameplay.interact)) {
                g_ability_vendor_npc_id = nid
                ui_open(.AbilityVendor)
            }
            break
        }
    }
}


draw_ability_vendor_world :: proc(w: ^cw.World) {
    if !cw.world_is_valid(w, w.player_id) { return }
    if !cw.world_has_component(w, w.player_id, .Transform) { return }
    player_pos := cw.world_get_transform(w, w.player_id).position

    npc_ids := cw.world_query(w, cw.query_mask(.NPC, .Transform, .RenderConfig))
    defer delete(npc_ids)

    for nid in npc_ids {
        npc := cw.world_get_npc(w, nid)
        if npc.npc_type != .AbilityVendor { continue }

        nt   := cw.world_get_transform(w, nid)
        dx   := nt.position[0] - player_pos[0]
        dy   := nt.position[1] - player_pos[1]
        dist_sq := dx*dx + dy*dy

        pos  := world_to_iso_xy(nt.position[0], nt.position[1])
        rc   := cw.world_get_render_config(w, nid)
        name := loc_lookup(cw.render_config_name_cstr(rc))
        nfs  := f32(10)
        nsz  := rl.MeasureTextEx(g_font_body, name, nfs, 0.5)
        rl.DrawTextEx(g_font_body, name,
            { pos.x - nsz.x*0.5, pos.y - 14 - nfs - 2 },
            nfs, 0.5, rl.Color{ 180, 220, 255, 220 })

        if !ui_has(.AbilityVendor) &&
           dist_sq <= ABILITY_VENDOR_PROMPT_DIST * ABILITY_VENDOR_PROMPT_DIST {
            prompt  := t(.ABILITY_VENDOR_INTERACT)
            pfs     := f32(9)
            psz     := rl.MeasureTextEx(g_font_body, prompt, pfs, 0.5)
            t_now   := f32(rl.GetTime())
            pulse   := u8(180 + 60 * (t_now - f32(int(t_now))))
            rl.DrawTextEx(g_font_body, prompt,
                { pos.x - psz.x*0.5, pos.y + 18 },
                pfs, 0.5, rl.Color{ 180, 220, 255, pulse })
        }
    }
}


@(private = "file")
_av_panel_origin :: proc() -> (px, py: i32) {
    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()
    PW := i32(uis(480))
    PH := i32(uis(520))
    px  = (sw - PW) / 2
    py  = (sh - PH) / 2
    return
}

draw_ability_vendor_hud :: proc(w: ^cw.World) {
    if !ui_has(.AbilityVendor) { return }
    if !cw.world_is_valid(w, g_ability_vendor_npc_id) {
        ui_close_top()
        return
    }

    pid := w.player_id
    mp  := rl.GetMousePosition()
    PW  := i32(uis(480))
    PH  := i32(uis(520))
    px, py := _av_panel_origin()


    rl.DrawRectangle(px, py, PW, PH, rl.Color{ 4, 6, 12, 252 })
    rl.DrawRectangle(px, py, PW, i32(uis(3)), rl.Color{ 120, 160, 220, 255 })
    rl.DrawRectangleLinesEx({ f32(px), f32(py), f32(PW), f32(PH) }, 2, COL_RULE)


    rc       := cw.world_get_render_config(w, g_ability_vendor_npc_id)
    npc_name := loc_lookup(cw.render_config_name_cstr(rc))
    title_fs := uis(20)
    tsz      := rl.MeasureTextEx(g_font, npc_name, title_fs, 1)
    rl.DrawTextEx(g_font, npc_name,
        { f32(px) + f32(PW)*0.5 - tsz.x*0.5, f32(py) + uis(12) },
        title_fs, 1, COL_PARCH)

    sub_cs := t(.ABILITY_VENDOR_SUBTITLE)
    sub_sz := rl.MeasureTextEx(g_font_body, sub_cs, uis(10), 1)
    rl.DrawTextEx(g_font_body, sub_cs,
        { f32(px) + f32(PW)*0.5 - sub_sz.x*0.5,
          f32(py) + uis(12) + title_fs + uis(2) },
        uis(10), 1, COL_MUTED)
    rl.DrawLineEx(
        { f32(px) + uis(16), f32(py) + uis(56) },
        { f32(px + PW) - uis(16), f32(py) + uis(56) }, 1, COL_RULE)


    player_serums := 0
    if cw.world_is_valid(w, pid) && cw.world_has_component(w, pid, .MutationContainer) {
        player_serums = cw.world_get_mutation(w, pid).serums
    }
    {
        buf: [32]u8
        s   := fmt.bprintf(buf[:31], "%d serums", player_serums)
        buf[len(s)] = 0
        sfs  := uis(13)
        ssz  := rl.MeasureTextEx(g_font_body, cstring(&buf[0]), sfs, 1)
        rl.DrawTextEx(g_font_body, cstring(&buf[0]),
            { f32(px + PW) - uis(16) - ssz.x, f32(py) + uis(12) },
            sfs, 1, rl.Color{ 120, 200, 120, 255 })
    }


    slot_idx := g_ability_vendor_npc_id % MAX_NPC_ENTITIES
    n        := g_av_stk_count[slot_idx]
    item_h   := i32(uis(70))
    item_pad := i32(uis(8))
    start_y  := py + i32(uis(66))

    for i in 0..<n {
        ss := &g_av_stock[slot_idx][i]

        iy    := start_y + i32(i) * (item_h + item_pad)
        row_r := rl.Rectangle{
            f32(px + i32(uis(12))), f32(iy),
            f32(PW - i32(uis(24))), f32(item_h),
        }

        if ss.item_entity == cw.INVALID_ENTITY {

            rl.DrawRectangleRec(row_r, rl.Color{ 12, 10, 8, 180 })
            rl.DrawRectangleLinesEx(row_r, 1, rl.Color{ 55, 48, 34, 80 })
            so_cs := t(.SHOP_SOLD_OUT)
            so_fs := uis(11)
            rl.DrawTextEx(g_font_body, so_cs,
                { row_r.x + row_r.width*0.5 - rl.MeasureTextEx(g_font_body, so_cs, so_fs, 0.5).x*0.5,
                  row_r.y + row_r.height*0.5 - so_fs*0.5 },
                so_fs, 0.5, COL_MUTED)
            continue
        }

        if !cw.world_is_valid(w, ss.item_entity) { continue }
        irc := cw.world_get_render_config(w, ss.item_entity)

        is_hot := rl.CheckCollisionPointRec(mp, row_r)
        bg     := rl.Color{ 18, 24, 38, 220 } if is_hot else rl.Color{ 10, 14, 24, 200 }
        rc_col := rl.Color{ 100, 160, 220, 255 }
        rl.DrawRectangleRec(row_r, bg)
        rl.DrawRectangleLinesEx(row_r, 1, rc_col if is_hot else COL_RULE)


        icon_r := f32(uis(20))
        rl.DrawRectangle(
            i32(row_r.x + uis(8)), i32(row_r.y + row_r.height*0.5 - icon_r),
            i32(icon_r*2), i32(icon_r*2), rl.Color{ 20, 30, 50, 255 })
        rl.DrawRectangleLinesEx(
            { row_r.x + uis(8), row_r.y + row_r.height*0.5 - icon_r, icon_r*2, icon_r*2 },
            1, rc_col)


        name_fs := uis(13)
        name_x  := row_r.x + icon_r*2 + uis(18)
        rl.DrawTextEx(g_font_body, loc_lookup(cw.render_config_name_cstr(irc)),
            { name_x, row_r.y + uis(8) }, name_fs, 0.5, rc_col)


        desc_fs := uis(9)
        rl.DrawTextEx(g_font_body, loc_lookup(cw.render_config_desc_cstr(irc)),
            { name_x, row_r.y + uis(8) + name_fs + uis(4) }, desc_fs, 0.5, COL_MUTED)


        rar_fs  := uis(9)
        rl.DrawTextEx(g_font_body, "Epic",
            { name_x, row_r.y + uis(8) + name_fs + uis(4) + desc_fs + uis(3) },
            rar_fs, 0.5, rarity_color(.Epic))


        can_afford := player_serums >= ABILITY_VENDOR_SERUM_COST
        price_buf: [24]u8
        price_str := fmt.bprintf(price_buf[:23], "%d serums", ABILITY_VENDOR_SERUM_COST)
        price_buf[len(price_str)] = 0
        price_fs  := uis(13)
        psz       := rl.MeasureTextEx(g_font_body, cstring(&price_buf[0]), price_fs, 1)
        price_col := rl.Color{ 120, 200, 120, 255 } if can_afford else rl.Color{ 180, 80, 60, 255 }
        rl.DrawTextEx(g_font_body, cstring(&price_buf[0]),
            { row_r.x + row_r.width - uis(12) - psz.x,
              row_r.y + row_r.height*0.5 - price_fs*0.5 },
            price_fs, 1, price_col)


        if is_hot && rl.IsMouseButtonPressed(.LEFT) && can_afford {
            _av_buy(w, i)
        }
    }


    sell_y := start_y + i32(n) * (item_h + item_pad) + i32(uis(8))
    rl.DrawLineEx(
        { f32(px) + uis(16), f32(sell_y) },
        { f32(px + PW) - uis(16), f32(sell_y) }, 1, COL_RULE)


    close_cs := t(.SHOP_ESC_CLOSE)
    close_fs := uis(10)
    rl.DrawTextEx(g_font_body, close_cs,
        { f32(px) + f32(PW)*0.5 -
          rl.MeasureTextEx(g_font_body, close_cs, close_fs, 0.5).x*0.5,
          f32(py + PH) - close_fs - uis(10) },
        close_fs, 0.5, COL_MUTED)
}


@(private = "file")
_av_buy :: proc(w: ^cw.World, stock_i: int) {
    pid := w.player_id
    if !cw.world_is_valid(w, pid)                       { return }
    if !cw.world_has_component(w, pid, .Inventory)      { return }
    if !cw.world_has_component(w, pid, .MutationContainer) { return }

    slot_idx := g_ability_vendor_npc_id % MAX_NPC_ENTITIES
    ss       := &g_av_stock[slot_idx][stock_i]
    if ss.item_entity == cw.INVALID_ENTITY              { return }
    if !cw.world_is_valid(w, ss.item_entity)            { return }

    mc := cw.world_get_mutation(w, pid)
    if mc.serums < ABILITY_VENDOR_SERUM_COST {
        play_sfx("ui_deny")
        return
    }

    inv  := cw.world_get_inventory(w, pid)
    item := cw.world_get_item(w, ss.item_entity)

    col, row, fits := backpack_find_free(inv, item)
    if !fits {
        play_sfx("ui_deny")
        return
    }

    mc.serums -= ABILITY_VENDOR_SERUM_COST
    backpack_place(inv, item, ss.item_entity, col, row)
    ss.item_entity = cw.INVALID_ENTITY

    play_sfx("pickup")
    ui_mark_dirty(.AbilityVendor)
    ui_mark_dirty(.Inventory)

    if cw.world_is_valid(w, pid) {
        save_player(w, pid)
    }
}
