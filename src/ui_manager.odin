package main

// =============================================================================
// ui_manager.odin — Panel layer stack with fade-in / fade-out
//
// UI panels are now separate from world/sim state (PlayingSubstate).
// World states (Gameplay, Hub, Editor, DeathScreen, ExtractScreen) live in
// g_playing_state.  Overlay panels (Inventory, Stats, Shop, etc.) are pushed
// onto a small layer stack here.  Each layer owns an alpha value that ramps
// from 0→1 on open and 1→0 on close before the layer is removed.
//
// Usage:
//   ui_open(.Inventory)      // push panel (no-op if already open)
//   ui_close_top()           // begin fade-out on topmost panel
//   ui_close(.Shop)          // begin fade-out on a specific panel
//   ui_close_all()           // instant remove all (used on shutdown/reset)
//   ui_has(.Shop)            // true while panel is open or fading in
//   ui_any()                 // true while any panel is visible
//   ui_top()                 // topmost panel, bool ok
//   ui_update(dt)            // tick fade states  (call from update_playing)
//   ui_draw(w)               // render panels     (call from draw_playing)
// =============================================================================

import rl "vendor:raylib"
import cw "clockwork"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

UIPanel :: enum {
    Inventory,
    Stats,
    MutationTree,
    Shop,
    Stash,
    PauseMenu,
    Settings,   // resolution / volume / window-mode (main-menu & in-game)
    Keybinds,   // keybind editor — pushed on top of PauseMenu or Settings
    LevelSelect,
}

UILayerState :: enum { FadeIn, Visible, FadeOut }

MAX_UI_LAYERS :: 8

UILayer :: struct {
    panel: UIPanel,
    alpha: f32,
    state: UILayerState,
}

