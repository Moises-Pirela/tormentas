package main

import rl   "vendor:raylib"
import      "core:fmt"
import      "core:math"
import cw   "clockwork"

// ── panel geometry constants (base px, scaled by uis) ─────────────────────
MUT_PANEL_W  :: f32(680)
MUT_PANEL_H  :: f32(560)
MUT_CARD_H   :: f32(105)
MUT_CARD_GAP :: f32(8)

// ── palette ────────────────────────────────────────────────────────────────
@(private="file") MUT_BG       :: rl.Color{  10,  8, 16, 252 }
@(private="file") MUT_BORDER   :: rl.Color{ 140, 60,200, 220 }
@(private="file") MUT_HEADER   :: rl.Color{ 210,160,255, 255 }
@(private="file") MUT_MUTED    :: rl.Color{ 128,110,150, 195 }
@(private="file") MUT_OWNED    :: rl.Color{  80,200,100, 220 }
@(private="file") MUT_CONFLICT :: rl.Color{ 220, 60, 60, 220 }
@(private="file") MUT_CANGET   :: rl.Color{ 180, 80,255, 220 }
@(private="file") MUT_LOCKED   :: rl.Color{  70, 50, 90, 160 }

// ── per-screen state ───────────────────────────────────────────────────────
@(private="file") g_mut_tab:    MutationBranch = .Corpus
@(private="file") g_mut_scroll: f32

// ── helpers ────────────────────────────────────────────────────────────────
@(private="file")
mut_panel_rect :: proc() -> (px, py, pw, ph: f32) {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    pw  = uis(MUT_PANEL_W)
    ph  = uis(MUT_PANEL_H)
    px  = sw*0.5 - pw*0.5
    py  = sh*0.5 - ph*0.5
    return
}

@(private="file")
mutation_branch_name :: proc(branch: MutationBranch) -> string {
    switch branch {
    case .Corpus: return "CORPUS"
    case .Shadow: return "SHADOW"
    case .Venom:  return "VENOM"
    }
    return ""
}

@(private="file")
mutation_close_state :: proc() -> PlayingSubstate {
    return .Hub if g_hub_active else .Gameplay
}

@(private="file")
mut_count_in_branch :: proc(branch: MutationBranch) -> int {
    n := 0
    for mt in cw.MutationType {
        if mt == .None { continue }
        if MUTATION_DEFS[mt].branch == branch { n += 1 }
    }
    return n
}

// content_geometry returns the scrollable-area rectangle and the max scroll.
@(private="file")
mut_content_geo :: proc(px, py, pw, ph: f32) -> (cx, cy, cw_, ch, max_scroll: f32) {
    pad      := uis(12)
    header_h := uis(32)
    tab_h    := uis(28)
    footer_h := uis(24)
    scroll_w := uis(6)
    card_h   := uis(MUT_CARD_H)
    card_gap := uis(MUT_CARD_GAP)

    cx  = px + pad
    cy  = py + pad + header_h + uis(6) + tab_h + uis(8)
    cw_ = pw - pad*2 - scroll_w - uis(4)
    ch  = ph - (cy - py) - footer_h - pad

    n := mut_count_in_branch(g_mut_tab)
    total_h := f32(n)*(card_h + card_gap) - (card_gap if n > 0 else 0)
    max_scroll = max(total_h - ch, 0)
    return
}

// ── workbench interaction ──────────────────────────────────────────────────

