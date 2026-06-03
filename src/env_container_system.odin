package main

import cw "clockwork"
import "core:math/rand"


env_container_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .LateUpdate { return }

    ids := cw.world_query(w, cw.query_mask(.Container, .Health))
    defer delete(ids)

    for id in ids {
        if !cw.world_is_valid(w, id)              { continue }
        if !cw.world_tag_is_destroy(w, id)        { continue }

        ct := cw.world_get_container(w, id)
        if ct.is_open { continue }

        env_container_open(w, cw.INVALID_ENTITY, id)
    }


    ph_ids := cw.world_query(w, cw.query_mask(.Phonograph))
    defer delete(ph_ids)
    for id in ph_ids {
        phonograph_tick(w, id, dt)
    }
}


env_container_open :: proc(w: ^cw.World, player_id: int, container_id: int) {
    if !cw.world_has_component(w, container_id, .Container) { return }
    ct := cw.world_get_container(w, container_id)

    t := cw.world_get_transform(w, container_id)
    cx := t.position[0]
    cy := t.position[1]


    if ct.gold_max > 0 {
        range := int(ct.gold_max) - int(ct.gold_min)
        gold  := int(ct.gold_min)
        if range > 0 { gold += int(rand.uint32()) % (range + 1) }
        if gold > 0 {
            spawn_gold_drop(w, {cx, cy, 0}, gold)
        }
    } else if ct.loot_table_id == 0 {


        gold := 5 + int(rand.uint32() % 16)
        spawn_gold_drop(w, {cx, cy, 0}, gold)
    }


    if ct.loot_table_id > 0 {
        container_roll_loot(w, ct.loot_table_id, cx, cy)
    }


    if ct.emits_signal && ct.link_id != 0 {
        signal_broadcast(w, ct.link_id, true)
    }
}


@(private = "file")
container_roll_loot :: proc(w: ^cw.World, table_id: u8, cx, cy: f32) {
    if len(g_loot_table) == 0 { return }

    drop_count := int(min(table_id, 3))


    pos_hash := u64(transmute(u32)cx) ~ (u64(transmute(u32)cy) << 32)

    for i in 0..<drop_count {
        seed := loot_seed(pos_hash ~ u64(i)*2685821657736338717, int(table_id))

        ox := f32(i) * 0.25
        spawn_loot_drop(w, {cx + ox, cy, 0}, seed)
    }
}
