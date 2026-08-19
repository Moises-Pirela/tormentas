package main

import math "core:math"

status_effect_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    #partial switch event {
    case .Update:
        for id in 0..<len(w.entities) {
            if !world_is_valid(w, id) { continue }
            if !world_has_component(w, id, .StatusEffect) { continue }

            sec := comp_get(w, id, .StatusEffect, StatusEffectComp)


            if status_effect_is_active(sec, .Wet) {
                sec.effects[int(StatusEffectType.Burn)].duration  = 0
                sec.effects[int(StatusEffectType.Oiled)].duration = 0
            }


            for et in 0..<len(StatusEffectType) {
                stype  := StatusEffectType(et)
                effect := &sec.effects[et]

                if effect.duration <= 0 { continue }

                effect.duration -= dt


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
_apply_poison_damage :: proc(w: ^World, id: int, effect: ^StatusEffect, dt: f32) {
    if !world_has_component(w, id, .Health) { return }

    if !world_has_component(w, id, .Organic) { return }

    h := comp_get(w, id, .Health, HealthComp)

    damage_per_sec := effect.strength * h.max
    damage_this_tick := damage_per_sec * dt
    effect.acumulator += damage_this_tick

    damage_to_apply := math.floor_f32(effect.acumulator)

    if (damage_to_apply < 1.0) {
        return
    }

    effect.acumulator -= damage_to_apply

    append(&w.damage_events, DamageEvent{
        target_id = id,
        amount    = damage_to_apply,
        source_id = int(effect.source_id),
        kind      = .Poison,
    })
}

@(private = "file")
_apply_burn_damage :: proc(w: ^World, id: int, effect: ^StatusEffect, dt: f32) {

    if !world_has_component(w, id, .Health) { return }
    if !world_has_component(w, id, .Flammable) {return }

    h := comp_get(w, id, .Health, HealthComp)

    damage_per_sec := effect.strength * h.max
    damage_this_tick := damage_per_sec * dt
    effect.acumulator += damage_this_tick
    damage_to_apply := math.floor_f32(effect.acumulator)

    if (damage_to_apply < 1.0) {
        return
    }

    effect.acumulator -= damage_to_apply

    append(&w.damage_events, DamageEvent{
        target_id = id,
        amount    = damage_to_apply,
        source_id = int(effect.source_id),
        kind      = .Fire,
    })
}
