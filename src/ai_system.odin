package main

import "core:math"
import "core:math/rand"
import cw "clockwork"

ARC_LIFETIME :: f32(0.22)
ARC_SPREAD   :: f32(math.PI / 2.8)

RANGED_SPAWN_OFFSET :: f32(20)


AI_AIM_DEVIATION_MAX :: f32(math.PI / 6.0)

@(private)
nearest_player_pos :: proc(w: ^cw.World, origin: [3]f32) -> (pos: [3]f32, target_id: int, found: bool) {
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
    if best_id < 0 { return {}, -1, false }


    if cw.world_has_component(w, best_id, .MutationContainer) {
        mc := cw.world_get_mutation(w, best_id)
        for mi in 0..<mc.entity_count {
            meid := mc.entities[mi]
            if !cw.world_is_valid(w, meid)                     { continue }
            if !cw.world_has_component(w, meid, .MutHeartCage) { continue }
            hc := cw.world_get_mut_heart_cage(w, meid)
            if cw.world_is_valid(w, hc.heart_id) &&
               cw.world_has_component(w, hc.heart_id, .Transform) &&
               cw.world_has_component(w, hc.heart_id, .Health) &&
               cw.world_get_health(w, hc.heart_id).current > 0 {
                return cw.world_get_transform(w, hc.heart_id).position, best_id, true
            }
            break
        }
    }

    return cw.world_get_transform(w, best_id).position, best_id, true
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

        player_pos, target_pid, has_player := nearest_player_pos(w, t.position)


        pdx, pdy, pdist: f32
        pndx, pndy: f32
        if has_player {
            pdx   = player_pos[0] - t.position[0]
            pdy   = player_pos[1] - t.position[1]
            pdist = math.sqrt(pdx*pdx + pdy*pdy)
            if pdist > 0.5 {
                pndx = pdx / pdist
                pndy = pdy / pdist
            }
        }


        lkdx  := ai.last_known_pos[0] - t.position[0]
        lkdy  := ai.last_known_pos[1] - t.position[1]
        lkdist := math.sqrt(lkdx*lkdx + lkdy*lkdy)

        switch ai.state {


        case AI_STATE_IDLE, AI_STATE_SUSPICIOUS:
            v.value = {}

            if ai.state == AI_STATE_SUSPICIOUS && lkdist > 0.5 {
                t.rotation = math.atan2(lkdy, lkdx)
            }


        case AI_STATE_SEARCHING:
            if lkdist > 12 {
                lknx  := lkdx / lkdist
                lkny  := lkdy / lkdist
                t.rotation = math.atan2(lkny, lknx)
                spd   := ai.speed if ai.speed > 0 else 80
                steer := ai_navigate(id,
                    { t.position[0], t.position[1] },
                    { ai.last_known_pos[0], ai.last_known_pos[1] },
                    dt)
                if steer[0] != 0 || steer[1] != 0 {
                    v.value = { steer[0] * spd * 0.8, steer[1] * spd * 0.8, 0 }
                } else {
                    v.value = { lknx * spd * 0.8, lkny * spd * 0.8, 0 }
                }
            } else {
                v.value = {}
            }


        case AI_STATE_CHASE, AI_STATE_ATTACK:
            if !has_player {
                v.value = {}
                continue
            }


            if pdist > 0.5 {
                t.rotation = math.atan2(pndy, pndx)
            }

            if pdist <= ai.attack_range {

                ai.state = AI_STATE_ATTACK
                v.value  = {}

                if ai.cooldown <= 0 {
                    angle    := math.atan2(pndy, pndx)
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


                        aim_deviation: f32 = 0
                        if target_pid >= 0 && cw.world_has_component(w, target_pid, .Velocity) {
                            tv  := cw.world_get_velocity(w, target_pid).value
                            spd := math.sqrt(tv[0]*tv[0] + tv[1]*tv[1])
                            if spd > 1.0 {
                                speed_factor := min(spd / MOVE_SPEED, 1.0)
                                rng          := rand.create(u64(w.tick) ~ (u64(id) * 6364136223846793005))
                                ctx          := rand.default_random_generator(&rng)
                                r            := rand.float32(ctx)
                                aim_deviation = (r * 2.0 - 1.0) * AI_AIM_DEVIATION_MAX * speed_factor
                            }
                        }

                        for i in 0..<pellets {
                            t_ratio      := f32(i) / f32(max(pellets - 1, 1))
                            offset_angle := spread * (t_ratio - 0.5)
                            pellet_angle := angle + offset_angle + aim_deviation
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

            } else {

                ai.state = AI_STATE_CHASE
                spd := ai.speed if ai.speed > 0 else 80
                steer := ai_navigate(id,
                    { t.position[0], t.position[1] },
                    { player_pos[0], player_pos[1] },
                    dt)
                if steer[0] != 0 || steer[1] != 0 {
                    v.value = { steer[0] * spd, steer[1] * spd, 0 }
                } else {
                    v.value = { pndx * spd, pndy * spd, 0 }
                }
            }
        }
    }
}
