package main

import "core:math/rand"

@(private = "file")
DropPending :: struct { pos: [3]f32, seed: u64, entity_id: int, was_boss: bool }

RESPAWN_DELAY      :: f32(2.0)
XP_PER_KILL        :: f32(20)
LEVELUP_FLASH_TIME :: f32(2.5)

damage_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
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
        if !world_is_valid(w, ev.target_id)               { continue }
        if !world_has_component(w, ev.target_id, .Health) { continue }

        if ev.amount > 0 && (ev.target_id == w.player_id || ev.source_id == w.player_id) {
            mark_combat()
        }

        h := comp_get(w, ev.target_id, .Health, HealthComp)
        amount := ev.amount

        if ev.amount > 0 && ev.kind == .Physical &&
           world_has_component(w, ev.target_id, .Stats) {
            amount *= (1.0 - comp_get(w, ev.target_id, .Stats, StatsComp).armor)
        }

        if ev.amount > 0 && world_has_component(w, ev.target_id, .DamageAmp) {
            amount *= comp_get(w, ev.target_id, .DamageAmp, DamageAmpComp).mult
        }

        if ev.amount > 0 && world_has_component(w, ev.target_id, .Resistance) {
            res := comp_get(w, ev.target_id, .Resistance, ResistanceComp)
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
           world_has_component(w, ev.source_id, .MutationContainer) &&
           world_has_component(w, ev.target_id, .AIAgent) {
            src_mc := comp_get(w, ev.source_id, .MutationContainer, MutationContainerComp)
            for mi in 0..<src_mc.entity_count {
                meid := src_mc.entities[mi]
                if !world_is_valid(w, meid) { continue }
                if world_has_component(w, meid, .MutUnseenDamageMult) {
                    udm := comp_get(w, meid, .MutUnseenDamageMult, MutUnseenDamageMultComp)
                    if world_has_component(w, ev.source_id, .Transform) &&
                       world_has_component(w, ev.target_id, .Transform) {
                        pp := comp_get(w, ev.source_id, .Transform, TransformComp).position
                        ep := comp_get(w, ev.target_id, .Transform, TransformComp).position
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

        if amount > 0 && world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := comp_get(w, ev.target_id, .MutationContainer, MutationContainerComp)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !world_is_valid(w, meid)                          { continue }
                if !world_has_component(w, meid, .MutDamageTakenMult) { continue }
                amount *= comp_get(w, meid, .MutDamageTakenMult, MutDamageTakenMultComp).mult
                break
            }
        }

        if amount > 0 && world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := comp_get(w, ev.target_id, .MutationContainer, MutationContainerComp)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !world_is_valid(w, meid)                     { continue }
                if !world_has_component(w, meid, .MutHeartCage) { continue }
                hc := comp_get(w, meid, .MutHeartCage, MutHeartCageComp)

                if ev.source_id == ev.target_id { continue }
                if world_is_valid(w, hc.heart_id) &&
                   world_has_component(w, hc.heart_id, .Health) {
                    hh := comp_get(w, hc.heart_id, .Health, HealthComp)
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

        if amount > 0 && world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := comp_get(w, ev.target_id, .MutationContainer, MutationContainerComp)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !world_is_valid(w, meid)                         { continue }
                if !world_has_component(w, meid, .MutStationaryShield) { continue }
                ss := comp_get(w, meid, .MutStationaryShield, MutStationaryShieldComp)
                if ss.shield > 0 {
                    absorbed := min(ss.shield, amount)
                    ss.shield -= absorbed
                    amount    -= absorbed
                }
                break
            }
        }

        is_crit := false
        if amount > 0 && world_has_component(w, ev.target_id, .AIAgent) {
            best_crit := f32(0.05)
            for slot in 0..<MAX_PLAYERS {
                pid := w.player_ids[slot]
                if !world_is_valid(w, pid) { continue }
                if !world_has_component(w, pid, .Stats) { continue }
                c := comp_get(w, pid, .Stats, StatsComp).crit_chance
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
           world_has_component(w, ev.target_id, .Stats) &&
           comp_get(w, ev.target_id, .Stats, StatsComp).healing_blocked {
            amount = 0
        }

        if amount < 0 && ev.source_id == 0 &&
           world_has_component(w, ev.target_id, .Stats) &&
           comp_get(w, ev.target_id, .Stats, StatsComp).pickup_healing_blocked {
            amount = 0
        }

        if amount < 0 && world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := comp_get(w, ev.target_id, .MutationContainer, MutationContainerComp)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !world_is_valid(w, meid)                     { continue }
                if !world_has_component(w, meid, .MutThornPact) { continue }
                tp     := comp_get(w, meid, .MutThornPact, MutThornPactComp)
                amount *= tp.slow_heal_mult
                break
            }
        }

        force_death := false
        if amount > 0 && world_has_component(w, ev.target_id, .Stats) {
            threshold := h.max * comp_get(w, ev.target_id, .Stats, StatsComp).deadman_early_death_pct
            if h.current - amount < threshold {
                h.current  = 0
                force_death = true
            }
        }

        if !force_death && amount > 0 && world_has_component(w, ev.target_id, .AIAgent) {
            if ev.source_id != 0 &&
               world_has_component(w, ev.source_id, .Stats) &&
               comp_get(w, ev.source_id, .Stats, StatsComp).nonlethal_shots {
                if h.current - amount <= 0 {
                    h.current = 1
                    continue
                }
            }
        }

        if amount > 0 && ev.source_id != 0 &&
           world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := comp_get(w, ev.target_id, .MutationContainer, MutationContainerComp)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !world_is_valid(w, meid)                     { continue }
                if !world_has_component(w, meid, .MutThornPact) { continue }
                tp := comp_get(w, meid, .MutThornPact, MutThornPactComp)
                world_push_damage(w, ev.source_id, amount * tp.reflect_pct, ev.target_id)
                break
            }
        }

        if amount > 0 && world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := comp_get(w, ev.target_id, .MutationContainer, MutationContainerComp)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !world_is_valid(w, meid)                     { continue }
                if !world_has_component(w, meid, .MutBlackLung) { continue }
                bl := comp_get(w, meid, .MutBlackLung, MutBlackLungComp)
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

        if world_has_component(w, ev.target_id, .Stats) &&
           comp_get(w, ev.target_id, .Stats, StatsComp).hp_locked_to_one {
            if h.current > 1 { h.current = 1 }
        }

        if amount > 0 && ev.source_id != 0 &&
           world_has_component(w, ev.source_id, .MutationContainer) &&
           world_has_component(w, ev.target_id, .AIAgent) {
            src_mc := comp_get(w, ev.source_id, .MutationContainer, MutationContainerComp)
            for mi in 0..<src_mc.entity_count {
                meid := src_mc.entities[mi]
                if !world_is_valid(w, meid)                 { continue }
                if !world_has_component(w, meid, .MutLifesteal) { continue }
                ls := comp_get(w, meid, .MutLifesteal, MutLifestealComp)
                world_push_heal(w, ev.source_id, ls.hp_per_hit)
                break
            }
        }

        if amount > 0 && world_has_component(w, ev.target_id, .Transform) {
            pos := comp_get(w, ev.target_id, .Transform, TransformComp).position
            push_dmg_number(pos[0], pos[1], amount, ev.target_id != w.player_id, is_crit)
        }

        if h.current > 0 && !force_death {
            if ev.target_id == w.player_id && amount > 0 {
                play_sfx("player_hurt")
            }
            continue
        }

        bomb_triggered := false
        if world_has_component(w, ev.target_id, .MutationContainer) {
            tgt_mc := comp_get(w, ev.target_id, .MutationContainer, MutationContainerComp)
            for mi in 0..<tgt_mc.entity_count {
                meid := tgt_mc.entities[mi]
                if !world_is_valid(w, meid)                         { continue }
                if !world_has_component(w, meid, .MutOnDeathExplode) { continue }
                ode := comp_get(w, meid, .MutOnDeathExplode, MutOnDeathExplodeComp)
                if ode.timer > 0                                        { continue }
                tgt_h := comp_get(w, ev.target_id, .Health, HealthComp)
                exp_dmg := tgt_h.max * ode.damage_pct
                if world_has_component(w, ev.target_id, .Transform) {
                    epos := comp_get(w, ev.target_id, .Transform, TransformComp).position
                    r2   := ode.radius * ode.radius
                    if is_player_entity(w, ev.target_id) {
                        ai_ids := world_query(w, query_mask(.AIAgent, .Transform), context.temp_allocator)
                        for ai_id in ai_ids {
                            ap  := comp_get(w, ai_id, .Transform, TransformComp).position
                            dx  := ap[0] - epos[0]
                            dy  := ap[1] - epos[1]
                            if dx*dx + dy*dy <= r2 {
                                world_push_damage(w, ai_id, exp_dmg, ev.target_id)
                            }
                        }
                        camera_shake(5)
                        push_explosion(epos[0], epos[1], ode.radius, 255, 140, 30)
                    } else {
                        for pslot in 0..<MAX_PLAYERS {
                            ppid := w.player_ids[pslot]
                            if !world_is_valid(w, ppid)                  { continue }
                            if !world_has_component(w, ppid, .Transform) { continue }
                            if world_has_component(w, ppid, .Respawn) &&
                               comp_get(w, ppid, .Respawn, RespawnComp).timer > 0      { continue }
                            pp  := comp_get(w, ppid, .Transform, TransformComp).position
                            dx  := pp[0] - epos[0]
                            dy  := pp[1] - epos[1]
                            if dx*dx + dy*dy <= r2 {
                                world_push_damage(w, ppid, exp_dmg, ev.target_id)
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

        if !bomb_triggered && world_has_component(w, ev.target_id, .Respawn) {
            rsp := comp_get(w, ev.target_id, .Respawn, RespawnComp)
            if rsp.timer <= 0 {
                rsp.timer = rsp.delay
                play_sfx("player_death")
            }
        } else if !bomb_triggered {
            if world_has_component(w, ev.target_id, .Reanimated) {
                world_tag_destroy(w, ev.target_id)
                continue
            }

            is_heart := false
            heart_check: for pslot in 0..<MAX_PLAYERS {
                ppid := w.player_ids[pslot]
                if !world_is_valid(w, ppid)                          { continue }
                if !world_has_component(w, ppid, .MutationContainer) { continue }
                ppmc := comp_get(w, ppid, .MutationContainer, MutationContainerComp)
                for mi in 0..<ppmc.entity_count {
                    meid := ppmc.entities[mi]
                    if !world_is_valid(w, meid)                     { continue }
                    if !world_has_component(w, meid, .MutHeartCage) { continue }
                    if comp_get(w, meid, .MutHeartCage, MutHeartCageComp).heart_id == ev.target_id {
                        heart_killed_player = true
                        is_heart            = true
                    }
                    break heart_check
                }
            }
            if is_heart {
                world_tag_destroy(w, ev.target_id)
                continue
            }

            was_reanimated := false
            if world_has_component(w, ev.target_id, .AIAgent) {
                g_lifetime_stats.enemies_killed += 1
                ai := comp_get(w, ev.target_id, .AIAgent, AIAgentComp)
                if ai.tier == .Legendary {
                    g_lifetime_stats.elites_killed += 1
                }
                if ev.target_id == g_boss_id {
                    g_lifetime_stats.bosses_killed += 1
                }

                for pslot in 0..<MAX_PLAYERS {
                    ppid := w.player_ids[pslot]
                    if !world_is_valid(w, ppid)                          { continue }
                    if !world_has_component(w, ppid, .MutationContainer) { continue }
                    cc_mc := comp_get(w, ppid, .MutationContainer, MutationContainerComp)
                    for mi in 0..<cc_mc.entity_count {
                        meid := cc_mc.entities[mi]
                        if !world_is_valid(w, meid)                        { continue }
                        if !world_has_component(w, meid, .MutCarrionCrown) { continue }
                        cc := comp_get(w, meid, .MutCarrionCrown, MutCarrionCrownComp)
                        living := 0
                        for si in 0..<CARRION_MAX_SERVANTS {
                            if world_is_valid(w, cc.servant_ids[si]) { living += 1 }
                        }
                        if living < CARRION_MAX_SERVANTS {
                            rng := rand.create(loot_seed(w.tick, ev.target_id) ~ 0xfeedface_cafebabe)
                            context.random_generator = rand.default_random_generator(&rng)
                            if rand.float32() < 0.30 {
                                _reanimate_enemy(w, ev.target_id, ppid)
                                for si in 0..<CARRION_MAX_SERVANTS {
                                    if !world_is_valid(w, cc.servant_ids[si]) {
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
                if world_has_component(w, ev.target_id, .Transform) {
                    death_pos = comp_get(w, ev.target_id, .Transform, TransformComp).position
                    if !was_reanimated {
                        append(&pending_drops, DropPending{
                            pos       = death_pos,
                            seed      = loot_seed(w.tick, ev.target_id),
                            entity_id = ev.target_id,
                            was_boss  = ev.target_id == g_boss_id,
                        })
                    }
                }

                for pslot in 0..<MAX_PLAYERS {
                    ppid := w.player_ids[pslot]
                    if !world_is_valid(w, ppid)                          { continue }
                    if !world_has_component(w, ppid, .MutationContainer) { continue }
                    kh_mc := comp_get(w, ppid, .MutationContainer, MutationContainerComp)
                    for mi in 0..<kh_mc.entity_count {
                        meid := kh_mc.entities[mi]
                        if !world_is_valid(w, meid)                  { continue }
                        if !world_has_component(w, meid, .MutKillHeal) { continue }
                        kh := comp_get(w, meid, .MutKillHeal, MutKillHealComp)
                        if world_has_component(w, ppid, .Health) {
                            ph := comp_get(w, ppid, .Health, HealthComp)
                            world_push_heal(w, ppid, ph.max * kh.heal_pct)
                        }
                        break
                    }
                }

                for slot in 0..<MAX_PLAYERS {
                    ppid := w.player_ids[slot]
                    if !world_is_valid(w, ppid)                      { continue }
                    if !world_has_component(w, ppid, .KillHeal)      { continue }
                    kh := comp_get(w, ppid, .KillHeal, KillHealComp)
                    if kh.timer < kh.duration &&
                       world_has_component(w, ppid, .Health) {
                        if world_has_component(w, ppid, .Stats) &&
                           comp_get(w, ppid, .Stats, StatsComp).healing_blocked { continue }
                        ph := comp_get(w, ppid, .Health, HealthComp)
                        ph.current = min(ph.current + kh.amount, ph.max)
                    }
                }

                if world_has_component(w, ev.target_id, .ContagionTag) {
                    comp_rm(w, ev.target_id, .ContagionTag)
                    if world_has_component(w, ev.target_id, .Transform) {
                        dead_pos := comp_get(w, ev.target_id, .Transform, TransformComp).position
                        spread_r2 :: f32(160 * 160)
                        near := world_query(w, query_mask(.AIAgent, .Transform),
                                               context.temp_allocator)
                        for nid in near {
                            if nid == ev.target_id { continue }
                            np  := comp_get(w, nid, .Transform, TransformComp).position
                            dx  := np[0] - dead_pos[0]
                            dy  := np[1] - dead_pos[1]
                            if dx*dx + dy*dy <= spread_r2 {
                                status_effect_apply(w, nid, StatusEffect{
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

                if world_has_component(w, ev.source_id, .Ability) &&
                   world_has_component(w, ev.source_id, .Inventory) {
                    ab := comp_get(w, ev.source_id, .Ability, AbilityComp)
                    for sli in 0..<ABILITY_SLOT_COUNT {
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

                for slot in 0..<MAX_PLAYERS {
                    ppid := w.player_ids[slot]
                    if !world_is_valid(w, ppid)                      { continue }
                    if !world_has_component(w, ppid, .Inventory)     { continue }
                    inv := comp_get(w, ppid, .Inventory, InventoryComp)
                    flask_slots := []EquipSlot{ .Flask1, .Flask2 }
                    for fs in flask_slots {
                        fid := inv.equipped[int(fs)]
                        if !world_is_valid(w, fid)                   { continue }
                        if !world_has_component(w, fid, .Flask)      { continue }
                        fc := comp_get(w, fid, .Flask, FlaskComp)
                        if fc.charges < fc.max_charges {
                            fc.charges += 1
                        }
                    }
                }

                for slot in 0..<MAX_PLAYERS {
                    pid := w.player_ids[slot]
                    if !world_is_valid(w, pid) { continue }
                    if !world_has_component(w, pid, .Stats) { continue }

                    st := comp_get(w, pid, .Stats, StatsComp)
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
                        if world_has_component(w, pid, .Health) {
                            health := comp_get(w, pid, .Health, HealthComp)
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
                g_boss_id = INVALID_ENTITY
            }
            if !was_reanimated {
                world_tag_destroy(w, ev.target_id)
            }
        }
    }
    world_clear_damage_events(w)

    if heart_killed_player && g_playing_state == .Gameplay {
        on_player_death(w)
        return
    }

    for d in pending_drops {
        drop_rng := rand.create(d.seed ~ 0xd1ce_face_cafe_b00b)
        context.random_generator = rand.default_random_generator(&drop_rng)
        roll := rand.float32()
        if roll < ITEM_DROP_CHANCE_UNIQUE {
            spawn_loot_drop(w, d.pos, d.seed, ItemRarity.Unique)
        } else if roll < ITEM_DROP_CHANCE_LEGENDARY {
            spawn_loot_drop(w, d.pos, d.seed, ItemRarity.Legendary)
        } else if roll < ITEM_DROP_CHANCE_EPIC {
            spawn_loot_drop(w, d.pos, d.seed, ItemRarity.Epic)
        } else if roll < ITEM_DROP_CHANCE_RARE {
            spawn_loot_drop(w, d.pos, d.seed, ItemRarity.Rare)
        } else if roll < ITEM_DROP_CHANCE_NORMAL {
            spawn_loot_drop(w, d.pos, d.seed, ItemRarity.Normal)
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

    rsp_ids := world_query(w, query_mask(.Respawn))
    defer delete(rsp_ids)

    for id in rsp_ids {
        rsp := comp_get(w, id, .Respawn, RespawnComp)
        if rsp.timer <= 0 { continue }

        rsp.timer -= dt
        if rsp.timer > 0 { continue }

        rsp.timer = 0
        if id == w.player_id { play_sfx("player_respawn") }

        if world_has_component(w, id, .Health) {
            h := comp_get(w, id, .Health, HealthComp)
            h.current            = h.max
        }
        if world_has_component(w, id, .Transform) {
            t := comp_get(w, id, .Transform, TransformComp)
            t.position = rsp.spawn_pos
            t.rotation = 0
        }
        if world_has_component(w, id, .Velocity) {
            comp_get(w, id, .Velocity, VelocityComp).value = {}
        }
    }
}
