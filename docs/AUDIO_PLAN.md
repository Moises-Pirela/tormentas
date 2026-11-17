# Audio Plan — immersive audio

Companion to [`BUILD_PLAN.md`](BUILD_PLAN.md) and [`BACKEND_SWAP_PLAN.md`](BACKEND_SWAP_PLAN.md).
This is a separate track from the renderer: audio gets its own runtime and its own phases (A0–A6).
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

## 3. The two layers to choose

Immersive audio needs two different things, and they are often confused:

- **A runtime**: decoding and streaming, voices and virtual voices, buses and DSP, mixer snapshots,
  parameters, adaptive music, a profiler. This is what plays sound.
- **Acoustics**: HRTF spatialization, occlusion and transmission, reflections and reverb, pathing
  around corners. This is what makes sound sit in a space.

miniaudio's high-level engine gives a basic runtime and simple panning/attenuation, and neither layer
at the level above **[D: miniaudio alone is not enough]**. The options:

| | **A. FMOD Studio + Steam Audio** | **B. Wwise + Steam Audio** | **C. Own runtime + Steam Audio** |
|---|---|---|---|
| Runtime | FMOD Core/Studio (C API) | Wwise SDK (C++ API) | Our mixer on miniaudio's low-level device, decoding and resampling only |
| Acoustics | Steam Audio FMOD plugin | Steam Audio Wwise plugin | Steam Audio C API (`phonon.h`) in our DSP graph |
| Authoring tool | FMOD Studio: events, parameters, snapshots, live update, profiler | Wwise authoring: the most powerful, the steepest | None; we keep extending `audio.json` and build our own debug views |
| Adaptive music | Built in (timeline, transitions, parameters) | Built in, very deep | We build it |
| Licence (from 2026 sources; confirm on vendor sites before committing) | Free under US$200k revenue and US$600k budget; then US$2k–18k per title | Free under US$250k budget; paid tiers above, plus a revenue-based GaaS licence suited to live games | Steam Audio is Apache 2.0; miniaudio is public domain / MIT |
| Odin integration | Bind the FMOD C API (plain C); ship FMOD's binaries | C++ API; needs a C shim | Bind `phonon.h` (plain C); everything else is ours |
| Effort to parity with today | M | L | L |
| Effort to the full target in §1 | M–L | L | XL |
| Main risk | Proprietary binary and licence terms | Complexity and cost for a small team | We build and maintain a middleware |

**Steam Audio** is the common acoustics layer in every option: Apache 2.0 since 2024, a plain C API,
HRTF (built-in or SOFA files), raycast occlusion with transmission, real-time or baked reflections
and reverb, and pathing. It does not require the Steam client. It can trace rays against a **custom
scene through callbacks**, which matters here: we can answer occlusion rays from our own tile grid
instead of building triangle meshes (to verify in A0).

**[P] Recommendation: A, FMOD Studio + Steam Audio,** behind the existing `snd` facade.
- The authoring tool is the biggest lever on audio quality, and it is where a sound designer
  (contract or hire) will live. Options B and C either cost more than this team should spend, or
  make us build that tool.
- Today's `audio.json` concepts (events, variants, buses, music states, ducking) map directly onto
  FMOD events, buses and snapshots, so migration is mechanical.
- Licence cost is small next to the engineering C would take. The facade keeps the runtime swappable
  if the terms ever stop fitting.

**What would change the recommendation:**
- A hard requirement for an all-open-source stack, or for no third-party binaries → **C**.
- A dedicated audio team, or console certification needs → reconsider **B**.

---

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
- **The simulation must not call audio.** Today 76 calls sit in gameplay systems. The P0
  `sim.Presentation` hooks are the fix, and they block A5.
- **The headless server never links audio.** `test.sh` already bans `ma_device`. Extend the ban to
  the chosen runtime's symbols (`FMOD_`, `ipl`).

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
- 48 kHz source. Banks (option A/B) or OGG Vorbis (C). Music and ambience streamed; SFX resident.
- Naming and folders follow event names; loudness normalized at import.
- Hot reload stays: FMOD live update in A/B, `audio.json` reload in C.
- Replace the 9 placeholder MP3s when real content arrives (MP3 decode costs CPU, and gapless loops
  are unreliable).

### 4.14 Debugging and budgets
- ImGui audio overlay: active / virtual voices, budget use, occlusion rays, current reverb zone,
  music state and parameters.
- **[P] Budgets:** audio thread ≤ 1.5 ms per 10 ms block on the min-spec CPU; Steam Audio simulation on
  its own thread; resident SFX memory ≤ 64 MB.

---

## 5. Phases

| Phase | Goal | Size | Depends on |
|---|---|---|---|
| **A0** | Decide the runtime; spike | S | — |
| **A1** | Runtime swap at parity | M | A0 |
| **A2** | 3D listener, spatial tiers, occlusion | M | A1, P1b camera |
| **A3** | Reverb zones, then baked chunk reverb | L | A2, chunk data (P3) |
| **A4** | Adaptive music, ambience system, surfaces | M | A1 |
| **A5** | MMO scale: voice budget, aggregation, networked events | M | A2, P0 hooks, P2 |
| **A6** | Mix snapshots, settings, accessibility | S–M | A1 |

### A0 — Decide and spike (S)
- Settle §3 (runtime) and the questions in §6.
- Spike in its own target, as the sokol spike was: bind the chosen runtime and Steam Audio. Play a
  looping source that moves around the listener with HRTF, occluded by a wall from a tiny tile grid
  through custom-scene callbacks.
