package main

import cw "clockwork"
import "core:math/rand"

// =============================================================================
// env_container_system — LateUpdate pass for Container + Health death,
// and the loot-spawn helper used by env_interaction_system.
//
// Breakable containers (Crate, Locker, Cabinet) can carry a HealthComp.
// When their HP hits zero the damage_system tags them for destruction; this
// system catches them before tag_destroy runs and spills loot first.
//
// Chests are opened via interaction only (no health).
// =============================================================================

env_container_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .LateUpdate { return }

    ids := cw.world_query(w, cw.query_mask(.Container, .Health))
    defer delete(ids)

    for id in ids {
        if !cw.world_is_valid(w, id)              { continue }
        if !cw.world_tag_is_destroy(w, id)        { continue }

        ct := cw.world_get_container(w, id)
        if ct.is_open { continue }  // loot already dropped via interaction

        env_container_open(w, cw.INVALID_ENTITY, id)
    }

    // Tick phonographs that are playing
    ph_ids := cw.world_query(w, cw.query_mask(.Phonograph))
    defer delete(ph_ids)
    for id in ph_ids {
        phonograph_tick(w, id, dt)
    }
}

// env_container_open spills loot for a container.
// player_id may be INVALID_ENTITY (e.g., broken by explosion).
// Call site sets ct.is_open = true before calling.
env_container_open :: proc(w: ^cw.World, player_id: int, container_id: int) {
    if !cw.world_has_component(w, container_id, .Container) { return }
    ct := cw.world_get_container(w, container_id)

    t := cw.world_get_transform(w, container_id)
    cx := t.position[0]
    cy := t.position[1]

    // Gold drop
    if ct.gold_max > 0 {
        range := int(ct.gold_max) - int(ct.gold_min)
        gold  := int(ct.gold_min)
        if range > 0 { gold += int(rand.uint32()) % (range + 1) }
        if gold > 0 {
            spawn_gold_drop(w, {cx, cy, 0}, gold)
        }
    } else if ct.loot_table_id == 0 {
        // Fallback: containers with no explicit config still drop a small amount
        // of gold so newly placed containers are never completely silent.
        gold := 5 + int(rand.uint32() % 16)   // 5–20 coins
        spawn_gold_drop(w, {cx, cy, 0}, gold)
    }

    // Loot table — drop items from the global loot table.
    if ct.loot_table_id > 0 {
        container_roll_loot(w, ct.loot_table_id, cx, cy)
    }

    // Signal link (e.g., opening a chest reveals a secret passage)
    if ct.emits_signal && ct.link_id != 0 {
        signal_broadcast(w, ct.link_id, true)
    }
}

// container_roll_loot spawns loot items at (cx, cy).
// table_id controls item count: 1 → 1 item, 2 → 2 items, 3+ → 3 items.
// All picks come from the global g_loot_table pool loaded from loot_table.csv.
@(private = "file")
container_roll_loot :: proc(w: ^cw.World, table_id: u8, cx, cy: f32) {
    if len(g_loot_table) == 0 { return }

    drop_count := int(min(table_id, 3))

    // Deterministic seed: mix container world position with table/index.
    // transmute gives us the raw bits of the float without any math import.
    pos_hash := u64(transmute(u32)cx) ~ (u64(transmute(u32)cy) << 32)

    for i in 0..<drop_count {
        seed := loot_seed(pos_hash ~ u64(i)*2685821657736338717, int(table_id))
        // Scatter items slightly so they don't overlap in the world.
        ox := f32(i) * 0.25
        spawn_loot_drop(w, {cx + ox, cy, 0}, seed)
    }
}
