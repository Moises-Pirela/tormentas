package main

import "core:math"
import cw "clockwork"

PICKUP_RADIUS :: f32(32)

pickup_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }

    gold_ids := cw.world_query(w, cw.query_mask(.GroundItem, .Transform, .Gold))
    defer delete(gold_ids)

    for slot in 0..<cw.MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !cw.world_is_valid(w, pid)                   { continue }
        if !cw.world_has_component(w, pid, .Wallet)     { continue }
        if !cw.world_has_component(w, pid, .Transform)  { continue }
        if cw.world_has_component(w, pid, .Stats) &&
           cw.world_get_stats(w, pid).pickups_blocked   { continue }
        if cw.world_has_component(w, pid, .Respawn) &&
           cw.world_get_respawn(w, pid).timer > 0       { continue }

        player_pos := cw.world_get_transform(w, pid).position
        wallet     := cw.world_get_wallet(w, pid)

        for gid in gold_ids {
            if !cw.world_has_component(w, gid, .GroundItem) { continue }

            t  := cw.world_get_transform(w, gid)
            dx := t.position[0] - player_pos[0]
            dy := t.position[1] - player_pos[1]
            if dx*dx + dy*dy > PICKUP_RADIUS * PICKUP_RADIUS { continue }

            gold_comp := cw.world_get_gold(w, gid)
            wallet.gold += gold_comp.amount
            if pid == w.player_id { play_sfx("pickup") }
            cw.world_tag_destroy(w, gid)
        }
    }

    if ui_has(.Inventory) || ui_has(.Shop) || ui_has(.Stash) { return }

    ground_ids := cw.world_query(w, cw.query_mask(.GroundItem, .Transform, .Item))
    defer delete(ground_ids)

    for slot in 0..<cw.MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !cw.world_is_valid(w, pid) { continue }
        if !cw.world_has_component(w, pid, .Inventory) { continue }
        if cw.world_has_component(w, pid, .Stats) &&
           cw.world_get_stats(w, pid).pickups_blocked { continue }

        if cw.world_has_component(w, pid, .Respawn) {
            if cw.world_get_respawn(w, pid).timer > 0 { continue }
        }

        player_pos := cw.world_get_transform(w, pid).position
        inv        := cw.world_get_inventory(w, pid)

        for gid in ground_ids {
            if !cw.world_has_component(w, gid, .GroundItem) { continue }

            t  := cw.world_get_transform(w, gid)
            dx := t.position[0] - player_pos[0]
            dy := t.position[1] - player_pos[1]
            if math.sqrt(dx*dx + dy*dy) > PICKUP_RADIUS { continue }

            item := cw.world_get_item(w, gid)

            if item.serum_value > 0 {
                if cw.world_has_component(w, pid, .MutationContainer) {
                    mc := cw.world_get_mutation(w, pid)
                    serum_mult := f32(1.0)
                    if cw.world_has_component(w, pid, .MutationContainer) {
                        pmc := cw.world_get_mutation(w, pid)
                        for i in 0..<pmc.entity_count {
                            meid := pmc.entities[i]
                            if !cw.world_is_valid(w, meid) { continue }
                            if cw.world_has_component(w, meid, .MutSerumGainMult) {
                                serum_mult *= cw.world_get_mut_serum_gain_mult(w, meid).mult
                            }
                        }
                    }
                    mc.serums += int(f32(item.serum_value) * serum_mult)
                }
                cw.world_tag_destroy(w, gid)
                if pid == w.player_id { play_sfx("pickup") }
                continue
            }


            if item.rarity < g_loot_filter_rarity { continue }

            col, row, ok := backpack_find_free(inv, item)
            if !ok { continue }

            backpack_place(inv, item, gid, col, row)
            cw.world_clear_ground_item(w, gid)
            if pid == w.player_id {
                play_sfx("pickup")
                ui_mark_dirty(.Inventory)
            }
            cw.entity_sig_clear(&w.entities[gid].signature, .Transform)
        }
    }
}
