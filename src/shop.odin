package main

import "core:math/rand"
import "core:fmt"
import rl  "vendor:raylib"
import cw  "clockwork"

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

MAX_SHOP_STOCK   :: 6    // max items any shopkeeper stocks at once
GOLD_DROP_MIN    :: 3    // min coins per enemy kill
GOLD_DROP_MAX    :: 18   // max coins per enemy kill
INTERACT_KEY     :: rl.KeyboardKey.E

// Base sell price = buy price × SELL_RATIO
SELL_RATIO :: f32(0.4)

// ---------------------------------------------------------------------------
// Shop catalogue — defines what shopkeepers can stock and at what base price.
// ---------------------------------------------------------------------------

ShopEntry :: struct {
    loot_idx:   int,    // index into LOOT_TABLE in items.odin
    base_price: int,    // gold cost at rarity Normal; multiplied by rarity
}

// Rarity price multipliers
RARITY_PRICE_MULT := [cw.ItemRarity]int{
    .Normal    = 1,
    .Rare      = 2,
    .Epic      = 4,
    .Legendary = 8,
    .Unique    = 16,
}

// SHOP_CATALOGUE lists every item a shopkeeper might carry.
// Indices must match LOOT_TABLE order in items.odin.
@(private = "file")
SHOP_CATALOGUE := [?]ShopEntry{
    { loot_idx = 0,  base_price = 30  },   // Reliquia Corrupta
    { loot_idx = 1,  base_price = 40  },   // Coraza de Cuero
    { loot_idx = 2,  base_price = 65  },   // Coraza de Hierro
    { loot_idx = 3,  base_price = 25  },   // Cartucho
    { loot_idx = 4,  base_price = 35  },   // Fragmento Etéreo
    { loot_idx = 5,  base_price = 30  },   // Botas de Coyote
    { loot_idx = 6,  base_price = 45  },   // Fetiche de Hueso
    { loot_idx = 7,  base_price = 30  },   // Percutor Reforzado
    { loot_idx = 8,  base_price = 30  },   // Resorte Ligero
    { loot_idx = 9,  base_price = 35  },   // Cargador Extendido
    { loot_idx = 10, base_price = 50  },   // Machete del Desierto
    { loot_idx = 11, base_price = 80  },   // Hacha de Guerra
    { loot_idx = 12, base_price = 45  },   // Navaja Veloz
    { loot_idx = 13, base_price = 20  },   // Suero Necrótico
    { loot_idx = 14, base_price = 55  },   // Suero Necrótico x3
}

// ---------------------------------------------------------------------------
// Per-shopkeeper stock (rolled at level load, stored on the main package side)
// ---------------------------------------------------------------------------

// MAX_NPC_ENTITIES is a generous upper bound for the per-NPC stock table.
MAX_NPC_ENTITIES :: 32

StockSlot :: struct {
    item_entity: int,    // entity ID of the item-for-sale (INVALID_ENTITY = sold out)
    price:       int,    // gold cost after rarity multiplier
}

// g_shop_stock holds the stock for each NPC (indexed by entity ID mod MAX_NPC_ENTITIES).
// Populated by shop_roll_stock; consumed by the buy logic.
g_shop_stock:     [MAX_NPC_ENTITIES][MAX_SHOP_STOCK]StockSlot
g_shop_stk_count: [MAX_NPC_ENTITIES]int

// ---------------------------------------------------------------------------
// UI state (render-only; not part of the lockstep sim)
// ---------------------------------------------------------------------------

g_shop_npc_id:  int = cw.INVALID_ENTITY

// ---------------------------------------------------------------------------
// Gold drop
// ---------------------------------------------------------------------------

// spawn_gold_drop creates a ground coin pile at world_pos.
// amount is pre-computed deterministically by the caller (damage_system).
spawn_gold_drop :: proc(w: ^cw.World, world_pos: [3]f32, amount: int) {
    if amount <= 0 { return }
    id := cw.world_create_entity(w)
    cw.world_set_transform(w, id, cw.TransformComp{ position = world_pos })
    cw.world_set_gold(w, id, cw.GoldComp{ amount = amount })
    cw.world_set_ground_item(w, id)
    cw.world_set_fog_of_war(w, id)
}

// gold_drop_amount returns a deterministic coin count for a dying enemy.
gold_drop_amount :: proc(tick: u64, entity_id: int) -> int {
    seed   := loot_seed(tick, entity_id) ~ 0x1234567890abcdef
    rstate := rand.create(seed)
    context.random_generator = rand.default_random_generator(&rstate)
    return GOLD_DROP_MIN + rand.int_max(GOLD_DROP_MAX - GOLD_DROP_MIN + 1)
}

