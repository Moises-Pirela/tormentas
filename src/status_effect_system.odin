package main

import cw "clockwork"

status_effect_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    #partial switch event {
    case .Update:
        for id in 0..<len(w.entities) {
            if !cw.world_is_valid(w, id) { continue }
            if !cw.world_has_component(w, id, .StatusEffect) { continue }

            sec := cw.world_get_status_effects(w, id)

            // Wet immediately extinguishes Burn and Oiled.
            // Do this before the tick loop so neither DoT fires this frame.
            if cw.status_effect_is_active(sec, .Wet) {
                sec.effects[int(cw.StatusEffectType.Burn)].duration  = 0
                sec.effects[int(cw.StatusEffectType.Oiled)].duration = 0
            }

            // Update each status effect type
            for et in 0..<len(cw.StatusEffectType) {
                stype  := cw.StatusEffectType(et)
                effect := &sec.effects[et]

                if effect.duration <= 0 { continue }

                effect.duration -= dt

                // Apply ongoing damage for damage-based effects
                #partial switch stype {
                case .Poison:
                    _apply_poison_damage(w, id, effect, dt)
                case .Burn:
                    _apply_burn_damage(w, id, effect, dt)
                }
            }
        }
    }
}

@(private = "file")
_apply_poison_damage :: proc(w: ^cw.World, id: int, effect: ^cw.StatusEffect, dt: f32) {
    if !cw.world_has_component(w, id, .Health) { return }
    
    // Check if this entity is a heart and if poison comes from its owner
    for slot in 0..<cw.MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !cw.world_is_valid(w, pid)                          { continue }
        if !cw.world_has_component(w, pid, .MutationContainer) { continue }
        mc := cw.world_get_mutation(w, pid)
        for mi in 0..<mc.entity_count {
            meid := mc.entities[mi]
            if !cw.world_is_valid(w, meid)                     { continue }
            if !cw.world_has_component(w, meid, .MutHeartCage) { continue }
            hc := cw.world_get_mut_heart_cage(w, meid)
            if id == hc.heart_id && int(effect.source_id) == pid {
                return  // Heart is immune to owner's poison
            }
            break
        }
    }
    
    h := cw.world_get_health(w, id)
    
    damage_per_sec := effect.strength * h.max
    damage_this_tick := damage_per_sec * dt
    
    append(&w.damage_events, cw.DamageEvent{
        target_id = id,
        amount    = damage_this_tick,
        source_id = int(effect.source_id),
    })
}

@(private = "file")
_apply_burn_damage :: proc(w: ^cw.World, id: int, effect: ^cw.StatusEffect, dt: f32) {

    if !cw.world_has_component(w, id, .Health) { return }
    if !cw.world_has_component(w, id, .Flammable) {return }
    
    h := cw.world_get_health(w, id)
    
    damage_per_sec := effect.strength * h.max
    damage_this_tick := damage_per_sec * dt
    
    append(&w.damage_events, cw.DamageEvent{
        target_id = id,
        amount    = damage_this_tick,
        source_id = int(effect.source_id),
    })
}
