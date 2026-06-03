package main


import "core:math"
import cw "clockwork"


AbilityTrait :: enum u8 {
    None,
    Strength,
    Dexterity,
    Science,
}

AbilityTagFlag :: enum u8 {
    Projectile,
    Melee,
    Attack,
    Ranged,
    Hit,
    Hazard,
    Spell,
    Trap,
    Minion,
}
AbilityTags :: distinct bit_set[AbilityTagFlag; u16]

AbilityDamageSource :: enum u8 {
    Weapon,
    Science,
}

SCIENCE_DAMAGE_PER_POINT :: f32(5.0)
ABILITY_MAX_LEVEL        :: 5


AbilityExecKind :: enum u8 {
    None,
    FireProjectile,
    BurstFire,
    FanFire,
    ChargeFire,
    SpinChannel,
    PrimeDodge,
    AoEBlast,
    ThrowGrenade,
    HealSelf,
    InstantReload,
    BuffArmor,
    CooldownReset,

    ConeBlast,
    DetonateStatus,
    HomingVolley,
    PlaceTrap,
    BuffStats,
}


SPIN_CHANNEL_DURATION :: f32(1.2)


SPIN_ANGULAR_VELOCITY :: f32(20.0)

MAX_ABILITY_EXECS :: 4

AbilityExecComp :: struct {
    kind:             AbilityExecKind,
    p1:               f32,
    p2:               f32,

    status:           cw.StatusEffectType,
    status_dur:       f32,
    status_str:       f32,

    damage_amp_mult:  f32,
    damage_amp_dur:   f32,

    spread_on_poison_death: bool,

    reset_cd_on_kill: bool,

    blink_on_land:    bool,
}


AbilityDef :: struct {
    name:          string,
    desc:          string,
    trait:         AbilityTrait,
    tags:          AbilityTags,
    damage_source: AbilityDamageSource,
    cd_max:        f32,
    level_scale:   f32,
    energy_cost:   f32,
    execs:      [MAX_ABILITY_EXECS]AbilityExecComp,
    exec_count: int,
}


