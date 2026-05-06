package main

// =============================================================================
// clay_renderer.odin — Raylib backend for Clay render commands
//
// clay_raylib_render() iterates the Clay command list and dispatches:
//   .Rectangle  → DrawRectangle / DrawRectangleRounded
//   .Border     → DrawRectangle (four edges)
//   .ScissorStart / .ScissorEnd
//   .Text       → DrawTextEx (multi-line aware)
//   .Custom     → UICustomData dispatch:
//                   .Orb         → _draw_orb
//                   .AbilityChip → _draw_ability_chip
//                   .AmmoChip    → _draw_ammo_chip
// =============================================================================

import clay "../clay"
import rl   "vendor:raylib"
import      "core:math"
import      "core:strings"

clay_color :: #force_inline proc(c: clay.Color) -> rl.Color {
    return { u8(c[0]), u8(c[1]), u8(c[2]), u8(c[3]) }
}

clay_raylib_render :: proc(cmds: ^clay.ClayArray(clay.RenderCommand)) {
    for i in 0..<cmds.length {
        cmd := clay.RenderCommandArray_Get(cmds, i)
        bb  := cmd.boundingBox

        switch cmd.commandType {

        case .Rectangle:
            cfg := cmd.renderData.rectangle
            col := clay_color(cfg.backgroundColor)
            r   := cfg.cornerRadius.topLeft
            if r > 0 {
                radius := (r * 2) / min(bb.width, bb.height)
                rl.DrawRectangleRounded({ bb.x, bb.y, bb.width, bb.height }, radius, 8, col)
            } else {
                rl.DrawRectangle(
                    i32(math.round(bb.x)),
                    i32(math.round(bb.y)),
                    i32(math.round(bb.width)),
                    i32(math.round(bb.height)),
                    col)
            }

        case .Border:
            cfg := cmd.renderData.border
            col := clay_color(cfg.color)
            cr  := cfg.cornerRadius
            bw  := cfg.width
            if bw.left   > 0 { rl.DrawRectangle(i32(bb.x),                              i32(bb.y + cr.topLeft),    i32(bw.left),   i32(bb.height - cr.topLeft    - cr.bottomLeft),  col) }
            if bw.right  > 0 { rl.DrawRectangle(i32(bb.x + bb.width - f32(bw.right)),   i32(bb.y + cr.topRight),   i32(bw.right),  i32(bb.height - cr.topRight   - cr.bottomRight), col) }
            if bw.top    > 0 { rl.DrawRectangle(i32(bb.x + cr.topLeft),                 i32(bb.y),                 i32(bb.width  - cr.topLeft    - cr.topRight),   i32(bw.top),    col) }
            if bw.bottom > 0 { rl.DrawRectangle(i32(bb.x + cr.bottomLeft),              i32(bb.y + bb.height - f32(bw.bottom)), i32(bb.width - cr.bottomLeft - cr.bottomRight), i32(bw.bottom), col) }

        case .ScissorStart:
            rl.BeginScissorMode(
                i32(math.round(bb.x)),
                i32(math.round(bb.y)),
                i32(math.round(bb.width)),
                i32(math.round(bb.height)))

        case .ScissorEnd:
            rl.EndScissorMode()

        case .Text:
            cfg := cmd.renderData.text
            text := string(cfg.stringContents.chars[:cfg.stringContents.length])
            if len(text) == 0 { continue }
            fs := f32(cfg.fontSize)
            if fs <= 0 { fs = 12 }
            spacing := f32(cfg.letterSpacing)
            if spacing <= 0 { spacing = 0.5 }
            col := clay_color(cfg.textColor)

            line_start := 0
            line_idx := 0
            for i := 0; i <= len(text); i += 1 {
                if i < len(text) && text[i] != '\n' { continue }
                line := text[line_start:i]
                line_cs := strings.clone_to_cstring(line, context.temp_allocator)
                rl.DrawTextEx(g_font, line_cs, { bb.x, bb.y + f32(line_idx) * fs }, fs, spacing, col)
                line_start = i + 1
                line_idx += 1
            }

        case .Custom:
            cd := cast(^UICustomData)cmd.renderData.custom.customData
            if cd == nil { continue }
            switch cd.kind {
            case .Orb:         _draw_orb(bb, &cd.orb)
            case .AbilityChip: _draw_ability_chip(bb, &cd.ability)
            case .AmmoChip:    _draw_ammo_chip(bb, &cd.ammo)
            case .InvSlot:     _draw_inv_slot(bb, &cd.inv_slot)
            case .WeaponSlot:  _draw_weapon_slot(bb, &cd.wep_slot)
            case .InvAbility:  _draw_inv_ability(bb, &cd.inv_abil)
            case .None:
            }

        case .Image:
        case .None:
        }
    }
}

