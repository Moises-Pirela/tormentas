package main


import "core:math"

homing_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    homing_ids := world_query(w, query_mask(.Homing, .Projectile, .Transform))
    defer delete(homing_ids)

    for pid in homing_ids {
        h  := comp_get(w, pid, .Homing, HomingComp)
        pr := comp_get(w, pid, .Projectile, ProjectileComp)
        pt := comp_get(w, pid, .Transform, TransformComp)


        best_dist_sq := h.seek_range * h.seek_range
        if h.seek_range <= 0 { best_dist_sq = max(f32) }
        target_found := false
        target_dx    := f32(0)
        target_dy    := f32(0)

        ai_ids := world_query(w, query_mask(.AIAgent, .Transform), context.temp_allocator)
        for eid in ai_ids {
            et := comp_get(w, eid, .Transform, TransformComp)
            dx := et.position[0] - pt.position[0]
            dy := et.position[1] - pt.position[1]
            d2 := dx*dx + dy*dy
            if d2 < best_dist_sq {
                best_dist_sq  = d2
                target_dx     = dx
                target_dy     = dy
                target_found  = true
            }
        }

        if !target_found { continue }


        current_angle := math.atan2(pr.direction[1], pr.direction[0])
        target_angle  := math.atan2(target_dy, target_dx)


        diff := target_angle - current_angle
        for diff >  math.PI { diff -= 2.0 * math.PI }
        for diff < -math.PI { diff += 2.0 * math.PI }


        max_turn := h.turn_rate * dt
        turn     := clamp(diff, -max_turn, max_turn)
        new_angle := current_angle + turn

        pr.direction = [3]f32{ math.cos(new_angle), math.sin(new_angle), 0 }
    }
}
