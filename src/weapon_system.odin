package main


import "core:math"
import cw "clockwork"


@(private = "file")
ArchetypeWeaponParams :: struct {
    wep_type:         cw.WeaponType,
    damage:           f32,
    fire_rate:        f32,
    projectile_speed: f32,
    projectile_life:  f32,
    ammo_max:         int,
    reload_time:      f32,
}

@(private = "file")
ARCHETYPE_WEP_PARAMS := [cw.WeaponArchetype]ArchetypeWeaponParams{

    .None    = { .Ranged, 25,  5.0, 500, 1.5,  8, 1.5 },
    .Pistol  = { .Ranged, 25,  5.0, 500, 1.5,  8, 1.5 },
    .Rifle   = { .Ranged, 50,  0.8, 720, 2.4,  5, 3.2 },
    .Shotgun = { .Ranged, 22,  1.2, 380, 0.5,  6, 2.5 },

    .Axe     = { .Melee,   0,  0,     0, 0,    0, 0   },
    .Knife   = { .Melee,   0,  0,     0, 0,    0, 0   },
    .Sword   = { .Melee,   0,  0,     0, 0,    0, 0   },
}


@(private = "file")
archetype_pellets :: proc(a: cw.WeaponArchetype) -> (count: int, spread: f32) {
    #partial switch a {
    case .Shotgun: return 5, 0.30
    }
    return 1, 0
}


@(private = "file")
equipped_primary_archetype :: proc(w: ^cw.World, holder_id: int) -> cw.WeaponArchetype {
    if !cw.world_has_component(w, holder_id, .Inventory) { return .None }
    inv := cw.world_get_inventory(w, holder_id)
    eid := inv.equipped[int(cw.EquipSlot.WeaponPrimary)]
    if eid == cw.INVALID_ENTITY                         { return .None }
    if !cw.world_has_component(w, eid, .Item)           { return .None }
    return cw.world_get_item(w, eid).weapon_archetype
}

