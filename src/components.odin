package main

ComponentType :: enum u8 {
    Transform,
    Velocity,
    Health,
    InputState,
    WeaponSlot,
    MutationContainer,
    MeshRenderer,
    Collider,
    Projectile,
    SelfDestruct,
    AIAgent,
    ProjectileTag,
    Weapon,
    Equipment,
    DodgeState,
    RenderConfig,
    MeleeArc,
    Respawn,
    Inventory,
    Item,
    GroundItem,
    Ability,
    Stats,
    FogOfWar,
    Extraction,
    Mut,
    Player,
    Wallet,
    Gold,
    NPC,
    MutDamageMult,
    MutLockHpToOne,
    MutRootOnFire,
    MutTimedSelfDamage,
    MutBlockHealing,
    MutMoveSpeedMult,
    MutBlockRanged,
    MutBlockPickupHeal,
    MutSerumGainMult,
    MutBlockPickups,
    MutNonlethalShots,
    MutDisableActives,
    MutEarlyDeathThreshold,
    MutMissingHealthDamage,
    MutPassivePower,
    PointLight,
    AnimState,
    MutKillHeal,
    MutLifesteal,
    MutProximityDamage,
    MutOnDeathExplode,
    MutStationaryShield,
    MutExtraDodgeCharges,
    MutDamageTakenMult,
    MutWallPhase,
    MutBodyMelee,
    MutCorpseTrigger,
    MutHideEnemySprites,
    MutUnseenDamageMult,
    MutHeartCage,
    MutThornPact,
    MutCarrionCrown,
    MutFalseSaint,
    MutBlackLung,
    Reanimated,
    StatusEffect,
    Flammable,
    Organic,

    Interactable,
    Openable,
    Lockable,
    SignalEmitter,
    SignalReceiver,
    Container,
    KeyPickup,
    KeyRing,
    LoreItem,
    Phonograph,
    Grenade,
    PoisonCloud,
    AimLock,

    DamageAmp,
    DamageAmpOnHit,
    Homing,
    ProximityTrigger,
    OverchargeBuff,
    KillHeal,
    ContagionTag,

    Flask,
    FlaskEffect,
    Resistance,

    Greybox,
}

_inv_clear :: proc(ptr: rawptr) {
    (cast(^InventoryComp)ptr)^ = inventory_make_empty()
}

_item_clear :: proc(ptr: rawptr) {
    (cast(^ItemComp)ptr)^ = item_empty()
}

StatusEffectType :: enum { Slow, Poison, Burn, Stun, Root, Oiled, Wet }
EffectApplicationPolicy :: enum {Flat, Base, Percent}
EffectStackPolicy  :: enum {Stack, Refresh, Extend}

StatusEffect :: struct {
    type:     StatusEffectType,
    application: EffectApplicationPolicy,
    stack_behavior: EffectStackPolicy,
    stacks: int,
    duration: f32,
    strength: f32,
    acumulator: f32,
    source_id: int,
}

MAX_STATUS_EFFECTS :: 8

OrganicComp :: struct {
}

FlammableComp :: struct {
    isImmune : bool
}

InteractableComp :: struct {
    radius:       f32,
    prompt:       [48]u8,
    active:       bool,
    cooldown:     f32,
    cooldown_max: f32,
}

OpenableComp :: struct {
    is_open:      bool,
    tile:         [2]int,
    link_id:      u8,
    blocks_sight: bool,
}

LockableComp :: struct {
    key_id:    u8,
    is_locked: bool,
}

SignalEmitterComp :: struct {
    link_id:       u8,
    is_on:         bool,
    is_toggle:     bool,
    needs_weight:  bool,
    weight_radius: f32,
}

SignalReceiverComp :: struct {
    link_id: u8,
    invert:  bool,
}

ContainerKind :: enum u8 { Chest, Crate, Locker, Cabinet }

ContainerComp :: struct {
    kind:          ContainerKind,
    is_open:       bool,
    loot_table_id: u8,
    gold_min:      u16,
    gold_max:      u16,
    emits_signal:  bool,
    link_id:       u8,
}

KeyPickupComp :: struct {
    key_id: u8,
    label:  [40]u8,
}

KeyRingComp :: struct {
    held: bit_set[0..<64; u64],
}

