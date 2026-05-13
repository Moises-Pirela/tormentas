package main

// =============================================================================
// ui_hud.odin — Diablo 2–style bottom HUD
//
// Replaces the three separate draw procs that were in render.odin:
//   draw_hud_clay   (HP/EN/XP bars)
//   draw_ability_hud (Q/E/F/G chips, top-right)
//   draw_ammo_ring   (radial ammo ring, bottom-left)
//
// New layout (anchored bottom-centre via Clay floating):
//
//   [HP ORB]  [AMMO]  [ Q ][ E ][ F ][ G ]  [EN ORB]
//                     [══════ XP bar ══════]
//
// Everything goes through one Clay frame so layout is consistent at any res.
// =============================================================================

import rl   "vendor:raylib"
import cw   "clockwork"
import clay "../clay"
import      "core:fmt"

// ── Status-effect display tables ─────────────────────────────────────────────
// Indexed by cw.StatusEffectType ordinal.  Keep in sync with the enum order:
//   Slow(0), Poison(1), Burn(2), Stun(3), Root(4), Oiled(5), Wet(6)

@(private = "file")
STATUS_EFFECT_LABELS := [len(cw.StatusEffectType)]string{
    "SLOW", "PSN", "BURN", "STUN", "ROOT", "OIL", "WET",
}

@(private = "file")
STATUS_EFFECT_COLORS := [len(cw.StatusEffectType)]rl.Color{
    {  80, 160, 220, 255 }, // Slow  — icy blue
    {  80, 205,  80, 255 }, // Poison — green
    { 240, 120,  30, 255 }, // Burn  — orange
    { 255, 220,  40, 255 }, // Stun  — yellow
    { 145, 100,  45, 255 }, // Root  — bark brown
    { 130,  95,  40, 255 }, // Oiled — dark amber
    { 100, 185, 240, 255 }, // Wet   — sky blue
}

