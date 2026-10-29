package main

import rl   "vendor:raylib"
import      "core:fmt"
import      "core:math"
import clay "../clay"
import p2p  "p2p"

HUB_BG_PATH :: "data/sprites/Town/Town.png"

HUB_PORTAL_POS     :: [2]f32{ -480, 0 }
HUB_PORTAL_RADIUS  :: f32(80)

HUB_SHOPKEEPER_POS         :: [3]f32{  320,    0, 0 }
HUB_MUTATION_WORKBENCH_POS :: [3]f32{  480,  -64, 0 }
HUB_STASH_POS              :: [3]f32{  168, -152, 0 }
HUB_ABILITY_VENDOR_POS     :: [3]f32{  320, -192, 0 }
HUB_QUEST_BOARD_POS        :: [3]f32{  168,    0, 0 }
HUB_QUARTERMASTER_POS      :: [3]f32{  480,    0, 0 }
HUB_SURGEON_POS            :: [3]f32{  480, -128, 0 }

g_hub_bg_tex:    rl.Texture2D
g_hub_bg_loaded: bool

hub_load_bg :: proc() {
    if g_hub_bg_loaded { return }
    tex := rl.LoadTexture(HUB_BG_PATH)
    if tex.id > 0 {
        rl.SetTextureFilter(tex, .BILINEAR)
        rl.SetTextureWrap(tex, .CLAMP)
        g_hub_bg_tex    = tex
        g_hub_bg_loaded = true
    }
}

hub_unload_bg :: proc() {
    if g_hub_bg_loaded {
        rl.UnloadTexture(g_hub_bg_tex)
        g_hub_bg_tex    = {}
        g_hub_bg_loaded = false
    }
}

draw_hub_background :: proc() {
    hub_load_bg()
    if !g_hub_bg_loaded { return }

    half_w := f32(DEFAULT_LEVEL_COLS / 2) * f32(TILE_SIZE)
    half_h := f32(DEFAULT_LEVEL_ROWS / 2) * f32(TILE_SIZE)
    span   := half_w + half_h

    sw := f32(g_hub_bg_tex.width)
    sh := f32(g_hub_bg_tex.height)

    scale  := span * 2 / sw
    dest_h := sh * scale

    src  := rl.Rectangle{ 0, 0, sw, sh }
    dest := rl.Rectangle{ -span, span * 0.5 - dest_h, span * 2, dest_h }
    rl.DrawTexturePro(g_hub_bg_tex, src, dest, {0, 0}, 0, rl.WHITE)
}

enter_hub :: proc(w: ^World, save_progress: bool = false) {
    if save_progress && world_is_valid(w, w.player_id) {
        save_player(w, w.player_id)
    }
    g_hub_remote_loaded  = {}
    g_raid_timer         = 0
    g_available_levels   = level_scan_available()
    level_clear(w)
    level_load(0)
    level_apply(w)
    door_init_blockers(w)
    hub_apply(w)
    spawn_players(w)
    if !load_player(w, w.player_id) {
        give_class_starter_items(w, w.player_id, class_idx_for_slot(g_active_slot))
    }
    hub_apply_quest_npcs(w)

    if world_has_component(w, w.player_id, .Health) {
        h := comp_get(w, w.player_id, .Health, HealthComp)
        h.current = h.max
    }
    g_hub_active       = true
    g_was_player_alive = true
    set_playing_state(.Hub)
}

