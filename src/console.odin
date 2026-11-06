package main

import im       "../deps/imgui/imgui"
import rl       "vendor:raylib"
import          "core:fmt"
import          "core:strings"
import          "core:strconv"

CONSOLE_MAX_LINES  :: 48
CONSOLE_LINE_CAP   :: 320

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

CONSOLE_HISTORY :: 16

@(private = "file") g_console_hist:      [CONSOLE_HISTORY][512]u8
@(private = "file") g_console_hist_len:  [CONSOLE_HISTORY]int
@(private = "file") g_console_hist_n:    int
@(private = "file") g_console_hist_pos:  int = -1
@(private = "file") g_console_refocus:   bool
@(private = "file") g_console_autoscroll: bool = true
@(private = "file") g_console_follow:    bool

console_set_open :: proc(open: bool) {
    g_console_open = open
    if open {
        g_console_in_len   = 0
        g_console_hist_pos = -1
        g_console_refocus  = true
        g_console_follow   = true
    }
}

update_console :: proc(dt: f32) {
    if rl.IsKeyPressed(.GRAVE) {
        devui_ignore_char('`')
        devui_ignore_char('~')
        console_set_open(!g_console_open)
    }
}

@(private = "file")
_console_submit :: proc() {
    raw := strings.trim_space(string(g_console_input[:g_console_in_len]))
    if raw == "" { return }
    console_logf("> %s", raw)
    slot := g_console_hist_n % CONSOLE_HISTORY
    copy(g_console_hist[slot][:], raw)
    g_console_hist_len[slot] = len(raw)
    g_console_hist_n += 1
    w: ^World = nil
    if g_sim_alive { w = &g_sim.world }
    _console_exec(w, raw)
    g_console_in_len   = 0
    g_console_hist_pos = -1
    g_console_follow   = true
}

@(private = "file")
_console_history_step :: proc(dir: int) {
    count := min(g_console_hist_n, CONSOLE_HISTORY)
    if count == 0 { return }
    if g_console_hist_pos < 0 {
        if dir > 0 { return }
        g_console_hist_pos = 0
    } else {
        g_console_hist_pos = clamp(g_console_hist_pos - dir, -1, count - 1)
    }
    if g_console_hist_pos < 0 { g_console_in_len = 0; return }
    slot := (g_console_hist_n - 1 - g_console_hist_pos) %% CONSOLE_HISTORY
    n := g_console_hist_len[slot]
    copy(g_console_input[:], g_console_hist[slot][:n])
    g_console_in_len = n
}

console_ui :: proc() {
    if !g_console_open { return }
    vp := im.GetMainViewport()
    im.SetNextWindowPos({ vp.WorkPos.x + 20, vp.WorkPos.y + vp.WorkSize.y * 0.55 }, .FirstUseEver)
    im.SetNextWindowSize({ vp.WorkSize.x * 0.6, vp.WorkSize.y * 0.38 }, .FirstUseEver)
    open := true
    defer im.End()
    if !im.Begin("Console", &open) {
        if !open { console_set_open(false) }
        return
    }
    if !open { console_set_open(false); return }

    footer := im.GetFrameHeightWithSpacing() + im.GetStyle().ItemSpacing.y
    if im.BeginChild("##log", { 0, -footer }, { .Borders }, { .HorizontalScrollbar }) {
        first := g_console_cursor - g_console_count
        for i in first..<g_console_cursor {
            line := &g_console_lines[((i % CONSOLE_MAX_LINES) + CONSOLE_MAX_LINES) % CONSOLE_MAX_LINES]
            text := string(line.buf[:line.len])
            if strings.has_prefix(text, "> ") {
                ui_text_col(DEVUI_GOLD, "%s", text)
            } else {
                ui_text("%s", text)
            }
        }
        if g_console_follow || (g_console_autoscroll && im.GetScrollY() >= im.GetScrollMaxY()) {
            im.SetScrollHereY(1)
            g_console_follow = false
        }
    }
    im.EndChild()

    if g_console_refocus {
        im.SetKeyboardFocusHere()
        g_console_refocus = false
    }
    im.SetNextItemWidth(-90)
    if ui_input_buf("##cin", g_console_input[:], &g_console_in_len, { .EnterReturnsTrue }, "command  (help for a list)") {
        _console_submit()
        g_console_refocus = true
    }
    if im.IsItemActive() {
        if im.IsKeyPressed(.UpArrow)   { _console_history_step(-1) }
        if im.IsKeyPressed(.DownArrow) { _console_history_step(+1) }
    }
    im.SameLine()
    im.Checkbox("Follow", &g_console_autoscroll)
}

