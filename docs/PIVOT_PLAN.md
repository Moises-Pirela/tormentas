# Pivot Plan — Sandbox MMO-ARPG (experimental)

> **Status:** experiment. This is the working design for the pivot. It does **not** replace
> `ROADMAP.md` yet, which still describes the current co-op game. Every item is tagged:
> **[D]** decided by you · **[P]** proposed, needs your sign-off · **[?]** open question.

---

## 1. Vision in one paragraph

A classless, use-based-skill sandbox ARPG. Players share a **persistent overworld** (2,000 per
shard) that was generated once, then saved and hand-edited. They gather, craft, fight, and trade
through **one global exchange**. Combat content lives in **instanced, procedurally generated
dungeons (party) and raids (10 players)**, entered with craftable or purchasable keys. Those
instances drop the materials and recipes that feed crafting. Rendering is **3D models on a 2D grid**,
top-down, with a **free-rotating camera**, on **sokol-gfx**.

## 2. Decisions locked

| Area | Decision |
|---|---|
| World | **[D]** Shared overworld, generated once from a seed with landmarks, saved, editable |
| World | **[D]** Overworld v1 content: mobs + resource spawns only |
| World | **[D]** PvP is OSRS-style: one designated high-loot PvP zone, safe elsewhere |
| World | **[D]** PvP death: the killer takes the items (keepsake excepted) |
| Scale | **[D]** 2,000 players per shard |
| Instances | **[D]** Dungeons and raids are instanced + procgen (D2-style maze, chunk-based) |
| Instances | **[D]** Raids are 10 players to start |
| Instances | **[D]** Keys are items, craftable or purchasable, and need materials to craft |
| Rendering | **[D]** 2D grid terrain, 3D models, free camera rotation |
| Rendering | **[D]** sokol-gfx; raylib removed |
| Rendering | **[D]** Metal (macOS) + D3D11 (Windows), shaders via sokol-shdc |
| Rendering | **[D]** Perspective camera, narrow FOV |
| Rendering | **[D]** Window modes: resizable window + borderless fullscreen |
| Art | **[D]** No art capacity yet: primitives through P1b, glTF/skinning deferred |
| Art | **[D]** Most 2D art is replaced over time |
| Tools | **[D]** New editor |
| Skills | **[D]** Use-based, classless, **cap 100** |
| Skills | **[D]** Every 10 levels is a significant milestone |
| Skills | **[D]** ~50 hours to max each skill; **quadratic** curve |
| Skills | **[D]** Gathering and crafting skills are distinct categories |
| Skills | **[D]** XP from combat, from using skills, and from quests |
| Progression | **[D]** Horizontal, always |
| Progression | **[D]** Specialization comes from time, not from locks; completionists get extra rewards |
| Mutations | **[D]** Folded into skills (alchemy and/or medicine, plus a combat skill) — **needs its own design pass** |
| Items | **[D]** Gear comes from monsters and players; higher tiers salvage into materials |
| Items | **[D]** Materials and some gear can be salvaged or sold as-is |
| Items | **[D]** Affix system becomes enchanting/engineering skills; players can sell these as services |
| Items | **[D]** Equipment must be repaired |
| Recipes | **[D]** Sources: known, found in dungeons/raids, or purchased |
| Death | **[D]** Keepsake is **one slot**; everything else is lost, equipped gear included |
| Death | **[D]** Corpse run to retrieve (outside PvP) |
| Death | **[D]** Dying in an instance: the corpse goes to the dungeon's overworld entrance; the player can re-enter |
| Economy | **[D]** One global exchange, with fees on selling |
| Economy | **[D]** Money comes from buying/selling; some quests give gold and skill XP |
| Economy | **[D]** Individual NPCs buy items, each with its own internal supply and demand (§5.8) |
| Death | **[D]** Carried gold is lost on death; gold in the bank is safe |
| Death | **[D]** Keepsake can be set anywhere, but not changed mid-fight |
| Skills | **[D]** Total XP is quadratic; XP rates differ per skill and per training method |
| Skills | **[D]** Skills that pay more along the way take longer to max (§5.3) |
| Economy | **[D]** NPCs sell basic supplies for skills; trade merchants + some general merchants |
| Death | **[D]** A corpse lasts 1 hour: owner-only, then public, then it feeds the reserve |
| Economy | **[D]** The exchange reserve exists, and its listings are visibly marked under a thematic name (§5.7.1) |
| Items | **[D]** At 0 durability items stop working; repaired by a player smith/engineer or an NPC |
| Anti-bot | **[D]** Deferred |

