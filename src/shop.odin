package main

import "core:math/rand"
import "core:fmt"
import rl   "vendor:raylib"
import clay "../clay"


MAX_SHOP_STOCK   :: 6
GOLD_DROP_MIN    :: 3
GOLD_DROP_MAX    :: 18

SELL_RATIO :: f32(0.4)


ShopEntry :: struct {
    item_name:  string,
    base_price: int,
}


RARITY_PRICE_MULT := [ItemRarity]int{
    .Normal    = 1,
    .Rare      = 2,
    .Epic      = 4,
    .Legendary = 8,
    .Unique    = 16,
}


@(private = "file")
SHOP_CATALOGUE := [?]ShopEntry{
    { item_name = "ITEM_CORRUPTED_RELIQUARY_NAME", base_price = 30 },
    { item_name = "ITEM_LEATHER_CARAPACE_NAME",    base_price = 40 },
    { item_name = "ITEM_IRON_BULWARK_NAME",        base_price = 65 },
    { item_name = "ITEM_BANDOLIER_RIG_NAME",       base_price = 25 },
    { item_name = "ITEM_ETHEREAL_SHARD_NAME",      base_price = 35 },
    { item_name = "ITEM_COYOTE_STRIDERS_NAME",     base_price = 30 },
    { item_name = "ITEM_BONE_FETISH_NAME",         base_price = 45 },
    { item_name = "ITEM_HAMMERLOCK_PISTOL_NAME",   base_price = 30 },
    { item_name = "ITEM_LIGHTCOIL_REPEATER_NAME",  base_price = 30 },
    { item_name = "ITEM_DRUMFEED_CARBINE_NAME",    base_price = 35 },
    { item_name = "ITEM_DESERT_MACHETE_NAME",      base_price = 50 },
    { item_name = "ITEM_WAR_CLEAVER_NAME",         base_price = 80 },
    { item_name = "ITEM_QUICKFANG_KNIFE_NAME",     base_price = 45 },
    { item_name = "ITEM_NECROTIC_SERUM_NAME",      base_price = 20 },
    { item_name = "ITEM_NECROTIC_SERUM3_NAME",     base_price = 55 },
}


MAX_NPC_ENTITIES :: 32

StockSlot :: struct {
    item_entity: int,
    price:       int,
}


g_shop_stock:     [MAX_NPC_ENTITIES][MAX_SHOP_STOCK]StockSlot
g_shop_stk_count: [MAX_NPC_ENTITIES]int


g_shop_npc_id:  int = INVALID_ENTITY


spawn_gold_drop :: proc(w: ^World, world_pos: [3]f32, amount: int) {
    if amount <= 0 { return }
    id := world_create_entity(w)
    comp_set(w, id, .Transform, TransformComp{ position = world_pos })
    comp_set(w, id, .Gold, GoldComp{ amount = amount })
    comp_add(w, id, .GroundItem)
    comp_add(w, id, .FogOfWar)
}


gold_drop_amount :: proc(tick: u64, entity_id: int) -> int {
    seed   := loot_seed(tick, entity_id) ~ 0x1234567890abcdef
    rstate := rand.create(seed)
    context.random_generator = rand.default_random_generator(&rstate)
    return GOLD_DROP_MIN + rand.int_max(GOLD_DROP_MAX - GOLD_DROP_MIN + 1)
}


