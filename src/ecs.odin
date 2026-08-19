package main

import ecs "cw:clockwork"

INVALID_ENTITY :: ecs.INVALID_ENTITY
MAX_PLAYERS    :: 4

World :: struct {
    using base:        ecs.World,

    player_ids:        [MAX_PLAYERS]int,
    local_player_slot: int,
    player_id:         int,

    damage_events:     [dynamic]DamageEvent,
    tagged:            [dynamic]int,
}

world_is_valid :: proc(w: ^World, id: int) -> bool {
    return ecs.world_is_valid(&w.base, id)
}

entity_is_active :: proc(e: ecs.Entity) -> bool {
    return ecs.entity_is_active(e)
}

world_has_component :: proc(w: ^World, id: int, ct: ComponentType) -> bool {
    return ecs.comp_has(&w.base, id, ct)
}

comp_get :: proc(w: ^World, id: int, ct: ComponentType, $T: typeid, loc := #caller_location) -> ^T {
    return ecs.comp_get(&w.base, id, ct, T, loc)
}

comp_set :: proc(w: ^World, id: int, ct: ComponentType, val: $T, loc := #caller_location) {
    ecs.comp_set(&w.base, id, ct, val, loc)
}

comp_add :: proc(w: ^World, id: int, ct: ComponentType) {
    ecs.comp_add(&w.base, id, ct)
}

comp_rm :: proc(w: ^World, id: int, ct: ComponentType) {
    ecs.comp_remove(&w.base, id, ct)
}

query_mask :: proc(types: ..ComponentType) -> ecs.Signature {
    m := ecs.Signature(0)
    for t in types {
        ecs.sig_set(&m, ecs.comp_id(t))
    }
    return m
}

world_query :: proc(w: ^World, m: ecs.Signature, allocator := context.allocator) -> []int {
    return ecs.query_collect(&w.base, m, allocator)
}

world_create_entity :: proc(w: ^World) -> int {
    return ecs.world_create_entity(&w.base)
}

world_destroy_entity :: proc(w: ^World, id: int) {
    ecs.world_mark_destroy(&w.base, id)
}

world_reset :: proc(w: ^World) {
    ecs.world_reset(&w.base)
    for &id in w.player_ids {id = INVALID_ENTITY}
    w.player_id = INVALID_ENTITY
    w.local_player_slot = 0
    clear(&w.damage_events)
    clear(&w.tagged)
}

world_push_damage :: proc(w: ^World, target_id: int, amount: f32, source_id: int = 0, kind: DamageKind = .Physical) {
    append(&w.damage_events, DamageEvent{target_id = target_id, amount = amount, source_id = source_id, kind = kind})
}

world_push_heal :: proc(w: ^World, target_id: int, amount: f32) {
    append(&w.damage_events, DamageEvent{target_id = target_id, amount = -amount})
}

world_clear_damage_events :: proc(w: ^World) {
    clear(&w.damage_events)
}

world_tag_destroy :: proc(w: ^World, id: int) {
    if id < 0 || id >= len(w.entities) {return}
    if .ToDestroy in w.entities[id].flags {return}
    w.entities[id].flags += {.ToDestroy}
    append(&w.tagged, id)
}

world_tag_is_destroy :: proc(w: ^World, id: int) -> bool {
    if id < 0 || id >= len(w.entities) {return false}
    return .ToDestroy in w.entities[id].flags
}

world_reap_tagged :: proc(w: ^World) {
    for id in w.tagged {
        ecs.world_mark_destroy(&w.base, id)
    }
    clear(&w.tagged)
}

