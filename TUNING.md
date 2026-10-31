# TUNING

Source carries no comments. Every rationale that would have been a comment lives here.

## Submission setup (2026-10-31)

The default build uses the MIT-authorized, hashed clockwork snapshot in
`deps/clockwork-ecs` and project-owned microui adapters in `ui/`. The original
clockwork UI packages were unavailable in the supplied source. Odin is pinned to
dev-2026-10 revision 84bc3fc; the file I/O wrappers preserve the game's boolean
success interface over the compiler's error-returning OS API. Scripts use lld
because the toolchain's default radlink crashed on this project's debug link.

Steam transport is opt-in through `STEAM_ENABLED` and an external `steam`
collection. The default collection is empty and the session entry points return
failure without claiming to host or connect. Existing Steam integration notes
below describe the optional private configuration, not bundled submission files.

Host snapshots must contain their complete declared entity list and all four
ability states before replacing the previous snapshot. The new truncation test
demonstrated that accepting partial packets previously cleared valid entity
state and marked an incomplete snapshot as available. Oversized entity counts
are rejected before allocation or mutation.

`test.ps1` covers that regression, protocol boundaries, projection speed, AI
navigation and clockwork invariants. See `docs/SETUP.md` and `docs/STEAMWORKS.md`.

---

## Movement and screen-space projection

### Do not normalize `screen_dir_to_world_dir`'s result

The engine runs a 2:1 iso projection: `world_to_iso_xy(wx,wy) = (wx-wy, (wx+wy)*0.5)`. Movement
input is normalized in **screen space**, then converted through the exact inverse
(`iso_to_world_xy`) to a world-space direction. Because the round trip back to screen preserves
that unit length, on-screen speed comes out identical in all eight directions — which is what the
player actually reads as "constant move speed."

The world-space magnitude of that same vector legitimately varies by direction — 1.414 up/down,
0.707 left/right, 1.118 diagonal — because the projection is anisotropic. That is not a bug.
Normalizing in world space instead makes world speed constant and on-screen speed vary 2x, so W/S
visibly crawls next to A/D. This exact regression happened once already: "fixing" the perceived
diagonal speed-up by normalizing world space broke vertical movement, and the real fix was to
leave the screen-space normalization alone and fix footstep cadence instead (below).

Anything that wants **perceived** distance — footstep cadence, screen-facing, dodge direction —
must measure in iso/screen space, not world space. `facing_system` and the dodge system both
derive `screen_x = wx - wy` for exactly this reason: art faces screen-left unflipped, so sprites
flip when screen-x goes negative, and a dodge is a backward horizontal screen-dash regardless of
which world-space direction that maps to.

### Footstep cadence is measured in iso screen space

Footsteps are driven by distance travelled, not animation frames — cadence then tracks actual
speed for free and needs no per-skin frame tuning (walk clips differ per sprite, and two of the
player skins have no anim def at all). Distance is accumulated in iso screen space, not world
space, for the same reason as above: world-space distance varies by direction under the 2:1
projection, so a world-space accumulator makes the cadence pump when you turn even though the
character hasn't sped up.

The stride length comes from the character, not taste: the sheriff's art is 389 of its 512
frame-row pixels tall, which at `world_size` 210 is ~160 iso px on screen; a human stride runs
about 0.75x height → ~120. Against the 240 iso px/s base `MOVE_SPEED` that's 2.0 footfalls/sec, a
walk. Raise the stride constant to slow the patter (140 → 1.7/s, 160 → 1.5/s), lower it to speed
up (100 → 2.4/s, 78 → 3.1/s); the manifest's `min_interval_ms` is the hard floor underneath it.

---

## Shadows

### The player has one shadow: a projected silhouette, no contact blob

`draw_player_projected_shadow` shears the player's *current sprite frame* onto the ground plane
along the sun vector — there is no separate blob shadow layered underneath. Other entities still
get the older blob-style shadow via `draw_entity_sprite_shadows`.

### Shadows pin to where the art meets the ground, not to the authored anchor

The authored anchor does not agree with the art on any player skin — the sheriff's sits 43px
above her boots, and the other three skins have no anim def at all so they fall back to the frame
bottom, which sits below the soles. Pinning the shadow to the anchor leaves a visible gap either
way, which reads as the character floating.

`sprite_ground_fraction` finds the real ground line instead, by scanning each skin's first frame
alpha from the bottom up and caching the result per sprite stem. Sprite *placement* still uses the
authored anchor — nothing moves on screen — only the shadow's attachment point changes.

### A flat shear splays the back leg; the fix is a biased curve, not more geometry

`_shadow_offset`'s `SHADOW_FOOT_BIAS` curve exists because a flat linear shear treats "higher in
the sprite frame" as "higher off the ground" — but in an iso billboard, vertical screen position
mixes height *and* depth. A walk cycle's trailing foot sits well above the planted one in the
frame, so a flat shear pushes it much further along the sun vector than the planted foot, and the
two feet visibly split apart. Biasing the curve (`pow(t, SHADOW_FOOT_BIAS)`) pulls low rows in
toward the feet while leaving the head at full stretch, so the legs stay together and only the
body leans.

### Shadow quad winding is chosen per-draw, never via global cull state

