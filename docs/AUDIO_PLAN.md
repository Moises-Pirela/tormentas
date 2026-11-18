# Audio Plan — immersive audio

Companion to [`BUILD_PLAN.md`](BUILD_PLAN.md) and [`BACKEND_SWAP_PLAN.md`](BACKEND_SWAP_PLAN.md).
This is a separate track from the renderer: audio gets its own runtime and its own stages (A0–A7).
Tags as elsewhere: **[D]** decided · **[P]** proposed, needs sign-off · **[?]** open.

**Sizing** as in `BUILD_PLAN.md`: S = days · M = 1–2 weeks · L = 3–6 weeks (one engineer, no content).

---

## 1. What "immersive" means for this game

The pivot makes audio harder than in the current game: a free-rotating top-down 3D camera, a shared
overworld with up to 2,000 players per shard, procgen dungeons built from authored chunks, and a PvP
zone where hearing someone before you see them matters. Concretely, the targets are:

1. **Sound is placed in 3D around the listener** and turns with the camera. A sound behind you on
   screen is behind you in your headphones.
2. **Walls and doors change what you hear.** A fight in the next room is muffled until the door
   opens (occlusion and transmission through the tile grid).
3. **Rooms sound like rooms.** Caves, crypts, halls and the open field each have their own reverb.
4. **The world is alive without the player doing anything**: region ambience beds, spot emitters
   (fires, water, machinery), later weather and time of day.
5. **Music follows play**: exploration, combat, boss, city, PvP tension, with musical transitions.
6. **Crowds stay readable.** A city with 300 players in view must not turn into mud, and a single
   enemy attack behind you must still cut through.
7. **Gameplay-critical cues are never lost**: telegraphs, your own hits and damage taken, low health.

Out of scope for now: voice chat, music authoring, and full sound propagation simulation in the
overworld (too large and too crowded for it to pay off).

---

## 2. Where we are

