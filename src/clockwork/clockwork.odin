package clockwork

import "core:mem"
import "base:intrinsics"

CHUNK_SIZE      :: 256
MAX_COMPONENTS  :: 128
INVALID_ENTITY  :: -1
MAX_PLAYERS     :: 4

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
}

COMPONENT_COUNT :: len(ComponentType)

EntityFlag :: enum u8 {
    Active      = 0,
    Dead        = 1,
    ToDestroy   = 2,
}

EntityFlags :: distinct bit_set[EntityFlag; u8]

ComponentSignature :: distinct u128

entity_sig_set :: proc(sig: ^ComponentSignature, ct: ComponentType) {
    sig^ |= ComponentSignature(1) << uint(ct)
}

entity_sig_clear :: proc(sig: ^ComponentSignature, ct: ComponentType) {
    sig^ &~= ComponentSignature(1) << uint(ct)
}

entity_sig_has :: proc(sig: ComponentSignature, ct: ComponentType) -> bool {
    return (sig & (ComponentSignature(1) << uint(ct))) != 0
}

Entity :: struct {
    id:        int,
    flags:     EntityFlags,
    signature: ComponentSignature,
}

entity_is_active :: proc(e: Entity) -> bool {
    return .Active in e.flags
}

entity_empty :: proc() -> Entity {
    return Entity{ id = INVALID_ENTITY }
}

Component_Pool :: struct {
    bytes:     [dynamic]u8,
    bitset:    [dynamic]u64,
    elem_size: int,
    clear:     proc(rawptr),
}

@(private="file")
_pool_init :: proc(w: ^World, ct: ComponentType, $T: typeid, clear_fn: proc(rawptr) = nil) {
    p := &w.pools[ct]
    p.elem_size = max(size_of(T), 1)  // zero-size structs still need addressable slots
    p.clear     = clear_fn
    resize(&p.bytes,  p.elem_size * CHUNK_SIZE)
    resize(&p.bitset, (CHUNK_SIZE + 63) / 64)
}

@(private="file")
_comp :: #force_inline proc(w: ^World, id: int, $T: typeid, ct: ComponentType) -> ^T {
    p := &w.pools[ct]
    return transmute(^T)(&p.bytes[id * p.elem_size])
}

@(private="file")
_comp_set :: #force_inline proc(w: ^World, id: int, $T: typeid, ct: ComponentType, val: T) {
    p := &w.pools[ct]
    (transmute(^T)(&p.bytes[id * p.elem_size]))^ = val
    p.bitset[id >> 6] |= u64(1) << uint(id & 63)
    entity_sig_set(&w.entities[id].signature, ct)
}

@(private="file")
_comp_clear :: #force_inline proc(w: ^World, id: int, $T: typeid, ct: ComponentType) {
    p := &w.pools[ct]
    (transmute(^T)(&p.bytes[id * p.elem_size]))^ = {}
    p.bitset[id >> 6] &~= u64(1) << uint(id & 63)
    entity_sig_clear(&w.entities[id].signature, ct)
}

@(private="file")
_inv_clear :: proc(ptr: rawptr) {
    (cast(^InventoryComp)ptr)^ = inventory_make_empty()
}

@(private="file")
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


World :: struct {
    entities:          [dynamic]Entity,
    next_id:           int,
    recycled_ids:      [dynamic]int,
    last_created:      int,

    player_ids:        [MAX_PLAYERS]int,
    local_player_slot: int,
    player_id:         int,

    pools:             [ComponentType]Component_Pool,

    damage_events:     [dynamic]DamageEvent,
    tick:              u64,
}

