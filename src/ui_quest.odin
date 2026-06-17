package main

import cw  "clockwork"
import rl  "vendor:raylib"
import fmt "core:fmt"

g_quest_board_npc_id: int = cw.INVALID_ENTITY

update_quest_board :: proc(w: ^cw.World) {
    if g_playing_state != .Hub { return }
    if ui_has(.QuestBoard)     { return }

    if !cw.world_is_valid(w, w.player_id)                  { return }
    if !cw.world_has_component(w, w.player_id, .Transform) { return }

    player_pos := cw.world_get_transform(w, w.player_id).position
    npc_ids    := cw.world_query(w, cw.query_mask(.NPC, .Transform))
    defer delete(npc_ids)

    for nid in npc_ids {
        npc := cw.world_get_npc(w, nid)
        if npc.npc_type != .QuestBoard { continue }
        nt  := cw.world_get_transform(w, nid)
        dx  := nt.position[0] - player_pos[0]
        dy  := nt.position[1] - player_pos[1]
        if dx*dx + dy*dy <= npc.interact_radius * npc.interact_radius {
            if input_pressed(rl.KeyboardKey(g_binds.gameplay.interact)) {
                g_quest_board_npc_id = nid
                ui_open(.QuestBoard)
            }
            break
        }
    }
}

draw_quest_board_world :: proc(w: ^cw.World) {
    if ui_has(.QuestBoard)                                 { return }
    if !cw.world_is_valid(w, w.player_id)                 { return }
    if !cw.world_has_component(w, w.player_id, .Transform) { return }

    player_pos := cw.world_get_transform(w, w.player_id).position
    npc_ids    := cw.world_query(w, cw.query_mask(.NPC, .Transform))
    defer delete(npc_ids)

    for nid in npc_ids {
        npc := cw.world_get_npc(w, nid)
        if npc.npc_type != .QuestBoard { continue }

        nt      := cw.world_get_transform(w, nid)
        dx      := nt.position[0] - player_pos[0]
        dy      := nt.position[1] - player_pos[1]
        dist_sq := dx*dx + dy*dy
        pos     := world_to_iso_xy(nt.position[0], nt.position[1])

        nfs := f32(10)
        lbl := t(.QUEST_BOARD_NPC_NAME)
        nsz := rl.MeasureTextEx(g_font_body, lbl, nfs, 0.5)
        rl.DrawTextEx(g_font_body, lbl,
            {pos.x - nsz.x*0.5, pos.y - 14 - nfs - 2},
            nfs, 0.5, rl.Color{240, 215, 120, 220})

        if dist_sq <= npc.interact_radius * npc.interact_radius {
            prompt := t(.QUEST_BOARD_INTERACT)
            pfs    := f32(9)
            psz    := rl.MeasureTextEx(g_font_body, prompt, pfs, 0.5)
            t_now  := f32(rl.GetTime())
            pulse  := u8(180 + 60 * (t_now - f32(int(t_now))))
            rl.DrawTextEx(g_font_body, prompt,
                {pos.x - psz.x*0.5, pos.y + 18},
                pfs, 0.5, rl.Color{255, 230, 100, pulse})
        }
        break
    }
}