// ---------------------------------------------------------------------------
// Stock generation (called from level_apply — deterministic)
// ---------------------------------------------------------------------------

// shop_roll_stock generates stock for a shopkeeper NPC.
// seed = loot_seed(level_num, npc_entity_id) — identical on both instances.
shop_roll_stock :: proc(w: ^cw.World, npc_id: int, level_num: int) {
    slot_idx := npc_id % MAX_NPC_ENTITIES
    g_shop_stk_count[slot_idx] = 0

    seed   := loot_seed(u64(level_num), npc_id) ~ 0xfeedfacecafebeef
    rstate := rand.create(seed)
    context.random_generator = rand.default_random_generator(&rstate)

    // Pick MAX_SHOP_STOCK unique entries from the catalogue
    cat_copy: [len(SHOP_CATALOGUE)]int
    for i in 0..<len(SHOP_CATALOGUE) { cat_copy[i] = i }
    // Partial Fisher-Yates
    n := min(MAX_SHOP_STOCK, len(SHOP_CATALOGUE))
    for i in 0..<n {
        j      := i + rand.int_max(len(SHOP_CATALOGUE) - i)
        cat_copy[i], cat_copy[j] = cat_copy[j], cat_copy[i]
    }

    for i in 0..<n {
        cat := SHOP_CATALOGUE[cat_copy[i]]
        def := &LOOT_TABLE[cat.loot_idx]

        // Spawn the item entity (not as GroundItem — it lives in the shop)
        item_id := cw.world_create_entity(w)
        cw.world_set_transform(w, item_id, cw.TransformComp{})   // no world pos needed

        item_comp := cw.item_empty()
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
        roll_affixes(&item_comp)
        cw.world_set_item(w, item_id, item_comp)

        rc: cw.RenderConfigComp
        cw.render_config_set_name(&rc, def.name)
        cw.render_config_set_icon(&rc, def.icon)
        cw.render_config_set_desc(&rc, def.desc)
        cw.world_set_render_config(w, item_id, rc)

        price := cat.base_price * RARITY_PRICE_MULT[item_comp.rarity]
        g_shop_stock[slot_idx][i] = StockSlot{
            item_entity = item_id,
            price       = price,
        }
        g_shop_stk_count[slot_idx] += 1
    }
}

// shop_clear_stock destroys item entities and resets the stock table for a slot.
shop_clear_stock :: proc(w: ^cw.World, npc_id: int) {
    slot_idx := npc_id % MAX_NPC_ENTITIES
    n := g_shop_stk_count[slot_idx]
    for i in 0..<n {
        eid := g_shop_stock[slot_idx][i].item_entity
        if cw.world_is_valid(w, eid) {
            cw.world_destroy_entity(w, eid)
        }
        g_shop_stock[slot_idx][i] = {}
    }
    g_shop_stk_count[slot_idx] = 0
}

// ---------------------------------------------------------------------------
// UI update / draw
// ---------------------------------------------------------------------------

SHOP_INTERACT_PROMPT_DIST :: f32(85)   // show "E: shop" prompt within this range

// update_shop handles keyboard interaction with the shop UI.
// In Shop substate: processes panel input.
// In Gameplay substate: checks proximity and opens on [E].
update_shop :: proc(w: ^cw.World) {
    pid := w.player_id
    if !cw.world_is_valid(w, pid) { return }
    if !cw.world_has_component(w, pid, .Transform) { return }
    player_pos := cw.world_get_transform(w, pid).position

    if g_playing_state == .Shop {
        _update_shop_panel(w)
        return
    }
    if g_playing_state != .Gameplay && g_playing_state != .Hub { return }

    // Proximity check — open on E (only from Gameplay)
    npc_ids := cw.world_query(w, cw.query_mask(.NPC, .Transform))
    defer delete(npc_ids)
    for nid in npc_ids {
        npc := cw.world_get_npc(w, nid)
        if npc.npc_type != .Shopkeeper { continue }
        nt  := cw.world_get_transform(w, nid)
        dx  := nt.position[0] - player_pos[0]
        dy  := nt.position[1] - player_pos[1]
        if dx*dx + dy*dy <= npc.interact_radius * npc.interact_radius {
            if rl.IsKeyPressed(INTERACT_KEY) {
                g_shop_npc_id = nid
                set_playing_state(.Shop)
            }
            break
        }
    }
}

