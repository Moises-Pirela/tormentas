package main

import rl     "vendor:raylib"
import        "core:fmt"
import        "core:strings"
import p2p    "p2p"

MenuFocus :: enum { None, Name, IP }

@(private = "file")
g_mm: struct {
    focus:         MenuFocus,
    show_join:     bool,       
    ip:            [64]u8,
    conn_timer:    f32,        
    settings_open: bool,       
}

CONN_TIMEOUT :: f32(15.0)

@(private)
_on_black_singleplayer :: proc() {
    g_is_host    = true
    init_game()
    g_hub_active = true
    g_app_state  = .Playing
    set_playing_state(.Hub)
    fade_from_black()
}

@(private)
_on_black_start_online :: proc() {
    init_game()
    g_hub_active = true
    g_app_state  = .Playing
    set_playing_state(.Hub)
    fade_from_black()
}

@(private)
_on_black_to_menu :: proc() {
    shutdown_game()
    g_app_state = .MainMenu
    fade_from_black()
}

update_main_menu :: proc(dt: f32) {
    if g_disconnect_msg_timer > 0 { g_disconnect_msg_timer -= dt }

    if g_mm.settings_open {
        update_keybinds_screen()
        if update_settings_overlay() {
            g_mm.settings_open = false
            g_keybinds_open    = false
            g_rebind_idx       = -1
        }
        return
    }

    mp := rl.GetMousePosition()
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    cx      := sw * 0.5
    field_w := sw * 0.28
    btn_w   := sw * 0.20
    btn_h   := uis(44)
    gap     := uis(10)

    name_r := rl.Rectangle{cx - field_w * 0.5, sh * 0.42, field_w, uis(34)}
    if rl.IsMouseButtonPressed(.LEFT) {
        if rl.CheckCollisionPointRec(mp, name_r) {
            g_mm.focus = .Name
        } else if g_mm.focus == .Name {
            g_mm.focus = .None
        }
    }
    if g_mm.focus == .Name {
        _mm_text_input(g_player_name[:PLAYER_NAME_MAX])
    }

    total  := btn_w * 3 + gap * 2
    b0x    := cx - total * 0.5
    btn_y  := sh * 0.57

    sp_r   := rl.Rectangle{b0x,                        btn_y, btn_w, btn_h}
    host_r := rl.Rectangle{b0x + btn_w + gap,           btn_y, btn_w, btn_h}
    join_r := rl.Rectangle{b0x + (btn_w + gap) * 2,    btn_y, btn_w, btn_h}

    if _mm_btn_hit(sp_r) {
        g_mm.show_join = false
        g_mm.focus     = .None
        fade_to_black(_on_black_singleplayer)
    }

    if _mm_btn_hit(host_r) {
        g_mm.show_join = false
        g_mm.focus     = .None
        g_is_host      = true
        copy(g_session.local_name[:], g_player_name[:])
        p2p.session_host(&g_session, 7777)
        g_mm.conn_timer = 0
        g_app_state = .Connecting
    }

    if _mm_btn_hit(join_r) {
        g_mm.show_join = !g_mm.show_join
        if g_mm.show_join { g_mm.focus = .IP } else { g_mm.focus = .None }
    }

    if g_mm.show_join {
        ip_r := rl.Rectangle{cx - field_w * 0.5, sh * 0.70, field_w, uis(34)}
        if rl.IsMouseButtonPressed(.LEFT) {
            if rl.CheckCollisionPointRec(mp, ip_r) {
                g_mm.focus = .IP
            } else if g_mm.focus == .IP {
                g_mm.focus = .None
            }
        }
        if g_mm.focus == .IP {
            _mm_text_input(g_mm.ip[:63])
        }

        conn_r := rl.Rectangle{cx - btn_w * 0.5, sh * 0.80, btn_w, btn_h}
        if _mm_btn_hit(conn_r) {
            ip_raw := strings.clone_from_cstring(cstring(&g_mm.ip[0]),
                context.temp_allocator)
            if ip_raw == "" { ip_raw = "127.0.0.1" }
            g_is_host = false
            copy(g_session.local_name[:], g_player_name[:])
            p2p.session_join(&g_session, ip_raw, 7777)
            g_mm.conn_timer = 0
            g_mm.focus      = .None
            g_app_state     = .Connecting
        }
    }
}

update_connecting :: proc(dt: f32) {
    g_mm.conn_timer += dt

    p2p.session_poll(&g_session, dt)

    // Handshake succeeded
    if p2p.session_is_online(&g_session) && g_fade_phase == .Idle {
        fade_to_black(_on_black_start_online)
        return
    }

    if p2p.session_is_disconnected(&g_session) {
        p2p.session_shutdown(&g_session)
        g_disconnect_msg_timer = DISCONNECT_MSG_DURATION
        g_app_state = .MainMenu
        return
    }

    if rl.IsKeyPressed(.ESCAPE) || g_mm.conn_timer >= CONN_TIMEOUT {
        p2p.session_shutdown(&g_session)
        g_is_host   = false
        g_app_state = .MainMenu
    }
}