Corner order for the shadow quad must match raylib's batch winding or the batch culls it
silently. The shear flips that winding when the sun crosses the horizontal, so the order is
picked from `sign(iso_d.y)` on every draw rather than toggling `EnableBackfaceCulling` /
`DisableBackfaceCulling` around the call. GL state changes apply immediately, but the raylib batch
doesn't flush until later — so a toggle-around-the-call pattern silently does nothing, and the
quad renders (or doesn't) according to whatever culling state was left by something else entirely.
Cost an afternoon to find; don't reintroduce it.

---

## Editor

### Entities replaced twelve typed arrays as the level's content model

Doors, switches, containers, lore items, phonographs, key pickups, barrels, NPCs and more used to
be separate typed arrays (`LevelDoor`, `LevelContainer`, ...), each hand-special-cased three times
over: once in the 39-member `EditorBrush` enum, once in `editor_inspector.odin`'s widgets, once in
`level.odin`'s binary read/write blocks. A door spawned from a def used to be an inert sprite —
everything that made it *function* as a door was bolted on afterward by `level_apply`.

`LevelEntity` + `FieldOverride` collapses this to one record type: instantiate the def, place it,
replay text overrides through the reflection layer (`cw.field_set_text`). Overrides are stored as
text on purpose — the reflection layer round-trips floats/ints/bools/enums/array elements through
it already, so a level can carry values for components that didn't exist when the level format was
written, and the file stays greppable. Format bumped to v15; the v14 reader is kept as a one-way
importer that runs transparently on first load.

Migrating one content type off the old model (doors, 2026-08-19) is the reference shape for the
rest: derive whatever the typed record used to carry (blocked tile, in doors' case) from the live
entity's own components instead of a parallel record, so entity-placed instances and
gizmo-moved instances behave identically.

### Override capture snapshots at selection, not at a clean respawn

Diffing a selected entity against a *fresh* `spawn_from_def` of the same def does not work: post-
spawn passes (`door_init_blockers`, `hub_apply`, `level_apply`) legitimately mutate entities after
spawn, so those mutations show up as false "authored" overrides, and any component added after
spawn (e.g. `Lockable` on a door) is simply missing from the comparison baseline. Edit mode pauses
the simulation, so between selection and capture the only thing that can touch the entity is the
user — snapshotting at selection time isolates exactly the user's edits and nothing else.

### The gizmo must move the live entity, not just the authored record

Dragging a gizmo writes the new position onto the *authored* `LevelEntity.position`. If the live
spawned entity is left where it was, the drag is invisible (nothing on screen moved), and worse:
`ed_entity_capture` — which runs on mouse release — copies the live entity's transform back onto
the authored record, silently undoing the entire drag. The gizmo update must write both: the
authored position for persistence, and the live entity's `Transform` for what capture reads back.

### `LevelEntity.live_id` must default to `INVALID_ENTITY`, never zero

A zero default aliases entity id 0. If entity 0 happens to be alive, `ed_entity_capture` reads
*that* entity's transform and stamps it over the newly authored record's position — a data-loss
bug that looks like "the editor moved my new entity to the origin" with no gizmo interaction at
all. `level_entity_add` sets `live_id = INVALID_ENTITY` explicitly for this reason.

### Gizmo drag axes are the world axes, not screen x/y

In an iso view, "up" on screen is not a world axis, so dragging along screen x/y would fight the
grid. `world_to_iso_xy` and `iso_to_world_xy` are exact inverses, so screen-space mouse deltas
convert back to world space with no accumulated drift — the gizmo's world-X and world-Y handles
are literally `world_to_iso_xy({1,0})` and `world_to_iso_xy({0,1})` as screen directions.

### The hub grid overlay is screen-pixel bounded, not grid-size bounded

At large grid sizes (200×200 cells) the naive per-cell draw is ~640k map lookups a frame
regardless of zoom — unusable well before it's even visible as detail. The fill now samples at a
step size derived from screen pixels per cell (`ceil(4 / (cell_size * zoom))`), so cost is bounded
by what's visually distinguishable on screen, not by how many cells exist. Verified this collapses
a 426ms/frame worst case to ~2–8ms across the full zoom range; see the grid-visibility toggle
(`g_ed_grid_visible`, `G` key) for turning the whole overlay off at cost-critical moments.

### Grid lines are spanning lines, not per-cell quads

`world_to_iso_xy` is affine, so an entire row or column of grid cells draws as one straight
screen-space line. The line/fill code walks rows and columns as runs (of existing tiles, for the
sparse non-hub grid; of matching color, for the hub fill) rather than one draw call per cell —
this is what makes the grid viewer usable at high cell counts instead of just fast at low ones.

### `cam_lims` was authored data with no reader (fixed 2026-08-20)

`g_level_data.cam_lims` (`[4]f32`: left/right/top/lower) has been editable in the "Grid & Camera"
panel and round-tripped through the binary format since the format existed — but nothing ever read
it back. `camera_follow_system` called `camera_set_target_world` directly with the raw player
position every tick; the four numbers just sat in the level file unused.

`g_camera.target` (and everything drawn inside its `BeginMode2D` block) lives in **iso space**,
not world space — `camera_set_target_world` itself runs every position through `world_to_iso_xy`
before assigning it, and `Camera2D` has no rotation, so from the camera's own point of view it is
just an ordinary axis-aligned rect over whatever space its `target` is expressed in. The first cut
of this fix clamped the pre-projection world `(wx, wy)` instead, which does bound the camera, but
the box that traces out is a diamond on screen (a world-space rectangle skewed by the same 2:1
projection everything else here goes through) — no good for a "plain rect" limit. Fixed by
projecting first and clamping the resulting `iso.x`/`iso.y` against `cam_lims` directly, so the
box the four sliders describe is an ordinary axis-aligned rectangle in the same space the camera
itself treats as a plain rect. `min < max` still gates each axis independently, so a level with the
untouched `{0,0,0,0}` default (min == max on both axes) clamps nothing.

The editor draws the matching outline in `draw_editor_world` — plain `{minx,miny}`/`{maxx,maxy}`
corners with no `world_to_iso_xy` transform, since `cam_lims` already lives in the same space the
rest of that function's draw calls land in after their own projection. Each axis draws
independently (`has_x`/`has_y`), falling back to a wide `±8192` span on whichever axis isn't set,
so a level with only one axis configured still shows two long bound lines instead of nothing — the
box only fails to appear when *both* axes are still at their `0,0` default. The editor's own
free-fly camera is unaffected (`camera_follow_system` early-returns whenever `g_editor_mode` is
true) — a level designer needs to be able to pan outside the play area to build and inspect content
beyond it; the clamp only ever applies to the real gameplay follow-camera.

### The clamp bounds the camera's *target* (center), not its visible edge — account for the half-viewport gap

The first cut of the iso-space clamp above bounded `g_camera.target` directly against `cam_lims`,
which bounds where the **center** of the screen can go, not where the **edge** of the screen stops.
Since `Camera2D.offset` is screen-center, the actual visible edge of the screen can still travel up
to half a viewport's worth of iso space past whatever line is drawn — so the drawn box and the
point where scrolling visibly stops disagreed by that gap, which is exactly what made the box hard
to place by eye. Fixed by insetting the clamp range itself by the half-viewport extent
(`(screen_width/2) / zoom` on X, same with height on Y) before clamping `iso.x`/`iso.y`, so the
*edge* of what the camera shows now lines up with the drawn box, not just its center. If the box is
narrower than the current viewport on an axis (inset range inverts, `lo > hi`), that axis' target
snaps to the box's midpoint instead of clamping — the alternative (an empty/inverted clamp range)
would either not bound anything or jitter at the inversion point, and this at least degrades to
"camera is centered but can't move on that axis" rather than either of those.

---

## Level format (binary, `level.odin`)

### Bound version checks against `LEVEL_VERSION`, never a literal

`if ver > 13` written by hand and left unbumped when `LEVEL_VERSION` moved to 14 silently wiped
every level saved by the newer build on next load — the check has to read `if ver > LEVEL_VERSION`
so a version bump can never leave a stale ceiling behind again.

### New per-version fields must be read behind a version gate even mid-block

`sun_elevation` was appended at the end of the v14 lighting block, but the lighting block is *not*
the last thing in the file — barrels and level objects follow it. Reading the new field
unconditionally would, on a v13 level, consume the barrel count as if it were `sun_elevation` and
corrupt every field after it. The reader gates the read on `ver >= 14` for exactly this reason;
any future mid-block addition needs the same treatment, not just fields appended at file end.

### Pre-v6 tile encoding predates Oil/Fire overlays and the extra Pillar/Floor variants

Versions before 6 packed Oil and Fire as tile-type bytes 4 and 5 directly in the tilemap, because
the overlay map didn't exist yet, and the Pillar/Floor art variants postdate that era too. The
reader still special-cases this range; it is legacy decoding, not a bug.

### Retiring a version-gated block must still consume its bytes, or convert them — never just delete

The reader is one sequential pass with a shared cursor (`cur`), so every block's byte length is
load-bearing for every block that comes after it in the file, for as long as any level on disk was
written before that block was retired. When doors were first migrated off the typed-array model,
the door-reading block (count-prefix + N fixed-size records, sitting between overlays and
switches) was deleted outright instead of being replaced with an equivalent-length skip or an
importer. The two existing level files are both older than that migration, so on their next load
every field read after doors — switches, containers, lore items, phonographs, key pickups —
silently came from the wrong byte offset. It did not crash; `lv_rb1`/`lv_rbi16`/etc. all have
`ok`-returning failure modes that quietly stop appending rather than panic, so the corruption
surfaced as **lost data**, not an error: the hub's level file round-tripped through a save during
unrelated editor testing and its 13 authored containers, along with everything the misaligned read
touched, were gone from disk. (Recovered from `tools/gen_level00.py`'s literal data, which is the
one ground truth for that level's original layout, since there is no version control on this
project to fall back on.)

The fix, and the pattern for retiring the next block (switches, containers, lore items,
phonographs, key pickups): keep the old read code exactly where it was, in the same version range,
consuming the same bytes — but instead of populating the old typed array, convert each record into
a `LevelEntity` and hold the converted records in a local list. Do **not** call
`level_entity_add`/`level_entity_set_override` at the read site itself: `level_entities_clear()`
runs later in the same function (right before the modules block, unconditionally, regardless of
version), and anything appended before that point is wiped a few lines later. Replay the held
records into `LevelEntity` form *after* that clear call instead.

### Spawns, exits, lights and player-start are fully entity-based; `LEVEL_VERSION` is 16 because of it

These four were first migrated the safe way — typed array kept alive, consumers reading both the
array and the new entity marker — right after the door byte-alignment bug above was found, because
retiring three more binary blocks under that same time pressure was judged too risky. Once both
existing level files were deliberately discarded (no authored content left to protect locally),
that caution became unnecessary and they got the same full-retirement treatment doors did:
`SpawnPoint`, `LevelExit` (the typed struct) and `LevelLight` are gone; `g_level_data` no longer
carries a `spawns`/`exits`/`lights`/`player_start` field at all. The equivalent entities
(`.SpawnAnchor`, `.LevelExit`, `.PointLight` via `level_light`, `.PlayerStart`) are the only source
from here on — `spawn_director`'s anchor picker, `level_exit_system`, `level_spawn_extraction_zones`
and `spawn_players` all read ECS queries exclusively, no fallback array.

**`LEVEL_VERSION` bumped 15 → 16 for this, and that bump is load-bearing, not decorative.** A build
already shipped as a zip before this cleanup, at format v15, with the *old* dual-path layout: tiles,
then spawns, exits, player_start, npcs, lights — as real typed-array sections — *in addition to* the
`LevelEntity` list at the end. If the reader had simply stopped reading those sections without a
version change, any file saved by that already-shipped build would misparse exactly like the door
bug did — same failure mode, this time potentially on a machine this codebase can't inspect. The
version bump makes the two v15 shapes distinguishable from v16 by number: `ver < 16` still reads and
converts the legacy sections (into `LevelEntity` records, same held-and-replayed-after-clear pattern
as doors — see `_LegacySpawn`/`_LegacyExit`/`_LegacyLight`), `ver >= 15` still reads the native
entity list (both conditions overlap at exactly 15, which is correct: a v15 file has *both* legacy
sections and a native entity list, and both need reading). The writer only ever emits v16. Verified
by hand-constructing a byte-exact v15 file matching that old dual-path layout and confirming every
legacy section imports into the right entity with the right overrides — this is the only reader path
in the file with no real level to test it against, so it stays worth re-verifying this way if it's
touched again.

The original one-time immediate-spawn behavior — `level_apply` used to spawn one `enemy_spider` on
top of every old-style spawn point the moment a level loaded, separately from whatever
`spawn_director` did later — was dropped rather than ported. `.SpawnAnchor` entities are anchors
only now, matching what `spawn_director`'s picker already treated them as; reintroducing an
immediate per-anchor spawn on `level_apply` would be new behavior, not a migration of old behavior,
and nothing depended on it once the director's own periodic spawning is the actual spawn path.

---

## Greybox

### Greybox art is procedural on purpose — authored art would bake in the iso mismatch

The tile art measures 0.537 (height/width of its ground diamond) against the engine's own 2:1
(0.500) projection — roughly a 2.4° pitch difference between what the art was drawn at and what
`world_to_iso_xy` actually does. Blockout volumes are drawn straight from `world_to_iso_xy`
instead of from authored sprites, so they agree with the engine's ground plane *by construction*
and can never inherit that mismatch. Height is a pure screen-space lift: a point `h` world units
above the floor at `(wx,wy)` draws at `world_to_iso_xy(wx,wy) - (0, h * GREYBOX_Z)`, the same
convention the sprite billboards use. Faces are shaded by orientation (top brightest, walls
progressively darker) so massing reads with no lighting pass.

### Greybox collision reuses the tile pushout, and must stay deterministic

The greybox footprint is a world-axis-aligned box — the same shape `wall_collision_system`
already resolves against tiles — so `greybox_collision_system` reuses that exact circle-vs-AABB
push-out rather than inventing a second collision response. This runs inside the simulation, so it
must stay lockstep-deterministic: both entity queries return ids in ascending order and the
resolution is pure arithmetic, so both peers always agree without needing to exchange anything.

---

## Audio

### Ambience runs on two independent crossfade channels, not one

`play_ambience` (the weather bed — wind, storm) and `play_ambience_bed` (a location bed —
industrial hum) need to run simultaneously, and a single crossfade channel can only hold one
active track. They're deliberately separate channels rather than one channel with a priority rule.

### Alias voice stealing only takes a *strictly* lower-priority voice

Freeing a global alias slot prefers an idle voice anywhere; failing that, it steals the
lowest-priority currently-playing voice — but only if that voice is strictly less important than
the incoming sound. A sound that can't beat anything currently playing simply doesn't play, rather
than displacing something of equal importance.

### Manifest hot-reload keeps existing alias pools; only new variant paths pool lazily

Reloading `audio.json` at runtime rebuilds the event registry, but existing alias pools and
loaded sources are reused rather than torn down — only sound variants newly added to the manifest
pool in on their first play after reload.

### `play_sfx` vs `play_sfx_at` decides who can hear it in co-op — not the manifest alone (2026-08-21)

`play_sfx(name)` plays at full volume everywhere, no matter where in the level it happened or
where the listener is — `_audio_play`'s `has_pos` is `false`, so `_spatial` never runs regardless
of what the event's own `spatial`/`rolloff`/`outer` fields say. `play_sfx_at(name, pos)` is the
only thing that actually applies distance falloff. This matters a lot more than it used to: once
`HostOnly` systems started correctly running for every connected player (see the netcode section),
sounds that fire for *any* player's actions — not just the local one — either need `play_sfx_at`
with a real position, or they'll blast at full volume for every other player regardless of
distance, which is what `env_interaction_system`'s door/lever/chest/lore/key sounds were doing:
all `play_sfx`, so a door opening across the map sounded identical to one at your feet, for every
connected player. Fixed by capturing `target_id`'s position once at the top of
`dispatch_interaction` and switching every call in that function to `play_sfx_at`. None of these
events are in `audio.json`, so they fall through to `_register_default_event`'s auto-registration
default (`spatial = true, rolloff = .Linear`, `outer` falling back to `SPATIAL_FALLOFF_RADIUS`) —
no manifest changes needed, the code side was the entire gap.

### Footsteps were computed for `w.player_id` only — not muted for other players, never generated for them

`tick_footsteps` tracked a single set of file-private globals (`g_step_accum`, `g_step_last_pos`,
`g_step_primed`) keyed to nothing but `w.player_id`, and called `play_sfx("step")` — no position,
and the `"step"` manifest entry itself was `"spatial": false` on top of that, so even a `play_sfx_at`
call wouldn't have carried distance falloff without also touching the manifest. Fixed both:
`tick_footsteps` now loops `for slot in 0..<MAX_PLAYERS` with all three step-tracking globals
turned into `[MAX_PLAYERS]` arrays (cadence — the accumulated iso-space distance since the last
footfall — is independent per player, same reasoning as everything else in this project that's
per-slot), and calls `play_sfx_at("step", p)` using the mover's real world position. `audio.json`'s
`"step"` entry is now `"spatial": true, "rolloff": "linear", "outer": 400` — a shorter falloff
radius than combat sounds (`enemy_shoot`/`pistol_shot` use 700–800) since footsteps are a quiet,
close-range sound in the first place; picked as a reasonable first pass, not deeply playtested.
Playing the *local* player's own footsteps through the same positional call works out correctly
for free: `g_listener_pos` is the local player's own position, so `dist ≈ 0` against their own feet
and the linear rolloff already returns full volume there — no local/remote special case needed.

### Ability sounds went positional too, once footsteps and interactions had (2026-08-21)

`ability_system`'s ~19 `play_sfx` call sites (`shoot`, `melee_hit`, `ability_fan`,
`ability_quickdraw`, `levelup`, `reload`) were all non-positional, same gap as footsteps and
interactions above — audible to every connected player (correct, since ability activation is a
world event like a door opening or a gunshot), but at full volume regardless of distance. All
switched to `play_sfx_at`. The position used depends on where in the file the call lives: the two
call sites inside `ability_spawn_projectile`/`ability_blast_aoe`/`ability_blast_cone` already had
their own local `origin` (the muzzle point or the caster's transform, computed for the damage math
those functions do anyway), so those pass `origin`; everything else lives inside
`_ability_tick_player` where `t_snap` (the acting player's own transform snapshot, already read
once at the top of that function for the ability logic itself) was already in scope, so those pass
`t_snap.position`. None of these six event names are in `audio.json`, so — same as the interaction
sounds — they fall through to `_register_default_event`'s `spatial = true` default with no manifest
changes needed.

**Deliberately left alone:** `play_sfx("no_energy")` (`ability_system.odin`), already gated
`if id == w.player_id` from the earlier multiplayer-correctness pass. It's personal feedback about
*your own* resource pool, not a world event — hearing it for a teammate's energy shortage would be
actively misleading, not just imprecise, so it stays local-only and non-positional on purpose. Same
category as `weapon_system`'s `reload_start`/`reload_done`/`empty_click`, which were never touched
here either.

---

## Netcode: host-authoritative + client prediction (replaced lockstep 2026-08-20)

### Why lockstep was replaced

Lockstep required both peers to compute bit-identical simulation state every tick, buffered input
`INPUT_DELAY` (2) ticks ahead and **stalled** — both peers frozen — whenever either side's input
for the current tick hadn't arrived yet. That put a fixed 33ms floor under every input regardless
of actual connection quality, and it meant *any* system that behaved even slightly differently
between the two peers (float rounding, iteration order, an uninitialized field) was a permanent,
silent desync with no correction mechanism — see the Steamworks packed-struct alignment bug this
project has already been bitten by once. Host-authoritative + client-side prediction (the model
`signal-hunt` uses, and what `clockwork-ecs`'s `predict.odin`/`interp.odin`/`transport.odin` were
already built for — proven there, sitting unused in this project until now) trades that fixed
floor for: the host is the sole source of truth, a client predicts *only its own player* locally
for immediate response, and a wrong prediction is corrected by replaying the client's own
still-pending inputs on top of the host's authoritative snapshot — a smooth catch-up, not a
freeze. Every other system only needs to be host-correct, not peer-identical.

### System `Authority` is the whole model: `Shared` predicts, `HostOnly` doesn't exist on the client

`sim_register_system` takes an `Authority` (`.Shared` or `.HostOnly`, default `.Shared`).
`Simulation.role` (`Standalone` / `Host` / `Client`) decides what actually runs:
`sim_broadcast` skips every `HostOnly` system when `role == .Client`. `Standalone` (single-player)
runs everything — this is the safety property the whole migration leans on: a game with no
network session behaves exactly as it always did, because nothing about "is this authority tag
respected" changes unless a client role is actually active.

**That safety property had a hole: nothing ever set `g_sim.role` to `.Client` (fixed
2026-08-20).** `Simulation.role` defaults to `.Standalone` (`make_simulation`), and `init_game()`
never assigned it — `w.local_player_slot = g_session.local_slot` was set, but the parallel
`g_sim.role` assignment was simply missing. `sim_broadcast`'s check is `run_host_only := s.role !=
.Client`, which is true for *both* `.Standalone` and `.Host` — so on an actual client, every
`HostOnly` system (`weapon_system`, `ai_system`, `damage_system`, `pickup_system`,
`spawn_director_system`, all of it) ran locally every tick exactly as if the client were
standalone, `sim_tick_predicted`'s replay-during-reconciliation included. The reported symptom was
specifically weapon fire — the client's own locally-run `weapon_system` was spawning real,
immediately-rendered projectiles on every predicted *and* replayed tick, on top of whatever the
host's authoritative fire produced and broadcast as a shadow projectile — but the same hole meant
every other `HostOnly` system was silently double-simulating on the client too, just less visibly
than "too many bullets." Fixed in `init_game()` (`main.odin`), right next to the
`local_player_slot` assignment: `.Standalone` if offline, `.Client` if online and
`local_slot == 1`, `.Host` otherwise — the same condition `do_sim_tick` already used to route
between `netcode_host_tick`/`netcode_client_tick`, just never mirrored onto `g_sim.role` itself.

The split: `player_input`, `dodge`, `animation`, `facing`, `stats`, `wall_collision`,
`greybox_collision`, `entity_separation`, `camera_follow`, and the base `movement_system` are
`Shared` — cheap, local-input-driven, safe to run without seeing the rest of the game's state.
Everything that deals damage, spawns something, grants loot, or advances progression —
`weapon_system`, `ai_system`, `spawn_director_system`, `damage_system`, `pickup_system`,
`extraction_system`, `projectile_system`, and the rest of combat/economy — is `HostOnly`. A client
never runs these; it only ever sees their *results* as snapshot data. This is a coarse first pass,
not a final audit — `ability_system`, `mutation_effects_system`, and `env_interaction_system`
landed `HostOnly` for safety (they gate combat-relevant stats or loot) at the cost of those actions
feeling networked-laggy for whoever presses the button; splitting out a `Shared` cosmetic-only
echo for any of them (matching how weapon fire is handled, below) is a deliberate, not-yet-done
follow-up, one system at a time, the same way doors/spawns/exits/lights got migrated off the
typed-array level format earlier.

### There is no separate prediction world — the predicted entity lives in the same world it renders from

The obvious design (mirroring `signal-hunt`'s `PredictState`) is a second, minimal `World`
containing only the local player, predicted in isolation and blended into the render world each
frame. Tormentas doesn't do that: `cw.Predictor`'s `apply`/`restore`/`read_pos` callbacks
(`netcode_predict_apply` etc. in `netcode.odin`) ignore the `^ecs.World` parameter the predictor
hands them and operate on the global `g_sim` directly, because there is exactly one client
simulation and it always is `g_sim`. `apply` calls `sim_tick_predicted` — `EarlyUpdate`/`Update`/
`LateUpdate` with no entity-lifecycle sweep — so replaying several pending inputs during
reconciliation never triggers entity creation/destruction as a side effect of speculative replay.
The predicted entity is a real entity in the real render world the whole time, so every existing
renderer, HUD, and inspector reads it with zero special-casing; the cost is that `Shared` systems
also nominally run against the *other* (host-authoritative) player slot every client tick using
whatever input was last received for it, which is harmless because the incoming host snapshot
overwrites that slot's `Transform`/`Velocity` immediately afterward regardless — the remote
player's occasional snapshot pop-correction was never going to be smoothly reconciled the way the
local player's is, so there's nothing to protect there.

### Non-player, non-predicted entities are shadow entities, not real simulation

Enemies and projectiles are `HostOnly`-simulated; the client never has a real one. What it has
instead are shadow entities keyed by `wire_id` (the host's own entity id, reused as-is — no
separate id allocator) in `g_shadow_map`: created the first time a `wire_id` appears in a host
snapshot, `Transform`/`Velocity`/`Health` overwritten directly on every snapshot after that, and
destroyed the moment a snapshot arrives without that `wire_id` in it. This is deliberately *not*
smoothed with `cw.Interpolator` yet — every snapshot hard-sets position, so entities currently pop
rather than glide between updates. `cw.Interpolator($T)` is generic and ready for this; wiring it
in per shadow entity is the natural next pass once the core loop is proven over a real connection.
Shadow enemies default to the `enemy_spider` def for their visual, matching `spawn_director`'s own
roster today — the roster has exactly one entry, so this is not yet a real simplification, but
`SyncEntity` will need an archetype field the day a second enemy type ships. Shadow projectiles
are *not* spawned from an entity def at all (nothing in `entities.json` describes a projectile —
they're built directly in code with a `Projectile` + `ProjectileTag` pair, matching how the host
constructs real ones) purely so `draw_tracer` has `direction`/`speed` to read; nothing ever ticks
them locally since `projectile_system` is `HostOnly`.

### The reflection inspector's lockstep-era write gate no longer matches the model

`debug_inspector.odin` still refuses to write whenever `p2p.session_is_online` is true, carried
over unchanged from the lockstep era where *any* online edit was an unreplicated, desyncing
mutation with no correction path. That reasoning doesn't hold anymore: on the **host**, an
inspector edit *is* now authoritative and would simply reach the client on the next snapshot like
any other host-side state change, so the gate is stricter than it needs to be there. On the
**client**, editing a `HostOnly`-simulated entity is still pointless (overwritten by the next
snapshot) and editing the predicted player entity would fight reconciliation — so the gate is
still *right* for clients, just not for hosts. Left as-is rather than changed in this pass; the
fix is `p2p.session_is_online(&g_session) && g_session.local_slot == 1` instead of
`session_is_online` alone.

### Catching up more than `MAX_CATCHUP_TICKS` drops the backlog instead of chasing it

A long frame (stall, GC pause, alt-tab) can leave several ticks' worth of accumulated time. Running
all of them in one frame to "catch up" risks that frame taking even longer, which schedules an
even bigger catch-up next time — a spiral of death. Capping catch-up ticks per frame and dropping
any remaining backlog trades a visible hitch for the alternative of the game locking up entirely.

### `DISCONNECT_TIMEOUT`'s no-receive timer clamps its per-poll `dt`, for the same reason `MAX_CATCHUP_TICKS` exists

`session_poll` (`p2p/session.odin`) drains every queued message first (each one resets
`no_recv_timer = 0`) and only *then* adds the frame's `dt` to it, disconnecting once it reaches
`DISCONNECT_TIMEOUT` (6s). That ordering is correct for genuine silence, but it has the same
spiral-of-death shape as the sim accumulator above: a single stalled frame — a GC pause, a
breakpoint, or (concretely hit while testing two `hostlocal`/`joinlocal` windows locally) Windows
deprioritizing an unfocused window's message pump — reports one huge `dt` on the frame it resumes.
Even though the peer was sending the entire time and those messages get drained (and reset the
timer) in that same call, the raw `dt` added right after can, by itself, already exceed 6 seconds
— an instant false-positive disconnect that has nothing to do with the peer actually going silent.
`MAX_DISCONNECT_STEP` (0.5s) caps what a single `session_poll` call can add to `no_recv_timer`,
mirroring `MAX_CATCHUP_TICKS`'s "cap the damage from one bad frame" fix — a real 6-second silence
still disconnects (it just takes at least ~12 polls to accumulate, which happens immediately once
polling resumes), but one resume-from-a-stall frame can no longer manufacture a fake one. Verified
by suspending one loopback process for 9 real seconds and resuming it: the *other* side correctly
timed out the genuinely-silent peer at ~6s and sent it a clean `ClosedByPeer`, while the resumed
process itself no longer self-reported a spurious "peer timed out" from its own catch-up burst.

### Steam lobby data is not readable until *after* the join completes

Accepting an invite only tells the game *which* lobby to join — `host_id` and the rest of the
lobby's data are not valid until the client has actually entered it. The real join (and the code
that reads lobby data) is kicked off in the `LobbyEnter` callback, not at the point the invite is
accepted; reading lobby fields any earlier reads garbage.

### The Steamworks packed-struct alignment bug (found via loopback testing, fixed 2026-08-20)

`steamworks/steamworks.odin`'s vendored bindings declared `SteamNetConnectionInfo :: struct
#packed`. Its own interior field offsets are correct either way, but `#packed` also forces its
*own* alignment to 1, and `SteamNetConnectionStatusChangedCallback` embeds it right after a
`hConn: HSteamNetConnection` (a `u32`). The real SDK struct has natural alignment 8, so `info`
belongs at byte offset 8 inside the callback struct; packed to alignment 1, Odin placed it at
offset 4 instead, so every field read out of it — `eState`, `eOldState`, `hListenSocket` — was
read 4 bytes early from the wrong memory. The observed symptom was indistinguishable from
"callbacks never fire at all": every connection-status event decoded as `eState=None,
eOldState=None, hListenSocket=0xFFFFFFFF`, so `session_on_conn_changed`'s `.Connecting` case
(`ev.info.hListenSocket == s.listen_sock`) never matched and a host never accepted an incoming
connection — this affected the real Steam P2P host-accept path exactly the same way, it just
had no way to be exercised end-to-end before `hostlocal`/`joinlocal` made a real two-process
connection attempt possible. Confirmed live: two local `tormentas.exe hostlocal` /
`... joinlocal` processes hung forever pre-fix (host never logged "accepted incoming
connection"), and completed a full hello handshake + character-data exchange immediately after
dropping `#packed` from `SteamNetConnectionInfo` (fix mirrors the one already applied in
`signal-hunt`'s copy of these bindings — same struct, same bug, independently vendored).

### `hostlocal`/`joinlocal`: direct-IP loopback for testing host/client on one machine

Real Steam P2P (`session_host`/`session_join`, `ConnectP2P`/`CreateListenSocketP2P`) is
identity-based: it connects two `SteamNetworkingIdentity`s, and Steam won't let two processes
sharing the same Steam ID negotiate a P2P connection with each other — so the netcode above can
never be exercised by launching two copies of the game on one dev machine, only across two real
accounts. `session_host_loopback`/`session_join_loopback` (`p2p/session.odin`) sidestep identity
entirely and connect by IP instead (`CreateListenSocketIP`/`ConnectByIPAddress` against
127.0.0.1), which Steam allows without any identity or certificate handshake as long as
`IP_AllowWithoutAuth` is set — `_allow_unauthenticated_ip` sets it globally on the
`NetworkingUtils` interface before either call. This bypass is safe specifically *because* it's
loopback-only: it's never invoked on the real `session_host`/`session_join` path, so a real P2P
game between two different Steam accounts still gets full certificate auth. `boot_loopback_from_args`
(`main.odin`) dispatches on `os.args[1]` (`"hostlocal"` / `"joinlocal"`, optional port arg,
default `LOOPBACK_PORT :: 27600`) and — unlike `_on_black_join_invite`, which calls `init_game()`
before `p2p.session_join(...)` — calls the loopback session proc *first*: joining sets
`local_slot = 1` synchronously, and `init_game()` reads `local_slot` to decide which player the
client predicts, so it must already be correct by the time `init_game()` runs.

`boot_loopback_from_args` also does not call `init_game()` immediately after the loopback connect
call — it blocks in `_boot_wait_for_connection` (pumping `steam_run_callbacks`/`session_poll` at
~60Hz, up to `LOOPBACK_CONNECT_TIMEOUT`) until `p2p.session_is_online` is actually true first.
This matters because `spawn_players` (`level.odin`) decides how many player slots to create with
`slots_to_spawn := 2 if p2p.session_is_online(&g_session) else 1` — the real online flow only ever
reaches `init_game()` after `update_connecting` has already confirmed `session_is_online` (see
`main_menu.odin`'s `update_connecting`/`_on_black_start_online`), but `session_host_loopback`/
`session_join_loopback` return the instant the socket call is issued, long before the Steam
callback that actually flips the connection to `.Connected` fires. Calling `init_game()` too early
was caught live: both processes' `session_state` was still `.Hosting`/`.Connecting` at
`spawn_players` time, so both spawned only slot 0 — the joining client's own `player_id` (its
`local_player_slot` is 1) pointed at a slot that was never created, so it had no character at all.

### `spawn_players`'s slot count is a snapshot of `session_is_online` at that instant

More generally: anything that calls `init_game()` (or otherwise re-enters `spawn_players`) needs
`session_is_online` to already reflect the *final* peer count, because `spawn_players` reads it
once and never revisits the decision — there's no "a second player joined later, retroactively
spawn them into the already-created level" path here (that dynamic add-on-join case is handled
separately, only for the *already-in-hub* invite flow, via `hub.odin`'s `remote_slot` creation).
Any new caller of `init_game()` down the line should wait for the connection the same way
`boot_loopback_from_args` now does, not assume the session is ready just because the connect call
returned.

### Shadow entities interpolate through `cw.Interpolator`, keyed by `wire_id` (fixed 2026-08-20)

`_netcode_apply_snapshot` used to write a shadow entity's `Transform.position`/`rotation` directly
from whatever the latest snapshot said, so every new snapshot was a hard teleport — enemies and
projectiles popped between positions instead of gliding, most visible on anything that doesn't
move in a straight line. Fixed by giving each shadow entity its own `ecs.Interpolator(ShadowPose)`
in `g_shadow_interp` (keyed by `wire_id`, same key as `g_shadow_map`, created/destroyed alongside
it): `_netcode_apply_snapshot` now calls `interp_observe` instead of writing `Transform` directly,
and a new `netcode_interp_update` — called once per **rendered frame** from `main.odin`, after the
fixed-tick loop, not from inside `do_sim_tick` — blends `interp_blend`'s two bracketing samples and
writes the result into `Transform` last, every frame. Two things make this safe rather than
fighting the rest of the sim: it runs after `movement_system` (`Shared`, so it also nudges shadow
entities forward each tick using their last-known `Velocity` — harmless, since the interpolated
write below always overwrites it last, sim ticks and render frames don't share a rate here so this
has to be frame-keyed, not tick-keyed) and it uses `rl.GetTime()` wall-clock time rather than sim
tick time, which is what `Interpolator` needs to smooth over jitter in when snapshots actually
arrive rather than assuming they arrive exactly on the tick boundary. `Velocity` itself is still
written directly (unsmoothed) — it only feeds projectile tracer direction/speed and animation
state, neither of which needs the same treatment. Scoped to shadow entities only; the remote
player (handled separately in the same function, `e.kind == .Player`) still snaps directly on
reconciliation and is a separate, not-yet-done piece of this same idea.

### `ability_system` and `env_interaction_system` didn't just feel laggy on the client — they never ran for the client's player at all (fixed 2026-08-20)

Both systems opened with `id := w.player_id` (`env_interaction_system` via a `local_pid` alias) —
*this machine's own* local player, a single-player-era assumption nothing had corrected since the
host/client split landed. Since both are `HostOnly`, the only simulation that ever runs them is the
**host's**, and on the host `w.player_id` is the host's own slot, never the client's. Concretely:
the client could never activate an ability and could never open a door, loot a container, pull a
lever, read lore, play a phonograph, or pick up a key — not "laggy," **inert**, in every build since
the migration. This is a correctness bug the "revisit `HostOnly` for responsiveness" framing had
been quietly sitting on top of; found by re-reading these systems end to end rather than assuming
the `HostOnly` tag itself was the whole story. Fixed the same way as `pickup_system`/`damage_system`
already do it: loop `for slot in 0..<MAX_PLAYERS`, look up `w.player_ids[slot]`, skip invalid slots.
`ability_system`'s body became `_ability_tick_player(w, id, dt)`, a straight hoist of the old
single-player body with `id` now a parameter. `env_interaction_system`'s emitter/weight-plate scan
also picked up the same loop (a pressure plate now triggers off *either* player's proximity, not
just the host's).

Fixing the loop surfaced a second, narrower thing worth calling out: with both players now running
through the same code path on the host, non-positional personal-feedback sounds (`"no_energy"`)
would otherwise play for a remote player's own resource shortage, which is actively misleading —
gated that one behind `if id == w.player_id`. World-action sounds (`"shoot"`, `"door_open"`,
`"chest_open"`, …) were deliberately left ungated, matching `weapon_system`'s own precedent
(`play_sfx_at("pistol_shot", …)` already plays for both players, unconditionally) — you're supposed
to hear your co-op partner open a door.

`env_interaction_system` also gained a sibling, `env_interaction_focus_system` (`Shared`): the old
code computed `g_interact_focused_id` (the "press E" prompt target) as a side effect of the same
`HostOnly` walk, so the client never had one — no prompt ever appeared on their screen. The prompt
target is pure read-only distance math with no state mutation, so it was split into its own system
that runs identically on host and client, each computing *their own* local player's focus with zero
network delay. The `HostOnly` system no longer touches `g_interact_focused_id` at all; the `Shared`
system is now its sole owner, on both host and client.

**Still open, deliberately not attempted here:** the actual state change from an interaction —
door opened, chest looted, lever toggled — has no sync path back to the client at all. Every
interactable is spawned identically (same entity IDs) on both sides at level load via
`level_apply`/`hub_apply`, so unlike enemies there's no shadow-entity problem to solve, but nothing
currently tells the client's copy of that entity that its state changed on the host. `SyncEntity`
only covers `Player`/`Enemy`/`Projectile` kinds, not world objects. The client can now correctly
*trigger* an interaction (the host processes it), but won't *see* the result — the door stays
visually closed on their screen even though the host has it open. A generic entity-id-keyed field
sync (reusing `cw.field_set_text`, the same reflection mechanism `FieldOverride` replay and the
debug inspector already use) is the natural shape for this and is the next piece of this area to
build, not a redesign.

`ability_system` itself was left fully `HostOnly` beyond the loop fix — cooldown and energy state
are not part of the snapshot protocol at all, so a client-side cosmetic echo (an immediate sound on
key-press, ahead of the real activation) risks playing feedback for an ability that's actually
still on cooldown, which is worse than the current round-trip delay. That's the real prerequisite
for the "feels networked-laggy" half of this item — syncing cooldown/energy state — not something
to bolt on without it.

### `w.player_id`-only spawn placement, boss placement, and extraction proximity (fixed 2026-08-20)

The same single-player hardcoding found in `ability_system`/`env_interaction_system` above turned
up in three more places once the codebase was grepped for `w\.player_id\b` end to end:
`spawn_director.odin`'s `_director_pick_anchor` and `_find_boss_tile` picked enemy/boss spawn
points using distance to `w.player_id` only, and `extraction_system` (`level.odin`) checked only
`w.player_id`'s proximity to an extraction zone to start the extract timer. In co-op this meant
enemies and the boss could spawn on top of (or nowhere near) the client, and the client standing
in an extraction zone did nothing at all — only the host's own presence there counted.

Spawn/boss placement: extracted a shared `_min_player_dist2(w, x, y)` (loops `MAX_PLAYERS`, returns
the smallest squared distance to *any* valid player, `max(f32)` if none) and swapped both
functions' single-player distance checks for it. This is the correct generalization of a
"must be at least this far from the player(s)" constraint — the candidate now has to clear the
threshold against whichever player is closest, not one arbitrarily-chosen one.

Extraction: the proximity check now loops all player slots per extraction zone and starts the
timer if *any* player is standing in it, matching the same "any player" shape as the emitter/
weight-plate fix above. `on_player_extract`/`on_player_death` still keyed their reward banking off
`w.player_id` alone at the time this was written — rewards are per-player, not pooled, and that fix
landed the next day; see below.

### Raid rewards are per-player: a new `RaidResult` message, because the client's own save data isn't reachable from the host (fixed 2026-08-21)

`on_player_extract`/`on_player_death` now loop `for slot in 0..<MAX_PLAYERS` like everything else
in this section, reading each player's own `WalletComp.gold`/`MutationContainerComp.serums` off
their own entity (correct and authoritative on the host regardless of slot) and stripping/zeroing
each player's own entity on death/extract. Where it can't just be a loop, though: banking into
`local_stash()`, bumping `g_lifetime_stats`, and `save_player` are not per-*session-slot* state —
they're per-*local-machine* state (`local_stash() == &g_stash[g_session.local_slot]`,
`save_player` writes `g_char_save.slots[g_active_slot]`, `g_lifetime_stats` is a single global).
Those three already only ever mean "my own machine's own save," on both host and client
independently — which is exactly the problem: the host has no access to the client's
`g_char_save`/`g_stash`/`g_lifetime_stats`, because those live in the client's own process. The
host can compute the client's authoritative reward numbers (it has the client's real entity), but
it cannot bank them.

So the loop branches on `slot == w.local_player_slot`: the local slot's reward applies directly
through a new shared helper (`_apply_raid_extract_local`/`_apply_raid_death_local`, also used by
the client below); every other slot's numbers go out over a new `RaidResult` message
(`MsgType.RaidResult = 11`, `p2p/netmsg.odin`) instead — `outcome` (`Extracted`/`Died`), `gold`,
`serums`, and `extract_value` (the gold-plus-carried-items total `max_extract_gold` tracks,
separate from raw `gold` on purpose — a good haul can be mostly equipment). Reliable send: unlike a
snapshot, a dropped `RaidResult` has no next tick to correct it. The client drains
`g_session.has_raid_result` once a frame from `update_playing` via `netcode_apply_raid_result`,
which calls the *same* local-apply helpers the host uses for its own slot — the client ends up
running its own `save_player`/`local_stash()`/`g_lifetime_stats` update using authoritative numbers
the host computed, exactly mirroring how the host already handles itself. This is the same shape as
`LevelLoad`'s existing host→client signal for entering a raid: send a small message, let each side
apply the consequence to its own local state, rather than trying to make one side own the other's
save data.

Deliberately left alone: `quest_check_all(w)` still only checks the host's own `w.player_id` (called
once, outside the per-slot loop) — quest progress is a separate system with its own local-save
semantics that wasn't part of "rewards," and mixing it into this pass without the same care would
be guessing, not fixing.

### The reflection inspector's write gate now checks role, not just online-ness (fixed 2026-08-20)

`g_dbg_authority.role` was set from `p2p.session_is_online(&g_session) ? Client : Host` — any
online session at all, host included, read as `Client` and got write-blocked. Matches exactly what
was already flagged as stale in the entry above this one; fixed now that the surrounding netcode is
settled: `is_client := p2p.session_is_online(&g_session) && g_session.local_slot == 1`. Offline
(`Standalone`, which `ecs.SimRole` — a `cw:clockwork` type distinct from tormentas's own
`Simulation.role` — has no dedicated value for) and online-as-host both now correctly map to
`.Host` (writable); only being the actual client maps to `.Client` (still read-only, since editing
a `HostOnly`-simulated entity there is still pointless and editing the predicted player would fight
reconciliation).

### `SyncEntity.archetype` (renamed from the never-used `visual` field) carries which enemy def a shadow entity should spawn as

`SyncEntity` already had an 8-bit field reserved for exactly this and nothing ever wrote to it.
Wired up now, ahead of actually needing it: `AIAgentComp` gained `roster_index: u8`, stamped by
`spawn_director_system` at spawn time with the enemy's index into `DIRECTOR_ROSTER` (today a
one-entry array — `{ "enemy_spider", 1 }` — so this is genuinely inert until a second entry is
added, same spirit as the door/spawn/exit/light migration: land the plumbing before the content
that needs it, not after). `_netcode_snapshot_entity` reads it back off `AIAgentComp` into
`SyncEntity.archetype`; the client's shadow-spawn path in `_netcode_apply_snapshot` indexes
`DIRECTOR_ROSTER` with it instead of hardcoding `find_entity_def(g_entity_defs, "enemy_spider")`,
falling back to roster index 0 if the value is ever out of range (a stale client build against a
newer roster, mainly).

