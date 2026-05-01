package main

// =============================================================================
// ENTITY CONFIG — data-driven entity spawning from JSON
//
// JSON format (data/entities.json): a top-level array of entity objects.
// Each object key names a component; its presence means "add this component".
// Absent key → component not added. Empty object {} is valid (flag-only).
//
// Workflow:
//   defs, ok := load_entity_defs("data/entities.json")
//   defer destroy_entity_defs(defs)
//   pid := spawn_from_def(world, find_entity_def(defs, "player"))
// =============================================================================

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import cw "clockwork"

TransformDef :: struct {
    position: [3]f32,
    rotation: f32,
}

HealthDef :: struct {
    current:    f32,
    max:        f32,
    corruption: f32,
    energy:     f32,
    max_energy: f32,
}

ColliderDef :: struct {
    radius:     f32,
    faction:    u8,
    is_trigger: bool,
}

WeaponDef :: struct {
    type:             cw.WeaponType, 
    damage:           f32,
    fire_rate:        f32,           
    projectile_speed: f32,           
    projectile_life:  f32,           
    range:            f32,           
    ammo_max:         int,           
    reload_time:      f32,           
}

AIAgentDef :: struct {
    state:        u8,
    aggro_range:  f32,
    attack_range: f32,
    cooldown_max: f32,      
    speed:        f32,
    damage:       f32,
    ai_type:      cw.AIType,
    pellet_count: int,      
    spread_angle: f32,      
}

DodgeDef :: struct {
    duration:     f32,   
    speed:        f32,   
    cooldown:     f32,   
}

RenderConfigDef :: struct {
    display_name: string,   
    sprite_name:  string,
    sprite_scale: f32,
    world_size:   f32,
    render_layer: cw.RenderLayer,
    show_hp_bar:  bool,
    show_dir_tip: bool,
}

NPCDef :: struct {
    npc_type:        cw.NPCType,
    interact_radius: f32,
}

MutDamageMultDef :: struct {
    mult: f32,
}

MutRootOnFireDef :: struct {
    duration:                 f32,
    damage_mult_while_rooted: f32,
    projectile_speed_mult:    f32,
}

MutTimedSelfDamageDef :: struct {
    grace: f32,
    dps:   f32,
}

MutEarlyDeathThresholdDef :: struct {
    threshold_pct: f32,
}

MutMissingHealthDamageDef :: struct {
    max_mult:     f32,
    floor_hp_pct: f32,
}

MutPassivePowerDef :: struct {
    mult: f32,
}

MutMoveSpeedMultDef :: struct {
    mult: f32,
}

MutSerumGainMultDef :: struct {
    mult: f32,
}

MutKillHealDef :: struct {
    heal_pct: f32,
}

MutLifestealDef :: struct {
    hp_per_hit: f32,
}

MutProximityDamageDef :: struct {
    radius:        f32,
    dps:           f32,
    self_fraction: f32,
}

MutOnDeathExplodeDef :: struct {
    radius:       f32,
    damage_pct:   f32,
    cooldown_max: f32,
}

MutStationaryShieldDef :: struct {
    shield_max:  f32,
    regen_rate:  f32,
}

MutExtraDodgeChargesDef :: struct {
    count:        int,
    recharge_max: f32,
}

MutDamageTakenMultDef :: struct {
    mult: f32,
}

MutBodyMeleeDef :: struct {
    damage:       f32,
    arc_angle:    f32,
    range:        f32,
    cooldown_max: f32,
}

MutCorpseTriggerDef :: struct {
    radius: f32,
    dps:    f32,
}

MutUnseenDamageMultDef :: struct {
    mult:          f32,
    vision_radius: f32,
}

