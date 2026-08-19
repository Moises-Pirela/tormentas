package main


import      "core:math"

entity_separation_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .LateUpdate { return }

    ids := world_query(w, query_mask(.Transform, .Collider))
    defer delete(ids)

    n := len(ids)
    for i in 0..<n {
        a    := ids[i]
        ca   := comp_get(w, a, .Collider, ColliderComp)
        if ca.is_trigger { continue }
        ta   := comp_get(w, a, .Transform, TransformComp)
        ra   := ca.radius

        for j in i+1..<n {
            b  := ids[j]
            cb := comp_get(w, b, .Collider, ColliderComp)
            if cb.is_trigger { continue }
            tb := comp_get(w, b, .Transform, TransformComp)
            rb := cb.radius

            dx      := ta.position[0] - tb.position[0]
            dy      := ta.position[1] - tb.position[1]
            dist_sq := dx*dx + dy*dy
            min_d   := ra + rb

            if dist_sq >= min_d * min_d { continue }

            dist    := math.sqrt(dist_sq)
            overlap := min_d - dist

            if dist < 0.5 {


                ta.position[1] -= overlap * 0.5
                tb.position[1] += overlap * 0.5
                continue
            }


            nx := dx / dist
            ny := dy / dist
            push := overlap * 0.5
            ta.position[0] += nx * push
            ta.position[1] += ny * push
            tb.position[0] -= nx * push
            tb.position[1] -= ny * push
        }
    }
}
