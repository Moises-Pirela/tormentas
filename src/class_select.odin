package main

import rl  "vendor:raylib"
import     "core:math"
import     "core:fmt"

@(private = "file")
CLASS_GLOW_COLORS := [4]rl.Color{
    { 200,  80,  80, 255 },
    {  80, 220,  80, 255 },
    { 230, 200,  80, 255 },
    { 160,  80, 240, 255 },
}

@(private = "file")
CLASS_NAME_KEYS := [4]LocKey{
    .CLASS_NURSE_NAME,
    .CLASS_PR1S_NAME,
    .CLASS_SHERIFF_NAME,
    .CLASS_SRBRAIN_NAME,
}

@(private = "file")
CLASS_TITLE_KEYS := [4]LocKey{
    .CLASS_NURSE_TITLE,
    .CLASS_PR1S_TITLE,
    .CLASS_SHERIFF_TITLE,
    .CLASS_SRBRAIN_TITLE,
}

@(private = "file")
CLASS_DESC_KEYS := [4]LocKey{
    .CLASS_NURSE_DESC,
    .CLASS_PR1S_DESC,
    .CLASS_SHERIFF_DESC,
    .CLASS_SRBRAIN_DESC,
}

@(private = "file")
CLASS_PRIMARY_STAT_KEYS := [4]LocKey{
    .STATS_SCIENCE,
    .STATS_STRENGTH,
    .STATS_DEXTERITY,
    .STATS_SCIENCE,
}

@(private = "file")
CLASS_WEAPON_KEYS := [4]LocKey{
    .CLASS_NURSE_WEAPON,
    .CLASS_PR1S_WEAPON,
    .CLASS_SHERIFF_WEAPON,
    .CLASS_SRBRAIN_WEAPON,
}

CLASS_BASE_STR    := [4]int { 1, 3, 1, 1 }
CLASS_BASE_DEX    := [4]int { 1, 1, 3, 2 }
CLASS_BASE_SCI    := [4]int { 3, 1, 1, 2 }
CLASS_BASE_HP     := [4]f32 { 100, 130,  90,  80 }
CLASS_BASE_ENERGY := [4]f32 { 130,  70,  80, 140 }
CLASS_BASE_SPEED  := [4]f32 { 220, 230, 270, 225 }

CLASS_WEAPON_ARCHETYPE := [4]WeaponArchetype{ .Pistol, .Shotgun, .Pistol, .Pistol }

player_class_archetype :: proc() -> WeaponArchetype {
    ci := class_idx_for_slot(g_active_slot)
    if ci < 0 || ci >= 4 { return .Pistol }
    return CLASS_WEAPON_ARCHETYPE[ci]
}

CLASS_STARTER_ABILITIES := [4]AbilityType{
    .CarbolicSpray,
    .OsseousSlam,
    .RapidDischarge,
    .GalvanicShock,
}

_mm_update_class_select :: proc() {
    dt := rl.GetFrameTime()
    g_mm.cs_anim_t += dt

    sw      := f32(rl.GetScreenWidth())
    sh      := f32(rl.GetScreenHeight())
    mp      := rl.GetMousePosition()
    n       := 4
    card_w  := uis(160)
    card_h  := uis(260)
    card_gap:= uis(18)
    total_w := card_w * f32(n) + card_gap * f32(n - 1)
    cards_x := sw * 0.5 - total_w * 0.5
    cards_y := sh * 0.26

    g_mm.cs_hovered = -1
    for i in 0..<n {
        cx := cards_x + f32(i) * (card_w + card_gap)
        r  := rl.Rectangle{cx, cards_y, card_w, card_h}
        if rl.CheckCollisionPointRec(mp, r) {
            g_mm.cs_hovered = i
        }
        if _mm_btn_hit(r) {
            g_mm.new_char = i
        }
    }

    btn_w   := sw * 0.14
    btn_h   := uis(42)
    btn_y   := sh * 0.86
    back_r  := rl.Rectangle{sw * 0.30 - btn_w * 0.5, btn_y, btn_w, btn_h}
    begin_r := rl.Rectangle{sw * 0.70 - btn_w * 0.5, btn_y, btn_w, btn_h}

    if _mm_btn_hit(back_r) || rl.IsKeyPressed(.ESCAPE) {
        char_slot_delete(g_mm.cs_pending_slot)
        g_mm.cs_pending_slot = -1
        g_mm.selected_slot   = -1
        g_mm.new_char        = 0
        g_mm.phase           = .CharSelect
        return
    }

    if _mm_btn_hit(begin_r) {
        _cs_confirm_class()
    }
}