shop_roll_stock :: proc(w: ^World, npc_id: int, level_num: int) {
    slot_idx := npc_id % MAX_NPC_ENTITIES
    g_shop_stk_count[slot_idx] = 0

    seed   := loot_seed(u64(level_num), npc_id) ~ 0xfeedfacecafebeef
    rstate := rand.create(seed)
    context.random_generator = rand.default_random_generator(&rstate)


    cat_copy: [len(SHOP_CATALOGUE)]int
    for i in 0..<len(SHOP_CATALOGUE) { cat_copy[i] = i }

    n := min(MAX_SHOP_STOCK, len(SHOP_CATALOGUE))
    for i in 0..<n {
        j      := i + rand.int_max(len(SHOP_CATALOGUE) - i)
        cat_copy[i], cat_copy[j] = cat_copy[j], cat_copy[i]
    }

    for i in 0..<n {
        cat := SHOP_CATALOGUE[cat_copy[i]]
        def := loot_find_by_name(cat.item_name)
        if def == nil { continue }


        item_id := world_create_entity(w)
        comp_set(w, item_id, .Transform, TransformComp{})

        item_comp := item_empty()
        item_comp.slot               = def.slot
        item_comp.rarity             = roll_rarity()
        item_comp.mutation_type      = def.mutation_type
        item_comp.serum_value        = def.serum_value
        item_comp.grid_w             = def.grid_w
        item_comp.grid_h             = def.grid_h
        item_comp.req_str            = def.req_str
        item_comp.req_dex            = def.req_dex
        item_comp.req_sci            = def.req_sci
        item_comp.is_two_handed      = def.is_two_handed
        item_comp.is_melee           = def.is_melee
        item_comp.melee_damage       = def.melee_damage
        item_comp.melee_range        = def.melee_range
        item_comp.melee_spread       = def.melee_spread
        item_comp.melee_cooldown_max = def.melee_cooldown_max
        item_comp.weapon_archetype   = def.weapon_archetype
        item_comp.base_damage        = def.base_damage
        item_comp.base_fire_rate     = def.base_fire_rate
        item_comp.base_ammo_max      = def.base_ammo_max
        item_comp.base_reload_time   = def.base_reload_time
        item_comp.base_proj_speed    = def.base_proj_speed
        item_comp.base_armor         = def.base_armor
        item_comp.base_shield        = def.base_shield
        item_comp.affix_count        = def.base_affix_count
        for affix in 0..<int(def.base_affix_count) { item_comp.affixes[affix] = def.base_affixes[affix] }
        roll_affixes(&item_comp)
        comp_set(w, item_id, .Item, item_comp)

        rc: RenderConfigComp
        render_config_set_name(&rc, def.name)
        render_config_set_icon(&rc, def.icon)
        render_config_set_desc(&rc, def.desc)
        comp_set(w, item_id, .RenderConfig, rc)

        price := cat.base_price * RARITY_PRICE_MULT[item_comp.rarity]
        g_shop_stock[slot_idx][i] = StockSlot{
            item_entity = item_id,
            price       = price,
        }
        g_shop_stk_count[slot_idx] += 1
    }
}


shop_clear_stock :: proc(w: ^World, npc_id: int) {
    slot_idx := npc_id % MAX_NPC_ENTITIES
    n := g_shop_stk_count[slot_idx]
    for i in 0..<n {
        eid := g_shop_stock[slot_idx][i].item_entity
        if world_is_valid(w, eid) {
            world_destroy_entity(w, eid)
        }
        g_shop_stock[slot_idx][i] = {}
    }
    g_shop_stk_count[slot_idx] = 0
}


SHOP_INTERACT_PROMPT_DIST :: f32(85)


update_shop :: proc(w: ^World) {
    pid := w.player_id
    if !world_is_valid(w, pid) { return }
    if !world_has_component(w, pid, .Transform) { return }
    player_pos := comp_get(w, pid, .Transform, TransformComp).position

    if ui_has(.Shop) {
        _update_shop_panel(w)
        return
    }
    if g_playing_state != .Gameplay && g_playing_state != .Hub { return }


    npc_ids := world_query(w, query_mask(.NPC, .Transform))
    defer delete(npc_ids)
    for nid in npc_ids {
        npc := comp_get(w, nid, .NPC, NPCComp)
        if npc.npc_type != .Shopkeeper { continue }
        nt  := comp_get(w, nid, .Transform, TransformComp)
        dx  := nt.position[0] - player_pos[0]
        dy  := nt.position[1] - player_pos[1]
        if dx*dx + dy*dy <= npc.interact_radius * npc.interact_radius {
            if input_pressed(rl.KeyboardKey(g_binds.gameplay.interact)) {
                g_shop_npc_id = nid
                ui_open(.Shop)
            }
            break
        }
    }
}