### 4 players, not 2: the session layer went from one connection to a star of up to three (2026-08-21)

Everything above this point was built and verified against exactly one host and one client.
`main.MAX_PLAYERS` was already `4` (the ECS/gameplay side — `world.player_ids`, the `for slot in
0..<MAX_PLAYERS` loops in `damage_system`/`pickup_system`/etc. — was written against it from the
start), but `p2p.Session` had a single `conn: sw.HSteamNetConnection` and a `local_slot` that was
always `0` or `1`. Scaling that to 4 total players meant the host accepting and tracking up to
three simultaneous peer connections, not just relabeling a constant.

**Connection layer.** `Session` keeps its single-`conn` fields for the *client* role unchanged —
a client only ever talks to the host, so nothing about that side of the API needed to change. A
new `peers: [MAX_REMOTE_PEERS]Peer` array (`MAX_REMOTE_PEERS :: MAX_PLAYERS - 1`) is host-role-only:
`session_on_conn_changed`'s host branch now finds a free slot (`_next_free_player_slot`) and a free
`Peer` for every new incoming connection, instead of only ever accepting the first one. `is_host(s)`
(`s.listen_sock != 0`) is what `session_poll`, `session_on_conn_changed`, and every send helper
branch on to decide whether to touch the single `conn` path or loop `peers[]`.