make_world :: proc() -> World {
    w := World{}
    for &id in w.player_ids { id = INVALID_ENTITY }
    w.local_player_slot = 0
    w.player_id    = INVALID_ENTITY
    w.next_id      = 0
    w.last_created = INVALID_ENTITY

    resize(&w.entities, CHUNK_SIZE)
    for i in 0..<CHUNK_SIZE { w.entities[i] = entity_empty() }

    _pool_init(&w, .Transform,              TransformComp)
    _pool_init(&w, .Velocity,               VelocityComp)
    _pool_init(&w, .Health,                 HealthComp)
    _pool_init(&w, .InputState,             InputStateComp)
    _pool_init(&w, .WeaponSlot,             WeaponSlotComp)
    _pool_init(&w, .MutationContainer,      MutationContainerComp)
    _pool_init(&w, .MeshRenderer,           MeshRendererComp)
    _pool_init(&w, .Collider,               ColliderComp)
    _pool_init(&w, .Projectile,             ProjectileComp)
    _pool_init(&w, .SelfDestruct,           SelfDestructComp)
    _pool_init(&w, .AIAgent,                AIAgentComp)
    _pool_init(&w, .ProjectileTag,          ProjectileTagComp)
    _pool_init(&w, .Weapon,                 WeaponComp)
    _pool_init(&w, .Equipment,              EquipmentComp)
    _pool_init(&w, .DodgeState,             DodgeComp)
    _pool_init(&w, .RenderConfig,           RenderConfigComp)
    _pool_init(&w, .MeleeArc,               MeleeArcComp)
    _pool_init(&w, .Respawn,                RespawnComp)
    _pool_init(&w, .Inventory,              InventoryComp,              _inv_clear)
    _pool_init(&w, .Item,                   ItemComp,                   _item_clear)
    _pool_init(&w, .GroundItem,             GroundItemComp)
    _pool_init(&w, .Ability,                AbilityComp)
    _pool_init(&w, .Stats,                  StatsComp)
    _pool_init(&w, .FogOfWar,               FogOfWarComp)
    _pool_init(&w, .Extraction,             ExtractionComp)
    _pool_init(&w, .Mut,                    MutComp)
    _pool_init(&w, .Player,                 PlayerComp)
    _pool_init(&w, .Wallet,                 WalletComp)
    _pool_init(&w, .Gold,                   GoldComp)
    _pool_init(&w, .NPC,                    NPCComp)
    _pool_init(&w, .MutDamageMult,          MutDamageMultComp)
    _pool_init(&w, .MutLockHpToOne,         MutLockHpToOneComp)
    _pool_init(&w, .MutRootOnFire,          MutRootOnFireComp)
    _pool_init(&w, .MutTimedSelfDamage,     MutTimedSelfDamageComp)
    _pool_init(&w, .MutBlockHealing,        MutBlockHealingComp)
    _pool_init(&w, .MutMoveSpeedMult,       MutMoveSpeedMultComp)
    _pool_init(&w, .MutBlockRanged,         MutBlockRangedComp)
    _pool_init(&w, .MutBlockPickupHeal,     MutBlockPickupHealComp)
    _pool_init(&w, .MutSerumGainMult,       MutSerumGainMultComp)
    _pool_init(&w, .MutBlockPickups,        MutBlockPickupsComp)
    _pool_init(&w, .MutNonlethalShots,      MutNonlethalShotsComp)
    _pool_init(&w, .MutDisableActives,      MutDisableActivesComp)
    _pool_init(&w, .MutEarlyDeathThreshold, MutEarlyDeathThresholdComp)
    _pool_init(&w, .MutMissingHealthDamage, MutMissingHealthDamageComp)
    _pool_init(&w, .MutPassivePower,        MutPassivePowerComp)
    _pool_init(&w, .PointLight,             PointLightComp)
    _pool_init(&w, .AnimState,              AnimStateComp)
    _pool_init(&w, .MutKillHeal,            MutKillHealComp)
    _pool_init(&w, .MutLifesteal,           MutLifestealComp)
    _pool_init(&w, .MutProximityDamage,     MutProximityDamageComp)
    _pool_init(&w, .MutOnDeathExplode,      MutOnDeathExplodeComp)
    _pool_init(&w, .MutStationaryShield,    MutStationaryShieldComp)
    _pool_init(&w, .MutExtraDodgeCharges,   MutExtraDodgeChargesComp)
    _pool_init(&w, .MutDamageTakenMult,     MutDamageTakenMultComp)
    _pool_init(&w, .MutWallPhase,           MutWallPhaseComp)
    _pool_init(&w, .MutBodyMelee,           MutBodyMeleeComp)
    _pool_init(&w, .MutCorpseTrigger,       MutCorpseTriggerComp)
    _pool_init(&w, .MutHideEnemySprites,    MutHideEnemySpritesComp)
    _pool_init(&w, .MutUnseenDamageMult,    MutUnseenDamageMultComp)
    _pool_init(&w, .MutHeartCage,           MutHeartCageComp)
    _pool_init(&w, .MutThornPact,           MutThornPactComp)
    _pool_init(&w, .MutCarrionCrown,        MutCarrionCrownComp)
    _pool_init(&w, .MutFalseSaint,          MutFalseSaintComp)
    _pool_init(&w, .MutBlackLung,           MutBlackLungComp)
    _pool_init(&w, .Reanimated,             ReanimatedComp)
    _pool_init(&w, .StatusEffect,           StatusEffectComp)
    _pool_init(&w, .Flammable,              FlammableComp)
    _pool_init(&w, .Organic,                OrganicComp)
    _pool_init(&w, .Interactable,           InteractableComp)
    _pool_init(&w, .Openable,               OpenableComp)
    _pool_init(&w, .Lockable,               LockableComp)
    _pool_init(&w, .SignalEmitter,          SignalEmitterComp)
    _pool_init(&w, .SignalReceiver,         SignalReceiverComp)
    _pool_init(&w, .Container,              ContainerComp)
    _pool_init(&w, .KeyPickup,              KeyPickupComp)
    _pool_init(&w, .KeyRing,                KeyRingComp)
    _pool_init(&w, .LoreItem,               LoreItemComp)
    _pool_init(&w, .Phonograph,             PhonographComp)
    _pool_init(&w, .Grenade,                GrenadeComp)
    _pool_init(&w, .PoisonCloud,            PoisonCloudComp)
    _pool_init(&w, .AimLock,                AimLockComp)
    _pool_init(&w, .DamageAmp,              DamageAmpComp)
    _pool_init(&w, .DamageAmpOnHit,         DamageAmpOnHitComp)
    _pool_init(&w, .Homing,                 HomingComp)
    _pool_init(&w, .ProximityTrigger,       ProximityTriggerComp)
    _pool_init(&w, .OverchargeBuff,         OverchargeBuffComp)
    _pool_init(&w, .KillHeal,               KillHealComp)
    _pool_init(&w, .ContagionTag,           ContagionTagComp)
    _pool_init(&w, .Flask,                  FlaskComp)
    _pool_init(&w, .FlaskEffect,            FlaskEffectComp)
    _pool_init(&w, .Resistance,             ResistanceComp)

    return w
}

destroy_world :: proc(w: ^World) {
    delete(w.entities)
    delete(w.recycled_ids)
    delete(w.damage_events)
    for &p in w.pools { delete(p.bytes); delete(p.bitset) }
}

world_create_entity :: proc(w: ^World) -> int {
    id: int
    if len(w.recycled_ids) > 0 {
        id = pop(&w.recycled_ids)
    } else {
        id = w.next_id
        w.next_id += 1
    }

    world_ensure_capacity(w, id)

    w.entities[id] = Entity{
        id    = id,
        flags = { .Active },
    }

    w.last_created = id
    return id
}

world_destroy_entity :: proc(w: ^World, id: int) {
    if id < 0 || id >= len(w.entities) { return }
    e := &w.entities[id]
    if !entity_is_active(e^) { return }
    e.flags     = { .ToDestroy }
    e.signature = 0
}

world_is_valid :: proc(w: ^World, id: int) -> bool {
    if id < 0 || id >= len(w.entities) { return false }
    return entity_is_active(w.entities[id])
}

world_reset :: proc(w: ^World) {
    for i in 0..<len(w.entities) {
        if entity_is_active(w.entities[i]) {
            world_destroy_entity(w, w.entities[i].id)
        }
    }
    world_sweep(w)

    clear(&w.recycled_ids)
    w.next_id      = 0
    w.last_created = INVALID_ENTITY

    for &id in w.player_ids { id = INVALID_ENTITY }
    w.player_id = INVALID_ENTITY

    clear(&w.damage_events)
}

world_ensure_capacity :: proc(w: ^World, id: int) {
    if id < len(w.entities) { return }
    target := ((id / CHUNK_SIZE) + 1) * CHUNK_SIZE
    resize(&w.entities, target)
    for &p in w.pools {
        resize(&p.bytes,  target * p.elem_size)
        resize(&p.bitset, (target + 63) / 64)
    }
}

