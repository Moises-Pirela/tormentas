package main

import rl   "vendor:raylib"
import      "core:fmt"
import      "core:math"
import cw   "clockwork"
import clay "../clay"

HUB_PORTAL_POS     :: [2]f32{ -300, 0 }
HUB_PORTAL_RADIUS  :: f32(50)

HUB_SHOPKEEPER_POS :: [3]f32{ 200, 0, 0 }
HUB_MUTATION_WORKBENCH_POS :: [3]f32{ 300, -40, 0 }
HUB_STASH_POS :: [3]f32{ 105, -95, 0 }

enter_hub :: proc(w: ^cw.World, save_progress: bool = false) {
    if save_progress && cw.world_is_valid(w, w.player_id) {
        save_player(w, w.player_id)
    }
    g_raid_timer      = 0
    g_available_levels = level_scan_available()
    level_clear(w)
    level_load(0)
    level_apply(w)
    door_init_blockers(w)
    hub_apply(w)
    spawn_players(w)
    load_player(w, w.player_id)
    // Full HP on hub entry (safe zone).
    if cw.world_has_component(w, w.player_id, .Health) {
        h := cw.world_get_health(w, w.player_id)
        h.current = h.max
    }
    g_hub_active       = true
    g_was_player_alive = true
    set_playing_state(.Hub)
}

enter_raid :: proc(w: ^cw.World, n: int) {
    if cw.world_is_valid(w, w.player_id) {
        save_player(w, w.player_id)
    }
    director_init()
    g_current_raid_level = n
    raid_result_gold     = 0
    raid_result_serums   = 0
    g_raid_timer         = RAID_TIME
    level_clear(w)
    level_load(n)
    level_apply(w)
    door_init_blockers(w)

    // Spawn timed extraction zones from exits with target_level == 0.
    // Falls back to the legacy hardcoded point if the level defines none.
    found_zone := false
    for ex in g_level_data.exits {
        if ex.target_level == 0 {
            spawn_extraction_at_tile(w, int(ex.tx), int(ex.ty))
            found_zone = true
        }
    }
    if !found_zone {
        spawn_extraction_point(w)
    }

    spawn_players(w)
    load_player(w, w.player_id)
    // Full HP at the start of every raid.
    if cw.world_has_component(w, w.player_id, .Health) {
        h := cw.world_get_health(w, w.player_id)
        h.current = h.max
    }
    // Capture serum baseline so on_player_extract can compute delta.
    g_raid_serums_start = 0
    if cw.world_has_component(w, w.player_id, .MutationContainer) {
        g_raid_serums_start = cw.world_get_mutation(w, w.player_id).serums
    }
    g_hub_active       = false
    g_was_player_alive = true
    set_playing_state(.Gameplay)

    ui_close_all()
}

update_hub_portal :: proc(w: ^cw.World) {
    if !cw.world_is_valid(w, w.player_id) { return }
    if !cw.world_has_component(w, w.player_id, .Transform) { return }

    pos  := cw.world_get_transform(w, w.player_id).position
    dx   := pos[0] - HUB_PORTAL_POS[0]
    dy   := pos[1] - HUB_PORTAL_POS[1]
    near := dx*dx + dy*dy < (HUB_PORTAL_RADIUS * 2) * (HUB_PORTAL_RADIUS * 2)

    if near && input_pressed(rl.KeyboardKey(g_binds.gameplay.interact)) {
        ui_open(.LevelSelect)
    }
}

draw_hub_world :: proc(w: ^cw.World) {
    px := HUB_PORTAL_POS[0]
    py := HUB_PORTAL_POS[1]
    tt := f32(rl.GetTime())
    center := rl.Vector2{ px, py }
    iso := world_to_iso_v(center)

    pulse      := 0.7 + 0.3 * math.sin(tt * 2.0)
    fill_alpha := u8(50  * pulse)
    ring_alpha := u8(200 * pulse)

    draw_world_circle(center, HUB_PORTAL_RADIUS, rl.Color{40, 60, 180, fill_alpha})
    draw_world_circle_lines(center, HUB_PORTAL_RADIUS, rl.Color{100, 140, 255, ring_alpha})

    if cw.world_is_valid(w, w.player_id) &&
       cw.world_has_component(w, w.player_id, .Transform) {
        pos := cw.world_get_transform(w, w.player_id).position
        dx  := pos[0] - px
        dy  := pos[1] - py
        if dx*dx + dy*dy < (HUB_PORTAL_RADIUS * 2) * (HUB_PORTAL_RADIUS * 2) {
            lbl    := t(.HUB_INTERACT)
            lbl_fs := f32(12)
            lsz    := rl.MeasureTextEx(g_font, lbl, lbl_fs, 0.5)
            rl.DrawTextEx(g_font, lbl,
                {iso.x - lsz.x * 0.5, iso.y - HUB_PORTAL_RADIUS - lbl_fs - 4},
                lbl_fs, 0.5, rl.Color{160, 200, 255, 230})
        }
    }
}

