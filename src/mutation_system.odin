package main


MutationBranch :: enum u8 { Corpus, Shadow, Venom }

MutationDef :: struct {
    name:       string,
    lore:       string,
    effect:     string,
    branch:     MutationBranch,
    serum_cost: int,
    conflicts:  [2]MutationType,
}

MUTATION_DEFS := [MutationType]MutationDef{
    .None = {},


    .SerratedHands = {
        name       = "Serrated Hands",
        lore       = "Bone fused with iron. Weapons are for the weak.",
        effect     = "Cannot equip weapons. Bare-hand melee deals x4 damage in a 90 degree cleave arc.",
        branch     = .Corpus,
        serum_cost = 5,
    },
    .HollowBones = {
        name       = "Hollow Bones",
        lore       = "The skeleton empties itself. Speed is life.",
        effect     = "Cannot wear armour. +70% move speed. 3 dodge charges. Pass through enemy bodies.",
        branch     = .Corpus,
        serum_cost = 4,
    },
    .Exoskeleton = {
        name       = "Exoskeleton",
        lore       = "Chitin plates seal the flesh. Stillness is strength.",
        effect     = "Cannot move while shooting. While stationary, shield regenerates (40 HP). Moving breaks the shield.",
        branch     = .Corpus,
        serum_cost = 4,
    },
    .Symbiote = {
        name       = "Symbiote",
        lore       = "The parasite demands company. Together or nothing.",
        effect     = "HP pool is shared equally with all allies within 200px. All damage and healing is split.",
        branch     = .Corpus,
        serum_cost = 5,
        conflicts  = { .GlassCannon, .None },
    },
    .LivingBomb = {
        name       = "Living Bomb",
        lore       = "Death is just the ignition point.",
        effect     = "Reaching 0 HP detonates a 150px AoE explosion (100% max HP as damage) then revives at 1 HP. 45s cooldown.",
        branch     = .Corpus,
        serum_cost = 6,
        conflicts  = { .DeadmansTrigger, .None },
    },


    .GlassCannon = {
        name       = "Glass Cannon",
        lore       = "Abandon the body. Become the bullet.",
        effect     = "Max HP is permanently 1. All damage you deal is multiplied by 5.",
        branch     = .Shadow,
        serum_cost = 6,
        conflicts  = { .Symbiote, .None },
    },
    .BlindFire = {
        name       = "Blind Fire",
        lore       = "Eyes are a crutch. Learn the shape of violence.",
        effect     = "Enemy sprites are invisible to you. Every hit on an unseen enemy deals x4 damage.",
        branch     = .Shadow,
        serum_cost = 5,
    },
    .Timelock = {
        name       = "Timelock",
        lore       = "The shot freezes the world. Only the bullet moves.",
        effect     = "Firing roots you for 0.4s. During the root, projectile speed x0.3 and damage x2.",
        branch     = .Shadow,
        serum_cost = 4,
    },
    .SpectralForm = {
        name       = "Spectral Form",
        lore       = "Flesh is optional. Pass through everything, take nothing.",
        effect     = "Walk through walls and enemies. Cannot pick up items or gold. Deal x2 damage.",
        branch     = .Shadow,
        serum_cost = 5,
    },
    .DeadmansTrigger = {
        name       = "Deadman's Trigger",
        lore       = "The edge between alive and dead is where you live.",
        effect     = "You die at 15% HP instead of 0%. Missing HP scales damage: at 16% HP you deal x6.",
        branch     = .Shadow,
        serum_cost = 5,
        conflicts  = { .LivingBomb, .None },
    },


    .BloodFrenzy = {
        name       = "Blood Frenzy",
        lore       = "The body feeds on death. Stop killing, start dying.",
        effect     = "Cannot be healed by any source. Killing fully restores HP. 8s without a kill deals 8 HP/s self-damage.",
        branch     = .Venom,
        serum_cost = 5,
        conflicts  = { .ParasiteKing, .None },
    },
    .ToxicFlesh = {
        name       = "Toxic Flesh",
        lore       = "The rot becomes the armor. Get close. Let them breathe.",
        effect     = "Emit a 90px poison cloud at all times (half potency hits you too). Enemies killed inside drop x2 loot.",
        branch     = .Venom,
        serum_cost = 4,
    },
    .ParasiteKing = {
        name       = "Parasite King",
        lore       = "Nourishment is for prey. Feed from the source.",
        effect     = "Healing pickups have no effect on you. Each bullet hit steals 4 HP from the target.",
        branch     = .Venom,
        serum_cost = 4,
        conflicts  = { .BloodFrenzy, .None },
    },
    .CorpseTide = {
        name       = "Corpse Tide",
        lore       = "You don't kill. You orchestrate.",
        effect     = "Your bullets cannot deal killing blows, enemies stop at 1 HP. Enemies at 1 HP take x10 damage from each other.",
        branch     = .Venom,
        serum_cost = 5,
    },
    .Metamorphosis = {
        name       = "Metamorphosis",
        lore       = "Shed the tools. The body is the weapon.",
        effect     = "Cannot use any active abilities. All passive effects apply at x2 strength. Serum pickups grant x3 serums.",
        branch     = .Venom,
        serum_cost = 6,
    },


    .HeartCage = {
        name       = "Heart Cage",
        lore       = "A second heart grows outside the body. Feed it well.",
        effect     = "An external heart (60% of your max HP) orbits you and absorbs all damage. Enemies target it instead of you. If the heart is destroyed, you die.",
        branch     = .Corpus,
        serum_cost = 6,
    },
    .ThornPact = {
        name       = "Thorn Pact",
        lore       = "The wound shares itself. Pain is a gift you give back.",
        effect     = "40% of all damage you take is reflected to the attacker. All healing you receive is reduced by 50%.",
        branch     = .Corpus,
        serum_cost = 5,
    },


    .CarrionCrown = {
        name       = "Carrion Crown",
        lore       = "Death is not the end. It is a recruitment.",
        effect     = "Enemies you kill have a 30% chance to reanimate as your servant (max 3). Servants attack other enemies.",
        branch     = .Shadow,
        serum_cost = 6,
    },
    .FalseSaint = {
        name       = "False Saint",
        lore       = "A halo of dread. They come not from faith, but from fear.",
        effect     = "Enemies within 200px move 40% slower. Idle enemies within 400px are forced to aggro toward you.",
        branch     = .Shadow,
        serum_cost = 5,
    },


    .BlackLung = {
        name       = "Black Lung",
        lore       = "Breathe in the black. Let it build. Release it.",
        effect     = "Taking damage builds pressure (0-100). At 100, you emit 20 HP/s in a 60px radius. Pressure decays at 5/s.",
        branch     = .Venom,
        serum_cost = 5,
    },
}