// ── Orb ───────────────────────────────────────────────────────────────────
// Draws a circular health/energy globe with a liquid-fill level effect.
// The shield_ratio > 0 adds a thin arc ring around the outside.

@(private = "file")
_draw_orb :: proc(bb: clay.BoundingBox, orb: ^UICustomOrb) {
    cx := i32(math.round(bb.x + bb.width  * 0.5))
    cy := i32(math.round(bb.y + bb.height * 0.5))
    radius := bb.width * 0.5

    // Dark background circle
    rl.DrawCircle(cx, cy, radius, orb.bg_col)

    // Liquid fill — scissor-clip to the bottom fill_ratio of the bounding box
    fill_ratio := clamp(orb.fill_ratio, 0, 1)
    if fill_ratio > 0 {
        fill_h := bb.height * fill_ratio
        clip_y := i32(math.round(bb.y + bb.height - fill_h))
        clip_h := i32(math.ceil(fill_h))
        if clip_h > 0 {
            rl.BeginScissorMode(i32(math.round(bb.x)), clip_y, i32(math.ceil(bb.width)), clip_h)
            rl.DrawCircle(cx, cy, radius - 1, orb.fill_col)
            rl.EndScissorMode()
        }
    }

    // Shield ring — thin arc around the orb, sweeping clockwise from the top
    if orb.shield_ratio > 0 {
        sr         := clamp(orb.shield_ratio, 0, 1)
        ring_inner := radius + 2
        ring_outer := radius + 5
        end_angle  := f32(-90) + 360 * sr
        rl.DrawRing(
            { f32(cx), f32(cy) },
            ring_inner, ring_outer,
            -90, end_angle, 24,
            COL_SHIELD)
    }

    // Inner rim ring (gives the globe a sense of depth)
    rl.DrawCircleLines(cx, cy, radius,     rl.Color{ 60,  46, 28, 180 })
    rl.DrawCircleLines(cx, cy, radius - 1, rl.Color{ 40,  30, 16, 120 })

    // Value text — current HP / Energy centred in the orb
    if orb.value_text[0] != 0 {
        val_cs := cstring(&orb.value_text[0])
        val_fs := uis(13)
        vsz    := rl.MeasureTextEx(g_font, val_cs, val_fs, 0.5)
        rl.DrawTextEx(g_font, val_cs,
            { f32(cx) - vsz.x * 0.5, f32(cy) - vsz.y * 0.5 },
            val_fs, 0.5, COL_PARCH)
    }
}

// ── Ability chip ──────────────────────────────────────────────────────────
// One Q/E/F/G slot: background, cooldown overlay, glow, key label, name.

