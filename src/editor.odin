package main

import rl  "vendor:raylib"
import     "core:fmt"
import     "core:math"
import     "core:os"
import p2p "p2p"

ED_NAME_LEN   :: 32
ED_MAX_LEVELS :: 100
META_PATH     :: "data/levels/meta.bin"
ED_BANNER_H   :: f32(32)

g_editor_mode: bool

EditorBrush :: enum u8 {
    Floor       = 0,
    Wall        = 1,
    Water       = 2,
    Shopkeeper  = 8,
    MutationWorkbench = 9,
    Erase       = 13,

    Oil         = 14,
    Fire        = 15,

    FireBarrel  = 16,
    WaterBarrel = 17,

    SwitchLever = 19,
    Chest       = 20,
    Crate       = 21,
    LoreItem    = 22,
    Phonograph  = 23,
    KeyPickup   = 24,
    Pillar      = 25,

    Floor1      = 27,
    Floor2      = 28,
    Floor3      = 29,
    Floor4      = 30,
    Wall1       = 31,
    Wall2       = 32,
    Wall3       = 33,
    Pillar1     = 34,
    Pillar2     = 35,

    HubCollision = 36,
    HubWalkable  = 37,

    Module       = 38,
}

g_ed_module_idx:     int

g_ed_brush:          EditorBrush = .HubCollision
g_ed_brush_size:     int = TILE_SIZE
              g_ed_cell_size:     int = TILE_SIZE
              g_ed_grid_cols:     int = DEFAULT_LEVEL_COLS
              g_ed_grid_rows:     int = DEFAULT_LEVEL_ROWS
g_ed_zoom:           f32 = 1.0
g_ed_grid_visible:   bool = true
g_ed_save_msg:       f32
g_ed_level:          int = 1
@(private = "file") g_ed_target_level:   int = 2
@(private = "file") g_ed_meta_loaded:    bool
@(private = "file") g_ed_inited:         bool
g_ed_level_names:    [ED_MAX_LEVELS+1][ED_NAME_LEN]u8
g_ed_level_exists:   [ED_MAX_LEVELS+1]bool
g_ed_filtered:       [ED_MAX_LEVELS+1]int
g_ed_filtered_count: int

@(private = "file")
ed_base_zoom :: proc() -> f32 { return f32(rl.GetScreenHeight()) / 720.0 }

@(private = "file")
ed_level_file :: proc(n: int) -> string {
    return fmt.tprintf("data/levels/level%02d.bin", n)
}

ed_rebuild_filtered :: proc() {
    g_ed_filtered_count = 0
    for i in 0..<ED_MAX_LEVELS+1 {
        if g_ed_level_exists[i] || i == g_ed_level {
            g_ed_filtered[g_ed_filtered_count] = i
            g_ed_filtered_count += 1
        }
    }
}

ed_refresh_exists :: proc() {
    for i in 0..<ED_MAX_LEVELS+1 {
        g_ed_level_exists[i] = os.exists(ed_level_file(i))
    }
    ed_rebuild_filtered()
}

ed_meta_save :: proc() {
    os.make_directory("data/levels")
    raw: [(ED_MAX_LEVELS+1) * ED_NAME_LEN]u8
    for i in 0..<ED_MAX_LEVELS+1 {
        copy(raw[i*ED_NAME_LEN:(i+1)*ED_NAME_LEN], g_ed_level_names[i][:])
    }
    write_game_file(META_PATH, raw[:])
}

@(private = "file")
ed_meta_load :: proc() {
    data, ok := read_game_file(META_PATH, context.temp_allocator)
    if !ok || len(data) < (ED_MAX_LEVELS+1) * ED_NAME_LEN { return }
    for i in 0..<ED_MAX_LEVELS+1 {
        copy(g_ed_level_names[i][:], data[i*ED_NAME_LEN:(i+1)*ED_NAME_LEN])
    }
}

editor_toggle :: proc() {
    if !g_is_host { return }
    if g_playing_state == .Editor {
        restore_n := 0 if g_hub_active else max(g_current_raid_level, 1)
        ed_mode_exit_editor()
        fire_system_reset()
        level_load(restore_n)
        set_playing_state(.Hub if g_hub_active else .Gameplay)
    } else {
        g_ed_level = 0 if g_hub_active else max(g_current_raid_level, 1)
        set_playing_state(.Editor)
        ed_mode_enter_editor()
    }
    if g_editor_mode { g_ed_inited = false }
}

