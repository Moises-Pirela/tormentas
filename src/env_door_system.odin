package main

import cw "clockwork"

// =============================================================================
// env_door_system — doors, switches, signal propagation
//
// Design:
//   • SignalEmitter (lever / pressure plate) fires all SignalReceivers with
//     the same link_id.  OpenableComp has link_id so it acts as its own
//     SignalReceiver — env_interaction_system writes directly to OpenableComp
//     when the player presses E on a door.
//   • g_door_blockers is the authoritative tile-walk authority.  Any code
//     that needs to know if a tile is blocked by a door reads that map.
//   • door_init_blockers rebuilds the map from scratch after level_apply.
//   • door_set_open is the single write path — it keeps the door entity,
//     the OpenableComp, and g_door_blockers consistent.
// =============================================================================

// door_init_blockers scans every entity with an Openable component and
// registers any that are currently closed in g_door_blockers.
// Call once after each level_apply.
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

// door_set_open opens or closes a door entity, keeping g_door_blockers
// in sync.  Safe to call multiple times with the same state.
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
    g_wall_mask_dirty = true  // recalculate fog / wall mask
}

// signal_broadcast fires all SignalReceiver entities that share link_id.
// Called by env_interaction_system when a lever / emitter activates.
signal_broadcast :: proc(w: ^cw.World, link_id: u8, signal_on: bool) {
    if link_id == 0 { return }

    // Receivers with OpenableComp — open/close the door
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
            // Door without explicit receiver — treat as direct toggle target
            door_set_open(w, id, signal_on)
        }
        // Lever-only doors (LockableComp with key_id == 0): show "Opens elsewhere"
        // prompt while closed, hide it while open so the player isn't confused.
        if cw.world_has_component(w, id, .Lockable) {
            lk := cw.world_get_lockable(w, id)
            if lk.key_id == 0 && cw.world_has_component(w, id, .Interactable) {
                cw.world_get_interactable(w, id).active = !signal_on
            }
        }
    }
}