world_sweep :: proc(w: ^World) {
    for i in 0..<len(w.entities) {
        e := &w.entities[i]
        if .ToDestroy not_in e.flags { continue }
        word := i >> 6
        bit  := uint(i & 63)
        for ct in ComponentType {
            p := &w.pools[ct]
            slot := rawptr(uintptr(raw_data(p.bytes)) + uintptr(i * p.elem_size))
            if p.clear != nil { p.clear(slot) } else { mem.zero(slot, p.elem_size) }
            p.bitset[word] &~= u64(1) << bit
        }
        w.entities[i] = entity_empty()
        append(&w.recycled_ids, i)
    }
}

world_set_transform :: proc(w: ^World, id: int, c: TransformComp) {
    _comp_set(w, id, TransformComp, .Transform, c)
}
world_get_transform :: proc(w: ^World, id: int) -> ^TransformComp {
    return _comp(w, id, TransformComp, .Transform)
}

world_set_velocity :: proc(w: ^World, id: int, c: VelocityComp) {
    _comp_set(w, id, VelocityComp, .Velocity, c)
}
world_get_velocity :: proc(w: ^World, id: int) -> ^VelocityComp {
    return _comp(w, id, VelocityComp, .Velocity)
}

world_set_health :: proc(w: ^World, id: int, c: HealthComp) {
    _comp_set(w, id, HealthComp, .Health, c)
}
world_get_health :: proc(w: ^World, id: int) -> ^HealthComp {
    return _comp(w, id, HealthComp, .Health)
}

world_set_input :: proc(w: ^World, id: int, c: InputStateComp) {
    _comp_set(w, id, InputStateComp, .InputState, c)
}
world_get_input :: proc(w: ^World, id: int) -> ^InputStateComp {
    return _comp(w, id, InputStateComp, .InputState)
}

world_set_weapon :: proc(w: ^World, id: int, c: WeaponSlotComp) {
    _comp_set(w, id, WeaponSlotComp, .WeaponSlot, c)
}
world_get_weapon :: proc(w: ^World, id: int) -> ^WeaponSlotComp {
    return _comp(w, id, WeaponSlotComp, .WeaponSlot)
}

world_set_mutation :: proc(w: ^World, id: int, c: MutationContainerComp) {
    _comp_set(w, id, MutationContainerComp, .MutationContainer, c)
}
world_get_mutation :: proc(w: ^World, id: int) -> ^MutationContainerComp {
    return _comp(w, id, MutationContainerComp, .MutationContainer)
}

world_set_flammable :: proc(w: ^World, id: int, c: FlammableComp) {
    _comp_set(w, id, FlammableComp, .Flammable, c)
}
world_get_flammable :: proc(w: ^World, id: int) -> ^FlammableComp {
    return _comp(w, id, FlammableComp, .Flammable)
}

world_set_organic :: proc(w: ^World, id: int, c: OrganicComp) {
    _comp_set(w, id, OrganicComp, .Organic, c)
}
world_get_organic :: proc(w: ^World, id: int) -> ^OrganicComp {
    return _comp(w, id, OrganicComp, .Organic)
}

world_set_interactable :: proc(w: ^World, id: int, c: InteractableComp) {
    _comp_set(w, id, InteractableComp, .Interactable, c)
}
world_get_interactable :: proc(w: ^World, id: int) -> ^InteractableComp {
    return _comp(w, id, InteractableComp, .Interactable)
}

world_set_openable :: proc(w: ^World, id: int, c: OpenableComp) {
    _comp_set(w, id, OpenableComp, .Openable, c)
}
world_get_openable :: proc(w: ^World, id: int) -> ^OpenableComp {
    return _comp(w, id, OpenableComp, .Openable)
}

world_set_lockable :: proc(w: ^World, id: int, c: LockableComp) {
    _comp_set(w, id, LockableComp, .Lockable, c)
}
world_get_lockable :: proc(w: ^World, id: int) -> ^LockableComp {
    return _comp(w, id, LockableComp, .Lockable)
}

world_set_signal_emitter :: proc(w: ^World, id: int, c: SignalEmitterComp) {
    _comp_set(w, id, SignalEmitterComp, .SignalEmitter, c)
}
world_get_signal_emitter :: proc(w: ^World, id: int) -> ^SignalEmitterComp {
    return _comp(w, id, SignalEmitterComp, .SignalEmitter)
}

world_set_signal_receiver :: proc(w: ^World, id: int, c: SignalReceiverComp) {
    _comp_set(w, id, SignalReceiverComp, .SignalReceiver, c)
}
world_get_signal_receiver :: proc(w: ^World, id: int) -> ^SignalReceiverComp {
    return _comp(w, id, SignalReceiverComp, .SignalReceiver)
}

world_set_container :: proc(w: ^World, id: int, c: ContainerComp) {
    _comp_set(w, id, ContainerComp, .Container, c)
}
world_get_container :: proc(w: ^World, id: int) -> ^ContainerComp {
    return _comp(w, id, ContainerComp, .Container)
}

world_set_key_pickup :: proc(w: ^World, id: int, c: KeyPickupComp) {
    _comp_set(w, id, KeyPickupComp, .KeyPickup, c)
}
world_get_key_pickup :: proc(w: ^World, id: int) -> ^KeyPickupComp {
    return _comp(w, id, KeyPickupComp, .KeyPickup)
}

world_set_key_ring :: proc(w: ^World, id: int, c: KeyRingComp) {
    _comp_set(w, id, KeyRingComp, .KeyRing, c)
}
world_get_key_ring :: proc(w: ^World, id: int) -> ^KeyRingComp {
    return _comp(w, id, KeyRingComp, .KeyRing)
}

world_set_lore_item :: proc(w: ^World, id: int, c: LoreItemComp) {
    _comp_set(w, id, LoreItemComp, .LoreItem, c)
}
world_get_lore_item :: proc(w: ^World, id: int) -> ^LoreItemComp {
    return _comp(w, id, LoreItemComp, .LoreItem)
}

world_set_phonograph :: proc(w: ^World, id: int, c: PhonographComp) {
    _comp_set(w, id, PhonographComp, .Phonograph, c)
}
world_get_phonograph :: proc(w: ^World, id: int) -> ^PhonographComp {
    return _comp(w, id, PhonographComp, .Phonograph)
}

world_set_grenade :: proc(w: ^World, id: int, c: GrenadeComp) {
    _comp_set(w, id, GrenadeComp, .Grenade, c)
}
world_get_grenade :: proc(w: ^World, id: int) -> ^GrenadeComp {
    return _comp(w, id, GrenadeComp, .Grenade)
}

