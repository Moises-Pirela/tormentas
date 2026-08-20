package main

import rl     "vendor:raylib"
import        "core:fmt"
import        "core:mem"
import p2p    "p2p"

MenuPhase :: enum { CharSelect, ClassSelect, PlayOptions }
MenuFocus :: enum { None, NewName }

g_mm: struct {
    phase:           MenuPhase,
    selected_slot:   int,
    creating_slot:   int,
    confirm_delete:  bool,
    new_name:        [PLAYER_NAME_MAX + 1]u8,
    focus:           MenuFocus,
    conn_timer:      f32,
    new_char:        int,
    cs_hovered:      int,
    cs_anim_t:       f32,
    cs_pending_slot: int,
}

CONN_TIMEOUT :: f32(15.0)

@(private)
_mm_init :: proc() {
    g_mm.phase           = .CharSelect
    g_mm.selected_slot   = -1
    g_mm.creating_slot   = -1
    g_mm.confirm_delete  = false
    g_mm.focus           = .None
    g_mm.cs_hovered      = -1
    g_mm.cs_anim_t       = 0
    g_mm.cs_pending_slot = -1
}

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
    _mm_init()
    fade_from_black()
}

@(private)
_on_black_join_invite :: proc() {
    if g_sim_alive { shutdown_game() }
    g_is_host = false
    init_game()
    g_hub_active = true
    g_app_state  = .Playing
    set_playing_state(.Hub)
    copy(g_session.local_name[:], g_player_name[:])
    p2p.session_join(&g_session, g_invite_host_id)
    g_invite_pending = false
    fade_from_black()
}

update_main_menu :: proc(dt: f32) {
    if g_disconnect_msg_timer > 0 { g_disconnect_msg_timer -= dt }

    if ui_any() {
        top, ok := ui_top()
        if ok {
            switch top {
            case .Settings:
                update_settings_overlay()
            case .Keybinds:
                update_keybinds_screen()
            case .Inventory, .Stats, .MutationTree, .Shop, .Stash, .AbilityVendor, .PauseMenu,
                 .LevelSelect, .Lore, .Phonograph, .Social, .QuestBoard:
            }
        }
        return
    }

    switch g_mm.phase {
    case .CharSelect:   _mm_update_char_select()
    case .ClassSelect:  _mm_update_class_select()
    case .PlayOptions:  _mm_update_play_options()
    }
}

draw_main_menu :: proc() {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    cx := sw * 0.5

    title    := t(.MENU_TITLE)
    title_fs := uis(52)
    tsz      := rl.MeasureTextEx(g_font, title, title_fs, 0.8)
    rl.DrawTextEx(g_font, title,
        {cx - tsz.x * 0.5, sh * 0.12},
        title_fs, 0.8, rl.Color{200, 178, 108, 255})

    sub    := t(.MENU_SUBTITLE)
    sub_fs := uis(16)
    ssz    := rl.MeasureTextEx(g_font, sub, sub_fs, 0.5)
    rl.DrawTextEx(g_font, sub,
        {cx - ssz.x * 0.5, sh * 0.12 + title_fs + uis(6)},
        sub_fs, 0.5, rl.Color{120, 108, 72, 160})

    if g_disconnect_msg_timer > 0 {
        frac := clamp(g_disconnect_msg_timer / DISCONNECT_MSG_DURATION, 0, 1)
        a    := u8(frac * 210)
        msg  := t(.MENU_DISCONNECTED)
        mfs  := uis(14)
        msz  := rl.MeasureTextEx(g_font_body, msg, mfs, 0.5)
        rl.DrawTextEx(g_font_body, msg,
            {cx - msz.x * 0.5, sh * 0.33},
            mfs, 0.5, rl.Color{220, 80, 60, a})
    }

    switch g_mm.phase {
    case .CharSelect:   _mm_draw_char_select()
    case .ClassSelect:  _mm_draw_class_select()
    case .PlayOptions:  _mm_draw_play_options()
    }

    btn_fs  := uis(13)
    btn_bh  := btn_fs + uis(14)

    set_lbl := t(.MENU_BTN_SETTINGS)
    set_sz  := rl.MeasureTextEx(g_font_body, set_lbl, btn_fs, 0.5)
    set_bw  := set_sz.x + uis(22)
    set_r   := rl.Rectangle{
        sw - set_bw - uis(12),
        sh - btn_bh - uis(12),
        set_bw, btn_bh,
    }
    set_hot := rl.CheckCollisionPointRec(rl.GetMousePosition(), set_r)
    rl.DrawRectangleRec(set_r, rl.Color{24, 20, 14, 240} if set_hot else rl.Color{14, 11, 8, 200})
    rl.DrawRectangleLinesEx(set_r, 1, COL_BRASS if set_hot else COL_RULE)
    rl.DrawTextEx(g_font_body, set_lbl,
        {set_r.x + (set_bw - set_sz.x) * 0.5, set_r.y + (btn_bh - btn_fs) * 0.5},
        btn_fs, 0.5, COL_BRASS if set_hot else COL_MUTED)
    if set_hot && rl.IsMouseButtonReleased(.LEFT) {
        ui_open(.Settings)
    }

    exit_lbl := t(.MENU_BTN_EXIT)
    exit_sz  := rl.MeasureTextEx(g_font_body, exit_lbl, btn_fs, 0.5)
    exit_bw  := exit_sz.x + uis(22)
    exit_r   := rl.Rectangle{
        uis(12),
        sh - btn_bh - uis(12),
        exit_bw, btn_bh,
    }
    exit_hot := rl.CheckCollisionPointRec(rl.GetMousePosition(), exit_r)
    rl.DrawRectangleRec(exit_r, rl.Color{24, 14, 14, 240} if exit_hot else rl.Color{14, 11, 8, 200})
    rl.DrawRectangleLinesEx(exit_r, 1, rl.Color{200, 80, 60, 220} if exit_hot else COL_RULE)
    rl.DrawTextEx(g_font_body, exit_lbl,
        {exit_r.x + (exit_bw - exit_sz.x) * 0.5, exit_r.y + (btn_bh - btn_fs) * 0.5},
        btn_fs, 0.5, rl.Color{220, 100, 80, 255} if exit_hot else COL_MUTED)
    if exit_hot && rl.IsMouseButtonReleased(.LEFT) {
        g_should_exit = true
    }
}

