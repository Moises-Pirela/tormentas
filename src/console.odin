package main

import rl       "vendor:raylib"
import          "core:fmt"
import          "core:strings"
import          "core:strconv"
import cw       "clockwork"

CONSOLE_MAX_LINES  :: 48
CONSOLE_LINE_CAP   :: 320
CONSOLE_SLIDE_SPD  :: f32(12.0)   // panel-heights per second
CONSOLE_SCROLL_AMT :: 3           // lines per wheel tick

g_console_open: bool   // true = input captured, game input blocked

@(private = "file")
ConsoleLine :: struct {
    buf: [CONSOLE_LINE_CAP]u8,
    len: int,
}

@(private = "file") g_console_lines:    [CONSOLE_MAX_LINES]ConsoleLine
@(private = "file") g_console_cursor:   int
@(private = "file") g_console_count:    int
@(private = "file") g_console_input:    [512]u8
@(private = "file") g_console_in_len:   int
@(private = "file") g_console_bs_timer: f32
@(private = "file") g_console_slide:    f32   // 0 = fully closed, 1 = fully open
@(private = "file") g_console_scroll:   int   // 0 = newest at bottom, +n = scroll back

console_log :: proc(msg: string) {
    idx := g_console_cursor % CONSOLE_MAX_LINES
    n   := min(len(msg), CONSOLE_LINE_CAP - 1)
    copy(g_console_lines[idx].buf[:], msg[:n])
    g_console_lines[idx].buf[n] = 0
    g_console_lines[idx].len    = n
    g_console_cursor += 1
    if g_console_count < CONSOLE_MAX_LINES { g_console_count += 1 }
}

@(private = "file")
console_logf :: proc(format: string, args: ..any) {
    buf: [CONSOLE_LINE_CAP]u8
    s := fmt.bprintf(buf[:CONSOLE_LINE_CAP - 1], format, ..args)
    console_log(s)
}

// ── console_geo: shared geometry so update + draw agree ───────────────────
@(private = "file")
ConsoleGeo :: struct {
    panel_h, y_off: f32,
    fs, line_h, pad: f32,
    input_y, log_bot_y: f32,
    visible: int,
}

@(private = "file")
console_geo :: proc() -> ConsoleGeo {
    sh      := f32(rl.GetScreenHeight())
    panel_h := sh * 0.46
    y_off   := panel_h * (g_console_slide - 1)   // 0 when open, -panel_h when closed
    fs      := uis(12)
    pad     := uis(8)
    line_h  := fs * 1.4
    input_y   := y_off + panel_h - line_h - pad
    log_bot_y := input_y - pad * 0.5
    visible   := int((panel_h - line_h - pad * 1.5) / line_h)
    if visible < 1 { visible = 1 }
    return { panel_h, y_off, fs, line_h, pad, input_y, log_bot_y, visible }
}

// ── update ─────────────────────────────────────────────────────────────────

update_console :: proc(dt: f32) {
    // Toggle on grave
    if rl.IsKeyPressed(.GRAVE) {
        g_console_open = !g_console_open
        if g_console_open {
            g_console_in_len   = 0
            g_console_bs_timer = 0
            g_console_scroll   = 0   // jump to newest on open
        }
    }

    // Animate slide toward target
    target := f32(1) if g_console_open else f32(0)
    if g_console_slide < target {
        g_console_slide = min(g_console_slide + dt * CONSOLE_SLIDE_SPD, f32(1))
    } else if g_console_slide > target {
        g_console_slide = max(g_console_slide - dt * CONSOLE_SLIDE_SPD, f32(0))
    }

    if !g_console_open { return }

    // Scroll wheel
    wh := rl.GetMouseWheelMove()
    if wh != 0 {
        g_console_scroll -= int(wh) * CONSOLE_SCROLL_AMT
        if g_console_scroll < 0 { g_console_scroll = 0 }
        // upper clamp applied in draw where visible count is known
    }

    // Character input
    for {
        ch := rl.GetCharPressed()
        if ch == 0 { break }
        if ch == '`' || ch == '~' { continue }
        if g_console_in_len < len(g_console_input) - 1 {
            g_console_input[g_console_in_len] = u8(ch)
            g_console_in_len += 1
        }
    }

    // Backspace
    if rl.IsKeyPressed(.BACKSPACE) {
        if g_console_in_len > 0 { g_console_in_len -= 1 }
        g_console_bs_timer = 0.4
    } else if rl.IsKeyDown(.BACKSPACE) {
        g_console_bs_timer -= dt
        if g_console_bs_timer <= 0 {
            if g_console_in_len > 0 { g_console_in_len -= 1 }
            g_console_bs_timer = 0.05
        }
    }

    // Enter: run command, jump back to newest
    if rl.IsKeyPressed(.ENTER) {
        raw := string(g_console_input[:g_console_in_len])
        console_logf("> %s", raw)
        w: ^cw.World = nil
        if g_sim_alive { w = &g_sim.world }
        _console_exec(w, raw)
        g_console_in_len = 0
        g_console_scroll = 0
    }
}

