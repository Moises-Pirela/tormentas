# Backend Swap Plan — raylib → sokol (P1a steps 7–8)

Companion to [`BUILD_PLAN.md`](BUILD_PLAN.md) (P1a) and [`AUDIO_PLAN.md`](AUDIO_PLAN.md).
Tags as elsewhere: **[D]** decided · **[P]** proposed, needs sign-off · **[?]** open.

**Scope:** rendering, window, input, main loop, ImGui, build and packaging. **Not** audio, which is
its own track ([`AUDIO_PLAN.md`](AUDIO_PLAN.md), with the interim question in its §7). **Not** 3D,
which is P1b.

**Exit:** the current game, still isometric 2D, runs on sokol (Metal on macOS, D3D11 on Windows),
and the game binary links no raylib.

**Basis:** steps 2–6 already route every raylib use in package main through `src/gfx` (389 lines),
plus `ui/imgui_raylib/backend.odin`. This plan comes from a full audit of what sits behind those
calls (2026-11-17): frame order, every render target, shader and texture, text and fonts, Clay,
ImGui, input semantics, startup and shutdown, window modes, build and packaging. Condensed
inventories are in the appendix. Each item there is either a task below or an explicit decision.

**Sizing:** about **L+ (6–8 weeks)**, up from the original P1a estimate of L for the whole phase.
The audit found work the first estimate did not see (§1).

---

## 1. What the audit changed

The spike proved the core patterns (sgl layers per pass, offscreen main target, shdc shaders,
fontstash atlas, readback). The audit found these on top:

1. **A render target can open inside another one.** Fallback entity sprites (`env_chest`,
   `env_door`, `env_key` and four more `env_*` stems, all without PNGs) are built lazily on first
   draw. That can happen inside `g_sprite_rt` + camera (`render.odin:1704`, `995`). sokol passes
   cannot nest.
2. **Orientation is written into game code** in more than 15 places: negative-height source rects
   (`tile_map.odin:129`, `render.odin:1552–1678` ×9, `lighting.odin:716/750`, `ui_manager.odin:230`),
   the shaders' wall-mask UV flips, and `gl_FragCoord` flips in four shaders.
   - Some places depend on raylib's flipped **storage**. The water tile and the floor/wall-top paths
     sample a baked target with a *positive* half-height rect (`tile_map.odin:302`, `395`).
   - Others depend on **REPEAT wrap**: the UI-layer src `{0, h, w, -h}` and projected shadows of
     render-target sprites (`shadow.odin:52`).
3. **Offscreen work happens in the middle of on-screen drawing** in four places: lighting targets,
   the dirty wall mask (`lighting.odin:879`), UI layers (`ui_manager.odin:223`, re-rendered every
   frame while visible), and the lazy sprite builds.
4. **Text depends on a mipmapped 512 px atlas.** All text is scaled down from it, including
   world-space text that the editor camera zooms up to about 9×.
   - Under fontstash, the 131 es/pt lines with accents will **start rendering**. Today they are
     probably `?`, because raylib loads ASCII only.
   - `←`, `▶` and `◼` (used in the UI) exist in **neither** font.
5. **Zero-tick frames drop keypresses.** Edge-triggered actions (dodge, skills, interact, reload)
   are collected once per frame and cleared after the first tick (`main.odin:468–474`). Today the
   60 FPS cap hides this. Under vsync on a 120 Hz or ProMotion display, about half of these presses
   would be lost.
6. **sokol_app changes the lifecycle.**
   - `sapp_run` never returns on macOS, and `cleanup_cb` is not guaranteed to run
     (`sokol_app.h:1205`). Today config and player saves happen after the loop.
   - Cmd+Q stops working, because sokol creates no NSMenu.
   - `boot_loopback_from_args` blocks for up to 15 s, which would freeze `init_cb`.
7. **HighDPI is deliberately off** (`TUNING.md`): composites land at the wrong scale when it is on.
   sokol on D3D11 always makes the process DPI-aware (`sokol_app.h:10418`).
8. **The ImGui backend shares input with the game.** It shares the character queue with name entry,
   passes raw GL texture ids to the anim editor, and handles clipboard and cursors through raylib.
