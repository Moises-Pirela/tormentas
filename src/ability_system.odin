package main

import "core:math"
import "core:math/rand"
import cw "clockwork"

AbilityDef :: struct {
    name:       string,
    desc:       string,
    is_passive: bool,
    cd_max:     f32,  // cooldown in seconds (0 for passives)
    param1:     f32,  // primary effect value
    param2:     f32,  // secondary effect value
}

ABILITY_DEFS := [cw.AbilityType]AbilityDef{
    .None = {},

    // ── Active abilities ────────────────────────────────────────────────────
    .QuickDraw      = { name = "Quick Draw",      desc = "Fire a rapid burst of shots in quick succession.",                    cd_max = 8,  param1 = 3,    param2 = 0.08  },
    .FanTheHammer   = { name = "Fan the Hammer",   desc = "Unleash a spray of shots in a wide cone.",                           cd_max = 10, param1 = 5,    param2 = 0.698 },
    .BulletRain     = { name = "Bullet Rain",      desc = "Full-auto fire for several seconds with unlimited ammo.",             cd_max = 18, param1 = 16,   param2 = 0.125 },
    .DoubleTap      = { name = "Double Tap",       desc = "Fire two shots; the second hits harder.",                            cd_max = 5,  param1 = 1.2                  },
    .MagDump        = { name = "Mag Dump",         desc = "Spend ammo in a devastating rapid burst.",                           cd_max = 12, param1 = 5,    param2 = 0.8   },
    .LastStand      = { name = "Last Stand",       desc = "Empty your magazine at once — each bullet hits harder.",             cd_max = 22, param1 = 8,    param2 = 1.5   },
    .Deadeye        = { name = "Deadeye",          desc = "Draw and fire a single devastating round.",                          cd_max = 12, param1 = 3.0                  },
    .HeavyCalibur   = { name = "Heavy Caliber",    desc = "Fire a round that punches through multiple enemies.",                cd_max = 10, param1 = 2,    param2 = 0.85  },
    .DeathShot      = { name = "Death Shot",       desc = "Charge up and release a shot of devastating force.",                 cd_max = 30, param1 = 10.0, param2 = 1.2   },
    .CorruptRound   = { name = "Corrupt Round",    desc = "Infecting shot that shreds armor and deals corruption over time.",   cd_max = 14, param1 = 0.20, param2 = 4.0   },
    .MarkedTarget   = { name = "Marked Target",    desc = "Mark an enemy — all damage against it is amplified.",               cd_max = 16, param1 = 0.20                 },
    .Execute        = { name = "Execute",          desc = "Kill-threshold shot against a grievously wounded enemy.",            cd_max = 20, param1 = 0.25                 },
    .Headshot       = { name = "Headshot",         desc = "A precisely aimed shot that stuns the target.",                     cd_max = 10, param1 = 0.5                   },
    .TrickShot      = { name = "Trick Shot",       desc = "Ricochet round that punches through every enemy in its path.",      cd_max = 12, param1 = 3                     },
    .IronWill       = { name = "Iron Will",        desc = "Steel yourself, immediately recovering health.",                    cd_max = 22, param1 = 10                    },
    .InstinctReload = { name = "Instinct Reload",  desc = "Instantly reload all equipped weapons.",                            cd_max = 20                                 },
    .DevilsDance    = { name = "Devil's Dance",    desc = "Your next dodge roll fires a burst of shots in every direction.",   cd_max = 18, param1 = 6                     },

    .SteadyAim      = { name = "Steady Aim",       desc = "Passive: bonus damage while standing still.",                       is_passive = true, param1 = 0.05  },
    .HuntersReflex  = { name = "Hunter's Reflex",  desc = "Passive: reduces your dodge cooldown.",                             is_passive = true, param1 = 0.08  },
    .Deathwish      = { name = "Deathwish",        desc = "Passive: damage surge when below 30% HP.",                         is_passive = true, param1 = 0.30  },
    .EagleEye       = { name = "Eagle Eye",        desc = "Passive: wider fog vision. Deadeye and Death Shot gain crit chance.", is_passive = true, param1 = 60, param2 = 0.05 },
}