weapon_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }


    wep_ids := cw.world_query(w, cw.query_mask(.Weapon))
    defer delete(wep_ids)
    for id in wep_ids {
        wp := cw.world_get_weapon_data(w, id)
        if wp.cooldown > 0 { wp.cooldown -= dt }
        if wp.is_reloading {
            wp.reload_timer -= dt
            if wp.reload_timer <= 0 {
                wp.reload_timer  = 0
                wp.is_reloading  = false
                wp.ammo_current  = wp.ammo_max

                if cw.world_has_component(w, w.player_id, .Equipment) {
                    if cw.world_get_equipment(w, w.player_id).weapon_entity_id == id {
                        play_sfx("reload_done")
                    }
                }
            }
        }
    }


    inv_ids := cw.world_query(w, cw.query_mask(.Inventory))
    defer delete(inv_ids)
    for holder_id in inv_ids {
        inv := cw.world_get_inventory(w, holder_id)
        for i in 0..<cw.EQUIP_SLOT_COUNT {
            eid := inv.equipped[i]
            if eid == cw.INVALID_ENTITY                         { continue }
            if !cw.world_has_component(w, eid, .Item)           { continue }
            mi := cw.world_get_item(w, eid)
            if !mi.is_melee                                     { continue }
            if mi.melee_cooldown > 0 { mi.melee_cooldown -= dt }
        }
    }


    fire_ids := cw.world_query(w, cw.query_mask(.Equipment, .InputState, .Transform))
    defer delete(fire_ids)

    for shooter_id in fire_ids {

        if cw.world_has_component(w, shooter_id, .AimLock) { continue }

        input := cw.world_get_input(w, shooter_id)^


        archetype := equipped_primary_archetype(w, shooter_id)

        equip_snap := cw.world_get_equipment(w, shooter_id)^
        wid        := equip_snap.weapon_entity_id
        if cw.world_is_valid(w, wid) && cw.world_has_component(w, wid, .Weapon) &&
           cw.world_has_component(w, shooter_id, .Inventory) {
            p  := ARCHETYPE_WEP_PARAMS[archetype]

            {
                inv  := cw.world_get_inventory(w, shooter_id)
                peid := inv.equipped[int(cw.EquipSlot.WeaponPrimary)]
                if peid != cw.INVALID_ENTITY && cw.world_has_component(w, peid, .Item) {
                    it := cw.world_get_item(w, peid)
                    if it.base_damage > 0      { p.damage           = it.base_damage }
                    if it.base_fire_rate > 0   { p.fire_rate        = it.base_fire_rate }
                    if it.base_ammo_max > 0    { p.ammo_max         = int(it.base_ammo_max) }
                    if it.base_reload_time > 0 { p.reload_time      = it.base_reload_time }
                    if it.base_proj_speed > 0  { p.projectile_speed = it.base_proj_speed }
                }
            }
            wp := cw.world_get_weapon_data(w, wid)
            wp.type             = p.wep_type
            wp.damage           = p.damage
            wp.fire_rate        = p.fire_rate
            wp.projectile_speed = p.projectile_speed
            wp.projectile_life  = p.projectile_life
            wp.reload_time      = p.reload_time

            bonus_ammo_pct := f32(0)
            if cw.world_has_component(w, shooter_id, .Stats) {
                bonus_ammo_pct = cw.world_get_stats(w, shooter_id).bonus_ammo_pct
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
        if cw.world_has_component(w, shooter_id, .Inventory) {
            inv          := cw.world_get_inventory(w, shooter_id)
            melee_item_id := inv.equipped[int(cw.EquipSlot.WeaponPrimary)]
            if melee_item_id != cw.INVALID_ENTITY &&
               cw.world_has_component(w, melee_item_id, .Item) {
                mi := cw.world_get_item(w, melee_item_id)
                if mi.is_melee {
                    melee_handled = true
                    if input.fire_pressed && mi.melee_cooldown <= 0 {

                        t_snap       := cw.world_get_transform(w, shooter_id)^
                        arc_angle    := t_snap.rotation
                        arc_pos      := t_snap.position
                        m_dmg        := mi.melee_damage
                        m_range      := mi.melee_range
                        m_spread     := mi.melee_spread
                        m_cd_max     := mi.melee_cooldown_max
                        owner_faction: u8
                        if cw.world_has_component(w, shooter_id, .Collider) {
                            owner_faction = cw.world_get_collider(w, shooter_id).faction
                        }
                        damage_mult:      f32 = 1.0
                        melee_dmg_mult:   f32 = 1.0
                        melee_range_mult: f32 = 1.0
                        melee_speed_mult: f32 = 1.0
                        if cw.world_has_component(w, shooter_id, .Stats) {
                            st := cw.world_get_stats(w, shooter_id)
                            damage_mult      = st.damage_mult
                            melee_dmg_mult   = st.melee_damage_mult
                            melee_range_mult = st.melee_range_mult
                            melee_speed_mult = st.melee_speed_mult
                        }

                        play_sfx("melee_swing")
                        arc_id := cw.world_create_entity(w)
                        cw.world_set_transform(w, arc_id, cw.TransformComp{
                            position = arc_pos,
                        })
                        cw.world_set_melee_arc(w, arc_id, cw.MeleeArcComp{
                            angle         = arc_angle,
                            arc_spread    = m_spread,
                            radius        = m_range * melee_range_mult,
                            damage        = m_dmg * damage_mult * melee_dmg_mult,
                            owner_id      = shooter_id,
                            owner_faction = owner_faction,
                            lifetime      = 0.18,
                        })
                        cw.world_set_self_destruct(w, arc_id, cw.SelfDestructComp{ timer = 0.18 })


                        mi_fresh := cw.world_get_item(w, melee_item_id)
                        mi_fresh.melee_cooldown = m_cd_max / melee_speed_mult
                    }
                }
            }
        }
        if melee_handled { continue }


        equip := cw.world_get_equipment(w, shooter_id)^
        wid    = equip.weapon_entity_id
        if !cw.world_is_valid(w, wid)               { continue }
        if !cw.world_has_component(w, wid, .Weapon) { continue }

        wp := cw.world_get_weapon_data(w, wid)

        damage_mult:           f32 = 1.0
        fire_rate_mult:        f32 = 1.0
        reload_speed_mult:     f32 = 1.0
        projectile_speed_mult: f32 = 1.0
        ranged_blocked               := false
        if cw.world_has_component(w, shooter_id, .Stats) {
            st := cw.world_get_stats(w, shooter_id)
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
        t_snap  := cw.world_get_transform(w, shooter_id)^

        owner_faction: u8
        if cw.world_has_component(w, shooter_id, .Collider) {
            owner_faction = cw.world_get_collider(w, shooter_id).faction
        }

        pierce_rem := i8(0)
        if cw.world_has_component(w, shooter_id, .Stats) {
            pierce_rem = i8(clamp(cw.world_get_stats(w, shooter_id).bonus_pierce, 0, 10))
        }


        if rof := player_get_root_on_fire(w, shooter_id); rof != nil {
            rof.timer = rof.duration
        }


        pellet_count, pellet_spread := archetype_pellets(archetype)

        spawn_offset :: PLAYER_RADIUS + 6

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
                t_snap.position[0] + dir[0] * spawn_offset,
                t_snap.position[1] + dir[1] * spawn_offset,
                0,
            }

            proj_id := cw.world_create_entity(w)
            cw.world_set_transform(w, proj_id, cw.TransformComp{
                position = origin,
                rotation = fire_angle,
            })
            cw.world_set_projectile(w, proj_id, cw.ProjectileComp{
                direction        = dir,
                speed            = wp_snap.projectile_speed * projectile_speed_mult,
                lifetime         = wp_snap.projectile_life,
                max_lifetime     = wp_snap.projectile_life,
                damage           = wp_snap.damage * damage_mult,
                owner_id         = shooter_id,
                owner_faction    = owner_faction,
                visual           = .Standard if damage_mult > 1.0 else .Smoke,
                pierce_remaining = pierce_rem,
            })
            cw.world_set_self_destruct(w, proj_id, cw.SelfDestructComp{
                timer = wp_snap.projectile_life,
            })
            cw.world_set_projectile_tag(w, proj_id)
        }

        play_sfx("shoot")


        emit_noise(
            { t_snap.position[0], t_snap.position[1], 0 },
            280,
            STEALTH_NOISE_LOUD,
        )


        wfresh := cw.world_get_weapon_data(w, wid)
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
