package main


import "core:math/rand"
import "core:fmt"
import rl   "vendor:raylib"
import clay "../clay"


MAX_ABILITY_VENDOR_STOCK  :: 4
ABILITY_VENDOR_SERUM_COST :: 2

ABILITY_VENDOR_PROMPT_DIST :: f32(85)


AVSlot :: struct {
    item_entity: int,
}

g_av_stock:     [MAX_NPC_ENTITIES][MAX_ABILITY_VENDOR_STOCK]AVSlot
g_av_stk_count: [MAX_NPC_ENTITIES]int


g_ability_vendor_npc_id: int = INVALID_ENTITY


ability_vendor_roll_stock :: proc(w: ^World, npc_id: int, level_num: int) {
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
        if item_id == INVALID_ENTITY { continue }

        g_av_stock[slot_idx][i] = AVSlot{ item_entity = item_id }
        g_av_stk_count[slot_idx] += 1
    }
}


ability_vendor_clear_stock :: proc(w: ^World, npc_id: int) {
    slot_idx := npc_id % MAX_NPC_ENTITIES
    n := g_av_stk_count[slot_idx]
    for i in 0..<n {
        eid := g_av_stock[slot_idx][i].item_entity
        if world_is_valid(w, eid) {
            world_destroy_entity(w, eid)
        }
        g_av_stock[slot_idx][i] = {}
    }
    g_av_stk_count[slot_idx] = 0
}