enter_raid :: proc(w: ^World, n: int) {
    if world_is_valid(w, w.player_id) {
        save_player(w, w.player_id)
    }
    director_init()
    g_current_raid_level = n
    raid_result_gold     = 0
    raid_result_serums   = 0
    g_raid_timer         = RAID_TIME
    g_raid_enemies_killed = 0
    g_raid_elites_killed  = 0
    g_raid_bosses_killed  = 0
    level_clear(w)
    level_load(n)
    level_apply(w)
    door_init_blockers(w)

    level_spawn_extraction_zones(w)

    spawn_players(w)
    if !load_player(w, w.player_id) {
        give_class_starter_items(w, w.player_id, class_idx_for_slot(g_active_slot))
    }
    if p2p.session_is_online(&g_session) {
        for slot in 0..<MAX_PLAYERS {
            if slot == g_session.local_slot { continue }
            entry := &g_session.roster[slot]
            if !entry.known || !entry.char_ready { continue }
            if world_is_valid(w, w.player_ids[slot]) {
                load_player_from_bytes(w, w.player_ids[slot], entry.char_data[:entry.char_len])
            }
        }
    }

    if world_has_component(w, w.player_id, .Health) {
        h := comp_get(w, w.player_id, .Health, HealthComp)
        h.current = h.max
    }

    g_raid_serums_start = 0
    if world_has_component(w, w.player_id, .MutationContainer) {
        g_raid_serums_start = comp_get(w, w.player_id, .MutationContainer, MutationContainerComp).serums
    }
    g_hub_active       = false
    g_was_player_alive = true
    set_playing_state(.Gameplay)

    ui_close_all()
}

hub_spawn_remote_player :: proc(w: ^World, remote_slot: int) {
    if world_is_valid(w, w.player_ids[remote_slot]) { return }

    ps: [2]f32
    start_ids := world_query(w, query_mask(.PlayerStart, .Transform))
    if len(start_ids) > 0 {
        p := comp_get(w, start_ids[0], .Transform, TransformComp).position
        ps = { p[0], p[1] }
    }
    delete(start_ids)

    sp: [3]f32
    if ps[0] != 0 || ps[1] != 0 {
        sp = { ps[0] + f32(remote_slot) * 60, ps[1], 0 }
    } else {
        sp = { f32(remote_slot) * 60, 0, 0 }
    }

    wep := spawn_from_def(w, find_entity_def(g_entity_defs, "weapon_pistol"))
    pid := spawn_from_def(w, find_entity_def(g_entity_defs, "player"))

    if world_has_component(w, pid, .Transform) {
        comp_get(w, pid, .Transform, TransformComp).position = sp
    }
    comp_set(w, pid, .Equipment, EquipmentComp{ weapon_entity_id = wep })
    comp_set(w, pid, .Inventory, inventory_make_empty())
    comp_set(w, pid, .Respawn, RespawnComp{ spawn_pos = sp, delay = RESPAWN_DELAY })
    comp_set(w, pid, .Ability, AbilityComp{})
    comp_set(w, pid, .MutationContainer, mutation_container_empty())
    comp_set(w, pid, .Stats, StatsComp{
        strength    = 1, dexterity  = 1, science    = 1,
        level       = 1, xp         = 0, xp_next    = 100.0,
        stat_points = 0, base_hp    = 100.0,
        base_energy = 100.0, base_speed = 240.0,
    })
    comp_set(w, pid, .Player, PlayerComp{ slot = remote_slot })
    comp_set(w, pid, .Wallet, WalletComp{ gold = 0 })
    comp_set(w, pid, .StatusEffect, StatusEffectComp{})
    comp_set(w, pid, .KeyRing, KeyRingComp{})
    w.player_ids[remote_slot] = pid

    entry := &g_session.roster[remote_slot]
    if entry.char_ready {
        load_player_from_bytes(w, pid, entry.char_data[:entry.char_len])
    }
    copy(g_player_names[remote_slot][:], entry.name[:])
}

update_hub_portal :: proc(w: ^World) {
    if !world_is_valid(w, w.player_id) { return }
    if !world_has_component(w, w.player_id, .Transform) { return }

    pos  := comp_get(w, w.player_id, .Transform, TransformComp).position
    dx   := pos[0] - HUB_PORTAL_POS[0]
    dy   := pos[1] - HUB_PORTAL_POS[1]
    near := dx*dx + dy*dy < (HUB_PORTAL_RADIUS * 2) * (HUB_PORTAL_RADIUS * 2)

    online := p2p.session_is_online(&g_session)
    if near && (!online || g_session.local_slot == 0) &&
       input_pressed(rl.KeyboardKey(g_binds.gameplay.interact)) {
        ui_open(.LevelSelect)
    }
}

