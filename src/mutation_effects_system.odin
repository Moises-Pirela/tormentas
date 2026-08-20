package main

import "core:math"

mutation_effects_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    #partial switch event {
    case .EarlyUpdate:

        mut_owners := world_query(w, query_mask(.MutationContainer), context.temp_allocator)
        for pid in mut_owners {
            mc := comp_get(w, pid, .MutationContainer, MutationContainerComp)
            for i in 0..<mc.entity_count {
                eid := mc.entities[i]
                if !world_is_valid(w, eid) { continue }
                _mut_early_false_saint_beacon(w, pid, eid)
            }
        }

    case .Update:
        mut_owners := world_query(w, query_mask(.MutationContainer), context.temp_allocator)
        for pid in mut_owners {
            mc := comp_get(w, pid, .MutationContainer, MutationContainerComp)
            for i in 0..<mc.entity_count {
                eid := mc.entities[i]
                if !world_is_valid(w, eid) { continue }

                _mut_tick_proximity_damage(w, pid, eid, dt)
                _mut_tick_stationary_shield(w, pid, eid, dt)
                _mut_tick_body_melee(w, pid, eid, dt)
                _mut_tick_on_death_explode(w, eid, dt)
                _mut_tick_extra_dodge_charges(w, eid, dt)
                _mut_tick_heart_cage(w, pid, eid, dt)
                _mut_tick_black_lung(w, pid, eid, dt)
                _mut_tick_false_saint_slow(w, pid, eid, dt)
            }
        }

        _mut_tick_corpse_trigger(w, dt)
    }
}

@(private = "file")
_mut_tick_proximity_damage :: proc(w: ^World, pid: int, eid: int, dt: f32) {
    if !world_has_component(w, eid, .MutProximityDamage)  { return }
    if !world_has_component(w, pid, .Transform)           { return }

    pd  := comp_get(w, eid, .MutProximityDamage, MutProximityDamageComp)^

    pos := comp_get(w, pid, .Transform, TransformComp).position
    r2  := pd.radius * pd.radius

    if is_player_entity(w, pid) {
        ai_ids := world_query(w, query_mask(.AIAgent, .Transform), context.temp_allocator)
        for ai_id in ai_ids {
            if world_has_component(w, ai_id, .Reanimated) { continue }
            ap := comp_get(w, ai_id, .Transform, TransformComp).position
            dx := ap[0] - pos[0]
            dy := ap[1] - pos[1]
            if dx*dx + dy*dy > r2 { continue }

            if pd.dps > 0 {
                world_push_damage(w, ai_id, pd.dps * dt, pid)
            }
            if pd.effect_strength > 0 {
                status_effect_apply(w, ai_id, StatusEffect{
                    type           = pd.effect_type,
                    application    = .Percent,
                    stack_behavior = .Refresh,
                    duration       = pd.effect_duration,
                    strength       = pd.effect_strength,
                    source_id      = pid,
                })
            }
        }
    } else {
        for slot in 0..<MAX_PLAYERS {
            target_id := w.player_ids[slot]
            if !world_is_valid(w, target_id)                  { continue }
            if !world_has_component(w, target_id, .Transform) { continue }
            if world_has_component(w, target_id, .Respawn) &&
               comp_get(w, target_id, .Respawn, RespawnComp).timer > 0      { continue }
            tp := comp_get(w, target_id, .Transform, TransformComp).position
            dx := tp[0] - pos[0]
            dy := tp[1] - pos[1]
            if dx*dx + dy*dy > r2 { continue }
            if pd.dps > 0 {
                world_push_damage(w, target_id, pd.dps * dt, pid)
            }
        }
    }

    if pd.light_radius > 0 {
        lc := PointLightComp{
            color     = pd.light_color,
            radius    = pd.light_radius,
            intensity = pd.light_intensity,
        }
        if !world_has_component(w, pid, .PointLight) {
            comp_set(w, pid, .PointLight, lc)
        } else {
            comp_get(w, pid, .PointLight, PointLightComp)^ = lc
        }
    }
}

@(private = "file")
_mut_tick_stationary_shield :: proc(w: ^World, pid: int, eid: int, dt: f32) {
    if !world_has_component(w, eid, .MutStationaryShield) { return }

    ss := comp_get(w, eid, .MutStationaryShield, MutStationaryShieldComp)

    slot := -1
    if world_has_component(w, pid, .Player) {
        slot = comp_get(w, pid, .Player, PlayerComp).slot
    }
    if status_is_stationary(w, pid, slot) {
        ss.shield      = min(ss.shield + ss.regen_rate * dt, ss.shield_max)
        ss.was_moving  = false
    } else {
        ss.shield     = 0
        ss.was_moving = true
    }
}