`src/audio.odin` (795 lines) on `src/snd` (raylib's audio, i.e. miniaudio underneath) is a small
data-driven event bank, close to a stripped-down middleware:

| Feature | State |
|---|---|
| Event bank in `data/sounds/audio.json` (hot-reloadable) | ✅ variants, random / round-robin, gain and pitch variance, per-event `max_instances`, `min_interval`, `priority` |
| Voice management | ✅ alias pools, 48 voices total, priority stealing |
| Buses | ✅ SFX, Music, Ambience, Voice, UI |
| Positional | ⚠️ distance rolloff (linear / inverse / none) and stereo pan only. **Pan uses world-x distance** (`_spatial`), not the listener's orientation, so it is already off under the isometric view and becomes wrong under a rotating camera |
| Music | ✅ state machine (`MusicState`: Menu, Hub, Explore, Combat, Boss, Tension), crossfades, ducking |
| Ambience | ✅ two crossfading layers (ambience + bed) |
| Footsteps | ✅ from movement speed; no surface types |
| Settings | ⚠️ SFX and Music sliders only; **volumes are not saved** to the config; master / ambience / voice have no UI; `apply_bus_volumes` is an empty stub |
| Content | 9 placeholder MP3s; 76 call sites use 34 event names (`play_sfx`, `play_sfx_at`) |
| Architecture | ⚠️ simulation systems call audio directly (`ability_system.odin` 22 calls, `damage_system.odin` 6, …). The headless server only works because those systems are not in `src/sim` yet |

The bank format and the `play_sfx` / `play_sfx_at` facade are worth keeping: callers should not
change when the runtime underneath does.

---

## 3. The runtime

**Decided 2026-11-17:** sound is **sourced paid audio, programmer-driven** (no sound designer),
**PC only** (macOS + Windows), and **free or open-source licences only**.

That removes the case for FMOD and Wwise. Their value is the authoring tool a designer lives in,
and their free tiers end where a live game's revenue begins (FMOD's indie tier at US$200k revenue;
Wwise's at a US$250k budget). Without an authoring tool to justify them, what is left is a mixer
plus an acoustics layer, and both have free options.

Audio still needs two things:

- **A mixer**: decoding and streaming, voices, buses, filters, 3D panning and attenuation.
- **Acoustics**: HRTF, occlusion and transmission, reverb. Only needed from stage A3 on.

| | **Keep miniaudio** | **OpenAL Soft** | **miniaudio + Steam Audio** |
|---|---|---|---|
| Status | already vendored and shipping (`src/snd`) | would be new | miniaudio shipping, Steam Audio new |
| Licence | public domain / MIT, no obligations | **LGPL 2+**: ship as a shared library, include the licence and the Apache-2.0 HRTF-data notice | miniaudio as-is; Steam Audio Apache 2.0 |
| Odin bindings | **done** (`vendor:miniaudio`) | **none exist**: AL + ALC + EFX, ~100 entry points | **none exist** for `phonon.h` |
| 3D panning, attenuation, doppler, cones | yes | yes | yes |
| HRTF | no | **yes, built in** | **yes**, including SOFA files |
| Reverb | no (write one, or take it from the acoustics layer) | **yes, EFX reverb and occlusion filters** | **yes**, simulated from geometry |
| Occlusion | filters, driven by our own ray casts | filters, driven by our own ray casts | **modelled**, with transmission through materials |
| Ceiling | lowest | mid: EFX presets | highest: reflections, pathing |

**[D] Keep miniaudio as the mixer for now.** Everything scheduled before A3 — the event layer, the
bank, music, ambience, surfaces, voice limits, settings — is mixer-agnostic and sits above the
`snd` facade. Swapping the mixer later touches roughly 200 lines behind that facade, so there is
nothing to gain by paying the binding and licensing cost today.

**[?] The acoustics provider is decided at A3**, with a spike that measures both: OpenAL Soft (HRTF
and EFX reverb out of the box, LGPL, replaces the mixer too) against Steam Audio as a DSP inside
miniaudio's node graph (better occlusion and reverb, Apache 2.0, keeps the mixer). Deciding then
means deciding with the 3D camera in hand and numbers on the table, instead of now.

**What "audio events" means here**, since that is the part worth having early: game code names a
sound (`play_sfx("enemy_melee")`), and a data-driven bank decides everything else — which file or
variant, the bus, gain and pitch variance, voice limits, priority and 3D settings. That already
exists in `data/sounds/audio.json` and survives every option above; A1 hardens it.

## 4. Design (holds for any option)

### 4.1 Listener
- **[P]** Position at the local player's head height; orientation from the **camera yaw** (P1b), so
  "left of the screen" is left in the ears whatever the rotation.
- Distance attenuation measured from the player, not the camera. Otherwise zooming out would make
  the player's own sounds quieter.
- With a top-down camera, elevation cues carry little. HRTF earns its keep mainly on front/back.

### 4.2 Spatialization tiers
| Tier | Which voices | Treatment |
|---|---|---|
| 1 | Nearest / most important ~16–32 | HRTF (headphones) or panning (speakers), occlusion, reverb send |
| 2 | Other audible voices | Panning + attenuation + reverb send; occlusion at a lower update rate |
| 3 | Inaudible or over budget | Virtual: tracked and timed, not mixed |

- **Settings: Headphones / Speakers.** Speakers turn HRTF off and use panning, because HRTF over
  speakers sounds worse.

### 4.3 Occlusion and transmission
- Rays from the listener to tier 1–2 sources against the **tile grid** (walls, closed doors,
  greybox), through Steam Audio's custom-scene callbacks.
- A **material per tile type** (stone, wood, metal, water) sets transmission per frequency band.
  This is data, next to the tile definitions.
- Doors already have state (`env_door_system.odin`). Opening one must update occlusion immediately.

### 4.4 Reverb and reflections
1. **Parametric reverb zones first.** A reverb preset per biome, per region (overworld) and per chunk
   tag (dungeons), blended as the listener moves. Cheap, and it covers most of the effect.
2. **Then baked reverb for dungeon chunks.** Dungeons are stamped from authored `ChunkDef`s, so each
   chunk can be baked once in the editor (Steam Audio, listener-centric reverb) and looked up by which
   chunk the listener stands in. Procgen layouts cost nothing at runtime.
3. **Real-time reflections** only if 1–2 fall short, and only inside instances (≤10 players, small
   spaces). Never in the overworld.

### 4.5 Pathing (sound around corners)
Stretch goal, dungeons and raids only: baked per instance at load time, if the bake is fast enough.

### 4.6 Voice management at MMO scale
- Keep per-event `max_instances`, `min_interval` and `priority`. Add a **global voice budget**,
  scored by priority × audibility (distance, occlusion, bus volume), with virtualization (tier 3).
- **Aggregation instead of a voice per player:** footsteps and chatter of many other players become a
  *crowd bed* driven by a density parameter; distant combat becomes a *battle bed*.
- **Never stolen:** your own actions, damage you take, telegraphs aimed at you, low-health cues.
  These are a reserved band.

### 4.7 Music
- Map today's `MusicState` onto horizontal re-sequencing (transitions on bar or beat boundaries)
  plus **vertical layers** driven by an intensity parameter (enemy count, threat).
- **Stingers**: level-up, boss phase, key moments.
- **Zone overrides**: cities, the PvP zone (with an entry cue), dungeon/raid themes per biome.

### 4.8 Ambience
- **Region beds** chosen by biome or overworld region (data from `data/world/...`, P3).
- **Spot emitters** placed in the editor (fire, water, machinery, wind gaps). They are props with a
  sound, so they belong in the same placement tools as models.
- Later: weather and time-of-day parameters.

### 4.9 Surfaces
Footsteps, impacts and drops per material, using the same tile-material table as occlusion (§4.3).

### 4.10 Where sound events come from (client only)
The server is silent. Sounds come from three places:
1. **Local prediction**: your own actions play immediately.
2. **Replicated state changes** seen in snapshots: deaths, hits, state transitions.
3. **Explicit presentation events** in the protocol, for anything not derivable from state.

Requirements:
- **De-duplication**: a predicted sound must not play again when the server confirms it.
- **The simulation must not call audio.** Today 76 calls sit in gameplay systems. Step A0.3 moves
  them onto an event queue (the audio part of P0's `sim.Presentation` hooks); A5.4 builds on it.
- **The headless server never links audio.** `test.sh` already bans `ma_device`. Extend the ban to
  the acoustics provider's symbols once A3.2 picks one (`alc`/`alSource` for OpenAL, `ipl` for
  Steam Audio).

### 4.11 Mixing
- Keep the buses. Add **snapshots**: pause menu (low-pass), low health (muffle plus heartbeat), dialogue
  (duck music and ambience), big hits (short sidechain duck).
- **Loudness targets per bus** (integrated LUFS) so content from different sources sits together.

### 4.12 Settings and accessibility
- Persist every bus volume (today none are saved), and add sliders for master, ambience and voice.
- Output device, Headphones/Speakers, mono downmix, dynamic range ("night mode").
- Mute when the window loses focus (option).
- **Directional sound indicators** for threats and attacks (accessibility, and useful in PvP), plus
  subtitles for voice lines.

### 4.13 Assets and pipeline
- 48 kHz source, OGG Vorbis. Music and ambience streamed; SFX resident.
- Naming and folders follow event names; loudness normalized at import.
- Hot reload stays: `audio.json` reloads at runtime (`audio_reload`).
- Replace the 9 placeholder MP3s as sourced audio arrives: convert to OGG at import (MP3 decode
  costs CPU and its loops are not gapless). Buy against the event list from A1.1, so every purchase
  has a slot waiting.

### 4.14 Debugging and budgets
- ImGui audio overlay: active / virtual voices, budget use, occlusion rays, current reverb zone,
  music state and parameters.
- **[P] Budgets:** audio thread ≤ 1.5 ms per 10 ms block on the min-spec CPU; Steam Audio simulation on
  its own thread; resident SFX memory ≤ 64 MB.

---

## 5. Steps

**How this is ordered.** The mixer is decided (§3: keep miniaudio), so there is no runtime swap to
schedule. Work that is mixer-agnostic comes first and can start now. 3D listening waits for the
P1b camera, and that is also where the acoustics provider is chosen; networked sound waits for P2.

**Sizes are in days** for one engineer, content excluded. Each step ends in a build that runs.

| Stage | Goal | Days | Waits for |
|---|---|---|---|
| **A0** | Groundwork: settings, panning, events out of the simulation | 6–9 | nothing: can start now |
| **A1** | The event layer and bank on miniaudio | 6–9 | A0 |
| **A2** | Music, ambience, surfaces | 8–12 | A1 |
| **A3** | 3D listener, occlusion, and the acoustics decision | 10–15 | A1, P1b camera |
| **A4** | Spaces: reverb zones, then baked chunk reverb | 12–20 | A3; chunk data (P3) for baking |
| **A5** | MMO scale and networked sound | 8–12 | A3, P2 |
| **A6** | Mix and accessibility | 5–8 | A1 |

### A0 — Groundwork (6–9 days, can start now)

Nothing here adds a dependency, and nothing is thrown away when the runtime changes: it all sits
above the `snd` facade.

**A0.1 Bus volumes that work and persist (1 day).**
- Today: volumes are not saved (`config.odin` has no audio fields), `apply_bus_volumes` is an
  empty stub, the SFX slider only affects sounds started *after* a change (volume is set once, at
  play time), the UI bus shares the SFX volume, and master, ambience and voice have no slider.
- Do: an `audio` block in the saved bindings (master, sfx, music, ambience, voice, ui);
  `apply_bus_volumes` re-applies the volume of every playing voice; sliders for all six buses in
  both settings screens.
- **Done when:** moving a slider changes a sound that is already playing, and the values survive a
  restart (round-trip test next to the existing display-settings one).

**A0.2 Panning relative to the listener (1 day).**
- Today: `_spatial` pans by world-x distance, which is already slightly wrong in the isometric
  view and becomes wrong under P1b's rotating camera.
- Do: a `Listener` with a position and a right vector, set from the camera module each frame
  (`cam_*`, so P1b only changes where the vector comes from). Pan from the source's position
  projected onto the listener's right vector.
- **Done when:** a source on the left of the screen pans left; a unit test covers the pan maths
  for the isometric basis.

**A0.3 Sounds leave the simulation (3–4 days).** The largest step, and the one that unblocks A6.
- Today: 76 calls (`play_sfx` 33, `play_sfx_at` 43) in 22 files, most of them inside gameplay
  systems (`ability_system.odin` alone has 22). A server must never make sound, and the client
  will later hear about most events through replication, not by running the code that caused them.
- Do: gameplay systems push a `SoundEvent { name, position, source entity, flags }` onto a
  per-world queue; the client drains it once per frame and plays. UI code keeps calling `play_sfx`
  directly, because UI is client-only. This is the audio part of P0's `sim.Presentation` hooks.
- **Done when:** no gameplay system calls `play_sfx*`; a sim test asserts that firing a weapon
  queues its sound event; the game sounds the same.

**A0.4 Event bank checks (1 day).**
- Today: `audio.json` defines 6 events; the other ~28 names used in code are auto-registered with
  defaults, so a typo in an event name fails silently.
- Do: a test that collects every event name used in code and checks it against the bank (or an
  explicit allow-list), plus load-time validation of buses, select modes and missing files.
- **Done when:** the test passes, and a deliberately misspelled event fails it.

**A0.5 Audio debug panel (1 day).**
- An ImGui panel next to the lighting widget: active and stolen voices per event, the last 50
  events with positions, bus volumes, music state and crossfade progress.
- **Done when:** firing in a raid shows events arriving and voices being stolen at the limits.

**A0 exit:** the game sounds the same, settings work and persist, and gameplay code no longer
plays sound directly.

### A1 — The event layer and bank on miniaudio (6–9 days)

Make the data-driven event bank do the work that game code and `audio.odin` do by hand today.
Nothing here is specific to a mixer beyond the calls behind `snd`.

**A1.1 Bank format and coverage (1–2 days).**
- Define all 34 events used in code, instead of 6 (the rest auto-register with defaults today).
  Extend the schema with the 3D fields the mixer can use: minimum and maximum distance, attenuation
  model, spread, and whether a sound is positioned at all.
- **Done when:** A0.4's test passes with no auto-registered events, and the schema is documented in
  the bank's header comment.

**A1.2 Positioned voices through the mixer (2 days).**
- Replace `_spatial`'s hand-rolled volume and pan with miniaudio's spatializer: set the listener
  (from A0.2) and each voice's position, and let it compute attenuation and panning.
- Keep today's curves audible: map the bank's `linear` and `inverse` rolloff onto the mixer's
  attenuation models, with the same inner and outer distances.
- **Done when:** a sound circling the player sounds as it does today, and `_spatial` is gone.

**A1.3 Buses as groups (1–2 days).**
- One mixer group per bus (SFX, Music, Ambience, Voice, UI, plus master). Volume changes set the
  group's gain, which makes A0.1's live updates a single call, and gives ducking somewhere to live.
- **Done when:** every voice routes through its bus group; ducking music under a big hit is one
  gain envelope on the music group.

**A1.4 Voice budget (1–2 days).**
- Today limits are per event, with priority stealing inside a pool. Add a global budget, and
  virtual voices: over budget, a sound keeps its timing and position but allocates nothing, so it
  can become audible later.
- **Done when:** A0.5's panel shows budget use, and 200 simultaneous events stay inside it.

**A1.5 Loading and memory (1 day).**
- Preload what the bank marks, stream music and ambience, and report resident size.
- **Done when:** resident SFX memory is reported in the panel and sits inside §4.14's budget.

**A1 exit:** the bank describes every sound, the mixer does the positioning, buses carry volume and
ducking, and the voice budget is visible.

### A2 — Music, ambience, surfaces (8–12 days)

**A2.1 Musical transitions (2–3 days).** Crossfade on a bar or beat boundary instead of a fixed
fade, using tempo and bar length stored per track in the bank. Stingers for level-up and boss
phases.

**A2.2 Intensity layers (2–3 days).** Vertical layers driven by a threat parameter (enemy count,
damage taken), so combat rises and falls instead of switching. Needs layered stems as content.

**A2.3 Ambience (2–3 days).** Region beds chosen from level or biome data, and spot emitters (fire,
water, machinery) placed in the editor as entities with a sound and a radius.

**A2.4 Surfaces (1–2 days).** A material per tile type, driving footsteps, impacts and item drops.
This table is the same one A3.5 uses for occlusion; whichever stage lands first creates it.

**A2 exit:** a 30-minute session has no abrupt music cuts, every tile type has footsteps, and
standing near a fire is audible without scripting.

### A3 — 3D listener, occlusion, and the acoustics decision (10–15 days, after P1b's camera)

**A3.1 Listener from the 3D camera (1 day).** Position at the player, orientation from camera yaw
(A0.2's `Listener`, now fed by P1b instead of the isometric basis).

**A3.2 Acoustics spike and decision (3–4 days).** The open question from §3. Both candidates need
Odin bindings, so the spike writes the minimum of each and measures:
- **OpenAL Soft**: HRTF and EFX reverb built in, LGPL (ship as a shared library, include the licence
  and the HRTF-data notice). Replaces miniaudio as the mixer.
- **Steam Audio inside miniaudio's node graph**: Apache 2.0, HRTF plus modelled occlusion with
  transmission, and reflections later. Keeps the mixer.
- Measure: audio-thread CPU per HRTF voice at 8, 16 and 32 voices; reverb quality by ear in a cave
  and a hall; and the integration cost actually paid in the spike.
- **Done when:** the numbers are recorded here and the choice is tagged **[D]**.

**A3.3 Spatial tiers (2–3 days).** Score voices by priority × audibility. Tier 1 (count from A3.2's
measurements) gets HRTF and per-frame occlusion; tier 2 is panned with occlusion at a lower rate;
tier 3 is virtual (A1.4).

**A3.4 Headphones / Speakers setting (1 day).** HRTF off for speakers, because it sounds worse over
them.

**A3.5 Occlusion (3–4 days).** Rays from listener to tier 1–2 sources against the tile grid, with
the material table (A2.4) setting how much passes through. Doors update the moment they open.

**A3 exit:** with eyes closed, a listener points to a source behind a wall within ~45°, hears the
door open, and tier-1 CPU is inside §4.14's budget.

### A4 — Spaces (12–20 days)

**A4.1 Reverb zones (3–4 days).** A preset per biome, region and chunk tag, blended over a few
metres at the edges. With OpenAL this is an EFX effect slot; with Steam Audio it is a reverb from
the zone's parameters.

**A4.2 Chunk reverb bake in the editor (5–8 days, needs P3's chunk mode).** One listener-centric
bake per `ChunkDef`, cached by content hash so unchanged chunks never rebake. Steam Audio only.

**A4.3 Runtime lookup** by the chunk the listener stands in.

**A4.4 (Optional) real-time reflections** inside instances only, if A4.1–A4.3 fall short.

**A4 exit:** field → cave → crypt changes audibly with no clicks at the edges; bake time per chunk
recorded.

### A5 — MMO scale and networked sound (8–12 days, after A3 and P2)

**A5.1 Budget at crowd scale.** A5 inherits A1.4's budget; here it is tuned for hundreds of
emitters, with audibility scoring that accounts for occlusion.

**A5.2 Reserved cues.** Your own actions, damage you take, telegraphs aimed at you and low health
are never stolen.

**A5.3 Crowd and battle beds.** Density-driven beds instead of a voice per distant player.

**A5.4 Sound from replication.** The client builds sound events (A0.3) from replicated state and
from explicit presentation events in the protocol; event ids de-duplicate a sound predicted
locally against the server's confirmation.

**A5.5 Soak:** 300 bots in a city, inside §4.14's budget, with no doubled sounds.

### A6 — Mix and accessibility (5–8 days, after A1)

**A6.1 Snapshots:** pause (low-pass), low health (muffle plus heartbeat), dialogue (duck music and
ambience), big hits (short sidechain duck on the music group from A1.3).

**A6.2 Loudness:** a target per bus, and normalization when importing sourced audio.

**A6.3 Settings:** output device, mono downmix, night mode, mute when unfocused.

**A6.4 Directional indicators** for threats and attacks, matched to sound sources, and subtitles for
voice lines.

---

## 6. Decisions

| # | Decision | State |
|---|---|---|
| 1 | Who authors sound | **[D]** Sourced paid audio, programmer-driven. No authoring tool to pay for |
| 2 | Platforms | **[D]** PC only: macOS and Windows |
| 3 | Budget | **[D]** Free or open-source licences only |
| 4 | Mixer | **[D]** Keep miniaudio (§3). FMOD and Wwise are out on 1 and 3 |
| 5 | Acoustics provider | **[?]** OpenAL Soft or Steam Audio, decided at **A3.2** with measurements |
| 6 | Listener | **[P]** Player position, camera-yaw orientation (§4.1) |
| 7 | Acoustics scope | **[P]** Zones → baked chunk reverb → real-time reflections only in instances (§4.4) |
| 8 | Interim audio | **[D]** `snd` runs on miniaudio since the backend swap (§7) |

## 7. Relationship to the backend swap

Settled. The swap (commit `7c60525`) moved `src/snd` onto miniaudio's high-level engine, which is
what raylib's audio wrapped anyway, so raylib could be deleted and the game sounds the same. That
runtime carries stage A0; stage A2 replaces it.

---

## 8. Risks

| Risk | Phase | Mitigation |
|---|---|---|
| An LGPL shared library is awkward to ship | A3.2 | dynamic linking plus the licence and HRTF notices; Steam Audio is the Apache-2.0 alternative |
| Licence terms change | A3.2 | `snd` facade; confirm current terms, consider the GaaS-type licences; C stays possible |
| HRTF CPU cost at crowd scale | A3/A5 | tier 1 cap, virtual voices, measured in A3.2 |
| Occlusion rays against a large overworld | A3.5 | rays only for tier 1–2 voices, low update rate for tier 2, grid DDA |
| Bake times for chunk reverb | A4 | bake in the editor per chunk, cache by chunk hash |
| Double sounds from prediction + replication | A5.4 | event ids and de-duplication (§4.10) |
| Audio leaking into the headless server | all | symbol ban in `test.sh` extended per runtime |
| Sourced audio does not fit the bank's shape | A1.1 | define every event first, then buy to the list |

Sources for licensing and Steam Audio facts (checked 2026-11-17; confirm on vendor sites):
- [Steam Audio C API documentation](https://valvesoftware.github.io/steam-audio/doc/capi/index.html)
- [Valve releases all Steam Audio source under Apache 2.0 (Phoronix)](https://www.phoronix.com/news/Steam-Audio-SDK-Fully-Open)
- [ValveSoftware/steam-audio releases](https://github.com/ValveSoftware/steam-audio/releases)
- [FMOD Studio free for small developers (Game Developer)](https://www.gamedeveloper.com/audio/small-developers-and-creators-can-now-use-fmod-studio-for-free)
- [CRI ADX vs Wwise vs FMOD Studio, 2026 pricing (DEV Community)](https://dev.to/gamedevtoollab/where-unity-audio-reaches-its-limits-cri-adx-vs-wwise-vs-fmod-studio-1m4f)
- [Free Wwise Indie License (Audiokinetic)](https://www.audiokinetic.com/en/blog/free-wwise-indie-license/)