draw_quest_board_panel :: proc(w: ^cw.World) {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    pw := uis(520)
    ph := sh * 0.86
    px := (sw - pw) * 0.5
    py := sh * 0.07

    rl.DrawRectangleRec({px, py, pw, ph}, rl.Color{10, 8, 6, 252})
    rl.DrawRectangleLinesEx({px, py, pw, ph}, 1.5, COL_RULE)
    rl.DrawRectangle(i32(px), i32(py), i32(pw), i32(uis(3)), COL_BRASS)

    title    := t(.QUEST_BOARD_TITLE)
    title_fs := uis(17)
    tsz      := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title,
        {px + pw*0.5 - tsz.x*0.5, py + uis(14)}, title_fs, 1, COL_PARCH)
    rl.DrawLineEx(
        {px + uis(16), py + uis(46)},
        {px + pw - uis(16), py + uis(46)}, 1, COL_RULE)

    list_y   := py + uis(54)
    card_h   := uis(78)
    card_gap := uis(5)

    for qi in QuestID {
        idx  := int(qi)
        def  := &QUEST_DEFS[idx]
        done := quest_is_done(qi)
        cur, tgt := quest_progress(qi, w)

        cy := list_y + f32(idx) * (card_h + card_gap)
        if cy + card_h > py + ph - uis(44) { break }

        card_r  := rl.Rectangle{px + uis(14), cy, pw - uis(28), card_h}
        card_bg := rl.Color{15, 22, 15, 255} if done else rl.Color{22, 17, 12, 255}
        rl.DrawRectangleRec(card_r, card_bg)
        rl.DrawRectangleLinesEx(card_r, 1,
            rl.Color{70, 150, 70, 140} if done else COL_RULE)

        tx := card_r.x + uis(12)

        title_col := rl.Color{120, 200, 120, 255} if done else COL_PARCH
        rl.DrawTextEx(g_font_body, t(def.title_key),
            {tx, cy + uis(7)}, uis(12), 0.5, title_col)

        if done {
            clbl := cstring("COMPLETED")
            clsz := rl.MeasureTextEx(g_font_body, clbl, uis(9), 0.5)
            rl.DrawTextEx(g_font_body, clbl,
                {card_r.x + card_r.width - uis(12) - clsz.x, cy + uis(8)},
                uis(9), 0.5, rl.Color{80, 200, 80, 220})
        }

        rl.DrawTextEx(g_font_body, t(def.obj_key),
            {tx, cy + uis(26)}, uis(10), 0.5, COL_MUTED)

        bar_x    := tx
        bar_y    := cy + uis(43)
        bar_w    := pw - uis(80)
        bar_h    := uis(5)
        fill     := f32(min(cur, tgt)) / f32(tgt) * bar_w
        fill_col := rl.Color{80, 200, 80, 210} if done else rl.Color{180, 140, 60, 210}
        rl.DrawRectangle(i32(bar_x), i32(bar_y), i32(bar_w), i32(bar_h), rl.Color{35, 28, 20, 255})
        if fill > 0 {
            rl.DrawRectangle(i32(bar_x), i32(bar_y), i32(fill), i32(bar_h), fill_col)
        }
        prog := fmt.ctprintf("%d / %d", min(cur, tgt), tgt)
        rl.DrawTextEx(g_font_body, prog,
            {bar_x + bar_w + uis(6), bar_y - uis(1)}, uis(9), 0.5, COL_MUTED)

        rew := _quest_reward_cstr(def)
        rl.DrawTextEx(g_font_body, rew,
            {tx, cy + uis(56)}, uis(9), 0.5, rl.Color{200, 170, 80, 200})
    }

    rl.DrawTextEx(g_font_body, cstring("[ESC] Close"),
        {px + pw*0.5 - uis(28), py + ph - uis(28)}, uis(9), 0.5, COL_MUTED)
}

@(private = "file")
_quest_reward_cstr :: proc(def: ^QuestDef) -> cstring {
    parts: [3]string
    n := 0
    if def.reward_stats  > 0 { parts[n] = fmt.tprintf("+%d stat pts", def.reward_stats);  n += 1 }
    if def.reward_gold   > 0 { parts[n] = fmt.tprintf("+%dg", def.reward_gold);            n += 1 }
    if def.reward_serums > 0 { parts[n] = fmt.tprintf("+%d serum", def.reward_serums);     n += 1 }
    switch n {
    case 1: return fmt.ctprintf("%s", parts[0])
    case 2: return fmt.ctprintf("%s  ·  %s", parts[0], parts[1])
    case 3: return fmt.ctprintf("%s  ·  %s  ·  %s", parts[0], parts[1], parts[2])
    }
    return cstring("")
}

draw_quest_flash :: proc() {
    if g_quest_flash_timer <= 0 || g_quest_flash_title == nil { return }
    g_quest_flash_timer = max(g_quest_flash_timer - rl.GetFrameTime(), 0)

    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()
    t0 := g_quest_flash_timer / QUEST_FLASH_TIME
    a  := u8(clamp(t0, 0, 1) * 220)

    hdr := cstring("QUEST COMPLETE")
    hfs := uis(14)
    hsz := rl.MeasureTextEx(g_font_body, hdr, hfs, 1)
    tfs := uis(22)
    ttl := g_quest_flash_title
    tsz := rl.MeasureTextEx(g_font, ttl, tfs, 1)
    cx  := f32(sw) * 0.5
    by  := f32(sh) * 0.30

    rl.DrawTextEx(g_font_body, hdr,
        {cx - hsz.x*0.5, by - uis(20)}, hfs, 1,
        rl.Color{140, 220, 100, u8(f32(a) * 0.72)})
    rl.DrawTextEx(g_font, ttl,
        {cx - tsz.x*0.5, by}, tfs, 1,
        rl.Color{220, 196, 58, a})
}

draw_quest_hud :: proc(w: ^cw.World) {
    if g_playing_state != .Gameplay { return }

    track := [?]QuestID{.TheHorde, .Aberration, .TheDeepRun, .ElitePredator, .PerfectRun}
    visible: [5]QuestID
    count := 0
    for qi in track {
        if !quest_is_done(qi) {
            visible[count] = qi
            count += 1
        }
    }
    if count == 0 { return }

    sw    := f32(rl.GetScreenWidth())
    row_h := uis(17)
    px    := sw - uis(205)
    py    := uis(90)

    for i in 0..<count {
        qi      := visible[i]
        cur, tgt := quest_progress(qi, w)
        cy      := py + f32(i) * row_h
        lbl     := fmt.ctprintf("%s  %d/%d", t(QUEST_DEFS[int(qi)].title_key), min(cur, tgt), tgt)
        rl.DrawTextEx(g_font_body, lbl, {px, cy}, uis(9), 0.5, rl.Color{200, 180, 100, 180})
    }
}