@(private = "file")
_mut_tick_body_melee :: proc(w: ^World, pid: int, eid: int, dt: f32) {
    if !world_has_component(w, eid, .MutBodyMelee) { return }
    if !world_has_component(w, pid, .InputState)   { return }
    if !world_has_component(w, pid, .Transform)    { return }

    bm    := comp_get(w, eid, .MutBodyMelee, MutBodyMeleeComp)
    input := comp_get(w, pid, .InputState, InputStateComp)
    t     := comp_get(w, pid, .Transform, TransformComp)

    if bm.timer > 0 {
        bm.timer = max(0, bm.timer - dt)
    }

    if input.fire_pressed && bm.timer <= 0 {
        damage := bm.damage
        if world_has_component(w, pid, .Stats) {
            damage *= comp_get(w, pid, .Stats, StatsComp).damage_mult
        }

        arc_id := world_create_entity(w)
        comp_set(w, arc_id, .Transform, t^)
        comp_set(w, arc_id, .MeleeArc, MeleeArcComp{
            angle         = t.rotation,
            arc_spread    = bm.arc_angle,
            radius        = bm.range,
            damage        = damage,
            owner_id      = pid,
            owner_faction = 0,
            lifetime      = 0.12,
        })
        comp_set(w, arc_id, .SelfDestruct, SelfDestructComp{ timer = 0.12 })
        bm.timer = bm.cooldown_max
        if pid == w.player_id { play_sfx("melee_swing") }
    }
}

@(private = "file")
_mut_tick_on_death_explode :: proc(w: ^World, eid: int, dt: f32) {
    if !world_has_component(w, eid, .MutOnDeathExplode) { return }
    ode := comp_get(w, eid, .MutOnDeathExplode, MutOnDeathExplodeComp)
    if ode.timer > 0 {
        ode.timer = max(0, ode.timer - dt)
    }
}

@(private = "file")
_mut_tick_extra_dodge_charges :: proc(w: ^World, eid: int, dt: f32) {
    if !world_has_component(w, eid, .MutExtraDodgeCharges) { return }
    edc := comp_get(w, eid, .MutExtraDodgeCharges, MutExtraDodgeChargesComp)
    if edc.charges >= edc.count { return }
    edc.recharge_timer += dt
    if edc.recharge_timer >= edc.recharge_max {
        edc.recharge_timer = 0
        edc.charges        = min(edc.charges + 1, edc.count)
    }
}

@(private = "file")
_mut_tick_heart_cage :: proc(w: ^World, pid: int, eid: int, dt: f32) {
    if !world_has_component(w, eid, .MutHeartCage) { return }
    hc := comp_get(w, eid, .MutHeartCage, MutHeartCageComp)
    if hc.heart_id == INVALID_ENTITY { return }

    hc.orbit_angle += HEART_CAGE_ORBIT_SPEED * dt

    if !world_is_valid(w, hc.heart_id)                        { return }
    if !world_has_component(w, hc.heart_id, .Health)          { return }
    if comp_get(w, hc.heart_id, .Health, HealthComp).current <= 0          { return }

    if world_is_valid(w, hc.heart_id) &&
       world_has_component(w, pid, .Transform) {
        pt := comp_get(w, pid, .Transform, TransformComp)
        ht := comp_get(w, hc.heart_id, .Transform, TransformComp)
        r  := HEART_CAGE_ORBIT_RADIUS
        ht.position[0] = pt.position[0] + math.cos(hc.orbit_angle) * r
        ht.position[1] = pt.position[1] + math.sin(hc.orbit_angle) * r
        ht.position[2] = pt.position[2]
    }
}

_spawn_heart_entity :: proc(w: ^World, owner_id: int, max_hp: f32) -> int {
    id  := world_create_entity(w)
    pos : [3]f32
    if world_has_component(w, owner_id, .Transform) {
        pos    = comp_get(w, owner_id, .Transform, TransformComp).position
        pos[0] += HEART_CAGE_ORBIT_RADIUS
    }
    comp_set(w, id, .Transform, TransformComp{ position = pos })

    comp_set(w, id, .Collider, ColliderComp{ radius = 14, faction = 0 })

    comp_set(w, id, .Health, HealthComp{ current = max_hp, max = max_hp })
    return id
}

