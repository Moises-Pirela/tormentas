package main

import "core:math"
import cw "clockwork"

melee_arc_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }

    arc_ids := cw.world_query(w, cw.query_mask(.MeleeArc, .Transform))
    defer delete(arc_ids)

    for arc_id in arc_ids {
        arc := cw.world_get_melee_arc(w, arc_id)
        if arc.hit_applied        { continue }
        if arc.owner_faction == 0 { continue }

        at := cw.world_get_transform(w, arc_id)

        for slot in 0..<cw.MAX_PLAYERS {
            pid := w.player_ids[slot]
            if !cw.world_is_valid(w, pid) { continue }
            if !cw.world_has_component(w, pid, .Transform) { continue }

            if cw.world_has_component(w, pid, .Respawn) {
                if cw.world_get_respawn(w, pid).timer > 0 { continue }
            }

            check_pos := cw.world_get_transform(w, pid).position
            if cw.world_has_component(w, pid, .MutationContainer) {
                mc := cw.world_get_mutation(w, pid)
                for mi in 0..<mc.entity_count {
                    meid := mc.entities[mi]
                    if !cw.world_is_valid(w, meid)                     { continue }
                    if !cw.world_has_component(w, meid, .MutHeartCage) { continue }
                    hc := cw.world_get_mut_heart_cage(w, meid)
                    if cw.world_is_valid(w, hc.heart_id) &&
                       cw.world_has_component(w, hc.heart_id, .Health) &&
                       cw.world_has_component(w, hc.heart_id, .Transform) &&
                       cw.world_get_health(w, hc.heart_id).current > 0 {
                        check_pos = cw.world_get_transform(w, hc.heart_id).position
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

            cw.world_push_damage(w, pid, arc.damage, arc.owner_id)
            arc.hit_applied = true
            break
        }
    }

    enemy_ids := cw.world_query(w, cw.query_mask(.AIAgent, .Collider, .Health, .Transform))
    defer delete(enemy_ids)

    for arc_id in arc_ids {
        arc := cw.world_get_melee_arc(w, arc_id)
        if arc.hit_applied        { continue }
        if arc.owner_faction != 0 { continue }

        at := cw.world_get_transform(w, arc_id)

        hit_count := 0
        for eid in enemy_ids {
            col := cw.world_get_collider(w, eid)
            if col.faction == 0 { continue }

            et   := cw.world_get_transform(w, eid)
            dx   := et.position[0] - at.position[0]
            dy   := et.position[1] - at.position[1]
            dist := math.sqrt(dx*dx + dy*dy)
            if dist > arc.radius { continue }

            if dist > 0.5 {
                to_enemy := math.atan2(dy, dx)
                diff     := wrap_pi(to_enemy - arc.angle)
                if abs(diff) > arc.arc_spread { continue }
            }

            cw.world_push_damage(w, eid, arc.damage, arc.owner_id)
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