EntityDef :: struct {
    name:         string,            

    transform:    Maybe(TransformDef),
    health:       Maybe(HealthDef),
    collider:     Maybe(ColliderDef),
    weapon:       Maybe(WeaponDef),
    ai_agent:     Maybe(AIAgentDef),
    dodge:        Maybe(DodgeDef),
    render_cfg:   Maybe(RenderConfigDef),

    npc:          Maybe(NPCDef),
    mut_damage_mult:      Maybe(MutDamageMultDef),
    mut_root_on_fire:     Maybe(MutRootOnFireDef),
    mut_timed_self_damage: Maybe(MutTimedSelfDamageDef),
    mut_early_death_threshold: Maybe(MutEarlyDeathThresholdDef),
    mut_missing_health_damage: Maybe(MutMissingHealthDamageDef),
    mut_passive_power: Maybe(MutPassivePowerDef),
    mut_move_speed_mult: Maybe(MutMoveSpeedMultDef),
    mut_serum_gain_mult: Maybe(MutSerumGainMultDef),
    mut_kill_heal:            Maybe(MutKillHealDef),
    mut_lifesteal:            Maybe(MutLifestealDef),
    mut_proximity_damage:     Maybe(MutProximityDamageDef),
    mut_on_death_explode:     Maybe(MutOnDeathExplodeDef),
    mut_stationary_shield:    Maybe(MutStationaryShieldDef),
    mut_extra_dodge_charges:  Maybe(MutExtraDodgeChargesDef),
    mut_damage_taken_mult:    Maybe(MutDamageTakenMultDef),
    mut_body_melee:           Maybe(MutBodyMeleeDef),
    mut_corpse_trigger:       Maybe(MutCorpseTriggerDef),
    mut_unseen_damage_mult:   Maybe(MutUnseenDamageMultDef),

    has_velocity:    bool,
    has_input:       bool,
    has_fog_of_war:  bool,
    has_mut_lock_hp_to_one: bool,
    has_mut_block_healing:  bool,
    has_mut_block_ranged:   bool,
    has_mut_block_pickup_heal: bool,
    has_mut_block_pickups:  bool,
    has_mut_nonlethal_shots: bool,
    has_mut_disable_actives: bool,
    has_mut_wall_phase:       bool,
    has_mut_hide_enemy_sprites: bool,
}

