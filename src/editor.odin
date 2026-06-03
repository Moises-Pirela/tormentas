package main

import rl  "vendor:raylib"
import     "core:fmt"
import     "core:math"
import     "core:os"
import cw  "clockwork"
import p2p "p2p"

ED_NAME_LEN   :: 32
ED_MAX_LEVELS :: 100
META_PATH     :: "data/levels/meta.bin"
ED_TAB_W      :: f32(22)
ED_PANEL_W    :: f32(200)
ED_PANEL_SPD  :: f32(14)
ED_BANNER_H   :: f32(32)

g_editor_mode: bool

EditorBrush :: enum u8 {
    Floor       = 0,
    Wall        = 1,
    Water       = 2,
    SpawnMelee  = 3,
    SpawnBrute  = 4,
    SpawnHunter = 5,
    SpawnRanged = 6,
    SpawnSniper = 7,
    Shopkeeper  = 8,
    MutationWorkbench = 9,
    ExitTile    = 10,
    PlayerStart = 11,
    Light       = 12,
    Erase       = 13,

    Oil         = 14,
    Fire        = 15,

    FireBarrel  = 16,
    WaterBarrel = 17,

    Door        = 18,
    SwitchLever = 19,
    Chest       = 20,
    Crate       = 21,
    LoreItem    = 22,
    Phonograph  = 23,
    KeyPickup   = 24,
    Pillar      = 25,
    SpawnSpider = 26,

    Floor1      = 27,
    Floor2      = 28,
    Floor3      = 29,
    Floor4      = 30,
    Wall1       = 31,
    Wall2       = 32,
    Wall3       = 33,
    Pillar1     = 34,
    Pillar2     = 35,
}

EditorCategory :: enum u8 { Environment, Entities, Interactive }

@(private = "file")
PaletteEntry :: struct {
    brush:    EditorBrush,
    category: EditorCategory,
    label:    cstring,
    key:      cstring,
    bg:       rl.Color,
}

ED_PAL_W      :: f32(130)
ED_PAL_ITEM_H :: f32(36)
ED_PAL_PAD    :: f32(6)
ED_PAL_HOTKEYS :: [14]cstring{"1","2","3","4","5","6","7","8","9","0","","","",""}

@(private = "file") g_ed_palette:        [40]PaletteEntry
@(private = "file") g_ed_palette_n:      int
@(private = "file") g_ed_pal_scroll:     f32
@(private = "file") g_ed_cat_collapsed:  [3]bool
@(private = "file") g_ed_key_id:         int = 0

@(private = "file") g_ed_brush:          EditorBrush = .Floor
@(private = "file") g_ed_zoom:           f32 = 1.0
@(private = "file") g_ed_save_msg:       f32
@(private = "file") g_ed_level:          int = 1
@(private = "file") g_ed_target_level:   int = 2
@(private = "file") g_ed_panel_open:     bool
@(private = "file") g_ed_panel_anim:     f32
@(private = "file") g_ed_name_editing:   bool
@(private = "file") g_ed_meta_loaded:    bool
@(private = "file") g_ed_level_names:    [ED_MAX_LEVELS+1][ED_NAME_LEN]u8
@(private = "file") g_ed_level_exists:   [ED_MAX_LEVELS+1]bool
@(private = "file") g_ed_list_scroll:    int
@(private = "file") g_ed_filtered:       [ED_MAX_LEVELS+1]int
@(private = "file") g_ed_filtered_count: int

@(private = "file")
ed_base_zoom :: proc() -> f32 { return f32(rl.GetScreenHeight()) / 720.0 }

@(private = "file")
ed_build_palette :: proc() {
    g_ed_palette_n  = 0
    g_ed_pal_scroll = 0

    ki := 0

    add :: proc(brush: EditorBrush, cat: EditorCategory, label: cstring,
                bg: rl.Color, ki: ^int) {
        if g_ed_palette_n >= len(g_ed_palette) { return }
        hotkeys := ED_PAL_HOTKEYS
        g_ed_palette[g_ed_palette_n] = PaletteEntry{
            brush    = brush,
            category = cat,
            label    = label,
            key      = hotkeys[min(ki^, 10)],
            bg       = bg,
        }
        g_ed_palette_n += 1
        ki^ += 1
    }

    for tt in TileType {
        #partial switch tt {
        case .Floor:  add(.Floor,  .Environment, "Floor",  {26, 24, 20, 255}, &ki)
        case .Wall:   add(.Wall,   .Environment, "Wall",   {52, 46, 38, 255}, &ki)
        case .Water:  add(.Water,  .Environment, "Water",  {18, 42, 80,  255}, &ki)
        case .Pillar: add(.Pillar, .Environment, "Pillar", {62, 54, 44, 255}, &ki)
        }
    }

    n_floors := g_tile_variant_count[int(TileType.Floor)]
    if n_floors >= 1 { add(.Floor1, .Environment, "Flr-1", {34, 30, 24, 255}, &ki) }
    if n_floors >= 2 { add(.Floor2, .Environment, "Flr-2", {40, 36, 28, 255}, &ki) }
    if n_floors >= 3 { add(.Floor3, .Environment, "Flr-3", {46, 40, 32, 255}, &ki) }
    if n_floors >= 4 { add(.Floor4, .Environment, "Flr-4", {52, 46, 36, 255}, &ki) }

    n_walls := g_tile_variant_count[int(TileType.Wall)]
    if n_walls >= 1 { add(.Wall1, .Environment, "Wll-1", {62, 54, 44, 255}, &ki) }
    if n_walls >= 2 { add(.Wall2, .Environment, "Wll-2", {70, 60, 48, 255}, &ki) }
    if n_walls >= 3 { add(.Wall3, .Environment, "Wll-3", {78, 66, 52, 255}, &ki) }

    n_pillars := g_tile_variant_count[int(TileType.Pillar)]
    if n_pillars >= 1 { add(.Pillar1, .Environment, "Pil-1", {72, 64, 52, 255}, &ki) }
    if n_pillars >= 2 { add(.Pillar2, .Environment, "Pil-2", {80, 70, 56, 255}, &ki) }

    add(.Oil,  .Environment, "Oil",  {16, 12,  8, 255}, &ki)
    add(.Fire, .Environment, "Fire", {80, 24,  6, 255}, &ki)


    entity_to_brush :: proc(name: string) -> (brush: EditorBrush, label: cstring, bg: rl.Color, cat: EditorCategory, ok: bool) {
        switch name {
        case "enemy_spider": return .SpawnSpider, "Spider", {20, 60, 20, 255}, .Entities, true
        case "env_door":       return .Door,        "Door",   {52, 34, 16, 255}, .Interactive, true
        case "env_switch":     return .SwitchLever, "Lever",  {36, 60, 36, 255}, .Interactive, true
        case "env_chest":      return .Chest,       "Chest",  {70, 56, 14, 255}, .Interactive, true
        case "env_crate":      return .Crate,       "Crate",  {44, 32, 16, 255}, .Interactive, true
        case "env_lore_item":  return .LoreItem,    "Lore",   {24, 44, 68, 255}, .Interactive, true
        case "env_phonograph": return .Phonograph,  "Phono",  {52, 28, 52, 255}, .Interactive, true
        case "env_key":        return .KeyPickup,   "Key",    {80, 70, 14, 255}, .Interactive, true
        }
        return .Erase, "", {}, .Entities, false
    }
    for &def in g_entity_defs {
        b, lbl, bg, cat, ok := entity_to_brush(def.name)
        if !ok { continue }
        add(b, cat, lbl, bg, &ki)
    }
    add(.Shopkeeper,       .Entities, "Shop",    {84, 64, 28, 255}, &ki)
    add(.MutationWorkbench,.Entities, "Mutator", {76, 34, 84, 255}, &ki)
    add(.ExitTile,         .Entities, "Exit",    {16, 56, 24, 255}, &ki)
    add(.PlayerStart,      .Entities, "Start",   {80, 64, 12, 255}, &ki)
    add(.Light,            .Entities, "Light",   {80, 70, 20, 255}, &ki)
    add(.FireBarrel,       .Entities, "FireBar", {90, 36, 10, 255}, &ki)
    add(.WaterBarrel,      .Entities, "WtrBar",  {12, 52, 90, 255}, &ki)
    add(.Erase,            .Entities, "Erase",   {55, 18, 18, 255}, &ki)
}