draw_hub_hud :: proc(w: ^cw.World) {
    sw := f32(rl.GetScreenWidth())

    loc    := t(.HUB_LABEL)
    loc_fs := uis(11)
    lsz    := rl.MeasureTextEx(g_font, loc, loc_fs, 0.5)
    rl.DrawTextEx(g_font, loc,
        {sw * 0.5 - lsz.x * 0.5, uis(10)},
        loc_fs, 0.5, COL_MUTED)

    rl.DrawTextEx(g_font, tf(.HUB_STASH, g_stash.gold, g_stash.serums),
        {uis(14), uis(14)}, uis(11), 0.5, COL_BRASS)
}

draw_level_select :: proc(w: ^cw.World) {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 160})

    n_levels := max(g_available_levels, 1)   // at least one row so the panel isn't empty
    pw := uis(360)
    ph := uis(80) + f32(n_levels) * uis(62) + uis(48)
    px := (sw - pw) * 0.5
    py := (sh - ph) * 0.5

    clay.BeginLayout()
    if clay.UI(clay.ID("LevelSelectPanel"))({
        layout = { sizing = { clay.SizingFixed(pw), clay.SizingFixed(ph) } },
        floating = {
            offset     = { px, py },
            attachment = { element = .LeftTop, parent = .LeftTop },
            attachTo   = .Root,
        },
        backgroundColor = { 10, 8, 6, 252 },
        border          = { color = { 90, 68, 28, 200 }, width = { 1, 1, 1, 1, 0 } },
        cornerRadius    = clay.CornerRadiusAll(5),
    }) {}
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)

    rl.DrawRectangle(i32(px), i32(py), i32(pw), i32(uis(3)), COL_BRASS)

    title    := t(.HUB_LEVEL_SELECT)
    title_fs := uis(16)
    tsz      := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title,
        {px + pw * 0.5 - tsz.x * 0.5, py + uis(16)},
        title_fs, 1, COL_PARCH)
    rl.DrawLineEx(
        {px + uis(16), py + uis(46)},
        {px + pw - uis(16), py + uis(46)}, 1, COL_RULE)

    btn_w := pw - uis(32)
    btn_h := uis(46)
    bx    := px + uis(16)

    if g_available_levels == 0 {
        // No raid levels found — show a hint instead of an empty panel.
        msg    := t(.HUB_NO_LEVELS)
        msg_fs := uis(11)
        msz    := rl.MeasureTextEx(g_font, msg, msg_fs, 0.5)
        rl.DrawTextEx(g_font, msg,
            {px + pw * 0.5 - msz.x * 0.5, py + uis(70)},
            msg_fs, 0.5, COL_MUTED)
    }
    for i in 1 ..= g_available_levels {
        by := py + uis(58) + f32(i - 1) * (btn_h + uis(10))
        r  := rl.Rectangle{ bx, by, btn_w, btn_h }

        mp  := rl.GetMousePosition()
        hot := rl.CheckCollisionPointRec(mp, r)

        bg     := rl.Color{  80,  58, 14, 255 } if hot else rl.Color{  50,  36, 10, 235 }
        border := rl.Color{ 200, 162, 55, 255 } if hot else rl.Color{ 140, 108, 38, 200 }
        rl.DrawRectangleRec(r, bg)
        rl.DrawRectangleLinesEx(r, 1.5, border)

        lbl_cs  := tf(.HUB_LEVEL_N, i)
        lbl_fs  := uis(12)
        lsz     := rl.MeasureTextEx(g_font, lbl_cs, lbl_fs, 0.5)
        lbl_col := rl.Color{235, 215, 145, 255} if hot else COL_BRASS
        rl.DrawTextEx(g_font, lbl_cs,
            {r.x + (r.width - lsz.x) * 0.5, r.y + (r.height - lbl_fs) * 0.5},
            lbl_fs, 0.5, lbl_col)

        if hot && rl.IsMouseButtonReleased(.LEFT) {
            // Do NOT call enter_raid here — this proc runs inside ui_draw's
            // BeginTextureMode context.  enter_raid calls ui_close_all() which
            // unloads the active RT mid-render, corrupting the frame.
            // Defer to the update phase via g_pending_raid_start instead.
            g_pending_raid_start = i
            ui_close(.LevelSelect)
            return
        }
    }

    cancel    := t(.HUB_ESC_CANCEL)
    cancel_fs := uis(10)
    csz       := rl.MeasureTextEx(g_font, cancel, cancel_fs, 0.5)
    rl.DrawTextEx(g_font, cancel,
        {px + pw * 0.5 - csz.x * 0.5, py + ph - uis(22)},
        cancel_fs, 0.5, COL_MUTED)
}