UIManager :: struct {
    layers: [MAX_UI_LAYERS]UILayer,
    count:  int,
    rt:     rl.RenderTexture2D,
    rt_w:   i32,
    rt_h:   i32,
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// Panels fade in/out in ~0.12 s  (alpha 0→1 at 8 units/sec).
UI_FADE_SPEED :: f32(8.0)

// ---------------------------------------------------------------------------
// Global
// ---------------------------------------------------------------------------

g_ui: UIManager

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

ui_init :: proc() {
    g_ui.rt_w = rl.GetScreenWidth()
    g_ui.rt_h = rl.GetScreenHeight()
    g_ui.rt   = rl.LoadRenderTexture(g_ui.rt_w, g_ui.rt_h)
}

ui_destroy :: proc() {
    rl.UnloadRenderTexture(g_ui.rt)
    g_ui = {}
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// Recreate the render texture when the window is resized.
@(private = "file")
_ui_ensure_rt :: proc() {
    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()
    if sw == g_ui.rt_w && sh == g_ui.rt_h { return }
    rl.UnloadRenderTexture(g_ui.rt)
    g_ui.rt   = rl.LoadRenderTexture(sw, sh)
    g_ui.rt_w = sw
    g_ui.rt_h = sh
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// Open a panel.  If it is already in the stack (even fading out) nothing is
// pushed; fading-out panels are reversed back to fading-in instead.
ui_open :: proc(panel: UIPanel) {
    for i in 0..<g_ui.count {
        l := &g_ui.layers[i]
        if l.panel == panel {
            if l.state == .FadeOut { l.state = .FadeIn }
            return
        }
    }
    if g_ui.count >= MAX_UI_LAYERS { return }
    g_ui.layers[g_ui.count] = UILayer{
        panel = panel,
        alpha = 0,
        state = .FadeIn,
    }
    g_ui.count += 1
    _ui_on_open(panel)
}

// Begin fade-out on the topmost panel.
ui_close_top :: proc() {
    if g_ui.count == 0 { return }
    l := &g_ui.layers[g_ui.count - 1]
    if l.state == .FadeOut { return }
    l.state = .FadeOut
    _ui_on_close(l.panel)
}

// Begin fade-out on a specific panel (does nothing if not found).
ui_close :: proc(panel: UIPanel) {
    for i in 0..<g_ui.count {
        l := &g_ui.layers[i]
        if l.panel == panel && l.state != .FadeOut {
            l.state = .FadeOut
            _ui_on_close(panel)
            return
        }
    }
}

// Instantly remove every open panel (no fade).  Use on reset/shutdown.
ui_close_all :: proc() {
    for i in 0..<g_ui.count {
        l := &g_ui.layers[i]
        if l.state != .FadeOut {
            _ui_on_close(l.panel)
        }
    }
    g_ui.count = 0
}

// True if a panel is open (FadeIn or Visible — not FadeOut).
ui_has :: proc(panel: UIPanel) -> bool {
    for i in 0..<g_ui.count {
        l := &g_ui.layers[i]
        if l.panel == panel && l.state != .FadeOut { return true }
    }
    return false
}

// Returns the topmost panel that is not fading out.
// FadeOut layers are skipped so the panel beneath becomes active immediately
// once a close starts — prevents stale update dispatch during the fade.
ui_top :: proc() -> (panel: UIPanel, ok: bool) {
    for i := g_ui.count - 1; i >= 0; i -= 1 {
        l := &g_ui.layers[i]
        if l.state != .FadeOut { return l.panel, true }
    }
    return {}, false
}

// True while any panel exists (including ones that are fading out).
ui_any :: proc() -> bool {
    return g_ui.count > 0
}

// ---------------------------------------------------------------------------
// Update  (call once per frame, before draw)
// ---------------------------------------------------------------------------

ui_update :: proc(dt: f32) {
    i := 0
    for i < g_ui.count {
        l := &g_ui.layers[i]
        switch l.state {
        case .FadeIn:
            l.alpha = min(l.alpha + dt * UI_FADE_SPEED, 1)
            if l.alpha >= 1 { l.alpha = 1; l.state = .Visible }
        case .Visible:
            // idle
        case .FadeOut:
            l.alpha = max(l.alpha - dt * UI_FADE_SPEED, 0)
            if l.alpha <= 0 {
                // Compact the array by shifting subsequent entries down.
                for j in i..<(g_ui.count - 1) {
                    g_ui.layers[j] = g_ui.layers[j + 1]
                }
                g_ui.count -= 1
                continue // re-check the same index
            }
        }
        i += 1
    }
}

// ---------------------------------------------------------------------------
// Draw  (call once per frame, after all world drawing)
// ---------------------------------------------------------------------------

// Renders each layer into the shared render texture and blits it to the
// framebuffer with its current alpha.  Layers are drawn bottom-to-top so
// later panels appear in front.
ui_draw :: proc(w: ^cw.World) {
    if g_ui.count == 0 { return }
    _ui_ensure_rt()

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    for i in 0..<g_ui.count {
        l := &g_ui.layers[i]

        // Render this panel into the offscreen texture.
        rl.BeginTextureMode(g_ui.rt)
        rl.ClearBackground(rl.BLANK)
        _ui_draw_panel(l.panel, w)
        rl.EndTextureMode()

        // Blit with per-layer alpha.
        // Source rect uses negative height to flip the OpenGL Y axis.
        src  := rl.Rectangle{ 0, f32(g_ui.rt_h), f32(g_ui.rt_w), -f32(g_ui.rt_h) }
        dst  := rl.Rectangle{ 0, 0, sw, sh }
        tint := rl.Color{ 255, 255, 255, u8(l.alpha * 255) }
        rl.DrawTexturePro(g_ui.rt.texture, src, dst, {0, 0}, 0, tint)
    }
}

// ---------------------------------------------------------------------------
// Internal — panel dispatch
// ---------------------------------------------------------------------------

@(private = "file")
_ui_draw_panel :: proc(panel: UIPanel, w: ^cw.World) {
    switch panel {
    case .Inventory:
        if w == nil { return }
        draw_inventory(w)
    case .Stats:
        if w == nil { return }
        draw_stats_screen(w)
    case .MutationTree:
        if w == nil { return }
        draw_mutation_tree(w)
    case .Shop:
        if w == nil { return }
        // Shop shows the inventory panel on the left + shop HUD on the right.
        draw_inventory(w)
        draw_shop_hud(w)
    case .Stash:
        if w == nil { return }
        draw_inventory(w)
        draw_stash_hud(w)
    case .PauseMenu:
        draw_pause_menu()
    case .Settings:
        draw_settings_overlay()
    case .Keybinds:
        draw_keybinds_screen()
    case .LevelSelect:
        if w == nil { return }
        draw_level_select(w)
    }
}

// Called the moment a panel is pushed onto the stack.
@(private = "file")
_ui_on_open :: proc(panel: UIPanel) {
    switch panel {
    case .PauseMenu:
        g_paused = true
    case .Keybinds:
        g_rebind_idx = -1
    case .Inventory, .Stats, .MutationTree, .Shop, .Stash, .Settings, .LevelSelect:
        // no extra side effects
    }
}

// Called the moment a panel begins fading out (before it is removed).
@(private = "file")
_ui_on_close :: proc(panel: UIPanel) {
    switch panel {
    case .PauseMenu:
        g_paused = false
    case .Shop:
        g_shop_npc_id = cw.INVALID_ENTITY
    case .Stash:
        g_stash_npc_id = cw.INVALID_ENTITY
    case .Keybinds:
        g_rebind_idx = -1
    case .Inventory, .Stats, .MutationTree, .Settings, .LevelSelect:
        // no extra side effects
    }
}
