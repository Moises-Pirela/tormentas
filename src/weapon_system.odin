package main

import "core:math"

MUZZLE_OFFSET :: f32(PLAYER_RADIUS + 6)

@(private = "file")
ArchetypeWeaponParams :: struct {
    wep_type:         WeaponType,
    damage:           f32,
    fire_rate:        f32,
    projectile_speed: f32,
    projectile_life:  f32,
    ammo_max:         int,
    reload_time:      f32,
}

@(private = "file")
ARCHETYPE_WEP_PARAMS := [WeaponArchetype]ArchetypeWeaponParams{
    .None    = { .Ranged, 25,  5.0, 2000, 0.375,  8, 1.5 },
    .Pistol  = { .Ranged, 25,  5.0, 2000, 0.375,  8, 1.5 },
    .Rifle   = { .Ranged, 50,  0.8, 2400, 0.720,  5, 3.2 },
    .Shotgun = { .Ranged, 22,  1.2, 1400, 0.136,  6, 2.5 },

    .Axe     = { .Melee,   0,  0,     0, 0,    0, 0   },
    .Knife   = { .Melee,   0,  0,     0, 0,    0, 0   },
    .Sword   = { .Melee,   0,  0,     0, 0,    0, 0   },
}

@(private = "file")
archetype_pellets :: proc(a: WeaponArchetype) -> (count: int, spread: f32) {
    #partial switch a {
    case .Shotgun: return 5, 0.30
    }
    return 1, 0
}

@(private = "file")
equipped_primary_archetype :: proc(w: ^World, holder_id: int) -> WeaponArchetype {
    if !world_has_component(w, holder_id, .Inventory) { return .None }
    inv := comp_get(w, holder_id, .Inventory, InventoryComp)
    eid := inv.equipped[int(EquipSlot.WeaponPrimary)]
    if eid == INVALID_ENTITY                         { return .None }
    if !world_has_component(w, eid, .Item)           { return .None }
    return comp_get(w, eid, .Item, ItemComp).weapon_archetype
}

