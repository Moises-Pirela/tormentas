package main

import rl       "vendor:raylib"
import          "core:fmt"
import          "core:strings"
import          "core:strconv"
import cw       "clockwork"

CONSOLE_MAX_LINES  :: 48
CONSOLE_LINE_CAP   :: 320
CONSOLE_SLIDE_SPD  :: f32(12.0)
CONSOLE_SCROLL_AMT :: 3

g_console_open: bool
g_god_mode:     bool

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
@(private = "file") g_console_slide:    f32
@(private = "file") g_console_scroll:   int

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
    y_off   := panel_h * (g_console_slide - 1)
    fs      := uis(12)
    pad     := uis(8)
    line_h  := fs * 1.4
    input_y   := y_off + panel_h - line_h - pad
    log_bot_y := input_y - pad * 0.5
    visible   := int((panel_h - line_h - pad * 1.5) / line_h)
    if visible < 1 { visible = 1 }
    return { panel_h, y_off, fs, line_h, pad, input_y, log_bot_y, visible }
}


update_console :: proc(dt: f32) {

    if rl.IsKeyPressed(.GRAVE) {
        g_console_open = !g_console_open
        if g_console_open {
            g_console_in_len   = 0
            g_console_bs_timer = 0
            g_console_scroll   = 0
        }
    }


    target := f32(1) if g_console_open else f32(0)
    if g_console_slide < target {
        g_console_slide = min(g_console_slide + dt * CONSOLE_SLIDE_SPD, f32(1))
    } else if g_console_slide > target {
        g_console_slide = max(g_console_slide - dt * CONSOLE_SLIDE_SPD, f32(0))
    }

    if !g_console_open { return }


    wh := rl.GetMouseWheelMove()
    if wh != 0 {
        g_console_scroll -= int(wh) * CONSOLE_SCROLL_AMT
        if g_console_scroll < 0 { g_console_scroll = 0 }

    }


    for {
        ch := rl.GetCharPressed()
        if ch == 0 { break }
        if ch == '`' || ch == '~' { continue }
        if g_console_in_len < len(g_console_input) - 1 {
            g_console_input[g_console_in_len] = u8(ch)
            g_console_in_len += 1
        }
    }


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


draw_console :: proc() {
    if g_console_slide <= 0 { return }

    sw  := f32(rl.GetScreenWidth())
    g   := console_geo()
    bar_w := uis(6)
    spacing := f32(0.4)


    max_scroll := max(g_console_count - g.visible, 0)
    if g_console_scroll > max_scroll { g_console_scroll = max_scroll }


    rl.DrawRectangle(0, i32(g.y_off), i32(sw), i32(g.panel_h),
        rl.Color{ 8, 8, 12, 225 })
    rl.DrawRectangle(0, i32(g.y_off + g.panel_h) - 1, i32(sw), 1,
        rl.Color{ 140, 90, 35, 255 })


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


    if max_scroll > 0 {
        track_x := sw - bar_w - g.pad * 0.5
        track_y := g.y_off + g.pad
        track_h := g.log_bot_y - track_y

        thumb_frac := f32(g.visible) / f32(g_console_count)
        thumb_h    := max(track_h * thumb_frac, uis(20))

        t := f32(g_console_scroll) / f32(max_scroll)
        thumb_y := track_y + (track_h - thumb_h) * (1.0 - t)


        if track_y + track_h > 0 {
            rl.DrawRectangleRounded(
                { track_x, track_y, bar_w, track_h }, 0.5, 4,
                rl.Color{ 30, 26, 20, 160 })
            rl.DrawRectangleRounded(
                { track_x, thumb_y, bar_w, thumb_h }, 0.5, 4,
                rl.Color{ 160, 100, 40, 220 })
        }
    }


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


@(private = "file")
_console_exec :: proc(w: ^cw.World, raw: string) {
    s := strings.trim_space(raw)
    if len(s) == 0 { return }

    sep  := strings.index_byte(s, ' ')
    cmd  := s if sep < 0 else s[:sep]
    args := "" if sep < 0 else strings.trim_space(s[sep + 1:])

    switch cmd {

    case "help":
        console_log("  mut <name>                apply mutation by json entity name")
        console_log("  ability <name> [lv]       spawn ability item at feet (lv 1-5)")
        console_log("  ability_levelup <1-4>     level up ability in equip slot")
        console_log("  serums <n>                set player serum count")
        console_log("  gold <n>                  add gold to wallet")
        console_log("  hp <n>                    set player current HP")
        console_log("  kill                      kill player")
        console_log("  god_mode                  toggle invincibility")
        console_log("  clear                     clear console log")
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

    case "god_mode":
        g_god_mode = !g_god_mode
        if g_god_mode {
            console_log("god mode ON — player cannot die")
        } else {
            console_log("god mode OFF")
        }

    case "ability":


        if w == nil { console_log("ERROR: no world active"); return }
        if !cw.world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
        sep2 := strings.last_index_byte(args, ' ')
        name_part := args
        lv_part   := "1"
        if sep2 >= 0 {
            maybe_lv := strings.trim_space(args[sep2+1:])
            _, ok2 := strconv.parse_int(maybe_lv)
            if ok2 {
                name_part = strings.trim_space(args[:sep2])
                lv_part   = maybe_lv
            }
        }
        at := _ability_type_from_name(name_part)
        if at == .None || int(at) >= len(ABILITY_DEFS) {
            console_logf("ERROR: unknown ability '%s'", name_part)
            console_log("  try: spasm, slam, surge, grip, burst, charge, blink, indexed, vitriol, spray, contagion, exothermic, tormenta, overcharged, coil, shock")
            return
        }
        lv, _ := strconv.parse_int(lv_part)
        lv      = clamp(lv, 1, ABILITY_MAX_LEVEL)
        if cw.world_has_component(w, w.player_id, .Transform) {
            pos := cw.world_get_transform(w, w.player_id).position
            iid := cw.world_create_entity(w)
            cw.world_set_transform(w, iid, cw.TransformComp{ position = pos })
            item               := cw.item_empty()
            item.slot           = .Ability1
            item.ability_type   = at
            item.ability_level  = u8(lv)
            item.grid_w         = 1
            item.grid_h         = 1
            item.rarity         = .Epic
            cw.world_set_item(w, iid, item)
            def := &ABILITY_DEFS[at]
            rc: cw.RenderConfigComp
            cw.render_config_set_name(&rc, def.name)
            cw.render_config_set_icon(&rc, "ability_active")
            cw.render_config_set_desc(&rc, def.desc)
            cw.world_set_render_config(w, iid, rc)
            cw.world_set_ground_item(w, iid)
            cw.world_set_fog_of_war(w, iid)
            console_logf("spawned %s (lv %d) at player position", def.name, lv)
        }

    case "ability_levelup":

        if w == nil { console_log("ERROR: no world active"); return }
        if !cw.world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
        slot_n, ok3 := strconv.parse_int(args)
        if !ok3 || slot_n < 1 || slot_n > 4 {
            console_log("usage: ability_levelup <1-4>")
            return
        }
        if cw.world_has_component(w, w.player_id, .Inventory) {
            inv  := cw.world_get_inventory(w, w.player_id)
            eq   := ability_slot_to_equip(slot_n - 1)
            iid  := inv.equipped[eq]
            if cw.world_is_valid(w, iid) && cw.world_has_component(w, iid, .Item) {
                item := cw.world_get_item(w, iid)
                if item.ability_type != .None {
                    old_lv := max(1, int(item.ability_level))
                    if old_lv >= ABILITY_MAX_LEVEL {
                        console_logf("slot %d already at max level (%d)", slot_n, ABILITY_MAX_LEVEL)
                    } else {
                        item.ability_level = u8(old_lv + 1)
                        save_player(w, w.player_id)
                        console_logf("slot %d upgraded to level %d", slot_n, old_lv+1)
                    }
                } else { console_logf("slot %d has no ability", slot_n) }
            } else { console_logf("slot %d is empty", slot_n) }
        }

    case:
        console_logf("unknown command '%s' — type 'help'", cmd)
    }
}

@(private = "file")
_ability_type_from_name :: proc(raw: string) -> cw.AbilityType {
    s := strings.to_lower(raw, context.temp_allocator)

    switch s {

    case "cadavericspasm",  "cadaveric_spasm",  "spasm":    return .CadavericSpasm
    case "osseouslam",      "osseous_slam",     "slam":     return .OsseousSlam
    case "necroticsurge",   "necrotic_surge",   "surge":    return .NecroticSurge
    case "crushinggrip",    "crushing_grip",    "grip":     return .CrushingGrip

    case "rapiddischarge",  "rapid_discharge",  "burst":    return .RapidDischarge
    case "deliberateround", "deliberate_round", "charge":   return .DeliberateRound
    case "ethervial",       "ether_vial",       "blink":    return .EtherVial
    case "indexed":                                          return .Indexed

    case "vetriolflask",    "vetriol_flask",    "vitriol":  return .VetriolFlask
    case "carbolicspray",   "carbolic_spray",   "spray":    return .CarbolicSpray
    case "contagion":                                        return .Contagion
    case "exothermic":                                      return .Exothermic

    case "latormenta",      "la_tormenta",      "tormenta": return .LaTormenta
    case "overcharged":                                      return .Overcharged
    case "inductioncoil",   "induction_coil",   "coil":     return .InductionCoil
    case "galvanicshock",   "galvanic_shock",   "shock":    return .GalvanicShock

    case "whirlwind",   "whirl_wind":   return .CadavericSpasm
    case "chemgrenade", "chem_grenade": return .VetriolFlask
    }
    return .None
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