@(private = "file")
_mut_tick_black_lung :: proc(w: ^World, pid: int, eid: int, dt: f32) {
    if !world_has_component(w, eid, .MutBlackLung)  { return }
    if !world_has_component(w, pid, .Transform)      { return }

    bl  := comp_get(w, eid, .MutBlackLung, MutBlackLungComp)
    pos := comp_get(w, pid, .Transform, TransformComp).position

    bl.pressure = max(bl.pressure - bl.regen_rate * dt, 0)
    if bl.pressure <= 0 { return }

    dps := bl.dps_max * (bl.pressure / 100.0)
    r2  := bl.radius * bl.radius

    if is_player_entity(w, pid) {
        ai_ids := world_query(w, query_mask(.AIAgent, .Transform), context.temp_allocator)
        for ai_id in ai_ids {
            if world_has_component(w, ai_id, .Reanimated) { continue }
            ap := comp_get(w, ai_id, .Transform, TransformComp).position
            dx := ap[0] - pos[0]
            dy := ap[1] - pos[1]
            if dx*dx + dy*dy > r2 { continue }
            world_push_damage(w, ai_id, dps * dt, pid)
        }
    } else {
        for slot in 0..<MAX_PLAYERS {
            target_id := w.player_ids[slot]
            if !world_is_valid(w, target_id)                  { continue }
            if !world_has_component(w, target_id, .Transform) { continue }
            if world_has_component(w, target_id, .Respawn) &&
               comp_get(w, target_id, .Respawn, RespawnComp).timer > 0      { continue }
            tp := comp_get(w, target_id, .Transform, TransformComp).position
            dx := tp[0] - pos[0]
            dy := tp[1] - pos[1]
            if dx*dx + dy*dy > r2 { continue }
            world_push_damage(w, target_id, dps * dt, pid)
        }
    }
}

@(private = "file")
_mut_early_false_saint_beacon :: proc(w: ^World, pid: int, eid: int) {
    if !world_has_component(w, eid, .MutFalseSaint) { return }
    if !world_has_component(w, pid, .Transform)      { return }
    if !is_player_entity(w, pid)                        { return }

    fs  := comp_get(w, eid, .MutFalseSaint, MutFalseSaintComp)
    pos := comp_get(w, pid, .Transform, TransformComp).position
    r2  := fs.beacon_radius * fs.beacon_radius

    ai_ids := world_query(w, query_mask(.AIAgent, .Transform), context.temp_allocator)
    for ai_id in ai_ids {
        if world_has_component(w, ai_id, .Reanimated) { continue }
        ai := comp_get(w, ai_id, .AIAgent, AIAgentComp)
        if ai.state != 0 { continue }
        ap := comp_get(w, ai_id, .Transform, TransformComp).position
        dx := ap[0] - pos[0]
        dy := ap[1] - pos[1]
        if dx*dx + dy*dy > r2 { continue }
        ai.state     = 1
        ai.target_id = pid
    }
}

@(private = "file")
_mut_tick_false_saint_slow :: proc(w: ^World, pid: int, eid: int, dt: f32) {
    if !world_has_component(w, eid, .MutFalseSaint) { return }
    if !world_has_component(w, pid, .Transform)      { return }
    if !is_player_entity(w, pid)                        { return }

    fs  := comp_get(w, eid, .MutFalseSaint, MutFalseSaintComp)
    pos := comp_get(w, pid, .Transform, TransformComp).position
    r2  := fs.aura_radius * fs.aura_radius

    ai_ids := world_query(w, query_mask(.AIAgent, .Transform, .Velocity), context.temp_allocator)
    for ai_id in ai_ids {
        if world_has_component(w, ai_id, .Reanimated) { continue }
        ap := comp_get(w, ai_id, .Transform, TransformComp).position
        dx := ap[0] - pos[0]
        dy := ap[1] - pos[1]
        if dx*dx + dy*dy > r2 { continue }
        v := comp_get(w, ai_id, .Velocity, VelocityComp)
        v.value[0] *= fs.slow_mult
        v.value[1] *= fs.slow_mult
    }
}

_reanimate_enemy :: proc(w: ^World, enemy_id: int, owner_id: int) {
    if world_has_component(w, enemy_id, .Health) {
        h := comp_get(w, enemy_id, .Health, HealthComp)
        h.current = h.max * 0.4
    }
    if world_has_component(w, enemy_id, .Collider) {
        comp_get(w, enemy_id, .Collider, ColliderComp).faction = 0
    }
    comp_set(w, enemy_id, .Reanimated, ReanimatedComp{ owner_id = owner_id })
    if world_has_component(w, enemy_id, .AIAgent) {
        ai := comp_get(w, enemy_id, .AIAgent, AIAgentComp)
        ai.state     = 0
        ai.target_id = INVALID_ENTITY
    }
}

