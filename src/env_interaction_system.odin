package main

import "core:math"
import cw "clockwork"

// =============================================================================
// env_interaction_system — proximity detection, prompt display, dispatch
//
// Each Update tick:
//   1. Find the nearest Interactable within radius of each local player.
//   2. Store it in g_interact_focused_id so the HUD renderer can draw a prompt.
//   3. If the player pressed Interact this tick, dispatch to the correct handler
//      based on which components the focused entity holds.
//
// Weight plates (needs_weight = true on SignalEmitterComp) are checked every
// tick — they don't need an Interact keypress.
// =============================================================================

// g_interact_focused_id is the entity the local player is hovering over.
// cw.INVALID_ENTITY when nothing is in range.  Read by ui_hud.odin.
g_interact_focused_id: int = cw.INVALID_ENTITY

env_interaction_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }

    local_pid := w.player_id
    if !cw.world_is_valid(w, local_pid) { return }

    pt := cw.world_get_transform(w, local_pid)
    px := pt.position[0]
    py := pt.position[1]

    // ── Weight-plate check (runs every frame, no keypress needed) ────────────
    emitter_ids := cw.world_query(w, cw.query_mask(.SignalEmitter))
    defer delete(emitter_ids)

    for id in emitter_ids {
        em := cw.world_get_signal_emitter(w, id)
        if !em.needs_weight { continue }
        et := cw.world_get_transform(w, id)
        dx := et.position[0] - px
        dy := et.position[1] - py
        on := math.sqrt(dx*dx + dy*dy) <= em.weight_radius
        if on == em.is_on { continue }
        em.is_on = on
        signal_broadcast(w, em.link_id, on)
    }

    // ── Find nearest interactable in range ───────────────────────────────────
    best_id   := cw.INVALID_ENTITY
    best_dist := max(f32)

    ia_ids := cw.world_query(w, cw.query_mask(.Interactable))
    defer delete(ia_ids)

    for id in ia_ids {
        ia := cw.world_get_interactable(w, id)
        if !ia.active { continue }
        if ia.cooldown > 0 {
            ia.cooldown -= dt
            if ia.cooldown < 0 { ia.cooldown = 0 }
        }
        et := cw.world_get_transform(w, id)
        dx := et.position[0] - px
        dy := et.position[1] - py
        d  := math.sqrt(dx*dx + dy*dy)
        if d <= ia.radius && d < best_dist {
            best_dist = d
            best_id   = id
        }
    }

    g_interact_focused_id = best_id

    // ── Dispatch on Interact press ────────────────────────────────────────────
    if best_id == cw.INVALID_ENTITY { return }

    input := cw.world_get_input(w, local_pid)
    if !input.interact_pressed { return }

    ia := cw.world_get_interactable(w, best_id)
    if ia.cooldown > 0 { return }

    dispatch_interaction(w, local_pid, best_id)
}

@(private = "file")
dispatch_interaction :: proc(w: ^cw.World, player_id: int, target_id: int) {
    // ── Door ─────────────────────────────────────────────────────────────────
    if cw.world_has_component(w, target_id, .Openable) {
        // Check lock first
        if cw.world_has_component(w, target_id, .Lockable) {
            lk := cw.world_get_lockable(w, target_id)
            if lk.is_locked {
                // Check if player holds the matching key
                if cw.world_has_component(w, player_id, .KeyRing) {
                    kr := cw.world_get_key_ring(w, player_id)
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
        op := cw.world_get_openable(w, target_id)
        // Capture intent BEFORE door_set_open — world_get_openable returns a pointer
        // and door_set_open writes through it immediately, so reading !op.is_open
        // after the call would see the already-flipped value.
        opening := !op.is_open
        door_set_open(w, target_id, opening)
        play_sfx("door_open" if opening else "door_close")
        // Signal any linked entities (e.g., a door opening triggers another door)
        if op.link_id != 0 {
            signal_broadcast(w, op.link_id, opening)
        }
        return
    }

    // ── Lever / switch ────────────────────────────────────────────────────────
    if cw.world_has_component(w, target_id, .SignalEmitter) {
        em := cw.world_get_signal_emitter(w, target_id)
        if em.needs_weight { return }  // pressure plates don't respond to E
        if em.is_toggle {
            em.is_on = !em.is_on
        } else {
            em.is_on = true
        }
        signal_broadcast(w, em.link_id, em.is_on)
        play_sfx("lever_pull")
        ia := cw.world_get_interactable(w, target_id)
        ia.cooldown = 0.25
        return
    }

    // ── Container ─────────────────────────────────────────────────────────────
    if cw.world_has_component(w, target_id, .Container) {
        ct := cw.world_get_container(w, target_id)
        if ct.is_open { return }
        ct.is_open = true
        env_container_open(w, player_id, target_id)
        play_sfx("chest_open")
        ia := cw.world_get_interactable(w, target_id)
        ia.active = false  // can't open twice
        return
    }

    // ── Lore item ─────────────────────────────────────────────────────────────
    if cw.world_has_component(w, target_id, .LoreItem) {
        li := cw.world_get_lore_item(w, target_id)
        li.is_read = true
        ui_open_lore(li.lore_id)
        play_sfx("paper_rustle")
        return
    }

    // ── Phonograph ────────────────────────────────────────────────────────────
    if cw.world_has_component(w, target_id, .Phonograph) {
        ph := cw.world_get_phonograph(w, target_id)
        if ph.is_playing { return }
        rec, ok := lore_get_recording(ph.recording_id)
        if !ok { return }
        ph.is_playing  = true
        ph.play_timer  = rec.duration
        ui_open_phonograph(ph.recording_id, target_id)
        // sfx_key is a null-terminated fixed array — trim to first zero
        sfx := rec.sfx_key[:]
        sfx_end := len(sfx)
        for i in 0..<len(sfx) { if sfx[i] == 0 { sfx_end = i; break } }
        if sfx_end > 0 { play_sfx(string(sfx[:sfx_end])) }
        return
    }

    // ── Key pickup ────────────────────────────────────────────────────────────
    if cw.world_has_component(w, target_id, .KeyPickup) {
        kp := cw.world_get_key_pickup(w, target_id)
        if cw.world_has_component(w, player_id, .KeyRing) {
            kr := cw.world_get_key_ring(w, player_id)
            kr.held += {int(kp.key_id)}
        }
        play_sfx("key_pickup")
        cw.world_destroy_entity(w, target_id)
        return
    }
}