world_set_poison_cloud :: proc(w: ^World, id: int, c: PoisonCloudComp) {
    _comp_set(w, id, PoisonCloudComp, .PoisonCloud, c)
}
world_get_poison_cloud :: proc(w: ^World, id: int) -> ^PoisonCloudComp {
    return _comp(w, id, PoisonCloudComp, .PoisonCloud)
}

world_set_aim_lock :: proc(w: ^World, id: int) {
    _comp_set(w, id, AimLockComp, .AimLock, AimLockComp{})
}
world_clear_aim_lock :: proc(w: ^World, id: int) {
    _comp_clear(w, id, AimLockComp, .AimLock)
}

world_set_damage_amp :: proc(w: ^World, id: int, c: DamageAmpComp) {
    _comp_set(w, id, DamageAmpComp, .DamageAmp, c)
}
world_get_damage_amp :: proc(w: ^World, id: int) -> ^DamageAmpComp {
    return _comp(w, id, DamageAmpComp, .DamageAmp)
}
world_clear_damage_amp :: proc(w: ^World, id: int) {
    _comp_clear(w, id, DamageAmpComp, .DamageAmp)
}

world_set_damage_amp_on_hit :: proc(w: ^World, id: int, c: DamageAmpOnHitComp) {
    _comp_set(w, id, DamageAmpOnHitComp, .DamageAmpOnHit, c)
}
world_get_damage_amp_on_hit :: proc(w: ^World, id: int) -> ^DamageAmpOnHitComp {
    return _comp(w, id, DamageAmpOnHitComp, .DamageAmpOnHit)
}
world_clear_damage_amp_on_hit :: proc(w: ^World, id: int) {
    _comp_clear(w, id, DamageAmpOnHitComp, .DamageAmpOnHit)
}

world_set_homing :: proc(w: ^World, id: int, c: HomingComp) {
    _comp_set(w, id, HomingComp, .Homing, c)
}
world_get_homing :: proc(w: ^World, id: int) -> ^HomingComp {
    return _comp(w, id, HomingComp, .Homing)
}

world_set_proximity_trigger :: proc(w: ^World, id: int, c: ProximityTriggerComp) {
    _comp_set(w, id, ProximityTriggerComp, .ProximityTrigger, c)
}
world_get_proximity_trigger :: proc(w: ^World, id: int) -> ^ProximityTriggerComp {
    return _comp(w, id, ProximityTriggerComp, .ProximityTrigger)
}

world_set_overcharge_buff :: proc(w: ^World, id: int, c: OverchargeBuffComp) {
    _comp_set(w, id, OverchargeBuffComp, .OverchargeBuff, c)
}
world_get_overcharge_buff :: proc(w: ^World, id: int) -> ^OverchargeBuffComp {
    return _comp(w, id, OverchargeBuffComp, .OverchargeBuff)
}
world_clear_overcharge_buff :: proc(w: ^World, id: int) {
    _comp_clear(w, id, OverchargeBuffComp, .OverchargeBuff)
}

world_set_kill_heal :: proc(w: ^World, id: int, c: KillHealComp) {
    _comp_set(w, id, KillHealComp, .KillHeal, c)
}
world_get_kill_heal :: proc(w: ^World, id: int) -> ^KillHealComp {
    return _comp(w, id, KillHealComp, .KillHeal)
}
world_clear_kill_heal :: proc(w: ^World, id: int) {
    _comp_clear(w, id, KillHealComp, .KillHeal)
}

world_set_contagion_tag :: proc(w: ^World, id: int) {
    _comp_set(w, id, ContagionTagComp, .ContagionTag, ContagionTagComp{})
}
world_clear_contagion_tag :: proc(w: ^World, id: int) {
    _comp_clear(w, id, ContagionTagComp, .ContagionTag)
}

world_set_flask :: proc(w: ^World, id: int, c: FlaskComp) {
    _comp_set(w, id, FlaskComp, .Flask, c)
}
world_get_flask :: proc(w: ^World, id: int) -> ^FlaskComp {
    return _comp(w, id, FlaskComp, .Flask)
}
world_clear_flask :: proc(w: ^World, id: int) {
    _comp_clear(w, id, FlaskComp, .Flask)
}

world_set_flask_effect :: proc(w: ^World, id: int, c: FlaskEffectComp) {
    _comp_set(w, id, FlaskEffectComp, .FlaskEffect, c)
}
world_get_flask_effect :: proc(w: ^World, id: int) -> ^FlaskEffectComp {
    return _comp(w, id, FlaskEffectComp, .FlaskEffect)
}
world_clear_flask_effect :: proc(w: ^World, id: int) {
    _comp_clear(w, id, FlaskEffectComp, .FlaskEffect)
}

world_set_resistance :: proc(w: ^World, id: int, c: ResistanceComp) {
    _comp_set(w, id, ResistanceComp, .Resistance, c)
}
world_get_resistance :: proc(w: ^World, id: int) -> ^ResistanceComp {
    return _comp(w, id, ResistanceComp, .Resistance)
}
world_clear_resistance :: proc(w: ^World, id: int) {
    _comp_clear(w, id, ResistanceComp, .Resistance)
}

world_set_extraction :: proc(w: ^World, id: int, c: ExtractionComp) {
    _comp_set(w, id, ExtractionComp, .Extraction, c)
}
world_get_extraction :: proc(w: ^World, id: int) -> ^ExtractionComp {
    return _comp(w, id, ExtractionComp, .Extraction)
}

world_set_mut :: proc(w: ^World, id: int, c: MutComp) {
    _comp_set(w, id, MutComp, .Mut, c)
}
world_get_mut :: proc(w: ^World, id: int) -> ^MutComp {
    return _comp(w, id, MutComp, .Mut)
}

world_set_player :: proc(w: ^World, id: int, c: PlayerComp) {
    _comp_set(w, id, PlayerComp, .Player, c)
}
world_get_player :: proc(w: ^World, id: int) -> ^PlayerComp {
    return _comp(w, id, PlayerComp, .Player)
}

world_set_wallet :: proc(w: ^World, id: int, c: WalletComp) {
    _comp_set(w, id, WalletComp, .Wallet, c)
}
world_get_wallet :: proc(w: ^World, id: int) -> ^WalletComp {
    return _comp(w, id, WalletComp, .Wallet)
}