@(private = "file")
_hub_btn_hit :: proc(r: rl.Rectangle) -> bool {
    return rl.IsMouseButtonReleased(.LEFT) &&
           rl.CheckCollisionPointRec(rl.GetMousePosition(), r)
}

@(private = "file")
_hub_btn_draw :: proc(r: rl.Rectangle, label: cstring, accent := false) {
    mp  := rl.GetMousePosition()
    hot := rl.CheckCollisionPointRec(mp, r)

    if accent {
        bg     := rl.Color{  80,  58, 14, 255 } if hot else rl.Color{  50,  36, 10, 235 }
        border := rl.Color{ 200, 162, 55, 255 } if hot else rl.Color{ 140, 108, 38, 200 }
        rl.DrawRectangleRec(r, bg)
        rl.DrawRectangleLinesEx(r, 1.5, border)
    } else {
        bg     := rl.Color{  32,  27, 20, 240 } if hot else rl.Color{  18,  15, 11, 230 }
        border := COL_BRASS if hot else COL_RULE
        rl.DrawRectangleRec(r, bg)
        rl.DrawRectangleLinesEx(r, 1, border)
    }

    fs  := uis(12)
    tsz := rl.MeasureTextEx(g_font, label, fs, 0.5)
    col: rl.Color
    if hot          { col = rl.Color{235, 215, 145, 255} }
    else if accent  { col = COL_BRASS }
    else            { col = COL_PARCH }
    rl.DrawTextEx(g_font, label,
        {r.x + (r.width  - tsz.x) * 0.5,
         r.y + (r.height - tsz.y) * 0.5},
        fs, 0.5, col)
}


draw_extract_screen :: proc(w: ^cw.World) {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 185})

    pw := uis(360)
    ph := uis(310)
    px := (sw - pw) * 0.5
    py := (sh - ph) * 0.5

    clay.BeginLayout()
    if clay.UI(clay.ID("ExtractPanel"))({
        layout = { sizing = { clay.SizingFixed(pw), clay.SizingFixed(ph) } },
        floating = {
            offset     = { px, py },
            attachment = { element = .LeftTop, parent = .LeftTop },
            attachTo   = .Root,
        },
        backgroundColor = { 10, 14, 10, 252 },
        border          = { color = { 48, 140, 55, 200 }, width = { 1, 1, 1, 1, 0 } },
        cornerRadius    = clay.CornerRadiusAll(5),
    }) {}
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)

    rl.DrawRectangle(i32(px), i32(py), i32(pw), i32(uis(3)), rl.Color{60, 200, 80, 200})

    t_fs := uis(20)
    t1   := t(.EXTRACT_TITLE)
    t2   := t(.EXTRACT_SUBTITLE)
    t1sz := rl.MeasureTextEx(g_font, t1, t_fs, 1)
    t2sz := rl.MeasureTextEx(g_font, t2, t_fs, 1)
    rl.DrawTextEx(g_font, t1, {px + pw*0.5 - t1sz.x*0.5, py + uis(16)},
        t_fs, 1, rl.Color{100, 230, 100, 255})
    rl.DrawTextEx(g_font, t2, {px + pw*0.5 - t2sz.x*0.5, py + uis(42)},
        t_fs, 1, rl.Color{80, 200, 80, 200})
    rl.DrawLineEx(
        {px + uis(16), py + uis(74)},
        {px + pw - uis(16), py + uis(74)}, 1, rl.Color{40, 100, 45, 180})

    row_fs := uis(15)
    r1y    := py + uis(86)
    r2y    := r1y + uis(28)
    sep_y  := r2y + uis(30)
    r3y    := sep_y + uis(14)

    rl.DrawTextEx(g_font, t(.EXTRACT_GOLD),   {px + uis(24), r1y}, row_fs, 1, COL_MUTED)
    rl.DrawTextEx(g_font, t(.EXTRACT_SERUMS), {px + uis(24), r2y}, row_fs, 1, COL_MUTED)
    {
        buf: [32]u8
        s   := fmt.bprintf(buf[:31], "+ %d", raid_result_gold)
        buf[len(s)] = 0
        sz := rl.MeasureTextEx(g_font, cstring(&buf[0]), row_fs, 1)
        rl.DrawTextEx(g_font, cstring(&buf[0]),
            {px + pw - uis(24) - sz.x, r1y}, row_fs, 1, COL_BRASS)
    }
    {
        buf: [32]u8
        s   := fmt.bprintf(buf[:31], "+ %d", raid_result_serums)
        buf[len(s)] = 0
        sz := rl.MeasureTextEx(g_font, cstring(&buf[0]), row_fs, 1)
        rl.DrawTextEx(g_font, cstring(&buf[0]),
            {px + pw - uis(24) - sz.x, r2y}, row_fs, 1, COL_BRASS)
    }
    rl.DrawLineEx({px + uis(16), sep_y}, {px + pw - uis(16), sep_y}, 1, COL_RULE)
    rl.DrawTextEx(g_font, t(.EXTRACT_STASH_TOTAL), {px + uis(24), r3y}, row_fs, 1, COL_MUTED)
    {
        buf: [48]u8
        s   := fmt.bprintf(buf[:47], "%d gold   %d serums", g_stash.gold, g_stash.serums)
        buf[len(s)] = 0
        sz := rl.MeasureTextEx(g_font, cstring(&buf[0]), row_fs, 1)
        rl.DrawTextEx(g_font, cstring(&buf[0]),
            {px + pw - uis(24) - sz.x, r3y}, row_fs, 1, COL_PARCH)
    }

    btn_w  := uis(200)
    btn_h  := uis(44)
    cont_r := rl.Rectangle{
        px + pw*0.5 - btn_w*0.5,
        py + ph - uis(62),
        btn_w, btn_h,
    }
    _hub_btn_draw(cont_r, t(.HUB_BTN_RETURN), true)
    if _hub_btn_hit(cont_r) {
        enter_hub(w, true)
    }
}


