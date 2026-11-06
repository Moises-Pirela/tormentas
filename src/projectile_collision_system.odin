package main

import "core:math"

PROJ_RADIUS    :: f32(4)
MAX_SWEEP_HITS :: 16

@(private = "file")
SweepHit :: struct {
    t:  f32,
    id: int,
}

PLAYER_SHOT_GRACE    :: f32(6)
ENEMY_SHOT_FORGIVE   :: f32(4)

projectile_hit_radius :: proc(target_radius: f32, shooter_faction: u8) -> f32 {
    r := target_radius + PROJ_RADIUS
    r += PLAYER_SHOT_GRACE if shooter_faction == 0 else -ENEMY_SHOT_FORGIVE
    return max(r, 2)
}

@(private = "file")
_projectile_can_hit :: proc(w: ^World, target_id: int, proj: ^ProjectileComp) -> bool {
    if world_tag_is_destroy(w, target_id) { return false }
    col := comp_get(w, target_id, .Collider, ColliderComp)
    if col.is_trigger                      { return false }
    if col.faction == proj.owner_faction   { return false }
    if comp_get(w, target_id, .Health, HealthComp).current <= 0 { return false }
    if world_has_component(w, target_id, .Respawn) &&
       comp_get(w, target_id, .Respawn, RespawnComp).timer > 0 { return false }
    if world_has_component(w, target_id, .DodgeState) &&
       comp_get(w, target_id, .DodgeState, DodgeComp).active { return false }
    return true
}

projectile_segment_start :: proc(w: ^World, proj: ^ProjectileComp, pos: [3]f32) -> [2]f32 {
    if proj.has_prev { return proj.prev_pos }
    if world_is_valid(w, proj.owner_id) && world_has_component(w, proj.owner_id, .Transform) {
        op := comp_get(w, proj.owner_id, .Transform, TransformComp).position
        return { op[0], op[1] }
    }
    return { pos[0], pos[1] }
}

projectile_collision_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    proj_ids := world_query(w, query_mask(.ProjectileTag, .Projectile, .Transform))
    defer delete(proj_ids)

    target_ids := world_query(w, query_mask(.Collider, .Health, .Transform))
    defer delete(target_ids)

    boxes := world_query(w, query_mask(.Greybox, .Transform))
    defer delete(boxes)

    for proj_id in proj_ids {
        proj   := comp_get(w, proj_id, .Projectile, ProjectileComp)
        if world_tag_is_destroy(w, proj_id) && proj.lifetime > 0 { continue }
        proj_t := comp_get(w, proj_id, .Transform, TransformComp)

        a  := projectile_segment_start(w, proj, proj_t.position)
        ax := a[0]
        ay := a[1]
        bx := proj_t.position[0]
        by := proj_t.position[1]
        dx := bx - ax
        dy := by - ay
        proj.prev_pos = { bx, by }
        proj.has_prev = true

        t_block := raycast_walls_t(ax, ay, bx, by)
        for bid in boxes {
            gb := comp_get(w, bid, .Greybox, GreyboxComp)
            if !gb.solid { continue }
            bt := comp_get(w, bid, .Transform, TransformComp).position
            hx := max(gb.size[0], 1) * 0.5
            hy := max(gb.size[1], 1) * 0.5
            if tb, hit := _ray_bounds_t(ax, ay, dx, dy, bt[0] - hx, bt[1] - hy, bt[0] + hx, bt[1] + hy); hit {
                t_block = min(t_block, tb)
            }
        }

        hits:   [MAX_SWEEP_HITS]SweepHit
        n_hits: int
        for target_id in target_ids {
            if target_id == proj_id || target_id == proj.owner_id { continue }
            if !_projectile_can_hit(w, target_id, proj) { continue }
            tp := comp_get(w, target_id, .Transform, TransformComp).position
            r  := projectile_hit_radius(entity_hit_radius(w, target_id), proj.owner_faction)
            th: f32
            hit: bool
            if dx*dx + dy*dy < 1e-6 {
                ox := bx - tp[0]
                oy := by - tp[1]
                hit = ox*ox + oy*oy <= r*r
            } else {
                th, hit = _ray_circle_t(ax, ay, dx, dy, tp[0], tp[1], r)
            }
            if !hit || th > t_block { continue }
            if n_hits < MAX_SWEEP_HITS {
                k := n_hits
                for k > 0 && hits[k-1].t > th { hits[k] = hits[k-1]; k -= 1 }
                hits[k] = SweepHit{ th, target_id }
                n_hits += 1
            }
        }

        stop_t    := f32(1)
        destroyed := false
        for k in 0..<n_hits {
            tid := hits[k].id
            tt  := comp_get(w, tid, .Transform, TransformComp)
            if _apply_proj_hit(w, proj_id, proj, tid, tt.position) {
                stop_t    = hits[k].t
                destroyed = true
                break
            }
        }
        if !destroyed && t_block < 1 {
            stop_t    = t_block
            destroyed = true
        }

        if destroyed {
            proj_t.position[0] = ax + dx * stop_t
            proj_t.position[1] = ay + dy * stop_t
            world_tag_destroy(w, proj_id)
        }
    }
}

@(private = "file")
_apply_proj_hit :: proc(w: ^World, proj_id: int, proj: ^ProjectileComp, target_id: int, target_pos: [3]f32) -> (destroy: bool) {
    for i in 0..<int(proj.hit_count) {
        if int(proj.hit_ids[i]) == target_id { return false }
    }
    if int(proj.hit_count) < PROJECTILE_HIT_MEMORY {
        proj.hit_ids[proj.hit_count] = i32(target_id)
        proj.hit_count += 1
    }
    world_push_damage(w, target_id, proj.damage, proj.owner_id)

    if world_has_component(w, proj_id, .DamageAmpOnHit) {
        dah := comp_get(w, proj_id, .DamageAmpOnHit, DamageAmpOnHitComp)
        if world_has_component(w, target_id, .DamageAmp) {
            da      := comp_get(w, target_id, .DamageAmp, DamageAmpComp)
            da.mult  = min(da.mult * dah.mult, DAMAGE_AMP_MAX)
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

@(private = "file")
_ray_bounds_t :: proc(ax, ay, dx, dy, min_x, min_y, max_x, max_y: f32) -> (t: f32, hit: bool) {
    enter := f32(0)
    exit := f32(1)
    origins := [2]f32{ax, ay}
    deltas  := [2]f32{dx, dy}
    lows    := [2]f32{min_x, min_y}
    highs   := [2]f32{max_x, max_y}
    for i in 0..<2 {
        origin := origins[i]
        delta  := deltas[i]
        low    := lows[i]
        high   := highs[i]
        if abs(delta) < 1e-9 {
            if origin < low || origin > high { return 0, false }
            continue
        }
        a := (low - origin) / delta
        b := (high - origin) / delta
        if a > b { a, b = b, a }
        enter = max(enter, a)
        exit = min(exit, b)
        if enter > exit { return 0, false }
    }
    return enter, true
}

raycast_walls_t :: proc(ax, ay, bx, by: f32) -> f32 {
    ix, iy := world_to_tile(ax, ay)
    if !tile_is_walkable(ix, iy) { return 0 }

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
        if !tile_is_walkable(ix, iy) { return t_enter }
    }
}
