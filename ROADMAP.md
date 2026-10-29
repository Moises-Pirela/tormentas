# Roadmap

Target: a content-complete, balanced release in **2027**. The engine and systems are deep; the
work ahead is **content, the missing gameplay pillars, and stability** — not more architecture.

Status legend: ✅ done · 🚧 in progress · 📋 planned · ❓ needs decision

---

## Defining reality

**Deep engine, thin content.** The extraction loop, buildcraft, co-op, UI, and tooling all work.
What's missing is the stuff that turns the systems into a *game people replay*: stakes, pressure,
an endgame, and far more content feeding the machine.

---

## The four missing pillars (highest priority)

These are the features that change the game's identity, not just its volume. Roughly in order.

### 1. The storm 📋
The title mechanic isn't in the game yet. Add an encroaching storm / raid pressure that forces the
extraction decision — a closing danger zone and/or escalating spawns over time.
- [ ] Storm/zone state machine (safe → warning → closing → lethal)
- [ ] Visual + audio telegraphing
- [ ] Spawn/intensity escalation tied to storm phase

### 2. Extraction stakes 📋
Right now death is a 2s respawn with no loss, so the core loop has no tension.
- [ ] Gear/loot loss on death (what you carry vs. what's banked)
- [ ] Secure-container / insurance concept to soften the floor
- [ ] Raid-fail vs. extract-success economy (what you keep either way)
- [ ] Co-op downed state + teammate revive

### 3. Crafting & item sinks 📋
No crafting, reroll, salvage, or upgrade exists — the biggest retention lever is absent.
- [ ] Affix reroll / reforge
- [ ] Salvage / disenchant into a crafting currency
- [ ] Item upgrade path
- [ ] A hub station (and NPC) for all of the above

### 4. Endgame / difficulty ladder 📋
Enemy "tier" is per-enemy loot rarity, not a run-level difficulty scale. After the authored content
is cleared, the loop ends.
- [ ] Ascending difficulty tiers or map modifiers
- [ ] Rewards that scale with difficulty
- [ ] A reason to re-run (meta objectives, rotating modifiers)

---

## Content production

The schedule driver. Secure art/audio capacity early.

- [ ] **Maps:** author 6–8 levels across 2–3 biomes via `tools/gen_levelNN.py` (no procedural gen)
- [ ] **Enemies:** expand from ~6 types toward 12–15
- [ ] **AI behaviors:** grow past melee + ranged (chargers, exploders, summoners, shielded, support)
- [ ] **Bosses:** from 1 toward 3–4, each with telegraphed phases/mechanics
- [ ] **Audio:** fill the pipeline — 40–60 SFX, 6–10 music tracks (engine is ready, content is not)
- [ ] **In-raid objective variety:** beyond kill + extract (defend / collect / hack / escort)
- [ ] HUD/VFX art pass

---

## Milestones to release

- **M-now — foundation:** commit the large working stack; stand up a Steam "Coming Soon" page; begin devlog capture.
- **M1 — identity:** ship pillars #1 and #2 (storm + extraction stakes). This is the make-or-break phase.
- **M2 — retention:** crafting/item sinks (#3) + first balance pass + 1–2 new AI behaviors.
- **M3–M4 — content production:** maps/biomes, bosses #2–3, audio fill, class balance, quest/meta verified.
- **M5 — feature + content lock:** endgame ladder (#4), boss #4, all audio in, economy balance.
- **M6 — stability:** save-migration + multiplayer-desync test harness, first external playtest, crash/desync fixes.
- **M7 — polish:** balance to release quality, VFX/juice, UX cleanup.
- **M8 — RC + launch prep + buffer.**

---

## Known issues & tech debt

- [ ] **gen_level drift:** the `tools/` scripts emit an old level `version`; reconcile to the current
      `LEVEL_VERSION` and round-trip verify before treating them as the map pipeline.
- [ ] **`tools/` untracked** in git — decide what to commit.
- [ ] **No automated tests.** At minimum: save round-trip + a lockstep determinism/desync harness (M6).
- [ ] **Versioned binary saves** carry migration risk — add migration or an explicit wipe-on-breaking-change policy.
- [ ] **Multiplayer lockstep is under-tested** — needs sustained live co-op playtesting.
- [ ] **Physics:** O(n²) separation/collision with no spatial grid (deferred); single-pass resolution.
- [ ] Confirm the Steam join / invite flow end-to-end with two live clients.

---

## Near-term TODO

- [ ] Commit the uncommitted stack (UI rework, audio pipeline, module system, weapon-per-class, animation work)
- [ ] Live two-client co-op smoke test (host + join on `127.0.0.1`)
- [ ] Update `gen_level` scripts to the current level version
- [ ] Feed first batch of real audio content through the pipeline
- [ ] Tune dodge timings and the new animation fps values in-game
- [ ] ❓ Decide save-migration policy before the next breaking save change