The PvP high-loot zone takes over the "danger zone" role the storm was evolving into
(see `ROADMAP.md` pillar #1).

---

## 3. What happens to the current codebase

### Survives (the valuable part)
- **clockwork ECS** and the entity-def + override model (`entities.json`, `LevelEntity`).
- **Simulation systems.** AI, damage, weapons, abilities, status effects, projectiles, A\*
  pathfinding. They import no raylib, and they already work on `[3]f32` positions over a 2D tile grid.
- **Host-authoritative netcode model.** Host sim + snapshots + client prediction/reconcile
  (`netcode.odin`). The "host" becomes the dedicated server.
- **Procgen maze design** from the earlier back-and-forth (BiomeDef → ChunkDef → LevelPlan → stamp → populate).
- Loot rolling, seeded RNG conventions, localization, the dev console concept.

### Replaced
| Today | Becomes |
|---|---|
| raylib (window, input, 2D draw, textures, audio, fonts) | sokol_app + sokol_gfx + own 2D batcher + miniaudio + fontstash/stb_truetype |
| Isometric projection + sprite sheets + facing flip | 3D camera, glTF models (cgltf), skeletal animation |
| Steam P2P sockets | Client→server UDP (ENet proposed). Steam kept for identity/auth only |
| Local `save/*.bin` | Server-owned database |
| `SavedItem` (every base stat, name, icon and description inline) | `ItemDef` (data) + `ItemInstance` (id + variance only) |
| Random affixes rolled on drops | Enchantments applied by enchanting/engineering skills |
| 4 classes locked to weapon archetypes | Classless. The weapon archetype becomes a combat skill |
| Mutation tree | Skill content (design pass pending) |
| Level editor | New editor (3D viewport, overworld + chunk modes) |
| O(n²) separation/collision (`separation_system.odin`) | Spatial hash. **Mandatory** at 2,000 players |

### Deleted
- Raid timer, `RAID_TIME`, dungeon clock, timer-scheduled boss spawns.
- Spawn director's time-pressure model. Replaced by overworld spawners + instance populate pass.
- Hub as a separate mode. Hubs become cities in the overworld.
- Extraction value, level select, class select.

---

## 4. Architecture

### 4.1 Processes

```
                 ┌──────────────────────────────┐
  clients ──UDP──►  WORLD process (1 per shard) │  overworld sim, 20 Hz, AoI replication
     │           └──────────────┬───────────────┘
     │                          │ char handoff (lease)
     │           ┌──────────────▼───────────────┐
     └──UDP─────►  INSTANCE processes (N)       │  dungeon / raid sim, 30–60 Hz, ≤10 players
                 └──────────────┬───────────────┘
                                │
                 ┌──────────────▼───────────────┐
                 │  BACKEND (accounts, chars,   │  sole owner of the DB; mints ItemIds;
                 │  items, exchange, corpses)   │  runs exchange matching
                 └──────────────────────────────┘
```

- **[P] One OS process per instance.** The game relies on globals (`g_tilemap`, `g_level_data`,
  `g_director`…). Separate processes keep that valid with no refactor. Instances are cheap
  to spawn and to kill.
- **[P] The overworld is one process per shard**, with a single-threaded sim. Replication
  encoding is parallelized per client, because at 2k players that is where the CPU goes.
- **[P] For the experiment, the backend can live inside the world process** behind an interface.
  Split it out once instances exist.

### 4.2 Anti-dupe invariants (non-negotiable once items have value)
1. **Only the backend mints `ItemId`s.** Clients never create items.
2. **One owner per character.** A character is owned by exactly one process at a time
   (`CharacterLease` with an epoch). The backend rejects writes that carry a stale epoch. Moving
   from overworld → instance is lease release → lease acquire, never two live copies.
3. **Every inventory mutation happens on the server.** The client only *requests*.
4. **The exchange uses escrow.** A listed item or gold leaves the inventory when the order is placed,
   not when it fills.

### 4.3 Code layout (prerequisite refactor)

Today all 93 files are `package main`, so there's no way to build a headless server.

```
src/
  sim/        components, systems, items, ai, damage, skills, recipes  (NO gfx imports)
  world/      tilemap, procgen, overworld regions, spatial hash         (NO gfx imports)
  net/        protocol, replication, transport (ENet)
  backend/    db, characters, items, exchange, corpses
  client/     main, gfx (sokol), ui (Clay backend), audio, input, camera
  server/     main_world, main_instance
  editor/     main, overworld mode, chunk mode
```

**[P] Rule:** if `sim/` or `world/` imports `client/`, the build fails. Enforce this with a
headless server build in `test.sh`.

### 4.4 Tick rates
- **[P] Overworld: 20 Hz.** Instances: **30 Hz** to start (60 is affordable at ≤10 players if feel demands).
- Systems already take `dt`, but `TUNING.md` was tuned at 60 Hz. Expect re-tuning around
  cooldowns, projectiles and the melee arc.

### 4.5 Replication budget (why AoI + quantization are mandatory)

| | per entity | rate | visible | per client | ×2,000 |
|---|---|---|---|---|---|
| Today's format | 40 B | 60 Hz | 150 | 360 KB/s | **720 MB/s** ✗ |
| Target | ~14 B quantized, delta | 20 Hz | 150, ~50% changed | ~21 KB/s | **~42 MB/s** ✓ |

- **[P] AoI grid:** 16×16-tile cells. Each client subscribes to cells within its view radius. Entities
  are prioritized by distance, with far players degraded to position-only at a lower rate.
- **[P] Crowd cap.** In a 300-player city, show the nearest N fully and the rest as nameplates or
  not at all. This is a design rule, not just an optimization.

---

## 5. Data structures

### 5.1 Identity
```odin
AccountId :: distinct u64
CharId    :: distinct u64
ItemId    :: distinct u64     // minted by backend only
ItemDefId :: distinct u32     // stable, data-driven
```

### 5.2 Items — definition vs instance
```odin
ItemKind :: enum u8 { Material, Gear, Consumable, Key, Recipe, Tool }
ItemFlag :: enum u8 { Keepsake, Bound, Crafted, Damaged }

ItemDef :: struct {                 // data/items/*.json — shipped with client + server
    id:             ItemDefId,
    kind:           ItemKind,
    tier:           u8,
    stack_max:      u32,            // 1 for gear
    equip_slot:     EquipSlot,
    gear:           GearBase,       // what SavedItem inlines today (damage, rate, armor…)
    max_durability: u16,
    salvage:        SalvageTableId, // → materials
    vendor_value:   u32,
    model:          ModelId,
    name, desc:     LocKey,
}

ItemInstance :: struct {            // what the DB stores — small
    id:         ItemId,
    def:        ItemDefId,
    qty:        u32,
    durability: u16,
    quality:    u8,
    enchants:   [MAX_ENCHANTS]Enchant,   // the old affixes, now player-applied
    crafted_by: CharId,
    flags:      bit_set[ItemFlag],
}

Enchant :: struct { kind: EnchantKind, value: f32, applied_by: CharId }
```

#### 5.2.1 Durability and repair

**[D] At 0 durability an item stops working — it is not destroyed.** It must be repaired by a
player smith/engineer or by an NPC.

```odin
RepairKind :: enum u8 { Npc, PlayerService }

// NPC repair:    gold cost, always available, shaves max_durability
// Player repair: materials + whatever fee the players agree, restores fully
repair_cost_gold :: proc(it: ItemInstance, def: ItemDef) -> u64
```

**[P] The two repairs are deliberately different, so player smiths have a business:**

| | NPC repair | Player repair (Smithing / Engineering) |
|---|---|---|
| Cost | gold (a **sink**) | materials (an **item sink**) + a fee to the crafter (a transfer) |
| Availability | any city, instant | needs a player with the skill |
| Catch | **permanently shaves a little off `max_durability`** | restores fully, no loss |

The NPC is the convenient option that slowly wears gear out, which keeps a long-run item sink
alive even though breaking no longer destroys items. The player smith is the better option, which
is exactly the service economy you asked for. Repairs grant the repairer XP, so repair work is
itself a training method (§5.3.1).

### 5.3 Skills
```odin
SkillCategory :: enum u8 { Combat, Gathering, Crafting, Support }
SKILL_LEVEL_CAP     :: 100
SKILL_MILESTONE_GAP :: 10
SKILL_XP_K          :: 100       // tuning knob: total XP scale

SkillDef :: struct {
    id:       SkillId,
    category: SkillCategory,
    name:     LocKey,
    unlocks:  []SkillUnlock,     // level → recipe / node / ability / passive
}

CharSkills :: struct { xp: [SkillId]u32 }   // level derived, never stored

XpSource :: enum u8 { Combat, Gather, Craft, Quest, Salvage }
skill_grant_xp :: proc(c: ^CharSkills, s: SkillId, amount: u32, src: XpSource)

// total XP needed to *reach* level L (L=1 → 0)
skill_xp_to_reach :: proc(L: int) -> u32 { return u32(SKILL_XP_K * (L-1) * (L-1)) }
// level from XP: closed form, no table needed
skill_level :: proc(xp: u32) -> int {
    return min(1 + int(math.sqrt(f64(xp) / SKILL_XP_K)), SKILL_LEVEL_CAP)
}
```

**[D] Quadratic curve.** Total XP to reach level L is `100·(L−1)²`. Level 100 = **980,100 XP**,
which fits easily in `u32`. The XP to go up one level grows linearly, from 100 XP (1→2) to
19,700 XP (99→100).

**[D] The curve is the same for every skill; XP *rates* are not.** How fast you level depends
on the training method you pick (§5.3.1). The curve fixes how much XP each milestone costs.
The content decides how many hours that is.

**Reference rate.** As a yardstick, 50 hours to max means averaging **~19,600 XP/hour**. At that
constant rate, the milestones land like this:

| Milestone | Total XP | Hours to reach | Hours in this band |
|---|---|---|---|
| 10 | 8,100 | 0.4 | 0.4 |
| 20 | 36,100 | 1.8 | 1.4 |
| 30 | 84,100 | 4.3 | 2.5 |
| 40 | 152,100 | 7.8 | 3.5 |
| 50 | 240,100 | 12.3 | 4.5 |
| 60 | 348,100 | 17.8 | 5.5 |
| 70 | 476,100 | 24.3 | 6.5 |
| 80 | 624,100 | 31.8 | 7.6 |
| 90 | 792,100 | 40.4 | 8.6 |
| 100 | 980,100 | 50.0 | 9.6 |

At the reference rate, each band takes ~1 hour longer than the one before. The first milestone
arrives in ~25 minutes, which is good onboarding. Half the time is spent getting from 70 to 100.
Real times per skill and per player will differ, because methods differ.

**[D] Skills that pay more take longer to max.** Every skill pays you back in two
currencies: **levels** and **gold**. A skill that makes good money along the way is slower to
level. A skill that costs gold to train (most crafting) is faster. That keeps an hour of play
roughly equally valuable whatever you choose, so nobody is *forced* into the money skill.

**[P] Pacing profiles.** Each `SkillDef` declares one, and the training-method report enforces it:

| Profile | Net gold while training | Target hours to max (fastest path) | Typical skills |
|---|---|---|---|
| **Spender** | costs gold | ~35 h | most crafting (Smithing, Tailoring, Enchanting) |
| **Neutral** | ≈ break-even | ~50 h | combat skills, Salvaging |
| **Earner** | earns gold | ~70 h | most gathering (Mining, Harvesting) |
| **High earner** | earns a lot | ~90 h | rare-resource gathering, top-tier trade crafts |

The numbers are tuning knobs. The **ordering** is the rule: a skill that earns more per hour
must take longer to max.

```odin
SkillPacing :: enum u8 { Spender, Neutral, Earner, HighEarner }
// SkillDef gains: pacing: SkillPacing, target_hours: f32
```

**Completionist scale.** With the ~19 skills in the draft list below and a mix of profiles,
maxing everything is roughly **1,000 hours**. That's the horizon the completionist rewards are
aimed at.

#### 5.3.1 Training methods

Every XP source is a **training method**: a resource node, a recipe, a mob, a salvage action, or a
quest. Methods compete on three axes, OSRS-style:

| Axis | Example trade-off |
|---|---|
| **XP/hour** | the fastest methods are usually expensive or demanding |
| **Gold/hour** | gathering tends to *earn* gold; crafting tends to *cost* gold (materials) |
| **Attention** | active (clicky, fast) vs. AFK (slow, relaxing) |

This axis split is what ties skills to the economy. **Training crafting skills consumes
materials, and that consumption is the demand for gatherers' output.** Gatherers earn gold
selling to crafters (via the exchange) and NPCs. Crafters spend gold on XP and earn some of it
back selling products. Specialization then has an economic reason, not just a time reason.

```odin
Attention :: enum u8 { Active, Moderate, AFK }

TrainingMethod :: struct {     // derived view over nodes / recipes / mobs — not stored
    skill:         SkillId,
    level_req:     u16,
    source:        XpSource,
    ref:           u32,          // NodeDefId / RecipeId / mob def
    xp_per_action: u32,
    action_secs:   f32,          // for mobs: est. time-to-kill at the tier's reference gear
    inputs:        []ItemStack,  // consumed per action
    outputs:       []ItemStack,  // produced per action
    attention:     Attention,
}
// derived: xp_per_hour, gold_per_hour (inputs/outputs priced at NPC base_price)
```

**[P] Training-method report (headless tool, runs in `test.sh`).** It reads all content data and,
for each skill, prints:
- hours to 100 on the **fastest** path (best XP/h method available at each level)
- hours and **total gold cost/profit** on the cheapest and the most profitable paths
- **dominated methods:** any method beaten by another on *all three* axes at the same level.
  That's dead content, or a balance bug.
- **gaps:** level bands where a skill has no method, or only one
- **pacing check:** each skill's fastest-path hours are within ±15% of its profile's target
- **ordering check:** across all skills, ranking by average gold/h must match ranking by hours to max.
  A high earner that maxes fast is a **failure**, because it makes every other skill a bad choice

It makes the pacing profiles checked numbers instead of hopes. Balance changes stop being
guesswork.

**Quest XP behaves well on this curve without special-casing.** A fixed reward of, say, 5,000 XP
is >half of level 10 but only ~25% of one level at 99. Quests accelerate early levels and
become a minor bonus late.

**[P] Milestones = tiers.** Each 10-level milestone unlocks the next **material / gear / key
tier**: T1 at level 1, T2 at 10, T3 at 20, …, T10 at 90. Level 100 is **mastery** (cosmetic +
convenience). This gives every gathering, crafting and combat skill the same
10-step ladder, and it gives dungeon/raid keys a natural tier → required-level mapping.

**[P] Horizontal power with 100 levels.** Levels unlock *breadth*: tiers, recipes, nodes,
abilities, efficiency (speed, yield, material cost). Raw combat stats come mostly from gear,
with a small, **capped** per-level bonus. Max level means "can do more things, more
efficiently," not "one-shots everyone."

**[P] Draft skill list.** Names are placeholders for setting-appropriate ones.

| Combat | Gathering | Crafting | Support |
|---|---|---|---|
| one per weapon archetype (4 today) | Mining | Smithing / Gunsmithing | Repair |
| Defense / Toughness | Scavenging (ruins, containers) | Tailoring / Armorcraft | Keymaking (keys) |
| Mutagenics (mutation combat) ‡ | Harvesting (plants, fungi) | Alchemy ‡ | |
| | Butchery (mob parts) | Medicine ‡ | |
| | Salvaging (break down gear) | Enchanting | |
| | | Engineering | |

‡ = touched by the mutations design pass.

**[P] Completionist rewards.** Total-level milestones, per-skill mastery cosmetics at 100, and an
all-skills mastery reward. Cosmetic or convenience only, never power, so progression stays horizontal.

### 5.4 Recipes, gathering, salvage
```odin
RecipeSource :: enum u8 { Known, Found, Purchased }

Recipe :: struct {
    id:        RecipeId,
    skill:     SkillId,
    level_req: u16,
    station:   StationKind,          // forge, bench, alchemy table…
    inputs:    []ItemStack,
    outputs:   []ItemStack,
    xp:        u32,
    source:    RecipeSource,
}

NodeDef :: struct {                  // resource spawn definition
    skill: SkillId, level_req: u16,
    yields: LootTableId, xp: u32,
    respawn_s: f32, model: ModelId,
}
ResourceNode :: struct { def: NodeDefId, tile: [2]i32, depleted_until: u64 }

SalvageTable :: struct { outputs: []WeightedStack, skill: SkillId, xp: u32 }
```

A learned recipe is a per-character bitset. A found or purchased recipe is an `ItemKind.Recipe`
that is consumed to learn it, so it is tradeable on the exchange.

### 5.5 Death and corpses
```odin
LocationKind :: enum u8 { Overworld, Instance }
LocationRef  :: struct { kind: LocationKind, shard: u16, instance: u64, pos: [2]f32 }

KEEPSAKE_SLOTS :: 1

Corpse :: struct {                    // PvE deaths
    id:         u64,
    owner:      CharId,               // owner-only at first, then public (see below)
    public_at:  i64,                  // after this, anyone may loot
    location:   LocationRef,
    items:      []ItemId,             // everything except the keepsake — equipped included
    gold:       u64,                  // all carried gold; banked gold is never at risk
    created_at: i64,
    expires_at: i64,
}

LootPile :: struct {                  // PvP deaths — no corpse, the killer claims it
    id:          u64,
    location:    LocationRef,
    items:       []ItemId,
    gold:        u64,
    claimant:    CharId,              // the killer
    claim_until: i64,                 // after this, anyone can loot
    expires_at:  i64,
}
```

On every death, the server moves everything except the keepsake (inventory + equipment) into the
corpse or loot pile in **one DB transaction**. The player respawns in the nearest city with only
the keepsake. Corpses and loot piles are backend-persisted, so they survive disconnects and
restarts.

**[D] A corpse lasts 1 hour.** Items nobody picks up are **destroyed**, removed from the economy.
The carried gold in it is destroyed too.
**[D] Corpse lifecycle: owner → public → the reserve.**

| Window | **[P]** Timing | Who can loot |
|---|---|---|
| Owner-only | 0–30 min | just the owner |
| Public | 30–60 min | anyone who finds it |
| Expired | at 60 min | contents go to the exchange reserve (§5.7.1) |

- **[P] The clock starts at death and runs in real time.** Logging out doesn't pause it, and neither
  does the corpse moving from an instance to the overworld entrance.
- The public window gives the corpse a second life as content: a reason to explore dangerous
  places looking for other players' losses, without turning safe zones into instant theft.
- **[P]** The gear in an expired corpse is still destroyed; the reserve receives only ~30%
  salvaged materials (§5.7.1). The carried gold is destroyed outright.

| Where you die | What happens to your items |
|---|---|
| Overworld, safe area | **[D]** Corpse at the death spot; corpse run to retrieve |
| Inside a dungeon/raid | **[D]** Corpse stays in the instance and **you can re-enter while it's alive**. When the instance shuts down, the corpse moves to the **dungeon's overworld entrance** |
| PvP zone | **[D]** No corpse. **The killer takes the items.** **[P]** As a `LootPile` the killer has exclusive claim on for 60 s, then it's public until it expires |

**Keepsake and the combat timer.**
```odin
COMBAT_TIMER_SECS :: 10

CombatState :: struct {
    last_hostile_tick: u64,   // set when the character deals OR takes damage (PvE or PvP)
}
in_combat :: proc(c: CombatState, now: u64) -> bool
```
- **[D]** The keepsake can be set anywhere, but not while `in_combat`. The server rejects the
  change; the client just greys out the button.
- **[P]** "Mid-fight" = dealt or took damage in the last **10 s**. Without a timer, "mid-fight" has no
  definition the server can enforce.
- **[P] Logging out in combat doesn't save you.** If you disconnect while `in_combat`, your
  character stays in the world until the timer expires. Without this rule, PvP players escape
  death (and the item loss) by quitting the client.

**[?] Keepsake rules: undecided.** Make them **data, not code**, so the vertical slice can
playtest several and you can decide from experience:
```odin
KeepsakeRules :: struct {
    pvp_protects:        bool,  // does the keepsake survive a PvP death?
    max_tier:            u8,    // 0 = any tier; else only items ≤ this tier qualify
    death_durability_pct: f32,  // durability the keepsake loses each death (a cost to keep it)
    allowed_kinds:       bit_set[ItemKind],
}
```

| Option | Rules | Effect |
|---|---|---|
| A. Anything, always | `pvp_protects=true, max_tier=0` | Simplest. Your best weapon is never at risk, even in PvP |
| B. Not in PvP | `pvp_protects=false` | The PvP zone is truly all-or-nothing, so the "high-loot" promise is real |
| C. Costly to keep | `death_durability_pct=0.25` | The keepsake survives but comes back damaged; repair is a gold sink |
| D. Tier-capped | `max_tier=5` | Mid-tier insurance; top gear always carries risk |

**[P] Lean:** B + C. The keepsake protects you in PvE but not in PvP, and comes back damaged.
That preserves the stakes where you said loot should be high, and adds a repair sink.

**[P] Instance lifetime after a wipe.** An instance with zero players lingers **10 minutes**
before shutting down. That gives the party time to run back from the city.
**[P] Re-entry needs no new key** for members of the original party while the instance is alive.
The key was consumed once for that instance.

### 5.6 Instances and keys
```odin
KeyDef :: struct {                   // ItemDef where kind == .Key
    dungeon:   DungeonDefId,         // which BiomeDef / raid def
    tier:      u8,
    modifiers: []ZoneModifierId,     // optional; PoE-map-like
    party_max: u8,                   // 4 dungeon, 10 raid
}

InstanceRequest :: struct { key_item: ItemId, party: []CharId }
// backend: consume key → mint instance_seed → spawn instance process → hand off leases
```
The instance seed is minted when the key is consumed. The instance process runs the procgen
pipeline from the earlier design (plan → stamp → populate), now with 3D props per chunk.

### 5.7 Exchange
```odin
OrderSide :: enum u8 { Buy, Sell }

ExchangeOrder :: struct {
    id:          u64,
    owner:       CharId,
    side:        OrderSide,
    def:         ItemDefId,
    instance:    ItemId,       // non-zero only for unique gear listings
    price_each:  u64,
    qty_total:   u32,
    qty_filled:  u32,
    escrow_gold: u64,          // buy orders
    created_at:  i64,
    expires_at:  i64,
}
EXCHANGE_SELL_FEE_BP :: 250     // 2.5% — tuning knob, charged on fill
```
- **[P] Fungible goods** (materials, keys, consumables, recipes) go into an **order book**:
  buy/sell matched by price, OSRS Grand Exchange style.
- **[P] Unique gear** (durability + enchants make it non-fungible) goes into **sell listings**
  with a buyout price.
- Proceeds and purchases go to a **collection box**, claimed in any city.

#### 5.7.1 The exchange reserve: the game as a market regulator [?]

**Your idea:** the game holds its own stock of items and sells it on the exchange. Some stock
comes from dead players, and some is refreshed artificially every week.

**[P] Shape it as a price band.**
```
   price
     │  ── reserve sells here (ceiling) ──   ← game lists stock when prices run too high
     │        players trade freely
     │  ── NPC merchants buy here (floor) ──  ← §5.8
```
- **Floor:** NPC merchants buying (§5.8) stop prices collapsing.
- **Ceiling:** when an item's 7-day median price climbs above `target × ceiling_mult`, the reserve
  lists stock at the ceiling, up to a weekly cap. That stops prices running away, and it keeps
  thin markets usable. Thin markets matter for the experiment, where there may only be dozens of players.
- **Gold the reserve receives is destroyed.** The reserve is a gold sink that works hardest exactly
  when prices are inflating. That's the regulator behaviour you want.

**The conflict to resolve: dead players' items vs. "destroyed".** If expired corpses feed the reserve,
death stops removing gear from the game. Gear just changes owner through the system, and gear
accumulates.
**[P] Compromise:** the system **salvages** expired corpse contents at a poor yield (~30%). The
gear itself is destroyed (the item sink survives), and some materials flow back into the reserve.

```odin
ReserveSource :: enum u8 { ExpiredCorpse, WeeklyRefresh }

ReservePolicy :: struct {              // designer data, per regulated item
    def:            ItemDefId,
    target_price:   u64,
    ceiling_mult:   f32,               // e.g. 1.5 → reserve lists at target × 1.5
    weekly_refresh: u32,               // units minted into the reserve each week
    weekly_cap:     u32,               // max units the reserve lists per week
    sources:        bit_set[ReserveSource],
}

ReserveStock :: struct { def: ItemDefId, qty: u64 }

PriceStats :: struct {                 // player-to-player fills ONLY
    def:       ItemDefId,
    median_7d: u64,
    volume_7d: u64,
}
```

**Rules that keep it from breaking.**
- **Ceiling > every NPC's base buy price,** for every regulated item. Otherwise "buy from the
  reserve, sell to an NPC" is an infinite gold printer. Unit-tested against the data.
- **The reserve never buys.** Buying would be a second faucet; NPCs already are one.
- **Price stats exclude the reserve's own sales.** Otherwise it reacts to prices it set itself.
- **[P] Only regulate mid- and low-tier goods:** T1–T6 materials, consumables, keys. **Never
  top-tier materials or gear.** The high end stays a purely player-driven market; that's where
  status and the best money live.
- Unsold weekly listings return to the reserve at week end.

**[D] Reserve listings are marked, under a thematic name** — not hidden behind fake player names.
**[P] Candidates** (the game is *Las Tormentas*, and Spanish is already a shipped locale):

| Name | Reads as |
|---|---|
| **La Casa** — "the House" | the house always has stock, and the house always wins. My pick |
| **La Bodega** | the storehouse / stockroom |
| **El Almacén** | the warehouse, more industrial |
| **La Consigna** | the consignment desk, ties to the exchange-house framing |

Whichever it is, the seller column shows it, with a tooltip explaining it's the exchange's own
stock. Players will deduce a regulator exists; being open about it reads as a feature instead of
a scam.

### 5.8 NPC merchants (supply and demand)

**[D]** Individual NPCs buy items, and each runs its own internal supply and demand. This replaces
today's fixed `SELL_RATIO :: 0.4` in `shop.odin`. NPC buying is also the economy's **main gold
faucet**. Player-to-player trade only moves gold around, while fees and repairs destroy it, so
something has to create it.

**Model, per NPC per item.**
- The NPC tracks a **surplus**: how much more of the item it holds than it wants.
- Every unit a player sells raises the surplus and lowers the next unit's price by a fixed factor.
- The surplus drains back toward zero at a **consume rate**: the NPC "uses up" stock over time.
- Past a **stock cap** the NPC stops buying. Without the cap, the price floor would be an
  unbounded faucet.

```odin
NpcDemand :: struct {
    def:          ItemDefId,
    base_price:   u32,     // ItemDef.vendor_value × this NPC's multiplier
    surplus:      f32,     // ≥ 0; units above what the NPC wants
    max_surplus:  u32,     // stock cap: NPC refuses to buy beyond this
    consume_rate: f32,     // units/hour the surplus drains
    decay:        f32,     // per-unit price factor, e.g. 0.99
    floor_frac:   f32,     // never quote below base × floor_frac
    updated_at:   i64,     // lazy update — no per-tick cost
}

NpcMerchant :: struct {
    id:       NpcId,
    location: LocationRef,
    demands:  []NpcDemand,   // what it buys: blacksmith → ore, bars; apothecary → herbs
    sells:    []NpcOffer,    // basic supplies for skills (see below)
    spread:   f32,           // markup when the NPC sells
}

// unit price at surplus s:        base · max(floor, decay^s)
// selling n units from surplus s: base · decay^s · (1 − decay^n) / (1 − decay)   (above the floor)
```

**Worked example** (base 10 g, decay 0.99, floor 25%, consume 60/h):

| Player sells into a fresh NPC | Gold received | Avg per unit | Next unit pays |
|---|---|---|---|
| 1 | 10 | 10.00 | 9.90 |
| 50 | 395 | 7.90 | 6.05 |
| 100 | 634 | 6.34 | 3.66 |
| 200 | 905 | 4.53 | 2.50 (floor) |

A 200-unit surplus drains back in ~3.3 hours.

**Why this shape is good for the game.**
- **The gold faucet has a ceiling you choose.** Sustained gold injection per NPC-item is at most
  `consume_rate × base_price` (600 g/h in the example). The whole shard's faucet is the sum over
  all NPCs. That makes it *the* economy dial, and it can be tuned live.
- **Dumping is self-limiting.** A bot farm, or 200 players, flooding one NPC tanks its price
  for everyone. It can't print gold.
- **Prices differ between NPCs.** A blacksmith in a quiet town pays more than one in the
  capital. That makes hauling worthwhile and spreads players across the map, even with one
  global exchange.
- **The NPC price acts as a soft floor under the exchange.** Nobody lists ore below what the
  nearest unsaturated NPC pays.

**Implementation rules.**
- NPC state lives in the **backend**, one copy per shard, shared by all 2k players.
- It is updated **lazily** on access (`surplus -= consume_rate · Δt`). There's no tick cost and
  no cost at all for NPCs nobody visits.
- **Selling is atomic with slippage protection.** The client gets a quote, then sends `sell(n,
  min_total)`. The server recomputes and rejects if another player's sale moved the price below
  `min_total`.
- **[P] Invariant, unit-tested: no buy-back loop.** If the NPC also sells an item, buying it and
  selling it straight back must lose money: `spread > 1/decay − 1` (> 1.01% at decay 0.99).
  **[P]** Use a spread of ~25% so buying from NPCs is a gold *sink*.

**[D] Merchant types.** Trade merchants (blacksmith, apothecary…) buy their own trade's goods.
Some general merchants buy anything. **[P]** General merchants pay a lower multiplier, so the
right specialist is always the better sale.

**[D] NPCs sell basic supplies for skills.**
**[P] Rule: NPCs sell tools and auxiliary inputs (pickaxes, vials, flux, thread, bait) but never
primary gathered materials, and nothing a player skill produces above T1.** If a blacksmith NPC sold
ore, crafters would never buy from gatherers, and the whole gatherer → crafter demand chain of
§5.3.1 would collapse.

Items sold *to* NPCs are consumed by them, not resold. That makes NPC buying an **item sink** as
well as a gold faucet.

### 5.9 Economy ledger: faucets, sinks, and logging them

| | Gold | Items |
|---|---|---|
| **Faucets** (create) | NPC merchants buying · quest rewards | mob drops · gathering · crafting outputs · NPC supplies · reserve weekly refresh |
| **Sinks** (destroy) | exchange fees · repairs · NPC supplies · reserve sales · expired corpse gold | crafting inputs · salvage · sold to NPCs · expired corpses |
| **Transfers** (neither) | player trades · PvP loot | player trades · PvP loot |

**[P] Log every gold and item creation or destruction with a reason code, from day one.**
```odin
EconReason :: enum u16 {
    NpcSale, QuestReward,                             // gold faucets
    ExchangeFee, Repair, NpcPurchase, ReservePurchase, CorpseExpired,  // gold sinks
    Drop, Gather, Craft, Salvage, ReserveRefresh,     // item flows
}

EconomyEvent :: struct {        // append-only table; rolled up daily
    at:         i64,
    shard:      u16,
    char:       CharId,
    reason:     EconReason,
    gold_delta: i64,
    def:        ItemDefId,
    qty_delta:  i64,
}
```
This is cheap to add now and impossible to reconstruct later. It's how you'll know whether the
NPC faucet, the reserve and corpse expiry are balanced, and it's the data every tuning decision
in §5.7–5.8 depends on. The daily rollup has one headline number: **net gold created per day**.
That number should grow roughly with the player count, not faster.

### 5.10 Overworld on disk
```
data/world/<template>/
  world.json              size, generation seed, landmarks, zone polygons (PvP, cities)
  regions/r_<x>_<y>.bin   64×64 tiles: tiles, props (model, pos, rot), spawners, nodes
```
- **[P] Generate once:** generator(seed, landmark list) → region files. After that, the **files are
  the truth**. The seed is history, not a dependency.
- **[P] One grid for everything:** 64×64 region files → 16×16 AoI cells → render culling chunks →
  spatial hash buckets. Pick the numbers once and share them.

---

## 6. Rendering (sokol)

**[P] Order of work:**
1. **Platform layer:** sokol_app (window, input, events), miniaudio, fontstash/stb_truetype.
2. **2D batcher** for UI and editor: the ~15 calls that cover most of today's 2,449 `rl.` uses
   (rects, lines, triangles, textured quads, text). Port the Clay renderer and ImGui backend onto
   it. Port `rl.Color`/`rl.Rectangle`/`rl.Vector2` to local types. That step is mechanical.
3. **3D world:**
   - instanced meshes for tiles and props, chunk frustum culling
   - glTF via cgltf, skinned meshes, animation state machine driven by the existing `AnimState`
   - one directional light with shadow map, fog
   - `LevelLightingConfig` remapped to 3D (sun dir, color, fog already exist)
4. **Camera:** top-down orbit, free yaw, clamped pitch. Movement input is camera-relative. Mouse
   aim is a ray-cast to the z=0 ground plane, which is trivial on a 2D grid.
5. **Occlusion:** with free rotation, walls end up between camera and player. Use a
   cutaway/fade for geometry inside a camera→player capsule.

External deps: **sokol-odin** bindings and **sokol-shdc** for shaders. Vendor them into
`deps/` with provenance + SHA manifest, the same way as `clockwork-ecs`.

**Placeholder art [D]:** primitives only (capsules, boxes, cylinders), described per entity def
in data so glTF models can replace them without code changes. Details in `BUILD_PLAN.md`, P1.

---

## 7. New editor

- **[P] Separate binary** (`editor/`) sharing `sim/` + `world/`. This keeps the client lean and the server headless.
- ImGui (already vendored) + sokol 3D viewport.
- **Overworld mode:**
  - paint tiles
  - place landmarks and props (model, rot)
  - place mob spawners and resource nodes
  - draw zone polygons (PvP, cities, safe areas)
  - edit region-by-region, with live AoI cell overlay
- **Chunk mode** (procgen rooms):
  - tiles + 3D props
  - edge flags (Wall/Door/Open)
  - spawn slots with roles
  - tags (Entry/Exit/Boss/Vault)
  - "generate 20 dungeons from this chunk set" preview
- **Data mode:** ItemDefs, Recipes, NodeDefs, SkillDefs, KeyDefs. This could just be JSON +
  hot reload at first.

---

## 8. Phased build

The execution order lives in **[`BUILD_PLAN.md`](BUILD_PLAN.md)** — tasks, exit criteria,
verification and risks per phase. Summary:

| Phase | Goal | Size |
|---|---|---|
| P0 | Foundation: package split, spatial hash, item split, ledger | L |
| P1a | raylib → sokol, 2D parity | L |
| P1b | Top-down 3D: models, free camera, instancing | XL |
| P2 | Dedicated server, persistence, AoI replication | XL |
| P3 | Vertical slice: the full loop, thin | XL |
| P4 | Widen: all skills, raids, enchanting, services | XL |
| P5 | Scale to 2,000 players and harden | L |
| P6 | Playtest and live-ops prep | L |

---

## 9. Design passes still needed (design work, not engineering)

1. **Mutations → skills.** How alchemy/medicine produce mutations, and what the combat mutation skill does.
2. **Full skill list + unlock tables** per skill, levels 1–100, with what each 10-level milestone unlocks.
3. **Horizontal combat power model.** What the per-level stat cap is; how gear tiers plateau.
4. **Item tiers + material economy.** Tiers, salvage yields, which dungeons drop which materials.
5. **Service economy.** How a player sells enchanting to another without a trust problem.
   Proposed: **escrowed crafting orders**. The customer posts item + materials + fee, the crafter
   fulfills, and the server swaps atomically.
6. **PvP zone rules.** Loot rules, skulling/aggression flags, entry warnings.
7. **Quests in a sandbox.** What quest XP rewards look like (choose-a-skill XP? fixed skills?).

---

## 10. Open questions

Everything blocking the build is decided. What's left is tuning and two naming calls.

1. **[?] The reserve's name.** *[P] "La Casa".* Alternatives in §5.7.1.
2. **[?] Keepsake rules.** Built as data (§5.5) and deliberately deferred to slice playtests.
   *[P] Lean: protects in PvE, not in PvP, and comes back damaged.*
3. **[?] Database.** *[P] SQLite for the experiment, behind an interface; Postgres if it binds.*
4. **[?] Steam.** *[P] Keep it for identity/auth and the storefront; gameplay traffic over ENet.*
5. **[?] Overworld size.** Needed before P3 (region count, AoI cost, editor workload). A number
   like "2,048 × 2,048 tiles" is enough to start.
6. **[?] Team size and calendar.** `BUILD_PLAN.md` sizes the work in effort, not weeks, because
   this is still unanswered.
