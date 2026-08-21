package main

import "core:math"

g_interact_focused_id: int = INVALID_ENTITY

@(private = "file")
_find_nearest_interactable :: proc(w: ^World, pid: int) -> int {
    if !world_is_valid(w, pid)                  { return INVALID_ENTITY }
    if !world_has_component(w, pid, .Transform) { return INVALID_ENTITY }
    pt := comp_get(w, pid, .Transform, TransformComp)
    px := pt.position[0]
    py := pt.position[1]

    best_id   := INVALID_ENTITY
    best_dist := max(f32)

    ia_ids := world_query(w, query_mask(.Interactable))
    defer delete(ia_ids)

    for id in ia_ids {
        ia := comp_get(w, id, .Interactable, InteractableComp)
        if !ia.active { continue }
        et := comp_get(w, id, .Transform, TransformComp)
        dx := et.position[0] - px
        dy := et.position[1] - py
        d  := math.sqrt(dx*dx + dy*dy)
        if d <= ia.radius && d < best_dist {
            best_dist = d
            best_id   = id
        }
    }
    return best_id
}

// Local-only, read-only, and safe to run on both host and client — the
// authoritative env_interaction_system below decides what actually happens.
env_interaction_focus_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }
    g_interact_focused_id = _find_nearest_interactable(w, w.player_id)
}

env_interaction_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    emitter_ids := world_query(w, query_mask(.SignalEmitter))
    defer delete(emitter_ids)

    for id in emitter_ids {
        em := comp_get(w, id, .SignalEmitter, SignalEmitterComp)
        if !em.needs_weight { continue }
        et := comp_get(w, id, .Transform, TransformComp)

        on := false
        for slot in 0..<MAX_PLAYERS {
            pid := w.player_ids[slot]
            if !world_is_valid(w, pid)                  { continue }
            if !world_has_component(w, pid, .Transform) { continue }
            pt := comp_get(w, pid, .Transform, TransformComp)
            dx := et.position[0] - pt.position[0]
            dy := et.position[1] - pt.position[1]
            if math.sqrt(dx*dx + dy*dy) <= em.weight_radius { on = true; break }
        }
        if on == em.is_on { continue }
        em.is_on = on
        signal_broadcast(w, em.link_id, on)
    }

    ia_ids := world_query(w, query_mask(.Interactable))
    defer delete(ia_ids)
    for id in ia_ids {
        ia := comp_get(w, id, .Interactable, InteractableComp)
        if ia.cooldown > 0 {
            ia.cooldown = max(0, ia.cooldown - dt)
        }
    }

    for slot in 0..<MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !world_is_valid(w, pid)                    { continue }
        if !world_has_component(w, pid, .InputState)  { continue }
        input := comp_get(w, pid, .InputState, InputStateComp)
        if !input.interact_pressed { continue }

        target_id := _find_nearest_interactable(w, pid)
        if target_id == INVALID_ENTITY { continue }

        ia := comp_get(w, target_id, .Interactable, InteractableComp)
        if ia.cooldown > 0 { continue }

        dispatch_interaction(w, pid, target_id)
    }
}

@(private = "file")
dispatch_interaction :: proc(w: ^World, player_id: int, target_id: int) {
    pos: [3]f32
    if world_has_component(w, target_id, .Transform) {
        pos = comp_get(w, target_id, .Transform, TransformComp).position
    }

    if world_has_component(w, target_id, .Openable) {
        if world_has_component(w, target_id, .Lockable) {
            lk := comp_get(w, target_id, .Lockable, LockableComp)
            if lk.is_locked {
                if world_has_component(w, player_id, .KeyRing) {
                    kr := comp_get(w, player_id, .KeyRing, KeyRingComp)
                    if int(lk.key_id) in kr.held {
                        lk.is_locked = false
                        play_sfx_at("door_unlock", pos)
                    } else {
                        play_sfx_at("door_locked", pos)
                        return
                    }
                } else {
                    play_sfx_at("door_locked", pos)
                    return
                }
            }
        }
        op := comp_get(w, target_id, .Openable, OpenableComp)

        opening := !op.is_open
        door_set_open(w, target_id, opening)
        play_sfx_at("door_open" if opening else "door_close", pos)

        if op.link_id != 0 {
            signal_broadcast(w, op.link_id, opening)
        }
        return
    }

    if world_has_component(w, target_id, .SignalEmitter) {
        em := comp_get(w, target_id, .SignalEmitter, SignalEmitterComp)
        if em.needs_weight { return }
        if em.is_toggle {
            em.is_on = !em.is_on
        } else {
            em.is_on = true
        }
        signal_broadcast(w, em.link_id, em.is_on)
        play_sfx_at("lever_pull", pos)
        ia := comp_get(w, target_id, .Interactable, InteractableComp)
        ia.cooldown = 0.25
        return
    }

    if world_has_component(w, target_id, .Container) {
        ct := comp_get(w, target_id, .Container, ContainerComp)
        if ct.is_open { return }
        ct.is_open = true
        env_container_open(w, player_id, target_id)
        play_sfx_at("chest_open", pos)
        ia := comp_get(w, target_id, .Interactable, InteractableComp)
        ia.active = false
        return
    }

    if world_has_component(w, target_id, .LoreItem) {
        li := comp_get(w, target_id, .LoreItem, LoreItemComp)
        li.is_read = true
        ui_open_lore(li.lore_id)
        play_sfx_at("paper_rustle", pos)
        return
    }

    if world_has_component(w, target_id, .Phonograph) {
        ph := comp_get(w, target_id, .Phonograph, PhonographComp)
        if ph.is_playing { return }
        rec, ok := lore_get_recording(ph.recording_id)
        if !ok { return }
        ph.is_playing  = true
        ph.play_timer  = rec.duration
        ui_open_phonograph(ph.recording_id, target_id)

        sfx := rec.sfx_key[:]
        sfx_end := len(sfx)
        for i in 0..<len(sfx) { if sfx[i] == 0 { sfx_end = i; break } }
        if sfx_end > 0 { play_sfx_at(string(sfx[:sfx_end]), pos) }
        return
    }

    if world_has_component(w, target_id, .KeyPickup) {
        kp := comp_get(w, target_id, .KeyPickup, KeyPickupComp)
        if world_has_component(w, player_id, .KeyRing) {
            kr := comp_get(w, player_id, .KeyRing, KeyRingComp)
            kr.held += {int(kp.key_id)}
        }
        play_sfx_at("key_pickup", pos)
        world_destroy_entity(w, target_id)
        return
    }
}
