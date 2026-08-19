package main

import "core:math"


g_interact_focused_id: int = INVALID_ENTITY

env_interaction_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    local_pid := w.player_id
    if !world_is_valid(w, local_pid) { return }

    pt := comp_get(w, local_pid, .Transform, TransformComp)
    px := pt.position[0]
    py := pt.position[1]


    emitter_ids := world_query(w, query_mask(.SignalEmitter))
    defer delete(emitter_ids)

    for id in emitter_ids {
        em := comp_get(w, id, .SignalEmitter, SignalEmitterComp)
        if !em.needs_weight { continue }
        et := comp_get(w, id, .Transform, TransformComp)
        dx := et.position[0] - px
        dy := et.position[1] - py
        on := math.sqrt(dx*dx + dy*dy) <= em.weight_radius
        if on == em.is_on { continue }
        em.is_on = on
        signal_broadcast(w, em.link_id, on)
    }


    best_id   := INVALID_ENTITY
    best_dist := max(f32)

    ia_ids := world_query(w, query_mask(.Interactable))
    defer delete(ia_ids)

    for id in ia_ids {
        ia := comp_get(w, id, .Interactable, InteractableComp)
        if !ia.active { continue }
        if ia.cooldown > 0 {
            ia.cooldown -= dt
            if ia.cooldown < 0 { ia.cooldown = 0 }
        }
        et := comp_get(w, id, .Transform, TransformComp)
        dx := et.position[0] - px
        dy := et.position[1] - py
        d  := math.sqrt(dx*dx + dy*dy)
        if d <= ia.radius && d < best_dist {
            best_dist = d
            best_id   = id
        }
    }

    g_interact_focused_id = best_id


    if best_id == INVALID_ENTITY { return }

    input := comp_get(w, local_pid, .InputState, InputStateComp)
    if !input.interact_pressed { return }

    ia := comp_get(w, best_id, .Interactable, InteractableComp)
    if ia.cooldown > 0 { return }

    dispatch_interaction(w, local_pid, best_id)
}

@(private = "file")
dispatch_interaction :: proc(w: ^World, player_id: int, target_id: int) {

    if world_has_component(w, target_id, .Openable) {

        if world_has_component(w, target_id, .Lockable) {
            lk := comp_get(w, target_id, .Lockable, LockableComp)
            if lk.is_locked {

                if world_has_component(w, player_id, .KeyRing) {
                    kr := comp_get(w, player_id, .KeyRing, KeyRingComp)
                    if int(lk.key_id) in kr.held {
                        lk.is_locked = false
                        play_sfx("door_unlock")
                    } else {
                        play_sfx("door_locked")
                        return
                    }
                } else {
                    play_sfx("door_locked")
                    return
                }
            }
        }
        op := comp_get(w, target_id, .Openable, OpenableComp)


        opening := !op.is_open
        door_set_open(w, target_id, opening)
        play_sfx("door_open" if opening else "door_close")

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
        play_sfx("lever_pull")
        ia := comp_get(w, target_id, .Interactable, InteractableComp)
        ia.cooldown = 0.25
        return
    }


    if world_has_component(w, target_id, .Container) {
        ct := comp_get(w, target_id, .Container, ContainerComp)
        if ct.is_open { return }
        ct.is_open = true
        env_container_open(w, player_id, target_id)
        play_sfx("chest_open")
        ia := comp_get(w, target_id, .Interactable, InteractableComp)
        ia.active = false
        return
    }


    if world_has_component(w, target_id, .LoreItem) {
        li := comp_get(w, target_id, .LoreItem, LoreItemComp)
        li.is_read = true
        ui_open_lore(li.lore_id)
        play_sfx("paper_rustle")
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
        if sfx_end > 0 { play_sfx(string(sfx[:sfx_end])) }
        return
    }


    if world_has_component(w, target_id, .KeyPickup) {
        kp := comp_get(w, target_id, .KeyPickup, KeyPickupComp)
        if world_has_component(w, player_id, .KeyRing) {
            kr := comp_get(w, player_id, .KeyRing, KeyRingComp)
            kr.held += {int(kp.key_id)}
        }
        play_sfx("key_pickup")
        world_destroy_entity(w, target_id)
        return
    }
}