// draw_shop renders the shop panel and the world-space "E: shop" prompt.
// Call from draw_playing — the panel part should be outside BeginMode2D.
draw_shop_world :: proc(w: ^cw.World) {
    if !cw.world_has_component(w, w.player_id, .Transform) { return }
    player_pos := cw.world_get_transform(w, w.player_id).position

    npc_ids := cw.world_query(w, cw.query_mask(.NPC, .Transform, .RenderConfig))
    defer delete(npc_ids)

    for nid in npc_ids {
        npc := cw.world_get_npc(w, nid)
        if npc.npc_type != .Shopkeeper { continue }
        
        nt  := cw.world_get_transform(w, nid)
        dx  := nt.position[0] - player_pos[0]
        dy  := nt.position[1] - player_pos[1]
        dist_sq := dx*dx + dy*dy

        // Name tag
        pos := world_to_iso_xy(nt.position[0], nt.position[1])
        rc   := cw.world_get_render_config(w, nid)
        name := cw.render_config_name_cstr(rc)
        nfs  := f32(10)
        nsz  := rl.MeasureTextEx(g_font, name, nfs, 0.5)
        rl.DrawTextEx(g_font, name,
            { pos.x - nsz.x*0.5, pos.y - 14 - nfs - 2 },
            nfs, 0.5, rl.Color{ 240, 215, 120, 220 })

        // "E: Shop" prompt when nearby
        if g_playing_state != .Shop && dist_sq <= SHOP_INTERACT_PROMPT_DIST * SHOP_INTERACT_PROMPT_DIST {
            prompt    := cstring("[E] Shop")
            pfs       := f32(9)
            psz       := rl.MeasureTextEx(g_font, prompt, pfs, 0.5)
            t_now     := f32(rl.GetTime())
            pulse     := u8(180 + 60 * (t_now - f32(int(t_now))))   // 180-240 flicker
            rl.DrawTextEx(g_font, prompt,
                { pos.x - psz.x*0.5, pos.y + 18 },
                pfs, 0.5, rl.Color{ 255, 230, 100, pulse })
        }
    }
}