mutation_get_entity :: proc(w: ^World, player_id: int, mt: MutationType) -> int {
    if mt == .None { return INVALID_ENTITY }
    if !world_has_component(w, player_id, .MutationContainer) { return INVALID_ENTITY }
    mc := comp_get(w, player_id, .MutationContainer, MutationContainerComp)
    for i in 0..<mc.entity_count {
        eid := mc.entities[i]
        if !world_is_valid(w, eid) { continue }
        if !world_has_component(w, eid, .Mut) { continue }
        if comp_get(w, eid, .Mut, MutComp).type_id == mt { return eid }
    }
    return INVALID_ENTITY
}

player_has_mutation :: proc(w: ^World, player_id: int, mt: MutationType) -> bool {
    return mutation_get_entity(w, player_id, mt) != INVALID_ENTITY
}

mutation_get_state :: proc(w: ^World, player_id: int, mt: MutationType) -> ^MutComp {
    eid := mutation_get_entity(w, player_id, mt)
    if eid == INVALID_ENTITY { return nil }
    return comp_get(w, eid, .Mut, MutComp)
}

@(private = "file")
mutation_template_name :: proc(mt: MutationType) -> string {
    #partial switch mt {
    case .GlassCannon: return "mut_glass_cannon"
    case .SerratedHands: return "mut_serrated_hands"
    case .HollowBones: return "mut_hollow_bones"
    case .Exoskeleton: return "mut_exoskeleton"
    case .Symbiote: return "mut_symbiote"
    case .LivingBomb: return "mut_living_bomb"
    case .BlindFire: return "mut_blind_fire"
    case .Timelock:    return "mut_timelock"
    case .BloodFrenzy: return "mut_blood_frenzy"
    case .ToxicFlesh: return "mut_toxic_flesh"
    case .ParasiteKing: return "mut_parasite_king"
    case .SpectralForm: return "mut_spectral_form"
    case .CorpseTide: return "mut_corpse_tide"
    case .DeadmansTrigger: return "mut_deadmans_trigger"
    case .Metamorphosis: return "mut_metamorphosis"

    case .HeartCage:    return ""
    case .ThornPact:    return ""
    case .CarrionCrown: return ""
    case .FalseSaint:   return ""
    case .BlackLung:    return ""
    }
    return ""
}