make_world :: proc() -> World {
    w := World{}
    w.base = ecs.make_world()
    for &id in w.player_ids {id = INVALID_ENTITY}
    w.local_player_slot = 0
    w.player_id = INVALID_ENTITY

    ecs.comp_register(&w.base, ComponentType.Transform, TransformComp)
    ecs.comp_register(&w.base, ComponentType.Velocity, VelocityComp)
    ecs.comp_register(&w.base, ComponentType.Health, HealthComp)
    ecs.comp_register(&w.base, ComponentType.InputState, InputStateComp)
    ecs.comp_register(&w.base, ComponentType.WeaponSlot, WeaponSlotComp)
    ecs.comp_register(&w.base, ComponentType.MutationContainer, MutationContainerComp)
    ecs.comp_register(&w.base, ComponentType.MeshRenderer, MeshRendererComp)
    ecs.comp_register(&w.base, ComponentType.Collider, ColliderComp)
    ecs.comp_register(&w.base, ComponentType.Projectile, ProjectileComp)
    ecs.comp_register(&w.base, ComponentType.SelfDestruct, SelfDestructComp)
    ecs.comp_register(&w.base, ComponentType.AIAgent, AIAgentComp)
    ecs.comp_register(&w.base, ComponentType.ProjectileTag, ProjectileTagComp)
    ecs.comp_register(&w.base, ComponentType.Weapon, WeaponComp)
    ecs.comp_register(&w.base, ComponentType.Equipment, EquipmentComp)
    ecs.comp_register(&w.base, ComponentType.DodgeState, DodgeComp)
    ecs.comp_register(&w.base, ComponentType.RenderConfig, RenderConfigComp)
    ecs.comp_register(&w.base, ComponentType.MeleeArc, MeleeArcComp)
    ecs.comp_register(&w.base, ComponentType.Respawn, RespawnComp)
    ecs.comp_register(&w.base, ComponentType.Inventory, InventoryComp, _inv_clear)
    ecs.comp_register(&w.base, ComponentType.Item, ItemComp, _item_clear)
    ecs.comp_register(&w.base, ComponentType.GroundItem, GroundItemComp)
    ecs.comp_register(&w.base, ComponentType.Ability, AbilityComp)
    ecs.comp_register(&w.base, ComponentType.Stats, StatsComp)
    ecs.comp_register(&w.base, ComponentType.FogOfWar, FogOfWarComp)
    ecs.comp_register(&w.base, ComponentType.Extraction, ExtractionComp)
    ecs.comp_register(&w.base, ComponentType.Mut, MutComp)
    ecs.comp_register(&w.base, ComponentType.Player, PlayerComp)
    ecs.comp_register(&w.base, ComponentType.Wallet, WalletComp)
    ecs.comp_register(&w.base, ComponentType.Gold, GoldComp)
    ecs.comp_register(&w.base, ComponentType.NPC, NPCComp)
    ecs.comp_register(&w.base, ComponentType.MutDamageMult, MutDamageMultComp)
    ecs.comp_register(&w.base, ComponentType.MutLockHpToOne, MutLockHpToOneComp)
    ecs.comp_register(&w.base, ComponentType.MutRootOnFire, MutRootOnFireComp)
    ecs.comp_register(&w.base, ComponentType.MutTimedSelfDamage, MutTimedSelfDamageComp)
    ecs.comp_register(&w.base, ComponentType.MutBlockHealing, MutBlockHealingComp)
    ecs.comp_register(&w.base, ComponentType.MutMoveSpeedMult, MutMoveSpeedMultComp)
    ecs.comp_register(&w.base, ComponentType.MutBlockRanged, MutBlockRangedComp)
    ecs.comp_register(&w.base, ComponentType.MutBlockPickupHeal, MutBlockPickupHealComp)
    ecs.comp_register(&w.base, ComponentType.MutSerumGainMult, MutSerumGainMultComp)
    ecs.comp_register(&w.base, ComponentType.MutBlockPickups, MutBlockPickupsComp)
    ecs.comp_register(&w.base, ComponentType.MutNonlethalShots, MutNonlethalShotsComp)
    ecs.comp_register(&w.base, ComponentType.MutDisableActives, MutDisableActivesComp)
    ecs.comp_register(&w.base, ComponentType.MutEarlyDeathThreshold, MutEarlyDeathThresholdComp)
    ecs.comp_register(&w.base, ComponentType.MutMissingHealthDamage, MutMissingHealthDamageComp)
    ecs.comp_register(&w.base, ComponentType.MutPassivePower, MutPassivePowerComp)
    ecs.comp_register(&w.base, ComponentType.PointLight, PointLightComp)
    ecs.comp_register(&w.base, ComponentType.AnimState, AnimStateComp)
    ecs.comp_register(&w.base, ComponentType.MutKillHeal, MutKillHealComp)
    ecs.comp_register(&w.base, ComponentType.MutLifesteal, MutLifestealComp)
    ecs.comp_register(&w.base, ComponentType.MutProximityDamage, MutProximityDamageComp)
    ecs.comp_register(&w.base, ComponentType.MutOnDeathExplode, MutOnDeathExplodeComp)
    ecs.comp_register(&w.base, ComponentType.MutStationaryShield, MutStationaryShieldComp)
    ecs.comp_register(&w.base, ComponentType.MutExtraDodgeCharges, MutExtraDodgeChargesComp)
    ecs.comp_register(&w.base, ComponentType.MutDamageTakenMult, MutDamageTakenMultComp)
    ecs.comp_register(&w.base, ComponentType.MutWallPhase, MutWallPhaseComp)
    ecs.comp_register(&w.base, ComponentType.MutBodyMelee, MutBodyMeleeComp)
    ecs.comp_register(&w.base, ComponentType.MutCorpseTrigger, MutCorpseTriggerComp)
    ecs.comp_register(&w.base, ComponentType.MutHideEnemySprites, MutHideEnemySpritesComp)
    ecs.comp_register(&w.base, ComponentType.MutUnseenDamageMult, MutUnseenDamageMultComp)
    ecs.comp_register(&w.base, ComponentType.MutHeartCage, MutHeartCageComp)
    ecs.comp_register(&w.base, ComponentType.MutThornPact, MutThornPactComp)
    ecs.comp_register(&w.base, ComponentType.MutCarrionCrown, MutCarrionCrownComp)
    ecs.comp_register(&w.base, ComponentType.MutFalseSaint, MutFalseSaintComp)
    ecs.comp_register(&w.base, ComponentType.MutBlackLung, MutBlackLungComp)
    ecs.comp_register(&w.base, ComponentType.Reanimated, ReanimatedComp)
    ecs.comp_register(&w.base, ComponentType.StatusEffect, StatusEffectComp)
    ecs.comp_register(&w.base, ComponentType.Flammable, FlammableComp)
    ecs.comp_register(&w.base, ComponentType.Organic, OrganicComp)
    ecs.comp_register(&w.base, ComponentType.Interactable, InteractableComp)
    ecs.comp_register(&w.base, ComponentType.Openable, OpenableComp)
    ecs.comp_register(&w.base, ComponentType.Lockable, LockableComp)
    ecs.comp_register(&w.base, ComponentType.SignalEmitter, SignalEmitterComp)
    ecs.comp_register(&w.base, ComponentType.SignalReceiver, SignalReceiverComp)
    ecs.comp_register(&w.base, ComponentType.Container, ContainerComp)
    ecs.comp_register(&w.base, ComponentType.KeyPickup, KeyPickupComp)
    ecs.comp_register(&w.base, ComponentType.KeyRing, KeyRingComp)
    ecs.comp_register(&w.base, ComponentType.LoreItem, LoreItemComp)
    ecs.comp_register(&w.base, ComponentType.Phonograph, PhonographComp)
    ecs.comp_register(&w.base, ComponentType.Grenade, GrenadeComp)
    ecs.comp_register(&w.base, ComponentType.PoisonCloud, PoisonCloudComp)
    ecs.comp_register(&w.base, ComponentType.AimLock, AimLockComp)
    ecs.comp_register(&w.base, ComponentType.DamageAmp, DamageAmpComp)
    ecs.comp_register(&w.base, ComponentType.DamageAmpOnHit, DamageAmpOnHitComp)
    ecs.comp_register(&w.base, ComponentType.Homing, HomingComp)
    ecs.comp_register(&w.base, ComponentType.ProximityTrigger, ProximityTriggerComp)
    ecs.comp_register(&w.base, ComponentType.OverchargeBuff, OverchargeBuffComp)
    ecs.comp_register(&w.base, ComponentType.KillHeal, KillHealComp)
    ecs.comp_register(&w.base, ComponentType.ContagionTag, ContagionTagComp)
    ecs.comp_register(&w.base, ComponentType.Flask, FlaskComp)
    ecs.comp_register(&w.base, ComponentType.FlaskEffect, FlaskEffectComp)
    ecs.comp_register(&w.base, ComponentType.Resistance, ResistanceComp)

    return w
}

