package main

import cw "clockwork"


door_init_blockers :: proc(w: ^cw.World) {
    door_blockers_clear()
    ids := cw.world_query(w, cw.query_mask(.Openable))
    defer delete(ids)
    for id in ids {
        op := cw.world_get_openable(w, id)
        if !op.is_open {
            g_door_blockers[op.tile] = id
        }
    }
}


door_set_open :: proc(w: ^cw.World, entity_id: int, open: bool) {
    if !cw.world_has_component(w, entity_id, .Openable) { return }
    op := cw.world_get_openable(w, entity_id)
    if op.is_open == open { return }

    op.is_open = open
    if open {
        delete_key(&g_door_blockers, op.tile)
    } else {
        g_door_blockers[op.tile] = entity_id
    }
    g_wall_mask_dirty = true
}


signal_broadcast :: proc(w: ^cw.World, link_id: u8, signal_on: bool) {
    if link_id == 0 { return }


    ids := cw.world_query(w, cw.query_mask(.Openable))
    defer delete(ids)
    for id in ids {
        op := cw.world_get_openable(w, id)
        if op.link_id != link_id { continue }
        if cw.world_has_component(w, id, .SignalReceiver) {
            sr := cw.world_get_signal_receiver(w, id)
            effective := signal_on ~ sr.invert
            door_set_open(w, id, effective)
        } else {

            door_set_open(w, id, signal_on)
        }


        if cw.world_has_component(w, id, .Lockable) {
            lk := cw.world_get_lockable(w, id)
            if lk.key_id == 0 && cw.world_has_component(w, id, .Interactable) {
                cw.world_get_interactable(w, id).active = !signal_on
            }
        }
    }
}
