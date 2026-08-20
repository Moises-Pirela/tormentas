package main

import "core:math"

PICKUP_RADIUS :: f32(32)

pickup_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    gold_ids := world_query(w, query_mask(.GroundItem, .Transform, .Gold))
    defer delete(gold_ids)

    for slot in 0..<MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !world_is_valid(w, pid)                   { continue }
        if !world_has_component(w, pid, .Wallet)     { continue }
        if !world_has_component(w, pid, .Transform)  { continue }
        if world_has_component(w, pid, .Stats) &&
           comp_get(w, pid, .Stats, StatsComp).pickups_blocked   { continue }
        if world_has_component(w, pid, .Respawn) &&
           comp_get(w, pid, .Respawn, RespawnComp).timer > 0       { continue }

        player_pos := comp_get(w, pid, .Transform, TransformComp).position
        wallet     := comp_get(w, pid, .Wallet, WalletComp)

        for gid in gold_ids {
            if !world_has_component(w, gid, .GroundItem) { continue }

            t  := comp_get(w, gid, .Transform, TransformComp)
            dx := t.position[0] - player_pos[0]
            dy := t.position[1] - player_pos[1]
            if dx*dx + dy*dy > PICKUP_RADIUS * PICKUP_RADIUS { continue }

            gold_comp := comp_get(w, gid, .Gold, GoldComp)
            wallet.gold += gold_comp.amount
            if pid == w.player_id { play_sfx("pickup") }
            world_tag_destroy(w, gid)
        }
    }

    if ui_has(.Inventory) || ui_has(.Shop) || ui_has(.Stash) { return }

    ground_ids := world_query(w, query_mask(.GroundItem, .Transform, .Item))
    defer delete(ground_ids)

    for slot in 0..<MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !world_is_valid(w, pid) { continue }
        if !world_has_component(w, pid, .Inventory) { continue }
        if world_has_component(w, pid, .Stats) &&
           comp_get(w, pid, .Stats, StatsComp).pickups_blocked { continue }

        if world_has_component(w, pid, .Respawn) {
            if comp_get(w, pid, .Respawn, RespawnComp).timer > 0 { continue }
        }

        player_pos := comp_get(w, pid, .Transform, TransformComp).position
        inv        := comp_get(w, pid, .Inventory, InventoryComp)

        for gid in ground_ids {
            if !world_has_component(w, gid, .GroundItem) { continue }

            t  := comp_get(w, gid, .Transform, TransformComp)
            dx := t.position[0] - player_pos[0]
            dy := t.position[1] - player_pos[1]
            if math.sqrt(dx*dx + dy*dy) > PICKUP_RADIUS { continue }

            item := comp_get(w, gid, .Item, ItemComp)

            if item.serum_value > 0 {
                if world_has_component(w, pid, .MutationContainer) {
                    mc := comp_get(w, pid, .MutationContainer, MutationContainerComp)
                    serum_mult := f32(1.0)
                    if world_has_component(w, pid, .MutationContainer) {
                        pmc := comp_get(w, pid, .MutationContainer, MutationContainerComp)
                        for i in 0..<pmc.entity_count {
                            meid := pmc.entities[i]
                            if !world_is_valid(w, meid) { continue }
                            if world_has_component(w, meid, .MutSerumGainMult) {
                                serum_mult *= comp_get(w, meid, .MutSerumGainMult, MutSerumGainMultComp).mult
                            }
                        }
                    }
                    mc.serums += int(f32(item.serum_value) * serum_mult)
                }
                world_tag_destroy(w, gid)
                if pid == w.player_id { play_sfx("pickup") }
                continue
            }

            if item.rarity < g_loot_filter_rarity { continue }

            col, row, ok := backpack_find_free(inv, item)
            if !ok { continue }

            backpack_place(inv, item, gid, col, row)
            comp_rm(w, gid, .GroundItem)
            if pid == w.player_id {
                play_sfx("pickup")
                ui_mark_dirty(.Inventory)
            }
            comp_rm(w, gid, .Transform)
        }
    }
}