player_has_mutation_effect :: proc(w: ^World, player_id: int, ct: ComponentType) -> bool {
    if !world_has_component(w, player_id, .MutationContainer) { return false }
    mc := comp_get(w, player_id, .MutationContainer, MutationContainerComp)
    for i in 0..<mc.entity_count {
        eid := mc.entities[i]
        if !world_is_valid(w, eid) { continue }
        if world_has_component(w, eid, ct) { return true }
    }
    return false
}

player_get_root_on_fire :: proc(w: ^World, player_id: int) -> ^MutRootOnFireComp {
    if !world_has_component(w, player_id, .MutationContainer) { return nil }
    mc := comp_get(w, player_id, .MutationContainer, MutationContainerComp)
    for i in 0..<mc.entity_count {
        eid := mc.entities[i]
        if !world_is_valid(w, eid) { continue }
        if world_has_component(w, eid, .MutRootOnFire) {
            return comp_get(w, eid, .MutRootOnFire, MutRootOnFireComp)
        }
    }
    return nil
}

mutation_conflicts :: proc(w: ^World, player_id: int, mt: MutationType) -> bool {
    def := &MUTATION_DEFS[mt]
    for c in def.conflicts {
        if c == .None { continue }
        if player_has_mutation(w, player_id, c) { return true }
    }
    if !world_has_component(w, player_id, .MutationContainer) { return false }
    mc := comp_get(w, player_id, .MutationContainer, MutationContainerComp)
    for i in 0..<mc.entity_count {
        eid := mc.entities[i]
        if !world_is_valid(w, eid) { continue }
        if !world_has_component(w, eid, .Mut) { continue }
        existing := comp_get(w, eid, .Mut, MutComp).type_id
        for c in MUTATION_DEFS[existing].conflicts {
            if c == mt { return true }
        }
    }
    return false
}

mutation_can_unlock :: proc(w: ^World, player_id: int, mt: MutationType) -> bool {
    if mt == .None { return false }
    if player_has_mutation(w, player_id, mt) { return false }
    if mutation_conflicts(w, player_id, mt) { return false }
    if !world_has_component(w, player_id, .MutationContainer) { return false }
    mc := comp_get(w, player_id, .MutationContainer, MutationContainerComp)
    if mc.entity_count >= MAX_MUTATION_SLOTS { return false }
    return mc.serums >= MUTATION_DEFS[mt].serum_cost
}

mutation_init_components :: proc(w: ^World, player_id: int, eid: int, mt: MutationType) {
    switch mt {
    case .HeartCage:
        max_hp := f32(60)
        if world_has_component(w, player_id, .Health) {
            max_hp = comp_get(w, player_id, .Health, HealthComp).max * 0.6
        }
        heart_id := _spawn_heart_entity(w, player_id, max_hp)

        init_angle := f32(player_id % 7) * 0.9
        comp_set(w, eid, .MutHeartCage, MutHeartCageComp{
            heart_id    = heart_id,
            max_hp_pct  = 0.6,
            orbit_angle = init_angle,
        })

    case .ThornPact:
        comp_set(w, eid, .MutThornPact, MutThornPactComp{
            reflect_pct    = 0.4,
            slow_heal_mult = 0.5,
        })

    case .CarrionCrown:
        c := MutCarrionCrownComp{}
        for &sid in c.servant_ids { sid = INVALID_ENTITY }
        comp_set(w, eid, .MutCarrionCrown, c)

    case .FalseSaint:
        comp_set(w, eid, .MutFalseSaint, MutFalseSaintComp{
            aura_radius   = 200.0,
            slow_mult     = 0.60,
            beacon_radius = 400.0,
        })

    case .BlackLung:
        comp_set(w, eid, .MutBlackLung, MutBlackLungComp{
            pressure     = 0,
            regen_rate   = 5.0,
            gain_per_hit = 15.0,
            dps_max      = 20.0,
            radius       = 60.0,
        })
    case .None:
    case .SerratedHands:
    case .HollowBones:
    case .Exoskeleton:
    case .Symbiote:
    case .LivingBomb:
    case .GlassCannon:
    case .BlindFire:
    case .Timelock:
    case .SpectralForm:
    case .DeadmansTrigger:
    case .BloodFrenzy:
    case .ToxicFlesh:
    case .ParasiteKing:
    case .CorpseTide:
    case .Metamorphosis:
    }
}


