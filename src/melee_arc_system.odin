package main

import "core:math"

melee_arc_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    arc_ids := world_query(w, query_mask(.MeleeArc, .Transform))
    defer delete(arc_ids)

    for arc_id in arc_ids {
        arc := comp_get(w, arc_id, .MeleeArc, MeleeArcComp)
        if arc.hit_applied        { continue }
        if arc.owner_faction == 0 { continue }

        at := comp_get(w, arc_id, .Transform, TransformComp)

        for slot in 0..<MAX_PLAYERS {
            pid := w.player_ids[slot]
            if !world_is_valid(w, pid) { continue }
            if !world_has_component(w, pid, .Transform) { continue }

            if world_has_component(w, pid, .Respawn) {
                if comp_get(w, pid, .Respawn, RespawnComp).timer > 0 { continue }
            }

            check_pos := comp_get(w, pid, .Transform, TransformComp).position
            if world_has_component(w, pid, .MutationContainer) {
                mc := comp_get(w, pid, .MutationContainer, MutationContainerComp)
                for mi in 0..<mc.entity_count {
                    meid := mc.entities[mi]
                    if !world_is_valid(w, meid)                     { continue }
                    if !world_has_component(w, meid, .MutHeartCage) { continue }
                    hc := comp_get(w, meid, .MutHeartCage, MutHeartCageComp)
                    if world_is_valid(w, hc.heart_id) &&
                       world_has_component(w, hc.heart_id, .Health) &&
                       world_has_component(w, hc.heart_id, .Transform) &&
                       comp_get(w, hc.heart_id, .Health, HealthComp).current > 0 {
                        check_pos = comp_get(w, hc.heart_id, .Transform, TransformComp).position
                    }
                    break
                }
            }

            dx   := check_pos[0] - at.position[0]
            dy   := check_pos[1] - at.position[1]
            dist := math.sqrt(dx*dx + dy*dy)

            if dist > arc.radius { continue }

            if dist > 0.5 {
                to_player := math.atan2(dy, dx)
                diff      := wrap_pi(to_player - arc.angle)
                if abs(diff) > arc.arc_spread { continue }
            }

            world_push_damage(w, pid, arc.damage, arc.owner_id)
            arc.hit_applied = true
            break
        }
    }

    enemy_ids := world_query(w, query_mask(.AIAgent, .Collider, .Health, .Transform))
    defer delete(enemy_ids)

    for arc_id in arc_ids {
        arc := comp_get(w, arc_id, .MeleeArc, MeleeArcComp)
        if arc.hit_applied        { continue }
        if arc.owner_faction != 0 { continue }

        at := comp_get(w, arc_id, .Transform, TransformComp)

        hit_count := 0
        for eid in enemy_ids {
            col := comp_get(w, eid, .Collider, ColliderComp)
            if col.faction == 0 { continue }

            et   := comp_get(w, eid, .Transform, TransformComp)
            dx   := et.position[0] - at.position[0]
            dy   := et.position[1] - at.position[1]
            dist := math.sqrt(dx*dx + dy*dy)
            if dist > arc.radius { continue }

            if dist > 0.5 {
                to_enemy := math.atan2(dy, dx)
                diff     := wrap_pi(to_enemy - arc.angle)
                if abs(diff) > arc.arc_spread { continue }
            }

            world_push_damage(w, eid, arc.damage, arc.owner_id)
            hit_count += 1
        }
        if hit_count > 0 { play_sfx_at("melee_hit", at.position) }
        arc.hit_applied = true
    }
}

@(private = "file")
wrap_pi :: proc(a: f32) -> f32 {
    a := a
    for a >  math.PI { a -= math.TAU }
    for a < -math.PI { a += math.TAU }
    return a
}