@(private = "file")
_draw_ability_chip :: proc(bb: clay.BoundingBox, chip: ^UICustomAbility) {
    bx := i32(bb.x); by := i32(bb.y)
    bw := i32(bb.width); bh := i32(bb.height)

    // Background
    bg_col := rl.Color{ 10, 7, 5, 220 } if chip.has_ability else rl.Color{ 8, 6, 4, 160 }
    rl.DrawRectangle(bx, by, bw, bh, bg_col)

    // Cooldown overlay — fills from the bottom, drains upward as CD expires
    if chip.has_ability && chip.cd_ratio > 0 {
        overlay_h := i32(f32(bh) * clamp(chip.cd_ratio, 0, 1))
        rl.DrawRectangle(bx, by + bh - overlay_h, bw, overlay_h, rl.Color{ 0, 0, 0, 160 })
    }

    // Special-state glow overlays
    if chip.charge_glow { rl.DrawRectangle(bx, by, bw, bh, rl.Color{ 200,  40,  20, 70 }) }
    if chip.dance_glow  { rl.DrawRectangle(bx, by, bw, bh, rl.Color{  20, 200, 200, 65 }) }

    // Border — brass when ready or glowing, muted otherwise
    ready   := chip.has_ability && chip.cd_ratio <= 0
    glow    := chip.charge_glow || chip.dance_glow
    bdr_col := COL_BRASS if (ready || glow) else COL_RULE
    rl.DrawRectangleLinesEx({ bb.x, bb.y, bb.width, bb.height }, 1, bdr_col)

    // Text colour
    key_col: rl.Color
    switch {
    case glow:             key_col = COL_PARCH
    case ready:            key_col = COL_PARCH
    case chip.has_ability: key_col = COL_MUTED
    case:                  key_col = rl.Color{ 55, 50, 40, 140 }
    }

    // Key label (top-left corner)
    if chip.key_label[0] != 0 {
        rl.DrawTextEx(g_font, cstring(&chip.key_label[0]),
            { bb.x + uis(5), bb.y + uis(4) },
            uis(16), 1, key_col)
    }

    // Ability name (bottom-centre)
    if chip.has_ability && chip.name_label[0] != 0 {
        name_fs := uis(10)
        name_cs := cstring(&chip.name_label[0])
        nsz     := rl.MeasureTextEx(g_font, name_cs, name_fs, 0.5)
        rl.DrawTextEx(g_font, name_cs,
            { bb.x + bb.width * 0.5 - nsz.x * 0.5, bb.y + bb.height - uis(15) },
            name_fs, 0.5, key_col)
    }
}

// ── Ammo chip ─────────────────────────────────────────────────────────────
// Shows the equipped weapon's current ammo count (or reload progress).
// Melee / infinite-ammo weapons show a simple "M" symbol.

@(private = "file")
_draw_ammo_chip :: proc(bb: clay.BoundingBox, chip: ^UICustomAmmo) {
    bx := i32(bb.x); by := i32(bb.y)
    bw := i32(bb.width); bh := i32(bb.height)

    rl.DrawRectangle(bx, by, bw, bh, rl.Color{ 12, 9, 6, 220 })

    if !chip.is_melee {
        // Ammo strip — thin bar at the very bottom of the chip
        strip_h := max(i32(uis(4)), 2)
        strip_y := by + bh - strip_h
        rl.DrawRectangle(bx, strip_y, bw, strip_h, rl.Color{ 40, 34, 24, 255 })
        if chip.ammo_ratio > 0 {
            ammo_col := COL_CRIMSON if chip.ammo_ratio <= 0.334 else rl.Color{ 192, 152, 44, 255 }
            rl.DrawRectangle(bx, strip_y, i32(f32(bw) * chip.ammo_ratio), strip_h, ammo_col)
        }

        // Reload overlay — sweeps across when reloading
        if chip.is_reloading && chip.reload_ratio > 0 {
            rl.DrawRectangle(bx, by, bw, bh - strip_h, rl.Color{ 0, 0, 0, 100 })
            rl.DrawRectangle(bx, by,
                i32(f32(bw) * chip.reload_ratio), bh - strip_h,
                rl.Color{ 100, 158, 210, 80 })
        }
    }

    // Ammo count / state label (centred)
    if chip.ammo_text[0] != 0 {
        val_fs   := uis(18)
        val_cs   := cstring(&chip.ammo_text[0])
        vsz      := rl.MeasureTextEx(g_font, val_cs, val_fs, 1)
        text_col := COL_PARCH if !chip.is_reloading else COL_MUTED
        rl.DrawTextEx(g_font, val_cs,
            { bb.x + bb.width * 0.5 - vsz.x * 0.5,
              bb.y + bb.height * 0.5 - vsz.y * 0.5 - uis(2) },
            val_fs, 1, text_col)
    }

    // Weapon name (tiny, top-centre)
    if chip.wep_name[0] != 0 {
        name_fs := uis(8)
        name_cs := cstring(&chip.wep_name[0])
        nsz     := rl.MeasureTextEx(g_font, name_cs, name_fs, 0.4)
        rl.DrawTextEx(g_font, name_cs,
            { bb.x + bb.width * 0.5 - nsz.x * 0.5, bb.y + uis(3) },
            name_fs, 0.4, COL_MUTED)
    }

    // Border
    rl.DrawRectangleLinesEx({ bb.x, bb.y, bb.width, bb.height }, 1, COL_RULE)
}