9. Small things that would otherwise bite:
   - Clay measures text with spacing 0 but draws with 0.5 (`render.odin:466` vs
     `clay_renderer.odin:62`).
   - The wall mask is written with `draw_pixel` and needs texel-exact results.
   - `point_lights.fs` is not loaded anywhere (the decided lighting scope counted it).
   - Window probe steps (resize, monitor/DPI logging) have no sokol equivalent.

---

## 2. Decisions before starting

| # | Decision | Proposal |
|---|---|---|
| D1 | HighDPI | **[P] Off for the swap** (`high_dpi = false`), for parity. Turn it on afterwards as its own task: targets and shaders use framebuffer size, scissor and ImGui use the DPI scale. On Windows, verify in S1 what sokol does with `high_dpi=false` while the process is DPI-aware |
| D2 | Frame pacing | **[P] `swap_interval = 1`, no cap**, and fix finding 5 properly: latch edge-triggered actions until a tick consumes them. Add an optional 60 FPS cap in settings only if needed. The probe runs with a fixed dt (§3.13) |
| D3 | Window | **[D]** resizable window + fullscreen toggle (borderless on Windows, native on macOS). Consequences: drop the resolution presets, minimum size, fit-to-monitor, centering and monitor queries. Restore the windowed size from the config at launch; start fullscreen from `desc.fullscreen` |
| D4 | Text | **[P]** fontstash rasterizes at the real pixel size, quantized to whole pixels. World-space text is rasterized at `size × camera zoom`. **[?] Missing glyphs `← ▶ ◼`:** add a small symbol fallback font, or replace them with icons/ASCII |
| D5 | Blend parity | **[P]** Reproduce raylib's default blend exactly: `SRC_ALPHA, ONE_MINUS_SRC_ALPHA` for colour **and** alpha. The spike's separate-alpha factors would change how UI panels and lit composites look. Additive = `SRC_ALPHA, ONE`. Verify raylib's factors against its source in S2 |
| D6 | Lighting scope | **[D]** Port `directional_light`, `sprite_light` and `fog_lights` (fog includes the vision radius). Stub `cloud_shadow` and `god_rays` until P1b. Drop the unused `point_lights.fs` |
| D7 | Shader API | **[P]** `shader_location` + per-uniform setters become **typed uniform blocks** generated by shdc. The ~155 calls in `lighting.odin` become struct fills |
| D8 | Audio | **[?]** Interim miniaudio port vs keep raylib's audio linked (see `AUDIO_PLAN.md` §7). It blocks only S7 |
| D9 | Resolution settings | **[P]** Remove the resolution stepper from settings (D3 makes it inert). Keep the Mode stepper |

---

## 3. Architecture of the sokol backend

### 3.1 Frame recorder (passes from a flat draw stream)
Game code keeps calling `target_begin/end`, `camera_begin/end`, `scissor`, `blend`, `shader` and
draw procedures in its current order. `gfx` records them and replays them as passes:

- The frame is split into **segments**. A segment is a run of draws into one target. Swapchain
  draws go to an offscreen **main target**; that is the backbuffer raylib had.
- `target_begin(rt)` closes the current segment and opens one for `rt`. `target_end` reopens the
  previous target with a **LOAD** action. A swapchain → offscreen → swapchain sequence becomes
  three passes.
- Each segment holds an ordered list of **items**: sgl layer ranges and *custom draws*
  (fullscreen shader passes). A custom draw splits the sgl stream; layer ids just increase.
- `clear(c)` as the first operation of a segment becomes that pass's clear action.
  - Two clears before any draw (the tile bake): the last one wins.
  - A clear after draws (none exist today): assert in debug, fall back to a full-target quad with
    blending off.
- At `frame_end`: run uploads (font atlas, dynamic textures, ImGui), replay the segments in order,
  draw ImGui into the main target, then present the main target in the swapchain pass and commit.
- **Load-time targets** (tile bake in `tilemap_init`, fallback sprites) record before the first
  frame and replay first at the first `frame_end`.
- **Nesting:** debug assert. Remove the one nested case in S0. The recorder can also split the outer
  segment around an inner one, but with the case removed it doesn't need to.