draw_death_screen :: proc(w: ^cw.World) {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 185})

    pw := uis(370)
    ph := uis(300)
    px := (sw - pw) * 0.5
    py := (sh - ph) * 0.5

    clay.BeginLayout()
    if clay.UI(clay.ID("DeathPanel"))({
        layout = { sizing = { clay.SizingFixed(pw), clay.SizingFixed(ph) } },
        floating = {
            offset     = { px, py },
            attachment = { element = .LeftTop, parent = .LeftTop },
            attachTo   = .Root,
        },
        backgroundColor = { 14, 6, 6, 252 },
        border          = { color = { 140, 28, 28, 200 }, width = { 1, 1, 1, 1, 0 } },
        cornerRadius    = clay.CornerRadiusAll(5),
    }) {}
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)

    rl.DrawRectangle(i32(px), i32(py), i32(pw), i32(uis(3)), rl.Color{200, 40, 40, 200})

    title    := t(.DEATH_TITLE)
    title_fs := uis(26)
    tsz      := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title,
        {px + pw*0.5 - tsz.x*0.5, py + uis(16)},
        title_fs, 1, rl.Color{200, 55, 55, 255})
    rl.DrawLineEx(
        {px + uis(16), py + uis(60)},
        {px + pw - uis(16), py + uis(60)}, 1, rl.Color{100, 28, 28, 180})

    sub    := t(.DEATH_MSG)
    sub_fs := uis(12)
    ssz    := rl.MeasureTextEx(g_font, sub, sub_fs, 0.5)
    rl.DrawTextEx(g_font, sub,
        {px + pw*0.5 - ssz.x*0.5, py + uis(72)},
        sub_fs, 0.5, COL_MUTED)

    rl.DrawLineEx(
        {px + uis(16), py + uis(100)},
        {px + pw - uis(16), py + uis(100)}, 1, COL_RULE)
    row_fs := uis(15)
    rl.DrawTextEx(g_font, t(.DEATH_STASH), {px + uis(24), py + uis(112)}, row_fs, 1, COL_MUTED)
    {
        buf: [32]u8
        s   := fmt.bprintf(buf[:31], "%d gold", g_stash.gold)
        buf[len(s)] = 0
        sz := rl.MeasureTextEx(g_font, cstring(&buf[0]), row_fs, 1)
        rl.DrawTextEx(g_font, cstring(&buf[0]),
            {px + pw - uis(24) - sz.x, py + uis(112)}, row_fs, 1, COL_PARCH)
    }

    btn_w := uis(155)
    btn_h := uis(44)
    gap   := uis(14)
    total := btn_w*2 + gap
    bx    := px + pw*0.5 - total*0.5
    by    := py + ph - uis(64)

    retry_r := rl.Rectangle{ bx,             by, btn_w, btn_h }
    hub_r   := rl.Rectangle{ bx + btn_w+gap, by, btn_w, btn_h }

    _hub_btn_draw(retry_r, t(.HUB_BTN_RETRY),  true)
    _hub_btn_draw(hub_r,   t(.HUB_BTN_RETURN), false)

    if _hub_btn_hit(retry_r) {
        enter_raid(w, g_current_raid_level)
    }
    if _hub_btn_hit(hub_r) {
        enter_hub(w)
    }
}