// ── draw ───────────────────────────────────────────────────────────────────

draw_console :: proc() {
    if g_console_slide <= 0 { return }

    sw  := f32(rl.GetScreenWidth())
    g   := console_geo()
    bar_w := uis(6)
    spacing := f32(0.4)

    // Clamp scroll now that we know visible
    max_scroll := max(g_console_count - g.visible, 0)
    if g_console_scroll > max_scroll { g_console_scroll = max_scroll }

    // ── Panel background + bottom edge ─────────────────────────────────────
    rl.DrawRectangle(0, i32(g.y_off), i32(sw), i32(g.panel_h),
        rl.Color{ 8, 8, 12, 225 })
    rl.DrawRectangle(0, i32(g.y_off + g.panel_h) - 1, i32(sw), 1,
        rl.Color{ 140, 90, 35, 255 })

    // ── Log lines (drawn bottom-to-top, newest at bottom) ──────────────────
    log_clip_y := i32(max(g.y_off, 0))
    log_clip_h := i32(g.log_bot_y) - log_clip_y
    if log_clip_h > 0 {
        rl.BeginScissorMode(0, log_clip_y, i32(sw - bar_w - g.pad), log_clip_h)

        draw_y := g.log_bot_y - g.line_h
        for i in 0..<min(g.visible, g_console_count) {
            raw_idx := g_console_cursor - 1 - i - g_console_scroll
            if raw_idx < g_console_cursor - g_console_count { break }
            idx  := ((raw_idx % CONSOLE_MAX_LINES) + CONSOLE_MAX_LINES) % CONSOLE_MAX_LINES
            line := &g_console_lines[idx]
            if line.len == 0 { draw_y -= g.line_h; continue }
            alpha := u8(clamp(230 - i * 5, 60, 230))
            rl.DrawTextEx(g_font, cstring(&line.buf[0]),
                { g.pad, draw_y }, g.fs, spacing,
                rl.Color{ 200, 194, 178, alpha })
            draw_y -= g.line_h
        }

        rl.EndScissorMode()
    }

    // ── Scrollbar ──────────────────────────────────────────────────────────
    if max_scroll > 0 {
        track_x := sw - bar_w - g.pad * 0.5
        track_y := g.y_off + g.pad
        track_h := g.log_bot_y - track_y

        thumb_frac := f32(g.visible) / f32(g_console_count)
        thumb_h    := max(track_h * thumb_frac, uis(20))
        // scroll=0 → thumb at bottom; scroll=max → thumb at top
        t := f32(g_console_scroll) / f32(max_scroll)
        thumb_y := track_y + (track_h - thumb_h) * (1.0 - t)

        // only draw if track is actually on screen
        if track_y + track_h > 0 {
            rl.DrawRectangleRounded(
                { track_x, track_y, bar_w, track_h }, 0.5, 4,
                rl.Color{ 30, 26, 20, 160 })
            rl.DrawRectangleRounded(
                { track_x, thumb_y, bar_w, thumb_h }, 0.5, 4,
                rl.Color{ 160, 100, 40, 220 })
        }
    }

    // ── Input line ─────────────────────────────────────────────────────────
    prompt     := cstring("> ")
    prompt_col := rl.Color{ 160, 120, 55, 255 }
    rl.DrawTextEx(g_font, prompt, { g.pad, g.input_y }, g.fs, spacing, prompt_col)
    prompt_w := rl.MeasureTextEx(g_font, prompt, g.fs, spacing).x

    input_x := g.pad + prompt_w
    if g_console_in_len > 0 {
        g_console_input[g_console_in_len] = 0
        rl.DrawTextEx(g_font, cstring(&g_console_input[0]),
            { input_x, g.input_y }, g.fs, spacing,
            rl.Color{ 240, 234, 216, 255 })
        input_x += rl.MeasureTextEx(g_font,
            cstring(&g_console_input[0]), g.fs, spacing).x
    }

    if int(rl.GetTime() * 2) % 2 == 0 {
        rl.DrawTextEx(g_font, "_",
            { input_x, g.input_y + g.fs * 0.15 },
            g.fs, spacing, rl.Color{ 200, 155, 70, 210 })
    }
}

// ── command execution ──────────────────────────────────────────────────────