SLOT_CARD_W :: f32(160)
SLOT_CARD_H :: f32(110)
SLOT_CARD_GAP :: f32(14)

@(private = "file")
_mm_update_char_select :: proc() {
    sw  := f32(rl.GetScreenWidth())
    sh  := f32(rl.GetScreenHeight())

    card_w   := uis(SLOT_CARD_W)
    card_h   := uis(SLOT_CARD_H)
    card_gap := uis(SLOT_CARD_GAP)
    total_w  := card_w * MAX_CHAR_SLOTS + card_gap * (MAX_CHAR_SLOTS - 1)
    cards_x  := sw * 0.5 - total_w * 0.5
    cards_y  := sh * 0.42

    for i in 0..<MAX_CHAR_SLOTS {
        cx := cards_x + f32(i) * (card_w + card_gap)
        r  := rl.Rectangle{cx, cards_y, card_w, card_h}
        if _mm_btn_hit(r) {
            if g_mm.creating_slot >= 0 && g_mm.creating_slot != i {
                g_mm.creating_slot = -1
                mem.zero_slice(g_mm.new_name[:])
                g_mm.focus = .None
            }
            g_mm.confirm_delete = false
            s := &g_char_save.slots[i]
            if s.exists == 1 {
                g_mm.selected_slot = i
            } else {
                g_mm.selected_slot = i
                g_mm.creating_slot = i
                mem.zero_slice(g_mm.new_name[:])
                g_mm.focus = .NewName
            }
        }
    }

    if g_mm.focus == .NewName {
        _mm_text_input(g_mm.new_name[:PLAYER_NAME_MAX])
        if rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.KP_ENTER) {
            _mm_confirm_create()
        }
    }

    btn_y   := cards_y + card_h + uis(28)
    btn_w   := sw * 0.14
    btn_h   := uis(38)
    cx_base := sw * 0.5

    if g_mm.creating_slot >= 0 {
        create_r := rl.Rectangle{cx_base - btn_w - uis(6), btn_y, btn_w, btn_h}
        cancel_r := rl.Rectangle{cx_base + uis(6),          btn_y, btn_w, btn_h}
        if _mm_btn_hit(create_r) { _mm_confirm_create() }
        if _mm_btn_hit(cancel_r) {
            g_mm.creating_slot = -1
            g_mm.selected_slot = -1
            mem.zero_slice(g_mm.new_name[:])
            g_mm.focus = .None
        }
    } else if g_mm.selected_slot >= 0 && g_char_save.slots[g_mm.selected_slot].exists == 1 {
        play_r   := rl.Rectangle{cx_base - btn_w - uis(6), btn_y, btn_w, btn_h}
        delete_r := rl.Rectangle{cx_base + uis(6),          btn_y, btn_w, btn_h}
        if _mm_btn_hit(play_r) {
            _mm_select_slot(g_mm.selected_slot)
            g_mm.phase = .PlayOptions
        }
        if _mm_btn_hit(delete_r) {
            if g_mm.confirm_delete {
                char_slot_delete(g_mm.selected_slot)
                g_mm.selected_slot  = -1
                g_mm.confirm_delete = false
            } else {
                g_mm.confirm_delete = true
            }
        } else if rl.IsMouseButtonPressed(.LEFT) {
            g_mm.confirm_delete = false
        }
    }
}