update_editor :: proc(dt: f32) {
    if !g_editor_mode { return }

    if !g_ed_inited {
        g_ed_inited   = true
        g_ed_zoom     = 1.0
        g_camera.zoom = ed_base_zoom() * g_ed_zoom
        if !g_ed_meta_loaded {
            ed_meta_load()
            g_ed_meta_loaded = true
        }
        ed_refresh_exists()
    }

    remote_ops, load_n := p2p.session_drain_editor(&g_session)
    for op in remote_ops { ed_apply_op(op) }
    if load_n > 0 {
        g_ed_level = load_n
        level_load(g_ed_level)
        ed_rebuild_filtered()
        ed_insp_deselect()
    }

    remote_mod_ops := p2p.session_drain_editor_mod_ops(&g_session)
    for op in remote_mod_ops { ed_apply_mod_op(op) }

    ed_insp_update_anim(dt)
    ed_insp_validate()

    mp      := rl.GetMousePosition()
    over_ui := imui_wants_mouse() || ed_insp_over_ui()

    if ed_gizmo_dragging() || (!over_ui && (g_ed_tool == .Select || g_ed_tool == .Place)) {
        ed_gizmo_update(mp)

        if !ed_gizmo_dragging() && rl.IsMouseButtonPressed(.LEFT) && !over_ui {
            switch g_ed_tool {
            case .Place:
                ed_entity_place(screen_to_world_cartesian(mp))
            case .Select:
                ed_entity_capture()
                g_ed_sel_entity = ed_entity_pick(mp)
                ed_entity_snapshot()
            case .Paint, .Erase:
            }
        }
        if rl.IsKeyPressed(.DELETE) { ed_entity_delete_selected() }
        if rl.IsKeyPressed(.ESCAPE) { ed_entity_deselect() }
    }

    if !imui_wants_keys() && !ed_insp_is_text_active() {
        PAL_KEYS := [10]rl.KeyboardKey{
            .ONE, .TWO, .THREE, .FOUR, .FIVE,
            .SIX, .SEVEN, .EIGHT, .NINE, .ZERO,
        }
        for ki in 0..<10 {
            if rl.IsKeyPressed(PAL_KEYS[ki]) && ki < len(ED_BRUSHES) {
                g_ed_brush = ED_BRUSHES[ki]
                g_ed_tool  = .Paint
            }
        }

        if rl.IsKeyPressed(.G) { g_ed_grid_visible = !g_ed_grid_visible }

        if g_ed_brush == .Module {
            if rl.IsKeyPressed(.COMMA)  { ed_cycle_module(-1) }
            if rl.IsKeyPressed(.PERIOD) { ed_cycle_module(+1) }
        }

        shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
        if shift {
            if rl.IsKeyPressed(.LEFT_BRACKET)  { g_ed_brush_size = max(g_ed_cell_size, g_ed_brush_size - g_ed_cell_size) }
            if rl.IsKeyPressed(.RIGHT_BRACKET) { g_ed_brush_size = min(512,             g_ed_brush_size + g_ed_cell_size) }
        } else {
            if rl.IsKeyPressed(.LEFT_BRACKET)  && g_ed_target_level > 0  { g_ed_target_level -= 1 }
            if rl.IsKeyPressed(.RIGHT_BRACKET) && g_ed_target_level < 99 { g_ed_target_level += 1 }
        }

        if rl.IsKeyPressed(.MINUS) && g_ed_level > 0 {
            g_ed_level -= 1
            ed_rebuild_filtered()
            level_load(g_ed_level)
            p2p.session_send_level_load(&g_session, g_ed_level)
        }
        if rl.IsKeyPressed(.EQUAL) && g_ed_level < 99 {
            g_ed_level += 1
            ed_rebuild_filtered()
            level_load(g_ed_level)
            p2p.session_send_level_load(&g_session, g_ed_level)
        }
    }

    wheel := rl.GetMouseWheelMove()
    if wheel != 0 && !over_ui {
        g_ed_zoom = clamp(g_ed_zoom * (1.0 + wheel * 0.12), 0.10, 6.0)
    }
    g_camera.zoom = ed_base_zoom() * g_ed_zoom

    PAN :: f32(400)
    pan_screen: [2]f32
    if !imui_wants_keys() && !ed_insp_is_text_active() {
        if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP)    { pan_screen[1] -= 1 }
        if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN)  { pan_screen[1] += 1 }
        if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT)  { pan_screen[0] -= 1 }
        if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) { pan_screen[0] += 1 }
    }
    pan_mag := math.sqrt(pan_screen[0]*pan_screen[0] + pan_screen[1]*pan_screen[1])
    if pan_mag > 0 {
        pan_screen[0] /= pan_mag
        pan_screen[1] /= pan_mag
    }
    pan_mult := f32(1.8) if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) else f32(1.0)
    spd := PAN / g_ed_zoom * pan_mult
    g_camera.target.x += pan_screen[0] * spd * dt
    g_camera.target.y += pan_screen[1] * spd * dt

    if rl.IsMouseButtonDown(.MIDDLE) {
        d := rl.GetMouseDelta()
        g_camera.target.x -= d.x / g_camera.zoom
        g_camera.target.y -= d.y / g_camera.zoom
    }

    if !over_ui && (g_ed_tool == .Paint || g_ed_tool == .Erase) {
        world_mp := screen_to_world_cartesian(mp)
        tx, ty   := world_to_tile(world_mp.x, world_mp.y)
        brush    := g_ed_tool == .Erase ? EditorBrush.Erase : g_ed_brush

        if g_hub_active {
            cs     := f32(g_ed_cell_size)
            cell_x := int(math.floor(world_mp.x / cs))
            cell_y := int(math.floor(world_mp.y / cs))
            if rl.IsMouseButtonDown(.LEFT) {
                bx, by, n := ed_brush_footprint(cell_x, cell_y, g_ed_cell_size, ed_paint_snap_held())
                for dy in 0..<n {
                    for dx in 0..<n {
                        if brush == .Erase { ed_erase_cell(bx + dx, by + dy) }
                        else               { ed_paint_cell(bx + dx, by + dy) }
                    }
                }
            }
            if rl.IsMouseButtonPressed(.RIGHT) {
                if !ed_try_select_at(tx, ty) {
                    ed_erase_cell(cell_x, cell_y)
                }
            } else if rl.IsMouseButtonDown(.RIGHT) && !ed_insp_has_selection() {
                ed_erase_cell(cell_x, cell_y)
            }
        } else if brush == .Module {
            if rl.IsMouseButtonPressed(.LEFT)  { module_place_at(g_ed_module_idx, tx, ty) }
            if rl.IsMouseButtonPressed(.RIGHT) { module_erase_at(tx, ty) }
        } else {
            if rl.IsMouseButtonDown(.LEFT) {
                bx, by, n := ed_brush_footprint(tx, ty, TILE_SIZE, ed_paint_snap_held())
                for dy in 0..<n {
                    for dx in 0..<n {
                        ed_paint(bx + dx, by + dy, brush)
                    }
                }
            }
            if rl.IsMouseButtonPressed(.RIGHT) {
                if !ed_try_select_at(tx, ty) {
                    ed_erase_objects(tx, ty)
                }
            } else if rl.IsMouseButtonDown(.RIGHT) && !ed_insp_has_selection() {
                ed_erase_objects(tx, ty)
            }
        }
    }

    if !imui_wants_keys() && !ed_insp_is_text_active() && rl.IsKeyPressed(.ESCAPE) {
        ed_insp_deselect()
    }

    ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
    if ctrl && rl.IsKeyPressed(.S) {
        level_save(g_ed_level)
        ed_refresh_exists()
        g_ed_save_msg = 2.0
    }
    if ctrl && rl.IsKeyPressed(.L) {
        level_load(g_ed_level)
        p2p.session_send_level_load(&g_session, g_ed_level)
    }

    if g_ed_save_msg > 0 { g_ed_save_msg -= dt }
}

@(private = "file")
ed_paint :: proc(tx, ty: int, brush: EditorBrush) {
    tl_val := u16(g_ed_target_level & 0xFF)
    op := p2p.EditorOp{
        action       = .Paint,
        brush        = u8(brush),
        tx           = i16(tx),
        ty           = i16(ty),
        target_level = tl_val,
    }
    ed_apply_op(op)
    p2p.session_send_editor_op(&g_session, op)
}

ed_clear_all :: proc() {
    op := p2p.EditorOp{ action = .ClearAll }
    ed_apply_op(op)
    p2p.session_send_editor_op(&g_session, op)
}

ed_reset_grid_walkable :: proc() {
    op := p2p.EditorOp{
        action = .FillWalkable,
        tx     = i16(g_ed_grid_cols),
        ty     = i16(g_ed_grid_rows),
    }
    ed_apply_op(op)
    p2p.session_send_editor_op(&g_session, op)
}

@(private = "file")
ed_fill_walkable :: proc(cols, rows: int) {
    ts      := f32(TILE_SIZE)
    half_cw := f32(cols) * ts * 0.5
    half_ch := f32(rows) * ts * 0.5

    tx0 := int(math.floor(-half_cw / ts))
    ty0 := int(math.floor(-half_ch / ts))
    tx1 := int(math.ceil (  half_cw / ts)) - 1
    ty1 := int(math.ceil (  half_ch / ts)) - 1

    scale := TILE_SIZE / HUB_CELL_RES
    for y in ty0..=ty1 {
        for x in tx0..=tx1 {
            g_tilemap[[2]int{x, y}] = .Floor
            delete_key(&g_overlay_map, [2]int{x, y})
            for sy in 0..<scale {
                for sx in 0..<scale {
                    g_hub_cell_map[[2]int{x*scale+sx, y*scale+sy}] = .Floor
                }
            }
        }
    }
}

ed_visible_world_aabb :: proc() -> (x0, y0, x1, y1: f32) {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    c  := [4]rl.Vector2{
        screen_to_world_cartesian({ 0,  0}),
        screen_to_world_cartesian({sw,  0}),
        screen_to_world_cartesian({sw, sh}),
        screen_to_world_cartesian({ 0, sh}),
    }
    x0, y0, x1, y1 = c[0].x, c[0].y, c[0].x, c[0].y
    for i in 1..<4 {
        x0 = min(x0, c[i].x); x1 = max(x1, c[i].x)
        y0 = min(y0, c[i].y); y1 = max(y1, c[i].y)
    }
    return
}

ed_grid_visible_range :: proc(half_cw, half_ch, cs: f32, num_x, num_y: int) -> (gx0, gy0, gx1, gy1: int) {
    vx0, vy0, vx1, vy1 := ed_visible_world_aabb()
    gx0 = clamp(int(math.floor((vx0 + half_cw) / cs)), 0, num_x)
    gx1 = clamp(int(math.ceil ((vx1 + half_cw) / cs)), 0, num_x)
    gy0 = clamp(int(math.floor((vy0 + half_ch) / cs)), 0, num_y)
    gy1 = clamp(int(math.ceil ((vy1 + half_ch) / cs)), 0, num_y)
    return
}