**A joining client doesn't get to pick its own slot.** The host assigns it. A new message,
`SlotAssign` (value `4` — the one gap `MsgType`'s numbering already had, filled rather than left
odd), is the first thing a peer receives after its connection is accepted; the client sets
`s.local_slot` from it. `session_is_online` was widened to require `local_slot >= 0` as well as
`state == .Connected` — before `SlotAssign` arrives, the client is connected but doesn't know who
it is yet, and nothing downstream (`spawn_players`, `g_sim.role`, `w.local_player_slot`) can run
correctly against an unassigned slot. This closed a real race: the transport-level `.Connected`
callback can fire before the app-level `SlotAssign` payload has been polled and processed.

**`session_is_online` means something different per role now.** For a client it's still "my one
connection is up and I know my slot." For a host it's "at least one peer is actively connected" —
computed by scanning `peers[]`, *not* by checking `s.state`. `s.state` deliberately stays
`.Hosting` for the host's entire lifetime once it starts accepting connections, whether it has 0
or 3 peers right now — `social.odin`'s "Waiting for friend..." vs. "Hosting — N connected" display
depends on that distinction surviving, and one peer disconnecting must not look like the host itself
went offline. `session_on_conn_changed`'s host branch reflects this: a peer's `.ClosedByPeer` just
clears that one `Peer` and relays a `RosterLeft`, never touches `s.state`.

