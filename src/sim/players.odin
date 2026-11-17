package sim

is_player_entity :: proc(w: ^World, id: int) -> bool {
    for pid in w.player_ids {
        if pid == id { return true }
    }
    return false
}

player_slot_for_id :: proc(w: ^World, id: int) -> int {
    for slot in 0..<MAX_PLAYERS {
        if w.player_ids[slot] == id { return slot }
    }
    return -1
}

player_is_dead :: proc(w: ^World, id: int) -> bool {
    if world_has_component(w, id, .Health) && comp_get(w, id, .Health, HealthComp).current <= 0 {
        return true
    }
    return world_has_component(w, id, .Respawn) && comp_get(w, id, .Respawn, RespawnComp).timer > 0
}