ability_slot_to_equip :: proc(slot_idx: int) -> cw.EquipSlot {
    switch slot_idx {
    case 0: return .Ability1
    case 1: return .Ability2
    case 2: return .Ability3
    case 3: return .Ability4
    }
    return .Ability1
}

player_ability_in_slot :: proc(w: ^cw.World, player_id: int, slot_idx: int) -> cw.AbilityType {
    if !cw.world_has_component(w, player_id, .Inventory) { return .None }
    inv  := cw.world_get_inventory(w, player_id)
    eq   := ability_slot_to_equip(slot_idx)
    iid  := inv.equipped[eq]
    if !cw.world_is_valid(w, iid) { return .None }
    if !cw.world_has_component(w, iid, .Item) { return .None }
    return cw.world_get_item(w, iid).ability_type
}

player_has_ability :: proc(w: ^cw.World, player_id: int, at: cw.AbilityType) -> bool {
    if at == .None { return false }
    for i in 0..<cw.ABILITY_SLOT_COUNT {
        if player_ability_in_slot(w, player_id, i) == at { return true }
    }
    return false
}

@(private = "file")
ability_spawn_projectile :: proc(w: ^cw.World, shooter_id: int,
                                  dir: [3]f32, damage_mult: f32, pierce: i8 = 0) {
    if !cw.world_has_component(w, shooter_id, .Equipment) { return }
    equip := cw.world_get_equipment(w, shooter_id)^
    wid   := equip.weapon_entity_id
    if !cw.world_is_valid(w, wid)               { return }
    if !cw.world_has_component(w, wid, .Weapon) { return }

    wp_snap := cw.world_get_weapon_data(w, wid)^
    t_snap  := cw.world_get_transform(w, shooter_id)^
    resolved_damage_mult:      f32 = 1.0
    resolved_proj_speed_mult:  f32 = 1.0
    if cw.world_has_component(w, shooter_id, .Stats) {
        st := cw.world_get_stats(w, shooter_id)
        resolved_damage_mult     = st.damage_mult
        resolved_proj_speed_mult = st.projectile_speed_mult
    }

    owner_faction: u8
    if cw.world_has_component(w, shooter_id, .Collider) {
        owner_faction = cw.world_get_collider(w, shooter_id).faction
    }

    eff_pierce := pierce

    spawn_offset :: PLAYER_RADIUS + 6
    origin := [3]f32{
        t_snap.position[0] + dir[0] * spawn_offset,
        t_snap.position[1] + dir[1] * spawn_offset,
        0,
    }

    proj_id := cw.world_create_entity(w)
    cw.world_set_transform(w, proj_id, cw.TransformComp{ position = origin })
    cw.world_set_projectile(w, proj_id, cw.ProjectileComp{
        direction        = dir,
        speed            = wp_snap.projectile_speed * resolved_proj_speed_mult,
        lifetime         = wp_snap.projectile_life,
        max_lifetime     = wp_snap.projectile_life,
        damage           = wp_snap.damage * damage_mult * resolved_damage_mult,
        owner_id         = shooter_id,
        owner_faction    = owner_faction,
        visual           = .Standard,
        pierce_remaining = eff_pierce,
    })
    cw.world_set_self_destruct(w, proj_id, cw.SelfDestructComp{ timer = wp_snap.projectile_life })
    cw.world_set_projectile_tag(w, proj_id)
    play_sfx("shoot")
}

MAX_SPAWNS :: 24