ed_paint_snap_held :: proc() -> bool {
    return rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
}

ed_brush_footprint :: proc(cx, cy, unit: int, snap: bool) -> (x0, y0, n: int) {
    if snap {
        n  = max(1, g_ed_brush_size / unit)
        x0 = cx - (cx %% n)
        y0 = cy - (cy %% n)
        return
    }
    r := g_ed_brush_size / unit / 2
    return cx - r, cy - r, 2 * r + 1
}

ed_cycle_module :: proc(delta: int) {
    n := module_count()
    if n == 0 { return }
    g_ed_module_idx = (g_ed_module_idx + delta + n) %% n
}

ed_set_cell_size :: proc(v: int) {
    g_ed_cell_size  = clamp(v, 16, 512)
    g_ed_brush_size = max(g_ed_cell_size, (g_ed_brush_size / g_ed_cell_size) * g_ed_cell_size)
}

@(private = "file")
ed_erase :: proc(tx, ty: int) {
    op := p2p.EditorOp{
        action = .Erase,
        tx     = i16(tx),
        ty     = i16(ty),
    }
    ed_apply_op(op)
    p2p.session_send_editor_op(&g_session, op)
}

@(private = "file")
ed_brush_hub_tile :: proc(b: EditorBrush) -> TileType {
    #partial switch b {
    case .Wall,  .Wall1,  .Wall2,  .Wall3,  .HubCollision: return .Wall
    case .Water:                                             return .Water
    case .Pillar,.Pillar1,.Pillar2:                         return .Pillar
    }
    return .Floor
}

@(private = "file")
ed_paint_cell :: proc(cell_x, cell_y: int) {
    cs  := f32(g_ed_cell_size)
    ts  := f32(TILE_SIZE)
    wx0 := f32(cell_x) * cs
    wy0 := f32(cell_y) * cs
    tx0 := int(math.floor(wx0 / ts))
    ty0 := int(math.floor(wy0 / ts))
    tx1 := int(math.floor((wx0 + cs - 0.1) / ts))
    ty1 := int(math.floor((wy0 + cs - 0.1) / ts))
    for ty in ty0..=ty1 {
        for tx in tx0..=tx1 {
            ed_paint(tx, ty, g_ed_brush)
        }
    }

    tt    := ed_brush_hub_tile(g_ed_brush)
    scale := max(1, g_ed_cell_size / HUB_CELL_RES)
    for sy in 0..<scale {
        for sx in 0..<scale {
            g_hub_cell_map[[2]int{cell_x*scale+sx, cell_y*scale+sy}] = tt
        }
    }
}

@(private = "file")
ed_erase_cell :: proc(cell_x, cell_y: int) {
    cs  := f32(g_ed_cell_size)
    ts  := f32(TILE_SIZE)
    wx0 := f32(cell_x) * cs
    wy0 := f32(cell_y) * cs
    tx0 := int(math.floor(wx0 / ts))
    ty0 := int(math.floor(wy0 / ts))
    tx1 := int(math.floor((wx0 + cs - 0.1) / ts))
    ty1 := int(math.floor((wy0 + cs - 0.1) / ts))
    for ty in ty0..=ty1 {
        for tx in tx0..=tx1 {
            ed_erase(tx, ty)
        }
    }
    scale := max(1, g_ed_cell_size / HUB_CELL_RES)
    for sy in 0..<scale {
        for sx in 0..<scale {
            delete_key(&g_hub_cell_map, [2]int{cell_x*scale+sx, cell_y*scale+sy})
        }
    }
}

@(private = "file")
ed_apply_op :: proc(op: p2p.EditorOp) {
    tx := int(op.tx)
    ty := int(op.ty)
    switch op.action {
    case .Paint:
        switch EditorBrush(op.brush) {
        case .Floor:   g_tilemap[[2]int{tx, ty}] = .Floor;   delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Wall:    g_tilemap[[2]int{tx, ty}] = .Wall;    delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Water:   g_tilemap[[2]int{tx, ty}] = .Water;   delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Module:
        case .Pillar:  g_tilemap[[2]int{tx, ty}] = .Pillar;  delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Floor1:  g_tilemap[[2]int{tx, ty}] = .Floor1;  delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Floor2:  g_tilemap[[2]int{tx, ty}] = .Floor2;  delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Floor3:  g_tilemap[[2]int{tx, ty}] = .Floor3;  delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Floor4:  g_tilemap[[2]int{tx, ty}] = .Floor4;  delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Wall1:   g_tilemap[[2]int{tx, ty}] = .Wall1;   delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Wall2:   g_tilemap[[2]int{tx, ty}] = .Wall2;   delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Wall3:   g_tilemap[[2]int{tx, ty}] = .Wall3;   delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Pillar1: g_tilemap[[2]int{tx, ty}] = .Pillar1; delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Pillar2: g_tilemap[[2]int{tx, ty}] = .Pillar2; delete_key(&g_overlay_map, [2]int{tx, ty})
        case .HubCollision: g_tilemap[[2]int{tx, ty}] = .Wall;  delete_key(&g_overlay_map, [2]int{tx, ty})
        case .HubWalkable:  g_tilemap[[2]int{tx, ty}] = .Floor; delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Oil:
            g_tilemap[[2]int{tx, ty}] = .Floor
            g_overlay_map[[2]int{tx, ty}] = .Oil
        case .Fire:
            g_tilemap[[2]int{tx, ty}] = .Floor
            g_overlay_map[[2]int{tx, ty}] = .Fire
        case .FireBarrel, .WaterBarrel:
            btype := u8(0) if EditorBrush(op.brush) == .FireBarrel else u8(1)
            for i := len(g_level_data.barrels) - 1; i >= 0; i -= 1 {
                b := g_level_data.barrels[i]
                if int(b.tx) == tx && int(b.ty) == ty {
                    unordered_remove(&g_level_data.barrels, i)
                }
            }
            append(&g_level_data.barrels, LevelBarrel{
                tx = i16(tx), ty = i16(ty), btype = btype,
            })
        case .Shopkeeper, .MutationWorkbench:
            npc_type := NPCType.Shopkeeper
            if EditorBrush(op.brush) == .MutationWorkbench {
                npc_type = .MutationWorkbench
            }
            for i := len(g_level_data.npcs) - 1; i >= 0; i -= 1 {
                npc := g_level_data.npcs[i]
                if int(npc.tx) == tx && int(npc.ty) == ty {
                    unordered_remove(&g_level_data.npcs, i)
                }
            }
            append(&g_level_data.npcs, LevelNPC{
                tx = i16(tx), ty = i16(ty),
                npc_type = npc_type,
            })
        case .SwitchLever:
            param := u8(op.target_level & 0xFF)
            for i := len(g_level_data.switches) - 1; i >= 0; i -= 1 {
                s := g_level_data.switches[i]
                if int(s.tx) == tx && int(s.ty) == ty {
                    unordered_remove(&g_level_data.switches, i)
                }
            }
            append(&g_level_data.switches, LevelSwitch{
                tx = i16(tx), ty = i16(ty),
                link_id = param, flags = 0x01,
            })
        case .Chest:
            for i := len(g_level_data.containers) - 1; i >= 0; i -= 1 {
                c := g_level_data.containers[i]
                if int(c.tx) == tx && int(c.ty) == ty {
                    unordered_remove(&g_level_data.containers, i)
                }
            }
            append(&g_level_data.containers, LevelContainer{
                tx = i16(tx), ty = i16(ty),
                kind = .Chest, gold_min = 5, gold_max = 25,
            })
        case .Crate:
            for i := len(g_level_data.containers) - 1; i >= 0; i -= 1 {
                c := g_level_data.containers[i]
                if int(c.tx) == tx && int(c.ty) == ty {
                    unordered_remove(&g_level_data.containers, i)
                }
            }
            append(&g_level_data.containers, LevelContainer{
                tx = i16(tx), ty = i16(ty),
                kind = .Crate, gold_min = 0, gold_max = 10,
            })
        case .LoreItem:
            id := u8(op.target_level & 0xFF)
            if id == 0 { id = 1 }
            for i := len(g_level_data.lore_items) - 1; i >= 0; i -= 1 {
                li := g_level_data.lore_items[i]
                if int(li.tx) == tx && int(li.ty) == ty {
                    unordered_remove(&g_level_data.lore_items, i)
                }
            }
            append(&g_level_data.lore_items, LevelLoreItem{
                tx = i16(tx), ty = i16(ty), lore_id = id,
            })
        case .Phonograph:
            id := u8(op.target_level & 0xFF)
            if id == 0 { id = 1 }
            for i := len(g_level_data.phonographs) - 1; i >= 0; i -= 1 {
                ph := g_level_data.phonographs[i]
                if int(ph.tx) == tx && int(ph.ty) == ty {
                    unordered_remove(&g_level_data.phonographs, i)
                }
            }
            append(&g_level_data.phonographs, LevelPhonograph{
                tx = i16(tx), ty = i16(ty), recording_id = id,
            })
        case .KeyPickup:
            id := u8(op.target_level & 0xFF)
            if id == 0 { id = 1 }
            for i := len(g_level_data.key_pickups) - 1; i >= 0; i -= 1 {
                kp := g_level_data.key_pickups[i]
                if int(kp.tx) == tx && int(kp.ty) == ty {
                    unordered_remove(&g_level_data.key_pickups, i)
                }
            }
            append(&g_level_data.key_pickups, LevelKeyPickup{
                tx = i16(tx), ty = i16(ty), key_id = id,
            })
        case .Erase:
            ed_apply_erase(tx, ty)
        }
    case .Erase:
        ed_apply_erase(tx, ty)
    case .EraseObjects:
        _erase_objects(tx, ty)
    case .FillWalkable:
        ed_fill_walkable(max(1, int(op.tx)), max(1, int(op.ty)))
    case .ClearAll:
        tilemap_fill_default()
        level_entities_clear()
        clear(&g_level_data.npcs)
        clear(&g_level_data.barrels)
        clear(&g_level_data.switches)
        clear(&g_level_data.containers)
        clear(&g_level_data.lore_items)
        clear(&g_level_data.phonographs)
        clear(&g_level_data.key_pickups)
    }

    g_wall_mask_dirty = true
}