@(private="file")
find_nearby_mutation_workbench :: proc(w: ^cw.World) -> (id: int, pos: [3]f32, ok: bool) {
    if !cw.world_is_valid(w, w.player_id) { return }
    if !cw.world_has_component(w, w.player_id, .Transform) { return }

    player_pos := cw.world_get_transform(w, w.player_id).position
    npc_ids := cw.world_query(w, cw.query_mask(.NPC, .Transform))
    defer delete(npc_ids)

    best_dist_sq := f32(1e30)
    for nid in npc_ids {
        npc := cw.world_get_npc(w, nid)
        if npc.npc_type != .MutationWorkbench { continue }
        nt := cw.world_get_transform(w, nid)
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

update_mutation_workbench :: proc(w: ^cw.World) {
    if g_playing_state != .Gameplay && g_playing_state != .Hub { return }
    if _, _, ok := find_nearby_mutation_workbench(w); ok && rl.IsKeyPressed(INTERACT_KEY) {
        g_mut_tab    = .Corpus
        g_mut_scroll = 0
        set_playing_state(.MutationTree)
    }
}

draw_mutation_workbench_world :: proc(w: ^cw.World) {
    if g_playing_state == .MutationTree { return }
    _, pos, ok := find_nearby_mutation_workbench(w)
    if !ok { return }

    prompt := cstring("[E] Craft Mutation")
    fs := f32(10)
    sz := rl.MeasureTextEx(g_font, prompt, fs, 0.5)
    pulse := u8(185 + i32((0.5 + 0.5 * math.sin(rl.GetTime() * 4.0)) * 45))
    rl.DrawTextEx(g_font, prompt,
        { pos[0] - sz.x * 0.5, pos[1] - 48 },
        fs, 0.5, rl.Color{ 220, 170, 255, pulse })
}

// ── update ─────────────────────────────────────────────────────────────────

update_mutation_tree :: proc(w: ^cw.World) {
    if !cw.world_is_valid(w, w.player_id) { return }
    if !cw.world_has_component(w, w.player_id, .MutationContainer) { return }

    if rl.IsKeyPressed(.ESCAPE) {
        set_playing_state(mutation_close_state())
        return
    }

    px, py, pw, ph := mut_panel_rect()
    pad     := uis(12)
    tab_h   := uis(28)
    tab_top := py + pad + uis(32) + uis(6)   // matches draw layout

    cx, cy, cw_, ch, max_scroll := mut_content_geo(px, py, pw, ph)

    mp := rl.GetMousePosition()

    // ── Tab click ──────────────────────────────────────────────────────────
    tab_count := len(MutationBranch)
    tab_w     := (pw - pad*2) / f32(tab_count)
    for branch in MutationBranch {
        tx  := px + pad + f32(int(branch))*tab_w
        rec := rl.Rectangle{ tx, tab_top, tab_w - uis(4), tab_h }
        if rl.IsMouseButtonPressed(.LEFT) && rl.CheckCollisionPointRec(mp, rec) {
            if g_mut_tab != branch {
                g_mut_tab    = branch
                g_mut_scroll = 0
                // recompute max_scroll for new tab
                _, _, _, _, max_scroll = mut_content_geo(px, py, pw, ph)
            }
        }
    }

    // ── Scroll wheel ───────────────────────────────────────────────────────
    if rl.CheckCollisionPointRec(mp, rl.Rectangle{px, py, pw, ph}) {
        wh := rl.GetMouseWheelMove()
        if wh != 0 {
            g_mut_scroll = clamp(g_mut_scroll - wh*uis(40), 0, max_scroll)
        }
    }

    // ── Card click ─────────────────────────────────────────────────────────
    if rl.IsMouseButtonPressed(.LEFT) {
        clip_rec := rl.Rectangle{ cx, cy, cw_, ch }
        card_h   := uis(MUT_CARD_H)
        card_gap := uis(MUT_CARD_GAP)
        row := 0
        for mt in cw.MutationType {
            if mt == .None { continue }
            if MUTATION_DEFS[mt].branch != g_mut_tab { continue }
            card_y   := cy + f32(row)*(card_h + card_gap) - g_mut_scroll
            card_rec := rl.Rectangle{ cx, card_y, cw_, card_h }
            if rl.CheckCollisionPointRec(mp, card_rec) &&
               rl.CheckCollisionPointRec(mp, clip_rec) {
                if mutation_unlock(w, w.player_id, mt) {
                    play_sfx("stat_up")
                }
                break
            }
            row += 1
        }
    }
}

// ── draw ───────────────────────────────────────────────────────────────────

draw_mutation_tree :: proc(w: ^cw.World) {
    if !cw.world_is_valid(w, w.player_id) { return }
    if !cw.world_has_component(w, w.player_id, .MutationContainer) { return }

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 165})

    px, py, pw, ph := mut_panel_rect()
    pad      := uis(12)
    header_h := uis(32)
    tab_h    := uis(28)
    footer_h := uis(24)
    card_h   := uis(MUT_CARD_H)
    card_gap := uis(MUT_CARD_GAP)
    scroll_w := uis(6)

    // ── Panel background ───────────────────────────────────────────────────
    rl.DrawRectangleRounded({px, py, pw, ph}, 0.04, 8, MUT_BG)
    rl.DrawRectangleLinesEx({px, py, pw, ph}, uis(1.5), MUT_BORDER)

    mc := cw.world_get_mutation(w, w.player_id)

    // ── Header ─────────────────────────────────────────────────────────────
    header_fs := uis(14)
    body_fs   := uis(9)

    rl.DrawTextEx(g_font, "MUTATION WORKBENCH",
        {px + uis(14), py + uis(10)}, header_fs, 0.6, MUT_HEADER)

    serum_str := fmt.ctprintf("SERUMS: %d", mc.serums)
    serum_sz  := rl.MeasureTextEx(g_font, serum_str, body_fs, 0.5)
    rl.DrawTextEx(g_font, serum_str,
        {px + pw - serum_sz.x - uis(14), py + uis(12)},
        body_fs, 0.5, MUT_OWNED)

    // divider under header
    div_y := py + pad + header_h - uis(4)
    rl.DrawRectangle(i32(px + pad), i32(div_y), i32(pw - pad*2), i32(uis(1)),
        rl.Color{100, 50, 160, 120})

    // ── Tabs ───────────────────────────────────────────────────────────────
    tab_count := len(MutationBranch)
    tab_w     := (pw - pad*2) / f32(tab_count)
    tab_top   := py + pad + header_h + uis(6)

    for branch in MutationBranch {
        tx  := px + pad + f32(int(branch))*tab_w
        rec := rl.Rectangle{ tx, tab_top, tab_w - uis(4), tab_h }

        active := branch == g_mut_tab
        bg_col := rl.Color{50, 20, 80, 245} if active else rl.Color{22, 14, 36, 210}
        bd_col := MUT_BORDER                if active else MUT_LOCKED
        tx_col := MUT_HEADER                if active else MUT_MUTED

        rl.DrawRectangleRounded(rec, 0.28, 6, bg_col)
        rl.DrawRectangleLinesEx(rec, uis(1), bd_col)

        label  := fmt.ctprintf("%s", mutation_branch_name(branch))
        lsz    := rl.MeasureTextEx(g_font, label, body_fs, 0.5)
        rl.DrawTextEx(g_font, label,
            {rec.x + rec.width*0.5 - lsz.x*0.5, rec.y + rec.height*0.5 - lsz.y*0.5},
            body_fs, 0.5, tx_col)
    }

    // ── Scrollable card area ───────────────────────────────────────────────
    cx, cy, cw_, ch, max_scroll := mut_content_geo(px, py, pw, ph)

    // recompute total height for scrollbar
    n       := mut_count_in_branch(g_mut_tab)
    total_h := f32(n)*(card_h + card_gap) - (card_gap if n > 0 else 0)

    rl.BeginScissorMode(i32(cx), i32(cy), i32(cw_), i32(ch))

    row    := 0
    small_fs := uis(8)
    name_fs  := uis(10)
    mp := rl.GetMousePosition()

    for mt in cw.MutationType {
        if mt == .None { continue }
        def := &MUTATION_DEFS[mt]
        if def.branch != g_mut_tab { continue }

        card_y := cy + f32(row)*(card_h + card_gap) - g_mut_scroll
        if card_y + card_h < cy || card_y > cy + ch { row += 1; continue }

        owned    := player_has_mutation(w, w.player_id, mt)
        can      := mutation_can_unlock(w, w.player_id, mt)
        conflict := !owned && mutation_conflicts(w, w.player_id, mt)
        clip_rec := rl.Rectangle{cx, cy, cw_, ch}
        hovered  := rl.CheckCollisionPointRec(mp, rl.Rectangle{cx, card_y, cw_, card_h}) &&
                    rl.CheckCollisionPointRec(mp, clip_rec)

        bg     := rl.Color{ 16, 14, 28, 240 }
        border := MUT_LOCKED
        name_c := MUT_HEADER
        status := fmt.ctprintf("%d serums", def.serum_cost)
        stat_c := rl.Color{180, 60, 60, 200}

        if owned {
            bg = rl.Color{20, 40, 24, 240}; border = MUT_OWNED; name_c = MUT_OWNED
            status = "ACQUIRED"; stat_c = MUT_OWNED
        } else if conflict {
            bg = rl.Color{40, 14, 14, 240}; border = MUT_CONFLICT; name_c = MUT_CONFLICT
            status = "CONFLICT"; stat_c = MUT_CONFLICT
        } else if can {
            bg = rl.Color{28, 14, 50, 240}
            border = rl.Color{220, 120, 255, 255} if hovered else MUT_CANGET
            stat_c = rl.Color{100, 210, 120, 210}
        }

        card_rec := rl.Rectangle{cx, card_y, cw_, card_h}
        rl.DrawRectangleRounded(card_rec, 0.06, 8, bg)
        rl.DrawRectangleLinesEx(card_rec, uis(1.5), border)

        ipad := uis(10)
        ty   := card_y + ipad

        rl.DrawTextEx(g_font, fmt.ctprintf("%s", def.name),
            {cx + ipad, ty}, name_fs, 0.5, name_c)
        ty += name_fs + uis(3)

        rl.DrawTextEx(g_font, fmt.ctprintf("%s", def.effect),
            {cx + ipad, ty}, small_fs, 0.4, MUT_MUTED)
        ty += small_fs + uis(3)

        rl.DrawTextEx(g_font, status, {cx + ipad, ty}, small_fs, 0.4, stat_c)

        if can && !owned && !conflict {
            craft := cstring("CLICK TO CRAFT")
            csz   := rl.MeasureTextEx(g_font, craft, small_fs, 0.4)
            rl.DrawTextEx(g_font, craft,
                {cx + cw_ - csz.x - ipad, ty}, small_fs, 0.4, MUT_CANGET)
        }

        row += 1
    }

    rl.EndScissorMode()

    // ── Scrollbar ──────────────────────────────────────────────────────────
    if max_scroll > 0 {
        track_x := px + pw - scroll_w - uis(4)
        track_h := ch
        thumb_h := max(ch * (ch / total_h), uis(20))
        thumb_y := cy + (ch - thumb_h) * (g_mut_scroll / max_scroll)
        rl.DrawRectangleRounded(
            {track_x, cy, scroll_w, track_h}, 0.5, 4,
            rl.Color{30, 20, 44, 160})
        rl.DrawRectangleRounded(
            {track_x, thumb_y, scroll_w, thumb_h}, 0.5, 4,
            rl.Color{160, 80, 240, 200})
    }

    // ── Footer ─────────────────────────────────────────────────────────────
    footer_fs := uis(8)
    hint      := cstring("[ESC] Close   |   Scroll to browse")
    hint_sz   := rl.MeasureTextEx(g_font, hint, footer_fs, 0.4)
    footer_y  := py + ph - footer_h
    rl.DrawTextEx(g_font, hint,
        {px + pw*0.5 - hint_sz.x*0.5, footer_y + uis(5)},
        footer_fs, 0.4, rl.Color{90, 70, 110, 180})
}
