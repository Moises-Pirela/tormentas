package main

import rl   "vendor:raylib"
import      "core:math"
import cw   "clockwork"

// ── Panel state ───────────────────────────────────────────────────────────────

g_phonograph_panel_id:        u8  = 0
g_phonograph_panel_entity_id: int = cw.INVALID_ENTITY

ui_open_phonograph :: proc(recording_id: u8, entity_id: int = cw.INVALID_ENTITY) {
    g_phonograph_panel_id        = recording_id
    g_phonograph_panel_entity_id = entity_id
    ui_open(.Phonograph)
}

// ── Draw ──────────────────────────────────────────────────────────────────────

draw_phonograph_panel :: proc() {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    if rl.IsKeyPressed(.ESCAPE) {
        ui_close(.Phonograph)
        return
    }

    // Resolve live play state from ECS entity
    is_playing := false
    play_timer := f32(0)
    w := &g_sim.world
    if cw.world_is_valid(w, g_phonograph_panel_entity_id) &&
       cw.world_has_component(w, g_phonograph_panel_entity_id, .Phonograph) {
        ph := cw.world_get_phonograph(w, g_phonograph_panel_entity_id)
        is_playing = ph.is_playing
        play_timer = ph.play_timer
    }

    rec, rec_ok := lore_get_recording(g_phonograph_panel_id)

    // Close automatically when playback ends
    if rec_ok && !is_playing && g_phonograph_panel_entity_id != cw.INVALID_ENTITY {
        ui_close(.Phonograph)
        return
    }

    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{0, 0, 0, 180})

    PW  := uis(540)
    PH  := uis(380)
    px  := (sw - PW) * 0.5
    py  := (sh - PH) * 0.5

    // ── Panel background — mahogany cabinet ───────────────────────────────────
    rl.DrawRectangleRec({px + uis(5), py + uis(5), PW, PH}, rl.Color{0, 0, 0, 90})
    rl.DrawRectangleRec({px, py, PW, PH}, rl.Color{38, 18, 8, 252})
    for i in 0..<8 {
        gy := py + f32(i) * (PH / 8.0)
        rl.DrawRectangleRec({px, gy, PW, PH / 8.0 * 0.35}, rl.Color{55, 26, 10, 30})
    }
    rl.DrawRectangleRec({px, py, PW, uis(5)},             rl.Color{160, 128, 42, 220})
    rl.DrawRectangleRec({px, py + PH - uis(5), PW, uis(5)}, rl.Color{120,  96, 28, 200})
    rl.DrawRectangleLinesEx({px, py, PW, PH}, uis(2), rl.Color{140, 110, 42, 230})

    // ── Machine illustration (left half) ─────────────────────────────────────
    mach_cx := px + PW * 0.28
    mach_cy := py + PH * 0.48
    t_anim   := f32(rl.GetTime())

    // Cabinet body
    rl.DrawRectangleRec({mach_cx - uis(45), mach_cy + uis(14), uis(90), uis(40)},
        rl.Color{50, 24, 10, 255})
    rl.DrawRectangleLinesEx({mach_cx - uis(45), mach_cy + uis(14), uis(90), uis(40)},
        uis(1.5), rl.Color{100, 78, 30, 200})

    // Wax cylinder (rotating when playing)
    cyl_angle := t_anim * 180 if is_playing else f32(0)
    cyl_rx    := uis(28)
    cyl_ry    := uis(10)
    rl.DrawEllipse(i32(mach_cx), i32(mach_cy + uis(2)), cyl_rx, cyl_ry,
        rl.Color{20, 8, 4, 120})
    rl.DrawEllipse(i32(mach_cx), i32(mach_cy), cyl_rx, cyl_ry,
        rl.Color{210, 180, 100, 240})
    // Rotating grooves
    for ring in 0..<5 {
        ang := (cyl_angle + f32(ring) * 36) * math.PI / 180
        sy  := math.sin(ang) * cyl_ry * 0.7
        rl.DrawLineEx({mach_cx - cyl_rx, mach_cy + sy},
                      {mach_cx + cyl_rx, mach_cy + sy},
                      uis(0.8), rl.Color{150, 120, 60, 80})
    }
    rl.DrawEllipseLines(i32(mach_cx), i32(mach_cy), cyl_rx, cyl_ry,
        rl.Color{160, 130, 50, 200})

    // Tone arm + needle
    rl.DrawLineEx(
        {mach_cx - uis(12), mach_cy - uis(4)},
        {mach_cx + uis(18), mach_cy + uis(8)},
        uis(2), rl.Color{180, 148, 54, 220})
    rl.DrawCircleV({mach_cx + uis(18), mach_cy + uis(8)}, uis(3),
        rl.Color{200, 170, 60, 240})

    // Horn / bell
    horn_tip := rl.Vector2{mach_cx + uis(72), mach_cy - uis(44)}
    horn_base_t := rl.Vector2{mach_cx + uis(16), mach_cy - uis(2)}
    horn_base_b := rl.Vector2{horn_base_t.x, horn_base_t.y + uis(6)}
    rl.DrawTriangle(horn_tip, horn_base_t, horn_base_b, rl.Color{170, 136, 44, 220})
    rl.DrawTriangle(horn_tip, horn_base_b, {horn_tip.x + uis(2), horn_tip.y + uis(2)},
        rl.Color{140, 110, 32, 180})
    rl.DrawEllipseLines(i32(horn_tip.x), i32(horn_tip.y), uis(12), uis(18),
        rl.Color{200, 165, 55, 200})

    // Sound waves when playing
    if is_playing {
        pulse := u8(math.sin(t_anim * 5) * 40 + 80)
        for wi in 1..=3 {
            r := uis(f32(wi) * 9)
            rl.DrawCircleLinesV(horn_tip, r, rl.Color{200, 165, 55, pulse / u8(wi)})
        }
    }

    // ── Text area (right half) ────────────────────────────────────────────────
    tx_x := px + PW * 0.52
    tx_w := PW * 0.44

    if !rec_ok {
        msg := cstring("[ Recording not found ]")
        msz := rl.MeasureTextEx(g_font, msg, uis(11), 1)
        rl.DrawTextEx(g_font, msg,
            {tx_x + tx_w*0.5 - msz.x*0.5, py + PH*0.5 - msz.y*0.5},
            uis(11), 1, COL_MUTED)
    } else {
        // Title
        title    := loc_lookup(cstring(&rec.title[0]))
        title_fs := uis(13)
        ty       := py + uis(30)
        rl.DrawTextEx(g_font, title, {tx_x, ty}, title_fs, 0.5, COL_BRASS)
        ty += title_fs + uis(4)

        rl.DrawLineEx({tx_x, ty}, {tx_x + tx_w, ty}, uis(1),
            rl.Color{130, 100, 38, 100})
        ty += uis(8)

        // Status
        status  := cstring("▶  PLAYING")      if is_playing else cstring("◼  STOPPED")
        st_col  := rl.Color{80, 200, 80, 220}  if is_playing else rl.Color{180, 120, 40, 180}
        rl.DrawTextEx(g_font, status, {tx_x, ty}, uis(9), 0.5, st_col)
        ty += uis(16)

        // Progress bar
        if rec.duration > 0 {
            progress := f32(0)
            if is_playing && play_timer > 0 {
                progress = 1.0 - (play_timer / rec.duration)
            } else if !is_playing {
                progress = 1.0
            }
            bar_h := uis(6)
            rl.DrawRectangleRec({tx_x, ty, tx_w, bar_h}, rl.Color{50, 38, 16, 180})
            rl.DrawRectangleRec({tx_x, ty, tx_w * progress, bar_h}, rl.Color{168, 132, 44, 230})
            rl.DrawRectangleLinesEx({tx_x, ty, tx_w, bar_h}, uis(0.8),
                rl.Color{110, 84, 28, 150})
            ty += bar_h + uis(12)
        }

        // Transcript
        trans_str := string(loc_lookup(cstring(&rec.transcript[0])))
        if len(trans_str) > 0 {
            rl.DrawTextEx(g_font, "— Transcript —", {tx_x, ty}, uis(9), 0.5,
                rl.Color{110, 90, 50, 140})
            ty += uis(13)
            lore_draw_wrapped(trans_str, tx_x, ty, tx_w,
                uis(10), uis(15), rl.Color{195, 175, 130, 210})
        }
    }

    // Footer
    hint := cstring("[ ESC to close ]")
    hsz  := rl.MeasureTextEx(g_font, hint, uis(9), 0.5)
    rl.DrawTextEx(g_font, hint,
        {px + PW*0.5 - hsz.x*0.5, py + PH - uis(18)},
        uis(9), 0.5, rl.Color{100, 80, 40, 140})

    mp := rl.GetMousePosition()
    if rl.IsMouseButtonPressed(.LEFT) &&
       !rl.CheckCollisionPointRec(mp, {px, py, PW, PH}) {
        ui_close(.Phonograph)
    }
}