draw_main_menu :: proc() {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    cx := sw * 0.5

    title    := cstring("LAS TORMENTAS")
    title_fs := uis(52)
    tsz      := rl.MeasureTextEx(g_font, title, title_fs, 0.8)
    rl.DrawTextEx(g_font, title,
        {cx - tsz.x * 0.5, sh * 0.12},
        title_fs, 0.8, rl.Color{200, 178, 108, 255})

    sub    := cstring("prototype")
    sub_fs := uis(11)
    ssz    := rl.MeasureTextEx(g_font, sub, sub_fs, 0.5)
    rl.DrawTextEx(g_font, sub,
        {cx - ssz.x * 0.5, sh * 0.12 + title_fs + uis(6)},
        sub_fs, 0.5, rl.Color{120, 108, 72, 160})

    if g_disconnect_msg_timer > 0 {
        frac := clamp(g_disconnect_msg_timer / DISCONNECT_MSG_DURATION, 0, 1)
        a    := u8(frac * 210)
        msg  := cstring("Connection to peer was lost.")
        mfs  := uis(11)
        msz  := rl.MeasureTextEx(g_font, msg, mfs, 0.5)
        rl.DrawTextEx(g_font, msg,
            {cx - msz.x * 0.5, sh * 0.33},
            mfs, 0.5, rl.Color{220, 80, 60, a})
    }

    field_w := sw * 0.28
    btn_w   := sw * 0.20
    btn_h   := uis(44)
    gap     := uis(10)

    lbl    := cstring("PLAYER NAME")
    lbl_fs := uis(10)
    lsz    := rl.MeasureTextEx(g_font, lbl, lbl_fs, 0.5)
    name_r := rl.Rectangle{cx - field_w * 0.5, sh * 0.42, field_w, uis(34)}
    rl.DrawTextEx(g_font, lbl,
        {cx - lsz.x * 0.5, name_r.y - lbl_fs - uis(5)},
        lbl_fs, 0.5, rl.Color{130, 118, 82, 200})
    _mm_field_draw(name_r, g_player_name[:], g_mm.focus == .Name, "Wanderer")

    total := btn_w * 3 + gap * 2
    b0x   := cx - total * 0.5
    btn_y := sh * 0.57

    sp_r   := rl.Rectangle{b0x,                        btn_y, btn_w, btn_h}
    host_r := rl.Rectangle{b0x + btn_w + gap,           btn_y, btn_w, btn_h}
    join_r := rl.Rectangle{b0x + (btn_w + gap) * 2,    btn_y, btn_w, btn_h}

    _mm_btn_draw(sp_r,   "SINGLEPLAYER", false)
    _mm_btn_draw(host_r, "HOST GAME",    false)
    _mm_btn_draw(join_r, "JOIN GAME",    g_mm.show_join) // highlighted when open

    if g_mm.show_join {
        ip_lbl    := cstring("HOST IP  (port 7777)")
        ip_lbl_fs := uis(10)
        ilsz      := rl.MeasureTextEx(g_font, ip_lbl, ip_lbl_fs, 0.5)
        ip_r      := rl.Rectangle{cx - field_w * 0.5, sh * 0.70, field_w, uis(34)}
        rl.DrawTextEx(g_font, ip_lbl,
            {cx - ilsz.x * 0.5, ip_r.y - ip_lbl_fs - uis(5)},
            ip_lbl_fs, 0.5, rl.Color{130, 118, 82, 200})
        _mm_field_draw(ip_r, g_mm.ip[:], g_mm.focus == .IP, "127.0.0.1")

        conn_r := rl.Rectangle{cx - btn_w * 0.5, sh * 0.80, btn_w, btn_h}
        _mm_btn_draw(conn_r, "CONNECT", false)
    }

    set_fs   := uis(10)
    set_lbl  := cstring("SETTINGS")
    set_sz   := rl.MeasureTextEx(g_font, set_lbl, set_fs, 0.5)
    set_bw   := set_sz.x + uis(22)
    set_bh   := set_fs + uis(14)
    set_r    := rl.Rectangle{
        sw - set_bw - uis(12),
        sh - set_bh - uis(12),
        set_bw, set_bh,
    }
    set_hot := rl.CheckCollisionPointRec(rl.GetMousePosition(), set_r)
    rl.DrawRectangleRec(set_r, rl.Color{24, 20, 14, 240} if set_hot else rl.Color{14, 11, 8, 200})
    rl.DrawRectangleLinesEx(set_r, 1, COL_BRASS if set_hot else COL_RULE)
    rl.DrawTextEx(g_font, set_lbl,
        {set_r.x + (set_bw - set_sz.x) * 0.5, set_r.y + (set_bh - set_fs) * 0.5},
        set_fs, 0.5, COL_BRASS if set_hot else COL_MUTED)

    if set_hot && rl.IsMouseButtonReleased(.LEFT) {
        g_mm.settings_open = true
    }

    if g_mm.settings_open {
        draw_settings_overlay()
        draw_keybinds_screen()
    }
}