@(private = "file")
_cs_confirm_class :: proc() {
    ci            := clamp(g_mm.new_char, 0, 3)
    stems         := PLAYER_STEMS
    g_player_stem  = stems[ci]
    g_selected_class_idx = ci

    idx := g_mm.cs_pending_slot
    if idx >= 0 && idx < MAX_CHAR_SLOTS {
        g_char_save.slots[idx]._reserved[0] = u8(ci + 1)
    }

    chars_save_all()
    _mm_select_slot(idx)
    g_mm.cs_pending_slot = -1
    g_mm.phase           = .PlayOptions
}

_mm_draw_class_select :: proc() {
    sw      := f32(rl.GetScreenWidth())
    sh      := f32(rl.GetScreenHeight())
    n       := 4
    card_w  := uis(160)
    card_h  := uis(260)
    card_gap:= uis(18)
    total_w := card_w * f32(n) + card_gap * f32(n - 1)
    cards_x := sw * 0.5 - total_w * 0.5
    cards_y := sh * 0.26

    rl.DrawRectangleRec({0, 0, sw, sh}, rl.Color{6, 4, 3, 235})

    lbl := t(.CLASS_SELECT_TITLE)
    lfs := uis(14)
    lsz := rl.MeasureTextEx(g_font_body, lbl, lfs, 0.5)
    rl.DrawTextEx(g_font_body, lbl,
        {sw * 0.5 - lsz.x * 0.5, cards_y - lfs - uis(18)},
        lfs, 0.5, rl.Color{130, 118, 82, 200})

    for i in 0..<n {
        cx := cards_x + f32(i) * (card_w + card_gap)
        r  := rl.Rectangle{cx, cards_y, card_w, card_h}
        _cs_draw_class_card(i, r, g_mm.cs_hovered == i, g_mm.new_char == i)
    }

    display_idx := g_mm.cs_hovered if g_mm.cs_hovered >= 0 else g_mm.new_char
    panel_r := rl.Rectangle{
        cards_x + total_w + uis(28),
        cards_y,
        uis(210),
        card_h,
    }
    _cs_draw_stats_panel(display_idx, panel_r)

    desc    := t(CLASS_DESC_KEYS[display_idx])
    desc_fs := uis(12)
    desc_y  := cards_y + card_h + uis(18)
    dsz     := rl.MeasureTextEx(g_font_body, desc, desc_fs, 0.5)
    rl.DrawTextEx(g_font_body, desc,
        {sw * 0.5 - dsz.x * 0.5, desc_y},
        desc_fs, 0.5, COL_MUTED)

    btn_w   := sw * 0.14
    btn_h   := uis(42)
    btn_y   := sh * 0.86
    back_r  := rl.Rectangle{sw * 0.30 - btn_w * 0.5, btn_y, btn_w, btn_h}
    begin_r := rl.Rectangle{sw * 0.70 - btn_w * 0.5, btn_y, btn_w, btn_h}
    _mm_btn_draw(back_r,  t(.MENU_BTN_BACK),     false)
    _mm_btn_draw(begin_r, t(.CLASS_SELECT_BEGIN), true)

    hint    := cstring("ESC  Back")
    hint_fs := uis(10)
    hsz     := rl.MeasureTextEx(g_font_body, hint, hint_fs, 0.5)
    rl.DrawTextEx(g_font_body, hint,
        {sw * 0.5 - hsz.x * 0.5, sh * 0.94},
        hint_fs, 0.5, rl.Color{80, 72, 52, 160})
}