- **Expected pass count** while playing with one UI panel open: shadow, world, main, sprite, main,
  [mask], main, UI layer, main, present. About 10, which is cheap for sokol.

### 3.2 Orientation (render targets are upright)
- **Centralize first, on raylib (S0):** `gfx.target_src(rt) -> Rect` and `gfx.target_uv_flip(rt)`
  replace every hand-written negative height and `y` offset. The shaders take the flip as a
  uniform. Then the sokol backend returns unflipped values, and game code never encodes
  orientation.
- **Positive-half-height samplers** that rely on flipped storage (water, floor, wall tops) need
  their intended half checked against screenshots in S0, then expressed explicitly.
- **REPEAT-dependent** UVs (UI layer src, `shadow.odin` with RT sprites) become plain 0..1 UVs.
- **Negative src heights reaching maths:** `draw_player_sprite` computes `aspect` from `src.height`
  (`render.odin:1736`, `998`). Use `abs`, or the centralized helper.
- **Anim editor previews** of RT sprites, upside down today in ImGui, become correct.

### 3.3 Pipelines and state
- **Two sgl contexts:** RGBA8 for offscreen targets and the main target, plus the default
  (swapchain, BGRA8 on Metal) context, used only for presenting.
- **Every sgl pipeline needs `write_mask = .RGBA`** (spike finding: sgl defaults to RGB).
- **Pipelines per blend mode:** alpha (D5) and additive. For custom draws, per shader × blend.
- **Culling off.** Winding stops mattering: the `flip_winding` logic in `shadow.odin` becomes
  harmless, and the degenerate greybox quads are fine.
- **Scissor** in pass pixels with a top-left origin: logical × DPI on the main target, ×1 in
  screen-sized UI targets.

### 3.4 Shapes
On sgl, matching raylib where it shows:
- rects, rects with integer rounding as today, lines
- `draw_line` / `draw_line_v`: 1 px hairlines (`sgl.begin_lines`)
- `draw_line_ex`: a quad, including sub-pixel thickness in the editor
- triangles
- circles and ellipses: use raylib's automatic segment-count rule; check it against raylib's source
- `draw_ring` and `draw_rect_rounded`: explicit segment counts
- `draw_pixel`: 1×1 quads at texel centres

### 3.5 Textures and images
- `gfx.Texture` becomes our own struct `{ id, width, height, view, ... }`. Keep `id` non-zero when
  valid, because game code checks `.id` in about 32 places.
- Loading: stb_image to RGBA8, immutable images, an explicit sampler per texture.
- Defaults must match raylib's: **point filter, REPEAT wrap**. Verify sokol's sampler defaults in
  S2 and set them explicitly either way. BILINEAR where the game asks for it; CLAMP on the hub
  background.
- **Mipmaps:** only fonts used them, and fontstash removes that need (D4). If ever needed: CPU mip
  generation with `vendor:stb/image` resize.
- **`gfx.Image`** becomes our own CPU struct `{ data, width, height }`, always RGBA8, so
  `image_format` becomes a no-op. Used by `sprite_ground_fraction` and the app icon.
- **Size limits:** `player_sheriff` is 4096², `Town.png` 3278×2403, both within Metal/D3D11 limits.

### 3.6 Text (fontstash)
- Two fonts: Cinzel (title) and body. Atlas upload through a staging buffer as in the spike, expanded
  to white RGBA. The atlas grows through fontstash's resize callback (image recreated).
- **Metrics parity:** top-left positioning, and a single-line measured height of about `fs`. Code
  mixes `fs` and `measure_text().y` when centering (`render.odin:106`, `257`).
- **World-space text:** `gfx` knows the active camera zoom, rasterizes at `fs × zoom`, and draws
  scaled by `1/zoom`. Sizes are quantized to whole pixels to limit atlas churn.
- **Clay:** fix the spacing mismatch so measure matches draw.
- **Non-ASCII:** text is UTF-8 already (`localization.odin:329`). Accents appear; check es/pt
  layouts for overflow. Missing glyphs per D4. `lore_draw_wrapped` copies words into 256-byte
  buffers, which can cut a UTF-8 character; make that UTF-8-safe.