destroy_world :: proc(w: ^World) {
    delete(w.damage_events)
    delete(w.tagged)
    ecs.destroy_world(&w.base)
}

SystemEvent     :: ecs.Phase
SystemEventMask :: ecs.PhaseMask
SystemProc      :: #type proc(w: ^World, event: SystemEvent, dt: f32)

RegisteredSystem :: struct {
    mask:  SystemEventMask,
    proc_: SystemProc,
}

SimState :: enum u8 {
    Initializing,
    Running,
    Paused,
    Stopped,
}

Simulation :: struct {
    world:   World,
    systems: [dynamic]RegisteredSystem,
    state:   SimState,
}

make_simulation :: proc() -> Simulation {
    return Simulation{world = make_world(), state = .Initializing}
}

destroy_simulation :: proc(s: ^Simulation) {
    destroy_world(&s.world)
    delete(s.systems)
}

sim_register_system :: proc(s: ^Simulation, mask: SystemEventMask, p: SystemProc) {
    append(&s.systems, RegisteredSystem{mask = mask, proc_ = p})
}

sim_broadcast :: proc(s: ^Simulation, event: SystemEvent, dt: f32 = 0) {
    for &sys in s.systems {
        if event in sys.mask {
            sys.proc_(&s.world, event, dt)
        }
    }
}

sim_tick :: proc(s: ^Simulation, dt: f32) {
    if s.state != .Running {return}

    sim_broadcast(s, .EarlyUpdate, dt)
    sim_broadcast(s, .Update, dt)
    sim_broadcast(s, .LateUpdate, dt)

    sim_broadcast(s, .EntityDestroyed, dt)
    world_reap_tagged(&s.world)
    ecs.world_sweep(&s.world.base)
    sim_broadcast(s, .EntityCreated, dt)

    s.world.tick += 1
}

make_default_simulation :: proc() -> Simulation {
    s := make_simulation()
    sim_register_system(&s, {.Update}, movement_system)
    sim_register_system(&s, {.Update}, projectile_system)
    sim_register_system(&s, {.Update}, self_destruct_system)
    return s
}