draw_hub_world :: proc(w: ^World) {
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

    if world_is_valid(w, w.player_id) &&
       world_has_component(w, w.player_id, .Transform) {
        pos := comp_get(w, w.player_id, .Transform, TransformComp).position
        dx  := pos[0] - px
        dy  := pos[1] - py
        if dx*dx + dy*dy < (HUB_PORTAL_RADIUS * 2) * (HUB_PORTAL_RADIUS * 2) {
            online := p2p.session_is_online(&g_session)
            lbl: cstring
            if online && g_session.local_slot != 0 {
                lbl = "Waiting for host..."
            } else {
                lbl = t(.HUB_INTERACT)
            }
            lbl_fs := f32(12)
            lsz    := rl.MeasureTextEx(g_font_body, lbl, lbl_fs, 0.5)
            rl.DrawTextEx(g_font_body, lbl,
                {iso.x - lsz.x * 0.5, iso.y - HUB_PORTAL_RADIUS - lbl_fs - 4},
                lbl_fs, 0.5, rl.Color{160, 200, 255, 230})
        }
    }
}

draw_hub_hud :: proc(w: ^World) {
    sw := f32(rl.GetScreenWidth())

    loc    := t(.HUB_LABEL)
    loc_fs := uis(11)
    lsz    := rl.MeasureTextEx(g_font_body, loc, loc_fs, 0.5)
    rl.DrawTextEx(g_font_body, loc,
        {sw * 0.5 - lsz.x * 0.5, uis(10)},
        loc_fs, 0.5, COL_MUTED)

    rl.DrawTextEx(g_font_body, tf(.HUB_STASH, local_stash().gold, local_stash().serums),
        {uis(14), uis(14)}, uis(11), 0.5, COL_BRASS)
}

draw_level_select :: proc(w: ^World) {
    ui_scrim(160)

    n_levels := max(g_available_levels, 1)
    pw := uis(360)
    ph := uis(80) + f32(n_levels) * uis(62) + uis(48)

    btn_w := pw - uis(32)
    btn_h := uis(46)

    clay.BeginLayout()
    ui_panel_begin("LevelSelectPanel", string(t(.HUB_LEVEL_SELECT)), pw, ph,
        { anchor = .CenterCenter })
    {
        if g_available_levels == 0 {
            ui_label("LSNoLevels", string(t(.HUB_NO_LEVELS)), uis(11), COL_MUTED)
        }

        ui_vstack_begin("LSList", u16(uis(10)))
        for i in 1 ..= g_available_levels {
            if ui_button(fmt.tprintf("LSLvl%d", i), string(tf(.HUB_LEVEL_N, i)),
                btn_w, btn_h, .Primary) {
                g_pending_raid_start = i
                p2p.session_send_level_load(&g_session, i)
                ui_close(.LevelSelect)
                break
            }
        }
        ui_vstack_end()

        ui_grow("LSSpacer")
        ui_hstack_begin("LSCancelRow", 0, 0, .Center)
        ui_grow("LSCancelL")
        ui_label("LSCancel", string(t(.HUB_ESC_CANCEL)), uis(10), COL_MUTED)
        ui_grow("LSCancelR")
        ui_hstack_end()
    }
    ui_panel_end()
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)
}