@(private = "file")
_erase_objects :: proc(tx, ty: int) {
    for i := len(g_level_data.npcs) - 1; i >= 0; i -= 1 {
        npc := g_level_data.npcs[i]
        if int(npc.tx) == tx && int(npc.ty) == ty {
            unordered_remove(&g_level_data.npcs, i)
        }
    }
    for i := len(g_level_data.barrels) - 1; i >= 0; i -= 1 {
        b := g_level_data.barrels[i]
        if int(b.tx) == tx && int(b.ty) == ty {
            unordered_remove(&g_level_data.barrels, i)
        }
    }
    for i := len(g_level_data.switches) - 1; i >= 0; i -= 1 {
        s := g_level_data.switches[i]
        if int(s.tx) == tx && int(s.ty) == ty {
            unordered_remove(&g_level_data.switches, i)
        }
    }
    for i := len(g_level_data.containers) - 1; i >= 0; i -= 1 {
        c := g_level_data.containers[i]
        if int(c.tx) == tx && int(c.ty) == ty {
            unordered_remove(&g_level_data.containers, i)
        }
    }
    for i := len(g_level_data.lore_items) - 1; i >= 0; i -= 1 {
        li := g_level_data.lore_items[i]
        if int(li.tx) == tx && int(li.ty) == ty {
            unordered_remove(&g_level_data.lore_items, i)
        }
    }
    for i := len(g_level_data.phonographs) - 1; i >= 0; i -= 1 {
        ph := g_level_data.phonographs[i]
        if int(ph.tx) == tx && int(ph.ty) == ty {
            unordered_remove(&g_level_data.phonographs, i)
        }
    }
    for i := len(g_level_data.key_pickups) - 1; i >= 0; i -= 1 {
        kp := g_level_data.key_pickups[i]
        if int(kp.tx) == tx && int(kp.ty) == ty {
            unordered_remove(&g_level_data.key_pickups, i)
        }
    }
}

@(private = "file")
ed_apply_erase :: proc(tx, ty: int) {
    delete_key(&g_tilemap,    [2]int{tx, ty})
    delete_key(&g_overlay_map,[2]int{tx, ty})
    _erase_objects(tx, ty)
}

@(private = "file")
ed_erase_objects :: proc(tx, ty: int) {
    op := p2p.EditorOp{
        action = .EraseObjects,
        tx     = i16(tx),
        ty     = i16(ty),
    }
    ed_apply_op(op)
    p2p.session_send_editor_op(&g_session, op)
}