LoreItemComp :: struct {
    lore_id: u8,
    is_read: bool,
}

PhonographComp :: struct {
    recording_id: u8,
    is_playing:   bool,
    play_timer:   f32,
}

AimLockComp :: struct {}

DamageAmpComp :: struct {
    mult:  f32,
    timer: f32,
}

DamageAmpOnHitComp :: struct {
    mult: f32,
    dur:  f32,
}

HomingComp :: struct {
    turn_rate:  f32,
    seek_range: f32,
    owner_id:   int,
}

ProximityTriggerComp :: struct {
    arm_timer:    f32,
    radius:       f32,
    damage:       f32,
    owner_id:     int,
    status:       StatusEffectType,
    status_dur:   f32,
    status_str:   f32,
    er, eg, eb:   u8,
}

OverchargeBuffComp :: struct {
    speed_mult:     f32,
    fire_rate_mult: f32,
    damage_mult:    f32,
    duration:       f32,
    timer:          f32,
}

KillHealComp :: struct {
    amount:   f32,
    duration: f32,
    timer:    f32,
}

ContagionTagComp :: struct {}

GrenadeComp :: struct {
    owner_id:       int,
    target:         [3]f32,
    speed:          f32,
    fuse_timer:     f32,
    damage:         f32,
    blast_radius:   f32,
    cloud_radius:   f32,
    cloud_duration: f32,
    cloud_dps:      f32,
    cloud_status:   StatusEffectType,
    cloud_status_dur: f32,
    blink_on_land:  bool,
    er, eg, eb:     u8,
}

PoisonCloudComp :: struct {
    owner_id:       int,
    radius:         f32,
    dps:            f32,
    duration:       f32,
    tick_timer:     f32,
    tick_interval:  f32,
    cloud_status:   StatusEffectType,
    cloud_status_dur: f32,
    er, eg, eb:     u8,
}

StatusEffectComp :: struct {
    effects: [len(StatusEffectType)]StatusEffect,
    count:   int,
}

TransformComp :: struct {
    position: [3]f32,
    rotation: f32,
}

VelocityComp :: struct {
    value: [3]f32,
}

HealthComp :: struct {
    current:            f32,
    max:                f32,
    energy:             f32,
    max_energy:         f32,
    shield:             f32,
}

InputStateComp :: struct {
    move:             [2]f32,
    mouse_world:      [3]f32,
    fire_pressed:     bool,
    reload_pressed:   bool,
    dodge_pressed:    bool,
    skill1_pressed:   bool,
    skill2_pressed:   bool,
    skill3_pressed:   bool,
    skill4_pressed:   bool,
    interact_pressed: bool,
}

WeaponSlotComp :: struct {
    weapon_id: int,
    cooldown:  f32,
}

MAX_MUTATION_SLOTS :: 15

MutationContainerComp :: struct {
    entities:     [MAX_MUTATION_SLOTS]int,
    entity_count: int,
    serums:       int,
}

mutation_container_empty :: proc() -> MutationContainerComp {
    mc := MutationContainerComp{}
    for &e in mc.entities { e = INVALID_ENTITY }
    return mc
}

MutComp :: struct {
    type_id:      MutationType,
}

MutDamageMultComp :: struct {
    mult: f32,
}

MutLockHpToOneComp :: struct {}

MutRootOnFireComp :: struct {
    duration:                 f32,
    damage_mult_while_rooted: f32,
    projectile_speed_mult:    f32,
    timer:                    f32,
}

MutTimedSelfDamageComp :: struct {
    grace: f32,
    dps:   f32,
    timer: f32,
}

MutBlockHealingComp :: struct {}

MutMoveSpeedMultComp :: struct {
    mult: f32,
}

MutBlockRangedComp :: struct {}

MutBlockPickupHealComp :: struct {}

MutSerumGainMultComp :: struct {
    mult: f32,
}

MutBlockPickupsComp :: struct {}

MutNonlethalShotsComp :: struct {}

MutDisableActivesComp :: struct {}

MutEarlyDeathThresholdComp :: struct {
    threshold_pct: f32,
}

MutMissingHealthDamageComp :: struct {
    max_mult:      f32,
    floor_hp_pct:  f32,
}

