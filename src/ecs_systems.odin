package main

movement_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update {return}

    ids := world_query(w, query_mask(.Transform, .Velocity))
    defer delete(ids)

    for id in ids {
        t := comp_get(w, id, .Transform, TransformComp)
        v := comp_get(w, id, .Velocity, VelocityComp)

        if is_player_entity(w, id) && (player_is_dead(w, id) ||
           (world_has_component(w, id, .AnimState) &&
            comp_get(w, id, .AnimState, AnimStateComp).current_state == .Attack)) {
            continue
        }

        vel_mult := f32(1.0)
        if world_has_component(w, id, .StatusEffect) {
            sec := comp_get(w, id, .StatusEffect, StatusEffectComp)
            if status_effect_is_active(sec, .Slow) {
                slow := status_effect_get(sec, .Slow)
                vel_mult *= (1.0 - slow.strength)
            }
        }

        t.position[0] += v.value[0] * vel_mult * dt
        t.position[1] += v.value[1] * vel_mult * dt
        t.position[2] += v.value[2] * vel_mult * dt
    }
}

projectile_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update {return}

    ids := world_query(w, query_mask(.Transform, .Projectile))
    defer delete(ids)

    for id in ids {
        t := comp_get(w, id, .Transform, TransformComp)
        p := comp_get(w, id, .Projectile, ProjectileComp)

        t.position[0] += p.direction[0] * p.speed * dt
        t.position[1] += p.direction[1] * p.speed * dt
        t.position[2] += p.direction[2] * p.speed * dt

        p.lifetime -= dt
        if p.lifetime <= 0 {
            world_tag_destroy(w, id)
        }
    }
}

self_destruct_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update {return}

    ids := world_query(w, query_mask(.SelfDestruct))
    defer delete(ids)

    for id in ids {
        sd := comp_get(w, id, .SelfDestruct, SelfDestructComp)
        sd.timer -= dt
        if sd.timer <= 0 {
            world_tag_destroy(w, id)
        }
    }
}
