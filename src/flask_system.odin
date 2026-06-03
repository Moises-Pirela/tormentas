package main


import cw "clockwork"
import rl "vendor:raylib"

flask_system :: proc(w: ^cw.World, _ev: cw.SystemEvent, dt: f32) {
    for slot in 0..<cw.MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !cw.world_is_valid(w, pid)                  { continue }
        if !cw.world_has_component(w, pid, .Inventory) { continue }

        inv := cw.world_get_inventory(w, pid)


        if rl.IsKeyPressed(.ONE) {
            _try_use_flask(w, pid, inv, .Flask1)
        }


        if rl.IsKeyPressed(.TWO) {
            _try_use_flask(w, pid, inv, .Flask2)
        }


        if cw.world_has_component(w, pid, .FlaskEffect) {
            fe := cw.world_get_flask_effect(w, pid)
            fe.remaining -= dt

            if fe.remaining <= 0 {
                cw.world_clear_flask_effect(w, pid)
            } else {

                if fe.heal_per_sec > 0 && cw.world_has_component(w, pid, .Health) {
                    h := cw.world_get_health(w, pid)
                    if !cw.world_has_component(w, pid, .Stats) ||
                       !cw.world_get_stats(w, pid).healing_blocked {
                        h.current = min(h.current + fe.heal_per_sec * dt, h.max)
                    }
                }
                if fe.energy_per_sec > 0 && cw.world_has_component(w, pid, .Health) {
                    h := cw.world_get_health(w, pid)
                    h.energy = min(h.energy + fe.energy_per_sec * dt, h.max_energy)
                }
            }
        }
    }
}

@(private = "file")
_try_use_flask :: proc(w: ^cw.World, pid: int, inv: ^cw.InventoryComp, slot: cw.EquipSlot) {
    fid := inv.equipped[int(slot)]
    if !cw.world_is_valid(w, fid)              { return }
    if !cw.world_has_component(w, fid, .Flask) { return }

    fc := cw.world_get_flask(w, fid)
    if fc.charges <= 0 { return }


    fc.charges -= 1


    rate := fc.recover_amount / fc.recover_duration


    if cw.world_has_component(w, pid, .FlaskEffect) {
        fe := cw.world_get_flask_effect(w, pid)

        if fc.recover_duration > fe.remaining {
            fe.remaining = fc.recover_duration
        }
        switch fc.kind {
        case .Health: fe.heal_per_sec   += rate
        case .Energy: fe.energy_per_sec += rate
        }
    } else {
        fe := cw.FlaskEffectComp{ remaining = fc.recover_duration }
        switch fc.kind {
        case .Health: fe.heal_per_sec   = rate
        case .Energy: fe.energy_per_sec = rate
        }
        cw.world_set_flask_effect(w, pid, fe)
    }
}