world_set_gold :: proc(w: ^World, id: int, c: GoldComp) {
    _comp_set(w, id, GoldComp, .Gold, c)
}
world_get_gold :: proc(w: ^World, id: int) -> ^GoldComp {
    return _comp(w, id, GoldComp, .Gold)
}

world_set_npc :: proc(w: ^World, id: int, c: NPCComp) {
    _comp_set(w, id, NPCComp, .NPC, c)
}
world_get_npc :: proc(w: ^World, id: int) -> ^NPCComp {
    return _comp(w, id, NPCComp, .NPC)
}

world_set_mut_damage_mult :: proc(w: ^World, id: int, c: MutDamageMultComp) {
    _comp_set(w, id, MutDamageMultComp, .MutDamageMult, c)
}
world_get_mut_damage_mult :: proc(w: ^World, id: int) -> ^MutDamageMultComp {
    return _comp(w, id, MutDamageMultComp, .MutDamageMult)
}

world_set_mut_lock_hp_to_one :: proc(w: ^World, id: int) {
    _comp_set(w, id, MutLockHpToOneComp, .MutLockHpToOne, MutLockHpToOneComp{})
}

world_set_mut_root_on_fire :: proc(w: ^World, id: int, c: MutRootOnFireComp) {
    _comp_set(w, id, MutRootOnFireComp, .MutRootOnFire, c)
}
world_get_mut_root_on_fire :: proc(w: ^World, id: int) -> ^MutRootOnFireComp {
    return _comp(w, id, MutRootOnFireComp, .MutRootOnFire)
}

world_set_mut_timed_self_damage :: proc(w: ^World, id: int, c: MutTimedSelfDamageComp) {
    _comp_set(w, id, MutTimedSelfDamageComp, .MutTimedSelfDamage, c)
}
world_get_mut_timed_self_damage :: proc(w: ^World, id: int) -> ^MutTimedSelfDamageComp {
    return _comp(w, id, MutTimedSelfDamageComp, .MutTimedSelfDamage)
}

world_set_mut_block_healing :: proc(w: ^World, id: int) {
    _comp_set(w, id, MutBlockHealingComp, .MutBlockHealing, MutBlockHealingComp{})
}

world_set_mut_move_speed_mult :: proc(w: ^World, id: int, c: MutMoveSpeedMultComp) {
    _comp_set(w, id, MutMoveSpeedMultComp, .MutMoveSpeedMult, c)
}
world_get_mut_move_speed_mult :: proc(w: ^World, id: int) -> ^MutMoveSpeedMultComp {
    return _comp(w, id, MutMoveSpeedMultComp, .MutMoveSpeedMult)
}

world_set_mut_block_ranged :: proc(w: ^World, id: int) {
    _comp_set(w, id, MutBlockRangedComp, .MutBlockRanged, MutBlockRangedComp{})
}

world_set_mut_block_pickup_heal :: proc(w: ^World, id: int) {
    _comp_set(w, id, MutBlockPickupHealComp, .MutBlockPickupHeal, MutBlockPickupHealComp{})
}

world_set_mut_serum_gain_mult :: proc(w: ^World, id: int, c: MutSerumGainMultComp) {
    _comp_set(w, id, MutSerumGainMultComp, .MutSerumGainMult, c)
}
world_get_mut_serum_gain_mult :: proc(w: ^World, id: int) -> ^MutSerumGainMultComp {
    return _comp(w, id, MutSerumGainMultComp, .MutSerumGainMult)
}

world_set_mut_block_pickups :: proc(w: ^World, id: int) {
    _comp_set(w, id, MutBlockPickupsComp, .MutBlockPickups, MutBlockPickupsComp{})
}

world_set_mut_nonlethal_shots :: proc(w: ^World, id: int) {
    _comp_set(w, id, MutNonlethalShotsComp, .MutNonlethalShots, MutNonlethalShotsComp{})
}

world_set_mut_disable_actives :: proc(w: ^World, id: int) {
    _comp_set(w, id, MutDisableActivesComp, .MutDisableActives, MutDisableActivesComp{})
}

world_set_mut_early_death_threshold :: proc(w: ^World, id: int, c: MutEarlyDeathThresholdComp) {
    _comp_set(w, id, MutEarlyDeathThresholdComp, .MutEarlyDeathThreshold, c)
}
world_get_mut_early_death_threshold :: proc(w: ^World, id: int) -> ^MutEarlyDeathThresholdComp {
    return _comp(w, id, MutEarlyDeathThresholdComp, .MutEarlyDeathThreshold)
}

world_set_mut_missing_health_damage :: proc(w: ^World, id: int, c: MutMissingHealthDamageComp) {
    _comp_set(w, id, MutMissingHealthDamageComp, .MutMissingHealthDamage, c)
}
world_get_mut_missing_health_damage :: proc(w: ^World, id: int) -> ^MutMissingHealthDamageComp {
    return _comp(w, id, MutMissingHealthDamageComp, .MutMissingHealthDamage)
}

world_set_mut_passive_power :: proc(w: ^World, id: int, c: MutPassivePowerComp) {
    _comp_set(w, id, MutPassivePowerComp, .MutPassivePower, c)
}
world_get_mut_passive_power :: proc(w: ^World, id: int) -> ^MutPassivePowerComp {
    return _comp(w, id, MutPassivePowerComp, .MutPassivePower)
}

world_set_mut_kill_heal :: proc(w: ^World, id: int, c: MutKillHealComp) {
    _comp_set(w, id, MutKillHealComp, .MutKillHeal, c)
}
world_get_mut_kill_heal :: proc(w: ^World, id: int) -> ^MutKillHealComp {
    return _comp(w, id, MutKillHealComp, .MutKillHeal)
}

world_set_mut_lifesteal :: proc(w: ^World, id: int, c: MutLifestealComp) {
    _comp_set(w, id, MutLifestealComp, .MutLifesteal, c)
}
world_get_mut_lifesteal :: proc(w: ^World, id: int) -> ^MutLifestealComp {
    return _comp(w, id, MutLifestealComp, .MutLifesteal)
}

world_set_mut_proximity_damage :: proc(w: ^World, id: int, c: MutProximityDamageComp) {
    _comp_set(w, id, MutProximityDamageComp, .MutProximityDamage, c)
}
world_get_mut_proximity_damage :: proc(w: ^World, id: int) -> ^MutProximityDamageComp {
    return _comp(w, id, MutProximityDamageComp, .MutProximityDamage)
}