MutPassivePowerComp :: struct {
    mult: f32,
}

MutKillHealComp :: struct {
    heal_pct: f32,
}

MutLifestealComp :: struct {
    hp_per_hit: f32,
}

MutProximityDamageComp :: struct {
    radius:          f32,

    dps:             f32,
    self_fraction:   f32,

    effect_type:     StatusEffectType,
    effect_strength: f32,
    effect_duration: f32,

    light_color:     [3]f32,
    light_radius:    f32,
    light_intensity: f32,
}

MutOnDeathExplodeComp :: struct {
    radius:       f32,
    damage_pct:   f32,
    cooldown_max: f32,
    timer:        f32,
}

MutStationaryShieldComp :: struct {
    shield_max:  f32,
    regen_rate:  f32,
    shield:      f32,
    was_moving:  bool,
}

MutExtraDodgeChargesComp :: struct {
    count:          int,
    charges:        int,
    recharge_timer: f32,
    recharge_max:   f32,
}

MutDamageTakenMultComp :: struct {
    mult: f32,
}

MutWallPhaseComp :: struct {}

MutBodyMeleeComp :: struct {
    damage:       f32,
    arc_angle:    f32,
    range:        f32,
    cooldown_max: f32,
    timer:        f32,
}

MutCorpseTriggerComp :: struct {
    radius: f32,
    dps:    f32,
}

MutHideEnemySpritesComp :: struct {}

MutUnseenDamageMultComp :: struct {
    mult:          f32,
    vision_radius: f32,
}

HEART_CAGE_ORBIT_RADIUS :: f32(80.0)
HEART_CAGE_ORBIT_SPEED  :: f32(0.9)
CARRION_MAX_SERVANTS    :: 3

MutHeartCageComp :: struct {
    heart_id:    int,
    max_hp_pct:  f32,
    orbit_angle: f32,
}

MutCarrionCrownComp :: struct {
    servant_ids: [CARRION_MAX_SERVANTS]int,
}

ReanimatedComp :: struct {
    owner_id: int,
}

MutBlackLungComp :: struct {
    pressure:     f32,
    regen_rate:   f32,
    gain_per_hit: f32,
    dps_max:      f32,
    radius:       f32,
}

MutThornPactComp :: struct {
    reflect_pct:   f32,
    slow_heal_mult: f32,
}

MutFalseSaintComp :: struct {
    aura_radius:   f32,
    slow_mult:     f32,
    beacon_radius: f32,
}

PointLightComp :: struct {
    color:     [3]f32,
    radius:    f32,
    intensity: f32,
}

AnimStateName :: enum u8 { Idle, Walk, Dodge, Attack, Death }

AnimStateComp :: struct {
    current_state: AnimStateName,
    frame_index:   int,
    elapsed:       f32,
}

ExtractionComp :: struct {
    interact_radius: f32,
    activate_time:   f32,
    timer:           f32,
    activated:       bool,
}

PlayerComp :: struct {
    slot: int,
}

WalletComp :: struct {
    gold: int,
}

GoldComp :: struct {
    amount: int,
}

NPCType :: enum u8 {
    Shopkeeper,
    MutationWorkbench,
    Stash,
    AbilityVendor,
    QuestBoard,
    Quartermaster,
    Surgeon,
}

NPCComp :: struct {
    npc_type:        NPCType,
    interact_radius: f32,
}

MeshRendererComp :: struct {
    mesh_id:     int,
    material_id: int,
    visible:     bool,
}

ColliderComp :: struct {
    radius:    f32,
    faction:   u8,
    is_trigger: bool,
}

ProjectileVisual :: enum u8 { Standard, Smoke }

ProjectileComp :: struct {
    direction:        [3]f32,
    speed:            f32,
    lifetime:         f32,
    max_lifetime:     f32,
    damage:           f32,
    owner_id:         int,
    owner_faction:    u8,
    visual:           ProjectileVisual,
    pierce_remaining: i8,
}

SelfDestructComp :: struct {
    timer: f32,
}

AIType :: enum u8 { Melee, Ranged }

EnemyTier :: enum u8 { Normal, Rare, Legendary }