@(private = "file")
_mm_confirm_create :: proc() {
    if g_mm.new_name[0] == 0 { return }
    idx := g_mm.creating_slot

    char_slot_create(idx, g_mm.new_name[:], save_to_disk = false)
    g_mm.cs_pending_slot = idx
    g_mm.creating_slot   = -1
    g_mm.focus           = .None
    g_mm.new_char        = 0
    g_mm.cs_hovered      = 0
    g_mm.cs_anim_t       = 0
    g_mm.phase           = .ClassSelect
}

_mm_select_slot :: proc(idx: int) {
    g_active_slot = idx
    mem.zero_slice(g_player_name[:])
    copy(g_player_name[:], g_char_save.slots[idx].name[:])
}

@(private = "file")
_mm_draw_char_select :: proc() {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    card_w   := uis(SLOT_CARD_W)
    card_h   := uis(SLOT_CARD_H)
    card_gap := uis(SLOT_CARD_GAP)
    total_w  := card_w * MAX_CHAR_SLOTS + card_gap * (MAX_CHAR_SLOTS - 1)
    cards_x  := sw * 0.5 - total_w * 0.5
    cards_y  := sh * 0.42

    lbl    := t(.MENU_SELECT_CHARACTER)
    lfs    := uis(13)
    lsz    := rl.MeasureTextEx(g_font_body, lbl, lfs, 0.5)
    rl.DrawTextEx(g_font_body, lbl,
        {sw * 0.5 - lsz.x * 0.5, cards_y - lfs - uis(14)},
        lfs, 0.5, rl.Color{130, 118, 82, 200})

    for i in 0..<MAX_CHAR_SLOTS {
        cx := cards_x + f32(i) * (card_w + card_gap)
        r  := rl.Rectangle{cx, cards_y, card_w, card_h}
        _mm_draw_slot_card(r, i)
    }

    btn_y   := cards_y + card_h + uis(28)
    btn_w   := sw * 0.14
    btn_h   := uis(38)
    cx_base := sw * 0.5

    if g_mm.creating_slot >= 0 {
        name_w := sw * 0.24
        name_r := rl.Rectangle{sw * 0.5 - name_w * 0.5, btn_y - uis(52), name_w, uis(32)}
        n_lbl  := t(.MENU_NAME_CHARACTER)
        n_lfs  := uis(12)
        n_lsz  := rl.MeasureTextEx(g_font_body, n_lbl, n_lfs, 0.5)
        rl.DrawTextEx(g_font_body, n_lbl,
            {sw * 0.5 - n_lsz.x * 0.5, name_r.y - n_lfs - uis(5)},
            n_lfs, 0.5, rl.Color{130, 118, 82, 200})
        _mm_field_draw(name_r, g_mm.new_name[:], g_mm.focus == .NewName, t(.MENU_CHAR_DEFAULT))

        create_r := rl.Rectangle{cx_base - btn_w - uis(6), btn_y, btn_w, btn_h}
        cancel_r := rl.Rectangle{cx_base + uis(6),          btn_y, btn_w, btn_h}
        _mm_btn_draw(create_r, t(.MENU_BTN_CREATE), false)
        _mm_btn_draw(cancel_r, t(.MENU_BTN_CANCEL), false)
    } else if g_mm.selected_slot >= 0 && g_char_save.slots[g_mm.selected_slot].exists == 1 {
        play_r   := rl.Rectangle{cx_base - btn_w - uis(6), btn_y, btn_w, btn_h}
        delete_r := rl.Rectangle{cx_base + uis(6),          btn_y, btn_w, btn_h}
        _mm_btn_draw(play_r, t(.MENU_BTN_PLAY), false)

        if g_mm.confirm_delete {
            _mm_btn_draw(delete_r, t(.MENU_BTN_CONFIRM), true)
        } else {
            _mm_btn_draw(delete_r, t(.MENU_BTN_DELETE), false)
        }
    }
}