world_set_mut_on_death_explode :: proc(w: ^World, id: int, c: MutOnDeathExplodeComp) {
    _comp_set(w, id, MutOnDeathExplodeComp, .MutOnDeathExplode, c)
}
world_get_mut_on_death_explode :: proc(w: ^World, id: int) -> ^MutOnDeathExplodeComp {
    return _comp(w, id, MutOnDeathExplodeComp, .MutOnDeathExplode)
}

world_set_mut_stationary_shield :: proc(w: ^World, id: int, c: MutStationaryShieldComp) {
    _comp_set(w, id, MutStationaryShieldComp, .MutStationaryShield, c)
}
world_get_mut_stationary_shield :: proc(w: ^World, id: int) -> ^MutStationaryShieldComp {
    return _comp(w, id, MutStationaryShieldComp, .MutStationaryShield)
}

world_set_mut_extra_dodge_charges :: proc(w: ^World, id: int, c: MutExtraDodgeChargesComp) {
    _comp_set(w, id, MutExtraDodgeChargesComp, .MutExtraDodgeCharges, c)
}
world_get_mut_extra_dodge_charges :: proc(w: ^World, id: int) -> ^MutExtraDodgeChargesComp {
    return _comp(w, id, MutExtraDodgeChargesComp, .MutExtraDodgeCharges)
}

world_set_mut_damage_taken_mult :: proc(w: ^World, id: int, c: MutDamageTakenMultComp) {
    _comp_set(w, id, MutDamageTakenMultComp, .MutDamageTakenMult, c)
}
world_get_mut_damage_taken_mult :: proc(w: ^World, id: int) -> ^MutDamageTakenMultComp {
    return _comp(w, id, MutDamageTakenMultComp, .MutDamageTakenMult)
}

world_set_mut_wall_phase :: proc(w: ^World, id: int) {
    _comp_set(w, id, MutWallPhaseComp, .MutWallPhase, MutWallPhaseComp{})
}

world_set_mut_body_melee :: proc(w: ^World, id: int, c: MutBodyMeleeComp) {
    _comp_set(w, id, MutBodyMeleeComp, .MutBodyMelee, c)
}
world_get_mut_body_melee :: proc(w: ^World, id: int) -> ^MutBodyMeleeComp {
    return _comp(w, id, MutBodyMeleeComp, .MutBodyMelee)
}

world_set_mut_corpse_trigger :: proc(w: ^World, id: int, c: MutCorpseTriggerComp) {
    _comp_set(w, id, MutCorpseTriggerComp, .MutCorpseTrigger, c)
}
world_get_mut_corpse_trigger :: proc(w: ^World, id: int) -> ^MutCorpseTriggerComp {
    return _comp(w, id, MutCorpseTriggerComp, .MutCorpseTrigger)
}

world_set_mut_hide_enemy_sprites :: proc(w: ^World, id: int) {
    _comp_set(w, id, MutHideEnemySpritesComp, .MutHideEnemySprites, MutHideEnemySpritesComp{})
}

world_set_mut_unseen_damage_mult :: proc(w: ^World, id: int, c: MutUnseenDamageMultComp) {
    _comp_set(w, id, MutUnseenDamageMultComp, .MutUnseenDamageMult, c)
}
world_get_mut_unseen_damage_mult :: proc(w: ^World, id: int) -> ^MutUnseenDamageMultComp {
    return _comp(w, id, MutUnseenDamageMultComp, .MutUnseenDamageMult)
}

world_set_mut_heart_cage :: proc(w: ^World, id: int, c: MutHeartCageComp) {
    _comp_set(w, id, MutHeartCageComp, .MutHeartCage, c)
}
world_get_mut_heart_cage :: proc(w: ^World, id: int) -> ^MutHeartCageComp {
    return _comp(w, id, MutHeartCageComp, .MutHeartCage)
}

world_set_mut_thorn_pact :: proc(w: ^World, id: int, c: MutThornPactComp) {
    _comp_set(w, id, MutThornPactComp, .MutThornPact, c)
}
world_get_mut_thorn_pact :: proc(w: ^World, id: int) -> ^MutThornPactComp {
    return _comp(w, id, MutThornPactComp, .MutThornPact)
}

world_set_mut_carrion_crown :: proc(w: ^World, id: int, c: MutCarrionCrownComp) {
    _comp_set(w, id, MutCarrionCrownComp, .MutCarrionCrown, c)
}
world_get_mut_carrion_crown :: proc(w: ^World, id: int) -> ^MutCarrionCrownComp {
    return _comp(w, id, MutCarrionCrownComp, .MutCarrionCrown)
}

world_set_mut_false_saint :: proc(w: ^World, id: int, c: MutFalseSaintComp) {
    _comp_set(w, id, MutFalseSaintComp, .MutFalseSaint, c)
}
world_get_mut_false_saint :: proc(w: ^World, id: int) -> ^MutFalseSaintComp {
    return _comp(w, id, MutFalseSaintComp, .MutFalseSaint)
}

world_set_mut_black_lung :: proc(w: ^World, id: int, c: MutBlackLungComp) {
    _comp_set(w, id, MutBlackLungComp, .MutBlackLung, c)
}
world_get_mut_black_lung :: proc(w: ^World, id: int) -> ^MutBlackLungComp {
    return _comp(w, id, MutBlackLungComp, .MutBlackLung)
}

world_set_reanimated :: proc(w: ^World, id: int, c: ReanimatedComp) {
    _comp_set(w, id, ReanimatedComp, .Reanimated, c)
}
world_get_reanimated :: proc(w: ^World, id: int) -> ^ReanimatedComp {
    return _comp(w, id, ReanimatedComp, .Reanimated)
}

world_set_point_light :: proc(w: ^World, id: int, c: PointLightComp) {
    _comp_set(w, id, PointLightComp, .PointLight, c)
}
world_get_point_light :: proc(w: ^World, id: int) -> ^PointLightComp {
    return _comp(w, id, PointLightComp, .PointLight)
}

world_set_anim_state :: proc(w: ^World, id: int, c: AnimStateComp) {
    _comp_set(w, id, AnimStateComp, .AnimState, c)
}
world_get_anim_state :: proc(w: ^World, id: int) -> ^AnimStateComp {
    return _comp(w, id, AnimStateComp, .AnimState)
}