ABILITY_DEFS := [cw.AbilityType]AbilityDef{

    .None = {},


    .CadavericSpasm = {
        name = "Cadaveric Spasm",
        desc = "Channel galvanic energy through your limbs — spin furiously, striking all nearby enemies every 0.15 s for 1.2 s. Each hit briefly stuns.",
        trait = .Strength, tags = { .Melee, .Attack, .Hit },
        damage_source = .Weapon,
        cd_max = 10, level_scale = 0.18, energy_cost = 25, exec_count = 1,
        execs = { {
            kind       = .SpinChannel,
            p1         = 80,
            p2         = 0.15,
            status     = .Stun,
            status_dur = 0.25,
            status_str = 1.0,
        }, {}, {}, {} },
    },

    .OsseousSlam = {
        name = "Osseous Slam",
        desc = "Drive a reinforced bone strut into the ground, sending a cone of calcified shrapnel forward. Enemies in the cone are rooted.",
        trait = .Strength, tags = { .Melee, .Attack, .Hit },
        damage_source = .Weapon,
        cd_max = 8, level_scale = 0.20, energy_cost = 20, exec_count = 1,
        execs = { {
            kind       = .ConeBlast,
            p1         = 0.61,
            p2         = 200,
            status     = .Root,
            status_dur = 1.5,
            status_str = 1.0,
        }, {}, {}, {} },
    },

    .NecroticSurge = {
        name = "Necrotic Surge",
        desc = "Stimulate the regenerative glands — for 10 s, each kill restores a measure of vitality.",
        trait = .Strength, tags = { .Spell },
        damage_source = .Weapon,
        cd_max = 25, level_scale = 0.15, energy_cost = 30, exec_count = 1,

        execs = { { kind = .BuffStats, p1 = 0, p2 = 10.0 }, {}, {}, {} },
    },

    .CrushingGrip = {
        name = "Crushing Grip",
        desc = "Lunge forward and seize the nearest enemy in a crushing hold. Deals burst damage and stuns. Killing a stunned enemy resets this ability.",
        trait = .Strength, tags = { .Melee, .Attack, .Hit },
        damage_source = .Weapon,
        cd_max = 6, level_scale = 0.22, energy_cost = 15, exec_count = 1,
        execs = { {
            kind             = .AoEBlast,
            p1               = 90,
            p2               = 1.4,
            status           = .Stun,
            status_dur       = 0.6,
            status_str       = 1.0,
            reset_cd_on_kill = true,
        }, {}, {}, {} },
    },


    .RapidDischarge = {
        name = "Rapid Discharge",
        desc = "Bypass the magazine — fire 6 rounds from the chamber in rapid succession.",
        trait = .Dexterity, tags = { .Projectile, .Attack, .Ranged, .Hit },
        damage_source = .Weapon,
        cd_max = 8, level_scale = 0.12, energy_cost = 20, exec_count = 1,
        execs = { { kind = .BurstFire, p1 = 6, p2 = 0.06 }, {}, {}, {} },
    },

    .DeliberateRound = {
        name = "Deliberate Round",
        desc = "Hold to compress the propellant charge to maximum. Release a single high-velocity shot with devastating force.",
        trait = .Dexterity, tags = { .Projectile, .Attack, .Ranged, .Hit },
        damage_source = .Weapon,
        cd_max = 12, level_scale = 0.25, energy_cost = 25, exec_count = 1,
        execs = { { kind = .ChargeFire, p1 = 3.5, p2 = 1.2 }, {}, {}, {} },
    },

    .EtherVial = {
        name = "Ether Vial",
        desc = "Hurl a flask of ether compound to the cursor. On contact it detonates, teleporting you to the landing point and leaving a Slow cloud.",
        trait = .Dexterity, tags = { .Spell, .Hazard, .Trap },
        damage_source = .Science,
        cd_max = 18, level_scale = 0.10, energy_cost = 30, exec_count = 1,
        execs = { {
            kind           = .ThrowGrenade,
            p1             = 80,
            p2             = 4.0,
            blink_on_land  = true,
            status         = .Slow,
            status_dur     = 3.0,
            status_str     = 0.5,
        }, {}, {}, {} },
    },

    .Indexed = {
        name = "Indexed",
        desc = "Tag a target with a tracer round. For 4 s all damage dealt to that target is amplified by 60%.",
        trait = .Dexterity, tags = { .Projectile, .Attack, .Ranged, .Hit },
        damage_source = .Weapon,
        cd_max = 14, level_scale = 0.08, energy_cost = 20, exec_count = 1,
        execs = { {
            kind             = .FireProjectile,
            p1               = 0.6,
            p2               = 0,
            damage_amp_mult  = 1.6,
            damage_amp_dur   = 4.0,
        }, {}, {}, {} },
    },


    .VetriolFlask = {
        name = "Vetriol Flask",
        desc = "Hurl a flask of vitriol acid to the cursor; it explodes on landing and leaves a corrosive Poison cloud.",
        trait = .Science, tags = { .Spell, .Hazard, .Trap },
        damage_source = .Science,
        cd_max = 15, level_scale = 0.18, energy_cost = 25, exec_count = 1,
        execs = { {
            kind       = .ThrowGrenade,
            p1         = 110,
            p2         = 5.0,
            status     = .Poison,
            status_dur = 4.0,
            status_str = 1.0,
        }, {}, {}, {} },
    },

    .CarbolicSpray = {
        name = "Carbolic Spray",
        desc = "Pressurised carbolic acid and coal-tar spray — coats enemies in a forward arc with Oiled and Poison.",
        trait = .Science, tags = { .Spell, .Hazard, .Hit },
        damage_source = .Science,
        cd_max = 10, level_scale = 0.14, energy_cost = 20, exec_count = 2,
        execs = { {

            kind       = .ConeBlast,
            p1         = 0.79,
            p2         = 160,
            status     = .Oiled,
            status_dur = 4.0,
            status_str = 1.0,
        }, {

            kind       = .ConeBlast,
            p1         = 0.79,
            p2         = 160,
            status     = .Poison,
            status_dur = 3.0,
            status_str = 1.0,
        }, {}, {} },
    },

    .Contagion = {
        name = "Contagion",
        desc = "Release a spore cloud — AoE Poison pulse. Enemies that die while infected spread Poison to their neighbours.",
        trait = .Science, tags = { .Spell, .Hazard, .Hit },
        damage_source = .Science,
        cd_max = 20, level_scale = 0.16, energy_cost = 30, exec_count = 1,
        execs = { {
            kind                   = .AoEBlast,
            p1                     = 200,
            p2                     = 0.4,
            status                 = .Poison,
            status_dur             = 5.0,
            status_str             = 1.0,
            spread_on_poison_death = true,
        }, {}, {}, {} },
    },

    .Exothermic = {
        name = "Exothermic",
        desc = "Ignite all Oiled enemies within range simultaneously. Each detonation deals heavy damage and clears the Oiled condition.",
        trait = .Science, tags = { .Spell, .Hit },
        damage_source = .Science,
        cd_max = 16, level_scale = 0.22, energy_cost = 25, exec_count = 1,
        execs = { {
            kind   = .DetonateStatus,
            p1     = 2.5,
            p2     = 350,
            status = .Oiled,
        }, {}, {}, {} },
    },


    .LaTormenta = {
        name = "La Tormenta",
        desc = "Discharge a volley of galvanic bolts that seek out the nearest enemy with relentless precision.",
        trait = .Science, tags = { .Projectile, .Attack, .Ranged, .Hit, .Spell },
        damage_source = .Science,
        cd_max = 12, level_scale = 0.15, energy_cost = 30, exec_count = 1,
        execs = { { kind = .HomingVolley, p1 = 5, p2 = 8.0 }, {}, {}, {} },
    },

    .Overcharged = {
        name = "Overcharged",
        desc = "Surge excess galvanic current through your own nervous system — speed, fire rate, and damage all increase for 6 s.",
        trait = .Science, tags = { .Spell },
        damage_source = .Science,
        cd_max = 22, level_scale = 0.05, energy_cost = 40, exec_count = 1,

        execs = { { kind = .BuffStats, p1 = 1.35, p2 = 1.4 }, {}, {}, {} },
    },

    .InductionCoil = {
        name = "Induction Coil",
        desc = "Deploy a coiled galvanic trap at your feet. The first enemy that steps within range takes a shock blast and is stunned.",
        trait = .Science, tags = { .Trap, .Spell },
        damage_source = .Science,
        cd_max = 18, level_scale = 0.18, energy_cost = 20, exec_count = 1,
        execs = { {
            kind       = .PlaceTrap,
            p1         = 80,
            p2         = 1.8,
            status     = .Stun,
            status_dur = 1.2,
            status_str = 1.0,
        }, {}, {}, {} },
    },

    .GalvanicShock = {
        name = "Galvanic Shock",
        desc = "Fire a capacitor round that paralyses the target and renders it vulnerable — all damage dealt to it is doubled for 3 s.",
        trait = .Science, tags = { .Projectile, .Attack, .Ranged, .Hit, .Spell },
        damage_source = .Science,
        cd_max = 14, level_scale = 0.12, energy_cost = 25, exec_count = 1,
        execs = { {
            kind            = .FireProjectile,
            p1              = 0.8,
            p2              = 0,
            status          = .Stun,
            status_dur      = 0.5,
            status_str      = 1.0,
            damage_amp_mult = 2.0,
            damage_amp_dur  = 3.0,
        }, {}, {}, {} },
    },
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
    raw := cw.world_get_item(w, iid).ability_type

    if int(raw) >= len(ABILITY_DEFS) { return .None }
    return raw
}