reanimated_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    ids := world_query(w, query_mask(.Reanimated, .AIAgent), context.temp_allocator)
    for sid in ids {
        _tick_reanimated_servant(w, sid)
    }

    cc_owners := world_query(w, query_mask(.MutationContainer), context.temp_allocator)
    for pid in cc_owners {
        mc := comp_get(w, pid, .MutationContainer, MutationContainerComp)
        for i in 0..<mc.entity_count {
            meid := mc.entities[i]
            if !world_is_valid(w, meid)                          { continue }
            if !world_has_component(w, meid, .MutCarrionCrown)   { continue }
            cc := comp_get(w, meid, .MutCarrionCrown, MutCarrionCrownComp)
            for si in 0..<CARRION_MAX_SERVANTS {
                if cc.servant_ids[si] == INVALID_ENTITY { continue }
                if !world_is_valid(w, cc.servant_ids[si]) {
                    cc.servant_ids[si] = INVALID_ENTITY
                }
            }
        }
    }
}

@(private = "file")
_tick_reanimated_servant :: proc(w: ^World, sid: int) {
    if !world_has_component(w, sid, .AIAgent)    { return }
    if !world_has_component(w, sid, .Transform)  { return }

    ai := comp_get(w, sid, .AIAgent, AIAgentComp)

    if world_is_valid(w, ai.target_id) &&
       world_has_component(w, ai.target_id, .AIAgent) &&
       !world_has_component(w, ai.target_id, .Reanimated) {
        ai.state = 1
        return
    }

    best_id   := INVALID_ENTITY
    best_dist := f32(1e30)
    sp := comp_get(w, sid, .Transform, TransformComp).position

    candidates := world_query(w, query_mask(.AIAgent, .Transform), context.temp_allocator)
    for cid in candidates {
        if cid == sid                                         { continue }
        if world_has_component(w, cid, .Reanimated)       { continue }
        cp := comp_get(w, cid, .Transform, TransformComp).position
        dx := cp[0] - sp[0]
        dy := cp[1] - sp[1]
        d2 := dx*dx + dy*dy
        if d2 < best_dist {
            best_dist = d2
            best_id   = cid
        }
    }

    if best_id != INVALID_ENTITY {
        ai.target_id = best_id
        ai.state     = 1
    } else {
        ai.state = 0
    }
}

@(private = "file")
_mut_tick_corpse_trigger :: proc(w: ^World, dt: f32) {
    ct_radius := f32(0)
    ct_dps    := f32(0)
    ct_pid    := INVALID_ENTITY

    for slot in 0..<MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !world_is_valid(w, pid)                          { continue }
        if !world_has_component(w, pid, .MutationContainer) { continue }
        mc := comp_get(w, pid, .MutationContainer, MutationContainerComp)
        for i in 0..<mc.entity_count {
            eid := mc.entities[i]
            if !world_is_valid(w, eid)                         { continue }
            if !world_has_component(w, eid, .MutCorpseTrigger) { continue }
            ct        := comp_get(w, eid, .MutCorpseTrigger, MutCorpseTriggerComp)
            ct_radius  = ct.radius
            ct_dps     = ct.dps
            ct_pid     = pid
            break
        }
        if ct_pid != INVALID_ENTITY { break }
    }
    if ct_pid == INVALID_ENTITY { return }

    r2 := ct_radius * ct_radius

    corpse_ids := world_query(w, query_mask(.AIAgent, .Transform, .Health), context.temp_allocator)

    for i in 0..<len(corpse_ids) {
        ai_a := corpse_ids[i]
        ha   := comp_get(w, ai_a, .Health, HealthComp)
        if ha.current > 1 { continue }
        pa := comp_get(w, ai_a, .Transform, TransformComp).position

        for j in i+1..<len(corpse_ids) {
            ai_b := corpse_ids[j]
            hb   := comp_get(w, ai_b, .Health, HealthComp)
            if hb.current > 1 { continue }
            pb := comp_get(w, ai_b, .Transform, TransformComp).position

            dx := pa[0] - pb[0]
            dy := pa[1] - pb[1]
            if dx*dx + dy*dy > r2 { continue }

            dmg := ct_dps * dt
            world_push_damage(w, ai_a, dmg, ct_pid)
            world_push_damage(w, ai_b, dmg, ct_pid)
        }
    }
}
