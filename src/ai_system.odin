package main

import "core:math"

ARC_LIFETIME :: f32(0.22)
ARC_SPREAD   :: f32(math.PI / 2.8)

RANGED_SPAWN_OFFSET :: f32(20)

AI_DEFAULT_WINDUP_MELEE  :: f32(0.4)
AI_DEFAULT_WINDUP_RANGED :: f32(0.55)
AI_RANGED_AIM_LOCK_AT    :: f32(0.6)
AI_INTERRUPT_COOLDOWN    :: f32(0.35)
AI_DEFAULT_PROJ_SPEED    :: f32(420)
AI_PROJ_REACH_MULT       :: f32(1.2)

@(private)
nearest_player_pos :: proc(w: ^World, origin: [3]f32) -> (pos: [3]f32, target_id: int, found: bool) {
    best_dist := f32(1e30)
    best_id   := -1
    for slot in 0..<MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !world_is_valid(w, pid) { continue }
        if !world_has_component(w, pid, .Transform) { continue }
        if world_has_component(w, pid, .Respawn) &&
           comp_get(w, pid, .Respawn, RespawnComp).timer > 0 { continue }
        pt := comp_get(w, pid, .Transform, TransformComp)
        dx := pt.position[0] - origin[0]
        dy := pt.position[1] - origin[1]
        d  := dx*dx + dy*dy
        if d < best_dist || (d == best_dist && pid < best_id) {
            best_dist = d
            best_id   = pid
        }
    }
    if best_id < 0 { return {}, -1, false }

    if world_has_component(w, best_id, .MutationContainer) {
        mc := comp_get(w, best_id, .MutationContainer, MutationContainerComp)
        for mi in 0..<mc.entity_count {
            meid := mc.entities[mi]
            if !world_is_valid(w, meid)                     { continue }
            if !world_has_component(w, meid, .MutHeartCage) { continue }
            hc := comp_get(w, meid, .MutHeartCage, MutHeartCageComp)
            if world_is_valid(w, hc.heart_id) &&
               world_has_component(w, hc.heart_id, .Transform) &&
               world_has_component(w, hc.heart_id, .Health) &&
               comp_get(w, hc.heart_id, .Health, HealthComp).current > 0 {
                return comp_get(w, hc.heart_id, .Transform, TransformComp).position, best_id, true
            }
            break
        }
    }

    return comp_get(w, best_id, .Transform, TransformComp).position, best_id, true
}

