package main

import rl   "vendor:raylib"
import p2p  "p2p"
import sw   "../steamworks"
import clay "../clay"

@(private="file")
g_invite_sent_id: sw.CSteamID
@(private="file")
g_invite_timer: f32

draw_social_panel :: proc() {
    sW := f32(rl.GetScreenWidth())
    mp  := rl.GetMousePosition()

    g_invite_timer = max(g_invite_timer - rl.GetFrameTime(), 0)

    online   := p2p.session_is_online(&g_session)
    hosting  := g_session.state == .Hosting
    offline  := g_session.state == .Offline

    friends := steam_get_friends()
    nf      := len(friends)

    row_h    := uis(38)
    header_h := uis(80)
    status_h := uis(46)
    bottom_h := uis(60)
    ph := header_h + status_h + f32(max(nf, 1)) * row_h + bottom_h
    pw := uis(310)
    px := sW - pw - uis(14)
    py := uis(46)

    // Panel background (Clay for border + bg)
    clay.BeginLayout()
    if clay.UI(clay.ID("SocialPanel"))({
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

    // Title
    title    := cstring("Social")
    title_fs := uis(16)
    tsz      := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title,
        {px + pw * 0.5 - tsz.x * 0.5, py + uis(14)},
        title_fs, 1, COL_PARCH)
    rl.DrawLineEx(
        {px + uis(14), py + uis(42)},
        {px + pw - uis(14), py + uis(42)}, 1, COL_RULE)

    // Session status
    status_y := py + header_h - uis(6)
    status_msg: cstring
    status_col: rl.Color
    switch {
    case online:
        status_msg = cstring(&g_session.remote_name[0])
        status_col = rl.Color{100, 220, 100, 255}
    case hosting:
        status_msg = "Waiting for friend..."
        status_col = COL_BRASS
    case:
        status_msg = "Offline"
        status_col = COL_MUTED
    }
    label_fs := uis(10)
    rl.DrawTextEx(g_font_body, "Session:", {px + uis(14), status_y}, label_fs, 0.5, COL_MUTED)
    ssz := rl.MeasureTextEx(g_font_body, status_msg, label_fs, 0.5)
    rl.DrawTextEx(g_font_body, status_msg,
        {px + pw - uis(14) - ssz.x, status_y}, label_fs, 0.5, status_col)
    rl.DrawLineEx(
        {px + uis(14), status_y + uis(20)},
        {px + pw - uis(14), status_y + uis(20)}, 1, COL_RULE)

    // Friends list
    friends_y0 := py + header_h + status_h
    if nf == 0 {
        no_friends := cstring(g_steam_ok ? "No friends online" : "Steam not available")
        nfsz := rl.MeasureTextEx(g_font_body, no_friends, label_fs, 0.5)
        rl.DrawTextEx(g_font_body, no_friends,
            {px + pw * 0.5 - nfsz.x * 0.5, friends_y0 + row_h * 0.5 - label_fs * 0.5},
            label_fs, 0.5, COL_MUTED)
    }

    for i in 0..<nf {
        f  := friends[i]
        fy := friends_y0 + f32(i) * row_h

        rl.DrawCircle(i32(px + uis(22)), i32(fy + row_h * 0.5), uis(4),
            rl.Color{100, 220, 100, 220})

        name_cs := cstring(raw_data(f.name))
        name_fs := uis(11)
        rl.DrawTextEx(g_font_body, name_cs,
            {px + uis(32), fy + row_h * 0.5 - name_fs * 0.5},
            name_fs, 0.5, COL_PARCH)

        if g_steam_lobby_id != 0 {
            inv_w  := uis(52)
            inv_h  := uis(22)
            inv_r  := rl.Rectangle{
                px + pw - uis(14) - inv_w,
                fy + row_h * 0.5 - inv_h * 0.5,
                inv_w, inv_h,
            }
            inv_fs := uis(10)
            sent   := g_invite_timer > 0 && g_invite_sent_id == f.steam_id
            if sent {
                rl.DrawRectangleRec(inv_r, rl.Color{20, 80, 20, 200})
                rl.DrawRectangleLinesEx(inv_r, 1, rl.Color{80, 200, 80, 180})
                lbl := cstring("Sent!")
                lsz := rl.MeasureTextEx(g_font_body, lbl, inv_fs, 0.5)
                rl.DrawTextEx(g_font_body, lbl,
                    {inv_r.x + (inv_r.width - lsz.x) * 0.5,
                     inv_r.y + (inv_r.height - inv_fs) * 0.5},
                    inv_fs, 0.5, rl.Color{120, 240, 120, 255})
            } else {
                inv_hot := rl.CheckCollisionPointRec(mp, inv_r)
                inv_bg  := rl.Color{80, 58, 14, 255} if inv_hot else rl.Color{50, 36, 10, 200}
                rl.DrawRectangleRec(inv_r, inv_bg)
                rl.DrawRectangleLinesEx(inv_r, 1, COL_BRASS if inv_hot else COL_RULE)
                lbl     := cstring("Invite")
                lsz     := rl.MeasureTextEx(g_font_body, lbl, inv_fs, 0.5)
                lbl_col := rl.Color{235, 215, 145, 255} if inv_hot else COL_BRASS
                rl.DrawTextEx(g_font_body, lbl,
                    {inv_r.x + (inv_r.width - lsz.x) * 0.5,
                     inv_r.y + (inv_r.height - inv_fs) * 0.5},
                    inv_fs, 0.5, lbl_col)
                if inv_hot && rl.IsMouseButtonReleased(.LEFT) {
                    steam_lobby_invite(f.steam_id)
                    g_invite_sent_id = f.steam_id
                    g_invite_timer   = 2.5
                }
            }
        }
    }

    // Bottom action button
    btn_w  := uis(180)
    btn_h  := uis(34)
    btn_x  := px + pw * 0.5 - btn_w * 0.5
    btn_y  := py + ph - bottom_h * 0.5 - btn_h * 0.5
    btn_r  := rl.Rectangle{btn_x, btn_y, btn_w, btn_h}
    btn_hot := rl.CheckCollisionPointRec(mp, btn_r)

    switch {
    case online:
        // Disconnect
        btn_bg  := rl.Color{90, 20, 20, 240} if btn_hot else rl.Color{50, 12, 12, 220}
        btn_brd := rl.Color{200, 50, 50, 200} if btn_hot else rl.Color{140, 30, 30, 180}
        rl.DrawRectangleRec(btn_r, btn_bg)
        rl.DrawRectangleLinesEx(btn_r, 1.5, btn_brd)
        lbl     := cstring("Disconnect")
        lfs     := uis(12)
        lsz     := rl.MeasureTextEx(g_font_body, lbl, lfs, 0.5)
        lbl_col := rl.Color{240, 100, 100, 255} if btn_hot else rl.Color{200, 70, 70, 230}
        rl.DrawTextEx(g_font_body, lbl,
            {btn_r.x + (btn_r.width - lsz.x) * 0.5,
             btn_r.y + (btn_r.height - lfs) * 0.5},
            lfs, 0.5, lbl_col)
        if btn_hot && rl.IsMouseButtonReleased(.LEFT) {
            p2p.session_shutdown(&g_session)
            steam_lobby_leave()
            g_is_host = false
        }

    case hosting:
        // Already waiting — show greyed out status
        lbl := cstring("Waiting for friend...")
        lfs := uis(11)
        lsz := rl.MeasureTextEx(g_font_body, lbl, lfs, 0.5)
        rl.DrawTextEx(g_font_body, lbl,
            {btn_r.x + (btn_r.width - lsz.x) * 0.5,
             btn_r.y + (btn_r.height - lfs) * 0.5},
            lfs, 0.5, COL_MUTED)

    case offline:
        // Open to Friends
        btn_bg  := rl.Color{80, 58, 14, 255} if btn_hot else rl.Color{50, 36, 10, 220}
        btn_brd := COL_BRASS if btn_hot else COL_RULE
        rl.DrawRectangleRec(btn_r, btn_bg)
        rl.DrawRectangleLinesEx(btn_r, 1.5, btn_brd)
        lbl     := cstring("Open to Friends")
        lfs     := uis(12)
        lsz     := rl.MeasureTextEx(g_font_body, lbl, lfs, 0.5)
        lbl_col := rl.Color{235, 215, 145, 255} if btn_hot else COL_BRASS
        rl.DrawTextEx(g_font_body, lbl,
            {btn_r.x + (btn_r.width - lsz.x) * 0.5,
             btn_r.y + (btn_r.height - lfs) * 0.5},
            lfs, 0.5, lbl_col)
        if btn_hot && rl.IsMouseButtonReleased(.LEFT) {
            copy(g_session.local_name[:], g_player_name[:])
            g_is_host = true
            p2p.session_host(&g_session)
            steam_lobby_create()
        }
    }
}
