package main

import "core:math"

greybox_collision_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .LateUpdate { return }

    boxes := world_query(w, query_mask(.Greybox, .Transform))
    defer delete(boxes)
    if len(boxes) == 0 { return }

    movers := world_query(w, query_mask(.Transform, .Collider))
    defer delete(movers)

    for mid in movers {
        if player_has_mutation_effect(w, mid, .MutWallPhase) { continue }

        t := comp_get(w, mid, .Transform, TransformComp)
        r := comp_get(w, mid, .Collider, ColliderComp).radius

        for bid in boxes {
            if bid == mid { continue }
            gb := comp_get(w, bid, .Greybox, GreyboxComp)
            if !gb.solid { continue }

            bt := comp_get(w, bid, .Transform, TransformComp)
            resolve_box_overlap(t, r, bt.position[0], bt.position[1], gb.size[0], gb.size[1])
        }
    }

    shots := world_query(w, query_mask(.ProjectileTag, .Transform))
    defer delete(shots)

    for sid in shots {
        if world_tag_is_destroy(w, sid) { continue }
        p := comp_get(w, sid, .Transform, TransformComp).position

        for bid in boxes {
            gb := comp_get(w, bid, .Greybox, GreyboxComp)
            if !gb.solid { continue }

            bt := comp_get(w, bid, .Transform, TransformComp)
            if point_in_box(p[0], p[1], bt.position[0], bt.position[1], gb.size[0], gb.size[1]) {
                world_tag_destroy(w, sid)
                break
            }
        }
    }
}

@(private = "file")
point_in_box :: proc(px, py, cx, cy, sx, sy: f32) -> bool {
    hx := max(sx, 1) * 0.5
    hy := max(sy, 1) * 0.5
    return px >= cx - hx && px <= cx + hx && py >= cy - hy && py <= cy + hy
}

@(private = "file")
resolve_box_overlap :: proc(t: ^TransformComp, radius, cx, cy, sx, sy: f32) {
    hx := max(sx, 1) * 0.5
    hy := max(sy, 1) * 0.5

    min_x := cx - hx
    max_x := cx + hx
    min_y := cy - hy
    max_y := cy + hy

    px := t.position[0]
    py := t.position[1]
    near_x := clamp(px, min_x, max_x)
    near_y := clamp(py, min_y, max_y)
    ddx := px - near_x
    ddy := py - near_y
    sq  := ddx*ddx + ddy*ddy
    if sq >= radius * radius { return }
    dist := math.sqrt(sq)
    if dist < 0.001 {
        left := px - min_x; right := max_x - px
        up := py - min_y; down := max_y - py
        m := min(min(left, right), min(up, down))
        switch {
        case m == left: t.position[0] = min_x - radius - 0.5
        case m == right: t.position[0] = max_x + radius + 0.5
        case m == up: t.position[1] = min_y - radius - 0.5
        case: t.position[1] = max_y + radius + 0.5
        }
        return
    }
    push := radius - dist
    t.position[0] += ddx / dist * push
    t.position[1] += ddy / dist * push
}
