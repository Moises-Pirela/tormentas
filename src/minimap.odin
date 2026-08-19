package main

import rl  "vendor:raylib"

// ────────────────────────────────────────────────────────────
// Constants
// ────────────────────────────────────────────────────────────

MINIMAP_BASE_W     :: f32(200)    // panel width in base pixels (scaled by uis)
MINIMAP_EXPLORE_R  :: 5           // tile radius revealed around the player each frame
MINIMAP_EXPLORE_R2 :: MINIMAP_EXPLORE_R * MINIMAP_EXPLORE_R

// Fixed map grid origin (tiles are centered on world-origin)
MINIMAP_TX_ORIGIN :: -(DEFAULT_LEVEL_COLS / 2)
MINIMAP_TY_ORIGIN :: -(DEFAULT_LEVEL_ROWS / 2)

// ────────────────────────────────────────────────────────────
// State
// ────────────────────────────────────────────────────────────

g_minimap_visible:   bool = true
g_explored_tiles:    map[[2]int]bool

// ────────────────────────────────────────────────────────────
// Public API
// ────────────────────────────────────────────────────────────

minimap_clear_explored :: proc() {
    delete(g_explored_tiles)
    g_explored_tiles = make(map[[2]int]bool)
}

minimap_update :: proc(w: ^World) {
    // Lazy init
    if g_explored_tiles == nil {
        g_explored_tiles = make(map[[2]int]bool)
    }

    // Toggle with Tab (gameplay only, not in UI / editor / console)
    if rl.IsKeyPressed(.TAB) && !g_editor_mode && !g_console_open && !ui_any() {
        g_minimap_visible = !g_minimap_visible
    }

    if !g_minimap_visible                                          { return }
    if g_playing_state != .Gameplay && g_playing_state != .Hub    { return }
    if !world_is_valid(w, w.player_id)                         { return }
    if !world_has_component(w, w.player_id, .Transform)        { return }

    // Reveal tiles in a circle around the player
    pp        := comp_get(w, w.player_id, .Transform, TransformComp).position
    ptx, pty  := world_to_tile(pp[0], pp[1])
    R         := MINIMAP_EXPLORE_R

    for dy in -R..=R {
        for dx in -R..=R {
            if dx*dx + dy*dy > MINIMAP_EXPLORE_R2 { continue }
            tx := ptx + dx
            ty := pty + dy
            if tile_exists(tx, ty) {
                g_explored_tiles[[2]int{tx, ty}] = true
            }
        }
    }
}