update_ability_vendor :: proc(w: ^World) {
    pid := w.player_id
    if !world_is_valid(w, pid) { return }
    if !world_has_component(w, pid, .Transform) { return }

    if ui_has(.AbilityVendor) {

        return
    }

    if g_playing_state != .Gameplay && g_playing_state != .Hub { return }

    player_pos := comp_get(w, pid, .Transform, TransformComp).position

    npc_ids := world_query(w, query_mask(.NPC, .Transform))
    defer delete(npc_ids)
    for nid in npc_ids {
        npc := comp_get(w, nid, .NPC, NPCComp)
        if npc.npc_type != .AbilityVendor { continue }
        nt  := comp_get(w, nid, .Transform, TransformComp)
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


draw_ability_vendor_world :: proc(w: ^World) {
    if !world_is_valid(w, w.player_id) { return }
    if !world_has_component(w, w.player_id, .Transform) { return }
    player_pos := comp_get(w, w.player_id, .Transform, TransformComp).position

    npc_ids := world_query(w, query_mask(.NPC, .Transform, .RenderConfig))
    defer delete(npc_ids)

    for nid in npc_ids {
        npc := comp_get(w, nid, .NPC, NPCComp)
        if npc.npc_type != .AbilityVendor { continue }

        nt   := comp_get(w, nid, .Transform, TransformComp)
        dx   := nt.position[0] - player_pos[0]
        dy   := nt.position[1] - player_pos[1]
        dist_sq := dx*dx + dy*dy

        pos  := world_to_iso_xy(nt.position[0], nt.position[1])
        rc   := comp_get(w, nid, .RenderConfig, RenderConfigComp)
        name := loc_lookup(render_config_name_cstr(rc))
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


draw_ability_vendor_hud :: proc(w: ^World) {
    if !ui_has(.AbilityVendor) { return }
    if !world_is_valid(w, g_ability_vendor_npc_id) {
        ui_close_top()
        return
    }

    pid := w.player_id
    blue := rl.Color{ 100, 160, 220, 255 }

    rc       := comp_get(w, g_ability_vendor_npc_id, .RenderConfig, RenderConfigComp)
    npc_name := loc_lookup(render_config_name_cstr(rc))

    player_serums := 0
    if world_is_valid(w, pid) && world_has_component(w, pid, .MutationContainer) {
        player_serums = comp_get(w, pid, .MutationContainer, MutationContainerComp).serums
    }
    can_afford := player_serums >= ABILITY_VENDOR_SERUM_COST

    slot_idx := g_ability_vendor_npc_id % MAX_NPC_ENTITIES
    n        := g_av_stk_count[slot_idx]
    item_h   := uis(70)

    clay.BeginLayout()
    ui_panel_begin("AbilityVendorPanel", string(npc_name), uis(480), uis(520), {
        anchor     = .CenterCenter,
        bg_col     = rl.Color{ 4, 6, 12, 252 },
        border_col = COL_RULE,
        accent_col = blue,
        title_col  = COL_PARCH,
        title_fs   = uis(20),
    })
    {
        // Header row: subtitle (left) + serum balance (right)
        ui_hstack_begin("AVHeader", 0, 0, .Center)
        ui_label("AVSub", string(t(.ABILITY_VENDOR_SUBTITLE)), uis(10), COL_MUTED)
        ui_grow("AVHeaderSpc")
        ui_label("AVSerums", fmt.tprintf("%d serums", player_serums), uis(13),
            rl.Color{ 120, 200, 120, 255 })
        ui_hstack_end()

        // Stock list
        ui_vstack_begin("AVList", u16(uis(8)))
        for i in 0..<n {
            ss := &g_av_stock[slot_idx][i]

            if ss.item_entity == INVALID_ENTITY || !world_is_valid(w, ss.item_entity) {
                // Sold-out placeholder
                ui_hstack_begin(fmt.tprintf("AVSold%d", i), 0, u16(uis(10)), .Center)
                ui_grow(fmt.tprintf("AVSoldL%d", i))
                ui_label(fmt.tprintf("AVSoldT%d", i), string(t(.SHOP_SOLD_OUT)), uis(11), COL_MUTED)
                ui_grow(fmt.tprintf("AVSoldR%d", i))
                ui_hstack_end()
                continue
            }

            irc := comp_get(w, ss.item_entity, .RenderConfig, RenderConfigComp)

            hovered := ui_clickable_begin(fmt.tprintf("AVRow%d", i), item_h, blue)
            {
                ui_box(fmt.tprintf("AVIcon%d", i), uis(40), uis(40), rl.Color{ 20, 30, 50, 255 }, 2)
                ui_vstack_begin(fmt.tprintf("AVInfo%d", i), u16(uis(3)))
                ui_label(fmt.tprintf("AVName%d", i),
                    string(loc_lookup(render_config_name_cstr(irc))), uis(13), blue)
                ui_label(fmt.tprintf("AVDesc%d", i),
                    string(loc_lookup(render_config_desc_cstr(irc))), uis(9), COL_MUTED)
                ui_label(fmt.tprintf("AVRar%d", i), "Epic", uis(9), rarity_color(.Epic))
                ui_vstack_end()
                ui_grow(fmt.tprintf("AVRowSpc%d", i))
                price_col := rl.Color{ 120, 200, 120, 255 } if can_afford else rl.Color{ 180, 80, 60, 255 }
                ui_label(fmt.tprintf("AVPrice%d", i),
                    fmt.tprintf("%d serums", ABILITY_VENDOR_SERUM_COST), uis(13), price_col)
            }
            ui_clickable_end()

            if hovered && rl.IsMouseButtonReleased(.LEFT) && can_afford {
                _av_buy(w, i)
            }
        }
        ui_vstack_end()

        // Close hint
        ui_grow("AVSpacer")
        ui_hstack_begin("AVCloseRow", 0, 0, .Center)
        ui_grow("AVCloseL")
        ui_label("AVClose", string(t(.SHOP_ESC_CLOSE)), uis(10), COL_MUTED)
        ui_grow("AVCloseR")
        ui_hstack_end()
    }
    ui_panel_end()
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)
}


@(private = "file")
_av_buy :: proc(w: ^World, stock_i: int) {
    pid := w.player_id
    if !world_is_valid(w, pid)                       { return }
    if !world_has_component(w, pid, .Inventory)      { return }
    if !world_has_component(w, pid, .MutationContainer) { return }

    slot_idx := g_ability_vendor_npc_id % MAX_NPC_ENTITIES
    ss       := &g_av_stock[slot_idx][stock_i]
    if ss.item_entity == INVALID_ENTITY              { return }
    if !world_is_valid(w, ss.item_entity)            { return }

    mc := comp_get(w, pid, .MutationContainer, MutationContainerComp)
    if mc.serums < ABILITY_VENDOR_SERUM_COST {
        play_sfx("ui_deny")
        return
    }

    inv  := comp_get(w, pid, .Inventory, InventoryComp)
    item := comp_get(w, ss.item_entity, .Item, ItemComp)

    col, row, fits := backpack_find_free(inv, item)
    if !fits {
        play_sfx("ui_deny")
        return
    }

    mc.serums -= ABILITY_VENDOR_SERUM_COST
    backpack_place(inv, item, ss.item_entity, col, row)
    ss.item_entity = INVALID_ENTITY

    play_sfx("pickup")
    ui_mark_dirty(.AbilityVendor)
    ui_mark_dirty(.Inventory)

    if world_is_valid(w, pid) {
        save_player(w, pid)
    }
}