draw_extract_screen :: proc(w: ^World) {
    ui_scrim(185)

    pw := uis(360)
    ph := uis(310)

    green_title  := rl.Color{100, 230, 100, 255}
    green_accent := rl.Color{ 60, 200,  80, 200}
    green_border := rl.Color{ 48, 140,  55, 200}

    clay.BeginLayout()
    ui_panel_begin("ExtractPanel", string(t(.EXTRACT_TITLE)), pw, ph, {
        anchor     = .CenterCenter,
        bg_col     = rl.Color{10, 14, 10, 252},
        border_col = green_border,
        accent_col = green_accent,
        title_col  = green_title,
        title_fs   = uis(20),
    })
    {
        ui_hstack_begin("ExSubRow", 0, 0, .Center)
        ui_grow("ExSubL")
        ui_label("ExSub", string(t(.EXTRACT_SUBTITLE)), uis(16), rl.Color{80, 200, 80, 200})
        ui_grow("ExSubR")
        ui_hstack_end()

        _hub_reward_row("ExGold",   string(t(.EXTRACT_GOLD)),
            fmt.tprintf("+ %d", raid_result_gold), COL_BRASS)
        _hub_reward_row("ExSerums", string(t(.EXTRACT_SERUMS)),
            fmt.tprintf("+ %d", raid_result_serums), COL_BRASS)

        ui_divider("ExSep")

        _hub_reward_row("ExStash", string(t(.EXTRACT_STASH_TOTAL)),
            fmt.tprintf("%d gold   %d serums", local_stash().gold, local_stash().serums),
            COL_PARCH)

        ui_grow("ExSpacer")
        ui_hstack_begin("ExBtnRow", 0, 0, .Center)
        ui_grow("ExBtnL")
        if ui_button("ExReturn", string(t(.HUB_BTN_RETURN)), uis(200), uis(44), .Primary) {
            enter_hub(w, true)
        }
        ui_grow("ExBtnR")
        ui_hstack_end()
    }
    ui_panel_end()
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)
}

draw_death_screen :: proc(w: ^World) {
    ui_scrim(185)

    pw := uis(370)
    ph := uis(300)

    red_title  := rl.Color{200,  55,  55, 255}
    red_accent := rl.Color{200,  40,  40, 200}
    red_border := rl.Color{140,  28,  28, 200}

    clay.BeginLayout()
    ui_panel_begin("DeathPanel", string(t(.DEATH_TITLE)), pw, ph, {
        anchor     = .CenterCenter,
        bg_col     = rl.Color{14, 6, 6, 252},
        border_col = red_border,
        accent_col = red_accent,
        title_col  = red_title,
        title_fs   = uis(26),
    })
    {
        ui_hstack_begin("DeSubRow", 0, 0, .Center)
        ui_grow("DeSubL")
        ui_label("DeSub", string(t(.DEATH_MSG)), uis(12), COL_MUTED)
        ui_grow("DeSubR")
        ui_hstack_end()

        ui_divider("DeSep")

        _hub_reward_row("DeStash", string(t(.DEATH_STASH)),
            fmt.tprintf("%d gold", local_stash().gold), COL_PARCH)

        ui_grow("DeSpacer")
        ui_hstack_begin("DeBtnRow", u16(uis(14)), 0, .Center)
        ui_grow("DeBtnL")
        if ui_button("DeRetry", string(t(.HUB_BTN_RETRY)), uis(155), uis(44), .Primary) {
            enter_raid(w, g_current_raid_level)
        }
        if ui_button("DeReturn", string(t(.HUB_BTN_RETURN)), uis(155), uis(44), .Default) {
            enter_hub(w)
        }
        ui_grow("DeBtnR")
        ui_hstack_end()
    }
    ui_panel_end()
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)
}

@(private = "file")
_hub_reward_row :: proc(base_id, label, value: string, value_col: rl.Color) {
    ui_hstack_begin(fmt.tprintf("%sRow", base_id), 0, 0, .Center)
    ui_label(fmt.tprintf("%sLbl", base_id), label, uis(15), COL_MUTED)
    ui_grow(fmt.tprintf("%sSpc", base_id))
    ui_label(fmt.tprintf("%sVal", base_id), value, uis(15), value_col)
    ui_hstack_end()
}