AIAgentComp :: struct {
    state:        u8,
    target_id:    int,
    cooldown:     f32,

    aggro_range:  f32,
    attack_range: f32,
    cooldown_max: f32,
    speed:        f32,
    damage:       f32,
    ai_type:      AIType,
    pellet_count: int,
    spread_angle: f32,

    suspicion:      f32,
    last_known_pos: [3]f32,
    search_timer:   f32,

    tier: EnemyTier,
}

MeleeArcComp :: struct {
    angle:         f32,
    arc_spread:    f32,
    radius:        f32,
    damage:        f32,
    owner_id:      int,
    owner_faction: u8,
    hit_applied:   bool,
    lifetime:      f32,
}

DamageKind :: enum u8 {
    Physical,
    Necrotic,
    Fire,
    Galvanic,
    Poison,
}

DamageEvent :: struct {
    target_id: int,
    amount:    f32,
    source_id: int,
    kind:      DamageKind,
}

RespawnComp :: struct {
    spawn_pos: [3]f32,
    delay:     f32,
    timer:     f32,
}

FlaskKind :: enum u8 { Health, Energy }
FlaskSize :: enum u8 { Small, Medium, Large }

FlaskComp :: struct {
    kind:             FlaskKind,
    size:             FlaskSize,
    recover_amount:   f32,
    recover_duration: f32,
    charges:          i32,
    max_charges:      i32,
}

FlaskEffectComp :: struct {
    heal_per_sec:   f32,
    energy_per_sec: f32,
    remaining:      f32,
}

ResistanceComp :: struct {
    physical:  f32,
    necrotic:  f32,
    fire:      f32,
    galvanic:  f32,
    poison:    f32,
}

EquipSlot :: enum u8 {
    Head,
    Chest,
    Boots,
    WeaponPrimary,
    WeaponOffhand,
    Consumable,
    Ability1,
    Ability2,
    Ability3,
    Ability4,
    Flask1,
    Flask2,
}

EQUIP_SLOT_COUNT :: len(EquipSlot)

BACKPACK_COLS :: 10
BACKPACK_ROWS ::  4

InventoryComp :: struct {
    equipped: [EQUIP_SLOT_COUNT]int,
    backpack: [BACKPACK_ROWS * BACKPACK_COLS]int,
}

inventory_make_empty :: proc() -> InventoryComp {
    inv := InventoryComp{}
    for &s in inv.equipped { s = INVALID_ENTITY }
    for &c in inv.backpack  { c = INVALID_ENTITY }
    return inv
}

ItemRarity :: enum u8 { Normal, Rare, Epic, Legendary, Unique }

MutationType :: enum u8 {
    None,

    SerratedHands,
    HollowBones,
    Exoskeleton,
    Symbiote,
    LivingBomb,

    GlassCannon,
    BlindFire,
    Timelock,
    SpectralForm,
    DeadmansTrigger,

    BloodFrenzy,
    ToxicFlesh,
    ParasiteKing,
    CorpseTide,
    Metamorphosis,

    HeartCage,
    ThornPact,
    CarrionCrown,
    FalseSaint,
    BlackLung,
}

MAX_AFFIXES :: 6

AbilityType :: enum u8 {
    None,

    CadavericSpasm,
    OsseousSlam,
    NecroticSurge,
    CrushingGrip,

    RapidDischarge,
    DeliberateRound,
    EtherVial,
    Indexed,

    VetriolFlask,
    CarbolicSpray,
    Contagion,
    Exothermic,

    LaTormenta,
    Overcharged,
    InductionCoil,
    GalvanicShock,
}

AffixType :: enum u8 {
    None,
    BonusHP,
    Armor,
    BonusMoveSpeed,
    BonusEnergy,
    BonusDamage,
    BonusFireRate,
    BonusReloadSpeed,
    HealthRegen,

    BonusProjSpeed,
    BonusPierce,
    BonusAmmo,

    BonusMeleeDamage,
    BonusMeleeRange,
    BonusMeleeSpeed,

    BonusStrength,
    BonusDexterity,
    BonusScience,

    BonusEnergyRegen,
    ReduceEnergyCost,

    ResistPhysical,
    ResistNecrotic,
    ResistFire,
    ResistGalvanic,
    ResistPoison,
}

Affix :: struct {
    type:  AffixType,
    value: f32,
}

