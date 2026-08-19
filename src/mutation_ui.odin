package main

import rl   "vendor:raylib"
import      "core:fmt"
import      "core:math"
import clay "../clay"


MUT_PANEL_W  :: f32(680)
MUT_PANEL_H  :: f32(560)
MUT_CARD_GAP :: f32(8)


@(private="file") MUT_BG       :: rl.Color{  10,  8, 16, 252 }
@(private="file") MUT_BORDER   :: rl.Color{ 140, 60,200, 220 }
@(private="file") MUT_HEADER   :: rl.Color{ 210,160,255, 255 }
@(private="file") MUT_MUTED    :: rl.Color{ 128,110,150, 195 }
@(private="file") MUT_OWNED    :: rl.Color{  80,200,100, 220 }
@(private="file") MUT_CONFLICT :: rl.Color{ 220, 60, 60, 220 }
@(private="file") MUT_CANGET   :: rl.Color{ 180, 80,255, 220 }
@(private="file") MUT_LOCKED   :: rl.Color{  70, 50, 90, 160 }


@(private="file") g_mut_tab: MutationBranch = .Corpus


@(private="file")
mutation_branch_name :: proc(branch: MutationBranch) -> cstring {
    switch branch {
    case .Corpus: return t(.MUT_BRANCH_CORPUS)
    case .Shadow: return t(.MUT_BRANCH_SHADOW)
    case .Venom:  return t(.MUT_BRANCH_VENOM)
    }
    return ""
}

@(private="file")
find_nearby_mutation_workbench :: proc(w: ^World) -> (id: int, pos: [3]f32, ok: bool) {
    if !world_is_valid(w, w.player_id) { return }
    if !world_has_component(w, w.player_id, .Transform) { return }

    player_pos := comp_get(w, w.player_id, .Transform, TransformComp).position
    npc_ids := world_query(w, query_mask(.NPC, .Transform))
    defer delete(npc_ids)

    best_dist_sq := f32(1e30)
    for nid in npc_ids {
        npc := comp_get(w, nid, .NPC, NPCComp)
        if npc.npc_type != .MutationWorkbench { continue }
        nt := comp_get(w, nid, .Transform, TransformComp)
        dx := nt.position[0] - player_pos[0]
        dy := nt.position[1] - player_pos[1]
        dist_sq := dx*dx + dy*dy
        if dist_sq > npc.interact_radius * npc.interact_radius { continue }
        if dist_sq < best_dist_sq {
            best_dist_sq = dist_sq
            id  = nid
            pos = nt.position
            ok  = true
        }
    }
    return
}

update_mutation_workbench :: proc(w: ^World) {
    if g_playing_state != .Gameplay && g_playing_state != .Hub { return }
    if _, _, ok := find_nearby_mutation_workbench(w); ok && input_pressed(rl.KeyboardKey(g_binds.gameplay.interact)) {
        g_mut_tab = .Corpus
        ui_open(.MutationTree)
    }
}

draw_mutation_workbench_world :: proc(w: ^World) {
    if ui_has(.MutationTree) { return }
    _, pos, ok := find_nearby_mutation_workbench(w)
    if !ok { return }

    prompt := t(.MUT_INTERACT)
    fs := f32(10)
    sz := rl.MeasureTextEx(g_font_body, prompt, fs, 0.5)
    pulse := u8(185 + i32((0.5 + 0.5 * math.sin(rl.GetTime() * 4.0)) * 45))
    p := world_to_iso_xy(pos[0], pos[1])
    rl.DrawTextEx(g_font_body, prompt,
        { p.x - sz.x * 0.5, p.y - 48 },
        fs, 0.5, rl.Color{ 220, 170, 255, pulse })
}


update_mutation_tree :: proc(w: ^World) {
    if !world_is_valid(w, w.player_id) { return }
    if !world_has_component(w, w.player_id, .MutationContainer) { return }

    // Tab/card/reset clicks and wheel scrolling are handled in draw_mutation_tree
    // (Clay immediate-mode + wired scroll); only ESC-to-close stays here.
    if input_pressed(.ESCAPE) {
        ui_close_top()
        return
    }
}