**Reconciliation no longer needs its own field.** The old protocol sent a dedicated
`PlayerReconcileState` (pos/vel/rot) inside every `HostSnapshot`, redundant with the pos/rot/vel
already carried by that same player's generic `SyncEntity` entry in the same message — a leftover
from when there was exactly one client, so "the reconcile data" and "the other player's sync data"
never got compared side by side. Removed entirely: `netcode_client_tick` now finds its own
`Player`-kind entry (`kind == .Player && slot == local_player_slot`) in the received entities and
builds `PredictReconcileState` from that locally. This also sidesteps a real multi-peer problem —
each peer's reconciliation needs *that peer's own* `ack_seq`, which differs per recipient, while
the entity list itself is identical for everyone. `session_broadcast_snapshot` encodes the shared
entity payload once and resends it with each connected peer's own `ack_by_slot[peer.slot]`
substituted into the 4-byte header, rather than re-serializing per recipient.

**Who relays what.** Clients never connect to each other — star topology, host in the middle — so
a client only ever learns about a *third* player through the host. Two new host→client message
types, `RosterName` and `RosterCharData`, carry `{slot, payload}` and exist specifically to relay:
when a peer's `Hello`/`CharacterData` arrives at the host, the host both records it (`s.roster[slot]`,
used identically by host and client code — `hub.odin`'s remote-spawn logic doesn't need to know
which role it's running as) and rebroadcasts it to every *other* connected peer
(`_broadcast_roster_name`/`_broadcast_roster_char_data`, with `except` set to the sender so it isn't
echoed back). A brand-new peer additionally gets `_send_known_roster_to`'d the host's own identity
plus every already-connected peer's name and character data immediately after `SlotAssign`, so it
doesn't have to wait for those peers to say anything again.