player_has_ability :: proc(w: ^cw.World, player_id: int, at: cw.AbilityType) -> bool {
    if at == .None { return false }
    for i in 0..<cw.ABILITY_SLOT_COUNT {
        if player_ability_in_slot(w, player_id, i) == at { return true }
    }
    return false
}


ability_item_level :: proc(w: ^cw.World, player_id: int, slot_idx: int) -> int {
    if !cw.world_has_component(w, player_id, .Inventory) { return 1 }
    inv := cw.world_get_inventory(w, player_id)
    eq  := ability_slot_to_equip(slot_idx)
    iid := inv.equipped[eq]
    if !cw.world_is_valid(w, iid)             { return 1 }
    if !cw.world_has_component(w, iid, .Item) { return 1 }
    lv := int(cw.world_get_item(w, iid).ability_level)
    return max(1, lv)
}


ability_base_damage :: proc(w: ^cw.World, id: int, def: ^AbilityDef, level: int, exec_p1: f32) -> f32 {
    level_bonus := 1.0 + f32(max(0, level - 1)) * def.level_scale

    stat_mult: f32 = 1.0
    sci_val:   int = 0
    if cw.world_has_component(w, id, .Stats) {
        st        := cw.world_get_stats(w, id)
        stat_mult  = st.damage_mult
        sci_val    = st.science
    }

    base: f32
    switch def.damage_source {
    case .Weapon:

        weapon_dmg: f32 = 0
        if cw.world_has_component(w, id, .Equipment) {
            equip := cw.world_get_equipment(w, id)
            wid   := equip.weapon_entity_id
            if cw.world_is_valid(w, wid) && cw.world_has_component(w, wid, .Weapon) {
                weapon_dmg = cw.world_get_weapon_data(w, wid).damage
            }
        }

        if weapon_dmg == 0 && cw.world_has_component(w, id, .Inventory) {
            inv  := cw.world_get_inventory(w, id)
            peid := inv.equipped[int(cw.EquipSlot.WeaponPrimary)]
            if cw.world_is_valid(w, peid) && cw.world_has_component(w, peid, .Item) {
                weapon_dmg = cw.world_get_item(w, peid).melee_damage
            }
        }

        if weapon_dmg == 0 { weapon_dmg = 20 }
        base = weapon_dmg * 0.75

    case .Science:

        eff_sci := max(sci_val, 2)
        base     = f32(eff_sci) * SCIENCE_DAMAGE_PER_POINT
    }

    return base * exec_p1 * level_bonus * stat_mult
}