weapon_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    wep_ids := world_query(w, query_mask(.Weapon))
    defer delete(wep_ids)
    for id in wep_ids {
        wp := comp_get(w, id, .Weapon, WeaponComp)
        if wp.cooldown > 0 { wp.cooldown -= dt }
        if wp.is_reloading {
            wp.reload_timer -= dt
            if wp.reload_timer <= 0 {
                wp.reload_timer  = 0
                wp.is_reloading  = false
                wp.ammo_current  = wp.ammo_max

                if world_has_component(w, w.player_id, .Equipment) {
                    if comp_get(w, w.player_id, .Equipment, EquipmentComp).weapon_entity_id == id {
                        play_sfx("reload_done")
                    }
                }
            }
        }
    }

    inv_ids := world_query(w, query_mask(.Inventory))
    defer delete(inv_ids)
    for holder_id in inv_ids {
        inv := comp_get(w, holder_id, .Inventory, InventoryComp)
        for i in 0..<EQUIP_SLOT_COUNT {
            eid := inv.equipped[i]
            if eid == INVALID_ENTITY                         { continue }
            if !world_has_component(w, eid, .Item)           { continue }
            mi := comp_get(w, eid, .Item, ItemComp)
            if !mi.is_melee                                     { continue }
            if mi.melee_cooldown > 0 { mi.melee_cooldown -= dt }
        }
    }

    fire_ids := world_query(w, query_mask(.Equipment, .InputState, .Transform))
    defer delete(fire_ids)

    for shooter_id in fire_ids {
        if world_has_component(w, shooter_id, .AimLock) { continue }

        input := comp_get(w, shooter_id, .InputState, InputStateComp)^

        archetype := equipped_primary_archetype(w, shooter_id)

        equip_snap := comp_get(w, shooter_id, .Equipment, EquipmentComp)^
        wid        := equip_snap.weapon_entity_id
        if world_is_valid(w, wid) && world_has_component(w, wid, .Weapon) &&
           world_has_component(w, shooter_id, .Inventory) {
            p  := ARCHETYPE_WEP_PARAMS[archetype]

            {
                inv  := comp_get(w, shooter_id, .Inventory, InventoryComp)
                peid := inv.equipped[int(EquipSlot.WeaponPrimary)]
                if peid != INVALID_ENTITY && world_has_component(w, peid, .Item) {
                    it := comp_get(w, peid, .Item, ItemComp)
                    if it.base_damage > 0      { p.damage           = it.base_damage }
                    if it.base_fire_rate > 0   { p.fire_rate        = it.base_fire_rate }
                    if it.base_ammo_max > 0    { p.ammo_max         = int(it.base_ammo_max) }
                    if it.base_reload_time > 0 { p.reload_time      = it.base_reload_time }
                    if it.base_proj_speed > 0  { p.projectile_speed = it.base_proj_speed }
                }
            }
            wp := comp_get(w, wid, .Weapon, WeaponComp)
            wp.type             = p.wep_type
            wp.damage           = p.damage
            wp.fire_rate        = p.fire_rate
            wp.projectile_speed = p.projectile_speed
            wp.projectile_life  = p.projectile_life
            wp.reload_time      = p.reload_time

            bonus_ammo_pct := f32(0)
            if world_has_component(w, shooter_id, .Stats) {
                bonus_ammo_pct = comp_get(w, shooter_id, .Stats, StatsComp).bonus_ammo_pct
            }
            new_ammo_max := int(f32(p.ammo_max) * (1.0 + bonus_ammo_pct)) if p.ammo_max > 0 else 0
            if new_ammo_max != wp.ammo_max {
                wp.ammo_max = new_ammo_max
                if new_ammo_max > 0 {
                    wp.ammo_current = clamp(wp.ammo_current, 0, new_ammo_max)
                }
            }
        }

        melee_handled := false
        if world_has_component(w, shooter_id, .Inventory) {
            inv          := comp_get(w, shooter_id, .Inventory, InventoryComp)
            melee_item_id := inv.equipped[int(EquipSlot.WeaponPrimary)]
            if melee_item_id != INVALID_ENTITY &&
               world_has_component(w, melee_item_id, .Item) {
                mi := comp_get(w, melee_item_id, .Item, ItemComp)
                if mi.is_melee {
                    melee_handled = true
                    if input.fire_pressed && mi.melee_cooldown <= 0 {
                        t_snap       := comp_get(w, shooter_id, .Transform, TransformComp)^
                        arc_angle    := t_snap.rotation
                        arc_pos      := t_snap.position
                        m_dmg        := mi.melee_damage
                        m_range      := mi.melee_range
                        m_spread     := mi.melee_spread
                        m_cd_max     := mi.melee_cooldown_max
                        owner_faction: u8
                        if world_has_component(w, shooter_id, .Collider) {
                            owner_faction = comp_get(w, shooter_id, .Collider, ColliderComp).faction
                        }
                        damage_mult:      f32 = 1.0
                        melee_dmg_mult:   f32 = 1.0
                        melee_range_mult: f32 = 1.0
                        melee_speed_mult: f32 = 1.0
                        if world_has_component(w, shooter_id, .Stats) {
                            st := comp_get(w, shooter_id, .Stats, StatsComp)
                            damage_mult      = st.damage_mult
                            melee_dmg_mult   = st.melee_damage_mult
                            melee_range_mult = st.melee_range_mult
                            melee_speed_mult = st.melee_speed_mult
                        }

                        play_sfx("melee_swing")
                        arc_id := world_create_entity(w)
                        comp_set(w, arc_id, .Transform, TransformComp{
                            position = arc_pos,
                        })
                        comp_set(w, arc_id, .MeleeArc, MeleeArcComp{
                            angle         = arc_angle,
                            arc_spread    = m_spread,
                            radius        = m_range * melee_range_mult,
                            damage        = m_dmg * damage_mult * melee_dmg_mult,
                            owner_id      = shooter_id,
                            owner_faction = owner_faction,
                            lifetime      = 0.18,
                        })
                        comp_set(w, arc_id, .SelfDestruct, SelfDestructComp{ timer = 0.18 })

                        mi_fresh := comp_get(w, melee_item_id, .Item, ItemComp)
                        mi_fresh.melee_cooldown = m_cd_max / melee_speed_mult
                    }
                }
            }
        }
        if melee_handled { continue }

        equip := comp_get(w, shooter_id, .Equipment, EquipmentComp)^
        wid    = equip.weapon_entity_id
        if !world_is_valid(w, wid)               { continue }
        if !world_has_component(w, wid, .Weapon) { continue }

        wp := comp_get(w, wid, .Weapon, WeaponComp)

        damage_mult:           f32 = 1.0
        fire_rate_mult:        f32 = 1.0
        reload_speed_mult:     f32 = 1.0
        projectile_speed_mult: f32 = 1.0
        ranged_blocked               := false
        if world_has_component(w, shooter_id, .Stats) {
            st := comp_get(w, shooter_id, .Stats, StatsComp)
            damage_mult           = st.damage_mult
            fire_rate_mult        = st.fire_rate_mult
            reload_speed_mult     = st.reload_speed_mult
            projectile_speed_mult = st.projectile_speed_mult
            ranged_blocked        = st.ranged_attacks_blocked
        }
        reload_div := reload_speed_mult

        if input.reload_pressed &&
           !wp.is_reloading     &&
           wp.ammo_max > 0      &&
           wp.ammo_current < wp.ammo_max {
            wp.is_reloading = true
            wp.reload_timer = wp.reload_time / reload_div
            play_sfx("reload_start")
            continue
        }

        if !input.fire_pressed { continue }
        if wp.type == .Melee   { continue }
        if wp.is_reloading     { continue }
        if wp.cooldown > 0     { continue }

        if wp.ammo_max > 0 && wp.ammo_current <= 0 {
            wp.is_reloading = true
            wp.reload_timer = wp.reload_time / reload_div
            play_sfx("empty_click")
            continue
        }

        if ranged_blocked { continue }

        wp_snap := wp^
        t_snap  := comp_get(w, shooter_id, .Transform, TransformComp)^

        owner_faction: u8
        if world_has_component(w, shooter_id, .Collider) {
            owner_faction = comp_get(w, shooter_id, .Collider, ColliderComp).faction
        }

        pierce_rem := i8(0)
        if world_has_component(w, shooter_id, .Stats) {
            pierce_rem = i8(clamp(comp_get(w, shooter_id, .Stats, StatsComp).bonus_pierce, 0, 10))
        }

        if rof := player_get_root_on_fire(w, shooter_id); rof != nil {
            rof.timer = rof.duration
        }

        pellet_count, pellet_spread := archetype_pellets(archetype)

        for p in 0..<pellet_count {
            angle_offset := f32(0)
            if pellet_count > 1 {
                t_ratio      := f32(p) / f32(pellet_count - 1)
                angle_offset  = pellet_spread * (t_ratio - 0.5)
            }
            fire_angle := t_snap.rotation + angle_offset
            dir := [3]f32{
                math.cos(fire_angle),
                math.sin(fire_angle),
                0,
            }
            origin := [3]f32{
                t_snap.position[0] + dir[0] * MUZZLE_OFFSET,
                t_snap.position[1] + dir[1] * MUZZLE_OFFSET,
                0,
            }

            proj_id := world_create_entity(w)
            comp_set(w, proj_id, .Transform, TransformComp{
                position = origin,
                rotation = fire_angle,
            })
            comp_set(w, proj_id, .Projectile, ProjectileComp{
                direction        = dir,
                speed            = wp_snap.projectile_speed * projectile_speed_mult,
                lifetime         = wp_snap.projectile_life,
                max_lifetime     = wp_snap.projectile_life,
                damage           = wp_snap.damage * damage_mult,
                owner_id         = shooter_id,
                owner_faction    = owner_faction,
                visual           = .Standard,
                pierce_remaining = pierce_rem,
            })
            comp_set(w, proj_id, .SelfDestruct, SelfDestructComp{
                timer = wp_snap.projectile_life,
            })
            comp_add(w, proj_id, .ProjectileTag)
        }

        play_sfx_at("pistol_shot", t_snap.position);

        emit_noise(
            { t_snap.position[0], t_snap.position[1], 0 },
            280,
            STEALTH_NOISE_LOUD,
        )

        wfresh := comp_get(w, wid, .Weapon, WeaponComp)
        if wp_snap.fire_rate > 0 {
            wfresh.cooldown = 1.0 / (wp_snap.fire_rate * fire_rate_mult)
        }

        if wp_snap.ammo_max > 0 {
            wfresh.ammo_current -= 1
            if wfresh.ammo_current <= 0 {
                wfresh.is_reloading = true
                wfresh.reload_timer = wp_snap.reload_time / reload_div
            }
        }
    }
}
