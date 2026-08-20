package main

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"

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

GreyboxDef :: struct {
    shape:   GreyboxShape,
    size:    [3]f32,
    r, g, b: u8,
    solid:   bool,
}

InteractableDef :: struct {
    radius:       f32,
    prompt:       string,
    active:       bool,
    cooldown_max: f32,
}

OpenableDef :: struct {
    is_open:      bool,
    link_id:      u8,
    blocks_sight: bool,
}

LockableDef :: struct {
    key_id:    u8,
    is_locked: bool,
}

SignalEmitterDef :: struct {
    link_id:       u8,
    is_on:         bool,
    is_toggle:     bool,
    needs_weight:  bool,
    weight_radius: f32,
}

ContainerDef :: struct {
    kind:          ContainerKind,
    loot_table_id: u8,
    gold_min:      u16,
    gold_max:      u16,
    emits_signal:  bool,
    link_id:       u8,
}

LoreItemDef :: struct {
    lore_id: u8,
}

PhonographDef :: struct {
    recording_id: u8,
}

KeyPickupDef :: struct {
    key_id: u8,
    label:  string,
}

WeaponDef :: struct {
    type:             WeaponType,
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
    ai_type:      AIType,
    pellet_count: int,
    spread_angle: f32,
}

DodgeDef :: struct {
    duration:     f32,
    speed:        f32,
    cooldown:     f32,
}

RenderConfigDef :: struct {
    display_name:    string,
    sprite_name:     string,
    sprite_scale:    f32,
    world_size:      f32,
    render_layer:    RenderLayer,
    show_hp_bar:     bool,
    show_dir_tip:    bool,
    top_down_sprite: bool,
}