@(private = "file")
ed_pal_panel_rect :: proc() -> rl.Rectangle {
    sh := f32(rl.GetScreenHeight())
    return rl.Rectangle{
        x      = 0,
        y      = uis(ED_BANNER_H),
        width  = uis(ED_PAL_W),
        height = sh - uis(ED_BANNER_H),
    }
}

@(private = "file")
ed_pal_content_height :: proc() -> f32 {
    CAT_H    :: f32(22)
    total    := f32(0)
    seen_cat := [3]bool{}
    for i in 0..<g_ed_palette_n {
        e := &g_ed_palette[i]
        if !seen_cat[e.category] {
            total            += uis(CAT_H)
            seen_cat[e.category] = true
        }
        if !g_ed_cat_collapsed[e.category] {
            total += uis(ED_PAL_ITEM_H) + uis(ED_PAL_PAD * 0.5)
        }
    }
    return total
}

@(private = "file")
ed_level_file :: proc(n: int) -> string {
    return fmt.tprintf("data/levels/level%02d.bin", n)
}

@(private = "file")
ed_rebuild_filtered :: proc() {
    g_ed_filtered_count = 0
    for i in 0..<ED_MAX_LEVELS+1 {
        if g_ed_level_exists[i] || i == g_ed_level {
            g_ed_filtered[g_ed_filtered_count] = i
            g_ed_filtered_count += 1
        }
    }
}

@(private = "file")
ed_refresh_exists :: proc() {
    for i in 0..<ED_MAX_LEVELS+1 {
        g_ed_level_exists[i] = os.exists(ed_level_file(i))
    }
    ed_rebuild_filtered()
}

@(private = "file")
ed_meta_save :: proc() {
    os.make_directory("data/levels")
    raw: [(ED_MAX_LEVELS+1) * ED_NAME_LEN]u8
    for i in 0..<ED_MAX_LEVELS+1 {
        copy(raw[i*ED_NAME_LEN:(i+1)*ED_NAME_LEN], g_ed_level_names[i][:])
    }
    os.write_entire_file(META_PATH, raw[:])
}

@(private = "file")
ed_meta_load :: proc() {
    data, ok := os.read_entire_file(META_PATH, context.temp_allocator)
    if !ok || len(data) < (ED_MAX_LEVELS+1) * ED_NAME_LEN { return }
    for i in 0..<ED_MAX_LEVELS+1 {
        copy(g_ed_level_names[i][:], data[i*ED_NAME_LEN:(i+1)*ED_NAME_LEN])
    }
}

editor_toggle :: proc() {
    if !g_is_host { return }
    if g_playing_state == .Editor {


        restore_n := 0 if g_hub_active else max(g_current_raid_level, 1)
        fire_system_reset()
        level_load(restore_n)
        set_playing_state(.Hub if g_hub_active else .Gameplay)
    } else {
        g_ed_level = 0 if g_hub_active else max(g_current_raid_level, 1)
        set_playing_state(.Editor)
    }
    if g_editor_mode { g_ed_palette_n = 0 }
}