load_entity_defs :: proc(path: string, allocator := context.allocator) -> (defs: []EntityDef, ok: bool) {
    data, file_ok := os.read_entire_file(path)
    if !file_ok {
        fmt.eprintln("[entity_config] Cannot read:", path)
        return nil, false
    }
    defer delete(data)

    root, parse_err := json.parse(data)
    if parse_err != .None {
        fmt.eprintln("[entity_config] JSON error in", path, "—", parse_err)
        return nil, false
    }
    defer json.destroy_value(root)

    arr, is_arr := root.(json.Array)
    if !is_arr {
        fmt.eprintln("[entity_config] Expected a JSON array at root in", path)
        return nil, false
    }

    result := make([]EntityDef, len(arr), allocator)

    for entry, i in arr {
        obj, is_obj := entry.(json.Object)
        if !is_obj { continue }

        def := &result[i]

        if n, n_ok := obj["name"].(string); n_ok {
            def.name = strings.clone(n, allocator)
        }

        if _, v_ok  := obj["velocity"];    v_ok  { def.has_velocity   = true }
        if _, in_ok := obj["input"];       in_ok { def.has_input      = true }
        if _, fw_ok := obj["fog_of_war"];  fw_ok { def.has_fog_of_war = true }
        if _, hp1_ok := obj["mut_lock_hp_to_one"]; hp1_ok { def.has_mut_lock_hp_to_one = true }
        if _, bhf_ok := obj["mut_block_healing"];  bhf_ok { def.has_mut_block_healing  = true }
        if _, mbr_ok := obj["mut_block_ranged"];   mbr_ok { def.has_mut_block_ranged   = true }
        if _, mbph_ok := obj["mut_block_pickup_heal"]; mbph_ok { def.has_mut_block_pickup_heal = true }
        if _, mbp_ok := obj["mut_block_pickups"];  mbp_ok { def.has_mut_block_pickups  = true }
        if _, mns_ok := obj["mut_nonlethal_shots"]; mns_ok { def.has_mut_nonlethal_shots = true }
        if _, mda_ok := obj["mut_disable_actives"];      mda_ok { def.has_mut_disable_actives      = true }
        if _, mwp_ok := obj["mut_wall_phase"];            mwp_ok { def.has_mut_wall_phase             = true }
        if _, mhe_ok := obj["mut_hide_enemy_sprites"];   mhe_ok { def.has_mut_hide_enemy_sprites     = true }

        if t_obj, t_ok := obj["transform"].(json.Object); t_ok {
            t: TransformDef
            if pos, p_ok := t_obj["position"].(json.Array); p_ok {
                for j in 0..<min(len(pos), 3) {
                    t.position[j] = jf32(pos[j])
                }
            }
            if rot, r_ok := t_obj["rotation"]; r_ok { t.rotation = jf32(rot) }
            def.transform = t
        }

        if h_obj, h_ok := obj["health"].(json.Object); h_ok {
            h: HealthDef
            if v, ok2 := h_obj["current"];    ok2 { h.current    = jf32(v) }
            if v, ok2 := h_obj["max"];        ok2 { h.max        = jf32(v) }
            if v, ok2 := h_obj["corruption"]; ok2 { h.corruption = jf32(v) }
            if v, ok2 := h_obj["energy"];     ok2 { h.energy     = jf32(v) }
            if v, ok2 := h_obj["max_energy"]; ok2 { h.max_energy = jf32(v) }
            def.health = h
        }

        if c_obj, c_ok := obj["collider"].(json.Object); c_ok {
            c: ColliderDef
            if v, ok2 := c_obj["radius"];     ok2 { c.radius     = jf32(v) }
            if v, ok2 := c_obj["faction"];    ok2 { c.faction    = u8(jf32(v)) }
            if v, ok2 := c_obj["is_trigger"]; ok2 {
                if b, b_ok := v.(bool); b_ok { c.is_trigger = b }
            }
            def.collider = c
        }

        if w_obj, w_ok := obj["weapon"].(json.Object); w_ok {
            wp: WeaponDef
            if v, ok2 := w_obj["type"].(string); ok2 {
                wp.type = .Ranged if v == "ranged" else .Melee
            }
            if v, ok2 := w_obj["damage"];           ok2 { wp.damage           = jf32(v) }
            if v, ok2 := w_obj["fire_rate"];         ok2 { wp.fire_rate        = jf32(v) }
            if v, ok2 := w_obj["projectile_speed"]; ok2 { wp.projectile_speed = jf32(v) }
            if v, ok2 := w_obj["projectile_life"];  ok2 { wp.projectile_life  = jf32(v) }
            if v, ok2 := w_obj["range"];             ok2 { wp.range            = jf32(v) }
            if v, ok2 := w_obj["ammo_max"];          ok2 { wp.ammo_max         = int(jf32(v)) }
            if v, ok2 := w_obj["reload_time"];       ok2 { wp.reload_time      = jf32(v) }
            def.weapon = wp
        }

        if a_obj, a_ok := obj["ai_agent"].(json.Object); a_ok {
            a: AIAgentDef
            if v, ok2 := a_obj["state"];        ok2 { a.state        = u8(jf32(v)) }
            if v, ok2 := a_obj["aggro_range"];  ok2 { a.aggro_range  = jf32(v) }
            if v, ok2 := a_obj["attack_range"]; ok2 { a.attack_range = jf32(v) }
            if v, ok2 := a_obj["cooldown"];     ok2 { a.cooldown_max = jf32(v) }
            if v, ok2 := a_obj["speed"];        ok2 { a.speed        = jf32(v) }
            if v, ok2 := a_obj["damage"];       ok2 { a.damage       = jf32(v) }
            if v, ok2 := a_obj["pellet_count"]; ok2 { a.pellet_count = int(jf32(v)) }
            if v, ok2 := a_obj["spread_angle"]; ok2 { a.spread_angle = jf32(v) }
            if v, ok2 := a_obj["ai_type"].(string); ok2 {
                a.ai_type = .Ranged if v == "ranged" else .Melee
            }
            def.ai_agent = a
        }

        if d_obj, d_ok := obj["dodge"].(json.Object); d_ok {
            d: DodgeDef
            if v, ok2 := d_obj["duration"]; ok2 { d.duration = jf32(v) }
            if v, ok2 := d_obj["speed"];    ok2 { d.speed    = jf32(v) }
            if v, ok2 := d_obj["cooldown"]; ok2 { d.cooldown = jf32(v) }
            def.dodge = d
        }

        if r_obj, r_ok := obj["render"].(json.Object); r_ok {
            r: RenderConfigDef
            if v, ok2 := r_obj["name"].(string); ok2 {
                r.display_name = strings.clone(v, allocator)
            }
            if v, ok2 := r_obj["sprite"].(string); ok2 {
                r.sprite_name = strings.clone(v, allocator)
            }
            if v, ok2 := r_obj["sprite_scale"]; ok2 {
                r.sprite_scale = jf32(v)
            }
            if v, ok2 := r_obj["world_size"]; ok2 {
                r.world_size = jf32(v)
            }
            if v, ok2 := r_obj["show_hp_bar"].(bool); ok2 {
                r.show_hp_bar = v
            }
            if v, ok2 := r_obj["show_dir_tip"].(bool); ok2 {
                r.show_dir_tip = v
            }
            if v, ok2 := r_obj["layer"].(string); ok2 {
                switch v {
                case "sprite":
                    r.render_layer = .Sprite
                case "world_fx":
                    r.render_layer = .WorldFX
                case:
                    r.render_layer = .None
                }
            }
            def.render_cfg = r
        }

        if n_obj, n_ok := obj["npc"].(json.Object); n_ok {
            n: NPCDef
            if v, ok2 := n_obj["npc_type"].(string); ok2 {
                switch v {
                case "shopkeeper":
                    n.npc_type = .Shopkeeper
                case "mutation_workbench":
                    n.npc_type = .MutationWorkbench
                case:
                    n.npc_type = .Shopkeeper
                }
            }
            if v, ok2 := n_obj["interact_radius"]; ok2 { n.interact_radius = jf32(v) }
            def.npc = n
        }

        if md_obj, md_ok := obj["mut_damage_mult"].(json.Object); md_ok {
            md: MutDamageMultDef
            if v, ok2 := md_obj["mult"]; ok2 { md.mult = jf32(v) }
            def.mut_damage_mult = md
        }

        if mr_obj, mr_ok := obj["mut_root_on_fire"].(json.Object); mr_ok {
            mr: MutRootOnFireDef
            if v, ok2 := mr_obj["duration"]; ok2 { mr.duration = jf32(v) }
            if v, ok2 := mr_obj["damage_mult_while_rooted"]; ok2 { mr.damage_mult_while_rooted = jf32(v) }
            if v, ok2 := mr_obj["projectile_speed_mult"]; ok2 { mr.projectile_speed_mult = jf32(v) }
            def.mut_root_on_fire = mr
        }

        if tsd_obj, tsd_ok := obj["mut_timed_self_damage"].(json.Object); tsd_ok {
            tsd: MutTimedSelfDamageDef
            if v, ok2 := tsd_obj["grace"]; ok2 { tsd.grace = jf32(v) }
            if v, ok2 := tsd_obj["dps"]; ok2 { tsd.dps = jf32(v) }
            def.mut_timed_self_damage = tsd
        }

        if edt_obj, edt_ok := obj["mut_early_death_threshold"].(json.Object); edt_ok {
            edt: MutEarlyDeathThresholdDef
            if v, ok2 := edt_obj["threshold_pct"]; ok2 { edt.threshold_pct = jf32(v) }
            def.mut_early_death_threshold = edt
        }

        if mhd_obj, mhd_ok := obj["mut_missing_health_damage"].(json.Object); mhd_ok {
            mhd: MutMissingHealthDamageDef
            if v, ok2 := mhd_obj["max_mult"]; ok2 { mhd.max_mult = jf32(v) }
            if v, ok2 := mhd_obj["floor_hp_pct"]; ok2 { mhd.floor_hp_pct = jf32(v) }
            def.mut_missing_health_damage = mhd
        }

        if mpp_obj, mpp_ok := obj["mut_passive_power"].(json.Object); mpp_ok {
            mpp: MutPassivePowerDef
            if v, ok2 := mpp_obj["mult"]; ok2 { mpp.mult = jf32(v) }
            def.mut_passive_power = mpp
        }

        if msm_obj, msm_ok := obj["mut_move_speed_mult"].(json.Object); msm_ok {
            msm: MutMoveSpeedMultDef
            if v, ok2 := msm_obj["mult"]; ok2 { msm.mult = jf32(v) }
            def.mut_move_speed_mult = msm
        }

        if sgm_obj, sgm_ok := obj["mut_serum_gain_mult"].(json.Object); sgm_ok {
            sgm: MutSerumGainMultDef
            if v, ok2 := sgm_obj["mult"]; ok2 { sgm.mult = jf32(v) }
            def.mut_serum_gain_mult = sgm
        }

        if kh_obj, kh_ok := obj["mut_kill_heal"].(json.Object); kh_ok {
            kh: MutKillHealDef
            if v, ok2 := kh_obj["heal_pct"]; ok2 { kh.heal_pct = jf32(v) }
            def.mut_kill_heal = kh
        }

        if ls_obj, ls_ok := obj["mut_lifesteal"].(json.Object); ls_ok {
            ls: MutLifestealDef
            if v, ok2 := ls_obj["hp_per_hit"]; ok2 { ls.hp_per_hit = jf32(v) }
            def.mut_lifesteal = ls
        }

        if pd_obj, pd_ok := obj["mut_proximity_damage"].(json.Object); pd_ok {
            pd: MutProximityDamageDef
            if v, ok2 := pd_obj["radius"];        ok2 { pd.radius        = jf32(v) }
            if v, ok2 := pd_obj["dps"];           ok2 { pd.dps           = jf32(v) }
            if v, ok2 := pd_obj["self_fraction"]; ok2 { pd.self_fraction = jf32(v) }
            def.mut_proximity_damage = pd
        }

        if ode_obj, ode_ok := obj["mut_on_death_explode"].(json.Object); ode_ok {
            ode: MutOnDeathExplodeDef
            if v, ok2 := ode_obj["radius"];       ok2 { ode.radius       = jf32(v) }
            if v, ok2 := ode_obj["damage_pct"];   ok2 { ode.damage_pct   = jf32(v) }
            if v, ok2 := ode_obj["cooldown_max"]; ok2 { ode.cooldown_max = jf32(v) }
            def.mut_on_death_explode = ode
        }

        if ss_obj, ss_ok := obj["mut_stationary_shield"].(json.Object); ss_ok {
            ss: MutStationaryShieldDef
            if v, ok2 := ss_obj["shield_max"]; ok2 { ss.shield_max = jf32(v) }
            if v, ok2 := ss_obj["regen_rate"]; ok2 { ss.regen_rate = jf32(v) }
            def.mut_stationary_shield = ss
        }

        if edc_obj, edc_ok := obj["mut_extra_dodge_charges"].(json.Object); edc_ok {
            edc: MutExtraDodgeChargesDef
            if v, ok2 := edc_obj["count"];        ok2 { edc.count        = int(jf32(v)) }
            if v, ok2 := edc_obj["recharge_max"]; ok2 { edc.recharge_max = jf32(v) }
            def.mut_extra_dodge_charges = edc
        }

        if dtm_obj, dtm_ok := obj["mut_damage_taken_mult"].(json.Object); dtm_ok {
            dtm: MutDamageTakenMultDef
            if v, ok2 := dtm_obj["mult"]; ok2 { dtm.mult = jf32(v) }
            def.mut_damage_taken_mult = dtm
        }

        if bm_obj, bm_ok := obj["mut_body_melee"].(json.Object); bm_ok {
            bm: MutBodyMeleeDef
            if v, ok2 := bm_obj["damage"];       ok2 { bm.damage       = jf32(v) }
            if v, ok2 := bm_obj["arc_angle"];    ok2 { bm.arc_angle    = jf32(v) }
            if v, ok2 := bm_obj["range"];        ok2 { bm.range        = jf32(v) }
            if v, ok2 := bm_obj["cooldown_max"]; ok2 { bm.cooldown_max = jf32(v) }
            def.mut_body_melee = bm
        }

        if ct_obj, ct_ok := obj["mut_corpse_trigger"].(json.Object); ct_ok {
            ct: MutCorpseTriggerDef
            if v, ok2 := ct_obj["radius"]; ok2 { ct.radius = jf32(v) }
            if v, ok2 := ct_obj["dps"];    ok2 { ct.dps    = jf32(v) }
            def.mut_corpse_trigger = ct
        }

        if udm_obj, udm_ok := obj["mut_unseen_damage_mult"].(json.Object); udm_ok {
            udm: MutUnseenDamageMultDef
            if v, ok2 := udm_obj["mult"];          ok2 { udm.mult          = jf32(v) }
            if v, ok2 := udm_obj["vision_radius"]; ok2 { udm.vision_radius = jf32(v) }
            def.mut_unseen_damage_mult = udm
        }
    }

    return result, true
}