@(private = "file")
_mm_draw_slot_card :: proc(r: rl.Rectangle, idx: int) {
    s       := &g_char_save.slots[idx]
    sel     := g_mm.selected_slot == idx
    creating := g_mm.creating_slot == idx
    mp      := rl.GetMousePosition()
    over    := rl.CheckCollisionPointRec(mp, r)
    hot     := over || sel

    bg     := rl.Color{52, 46, 34, 255} if hot else rl.Color{18, 16, 12, 255}
    border := COL_BRASS                  if sel  else (rl.Color{100, 88, 58, 200} if over else COL_RULE)
    rl.DrawRectangleRec(r, bg)
    rl.DrawRectangleLinesEx(r, 1, border)

    if creating {
        lbl := t(.MENU_SLOT_NEW)
        fs  := uis(13)
        sz  := rl.MeasureTextEx(g_font_body, lbl, fs, 0.5)
        rl.DrawTextEx(g_font_body, lbl,
            {r.x + (r.width - sz.x) * 0.5, r.y + (r.height - sz.y) * 0.5},
            fs, 0.5, COL_BRASS)
        return
    }

    if s.exists == 0 {
        lbl := t(.MENU_SLOT_EMPTY)
        fs  := uis(13)
        sz  := rl.MeasureTextEx(g_font_body, lbl, fs, 0.5)
        rl.DrawTextEx(g_font_body, lbl,
            {r.x + (r.width - sz.x) * 0.5, r.y + (r.height - sz.y) * 0.5},
            fs, 0.5, rl.Color{80, 72, 52, 180} if !over else rl.Color{140, 126, 82, 220})
        return
    }

    name_cs := cstring(&s.name[0])
    nfs     := uis(14)
    nsz     := rl.MeasureTextEx(g_font_body, name_cs, nfs, 0.5)
    rl.DrawTextEx(g_font_body, name_cs,
        {r.x + (r.width - nsz.x) * 0.5, r.y + uis(18)},
        nfs, 0.5, rl.Color{218, 206, 160, 255})

    num_buf: [32]u8
    lv_s   := fmt.bprintf(num_buf[:], "Lv. %d", s.level)
    num_buf[len(lv_s)] = 0
    lv_fs  := uis(12)
    lv_sz  := rl.MeasureTextEx(g_font_body, cstring(&num_buf[0]), lv_fs, 0.5)
    rl.DrawTextEx(g_font_body, cstring(&num_buf[0]),
        {r.x + (r.width - lv_sz.x) * 0.5, r.y + uis(42)},
        lv_fs, 0.5, rl.Color{160, 148, 100, 220})

    raid_s := fmt.bprintf(num_buf[:], "%d raids", s.raids_done)
    num_buf[len(raid_s)] = 0
    rd_fs  := uis(11)
    rd_sz  := rl.MeasureTextEx(g_font_body, cstring(&num_buf[0]), rd_fs, 0.5)
    rl.DrawTextEx(g_font_body, cstring(&num_buf[0]),
        {r.x + (r.width - rd_sz.x) * 0.5, r.y + uis(62)},
        rd_fs, 0.5, rl.Color{120, 110, 76, 180})

    if s.deaths > 0 {
        death_s := fmt.bprintf(num_buf[:], "%d deaths", s.deaths)
        num_buf[len(death_s)] = 0
        dt_fs := uis(11)
        dt_sz := rl.MeasureTextEx(g_font_body, cstring(&num_buf[0]), dt_fs, 0.5)
        rl.DrawTextEx(g_font_body, cstring(&num_buf[0]),
            {r.x + (r.width - dt_sz.x) * 0.5, r.y + uis(80)},
            dt_fs, 0.5, rl.Color{160, 80, 70, 160})
    }
}

@(private = "file")
_mm_update_play_options :: proc() {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    cx    := sw * 0.5
    btn_w := sw * 0.20
    btn_h := uis(44)
    btn_y := sh * 0.54

    play_r := rl.Rectangle{cx - btn_w * 0.5, btn_y, btn_w, btn_h}
    if _mm_btn_hit(play_r) {
        fade_to_black(_on_black_singleplayer)
    }

    back_w := sw * 0.12
    back_r := rl.Rectangle{cx - back_w * 0.5, sh * 0.88, back_w, uis(32)}
    if _mm_btn_hit(back_r) {
        g_mm.phase    = .CharSelect
        g_mm.focus    = .None
        g_active_slot = -1
    }
}