_console_exec :: proc(w: ^World, raw: string) {
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
        console_log("  audio <sub>               reload|list|play <ev>|state <name>|duck")
        console_log("  clear                     clear console log")
        console_log("available mutations:")
        for mt in MutationType {
            if mt == .None { continue }
            console_logf("    %s", _mut_def_name_from_type(mt))
        }

    case "clear":
        g_console_count  = 0
        g_console_cursor = 0

    case "mut":
        if w == nil { console_log("ERROR: no world active"); return }
        if !world_is_valid(w, w.player_id) {
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
        mc := comp_get(w, w.player_id, .MutationContainer, MutationContainerComp)
        if mc.entity_count >= MAX_MUTATION_SLOTS {
            console_log("ERROR: mutation slots full")
            return
        }
        mutation_restore_direct(w, w.player_id, mt)
        console_logf("applied %s", args)

    case "serums":
        if w == nil { console_log("ERROR: no world active"); return }
        if !world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
        n, ok := strconv.parse_int(args)
        if !ok { console_log("ERROR: expected integer"); return }
        if world_has_component(w, w.player_id, .MutationContainer) {
            comp_get(w, w.player_id, .MutationContainer, MutationContainerComp).serums = n
        }
        console_logf("serums = %d", n)

    case "gold":
        if w == nil { console_log("ERROR: no world active"); return }
        if !world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
        n, ok := strconv.parse_int(args)
        if !ok { console_log("ERROR: expected integer"); return }
        if world_has_component(w, w.player_id, .Wallet) {
            comp_get(w, w.player_id, .Wallet, WalletComp).gold += n
        }
        console_logf("gold += %d", n)

    case "hp":
        if w == nil { console_log("ERROR: no world active"); return }
        if !world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
        n, ok := strconv.parse_int(args)
        if !ok { console_log("ERROR: expected integer"); return }
        if world_has_component(w, w.player_id, .Health) {
            h := comp_get(w, w.player_id, .Health, HealthComp)
            h.current = clamp(f32(n), 0, h.max)
            if (h.current <= 0) {
                h.current = 0
                on_player_death(w)
            }
        }

        console_logf("hp = %d", n)

    case "kill":
        if w == nil { console_log("ERROR: no world active"); return }
        if !world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
        if world_has_component(w, w.player_id, .Health) {
            comp_get(w, w.player_id, .Health, HealthComp).current = 0
        }
        console_log("player killed")

    case "god_mode":
        g_god_mode = !g_god_mode
        if g_god_mode {
            console_log("god mode ON — player cannot die")
        } else {
            console_log("god mode OFF")
        }

    case "audio":
        sub  := args
        rest := ""
        if ssep := strings.index_byte(args, ' '); ssep >= 0 {
            sub  = args[:ssep]
            rest = strings.trim_space(args[ssep + 1:])
        }
        switch sub {
        case "reload":
            audio_reload()
            console_log("audio: reloaded data/sounds/audio.json")
        case "list":
            names := audio_debug_event_names()
            console_logf("audio: %d events registered", len(names))
            for n in names { console_logf("    %s", n) }
        case "play":
            if len(rest) == 0 { console_log("usage: audio play <event>"); return }
            play_sfx(rest)
            console_logf("audio: played '%s'", rest)
        case "state":
            if audio_music_set_state_named(rest) {
                console_logf("audio: music state -> %s", rest)
            } else {
                console_log("usage: audio state <none|menu|hub|explore|combat|boss|tension>")
            }
        case "duck":
            audio_duck_music(0.6, 200, 700)
            console_log("audio: ducked music")
        case:
            console_log("usage: audio <reload | list | play <event> | state <name> | duck>")
        }

    case "ability":

        if w == nil { console_log("ERROR: no world active"); return }
        if !world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
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
        if world_has_component(w, w.player_id, .Transform) {
            pos := comp_get(w, w.player_id, .Transform, TransformComp).position
            iid := world_create_entity(w)
            comp_set(w, iid, .Transform, TransformComp{ position = pos })
            item               := item_empty()
            item.slot           = .Ability1
            item.ability_type   = at
            item.ability_level  = u8(lv)
            item.grid_w         = 1
            item.grid_h         = 1
            item.rarity         = .Epic
            comp_set(w, iid, .Item, item)
            def := &ABILITY_DEFS[at]
            rc: RenderConfigComp
            render_config_set_name(&rc, def.name)
            render_config_set_icon(&rc, "ability_active")
            render_config_set_desc(&rc, def.desc)
            comp_set(w, iid, .RenderConfig, rc)
            comp_add(w, iid, .GroundItem)
            comp_add(w, iid, .FogOfWar)
            console_logf("spawned %s (lv %d) at player position", def.name, lv)
        }

    case "ability_levelup":

        if w == nil { console_log("ERROR: no world active"); return }
        if !world_is_valid(w, w.player_id) { console_log("ERROR: no active player"); return }
        slot_n, ok3 := strconv.parse_int(args)
        if !ok3 || slot_n < 1 || slot_n > 4 {
            console_log("usage: ability_levelup <1-4>")
            return
        }
        if world_has_component(w, w.player_id, .Inventory) {
            inv  := comp_get(w, w.player_id, .Inventory, InventoryComp)
            eq   := ability_slot_to_equip(slot_n - 1)
            iid  := inv.equipped[eq]
            if world_is_valid(w, iid) && world_has_component(w, iid, .Item) {
                item := comp_get(w, iid, .Item, ItemComp)
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
_ability_type_from_name :: proc(raw: string) -> AbilityType {
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
_mut_type_from_def_name :: proc(name: string) -> MutationType {
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
_mut_def_name_from_type :: proc(mt: MutationType) -> string {
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