// ── Inventory equip slot (armor) ──────────────────────────────────────────
// Draws a labelled row: "HEAD │ item name" with optional drop-target glow.

@(private = "file")
_draw_inv_slot :: proc(bb: clay.BoundingBox, slot: ^UICustomInvSlot) {
    rl.DrawRectangle(i32(bb.x), i32(bb.y), i32(bb.width), i32(bb.height),
        rl.Color{ 20, 16, 12, 240 })
    rl.DrawRectangleLinesEx({ bb.x, bb.y, bb.width, bb.height }, 1, COL_RULE)

    fs      := uis(18)
    label_y := bb.y + bb.height * 0.5 - fs * 0.5

    if slot.label[0] != 0 {
        rl.DrawTextEx(g_font, cstring(&slot.label[0]),
            { bb.x + uis(14), label_y }, fs, 1, COL_BRASS)
    }

    // Vertical divider between label column and item-name column
    div_x := bb.x + uis(122)
    rl.DrawLineEx({ div_x, bb.y + uis(8) }, { div_x, bb.y + bb.height - uis(8) }, 1, COL_RULE)

    if slot.item_name[0] != 0 {
        item_col := COL_PARCH if slot.has_item else rl.Color{ 95, 88, 68, 155 }
        rl.DrawTextEx(g_font, cstring(&slot.item_name[0]),
            { div_x + uis(14), label_y }, fs, 1, item_col)
    }

    if slot.is_target {
        rl.DrawRectangleLinesEx({ bb.x, bb.y, bb.width, bb.height }, 2,
            rl.Color{ 215, 175, 28, 200 })
    }
}

// ── Inventory weapon slot ─────────────────────────────────────────────────
// Draws a two-line box: type label on top, item name below (or 2H lock).