ItemComp :: struct {
    slot:          EquipSlot,
    rarity:        ItemRarity,
    mutation_type: MutationType,
    ability_type:  AbilityType,
    ability_level: u8,
    serum_value:   int,
    grid_w:        int,
    grid_h:        int,
    pack_x:        int,
    pack_y:        int,
    affixes:       [MAX_AFFIXES]Affix,
    affix_count:   u8,

    req_str: u8,
    req_dex: u8,
    req_sci: u8,

    is_two_handed: bool,

    is_melee:           bool,
    melee_damage:       f32,
    melee_range:        f32,
    melee_spread:       f32,
    melee_cooldown:     f32,
    melee_cooldown_max: f32,

    weapon_archetype: WeaponArchetype,

    base_damage:      f32,
    base_fire_rate:   f32,
    base_ammo_max:    u8,
    base_reload_time: f32,
    base_proj_speed:  f32,
    base_armor:       f32,
    base_shield:      f32,
}

item_empty :: proc() -> ItemComp {
    return ItemComp{ rarity = .Normal, grid_w = 1, grid_h = 1, pack_x = -1, pack_y = -1 }
}

GroundItemComp :: struct {}

ProjectileTagComp :: struct {}

FogOfWarComp :: struct {}

WeaponArchetype :: enum u8 {
    None,
    Pistol,
    Rifle,
    Shotgun,
    Axe,
    Knife,
    Sword,
}

WeaponType :: enum u8 { Melee, Ranged }

WeaponComp :: struct {
    type:             WeaponType,
    damage:           f32,
    fire_rate:        f32,
    projectile_speed: f32,
    projectile_life:  f32,
    range:            f32,
    ammo_max:         int,
    reload_time:      f32,

    cooldown:         f32,
    ammo_current:     int,
    reload_timer:     f32,
    is_reloading:     bool,
}

EquipmentComp :: struct {
    weapon_entity_id: int,
}

DodgeComp :: struct {
    active:       bool,
    direction:    [2]f32,
    timer:        f32,
    cooldown:     f32,

    duration:     f32,
    speed:        f32,
    cooldown_max: f32,
}

AbilitySlotState :: struct {
    cooldown:      f32,

    burst_shots:   int,
    burst_timer:   f32,
    burst_dmg:     f32,
    burst_pierce:  i8,

    charging:      bool,
    charge_timer:  f32,
    charge_dmg:    f32,

    primed:        bool,
    primed_count:  int,
    primed_dmg:    f32,

    buff_timer:    f32,
    buff_value:    f32,
}

ABILITY_SLOT_COUNT :: 4

AbilityComp :: struct {
    slots: [ABILITY_SLOT_COUNT]AbilitySlotState,
}

RENDER_NAME_CAP :: 48
RENDER_ICON_CAP :: 48
RENDER_SPRITE_CAP :: 48
RENDER_DESC_CAP :: 128

RenderLayer :: enum u8 {
    None,
    WorldFX,
    Sprite,
}

RenderConfigComp :: struct {
    display_name:    [RENDER_NAME_CAP]u8,
    name_len:        u8,
    icon_name:       [RENDER_ICON_CAP]u8,
    icon_len:        u8,
    sprite_name:     [RENDER_SPRITE_CAP]u8,
    sprite_len:      u8,
    sprite_scale:    f32,
    world_size:      f32,
    render_layer:    RenderLayer,
    show_hp_bar:     bool,
    show_dir_tip:    bool,
    top_down_sprite: bool,
    desc:            [RENDER_DESC_CAP]u8,
    desc_len:        u8,
}

render_config_set_name :: proc(c: ^RenderConfigComp, name: string) {
    n := min(len(name), RENDER_NAME_CAP - 1)
    copy(c.display_name[:], name[:n])
    c.display_name[n] = 0
    c.name_len = u8(n)
}

render_config_name_cstr :: proc(c: ^RenderConfigComp) -> cstring {
    return cstring(&c.display_name[0])
}

render_config_set_icon :: proc(c: ^RenderConfigComp, stem: string) {
    n := min(len(stem), RENDER_ICON_CAP - 1)
    copy(c.icon_name[:], stem[:n])
    c.icon_name[n] = 0
    c.icon_len = u8(n)
}