mutation_restore_direct :: proc(w: ^World, player_id: int, mt: MutationType) {
    if mt == .None { return }
    if !world_has_component(w, player_id, .MutationContainer) { return }

    tname := mutation_template_name(mt)
    eid   := INVALID_ENTITY
    if tname != "" {
        eid = spawn_from_def(w, find_entity_def(g_entity_defs, tname))
    }
    if eid == INVALID_ENTITY {
        eid = world_create_entity(w)
    }
    comp_set(w, eid, .Mut, MutComp{ type_id = mt })
    mutation_init_components(w, player_id, eid, mt)

    mc := comp_get(w, player_id, .MutationContainer, MutationContainerComp)
    if mc.entity_count < MAX_MUTATION_SLOTS {
        mc.entities[mc.entity_count] = eid
        mc.entity_count += 1
    }
}

mutation_unlock :: proc(w: ^World, player_id: int, mt: MutationType) -> bool {
    if !mutation_can_unlock(w, player_id, mt) { return false }

    mc := comp_get(w, player_id, .MutationContainer, MutationContainerComp)
    mc.serums -= MUTATION_DEFS[mt].serum_cost


    tname := mutation_template_name(mt)
    eid   := INVALID_ENTITY
    if tname != "" {
        eid = spawn_from_def(w, find_entity_def(g_entity_defs, tname))
    }
    if eid == INVALID_ENTITY {
        eid = world_create_entity(w)
    }
    comp_set(w, eid, .Mut, MutComp{ type_id = mt })
    mutation_init_components(w, player_id, eid, mt)


    mc = comp_get(w, player_id, .MutationContainer, MutationContainerComp)
    mc.entities[mc.entity_count] = eid
    mc.entity_count += 1
    return true
}


MUT_CLEAR_COST :: 3


mutation_clear_all :: proc(w: ^World, player_id: int) -> bool {
    if !world_has_component(w, player_id, .MutationContainer) { return false }
    mc := comp_get(w, player_id, .MutationContainer, MutationContainerComp)
    if mc.entity_count == 0       { return false }
    if mc.serums < MUT_CLEAR_COST { return false }

    mc.serums -= MUT_CLEAR_COST


    n    := mc.entity_count
    eids : [MAX_MUTATION_SLOTS]int
    for i in 0..<n { eids[i] = mc.entities[i] }

    for i in 0..<n {
        eid := eids[i]
        if !world_is_valid(w, eid) { continue }


        if world_has_component(w, eid, .MutHeartCage) {
            hc := comp_get(w, eid, .MutHeartCage, MutHeartCageComp)
            if world_is_valid(w, hc.heart_id) {
                world_destroy_entity(w, hc.heart_id)
            }
        }


        if world_has_component(w, eid, .MutCarrionCrown) {
            cc := comp_get(w, eid, .MutCarrionCrown, MutCarrionCrownComp)
            for si in 0..<CARRION_MAX_SERVANTS {
                sid := cc.servant_ids[si]
                if sid == INVALID_ENTITY         { continue }
                if !world_is_valid(w, sid)       { continue }
                world_destroy_entity(w, sid)
            }
        }

        world_destroy_entity(w, eid)
    }


    mc = comp_get(w, player_id, .MutationContainer, MutationContainerComp)
    mc.entity_count = 0
    return true
}


mutation_name_to_type :: proc(template_name: string) -> MutationType {
    for mt in MutationType {
        if mt == .None { continue }
        if mutation_template_name(mt) == template_name { return mt }
    }
    return .None
}
