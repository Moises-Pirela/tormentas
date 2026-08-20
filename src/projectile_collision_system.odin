package main

import "core:math"

PROJ_RADIUS    :: f32(4)
MAX_SWEEP_HITS :: 16

@(private = "file")
SweepHit :: struct {
    t:  f32,
    id: int,
}

projectile_collision_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    proj_ids := world_query(w, query_mask(.ProjectileTag, .Projectile, .Transform))
    defer delete(proj_ids)

    target_ids := world_query(w, query_mask(.Collider, .Health, .Transform))
    defer delete(target_ids)

    for proj_id in proj_ids {
        if world_tag_is_destroy(w, proj_id) { continue }

        proj   := comp_get(w, proj_id, .Projectile, ProjectileComp)
        proj_t := comp_get(w, proj_id, .Transform, TransformComp)

        bx := proj_t.position[0]
        by := proj_t.position[1]

        ax := bx - proj.direction[0] * proj.speed * dt
        ay := by - proj.direction[1] * proj.speed * dt

        dx := bx - ax
        dy := by - ay

        if dx*dx + dy*dy < 1.0 {
            for target_id in target_ids {
                if target_id == proj_id { continue }
                col := comp_get(w, target_id, .Collider, ColliderComp)
                if col.faction == proj.owner_faction { continue }
                tt  := comp_get(w, target_id, .Transform, TransformComp)
                ddx := tt.position[0] - bx
                ddy := tt.position[1] - by
                rr  := PROJ_RADIUS + col.radius
                if ddx*ddx + ddy*ddy < rr*rr {
                    if _apply_proj_hit(w, proj_id, proj, target_id, tt.position) {
                        world_tag_destroy(w, proj_id)
                        break
                    }
                }
            }
            continue
        }

        t_wall := raycast_walls_t(ax, ay, bx, by)

        hits:   [MAX_SWEEP_HITS]SweepHit
        n_hits: int
        for target_id in target_ids {
            if target_id == proj_id { continue }
            col := comp_get(w, target_id, .Collider, ColliderComp)
            if col.faction == proj.owner_faction { continue }
            tt := comp_get(w, target_id, .Transform, TransformComp)
            th, hit := _ray_circle_t(ax, ay, dx, dy, tt.position[0], tt.position[1], PROJ_RADIUS + col.radius)
            if !hit || th > t_wall { continue }
            if n_hits < MAX_SWEEP_HITS {
                k := n_hits
                for k > 0 && hits[k-1].t > th { hits[k] = hits[k-1]; k -= 1 }
                hits[k] = SweepHit{ th, target_id }
                n_hits += 1
            }
        }

        destroyed := false
        stop_t    := f32(1)
        for k in 0..<n_hits {
            tid := hits[k].id
            tt  := comp_get(w, tid, .Transform, TransformComp)
            if _apply_proj_hit(w, proj_id, proj, tid, tt.position) {
                stop_t    = hits[k].t
                destroyed = true
                break
            }
        }

        if destroyed {
            proj_t.position[0] = ax + dx * stop_t
            proj_t.position[1] = ay + dy * stop_t
            world_tag_destroy(w, proj_id)
        } else if t_wall < 1 {
            proj_t.position[0] = ax + dx * t_wall
            proj_t.position[1] = ay + dy * t_wall
            world_tag_destroy(w, proj_id)
        }
    }
}

@(private = "file")
_apply_proj_hit :: proc(w: ^World, proj_id: int, proj: ^ProjectileComp, target_id: int, target_pos: [3]f32) -> (destroy: bool) {
    world_push_damage(w, target_id, proj.damage, proj.owner_id)

    if world_has_component(w, proj_id, .DamageAmpOnHit) {
        dah := comp_get(w, proj_id, .DamageAmpOnHit, DamageAmpOnHitComp)
        if world_has_component(w, target_id, .DamageAmp) {
            da      := comp_get(w, target_id, .DamageAmp, DamageAmpComp)
            da.mult *= dah.mult
            da.timer = max(da.timer, dah.dur)
        } else {
            comp_set(w, target_id, .DamageAmp, DamageAmpComp{ mult = dah.mult, timer = dah.dur })
        }
        comp_rm(w, proj_id, .DamageAmpOnHit)
    }

    if target_id != w.player_id {
        play_sfx_at("impact", target_pos)
    }

    if proj.pierce_remaining > 0 {
        proj.pierce_remaining -= 1
        return false
    }
    return true
}

@(private = "file")
_ray_circle_t :: proc(ax, ay, dx, dy, cx, cy, r: f32) -> (t: f32, hit: bool) {
    fx := ax - cx
    fy := ay - cy
    a  := dx*dx + dy*dy
    if a < 1e-9 { return 0, false }
    c  := fx*fx + fy*fy - r*r
    if c <= 0 { return 0, true }
    b    := 2*(fx*dx + fy*dy)
    disc := b*b - 4*a*c
    if disc < 0 { return 0, false }
    sq := math.sqrt(disc)
    tt := (-b - sq) / (2*a)
    if tt < 0 || tt > 1 { return 0, false }
    return tt, true
}

raycast_walls_t :: proc(ax, ay, bx, by: f32) -> f32 {
    ix, iy := world_to_tile(ax, ay)
    if tile_base(tile_at(ix, iy)) != .Floor { return 0 }

    ts := f32(TILE_SIZE)
    dx := bx - ax
    dy := by - ay

    INF :: f32(1e30)
    step_x, step_y := 0, 0
    t_max_x, t_max_y := INF, INF
    t_dlt_x, t_dlt_y := INF, INF

    if dx > 0 {
        step_x  = 1
        t_max_x = (f32(ix+1)*ts - ax) / dx
        t_dlt_x = ts / dx
    } else if dx < 0 {
        step_x  = -1
        t_max_x = (f32(ix)*ts - ax) / dx
        t_dlt_x = -ts / dx
    }
    if dy > 0 {
        step_y  = 1
        t_max_y = (f32(iy+1)*ts - ay) / dy
        t_dlt_y = ts / dy
    } else if dy < 0 {
        step_y  = -1
        t_max_y = (f32(iy)*ts - ay) / dy
        t_dlt_y = -ts / dy
    }

    for {
        t_enter: f32
        if t_max_x < t_max_y {
            ix     += step_x
            t_enter = t_max_x
            t_max_x += t_dlt_x
        } else {
            iy     += step_y
            t_enter = t_max_y
            t_max_y += t_dlt_y
        }
        if t_enter > 1 { return 1 }
        if tile_base(tile_at(ix, iy)) != .Floor { return t_enter }
    }
}
