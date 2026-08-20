package main

import rl "vendor:raylib"

flask_system :: proc(w: ^World, _ev: SystemEvent, dt: f32) {
    for slot in 0..<MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !world_is_valid(w, pid)                  { continue }
        if !world_has_component(w, pid, .Inventory) { continue }

        inv := comp_get(w, pid, .Inventory, InventoryComp)

        if rl.IsKeyPressed(.ONE) {
            _try_use_flask(w, pid, inv, .Flask1)
        }

        if rl.IsKeyPressed(.TWO) {
            _try_use_flask(w, pid, inv, .Flask2)
        }

        if world_has_component(w, pid, .FlaskEffect) {
            fe := comp_get(w, pid, .FlaskEffect, FlaskEffectComp)
            fe.remaining -= dt

            if fe.remaining <= 0 {
                comp_rm(w, pid, .FlaskEffect)
            } else {
                if fe.heal_per_sec > 0 && world_has_component(w, pid, .Health) {
                    h := comp_get(w, pid, .Health, HealthComp)
                    if !world_has_component(w, pid, .Stats) ||
                       !comp_get(w, pid, .Stats, StatsComp).healing_blocked {
                        h.current = min(h.current + fe.heal_per_sec * dt, h.max)
                    }
                }
                if fe.energy_per_sec > 0 && world_has_component(w, pid, .Health) {
                    h := comp_get(w, pid, .Health, HealthComp)
                    h.energy = min(h.energy + fe.energy_per_sec * dt, h.max_energy)
                }
            }
        }
    }
}

@(private = "file")
_try_use_flask :: proc(w: ^World, pid: int, inv: ^InventoryComp, slot: EquipSlot) {
    fid := inv.equipped[int(slot)]
    if !world_is_valid(w, fid)              { return }
    if !world_has_component(w, fid, .Flask) { return }

    fc := comp_get(w, fid, .Flask, FlaskComp)
    if fc.charges <= 0 { return }

    fc.charges -= 1

    rate := fc.recover_amount / fc.recover_duration

    if world_has_component(w, pid, .FlaskEffect) {
        fe := comp_get(w, pid, .FlaskEffect, FlaskEffectComp)

        if fc.recover_duration > fe.remaining {
            fe.remaining = fc.recover_duration
        }
        switch fc.kind {
        case .Health: fe.heal_per_sec   += rate
        case .Energy: fe.energy_per_sec += rate
        }
    } else {
        fe := FlaskEffectComp{ remaining = fc.recover_duration }
        switch fc.kind {
        case .Health: fe.heal_per_sec   = rate
        case .Energy: fe.energy_per_sec = rate
        }
        comp_set(w, pid, .FlaskEffect, fe)
    }
}
