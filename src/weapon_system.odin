package main

// =============================================================================
// WEAPON SYSTEM
//
// Runs each Update tick for every entity that has Equipment + InputState:
//   1. Ticks down cooldowns and reload timers on all live weapon entities.
//      When a reload timer expires the magazine is fully replenished.
//   2. Ticks melee_cooldown on any melee weapon item in an equip slot.
//   3. On R key: starts a reload if the weapon is not already reloading and
//      the magazine is not already full.
//   4. On fire input:
//      a. If WeaponPrimary slot holds a melee item: spawn a MeleeArcComp
//         centred on the shooter's facing angle; skip ranged fire.
//      b. Otherwise: checks ammo, reloading state, and cooldown.
//         - If ammo_max > 0 and ammo is empty: auto-starts reload instead.
//         - If ranged + cooldown ready + not reloading: spawns a projectile,
//           decrements ammo, resets cooldown, and auto-reloads if now empty.
//
// Pointer safety: all component data is snapshot-copied into locals before
// world_create_entity is called, since that may resize the backing arrays.
// The weapon pointer is re-fetched after the spawn for write-back.
// =============================================================================

import "core:math"
import cw "clockwork"

weapon_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }

    // 1. Tick cooldowns + reload timers on weapon entities
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
                // Only play reload_done for the player's weapon (AI weapons don't reload)
                if cw.world_has_component(w, w.player_id, .Equipment) {
                    if cw.world_get_equipment(w, w.player_id).weapon_entity_id == id {
                        play_sfx("reload_done")
                    }
                }
            }
        }
    }

    // 2. Tick melee_cooldown on equipped melee items
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

    // 3. Process fire / reload input
    fire_ids := cw.world_query(w, cw.query_mask(.Equipment, .InputState, .Transform))
    defer delete(fire_ids)

    for shooter_id in fire_ids {
        input := cw.world_get_input(w, shooter_id)^

        // ----------------------------------------------------------------
        // 3a. Melee weapon override — if WeaponPrimary slot holds a melee
        //     item, LMB fires a melee arc and ranged fire is suppressed.
        // ----------------------------------------------------------------
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
                        // Snapshot needed data before potential array resize
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
                        damage_mult: f32 = 1.0
                        if cw.world_has_component(w, shooter_id, .Stats) {
                            damage_mult = cw.world_get_stats(w, shooter_id).damage_mult
                        }

                        play_sfx("melee_swing")
                        arc_id := cw.world_create_entity(w)
                        cw.world_set_transform(w, arc_id, cw.TransformComp{
                            position = arc_pos,
                        })
                        cw.world_set_melee_arc(w, arc_id, cw.MeleeArcComp{
                            angle         = arc_angle,
                            arc_spread    = m_spread,
                            radius        = m_range,
                            damage        = m_dmg * damage_mult,
                            owner_id      = shooter_id,
                            owner_faction = owner_faction,
                            lifetime      = 0.18,
                        })
                        cw.world_set_self_destruct(w, arc_id, cw.SelfDestructComp{ timer = 0.18 })

                        // Re-fetch item pointer after potential resize and reset cooldown
                        mi_fresh := cw.world_get_item(w, melee_item_id)
                        mi_fresh.melee_cooldown = m_cd_max
                    }
                }
            }
        }
        if melee_handled { continue }

        // ----------------------------------------------------------------
        // 3b. Ranged weapon fire
        // ----------------------------------------------------------------
        equip := cw.world_get_equipment(w, shooter_id)^
        wid   := equip.weapon_entity_id
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

        // Snapshot everything before world_create_entity may resize arrays
        wp_snap := wp^
        t_snap  := cw.world_get_transform(w, shooter_id)^

        owner_faction: u8
        if cw.world_has_component(w, shooter_id, .Collider) {
            owner_faction = cw.world_get_collider(w, shooter_id).faction
        }

        pierce_rem:  i8  = 0
        if ranged_blocked { continue }

        // Timelock: root + projectile speed/damage mods
        if rof := player_get_root_on_fire(w, shooter_id); rof != nil {
            rof.timer = rof.duration
        }

        dir := [3]f32{
            math.cos(t_snap.rotation),
            math.sin(t_snap.rotation),
            0,
        }

        spawn_offset :: PLAYER_RADIUS + 6
        origin := [3]f32{
            t_snap.position[0] + dir[0] * spawn_offset,
            t_snap.position[1] + dir[1] * spawn_offset,
            0,
        }

        proj_id := cw.world_create_entity(w)
        cw.world_set_transform(w, proj_id, cw.TransformComp{
            position = origin,
            rotation = t_snap.rotation,
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
        play_sfx("shoot")

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
