package main


import rl "vendor:raylib"
import cw "clockwork"


UIPanel :: enum {
    Inventory,
    Stats,
    MutationTree,
    Shop,
    Stash,
    AbilityVendor,
    PauseMenu,
    Settings,
    Keybinds,
    LevelSelect,
    Lore,
    Phonograph,
    Social,
    QuestBoard,
}

UILayerState :: enum { FadeIn, Visible, FadeOut }

MAX_UI_LAYERS :: 8

UILayer :: struct {
    panel: UIPanel,
    alpha: f32,
    state: UILayerState,
    dirty: bool,
    rt:    rl.RenderTexture2D,
    rt_ok: bool,
}

UIManager :: struct {
    layers:         [MAX_UI_LAYERS]UILayer,
    count:          int,
    rt_w:           i32,
    rt_h:           i32,
    last_mouse_pos: rl.Vector2,
}


UI_FADE_SPEED :: f32(8.0)


g_ui: UIManager


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


ui_open :: proc(panel: UIPanel) {
    for i in 0..<g_ui.count {
        l := &g_ui.layers[i]
        if l.panel == panel {
            if l.state == .FadeOut {
                l.state = .FadeIn
                l.dirty = true
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


ui_close_top :: proc() {
    if g_ui.count == 0 { return }
    l := &g_ui.layers[g_ui.count - 1]
    if l.state == .FadeOut { return }
    l.state = .FadeOut
    _ui_on_close(l.panel)
}


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


ui_has :: proc(panel: UIPanel) -> bool {
    for i in 0..<g_ui.count {
        l := &g_ui.layers[i]
        if l.panel == panel && l.state != .FadeOut { return true }
    }
    return false
}


ui_top :: proc() -> (panel: UIPanel, ok: bool) {
    for i := g_ui.count - 1; i >= 0; i -= 1 {
        l := &g_ui.layers[i]
        if l.state != .FadeOut { return l.panel, true }
    }
    return {}, false
}


ui_any :: proc() -> bool {
    return g_ui.count > 0
}


ui_mark_dirty :: proc(panel: UIPanel) {
    for i in 0..<g_ui.count {
        if g_ui.layers[i].panel == panel {
            g_ui.layers[i].dirty = true
            return
        }
    }
}


ui_update :: proc(dt: f32) {
    _ui_ensure_rt()


    mp  := rl.GetMousePosition()
    ddx := mp.x - g_ui.last_mouse_pos.x
    ddy := mp.y - g_ui.last_mouse_pos.y
    mouse_event :=
        (ddx*ddx + ddy*ddy > 0.25)        ||
        rl.IsMouseButtonPressed (.LEFT)    ||
        rl.IsMouseButtonPressed (.RIGHT)   ||
        rl.IsMouseButtonPressed (.MIDDLE)  ||
        rl.IsMouseButtonReleased(.LEFT)    ||
        rl.IsMouseButtonReleased(.RIGHT)   ||
        rl.IsMouseButtonReleased(.MIDDLE)
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

                l.dirty = true
            case .Inventory, .Stats, .MutationTree, .Shop, .Stash, .AbilityVendor,
                 .PauseMenu, .Settings, .Keybinds, .LevelSelect, .Lore, .Social, .QuestBoard:

                if mouse_event { l.dirty = true }
            }

        case .FadeOut:
            l.alpha = max(l.alpha - dt * UI_FADE_SPEED, 0)
            if l.alpha <= 0 {

                if l.rt_ok {
                    rl.UnloadRenderTexture(l.rt)
                }
                for j in i..<(g_ui.count - 1) {
                    g_ui.layers[j] = g_ui.layers[j + 1]
                }
                g_ui.layers[g_ui.count - 1] = {}
                g_ui.count -= 1
                continue
            }
        }
        i += 1
    }
}


ui_draw :: proc(w: ^cw.World) {
    if g_ui.count == 0 { return }

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    for i in 0..<g_ui.count {
        l := &g_ui.layers[i]
        if !l.rt_ok { continue }


        if l.dirty {
            rl.BeginTextureMode(l.rt)
            rl.ClearBackground(rl.BLANK)
            _ui_draw_panel(l.panel, w)
            rl.EndTextureMode()
            l.dirty = false
        }


        src  := rl.Rectangle{ 0, f32(g_ui.rt_h), f32(g_ui.rt_w), -f32(g_ui.rt_h) }
        dst  := rl.Rectangle{ 0, 0, sw, sh }
        tint := rl.Color{ 255, 255, 255, u8(l.alpha * 255) }
        rl.DrawTexturePro(l.rt.texture, src, dst, {0, 0}, 0, tint)
    }
}


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

        draw_inventory(w)
        draw_shop_hud(w)
    case .Stash:
        if w == nil { return }
        draw_inventory(w)
        draw_stash_hud(w)
    case .AbilityVendor:
        if w == nil { return }
        draw_ability_vendor_hud(w)
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
    case .Social:
        draw_social_panel()
    case .QuestBoard:
        if w == nil { return }
        draw_quest_board_panel(w)
    }
}


@(private = "file")
_ui_on_open :: proc(panel: UIPanel) {
    switch panel {
    case .PauseMenu:
        g_paused = true
    case .Keybinds:
        g_rebind_idx = -1
    case .Inventory, .Stats, .MutationTree, .Shop, .Stash, .AbilityVendor, .Settings,
         .LevelSelect, .Lore, .Phonograph, .Social, .QuestBoard:

    }
}


@(private = "file")
_ui_on_close :: proc(panel: UIPanel) {
    switch panel {
    case .PauseMenu:
        g_paused = false
    case .Shop:
        g_shop_npc_id = cw.INVALID_ENTITY
    case .Stash:
        g_stash_npc_id = cw.INVALID_ENTITY
    case .AbilityVendor:
        g_ability_vendor_npc_id = cw.INVALID_ENTITY
    case .QuestBoard:
        g_quest_board_npc_id = cw.INVALID_ENTITY
    case .Keybinds:
        g_rebind_idx = -1
    case .Inventory, .Stats, .MutationTree, .Settings, .LevelSelect,
         .Lore, .Phonograph, .Social:

    }
}
