package main

import rl   "vendor:raylib"

g_lore_panel_id: u8 = 0

ui_open_lore :: proc(lore_id: u8) {
    g_lore_panel_id = lore_id
    ui_open(.Lore)
}

draw_lore_panel :: proc() {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    if rl.IsKeyPressed(.ESCAPE) {
        ui_close(.Lore)
        return
    }

    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 160})

    page, ok := lore_get_page(g_lore_panel_id)

    PW  := uis(560)
    PH  := uis(420)
    px  := (sw - PW) * 0.5
    py  := (sh - PH) * 0.5

    rl.DrawRectangleRec({px + uis(6), py + uis(6), PW, PH},
        rl.Color{0, 0, 0, 100})

    rl.DrawRectangleRec({px, py, PW, PH},
        rl.Color{198, 178, 128, 252})
    rl.DrawRectangleRec({px, py, PW, uis(4)},
        rl.Color{160, 138, 90, 200})
    rl.DrawRectangleRec({px, py + PH - uis(4), PW, uis(4)},
        rl.Color{148, 126, 82, 200})

    for i in 0..<6 {
        fi := f32(i)
        a  := u8(28 - i * 4)
        rl.DrawRectangleRec({px + fi * uis(3), py, uis(3), PH},
            rl.Color{60, 40, 18, a})
        rl.DrawRectangleRec({px + PW - fi * uis(3) - uis(3), py, uis(3), PH},
            rl.Color{60, 40, 18, a})
    }

    rl.DrawRectangleLinesEx({px, py, PW, PH}, uis(2),
        rl.Color{110, 82, 36, 200})
    rl.DrawRectangleLinesEx({px + uis(8), py + uis(8), PW - uis(16), PH - uis(16)},
        uis(1), rl.Color{140, 110, 55, 100})

    CORN := uis(14)
    corners := [4][2]f32{
        {px + uis(12), py + uis(12)},
        {px + PW - uis(12) - CORN, py + uis(12)},
        {px + uis(12), py + PH - uis(12) - CORN},
        {px + PW - uis(12) - CORN, py + PH - uis(12) - CORN},
    }
    for c in corners {
        rl.DrawLineEx({c[0] + CORN*0.5, c[1]}, {c[0] + CORN*0.5, c[1] + CORN},
            uis(1.5), rl.Color{100, 72, 28, 160})
        rl.DrawLineEx({c[0], c[1] + CORN*0.5}, {c[0] + CORN, c[1] + CORN*0.5},
            uis(1.5), rl.Color{100, 72, 28, 160})
    }

    if !ok {
        msg := cstring("[ Document not found ]")
        msz := rl.MeasureTextEx(g_font_body, msg, uis(12), 1)
        rl.DrawTextEx(g_font_body, msg,
            {px + PW*0.5 - msz.x*0.5, py + PH*0.5 - msz.y*0.5},
            uis(12), 1, rl.Color{100, 80, 50, 180})
    } else {
        title := loc_lookup(cstring(&page.title[0]))
        title_fs := uis(16)
        tsz := rl.MeasureTextEx(g_font, title, title_fs, 1)
        rl.DrawTextEx(g_font, title,
            {px + PW*0.5 - tsz.x*0.5, py + uis(28)},
            title_fs, 1, rl.Color{80, 52, 18, 230})

        rl.DrawLineEx(
            {px + uis(32), py + uis(28) + title_fs + uis(4)},
            {px + PW - uis(32), py + uis(28) + title_fs + uis(4)},
            uis(1), rl.Color{110, 80, 32, 140})

        body_x   := px + uis(36)
        body_y   := py + uis(28) + title_fs + uis(18)
        body_w   := PW - uis(72)
        body_fs  := uis(12)
        body_col := rl.Color{50, 34, 14, 220}
        line_h   := body_fs * 1.55

        body_str := string(loc_lookup(cstring(&page.body[0])))

        lore_draw_wrapped(body_str, body_x, body_y, body_w, body_fs, line_h, body_col)
    }

    hint := cstring("[ ESC to close ]")
    hsz  := rl.MeasureTextEx(g_font_body, hint, uis(9), 0.5)
    rl.DrawTextEx(g_font_body, hint,
        {px + PW*0.5 - hsz.x*0.5, py + PH - uis(22)},
        uis(9), 0.5, rl.Color{90, 68, 32, 160})

    mp := rl.GetMousePosition()
    if rl.IsMouseButtonPressed(.LEFT) &&
       !rl.CheckCollisionPointRec(mp, {px, py, PW, PH}) {
        ui_close(.Lore)
    }
}

lore_draw_wrapped :: proc(text: string, x, y, max_w, fs, line_h: f32, col: rl.Color) {
    if len(text) == 0 { return }

    cur_x  := x
    cur_y  := y
    start  := 0
    i      := 0

    flush_word :: proc(s: string, cx, cy: ^f32, lh: f32, x0, max_w, fs: f32, col: rl.Color) {
        if len(s) == 0 { return }
        sb: [256]u8
        n := min(len(s), 255)
        copy(sb[:n], s[:n])
        sb[n] = 0
        wsz := rl.MeasureTextEx(g_font_body, cstring(&sb[0]), fs, 0.5)
        if cx^ > x0 && cx^ + wsz.x > x0 + max_w {
            cy^  += lh
            cx^   = x0
        }
        rl.DrawTextEx(g_font_body, cstring(&sb[0]), {cx^, cy^}, fs, 0.5, col)
        cx^ += wsz.x
    }

    space_w: f32
    {
        sb: [2]u8 = {' ', 0}
        space_w = rl.MeasureTextEx(g_font_body, cstring(&sb[0]), fs, 0.5).x
    }

    for i <= len(text) {
        is_end := i == len(text)
        is_sep := is_end || text[i] == ' ' || text[i] == '\n'
        if is_sep && i > start {
            word := text[start:i]

            if i > 0 && text[i-1] == '\n' {
                flush_word(word, &cur_x, &cur_y, line_h * 0.6, x, max_w, fs, col)
                cur_y += line_h
                cur_x  = x
            } else {
                flush_word(word, &cur_x, &cur_y, line_h, x, max_w, fs, col)
                if !is_end { cur_x += space_w }
            }
            start = i + 1
        } else if is_sep {
            if !is_end && text[i] == '\n' {
                cur_y += line_h
                cur_x  = x
            }
            start = i + 1
        }
        i += 1
    }
}