draw_editor_world :: proc() {
    if !g_editor_mode { return }

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    lw := 1.0 / g_camera.zoom

    tl := screen_to_world_cartesian({0, 0})
    br := screen_to_world_cartesian({sw, sh})

    tx0 := int(math.floor(tl.x / f32(TILE_SIZE))) - 1
    ty0 := int(math.floor(tl.y / f32(TILE_SIZE))) - 1
    tx1 := int(math.floor(br.x / f32(TILE_SIZE))) + 2
    ty1 := int(math.floor(br.y / f32(TILE_SIZE))) + 2

    if EditorBrush(g_ed_brush) == .Module && module_count() > 0 {
        wc := screen_to_world_cartesian(rl.GetMousePosition())
        mtx, mty := world_to_tile(wc.x, wc.y)
        module_draw_ghost(g_ed_module_idx, mtx, mty)
    }

    if g_hub_active {
        cs      := f32(g_ed_cell_size)
        half_cw := f32(g_ed_grid_cols) * f32(TILE_SIZE) * 0.5
        half_ch := f32(g_ed_grid_rows) * f32(TILE_SIZE) * 0.5
        num_x   := max(1, int(f32(g_ed_grid_cols) * f32(TILE_SIZE) / cs))
        num_y   := max(1, int(f32(g_ed_grid_rows) * f32(TILE_SIZE) / cs))
        cell_col := rl.Color{0, 240, 210, 160}
        bnd_col  := rl.Color{0, 255, 220, 255}

        if g_ed_grid_visible {
            gx0, gy0, gx1, gy1 := ed_grid_visible_range(half_cw, half_ch, cs, num_x, num_y)

            wy_a := -half_ch + f32(gy0) * cs
            wy_b := -half_ch + f32(gy1) * cs
            for gx in gx0..=gx1 {
                wx := -half_cw + f32(gx) * cs
                rl.DrawLineEx(world_to_iso_xy(wx, wy_a), world_to_iso_xy(wx, wy_b), lw, cell_col)
            }

            wx_a := -half_cw + f32(gx0) * cs
            wx_b := -half_cw + f32(gx1) * cs
            for gy in gy0..=gy1 {
                wy := -half_ch + f32(gy) * cs
                rl.DrawLineEx(world_to_iso_xy(wx_a, wy), world_to_iso_xy(wx_b, wy), lw, cell_col)
            }

            corners := [4]rl.Vector2{
                world_to_iso_xy(-half_cw, -half_ch), world_to_iso_xy(half_cw, -half_ch),
                world_to_iso_xy( half_cw,  half_ch), world_to_iso_xy(-half_cw,  half_ch),
            }
            for i in 0..<4 {
                rl.DrawLineEx(corners[i], corners[(i+1)%4], lw * 2, bnd_col)
            }
        }

        {
            world_mp_c := screen_to_world_cartesian(rl.GetMousePosition())
            cur_cx := int(math.floor(world_mp_c.x / cs))
            cur_cy := int(math.floor(world_mp_c.y / cs))
            fx, fy, fn := ed_brush_footprint(cur_cx, cur_cy, g_ed_cell_size, ed_paint_snap_held())
            fill_col, brd_col := ed_brush_colors(g_ed_brush)

            bx0 := f32(fx) * cs;      by0 := f32(fy) * cs
            bx1 := f32(fx + fn) * cs; by1 := f32(fy + fn) * cs
            btop    := world_to_iso_xy(bx0, by0)
            bright  := world_to_iso_xy(bx1, by0)
            bbottom := world_to_iso_xy(bx1, by1)
            bleft   := world_to_iso_xy(bx0, by1)
            rl.DrawTriangle(btop, bright, bbottom, fill_col)
            rl.DrawTriangle(btop, bbottom, bleft,  fill_col)
            rl.DrawLineEx(btop,    bright,  lw * 2.5, brd_col)
            rl.DrawLineEx(bright,  bbottom, lw * 2.5, brd_col)
            rl.DrawLineEx(bbottom, bleft,   lw * 2.5, brd_col)
            rl.DrawLineEx(bleft,   btop,    lw * 2.5, brd_col)
        }
    } else {
        if g_ed_grid_visible {
            grid_col := rl.Color{80, 76, 60, 55}
            ts       := f32(TILE_SIZE)

            for gy in ty0..=ty1 {
                gx := tx0
                for gx <= tx1 {
                    if !tile_exists(gx, gy) { gx += 1; continue }
                    run := gx
                    for run + 1 <= tx1 && tile_exists(run + 1, gy) { run += 1 }
                    ax := f32(gx) * ts;        bx := f32(run + 1) * ts
                    ay := f32(gy) * ts;        by := f32(gy + 1) * ts
                    rl.DrawLineEx(world_to_iso_xy(ax, ay), world_to_iso_xy(bx, ay), lw, grid_col)
                    rl.DrawLineEx(world_to_iso_xy(ax, by), world_to_iso_xy(bx, by), lw, grid_col)
                    gx = run + 1
                }
            }

            for gx in tx0..=tx1 {
                gy := ty0
                for gy <= ty1 {
                    if !tile_exists(gx, gy) { gy += 1; continue }
                    run := gy
                    for run + 1 <= ty1 && tile_exists(gx, run + 1) { run += 1 }
                    ax := f32(gx) * ts;        bx := f32(gx + 1) * ts
                    ay := f32(gy) * ts;        by := f32(run + 1) * ts
                    rl.DrawLineEx(world_to_iso_xy(ax, ay), world_to_iso_xy(ax, by), lw, grid_col)
                    rl.DrawLineEx(world_to_iso_xy(bx, ay), world_to_iso_xy(bx, by), lw, grid_col)
                    gy = run + 1
                }
            }
        }
    }

    {
        CAM_BOUNDS_COL      :: rl.Color{90, 170, 255, 220}
        CAM_BOUNDS_FALLBACK :: f32(8192)
        lims  := g_level_data.cam_lims
        has_x := lims[1] > lims[0]
        has_y := lims[3] > lims[2]
        if has_x || has_y {
            minx := lims[0] if has_x else -CAM_BOUNDS_FALLBACK
            maxx := lims[1] if has_x else  CAM_BOUNDS_FALLBACK
            miny := lims[2] if has_y else -CAM_BOUNDS_FALLBACK
            maxy := lims[3] if has_y else  CAM_BOUNDS_FALLBACK
            ctl := rl.Vector2{minx, miny}
            ctr := rl.Vector2{maxx, miny}
            cbr := rl.Vector2{maxx, maxy}
            cbl := rl.Vector2{minx, maxy}
            if has_y {
                rl.DrawLineEx(ctl, ctr, lw * 2, CAM_BOUNDS_COL)
                rl.DrawLineEx(cbl, cbr, lw * 2, CAM_BOUNDS_COL)
            }
            if has_x {
                rl.DrawLineEx(ctl, cbl, lw * 2, CAM_BOUNDS_COL)
                rl.DrawLineEx(ctr, cbr, lw * 2, CAM_BOUNDS_COL)
            }
        }
    }

    ts := f32(TILE_SIZE)
    fs := ts * 0.22
    cr := ts * 0.30

    if g_sim_alive {
        anchor_ids := world_query(&g_sim.world, query_mask(.SpawnAnchor, .Transform))
        for id in anchor_ids {
            p  := comp_get(&g_sim.world, id, .Transform, TransformComp).position
            ip := world_to_iso_xy(p[0], p[1])
            rl.DrawCircleV(ip, cr, rl.Color{190, 60, 60, 220})
            rl.DrawCircleV(ip, cr * 0.65, rl.Color{0, 0, 0, 100})
            lsz := rl.MeasureTextEx(g_font, "Sp", fs, 0.5)
            rl.DrawTextEx(g_font, "Sp", {ip.x - lsz.x*0.5, ip.y - lsz.y*0.5}, fs, 0.5,
                rl.Color{255, 240, 200, 230})
        }
        delete(anchor_ids)

        EXIT_COL :: rl.Color{50, 200, 90, 180}
        exit_ids := world_query(&g_sim.world, query_mask(.LevelExit, .Transform))
        for id in exit_ids {
            le := comp_get(&g_sim.world, id, .LevelExit, LevelExitComp)
            p  := comp_get(&g_sim.world, id, .Transform, TransformComp).position
            etx, ety := world_to_tile(p[0], p[1])
            center, top, right, bottom, left := iso_tile_bounds(etx, ety)
            iso_draw_shadow_diamond(center, ISO_TILE_W * 2, ISO_TILE_H * 2, rl.Color{30, 140, 60, 80})
            rl.DrawLineEx(top, right, lw * 2.5, EXIT_COL)
            rl.DrawLineEx(right, bottom, lw * 2.5, EXIT_COL)
            rl.DrawLineEx(bottom, left, lw * 2.5, EXIT_COL)
            rl.DrawLineEx(left, top, lw * 2.5, EXIT_COL)
            buf: [8]u8
            s := fmt.bprintf(buf[:7], "->%d", le.target_level)
            buf[len(s)] = 0
            lsz := rl.MeasureTextEx(g_font, cstring(&buf[0]), fs, 0.5)
            rl.DrawTextEx(g_font, cstring(&buf[0]),
                {center.x - lsz.x*0.5, center.y - lsz.y*0.5},
                fs, 0.5, rl.Color{140, 255, 160, 230})
        }
        delete(exit_ids)
    }

    for npc in g_level_data.npcs {
        wx := f32(int(npc.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(npc.ty) * TILE_SIZE + TILE_SIZE / 2)
        ip := world_to_iso_xy(wx, wy)
        col := rl.Color{212, 190, 92, 220}
        label := cstring("S")
        if npc.npc_type == .MutationWorkbench {
            col = rl.Color{180, 90, 220, 220}
            label = cstring("M")
        }
        rl.DrawRectangleV({ip.x - ts * 0.18, ip.y - ts * 0.30}, {ts * 0.36, ts * 0.36}, rl.Color{col.r, col.g, col.b, 70})
        rl.DrawRectangleLinesEx({ip.x - ts * 0.18, ip.y - ts * 0.30, ts * 0.36, ts * 0.36}, lw * 2.0, col)
        lsz := rl.MeasureTextEx(g_font, label, fs * 1.1, 0.5)
        rl.DrawTextEx(g_font, label,
            {ip.x - lsz.x * 0.5, ip.y - lsz.y * 0.5},
            fs * 1.1, 0.5, col)
    }

    LIGHT_COL :: rl.Color{255, 210, 80, 200}
    if g_sim_alive {
        light_ids := world_query(&g_sim.world, query_mask(.PointLight, .Transform))
        for id in light_ids {
            pl := comp_get(&g_sim.world, id, .PointLight, PointLightComp)
            p  := comp_get(&g_sim.world, id, .Transform, TransformComp).position
            ip := world_to_iso_xy(p[0], p[1])

            rl.DrawCircleV(ip, cr * 1.2, rl.Color{u8(pl.color[0]), u8(pl.color[1]), u8(pl.color[2]), 60})
            rl.DrawCircleV(ip, cr * 0.7, LIGHT_COL)
            rl.DrawCircleLinesV(ip, cr * 1.2, rl.Color{255, 220, 100, 160})
            lsz := rl.MeasureTextEx(g_font, "L", fs * 1.1, 0.5)
            rl.DrawTextEx(g_font, "L",
                {ip.x - lsz.x*0.5, ip.y - lsz.y*0.5},
                fs * 1.1, 0.5, rl.Color{40, 30, 0, 240})
        }
        delete(light_ids)
    }

    for b in g_level_data.barrels {
        wx := f32(int(b.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(b.ty) * TILE_SIZE + TILE_SIZE / 2)
        ip := world_to_iso_xy(wx, wy)
        is_fire := b.btype == 0
        body_col  := rl.Color{200,  72,  18, 220} if is_fire else rl.Color{ 28, 100, 210, 220}
        ring_col  := rl.Color{240, 120,  30, 200} if is_fire else rl.Color{ 70, 160, 255, 200}
        label_cs  := cstring("FB")           if is_fire else cstring("WB")

        body_h := ts * 0.24
        body_w := ts * 0.22

        rl.DrawRectangle(
            i32(ip.x - body_w * 0.5), i32(ip.y - body_h * 0.75),
            i32(body_w), i32(body_h),
            rl.Color{body_col.r, body_col.g, body_col.b, 60})
        rl.DrawRectangleLinesEx(
            {ip.x - body_w * 0.5, ip.y - body_h * 0.75, body_w, body_h},
            lw * 2.0, body_col)

        rl.DrawEllipse(i32(ip.x), i32(ip.y - body_h * 0.75),
            body_w * 0.5, body_h * 0.22, rl.Color{ring_col.r, ring_col.g, ring_col.b, 90})
        rl.DrawEllipseLines(i32(ip.x), i32(ip.y - body_h * 0.75),
            body_w * 0.5, body_h * 0.22, ring_col)

        rl.DrawEllipseLines(i32(ip.x), i32(ip.y - body_h * 0.20),
            body_w * 0.5, body_h * 0.12, ring_col)

        lsz := rl.MeasureTextEx(g_font, label_cs, fs * 0.85, 0.5)
        rl.DrawTextEx(g_font, label_cs,
            {ip.x - lsz.x * 0.5, ip.y - body_h * 0.45 - lsz.y * 0.5},
            fs * 0.85, 0.5, rl.Color{255, 240, 220, 240})
    }

    LEVER_COL :: rl.Color{60, 180, 60, 220}
    for s in g_level_data.switches {
        wx := f32(int(s.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(s.ty) * TILE_SIZE + TILE_SIZE / 2)
        ip := world_to_iso_xy(wx, wy)

        rl.DrawRectangleRec({ip.x - ts*0.14, ip.y + ts*0.02, ts*0.28, ts*0.12},
            rl.Color{LEVER_COL.r, LEVER_COL.g, LEVER_COL.b, 60})
        rl.DrawRectangleLinesEx({ip.x - ts*0.14, ip.y + ts*0.02, ts*0.28, ts*0.12},
            lw * 2, LEVER_COL)

        rl.DrawLineEx({ip.x, ip.y + ts*0.08}, {ip.x + ts*0.12, ip.y - ts*0.18},
            lw * 3, LEVER_COL)
        rl.DrawCircleV({ip.x + ts*0.12, ip.y - ts*0.18}, ts * 0.05, LEVER_COL)
        if s.link_id != 0 {
            buf: [8]u8
            str := fmt.bprintf(buf[:7], "L%d", s.link_id)
            buf[len(str)] = 0
            lsz := rl.MeasureTextEx(g_font, cstring(&buf[0]), fs * 0.8, 0.5)
            rl.DrawTextEx(g_font, cstring(&buf[0]),
                {ip.x - lsz.x*0.5, ip.y - ts*0.30},
                fs * 0.8, 0.5, rl.Color{120, 240, 120, 220})
        }
    }

    for c in g_level_data.containers {
        wx := f32(int(c.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(c.ty) * TILE_SIZE + TILE_SIZE / 2)
        ip := world_to_iso_xy(wx, wy)
        col: rl.Color
        lbl: cstring
        switch c.kind {
        case .Chest:   col = rl.Color{210, 175, 40, 220}; lbl = "CH"
        case .Crate:   col = rl.Color{150, 110, 55, 220}; lbl = "CR"
        case .Locker:  col = rl.Color{100, 140, 180, 220}; lbl = "LK"
        case .Cabinet: col = rl.Color{140, 100, 160, 220}; lbl = "CB"
        }
        box_w := ts * 0.32
        box_h := ts * 0.28
        rl.DrawRectangleRec({ip.x - box_w*0.5, ip.y - box_h*0.6, box_w, box_h},
            rl.Color{col.r, col.g, col.b, 45})
        rl.DrawRectangleLinesEx({ip.x - box_w*0.5, ip.y - box_h*0.6, box_w, box_h},
            lw * 2.5, col)

        rl.DrawLineEx({ip.x - box_w*0.5, ip.y - box_h*0.22},
                      {ip.x + box_w*0.5, ip.y - box_h*0.22},
                      lw * 1.5, rl.Color{col.r, col.g, col.b, 160})
        lsz := rl.MeasureTextEx(g_font, lbl, fs * 0.85, 0.5)
        rl.DrawTextEx(g_font, lbl,
            {ip.x - lsz.x*0.5, ip.y - box_h*0.1 - lsz.y*0.5},
            fs * 0.85, 0.5, col)
    }

    LORE_COL :: rl.Color{80, 160, 220, 220}
    for li in g_level_data.lore_items {
        wx := f32(int(li.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(li.ty) * TILE_SIZE + TILE_SIZE / 2)
        ip := world_to_iso_xy(wx, wy)

        pw := ts * 0.22
        ph := ts * 0.28
        rl.DrawRectangleRec({ip.x - pw*0.5, ip.y - ph*0.7, pw, ph},
            rl.Color{LORE_COL.r, LORE_COL.g, LORE_COL.b, 40})
        rl.DrawRectangleLinesEx({ip.x - pw*0.5, ip.y - ph*0.7, pw, ph},
            lw * 2, LORE_COL)

        rl.DrawLineEx({ip.x + pw*0.5 - pw*0.25, ip.y - ph*0.7},
                      {ip.x + pw*0.5, ip.y - ph*0.7 + ph*0.25},
                      lw * 1.5, LORE_COL)

        for row in 0..<3 {
            lx0 := ip.x - pw*0.35
            lx1 := ip.x + pw*0.35 * (0.7 if row == 2 else 1.0)
            ly  := ip.y - ph*0.55 + f32(row) * ph * 0.22
            rl.DrawLineEx({lx0, ly}, {lx1, ly}, lw, rl.Color{LORE_COL.r, LORE_COL.g, LORE_COL.b, 130})
        }
        buf: [6]u8
        s := fmt.bprintf(buf[:5], "#%d", li.lore_id)
        buf[len(s)] = 0
        lsz := rl.MeasureTextEx(g_font, cstring(&buf[0]), fs * 0.75, 0.5)
        rl.DrawTextEx(g_font, cstring(&buf[0]),
            {ip.x - lsz.x*0.5, ip.y - ph*0.7 - lsz.y - uis(2)},
            fs * 0.75, 0.5, rl.Color{120, 200, 255, 220})
    }

    PHONO_COL :: rl.Color{180, 80, 200, 220}
    for ph in g_level_data.phonographs {
        wx := f32(int(ph.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(ph.ty) * TILE_SIZE + TILE_SIZE / 2)
        ip := world_to_iso_xy(wx, wy)

        rl.DrawEllipse(i32(ip.x), i32(ip.y), ts*0.20, ts*0.07, rl.Color{PHONO_COL.r, PHONO_COL.g, PHONO_COL.b, 50})
        rl.DrawEllipseLines(i32(ip.x), i32(ip.y), ts*0.20, ts*0.07, PHONO_COL)

        rl.DrawTriangle(
            {ip.x + ts*0.22, ip.y - ts*0.26},
            {ip.x + ts*0.10, ip.y - ts*0.02},
            {ip.x + ts*0.10, ip.y + ts*0.04},
            rl.Color{PHONO_COL.r, PHONO_COL.g, PHONO_COL.b, 60})
        rl.DrawLineEx({ip.x + ts*0.10, ip.y - ts*0.02},
                      {ip.x + ts*0.22, ip.y - ts*0.26},
                      lw * 2, PHONO_COL)
        buf: [6]u8
        s := fmt.bprintf(buf[:5], "#%d", ph.recording_id)
        buf[len(s)] = 0
        lsz := rl.MeasureTextEx(g_font, cstring(&buf[0]), fs * 0.75, 0.5)
        rl.DrawTextEx(g_font, cstring(&buf[0]),
            {ip.x - lsz.x*0.5, ip.y - ts*0.38},
            fs * 0.75, 0.5, rl.Color{220, 120, 240, 220})
    }

    KEY_COL :: rl.Color{245, 210, 30, 230}
    for kp in g_level_data.key_pickups {
        wx := f32(int(kp.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(kp.ty) * TILE_SIZE + TILE_SIZE / 2)
        ip := world_to_iso_xy(wx, wy)

        rl.DrawCircleV({ip.x - ts*0.06, ip.y - ts*0.10}, ts*0.10,
            rl.Color{KEY_COL.r, KEY_COL.g, KEY_COL.b, 50})
        rl.DrawCircleLinesV({ip.x - ts*0.06, ip.y - ts*0.10}, ts*0.10, KEY_COL)

        rl.DrawCircleLinesV({ip.x - ts*0.06, ip.y - ts*0.10}, ts*0.04,
            rl.Color{KEY_COL.r, KEY_COL.g, KEY_COL.b, 180})

        rl.DrawLineEx({ip.x - ts*0.06 + ts*0.10, ip.y - ts*0.10},
                      {ip.x + ts*0.20, ip.y - ts*0.10},
                      lw * 2.5, KEY_COL)

        rl.DrawLineEx({ip.x + ts*0.14, ip.y - ts*0.10},
                      {ip.x + ts*0.14, ip.y - ts*0.03},
                      lw * 2, KEY_COL)
        rl.DrawLineEx({ip.x + ts*0.20, ip.y - ts*0.10},
                      {ip.x + ts*0.20, ip.y - ts*0.04},
                      lw * 2, KEY_COL)
        buf: [6]u8
        s := fmt.bprintf(buf[:5], "K%d", kp.key_id)
        buf[len(s)] = 0
        lsz := rl.MeasureTextEx(g_font, cstring(&buf[0]), fs * 0.8, 0.5)
        rl.DrawTextEx(g_font, cstring(&buf[0]),
            {ip.x - lsz.x*0.5, ip.y + ts*0.12},
            fs * 0.8, 0.5, rl.Color{255, 230, 60, 230})
    }

    if g_sim_alive {
        ps_ids := world_query(&g_sim.world, query_mask(.PlayerStart, .Transform))
        for id in ps_ids {
            p := comp_get(&g_sim.world, id, .Transform, TransformComp).position
            ptx, pty := world_to_tile(p[0], p[1])
            center, top, right, bottom, left := iso_tile_bounds(ptx, pty)
            iso_draw_shadow_diamond(center, ISO_TILE_W * 2, ISO_TILE_H * 2, rl.Color{200, 160, 30, 70})
            rl.DrawLineEx(top, right, lw * 2.5, rl.Color{255, 200, 50, 220})
            rl.DrawLineEx(right, bottom, lw * 2.5, rl.Color{255, 200, 50, 220})
            rl.DrawLineEx(bottom, left, lw * 2.5, rl.Color{255, 200, 50, 220})
            rl.DrawLineEx(left, top, lw * 2.5, rl.Color{255, 200, 50, 220})
            lsz := rl.MeasureTextEx(g_font, "P", fs*1.2, 0.5)
            rl.DrawTextEx(g_font, "P",
                {center.x - lsz.x*0.5, center.y - lsz.y*0.5},
                fs*1.2, 0.5, rl.Color{255, 230, 100, 240})
        }
        delete(ps_ids)
    }

    ed_insp_draw_selection_highlight()

    if !g_hub_active {
        mp       := rl.GetMousePosition()
        world_mp := screen_to_world_cartesian(mp)
        ctx, cty := world_to_tile(world_mp.x, world_mp.y)
        fx, fy, fn := ed_brush_footprint(ctx, cty, TILE_SIZE, ed_paint_snap_held())
        tsz := f32(TILE_SIZE)
        bx0 := f32(fx) * tsz;      by0 := f32(fy) * tsz
        bx1 := f32(fx + fn) * tsz; by1 := f32(fy + fn) * tsz
        btop    := world_to_iso_xy(bx0, by0)
        bright  := world_to_iso_xy(bx1, by0)
        bbottom := world_to_iso_xy(bx1, by1)
        bleft   := world_to_iso_xy(bx0, by1)
        fill_col, brd_col := ed_brush_colors(g_ed_brush)
        rl.DrawTriangle(btop, bright, bbottom, fill_col)
        rl.DrawTriangle(btop, bbottom, bleft,  fill_col)
        rl.DrawLineEx(btop,    bright,  lw * 2, brd_col)
        rl.DrawLineEx(bright,  bbottom, lw * 2, brd_col)
        rl.DrawLineEx(bbottom, bleft,   lw * 2, brd_col)
        rl.DrawLineEx(bleft,   btop,    lw * 2, brd_col)
    }
}

@(private = "file")
ed_brush_colors :: proc(b: EditorBrush) -> (fill, brd: rl.Color) {
    switch b {
    case .Floor:       return {110,  95,  65,  85}, {200, 170,  90, 200}
    case .Wall:        return { 70, 105, 140,  85}, { 90, 150, 210, 200}
    case .Water:       return { 18,  60, 130,  90}, { 40, 120, 220, 210}
    case .Module:      return { 40,  90, 160,  90}, { 90, 150, 230, 210}
    case .Shopkeeper:  return {180, 148,  62,  70}, {230, 200, 100, 210}
    case .MutationWorkbench: return {150,  60, 180,  70}, {210, 110, 255, 210}
    case .Oil:         return { 18,  14,  10,  90}, { 60,  80,  50, 200}
    case .Fire:        return { 90,  22,   6,  90}, {240,  80,  15, 210}
    case .FireBarrel:  return {120,  40,   8,  80}, {230,  90,  20, 210}
    case .WaterBarrel: return {  8,  42,  90,  80}, { 60, 150, 230, 210}
    case .SwitchLever: return { 24,  56,  24,  85}, { 60, 160,  60, 210}
    case .Chest:       return { 88,  68,  14,  85}, {210, 175,  40, 210}
    case .Crate:       return { 54,  38,  18,  85}, {150, 110,  55, 210}
    case .LoreItem:    return { 20,  42,  72,  85}, { 60, 120, 200, 210}
    case .Phonograph:  return { 62,  28,  62,  85}, {170,  70, 180, 210}
    case .KeyPickup:   return { 96,  84,  10,  85}, {245, 210,  30, 210}
    case .Pillar:      return { 80,  70,  56,  85}, {170, 148, 115, 210}
    case .Floor1:      return { 34,  30,  24,  85}, {110,  96,  68, 210}
    case .Floor2:      return { 40,  36,  28,  85}, {124, 108,  76, 210}
    case .Floor3:      return { 46,  40,  32,  85}, {138, 120,  84, 210}
    case .Floor4:      return { 52,  46,  36,  85}, {152, 132,  92, 210}
    case .Wall1:       return { 62,  54,  44,  85}, {150, 130,  98, 210}
    case .Wall2:       return { 70,  60,  48,  85}, {165, 143, 107, 210}
    case .Wall3:       return { 78,  66,  52,  85}, {180, 156, 116, 210}
    case .Pillar1:     return { 72,  64,  52,  85}, {175, 152, 118, 210}
    case .Pillar2:     return { 80,  70,  58,  85}, {185, 162, 126, 210}
    case .Erase:        return {170,  45,  45,  85}, {220,  70,  70, 200}
    case .HubCollision: return {160,  30,  30,  90}, {220,  55,  55, 210}
    case .HubWalkable:  return { 30, 160,  40,  90}, { 55, 220,  70, 210}
    }
    return {128, 128, 128, 85}, {200, 200, 200, 200}
}

draw_editor_hud :: proc() {
    if !g_editor_mode { return }

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    rl.DrawRectangle(0, 0, i32(sw), i32(uis(ED_BANNER_H)), rl.Color{8, 6, 4, 235})
    rl.DrawRectangle(0, i32(uis(ED_BANNER_H-2)), i32(sw), i32(uis(2)),
        rl.Color{180, 150, 60, 220})

    title_cs := cstring("-- EDITOR --")
    title_sz := rl.MeasureTextEx(g_font, title_cs, uis(13), 1)
    rl.DrawTextEx(g_font, title_cs,
        {sw*0.5 - title_sz.x*0.5, uis(9)}, uis(13), 1,
        rl.Color{220, 190, 80, 255})

    left_hint := cstring("1-6:Brush  LMB:Paint  RMB:Select/EraseObj  WASD:Pan  [/]:ID  ,/.:Module  -/=:Level")
    rl.DrawTextEx(g_font, left_hint, {uis(8), uis(10)}, uis(7.5), 0.5,
        rl.Color{140, 128, 95, 190})

    right_hint := cstring("Scroll:Zoom  Mid:Drag  F5:Live  Ctrl+S:Save  Ctrl+L:Load  F1:Exit")
    rhsz := rl.MeasureTextEx(g_font, right_hint, uis(7.5), 0.5)
    rl.DrawTextEx(g_font, right_hint,
        {sw - rhsz.x - uis(8), uis(10)}, uis(7.5), 0.5,
        rl.Color{140, 128, 95, 190})

    if g_ed_save_msg > 0 {
        alpha   := u8(clamp(g_ed_save_msg, 0, 1) * 255)
        save_cs := cstring("Saved!")
        save_sz := rl.MeasureTextEx(g_font, save_cs, uis(22), 1)
        rl.DrawTextEx(g_font, save_cs,
            {sw*0.5 - save_sz.x*0.5, sh*0.44},
            uis(22), 1, rl.Color{85, 210, 85, alpha})
    }

    ed_insp_draw_panel()
}

draw_editor_cell_overlay :: proc() {
    if !g_editor_mode { return }

    cell_fill :: proc(top, right, bottom, left: rl.Vector2, col: rl.Color) {
        rl.DrawTriangle(top, bottom, right, col)
        rl.DrawTriangle(top, left,   bottom, col)
    }

    if g_hub_active {
        if !g_ed_grid_visible { return }

        cs      := f32(g_ed_cell_size)
        half_cw := f32(g_ed_grid_cols) * f32(TILE_SIZE) * 0.5
        half_ch := f32(g_ed_grid_rows) * f32(TILE_SIZE) * 0.5
        num_x   := max(1, int(f32(g_ed_grid_cols) * f32(TILE_SIZE) / cs))
        num_y   := max(1, int(f32(g_ed_grid_rows) * f32(TILE_SIZE) / cs))
        scale   := max(1, g_ed_cell_size / HUB_CELL_RES)

        cell_col :: proc(bcx, bcy, gx, gy, scale: int) -> rl.Color {
            #partial switch tile_base(hub_cell_at((bcx + gx) * scale, (bcy + gy) * scale)) {
            case .Wall, .Pillar: return rl.Color{220,  40,  40, 120}
            case .Floor:         return rl.Color{ 40, 200,  60, 120}
            case .Water:         return rl.Color{ 40, 100, 220, 120}
            }
            return rl.Color{60, 180, 80, 60}
        }

        gx0, gy0, gx1, gy1 := ed_grid_visible_range(half_cw, half_ch, cs, num_x, num_y)

        step := 1
        if px := cs * g_camera.zoom; px > 0 {
            step = max(1, int(math.ceil(4.0 / px)))
        }

        bcx := int(math.floor(-half_cw / cs))
        bcy := int(math.floor(-half_ch / cs))

        for gy := gy0; gy < gy1; gy += step {
            gx := gx0
            for gx < gx1 {
                col := cell_col(bcx, bcy, gx, gy, scale)
                run := gx + step
                for run < gx1 && cell_col(bcx, bcy, run, gy, scale) == col { run += step }

                wx0 := -half_cw + f32(gx)             * cs
                wx1 := -half_cw + f32(min(run, gx1))  * cs
                wy0 := -half_ch + f32(gy)             * cs
                wy1 := -half_ch + f32(min(gy+step, gy1)) * cs
                cell_fill(
                    world_to_iso_xy(wx0, wy0), world_to_iso_xy(wx1, wy0),
                    world_to_iso_xy(wx1, wy1), world_to_iso_xy(wx0, wy1), col,
                )
                gx = run
            }
        }
    } else {
        cs := f32(TILE_SIZE)
        for k, tt in g_tilemap {
            base := tile_base(tt)
            col: rl.Color
            if      base == .Wall || base == .Pillar { col = rl.Color{220,  40,  40, 90} }
            else if base == .Floor                   { col = rl.Color{ 40, 200,  60, 90} }
            else if base == .Water                   { col = rl.Color{ 40, 100, 220, 90} }
            else                                     { continue }
            wx := f32(k[0]) * cs
            wy := f32(k[1]) * cs
            top    := world_to_iso_xy(wx,      wy)
            right  := world_to_iso_xy(wx + cs, wy)
            bottom := world_to_iso_xy(wx + cs, wy + cs)
            left   := world_to_iso_xy(wx,      wy + cs)
            cell_fill(top, right, bottom, left, col)
        }
    }
}