@(private = "file")
_cs_draw_class_card :: proc(ci: int, r: rl.Rectangle, hovered: bool, selected: bool) {
    glow := CLASS_GLOW_COLORS[ci]
    hot  := hovered || selected

    bg := rl.Color{52, 46, 34, 255} if hot else rl.Color{18, 16, 12, 255}
    rl.DrawRectangleRec(r, bg)

    if selected {
        rl.DrawRectangleRec(r, rl.Color{glow.r, glow.g, glow.b, 28})
    }

    border := COL_BRASS if selected else (rl.Color{100, 88, 58, 200} if hovered else COL_RULE)
    rl.DrawRectangleLinesEx(r, 1.5, border)

    sprite_h := r.height * 0.62
    sprite_area := rl.Rectangle{
        r.x + uis(6),
        r.y + uis(6),
        r.width - uis(12),
        sprite_h - uis(6),
    }
    tint  := rl.WHITE if hot else rl.Color{180, 180, 180, 200}
    stems := PLAYER_STEMS
    _cs_draw_sprite_frame(stems[ci], sprite_area, g_mm.cs_anim_t, tint)

    if hot {
        glow_y := r.y + sprite_h - uis(2)
        rl.DrawEllipse(
            i32(r.x + r.width * 0.5), i32(glow_y),
            r.width * 0.38, uis(5),
            rl.Color{glow.r, glow.g, glow.b, 55},
        )
    }

    name_y  := r.y + sprite_h + uis(6)
    name    := t(CLASS_NAME_KEYS[ci])
    name_fs := uis(14)
    nsz     := rl.MeasureTextEx(g_font_body, name, name_fs, 0.5)
    rl.DrawTextEx(g_font_body, name,
        {r.x + (r.width - nsz.x) * 0.5, name_y},
        name_fs, 0.5, COL_BRASS if hot else COL_MUTED)

    stat_lbl := t(CLASS_PRIMARY_STAT_KEYS[ci])
    stat_fs  := uis(11)
    ssz      := rl.MeasureTextEx(g_font_body, stat_lbl, stat_fs, 0.5)
    rl.DrawTextEx(g_font_body, stat_lbl,
        {r.x + (r.width - ssz.x) * 0.5, name_y + name_fs + uis(4)},
        stat_fs, 0.5,
        rl.Color{glow.r, glow.g, glow.b, 200} if hot else COL_RULE)

    if selected {
        bar_r := rl.Rectangle{r.x + uis(12), r.y + r.height - uis(6), r.width - uis(24), uis(3)}
        rl.DrawRectangleRec(bar_r, rl.Color{glow.r, glow.g, glow.b, 220})
    }
}

@(private = "file")
_cs_draw_sprite_frame :: proc(stem: string, dest_r: rl.Rectangle, anim_t: f32, tint: rl.Color) {
    buf: [64]u8
    n := min(len(stem), len(buf)-1)
    copy(buf[:], stem[:n])
    buf[n] = 0

    entry, ok := get_or_load_entity_sprite(cstring(&buf[0]))
    if !ok { return }

    src := entry.src

    adef, has_def := get_or_load_anim_def(stem)
    if has_def && adef.has_clip[AnimStateName.Idle] && adef.frame_width > 0 {
        clip := adef.clips[AnimStateName.Idle]
        fps  := clip.fps if clip.fps > 0 else 6
        fc   := max(clip.frame_count, 1)
        total_dur := f32(fc) / fps
        t_mod     := math.mod(anim_t, total_dur)
        frame_idx := clamp(int(t_mod * fps), 0, fc - 1)
        abs_frame := clip.start_frame + frame_idx
        ncols     := max(adef.columns, 1)
        col       := abs_frame % ncols
        row       := abs_frame / ncols
        src = rl.Rectangle{
            f32(col * adef.frame_width),
            f32(row * adef.frame_height),
            f32(adef.frame_width),
            f32(adef.frame_height),
        }
    }

    fw := src.width
    fh := src.height
    if fw <= 0 || fh <= 0 { return }

    scale  := min(dest_r.width / fw, dest_r.height / fh)
    dw     := fw * scale
    dh     := fh * scale
    draw_r := rl.Rectangle{
        dest_r.x + (dest_r.width - dw) * 0.5,
        dest_r.y + dest_r.height - dh,
        dw, dh,
    }
    rl.DrawTexturePro(entry.tex, src, draw_r, {}, 0, tint)
}