### 3.7 Shaders
- Port the three D6 shaders to `src/gfx/shaders/*.glsl` (shdc, `metal_macos:hlsl5`), in the
  spike's pattern:
  - one std140 block per shader, arrays packed as `vec4`
  - a fullscreen triangle
  - `gl_FragCoord` with a top-left origin and the **framebuffer** size as a uniform
  - the wall-mask UV flip removed
- **The source texture** (raylib's `texture0`, i.e. the world or sprite RT) and the extra textures
  (`u_shadow_tex`, `u_wall_mask`) become declared texture + sampler bindings.
  - `directional_light` and `sprite_light` sample `u_shadow_tex` at the host quad's UV. Keep both
    targets the same size and orientation.
  - `sprite_light` steps neighbour taps by `1/u_screen_size`, which assumes target size = screen
    size. Keep that, or pass the texel size.
- **gfx API:** `gfx.fullscreen_pass(shader, &params, textures, blend)` records a custom draw (§3.1).
  - `fog_lights` runs twice (`u_pass` 0 with alpha blend, 1 with additive): two custom draws.
- **Stubs:** `cloud_shadow` and `god_rays` draw nothing, behind their existing toggles.
- Delete `data/shaders/*.fs` once ported. Release packaging stops shipping them.

### 3.8 Wall mask
Build the 1-px-per-tile mask on the CPU and upload it (staging buffer + copy), instead of a pass of
`draw_pixel` calls. Exact by construction, and one less mid-frame pass. This can be done in S0 on
raylib.

### 3.9 ImGui backend (rewrite)
- **Rendering:** `ImDrawData` through dynamic vertex/index buffers (u16 indices). Set
  `RendererHasVtxOffset`. Clip rects in framebuffer pixels. Drawn into the main target, so
  screenshots include the dev tools as they do today.
- **Textures** (`RendererHasTextures`): create, and update **by update rect** through staging
  copies. Today the whole texture is re-uploaded.
  - `ImTextureID` maps to our `gfx.Texture` handle, so `devui_texture` / `texture_ref` (anim editor)
    keep working.
- **Input from sapp events directly:** keys, modifiers, characters, wheel x/y, focus. It shares one
  per-frame character queue with the game's text entry, keeping the `skip_chars` behaviour.
- **Cursors:** map onto `sapp.set_mouse_cursor`. **Clipboard:** `enable_clipboard` plus the
  `CLIPBOARD_PASTED` event.
- Keep: docking, the ini path, `MoveFromTitleBarOnly`, the 16 px body font.

### 3.10 Input on sapp events
`gfx/platform.odin` keeps its signatures. Underneath, events fill per-frame state:
- `down`, `pressed`, `released` per key and button. **`pressed` ignores `key_repeat`**: nothing in the
  game uses repeat, and name-entry Backspace is one per press. Character events keep their repeats.
- **A per-frame key queue** for `key_pressed_any` (rebinding), and the shared character queue.
- **Accumulated** wheel x/y and mouse delta.
- **`UNFOCUSED` releases every held key and button**, so nothing sticks after Alt-Tab.
- **The synthetic input mode stays as is** (probe determinism).
- State stays valid until `end_input_frame`, because draw code also reads input (menu and Clay
  buttons).
- **Hotkeys:** Alt+Enter / Ctrl+Cmd+F → `sapp.toggle_fullscreen`. **Cmd+Q on macOS →
  `request_quit`.** The close button → `QUIT_REQUESTED` → normal shutdown (§3.11).
- **Edge latch (D2):** pressed actions accumulate into a per-tick latch, cleared only when a sim tick
  consumes them (`collect_local_input` / `update_playing`).

### 3.11 Lifecycle (main loop inversion)
- **`main()` before `sapp.run`:** set the working directory, parse probe arguments,
  `migrate_legacy_user_files`, `load_config`, then build `sapp_desc` from `g_binds.display`
  (width, height, fullscreen, `high_dpi=false`, `swap_interval`, title, icon, logger,
  `enable_clipboard`).
- **`init_cb`:** everything from today's step 7 on.
  - Shader and texture loads need sokol, so they must run here, not before.
  - The two startup failures (`loot_table_load`, `load_entity_defs`) become `sapp.quit()`.
  - **The loopback boot becomes a state** that `app_frame` polls, not a blocking loop.
- **`frame_cb` = `app_frame()`.** Steam callbacks pumped there, as today.
- **`cleanup_cb`:** the post-loop block plus every `defer` in today's `main`, in the same order.
  sokol may not call it, so also:
  - save the config whenever it changes (most changes already do)
  - on `QUIT_REQUESTED`, run the saves (`save_config`, `save_player` via `shutdown_game`) before
    allowing the quit
- **`g_should_exit`** (main-menu Exit, Settings Exit) → `sapp.request_quit()`.

### 3.12 Window
- `desc.width/height` = the saved windowed size (default 1600×900). `desc.fullscreen` from the
  config.
- **Icon** from the PNG through `sapp.Icon_Desc`.
- The windowed size is saved from the framebuffer size on `RESIZED`, while windowed.
- **macOS:** sokol's toggle and `desc.fullscreen` use native fullscreen. `platform_darwin.odin`'s
  objc helpers (collection behaviour, style-mask polling) go away. Verify the green button stays in
  sync through `sapp.is_fullscreen()`.
- **Removed (D3/D9):** minimum size, fit-to-monitor, centering, monitor queries, resolution presets,
  `platform_window_fits`, and the window probe's resize steps. The window probe keeps startup →
  windowed → fullscreen, with sokol's own state in the log.

### 3.13 Timing
- `frame_time()` = `sapp.frame_duration()`. `time()` = `sokol_time` since init (already vendored).
- **The fixed-tick accumulator is unchanged.** D2's latch fixes input at any refresh rate.
- **Probe determinism:** in probe mode, `frame_time()` returns exactly 1/60, so frame-numbered
  scripts behave the same at any refresh rate.

### 3.14 Screenshots
- Move the spike's readback into `gfx`: `native/capture_metal.m` and `capture_windows.odin`. It
  reads the **main target** after `sg.commit`.
- Today `gfx.screenshot` reads the *previous* presented frame at the start of the next. The new
  version captures at the end of the requested frame. Re-time the probe so shots land on the same
  content.

### 3.15 Build, tests, packaging
- **`build.sh` / `build.ps1` game target:** `-collection:sokol`, `ensure_sokol_libs` /
  `Initialize-SokolLibs`, `compile_shaders` on `src/gfx/shaders`, and the native readback library
  (macOS).
- **`test.sh` / `test.ps1`:** pass `-collection:sokol` to `odin test src`.
- **Symbol checks:**
  - the server binary must not link `sapp_`, `sg_` or `sgl_`
  - the **game binary must not link raylib or GLFW** (new check)
- **`check_boundaries.py`:**
  - `src/gfx` allows `sokol:`, `vendor:fontstash`, `vendor:stb/image`, `vendor:directx` (Windows
    readback)
  - `vendor:raylib` is removed from the `src/gfx` rule
  - package main keeps banning raylib
- **macOS .app:** check `NSHighResolutionCapable=true` against `high_dpi=false`. No `data/shaders`
  any more.
- **Windows:** no manifest is needed (sokol sets DPI awareness at runtime).
  - **Clean up the 46 stray `RCa*` / `RDa*` rc.exe temp files** tracked in `data/app/`. They ship
    in every release today.
- **Docs that name raylib:** README, SETUP, SETUP-MACOS, VALIDATION, TUNING (§5 of the audit).
- **The spike becomes production code:** reuse its atlas, layer and readback code, then delete
  `src/spike` and its build targets.

---

## 4. Stages

Each stage ends with a build and a stated check. The game may be broken from S1 to S5 (accepted
2026-11-17).

### S0 — Prepare on raylib (M). The game still works; verify with the probe.
- [ ] Centralize render-target orientation (§3.2): `gfx.target_src`, a shader flip uniform, no
      negative heights in game code. Resolve the water/floor half-height paths explicitly.
- [ ] Build fallback entity sprites **eagerly** at init for every referenced stem without a PNG.
      Add a nesting assert to the raylib backend.
- [ ] Wall mask built on the CPU and uploaded (§3.8).
- [ ] Edge-action latch for zero-tick frames (D2). This is a gameplay fix on its own merits.
- [ ] Fixed dt in probe mode (§3.13).
- [ ] Fix Clay's spacing mismatch. Make `lore_draw_wrapped` UTF-8-safe.
- [ ] Remove dead code: `point_lights.fs`, `font_for`, `apply_resolution`, `g_borderless`.
- **Done when:** the probe matches the pre-S0 reference within noise. Tag this commit as the
  **raylib reference** for S6.

### S1 — sokol shell (M)
- [ ] `sapp.run` and the lifecycle (§3.11), including loopback as a state, quit handling and
      Cmd+Q.
- [ ] Event-driven input (§3.10), timing (§3.13), window and icon (§3.12).
- [ ] `gfx` draws are stubs except clear and present.
- **Done when:** the window opens at the saved size and mode; input reaches the game (verify by
  logging); the fullscreen toggle works on macOS; quitting saves the config; D1's Windows DPI
  question is answered.

### S2 — 2D batcher and recorder (M–L)
- [ ] The frame recorder (§3.1), pipelines (§3.3), shapes (§3.4), textures and samplers (§3.5),
      camera (sgl matrices from `Camera2D`), scissor, immediate quads.
- [ ] Verify raylib's blend factors, sampler defaults and circle segment rule against raylib's
      source.
- **Done when:** menu, hub and raid render **unlit and without text**; the pass count per frame is
  as §3.1 predicts; no validation errors.

### S3 — Text (M)
- [ ] fontstash backend (§3.6) for `draw_text` / `measure_text`, world-space zoom handling, missing
      glyph policy (D4).
- **Done when:** every screen is readable, and es/pt text shows its accents; no overflow on the 14
  UI panels.

### S4 — ImGui (S–M)
- [ ] The backend rewrite (§3.9).
- **Done when:** editor, inspector, console, anim editor (including sprite previews), lighting widget
  and docking all work; copy/paste works; cursors change.

### S5 — Lighting (M)
- [ ] Port the three shaders, stub the two (§3.7, D6). Typed uniform blocks replace
      `shader_location` (D7).
- **Done when:** lit composites, sprite outlines, fog, vision radius and point lights look right in
  hub and raid; screen-space reconstruction holds after a resize.

### S6 — Readback and parity (S)
- [ ] Screenshots on sokol (§3.14).
- [ ] Probe comparison against the S0 reference tag (`BUILD_PLAN.md` step 6 procedure), plus the
      manual checklist in §5.
- **Done when:** the probe is within noise, *or* every difference is explained (text metrics,
  stubbed clouds/god rays) and accepted.

### S7 — Remove raylib (S). Blocked by D8.
- [ ] Delete the raylib backend code and `ui/imgui_raylib`.
- [ ] Build, test and boundary updates (§3.15), symbol checks, docs, `src/spike` removal, `data/app`
      cleanup.
- **Done when:** `./test.sh` passes with the new symbol checks, and the game binary contains no
  raylib or GLFW symbols.

### S8 — Windows (S)
- [ ] Run S1–S7's checks on Windows/D3D11: build through `build.ps1`, readback, the probe, the
      fullscreen toggle, DPI.
- **Done when:** the probe runs on Windows and matches macOS within noise, apart from expected
  backend differences.

---

## 5. Manual checklist (S6, then again in S8)

- **Menus:** main menu, class select, character name entry with accents and Backspace.
- **Panels:** all 14 UI panels (inventory, stats, mutation tree, shop, stash, ability vendor,
  pause, settings, keybinds, level select, lore, phonograph, social, quest board).
- **Settings:** key rebinding, including Esc to cancel; the Mode stepper; volume sliders.
- **Hub:** background, portal labels, shop and NPC labels.
- **Raid:**
  - lighting, fog and vision radius
  - sprite shadows and the player's projected shadow
  - water tiles
  - fallback `env_*` sprites
  - damage numbers and health bars
  - the boss warning
- **Editor:** zoom extremes (text crisp at 6×), brush, gizmo drag, inspector, console, anim editor
  previews.
- **Window:** fullscreen toggle on both OSes, the green button on macOS, resize, Alt-Tab (no stuck
  keys), Cmd+Q, the close button saving config and player.
- **Display:** a 120 Hz display with no dropped dodges or skills; a high-DPI display at
  `high_dpi=false` with no misplaced composites.

---

## 6. Risks

| Risk | Stage | Mitigation |
|---|---|---|
| Orientation mistakes scattered through game code | S0 | centralize on raylib first, probe-verified |
| Blend or sampler defaults differ from raylib's | S2 | verify against raylib's source; explicit pipelines and samplers |
| Text metrics shift layouts (Clay, HUD) | S3 | top alignment and height ≈ fs; fix the measure mismatch; check all panels |
| Accents or missing glyphs overflow UI | S3 | D4 decision; es/pt pass over the 14 panels |
| Lifecycle: saves lost on quit | S1 | save on change, plus saves on `QUIT_REQUESTED` |
| Input regressions (repeat, focus, shared char queue) | S1/S4 | §3.10 rules; checklist items |
| Windows-only issues found late | S8 | spike already compiles for Windows; run S8 checks as soon as S2 renders |
| Scope creep into 3D or HighDPI | all | out of scope; HighDPI is a follow-up (D1) |

---

## Appendix — condensed audit (2026-11-17)

**A. Frame order while playing.** Offscreen passes are marked ◆.
1. ◆ shadow RT
2. ◆ world RT
3. screen: directional composite
4. screen: sprite and projected shadows (camera)
5. ◆ sprite RT (greybox quads, sprites, possibly a lazy fallback build)
6. screen: sprite composite, clouds, god rays (additive)
7. ◆ wall mask, if dirty
8. screen: fog pass 0 (alpha), fog pass 1 (additive)
9. screen: world overlays (camera), then HUD (Clay)
10. per visible UI layer: ◆ layer RT, then screen composite with alpha
11. screen: toast, fade, ImGui

**B. Render targets.**

| Target | Size | When | Read by |
|---|---|---|---|
| `g_shadow_rt` | screen | every frame | directional and sprite shaders at host UV |
| `g_world_rt` | screen | every frame | directional composite, src `{0,0,w,-h}` |
| `g_sprite_rt` | screen | every frame | sprite composite, src `{0,0,w,-h}` |
| `g_wall_mask` | tiles, ≤1024² | when dirty, mid-frame | fog and sprite shaders, UV flipped in shader |
| tile bake | 64² | load time | water tile (positive half-height src) |
| fallback entity sprites | 64² | lazily, possibly nested | sprites, shadows, class select, anim editor |
| UI layers (≤8) | screen | every frame while visible | composite with src `{0,h,w,-h}` and alpha |

**C. Shaders.**
- All are drawn on the screen, never into a target. Only alpha and additive blend.
- `cloud_shadow` (stub), `god_rays` (stub, additive): `gl_FragCoord`, no textures.
- `directional_light`: world RT and shadow RT, 6 uniforms.
- `sprite_light`: sprite RT, shadow RT and wall mask; 23 uniforms including 4 arrays of 32;
  `gl_FragCoord`; `discard`; neighbour taps.
- `fog_lights`: wall mask; 19 uniforms including 4 arrays of 32; `gl_FragCoord`; two passes
  (`u_pass`).

**D. Text.**
- 2 TTFs at 512 px with trilinear mipmaps, plus the ImGui 16 px font.
- About 250 draw/measure calls, sizes from about 5 to 156 px.
- World-space text inside the world RT, the sprite RT and the post-composite camera block.
- 131 non-ASCII loc lines; `← ▶ ◼` are missing from both fonts.

**E. Input and lifecycle.**
- Edge actions dropped on zero-tick frames.
- Shared character queue between ImGui and name entry; no key repeat use.
- Focus loss is handled only by ImGui.
- Startup steps 1–4 need no window; shader and texture loads need sokol.
- Shutdown: 5 explicit steps plus about 20 defers. The loopback boot blocks for up to 15 s.

**F. Build.**
- raylib comes from the Odin vendor folder. The test symbol check covers the server only.
- `build-clay.sh` has no raylib assumption (the original plan wrongly listed one).
- 46 rc.exe temp files are tracked in `data/app/`.
