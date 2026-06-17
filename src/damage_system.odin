package main

import "core:math/rand"
import cw "clockwork"

@(private = "file")
DropPending :: struct { pos: [3]f32, seed: u64, entity_id: int, was_boss: bool }

RESPAWN_DELAY      :: f32(2.0)
XP_PER_KILL        :: f32(20)
LEVELUP_FLASH_TIME :: f32(2.5)

damage_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .LateUpdate { return }

    pending_drops       := make([dynamic]DropPending, context.temp_allocator)
    heart_killed_player := false

    bomb_skip   : [32]int
    bomb_skip_n : int

    for ev in w.damage_events {
        {
            skip := false
            for i in 0..<bomb_skip_n { if bomb_skip[i] == ev.target_id { skip = true; break } }
            if skip { continue }
        }
        if !cw.world_is_valid(w, ev.target_id)               { continue }
        if !cw.world_has_component(w, ev.target_id, .Health) { continue }

        h := cw.world_get_health(w, ev.target_id)
        amount := ev.amount


        if ev.amount > 0 && ev.kind == .Physical &&
           cw.world_has_component(w, ev.target_id, .Stats) {
            amount *= (1.0 - cw.world_get_stats(w, ev.target_id).armor)
        }


        if ev.amount > 0 && cw.world_has_component(w, ev.target_id, .DamageAmp) {
            amount *= cw.world_get_damage_amp(w, ev.target_id).mult
        }


        if ev.amount > 0 && cw.world_has_component(w, ev.target_id, .Resistance) {
            res := cw.world_get_resistance(w, ev.target_id)
            resist := f32(0)
            #partial switch ev.kind {
            case .Physical:  resist = res.physical
            case .Necrotic:  resist = res.necrotic
            case .Fire:      resist = res.fire
            case .Galvanic:  resist = res.galvanic
            case .Poison:    resist = res.poison
            }
            if resist > 0 {
                amount *= (1.0 - clamp(resist, 0, 0.75))
            }
        }

        if amount > 0 && h.shield > 0 {
            absorbed  := min(h.shield, amount)
            h.shield  -= absorbed
            amount    -= absorbed
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

        if amount > 0 && cw.world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := cw.world_get_mutation(w, ev.target_id)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !cw.world_is_valid(w, meid)                     { continue }
                if !cw.world_has_component(w, meid, .MutHeartCage) { continue }
                hc := cw.world_get_mut_heart_cage(w, meid)

                if ev.source_id == ev.target_id { continue }
                if cw.world_is_valid(w, hc.heart_id) &&
                   cw.world_has_component(w, hc.heart_id, .Health) {
                    hh := cw.world_get_health(w, hc.heart_id)
                    if hh.current > 0 {
                        hh.current = max(0, hh.current - amount)
                        if hh.current <= 0 {
                            heart_killed_player = true
                        }
                    }
                }
                amount = 0
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

        if amount < 0 &&
           cw.world_has_component(w, ev.target_id, .Stats) &&
           cw.world_get_stats(w, ev.target_id).healing_blocked {
            amount = 0
        }

        if amount < 0 && ev.source_id == 0 &&
           cw.world_has_component(w, ev.target_id, .Stats) &&
           cw.world_get_stats(w, ev.target_id).pickup_healing_blocked {
            amount = 0
        }

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

        force_death := false
        if amount > 0 && cw.world_has_component(w, ev.target_id, .Stats) {
            threshold := h.max * cw.world_get_stats(w, ev.target_id).deadman_early_death_pct
            if h.current - amount < threshold {
                h.current  = 0
                force_death = true
            }
        }


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


        if g_god_mode && ev.target_id == w.player_id {
            if h.current <= 0 { h.current = 1 }
            force_death = false
        }


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
                    if is_player_entity(w, ev.target_id) {

                        ai_ids := cw.world_query(w, cw.query_mask(.AIAgent, .Transform), context.temp_allocator)
                        for ai_id in ai_ids {
                            ap  := cw.world_get_transform(w, ai_id).position
                            dx  := ap[0] - epos[0]
                            dy  := ap[1] - epos[1]
                            if dx*dx + dy*dy <= r2 {
                                cw.world_push_damage(w, ai_id, exp_dmg, ev.target_id)
                            }
                        }
                        camera_shake(5)
                        push_explosion(epos[0], epos[1], ode.radius, 255, 140, 30)
                    } else {

                        for pslot in 0..<cw.MAX_PLAYERS {
                            ppid := w.player_ids[pslot]
                            if !cw.world_is_valid(w, ppid)                  { continue }
                            if !cw.world_has_component(w, ppid, .Transform) { continue }
                            if cw.world_has_component(w, ppid, .Respawn) &&
                               cw.world_get_respawn(w, ppid).timer > 0      { continue }
                            pp  := cw.world_get_transform(w, ppid).position
                            dx  := pp[0] - epos[0]
                            dy  := pp[1] - epos[1]
                            if dx*dx + dy*dy <= r2 {
                                cw.world_push_damage(w, ppid, exp_dmg, ev.target_id)
                            }
                        }
                        push_explosion(epos[0], epos[1], ode.radius, 220, 60, 60)
                    }
                    play_sfx_at("explosion", epos)
                }
                tgt_h.current  = 1
                ode.timer      = ode.cooldown_max
                bomb_triggered = true
                break
            }
        }


        if bomb_triggered {
            bomb_skip[min(bomb_skip_n, len(bomb_skip) - 1)] = ev.target_id
            bomb_skip_n += 1
            continue
        }

        if !bomb_triggered && cw.world_has_component(w, ev.target_id, .Respawn) {
            rsp := cw.world_get_respawn(w, ev.target_id)
            if rsp.timer <= 0 {
                rsp.timer = rsp.delay
                play_sfx("player_death")
            }
        } else if !bomb_triggered {

            if cw.world_has_component(w, ev.target_id, .Reanimated) {
                cw.world_tag_destroy(w, ev.target_id)
                continue
            }


            is_heart := false
            heart_check: for pslot in 0..<cw.MAX_PLAYERS {
                ppid := w.player_ids[pslot]
                if !cw.world_is_valid(w, ppid)                          { continue }
                if !cw.world_has_component(w, ppid, .MutationContainer) { continue }
                ppmc := cw.world_get_mutation(w, ppid)
                for mi in 0..<ppmc.entity_count {
                    meid := ppmc.entities[mi]
                    if !cw.world_is_valid(w, meid)                     { continue }
                    if !cw.world_has_component(w, meid, .MutHeartCage) { continue }
                    if cw.world_get_mut_heart_cage(w, meid).heart_id == ev.target_id {
                        heart_killed_player = true
                        is_heart            = true
                    }
                    break heart_check
                }
            }
            if is_heart {
                cw.world_tag_destroy(w, ev.target_id)
                continue
            }

            was_reanimated := false
            if cw.world_has_component(w, ev.target_id, .AIAgent) {
                g_lifetime_stats.enemies_killed += 1
                ai := cw.world_get_ai(w, ev.target_id)
                if ai.tier == .Legendary {
                    g_lifetime_stats.elites_killed += 1
                }
                if ev.target_id == g_boss_id {
                    g_lifetime_stats.bosses_killed += 1
                }


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
                            was_boss  = ev.target_id == g_boss_id,
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
                    ppid := w.player_ids[slot]
                    if !cw.world_is_valid(w, ppid)                      { continue }
                    if !cw.world_has_component(w, ppid, .KillHeal)      { continue }
                    kh := cw.world_get_kill_heal(w, ppid)
                    if kh.timer < kh.duration &&
                       cw.world_has_component(w, ppid, .Health) {
                        if cw.world_has_component(w, ppid, .Stats) &&
                           cw.world_get_stats(w, ppid).healing_blocked { continue }
                        ph := cw.world_get_health(w, ppid)
                        ph.current = min(ph.current + kh.amount, ph.max)
                    }
                }


                if cw.world_has_component(w, ev.target_id, .ContagionTag) {
                    cw.world_clear_contagion_tag(w, ev.target_id)
                    if cw.world_has_component(w, ev.target_id, .Transform) {
                        dead_pos := cw.world_get_transform(w, ev.target_id).position
                        spread_r2 :: f32(160 * 160)
                        near := cw.world_query(w, cw.query_mask(.AIAgent, .Transform),
                                               context.temp_allocator)
                        for nid in near {
                            if nid == ev.target_id { continue }
                            np  := cw.world_get_transform(w, nid).position
                            dx  := np[0] - dead_pos[0]
                            dy  := np[1] - dead_pos[1]
                            if dx*dx + dy*dy <= spread_r2 {
                                cw.status_effect_apply(w, nid, cw.StatusEffect{
                                    type           = .Poison,
                                    application    = .Base,
                                    stack_behavior = .Refresh,
                                    duration       = 4.0,
                                    strength       = 1.0,
                                })
                            }
                        }
                    }
                }


                if cw.world_has_component(w, ev.source_id, .Ability) &&
                   cw.world_has_component(w, ev.source_id, .Inventory) {
                    ab := cw.world_get_ability(w, ev.source_id)
                    for sli in 0..<cw.ABILITY_SLOT_COUNT {
                        ab_type := player_ability_in_slot(w, ev.source_id, sli)
                        if ab_type == .None { continue }
                        def := &ABILITY_DEFS[ab_type]
                        should_reset := false
                        for ei in 0..<def.exec_count {
                            if def.execs[ei].reset_cd_on_kill {
                                should_reset = true
                                break
                            }
                        }
                        if should_reset {
                            ab.slots[sli].cooldown = 0
                        }
                    }
                }


                for slot in 0..<cw.MAX_PLAYERS {
                    ppid := w.player_ids[slot]
                    if !cw.world_is_valid(w, ppid)                      { continue }
                    if !cw.world_has_component(w, ppid, .Inventory)     { continue }
                    inv := cw.world_get_inventory(w, ppid)
                    flask_slots := []cw.EquipSlot{ .Flask1, .Flask2 }
                    for fs in flask_slots {
                        fid := inv.equipped[int(fs)]
                        if !cw.world_is_valid(w, fid)                   { continue }
                        if !cw.world_has_component(w, fid, .Flask)      { continue }
                        fc := cw.world_get_flask(w, fid)
                        if fc.charges < fc.max_charges {
                            fc.charges += 1
                        }
                    }
                }

                for slot in 0..<cw.MAX_PLAYERS {
                    pid := w.player_ids[slot]
                    if !cw.world_is_valid(w, pid) { continue }
                    if !cw.world_has_component(w, pid, .Stats) { continue }

                    st := cw.world_get_stats(w, pid)
                    st.xp += XP_PER_KILL
                    if pid == w.player_id { ui_mark_dirty(.Stats) }
                    leveled := false
                    for st.xp >= st.xp_next {
                        st.xp          -= st.xp_next
                        st.level       += 1
                        st.stat_points += 1
                        st.xp_next      = f32(st.level) * 100.0
                        leveled          = true
                    }
                    if leveled {

                        if cw.world_has_component(w, pid, .Health) {
                            health := cw.world_get_health(w, pid)
                            health.current = health.max
                            health.energy  = health.max_energy
                        }
                        if pid == w.player_id {
                            g_levelup_flash = LEVELUP_FLASH_TIME
                            play_sfx("levelup")
                        }
                    }
                }

                play_sfx_at("enemy_death", death_pos)
                quest_check_all(w)
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


    if heart_killed_player && g_playing_state == .Gameplay {
        on_player_death(w)
        return
    }

    for d in pending_drops {


        drop_rng := rand.create(d.seed ~ 0xd1ce_face_cafe_b00b)
        context.random_generator = rand.default_random_generator(&drop_rng)
        roll := rand.float32()
        if roll < ITEM_DROP_CHANCE_UNIQUE {
            spawn_loot_drop(w, d.pos, d.seed, cw.ItemRarity.Unique)
        } else if roll < ITEM_DROP_CHANCE_LEGENDARY {
            spawn_loot_drop(w, d.pos, d.seed, cw.ItemRarity.Legendary)
        } else if roll < ITEM_DROP_CHANCE_EPIC {
            spawn_loot_drop(w, d.pos, d.seed, cw.ItemRarity.Epic)
        } else if roll < ITEM_DROP_CHANCE_RARE {
            spawn_loot_drop(w, d.pos, d.seed, cw.ItemRarity.Rare)
        } else if roll < ITEM_DROP_CHANCE_NORMAL {
            spawn_loot_drop(w, d.pos, d.seed, cw.ItemRarity.Normal)
        }


        serum_rng := rand.create(d.seed ~ 0xfeedc0de_beefcafe)
        context.random_generator = rand.default_random_generator(&serum_rng)
        if rand.float32() < SERUM_DROP_CHANCE {
            serum_pos := [3]f32{ d.pos[0] - 18, d.pos[1] + 10, 0 }
            spawn_serum_drop(w, serum_pos, d.seed ~ 0xc0ffee11_deadbeef)
        }

        gold_amt := gold_drop_amount(w.tick, d.entity_id)
        gold_pos := [3]f32{ d.pos[0] + 16, d.pos[1] - 8, 0 }
        spawn_gold_drop(w, gold_pos, gold_amt)


        if d.was_boss {
            spawn_ability_drop(w, {d.pos[0] - 24, d.pos[1] - 18, 0},
                d.seed ~ 0xab11_cafe_babe)
            spawn_ability_drop(w, {d.pos[0] + 24, d.pos[1] + 18, 0},
                d.seed ~ 0xab22_dead_beef)
        } else {
            ab_rng := rand.create(d.seed ~ 0xab33_feed_face)
            context.random_generator = rand.default_random_generator(&ab_rng)
            if rand.float32() < ABILITY_DROP_CHANCE {
                spawn_ability_drop(w, {d.pos[0] + 12, d.pos[1] - 14, 0},
                    d.seed ~ 0xab44_c0ff_ee11)
            }
        }
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