// draw_hud is the single entry point called from main.odin's draw_playing.
// It supersedes draw_hud_clay + draw_ammo_ring + draw_ability_hud.
draw_hud :: proc(w: ^cw.World) {
    clay.BeginLayout()

    if cw.world_is_valid(w, w.player_id) {
        h := cw.world_get_health(w, w.player_id)

        hp_ratio := clamp(h.current / h.max, 0, 1) if h.max > 0 else f32(0)
        en_ratio := clamp(h.energy / h.max_energy, 0, 1) if h.max_energy > 0 else f32(0)

        // Shield ring on HP orb
        shield_ratio := f32(0)
        xp_ratio     := f32(0)
        if cw.world_has_component(w, w.player_id, .Stats) {
            st := cw.world_get_stats(w, w.player_id)
            if st.shield_max > 0 {
                shield_ratio = clamp(h.shield / st.shield_max, 0, 1)
            }
            if st.xp_next > 0 {
                xp_ratio = clamp(st.xp / st.xp_next, 0, 1)
            }
        }

        // ── Build custom draw data ─────────────────────────────────────────

        // HP orb
        hp_val_buf: [8]u8
        hp_val_s := fmt.bprintf(hp_val_buf[:7], "%.0f", h.current)
        hp_val_buf[len(hp_val_s)] = 0

        hp_orb := UICustomData{ kind = .Orb, orb = UICustomOrb{
            fill_ratio   = hp_ratio,
            shield_ratio = shield_ratio,
            fill_col     = rl.Color{ 158, 32, 32, 255 },
            bg_col       = rl.Color{  24,  7,  7, 255 },
        }}
        copy(hp_orb.orb.value_text[:], hp_val_buf[:])

        // Energy orb
        en_val_buf: [8]u8
        en_val_s := fmt.bprintf(en_val_buf[:7], "%.0f", h.energy)
        en_val_buf[len(en_val_s)] = 0

        en_orb := UICustomData{ kind = .Orb, orb = UICustomOrb{
            fill_ratio = en_ratio,
            fill_col   = rl.Color{  36, 72, 165, 255 },
            bg_col     = rl.Color{   7, 12,  32, 255 },
        }}
        copy(en_orb.orb.value_text[:], en_val_buf[:])

        // Ammo chip
        ammo_data := UICustomData{ kind = .AmmoChip }
        _hud_fill_ammo_chip(w, &ammo_data.ammo)

        // 4 ability chips (Q / E / F / G)
        chip_data: [cw.ABILITY_SLOT_COUNT]UICustomData
        _hud_fill_ability_chips(w, &chip_data)

        // Active status effects on the player
        HUDStatusInfo :: struct { label: string, color: rl.Color, duration: f32 }
        se_buf: [len(cw.StatusEffectType)]HUDStatusInfo
        se_n   := 0
        if cw.world_has_component(w, w.player_id, .StatusEffect) {
            sec := cw.world_get_status_effects(w, w.player_id)
            for et in 0..<len(cw.StatusEffectType) {
                ef := &sec.effects[et]
                if ef.duration <= 0 { continue }
                se_buf[se_n] = HUDStatusInfo{
                    label    = STATUS_EFFECT_LABELS[et],
                    color    = STATUS_EFFECT_COLORS[et],
                    duration = ef.duration,
                }
                se_n += 1
            }
        }

        // ── Clay layout ───────────────────────────────────────────────────
        ORB_SZ   := uis(80)
        CHIP_SZ  := uis(54)
        CHIP_GAP := u16(uis(6))
        XP_H     := uis(7)
        VPAD     := u16(uis(5))
        HPAD     := u16(uis(6))

        // Reset arena once per Clay frame
        ui_frame_reset()

        // Compute center column width = (n chips × size) + ((n-1) × gap)
        n_chips  := f32(cw.ABILITY_SLOT_COUNT + 1)   // +1 for ammo chip
        center_w := CHIP_SZ * n_chips + f32(CHIP_GAP) * (n_chips - 1)

        if clay.UI(clay.ID("HUDRoot"))({
            layout = {
                layoutDirection = .LeftToRight,
                childGap        = CHIP_GAP,
                childAlignment  = { y = .Center },
                padding         = { left = HPAD, right = HPAD,
                                    top  = VPAD, bottom = VPAD },
                sizing          = { clay.SizingFit(), clay.SizingFit() },
            },
            floating = {
                offset     = { 0, -4 },
                attachment = { element = .CenterBottom, parent = .CenterBottom },
                attachTo   = .Root,
            },
            backgroundColor = { 6, 4, 3, 210 },
            cornerRadius    = clay.CornerRadiusAll(5),
            border          = { color = ui_clay_color(COL_RULE),
                                width = { 1, 1, 1, 1, 0 } },
        }) {

            // HP globe (left)
            if clay.UI(clay.ID("HPOrb"))({
                layout = { sizing = { clay.SizingFixed(ORB_SZ),
                                      clay.SizingFixed(ORB_SZ) } },
                custom = { customData = ui_push_custom(hp_orb) },
            }) {}

            // Centre column: status row (conditional) + chip row + XP bar
            if clay.UI(clay.ID("HUDCenter"))({
                layout = {
                    layoutDirection = .TopToBottom,
                    childGap        = u16(uis(4)),
                    childAlignment  = { x = .Center },
                    sizing          = { clay.SizingFixed(center_w),
                                       clay.SizingFit() },
                },
            }) {

                // Status-effect indicators (only when at least one is active)
                if se_n > 0 {
                    SCHIP_W  := uis(36)
                    SCHIP_H  := uis(28)
                    SCHIP_ID := [len(cw.StatusEffectType)]string{
                        "SE0","SE1","SE2","SE3","SE4","SE5","SE6" }

                    if clay.UI(clay.ID("StatusRow"))({
                        layout = {
                            layoutDirection = .LeftToRight,
                            childGap        = u16(uis(4)),
                            childAlignment  = { x = .Center, y = .Center },
                            sizing          = { clay.SizingGrow(), clay.SizingFit() },
                        },
                    }) {
                        for i in 0..<se_n {
                            se     := &se_buf[i]
                            dark   := rl.Color{
                                se.color.r / 5, se.color.g / 5,
                                se.color.b / 5, 220 }
                            dur_s  := fmt.tprintf("%.1fs", se.duration)

                            if clay.UI(clay.ID(SCHIP_ID[i]))({
                                layout = {
                                    layoutDirection = .TopToBottom,
                                    childGap        = u16(uis(1)),
                                    childAlignment  = { x = .Center, y = .Center },
                                    padding         = {
                                        left = u16(uis(3)), right  = u16(uis(3)),
                                        top  = u16(uis(3)), bottom = u16(uis(3)),
                                    },
                                    sizing = { clay.SizingFixed(SCHIP_W),
                                               clay.SizingFixed(SCHIP_H) },
                                },
                                backgroundColor = ui_clay_color(dark),
                                cornerRadius    = clay.CornerRadiusAll(3),
                                border          = { color = ui_clay_color(se.color),
                                                    width = { 1, 1, 1, 1, 0 } },
                            }) {
                                clay.TextDynamic(se.label, clay.TextConfig({
                                    fontSize  = u16(uis(10)),
                                    textColor = ui_clay_color(se.color),
                                }))
                                clay.TextDynamic(dur_s, clay.TextConfig({
                                    fontSize  = u16(uis(8)),
                                    textColor = ui_clay_color(
                                        rl.Color{ 175, 165, 145, 190 }),
                                }))
                            }
                        }
                    } // StatusRow
                }

                // Chip row: ammo + 4 ability slots
                if clay.UI(clay.ID("ChipRow"))({
                    layout = {
                        layoutDirection = .LeftToRight,
                        childGap        = CHIP_GAP,
                        childAlignment  = { y = .Center },
                        sizing          = { clay.SizingFit(), clay.SizingFit() },
                    },
                }) {
                    // Ammo / weapon chip
                    if clay.UI(clay.ID("AmmoChip"))({
                        layout = { sizing = { clay.SizingFixed(CHIP_SZ),
                                              clay.SizingFixed(CHIP_SZ) } },
                        custom = { customData = ui_push_custom(ammo_data) },
                    }) {}

                    // Q / E / F / G
                    chip_ids := [cw.ABILITY_SLOT_COUNT]string{
                        "ChipQ", "ChipE", "ChipF", "ChipG" }
                    for i in 0..<cw.ABILITY_SLOT_COUNT {
                        if clay.UI(clay.ID(chip_ids[i]))({
                            layout = { sizing = { clay.SizingFixed(CHIP_SZ),
                                                  clay.SizingFixed(CHIP_SZ) } },
                            custom = { customData = ui_push_custom(chip_data[i]) },
                        }) {}
                    }
                } // ChipRow

                // XP bar
                ui_hbar("HUDXP", xp_ratio,
                    rl.Color{ 180, 148, 36, 255 },
                    rl.Color{  28,  22, 10, 255 },
                    XP_H)

            } // HUDCenter

            // Energy globe (right)
            if clay.UI(clay.ID("ENOrb"))({
                layout = { sizing = { clay.SizingFixed(ORB_SZ),
                                      clay.SizingFixed(ORB_SZ) } },
                custom = { customData = ui_push_custom(en_orb) },
            }) {}

        } // HUDRoot
    }

    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)

    // ── Interaction prompt (screen-space, above HUD) ───────────────────────────
    draw_interact_prompt(w)
}