@(private = "file")
_console_exec :: proc(w: ^cw.World, raw: string) {
    s := strings.trim_space(raw)
    if len(s) == 0 { return }

    sep  := strings.index_byte(s, ' ')
    cmd  := s if sep < 0 else s[:sep]
    args := "" if sep < 0 else strings.trim_space(s[sep + 1:])

    switch cmd {

    case "help":
        console_log("  mut <name>       apply mutation by json entity name")
        console_log("  serums <n>       set player serum count")
        console_log("  gold <n>         add gold to wallet")
        console_log("  hp <n>           set player current HP")
        console_log("  kill             kill player")
        console_log("  clear            clear console log")
        console_log("available mutations:")
        for mt in cw.MutationType {
            if mt == .None { continue }
            console_logf("    %s", _mut_def_name_from_type(mt))
        }

    case "clear":
        g_console_count  = 0
        g_console_cursor = 0
        g_console_scroll = 0

    case "mut":
        if w == nil { console_log("ERROR: no world active"); return }
        if !cw.world_is_valid(w, w.player_id) {
            console_log("ERROR: no active player")
            return
        }
        mt := _mut_type_from_def_name(args)
        if mt == .None {
            console_logf("ERROR: unknown mutation '%s'", args)
            return
        }
        if player_has_mutation(w, w.player_id, mt) {
            console_logf("player already has %s", args)
            return
        }
        mc := cw.world_get_mutation(w, w.player_id)
        if mc.entity_count >= cw.MAX_MUTATION_SLOTS {
            console_log("ERROR: mutation slots full")
            return
        }
        mutation_restore_direct(w, w.player_id, mt)
        console_logf("applied %s", args)

    case "serums":
        if w == nil { console_log("ERROR: no world active"); return }
        if !cw.world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
        n, ok := strconv.parse_int(args)
        if !ok { console_log("ERROR: expected integer"); return }
        if cw.world_has_component(w, w.player_id, .MutationContainer) {
            cw.world_get_mutation(w, w.player_id).serums = n
        }
        console_logf("serums = %d", n)

    case "gold":
        if w == nil { console_log("ERROR: no world active"); return }
        if !cw.world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
        n, ok := strconv.parse_int(args)
        if !ok { console_log("ERROR: expected integer"); return }
        if cw.world_has_component(w, w.player_id, .Wallet) {
            cw.world_get_wallet(w, w.player_id).gold += n
        }
        console_logf("gold += %d", n)

    case "hp":
        if w == nil { console_log("ERROR: no world active"); return }
        if !cw.world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
        n, ok := strconv.parse_int(args)
        if !ok { console_log("ERROR: expected integer"); return }
        if cw.world_has_component(w, w.player_id, .Health) {
            h := cw.world_get_health(w, w.player_id)
            h.current = clamp(f32(n), 0, h.max)
        }
        console_logf("hp = %d", n)

    case "kill":
        if w == nil { console_log("ERROR: no world active"); return }
        if !cw.world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
        if cw.world_has_component(w, w.player_id, .Health) {
            cw.world_get_health(w, w.player_id).current = 0
        }
        console_log("player killed")

    case:
        console_logf("unknown command '%s' — type 'help'", cmd)
    }
}

@(private = "file")
_mut_type_from_def_name :: proc(name: string) -> cw.MutationType {
    switch name {
    case "mut_serrated_hands":   return .SerratedHands
    case "mut_hollow_bones":     return .HollowBones
    case "mut_exoskeleton":      return .Exoskeleton
    case "mut_symbiote":         return .Symbiote
    case "mut_living_bomb":      return .LivingBomb
    case "mut_glass_cannon":     return .GlassCannon
    case "mut_blind_fire":       return .BlindFire
    case "mut_timelock":         return .Timelock
    case "mut_spectral_form":    return .SpectralForm
    case "mut_deadmans_trigger": return .DeadmansTrigger
    case "mut_blood_frenzy":     return .BloodFrenzy
    case "mut_toxic_flesh":      return .ToxicFlesh
    case "mut_parasite_king":    return .ParasiteKing
    case "mut_corpse_tide":      return .CorpseTide
    case "mut_metamorphosis":   return .Metamorphosis
    case "mut_heart_cage":      return .HeartCage
    case "mut_thorn_pact":      return .ThornPact
    case "mut_carrion_crown":   return .CarrionCrown
    case "mut_false_saint":     return .FalseSaint
    case "mut_black_lung":      return .BlackLung
    }
    return .None
}

@(private = "file")
_mut_def_name_from_type :: proc(mt: cw.MutationType) -> string {
    switch mt {
    case .SerratedHands:   return "mut_serrated_hands"
    case .HollowBones:     return "mut_hollow_bones"
    case .Exoskeleton:     return "mut_exoskeleton"
    case .Symbiote:        return "mut_symbiote"
    case .LivingBomb:      return "mut_living_bomb"
    case .GlassCannon:     return "mut_glass_cannon"
    case .BlindFire:       return "mut_blind_fire"
    case .Timelock:        return "mut_timelock"
    case .SpectralForm:    return "mut_spectral_form"
    case .DeadmansTrigger: return "mut_deadmans_trigger"
    case .BloodFrenzy:     return "mut_blood_frenzy"
    case .ToxicFlesh:      return "mut_toxic_flesh"
    case .ParasiteKing:    return "mut_parasite_king"
    case .CorpseTide:      return "mut_corpse_tide"
    case .Metamorphosis:   return "mut_metamorphosis"
    case .HeartCage:       return "mut_heart_cage"
    case .ThornPact:       return "mut_thorn_pact"
    case .CarrionCrown:    return "mut_carrion_crown"
    case .FalseSaint:      return "mut_false_saint"
    case .BlackLung:       return "mut_black_lung"
    case .None:            return ""
    }
    return ""
}