draw_mutation_tree :: proc(w: ^World) {
    if !world_is_valid(w, w.player_id) { return }
    if !world_has_component(w, w.player_id, .MutationContainer) { return }

    ui_scrim(165)
    mc := comp_get(w, w.player_id, .MutationContainer, MutationContainerComp)

    pw      := uis(MUT_PANEL_W)
    ph      := uis(MUT_PANEL_H)
    inner_w := pw - uis(28)                  // panel padding (~14 each side)
    tab_w   := (inner_w - uis(8)) / 3        // 3 tabs, 2 gaps of uis(4)
    purple_active := rl.Color{ 50, 20, 80, 245 }

    clay.BeginLayout()
    ui_panel_begin("MutPanel", string(t(.MUT_TITLE)), pw, ph, {
        anchor     = .CenterCenter,
        title_fs   = uis(14),
        bg_col     = MUT_BG,
        border_col = MUT_BORDER,
        accent_col = MUT_BORDER,
        title_col  = MUT_HEADER,
    })
    {
        // Serum balance (right-aligned)
        ui_hstack_begin("MutSerumRow", 0, 0, .Center)
        ui_grow("MutSerumL")
        ui_label("MutSerums", string(tf(.MUT_SERUMS, mc.serums)), uis(9), MUT_OWNED)
        ui_hstack_end()

        // Branch tabs
        ui_hstack_begin("MutTabs", u16(uis(4)), 0, .Center)
        for branch in MutationBranch {
            if ui_tab(fmt.tprintf("MutTab%d", int(branch)),
                string(mutation_branch_name(branch)), tab_w, uis(26),
                branch == g_mut_tab, MUT_BORDER, purple_active) {
                g_mut_tab = branch
            }
        }
        ui_hstack_end()

        // Scrollable card list (grows to fill remaining height; footer sits below it)
        ui_scroll_begin("MutScroll")
        ui_vstack_begin("MutList", u16(uis(MUT_CARD_GAP)))
        for mt in MutationType {
            if mt == .None { continue }
            def := &MUTATION_DEFS[mt]
            if def.branch != g_mut_tab { continue }

            cardid  := fmt.tprintf("MutCard%d", int(mt))
            hovered := clay.PointerOver(clay.ID(cardid))

            owned    := player_has_mutation(w, w.player_id, mt)
            can      := mutation_can_unlock(w, w.player_id, mt)
            conflict := !owned && mutation_conflicts(w, w.player_id, mt)

            bg     := rl.Color{ 16, 14, 28, 240 }
            border := MUT_LOCKED
            name_c := MUT_HEADER
            status := string(tf(.MUT_COST, def.serum_cost))
            stat_c := rl.Color{ 180, 60, 60, 200 }
            if owned {
                bg = rl.Color{ 20, 40, 24, 240 }; border = MUT_OWNED; name_c = MUT_OWNED
                status = string(t(.MUT_ACQUIRED)); stat_c = MUT_OWNED
            } else if conflict {
                bg = rl.Color{ 40, 14, 14, 240 }; border = MUT_CONFLICT; name_c = MUT_CONFLICT
                status = string(t(.MUT_CONFLICT)); stat_c = MUT_CONFLICT
            } else if can {
                bg = rl.Color{ 28, 14, 50, 240 }
                border = rl.Color{ 220, 120, 255, 255 } if hovered else MUT_CANGET
                stat_c = rl.Color{ 100, 210, 120, 210 }
            }

            ui_card_begin(cardid, bg, border, u16(uis(3)))
            ui_label(fmt.tprintf("MutName%d", int(mt)), fmt.tprintf("%s", def.name), uis(10), name_c)
            ui_label(fmt.tprintf("MutEff%d", int(mt)),  fmt.tprintf("%s", def.effect), uis(8), MUT_MUTED)
            ui_hstack_begin(fmt.tprintf("MutStatRow%d", int(mt)), 0, 0, .Center)
            ui_label(fmt.tprintf("MutStat%d", int(mt)), status, uis(8), stat_c)
            if can && !owned && !conflict {
                ui_grow(fmt.tprintf("MutStatSpc%d", int(mt)))
                ui_label(fmt.tprintf("MutCraft%d", int(mt)), string(t(.MUT_CRAFT_HINT)), uis(8), MUT_CANGET)
            }
            ui_hstack_end()
            ui_card_end()

            if hovered && rl.IsMouseButtonReleased(.LEFT) {
                if mutation_unlock(w, w.player_id, mt) { play_sfx("stat_up") }
            }
        }
        ui_vstack_end()
        ui_scroll_end()

        // Footer: hint (left) + reset (right)
        ui_hstack_begin("MutFooter", u16(uis(8)), 0, .Center)
        ui_label("MutHint", string(t(.MUT_FOOTER)), uis(8), rl.Color{ 90, 70, 110, 180 })
        ui_grow("MutFooterSpc")
        can_clear := mc.entity_count > 0 && mc.serums >= MUT_CLEAR_COST
        if ui_button("MutReset", string(tf(.MUT_RESET, MUT_CLEAR_COST)), uis(130), uis(22), .Danger) && can_clear {
            if mutation_clear_all(w, w.player_id) { play_sfx("stat_up") }
        }
        ui_hstack_end()
    }
    ui_panel_end()
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)
}