// draw_interact_prompt draws the "[E] Prompt" hint when the player is near an
// interactable entity.  Called from draw_hud (screen-space, no BeginMode2D).
@(private = "file")
draw_interact_prompt :: proc(w: ^cw.World) {
    if g_interact_focused_id == cw.INVALID_ENTITY { return }
    if !cw.world_is_valid(w, g_interact_focused_id) { return }
    if !cw.world_has_component(w, g_interact_focused_id, .Interactable) { return }

    ia := cw.world_get_interactable(w, g_interact_focused_id)
    if !ia.active || ia.prompt[0] == 0 { return }

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    prompt_cs := cstring(&ia.prompt[0])
    prompt_fs := uis(15)
    psz       := rl.MeasureTextEx(g_font, prompt_cs, prompt_fs, 1)
    px := sw * 0.5 - psz.x * 0.5
    py := sh * 0.60 - psz.y

    // Shadow
    rl.DrawTextEx(g_font, prompt_cs, {px + uis(1.5), py + uis(1.5)},
        prompt_fs, 1, rl.Color{0, 0, 0, 180})
    // Text
    rl.DrawTextEx(g_font, prompt_cs, {px, py},
        prompt_fs, 1, rl.Color{255, 235, 160, 240})

    // [E] key hint below the prompt
    key_cs  := cstring("[E]")
    key_fs  := uis(10)
    ksz     := rl.MeasureTextEx(g_font, key_cs, key_fs, 0.5)
    kx      := sw * 0.5 - ksz.x * 0.5
    ky      := py + psz.y + uis(3)
    rl.DrawTextEx(g_font, key_cs, {kx + uis(1), ky + uis(1)}, key_fs, 0.5,
        rl.Color{0, 0, 0, 150})
    rl.DrawTextEx(g_font, key_cs, {kx, ky}, key_fs, 0.5,
        rl.Color{190, 190, 190, 210})
}

