package main


status_is_stationary :: proc(w: ^World, id: int, slot: int) -> bool {
    moving_input := false
    if slot >= 0 && slot < MAX_PLAYERS {
        f := g_staged_input[slot]
        moving_input = f.move[0]*f.move[0] + f.move[1]*f.move[1] > 0.01
    }

    moving_velocity := false
    if world_has_component(w, id, .Velocity) {
        vel := comp_get(w, id, .Velocity, VelocityComp)
        moving_velocity = vel.value[0]*vel.value[0] + vel.value[1]*vel.value[1] > 400
    }

    dashing := false
    if world_has_component(w, id, .DodgeState) {
        dashing = comp_get(w, id, .DodgeState, DodgeComp).active
    }

    return !moving_input && !moving_velocity && !dashing
}

stats_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .EarlyUpdate { return }

    ids := world_query(w, query_mask(.Stats, .Health))
    defer delete(ids)

    for id in ids {
        st := comp_get(w, id, .Stats, StatsComp)
        h  := comp_get(w, id, .Health, HealthComp)

        slot := -1
        if world_has_component(w, id, .Player) {
            slot = comp_get(w, id, .Player, PlayerComp).slot
        }

        _ = status_is_stationary(w, id, slot)

        affix_hp_pct          := f32(0)
        affix_armor           := f32(0)
        affix_speed_pct       := f32(0)
        affix_energy_pct      := f32(0)
        affix_damage_pct      := f32(0)
        affix_fire_rate_pct   := f32(0)
        affix_reload_spd_pct  := f32(0)
        affix_hp_regen        := f32(0)
        affix_proj_speed_pct  := f32(0)
        affix_pierce          := f32(0)
        affix_ammo_pct        := f32(0)
        affix_melee_dmg_pct   := f32(0)
        affix_melee_range_pct := f32(0)
        affix_melee_speed_pct := f32(0)
        base_armor_sum        := f32(0)
        base_shield_sum       := f32(0)

        affix_str_bonus        := f32(0)
        affix_dex_bonus        := f32(0)
        affix_sci_bonus        := f32(0)
        affix_energy_regen     := f32(0)
        affix_energy_cost_pct  := f32(0)

        affix_res_physical     := f32(0)
        affix_res_necrotic     := f32(0)
        affix_res_fire         := f32(0)
        affix_res_galvanic     := f32(0)
        affix_res_poison       := f32(0)

        if world_has_component(w, id, .Inventory) {
            inv := comp_get(w, id, .Inventory, InventoryComp)
            for slot_idx in 0..<EQUIP_SLOT_COUNT {
                eid := inv.equipped[slot_idx]
                if eid == INVALID_ENTITY               { continue }
                if !world_is_valid(w, eid)             { continue }
                if !world_has_component(w, eid, .Item) { continue }

                item := comp_get(w, eid, .Item, ItemComp)
                base_armor_sum  += item.base_armor
                base_shield_sum += item.base_shield
                for i in 0..<int(item.affix_count) {
                    a := item.affixes[i]
                    switch a.type {
                    case .BonusHP:          affix_hp_pct          += a.value
                    case .Armor:            affix_armor           += a.value
                    case .BonusMoveSpeed:   affix_speed_pct       += a.value
                    case .BonusEnergy:      affix_energy_pct      += a.value
                    case .BonusDamage:      affix_damage_pct      += a.value
                    case .BonusFireRate:    affix_fire_rate_pct   += a.value
                    case .BonusReloadSpeed: affix_reload_spd_pct  += a.value
                    case .HealthRegen:      affix_hp_regen        += a.value
                    case .BonusProjSpeed:   affix_proj_speed_pct  += a.value
                    case .BonusPierce:      affix_pierce          += a.value
                    case .BonusAmmo:        affix_ammo_pct        += a.value
                    case .BonusMeleeDamage: affix_melee_dmg_pct   += a.value
                    case .BonusMeleeRange:  affix_melee_range_pct += a.value
                    case .BonusMeleeSpeed:  affix_melee_speed_pct += a.value
                    case .BonusStrength:    affix_str_bonus        += a.value
                    case .BonusDexterity:   affix_dex_bonus        += a.value
                    case .BonusScience:     affix_sci_bonus        += a.value
                    case .BonusEnergyRegen: affix_energy_regen     += a.value
                    case .ReduceEnergyCost: affix_energy_cost_pct  += a.value
                    case .ResistPhysical:   affix_res_physical     += a.value
                    case .ResistNecrotic:   affix_res_necrotic     += a.value
                    case .ResistFire:       affix_res_fire         += a.value
                    case .ResistGalvanic:   affix_res_galvanic     += a.value
                    case .ResistPoison:     affix_res_poison       += a.value
                    case .None:
                    }
                }
            }
        }

        passive_power := f32(1.0)

        mut_damage_mult        := f32(1.0)
        has_mut_lock_hp_to_one := false
        mut_healing_blocked    := false
        mut_pickup_heal_blocked:= false
        mut_block_pickups      := false
        mut_nonlethal_shots    := false
        mut_disable_actives    := false
        mut_ranged_blocked     := false
        early_death_pct        := f32(0)
        root_on_fire_active    := false
        root_proj_speed_mult   := f32(1.0)
        root_damage_mult       := f32(1.0)
        missing_hp_damage_mult := f32(1.0)
        move_speed_mult        := f32(1.0)


        if world_has_component(w, id, .OverchargeBuff) {
            ob := comp_get(w, id, .OverchargeBuff, OverchargeBuffComp)
            ob.timer += dt
            if ob.timer >= ob.duration {
                comp_rm(w, id, .OverchargeBuff)
            } else {
                mut_damage_mult  *= ob.damage_mult
                move_speed_mult  *= ob.speed_mult


            }
        }


        if world_has_component(w, id, .KillHeal) {
            kh := comp_get(w, id, .KillHeal, KillHealComp)
            kh.timer += dt
            if kh.timer >= kh.duration {
                comp_rm(w, id, .KillHeal)
            }
        }


        if world_has_component(w, id, .MutationContainer) {
            mc := comp_get(w, id, .MutationContainer, MutationContainerComp)
            for i in 0..<mc.entity_count {
                eid := mc.entities[i]
                if !world_is_valid(w, eid)          { continue }

                if world_has_component(w, eid, .MutDamageMult) {
                    mut_damage_mult *= comp_get(w, eid, .MutDamageMult, MutDamageMultComp).mult
                }

                if world_has_component(w, eid, .MutLockHpToOne) {
                    has_mut_lock_hp_to_one = true
                }

                if world_has_component(w, eid, .MutBlockHealing) {
                    mut_healing_blocked = true
                }

                if world_has_component(w, eid, .MutMoveSpeedMult) {
                    move_speed_mult *= comp_get(w, eid, .MutMoveSpeedMult, MutMoveSpeedMultComp).mult
                }

                if world_has_component(w, eid, .MutBlockRanged) {
                    mut_ranged_blocked = true
                }

                if world_has_component(w, eid, .MutBlockPickupHeal) {
                    mut_pickup_heal_blocked = true
                }

                if world_has_component(w, eid, .MutBlockPickups) {
                    mut_block_pickups = true
                }

                if world_has_component(w, eid, .MutNonlethalShots) {
                    mut_nonlethal_shots = true
                }

                if world_has_component(w, eid, .MutDisableActives) {
                    mut_disable_actives = true
                }

                if world_has_component(w, eid, .MutPassivePower) {
                    passive_power *= comp_get(w, eid, .MutPassivePower, MutPassivePowerComp).mult
                }

                if world_has_component(w, eid, .MutRootOnFire) {
                    rof := comp_get(w, eid, .MutRootOnFire, MutRootOnFireComp)
                    if rof.timer > 0 {
                        rof.timer = max(0, rof.timer - dt)
                        if rof.timer > 0 {
                            root_on_fire_active  = true
                            root_damage_mult    *= rof.damage_mult_while_rooted
                            root_proj_speed_mult = min(root_proj_speed_mult, rof.projectile_speed_mult)
                        }
                    }
                }

                if world_has_component(w, eid, .MutTimedSelfDamage) {
                    tsd := comp_get(w, eid, .MutTimedSelfDamage, MutTimedSelfDamageComp)
                    tsd.timer += dt
                    if tsd.timer >= tsd.grace && h.current > 1.0 {
                        world_push_damage(w, id, tsd.dps * dt)
                    }
                }

                if world_has_component(w, eid, .MutEarlyDeathThreshold) {
                    edt := comp_get(w, eid, .MutEarlyDeathThreshold, MutEarlyDeathThresholdComp)
                    early_death_pct = max(early_death_pct, edt.threshold_pct)
                }

                if world_has_component(w, eid, .MutMissingHealthDamage) && h.max > 0 {
                    mhd := comp_get(w, eid, .MutMissingHealthDamage, MutMissingHealthDamageComp)
                    missing := 1.0 - (h.current / h.max)
                    missing_hp_damage_mult *= 1.0 + missing * (mhd.max_mult - 1.0) / (1.0 - mhd.floor_hp_pct)
                }

            }
        }


        eff_str := st.strength  + int(affix_str_bonus)
        eff_dex := st.dexterity + int(affix_dex_bonus)
        eff_sci := st.science   + int(affix_sci_bonus)

        str_mult      := 1.0 + f32(eff_str - 1) * 0.15
        dex_mult      := 1.0 + f32(eff_dex - 1) * 0.08
        sci_hp_mult   := 1.0 + f32(eff_sci - 1) * 0.12
        sci_cd_mult   := 1.0 + f32(eff_sci - 1) * 0.05
        crit_chance   := clamp(0.05 + f32(eff_dex - 1) * 0.025, 0.05, 0.75)
        damage_mult   := 1.0 + affix_damage_pct
        damage_mult *= mut_damage_mult
        damage_mult *= missing_hp_damage_mult

        projectile_speed_mult := 1.0 + affix_proj_speed_pct
        movement_blocked      := false
        if root_on_fire_active {
            movement_blocked       = true
            damage_mult           *= root_damage_mult
            projectile_speed_mult *= root_proj_speed_mult
        }


        overcharge_fire_rate := f32(1.0)
        overcharge_reload    := f32(1.0)
        if world_has_component(w, id, .OverchargeBuff) {
            ob := comp_get(w, id, .OverchargeBuff, OverchargeBuffComp)
            overcharge_fire_rate = ob.fire_rate_mult
            overcharge_reload    = ob.fire_rate_mult
        }

        st.max_hp_mult              = str_mult * (1.0 + affix_hp_pct)
        st.max_energy_mult          = sci_hp_mult * (1.0 + affix_energy_pct)
        st.move_speed               = st.base_speed * dex_mult * (1.0 + affix_speed_pct) * move_speed_mult
        st.damage_mult              = damage_mult
        st.fire_rate_mult           = dex_mult * (1.0 + affix_fire_rate_pct) * overcharge_fire_rate
        st.reload_speed_mult        = dex_mult * (1.0 + affix_reload_spd_pct) * overcharge_reload
        st.projectile_speed_mult    = projectile_speed_mult
        st.armor                    = clamp(affix_armor + base_armor_sum, 0, 0.75)
        st.hp_regen_pct             = affix_hp_regen
        st.crit_chance              = clamp(crit_chance, 0, 0.95)
        st.special_ability_crit     = 0
        st.dodge_cooldown_reduction = 0
        st.vision_bonus             = 0
        st.ability_cooldown_mult    = sci_cd_mult
        st.deadman_early_death_pct  = early_death_pct

        st.energy_regen             = 8.0 + f32(max(0, eff_sci - 1)) * 1.5 + affix_energy_regen

        st.energy_cost_mult         = max(0.10, 1.0 - affix_energy_cost_pct)


        if affix_res_physical > 0 || affix_res_necrotic > 0 || affix_res_fire > 0 ||
           affix_res_galvanic > 0 || affix_res_poison > 0 {
            comp_set(w, id, .Resistance, ResistanceComp{
                physical = affix_res_physical,
                necrotic = affix_res_necrotic,
                fire     = affix_res_fire,
                galvanic = affix_res_galvanic,
                poison   = affix_res_poison,
            })
        } else if world_has_component(w, id, .Resistance) {
            comp_rm(w, id, .Resistance)
        }
        st.movement_blocked         = movement_blocked
        st.healing_blocked          = mut_healing_blocked
        st.pickup_healing_blocked   = mut_pickup_heal_blocked
        st.pickups_blocked          = mut_block_pickups
        st.active_abilities_blocked = mut_disable_actives
        st.ranged_attacks_blocked   = mut_ranged_blocked
        st.nonlethal_shots          = mut_nonlethal_shots
        st.hp_locked_to_one         = has_mut_lock_hp_to_one
        st.bonus_ammo_pct           = affix_ammo_pct
        st.bonus_pierce             = int(affix_pierce)
        st.melee_damage_mult        = 1.0 + affix_melee_dmg_pct
        st.melee_range_mult         = 1.0 + affix_melee_range_pct
        st.melee_speed_mult         = 1.0 + affix_melee_speed_pct


        old_shield_max := st.shield_max
        st.shield_max   = base_shield_sum
        if st.shield_max > old_shield_max {

            h.shield = clamp(h.shield + (st.shield_max - old_shield_max), 0, st.shield_max)
        } else {
            h.shield = clamp(h.shield, 0, st.shield_max)
        }

        new_max_hp     := st.base_hp * st.max_hp_mult
        new_max_energy := st.base_energy * st.max_energy_mult
        if st.hp_locked_to_one {
            new_max_hp = 1
        }

        if h.max > 0 && new_max_hp != h.max {
            h.current = clamp(h.current / h.max * new_max_hp, 0, new_max_hp)
        } else {
            h.current = clamp(h.current, 0, new_max_hp)
        }
        if h.max_energy > 0 && new_max_energy != h.max_energy {
            h.energy = clamp(h.energy / h.max_energy * new_max_energy, 0, new_max_energy)
        } else {
            h.energy = clamp(h.energy, 0, new_max_energy)
        }

        h.max        = new_max_hp
        h.max_energy = new_max_energy
        if st.hp_locked_to_one && h.current > 1 {
            h.current = 1
        }


        if st.hp_regen_pct > 0 && !st.healing_blocked && h.current < h.max && h.current > 0 {
            h.current = min(h.current + st.hp_regen_pct * h.max * dt, h.max)
        }


        if st.energy_regen > 0 && h.energy < h.max_energy {
            h.energy = min(h.energy + st.energy_regen * dt, h.max_energy)
        }
    }


    da_ids := world_query(w, query_mask(.DamageAmp))
    defer delete(da_ids)
    for eid in da_ids {
        da := comp_get(w, eid, .DamageAmp, DamageAmpComp)
        da.timer -= dt
        if da.timer <= 0 {
            comp_rm(w, eid, .DamageAmp)
        }
    }
}