draw_connecting :: proc() {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    cx := sw * 0.5

    msg: string
    if g_is_host {
        msg = "Waiting for player..."
    } else {
        ip_raw := strings.clone_from_cstring(cstring(&g_mm.ip[0]),
            context.temp_allocator)
        if ip_raw == "" { ip_raw = "127.0.0.1" }
        msg = fmt.tprintf("Connecting to %s:7777...", ip_raw)
    }
    msg_cs := strings.clone_to_cstring(msg, context.temp_allocator)

    mfs := uis(18)
    msz := rl.MeasureTextEx(g_font, msg_cs, mfs, 0.5)
    rl.DrawTextEx(g_font, msg_cs,
        {cx - msz.x * 0.5, sh * 0.40},
        mfs, 0.5, rl.Color{200, 182, 118, 255})

    bar_w := sw * 0.22
    bar_h := uis(3)
    prog  := clamp(g_mm.conn_timer / CONN_TIMEOUT, 0, 1)
    rl.DrawRectangleV({cx - bar_w * 0.5, sh * 0.50}, {bar_w, bar_h},
        rl.Color{35, 33, 25, 255})
    rl.DrawRectangleV({cx - bar_w * 0.5, sh * 0.50}, {bar_w * prog, bar_h},
        rl.Color{140, 118, 60, 200})

    cancel := cstring("ESC — cancel")
    cfs    := uis(10)
    csz    := rl.MeasureTextEx(g_font, cancel, cfs, 0.5)
    rl.DrawTextEx(g_font, cancel,
        {cx - csz.x * 0.5, sh * 0.58},
        cfs, 0.5, rl.Color{110, 100, 72, 180})
}

@(private = "file")
_mm_btn_hit :: proc(r: rl.Rectangle) -> bool {
    return rl.IsMouseButtonReleased(.LEFT) &&
           rl.CheckCollisionPointRec(rl.GetMousePosition(), r)
}

@(private = "file")
_mm_btn_draw :: proc(r: rl.Rectangle, label: cstring, active: bool) {
    mp   := rl.GetMousePosition()
    over := rl.CheckCollisionPointRec(mp, r)
    hot  := over || active

    bg     := rl.Color{52, 46, 34, 255} if hot else rl.Color{24, 21, 16, 255}
    border := rl.Color{165, 142, 72, 255} if hot else rl.Color{62, 56, 42, 200}
    rl.DrawRectangleRec(r, bg)
    rl.DrawRectangleLinesEx(r, 1, border)

    fs  := uis(11)
    tsz := rl.MeasureTextEx(g_font, label, fs, 0.5)
    col := rl.Color{235, 215, 145, 255} if hot else rl.Color{165, 152, 102, 215}
    rl.DrawTextEx(g_font, label,
        {r.x + (r.width - tsz.x) * 0.5, r.y + (r.height - tsz.y) * 0.5},
        fs, 0.5, col)
}

@(private = "file")
_mm_field_draw :: proc(r: rl.Rectangle, buf: []u8, focused: bool, placeholder: cstring) {
    bg     := rl.Color{16, 14, 11, 255}
    border := rl.Color{155, 135, 72, 255} if focused else rl.Color{52, 47, 36, 180}
    rl.DrawRectangleRec(r, bg)
    rl.DrawRectangleLinesEx(r, 1, border)

    cstr  := cstring(&buf[0])
    empty := buf[0] == 0
    fs    := uis(12)
    tx    := r.x + uis(10)
    ty    := r.y + (r.height - fs) * 0.5

    if empty && !focused {
        rl.DrawTextEx(g_font, placeholder, {tx, ty}, fs, 0.5,
            rl.Color{85, 78, 58, 145})
    } else {
        rl.DrawTextEx(g_font, cstr, {tx, ty}, fs, 0.5,
            rl.Color{218, 206, 160, 255})
        if focused && (int(rl.GetTime() * 2) % 2 == 0) {
            tw := rl.MeasureTextEx(g_font, cstr, fs, 0.5).x
            rl.DrawRectangle(i32(tx + tw + 2), i32(ty), 2, i32(fs),
                rl.Color{218, 206, 160, 255})
        }
    }
}

@(private = "file")
_mm_text_input :: proc(buf: []u8) {
    max := len(buf) - 1
    cur := 0
    for cur < max && buf[cur] != 0 { cur += 1 }
    c := rl.GetCharPressed()
    for c != 0 {
        if cur < max && c >= 32 && c < 127 {
            buf[cur] = u8(c)
            cur += 1
        }
        c = rl.GetCharPressed()
    }
    if rl.IsKeyPressed(.BACKSPACE) && cur > 0 {
        cur -= 1
        buf[cur] = 0
    }
}