render_config_icon_cstr :: proc(c: ^RenderConfigComp) -> cstring {
    return cstring(&c.icon_name[0])
}

render_config_set_sprite :: proc(c: ^RenderConfigComp, stem: string) {
    n := min(len(stem), RENDER_SPRITE_CAP - 1)
    copy(c.sprite_name[:], stem[:n])
    c.sprite_name[n] = 0
    c.sprite_len = u8(n)
}

render_config_sprite_cstr :: proc(c: ^RenderConfigComp) -> cstring {
    return cstring(&c.sprite_name[0])
}

render_config_set_desc :: proc(c: ^RenderConfigComp, desc: string) {
    n := min(len(desc), RENDER_DESC_CAP - 1)
    copy(c.desc[:], desc[:n])
    c.desc[n] = 0
    c.desc_len = u8(n)
}

render_config_desc_cstr :: proc(c: ^RenderConfigComp) -> cstring {
    return cstring(&c.desc[0])
}

status_effect_apply :: proc(w: ^World, id: int, effect: StatusEffect) {
    if !world_has_component(w, id, .StatusEffect) {
        comp_set(w, id, .StatusEffect, StatusEffectComp{})
    }
    sec := comp_get(w, id, .StatusEffect, StatusEffectComp)

    if effect.type == .Burn || effect.type == .Oiled {
        if status_effect_is_active(sec, .Wet) { return }
    }

    if effect.type == .Wet {
        if status_effect_is_active(sec, .Burn) {
            sec.effects[int(StatusEffectType.Burn)].duration = 0
            sec.count -= 1
        }
    }

    et := int(effect.type)
    current := &sec.effects[et]

    if current.duration <= 0 {
        current^ = effect
        current.stacks = 1
        sec.count += 1
    } else {
        switch effect.application {
        case .Flat, .Percent:
            current.strength += effect.strength
        case .Base:
            current.strength = effect.strength
        }

        switch effect.stack_behavior {
        case .Stack:
            current.duration = effect.duration
            current.stacks += 1
        case .Refresh:
            current.duration = max(current.duration, effect.duration)
        case .Extend:
            current.duration += effect.duration
        }
    }
}
status_effect_is_active :: proc(sec: ^StatusEffectComp, stype: StatusEffectType) -> bool {
    et := int(stype)
    return sec.effects[et].duration > 0
}

status_effect_get :: proc(sec: ^StatusEffectComp, stype: StatusEffectType) -> ^StatusEffect {
    et := int(stype)
    return &sec.effects[et]
}

StatsComp :: struct {
    strength:    int,
    dexterity:   int,
    science:     int,

    level:       int,
    xp:          f32,
    xp_next:     f32,
    stat_points: int,

    base_hp:     f32,
    base_energy: f32,
    base_speed:  f32,

    max_hp_mult:                f32,
    max_energy_mult:            f32,
    move_speed:                 f32,
    damage_mult:                f32,
    fire_rate_mult:             f32,
    reload_speed_mult:          f32,
    projectile_speed_mult:      f32,
    armor:                      f32,
    hp_regen_pct:               f32,
    crit_chance:                f32,
    special_ability_crit:       f32,
    dodge_cooldown_reduction:   f32,
    vision_bonus:               f32,
    ability_cooldown_mult:      f32,
    deadman_early_death_pct:    f32,
    movement_blocked:           bool,
    healing_blocked:            bool,
    pickup_healing_blocked:     bool,
    pickups_blocked:            bool,
    active_abilities_blocked:   bool,
    ranged_attacks_blocked:     bool,
    nonlethal_shots:            bool,
    hp_locked_to_one:           bool,

    bonus_ammo_pct:  f32,
    bonus_pierce:    int,

    melee_damage_mult: f32,
    melee_range_mult:  f32,
    melee_speed_mult:  f32,

    shield_max: f32,

    energy_regen: f32,

    energy_cost_mult: f32,
}

GreyboxShape :: enum u8 {
    Box,
    Ramp,
    Wedge,
    Cylinder,
    Platform,
}

GreyboxComp :: struct {
    shape:      GreyboxShape,
    size:       [3]f32,
    r, g, b:    u8,
    solid:      bool,
}
