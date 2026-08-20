package main

door_init_blockers :: proc(w: ^World) {
    door_blockers_clear()
    ids := world_query(w, query_mask(.Openable, .Transform))
    defer delete(ids)
    for id in ids {
        op := comp_get(w, id, .Openable, OpenableComp)

        p := comp_get(w, id, .Transform, TransformComp).position
        tx, ty := world_to_tile(p[0], p[1])
        op.tile = {tx, ty}

        if !op.is_open {
            g_door_blockers[op.tile] = id
        }
    }
}

door_set_open :: proc(w: ^World, entity_id: int, open: bool) {
    if !world_has_component(w, entity_id, .Openable) { return }
    op := comp_get(w, entity_id, .Openable, OpenableComp)
    if op.is_open == open { return }

    op.is_open = open
    if open {
        delete_key(&g_door_blockers, op.tile)
    } else {
        g_door_blockers[op.tile] = entity_id
    }
    g_wall_mask_dirty = true
}

signal_broadcast :: proc(w: ^World, link_id: u8, signal_on: bool) {
    if link_id == 0 { return }

    ids := world_query(w, query_mask(.Openable))
    defer delete(ids)
    for id in ids {
        op := comp_get(w, id, .Openable, OpenableComp)
        if op.link_id != link_id { continue }
        if world_has_component(w, id, .SignalReceiver) {
            sr := comp_get(w, id, .SignalReceiver, SignalReceiverComp)
            effective := signal_on ~ sr.invert
            door_set_open(w, id, effective)
        } else {
            door_set_open(w, id, signal_on)
        }

        if world_has_component(w, id, .Lockable) {
            lk := comp_get(w, id, .Lockable, LockableComp)
            if lk.key_id == 0 && world_has_component(w, id, .Interactable) {
                comp_get(w, id, .Interactable, InteractableComp).active = !signal_on
            }
        }
    }
}
