package main

import "core:math"
import cw "clockwork"

mutation_effects_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    #partial switch event {
    case .EarlyUpdate:

        mut_owners := cw.world_query(w, cw.query_mask(.MutationContainer), context.temp_allocator)
        for pid in mut_owners {
            mc := cw.world_get_mutation(w, pid)
            for i in 0..<mc.entity_count {
                eid := mc.entities[i]
                if !cw.world_is_valid(w, eid) { continue }
                _mut_early_false_saint_beacon(w, pid, eid)
            }
        }

    case .Update:
        mut_owners := cw.world_query(w, cw.query_mask(.MutationContainer), context.temp_allocator)
        for pid in mut_owners {
            mc := cw.world_get_mutation(w, pid)
            for i in 0..<mc.entity_count {
                eid := mc.entities[i]
                if !cw.world_is_valid(w, eid) { continue }

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
_mut_tick_proximity_damage :: proc(w: ^cw.World, pid: int, eid: int, dt: f32) {
    if !cw.world_has_component(w, eid, .MutProximityDamage)  { return }
    if !cw.world_has_component(w, pid, .Transform)           { return }

    pd  := cw.world_get_mut_proximity_damage(w, eid)^

    pos := cw.world_get_transform(w, pid).position
    r2  := pd.radius * pd.radius

    if is_player_entity(w, pid) {
        ai_ids := cw.world_query(w, cw.query_mask(.AIAgent, .Transform), context.temp_allocator)
        for ai_id in ai_ids {
            if cw.world_has_component(w, ai_id, .Reanimated) { continue }
            ap := cw.world_get_transform(w, ai_id).position
            dx := ap[0] - pos[0]
            dy := ap[1] - pos[1]
            if dx*dx + dy*dy > r2 { continue }

            if pd.dps > 0 {
                cw.world_push_damage(w, ai_id, pd.dps * dt, pid)
            }
            if pd.effect_strength > 0 {
                cw.status_effect_apply(w, ai_id, cw.StatusEffect{
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
        for slot in 0..<cw.MAX_PLAYERS {
            target_id := w.player_ids[slot]
            if !cw.world_is_valid(w, target_id)                  { continue }
            if !cw.world_has_component(w, target_id, .Transform) { continue }
            if cw.world_has_component(w, target_id, .Respawn) &&
               cw.world_get_respawn(w, target_id).timer > 0      { continue }
            tp := cw.world_get_transform(w, target_id).position
            dx := tp[0] - pos[0]
            dy := tp[1] - pos[1]
            if dx*dx + dy*dy > r2 { continue }
            if pd.dps > 0 {
                cw.world_push_damage(w, target_id, pd.dps * dt, pid)
            }
        }
    }

    if pd.light_radius > 0 {
        lc := cw.PointLightComp{
            color     = pd.light_color,
            radius    = pd.light_radius,
            intensity = pd.light_intensity,
        }
        if !cw.world_has_component(w, pid, .PointLight) {
            cw.world_set_point_light(w, pid, lc)
        } else {
            cw.world_get_point_light(w, pid)^ = lc
        }
    }
}

@(private = "file")
_mut_tick_stationary_shield :: proc(w: ^cw.World, pid: int, eid: int, dt: f32) {
    if !cw.world_has_component(w, eid, .MutStationaryShield) { return }

    ss := cw.world_get_mut_stationary_shield(w, eid)

    slot := -1
    if cw.world_has_component(w, pid, .Player) {
        slot = cw.world_get_player(w, pid).slot
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
_mut_tick_body_melee :: proc(w: ^cw.World, pid: int, eid: int, dt: f32) {
    if !cw.world_has_component(w, eid, .MutBodyMelee) { return }
    if !cw.world_has_component(w, pid, .InputState)   { return }
    if !cw.world_has_component(w, pid, .Transform)    { return }

    bm    := cw.world_get_mut_body_melee(w, eid)
    input := cw.world_get_input(w, pid)
    t     := cw.world_get_transform(w, pid)

    if bm.timer > 0 {
        bm.timer = max(0, bm.timer - dt)
    }

    if input.fire_pressed && bm.timer <= 0 {
        damage := bm.damage
        if cw.world_has_component(w, pid, .Stats) {
            damage *= cw.world_get_stats(w, pid).damage_mult
        }

        arc_id := cw.world_create_entity(w)
        cw.world_set_transform(w, arc_id, t^)
        cw.world_set_melee_arc(w, arc_id, cw.MeleeArcComp{
            angle         = t.rotation,
            arc_spread    = bm.arc_angle,
            radius        = bm.range,
            damage        = damage,
            owner_id      = pid,
            owner_faction = 0,
            lifetime      = 0.12,
        })
        cw.world_set_self_destruct(w, arc_id, cw.SelfDestructComp{ timer = 0.12 })
        bm.timer = bm.cooldown_max
        if pid == w.player_id { play_sfx("melee_swing") }
    }
}

@(private = "file")
_mut_tick_on_death_explode :: proc(w: ^cw.World, eid: int, dt: f32) {
    if !cw.world_has_component(w, eid, .MutOnDeathExplode) { return }
    ode := cw.world_get_mut_on_death_explode(w, eid)
    if ode.timer > 0 {
        ode.timer = max(0, ode.timer - dt)
    }
}

@(private = "file")
_mut_tick_extra_dodge_charges :: proc(w: ^cw.World, eid: int, dt: f32) {
    if !cw.world_has_component(w, eid, .MutExtraDodgeCharges) { return }
    edc := cw.world_get_mut_extra_dodge_charges(w, eid)
    if edc.charges >= edc.count { return }
    edc.recharge_timer += dt
    if edc.recharge_timer >= edc.recharge_max {
        edc.recharge_timer = 0
        edc.charges        = min(edc.charges + 1, edc.count)
    }
}


@(private = "file")
_mut_tick_heart_cage :: proc(w: ^cw.World, pid: int, eid: int, dt: f32) {
    if !cw.world_has_component(w, eid, .MutHeartCage) { return }
    hc := cw.world_get_mut_heart_cage(w, eid)
    if hc.heart_id == cw.INVALID_ENTITY { return }


    hc.orbit_angle += cw.HEART_CAGE_ORBIT_SPEED * dt


    if !cw.world_is_valid(w, hc.heart_id)                        { return }
    if !cw.world_has_component(w, hc.heart_id, .Health)          { return }
    if cw.world_get_health(w, hc.heart_id).current <= 0          { return }


    if cw.world_is_valid(w, hc.heart_id) &&
       cw.world_has_component(w, pid, .Transform) {
        pt := cw.world_get_transform(w, pid)
        ht := cw.world_get_transform(w, hc.heart_id)
        r  := cw.HEART_CAGE_ORBIT_RADIUS
        ht.position[0] = pt.position[0] + math.cos(hc.orbit_angle) * r
        ht.position[1] = pt.position[1] + math.sin(hc.orbit_angle) * r
        ht.position[2] = pt.position[2]
    }
}

_spawn_heart_entity :: proc(w: ^cw.World, owner_id: int, max_hp: f32) -> int {
    id  := cw.world_create_entity(w)
    pos : [3]f32
    if cw.world_has_component(w, owner_id, .Transform) {
        pos    = cw.world_get_transform(w, owner_id).position
        pos[0] += cw.HEART_CAGE_ORBIT_RADIUS
    }
    cw.world_set_transform(w, id, cw.TransformComp{ position = pos })


    cw.world_set_collider(w, id, cw.ColliderComp{ radius = 14, faction = 0 })

    cw.world_set_health(w, id, cw.HealthComp{ current = max_hp, max = max_hp })
    return id
}

@(private = "file")
_mut_tick_black_lung :: proc(w: ^cw.World, pid: int, eid: int, dt: f32) {
    if !cw.world_has_component(w, eid, .MutBlackLung)  { return }
    if !cw.world_has_component(w, pid, .Transform)      { return }

    bl  := cw.world_get_mut_black_lung(w, eid)
    pos := cw.world_get_transform(w, pid).position

    bl.pressure = max(bl.pressure - bl.regen_rate * dt, 0)
    if bl.pressure <= 0 { return }

    dps := bl.dps_max * (bl.pressure / 100.0)
    r2  := bl.radius * bl.radius

    if is_player_entity(w, pid) {
        ai_ids := cw.world_query(w, cw.query_mask(.AIAgent, .Transform), context.temp_allocator)
        for ai_id in ai_ids {
            if cw.world_has_component(w, ai_id, .Reanimated) { continue }
            ap := cw.world_get_transform(w, ai_id).position
            dx := ap[0] - pos[0]
            dy := ap[1] - pos[1]
            if dx*dx + dy*dy > r2 { continue }
            cw.world_push_damage(w, ai_id, dps * dt, pid)
        }
    } else {
        for slot in 0..<cw.MAX_PLAYERS {
            target_id := w.player_ids[slot]
            if !cw.world_is_valid(w, target_id)                  { continue }
            if !cw.world_has_component(w, target_id, .Transform) { continue }
            if cw.world_has_component(w, target_id, .Respawn) &&
               cw.world_get_respawn(w, target_id).timer > 0      { continue }
            tp := cw.world_get_transform(w, target_id).position
            dx := tp[0] - pos[0]
            dy := tp[1] - pos[1]
            if dx*dx + dy*dy > r2 { continue }
            cw.world_push_damage(w, target_id, dps * dt, pid)
        }
    }
}


@(private = "file")
_mut_early_false_saint_beacon :: proc(w: ^cw.World, pid: int, eid: int) {
    if !cw.world_has_component(w, eid, .MutFalseSaint) { return }
    if !cw.world_has_component(w, pid, .Transform)      { return }
    if !is_player_entity(w, pid)                        { return }

    fs  := cw.world_get_mut_false_saint(w, eid)
    pos := cw.world_get_transform(w, pid).position
    r2  := fs.beacon_radius * fs.beacon_radius

    ai_ids := cw.world_query(w, cw.query_mask(.AIAgent, .Transform), context.temp_allocator)
    for ai_id in ai_ids {
        if cw.world_has_component(w, ai_id, .Reanimated) { continue }
        ai := cw.world_get_ai(w, ai_id)
        if ai.state != 0 { continue }
        ap := cw.world_get_transform(w, ai_id).position
        dx := ap[0] - pos[0]
        dy := ap[1] - pos[1]
        if dx*dx + dy*dy > r2 { continue }
        ai.state     = 1
        ai.target_id = pid
    }
}

@(private = "file")
_mut_tick_false_saint_slow :: proc(w: ^cw.World, pid: int, eid: int, dt: f32) {
    if !cw.world_has_component(w, eid, .MutFalseSaint) { return }
    if !cw.world_has_component(w, pid, .Transform)      { return }
    if !is_player_entity(w, pid)                        { return }

    fs  := cw.world_get_mut_false_saint(w, eid)
    pos := cw.world_get_transform(w, pid).position
    r2  := fs.aura_radius * fs.aura_radius

    ai_ids := cw.world_query(w, cw.query_mask(.AIAgent, .Transform, .Velocity), context.temp_allocator)
    for ai_id in ai_ids {
        if cw.world_has_component(w, ai_id, .Reanimated) { continue }
        ap := cw.world_get_transform(w, ai_id).position
        dx := ap[0] - pos[0]
        dy := ap[1] - pos[1]
        if dx*dx + dy*dy > r2 { continue }
        v := cw.world_get_velocity(w, ai_id)
        v.value[0] *= fs.slow_mult
        v.value[1] *= fs.slow_mult
    }
}

_reanimate_enemy :: proc(w: ^cw.World, enemy_id: int, owner_id: int) {
    if cw.world_has_component(w, enemy_id, .Health) {
        h := cw.world_get_health(w, enemy_id)
        h.current = h.max * 0.4
    }
    if cw.world_has_component(w, enemy_id, .Collider) {
        cw.world_get_collider(w, enemy_id).faction = 0
    }
    cw.world_set_reanimated(w, enemy_id, cw.ReanimatedComp{ owner_id = owner_id })
    if cw.world_has_component(w, enemy_id, .AIAgent) {
        ai := cw.world_get_ai(w, enemy_id)
        ai.state     = 0
        ai.target_id = cw.INVALID_ENTITY
    }
}

reanimated_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }

    ids := cw.world_query(w, cw.query_mask(.Reanimated, .AIAgent), context.temp_allocator)
    for sid in ids {
        _tick_reanimated_servant(w, sid)
    }

    cc_owners := cw.world_query(w, cw.query_mask(.MutationContainer), context.temp_allocator)
    for pid in cc_owners {
        mc := cw.world_get_mutation(w, pid)
        for i in 0..<mc.entity_count {
            meid := mc.entities[i]
            if !cw.world_is_valid(w, meid)                          { continue }
            if !cw.world_has_component(w, meid, .MutCarrionCrown)   { continue }
            cc := cw.world_get_mut_carrion_crown(w, meid)
            for si in 0..<cw.CARRION_MAX_SERVANTS {
                if cc.servant_ids[si] == cw.INVALID_ENTITY { continue }
                if !cw.world_is_valid(w, cc.servant_ids[si]) {
                    cc.servant_ids[si] = cw.INVALID_ENTITY
                }
            }
        }
    }
}

@(private = "file")
_tick_reanimated_servant :: proc(w: ^cw.World, sid: int) {
    if !cw.world_has_component(w, sid, .AIAgent)    { return }
    if !cw.world_has_component(w, sid, .Transform)  { return }

    ai := cw.world_get_ai(w, sid)

    if cw.world_is_valid(w, ai.target_id) &&
       cw.world_has_component(w, ai.target_id, .AIAgent) &&
       !cw.world_has_component(w, ai.target_id, .Reanimated) {
        ai.state = 1
        return
    }

    best_id   := cw.INVALID_ENTITY
    best_dist := f32(1e30)
    sp := cw.world_get_transform(w, sid).position

    candidates := cw.world_query(w, cw.query_mask(.AIAgent, .Transform), context.temp_allocator)
    for cid in candidates {
        if cid == sid                                         { continue }
        if cw.world_has_component(w, cid, .Reanimated)       { continue }
        cp := cw.world_get_transform(w, cid).position
        dx := cp[0] - sp[0]
        dy := cp[1] - sp[1]
        d2 := dx*dx + dy*dy
        if d2 < best_dist {
            best_dist = d2
            best_id   = cid
        }
    }

    if best_id != cw.INVALID_ENTITY {
        ai.target_id = best_id
        ai.state     = 1
    } else {
        ai.state = 0
    }
}

@(private = "file")
_mut_tick_corpse_trigger :: proc(w: ^cw.World, dt: f32) {
    ct_radius := f32(0)
    ct_dps    := f32(0)
    ct_pid    := cw.INVALID_ENTITY

    for slot in 0..<cw.MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !cw.world_is_valid(w, pid)                          { continue }
        if !cw.world_has_component(w, pid, .MutationContainer) { continue }
        mc := cw.world_get_mutation(w, pid)
        for i in 0..<mc.entity_count {
            eid := mc.entities[i]
            if !cw.world_is_valid(w, eid)                         { continue }
            if !cw.world_has_component(w, eid, .MutCorpseTrigger) { continue }
            ct        := cw.world_get_mut_corpse_trigger(w, eid)
            ct_radius  = ct.radius
            ct_dps     = ct.dps
            ct_pid     = pid
            break
        }
        if ct_pid != cw.INVALID_ENTITY { break }
    }
    if ct_pid == cw.INVALID_ENTITY { return }

    r2 := ct_radius * ct_radius

    corpse_ids := cw.world_query(w, cw.query_mask(.AIAgent, .Transform, .Health), context.temp_allocator)

    for i in 0..<len(corpse_ids) {
        ai_a := corpse_ids[i]
        ha   := cw.world_get_health(w, ai_a)
        if ha.current > 1 { continue }
        pa := cw.world_get_transform(w, ai_a).position

        for j in i+1..<len(corpse_ids) {
            ai_b := corpse_ids[j]
            hb   := cw.world_get_health(w, ai_b)
            if hb.current > 1 { continue }
            pb := cw.world_get_transform(w, ai_b).position

            dx := pa[0] - pb[0]
            dy := pa[1] - pb[1]
            if dx*dx + dy*dy > r2 { continue }

            dmg := ct_dps * dt
            cw.world_push_damage(w, ai_a, dmg, ct_pid)
            cw.world_push_damage(w, ai_b, dmg, ct_pid)
        }
    }
}