@(private = "file")
_cs_draw_stats_panel :: proc(ci: int, r: rl.Rectangle) {
    rl.DrawRectangleRec(r, rl.Color{12, 10, 8, 220})
    rl.DrawRectangleLinesEx(r, 1, COL_RULE)

    px  := r.x + uis(12)
    py  := r.y + uis(14)
    glow := CLASS_GLOW_COLORS[ci]

    title_fs := uis(15)
    rl.DrawTextEx(g_font_body, t(CLASS_TITLE_KEYS[ci]), {px, py}, title_fs, 0.5, COL_BRASS)
    py += title_fs + uis(8)

    rl.DrawLineV({r.x + uis(6), py}, {r.x + r.width - uis(6), py}, COL_RULE)
    py += uis(10)

    _cs_draw_stat_dots(t(.CLASS_STAT_STR), CLASS_BASE_STR[ci], glow, px, py)
    py += uis(18)
    _cs_draw_stat_dots(t(.CLASS_STAT_DEX), CLASS_BASE_DEX[ci], glow, px, py)
    py += uis(18)
    _cs_draw_stat_dots(t(.CLASS_STAT_SCI), CLASS_BASE_SCI[ci], glow, px, py)
    py += uis(22)

    num_buf: [32]u8
    val_fs := uis(11)

    hp_s := fmt.bprintf(num_buf[:], "HP:      %d", int(CLASS_BASE_HP[ci]))
    num_buf[len(hp_s)] = 0
    rl.DrawTextEx(g_font_body, cstring(&num_buf[0]), {px, py}, val_fs, 0.5, rl.Color{170, 160, 118, 210})
    py += val_fs + uis(4)

    en_s := fmt.bprintf(num_buf[:], "Energy:  %d", int(CLASS_BASE_ENERGY[ci]))
    num_buf[len(en_s)] = 0
    rl.DrawTextEx(g_font_body, cstring(&num_buf[0]), {px, py}, val_fs, 0.5, rl.Color{170, 160, 118, 210})
    py += val_fs + uis(4)

    sp_s := fmt.bprintf(num_buf[:], "Speed:   %d", int(CLASS_BASE_SPEED[ci]))
    num_buf[len(sp_s)] = 0
    rl.DrawTextEx(g_font_body, cstring(&num_buf[0]), {px, py}, val_fs, 0.5, rl.Color{170, 160, 118, 210})
    py += val_fs + uis(10)

    rl.DrawLineV({r.x + uis(6), py}, {r.x + r.width - uis(6), py}, COL_RULE)
    py += uis(10)

    ab_lbl_fs := uis(11)
    rl.DrawTextEx(g_font_body, t(.CLASS_STARTER_ABILITY), {px, py}, ab_lbl_fs, 0.5, COL_MUTED)
    py += ab_lbl_fs + uis(4)

    at := CLASS_STARTER_ABILITIES[ci]
    ab_name := ABILITY_DEFS[at].name
    ab_buf: [64]u8
    ab_n := min(len(ab_name), len(ab_buf)-1)
    copy(ab_buf[:], ab_name[:ab_n])
    ab_buf[ab_n] = 0
    ab_fs := uis(12)
    rl.DrawTextEx(g_font_body, cstring(&ab_buf[0]), {px, py}, ab_fs, 0.5, COL_PARCH)
    py += ab_fs + uis(12)

    rl.DrawTextEx(g_font_body, t(.CLASS_STARTER_WEAPON), {px, py}, ab_lbl_fs, 0.5, COL_MUTED)
    py += ab_lbl_fs + uis(4)
    rl.DrawTextEx(g_font_body, t(CLASS_WEAPON_KEYS[ci]), {px, py}, ab_fs, 0.5, COL_PARCH)
}

@(private = "file")
_cs_draw_stat_dots :: proc(label: cstring, value: int, glow: rl.Color, x, y: f32) {
    fs  := uis(11)
    lsz := rl.MeasureTextEx(g_font_body, label, fs, 0.5)
    rl.DrawTextEx(g_font_body, label, {x, y}, fs, 0.5, COL_MUTED)

    dot_x   := x + lsz.x + uis(8)
    dot_r   := uis(4)
    dot_gap := uis(8)
    for i in 0..<3 {
        cx := dot_x + f32(i) * (dot_r * 2 + dot_gap) + dot_r
        cy := y + fs * 0.5
        if i < value {
            rl.DrawCircle(i32(cx), i32(cy), dot_r, rl.Color{glow.r, glow.g, glow.b, 220})
        } else {
            rl.DrawCircleLines(i32(cx), i32(cy), dot_r, COL_RULE)
        }
    }
}