ai_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    ids := world_query(w, query_mask(.AIAgent, .Transform, .Velocity))
    defer delete(ids)

    for id in ids {
        t  := comp_get(w, id, .Transform, TransformComp)
        v  := comp_get(w, id, .Velocity, VelocityComp)
        ai := comp_get(w, id, .AIAgent, AIAgentComp)

        if ai.cooldown > 0 {
            ai.cooldown -= dt
            if ai.cooldown < 0 { ai.cooldown = 0 }
        }

        if world_has_component(w, id, .StatusEffect) &&
           status_effect_is_active(comp_get(w, id, .StatusEffect, StatusEffectComp), .Stun) {
            v.value = {}
            if ai.windup > 0 {
                ai.windup   = 0
                ai.cooldown = max(ai.cooldown, AI_INTERRUPT_COOLDOWN)
            }
            continue
        }

        if ai.windup > 0 {
            v.value = {}
            if _, _, alive := nearest_player_pos(w, t.position); !alive {
                ai.windup = 0
                continue
            }
            progress := 1 - ai.windup / max(ai.windup_max, 0.001)
            if ai.ai_type == .Ranged && progress < AI_RANGED_AIM_LOCK_AT {
                if pp, _, ok := nearest_player_pos(w, t.position); ok {
                    ai.windup_angle = math.atan2(pp[1] - t.position[1], pp[0] - t.position[0])
                }
            }
            t.rotation = ai.windup_angle
            ai.windup -= dt
            if ai.windup <= 0 {
                ai.windup = 0
                _ai_release_attack(w, id, ai.windup_angle)
            }
            continue
        }

        player_pos, _, has_player := nearest_player_pos(w, t.position)

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

            can_strike := pdist <= ai.attack_range && ai_has_line_of_sight(t.position, player_pos)
            if can_strike {
                ai.state = AI_STATE_ATTACK
                v.value  = {}

                if ai.cooldown <= 0 {
                    ai.windup       = ai.windup_max
                    ai.windup_angle = math.atan2(pndy, pndx)
                    ai.cooldown     = max(ai.cooldown_max, ai.windup_max)
                    t.rotation      = ai.windup_angle
                    play_sfx_at("enemy_windup", t.position)
                    if ai.windup <= 0 {
                        _ai_release_attack(w, id, ai.windup_angle)
                    }
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

ai_has_line_of_sight :: proc(from, to: [3]f32) -> bool {
    return raycast_walls_t(from[0], from[1], to[0], to[1]) >= 1
}

ai_pellet_layout :: proc(ai: AIAgentComp) -> (count: int, spread: f32) {
    count  = ai.pellet_count if ai.pellet_count > 0 else 5
    spread = ai.spread_angle if ai.spread_angle > 0 else (math.PI / 6)
    return
}

ai_projectile_reach :: proc(ai: AIAgentComp) -> (speed, life: f32) {
    speed = ai.proj_speed if ai.proj_speed > 0 else AI_DEFAULT_PROJ_SPEED
    life  = max(ai.attack_range, 64) * AI_PROJ_REACH_MULT / speed
    return
}

ai_resolve_windup :: proc(a: AIAgentDef) -> f32 {
    wu := a.windup
    if wu <= 0 {
        wu = AI_DEFAULT_WINDUP_RANGED if a.ai_type == .Ranged else AI_DEFAULT_WINDUP_MELEE
    }
    if a.cooldown_max > 0 { wu = min(wu, a.cooldown_max) }
    return wu
}

@(private = "file")
_ai_release_attack :: proc(w: ^World, id: int, angle: f32) {
    pos_snap := comp_get(w, id, .Transform, TransformComp).position
    ai_snap  := comp_get(w, id, .AIAgent, AIAgentComp)^

    switch ai_snap.ai_type {
    case .Melee:
        play_sfx_at("enemy_melee", pos_snap)
        arc_id := world_create_entity(w)
        comp_set(w, arc_id, .Transform, TransformComp{
            position = pos_snap,
            rotation = angle,
        })
        comp_set(w, arc_id, .MeleeArc, MeleeArcComp{
            angle         = angle,
            arc_spread    = ARC_SPREAD,
            radius        = ai_snap.attack_range,
            damage        = ai_snap.damage,
            owner_id      = id,
            owner_faction = 1,
            lifetime      = ARC_LIFETIME,
        })
        comp_set(w, arc_id, .SelfDestruct, SelfDestructComp{
            timer = ARC_LIFETIME,
        })
        comp_add(w, arc_id, .FogOfWar)

    case .Ranged:
        proj_speed, proj_life := ai_projectile_reach(ai_snap)
        proj_damage : f32 = ai_snap.damage

        if world_has_component(w, id, .Equipment) {
            equip := comp_get(w, id, .Equipment, EquipmentComp)
            wid   := equip.weapon_entity_id
            if world_is_valid(w, wid) &&
               world_has_component(w, wid, .Weapon) {
                wp := comp_get(w, wid, .Weapon, WeaponComp)
                if wp.projectile_speed > 0 { proj_speed  = wp.projectile_speed }
                if wp.projectile_life  > 0 { proj_life   = wp.projectile_life  }
                if wp.damage           > 0 { proj_damage = wp.damage           }
            }
        }

        pellets, spread := ai_pellet_layout(ai_snap)

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

            pid := world_create_entity(w)
            comp_set(w, pid, .Transform, TransformComp{
                position = spawn_pos,
                rotation = pellet_angle,
            })
            comp_set(w, pid, .Projectile, ProjectileComp{
                direction     = pdir,
                speed         = proj_speed,
                lifetime      = proj_life,
                max_lifetime  = proj_life,
                damage        = proj_damage,
                owner_id      = id,
                owner_faction = 1,
                visual        = .Smoke,
            })
            comp_set(w, pid, .SelfDestruct, SelfDestructComp{
                timer = proj_life,
            })
            comp_add(w, pid, .ProjectileTag)
            comp_add(w, pid, .FogOfWar)
        }
        play_sfx_at("enemy_shoot", pos_snap)
    }
}