@(private = "file")
_mm_draw_play_options :: proc() {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    cx := sw * 0.5

    if g_active_slot >= 0 && g_active_slot < MAX_CHAR_SLOTS {
        s      := &g_char_save.slots[g_active_slot]
        name_s := cstring(&s.name[0]) if s.name[0] != 0 else t(.MENU_CHAR_DEFAULT)
        num_buf: [64]u8
        sub_s  := fmt.bprintf(num_buf[:], "Playing as: %s  |  Lv. %d", name_s, s.level)
        num_buf[len(sub_s)] = 0
        sfs    := uis(13)
        ssz    := rl.MeasureTextEx(g_font_body, cstring(&num_buf[0]), sfs, 0.5)
        rl.DrawTextEx(g_font_body, cstring(&num_buf[0]),
            {cx - ssz.x * 0.5, sh * 0.40},
            sfs, 0.5, rl.Color{160, 148, 100, 200})
    }

    btn_w  := sw * 0.20
    btn_h  := uis(44)
    btn_y  := sh * 0.54
    play_r := rl.Rectangle{cx - btn_w * 0.5, btn_y, btn_w, btn_h}
    _mm_btn_draw(play_r, t(.MENU_BTN_PLAY), false)

    hint    := cstring("Invite friends from the Social panel once in the hub  [O]")
    hint_fs := uis(11)
    hsz     := rl.MeasureTextEx(g_font_body, hint, hint_fs, 0.5)
    rl.DrawTextEx(g_font_body, hint,
        {cx - hsz.x * 0.5, btn_y + btn_h + uis(14)},
        hint_fs, 0.5, rl.Color{100, 92, 66, 180})

    back_w := sw * 0.12
    back_r := rl.Rectangle{cx - back_w * 0.5, sh * 0.88, back_w, uis(32)}
    _mm_btn_draw(back_r, t(.MENU_BTN_BACK), false)
}

update_connecting :: proc(dt: f32) {
    g_mm.conn_timer += dt

    p2p.session_poll(&g_session, dt)

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

draw_connecting :: proc() {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    cx := sw * 0.5

    msg_cs: cstring = t(.MENU_WAITING)

    mfs := uis(22)
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

    cancel := t(.MENU_ESC_CANCEL)
    cfs    := uis(13)
    csz    := rl.MeasureTextEx(g_font_body, cancel, cfs, 0.5)
    rl.DrawTextEx(g_font_body, cancel,
        {cx - csz.x * 0.5, sh * 0.58},
        cfs, 0.5, rl.Color{110, 100, 72, 180})
}

_mm_btn_hit :: proc(r: rl.Rectangle) -> bool {
    return rl.IsMouseButtonReleased(.LEFT) &&
           rl.CheckCollisionPointRec(rl.GetMousePosition(), r)
}

_mm_btn_draw :: proc(r: rl.Rectangle, label: cstring, active: bool) {
    mp   := rl.GetMousePosition()
    over := rl.CheckCollisionPointRec(mp, r)
    hot  := over || active

    bg     := rl.Color{52, 46, 34, 255} if hot else rl.Color{24, 21, 16, 255}
    border := rl.Color{165, 142, 72, 255} if hot else rl.Color{62, 56, 42, 200}
    rl.DrawRectangleRec(r, bg)
    rl.DrawRectangleLinesEx(r, 1, border)

    fs  := uis(14)
    tsz := rl.MeasureTextEx(g_font_body, label, fs, 0.5)
    col := rl.Color{235, 215, 145, 255} if hot else rl.Color{165, 152, 102, 215}
    rl.DrawTextEx(g_font_body, label,
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
    fs    := uis(14)
    tx    := r.x + uis(10)
    ty    := r.y + (r.height - fs) * 0.5

    if empty && !focused {
        rl.DrawTextEx(g_font_body, placeholder, {tx, ty}, fs, 0.5,
            rl.Color{85, 78, 58, 145})
    } else {
        rl.DrawTextEx(g_font_body, cstr, {tx, ty}, fs, 0.5,
            rl.Color{218, 206, 160, 255})
        if focused && (int(rl.GetTime() * 2) % 2 == 0) {
            tw := rl.MeasureTextEx(g_font_body, cstr, fs, 0.5).x
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