draw_shop_world :: proc(w: ^World) {
    if !world_has_component(w, w.player_id, .Transform) { return }
    player_pos := comp_get(w, w.player_id, .Transform, TransformComp).position

    npc_ids := world_query(w, query_mask(.NPC, .Transform, .RenderConfig))
    defer delete(npc_ids)

    for nid in npc_ids {
        npc := comp_get(w, nid, .NPC, NPCComp)
        if npc.npc_type != .Shopkeeper { continue }

        nt  := comp_get(w, nid, .Transform, TransformComp)
        dx  := nt.position[0] - player_pos[0]
        dy  := nt.position[1] - player_pos[1]
        dist_sq := dx*dx + dy*dy


        pos := world_to_iso_xy(nt.position[0], nt.position[1])
        rc   := comp_get(w, nid, .RenderConfig, RenderConfigComp)
        name := loc_lookup(render_config_name_cstr(rc))
        nfs  := f32(10)
        nsz  := rl.MeasureTextEx(g_font_body, name, nfs, 0.5)
        rl.DrawTextEx(g_font_body, name,
            { pos.x - nsz.x*0.5, pos.y - 14 - nfs - 2 },
            nfs, 0.5, rl.Color{ 240, 215, 120, 220 })


        if !ui_has(.Shop) && dist_sq <= SHOP_INTERACT_PROMPT_DIST * SHOP_INTERACT_PROMPT_DIST {
            prompt    := t(.SHOP_INTERACT)
            pfs       := f32(9)
            psz       := rl.MeasureTextEx(g_font_body, prompt, pfs, 0.5)
            t_now     := f32(rl.GetTime())
            pulse     := u8(180 + 60 * (t_now - f32(int(t_now))))
            rl.DrawTextEx(g_font_body, prompt,
                { pos.x - psz.x*0.5, pos.y + 18 },
                pfs, 0.5, rl.Color{ 255, 230, 100, pulse })
        }
    }
}


draw_shop_hud :: proc(w: ^World) {
    if !ui_has(.Shop) { return }
    if !world_is_valid(w, g_shop_npc_id) {
        ui_close_top()
        return
    }

    pid := w.player_id

    rc       := comp_get(w, g_shop_npc_id, .RenderConfig, RenderConfigComp)
    npc_name := loc_lookup(render_config_name_cstr(rc))

    wallet_gold := 0
    if world_is_valid(w, pid) && world_has_component(w, pid, .Wallet) {
        wallet_gold = comp_get(w, pid, .Wallet, WalletComp).gold
    }

    slot_idx := g_shop_npc_id % MAX_NPC_ENTITIES
    n        := g_shop_stk_count[slot_idx]
    item_h   := uis(60)

    clay.BeginLayout()
    // Shift left by half the inventory panel width — the inventory is docked on the
    // right while the shop is open, so the shop centers in the area left of it.
    ui_panel_begin("ShopPanel", string(npc_name), uis(480), uis(520), {
        anchor     = .CenterCenter,
        offset     = { -f32(g_inv.panel_w) * 0.5, 0 },
        bg_col     = rl.Color{ 8, 6, 4, 252 },
        border_col = COL_RULE,
        accent_col = COL_BRASS,
        title_col  = COL_PARCH,
        title_fs   = uis(20),
    })
    {
        // Header row: shop subtitle (left) + wallet gold (right)
        ui_hstack_begin("ShopHeader", 0, 0, .Center)
        ui_label("ShopSub", string(t(.SHOP_TITLE)), uis(10), COL_MUTED)
        ui_grow("ShopHeaderSpc")
        ui_label("ShopGold", string(tf(.SHOP_GOLD, wallet_gold)), uis(13),
            rl.Color{ 255, 215, 50, 255 })
        ui_hstack_end()

        // Stock list
        ui_vstack_begin("ShopList", u16(uis(8)))
        for i in 0..<n {
            ss := &g_shop_stock[slot_idx][i]

            if ss.item_entity == INVALID_ENTITY || !world_is_valid(w, ss.item_entity) {
                ui_hstack_begin(fmt.tprintf("ShopSold%d", i), 0, u16(uis(8)), .Center)
                ui_grow(fmt.tprintf("ShopSoldL%d", i))
                ui_label(fmt.tprintf("ShopSoldT%d", i), string(t(.SHOP_SOLD_OUT)), uis(11), COL_MUTED)
                ui_grow(fmt.tprintf("ShopSoldR%d", i))
                ui_hstack_end()
                continue
            }

            item := comp_get(w, ss.item_entity, .Item, ItemComp)
            irc  := comp_get(w, ss.item_entity, .RenderConfig, RenderConfigComp)
            rc_col := rarity_color(item.rarity)
            can_afford := wallet_gold >= ss.price

            hovered := ui_clickable_begin(fmt.tprintf("ShopRow%d", i), item_h, rc_col)
            {
                ui_box(fmt.tprintf("ShopIcon%d", i), uis(36), uis(36), rl.Color{ 40, 34, 22, 255 }, 2)
                ui_vstack_begin(fmt.tprintf("ShopInfo%d", i), u16(uis(3)))
                ui_label(fmt.tprintf("ShopName%d", i),
                    string(loc_lookup(render_config_name_cstr(irc))), uis(12), rc_col)
                ui_label(fmt.tprintf("ShopDesc%d", i),
                    string(loc_lookup(render_config_desc_cstr(irc))), uis(9), COL_MUTED)
                ui_vstack_end()
                ui_grow(fmt.tprintf("ShopRowSpc%d", i))
                price_col := rl.Color{255, 215, 50, 255} if can_afford else rl.Color{180, 80, 60, 255}
                ui_label(fmt.tprintf("ShopPrice%d", i),
                    fmt.tprintf("%d g", ss.price), uis(13), price_col)
            }
            ui_clickable_end()

            if hovered && rl.IsMouseButtonReleased(.LEFT) && can_afford {
                _shop_buy(w, i)
            }
        }
        ui_vstack_end()

        // Sell section header
        ui_divider("ShopSellDiv")
        ui_label("ShopSell", string(t(.SHOP_SELL)), uis(11), COL_MUTED)

        // Close hint
        ui_grow("ShopSpacer")
        ui_hstack_begin("ShopCloseRow", 0, 0, .Center)
        ui_grow("ShopCloseL")
        ui_label("ShopClose", string(t(.SHOP_ESC_CLOSE)), uis(10), COL_MUTED)
        ui_grow("ShopCloseR")
        ui_hstack_end()
    }
    ui_panel_end()
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)
}


