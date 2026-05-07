package clockwork


CHUNK_SIZE      :: 256
MAX_COMPONENTS  :: 128  // u128 bitfield ceiling
INVALID_ENTITY  :: -1
MAX_PLAYERS     :: 4    // maximum simultaneous player slots

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

StatusEffectType :: enum { Slow, Poison, Burn, Stun, Root, Oiled, Wet }
EffectApplicationPolicy :: enum {Flat, Base, Percent}
EffectStackPolicy  :: enum {Stack, Refresh, Extend}

StatusEffect :: struct {
    type:     StatusEffectType,
    application: EffectApplicationPolicy,
    stack_behavior: EffectStackPolicy,
    duration: f32,
    strength: f32, 
    source_id: int,
}

MAX_STATUS_EFFECTS :: 8   

FlammableComp :: struct {
    isImmune : bool
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
    iron_will_consumed: bool,   // true after IronHeart has saved the player this life
    shield:             f32,    // current shield HP (absorbs damage before HP)
}

InputStateComp :: struct {
    move:           [2]f32,   
    mouse_world:    [3]f32,   
    fire_pressed:   bool,
    reload_pressed: bool,     
    dodge_pressed:  bool,     
    skill1_pressed: bool,
    skill2_pressed: bool,
    skill3_pressed: bool,
    skill4_pressed: bool,
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
    radius:          f32,   // aura radius in world units
    // Direct damage (scaled by dt each tick)
    dps:             f32,   // damage per second; 0 = disabled
    self_fraction:   f32,   // fraction of dps applied back to owner
    // Status-effect application
    effect_type:     StatusEffectType,  // Slow, Poison, Burn, Stun, Root
    effect_strength: f32,   // effect strength parameter; 0 = disabled
    effect_duration: f32,   // how long the status lasts on the target
    // Optional point light
    light_color:     [3]f32,  // RGB 0-255; all zero = no light
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

HEART_CAGE_ORBIT_RADIUS :: f32(80.0)   // world-space pixels from player centre
HEART_CAGE_ORBIT_SPEED  :: f32(0.9)    // radians per second
CARRION_MAX_SERVANTS    :: 3

// HeartCage: an external heart that orbits the player.  While it lives,
// enemies target it and the player is immune to all damage.  When the
// heart is destroyed the player dies — no respawn.
MutHeartCageComp :: struct {
    heart_id:    int,   // entity whose Transform + Health track the heart
    max_hp_pct:  f32,   // heart max_hp = player.max * max_hp_pct (stored for respawn)
    orbit_angle: f32,   // current angle in radians (advances each tick)
}

// CarrionCrown: tracks reanimated servant entity IDs.
MutCarrionCrownComp :: struct {
    servant_ids: [CARRION_MAX_SERVANTS]int,
}

// Reanimated: tag applied to servant entities created by CarrionCrown.
ReanimatedComp :: struct {
    owner_id: int,
}

// BlackLung: pressure builds on every hit; releases as area DPS.
MutBlackLungComp :: struct {
    pressure:     f32,   // 0..100
    regen_rate:   f32,   // pressure decay per second (when not hit)
    gain_per_hit: f32,   // pressure gained per incoming hit
    dps_max:      f32,   // damage/s at pressure == 100
    radius:       f32,   // aura radius in world units
}

// ThornPact: reflects incoming damage; reduces all healing.
MutThornPactComp :: struct {
    reflect_pct:   f32,   // fraction of damage reflected to attacker
    slow_heal_mult: f32,  // multiplier on any incoming heal (0.5 = 50%)
}

// FalseSaint: slow aura + idle-enemy beacon.
MutFalseSaintComp :: struct {
    aura_radius:   f32,   // enemies inside are slowed
    slow_mult:     f32,   // velocity multiplier (< 1 = slower)
    beacon_radius: f32,   // idle enemies inside are forced to aggro
}


PointLightComp :: struct {
    color:     [3]f32,  // RGB 0..255
    radius:    f32,     // falloff radius in world units
    intensity: f32,     // multiplier (1.0 = normal)
}

AnimStateName :: enum u8 { Idle, Walk, Dodge, Attack, Death }

AnimStateComp :: struct {
    current_state: AnimStateName,
    frame_index:   int,
    elapsed:       f32,
}

ExtractionComp :: struct {
    interact_radius: f32,
    activate_time:   f32,   // seconds player must hold interact key
    timer:           f32,   // runtime: how long player has been holding
    activated:       bool,
}

PlayerComp :: struct {
    slot: int,   // 0..MAX_PLAYERS-1
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
    faction:   u8,   // 0 = player, 1 = enemy, 2 = neutral
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

AIAgentComp :: struct {
    state:        u8,    // 0=idle 1=chase 2=attack
    target_id:    int,
    cooldown:     f32, 

    // config (from JSON, never mutated during play)
    aggro_range:  f32,
    attack_range: f32,
    cooldown_max: f32,   
    speed:        f32,   
    damage:       f32,   
    ai_type:      AIType,  // .Melee = arc swing, .Ranged = shotgun burst
    pellet_count: int,     
    spread_angle: f32,     
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

DamageEvent :: struct {
    target_id: int,
    amount:    f32,
    source_id: int,  
}

RespawnComp :: struct {
    spawn_pos: [3]f32,
    delay:     f32,  
    timer:     f32,  
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
    // Corpus
    SerratedHands,   
    HollowBones,     
    Exoskeleton,     
    Symbiote,        
    LivingBomb,      
    // Shadow
    GlassCannon,     
    BlindFire,       
    Timelock,        
    SpectralForm,    
    DeadmansTrigger, 
    // Venom
    BloodFrenzy,     
    ToxicFlesh,      
    ParasiteKing,    
    CorpseTide,      
    Metamorphosis,
    // Flagship
    HeartCage,
    ThornPact,
    CarrionCrown,
    FalseSaint,
    BlackLung,
}

MAX_AFFIXES :: 6

AbilityType :: enum u8 {
    None,
    //Active abiities
    QuickDraw,      
    FanTheHammer,   
    BulletRain,     
    DoubleTap,      
    MagDump,        
    LastStand,      
    Deadeye,        
    HeavyCalibur,   
    DeathShot,      
    CorruptRound,   
    MarkedTarget,   
    Execute,        
    Headshot,       
    TrickShot,      
    IronWill,       
    InstinctReload, 
    DevilsDance,    
    //Passive abilities 
    SteadyAim,      
    HuntersReflex,  
    Deathwish,      
    EagleEye,       
}

AffixType :: enum u8 {
    None,
    BonusHP,          // +X% max HP
    Armor,            // +X% incoming damage reduction (capped at 75%)
    BonusMoveSpeed,   // +X% move speed
    BonusEnergy,      // +X% max energy
    BonusDamage,      // +X% weapon damage (ranged + melee)
    BonusFireRate,    // +X% fire rate
    BonusReloadSpeed, // +X% reload speed
    HealthRegen,      // +X% of max HP regenerated per second
    // Ranged-specific
    BonusProjSpeed,   // +X% projectile speed
    BonusPierce,      // +1 enemies pierced per projectile (flat; value always 1.0)
    BonusAmmo,        // +X% magazine capacity
    // Melee-specific
    BonusMeleeDamage, // +X% melee damage (stacks with BonusDamage)
    BonusMeleeRange,  // +X% melee arc radius
    BonusMeleeSpeed,  // +X% attack speed (reduces cooldown)
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

    // Explicit per-item base combat stats (0 = unset; weapon_system falls back to archetype defaults)
    base_damage:      f32,   // ranged: damage per shot; melee uses melee_damage
    base_fire_rate:   f32,   // ranged: shots per second
    base_ammo_max:    u8,    // ranged: magazine capacity
    base_reload_time: f32,   // ranged: reload duration in seconds
    base_proj_speed:  f32,   // ranged: projectile speed
    base_armor:       f32,   // flat damage reduction fraction (additive with Armor affixes)
    base_shield:      f32,   // max shield HP granted by this item
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
    // static config
    type:             WeaponType,
    damage:           f32,
    fire_rate:        f32,    
    projectile_speed: f32,    
    projectile_life:  f32,    
    range:            f32,    
    ammo_max:         int,    
    reload_time:      f32,    

    //runtime state
    cooldown:         f32,    
    ammo_current:     int,    
    reload_timer:     f32,    
    is_reloading:     bool,
}

EquipmentComp :: struct {
    weapon_entity_id: int,
}

DodgeComp :: struct {
    // runtime state
    active:       bool,
    direction:    [2]f32,   
    timer:        f32,      
    cooldown:     f32,      

    // config
    duration:     f32,      
    speed:        f32,      
    cooldown_max: f32,      
}

AbilitySlotState :: struct {
    cooldown:     f32,  
    burst_shots:  int,  
    burst_timer:  f32,  
    charging:     bool, 
    charge_timer: f32,  
    dance_ready:  bool, 
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
    display_name: [RENDER_NAME_CAP]u8,
    name_len:     u8,
    icon_name:    [RENDER_ICON_CAP]u8,
    icon_len:     u8,
    sprite_name:  [RENDER_SPRITE_CAP]u8,
    sprite_len:   u8,
    sprite_scale: f32,
    world_size:   f32,
    render_layer: RenderLayer,
    show_hp_bar:  bool,
    show_dir_tip: bool,
    desc:         [RENDER_DESC_CAP]u8,
    desc_len:     u8,
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
    // Entity slots
    entities:     [dynamic]Entity,
    next_id:      int,
    recycled_ids: [dynamic]int,
    last_created: int,

    player_ids:        [MAX_PLAYERS]int,
    local_player_slot: int,
    player_id:         int,

    transforms:   [dynamic]TransformComp,
    velocities:   [dynamic]VelocityComp,
    healths:      [dynamic]HealthComp,
    inputs:       [dynamic]InputStateComp,
    weapons:      [dynamic]WeaponSlotComp,
    mutations:    [dynamic]MutationContainerComp,
    renderers:    [dynamic]MeshRendererComp,
    colliders:    [dynamic]ColliderComp,
    projectiles:     [dynamic]ProjectileComp,
    self_destructs:  [dynamic]SelfDestructComp,
    ai_agents:       [dynamic]AIAgentComp,
    projectile_tags: [dynamic]ProjectileTagComp,
    weapon_data:     [dynamic]WeaponComp,
    equipment:       [dynamic]EquipmentComp,
    dodge_states:    [dynamic]DodgeComp,
    render_configs:  [dynamic]RenderConfigComp,
    melee_arcs:      [dynamic]MeleeArcComp,
    respawns:        [dynamic]RespawnComp,
    inventories:     [dynamic]InventoryComp,
    items:           [dynamic]ItemComp,
    ground_items:    [dynamic]GroundItemComp,
    abilities:          [dynamic]AbilityComp,
    stats:              [dynamic]StatsComp,
    fog_of_wars:        [dynamic]FogOfWarComp,
    extractions:        [dynamic]ExtractionComp,
    muts:               [dynamic]MutComp,
    players:            [dynamic]PlayerComp,
    wallets:            [dynamic]WalletComp,
    golds:              [dynamic]GoldComp,
    npcs:               [dynamic]NPCComp,
    mut_damage_mults:   [dynamic]MutDamageMultComp,
    mut_lock_hp_to_one: [dynamic]MutLockHpToOneComp,
    mut_root_on_fire:   [dynamic]MutRootOnFireComp,
    mut_timed_self_dmg: [dynamic]MutTimedSelfDamageComp,
    mut_block_healing:  [dynamic]MutBlockHealingComp,
    mut_move_speed:     [dynamic]MutMoveSpeedMultComp,
    mut_block_ranged:   [dynamic]MutBlockRangedComp,
    mut_block_pickup_heal: [dynamic]MutBlockPickupHealComp,
    mut_serum_gain:     [dynamic]MutSerumGainMultComp,
    mut_block_pickups:  [dynamic]MutBlockPickupsComp,
    mut_nonlethal:      [dynamic]MutNonlethalShotsComp,
    mut_disable_actives:[dynamic]MutDisableActivesComp,
    mut_early_death:    [dynamic]MutEarlyDeathThresholdComp,
    mut_missing_hp_dmg: [dynamic]MutMissingHealthDamageComp,
    mut_passive_power:  [dynamic]MutPassivePowerComp,
    point_lights:       [dynamic]PointLightComp,
    anim_states:        [dynamic]AnimStateComp,
    mut_kill_heal:          [dynamic]MutKillHealComp,
    mut_lifesteal:          [dynamic]MutLifestealComp,
    mut_proximity_damage:   [dynamic]MutProximityDamageComp,
    mut_on_death_explode:   [dynamic]MutOnDeathExplodeComp,
    mut_stationary_shield:  [dynamic]MutStationaryShieldComp,
    mut_extra_dodges:       [dynamic]MutExtraDodgeChargesComp,
    mut_dmg_taken_mult:     [dynamic]MutDamageTakenMultComp,
    mut_wall_phase:         [dynamic]MutWallPhaseComp,
    mut_body_melee:         [dynamic]MutBodyMeleeComp,
    mut_corpse_trigger:     [dynamic]MutCorpseTriggerComp,
    mut_hide_enemy_sprites: [dynamic]MutHideEnemySpritesComp,
    mut_unseen_dmg_mult:    [dynamic]MutUnseenDamageMultComp,
    mut_heart_cage:         [dynamic]MutHeartCageComp,
    mut_thorn_pact:         [dynamic]MutThornPactComp,
    mut_carrion_crown:      [dynamic]MutCarrionCrownComp,
    mut_false_saint:        [dynamic]MutFalseSaintComp,
    mut_black_lung:         [dynamic]MutBlackLungComp,
    reanimateds:            [dynamic]ReanimatedComp,
    status_effects:         [dynamic]StatusEffectComp,
    flammbles:              [dynamic]FlammableComp,

    damage_events:   [dynamic]DamageEvent,

    tick: u64,
}

make_world :: proc() -> World {
    w := World{}
    for &id in w.player_ids { id = INVALID_ENTITY }
    w.local_player_slot = 0
    w.player_id    = INVALID_ENTITY
    w.next_id      = 0
    w.last_created = INVALID_ENTITY

    resize(&w.entities,      CHUNK_SIZE)
    resize(&w.transforms,    CHUNK_SIZE)
    resize(&w.velocities,    CHUNK_SIZE)
    resize(&w.healths,       CHUNK_SIZE)
    resize(&w.inputs,        CHUNK_SIZE)
    resize(&w.weapons,       CHUNK_SIZE)
    resize(&w.mutations,     CHUNK_SIZE)
    resize(&w.renderers,     CHUNK_SIZE)
    resize(&w.colliders,     CHUNK_SIZE)
    resize(&w.projectiles,     CHUNK_SIZE)
    resize(&w.self_destructs,  CHUNK_SIZE)
    resize(&w.ai_agents,       CHUNK_SIZE)
    resize(&w.projectile_tags, CHUNK_SIZE)
    resize(&w.weapon_data,     CHUNK_SIZE)
    resize(&w.equipment,       CHUNK_SIZE)
    resize(&w.dodge_states,    CHUNK_SIZE)
    resize(&w.render_configs,  CHUNK_SIZE)
    resize(&w.melee_arcs,      CHUNK_SIZE)
    resize(&w.respawns,        CHUNK_SIZE)
    resize(&w.inventories,     CHUNK_SIZE)
    resize(&w.items,           CHUNK_SIZE)
    resize(&w.ground_items,    CHUNK_SIZE)
    resize(&w.abilities,          CHUNK_SIZE)
    resize(&w.stats,              CHUNK_SIZE)
    resize(&w.fog_of_wars,        CHUNK_SIZE)
    resize(&w.extractions,        CHUNK_SIZE)
    resize(&w.muts,               CHUNK_SIZE)
    resize(&w.players,            CHUNK_SIZE)
    resize(&w.wallets,            CHUNK_SIZE)
    resize(&w.golds,              CHUNK_SIZE)
    resize(&w.npcs,               CHUNK_SIZE)
    resize(&w.mut_damage_mults,   CHUNK_SIZE)
    resize(&w.mut_lock_hp_to_one, CHUNK_SIZE)
    resize(&w.mut_root_on_fire,   CHUNK_SIZE)
    resize(&w.mut_timed_self_dmg, CHUNK_SIZE)
    resize(&w.mut_block_healing,  CHUNK_SIZE)
    resize(&w.mut_move_speed,     CHUNK_SIZE)
    resize(&w.mut_block_ranged,   CHUNK_SIZE)
    resize(&w.mut_block_pickup_heal, CHUNK_SIZE)
    resize(&w.mut_serum_gain,     CHUNK_SIZE)
    resize(&w.mut_block_pickups,  CHUNK_SIZE)
    resize(&w.mut_nonlethal,      CHUNK_SIZE)
    resize(&w.mut_disable_actives,CHUNK_SIZE)
    resize(&w.mut_early_death,    CHUNK_SIZE)
    resize(&w.mut_missing_hp_dmg, CHUNK_SIZE)
    resize(&w.mut_passive_power,  CHUNK_SIZE)
    resize(&w.point_lights,       CHUNK_SIZE)
    resize(&w.anim_states,        CHUNK_SIZE)
    resize(&w.mut_kill_heal,          CHUNK_SIZE)
    resize(&w.mut_lifesteal,          CHUNK_SIZE)
    resize(&w.mut_proximity_damage,   CHUNK_SIZE)
    resize(&w.mut_on_death_explode,   CHUNK_SIZE)
    resize(&w.mut_stationary_shield,  CHUNK_SIZE)
    resize(&w.mut_extra_dodges,       CHUNK_SIZE)
    resize(&w.mut_dmg_taken_mult,     CHUNK_SIZE)
    resize(&w.mut_wall_phase,         CHUNK_SIZE)
    resize(&w.mut_body_melee,         CHUNK_SIZE)
    resize(&w.mut_corpse_trigger,     CHUNK_SIZE)
    resize(&w.mut_hide_enemy_sprites, CHUNK_SIZE)
    resize(&w.mut_unseen_dmg_mult,    CHUNK_SIZE)
    resize(&w.mut_heart_cage,         CHUNK_SIZE)
    resize(&w.mut_thorn_pact,         CHUNK_SIZE)
    resize(&w.mut_carrion_crown,      CHUNK_SIZE)
    resize(&w.mut_false_saint,        CHUNK_SIZE)
    resize(&w.mut_black_lung,         CHUNK_SIZE)
    resize(&w.reanimateds,            CHUNK_SIZE)
    resize(&w.status_effects,         CHUNK_SIZE)
    resize(&w.flammbles,              CHUNK_SIZE)
    for i in 0..<CHUNK_SIZE {
        w.entities[i] = entity_empty()
    }

    return w
}

destroy_world :: proc(w: ^World) {
    delete(w.entities)
    delete(w.transforms)
    delete(w.velocities)
    delete(w.healths)
    delete(w.inputs)
    delete(w.weapons)
    delete(w.mutations)
    delete(w.renderers)
    delete(w.colliders)
    delete(w.projectiles)
    delete(w.self_destructs)
    delete(w.ai_agents)
    delete(w.projectile_tags)
    delete(w.weapon_data)
    delete(w.equipment)
    delete(w.dodge_states)
    delete(w.render_configs)
    delete(w.melee_arcs)
    delete(w.respawns)
    delete(w.inventories)
    delete(w.items)
    delete(w.ground_items)
    delete(w.abilities)
    delete(w.stats)
    delete(w.fog_of_wars)
    delete(w.extractions)
    delete(w.muts)
    delete(w.players)
    delete(w.wallets)
    delete(w.golds)
    delete(w.npcs)
    delete(w.mut_damage_mults)
    delete(w.mut_lock_hp_to_one)
    delete(w.mut_root_on_fire)
    delete(w.mut_timed_self_dmg)
    delete(w.mut_block_healing)
    delete(w.mut_move_speed)
    delete(w.mut_block_ranged)
    delete(w.mut_block_pickup_heal)
    delete(w.mut_serum_gain)
    delete(w.mut_block_pickups)
    delete(w.mut_nonlethal)
    delete(w.mut_disable_actives)
    delete(w.mut_early_death)
    delete(w.mut_missing_hp_dmg)
    delete(w.mut_passive_power)
    delete(w.point_lights)
    delete(w.anim_states)
    delete(w.mut_kill_heal)
    delete(w.mut_lifesteal)
    delete(w.mut_proximity_damage)
    delete(w.mut_on_death_explode)
    delete(w.mut_stationary_shield)
    delete(w.mut_extra_dodges)
    delete(w.mut_dmg_taken_mult)
    delete(w.mut_wall_phase)
    delete(w.mut_body_melee)
    delete(w.mut_corpse_trigger)
    delete(w.mut_hide_enemy_sprites)
    delete(w.mut_unseen_dmg_mult)
    delete(w.mut_heart_cage)
    delete(w.mut_thorn_pact)
    delete(w.mut_carrion_crown)
    delete(w.mut_false_saint)
    delete(w.mut_black_lung)
    delete(w.reanimateds)
    delete(w.damage_events)
    delete(w.recycled_ids)
    delete(w.status_effects)
    delete(w.flammbles)
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

    e.flags     = {}
    e.signature = 0
    w.entities[id] = entity_empty()

    w.transforms[id]    = {}
    w.velocities[id]    = {}
    w.healths[id]       = {}
    w.inputs[id]        = {}
    w.weapons[id]       = {}
    w.mutations[id]     = {}
    w.renderers[id]     = {}
    w.colliders[id]     = {}
    w.projectiles[id]     = {}
    w.self_destructs[id]  = {}
    w.ai_agents[id]       = {}
    w.projectile_tags[id] = {}
    w.weapon_data[id]     = {}
    w.equipment[id]       = {}
    w.dodge_states[id]    = {}
    w.render_configs[id]  = {}
    w.melee_arcs[id]      = {}
    w.respawns[id]        = {}
    w.inventories[id]     = inventory_make_empty()
    w.items[id]           = item_empty()
    w.ground_items[id]    = {}
    w.abilities[id]          = {}
    w.stats[id]              = {}
    w.fog_of_wars[id]        = {}
    w.extractions[id]        = {}
    w.muts[id]               = {}
    w.players[id]            = {}
    w.wallets[id]            = {}
    w.golds[id]              = {}
    w.npcs[id]               = {}
    w.mut_damage_mults[id]   = {}
    w.mut_lock_hp_to_one[id] = {}
    w.mut_root_on_fire[id]   = {}
    w.mut_timed_self_dmg[id] = {}
    w.mut_block_healing[id]  = {}
    w.mut_move_speed[id]     = {}
    w.mut_block_ranged[id]   = {}
    w.mut_block_pickup_heal[id] = {}
    w.mut_serum_gain[id]     = {}
    w.mut_block_pickups[id]  = {}
    w.mut_nonlethal[id]      = {}
    w.mut_disable_actives[id]= {}
    w.mut_early_death[id]    = {}
    w.mut_missing_hp_dmg[id] = {}
    w.mut_passive_power[id]  = {}
    w.point_lights[id]       = {}
    w.anim_states[id]        = {}
    w.mut_kill_heal[id]          = {}
    w.mut_lifesteal[id]          = {}
    w.mut_proximity_damage[id]   = {}
    w.mut_on_death_explode[id]   = {}
    w.mut_stationary_shield[id]  = {}
    w.mut_extra_dodges[id]       = {}
    w.mut_dmg_taken_mult[id]     = {}
    w.mut_wall_phase[id]         = {}
    w.mut_body_melee[id]         = {}
    w.mut_corpse_trigger[id]     = {}
    w.mut_hide_enemy_sprites[id] = {}
    w.mut_unseen_dmg_mult[id]    = {}
    w.mut_heart_cage[id]         = {}
    w.mut_thorn_pact[id]         = {}
    w.mut_carrion_crown[id]      = {}
    w.mut_false_saint[id]        = {}
    w.mut_black_lung[id]         = {}
    w.reanimateds[id]            = {}
    w.status_effects[id]           = {}
    w.flammbles[id]                = {}
    append(&w.recycled_ids, id)
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

    resize(&w.entities,      target)
    resize(&w.transforms,    target)
    resize(&w.velocities,    target)
    resize(&w.healths,       target)
    resize(&w.inputs,        target)
    resize(&w.weapons,       target)
    resize(&w.mutations,     target)
    resize(&w.renderers,     target)
    resize(&w.colliders,     target)
    resize(&w.projectiles,     target)
    resize(&w.self_destructs,  target)
    resize(&w.ai_agents,       target)
    resize(&w.projectile_tags, target)
    resize(&w.weapon_data,     target)
    resize(&w.equipment,       target)
    resize(&w.dodge_states,    target)
    resize(&w.render_configs,  target)
    resize(&w.melee_arcs,      target)
    resize(&w.respawns,        target)
    resize(&w.inventories,     target)
    resize(&w.items,           target)
    resize(&w.ground_items,    target)
    resize(&w.abilities,         target)
    resize(&w.stats,             target)
    resize(&w.fog_of_wars,       target)
    resize(&w.extractions,       target)
    resize(&w.muts,              target)
    resize(&w.players,            target)
    resize(&w.wallets,            target)
    resize(&w.golds,              target)
    resize(&w.npcs,               target)
    resize(&w.mut_damage_mults,   target)
    resize(&w.mut_lock_hp_to_one, target)
    resize(&w.mut_root_on_fire,   target)
    resize(&w.mut_timed_self_dmg, target)
    resize(&w.mut_block_healing,  target)
    resize(&w.mut_move_speed,     target)
    resize(&w.mut_block_ranged,   target)
    resize(&w.mut_block_pickup_heal, target)
    resize(&w.mut_serum_gain,     target)
    resize(&w.mut_block_pickups,  target)
    resize(&w.mut_nonlethal,      target)
    resize(&w.mut_disable_actives,target)
    resize(&w.mut_early_death,    target)
    resize(&w.mut_missing_hp_dmg, target)
    resize(&w.mut_passive_power,  target)
    resize(&w.point_lights,       target)
    resize(&w.anim_states,        target)
    resize(&w.mut_kill_heal,          target)
    resize(&w.mut_lifesteal,          target)
    resize(&w.mut_proximity_damage,   target)
    resize(&w.mut_on_death_explode,   target)
    resize(&w.mut_stationary_shield,  target)
    resize(&w.mut_extra_dodges,       target)
    resize(&w.mut_dmg_taken_mult,     target)
    resize(&w.mut_wall_phase,         target)
    resize(&w.mut_body_melee,         target)
    resize(&w.mut_corpse_trigger,     target)
    resize(&w.mut_hide_enemy_sprites, target)
    resize(&w.mut_unseen_dmg_mult,    target)
    resize(&w.mut_heart_cage,         target)
    resize(&w.mut_thorn_pact,         target)
    resize(&w.mut_carrion_crown,      target)
    resize(&w.mut_false_saint,        target)
    resize(&w.mut_black_lung,         target)
    resize(&w.reanimateds,            target)
    resize(&w.status_effects,         target)
    resize(&w.flammbles,              target)
}

world_set_transform :: proc(w: ^World, id: int, c: TransformComp) {
    w.transforms[id] = c
    entity_sig_set(&w.entities[id].signature, .Transform)
}
world_get_transform :: proc(w: ^World, id: int) -> ^TransformComp {
    return &w.transforms[id]
}

world_set_velocity :: proc(w: ^World, id: int, c: VelocityComp) {
    w.velocities[id] = c
    entity_sig_set(&w.entities[id].signature, .Velocity)
}
world_get_velocity :: proc(w: ^World, id: int) -> ^VelocityComp {
    return &w.velocities[id]
}

world_set_health :: proc(w: ^World, id: int, c: HealthComp) {
    w.healths[id] = c
    entity_sig_set(&w.entities[id].signature, .Health)
}
world_get_health :: proc(w: ^World, id: int) -> ^HealthComp {
    return &w.healths[id]
}

world_set_input :: proc(w: ^World, id: int, c: InputStateComp) {
    w.inputs[id] = c
    entity_sig_set(&w.entities[id].signature, .InputState)
}
world_get_input :: proc(w: ^World, id: int) -> ^InputStateComp {
    return &w.inputs[id]
}

world_set_weapon :: proc(w: ^World, id: int, c: WeaponSlotComp) {
    w.weapons[id] = c
    entity_sig_set(&w.entities[id].signature, .WeaponSlot)
}
world_get_weapon :: proc(w: ^World, id: int) -> ^WeaponSlotComp {
    return &w.weapons[id]
}

world_set_mutation :: proc(w: ^World, id: int, c: MutationContainerComp) {
    w.mutations[id] = c
    entity_sig_set(&w.entities[id].signature, .MutationContainer)
}
world_get_mutation :: proc(w: ^World, id: int) -> ^MutationContainerComp {
    return &w.mutations[id]
}

world_set_flammable :: proc(w: ^World, id: int, c: FlammableComp) {
    w.flammbles[id] = c
    entity_sig_set(&w.entities[id].signature, .Flammable)
}

world_get_flammable :: proc(w: ^World, id: int) -> ^FlammableComp {
    return &w.flammbles[id]
}

world_set_extraction :: proc(w: ^World, id: int, c: ExtractionComp) {
    w.extractions[id] = c
    entity_sig_set(&w.entities[id].signature, .Extraction)
}
world_get_extraction :: proc(w: ^World, id: int) -> ^ExtractionComp {
    return &w.extractions[id]
}

world_set_mut :: proc(w: ^World, id: int, c: MutComp) {
    w.muts[id] = c
    entity_sig_set(&w.entities[id].signature, .Mut)
}
world_get_mut :: proc(w: ^World, id: int) -> ^MutComp {
    return &w.muts[id]
}

world_set_player :: proc(w: ^World, id: int, c: PlayerComp) {
    w.players[id] = c
    entity_sig_set(&w.entities[id].signature, .Player)
}
world_get_player :: proc(w: ^World, id: int) -> ^PlayerComp {
    return &w.players[id]
}

world_set_wallet :: proc(w: ^World, id: int, c: WalletComp) {
    w.wallets[id] = c
    entity_sig_set(&w.entities[id].signature, .Wallet)
}
world_get_wallet :: proc(w: ^World, id: int) -> ^WalletComp {
    return &w.wallets[id]
}

world_set_gold :: proc(w: ^World, id: int, c: GoldComp) {
    w.golds[id] = c
    entity_sig_set(&w.entities[id].signature, .Gold)
}
world_get_gold :: proc(w: ^World, id: int) -> ^GoldComp {
    return &w.golds[id]
}

world_set_npc :: proc(w: ^World, id: int, c: NPCComp) {
    w.npcs[id] = c
    entity_sig_set(&w.entities[id].signature, .NPC)
}
world_get_npc :: proc(w: ^World, id: int) -> ^NPCComp {
    return &w.npcs[id]
}

world_set_mut_damage_mult :: proc(w: ^World, id: int, c: MutDamageMultComp) {
    w.mut_damage_mults[id] = c
    entity_sig_set(&w.entities[id].signature, .MutDamageMult)
}
world_get_mut_damage_mult :: proc(w: ^World, id: int) -> ^MutDamageMultComp {
    return &w.mut_damage_mults[id]
}

world_set_mut_lock_hp_to_one :: proc(w: ^World, id: int) {
    w.mut_lock_hp_to_one[id] = {}
    entity_sig_set(&w.entities[id].signature, .MutLockHpToOne)
}

world_set_mut_root_on_fire :: proc(w: ^World, id: int, c: MutRootOnFireComp) {
    w.mut_root_on_fire[id] = c
    entity_sig_set(&w.entities[id].signature, .MutRootOnFire)
}
world_get_mut_root_on_fire :: proc(w: ^World, id: int) -> ^MutRootOnFireComp {
    return &w.mut_root_on_fire[id]
}

world_set_mut_timed_self_damage :: proc(w: ^World, id: int, c: MutTimedSelfDamageComp) {
    w.mut_timed_self_dmg[id] = c
    entity_sig_set(&w.entities[id].signature, .MutTimedSelfDamage)
}
world_get_mut_timed_self_damage :: proc(w: ^World, id: int) -> ^MutTimedSelfDamageComp {
    return &w.mut_timed_self_dmg[id]
}

world_set_mut_block_healing :: proc(w: ^World, id: int) {
    w.mut_block_healing[id] = {}
    entity_sig_set(&w.entities[id].signature, .MutBlockHealing)
}

world_set_mut_move_speed_mult :: proc(w: ^World, id: int, c: MutMoveSpeedMultComp) {
    w.mut_move_speed[id] = c
    entity_sig_set(&w.entities[id].signature, .MutMoveSpeedMult)
}
world_get_mut_move_speed_mult :: proc(w: ^World, id: int) -> ^MutMoveSpeedMultComp {
    return &w.mut_move_speed[id]
}

world_set_mut_block_ranged :: proc(w: ^World, id: int) {
    w.mut_block_ranged[id] = {}
    entity_sig_set(&w.entities[id].signature, .MutBlockRanged)
}

world_set_mut_block_pickup_heal :: proc(w: ^World, id: int) {
    w.mut_block_pickup_heal[id] = {}
    entity_sig_set(&w.entities[id].signature, .MutBlockPickupHeal)
}

world_set_mut_serum_gain_mult :: proc(w: ^World, id: int, c: MutSerumGainMultComp) {
    w.mut_serum_gain[id] = c
    entity_sig_set(&w.entities[id].signature, .MutSerumGainMult)
}
world_get_mut_serum_gain_mult :: proc(w: ^World, id: int) -> ^MutSerumGainMultComp {
    return &w.mut_serum_gain[id]
}

world_set_mut_block_pickups :: proc(w: ^World, id: int) {
    w.mut_block_pickups[id] = {}
    entity_sig_set(&w.entities[id].signature, .MutBlockPickups)
}

world_set_mut_nonlethal_shots :: proc(w: ^World, id: int) {
    w.mut_nonlethal[id] = {}
    entity_sig_set(&w.entities[id].signature, .MutNonlethalShots)
}

world_set_mut_disable_actives :: proc(w: ^World, id: int) {
    w.mut_disable_actives[id] = {}
    entity_sig_set(&w.entities[id].signature, .MutDisableActives)
}

world_set_mut_early_death_threshold :: proc(w: ^World, id: int, c: MutEarlyDeathThresholdComp) {
    w.mut_early_death[id] = c
    entity_sig_set(&w.entities[id].signature, .MutEarlyDeathThreshold)
}
world_get_mut_early_death_threshold :: proc(w: ^World, id: int) -> ^MutEarlyDeathThresholdComp {
    return &w.mut_early_death[id]
}

world_set_mut_missing_health_damage :: proc(w: ^World, id: int, c: MutMissingHealthDamageComp) {
    w.mut_missing_hp_dmg[id] = c
    entity_sig_set(&w.entities[id].signature, .MutMissingHealthDamage)
}
world_get_mut_missing_health_damage :: proc(w: ^World, id: int) -> ^MutMissingHealthDamageComp {
    return &w.mut_missing_hp_dmg[id]
}

world_set_mut_passive_power :: proc(w: ^World, id: int, c: MutPassivePowerComp) {
    w.mut_passive_power[id] = c
    entity_sig_set(&w.entities[id].signature, .MutPassivePower)
}
world_get_mut_passive_power :: proc(w: ^World, id: int) -> ^MutPassivePowerComp {
    return &w.mut_passive_power[id]
}

world_set_mut_kill_heal :: proc(w: ^World, id: int, c: MutKillHealComp) {
    w.mut_kill_heal[id] = c
    entity_sig_set(&w.entities[id].signature, .MutKillHeal)
}
world_get_mut_kill_heal :: proc(w: ^World, id: int) -> ^MutKillHealComp {
    return &w.mut_kill_heal[id]
}

world_set_mut_lifesteal :: proc(w: ^World, id: int, c: MutLifestealComp) {
    w.mut_lifesteal[id] = c
    entity_sig_set(&w.entities[id].signature, .MutLifesteal)
}
world_get_mut_lifesteal :: proc(w: ^World, id: int) -> ^MutLifestealComp {
    return &w.mut_lifesteal[id]
}

world_set_mut_proximity_damage :: proc(w: ^World, id: int, c: MutProximityDamageComp) {
    w.mut_proximity_damage[id] = c
    entity_sig_set(&w.entities[id].signature, .MutProximityDamage)
}
world_get_mut_proximity_damage :: proc(w: ^World, id: int) -> ^MutProximityDamageComp {
    return &w.mut_proximity_damage[id]
}

world_set_mut_on_death_explode :: proc(w: ^World, id: int, c: MutOnDeathExplodeComp) {
    w.mut_on_death_explode[id] = c
    entity_sig_set(&w.entities[id].signature, .MutOnDeathExplode)
}
world_get_mut_on_death_explode :: proc(w: ^World, id: int) -> ^MutOnDeathExplodeComp {
    return &w.mut_on_death_explode[id]
}

world_set_mut_stationary_shield :: proc(w: ^World, id: int, c: MutStationaryShieldComp) {
    w.mut_stationary_shield[id] = c
    entity_sig_set(&w.entities[id].signature, .MutStationaryShield)
}
world_get_mut_stationary_shield :: proc(w: ^World, id: int) -> ^MutStationaryShieldComp {
    return &w.mut_stationary_shield[id]
}

world_set_mut_extra_dodge_charges :: proc(w: ^World, id: int, c: MutExtraDodgeChargesComp) {
    w.mut_extra_dodges[id] = c
    entity_sig_set(&w.entities[id].signature, .MutExtraDodgeCharges)
}
world_get_mut_extra_dodge_charges :: proc(w: ^World, id: int) -> ^MutExtraDodgeChargesComp {
    return &w.mut_extra_dodges[id]
}

world_set_mut_damage_taken_mult :: proc(w: ^World, id: int, c: MutDamageTakenMultComp) {
    w.mut_dmg_taken_mult[id] = c
    entity_sig_set(&w.entities[id].signature, .MutDamageTakenMult)
}
world_get_mut_damage_taken_mult :: proc(w: ^World, id: int) -> ^MutDamageTakenMultComp {
    return &w.mut_dmg_taken_mult[id]
}

world_set_mut_wall_phase :: proc(w: ^World, id: int) {
    w.mut_wall_phase[id] = {}
    entity_sig_set(&w.entities[id].signature, .MutWallPhase)
}

world_set_mut_body_melee :: proc(w: ^World, id: int, c: MutBodyMeleeComp) {
    w.mut_body_melee[id] = c
    entity_sig_set(&w.entities[id].signature, .MutBodyMelee)
}
world_get_mut_body_melee :: proc(w: ^World, id: int) -> ^MutBodyMeleeComp {
    return &w.mut_body_melee[id]
}

world_set_mut_corpse_trigger :: proc(w: ^World, id: int, c: MutCorpseTriggerComp) {
    w.mut_corpse_trigger[id] = c
    entity_sig_set(&w.entities[id].signature, .MutCorpseTrigger)
}
world_get_mut_corpse_trigger :: proc(w: ^World, id: int) -> ^MutCorpseTriggerComp {
    return &w.mut_corpse_trigger[id]
}

world_set_mut_hide_enemy_sprites :: proc(w: ^World, id: int) {
    w.mut_hide_enemy_sprites[id] = {}
    entity_sig_set(&w.entities[id].signature, .MutHideEnemySprites)
}

world_set_mut_unseen_damage_mult :: proc(w: ^World, id: int, c: MutUnseenDamageMultComp) {
    w.mut_unseen_dmg_mult[id] = c
    entity_sig_set(&w.entities[id].signature, .MutUnseenDamageMult)
}
world_get_mut_unseen_damage_mult :: proc(w: ^World, id: int) -> ^MutUnseenDamageMultComp {
    return &w.mut_unseen_dmg_mult[id]
}

world_set_mut_heart_cage :: proc(w: ^World, id: int, c: MutHeartCageComp) {
    w.mut_heart_cage[id] = c
    entity_sig_set(&w.entities[id].signature, .MutHeartCage)
}
world_get_mut_heart_cage :: proc(w: ^World, id: int) -> ^MutHeartCageComp {
    return &w.mut_heart_cage[id]
}

world_set_mut_thorn_pact :: proc(w: ^World, id: int, c: MutThornPactComp) {
    w.mut_thorn_pact[id] = c
    entity_sig_set(&w.entities[id].signature, .MutThornPact)
}
world_get_mut_thorn_pact :: proc(w: ^World, id: int) -> ^MutThornPactComp {
    return &w.mut_thorn_pact[id]
}

world_set_mut_carrion_crown :: proc(w: ^World, id: int, c: MutCarrionCrownComp) {
    w.mut_carrion_crown[id] = c
    entity_sig_set(&w.entities[id].signature, .MutCarrionCrown)
}
world_get_mut_carrion_crown :: proc(w: ^World, id: int) -> ^MutCarrionCrownComp {
    return &w.mut_carrion_crown[id]
}

world_set_mut_false_saint :: proc(w: ^World, id: int, c: MutFalseSaintComp) {
    w.mut_false_saint[id] = c
    entity_sig_set(&w.entities[id].signature, .MutFalseSaint)
}
world_get_mut_false_saint :: proc(w: ^World, id: int) -> ^MutFalseSaintComp {
    return &w.mut_false_saint[id]
}

world_set_mut_black_lung :: proc(w: ^World, id: int, c: MutBlackLungComp) {
    w.mut_black_lung[id] = c
    entity_sig_set(&w.entities[id].signature, .MutBlackLung)
}
world_get_mut_black_lung :: proc(w: ^World, id: int) -> ^MutBlackLungComp {
    return &w.mut_black_lung[id]
}


world_set_reanimated :: proc(w: ^World, id: int, c: ReanimatedComp) {
    w.reanimateds[id] = c
    entity_sig_set(&w.entities[id].signature, .Reanimated)
}
world_get_reanimated :: proc(w: ^World, id: int) -> ^ReanimatedComp {
    return &w.reanimateds[id]
}

world_set_point_light :: proc(w: ^World, id: int, c: PointLightComp) {
    w.point_lights[id] = c
    entity_sig_set(&w.entities[id].signature, .PointLight)
}
world_get_point_light :: proc(w: ^World, id: int) -> ^PointLightComp {
    return &w.point_lights[id]
}

world_set_anim_state :: proc(w: ^World, id: int, c: AnimStateComp) {
    w.anim_states[id] = c
    entity_sig_set(&w.entities[id].signature, .AnimState)
}
world_get_anim_state :: proc(w: ^World, id: int) -> ^AnimStateComp {
    return &w.anim_states[id]
}

world_set_collider :: proc(w: ^World, id: int, c: ColliderComp) {
    w.colliders[id] = c
    entity_sig_set(&w.entities[id].signature, .Collider)
}
world_get_collider :: proc(w: ^World, id: int) -> ^ColliderComp {
    return &w.colliders[id]
}

world_set_projectile :: proc(w: ^World, id: int, c: ProjectileComp) {
    w.projectiles[id] = c
    entity_sig_set(&w.entities[id].signature, .Projectile)
}

world_set_self_destruct :: proc(w: ^World, id: int, c: SelfDestructComp) {
    w.self_destructs[id] = c
    entity_sig_set(&w.entities[id].signature, .SelfDestruct)
}

world_set_ai :: proc(w: ^World, id: int, c: AIAgentComp) {
    w.ai_agents[id] = c
    entity_sig_set(&w.entities[id].signature, .AIAgent)
}
world_get_ai :: proc(w: ^World, id: int) -> ^AIAgentComp {
    return &w.ai_agents[id]
}

world_get_self_destruct :: proc(w: ^World, id: int) -> ^SelfDestructComp {
    return &w.self_destructs[id]
}

world_set_melee_arc :: proc(w: ^World, id: int, c: MeleeArcComp) {
    w.melee_arcs[id] = c
    entity_sig_set(&w.entities[id].signature, .MeleeArc)
}
world_get_melee_arc :: proc(w: ^World, id: int) -> ^MeleeArcComp {
    return &w.melee_arcs[id]
}

world_set_respawn :: proc(w: ^World, id: int, c: RespawnComp) {
    w.respawns[id] = c
    entity_sig_set(&w.entities[id].signature, .Respawn)
}
world_get_respawn :: proc(w: ^World, id: int) -> ^RespawnComp {
    return &w.respawns[id]
}

world_set_inventory :: proc(w: ^World, id: int, c: InventoryComp) {
    w.inventories[id] = c
    entity_sig_set(&w.entities[id].signature, .Inventory)
}
world_get_inventory :: proc(w: ^World, id: int) -> ^InventoryComp {
    return &w.inventories[id]
}

world_set_item :: proc(w: ^World, id: int, c: ItemComp) {
    w.items[id] = c
    entity_sig_set(&w.entities[id].signature, .Item)
}
world_get_item :: proc(w: ^World, id: int) -> ^ItemComp {
    return &w.items[id]
}

world_set_ground_item :: proc(w: ^World, id: int) {
    w.ground_items[id] = {}
    entity_sig_set(&w.entities[id].signature, .GroundItem)
}

world_clear_ground_item :: proc(w: ^World, id: int) {
    entity_sig_clear(&w.entities[id].signature, .GroundItem)
}

world_get_projectile :: proc(w: ^World, id: int) -> ^ProjectileComp {
    return &w.projectiles[id]
}

world_push_damage :: proc(w: ^World, target_id: int, amount: f32, source_id: int = 0) {
    append(&w.damage_events, DamageEvent{ target_id = target_id, amount = amount, source_id = source_id })
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
    w.projectile_tags[id] = {}
    entity_sig_set(&w.entities[id].signature, .ProjectileTag)
}

world_set_fog_of_war :: proc(w: ^World, id: int) {
    w.fog_of_wars[id] = {}
    entity_sig_set(&w.entities[id].signature, .FogOfWar)
}

world_set_weapon_data :: proc(w: ^World, id: int, c: WeaponComp) {
    w.weapon_data[id] = c
    entity_sig_set(&w.entities[id].signature, .Weapon)
}
world_get_weapon_data :: proc(w: ^World, id: int) -> ^WeaponComp {
    return &w.weapon_data[id]
}

world_set_equipment :: proc(w: ^World, id: int, c: EquipmentComp) {
    w.equipment[id] = c
    entity_sig_set(&w.entities[id].signature, .Equipment)
}
world_get_equipment :: proc(w: ^World, id: int) -> ^EquipmentComp {
    return &w.equipment[id]
}

world_set_dodge :: proc(w: ^World, id: int, c: DodgeComp) {
    w.dodge_states[id] = c
    entity_sig_set(&w.entities[id].signature, .DodgeState)
}
world_get_dodge :: proc(w: ^World, id: int) -> ^DodgeComp {
    return &w.dodge_states[id]
}

world_set_render_config :: proc(w: ^World, id: int, c: RenderConfigComp) {
    w.render_configs[id] = c
    entity_sig_set(&w.entities[id].signature, .RenderConfig)
}
world_get_render_config :: proc(w: ^World, id: int) -> ^RenderConfigComp {
    return &w.render_configs[id]
}

world_set_status_effect :: proc(w: ^World, id: int, c: StatusEffectComp) {
    w.status_effects[id] = c
    entity_sig_set(&w.entities[id].signature, .StatusEffect)
}

world_get_status_effects :: proc(w: ^World, id: int) -> ^StatusEffectComp {
    return &w.status_effects[id]
}

status_effect_apply :: proc(w: ^World, id: int, effect: StatusEffect) {
    // Wet blocks Burn and Oiled from being applied.
    if effect.type == .Burn || effect.type == .Oiled {
        if world_has_component(w, id, .StatusEffect) {
            sec_chk := world_get_status_effects(w, id)
            if status_effect_is_active(sec_chk, .Wet) { return }
        }
    }

    if !world_has_component(w, id, .StatusEffect) {
        world_set_status_effect(w, id, StatusEffectComp{})
    }

    sec := world_get_status_effects(w, id)
    et := int(effect.type)
    current := &sec.effects[et]
    
    if current.duration <= 0 {
        // No active effect, apply new one
        current^ = effect
        sec.count += 1
    } else {
        // Effect already active, apply stacking policy
        #partial switch effect.application {
        case .Flat:
            current.strength += effect.strength
        case .Base:
            current.strength *= effect.strength
        case .Percent:
            current.strength += effect.strength
        }
        
        #partial switch effect.stack_behavior {
        case .Stack:
            // Already added strength above
            current.duration = max(current.duration, effect.duration)
        case .Refresh:
            current.duration = effect.duration
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
    hp_regen_pct:               f32,   // fraction of max HP regenerated per second (from affixes)
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

    // Ranged-weapon affix stats (computed each frame from equipped item affixes)
    bonus_ammo_pct:  f32,  // fractional bonus to ammo_max (0.20 = +20%)
    bonus_pierce:    int,  // extra enemies each projectile passes through

    // Melee-weapon affix stats (computed each frame from equipped item affixes)
    melee_damage_mult: f32,  // multiplicative bonus on top of damage_mult
    melee_range_mult:  f32,  // scales arc radius
    melee_speed_mult:  f32,  // divides cooldown_max (higher = faster swings)

    // Shield resource (computed each frame from equipped items' base_shield)
    shield_max: f32,  // max shield HP; 0 when no shield items equipped
}

world_set_ability :: proc(w: ^World, id: int, c: AbilityComp) {
    w.abilities[id] = c
    entity_sig_set(&w.entities[id].signature, .Ability)
}
world_get_ability :: proc(w: ^World, id: int) -> ^AbilityComp {
    return &w.abilities[id]
}

world_set_stats :: proc(w: ^World, id: int, c: StatsComp) {
    w.stats[id] = c
    entity_sig_set(&w.entities[id].signature, .Stats)
}
world_get_stats :: proc(w: ^World, id: int) -> ^StatsComp {
    return &w.stats[id]
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

world_query :: proc(w: ^World, mask: ComponentSignature, allocator := context.allocator) -> []int {
    results := make([dynamic]int, allocator)
    for i in 0..<len(w.entities) {
        e := w.entities[i]
        if !entity_is_active(e) { continue }
        if (e.signature & mask) == mask {
            append(&results, e.id)
        }
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
        p := &w.projectiles[id]

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
        sd := &w.self_destructs[id]
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