update_editor :: proc(dt: f32) {
    if !g_editor_mode { return }

    if g_ed_palette_n == 0 {
        g_ed_zoom = 1.0
        g_ed_brush = .Floor
        g_camera.zoom = ed_base_zoom() * g_ed_zoom
        if !g_ed_meta_loaded {
            ed_meta_load()
            g_ed_meta_loaded = true
        }
        ed_refresh_exists()
        ed_build_palette()
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

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    target_anim     := f32(1) if g_ed_panel_open else f32(0)
    g_ed_panel_anim += (target_anim - g_ed_panel_anim) * min(dt * ED_PANEL_SPD, 1)

    panel_x  := sw - uis(ED_TAB_W) - uis(ED_PANEL_W) * g_ed_panel_anim
    tab_rect := rl.Rectangle{sw - uis(ED_TAB_W), uis(ED_BANNER_H), uis(ED_TAB_W), sh - uis(ED_BANNER_H)}

    mp       := rl.GetMousePosition()
    over_tab := rl.CheckCollisionPointRec(mp, tab_rect)
    over_pal := rl.CheckCollisionPointRec(mp, ed_pal_panel_rect())
    over_ui  := over_tab || over_pal || (g_ed_panel_open && mp.x >= panel_x) || ed_insp_over_ui()

    if rl.IsMouseButtonPressed(.LEFT) && over_tab {
        g_ed_panel_open = !g_ed_panel_open
        if g_ed_panel_open { ed_refresh_exists() }
    }

    if g_ed_panel_open && g_ed_panel_anim > 0.3 {
        name_rect := rl.Rectangle{
            panel_x + uis(8), uis(ED_BANNER_H) + uis(52),
            uis(ED_PANEL_W) - uis(16), uis(20),
        }

        if rl.IsMouseButtonPressed(.LEFT) {
            if rl.CheckCollisionPointRec(mp, name_rect) {
                g_ed_name_editing = true
            } else if over_ui && g_ed_name_editing {
                g_ed_name_editing = false
                ed_meta_save()
            }
        }

        if g_ed_name_editing {
            c := rl.GetCharPressed()
            for c != 0 {
                nm  := &g_ed_level_names[g_ed_level]
                cur := 0
                for cur < ED_NAME_LEN - 1 && nm[cur] != 0 { cur += 1 }
                if cur < ED_NAME_LEN - 1 && c >= 32 && c < 127 {
                    nm[cur] = u8(c)
                }
                c = rl.GetCharPressed()
            }
            if rl.IsKeyPressed(.BACKSPACE) {
                nm  := &g_ed_level_names[g_ed_level]
                cur := 0
                for cur < ED_NAME_LEN - 1 && nm[cur] != 0 { cur += 1 }
                if cur > 0 { nm[cur - 1] = 0 }
            }
            if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.ESCAPE) {
                g_ed_name_editing = false
                ed_meta_save()
            }
        }

        btn_y     := uis(ED_BANNER_H) + uis(82)
        half_w    := (uis(ED_PANEL_W) - uis(20)) * 0.5
        save_rect := rl.Rectangle{panel_x + uis(8),             btn_y, half_w, uis(22)}
        load_rect := rl.Rectangle{panel_x + uis(12) + half_w,   btn_y, half_w, uis(22)}
        clr_rect  := rl.Rectangle{panel_x + uis(8), btn_y + uis(26), uis(ED_PANEL_W) - uis(16), uis(22)}

        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mp, save_rect) {
            g_ed_name_editing = false
            level_save(g_ed_level)
            ed_refresh_exists()
            g_ed_save_msg = 2.0
        }
        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mp, load_rect) {
            g_ed_name_editing = false
            level_load(g_ed_level)
            p2p.session_send_level_load(&g_session, g_ed_level)
        }
        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mp, clr_rect) {
            g_ed_name_editing = false
            clr_op := p2p.EditorOp{ action = .ClearAll }
            ed_apply_op(clr_op)
            p2p.session_send_editor_op(&g_session, clr_op)
        }

        LIST_ROW_H :: f32(18)
        LIST_Y0    :: f32(138)
        list_start_y := uis(ED_BANNER_H) + uis(LIST_Y0)
        list_height  := sh - list_start_y - uis(44)
        list_count   := int(list_height / uis(LIST_ROW_H))
        if list_count < 1 { list_count = 1 }

        if over_ui {
            wh := rl.GetMouseWheelMove()
            if wh != 0 {
                g_ed_list_scroll -= int(wh)
                max_sc := g_ed_filtered_count - list_count
                if max_sc < 0 { max_sc = 0 }
                g_ed_list_scroll = clamp(g_ed_list_scroll, 0, max_sc)
            }
        }

        for row in 0..<list_count {
            fi := g_ed_list_scroll + row
            if fi >= g_ed_filtered_count { break }
            idx  := g_ed_filtered[fi]
            ry   := list_start_y + f32(row) * uis(LIST_ROW_H)
            rrec := rl.Rectangle{panel_x + uis(4), ry, uis(ED_PANEL_W) - uis(8), uis(LIST_ROW_H)}
            if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mp, rrec) {
                g_ed_name_editing = false
                g_ed_level = idx
                ed_rebuild_filtered()
                level_load(g_ed_level)
                p2p.session_send_level_load(&g_session, g_ed_level)
            }
        }

        new_rect := rl.Rectangle{panel_x + uis(8), sh - uis(36), uis(ED_PANEL_W) - uis(16), uis(24)}
        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mp, new_rect) {
            for i in 1..=ED_MAX_LEVELS {
                if !g_ed_level_exists[i] {
                    g_ed_name_editing = false
                    g_ed_level = i
                    clr_op := p2p.EditorOp{ action = .ClearAll }
                    ed_apply_op(clr_op)
                    p2p.session_send_editor_op(&g_session, clr_op)
                    level_save(g_ed_level)
                    ed_refresh_exists()
                    g_ed_save_msg = 2.0
                    break
                }
            }
        }
    }

    if !g_ed_name_editing && !ed_insp_is_text_active() {
        PAL_KEYS := [10]rl.KeyboardKey{
            .ONE, .TWO, .THREE, .FOUR, .FIVE,
            .SIX, .SEVEN, .EIGHT, .NINE, .ZERO,
        }
        for ki in 0..<10 {
            if rl.IsKeyPressed(PAL_KEYS[ki]) && ki < g_ed_palette_n {
                g_ed_brush = g_ed_palette[ki].brush
            }
        }

        if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) {

            if rl.IsKeyPressed(.LEFT_BRACKET)  && g_ed_key_id > 0  { g_ed_key_id -= 1 }
            if rl.IsKeyPressed(.RIGHT_BRACKET) && g_ed_key_id < 63 { g_ed_key_id += 1 }
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

    pal_rect := ed_pal_panel_rect()
    if over_pal {
        wh := rl.GetMouseWheelMove()
        if wh != 0 {
            content_h := ed_pal_content_height()
            max_scroll := max(content_h - pal_rect.height, 0)
            g_ed_pal_scroll = clamp(g_ed_pal_scroll - wh * uis(30), 0, max_scroll)
        }
        if rl.IsMouseButtonPressed(.LEFT) {
            cy   := pal_rect.y + uis(ED_PAL_PAD) - g_ed_pal_scroll
            seen_cat_pal := [3]bool{}
            for i in 0..<g_ed_palette_n {
                e := &g_ed_palette[i]
                if !seen_cat_pal[e.category] {
                    hdr_r := rl.Rectangle{ pal_rect.x, cy, pal_rect.width, uis(22) }
                    if rl.CheckCollisionPointRec(mp, hdr_r) {
                        g_ed_cat_collapsed[e.category] = !g_ed_cat_collapsed[e.category]
                    }
                    cy                          += uis(22)
                    seen_cat_pal[e.category]     = true
                }
                if !g_ed_cat_collapsed[e.category] {
                    row_r := rl.Rectangle{ pal_rect.x + uis(4), cy,
                                           pal_rect.width - uis(8), uis(ED_PAL_ITEM_H) }
                    if rl.CheckCollisionPointRec(mp, row_r) {
                        g_ed_brush = e.brush
                    }
                    cy += uis(ED_PAL_ITEM_H) + uis(ED_PAL_PAD * 0.5)
                }
            }
        }
    }

    wheel := rl.GetMouseWheelMove()
    if wheel != 0 && !over_ui {
        g_ed_zoom = clamp(g_ed_zoom * (1.0 + wheel * 0.12), 0.10, 6.0)
    }
    g_camera.zoom = ed_base_zoom() * g_ed_zoom

    PAN :: f32(400)
    pan_screen: [2]f32
    if !g_ed_name_editing && !ed_insp_is_text_active() {
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

    if !over_ui {
        world_mp := screen_to_world_cartesian(mp)
        tx, ty   := world_to_tile(world_mp.x, world_mp.y)
        if rl.IsMouseButtonDown(.LEFT)  { ed_paint(tx, ty) }
        if rl.IsMouseButtonPressed(.RIGHT) {

            if !ed_try_select_at(tx, ty) {
                ed_erase_objects(tx, ty)
            }
        } else if rl.IsMouseButtonDown(.RIGHT) && !ed_insp_has_selection() {

            ed_erase_objects(tx, ty)
        }
    }

    if !g_ed_name_editing && !ed_insp_is_text_active() && rl.IsKeyPressed(.ESCAPE) {
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
ed_paint :: proc(tx, ty: int) {


    tl_val := u16(g_ed_target_level & 0xFF)
    if EditorBrush(g_ed_brush) == .Door {
        tl_val |= u16(g_ed_key_id & 0xFF) << 8
    }
    op := p2p.EditorOp{
        action       = .Paint,
        brush        = u8(g_ed_brush),
        tx           = i16(tx),
        ty           = i16(ty),
        target_level = tl_val,
    }
    ed_apply_op(op)
    p2p.session_send_editor_op(&g_session, op)
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
ed_apply_op :: proc(op: p2p.EditorOp) {
    tx := int(op.tx)
    ty := int(op.ty)
    switch op.action {
    case .Paint:
        switch EditorBrush(op.brush) {
        case .Floor:   g_tilemap[[2]int{tx, ty}] = .Floor;   delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Wall:    g_tilemap[[2]int{tx, ty}] = .Wall;    delete_key(&g_overlay_map, [2]int{tx, ty})
        case .Water:   g_tilemap[[2]int{tx, ty}] = .Water;   delete_key(&g_overlay_map, [2]int{tx, ty})
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
        case .SpawnMelee, .SpawnBrute, .SpawnHunter, .SpawnRanged, .SpawnSniper, .SpawnSpider:
            et := brush_to_spawn_type(EditorBrush(op.brush))
            for i := len(g_level_data.spawns) - 1; i >= 0; i -= 1 {
                sp := g_level_data.spawns[i]
                if int(sp.tx) == tx && int(sp.ty) == ty {
                    unordered_remove(&g_level_data.spawns, i)
                }
            }
            append(&g_level_data.spawns, SpawnPoint{
                tx = i16(tx), ty = i16(ty),
                enemy_type = et,
            })
        case .Shopkeeper, .MutationWorkbench:
            npc_type := cw.NPCType.Shopkeeper
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
        case .ExitTile:
            for i := len(g_level_data.exits) - 1; i >= 0; i -= 1 {
                ex := g_level_data.exits[i]
                if int(ex.tx) == tx && int(ex.ty) == ty {
                    unordered_remove(&g_level_data.exits, i)
                }
            }
            append(&g_level_data.exits, LevelExit{
                tx = i16(tx), ty = i16(ty),
                target_level = op.target_level,
            })
        case .PlayerStart:
            g_level_data.player_start = {
                f32(tx * TILE_SIZE + TILE_SIZE / 2),
                f32(ty * TILE_SIZE + TILE_SIZE / 2),
            }
        case .Light:
            for i := len(g_level_data.lights) - 1; i >= 0; i -= 1 {
                lt := g_level_data.lights[i]
                if int(lt.tx) == tx && int(lt.ty) == ty {
                    unordered_remove(&g_level_data.lights, i)
                }
            }
            append(&g_level_data.lights, LevelLight{
                tx = i16(tx), ty = i16(ty),
                r = 255, g = 200, b = 100,
                radius = 120.0, intensity = 1.0,
            })
        case .Door:
            link_id := u8(op.target_level & 0xFF)
            key_id  := u8(op.target_level >> 8)
            for i := len(g_level_data.doors) - 1; i >= 0; i -= 1 {
                d := g_level_data.doors[i]
                if int(d.tx) == tx && int(d.ty) == ty {
                    unordered_remove(&g_level_data.doors, i)
                }
            }

            g_tilemap[[2]int{tx, ty}] = .Wall
            append(&g_level_data.doors, LevelDoor{
                tx = i16(tx), ty = i16(ty),
                link_id = link_id, key_id = key_id,
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
    case .ClearAll:
        tilemap_fill_default()
        clear(&g_level_data.spawns)
        clear(&g_level_data.exits)
        clear(&g_level_data.lights)
        clear(&g_level_data.npcs)
        clear(&g_level_data.barrels)
        clear(&g_level_data.doors)
        clear(&g_level_data.switches)
        clear(&g_level_data.containers)
        clear(&g_level_data.lore_items)
        clear(&g_level_data.phonographs)
        clear(&g_level_data.key_pickups)
        g_level_data.player_start = {}
    }

    g_wall_mask_dirty = true
}


@(private = "file")
_erase_objects :: proc(tx, ty: int) {
    for i := len(g_level_data.spawns) - 1; i >= 0; i -= 1 {
        sp := g_level_data.spawns[i]
        if int(sp.tx) == tx && int(sp.ty) == ty {
            unordered_remove(&g_level_data.spawns, i)
        }
    }
    for i := len(g_level_data.exits) - 1; i >= 0; i -= 1 {
        ex := g_level_data.exits[i]
        if int(ex.tx) == tx && int(ex.ty) == ty {
            unordered_remove(&g_level_data.exits, i)
        }
    }
    for i := len(g_level_data.npcs) - 1; i >= 0; i -= 1 {
        npc := g_level_data.npcs[i]
        if int(npc.tx) == tx && int(npc.ty) == ty {
            unordered_remove(&g_level_data.npcs, i)
        }
    }
    for i := len(g_level_data.lights) - 1; i >= 0; i -= 1 {
        lt := g_level_data.lights[i]
        if int(lt.tx) == tx && int(lt.ty) == ty {
            unordered_remove(&g_level_data.lights, i)
        }
    }
    for i := len(g_level_data.barrels) - 1; i >= 0; i -= 1 {
        b := g_level_data.barrels[i]
        if int(b.tx) == tx && int(b.ty) == ty {
            unordered_remove(&g_level_data.barrels, i)
        }
    }
    for i := len(g_level_data.doors) - 1; i >= 0; i -= 1 {
        d := g_level_data.doors[i]
        if int(d.tx) == tx && int(d.ty) == ty {
            unordered_remove(&g_level_data.doors, i)
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

@(private = "file")
brush_to_spawn_type :: proc(b: EditorBrush) -> EnemySpawnType {
    #partial switch b {
    case .SpawnMelee:  return .Melee
    case .SpawnBrute:  return .Brute
    case .SpawnHunter: return .Hunter
    case .SpawnRanged: return .Ranged
    case .SpawnSniper: return .Sniper
    case .SpawnSpider: return .Spider
    }
    return .Melee
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

    grid_col := rl.Color{80, 76, 60, 55}
    for gx in tx0..=tx1 {
        for gy in ty0..=ty1 {
            if !tile_exists(gx, gy) { continue }
            _, top, right, bottom, left := iso_tile_bounds(gx, gy)
            rl.DrawLineEx(top, right, lw, grid_col)
            rl.DrawLineEx(right, bottom, lw, grid_col)
            rl.DrawLineEx(bottom, left, lw, grid_col)
            rl.DrawLineEx(left, top, lw, grid_col)
        }
    }

    ts := f32(TILE_SIZE)
    fs := ts * 0.22
    cr := ts * 0.30

    for sp in g_level_data.spawns {
        wx := f32(int(sp.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(sp.ty) * TILE_SIZE + TILE_SIZE / 2)
        ip := world_to_iso_xy(wx, wy)
        col := spawn_marker_color(sp.enemy_type)
        rl.DrawCircleV(ip, cr, col)
        rl.DrawCircleV(ip, cr * 0.65, rl.Color{0, 0, 0, 100})
        lbl := spawn_marker_label(sp.enemy_type)
        lsz := rl.MeasureTextEx(g_font, lbl, fs, 0.5)
        rl.DrawTextEx(g_font, lbl, {ip.x - lsz.x*0.5, ip.y - lsz.y*0.5}, fs, 0.5,
            rl.Color{255, 240, 200, 230})
    }

    EXIT_COL :: rl.Color{50, 200, 90, 180}
    for ex in g_level_data.exits {
        center, top, right, bottom, left := iso_tile_bounds(int(ex.tx), int(ex.ty))
        iso_draw_shadow_diamond(center, ISO_TILE_W * 2, ISO_TILE_H * 2, rl.Color{30, 140, 60, 80})
        rl.DrawLineEx(top, right, lw * 2.5, EXIT_COL)
        rl.DrawLineEx(right, bottom, lw * 2.5, EXIT_COL)
        rl.DrawLineEx(bottom, left, lw * 2.5, EXIT_COL)
        rl.DrawLineEx(left, top, lw * 2.5, EXIT_COL)
        buf: [8]u8
        s := fmt.bprintf(buf[:7], "->%d", ex.target_level)
        buf[len(s)] = 0
        lsz := rl.MeasureTextEx(g_font, cstring(&buf[0]), fs, 0.5)
        rl.DrawTextEx(g_font, cstring(&buf[0]),
            {center.x - lsz.x*0.5, center.y - lsz.y*0.5},
            fs, 0.5, rl.Color{140, 255, 160, 230})
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
    for lt in g_level_data.lights {
        wx := f32(int(lt.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(lt.ty) * TILE_SIZE + TILE_SIZE / 2)
        ip := world_to_iso_xy(wx, wy)

        rl.DrawCircleV(ip, cr * 1.2, rl.Color{lt.r, lt.g, lt.b, 60})
        rl.DrawCircleV(ip, cr * 0.7, LIGHT_COL)
        rl.DrawCircleLinesV(ip, cr * 1.2, rl.Color{255, 220, 100, 160})
        lsz := rl.MeasureTextEx(g_font, "L", fs * 1.1, 0.5)
        rl.DrawTextEx(g_font, "L",
            {ip.x - lsz.x*0.5, ip.y - lsz.y*0.5},
            fs * 1.1, 0.5, rl.Color{40, 30, 0, 240})
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


    DOOR_COL :: rl.Color{160, 110, 50, 220}
    for d in g_level_data.doors {
        wx := f32(int(d.tx) * TILE_SIZE + TILE_SIZE / 2)
        wy := f32(int(d.ty) * TILE_SIZE + TILE_SIZE / 2)
        ip := world_to_iso_xy(wx, wy)
        rl.DrawRectangleLinesEx({ip.x - ts*0.16, ip.y - ts*0.35, ts*0.32, ts*0.38},
            lw * 2.5, DOOR_COL)
        rl.DrawRectangleRec({ip.x - ts*0.16, ip.y - ts*0.35, ts*0.32, ts*0.38},
            rl.Color{DOOR_COL.r, DOOR_COL.g, DOOR_COL.b, 40})

        rl.DrawCircleV({ip.x, ip.y - ts*0.08}, ts*0.04, DOOR_COL)
        if d.link_id != 0 {
            buf: [8]u8
            s := fmt.bprintf(buf[:7], "L%d", d.link_id)
            buf[len(s)] = 0
            lsz := rl.MeasureTextEx(g_font, cstring(&buf[0]), fs * 0.8, 0.5)
            rl.DrawTextEx(g_font, cstring(&buf[0]),
                {ip.x - lsz.x*0.5, ip.y + ts*0.12},
                fs * 0.8, 0.5, rl.Color{220, 180, 80, 220})
        }
        if d.key_id != 0 {
            buf: [8]u8
            s := fmt.bprintf(buf[:7], "K%d", d.key_id)
            buf[len(s)] = 0
            lsz := rl.MeasureTextEx(g_font, cstring(&buf[0]), fs * 0.8, 0.5)
            rl.DrawTextEx(g_font, cstring(&buf[0]),
                {ip.x - lsz.x*0.5, ip.y - ts*0.32},
                fs * 0.8, 0.5, rl.Color{220, 80, 80, 220})
        }

        switch d.open_type {
        case .LeverSwitch:
            badge := cstring("[LV]")
            bsz := rl.MeasureTextEx(g_font, badge, fs * 0.65, 0.5)
            rl.DrawTextEx(g_font, badge,
                {ip.x + ts*0.17 - bsz.x*0.5, ip.y - ts*0.38},
                fs * 0.65, 0.5, rl.Color{80, 210, 110, 230})
        case .Key:
            badge := cstring("[KY]")
            bsz := rl.MeasureTextEx(g_font, badge, fs * 0.65, 0.5)
            rl.DrawTextEx(g_font, badge,
                {ip.x + ts*0.17 - bsz.x*0.5, ip.y - ts*0.38},
                fs * 0.65, 0.5, rl.Color{230, 160, 60, 230})
        case .None:
        }

        if d.is_locked {
            rl.DrawCircleV({ip.x + ts*0.14, ip.y - ts*0.08}, ts*0.035,
                rl.Color{220, 55, 55, 210})
        }
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

    ps := g_level_data.player_start
    if ps[0] != 0 || ps[1] != 0 {
        ptx, pty := world_to_tile(ps[0], ps[1])
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


    ed_insp_draw_selection_highlight()

    mp       := rl.GetMousePosition()
    world_mp := screen_to_world_cartesian(mp)
    ctx, cty := world_to_tile(world_mp.x, world_mp.y)
    center, top, right, bottom, left := iso_tile_bounds(ctx, cty)

    fill_col, brd_col := ed_brush_colors(g_ed_brush)
    iso_draw_shadow_diamond(center, ISO_TILE_W * 2, ISO_TILE_H * 2, fill_col)
    rl.DrawLineEx(top, right, lw * 2, brd_col)
    rl.DrawLineEx(right, bottom, lw * 2, brd_col)
    rl.DrawLineEx(bottom, left, lw * 2, brd_col)
    rl.DrawLineEx(left, top, lw * 2, brd_col)
}

@(private = "file")
spawn_marker_color :: proc(et: EnemySpawnType) -> rl.Color {
    switch et {
    case .Melee:  return rl.Color{220,  70,  50, 200}
    case .Brute:  return rl.Color{160,  30,  30, 200}
    case .Hunter: return rl.Color{120,  60, 200, 200}
    case .Ranged:  return rl.Color{ 40, 160, 160, 200}
    case .Sniper:  return rl.Color{ 40,  70, 200, 200}
    case .Spider:  return rl.Color{ 30, 160,  30, 200}
    }
    return rl.Color{200, 200, 200, 200}
}

@(private = "file")
spawn_marker_label :: proc(et: EnemySpawnType) -> cstring {
    switch et {
    case .Melee:  return "M"
    case .Brute:  return "B"
    case .Hunter: return "H"
    case .Ranged:  return "R"
    case .Sniper:  return "S"
    case .Spider:  return "Sp"
    }
    return "?"
}

@(private = "file")
ed_brush_colors :: proc(b: EditorBrush) -> (fill, brd: rl.Color) {
    switch b {
    case .Floor:       return {110,  95,  65,  85}, {200, 170,  90, 200}
    case .Wall:        return { 70, 105, 140,  85}, { 90, 150, 210, 200}
    case .Water:       return { 18,  60, 130,  90}, { 40, 120, 220, 210}
    case .SpawnMelee:  return {220,  70,  50,  70}, {255, 110,  80, 210}
    case .SpawnBrute:  return {160,  30,  30,  70}, {210,  60,  60, 210}
    case .SpawnHunter: return {120,  60, 200,  70}, {160,  90, 255, 210}
    case .SpawnRanged: return { 40, 160, 160,  70}, { 60, 210, 210, 210}
    case .SpawnSniper: return { 40,  70, 200,  70}, { 70, 110, 255, 210}
    case .Shopkeeper:  return {180, 148,  62,  70}, {230, 200, 100, 210}
    case .MutationWorkbench: return {150,  60, 180,  70}, {210, 110, 255, 210}
    case .ExitTile:    return { 30, 140,  60,  70}, { 50, 210,  90, 210}
    case .PlayerStart: return {200, 160,  30,  70}, {255, 200,  50, 210}
    case .Light:       return {200, 180,  50,  70}, {255, 220,  80, 210}
    case .Oil:         return { 18,  14,  10,  90}, { 60,  80,  50, 200}
    case .Fire:        return { 90,  22,   6,  90}, {240,  80,  15, 210}
    case .FireBarrel:  return {120,  40,   8,  80}, {230,  90,  20, 210}
    case .WaterBarrel: return {  8,  42,  90,  80}, { 60, 150, 230, 210}
    case .Door:        return { 64,  40,  18,  85}, {160, 110,  50, 210}
    case .SwitchLever: return { 24,  56,  24,  85}, { 60, 160,  60, 210}
    case .Chest:       return { 88,  68,  14,  85}, {210, 175,  40, 210}
    case .Crate:       return { 54,  38,  18,  85}, {150, 110,  55, 210}
    case .LoreItem:    return { 20,  42,  72,  85}, { 60, 120, 200, 210}
    case .Phonograph:  return { 62,  28,  62,  85}, {170,  70, 180, 210}
    case .KeyPickup:   return { 96,  84,  10,  85}, {245, 210,  30, 210}
    case .Pillar:      return { 80,  70,  56,  85}, {170, 148, 115, 210}
    case .SpawnSpider: return { 20,  60,  20,  70}, { 50, 180,  50, 210}
    case .Floor1:      return { 34,  30,  24,  85}, {110,  96,  68, 210}
    case .Floor2:      return { 40,  36,  28,  85}, {124, 108,  76, 210}
    case .Floor3:      return { 46,  40,  32,  85}, {138, 120,  84, 210}
    case .Floor4:      return { 52,  46,  36,  85}, {152, 132,  92, 210}
    case .Wall1:       return { 62,  54,  44,  85}, {150, 130,  98, 210}
    case .Wall2:       return { 70,  60,  48,  85}, {165, 143, 107, 210}
    case .Wall3:       return { 78,  66,  52,  85}, {180, 156, 116, 210}
    case .Pillar1:     return { 72,  64,  52,  85}, {175, 152, 118, 210}
    case .Pillar2:     return { 80,  70,  58,  85}, {185, 162, 126, 210}
    case .Erase:       return {170,  45,  45,  85}, {220,  70,  70, 200}
    }
    return {128, 128, 128, 85}, {200, 200, 200, 200}
}

@(private = "file")
ed_panel_btn :: proc(mp: rl.Vector2, r: rl.Rectangle, label: cstring,
                     bg_n, bg_h, brd, text: rl.Color) {
    hov := rl.CheckCollisionPointRec(mp, r)
    rl.DrawRectangleRec(r, bg_h if hov else bg_n)
    rl.DrawRectangleLinesEx(r, uis(1), brd)
    sz := rl.MeasureTextEx(g_font, label, uis(9), 0.5)
    rl.DrawTextEx(g_font, label,
        {r.x + r.width*0.5 - sz.x*0.5, r.y + r.height*0.5 - sz.y*0.5},
        uis(9), 0.5, text)
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

    left_hint := cstring("1-0:Brush  LMB:Paint  RMB:Select/EraseObj  WASD:Pan  [/]:ID  Ctrl+[/]:KeyID  -/=:Level")
    rl.DrawTextEx(g_font, left_hint, {uis(8), uis(10)}, uis(7.5), 0.5,
        rl.Color{140, 128, 95, 190})

    right_hint := cstring("Scroll:Zoom  Mid:Drag  Ctrl+S:Save  Ctrl+L:Load  F1:Exit")
    rhsz := rl.MeasureTextEx(g_font, right_hint, uis(7.5), 0.5)
    rl.DrawTextEx(g_font, right_hint,
        {sw - rhsz.x - uis(ED_TAB_W) - uis(8), uis(10)}, uis(7.5), 0.5,
        rl.Color{140, 128, 95, 190})

    CAT_H     :: f32(22)
    ITEM_H    :: ED_PAL_ITEM_H
    PAD       :: ED_PAL_PAD
    CAT_NAMES := [EditorCategory]cstring{
        .Environment = "ENVIRONMENT",
        .Entities    = "ENTITIES",
        .Interactive = "INTERACTIVE",
    }
    CAT_COLS  := [EditorCategory]rl.Color{
        .Environment = { 40, 110,  60, 255},
        .Entities    = {110,  60,  40, 255},
        .Interactive = { 50,  70, 130, 255},
    }

    pal_r := ed_pal_panel_rect()
    rl.DrawRectangleRec(pal_r, rl.Color{10, 8, 6, 245})
    rl.DrawRectangleLinesEx(pal_r, uis(1), rl.Color{80, 70, 45, 180})
    rl.DrawRectangle(i32(pal_r.x + pal_r.width - uis(1.5)), i32(pal_r.y),
        i32(uis(1.5)), i32(pal_r.height), rl.Color{150, 130, 60, 200})

    rl.BeginScissorMode(i32(pal_r.x), i32(pal_r.y), i32(pal_r.width), i32(pal_r.height))

    cy           := pal_r.y + uis(PAD) - g_ed_pal_scroll
    seen_cat_drw := [3]bool{}

    for i in 0..<g_ed_palette_n {
        entry := &g_ed_palette[i]

        if !seen_cat_drw[entry.category] {

            cat_col  := CAT_COLS[entry.category]
            hdr_r    := rl.Rectangle{ pal_r.x, cy, pal_r.width, uis(CAT_H) }
            hdr_bg   := rl.Color{ cat_col.r/2, cat_col.g/2, cat_col.b/2, 220 }
            rl.DrawRectangleRec(hdr_r, hdr_bg)
            rl.DrawRectangle(i32(pal_r.x), i32(cy), i32(pal_r.width), i32(uis(2)), cat_col)

            cat_name := CAT_NAMES[entry.category]
            csz      := rl.MeasureTextEx(g_font, cat_name, uis(8), 1)
            rl.DrawTextEx(g_font, cat_name,
                { pal_r.x + uis(22), cy + uis(CAT_H)*0.5 - csz.y*0.5 },
                uis(8), 1, rl.Color{220, 200, 140, 240})

            arrow := cstring("v") if !g_ed_cat_collapsed[entry.category] else cstring(">")
            rl.DrawTextEx(g_font, arrow,
                { pal_r.x + uis(6), cy + uis(CAT_H)*0.5 - uis(5) },
                uis(9), 1, rl.Color{200, 180, 100, 220})

            cy                           += uis(CAT_H)
            seen_cat_drw[entry.category]  = true
        }

        if g_ed_cat_collapsed[entry.category] { continue }

        sel     := g_ed_brush == entry.brush
        row_r   := rl.Rectangle{ pal_r.x + uis(4), cy, pal_r.width - uis(8), uis(ITEM_H) }
        brd_col := rl.Color{220, 190, 80, 255} if sel else rl.Color{55, 50, 35, 160}
        brd_w   := uis(2) if sel else uis(1)

        rl.DrawRectangleRec(row_r, entry.bg)
        rl.DrawRectangleLinesEx(row_r, brd_w, brd_col)


        swatch_sz := uis(ITEM_H - 8)
        rl.DrawRectangle(
            i32(row_r.x + uis(4)), i32(cy + (uis(ITEM_H) - swatch_sz)*0.5),
            i32(swatch_sz), i32(swatch_sz),
            rl.Color{entry.bg.r + 30, entry.bg.g + 30, entry.bg.b + 30, 255})


        name_fs := uis(8.5)
        lsz     := rl.MeasureTextEx(g_font, entry.label, name_fs, 0.5)
        lx      := row_r.x + swatch_sz + uis(10)
        rl.DrawTextEx(g_font, entry.label,
            { lx, cy + uis(ITEM_H)*0.5 - lsz.y*0.5 },
            name_fs, 0.5, rl.Color{210, 190, 140, 230})


        if entry.key != nil && (cast([^]u8)entry.key)[0] != 0 {
            rl.DrawTextEx(g_font, entry.key,
                { row_r.x + row_r.width - uis(12), cy + uis(3) },
                uis(7.5), 0.5, rl.Color{160, 148, 100, 180})
        }

        cy += uis(ITEM_H) + uis(PAD * 0.5)
    }

    rl.EndScissorMode()


    stat_y := pal_r.y + pal_r.height - uis(26)
    rl.DrawRectangle(i32(pal_r.x), i32(stat_y), i32(pal_r.width), i32(uis(26)),
        rl.Color{8, 6, 4, 220})
    rl.DrawRectangle(i32(pal_r.x), i32(stat_y), i32(pal_r.width), i32(uis(1)),
        rl.Color{80, 70, 45, 160})
    lv_buf: [64]u8
    lv_s := fmt.bprintf(lv_buf[:63], "Lv%d  T%d  Sp%d",
        g_ed_level, len(g_tilemap), len(g_level_data.spawns))
    lv_buf[len(lv_s)] = 0
    rl.DrawTextEx(g_font, cstring(&lv_buf[0]),
        { pal_r.x + uis(5), stat_y + uis(5) }, uis(8), 0.5, rl.Color{150, 138, 100, 210})


    sx := uis(ED_PAL_W) + uis(8)
    zoom_buf: [64]u8
    zoom_s := fmt.bprintf(zoom_buf[:63], "Zoom %.2fx  ID:%d  KeyID:%d",
        g_ed_zoom, g_ed_target_level, g_ed_key_id)
    zoom_buf[len(zoom_s)] = 0
    rl.DrawTextEx(g_font, cstring(&zoom_buf[0]),
        { sx, uis(10) }, uis(7.5), 0.5, rl.Color{150, 138, 100, 210})

    if g_ed_save_msg > 0 {
        alpha   := u8(clamp(g_ed_save_msg, 0, 1) * 255)
        save_cs := cstring("Saved!")
        save_sz := rl.MeasureTextEx(g_font, save_cs, uis(22), 1)
        rl.DrawTextEx(g_font, save_cs,
            {sw*0.5 - save_sz.x*0.5, sh*0.44},
            uis(22), 1, rl.Color{85, 210, 85, alpha})
    }

    tab_x   := sw - uis(ED_TAB_W)
    tab_col := rl.Color{45, 40, 28, 230} if g_ed_panel_open else rl.Color{30, 26, 20, 230}
    rl.DrawRectangle(i32(tab_x), i32(uis(ED_BANNER_H)), i32(uis(ED_TAB_W)),
        i32(sh - uis(ED_BANNER_H)), tab_col)
    rl.DrawRectangleLinesEx({tab_x, uis(ED_BANNER_H), uis(ED_TAB_W), sh - uis(ED_BANNER_H)},
        uis(1), rl.Color{120, 104, 60, 180})

    tab_letters := [6]cstring{"L","E","V","E","L","S"}
    letter_h    := uis(10)
    total_h     := f32(6) * letter_h + f32(5) * uis(2)
    start_y     := uis(ED_BANNER_H) + (sh - uis(ED_BANNER_H) - total_h) * 0.5
    for i in 0..<6 {
        ls := rl.MeasureTextEx(g_font, tab_letters[i], letter_h, 0.5)
        rl.DrawTextEx(g_font, tab_letters[i],
            {tab_x + uis(ED_TAB_W)*0.5 - ls.x*0.5, start_y + f32(i)*(letter_h + uis(2))},
            letter_h, 0.5, rl.Color{200, 180, 100, 220})
    }

    if g_ed_panel_anim > 0.005 {
        panel_x  := sw - uis(ED_TAB_W) - uis(ED_PANEL_W) * g_ed_panel_anim
        rl.DrawRectangle(i32(panel_x), i32(uis(ED_BANNER_H)),
            i32(uis(ED_PANEL_W)), i32(sh - uis(ED_BANNER_H)), rl.Color{18, 16, 12, 240})
        rl.DrawRectangle(i32(panel_x), i32(uis(ED_BANNER_H)),
            i32(uis(1.5)), i32(sh - uis(ED_BANNER_H)), rl.Color{150, 130, 60, 200})

        mp := rl.GetMousePosition()
        cy = uis(ED_BANNER_H) + uis(10)

        hdr_cs := cstring("LEVELS")
        hdr_sz := rl.MeasureTextEx(g_font, hdr_cs, uis(12), 1)
        rl.DrawTextEx(g_font, hdr_cs,
            {panel_x + uis(ED_PANEL_W)*0.5 - hdr_sz.x*0.5, cy},
            uis(12), 1, rl.Color{220, 190, 80, 255})
        cy += uis(16)

        rl.DrawRectangle(i32(panel_x + uis(8)), i32(cy),
            i32(uis(ED_PANEL_W) - uis(16)), i32(uis(1)), rl.Color{100, 88, 52, 180})
        cy += uis(6)

        rl.DrawTextEx(g_font, "NAME:", {panel_x + uis(8), cy}, uis(8), 0.5,
            rl.Color{150, 138, 100, 210})
        cy += uis(12)

        name_rect  := rl.Rectangle{panel_x + uis(8), cy, uis(ED_PANEL_W) - uis(16), uis(20)}
        nm          := &g_ed_level_names[g_ed_level]
        nm[ED_NAME_LEN - 1] = 0
        name_cs := cstring(&nm[0])

        field_col := rl.Color{48, 44, 32, 255} if g_ed_name_editing else rl.Color{38, 34, 26, 255}
        field_brd := rl.Color{220, 190, 80, 200} if g_ed_name_editing else rl.Color{80, 72, 48, 180}
        rl.DrawRectangleRec(name_rect, field_col)
        rl.DrawRectangleLinesEx(name_rect, uis(1), field_brd)
        rl.DrawTextEx(g_font, name_cs,
            {name_rect.x + uis(4), name_rect.y + uis(4)},
            uis(9), 0.5, rl.Color{200, 185, 140, 230})

        if g_ed_name_editing && int(rl.GetTime() * 2) % 2 == 0 {
            name_sz  := rl.MeasureTextEx(g_font, name_cs, uis(9), 0.5)
            cursor_x := name_rect.x + uis(4) + name_sz.x
            rl.DrawRectangle(i32(cursor_x), i32(name_rect.y + uis(3)),
                i32(uis(1.5)), i32(uis(14)), rl.Color{220, 190, 80, 220})
        }
        cy += uis(26)

        half_w    := (uis(ED_PANEL_W) - uis(20)) * 0.5
        save_rect := rl.Rectangle{panel_x + uis(8),            cy, half_w, uis(22)}
        load_rect := rl.Rectangle{panel_x + uis(12) + half_w,  cy, half_w, uis(22)}
        ed_panel_btn(mp, save_rect, "SAVE",
            {30, 48, 30, 220}, {44, 70, 44, 220}, {60, 160, 70, 200}, {100, 220, 110, 230})
        ed_panel_btn(mp, load_rect, "LOAD",
            {28, 36, 52, 220}, {40, 54, 76, 220}, {60, 110, 180, 200}, {100, 160, 230, 230})
        cy += uis(26)

        clr_rect := rl.Rectangle{panel_x + uis(8), cy, uis(ED_PANEL_W) - uis(16), uis(22)}
        ed_panel_btn(mp, clr_rect, "CLEAR LEVEL",
            {52, 28, 28, 220}, {74, 40, 40, 220}, {160, 60, 60, 200}, {230, 100, 100, 230})
        cy += uis(28)

        rl.DrawRectangle(i32(panel_x + uis(8)), i32(cy),
            i32(uis(ED_PANEL_W) - uis(16)), i32(uis(1)), rl.Color{100, 88, 52, 180})
        cy += uis(4)

        LIST_ROW_H :: f32(18)
        list_height := sh - cy - uis(44)
        list_count  := int(list_height / uis(LIST_ROW_H))
        if list_count < 1 { list_count = 1 }

        for row in 0..<list_count {
            fi := g_ed_list_scroll + row
            if fi >= g_ed_filtered_count { break }
            idx    := g_ed_filtered[fi]
            lv     := idx
            ry     := cy + f32(row) * uis(LIST_ROW_H)
            is_cur := lv == g_ed_level
            is_hov := rl.CheckCollisionPointRec(mp,
                rl.Rectangle{panel_x + uis(4), ry, uis(ED_PANEL_W) - uis(8), uis(LIST_ROW_H)})

            bg: rl.Color
            if      is_cur { bg = rl.Color{55, 50, 30, 200} }
            else if is_hov { bg = rl.Color{36, 32, 22, 200} }
            if bg.a > 0 {
                rl.DrawRectangle(i32(panel_x + uis(4)), i32(ry),
                    i32(uis(ED_PANEL_W) - uis(8)), i32(uis(LIST_ROW_H)), bg)
            }

            dot_exists := g_ed_level_exists[idx]
            dot_cs  := cstring("*") if dot_exists else cstring("-")
            dot_col := rl.Color{80, 200, 90, 220} if dot_exists else rl.Color{80, 72, 50, 180}
            rl.DrawTextEx(g_font, dot_cs, {panel_x + uis(7), ry + uis(3)}, uis(9), 0.5, dot_col)

            num_buf: [8]u8
            num_s := fmt.bprintf(num_buf[:7], "%d", lv)
            num_buf[len(num_s)] = 0
            num_col := rl.Color{220, 200, 120, 255} if is_cur else rl.Color{160, 148, 110, 200}
            rl.DrawTextEx(g_font, cstring(&num_buf[0]),
                {panel_x + uis(18), ry + uis(3)}, uis(9), 0.5, num_col)

            lv_nm := &g_ed_level_names[idx]
            lv_nm[ED_NAME_LEN - 1] = 0
            if lv_nm[0] != 0 {
                nm_col := rl.Color{220, 205, 155, 255} if is_cur else rl.Color{185, 170, 128, 210}
                rl.DrawTextEx(g_font, cstring(&lv_nm[0]),
                    {panel_x + uis(38), ry + uis(3)}, uis(9), 0.5, nm_col)
            }
        }

        new_rect := rl.Rectangle{panel_x + uis(8), sh - uis(36), uis(ED_PANEL_W) - uis(16), uis(24)}
        ed_panel_btn(mp, new_rect, "+ NEW LEVEL",
            {28, 44, 28, 220}, {36, 60, 36, 220}, {60, 160, 70, 200}, {100, 220, 110, 230})
    }


    ed_insp_draw_panel()
}
