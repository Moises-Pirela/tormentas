package main

import rl   "vendor:raylib"
import clay "../clay"
import      "core:fmt"

@(private = "file") CHAR_PW :: f32(380)

draw_stats_screen :: proc(w: ^World) {
    if !world_is_valid(w, w.player_id) { return }
    if !world_has_component(w, w.player_id, .Stats) { return }

    st := comp_get(w, w.player_id, .Stats, StatsComp)

    PW   := uis(CHAR_PW)
    HPAD := u16(uis(20))
    VGAP := u16(uis(5))

    ROW_H  := uis(36)
    BTN_SZ := uis(26)

    stat_names  := [3]cstring{ t(.STATS_STRENGTH), t(.STATS_DEXTERITY), t(.STATS_SCIENCE) }
    stat_values := [3]int{ st.strength, st.dexterity, st.science }

    xp_ratio := clamp(st.xp / st.xp_next, 0, 1) if st.xp_next > 0 else f32(0)

    eff_bufs: [3][32]u8
    eff_strs: [3]string
    for i in 0..<3 {
        s: string
        switch i {
        case 0: s = fmt.bprintf(eff_bufs[i][:31], string(t(.STATS_HP_BONUS)),     f32(stat_values[i]-1)*15)
        case 1: s = fmt.bprintf(eff_bufs[i][:31], string(t(.STATS_SPEED_BONUS)),  f32(stat_values[i]-1)*8)
        case 2: s = fmt.bprintf(eff_bufs[i][:31], string(t(.STATS_ENERGY_BONUS)), f32(stat_values[i]-1)*12)
        }
        eff_bufs[i][len(s)] = 0
        eff_strs[i] = s
    }

    lv_buf: [32]u8
    lv_s := fmt.bprintf(lv_buf[:31], "Level  %d", st.level)
    lv_buf[len(lv_s)] = 0

    xp_buf: [48]u8
    xp_s := fmt.bprintf(xp_buf[:47], "%.0f / %.0f xp", st.xp, st.xp_next)
    xp_buf[len(xp_s)] = 0

    pts_buf: [48]u8
    pts_s := fmt.bprintf(pts_buf[:47], "%d  point%s",
        st.stat_points, "s" if st.stat_points != 1 else "")
    pts_buf[len(pts_s)] = 0

    hist_rows := [4][2]string{
        { string(t(.STATS_RAIDS)),        fmt.tprintf("%d",   g_lifetime_stats.successful_raids)    },
        { string(t(.STATS_KILLS)),        fmt.tprintf("%d",   g_lifetime_stats.enemies_killed)      },
        { string(t(.STATS_DEATHS)),       fmt.tprintf("%d",   g_lifetime_stats.deaths)              },
        { string(t(.STATS_BEST_EXTRACT)), fmt.tprintf("%d g", int(g_lifetime_stats.max_extract_gold)) },
    }

    btn_active := st.stat_points > 0

    ui_frame_reset()
    clay.BeginLayout()

    if clay.UI(clay.ID("StatsPanel"))({
        layout = {
            layoutDirection = .TopToBottom,
            childGap        = VGAP,
            childAlignment  = { x = .Center },
            padding         = { left = HPAD, right = HPAD,
                                top  = u16(uis(12)), bottom = u16(uis(12)) },
            sizing          = { clay.SizingFixed(PW), clay.SizingFit() },
        },
        floating = {
            offset     = { 0, 0 },
            attachment = { element = .CenterCenter, parent = .CenterCenter },
            attachTo   = .Root,
        },
        backgroundColor = ui_clay_color(COL_PANEL),
        border          = { color = ui_clay_color(COL_RULE), width = { 1, 1, 1, 1, 0 } },
        cornerRadius    = clay.CornerRadiusAll(4),
    }) {
        if clay.UI(clay.ID("CharTitle"))({
            layout = {
                sizing         = { clay.SizingGrow(), clay.SizingFit() },
                childAlignment = { x = .Center },
            },
        }) {
            clay.TextDynamic(string(t(.STATS_TITLE)), clay.TextConfig({
                fontSize      = u16(uis(20)),
                textColor     = ui_clay_color(COL_PARCH),
                letterSpacing = 10,
            }))
        }

        ui_divider("CharDiv0")

        if clay.UI(clay.ID("CharLevel"))({
            layout = { sizing = { clay.SizingGrow(), clay.SizingFit() } },
        }) {
            clay.TextDynamic(string(lv_s), clay.TextConfig({
                fontSize  = u16(uis(16)),
                textColor = ui_clay_color(COL_PARCH),
            }))
        }

        ui_hbar("CharXP", xp_ratio,
            rl.Color{ 180, 148, 36, 255 },
            rl.Color{  30,  24, 10, 255 },
            uis(10))

        if clay.UI(clay.ID("CharXPText"))({
            layout = {
                sizing         = { clay.SizingGrow(), clay.SizingFit() },
                childAlignment = { x = .Center },
            },
        }) {
            clay.TextDynamic(string(xp_s), clay.TextConfig({
                fontSize      = u16(uis(11)),
                textColor     = ui_clay_color(COL_MUTED),
                letterSpacing = 4,
            }))
        }

        ui_divider("CharDiv1")

        if clay.UI(clay.ID("CharStatsHdr"))({
            layout = {
                layoutDirection = .LeftToRight,
                sizing          = { clay.SizingGrow(), clay.SizingFit() },
            },
        }) {
            ui_label("CharStatsLbl", string(t(.STATS_SECTION)), uis(13), COL_MUTED)

            if clay.UI(clay.ID("CharStatsHdrSep"))({
                layout = { sizing = { clay.SizingGrow(), clay.SizingFit() } },
            }) {}

            if btn_active {
                ui_label("CharStatsAvail", string(pts_s), uis(13),
                    rl.Color{ 200, 175, 60, 230 })
            }
        }

        for i in 0..<3 {
            row_id := fmt.tprintf("CharStatRow%d",  i)
            btn_id := fmt.tprintf("CharStatBtn%d",  i)

            btn_bg  := rl.Color{ 55, 44, 18, 220 } if btn_active else rl.Color{ 24, 20, 12, 140 }
            btn_brd := ui_clay_color(COL_BRASS)     if btn_active else ui_clay_color(rl.Color{ 55, 48, 32,  80 })
            btn_col := ui_clay_color(COL_PARCH)     if btn_active else ui_clay_color(rl.Color{ 80, 70, 45, 100 })

            if clay.UI(clay.ID(row_id))({
                layout = {
                    layoutDirection = .LeftToRight,
                    childGap        = u16(uis(6)),
                    childAlignment  = { y = .Center },
                    padding         = { left  = u16(uis(10)), right  = u16(uis(8)),
                                        top   = 0,            bottom = 0 },
                    sizing          = { clay.SizingGrow(), clay.SizingFixed(ROW_H) },
                },
                backgroundColor = { 18, 14, 10, 200 },
                border          = { color = { 80, 65, 42, 120 }, width = { 1, 1, 1, 1, 0 } },
            }) {
                clay.TextDynamic(string(stat_names[i]), clay.TextConfig({
                    fontSize  = u16(uis(15)),
                    textColor = ui_clay_color(COL_PARCH),
                }))

                if clay.UI(clay.ID(fmt.tprintf("CharStatSep%d", i)))({
                    layout = { sizing = { clay.SizingGrow(), clay.SizingGrow() } },
                }) {}

                clay.TextDynamic(eff_strs[i], clay.TextConfig({
                    fontSize      = u16(uis(12)),
                    textColor     = ui_clay_color(COL_MUTED),
                    letterSpacing = 2,
                }))

                val_str := fmt.tprintf("%d", stat_values[i])
                if clay.UI(clay.ID(fmt.tprintf("CharStatVal%d", i)))({
                    layout = {
                        sizing         = { clay.SizingFixed(uis(24)), clay.SizingFit() },
                        childAlignment = { x = .Center },
                    },
                }) {
                    clay.TextDynamic(val_str, clay.TextConfig({
                        fontSize  = u16(uis(15)),
                        textColor = ui_clay_color(COL_BRASS),
                    }))
                }

                if clay.UI(clay.ID(btn_id))({
                    layout = {
                        sizing         = { clay.SizingFixed(BTN_SZ), clay.SizingFixed(BTN_SZ) },
                        childAlignment = { x = .Center, y = .Center },
                    },
                    backgroundColor = ui_clay_color(btn_bg),
                    border          = { color = btn_brd, width = { 1, 1, 1, 1, 0 } },
                    cornerRadius    = clay.CornerRadiusAll(3),
                }) {
                    clay.TextDynamic("+", clay.TextConfig({
                        fontSize  = u16(uis(16)),
                        textColor = btn_col,
                    }))
                }
            }
        }

        ui_divider("CharDiv2")

        ui_section("CharHistHdr", string(t(.STATS_HISTORY)))

        for ri in 0..<4 {
            if clay.UI(clay.ID(fmt.tprintf("CharHistRow%d", ri)))({
                layout = {
                    layoutDirection = .LeftToRight,
                    sizing          = { clay.SizingGrow(), clay.SizingFit() },
                },
            }) {
                clay.TextDynamic(hist_rows[ri][0], clay.TextConfig({
                    fontSize      = u16(uis(13)),
                    textColor     = ui_clay_color(COL_MUTED),
                    letterSpacing = 4,
                }))
                if clay.UI(clay.ID(fmt.tprintf("CharHistSep%d", ri)))({
                    layout = { sizing = { clay.SizingGrow(), clay.SizingFit() } },
                }) {}
                clay.TextDynamic(hist_rows[ri][1], clay.TextConfig({
                    fontSize      = u16(uis(13)),
                    textColor     = ui_clay_color(COL_PARCH),
                    letterSpacing = 4,
                }))
            }
        }

        ui_divider("CharDiv3")

        if clay.UI(clay.ID("CharClose"))({
            layout = {
                sizing         = { clay.SizingGrow(), clay.SizingFit() },
                childAlignment = { x = .Center },
            },
        }) {
            clay.TextDynamic(string(t(.STATS_BTN_CLOSE)), clay.TextConfig({
                fontSize      = u16(uis(12)),
                textColor     = ui_clay_color(COL_MUTED),
                letterSpacing = 5,
            }))
        }
    }

    cmds := clay.EndLayout()

    if btn_active && rl.IsMouseButtonPressed(.LEFT) {
        mp := rl.GetMousePosition()
        for i in 0..<3 {
            el := clay.GetElementData(clay.ID(fmt.tprintf("CharStatBtn%d", i)))
            if !el.found { continue }
            bb := el.boundingBox
            if !rl.CheckCollisionPointRec(mp, { bb.x, bb.y, bb.width, bb.height }) { continue }

            switch i {
            case 0: st.strength  += 1
            case 1: st.dexterity += 1
            case 2: st.science   += 1
            }
            st.stat_points -= 1
            play_sfx("stat_up")
            ui_mark_dirty(.Stats)
            if world_is_valid(w, w.player_id) {
                save_player(w, w.player_id)
            }
            break
        }
    }

    clay_raylib_render(&cmds)
}