// draw_shop_hud draws the full shop panel (call outside BeginMode2D).
draw_shop_hud :: proc(w: ^cw.World) {
    if g_playing_state != .Shop { return }
    if !cw.world_is_valid(w, g_shop_npc_id) {
        set_playing_state(.Gameplay)
        return
    }

    mp      := rl.GetMousePosition()
    PW      := i32(uis(480))
    PH      := i32(uis(520))
    px, py  := shop_panel_origin()

    // Backdrop
    rl.DrawRectangle(px, py, PW, PH, rl.Color{ 8, 6, 4, 252 })
    rl.DrawRectangle(px, py, PW, i32(uis(3)), COL_BRASS)
    rl.DrawRectangleLinesEx({ f32(px), f32(py), f32(PW), f32(PH) }, 2, COL_RULE)

    // Title
    rc       := cw.world_get_render_config(w, g_shop_npc_id)
    npc_name := cw.render_config_name_cstr(rc)
    title_fs := uis(20)
    tsz      := rl.MeasureTextEx(g_font, npc_name, title_fs, 1)
    rl.DrawTextEx(g_font, npc_name,
        { f32(px) + f32(PW)*0.5 - tsz.x*0.5, f32(py) + uis(12) },
        title_fs, 1, COL_PARCH)
    rl.DrawTextEx(g_font, cstring("TIENDA"),
        { f32(px) + f32(PW)*0.5 - rl.MeasureTextEx(g_font, "TIENDA", uis(10), 1).x*0.5,
          f32(py) + uis(12) + title_fs + uis(2) },
        uis(10), 1, COL_MUTED)
    rl.DrawLineEx(
        { f32(px) + uis(16), f32(py) + uis(56) },
        { f32(px + PW) - uis(16), f32(py) + uis(56) }, 1, COL_RULE)

    // Player wallet
    wallet_gold := 0
    pid := w.player_id
    if cw.world_is_valid(w, pid) && cw.world_has_component(w, pid, .Wallet) {
        wallet_gold = cw.world_get_wallet(w, pid).gold
    }
    gold_str: [32]u8
    gold_label := fmt.bprintf(gold_str[:31], "Gold: %d", wallet_gold)
    gold_str[len(gold_label)] = 0
    gfs := uis(13)
    rl.DrawTextEx(g_font, cstring(&gold_str[0]),
        { f32(px + PW) - uis(16) - rl.MeasureTextEx(g_font, cstring(&gold_str[0]), gfs, 1).x,
          f32(py) + uis(12) },
        gfs, 1, rl.Color{ 255, 215, 50, 255 })

    // Stock items
    slot_idx := g_shop_npc_id % MAX_NPC_ENTITIES
    n        := g_shop_stk_count[slot_idx]
    item_h   := i32(uis(60))
    item_pad := i32(uis(8))
    start_y  := py + i32(uis(66))

    for i in 0..<n {
        ss := &g_shop_stock[slot_idx][i]
        if ss.item_entity == cw.INVALID_ENTITY {
            // Sold-out slot
            iy := start_y + i32(i) * (item_h + item_pad)
            rl.DrawRectangle(px + i32(uis(12)), iy, PW - i32(uis(24)), item_h,
                rl.Color{ 12, 10, 8, 180 })
            rl.DrawRectangleLinesEx(
                { f32(px + i32(uis(12))), f32(iy), f32(PW - i32(uis(24))), f32(item_h) },
                1, rl.Color{ 55, 48, 34, 80 })
            so_fs := uis(11)
            rl.DrawTextEx(g_font, cstring("Sold out"),
                { f32(px) + f32(PW)*0.5 - rl.MeasureTextEx(g_font,"Sold out",so_fs,0.5).x*0.5,
                  f32(iy) + f32(item_h)*0.5 - so_fs*0.5 },
                so_fs, 0.5, COL_MUTED)
            continue
        }

        if !cw.world_is_valid(w, ss.item_entity) { continue }
        item := cw.world_get_item(w, ss.item_entity)
        irc  := cw.world_get_render_config(w, ss.item_entity)

        iy      := start_y + i32(i) * (item_h + item_pad)
        row_r   := rl.Rectangle{ f32(px + i32(uis(12))), f32(iy),
                                  f32(PW - i32(uis(24))), f32(item_h) }
        is_hot  := rl.CheckCollisionPointRec(mp, row_r)
        bg        := rl.Color{ 28, 22, 14, 220 } if is_hot else rl.Color{ 16, 12, 8, 200 }
        rc_col    := rarity_color(item.rarity)
        rc_border := rc_col
        rl.DrawRectangleRec(row_r, bg)
        rl.DrawRectangleLinesEx(row_r, 1, rc_border if is_hot else COL_RULE)

        // Icon placeholder
        icon_r := f32(uis(18))
        rl.DrawRectangle(
            i32(row_r.x + uis(8)), i32(row_r.y + f32(item_h)*0.5 - icon_r),
            i32(icon_r*2), i32(icon_r*2), rl.Color{ 40, 34, 22, 255 })
        rl.DrawRectangleLinesEx(
            { row_r.x + uis(8), row_r.y + f32(item_h)*0.5 - icon_r, icon_r*2, icon_r*2 },
            1, rc_col)

        // Name + rarity
        name_fs := uis(12)
        name_x  := row_r.x + icon_r*2 + uis(18)
        name_col := rarity_color(item.rarity)
        rl.DrawTextEx(g_font, cw.render_config_name_cstr(irc),
            { name_x, row_r.y + uis(8) }, name_fs, 0.5, name_col)

        // Description
        desc_fs := uis(9)
        rl.DrawTextEx(g_font, cw.render_config_desc_cstr(irc),
            { name_x, row_r.y + uis(8) + name_fs + uis(3) }, desc_fs, 0.5, COL_MUTED)

        // Price
        price_buf: [24]u8
        price_str := fmt.bprintf(price_buf[:23], "%d g", ss.price)
        price_buf[len(price_str)] = 0
        price_fs  := uis(13)
        psz       := rl.MeasureTextEx(g_font, cstring(&price_buf[0]), price_fs, 1)
        can_afford := wallet_gold >= ss.price
        price_col  := rl.Color{255, 215, 50, 255} if can_afford else rl.Color{180, 80, 60, 255}
        rl.DrawTextEx(g_font, cstring(&price_buf[0]),
            { row_r.x + row_r.width - uis(12) - psz.x,
              row_r.y + f32(item_h)*0.5 - price_fs*0.5 },
            price_fs, 1, price_col)

        // Buy on click
        if is_hot && rl.IsMouseButtonPressed(.LEFT) && can_afford {
            _shop_buy(w, i)
        }
    }

    // Sell section header
    sell_y := start_y + i32(n) * (item_h + item_pad) + i32(uis(8))
    rl.DrawLineEx(
        { f32(px) + uis(16), f32(sell_y) },
        { f32(px + PW) - uis(16), f32(sell_y) }, 1, COL_RULE)
    sell_hdr_fs := uis(11)
    rl.DrawTextEx(g_font, cstring("SELL  (click an item in your backpack)"),
        { f32(px) + uis(16), f32(sell_y) + uis(5) }, sell_hdr_fs, 0.5, COL_MUTED)

    // Close hint
    close_fs := uis(10)
    rl.DrawTextEx(g_font, cstring("ESC — close"),
        { f32(px) + f32(PW)*0.5 - rl.MeasureTextEx(g_font,"ESC — close",close_fs,0.5).x*0.5,
          f32(py + PH) - close_fs - uis(10) },
        close_fs, 0.5, COL_MUTED)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

@(private = "file")
_update_shop_panel :: proc(w: ^cw.World) {
    // Selling: player can right-click items in their inventory while shop is open.
    // The inventory draw procs handle the click; this is the execution side.
    // (Handled via g_sell_item_id set by inventory UI, consumed here.)
    if g_sell_item_id != cw.INVALID_ENTITY {
        _shop_sell(w, g_sell_item_id)
        g_sell_item_id = cw.INVALID_ENTITY
    }
}

@(private = "file")
_shop_buy :: proc(w: ^cw.World, stock_i: int) {
    pid := w.player_id
    if !cw.world_is_valid(w, pid) { return }
    if !cw.world_has_component(w, pid, .Inventory) { return }
    if !cw.world_has_component(w, pid, .Wallet)    { return }

    slot_idx := g_shop_npc_id % MAX_NPC_ENTITIES
    ss       := &g_shop_stock[slot_idx][stock_i]
    if ss.item_entity == cw.INVALID_ENTITY { return }

    wallet := cw.world_get_wallet(w, pid)
    if wallet.gold < ss.price { return }

    inv  := cw.world_get_inventory(w, pid)
    item := cw.world_get_item(w, ss.item_entity)

    col, row, fits := backpack_find_free(inv, item)
    if !fits {
        play_sfx("ui_deny")
        return
    }

    wallet.gold -= ss.price
    backpack_place(inv, item, ss.item_entity, col, row)
    ss.item_entity = cw.INVALID_ENTITY
    play_sfx("pickup")
    if cw.world_is_valid(w, pid) {
        save_player(w, pid)
    }
}

// Sell price = buy price × SELL_RATIO (at least 1 gold)
shop_sell_price :: proc(item: ^cw.ItemComp, base_price: int) -> int {
    p := int(f32(base_price * RARITY_PRICE_MULT[item.rarity]) * SELL_RATIO)
    return max(p, 1)
}

item_gold_value :: proc(item: ^cw.ItemComp) -> int {
    base := 25
    for ce in SHOP_CATALOGUE {
        def := &LOOT_TABLE[ce.loot_idx]
        if def.slot == item.slot && def.is_melee == item.is_melee {
            base = ce.base_price
            break
        }
    }
    return shop_sell_price(item, base)
}

@(private = "file")
_shop_sell :: proc(w: ^cw.World, item_id: int) {
    pid := w.player_id
    if !cw.world_is_valid(w, pid)                   { return }
    if !cw.world_has_component(w, pid, .Inventory)  { return }
    if !cw.world_has_component(w, pid, .Wallet)     { return }
    if !cw.world_is_valid(w, item_id)               { return }
    if !cw.world_has_component(w, item_id, .Item)   { return }

    inv  := cw.world_get_inventory(w, pid)
    item := cw.world_get_item(w, item_id)

    // Find the base price from the catalogue by matching slot + is_melee flags
    base_price := 25   // fallback
    for ce in SHOP_CATALOGUE {
        def := &LOOT_TABLE[ce.loot_idx]
        if def.slot == item.slot && def.is_melee == item.is_melee {
            base_price = ce.base_price
            break
        }
    }

    sell_val := shop_sell_price(item, base_price)

    // Remove from backpack
    backpack_remove(inv, item)
    // Remove from equipped slots
    for &slot in inv.equipped {
        if slot == item_id { slot = cw.INVALID_ENTITY }
    }

    wallet := cw.world_get_wallet(w, pid)
    wallet.gold += sell_val
    play_sfx("pickup")

    cw.world_destroy_entity(w, item_id)

    save_player(w, pid)
}

// g_sell_item_id is set by the inventory UI when the player right-clicks an item
// while the shop is open.  Consumed by _update_shop_panel each frame.
g_sell_item_id: int = cw.INVALID_ENTITY