draw_minimap :: proc(w: ^World) {
    if !g_minimap_visible                                          { return }
    if g_playing_state != .Gameplay && g_playing_state != .Hub    { return }
    if len(g_tilemap) == 0                                         { return }

    sw  := f32(rl.GetScreenWidth())

    cols := f32(DEFAULT_LEVEL_COLS)
    rows := f32(DEFAULT_LEVEL_ROWS)

    // Panel sizing — fixed width, aspect-correct height
    panel_w  := min(uis(MINIMAP_BASE_W), sw * 0.20)
    tile_px  := panel_w / cols
    panel_h  := rows * tile_px

    // Position: top-right, drop below raid timer when it is visible
    pad      := uis(12)
    panel_x  := sw - panel_w - pad
    panel_y  := uis(68) if (g_playing_state == .Gameplay && g_raid_timer > 0) else pad

    // ── Background ───────────────────────────────────────────
    rl.DrawRectangleRec({panel_x, panel_y, panel_w, panel_h}, rl.Color{6, 5, 4, 210})

    // ── Explored floor & wall tiles ──────────────────────────
    for coord, _ in g_explored_tiles {
        tx := coord[0]
        ty := coord[1]
        col := _minimap_tile_color(tile_at(tx, ty))
        if col.a == 0 { continue }
        px := panel_x + f32(tx - MINIMAP_TX_ORIGIN) * tile_px
        py := panel_y + f32(ty - MINIMAP_TY_ORIGIN) * tile_px
        rl.DrawRectangleRec({px, py, tile_px, tile_px}, col)
    }

    // ── Exit / extraction markers ─────────────────────────────
    for ex in g_level_data.exits {
        tx := int(ex.tx)
        ty := int(ex.ty)
        if _, explored := g_explored_tiles[[2]int{tx, ty}]; !explored { continue }
        cx := panel_x + f32(tx - MINIMAP_TX_ORIGIN) * tile_px + tile_px * 0.5
        cy := panel_y + f32(ty - MINIMAP_TY_ORIGIN) * tile_px + tile_px * 0.5
        r  := max(f32(2), tile_px * 1.3)
        rl.DrawCircle(i32(cx), i32(cy), r + 1, rl.Color{80, 220, 120, 60})
        rl.DrawCircle(i32(cx), i32(cy), r,     rl.Color{80, 220, 120, 240})
    }

    // ── NPC markers (teal) ───────────────────────────────────
    npc_ids := world_query(w, query_mask(.NPC, .Transform))
    defer delete(npc_ids)
    for id in npc_ids {
        t  := comp_get(w, id, .Transform, TransformComp)
        tx, ty := world_to_tile(t.position[0], t.position[1])
        if _, explored := g_explored_tiles[[2]int{tx, ty}]; !explored { continue }
        cx := panel_x + f32(tx - MINIMAP_TX_ORIGIN) * tile_px + tile_px * 0.5
        cy := panel_y + f32(ty - MINIMAP_TY_ORIGIN) * tile_px + tile_px * 0.5
        r  := max(f32(1.5), tile_px * 0.8)
        rl.DrawCircle(i32(cx), i32(cy), r, rl.Color{80, 200, 180, 230})
    }

    // ── Enemy markers (red) ──────────────────────────────────
    enemy_ids := world_query(w, query_mask(.AIAgent, .Transform, .Health))
    defer delete(enemy_ids)
    for id in enemy_ids {
        h := comp_get(w, id, .Health, HealthComp)
        if h.current <= 0 { continue }
        t  := comp_get(w, id, .Transform, TransformComp)
        tx, ty := world_to_tile(t.position[0], t.position[1])
        if _, explored := g_explored_tiles[[2]int{tx, ty}]; !explored { continue }
        cx := panel_x + f32(tx - MINIMAP_TX_ORIGIN) * tile_px + tile_px * 0.5
        cy := panel_y + f32(ty - MINIMAP_TY_ORIGIN) * tile_px + tile_px * 0.5
        r  := max(f32(1.5), tile_px * 0.7)
        rl.DrawCircle(i32(cx), i32(cy), r, rl.Color{220, 60, 60, 230})
    }

    // ── Player dot (white with brass glow) ───────────────────
    if world_is_valid(w, w.player_id) && world_has_component(w, w.player_id, .Transform) {
        pp       := comp_get(w, w.player_id, .Transform, TransformComp).position
        ptx, pty := world_to_tile(pp[0], pp[1])
        cx       := panel_x + f32(ptx - MINIMAP_TX_ORIGIN) * tile_px + tile_px * 0.5
        cy       := panel_y + f32(pty - MINIMAP_TY_ORIGIN) * tile_px + tile_px * 0.5
        r        := max(f32(2.5), tile_px * 1.1)
        rl.DrawCircle(i32(cx), i32(cy), r + 2, rl.Color{220, 185, 70, 90})   // glow
        rl.DrawCircle(i32(cx), i32(cy), r,     rl.Color{255, 255, 255, 255}) // dot
    }

    // ── Panel border ─────────────────────────────────────────
    rl.DrawRectangleLinesEx({panel_x, panel_y, panel_w, panel_h}, 1, rl.Color{110, 88, 44, 200})

    // ── Tab hint ─────────────────────────────────────────────
    hint    := cstring("[Tab]")
    hint_fs := uis(9)
    hsz     := rl.MeasureTextEx(g_font_body, hint, hint_fs, 0.5)
    rl.DrawTextEx(g_font_body, hint,
        {panel_x + panel_w - hsz.x, panel_y + panel_h + uis(3)},
        hint_fs, 0.5, rl.Color{80, 72, 50, 130})
}

// ────────────────────────────────────────────────────────────
// Internals
// ────────────────────────────────────────────────────────────

@(private = "file")
_minimap_tile_color :: proc(tt: TileType) -> rl.Color {
    #partial switch tile_base(tt) {
    case .Floor:  return rl.Color{62, 55, 42, 255}
    case .Wall:   return rl.Color{28, 24, 20, 255}
    case .Water:  return rl.Color{30, 55, 105, 255}
    case .Pillar: return rl.Color{72, 65, 50, 255}
    }
    return {}    // alpha == 0 → skip draw
}