- **Exit:** both platforms; occlusion audibly follows the grid; measured CPU per HRTF voice.

### A1 — Runtime swap at parity (M)
- Reimplement `snd` on the new runtime and migrate `audio.json` (events, buses, music states,
  ducking, ambience layers). `play_sfx` / `play_sfx_at` callers do not change.
- Fix on the way: panning relative to listener orientation; persist volumes; implement
  `apply_bus_volumes`.
- Remove the audio half of raylib (see §7).
- **Exit:** every one of the 34 current events plays as before; headless server symbol check extended.

### A2 — 3D listener, tiers, occlusion (M)
- Listener from the P1b camera (§4.1), tiers (§4.2), Headphones/Speakers, tile-grid occlusion and the
  material table (§4.3).
- **Exit:** blind test: with eyes closed, a listener can point to a source behind a wall to within
  ~45°, and hear the door open.

### A3 — Acoustics (L)
- Parametric reverb zones (§4.4.1), then the editor bake of chunk reverb and the runtime lookup
  (§4.4.2). Optional real-time reflections in instances (§4.4.3).
- **Exit:** walking from field to cave to crypt changes the space audibly, with no clicks at zone
  edges; bake time per chunk measured.

### A4 — Music, ambience, surfaces (M)
- Adaptive music (§4.7), region beds and spot emitters with editor placement (§4.8), surface
  materials (§4.9).
- **Exit:** a 30-minute session has no abrupt music cuts; every tile type has footsteps.

### A5 — MMO scale and networking (M)
- Global budget and virtualization, crowd and battle beds, reserved cue band (§4.6). Sound sources
  from replicated state and presentation events, with prediction de-duplication (§4.10).
- **Exit:** a 300-bot city soak stays within the §4.14 budget; your own and threat cues are never
  stolen; no doubled predicted sounds.

### A6 — Mix and accessibility (S–M)
- Snapshots and loudness targets (§4.11), settings and accessibility (§4.12).
- **Exit:** settings persist; mono and night-mode work; directional indicators match sound sources.

---

## 6. Decisions needed

1. **[?] Runtime:** A (FMOD + Steam Audio, recommended), B (Wwise + Steam Audio), or C (own runtime +
   Steam Audio).
2. **[?] Who makes sound:** a sound designer (contract/hire) or programmer-driven? This weighs heavily
   on 1: authoring tools only pay off with someone authoring.
3. **[?] Platforms:** PC only (macOS + Windows), or consoles later? Consoles change the licensing and
   the certification work.
4. **[P] Listener:** player position, camera-yaw orientation (§4.1).
5. **[P] Acoustics scope:** zones → baked chunk reverb → real-time reflections only in instances (§4.4).
6. **[?] Interim audio** for the backend swap (§7): port `snd` to miniaudio briefly, or keep raylib's
   audio linked until A1.

---

## 7. Relationship to the backend swap

The backend swap ([`BACKEND_SWAP_PLAN.md`](BACKEND_SWAP_PLAN.md)) removes raylib, but `src/snd`
still uses raylib's audio module. Two ways through:

- **[P] Interim port (S, 1–2 days):** reimplement `snd`'s 20 procedures on miniaudio's high-level
  engine (`vendor:miniaudio`, the same library raylib's audio wraps). Behaviour is unchanged, and
  raylib can be deleted on schedule. A1 replaces it later.
- **Keep raylib's audio linked until A1.** No throwaway work, but raylib stays in the binary next to
  sokol (its bundled GLFW and GL loader must not clash) and the swap's exit criterion slips.

The interim port is recommended unless A1 is scheduled right after the swap.

---

## 8. Risks

| Risk | Phase | Mitigation |
|---|---|---|
| Licence terms change or don't fit a live MMO | A0/A1 | `snd` facade; confirm current terms, consider the GaaS-type licences; C stays possible |
| HRTF CPU cost at crowd scale | A2/A5 | tier 1 cap, virtualization, measured in A0 |
| Occlusion rays against a large overworld | A2 | rays only for tier 1–2 voices, low update rate for tier 2, grid DDA |
| Bake times for chunk reverb | A3 | bake in the editor per chunk, cache by chunk hash |
| Double sounds from prediction + replication | A5 | event ids and de-duplication (§4.10) |
| Audio leaking into the headless server | all | symbol ban in `test.sh` extended per runtime |
| No one to author content | all | decision 2 before A0 closes |

Sources for licensing and Steam Audio facts (checked 2026-11-17; confirm on vendor sites):
- [Steam Audio C API documentation](https://valvesoftware.github.io/steam-audio/doc/capi/index.html)
- [Valve releases all Steam Audio source under Apache 2.0 (Phoronix)](https://www.phoronix.com/news/Steam-Audio-SDK-Fully-Open)
- [ValveSoftware/steam-audio releases](https://github.com/ValveSoftware/steam-audio/releases)
- [FMOD Studio free for small developers (Game Developer)](https://www.gamedeveloper.com/audio/small-developers-and-creators-can-now-use-fmod-studio-for-free)
- [CRI ADX vs Wwise vs FMOD Studio, 2026 pricing (DEV Community)](https://dev.to/gamedevtoollab/where-unity-audio-reaches-its-limits-cri-adx-vs-wwise-vs-fmod-studio-1m4f)
- [Free Wwise Indie License (Audiokinetic)](https://www.audiokinetic.com/en/blog/free-wwise-indie-license/)