@(private = "file")
_maybe_apply_status :: proc(w: ^cw.World, enemy_id: int, exec: AbilityExecComp) {
    if exec.status == cw.StatusEffectType(0) { return }
    cw.status_effect_apply(w, enemy_id, cw.StatusEffect{
        type            = exec.status,
        application     = .Base,
        stack_behavior  = .Refresh,
        duration        = exec.status_dur,
        strength        = exec.status_str,
    })
}


@(private = "file")
_maybe_stamp_damage_amp :: proc(w: ^cw.World, enemy_id: int, exec: AbilityExecComp) {
    if exec.damage_amp_mult <= 0 { return }
    if cw.world_has_component(w, enemy_id, .DamageAmp) {

        da := cw.world_get_damage_amp(w, enemy_id)
        da.mult  *= exec.damage_amp_mult
        da.timer  = max(da.timer, exec.damage_amp_dur)
    } else {
        cw.world_set_damage_amp(w, enemy_id, cw.DamageAmpComp{
            mult  = exec.damage_amp_mult,
            timer = exec.damage_amp_dur,
        })
    }
}


@(private = "file")
_maybe_stamp_contagion :: proc(w: ^cw.World, enemy_id: int, exec: AbilityExecComp) {
    if !exec.spread_on_poison_death { return }
    if exec.status != .Poison       { return }
    cw.world_set_contagion_tag(w, enemy_id)
}


MAX_SPAWNS :: 24

@(private = "file")
ability_spawn_projectile :: proc(w: ^cw.World, shooter_id: int,
                                  dir: [3]f32, damage: f32, pierce: i8 = 0) {

    proj_speed: f32 = 380
    proj_life:  f32 = 1.8

    if cw.world_has_component(w, shooter_id, .Equipment) {
        equip := cw.world_get_equipment(w, shooter_id)
        wid   := equip.weapon_entity_id
        if cw.world_is_valid(w, wid) && cw.world_has_component(w, wid, .Weapon) {
            wp         := cw.world_get_weapon_data(w, wid)
            proj_speed  = wp.projectile_speed
            proj_life   = wp.projectile_life
        }
    }

    proj_speed_mult: f32 = 1.0
    if cw.world_has_component(w, shooter_id, .Stats) {
        proj_speed_mult = cw.world_get_stats(w, shooter_id).projectile_speed_mult
    }

    owner_faction: u8
    if cw.world_has_component(w, shooter_id, .Collider) {
        owner_faction = cw.world_get_collider(w, shooter_id).faction
    }

    if !cw.world_has_component(w, shooter_id, .Transform) { return }
    t_snap := cw.world_get_transform(w, shooter_id)^

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
        speed            = proj_speed * proj_speed_mult,
        lifetime         = proj_life,
        max_lifetime     = proj_life,
        damage           = damage,
        owner_id         = shooter_id,
        owner_faction    = owner_faction,
        visual           = .Standard,
        pierce_remaining = pierce,
    })
    cw.world_set_self_destruct(w, proj_id, cw.SelfDestructComp{ timer = proj_life })
    cw.world_set_projectile_tag(w, proj_id)
    play_sfx("shoot")
}

@(private = "file")
_trait_color :: proc(trait: AbilityTrait) -> (er, eg, eb: u8) {
    switch trait {
    case .Strength:  return 240,  80,  30
    case .Science:   return  60, 180, 255
    case .Dexterity: return 255, 210,  50
    case .None:      return 220, 140,  50
    }
    return 220, 140, 50
}

@(private = "file")
ability_blast_aoe :: proc(w: ^cw.World, shooter_id: int, radius, damage: f32,
                           trait: AbilityTrait = .None,
                           exec: AbilityExecComp = {}) {
    if !cw.world_has_component(w, shooter_id, .Transform) { return }
    origin := cw.world_get_transform(w, shooter_id).position

    enemy_ids := cw.world_query(w, cw.query_mask(.AIAgent, .Health, .Transform))
    defer delete(enemy_ids)

    hit_any := false
    r2      := radius * radius
    for eid in enemy_ids {
        et := cw.world_get_transform(w, eid)
        dx := et.position[0] - origin[0]
        dy := et.position[1] - origin[1]
        if dx*dx + dy*dy <= r2 {
            cw.world_push_damage(w, eid, damage, shooter_id)
            _maybe_apply_status(w, eid, exec)
            _maybe_stamp_damage_amp(w, eid, exec)
            _maybe_stamp_contagion(w, eid, exec)
            hit_any = true
        }
    }

    er, eg, eb := _trait_color(trait)
    push_explosion(origin[0], origin[1], radius, er, eg, eb)
    if hit_any { play_sfx("melee_hit") } else { play_sfx("ability_fan") }
}