**Two more fixed-`[2]` arrays crashed on slot 2/3 before this was caught live.** `g_stash` and
`g_quest_completed` were both `[2]…`, indexed directly by `g_session.local_slot` — safe at 2
players, an out-of-bounds panic (`Index 2/3 is out of range 0..<2`) at 3 or 4. Neither showed up in
the `w.player_id`-grep audit from the item above (they're indexed by the raw slot number, not
`w.player_id`), which is exactly why this was verified with **four real processes actually
connecting** (`hostlocal` + three `joinlocal`s) rather than trusted from a code read — the crash
only reproduced with a 3rd and 4th peer present, and both share sizing with `MAX_PLAYERS` now.
Worth treating as a standing reminder: any array sized `[2]` and indexed by a slot number is
suspect and won't be caught by grepping for `w.player_id`.

### `spawn_players` spawned all 4 slots regardless of how many players actually showed up (fixed 2026-08-21)

The first cut of the `MAX_PLAYERS`-not-2 change (above) took the easy way out on purpose:
`slots_to_spawn := MAX_PLAYERS if session_is_online else 1`, spawning all four player entities the
moment *any* session was online, reasoned as "harmless — an unused player entity just sits there
inert." Wrong on the "inert" part: those entities render like anyone else's, so a 2-player game
visibly showed two idle, uncontrolled characters standing at the spawn point — caught from the
player's side, not from a log. Fixed by replacing the blanket count with a real per-slot presence
check, `_slot_is_present(slot)`: always true for `local_slot` (that's you), otherwise true only if
that slot is a currently-active peer — checked via `p2p.session_peer_for_slot` on the host (a
live `Peer` in `peers[]`) or `g_session.roster[slot].known` on a client (relayed roster info, since
a client only learns about other players through the host). `spawn_players` now loops all
`MAX_PLAYERS` slots but only actually spawns the ones that pass. Verified by printing
`w.player_ids` at spawn time across 2-, 3-, and 4-peer loopback runs: unfilled slots correctly show
`INVALID_ENTITY` instead of a phantom character.

That same run surfaced a narrower, self-healing timing gap worth knowing about rather than chasing
further: a *very* late joiner's own `spawn_players` call can run before roster relay for an
already-connected-but-not-yet-announced peer has arrived, under-spawning that one slot for a
frame or two. This doesn't need a separate fix — it's exactly what the existing dynamic
`hub_spawn_remote_player` catch-up loop (`main.odin`, runs every frame while in the hub, keyed off
`g_session.roster[slot].known`) already exists to paper over, and it does, within a frame or two of
the roster message actually landing. Distinct from the over-spawn bug above, which was permanent
and visible, not a one-frame race — that's why it's flagged here rather than fixed further.

**Deliberately not done here:**
- **Real Steam P2P beyond loopback, at any player count.** This entire session's netcode —
  1-peer and now up to 3 — has only ever run over `hostlocal`/`joinlocal` on one machine. Real
  NAT/latency/relay behavior across separate machines remains completely unverified (see
  [[signal-hunt-loopback-testing-constraint]]).
- **Mid-raid disconnect handling beyond freeing the slot.** A departed peer's `RosterLeft` clears
  their roster entry and frees their `Peer` so someone else can join into that slot later, but
  their in-world character is not despawned, respawned, or accounted for in extraction — it just
  sits there. Full graceful-leave handling is a separate feature.
- **`_on_black_join_invite`'s pre-existing ordering quirk** (`main_menu.odin`, calls `init_game()`
  before `p2p.session_join`) is unchanged and, if anything, more visibly wrong now:
  `local_slot` defaults to `-1` rather than a stale `1`, so `session_is_online` reads false and
  `spawn_players` spawns a single slot exactly as it did before this pass. Still out of scope,
  same as when it was first flagged.