ability_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }
    if !cw.world_is_valid(w, w.player_id)                { return }
    if !cw.world_has_component(w, w.player_id, .Ability) { return }

    id := w.player_id

    if cw.world_has_component(w, id, .Respawn) &&
       cw.world_get_respawn(w, id).timer > 0 { return }

    ab_snap := cw.world_get_ability(w, id)^
    input   := cw.world_get_input(w, id)^
    t_snap  := cw.world_get_transform(w, id)^

    cooldown_mult: f32 = 1.0
    special_crit:  f32 = 0
    if cw.world_has_component(w, id, .Stats) {
        st := cw.world_get_stats(w, id)
        if st.active_abilities_blocked { return }
        cooldown_mult = st.ability_cooldown_mult
        special_crit  = st.special_ability_crit
    }
    dt_scaled := dt * cooldown_mult

    spawn_dirs  : [MAX_SPAWNS][3]f32
    spawn_mults : [MAX_SPAWNS]f32
    spawn_pierce: [MAX_SPAWNS]i8
    spawn_count := 0

    facing := [3]f32{ math.cos(t_snap.rotation), math.sin(t_snap.rotation), 0 }

    inputs_pressed := [cw.ABILITY_SLOT_COUNT]bool{
        input.skill1_pressed,
        input.skill2_pressed,
        input.skill3_pressed,
        input.skill4_pressed,
    }

    enqueue :: #force_inline proc(dirs: ^[MAX_SPAWNS][3]f32, mults: ^[MAX_SPAWNS]f32,
                                   pierces: ^[MAX_SPAWNS]i8, cnt: ^int,
                                   dir: [3]f32, mult: f32, pierce: i8 = 0) {
        if cnt^ >= MAX_SPAWNS { return }
        dirs[cnt^]    = dir
        mults[cnt^]   = mult
        pierces[cnt^] = pierce
        cnt^ += 1
    }

    for slot_idx in 0..<cw.ABILITY_SLOT_COUNT {
        ab_type := player_ability_in_slot(w, id, slot_idx)
        if ab_type == .None { continue }
        if ABILITY_DEFS[ab_type].is_passive { continue }  // passives never activate

        def    := &ABILITY_DEFS[ab_type]
        cd_max := def.cd_max
        st     := &ab_snap.slots[slot_idx]

        if st.cooldown > 0 { st.cooldown = max(st.cooldown - dt_scaled, 0) }

        if st.burst_shots > 0 {
            st.burst_timer -= dt
            if st.burst_timer <= 0 {
                mult: f32 = 1.0
                #partial switch ab_type {
                case .MagDump:   mult = def.param2
                case .LastStand: mult = def.param2
                }
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count, facing, mult)
                st.burst_shots -= 1
                interval: f32
                #partial switch ab_type {
                case .QuickDraw, .BulletRain: interval = def.param2
                case: interval = 0.07
                }
                st.burst_timer = interval if st.burst_shots > 0 else 0
            }
        }

        if ab_type == .DeathShot && st.charging {
            st.charge_timer -= dt
            if st.charge_timer <= 0 {
                st.charging = false
                crit_roll  := rand.float32() < special_crit
                mult       := def.param1 * (2.0 if crit_roll else 1.0)
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count, facing, mult)
                play_sfx("ability_quickdraw")
            }
        }

        if ab_type == .DevilsDance && st.dance_ready && input.dodge_pressed {
            st.dance_ready = false
            n := int(def.param1)
            for i in 0..<n {
                angle := f32(i) * (2.0 * math.PI / f32(n))
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count,
                    [3]f32{ math.cos(angle), math.sin(angle), 0 }, 0.9)
            }
            play_sfx("ability_fan")
        }

        if inputs_pressed[slot_idx] && st.cooldown <= 0 {
            switch ab_type {

            case .QuickDraw:
                if st.burst_shots == 0 {
                    st.cooldown    = cd_max
                    st.burst_shots = int(def.param1)
                    st.burst_timer = 0
                    play_sfx("ability_quickdraw")
                }

            case .FanTheHammer:
                st.cooldown = cd_max
                n       := int(def.param1)
                spread  := def.param2
                step    := spread / f32(max(n - 1, 1))
                start_a := t_snap.rotation - spread * 0.5
                for i in 0..<n {
                    a := start_a + f32(i) * step
                    enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count,
                        [3]f32{ math.cos(a), math.sin(a), 0 }, 0.7)
                }
                play_sfx("ability_fan")

            case .BulletRain:
                if st.burst_shots == 0 {
                    st.cooldown    = cd_max
                    st.burst_shots = int(def.param1)
                    st.burst_timer = 0
                    play_sfx("ability_quickdraw")
                }

            case .DoubleTap:
                st.cooldown = cd_max
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count, facing, 1.0)
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count, facing, def.param1)
                play_sfx("shoot")

            case .MagDump:
                if st.burst_shots == 0 {
                    st.cooldown    = cd_max
                    st.burst_shots = int(def.param1)
                    st.burst_timer = 0
                    play_sfx("ability_quickdraw")
                }

            case .LastStand:
                if st.burst_shots == 0 {
                    st.cooldown    = cd_max
                    st.burst_shots = int(def.param1)
                    st.burst_timer = 0
                    play_sfx("ability_quickdraw")
                }

            case .Deadeye:
                st.cooldown = cd_max
                crit_roll   := rand.float32() < special_crit
                mult        := def.param1 * (2.0 if crit_roll else 1.0)
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count, facing, mult)
                play_sfx("ability_quickdraw")

            case .HeavyCalibur:
                st.cooldown = cd_max
                pierce_val  := i8(min(int(def.param1), 120))
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count, facing, 1.2, pierce_val)
                play_sfx("ability_quickdraw")

            case .DeathShot:
                if !st.charging {
                    st.charging     = true
                    st.charge_timer = def.param2
                    st.cooldown     = cd_max
                }

            case .CorruptRound:
                st.cooldown = cd_max
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count, facing, 0.9)
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count, facing, 0.9)
                play_sfx("ability_fan")

            case .MarkedTarget:
                st.cooldown = cd_max
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count,
                    facing, 1.0 + def.param1)
                play_sfx("ability_quickdraw")

            case .Execute:
                st.cooldown = cd_max
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count,
                    facing, 1.0 / def.param1)   // e.g. 25% threshold → 4× damage
                play_sfx("ability_quickdraw")

            case .Headshot:
                st.cooldown = cd_max
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count, facing, 1.5)
                play_sfx("ability_quickdraw")

            case .TrickShot:
                st.cooldown = cd_max
                pierce_val  := i8(min(int(def.param1), 120))
                enqueue(&spawn_dirs, &spawn_mults, &spawn_pierce, &spawn_count, facing, 1.0, pierce_val)
                play_sfx("ability_quickdraw")

            case .IronWill:
                st.cooldown = cd_max
                if cw.world_has_component(w, id, .Health) {
                    h := cw.world_get_health(w, id)
                    h.current = min(h.current + def.param1, h.max)
                }
                play_sfx("levelup")

            case .InstinctReload:
                st.cooldown = cd_max
                if cw.world_has_component(w, id, .Equipment) {
                    equip := cw.world_get_equipment(w, id)
                    wid   := equip.weapon_entity_id
                    if cw.world_is_valid(w, wid) && cw.world_has_component(w, wid, .Weapon) {
                        wcomp              := cw.world_get_weapon_data(w, wid)
                        wcomp.ammo_current  = wcomp.ammo_max
                        wcomp.is_reloading  = false
                        wcomp.reload_timer  = 0
                    }
                }
                play_sfx("reload")

            case .DevilsDance:
                if !st.dance_ready {
                    st.dance_ready = true
                    st.cooldown    = cd_max
                    play_sfx("ability_fan")
                }

            case .SteadyAim, .HuntersReflex, .Deathwish, .EagleEye, .None:
            }
        }
    }

    for i in 0..<spawn_count {
        ability_spawn_projectile(w, id, spawn_dirs[i], spawn_mults[i], spawn_pierce[i])
    }

    ab_live := cw.world_get_ability(w, id)
    ab_live.slots = ab_snap.slots
}