@(private = "file")
ability_blast_cone :: proc(w: ^cw.World, shooter_id: int,
                            half_angle_rad, range, damage: f32,
                            trait: AbilityTrait = .None,
                            exec: AbilityExecComp = {}) {
    if !cw.world_has_component(w, shooter_id, .Transform) { return }
    t      := cw.world_get_transform(w, shooter_id)
    origin := t.position
    rot    := t.rotation

    enemy_ids := cw.world_query(w, cw.query_mask(.AIAgent, .Health, .Transform))
    defer delete(enemy_ids)

    hit_any := false
    r2      := range * range
    for eid in enemy_ids {
        et := cw.world_get_transform(w, eid)
        dx := et.position[0] - origin[0]
        dy := et.position[1] - origin[1]
        dist_sq := dx*dx + dy*dy
        if dist_sq > r2 { continue }


        angle_to := math.atan2(dy, dx)
        diff      := angle_to - rot

        for diff >  math.PI { diff -= 2.0 * math.PI }
        for diff < -math.PI { diff += 2.0 * math.PI }

        if math.abs(diff) <= half_angle_rad {
            cw.world_push_damage(w, eid, damage, shooter_id)
            _maybe_apply_status(w, eid, exec)
            _maybe_stamp_damage_amp(w, eid, exec)
            _maybe_stamp_contagion(w, eid, exec)
            hit_any = true
        }
    }

    er, eg, eb := _trait_color(trait)
    push_explosion(origin[0], origin[1], range * 0.5, er, eg, eb)
    if hit_any { play_sfx("melee_hit") } else { play_sfx("ability_fan") }
}