- **`quest_check_all`** is still called once per raid end, off the host's own `w.player_id` only —
  quest progress remains single-player-tracked by design, unchanged from the raid-rewards pass
  above.

### Character appearance was a single global — every remote player rendered as a clone of whoever was watching (fixed 2026-08-21)

Stats, inventory, gold, and mutations all carried per-player correctly through the `CharacterData`/
roster-relay machinery above. Appearance didn't: `g_player_stem` (`animation.odin`) was one global,
set by `load_player`/`give_class_starter_items` for *whichever* `pid` last ran through them (in
practice always the local player), and read back by both `get_entity_sprite_stem` (animation
lookups) and `draw_entity_sprite_visual`'s player-sprite fallback. `save.character` (which skin was
picked) *was* being serialized into every `CharacterData` blob and sent over the wire — it just had
nowhere per-player to land, so it was silently dropped on arrival. Net effect: every player, on
every machine, rendered wearing whatever skin the *local viewer* had picked for themselves, not
their own.

Fixed by turning the single global into `g_player_stems: [MAX_PLAYERS]string`, keyed by slot rather
than by "whoever asked last." `_apply_player_save` (`save.odin`) — the one function both `load_player`
and `load_player_from_bytes` funnel through — now derives the slot from `pid` via
`player_slot_for_id` and sets `g_player_stems[slot]` from `save.character`, which fixes remote
players automatically since that's the function their `CharacterData` already runs through.
`give_class_starter_items` (`items.odin`, the no-save-yet fallback) got the same per-slot set
alongside its existing `g_player_stem` write. Both read sites (`get_entity_sprite_stem`,
`draw_entity_sprite_visual`) now look up the entity's own slot (`player_slot_for_id`) into
`g_player_stems` instead of reading the bare global.

One dead line fell out of this: `spawn_players`' `if slot == 0 { render_config_set_sprite(...) }`
never did anything visually to begin with — `draw_entity_sprite_visual` unconditionally bypasses
`RenderConfig` for every player entity in favor of the stem lookup (that bypass is itself
deliberate, see the Shadows/Audio-adjacent note on `load_player` needing no second round-trip) —
so setting `RenderConfig.sprite` for slot 0 was a no-op the whole time. Removed rather than left as
misleading dead code, since this pass was already touching exactly this path.

**Found and fixed in passing, not what was reported:** verifying this exposed a second, unrelated
bug in the same neighborhood. `g_hub_remote_spawned[slot]` (a bool tracking "have I created this
slot's entity") and `g_hub_remote_loaded[slot]` (a separate bool for "have I applied their character
data") were being set *together* whenever a slot's entity already existed at `spawn_players` time
(the common case, once `spawn_players` was fixed to only spawn present slots — see above) — because
`hub_spawn_remote_player` early-returns immediately if the entity already exists, doing nothing, but
the caller marked *both* bools true regardless of whether the function actually did any work.
Result: a remote player's real character data (including the appearance fix above) silently never
applied whenever they'd already connected before the hub loaded — which, after the spawn_players
fix, was nearly always. Caught because the appearance fix's own verification (`_apply_player_save`
debug logging) printed nothing at all where it should have. Fixed by dropping `g_hub_remote_spawned`
entirely and gating strictly on `world_is_valid(w, w.player_ids[slot])` (does the entity exist right
now) and `g_hub_remote_loaded[slot]` (has data been applied) as two independent, honest checks,
rather than one bool standing in for both questions.

### Entity-id-keyed field sync closes the "client can trigger but not see" gap (fixed 2026-08-21)

Direct follow-up to the "still open" note above: doors, levers, chests, lore items, phonographs and
key pickups are spawned identically on both sides via `level_apply`/`hub_apply`, so the client's
copy just needed to be *told* the host's copy changed state — no shadow-entity spawn/despawn
problem to solve, unlike enemies/projectiles. Built as a small, generic message (`EntitySyncMsg` in
`p2p/netmsg.odin`): `wire_id` + `component` (a `ComponentType` byte) + a `path`/`value` string pair,
replayed on arrival through the exact same `cw.comp_fields`/`cw.field_set_text` reflection path the
editor's `FieldOverride` replay already uses — so no new per-type decode logic was needed, matching
the level format's own "text overrides round-trip through reflection" design. `dispatch_interaction`
(`env_interaction_system.odin`) calls `p2p.session_broadcast_entity_sync` right alongside each state
mutation it already makes (`is_locked`, `is_open`, `is_on`, etc.), and `world_destroy_entity` calls
(key pickup) get the parallel `session_broadcast_entity_destroy` / `ENTITY_SYNC_DESTROY` sentinel
component byte. Applied client-side by `netcode_apply_entity_syncs`, drained once per tick the same
way `session_drain_editor_mod_ops` already works. Deliberately generic rather than one message per
content type — the same message shape will cover any future `Interactable` variant without a wire
format change.

### The remote player's own position now interpolates too, reusing the shadow-entity machinery (fixed 2026-08-21)

The "still open" gap called out above, closed the same way shadow entities were: `g_player_interp:
[MAX_PLAYERS]ecs.Interpolator(ShadowPose)`, one per slot instead of one per `wire_id`, fed by
`interp_observe` from `_netcode_apply_snapshot`'s `Player` branch instead of writing `Transform`
directly. The blend step itself (bracket lookup, position lerp, `lerp_angle` for rotation) was
identical between shadow entities and remote players, so it's factored into one helper,
`_blend_pose_into(w, id, it, now)`, called from `netcode_interp_update` for both the shadow map and
every non-local player slot. Scoped to remote players only — `w.local_player_slot` is skipped, since
the local player is driven by prediction/reconciliation, a different and already-correct mechanism
that this must not fight with.

### Graceful mid-raid disconnect handling: destroy the slot's entity, don't leave an orphaned idle body (fixed 2026-08-21)

