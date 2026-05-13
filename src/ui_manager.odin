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
// Event-driven rendering:
//   Each layer owns its own RenderTexture2D and a dirty flag.  The panel
//   content is only re-rendered when the flag is set, then blitted every frame
//   with its current alpha.  This avoids re-drawing complex UI every frame.
//
//   Always-dirty:  Phonograph (animated progress bar)
//   Mouse-dirty:   all interactive panels — re-render when mouse moves/clicks
//   Event-dirty:   any panel via ui_mark_dirty(panel) for game-state changes
//
// Usage:
//   ui_open(.Inventory)      // push panel (no-op if already open)
//   ui_close_top()           // begin fade-out on topmost panel
//   ui_close(.Shop)          // begin fade-out on a specific panel
//   ui_close_all()           // instant remove all (used on shutdown/reset)
//   ui_has(.Shop)            // true while panel is open or fading in
//   ui_any()                 // true while any panel is visible
//   ui_top()                 // topmost panel, bool ok
//   ui_mark_dirty(.Stats)    // force re-render on next draw
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
    Lore,       // parchment reading panel (env lore items)
    Phonograph, // wax-cylinder playback panel
}

UILayerState :: enum { FadeIn, Visible, FadeOut }

MAX_UI_LAYERS :: 8

UILayer :: struct {
    panel: UIPanel,
    alpha: f32,
    state: UILayerState,
    dirty: bool,               // content needs re-rendering this frame
    rt:    rl.RenderTexture2D, // per-layer cached texture
    rt_ok: bool,               // true once the RT is allocated
}

UIManager :: struct {
    layers:         [MAX_UI_LAYERS]UILayer,
    count:          int,
    rt_w:           i32,
    rt_h:           i32,
    last_mouse_pos: rl.Vector2, // for detecting mouse movement between frames
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
}

ui_destroy :: proc() {
    for i in 0..<g_ui.count {
        if g_ui.layers[i].rt_ok {
            rl.UnloadRenderTexture(g_ui.layers[i].rt)
        }
    }
    g_ui = {}
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

// Recreate every layer's render texture when the window is resized.
@(private = "file")
_ui_ensure_rt :: proc() {
    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()
    if sw == g_ui.rt_w && sh == g_ui.rt_h { return }
    for i in 0..<g_ui.count {
        l := &g_ui.layers[i]
        if l.rt_ok { rl.UnloadRenderTexture(l.rt) }
        l.rt    = rl.LoadRenderTexture(sw, sh)
        l.rt_ok = true
        l.dirty = true
    }
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
            if l.state == .FadeOut {
                l.state = .FadeIn
                l.dirty = true  // may need to reflect state that changed while closing
            }
            return
        }
    }
    if g_ui.count >= MAX_UI_LAYERS { return }
    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()
    g_ui.layers[g_ui.count] = UILayer{
        panel = panel,
        alpha = 0,
        state = .FadeIn,
        dirty = true,
        rt    = rl.LoadRenderTexture(sw, sh),
        rt_ok = true,
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
        if l.rt_ok {
            rl.UnloadRenderTexture(l.rt)
            l.rt_ok = false
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

// Mark a panel's layer dirty so it will be re-rendered next draw.
// Call this from game-logic code when the underlying data changes
// (e.g. item picked up → ui_mark_dirty(.Inventory)).
// Safe to call even when the panel is not open (no-op).
ui_mark_dirty :: proc(panel: UIPanel) {
    for i in 0..<g_ui.count {
        if g_ui.layers[i].panel == panel {
            g_ui.layers[i].dirty = true
            return
        }
    }
}

// ---------------------------------------------------------------------------
// Update  (call once per frame, before draw)
// ---------------------------------------------------------------------------

ui_update :: proc(dt: f32) {
    _ui_ensure_rt()

    // Detect mouse movement and button presses once per frame.
    mp  := rl.GetMousePosition()
    ddx := mp.x - g_ui.last_mouse_pos.x
    ddy := mp.y - g_ui.last_mouse_pos.y
    mouse_event :=
        (ddx*ddx + ddy*ddy > 0.25)       ||
        rl.IsMouseButtonPressed(.LEFT)    ||
        rl.IsMouseButtonPressed(.RIGHT)   ||
        rl.IsMouseButtonPressed(.MIDDLE)
    g_ui.last_mouse_pos = mp

    i := 0
    for i < g_ui.count {
        l := &g_ui.layers[i]
        switch l.state {
        case .FadeIn:
            l.alpha = min(l.alpha + dt * UI_FADE_SPEED, 1)
            if l.alpha >= 1 { l.alpha = 1; l.state = .Visible }

        case .Visible:
            switch l.panel {
            case .Phonograph:
                // Progress bar animates every frame.
                l.dirty = true
            case .Inventory, .Stats, .MutationTree, .Shop, .Stash,
                 .PauseMenu, .Settings, .Keybinds, .LevelSelect, .Lore:
                // Re-render when the mouse interacts (hover states, clicks).
                if mouse_event { l.dirty = true }
            }

        case .FadeOut:
            l.alpha = max(l.alpha - dt * UI_FADE_SPEED, 0)
            if l.alpha <= 0 {
                // Unload this layer's RT before compacting the array.
                if l.rt_ok {
                    rl.UnloadRenderTexture(l.rt)
                }
                for j in i..<(g_ui.count - 1) {
                    g_ui.layers[j] = g_ui.layers[j + 1]
                }
                g_ui.layers[g_ui.count - 1] = {}
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

// Re-renders a layer's texture only when dirty, then blits it to the
// framebuffer with its current alpha.  Layers are drawn bottom-to-top so
// later panels appear in front.
ui_draw :: proc(w: ^cw.World) {
    if g_ui.count == 0 { return }

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    for i in 0..<g_ui.count {
        l := &g_ui.layers[i]
        if !l.rt_ok { continue }

        // Re-render panel content only when the dirty flag is set.
        if l.dirty {
            rl.BeginTextureMode(l.rt)
            rl.ClearBackground(rl.BLANK)
            _ui_draw_panel(l.panel, w)
            rl.EndTextureMode()
            l.dirty = false
        }

        // Always blit — alpha changes every frame during fades.
        // Source rect uses negative height to flip the OpenGL Y axis.
        src  := rl.Rectangle{ 0, f32(g_ui.rt_h), f32(g_ui.rt_w), -f32(g_ui.rt_h) }
        dst  := rl.Rectangle{ 0, 0, sw, sh }
        tint := rl.Color{ 255, 255, 255, u8(l.alpha * 255) }
        rl.DrawTexturePro(l.rt.texture, src, dst, {0, 0}, 0, tint)
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
    case .Lore:
        draw_lore_panel()
    case .Phonograph:
        draw_phonograph_panel()
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
    case .Inventory, .Stats, .MutationTree, .Shop, .Stash, .Settings, .LevelSelect,
         .Lore, .Phonograph:
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
    case .Inventory, .Stats, .MutationTree, .Settings, .LevelSelect,
         .Lore, .Phonograph:
        // no extra side effects
    }
}
