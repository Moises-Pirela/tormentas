package main

import     "core:math"

wall_collision_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .LateUpdate { return }

    ids := world_query(w, query_mask(.Transform, .Collider))
    defer delete(ids)

    for id in ids {
        if player_has_mutation_effect(w, id, .MutWallPhase) { continue }
        t := comp_get(w, id, .Transform, TransformComp)
        r := comp_get(w, id, .Collider, ColliderComp).radius
        resolve_wall_overlap(t, r)
    }
}

projectile_wall_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .LateUpdate { return }

    ids := world_query(w, query_mask(.ProjectileTag, .Transform))
    defer delete(ids)

    for id in ids {
        if world_tag_is_destroy(w, id) { continue }
        t      := comp_get(w, id, .Transform, TransformComp)
        tx, ty := world_to_tile(t.position[0], t.position[1])
        if tile_base(tile_at(tx, ty)) != .Floor {
            world_tag_destroy(w, id)
        }
    }
}

@(private = "file")
resolve_wall_overlap :: proc(t: ^TransformComp, radius: f32) {
    cx := t.position[0]
    cy := t.position[1]

    ctx, cty := world_to_tile(cx, cy)
    ts       := f32(TILE_SIZE)

    for dy in -2..=2 {
        for dx in -2..=2 {
            wx := ctx + dx
            wy := cty + dy
            if tile_base(tile_at(wx, wy)) == .Floor { continue }

            tile_x := f32(wx * TILE_SIZE)
            tile_y := f32(wy * TILE_SIZE)

            near_x := clamp(cx, tile_x, tile_x + ts)
            near_y := clamp(cy, tile_y, tile_y + ts)
            ddx := cx - near_x
            ddy := cy - near_y
            sq  := ddx*ddx + ddy*ddy
            if sq >= radius * radius { continue }
            dist := math.sqrt(sq)
            if dist < 0.001 {
                t.position[1] = tile_y - radius - 0.5
                cy = t.position[1]
                continue
            }
            push := radius - dist
            t.position[0] += ddx / dist * push
            t.position[1] += ddy / dist * push
            cx = t.position[0]
            cy = t.position[1]
        }
    }
}