Before this, `session_on_conn_changed`'s host-side `ClosedByPeer`/`ProblemDetectedLocally` branch
cleared the peer and roster slot but left that slot's player *entity* untouched in the world — a
departed player's character just stood there forever, idle, on every remaining machine, with no
way to reconcile the fact that no input would ever arrive for it again. Fixed with the same
deferred-flag pattern the codebase already uses for cross-thread-ish state changes (`char_ready`,
`known`, etc.): a new `Session.disconnect_pending: [MAX_PLAYERS]bool`, set by the host's connection
callback and by the client's own `.RosterLeft` handler (so *every* peer's view converges, not just
the host's), drained once per sim tick by `netcode_apply_disconnects` — destroys the entity if it's
still valid, resets `w.player_ids[slot]`, and clears the slot's `g_hub_remote_loaded` and
`g_player_interp` state so a later reconnect to the same slot starts clean rather than replaying a
stale interpolation buffer. Verified against a real loopback connection, not just compiled: killing
the `joinlocal` process outright (not a graceful shutdown) still surfaces as
`ProblemDetectedLocally` on the host within its normal no-receive timeout, and the slot's entity is
confirmed destroyed on the next tick.

### Ability cooldown/energy sync, and the client-predicted cosmetic echo it unblocks (fixed 2026-08-21)

The "still open" note on `ability_system` above had this backwards as "feels laggy" — the real bug
is that the client's own `AbilityComp` cooldowns and `Health.energy` are frozen, full stop.
`ability_system` is `HostOnly`, so the client's local simulation never ticks its own ability state
down; nothing in the snapshot protocol carried it either. Concretely: a client's ability HUD showed
whatever cooldown/energy state existed at connect time, forever, regardless of what they actually
did. Not a feel problem — a correctness one.

Fixed by adding a small, fixed-size block to the snapshot broadcast rather than extending
`SyncEntity` (which would have put per-ability data on every enemy and projectile in every
snapshot): `PlayerAbilityState { energy_frac: u8, cooldown_frac: [4]u8 }` in `p2p/netmsg.odin`, one
per player slot, appended after the entity list in `session_broadcast_snapshot`'s wire format and
decoded into `Session.snapshot_abilities`. `netcode_host_tick` populates it per slot from each
player's real `AbilityComp.slots[i].cooldown` as a fraction of that ability's `ABILITY_DEFS[...].
cd_max` (looked up via the existing `player_ability_in_slot`), plus `Health.energy / max_energy`.
The client applies its *own* slot's entry (`_netcode_apply_ability_state`, called from
`netcode_client_tick` alongside the existing entity-snapshot apply) back onto its local
`AbilityComp`/`Health.energy` — deliberately local-slot-only; the ask was the presser's own HUD,
not remote players' cooldown display.

This is what "revisiting the `HostOnly` tag" turned into: `ability_system` stays fully `HostOnly` —
sync solves the correctness problem without needing to run any of its logic client-side. What was
added instead is `ability_echo_system` (`Shared`, new, gated on `g_sim.role == .Client`): on a
just-pressed ability key, if the client's own (now-synced, if slightly stale between snapshots)
cooldown fraction reads as ready, play an immediate local sound cue (`"ability_quickdraw"`, already
an existing sound key used by the real activation path). Deliberately scoped to sound only — no
per-`exec_kind` damage or visual prediction, which would require guessing which of a dozen ability
shapes (burst, charge, primed, AoE, …) is about to fire and risks a visible correction when the
guess is wrong or the ability is denied for a reason the client can't see (e.g. `active_abilities_
blocked`). The echo can be quietly wrong in one narrow window — pressed in the few hundred ms
between the ability going on cooldown host-side and the next snapshot arriving — same class of
staleness the interpolation and entity-sync fixes above already accept elsewhere in this protocol.

Verified against a real loopback connection: `apply_ability_state` printed the client receiving
`energy_frac=255 cooldown_frac=[0,0,0,0]` every tick once connected, confirming the wire path works
end to end. Not verified in this pass: the echo firing on an actual keypress, or a cooldown value
other than zero — both need a live play session (an ability on cooldown, or someone actually
pressing a skill key), not just a connected idle pair of processes.

### Quest progress: shared contribution, separate completion (fixed 2026-08-21)

Direct follow-up to the "deliberately left alone" note above, once the design question behind it
was actually answered: co-op quests should let players help each other toward a shared goal (kill
30 enemies *between you*) while keeping completion, and its rewards, individually tracked — not a
shared party quest log. `g_quest_completed: [MAX_PLAYERS]u8` was already shaped correctly for this
(one bitmask per slot); what was missing was getting each player's own `g_lifetime_stats` — the
thing `quest_progress` actually reads — to reflect the *whole raid's* kills, not just whatever that
one machine's own simulation happened to witness.

Combat only resolves on the host (`damage_system` is `HostOnly`), so only the host's own
`g_lifetime_stats.enemies_killed`/`elites_killed`/`bosses_killed` were ever live-incremented during
a raid; a client's copy of those fields never moved at all, even though `player_ability_in_slot`-
style per-slot XP already goes to everyone on every kill (see the `damage_system.odin` XP loop,
lines ~521-548) — quests were the odd one out, not everything else. Fixed by adding a second,
raid-scoped counter alongside the lifetime one (`g_raid_enemies_killed`/`elites_killed`/
`bosses_killed`, reset in `enter_raid`), incremented in the same place `damage_system` already
increments the lifetime version. At raid end, this raid-wide total — not any per-player count, on
purpose, since credit for a shared kill isn't divisible — rides along on the existing `RaidResult`
message (three new `u16` fields) that already carries each player's own gold/serums/extract\_value.
`netcode_apply_raid_result` (the client's receiver, already reusing the host's own
`_apply_raid_extract_local`/`_apply_raid_death_local` helpers per the note above) adds the received
totals into its own local `g_lifetime_stats` before calling `quest_check_all(w)` — a call that
didn't happen on the client at all before this fix. Each machine then evaluates its own
`quest_progress`/`quest_mark_done`/reward-banking independently, against its own now-consistent
lifetime totals — which is what actually delivers "tracked separately": two players who joined a
run with different starting lifetime kill counts can complete the same shared-raid quest on
different raids, exactly as intended.

Kill-based quests remain host-live, client-batched: the host still sees its own "quest complete"
flash mid-raid, the moment a kill crosses its threshold (unchanged, existing per-kill
`quest_check_all` call in `damage_system.odin`), while clients only resolve quest completion once,
at raid end, when the batched `RaidResult` arrives. Deliberately not building a continuous mid-raid
quest-state sync channel for this — reward banking (gold/serums) already only reconciles for
clients at the same raid-end point, so this keeps quests on the same cadence as everything else
`RaidResult` already carries, rather than introducing a new, differently-timed sync path. Quests
whose progress is personal rather than raid-shared (`Bloodlines`/`FinalForm`, both mutation-slot
counts read off `w.player_id`'s own `MutationContainer`) needed no change — they were already
correctly per-player, since mutations are owned equipment, never raid-shared state.

---

## UI (Clay immediate-mode)

### Container widgets must use the manual open/close API, not `clay.UI`'s deferred wrapper

`clay.UI`'s `@(deferred_none)` auto-close fires at the *wrapper procedure's* scope exit, not the
caller's. A container meant to stay open across several caller-side statements (`ui_hstack_begin`
/ `ui_hstack_end`, `ui_panel_begin` / `ui_panel_end`, and similar begin/end pairs) has to call
`clay._OpenElementWithId` / `clay._CloseElement` directly instead — using `clay.UI` for a
begin/end pair silently closes the container one line after it opens, before any children are
added.

### One shared microui context, not one per panel

The editor, the entity inspector and the F6 debug overlay all draw into a single `mu.Context`
rather than one each. microui tracks hover/focus globally per context; separate contexts would
each believe they exclusively own the mouse, and each would pay its own texture bind and render
flush. Input capture queries (`imui_wants_mouse`, `imui_wants_keys`) read the *previous* frame's
state — a one-frame lag, which is simply how immediate-mode UIs always answer "is the UI using the
input right now."

---

## Misc gotchas

### Player sprite RenderConfig key is bypassed on purpose

`draw_entity_sprite_visual` skips the entity's stored `RenderConfig.sprite` key for player
entities and reads `g_player_stem` directly instead (via `get_entity_sprite_stem`), so that
`load_player` / `give_class_starter_items` setting `g_player_stem` takes visual effect immediately
without a second `render_config_set_sprite` round trip.

### Class selection is the single source of truth for starter weapon archetype

Each class wields exactly one weapon archetype — whichever one is drawn in its select-screen
sprite (Nurse, PR1S, Sheriff, SRBrain, in that fixed order). There is no separate
class→archetype table to keep in sync; the sprite choice *is* the weapon choice, and the sheriff
additionally gets a fast-draw fire-rate affix baked onto her starter pistol.

---

## Packaging (`build.ps1`)

### The collaborator zip is built entry-by-entry, not via `Compress-Archive`

`Compress-Archive` stores Windows path separators (`\`) inside the zip's entry names, which the
ZIP spec forbids — it requires `/`. Windows tools tolerate this; macOS Archive Utility and Linux
`unzip` do not, and instead extract one flat pile of files literally named
`tormentas\data\sprites\...` rather than a nested folder tree. The release zip step opens the
archive directly and writes each entry with `\`→`/` replaced, so the archive is spec-correct and
opens as a proper `tormentas/` folder on every platform.
