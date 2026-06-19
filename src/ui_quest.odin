package main

import cw   "clockwork"
import rl   "vendor:raylib"
import fmt  "core:fmt"
import clay "../clay"

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
    sh := f32(rl.GetScreenHeight())

    clay.BeginLayout()
    ui_panel_begin("QuestBoardPanel", string(t(.QUEST_BOARD_TITLE)), uis(520), sh * 0.86, {
        anchor   = .CenterCenter,
        title_fs = uis(17),
    })
    {
        ui_vstack_begin("QBList", u16(uis(5)))
        for qi in QuestID {
            idx  := int(qi)
            def  := &QUEST_DEFS[idx]
            done := quest_is_done(qi)
            cur, tgt := quest_progress(qi, w)

            card_bg  := rl.Color{15, 22, 15, 255} if done else rl.Color{22, 17, 12, 255}
            card_bdr := rl.Color{70, 150, 70, 140} if done else COL_RULE
            ui_card_begin(fmt.tprintf("QBCard%d", idx), card_bg, card_bdr, u16(uis(5)))
            {
                // Title row + COMPLETED badge
                ui_hstack_begin(fmt.tprintf("QBTitleRow%d", idx), 0, 0, .Center)
                ui_label(fmt.tprintf("QBTitle%d", idx), string(t(def.title_key)), uis(12),
                    rl.Color{120, 200, 120, 255} if done else COL_PARCH)
                if done {
                    ui_grow(fmt.tprintf("QBTitleSpc%d", idx))
                    ui_label(fmt.tprintf("QBDone%d", idx), "COMPLETED", uis(9),
                        rl.Color{80, 200, 80, 220})
                }
                ui_hstack_end()

                ui_label(fmt.tprintf("QBObj%d", idx), string(t(def.obj_key)), uis(10), COL_MUTED)

                // Progress bar + count
                ui_hstack_begin(fmt.tprintf("QBProg%d", idx), u16(uis(6)), 0, .Center)
                ratio := f32(min(cur, tgt)) / f32(tgt) if tgt > 0 else 0
                ui_hbar(fmt.tprintf("QBBar%d", idx), ratio,
                    rl.Color{80, 200, 80, 210} if done else rl.Color{180, 140, 60, 210},
                    rl.Color{35, 28, 20, 255}, uis(5))
                ui_label(fmt.tprintf("QBCount%d", idx),
                    fmt.tprintf("%d / %d", min(cur, tgt), tgt), uis(9), COL_MUTED)
                ui_hstack_end()

                ui_label(fmt.tprintf("QBRew%d", idx), string(_quest_reward_cstr(def)), uis(9),
                    rl.Color{200, 170, 80, 200})
            }
            ui_card_end()
        }
        ui_vstack_end()

        ui_grow("QBSpacer")
        ui_hstack_begin("QBCloseRow", 0, 0, .Center)
        ui_grow("QBCloseL")
        ui_label("QBClose", "[ESC] Close", uis(9), COL_MUTED)
        ui_grow("QBCloseR")
        ui_hstack_end()
    }
    ui_panel_end()
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)
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