ability_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }
    if !cw.world_is_valid(w, w.player_id)                { return }
    if !cw.world_has_component(w, w.player_id, .Ability) { return }

    id := w.player_id

    if cw.world_has_component(w, id, .Respawn) &&
       cw.world_get_respawn(w, id).timer > 0 { return }

    ab_snap := cw.world_get_ability(w, id)^
    input   := cw.world_get_input(w, id)^

    if !cw.world_has_component(w, id, .Transform) { return }
    t_snap := cw.world_get_transform(w, id)^

    cooldown_mult: f32 = 1.0
    if cw.world_has_component(w, id, .Stats) {
        st := cw.world_get_stats(w, id)
        if st.active_abilities_blocked { return }
        cooldown_mult = st.ability_cooldown_mult
    }
    dt_scaled := dt * cooldown_mult

    spawn_dirs  : [MAX_SPAWNS][3]f32
    spawn_dmgs  : [MAX_SPAWNS]f32
    spawn_pierce: [MAX_SPAWNS]i8
    spawn_count := 0
    fire_proj_exec: AbilityExecComp

    facing := [3]f32{ math.cos(t_snap.rotation), math.sin(t_snap.rotation), 0 }

    inputs_pressed := [cw.ABILITY_SLOT_COUNT]bool{
        input.skill1_pressed,
        input.skill2_pressed,
        input.skill3_pressed,
        input.skill4_pressed,
    }

    enqueue :: #force_inline proc(dirs: ^[MAX_SPAWNS][3]f32, dmgs: ^[MAX_SPAWNS]f32,
                                   pierces: ^[MAX_SPAWNS]i8, cnt: ^int,
                                   dir: [3]f32, dmg: f32, pierce: i8 = 0) {
        if cnt^ >= MAX_SPAWNS { return }
        dirs[cnt^]    = dir
        dmgs[cnt^]    = dmg
        pierces[cnt^] = pierce
        cnt^ += 1
    }

    for slot_idx in 0..<cw.ABILITY_SLOT_COUNT {
        ab_type := player_ability_in_slot(w, id, slot_idx)
        if ab_type == .None { continue }

        def    := &ABILITY_DEFS[ab_type]
        cd_max := def.cd_max
        st     := &ab_snap.slots[slot_idx]
        level  := ability_item_level(w, id, slot_idx)


        if st.cooldown > 0 { st.cooldown = max(st.cooldown - dt_scaled, 0) }


        if st.buff_timer > 0 { st.buff_timer = max(st.buff_timer - dt, 0) }


        if st.burst_shots > 0 {
            st.burst_timer -= dt
            if st.burst_timer <= 0 {
                interval: f32 = 0.10
                for ei in 0..<def.exec_count {
                    ex := def.execs[ei]
                    if ex.kind == .BurstFire {
                        interval = ex.p2
                        break
                    }
                }
                enqueue(&spawn_dirs, &spawn_dmgs, &spawn_pierce, &spawn_count,
                    facing, st.burst_dmg, st.burst_pierce)
                st.burst_shots -= 1
                st.burst_timer  = interval if st.burst_shots > 0 else 0
            }
        }


        if st.charging {

            spin_radius:   f32 = 80
            spin_interval: f32 = 0.15
            spin_exec:     AbilityExecComp
            is_spin := false
            for ei in 0..<def.exec_count {
                if def.execs[ei].kind == .SpinChannel {
                    is_spin       = true
                    spin_radius   = def.execs[ei].p1
                    spin_interval = def.execs[ei].p2
                    spin_exec     = def.execs[ei]
                    break
                }
            }

            if is_spin {

                st.charge_timer -= dt
                st.burst_timer  -= dt
                if st.burst_timer <= 0 {
                    ability_blast_aoe(w, id, spin_radius, st.charge_dmg, def.trait, spin_exec)
                    st.burst_timer = spin_interval
                }
                if st.charge_timer <= 0 {
                    st.charging    = false
                    st.burst_timer = 0

                    cw.world_clear_aim_lock(w, id)
                }


                cw.world_get_transform(w, id).rotation += SPIN_ANGULAR_VELOCITY * dt
            } else {

                st.charge_timer -= dt
                if st.charge_timer <= 0 {
                    st.charging = false
                    enqueue(&spawn_dirs, &spawn_dmgs, &spawn_pierce, &spawn_count,
                        facing, st.charge_dmg, 0)
                    play_sfx("ability_quickdraw")
                }
            }
        }


        if st.primed && input.dodge_pressed {
            st.primed = false
            n := st.primed_count
            for i in 0..<n {
                angle := f32(i) * (2.0 * math.PI / f32(n))
                enqueue(&spawn_dirs, &spawn_dmgs, &spawn_pierce, &spawn_count,
                    [3]f32{ math.cos(angle), math.sin(angle), 0 },
                    st.primed_dmg, 0)
            }
            play_sfx("ability_fan")
        }


        if !inputs_pressed[slot_idx] || st.cooldown > 0 { continue }


        effective_energy_cost := def.energy_cost
        if def.energy_cost > 0 && cw.world_has_component(w, id, .Stats) {
            effective_energy_cost *= cw.world_get_stats(w, id).energy_cost_mult
        }
        if effective_energy_cost > 0 && cw.world_has_component(w, id, .Health) {
            h_en := cw.world_get_health(w, id)
            if h_en.energy < effective_energy_cost {
                play_sfx("no_energy")
                continue
            }
        }

        did_activate := false

        for ei in 0..<def.exec_count {
            ex := def.execs[ei]
            switch ex.kind {

            case .None:


            case .FireProjectile:
                dmg := ability_base_damage(w, id, def, level, ex.p1)
                enqueue(&spawn_dirs, &spawn_dmgs, &spawn_pierce, &spawn_count,
                    facing, dmg, i8(min(int(ex.p2), 120)))

                fire_proj_exec = ex
                did_activate = true
                play_sfx("ability_quickdraw")

            case .BurstFire:
                if st.burst_shots == 0 {
                    st.burst_shots  = int(ex.p1)
                    st.burst_timer  = 0
                    st.burst_dmg    = ability_base_damage(w, id, def, level, 1.0)
                    st.burst_pierce = 0
                    did_activate    = true
                    play_sfx("ability_quickdraw")
                }

            case .FanFire:
                n        := int(ex.p1)
                spread   := ex.p2
                step     := spread / f32(max(n - 1, 1))
                start_a  := t_snap.rotation - spread * 0.5
                base_dmg := ability_base_damage(w, id, def, level, 0.85)
                for i in 0..<n {
                    a := start_a + f32(i) * step
                    enqueue(&spawn_dirs, &spawn_dmgs, &spawn_pierce, &spawn_count,
                        [3]f32{ math.cos(a), math.sin(a), 0 }, base_dmg, 0)
                }
                did_activate = true
                play_sfx("ability_fan")

            case .ChargeFire:
                if !st.charging {
                    st.charging     = true
                    st.charge_timer = ex.p2
                    st.charge_dmg   = ability_base_damage(w, id, def, level, ex.p1)
                    did_activate    = true
                }

            case .SpinChannel:

                if !st.charging {
                    st.charging     = true
                    st.charge_timer = SPIN_CHANNEL_DURATION
                    st.burst_timer  = 0


                    st.charge_dmg   = ability_base_damage(w, id, def, level, 1.0)
                    did_activate    = true
                    play_sfx("ability_fan")

                    cw.world_set_aim_lock(w, id)
                }

            case .PrimeDodge:
                if !st.primed {
                    st.primed       = true
                    st.primed_count = int(ex.p1)
                    st.primed_dmg   = ability_base_damage(w, id, def, level, 1.0)
                    did_activate    = true
                    play_sfx("ability_fan")
                }

            case .AoEBlast:
                dmg := ability_base_damage(w, id, def, level, ex.p2)
                ability_blast_aoe(w, id, ex.p1, dmg, def.trait, ex)
                did_activate = true

            case .ConeBlast:
                dmg := ability_base_damage(w, id, def, level, 1.0)
                ability_blast_cone(w, id, ex.p1, ex.p2, dmg, def.trait, ex)
                did_activate = true

            case .DetonateStatus:

                if cw.world_has_component(w, id, .Transform) {
                    origin  := cw.world_get_transform(w, id).position
                    dmg     := ability_base_damage(w, id, def, level, ex.p1)
                    scan_r2 := ex.p2 * ex.p2
                    ids     := cw.world_query(w, cw.query_mask(.AIAgent, .Health, .Transform, .StatusEffect))
                    defer delete(ids)
                    detonated := false
                    for eid in ids {
                        et := cw.world_get_transform(w, eid)
                        dx := et.position[0] - origin[0]
                        dy := et.position[1] - origin[1]
                        if dx*dx + dy*dy > scan_r2 { continue }
                        sec := cw.world_get_status_effects(w, eid)
                        if !cw.status_effect_is_active(sec, ex.status) { continue }
                        cw.world_push_damage(w, eid, dmg, id)
                        push_explosion(et.position[0], et.position[1], 60, 255, 160, 30)

                        cw.status_effect_get(sec, ex.status).duration = 0
                        detonated = true
                    }
                    if detonated { play_sfx("ability_fan") }
                }
                did_activate = true

            case .HomingVolley:

                if cw.world_has_component(w, id, .Transform) {
                    t_hv    := cw.world_get_transform(w, id)
                    n_proj  := int(ex.p1)
                    dmg     := ability_base_damage(w, id, def, level, 1.0)
                    spread  :: f32(0.5)

                    owner_faction: u8
                    if cw.world_has_component(w, id, .Collider) {
                        owner_faction = cw.world_get_collider(w, id).faction
                    }

                    proj_speed: f32 = 280
                    proj_life:  f32 = 3.0
                    proj_speed_mult: f32 = 1.0
                    if cw.world_has_component(w, id, .Stats) {
                        proj_speed_mult = cw.world_get_stats(w, id).projectile_speed_mult
                    }

                    for i in 0..<n_proj {
                        t_ratio := f32(i) / max(f32(n_proj - 1), 1)
                        angle   := t_hv.rotation - spread*0.5 + t_ratio*spread
                        dir     := [3]f32{ math.cos(angle), math.sin(angle), 0 }
                        origin  := [3]f32{
                            t_hv.position[0] + dir[0] * (PLAYER_RADIUS + 6),
                            t_hv.position[1] + dir[1] * (PLAYER_RADIUS + 6),
                            0,
                        }

                        pid := cw.world_create_entity(w)
                        cw.world_set_transform(w, pid, cw.TransformComp{ position = origin })
                        cw.world_set_projectile(w, pid, cw.ProjectileComp{
                            direction     = dir,
                            speed         = proj_speed * proj_speed_mult,
                            lifetime      = proj_life,
                            max_lifetime  = proj_life,
                            damage        = dmg,
                            owner_id      = id,
                            owner_faction = owner_faction,
                            visual        = .Standard,
                        })
                        cw.world_set_homing(w, pid, cw.HomingComp{
                            turn_rate  = ex.p2,
                            seek_range = 600,
                            owner_id   = id,
                        })
                        cw.world_set_self_destruct(w, pid, cw.SelfDestructComp{ timer = proj_life })
                        cw.world_set_projectile_tag(w, pid)
                    }
                    play_sfx("ability_fan")
                }
                did_activate = true

            case .PlaceTrap:

                if cw.world_has_component(w, id, .Transform) {
                    t_pt := cw.world_get_transform(w, id)
                    dmg  := ability_base_damage(w, id, def, level, ex.p2)
                    er, eg, eb := _trait_color(def.trait)

                    trap_id := cw.world_create_entity(w)
                    cw.world_set_transform(w, trap_id, cw.TransformComp{ position = t_pt.position })
                    cw.world_set_proximity_trigger(w, trap_id, cw.ProximityTriggerComp{
                        arm_timer  = 0.5,
                        radius     = ex.p1,
                        damage     = dmg,
                        owner_id   = id,
                        status     = ex.status,
                        status_dur = ex.status_dur,
                        status_str = ex.status_str,
                        er = er, eg = eg, eb = eb,
                    })
                    play_sfx("ability_fan")
                }
                did_activate = true

            case .BuffStats:
                ab_type_check := player_ability_in_slot(w, id, slot_idx)
                #partial switch ab_type_check {
                case .Overcharged:

                    dur := def.cd_max * 0.5
                    cw.world_set_overcharge_buff(w, id, cw.OverchargeBuffComp{
                        speed_mult     = ex.p1,
                        fire_rate_mult = ex.p2,
                        damage_mult    = 1.25,
                        duration       = dur,
                        timer          = 0,
                    })
                    play_sfx("levelup")
                case .NecroticSurge:

                    base_heal := ability_base_damage(w, id, def, level, 0.3)
                    cw.world_set_kill_heal(w, id, cw.KillHealComp{
                        amount   = base_heal,
                        duration = ex.p2,
                        timer    = 0,
                    })
                    play_sfx("levelup")
                case:

                    play_sfx("levelup")
                }
                did_activate = true

            case .ThrowGrenade:

                blast_dmg := ability_base_damage(w, id, def, level, 1.3)
                cloud_dps := ability_base_damage(w, id, def, level, 0.35)

                er, eg, eb := _trait_color(def.trait)

                if def.trait == .Science && ex.status == .Poison {
                    er, eg, eb = 60, 220, 40
                }

                if ex.blink_on_land {
                    er, eg, eb = 160, 100, 255
                }

                gid := cw.world_create_entity(w)
                cw.world_set_transform(w, gid, t_snap)
                cw.world_set_grenade(w, gid, cw.GrenadeComp{
                    owner_id         = id,
                    target           = input.mouse_world,
                    speed            = 360,
                    fuse_timer       = 3.0,
                    damage           = blast_dmg,
                    blast_radius     = ex.p1,
                    cloud_radius     = ex.p1 * 0.72,
                    cloud_duration   = ex.p2,
                    cloud_dps        = cloud_dps,
                    cloud_status     = ex.status,
                    cloud_status_dur = ex.status_dur,
                    blink_on_land    = ex.blink_on_land,
                    er = er, eg = eg, eb = eb,
                })
                did_activate = true
                play_sfx("ability_fan")

            case .HealSelf:
                if cw.world_has_component(w, id, .Health) {
                    h    := cw.world_get_health(w, id)
                    heal := ex.p1 * (1.0 + f32(max(0, level - 1)) * def.level_scale)
                    h.current = min(h.current + heal, h.max)
                }
                did_activate = true
                play_sfx("levelup")

            case .InstantReload:
                if cw.world_has_component(w, id, .Equipment) {
                    equip := cw.world_get_equipment(w, id)
                    wid   := equip.weapon_entity_id
                    if cw.world_is_valid(w, wid) && cw.world_has_component(w, wid, .Weapon) {
                        wc             := cw.world_get_weapon_data(w, wid)
                        wc.ammo_current = wc.ammo_max
                        wc.is_reloading = false
                        wc.reload_timer = 0
                    }
                }
                did_activate = true
                play_sfx("reload")

            case .BuffArmor:
                st.buff_timer = ex.p2
                st.buff_value = ex.p1
                did_activate  = true
                play_sfx("levelup")

            case .CooldownReset:
                reduction := ex.p1
                for other_idx in 0..<cw.ABILITY_SLOT_COUNT {
                    if other_idx == slot_idx { continue }
                    ab_snap.slots[other_idx].cooldown *= (1.0 - reduction)
                }
                did_activate = true
                play_sfx("levelup")
            }
        }

        if did_activate {
            st.cooldown = cd_max

            if effective_energy_cost > 0 && cw.world_has_component(w, id, .Health) {
                h_en        := cw.world_get_health(w, id)
                h_en.energy  = max(0, h_en.energy - effective_energy_cost)
            }
        }
    }


    for i in 0..<spawn_count {
        ability_spawn_projectile(w, id, spawn_dirs[i], spawn_dmgs[i], spawn_pierce[i])

        if fire_proj_exec.damage_amp_mult > 0 {
            proj_id := w.last_created
            if cw.world_is_valid(w, proj_id) {
                cw.world_set_damage_amp_on_hit(w, proj_id, cw.DamageAmpOnHitComp{
                    mult = fire_proj_exec.damage_amp_mult,
                    dur  = fire_proj_exec.damage_amp_dur,
                })
            }
        }
    }

    ab_live := cw.world_get_ability(w, id)
    ab_live.slots = ab_snap.slots
}