world_set_collider :: proc(w: ^World, id: int, c: ColliderComp) {
    _comp_set(w, id, ColliderComp, .Collider, c)
}
world_get_collider :: proc(w: ^World, id: int) -> ^ColliderComp {
    return _comp(w, id, ColliderComp, .Collider)
}

world_set_projectile :: proc(w: ^World, id: int, c: ProjectileComp) {
    _comp_set(w, id, ProjectileComp, .Projectile, c)
}

world_set_self_destruct :: proc(w: ^World, id: int, c: SelfDestructComp) {
    _comp_set(w, id, SelfDestructComp, .SelfDestruct, c)
}

world_set_ai :: proc(w: ^World, id: int, c: AIAgentComp) {
    _comp_set(w, id, AIAgentComp, .AIAgent, c)
}
world_get_ai :: proc(w: ^World, id: int) -> ^AIAgentComp {
    return _comp(w, id, AIAgentComp, .AIAgent)
}

world_get_self_destruct :: proc(w: ^World, id: int) -> ^SelfDestructComp {
    return _comp(w, id, SelfDestructComp, .SelfDestruct)
}

world_set_melee_arc :: proc(w: ^World, id: int, c: MeleeArcComp) {
    _comp_set(w, id, MeleeArcComp, .MeleeArc, c)
}
world_get_melee_arc :: proc(w: ^World, id: int) -> ^MeleeArcComp {
    return _comp(w, id, MeleeArcComp, .MeleeArc)
}

world_set_respawn :: proc(w: ^World, id: int, c: RespawnComp) {
    _comp_set(w, id, RespawnComp, .Respawn, c)
}
world_get_respawn :: proc(w: ^World, id: int) -> ^RespawnComp {
    return _comp(w, id, RespawnComp, .Respawn)
}

world_set_inventory :: proc(w: ^World, id: int, c: InventoryComp) {
    _comp_set(w, id, InventoryComp, .Inventory, c)
}
world_get_inventory :: proc(w: ^World, id: int) -> ^InventoryComp {
    return _comp(w, id, InventoryComp, .Inventory)
}

world_set_item :: proc(w: ^World, id: int, c: ItemComp) {
    _comp_set(w, id, ItemComp, .Item, c)
}
world_get_item :: proc(w: ^World, id: int) -> ^ItemComp {
    return _comp(w, id, ItemComp, .Item)
}

world_set_ground_item :: proc(w: ^World, id: int) {
    _comp_set(w, id, GroundItemComp, .GroundItem, GroundItemComp{})
}
world_clear_ground_item :: proc(w: ^World, id: int) {
    _comp_clear(w, id, GroundItemComp, .GroundItem)
}

world_get_projectile :: proc(w: ^World, id: int) -> ^ProjectileComp {
    return _comp(w, id, ProjectileComp, .Projectile)
}

world_push_damage :: proc(w: ^World, target_id: int, amount: f32, source_id: int = 0, kind: DamageKind = .Physical) {
    append(&w.damage_events, DamageEvent{ target_id = target_id, amount = amount, source_id = source_id, kind = kind })
}

world_push_heal :: proc(w: ^World, target_id: int, amount: f32) {
    append(&w.damage_events, DamageEvent{ target_id = target_id, amount = -amount })
}

world_clear_damage_events :: proc(w: ^World) {
    clear(&w.damage_events)
}

world_tag_destroy :: proc(w: ^World, id: int) {
    if id >= 0 && id < len(w.entities) {
        w.entities[id].flags += { .ToDestroy }
    }
}

world_tag_is_destroy :: proc(w: ^World, id: int) -> bool {
    if id < 0 || id >= len(w.entities) { return false }
    return .ToDestroy in w.entities[id].flags
}

world_set_projectile_tag :: proc(w: ^World, id: int) {
    _comp_set(w, id, ProjectileTagComp, .ProjectileTag, ProjectileTagComp{})
}

world_set_fog_of_war :: proc(w: ^World, id: int) {
    _comp_set(w, id, FogOfWarComp, .FogOfWar, FogOfWarComp{})
}

world_set_weapon_data :: proc(w: ^World, id: int, c: WeaponComp) {
    _comp_set(w, id, WeaponComp, .Weapon, c)
}
world_get_weapon_data :: proc(w: ^World, id: int) -> ^WeaponComp {
    return _comp(w, id, WeaponComp, .Weapon)
}

world_set_equipment :: proc(w: ^World, id: int, c: EquipmentComp) {
    _comp_set(w, id, EquipmentComp, .Equipment, c)
}
world_get_equipment :: proc(w: ^World, id: int) -> ^EquipmentComp {
    return _comp(w, id, EquipmentComp, .Equipment)
}

world_set_dodge :: proc(w: ^World, id: int, c: DodgeComp) {
    _comp_set(w, id, DodgeComp, .DodgeState, c)
}
world_get_dodge :: proc(w: ^World, id: int) -> ^DodgeComp {
    return _comp(w, id, DodgeComp, .DodgeState)
}

world_set_render_config :: proc(w: ^World, id: int, c: RenderConfigComp) {
    _comp_set(w, id, RenderConfigComp, .RenderConfig, c)
}
world_get_render_config :: proc(w: ^World, id: int) -> ^RenderConfigComp {
    return _comp(w, id, RenderConfigComp, .RenderConfig)
}

world_set_status_effect :: proc(w: ^World, id: int, c: StatusEffectComp) {
    _comp_set(w, id, StatusEffectComp, .StatusEffect, c)
}
world_get_status_effects :: proc(w: ^World, id: int) -> ^StatusEffectComp {
    return _comp(w, id, StatusEffectComp, .StatusEffect)
}

