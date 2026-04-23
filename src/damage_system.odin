package main

import "core:math/rand"
import cw "clockwork"

@(private = "file")
DropPending :: struct { pos: [3]f32, seed: u64, entity_id: int }

RESPAWN_DELAY      :: f32(2.0)
XP_PER_KILL        :: f32(20)
LEVELUP_FLASH_TIME :: f32(2.5)

damage_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .LateUpdate { return }

    pending_drops := make([dynamic]DropPending, context.temp_allocator)

    for ev in w.damage_events {
        if !cw.world_is_valid(w, ev.target_id)               { continue }
        if !cw.world_has_component(w, ev.target_id, .Health) { continue }

        h := cw.world_get_health(w, ev.target_id)
        amount := ev.amount

        if ev.amount > 0 &&
           cw.world_has_component(w, ev.target_id, .Stats) {
            amount *= (1.0 - cw.world_get_stats(w, ev.target_id).armor)
        }

        if amount > 0 && ev.source_id != 0 &&
           cw.world_has_component(w, ev.source_id, .MutationContainer) &&
           cw.world_has_component(w, ev.target_id, .AIAgent) {
            src_mc := cw.world_get_mutation(w, ev.source_id)
            for mi in 0..<src_mc.entity_count {
                meid := src_mc.entities[mi]
                if !cw.world_is_valid(w, meid) { continue }
                if cw.world_has_component(w, meid, .MutUnseenDamageMult) {
                    udm := cw.world_get_mut_unseen_damage_mult(w, meid)
                    if cw.world_has_component(w, ev.source_id, .Transform) &&
                       cw.world_has_component(w, ev.target_id, .Transform) {
                        pp := cw.world_get_transform(w, ev.source_id).position
                        ep := cw.world_get_transform(w, ev.target_id).position
                        dx := ep[0] - pp[0]
                        dy := ep[1] - pp[1]
                        dist_sq := dx*dx + dy*dy
                        vr := udm.vision_radius
                        if vr <= 0 || dist_sq > vr*vr {
                            amount *= udm.mult
                        }
                    }
                }
            }
        }

        if amount > 0 && cw.world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := cw.world_get_mutation(w, ev.target_id)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !cw.world_is_valid(w, meid)                          { continue }
                if !cw.world_has_component(w, meid, .MutDamageTakenMult) { continue }
                amount *= cw.world_get_mut_damage_taken_mult(w, meid).mult
                break
            }
        }

        // HeartCage: redirect incoming damage to the external heart's HP pool
        // (before the stationary shield so both can partially absorb a hit)
        if amount > 0 && cw.world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := cw.world_get_mutation(w, ev.target_id)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !cw.world_is_valid(w, meid)                     { continue }
                if !cw.world_has_component(w, meid, .MutHeartCage) { continue }
                hc := cw.world_get_mut_heart_cage(w, meid)
                if hc.heart_hp > 0 {
                    absorbed    := min(hc.heart_hp, amount)
                    hc.heart_hp -= absorbed
                    amount      -= absorbed
                }
                break
            }
        }

        if amount > 0 && cw.world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := cw.world_get_mutation(w, ev.target_id)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !cw.world_is_valid(w, meid)                         { continue }
                if !cw.world_has_component(w, meid, .MutStationaryShield) { continue }
                ss := cw.world_get_mut_stationary_shield(w, meid)
                if ss.shield > 0 {
                    absorbed := min(ss.shield, amount)
                    ss.shield -= absorbed
                    amount    -= absorbed
                }
                break
            }
        }
        
        is_crit := false
        if amount > 0 && cw.world_has_component(w, ev.target_id, .AIAgent) {
            best_crit := f32(0.05)
            for slot in 0..<cw.MAX_PLAYERS {
                pid := w.player_ids[slot]
                if !cw.world_is_valid(w, pid) { continue }
                if !cw.world_has_component(w, pid, .Stats) { continue }
                c := cw.world_get_stats(w, pid).crit_chance
                if c > best_crit { best_crit = c }
            }

            crit_state               := rand.create(loot_seed(w.tick, ev.target_id) ~ 0xdeadbeef_cafebabe)
            context.random_generator  = rand.default_random_generator(&crit_state)
            if rand.float32() < best_crit {
                is_crit = true
                amount *= 2.0
                if ev.source_id == w.player_id {
                    camera_shake(2)
                }
            }

            push_hit_flash(ev.target_id)
            if ev.source_id == w.player_id {
                camera_shake(1)
            }
        }

        // BloodFrenzy
        if amount < 0 &&
           cw.world_has_component(w, ev.target_id, .Stats) &&
           cw.world_get_stats(w, ev.target_id).healing_blocked {
            amount = 0
        }

        // ParasiteKing
        if amount < 0 && ev.source_id == 0 &&
           cw.world_has_component(w, ev.target_id, .Stats) &&
           cw.world_get_stats(w, ev.target_id).pickup_healing_blocked {
            amount = 0
        }

        // ThornPact: halve all healing received
        if amount < 0 && cw.world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := cw.world_get_mutation(w, ev.target_id)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !cw.world_is_valid(w, meid)                     { continue }
                if !cw.world_has_component(w, meid, .MutThornPact) { continue }
                tp     := cw.world_get_mut_thorn_pact(w, meid)
                amount *= tp.slow_heal_mult
                break
            }
        }

        // DeadmansTrigger
        force_death := false
        if amount > 0 && cw.world_has_component(w, ev.target_id, .Stats) {
            threshold := h.max * cw.world_get_stats(w, ev.target_id).deadman_early_death_pct
            if h.current - amount < threshold {
                h.current  = 0
                force_death = true
            }
        }

        // CorpseTide
        if !force_death && amount > 0 && cw.world_has_component(w, ev.target_id, .AIAgent) {
            if ev.source_id != 0 &&
               cw.world_has_component(w, ev.source_id, .Stats) &&
               cw.world_get_stats(w, ev.source_id).nonlethal_shots {
                if h.current - amount <= 0 {
                    h.current = 1
                    continue
                }
            }
        }

        // ThornPact: reflect a portion of the final damage back to the attacker
        if amount > 0 && ev.source_id != 0 &&
           cw.world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := cw.world_get_mutation(w, ev.target_id)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !cw.world_is_valid(w, meid)                     { continue }
                if !cw.world_has_component(w, meid, .MutThornPact) { continue }
                tp := cw.world_get_mut_thorn_pact(w, meid)
                cw.world_push_damage(w, ev.source_id, amount * tp.reflect_pct, ev.target_id)
                break
            }
        }

        // BlackLung: each incoming hit builds pressure
        if amount > 0 && cw.world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := cw.world_get_mutation(w, ev.target_id)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !cw.world_is_valid(w, meid)                     { continue }
                if !cw.world_has_component(w, meid, .MutBlackLung) { continue }
                bl := cw.world_get_mut_black_lung(w, meid)
                bl.pressure = min(bl.pressure + bl.gain_per_hit, 100)
                break
            }
        }

        if !force_death {
            h.current = clamp(h.current - amount, 0, h.max)
        }

        // GlassCannon
        if cw.world_has_component(w, ev.target_id, .Stats) &&
           cw.world_get_stats(w, ev.target_id).hp_locked_to_one {
            if h.current > 1 { h.current = 1 }
        }

        if amount > 0 && ev.source_id != 0 &&
           cw.world_has_component(w, ev.source_id, .MutationContainer) &&
           cw.world_has_component(w, ev.target_id, .AIAgent) {
            src_mc := cw.world_get_mutation(w, ev.source_id)
            for mi in 0..<src_mc.entity_count {
                meid := src_mc.entities[mi]
                if !cw.world_is_valid(w, meid)                 { continue }
                if !cw.world_has_component(w, meid, .MutLifesteal) { continue }
                ls := cw.world_get_mut_lifesteal(w, meid)
                cw.world_push_heal(w, ev.source_id, ls.hp_per_hit)
                break
            }
        }

        if amount > 0 && cw.world_has_component(w, ev.target_id, .Transform) {
            pos := cw.world_get_transform(w, ev.target_id).position
            push_dmg_number(pos[0], pos[1], amount, ev.target_id != w.player_id, is_crit)
        }

        if h.current > 0 && !force_death {
            if ev.target_id == w.player_id && amount > 0 {
                play_sfx("player_hurt")
                camera_shake(1)  
            }
            continue
        }

        bomb_triggered := false
        if cw.world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := cw.world_get_mutation(w, ev.target_id)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !cw.world_is_valid(w, meid)                         { continue }
                if !cw.world_has_component(w, meid, .MutOnDeathExplode) { continue }
                ode := cw.world_get_mut_on_death_explode(w, meid)
                if ode.timer > 0                                        { continue }
                tgt_h := cw.world_get_health(w, ev.target_id)
                exp_dmg := tgt_h.max * ode.damage_pct
                if cw.world_has_component(w, ev.target_id, .Transform) {
                    epos := cw.world_get_transform(w, ev.target_id).position
                    r2   := ode.radius * ode.radius
                    ai_ids := cw.world_query(w, cw.query_mask(.AIAgent, .Transform), context.temp_allocator)
                    for ai_id in ai_ids {
                        ap  := cw.world_get_transform(w, ai_id).position
                        dx  := ap[0] - epos[0]
                        dy  := ap[1] - epos[1]
                        if dx*dx + dy*dy <= r2 {
                            cw.world_push_damage(w, ai_id, exp_dmg, ev.target_id)
                        }
                    }
                    if ev.target_id == w.player_id { camera_shake(5) }
                }
                tgt_h.current = 1
                ode.timer     = ode.cooldown_max
                bomb_triggered = true
                break
            }
        }

        if !bomb_triggered && cw.world_has_component(w, ev.target_id, .Respawn) {
            rsp := cw.world_get_respawn(w, ev.target_id)
            if rsp.timer <= 0 {
                rsp.timer = rsp.delay
                play_sfx("player_death")
            }
        } else if !bomb_triggered {
            // Reanimated servants die silently — no XP/loot, just destroy.
            if cw.world_has_component(w, ev.target_id, .Reanimated) {
                cw.world_tag_destroy(w, ev.target_id)
                continue
            }

            was_reanimated := false
            if cw.world_has_component(w, ev.target_id, .AIAgent) {
                g_lifetime_stats.enemies_killed += 1

                // CarrionCrown: 30 % chance to reanimate instead of dying
                for pslot in 0..<cw.MAX_PLAYERS {
                    ppid := w.player_ids[pslot]
                    if !cw.world_is_valid(w, ppid)                          { continue }
                    if !cw.world_has_component(w, ppid, .MutationContainer) { continue }
                    cc_mc := cw.world_get_mutation(w, ppid)
                    for mi in 0..<cc_mc.entity_count {
                        meid := cc_mc.entities[mi]
                        if !cw.world_is_valid(w, meid)                        { continue }
                        if !cw.world_has_component(w, meid, .MutCarrionCrown) { continue }
                        cc := cw.world_get_mut_carrion_crown(w, meid)
                        living := 0
                        for si in 0..<cw.CARRION_MAX_SERVANTS {
                            if cw.world_is_valid(w, cc.servant_ids[si]) { living += 1 }
                        }
                        if living < cw.CARRION_MAX_SERVANTS {
                            rng := rand.create(loot_seed(w.tick, ev.target_id) ~ 0xfeedface_cafebabe)
                            context.random_generator = rand.default_random_generator(&rng)
                            if rand.float32() < 0.30 {
                                _reanimate_enemy(w, ev.target_id, ppid)
                                for si in 0..<cw.CARRION_MAX_SERVANTS {
                                    if !cw.world_is_valid(w, cc.servant_ids[si]) {
                                        cc.servant_ids[si] = ev.target_id
                                        break
                                    }
                                }
                                was_reanimated = true
                            }
                        }
                        break
                    }
                    if was_reanimated { break }
                }

                death_pos: [3]f32
                if cw.world_has_component(w, ev.target_id, .Transform) {
                    death_pos = cw.world_get_transform(w, ev.target_id).position
                    if !was_reanimated {
                        append(&pending_drops, DropPending{
                            pos       = death_pos,
                            seed      = loot_seed(w.tick, ev.target_id),
                            entity_id = ev.target_id,
                        })
                    }
                }

                for pslot in 0..<cw.MAX_PLAYERS {
                    ppid := w.player_ids[pslot]
                    if !cw.world_is_valid(w, ppid)                          { continue }
                    if !cw.world_has_component(w, ppid, .MutationContainer) { continue }
                    kh_mc := cw.world_get_mutation(w, ppid)
                    for mi in 0..<kh_mc.entity_count {
                        meid := kh_mc.entities[mi]
                        if !cw.world_is_valid(w, meid)                  { continue }
                        if !cw.world_has_component(w, meid, .MutKillHeal) { continue }
                        kh := cw.world_get_mut_kill_heal(w, meid)
                        if cw.world_has_component(w, ppid, .Health) {
                            ph := cw.world_get_health(w, ppid)
                            cw.world_push_heal(w, ppid, ph.max * kh.heal_pct)
                        }
                        break
                    }
                }

                for slot in 0..<cw.MAX_PLAYERS {
                    pid := w.player_ids[slot]
                    if !cw.world_is_valid(w, pid) { continue }
                    if !cw.world_has_component(w, pid, .Stats) { continue }

                    st := cw.world_get_stats(w, pid)
                    st.xp += XP_PER_KILL
                    leveled := false
                    for st.xp >= st.xp_next {
                        st.xp          -= st.xp_next
                        st.level       += 1
                        st.stat_points += 1
                        st.xp_next      = f32(st.level) * 100.0
                        leveled          = true
                    }
                    if leveled {
                        if pid == w.player_id {
                            g_levelup_flash = LEVELUP_FLASH_TIME
                            play_sfx("levelup")
                        }
                        // TODO: ability points replaced by item system
                    }
                }

                play_sfx_at("enemy_death", death_pos)
            }
            if ev.target_id == g_boss_id {
                g_boss_id = cw.INVALID_ENTITY
            }
            if !was_reanimated {
                cw.world_tag_destroy(w, ev.target_id)
            }
        }
    }
    cw.world_clear_damage_events(w)

    for d in pending_drops {
        spawn_loot_drop(w, d.pos, d.seed)
        gold_amt := gold_drop_amount(w.tick, d.entity_id)
        gold_pos := [3]f32{ d.pos[0] + 16, d.pos[1] - 8, 0 }
        spawn_gold_drop(w, gold_pos, gold_amt)
    }

    rsp_ids := cw.world_query(w, cw.query_mask(.Respawn))
    defer delete(rsp_ids)

    for id in rsp_ids {
        rsp := cw.world_get_respawn(w, id)
        if rsp.timer <= 0 { continue }

        rsp.timer -= dt
        if rsp.timer > 0 { continue }

        rsp.timer = 0
        if id == w.player_id { play_sfx("player_respawn") }

        if cw.world_has_component(w, id, .Health) {
            h := cw.world_get_health(w, id)
            h.current            = h.max
            h.iron_will_consumed = false  
        }
        if cw.world_has_component(w, id, .Transform) {
            t := cw.world_get_transform(w, id)
            t.position = rsp.spawn_pos
            t.rotation = 0
        }
        if cw.world_has_component(w, id, .Velocity) {
            cw.world_get_velocity(w, id).value = {}
        }
    }
}