NPCDef :: struct {
    npc_type:        NPCType,
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
    radius:          f32,
    dps:             f32,
    self_fraction:   f32,
    effect_type:     StatusEffectType,
    effect_strength: f32,
    effect_duration: f32,
    light_r:         f32,
    light_g:         f32,
    light_b:         f32,
    light_radius:    f32,
    light_intensity: f32,
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

FlammableDef :: struct {
    is_immune: bool
}

EntityDef :: struct {
    name:         string,

    transform:    Maybe(TransformDef),
    health:       Maybe(HealthDef),
    collider:     Maybe(ColliderDef),
    greybox:      Maybe(GreyboxDef),
    interactable: Maybe(InteractableDef),
    openable:     Maybe(OpenableDef),
    lockable:     Maybe(LockableDef),
    signal_emit:  Maybe(SignalEmitterDef),
    container:    Maybe(ContainerDef),
    lore_item:    Maybe(LoreItemDef),
    phonograph:   Maybe(PhonographDef),
    key_pickup:   Maybe(KeyPickupDef),
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
    flammbles:                Maybe(FlammableDef),

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

    mutations: [dynamic]string,
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

        if g_obj, g_ok := obj["greybox"].(json.Object); g_ok {
            gb: GreyboxDef
            gb.size = {f32(TILE_SIZE), f32(TILE_SIZE), f32(TILE_SIZE)}
            gb.r, gb.g, gb.b = 150, 150, 158
            gb.solid = true
            if v, ok2 := g_obj["shape"].(string); ok2 {
                switch v {
                case "box":      gb.shape = .Box
                case "ramp":     gb.shape = .Ramp
                case "wedge":    gb.shape = .Wedge
                case "cylinder": gb.shape = .Cylinder
                case "platform": gb.shape = .Platform
                }
            }
            if v, ok2 := g_obj["size"].(json.Array); ok2 && len(v) >= 3 {
                gb.size = {jf32(v[0]), jf32(v[1]), jf32(v[2])}
            }
            if v, ok2 := g_obj["color"].(json.Array); ok2 && len(v) >= 3 {
                gb.r, gb.g, gb.b = u8(jf32(v[0])), u8(jf32(v[1])), u8(jf32(v[2]))
            }
            if v, ok2 := g_obj["solid"]; ok2 {
                if b, b_ok := v.(bool); b_ok { gb.solid = b }
            }
            def.greybox = gb
        }

        if i_obj, i_ok := obj["interactable"].(json.Object); i_ok {
            d: InteractableDef
            d.radius = f32(TILE_SIZE) * 1.5
            d.active = true
            if v, ok2 := i_obj["radius"];       ok2 { d.radius       = jf32(v) }
            if v, ok2 := i_obj["cooldown_max"]; ok2 { d.cooldown_max = jf32(v) }
            if v, ok2 := i_obj["prompt"].(string); ok2 { d.prompt = strings.clone(v) }
            if v, ok2 := i_obj["active"]; ok2 { if b, bk := v.(bool); bk { d.active = b } }
            def.interactable = d
        }

        if o_obj, o_ok := obj["openable"].(json.Object); o_ok {
            d: OpenableDef
            if v, ok2 := o_obj["link_id"]; ok2 { d.link_id = u8(jf32(v)) }
            if v, ok2 := o_obj["is_open"]; ok2 { if b, bk := v.(bool); bk { d.is_open = b } }
            if v, ok2 := o_obj["blocks_sight"]; ok2 { if b, bk := v.(bool); bk { d.blocks_sight = b } }
            def.openable = d
        }

        if l_obj, l_ok := obj["lockable"].(json.Object); l_ok {
            d: LockableDef
            if v, ok2 := l_obj["key_id"]; ok2 { d.key_id = u8(jf32(v)) }
            if v, ok2 := l_obj["is_locked"]; ok2 { if b, bk := v.(bool); bk { d.is_locked = b } }
            def.lockable = d
        }

        if s_obj, s_ok := obj["signal_emitter"].(json.Object); s_ok {
            d: SignalEmitterDef
            d.is_toggle = true
            if v, ok2 := s_obj["link_id"];       ok2 { d.link_id       = u8(jf32(v)) }
            if v, ok2 := s_obj["weight_radius"]; ok2 { d.weight_radius = jf32(v) }
            if v, ok2 := s_obj["is_on"];        ok2 { if b, bk := v.(bool); bk { d.is_on = b } }
            if v, ok2 := s_obj["is_toggle"];    ok2 { if b, bk := v.(bool); bk { d.is_toggle = b } }
            if v, ok2 := s_obj["needs_weight"]; ok2 { if b, bk := v.(bool); bk { d.needs_weight = b } }
            def.signal_emit = d
        }

        if c_obj2, c_ok2 := obj["container"].(json.Object); c_ok2 {
            d: ContainerDef
            if v, ok2 := c_obj2["kind"].(string); ok2 {
                switch v {
                case "chest":   d.kind = .Chest
                case "crate":   d.kind = .Crate
                case "locker":  d.kind = .Locker
                case "cabinet": d.kind = .Cabinet
                }
            }
            if v, ok2 := c_obj2["loot_table_id"]; ok2 { d.loot_table_id = u8(jf32(v)) }
            if v, ok2 := c_obj2["gold_min"];      ok2 { d.gold_min      = u16(jf32(v)) }
            if v, ok2 := c_obj2["gold_max"];      ok2 { d.gold_max      = u16(jf32(v)) }
            if v, ok2 := c_obj2["link_id"];       ok2 { d.link_id       = u8(jf32(v)) }
            if v, ok2 := c_obj2["emits_signal"];  ok2 { if b, bk := v.(bool); bk { d.emits_signal = b } }
            def.container = d
        }

        if lr_obj, lr_ok := obj["lore_item"].(json.Object); lr_ok {
            d: LoreItemDef
            if v, ok2 := lr_obj["lore_id"]; ok2 { d.lore_id = u8(jf32(v)) }
            def.lore_item = d
        }

        if ph_obj, ph_ok := obj["phonograph"].(json.Object); ph_ok {
            d: PhonographDef
            if v, ok2 := ph_obj["recording_id"]; ok2 { d.recording_id = u8(jf32(v)) }
            def.phonograph = d
        }

        if k_obj, k_ok := obj["key_pickup"].(json.Object); k_ok {
            d: KeyPickupDef
            if v, ok2 := k_obj["key_id"]; ok2 { d.key_id = u8(jf32(v)) }
            if v, ok2 := k_obj["label"].(string); ok2 { d.label = strings.clone(v) }
            def.key_pickup = d
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
            if v, ok2 := r_obj["top_down_sprite"].(bool); ok2 {
                r.top_down_sprite = v
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
                case "stash":
                    n.npc_type = .Stash
                case "ability_vendor":
                    n.npc_type = .AbilityVendor
                case "quest_board":
                    n.npc_type = .QuestBoard
                case "quartermaster":
                    n.npc_type = .Quartermaster
                case "surgeon":
                    n.npc_type = .Surgeon
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
            if v, ok2 := pd_obj["radius"];           ok2 { pd.radius          = jf32(v) }
            if v, ok2 := pd_obj["dps"];              ok2 { pd.dps             = jf32(v) }
            if v, ok2 := pd_obj["self_fraction"];    ok2 { pd.self_fraction   = jf32(v) }
            if v, ok2 := pd_obj["effect_strength"];  ok2 { pd.effect_strength = jf32(v) }
            if v, ok2 := pd_obj["effect_duration"];  ok2 { pd.effect_duration = jf32(v) }
            if v, ok2 := pd_obj["effect_type"];      ok2 {
                if s, s_ok := v.(json.String); s_ok {
                    switch s {
                    case "poison": pd.effect_type = .Poison
                    case "burn":   pd.effect_type = .Burn
                    case "slow":   pd.effect_type = .Slow
                    case "stun":   pd.effect_type = .Stun
                    case "root":   pd.effect_type = .Root
                    }
                }
            }
            if v, ok2 := pd_obj["light_r"];         ok2 { pd.light_r         = jf32(v) }
            if v, ok2 := pd_obj["light_g"];         ok2 { pd.light_g         = jf32(v) }
            if v, ok2 := pd_obj["light_b"];         ok2 { pd.light_b         = jf32(v) }
            if v, ok2 := pd_obj["light_radius"];    ok2 { pd.light_radius    = jf32(v) }
            if v, ok2 := pd_obj["light_intensity"]; ok2 { pd.light_intensity = jf32(v) }
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

        if m_arr, m_ok := obj["mutations"].(json.Array); m_ok {
            def.mutations = make([dynamic]string, 0, len(m_arr), allocator)
            for mv in m_arr {
                if s, s_ok := mv.(json.String); s_ok {
                    append(&def.mutations, strings.clone(s, allocator))
                }
            }
        }

        if f_obj, f_ok := obj["flammable"].(json.Object); f_ok {
            f: FlammableDef
            if v, ok2 := f_obj["is_immune"].(bool); ok2 { f.is_immune = v }
            def.flammbles = f
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
        for s in d.mutations {
            delete(s, allocator)
        }
        delete(d.mutations)
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

spawn_from_def :: proc(w: ^World, def: ^EntityDef) -> int {
    if def == nil { return INVALID_ENTITY }

    id := world_create_entity(w)

    if t, ok := def.transform.?; ok {
        comp_set(w, id, .Transform, TransformComp{
            position = t.position,
            rotation = t.rotation,
        })
    }
    if def.has_velocity {
        comp_set(w, id, .Velocity, VelocityComp{})
    }
    if h, ok := def.health.?; ok {
        comp_set(w, id, .Health, HealthComp{
            current    = h.current,
            max        = h.max,
            energy     = h.energy,
            max_energy = h.max_energy,
        })
    }
    if def.has_input {
        comp_set(w, id, .InputState, InputStateComp{})
    }
    if gb, ok := def.greybox.?; ok {
        comp_set(w, id, .Greybox, GreyboxComp{
            shape = gb.shape,
            size  = gb.size,
            r     = gb.r,
            g     = gb.g,
            b     = gb.b,
            solid = gb.solid,
        })
    }

    if d, ok := def.interactable.?; ok {
        prompt: [48]u8
        if d.prompt != "" {
            key := strings.clone_to_cstring(d.prompt, context.temp_allocator)
            copy(prompt[:], string(loc_lookup(key)))
        }
        comp_set(w, id, .Interactable, InteractableComp{
            radius       = d.radius,
            prompt       = prompt,
            active       = d.active,
            cooldown_max = d.cooldown_max,
        })
    }
    if d, ok := def.openable.?; ok {
        comp_set(w, id, .Openable, OpenableComp{
            is_open      = d.is_open,
            link_id      = d.link_id,
            blocks_sight = d.blocks_sight,
        })
    }
    if d, ok := def.lockable.?; ok {
        comp_set(w, id, .Lockable, LockableComp{ key_id = d.key_id, is_locked = d.is_locked })
    }
    if d, ok := def.signal_emit.?; ok {
        comp_set(w, id, .SignalEmitter, SignalEmitterComp{
            link_id       = d.link_id,
            is_on         = d.is_on,
            is_toggle     = d.is_toggle,
            needs_weight  = d.needs_weight,
            weight_radius = d.weight_radius,
        })
    }
    if d, ok := def.container.?; ok {
        comp_set(w, id, .Container, ContainerComp{
            kind          = d.kind,
            loot_table_id = d.loot_table_id,
            gold_min      = d.gold_min,
            gold_max      = d.gold_max,
            emits_signal  = d.emits_signal,
            link_id       = d.link_id,
        })
    }
    if d, ok := def.lore_item.?; ok {
        comp_set(w, id, .LoreItem, LoreItemComp{ lore_id = d.lore_id })
    }
    if d, ok := def.phonograph.?; ok {
        comp_set(w, id, .Phonograph, PhonographComp{ recording_id = d.recording_id })
    }
    if d, ok := def.key_pickup.?; ok {
        label: [40]u8
        if d.label != "" { copy(label[:], d.label) }
        comp_set(w, id, .KeyPickup, KeyPickupComp{ key_id = d.key_id, label = label })
    }
    if c, ok := def.collider.?; ok {
        comp_set(w, id, .Collider, ColliderComp{
            radius     = c.radius,
            faction    = c.faction,
            is_trigger = c.is_trigger,
        })
    }
    if wp, ok := def.weapon.?; ok {
        comp_set(w, id, .Weapon, WeaponComp{
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
        comp_set(w, id, .AIAgent, AIAgentComp{
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
        comp_set(w, id, .DodgeState, DodgeComp{
            duration     = d.duration,
            speed        = d.speed,
            cooldown_max = d.cooldown,
        })
    }
    if rc, ok := def.render_cfg.?; ok {
        comp: RenderConfigComp
        render_config_set_name(&comp, rc.display_name)
        if len(rc.sprite_name) > 0 {
            render_config_set_sprite(&comp, rc.sprite_name)
        }
        comp.sprite_scale = rc.sprite_scale if rc.sprite_scale > 0 else 1.0
        comp.world_size   = rc.world_size
        comp.render_layer = rc.render_layer
        comp.show_hp_bar  = rc.show_hp_bar
        comp.show_dir_tip    = rc.show_dir_tip
        comp.top_down_sprite = rc.top_down_sprite
        comp_set(w, id, .RenderConfig, comp)

        comp_set(w, id, .AnimState, AnimStateComp{})
    }
    if def.has_fog_of_war {
        comp_add(w, id, .FogOfWar)
    }
    if n, ok := def.npc.?; ok {
        comp_set(w, id, .NPC, NPCComp{
            npc_type        = n.npc_type,
            interact_radius = n.interact_radius,
        })
    }
    if md, ok := def.mut_damage_mult.?; ok {
        comp_set(w, id, .MutDamageMult, MutDamageMultComp{
            mult = md.mult,
        })
    }
    if def.has_mut_lock_hp_to_one {
        comp_add(w, id, .MutLockHpToOne)
    }
    if mr, ok := def.mut_root_on_fire.?; ok {
        comp_set(w, id, .MutRootOnFire, MutRootOnFireComp{
            duration                 = mr.duration,
            damage_mult_while_rooted = mr.damage_mult_while_rooted,
            projectile_speed_mult    = mr.projectile_speed_mult,
        })
    }
    if tsd, ok := def.mut_timed_self_damage.?; ok {
        comp_set(w, id, .MutTimedSelfDamage, MutTimedSelfDamageComp{
            grace = tsd.grace,
            dps   = tsd.dps,
        })
    }
    if def.has_mut_block_healing {
        comp_add(w, id, .MutBlockHealing)
    }
    if msm, ok := def.mut_move_speed_mult.?; ok {
        comp_set(w, id, .MutMoveSpeedMult, MutMoveSpeedMultComp{ mult = msm.mult })
    }
    if def.has_mut_block_ranged {
        comp_add(w, id, .MutBlockRanged)
    }
    if def.has_mut_block_pickup_heal {
        comp_add(w, id, .MutBlockPickupHeal)
    }
    if sgm, ok := def.mut_serum_gain_mult.?; ok {
        comp_set(w, id, .MutSerumGainMult, MutSerumGainMultComp{ mult = sgm.mult })
    }
    if def.has_mut_block_pickups {
        comp_add(w, id, .MutBlockPickups)
    }
    if def.has_mut_nonlethal_shots {
        comp_add(w, id, .MutNonlethalShots)
    }
    if def.has_mut_disable_actives {
        comp_add(w, id, .MutDisableActives)
    }
    if edt, ok := def.mut_early_death_threshold.?; ok {
        comp_set(w, id, .MutEarlyDeathThreshold, MutEarlyDeathThresholdComp{
            threshold_pct = edt.threshold_pct,
        })
    }
    if mhd, ok := def.mut_missing_health_damage.?; ok {
        comp_set(w, id, .MutMissingHealthDamage, MutMissingHealthDamageComp{
            max_mult     = mhd.max_mult,
            floor_hp_pct = mhd.floor_hp_pct,
        })
    }
    if mpp, ok := def.mut_passive_power.?; ok {
        comp_set(w, id, .MutPassivePower, MutPassivePowerComp{
            mult = mpp.mult,
        })
    }
    if kh, ok := def.mut_kill_heal.?; ok {
        comp_set(w, id, .MutKillHeal, MutKillHealComp{ heal_pct = kh.heal_pct })
    }
    if ls, ok := def.mut_lifesteal.?; ok {
        comp_set(w, id, .MutLifesteal, MutLifestealComp{ hp_per_hit = ls.hp_per_hit })
    }
    if pd, ok := def.mut_proximity_damage.?; ok {
        comp_set(w, id, .MutProximityDamage, MutProximityDamageComp{
            radius          = pd.radius,
            dps             = pd.dps,
            self_fraction   = pd.self_fraction,
            effect_type     = pd.effect_type,
            effect_strength = pd.effect_strength,
            effect_duration = pd.effect_duration,
            light_color     = { pd.light_r, pd.light_g, pd.light_b },
            light_radius    = pd.light_radius,
            light_intensity = pd.light_intensity,
        })
    }
    if ode, ok := def.mut_on_death_explode.?; ok {
        comp_set(w, id, .MutOnDeathExplode, MutOnDeathExplodeComp{
            radius       = ode.radius,
            damage_pct   = ode.damage_pct,
            cooldown_max = ode.cooldown_max,
        })
    }
    if ss, ok := def.mut_stationary_shield.?; ok {
        comp_set(w, id, .MutStationaryShield, MutStationaryShieldComp{
            shield_max = ss.shield_max,
            regen_rate = ss.regen_rate,
        })
    }
    if edc, ok := def.mut_extra_dodge_charges.?; ok {
        comp_set(w, id, .MutExtraDodgeCharges, MutExtraDodgeChargesComp{
            count        = edc.count,
            charges      = edc.count,
            recharge_max = edc.recharge_max,
        })
    }
    if dtm, ok := def.mut_damage_taken_mult.?; ok {
        comp_set(w, id, .MutDamageTakenMult, MutDamageTakenMultComp{ mult = dtm.mult })
    }
    if def.has_mut_wall_phase {
        comp_add(w, id, .MutWallPhase)
    }
    if bm, ok := def.mut_body_melee.?; ok {
        comp_set(w, id, .MutBodyMelee, MutBodyMeleeComp{
            damage       = bm.damage,
            arc_angle    = bm.arc_angle,
            range        = bm.range,
            cooldown_max = bm.cooldown_max,
        })
    }
    if ct, ok := def.mut_corpse_trigger.?; ok {
        comp_set(w, id, .MutCorpseTrigger, MutCorpseTriggerComp{
            radius = ct.radius,
            dps    = ct.dps,
        })
    }
    if def.has_mut_hide_enemy_sprites {
        comp_add(w, id, .MutHideEnemySprites)
    }
    if udm, ok := def.mut_unseen_damage_mult.?; ok {
        comp_set(w, id, .MutUnseenDamageMult, MutUnseenDamageMultComp{
            mult          = udm.mult,
            vision_radius = udm.vision_radius,
        })
    }

    if len(def.mutations) > 0 {
        comp_set(w, id, .MutationContainer, mutation_container_empty())
        for name in def.mutations {
            mt := mutation_name_to_type(name)
            if mt != .None {
                mutation_restore_direct(w, id, mt)
            }
        }
    }

    if fc, ok := def.flammbles.?; ok {
        comp_set(w, id, .Flammable, FlammableComp{
            isImmune = fc.is_immune
        })
    }

    return id
}

@(private = "file")
jf32 :: proc(v: json.Value) -> f32 {
    switch n in v {
    case json.Float:   return f32(n)
    case json.Integer: return f32(n)
    case json.Null, bool, string, json.Array, json.Object:
    }
    return 0
}