status_effect_apply :: proc(w: ^World, id: int, effect: StatusEffect) {
    if !world_has_component(w, id, .StatusEffect) {
        world_set_status_effect(w, id, StatusEffectComp{})
    }
    sec := world_get_status_effects(w, id)

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

world_set_ability :: proc(w: ^World, id: int, c: AbilityComp) {
    _comp_set(w, id, AbilityComp, .Ability, c)
}
world_get_ability :: proc(w: ^World, id: int) -> ^AbilityComp {
    return _comp(w, id, AbilityComp, .Ability)
}

world_set_stats :: proc(w: ^World, id: int, c: StatsComp) {
    _comp_set(w, id, StatsComp, .Stats, c)
}
world_get_stats :: proc(w: ^World, id: int) -> ^StatsComp {
    return _comp(w, id, StatsComp, .Stats)
}

world_entity_count :: proc(w: ^World) -> int {
    count := 0
    for e in w.entities {
        if entity_is_active(e) { count += 1 }
    }
    return count
}

world_has_component :: proc(w: ^World, id: int, ct: ComponentType) -> bool {
    if !world_is_valid(w, id) { return false }
    return entity_sig_has(w.entities[id].signature, ct)
}

Query :: struct {
    w:        ^World,
    mask:     ComponentSignature,
    word_idx: int,
    base:     int,
    cur_word: u64,
}

world_query_iter :: proc(w: ^World, mask: ComponentSignature) -> Query {
    return Query{ w = w, mask = mask }
}

query_next :: proc(q: ^Query) -> (id: int, ok: bool) {
    for {
        for q.cur_word != 0 {
            bit      := int(intrinsics.count_trailing_zeros(q.cur_word))
            q.cur_word &= q.cur_word - 1
            eid      := q.base + bit
            if eid < len(q.w.entities) && entity_is_active(q.w.entities[eid]) {
                return eid, true
            }
        }
        words := len(q.w.pools[ComponentType(0)].bitset)
        if q.word_idx >= words { return INVALID_ENTITY, false }
        combined := ~u64(0)
        for cm := u128(q.mask); cm != 0; cm &= cm - 1 {
            combined &= q.w.pools[ComponentType(intrinsics.count_trailing_zeros(cm))].bitset[q.word_idx]
        }
        q.base     = q.word_idx * 64
        q.word_idx += 1
        q.cur_word  = combined
    }
}

world_query :: proc(w: ^World, mask: ComponentSignature, allocator := context.allocator) -> []int {
    results := make([dynamic]int, allocator)
    q := world_query_iter(w, mask)
    for {
        id, ok := query_next(&q)
        if !ok { break }
        append(&results, id)
    }
    return results[:]
}

query_mask :: proc(types: ..ComponentType) -> ComponentSignature {
    mask := ComponentSignature(0)
    for t in types {
        mask |= ComponentSignature(1) << uint(t)
    }
    return mask
}

SystemEvent :: enum u16 {
    Initialized     = 0,
    GameplayStarted = 1,
    GameplayStopped = 2,
    EarlyUpdate     = 3,
    Update          = 4,
    LateUpdate      = 5,
    PhysicsUpdate   = 6,
    CreateEntity    = 7,
    DestroyEntity   = 8,
    Shutdown        = 9,
}

SystemEventMask :: distinct bit_set[SystemEvent; u16]

SystemProc :: #type proc(w: ^World, event: SystemEvent, dt: f32)

RegisteredSystem :: struct {
    mask: SystemEventMask,
    proc_: SystemProc,
}

Simulation :: struct {
    world:   World,
    systems: [dynamic]RegisteredSystem,
    state:   SimState,
}

SimState :: enum u8 {
    Initializing,
    Running,
    Paused,
    Stopped,
}

make_simulation :: proc() -> Simulation {
    return Simulation{
        world = make_world(),
        state = .Initializing,
    }
}

destroy_simulation :: proc(s: ^Simulation) {
    destroy_world(&s.world)
    delete(s.systems)
}

sim_register_system :: proc(s: ^Simulation, mask: SystemEventMask, p: SystemProc) {
    append(&s.systems, RegisteredSystem{ mask = mask, proc_ = p })
}

sim_broadcast :: proc(s: ^Simulation, event: SystemEvent, dt: f32 = 0) {
    for &sys in s.systems {
        if event in sys.mask {
            sys.proc_(&s.world, event, dt)
        }
    }
}

sim_tick :: proc(s: ^Simulation, dt: f32) {
    if s.state != .Running { return }

    sim_broadcast(s, .EarlyUpdate,  dt)
    sim_broadcast(s, .Update,       dt)
    sim_broadcast(s, .LateUpdate,   dt)

    sim_broadcast(s, .DestroyEntity, dt)
    world_sweep(&s.world)
    sim_broadcast(s, .CreateEntity,  dt)

    s.world.tick += 1
}

movement_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    mask := query_mask(.Transform, .Velocity)
    ids  := world_query(w, mask)
    defer delete(ids)

    for id in ids {
        t := world_get_transform(w, id)
        v := world_get_velocity(w, id)

        vel_mult := f32(1.0)
        if world_has_component(w, id, .StatusEffect) {
            sec := world_get_status_effects(w, id)
            if status_effect_is_active(sec, .Slow) {
                slow := status_effect_get(sec, .Slow)
                vel_mult *= (1.0 - slow.strength)
            }
        }

        t.position[0] += v.value[0] * vel_mult * dt
        t.position[1] += v.value[1] * vel_mult * dt
        t.position[2] += v.value[2] * vel_mult * dt
    }
}

projectile_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    mask := query_mask(.Transform, .Projectile)
    ids  := world_query(w, mask)
    defer delete(ids)

    for id in ids {
        t := world_get_transform(w, id)
        p := world_get_projectile(w, id)

        t.position[0] += p.direction[0] * p.speed * dt
        t.position[1] += p.direction[1] * p.speed * dt
        t.position[2] += p.direction[2] * p.speed * dt

        p.lifetime -= dt
        if p.lifetime <= 0 {
            w.entities[id].flags += { .ToDestroy }
        }
    }
}

self_destruct_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .Update { return }

    mask := query_mask(.SelfDestruct)
    ids  := world_query(w, mask)
    defer delete(ids)

    for id in ids {
        sd := world_get_self_destruct(w, id)
        sd.timer -= dt
        if sd.timer <= 0 {
            w.entities[id].flags += { .ToDestroy }
        }
    }
}

destroy_system :: proc(w: ^World, event: SystemEvent, dt: f32) {
    if event != .DestroyEntity { return }

    for i in 0..<len(w.entities) {
        e := w.entities[i]
        if entity_is_active(e) && .ToDestroy in e.flags {
            world_destroy_entity(w, e.id)
        }
    }
}

make_default_simulation :: proc() -> Simulation {
    s := make_simulation()

    sim_register_system(&s,
        { .Update },
        movement_system)

    sim_register_system(&s,
        { .Update },
        projectile_system)

    sim_register_system(&s,
        { .Update },
        self_destruct_system)

    sim_register_system(&s,
        { .DestroyEntity },
        destroy_system)

    return s
}