@(private = "file")
_draw_weapon_slot :: proc(bb: clay.BoundingBox, slot: ^UICustomWeaponSlot) {
    bg_col  := rl.Color{ 20, 16, 12, 240 } if !slot.is_blocked else rl.Color{ 14,  8,  8, 245 }
    bdr_col := COL_RULE                    if !slot.is_blocked else rl.Color{ 70, 28, 28, 200 }
    lbl_col := COL_BRASS                   if !slot.is_blocked else rl.Color{ 72, 52, 38, 180 }

    rl.DrawRectangle(i32(bb.x), i32(bb.y), i32(bb.width), i32(bb.height), bg_col)
    rl.DrawRectangleLinesEx({ bb.x, bb.y, bb.width, bb.height }, 1, bdr_col)

    lbl_fs := uis(16)
    if slot.type_label[0] != 0 {
        lsz := rl.MeasureTextEx(g_font, cstring(&slot.type_label[0]), lbl_fs, 1)
        rl.DrawTextEx(g_font, cstring(&slot.type_label[0]),
            { bb.x + bb.width * 0.5 - lsz.x * 0.5, bb.y + uis(7) }, lbl_fs, 1, lbl_col)
    }
    rl.DrawLineEx(
        { bb.x + uis(10), bb.y + uis(27) },
        { bb.x + bb.width - uis(10), bb.y + uis(27) }, 1, bdr_col)

    name_fs := uis(18)
    if slot.is_blocked {
        rl.DrawRectangle(i32(bb.x), i32(bb.y), i32(bb.width), i32(bb.height),
            rl.Color{ 60, 0, 0, 55 })
        lock_lbl := cstring("— 2H —")
        lksz := rl.MeasureTextEx(g_font, lock_lbl, name_fs, 1)
        rl.DrawTextEx(g_font, lock_lbl,
            { bb.x + bb.width * 0.5 - lksz.x * 0.5, bb.y + uis(34) },
            name_fs, 1, rl.Color{ 150, 50, 50, 210 })
    } else if slot.item_name[0] != 0 {
        item_col := COL_PARCH if slot.has_item else rl.Color{ 95, 88, 68, 155 }
        nsz := rl.MeasureTextEx(g_font, cstring(&slot.item_name[0]), name_fs, 1)
        rl.DrawTextEx(g_font, cstring(&slot.item_name[0]),
            { bb.x + bb.width * 0.5 - nsz.x * 0.5, bb.y + uis(34) },
            name_fs, 1, item_col)
    }

    if slot.is_target {
        rl.DrawRectangleLinesEx({ bb.x, bb.y, bb.width, bb.height }, 2,
            rl.Color{ 215, 175, 28, 200 })
    }
}

// ── Inventory ability slot ────────────────────────────────────────────────
// Draws an ability slot with rarity-tinted background and Active/Passive badge.

@(private = "file")
_draw_inv_ability :: proc(bb: clay.BoundingBox, slot: ^UICustomInvAbility) {
    rc     := slot.rarity_col
    bg_col  := rl.Color{ rc.r / 8, rc.g / 8, rc.b / 8, 240 } if slot.has_item \
               else rl.Color{ 20, 16, 12, 240 }
    bdr_col := rl.Color{ rc.r, rc.g, rc.b, 160 } if slot.has_item else COL_RULE

    rl.DrawRectangle(i32(bb.x), i32(bb.y), i32(bb.width), i32(bb.height), bg_col)
    rl.DrawRectangleLinesEx({ bb.x, bb.y, bb.width, bb.height }, 1, bdr_col)

    // Key label (Q / E / F / G) — top-left
    if slot.key_label[0] != 0 {
        rl.DrawTextEx(g_font, cstring(&slot.key_label[0]),
            { bb.x + uis(5), bb.y + uis(4) }, uis(13), 1, COL_BRASS)
    }

    // Ability name — below the key label
    name_col := COL_PARCH if slot.has_item else rl.Color{ 80, 74, 58, 130 }
    if slot.name[0] != 0 {
        rl.DrawTextEx(g_font, cstring(&slot.name[0]),
            { bb.x + uis(5), bb.y + uis(22) }, uis(11), 0.5, name_col)
    } else {
        rl.DrawTextEx(g_font, "empty",
            { bb.x + uis(5), bb.y + uis(22) }, uis(11), 0.5, name_col)
    }

    // Active / Passive badge (top-right corner)
    if slot.has_item {
        badge     := cstring("P") if slot.is_passive else cstring("A")
        badge_col := rl.Color{ 180, 150,  80, 210 } if slot.is_passive \
                     else rl.Color{ 100, 200, 255, 210 }
        bfs := uis(10)
        bsz := rl.MeasureTextEx(g_font, badge, bfs, 0.5)
        rl.DrawTextEx(g_font, badge,
            { bb.x + bb.width - bsz.x - uis(5), bb.y + uis(4) }, bfs, 0.5, badge_col)
    }

    if slot.is_target {
        rl.DrawRectangleLinesEx({ bb.x, bb.y, bb.width, bb.height }, 2,
            rl.Color{ 215, 175, 28, 200 })
    }
}
