package main

import "core:math"
import cw "clockwork"

ARC_LIFETIME :: f32(0.22)          
ARC_SPREAD   :: f32(math.PI / 2.8) 

RANGED_SPAWN_OFFSET :: f32(20) 


@(private)
nearest_player_pos :: proc(w: ^cw.World, origin: [3]f32) -> (pos: [3]f32, found: bool) {
    best_dist := f32(1e30)
    best_id   := -1
    for slot in 0..<cw.MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !cw.world_is_valid(w, pid) { continue }
        if !cw.world_has_component(w, pid, .Transform) { continue }
        if cw.world_has_component(w, pid, .Respawn) &&
           cw.world_get_respawn(w, pid).timer > 0 { continue }
        pt := cw.world_get_transform(w, pid)
        dx := pt.position[0] - origin[0]
        dy := pt.position[1] - origin[1]
        d  := dx*dx + dy*dy
        if d < best_dist || (d == best_dist && pid < best_id) {
            best_dist = d
            best_id   = pid
        }
    }
    if best_id < 0 { return {}, false }
    return cw.world_get_transform(w, best_id).position, true
}

ai_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }

    ids := cw.world_query(w, cw.query_mask(.AIAgent, .Transform, .Velocity))
    defer delete(ids)

    for id in ids {
        t  := cw.world_get_transform(w, id)
        v  := cw.world_get_velocity(w, id)
        ai := cw.world_get_ai(w, id)

        if ai.cooldown > 0 {
            ai.cooldown -= dt
            if ai.cooldown < 0 { ai.cooldown = 0 }
        }

        player_pos, has_player := nearest_player_pos(w, t.position)
        if !has_player {
            v.value = {}
            continue
        }

        dx   := player_pos[0] - t.position[0]
        dy   := player_pos[1] - t.position[1]
        dist := math.sqrt(dx*dx + dy*dy)

        ndx, ndy: f32
        if dist > 0.5 {
            ndx = dx / dist
            ndy = dy / dist
        }

        if dist <= ai.aggro_range && dist > 0.5 {
            t.rotation = math.atan2(ndy, ndx)
        }

        switch {

        case dist <= ai.attack_range:
            v.value = {}   // stop in place

            if ai.cooldown <= 0 {
                angle    := math.atan2(ndy, ndx)
                pos_snap := t.position
                ai_snap  := ai^

                switch ai_snap.ai_type {

                case .Melee:
                    play_sfx_at("enemy_melee", pos_snap)
                    arc_id := cw.world_create_entity(w)
                    cw.world_set_transform(w, arc_id, cw.TransformComp{
                        position = pos_snap,
                        rotation = angle,
                    })
                    cw.world_set_melee_arc(w, arc_id, cw.MeleeArcComp{
                        angle         = angle,
                        arc_spread    = ARC_SPREAD,
                        radius        = ai_snap.attack_range,
                        damage        = ai_snap.damage,
                        owner_id      = id,
                        owner_faction = 1,
                        lifetime      = ARC_LIFETIME,
                    })
                    cw.world_set_self_destruct(w, arc_id, cw.SelfDestructComp{
                        timer = ARC_LIFETIME,
                    })
                    cw.world_set_fog_of_war(w, arc_id)

                case .Ranged:
                    proj_speed  : f32 = 380
                    proj_life   : f32 = 0.50
                    proj_damage : f32 = ai_snap.damage

                    if cw.world_has_component(w, id, .Equipment) {
                        equip := cw.world_get_equipment(w, id)
                        wid   := equip.weapon_entity_id
                        if cw.world_is_valid(w, wid) &&
                           cw.world_has_component(w, wid, .Weapon) {
                            wp := cw.world_get_weapon_data(w, wid)
                            if wp.projectile_speed > 0 { proj_speed  = wp.projectile_speed }
                            if wp.projectile_life  > 0 { proj_life   = wp.projectile_life  }
                            if wp.damage           > 0 { proj_damage = wp.damage           }
                        }
                    }

                    pellets := ai_snap.pellet_count if ai_snap.pellet_count > 0 else 5
                    spread  := ai_snap.spread_angle if ai_snap.spread_angle > 0 else (math.PI / 6)

                    for i in 0..<pellets {
                        t_ratio      := f32(i) / f32(max(pellets - 1, 1))
                        offset_angle := spread * (t_ratio - 0.5)
                        pellet_angle := angle + offset_angle
                        pdir := [3]f32{
                            math.cos(pellet_angle),
                            math.sin(pellet_angle),
                            0,
                        }
                        spawn_pos := [3]f32{
                            pos_snap[0] + pdir[0] * RANGED_SPAWN_OFFSET,
                            pos_snap[1] + pdir[1] * RANGED_SPAWN_OFFSET,
                            0,
                        }

                        pid := cw.world_create_entity(w)
                        cw.world_set_transform(w, pid, cw.TransformComp{
                            position = spawn_pos,
                            rotation = pellet_angle,
                        })
                        cw.world_set_projectile(w, pid, cw.ProjectileComp{
                            direction     = pdir,
                            speed         = proj_speed,
                            lifetime      = proj_life,
                            max_lifetime  = proj_life,
                            damage        = proj_damage,
                            owner_id      = id,
                            owner_faction = 1,
                            visual        = .Smoke,
                        })
                        cw.world_set_self_destruct(w, pid, cw.SelfDestructComp{
                            timer = proj_life,
                        })
                        cw.world_set_projectile_tag(w, pid)
                        cw.world_set_fog_of_war(w, pid)
                    }
                    play_sfx_at("enemy_shoot", pos_snap)
                }

                cw.world_get_ai(w, id).cooldown = ai_snap.cooldown_max
            }

        case dist <= ai.aggro_range:
            spd := ai.speed if ai.speed > 0 else 80
            steer := ai_navigate(id,
                { t.position[0], t.position[1] },
                { player_pos[0], player_pos[1] },
                dt)
            if steer[0] != 0 || steer[1] != 0 {
                v.value = { steer[0] * spd, steer[1] * spd, 0 }
            } else {
                v.value = { ndx * spd, ndy * spd, 0 }
            }

        case:
            v.value = {}
        }
    }
}