@(private = "file")
_update_shop_panel :: proc(w: ^World) {


    if g_sell_item_id != INVALID_ENTITY {
        _shop_sell(w, g_sell_item_id)
        g_sell_item_id = INVALID_ENTITY
    }
}

@(private = "file")
_shop_buy :: proc(w: ^World, stock_i: int) {
    pid := w.player_id
    if !world_is_valid(w, pid) { return }
    if !world_has_component(w, pid, .Inventory) { return }
    if !world_has_component(w, pid, .Wallet)    { return }

    slot_idx := g_shop_npc_id % MAX_NPC_ENTITIES
    ss       := &g_shop_stock[slot_idx][stock_i]
    if ss.item_entity == INVALID_ENTITY { return }

    wallet := comp_get(w, pid, .Wallet, WalletComp)
    if wallet.gold < ss.price { return }

    inv  := comp_get(w, pid, .Inventory, InventoryComp)
    item := comp_get(w, ss.item_entity, .Item, ItemComp)

    col, row, fits := backpack_find_free(inv, item)
    if !fits {
        play_sfx("ui_deny")
        return
    }

    wallet.gold -= ss.price
    backpack_place(inv, item, ss.item_entity, col, row)
    ss.item_entity = INVALID_ENTITY
    play_sfx("pickup")
    ui_mark_dirty(.Shop)
    ui_mark_dirty(.Inventory)
    if world_is_valid(w, pid) {
        save_player(w, pid)
    }
}


shop_sell_price :: proc(item: ^ItemComp, base_price: int) -> int {
    p := int(f32(base_price * RARITY_PRICE_MULT[item.rarity]) * SELL_RATIO)
    return max(p, 1)
}

item_gold_value :: proc(item: ^ItemComp) -> int {
    base := 25
    for ce in SHOP_CATALOGUE {
        def := loot_find_by_name(ce.item_name)
        if def == nil { continue }
        if def.slot == item.slot && def.is_melee == item.is_melee {
            base = ce.base_price
            break
        }
    }
    return shop_sell_price(item, base)
}

@(private = "file")
_shop_sell :: proc(w: ^World, item_id: int) {
    pid := w.player_id
    if !world_is_valid(w, pid)                   { return }
    if !world_has_component(w, pid, .Inventory)  { return }
    if !world_has_component(w, pid, .Wallet)     { return }
    if !world_is_valid(w, item_id)               { return }
    if !world_has_component(w, item_id, .Item)   { return }

    inv  := comp_get(w, pid, .Inventory, InventoryComp)
    item := comp_get(w, item_id, .Item, ItemComp)


    base_price := 25
    for ce in SHOP_CATALOGUE {
        def := loot_find_by_name(ce.item_name)
        if def == nil { continue }
        if def.slot == item.slot && def.is_melee == item.is_melee {
            base_price = ce.base_price
            break
        }
    }

    sell_val := shop_sell_price(item, base_price)


    backpack_remove(inv, item)

    for &slot in inv.equipped {
        if slot == item_id { slot = INVALID_ENTITY }
    }

    wallet := comp_get(w, pid, .Wallet, WalletComp)
    wallet.gold += sell_val
    play_sfx("pickup")
    ui_mark_dirty(.Shop)
    ui_mark_dirty(.Inventory)

    world_destroy_entity(w, item_id)

    save_player(w, pid)
}


g_sell_item_id: int = INVALID_ENTITY