// ── Helpers ───────────────────────────────────────────────────────────────

@(private = "file")
_hud_fill_ammo_chip :: proc(w: ^cw.World, chip: ^UICustomAmmo) {
    chip^ = {}

    if !cw.world_has_component(w, w.player_id, .Equipment) { return }
    equip := cw.world_get_equipment(w, w.player_id)
    wid   := equip.weapon_entity_id
    if !cw.world_is_valid(w, wid) { return }

    // Weapon display name
    if cw.world_has_component(w, wid, .RenderConfig) {
        rc         := cw.world_get_render_config(w, wid)
        translated := string(loc_lookup(cw.render_config_name_cstr(rc)))
        n_copy     := min(len(translated), 23)
        copy(chip.wep_name[:], translated[:n_copy])
        chip.wep_name[n_copy] = 0
    }

    if !cw.world_has_component(w, wid, .Weapon) { return }
    wp := cw.world_get_weapon_data(w, wid)

    // Melee / infinite-ammo weapons
    if wp.ammo_max <= 0 {
        chip.is_melee  = true
        chip.ammo_text[0] = 'M'
        chip.ammo_text[1] = 0
        return
    }

    chip.ammo_ratio   = clamp(f32(wp.ammo_current) / f32(wp.ammo_max), 0, 1)
    chip.is_reloading = wp.is_reloading

    if wp.is_reloading {
        chip.ammo_text[0] = 'R'
        chip.ammo_text[1] = 0
        if wp.reload_time > 0 {
            chip.reload_ratio = 1 - clamp(wp.reload_timer / wp.reload_time, 0, 1)
        }
    } else {
        s := fmt.bprintf(chip.ammo_text[:7], "%d", wp.ammo_current)
        chip.ammo_text[len(s)] = 0
    }
}

@(private = "file")
_hud_fill_ability_chips :: proc(w: ^cw.World, chips: ^[cw.ABILITY_SLOT_COUNT]UICustomData) {
    ab: ^cw.AbilityComp = nil
    if cw.world_has_component(w, w.player_id, .Ability) {
        ab = cw.world_get_ability(w, w.player_id)
    }

    key_chars := [cw.ABILITY_SLOT_COUNT]u8{ 'Q', 'E', 'F', 'G' }

    for i in 0..<cw.ABILITY_SLOT_COUNT {
        chips[i].kind = .AbilityChip
        chip := &chips[i].ability

        chip.key_label[0] = key_chars[i]
        chip.key_label[1] = 0

        ab_type      := player_ability_in_slot(w, w.player_id, i)
        chip.has_ability = ab_type != .None

        if chip.has_ability && ab != nil {
            def   := &ABILITY_DEFS[ab_type]
            st_ab := ab.slots[i]

            chip.cd_ratio    = clamp(st_ab.cooldown / def.cd_max, 0, 1) if def.cd_max > 0 else 0
            chip.charge_glow = ab_type == .DeathShot   && st_ab.charging
            chip.dance_glow  = ab_type == .DevilsDance && st_ab.dance_ready

            // Copy up to 23 chars of the ability name
            name_bytes := transmute([]u8)def.name
            n_copy     := min(len(name_bytes), 23)
            copy(chip.name_label[:], name_bytes[:n_copy])
            chip.name_label[n_copy] = 0
        }
    }
}