destroy_entity_defs :: proc(defs: []EntityDef, allocator := context.allocator) {
    for &d in defs {
        delete(d.name, allocator)
        if rc, ok := d.render_cfg.?; ok {
            delete(rc.display_name, allocator)
            delete(rc.sprite_name, allocator)
        }
    }
    delete(defs, allocator)
}

find_entity_def :: proc(defs: []EntityDef, name: string) -> ^EntityDef {
    for &d in defs {
        if d.name == name { return &d }
    }
    fmt.eprintln("[entity_config] No entity def named:", name)
    return nil
}

spawn_from_def :: proc(w: ^cw.World, def: ^EntityDef) -> int {
    if def == nil { return cw.INVALID_ENTITY }

    id := cw.world_create_entity(w)

    if t, ok := def.transform.?; ok {
        cw.world_set_transform(w, id, cw.TransformComp{
            position = t.position,
            rotation = t.rotation,
        })
    }
    if def.has_velocity {
        cw.world_set_velocity(w, id, cw.VelocityComp{})
    }
    if h, ok := def.health.?; ok {
        cw.world_set_health(w, id, cw.HealthComp{
            current    = h.current,
            max        = h.max,
            energy     = h.energy,
            max_energy = h.max_energy,
        })
    }
    if def.has_input {
        cw.world_set_input(w, id, cw.InputStateComp{})
    }
    if c, ok := def.collider.?; ok {
        cw.world_set_collider(w, id, cw.ColliderComp{
            radius     = c.radius,
            faction    = c.faction,
            is_trigger = c.is_trigger,
        })
    }
    if wp, ok := def.weapon.?; ok {
        cw.world_set_weapon_data(w, id, cw.WeaponComp{
            type             = wp.type,
            damage           = wp.damage,
            fire_rate        = wp.fire_rate,
            projectile_speed = wp.projectile_speed,
            projectile_life  = wp.projectile_life,
            range            = wp.range,
            ammo_max         = wp.ammo_max,
            reload_time      = wp.reload_time,
            ammo_current     = wp.ammo_max,  
            cooldown         = 0,
            reload_timer     = 0,
            is_reloading     = false,
        })
    }
    if a, ok := def.ai_agent.?; ok {
        cw.world_set_ai(w, id, cw.AIAgentComp{
            state        = a.state,
            aggro_range  = a.aggro_range,
            attack_range = a.attack_range,
            cooldown_max = a.cooldown_max,
            speed        = a.speed,
            damage       = a.damage,
            ai_type      = a.ai_type,
            pellet_count = a.pellet_count,
            spread_angle = a.spread_angle,
        })
    }
    if d, ok := def.dodge.?; ok {
        cw.world_set_dodge(w, id, cw.DodgeComp{
            duration     = d.duration,
            speed        = d.speed,
            cooldown_max = d.cooldown,
        })
    }
    if rc, ok := def.render_cfg.?; ok {
        comp: cw.RenderConfigComp
        cw.render_config_set_name(&comp, rc.display_name)
        if len(rc.sprite_name) > 0 {
            cw.render_config_set_sprite(&comp, rc.sprite_name)
        }
        comp.sprite_scale = rc.sprite_scale if rc.sprite_scale > 0 else 1.0
        comp.world_size   = rc.world_size
        comp.render_layer = rc.render_layer
        comp.show_hp_bar  = rc.show_hp_bar
        comp.show_dir_tip = rc.show_dir_tip
        cw.world_set_render_config(w, id, comp)

        cw.world_set_anim_state(w, id, cw.AnimStateComp{})
    }
    if def.has_fog_of_war {
        cw.world_set_fog_of_war(w, id)
    }
    if n, ok := def.npc.?; ok {
        cw.world_set_npc(w, id, cw.NPCComp{
            npc_type        = n.npc_type,
            interact_radius = n.interact_radius,
        })
    }
    if md, ok := def.mut_damage_mult.?; ok {
        cw.world_set_mut_damage_mult(w, id, cw.MutDamageMultComp{
            mult = md.mult,
        })
    }
    if def.has_mut_lock_hp_to_one {
        cw.world_set_mut_lock_hp_to_one(w, id)
    }
    if mr, ok := def.mut_root_on_fire.?; ok {
        cw.world_set_mut_root_on_fire(w, id, cw.MutRootOnFireComp{
            duration                 = mr.duration,
            damage_mult_while_rooted = mr.damage_mult_while_rooted,
            projectile_speed_mult    = mr.projectile_speed_mult,
        })
    }
    if tsd, ok := def.mut_timed_self_damage.?; ok {
        cw.world_set_mut_timed_self_damage(w, id, cw.MutTimedSelfDamageComp{
            grace = tsd.grace,
            dps   = tsd.dps,
        })
    }
    if def.has_mut_block_healing {
        cw.world_set_mut_block_healing(w, id)
    }
    if msm, ok := def.mut_move_speed_mult.?; ok {
        cw.world_set_mut_move_speed_mult(w, id, cw.MutMoveSpeedMultComp{ mult = msm.mult })
    }
    if def.has_mut_block_ranged {
        cw.world_set_mut_block_ranged(w, id)
    }
    if def.has_mut_block_pickup_heal {
        cw.world_set_mut_block_pickup_heal(w, id)
    }
    if sgm, ok := def.mut_serum_gain_mult.?; ok {
        cw.world_set_mut_serum_gain_mult(w, id, cw.MutSerumGainMultComp{ mult = sgm.mult })
    }
    if def.has_mut_block_pickups {
        cw.world_set_mut_block_pickups(w, id)
    }
    if def.has_mut_nonlethal_shots {
        cw.world_set_mut_nonlethal_shots(w, id)
    }
    if def.has_mut_disable_actives {
        cw.world_set_mut_disable_actives(w, id)
    }
    if edt, ok := def.mut_early_death_threshold.?; ok {
        cw.world_set_mut_early_death_threshold(w, id, cw.MutEarlyDeathThresholdComp{
            threshold_pct = edt.threshold_pct,
        })
    }
    if mhd, ok := def.mut_missing_health_damage.?; ok {
        cw.world_set_mut_missing_health_damage(w, id, cw.MutMissingHealthDamageComp{
            max_mult     = mhd.max_mult,
            floor_hp_pct = mhd.floor_hp_pct,
        })
    }
    if mpp, ok := def.mut_passive_power.?; ok {
        cw.world_set_mut_passive_power(w, id, cw.MutPassivePowerComp{
            mult = mpp.mult,
        })
    }
    if kh, ok := def.mut_kill_heal.?; ok {
        cw.world_set_mut_kill_heal(w, id, cw.MutKillHealComp{ heal_pct = kh.heal_pct })
    }
    if ls, ok := def.mut_lifesteal.?; ok {
        cw.world_set_mut_lifesteal(w, id, cw.MutLifestealComp{ hp_per_hit = ls.hp_per_hit })
    }
    if pd, ok := def.mut_proximity_damage.?; ok {
        cw.world_set_mut_proximity_damage(w, id, cw.MutProximityDamageComp{
            radius        = pd.radius,
            dps           = pd.dps,
            self_fraction = pd.self_fraction,
        })
    }
    if ode, ok := def.mut_on_death_explode.?; ok {
        cw.world_set_mut_on_death_explode(w, id, cw.MutOnDeathExplodeComp{
            radius       = ode.radius,
            damage_pct   = ode.damage_pct,
            cooldown_max = ode.cooldown_max,
        })
    }
    if ss, ok := def.mut_stationary_shield.?; ok {
        cw.world_set_mut_stationary_shield(w, id, cw.MutStationaryShieldComp{
            shield_max = ss.shield_max,
            regen_rate = ss.regen_rate,
        })
    }
    if edc, ok := def.mut_extra_dodge_charges.?; ok {
        cw.world_set_mut_extra_dodge_charges(w, id, cw.MutExtraDodgeChargesComp{
            count        = edc.count,
            charges      = edc.count,
            recharge_max = edc.recharge_max,
        })
    }
    if dtm, ok := def.mut_damage_taken_mult.?; ok {
        cw.world_set_mut_damage_taken_mult(w, id, cw.MutDamageTakenMultComp{ mult = dtm.mult })
    }
    if def.has_mut_wall_phase {
        cw.world_set_mut_wall_phase(w, id)
    }
    if bm, ok := def.mut_body_melee.?; ok {
        cw.world_set_mut_body_melee(w, id, cw.MutBodyMeleeComp{
            damage       = bm.damage,
            arc_angle    = bm.arc_angle,
            range        = bm.range,
            cooldown_max = bm.cooldown_max,
        })
    }
    if ct, ok := def.mut_corpse_trigger.?; ok {
        cw.world_set_mut_corpse_trigger(w, id, cw.MutCorpseTriggerComp{
            radius = ct.radius,
            dps    = ct.dps,
        })
    }
    if def.has_mut_hide_enemy_sprites {
        cw.world_set_mut_hide_enemy_sprites(w, id)
    }
    if udm, ok := def.mut_unseen_damage_mult.?; ok {
        cw.world_set_mut_unseen_damage_mult(w, id, cw.MutUnseenDamageMultComp{
            mult          = udm.mult,
            vision_radius = udm.vision_radius,
        })
    }

    return id
}

@(private = "file")
jf32 :: proc(v: json.Value) -> f32 {
    switch n in v {
    case json.Float:   return f32(n)
    case json.Integer: return f32(n)
    case json.Null, bool, string, json.Array, json.Object: // not numeric — fall through
    }
    return 0
}
