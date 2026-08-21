package main

import rl   "vendor:raylib"
import p2p  "p2p"
import sw   "../steamworks"
import clay "../clay"
import      "core:fmt"

@(private="file")
g_invite_sent_id: sw.CSteamID
@(private="file")
g_invite_timer: f32

draw_social_panel :: proc() {
    g_invite_timer = max(g_invite_timer - rl.GetFrameTime(), 0)

    online   := p2p.session_is_online(&g_session)
    hosting  := g_session.state == .Hosting
    offline  := g_session.state == .Offline

    friends := steam_get_friends()
    nf      := len(friends)

    row_h    := uis(36)
    header_h := uis(80)
    status_h := uis(46)
    bottom_h := uis(60)
    ph := header_h + status_h + f32(max(nf, 1)) * row_h + bottom_h
    pw := uis(310)

    status_msg: string
    status_col: rl.Color
    switch {
    case online:
        if p2p.is_host(&g_session) {
            status_msg = fmt.tprintf("Hosting — %d connected", p2p.session_active_peer_count(&g_session))
        } else if g_session.roster[0].known {
            status_msg = string(cstring(&g_session.roster[0].name[0]))
        } else {
            status_msg = "Connected"
        }
        status_col = rl.Color{100, 220, 100, 255}
    case hosting:
        status_msg = "Waiting for friend..."
        status_col = COL_BRASS
    case:
        status_msg = "Offline"
        status_col = COL_MUTED
    }

    clay.BeginLayout()
    ui_panel_begin("SocialPanel", "Social", pw, ph,
        { anchor = .RightTop, offset = { -uis(14), uis(46) } })
    {
        ui_hstack_begin("SocStatus", u16(uis(6)), 0, .Center)
        ui_label("SocStatusLbl", "Session:", uis(10), COL_MUTED)
        ui_grow("SocStatusSpc")
        ui_label("SocStatusVal", status_msg, uis(10), status_col)
        ui_hstack_end()

        ui_divider("SocStatusDiv")

        if nf == 0 {
            ui_label("SocNoFriends",
                g_steam_ok ? "No friends online" : "Steam not available",
                uis(10), COL_MUTED)
        }

        ui_vstack_begin("SocFriends", u16(uis(4)))
        for i in 0..<nf {
            f := friends[i]
            ui_hstack_begin(fmt.tprintf("SocRow%d", i), u16(uis(8)), 0, .Center)
            ui_dot(fmt.tprintf("SocDot%d", i), rl.Color{100, 220, 100, 220}, uis(8))
            ui_label(fmt.tprintf("SocName%d", i), string(cstring(raw_data(f.name))),
                uis(11), COL_PARCH)
            ui_grow(fmt.tprintf("SocRowSpc%d", i))
            if g_steam_lobby_id != 0 {
                sent := g_invite_timer > 0 && g_invite_sent_id == f.steam_id
                if sent {
                    ui_label(fmt.tprintf("SocSent%d", i), "Sent!", uis(10),
                        rl.Color{120, 240, 120, 255})
                } else if ui_button(fmt.tprintf("SocInv%d", i), "Invite", uis(52), uis(22)) {
                    steam_lobby_invite(f.steam_id)
                    g_invite_sent_id = f.steam_id
                    g_invite_timer   = 2.5
                }
            }
            ui_hstack_end()
        }
        ui_vstack_end()

        ui_grow("SocBtnSpacer")

        btn_w := uis(180)
        btn_h := uis(34)
        ui_hstack_begin("SocActionRow", 0, 0, .Center)
        ui_grow("SocActL")
        switch {
        case online:
            if ui_button("SocActionBtn", "Disconnect", btn_w, btn_h, .Danger) {
                p2p.session_shutdown(&g_session)
                steam_lobby_leave()
                g_is_host = false
            }
        case hosting:
            ui_label("SocActionBtn", "Waiting for friend...", uis(11), COL_MUTED)
        case offline:
            if ui_button("SocActionBtn", "Open to Friends", btn_w, btn_h, .Primary) {
                copy(g_session.local_name[:], g_player_name[:])
                g_is_host = true
                p2p.session_host(&g_session)
                steam_lobby_create()
            }
        }
        ui_grow("SocActR")
        ui_hstack_end()
    }
    ui_panel_end()
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)
}
