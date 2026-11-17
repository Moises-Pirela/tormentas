package main

import clay "../clay"
import gfx  "gfx"
import      "core:math"
import      "core:strings"
import      "core:fmt"

clay_color :: #force_inline proc(c: clay.Color) -> gfx.Color {
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
                gfx.draw_rect_rounded({ bb.x, bb.y, bb.width, bb.height }, radius, 8, col)
            } else {
                gfx.draw_rect(
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
            if bw.left   > 0 { gfx.draw_rect(i32(bb.x),                              i32(bb.y + cr.topLeft),    i32(bw.left),   i32(bb.height - cr.topLeft    - cr.bottomLeft),  col) }
            if bw.right  > 0 { gfx.draw_rect(i32(bb.x + bb.width - f32(bw.right)),   i32(bb.y + cr.topRight),   i32(bw.right),  i32(bb.height - cr.topRight   - cr.bottomRight), col) }
            if bw.top    > 0 { gfx.draw_rect(i32(bb.x + cr.topLeft),                 i32(bb.y),                 i32(bb.width  - cr.topLeft    - cr.topRight),   i32(bw.top),    col) }
            if bw.bottom > 0 { gfx.draw_rect(i32(bb.x + cr.bottomLeft),              i32(bb.y + bb.height - f32(bw.bottom)), i32(bb.width - cr.bottomLeft - cr.bottomRight), i32(bw.bottom), col) }

        case .ScissorStart:
            gfx.scissor_begin(
                i32(math.round(bb.x)),
                i32(math.round(bb.y)),
                i32(math.round(bb.width)),
                i32(math.round(bb.height)))

        case .ScissorEnd:
            gfx.scissor_end()

        case .Text:
            cfg := cmd.renderData.text
            text := string(cfg.stringContents.chars[:cfg.stringContents.length])
            if len(text) == 0 { continue }
            fs := f32(cfg.fontSize)
            if fs <= 0 { fs = 12 }
            spacing := f32(cfg.letterSpacing)
            if spacing <= 0 { spacing = 0.5 }
            col := clay_color(cfg.textColor)
            fnt := clay_font(cfg.fontId)

            line_start := 0
            line_idx := 0
            for i := 0; i <= len(text); i += 1 {
                if i < len(text) && text[i] != '\n' { continue }
                line := text[line_start:i]
                line_cs := strings.clone_to_cstring(line, context.temp_allocator)
                gfx.draw_text(fnt, line_cs, { bb.x, bb.y + f32(line_idx) * fs }, fs, spacing, col)
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
            case .GoldChip:    _draw_gold_chip(bb, &cd.gold)
            case .None:
            }

        case .Image:
        case .None:
        }
    }
}

@(private = "file")
_draw_orb :: proc(bb: clay.BoundingBox, orb: ^UICustomOrb) {
    cx     := i32(math.round(bb.x + bb.width  * 0.5))
    cy     := i32(math.round(bb.y + bb.height * 0.5))
    radius := bb.width * 0.5

    gfx.draw_circle(cx, cy, radius, orb.bg_col)

    bx := i32(math.round(bb.x))
    bw := i32(math.ceil(bb.width))
    by := i32(math.round(bb.y))
    bh := i32(math.ceil(bb.height))
    tex: gfx.Texture
    if orb.portrait_idx == 1 { tex = g_hud_hp_icon }
    if tex.id != 0 {
        gfx.scissor_begin(bx, by, bw, bh)
        dst := gfx.Rect{ bb.x, bb.y, bb.width, bb.height }
        src := gfx.Rect{ 0, 0, f32(tex.width), f32(tex.height) }
        gfx.draw_texture_pro(tex, src, dst, {0, 0}, 0, gfx.Color{ 255, 255, 255, 200 })
        gfx.scissor_end()
    }

    fill_ratio := clamp(orb.fill_ratio, 0, 1)
    if fill_ratio > 0 {
        fill_h := bb.height * fill_ratio
        clip_y := i32(math.round(bb.y + bb.height - fill_h))
        clip_h := i32(math.ceil(fill_h))
        if clip_h > 0 {
            fill_col := orb.fill_col
            fill_col.a = 185
            gfx.scissor_begin(i32(math.round(bb.x)), clip_y, i32(math.ceil(bb.width)), clip_h)
            gfx.draw_circle(cx, cy, radius - 1, fill_col)
            gfx.scissor_end()
        }
    }

    if orb.shield_ratio > 0 {
        sr         := clamp(orb.shield_ratio, 0, 1)
        ring_inner := radius + 2
        ring_outer := radius + 5
        end_angle  := f32(-90) + 360 * sr
        gfx.draw_ring(
            { f32(cx), f32(cy) },
            ring_inner, ring_outer,
            -90, end_angle, 24,
            COL_SHIELD)
    }

    if g_hud_orb_frame.id != 0 {
        frame_sz := bb.width * 1.1
        fdst     := gfx.Rect{
            f32(cx) - frame_sz * 0.5,
            f32(cy) - frame_sz * 0.5,
            frame_sz, frame_sz,
        }
        fsrc := gfx.Rect{ 0, 0, f32(g_hud_orb_frame.width), f32(g_hud_orb_frame.height) }
        gfx.draw_texture_pro(g_hud_orb_frame, fsrc, fdst, {0, 0}, 0, gfx.WHITE)
    } else {
        gfx.draw_circle_lines(cx, cy, radius,     gfx.Color{ 60,  46, 28, 180 })
        gfx.draw_circle_lines(cx, cy, radius - 1, gfx.Color{ 40,  30, 16, 120 })
    }

    if orb.value_text[0] != 0 {
        val_cs := cstring(&orb.value_text[0])
        val_fs := uis(13)
        vsz    := gfx.measure_text(g_font_body, val_cs, val_fs, 0.5)
        gfx.draw_text(g_font_body, val_cs,
            { f32(cx) - vsz.x * 0.5, f32(cy) + radius * 0.4 - vsz.y * 0.5 },
            val_fs, 0.5, COL_PARCH)
    }
}

@(private = "file")
_draw_ability_chip :: proc(bb: clay.BoundingBox, chip: ^UICustomAbility) {
    cx     := i32(math.round(bb.x + bb.width  * 0.5))
    cy     := i32(math.round(bb.y + bb.height * 0.5))
    radius := bb.width * 0.5 - 1

    bg_col := gfx.Color{ 10, 7, 5, 220 } if chip.has_ability else gfx.Color{ 6, 5, 3, 160 }
    gfx.draw_circle(cx, cy, radius, bg_col)

    if chip.has_ability && chip.cd_ratio > 0 {
        cd_h := i32(math.ceil(bb.height * clamp(chip.cd_ratio, 0, 1)))
        if cd_h > 0 {
            gfx.scissor_begin(
                i32(math.round(bb.x)), i32(math.round(bb.y)),
                i32(math.ceil(bb.width)), cd_h)
            gfx.draw_circle(cx, cy, radius, gfx.Color{ 0, 0, 0, 165 })
            gfx.scissor_end()
        }
    }

    if chip.charge_glow { gfx.draw_circle(cx, cy, radius, gfx.Color{ 200,  40,  20, 70 }) }
    if chip.dance_glow  { gfx.draw_circle(cx, cy, radius, gfx.Color{  20, 200, 200, 65 }) }

    ready   := chip.has_ability && chip.cd_ratio <= 0
    glow    := chip.charge_glow || chip.dance_glow
    bdr_col := COL_BRASS if (ready || glow) else COL_RULE

    gfx.draw_circle_lines(cx, cy, radius,     bdr_col)
    gfx.draw_circle_lines(cx, cy, radius - 1, gfx.Color{ 30, 22, 10, 100 })

    key_col: gfx.Color
    switch {
    case glow:             key_col = COL_PARCH
    case ready:            key_col = COL_PARCH
    case chip.has_ability: key_col = COL_MUTED
    case:                  key_col = gfx.Color{ 55, 50, 40, 140 }
    }

    if chip.key_label[0] != 0 {
        key_cs := cstring(&chip.key_label[0])
        key_fs := uis(14)
        ksz    := gfx.measure_text(g_font_body, key_cs, key_fs, 0.5)
        gfx.draw_text(g_font_body, key_cs,
            { f32(cx) - ksz.x * 0.5, bb.y + uis(4) },
            key_fs, 0.5, key_col)
    }

    if chip.has_ability && chip.name_label[0] != 0 {
        name_fs := uis(9)
        name_cs := cstring(&chip.name_label[0])
        nsz     := gfx.measure_text(g_font_body, name_cs, name_fs, 0.5)
        gfx.draw_text(g_font_body, name_cs,
            { f32(cx) - nsz.x * 0.5, bb.y + bb.height - uis(13) },
            name_fs, 0.5, key_col)
    }
}

@(private = "file")
_draw_ammo_chip :: proc(bb: clay.BoundingBox, chip: ^UICustomAmmo) {
    bx := i32(bb.x); by := i32(bb.y)
    bw := i32(bb.width); bh := i32(bb.height)

    gfx.draw_rect(bx, by, bw, bh, gfx.Color{ 10, 7, 5, 230 })

    strip_h := max(i32(uis(4)), 2)

    if chip.is_melee {
        val_cs   := cstring(&chip.ammo_text[0])
        val_fs   := uis(20)
        vsz      := gfx.measure_text(g_font_body, val_cs, val_fs, 0.5)
        gfx.draw_text(g_font_body, val_cs,
            { bb.x + bb.width*0.5 - vsz.x*0.5, bb.y + bb.height*0.5 - vsz.y*0.5 },
            val_fs, 0.5, COL_MUTED)
    } else {
        strip_y := by + bh - strip_h
        gfx.draw_rect(bx, strip_y, bw, strip_h, gfx.Color{ 40, 34, 24, 255 })
        if chip.is_reloading {
            gfx.draw_rect(bx, strip_y, i32(f32(bw) * chip.reload_ratio), strip_h, gfx.Color{ 150, 170, 190, 255 })
        } else if chip.ammo_ratio > 0 {
            ammo_col := COL_CRIMSON if chip.ammo_ratio <= 0.334 else gfx.Color{ 192, 152, 44, 255 }
            gfx.draw_rect(bx, strip_y, i32(f32(bw) * chip.ammo_ratio), strip_h, ammo_col)
        }

        roller_h := bh - strip_h - i32(uis(2))

        if chip.ammo_text[0] != 0 {
            n_chars := 0
            for chip.ammo_text[n_chars] != 0 && n_chars < 7 { n_chars += 1 }

            n_slots := max(n_chars, 2)
            slot_w  := f32(bw) / f32(n_slots)
            dig_fs  := uis(24)
            text_col := COL_PARCH

            for s in 0..<n_slots {
                sx := bb.x + f32(s) * slot_w

                gfx.draw_rect(i32(sx) + 1, by, i32(slot_w) - 1, roller_h,
                    gfx.Color{ 6, 4, 2, 255 })

                gfx.draw_rect(i32(sx), by,              i32(slot_w), 1, gfx.Color{ 90, 68, 28, 180 })
                gfx.draw_rect(i32(sx), by + roller_h - 1, i32(slot_w), 1, gfx.Color{ 90, 68, 28, 180 })

                char_idx := s - (n_slots - n_chars)
                dig_buf: [2]u8
                if char_idx >= 0 {
                    dig_buf[0] = chip.ammo_text[char_idx]
                } else {
                    dig_buf[0] = '0'
                }
                dig_buf[1] = 0
                dig_cs := cstring(&dig_buf[0])
                dsz    := gfx.measure_text(g_font, dig_cs, dig_fs, 0)
                gfx.draw_text(g_font, dig_cs,
                    { sx + slot_w*0.5 - dsz.x*0.5, bb.y + f32(roller_h)*0.5 - dsz.y*0.5 },
                    dig_fs, 0, text_col)
            }
        }
    }

    if chip.wep_name[0] != 0 && !chip.is_melee {
        name_fs := uis(7)
        name_cs := cstring(&chip.wep_name[0])
        nsz     := gfx.measure_text(g_font_body, name_cs, name_fs, 0.4)
        gfx.draw_text(g_font_body, name_cs,
            { bb.x + bb.width*0.5 - nsz.x*0.5,
              bb.y + bb.height - f32(strip_h) - name_fs - uis(1) },
            name_fs, 0.4, COL_MUTED)
    }

    gfx.draw_rect_lines({ bb.x, bb.y, bb.width, bb.height }, 1, COL_RULE)
}

@(private = "file")
_draw_gold_chip :: proc(bb: clay.BoundingBox, chip: ^UICustomGold) {
    bx := i32(bb.x); by := i32(bb.y)
    bw := i32(bb.width); bh := i32(bb.height)

    gfx.draw_rect(bx, by, bw, bh, gfx.Color{ 12, 9, 4, 230 })
    gfx.draw_rect_lines({ bb.x, bb.y, bb.width, bb.height }, 1.5, COL_BRASS)

    coin_r := f32(uis(4))
    coin_y := bb.y + uis(7)
    cx     := bb.x + bb.width * 0.5
    gfx.draw_circle(i32(cx), i32(coin_y), coin_r,     gfx.Color{ 200, 160, 50, 220 })
    gfx.draw_circle_lines(i32(cx), i32(coin_y), coin_r, gfx.Color{ 240, 210, 100, 200 })

    val_cs := fmt.ctprintf("%d", chip.gold_val)
    val_fs := uis(16)
    vsz    := gfx.measure_text(g_font, val_cs, val_fs, 0.5)
    gfx.draw_text(g_font, val_cs,
        { cx - vsz.x*0.5, bb.y + bb.height*0.5 - vsz.y*0.5 + uis(2) },
        val_fs, 0.5, COL_BRASS)
}

@(private = "file")
_draw_inv_slot :: proc(bb: clay.BoundingBox, slot: ^UICustomInvSlot) {
    gfx.draw_rect(i32(bb.x), i32(bb.y), i32(bb.width), i32(bb.height),
        gfx.Color{ 20, 16, 12, 240 })
    gfx.draw_rect_lines({ bb.x, bb.y, bb.width, bb.height }, 1, COL_RULE)

    fs      := uis(18)
    label_y := bb.y + bb.height * 0.5 - fs * 0.5

    if slot.label[0] != 0 {
        gfx.draw_text(g_font, cstring(&slot.label[0]),
            { bb.x + uis(14), label_y }, fs, 1, COL_BRASS)
    }

    div_x := bb.x + uis(122)
    gfx.draw_line_ex({ div_x, bb.y + uis(8) }, { div_x, bb.y + bb.height - uis(8) }, 1, COL_RULE)

    if slot.item_name[0] != 0 {
        item_col := COL_PARCH if slot.has_item else gfx.Color{ 95, 88, 68, 155 }
        gfx.draw_text(g_font, cstring(&slot.item_name[0]),
            { div_x + uis(14), label_y }, fs, 1, item_col)
    }

    if slot.is_target {
        glow := gfx.Color{ 215, 175, 28, 200 } if !slot.has_item \
                else gfx.Color{ 235, 120, 20, 200 }
        gfx.draw_rect_lines({ bb.x, bb.y, bb.width, bb.height }, 2, glow)
    }
}

@(private = "file")
_draw_weapon_slot :: proc(bb: clay.BoundingBox, slot: ^UICustomWeaponSlot) {
    bg_col  := gfx.Color{ 20, 16, 12, 240 } if !slot.is_blocked && !slot.class_locked else gfx.Color{ 14,  8,  8, 245 }
    bdr_col := COL_RULE                    if !slot.is_blocked && !slot.class_locked else gfx.Color{ 70, 28, 28, 200 }
    lbl_col := COL_BRASS                   if !slot.is_blocked && !slot.class_locked else gfx.Color{ 72, 52, 38, 180 }

    gfx.draw_rect(i32(bb.x), i32(bb.y), i32(bb.width), i32(bb.height), bg_col)
    gfx.draw_rect_lines({ bb.x, bb.y, bb.width, bb.height }, 1, bdr_col)

    lbl_fs := uis(16)
    if slot.type_label[0] != 0 {
        lsz := gfx.measure_text(g_font, cstring(&slot.type_label[0]), lbl_fs, 1)
        gfx.draw_text(g_font, cstring(&slot.type_label[0]),
            { bb.x + bb.width * 0.5 - lsz.x * 0.5, bb.y + uis(7) }, lbl_fs, 1, lbl_col)
    }
    gfx.draw_line_ex(
        { bb.x + uis(10), bb.y + uis(27) },
        { bb.x + bb.width - uis(10), bb.y + uis(27) }, 1, bdr_col)

    name_fs := uis(18)
    if slot.is_blocked || slot.class_locked {
        gfx.draw_rect(i32(bb.x), i32(bb.y), i32(bb.width), i32(bb.height),
            gfx.Color{ 60, 0, 0, 55 })
        lock_lbl := cstring("— CLASS —") if slot.class_locked else cstring("— 2H —")
        lksz := gfx.measure_text(g_font, lock_lbl, name_fs, 1)
        gfx.draw_text(g_font, lock_lbl,
            { bb.x + bb.width * 0.5 - lksz.x * 0.5, bb.y + uis(34) },
            name_fs, 1, gfx.Color{ 150, 50, 50, 210 })
    } else if slot.item_name[0] != 0 {
        item_col := COL_PARCH if slot.has_item else gfx.Color{ 95, 88, 68, 155 }
        nsz := gfx.measure_text(g_font, cstring(&slot.item_name[0]), name_fs, 1)
        gfx.draw_text(g_font, cstring(&slot.item_name[0]),
            { bb.x + bb.width * 0.5 - nsz.x * 0.5, bb.y + uis(34) },
            name_fs, 1, item_col)
    }

    if slot.is_target {
        glow := gfx.Color{ 215, 175, 28, 200 } if !slot.has_item \
                else gfx.Color{ 235, 120, 20, 200 }
        gfx.draw_rect_lines({ bb.x, bb.y, bb.width, bb.height }, 2, glow)
    }
}

@(private = "file")
_draw_inv_ability :: proc(bb: clay.BoundingBox, slot: ^UICustomInvAbility) {
    rc     := slot.rarity_col
    bg_col  := gfx.Color{ rc.r / 8, rc.g / 8, rc.b / 8, 240 } if slot.has_item \
               else gfx.Color{ 20, 16, 12, 240 }
    bdr_col := gfx.Color{ rc.r, rc.g, rc.b, 160 } if slot.has_item else COL_RULE

    gfx.draw_rect(i32(bb.x), i32(bb.y), i32(bb.width), i32(bb.height), bg_col)
    gfx.draw_rect_lines({ bb.x, bb.y, bb.width, bb.height }, 1, bdr_col)

    if slot.key_label[0] != 0 {
        gfx.draw_text(g_font, cstring(&slot.key_label[0]),
            { bb.x + uis(5), bb.y + uis(4) }, uis(13), 1, COL_BRASS)
    }

    name_col := COL_PARCH if slot.has_item else gfx.Color{ 80, 74, 58, 130 }
    if slot.name[0] != 0 {
        gfx.draw_text(g_font, cstring(&slot.name[0]),
            { bb.x + uis(5), bb.y + uis(22) }, uis(11), 0.5, name_col)
    } else {
        gfx.draw_text(g_font, "empty",
            { bb.x + uis(5), bb.y + uis(22) }, uis(11), 0.5, name_col)
    }

    if slot.has_item {
        right_x := bb.x + bb.width - uis(5)

        if slot.level > 0 {
            lv_buf: [8]u8
            lv_str := fmt.bprintf(lv_buf[:], "Lv%d", slot.level)
            lv_buf[len(lv_str)] = 0
            lfs  := uis(9)
            lsz  := gfx.measure_text(g_font, cstring(&lv_buf[0]), lfs, 0.5)
            gfx.draw_text(g_font, cstring(&lv_buf[0]),
                { right_x - lsz.x, bb.y + bb.height - lsz.y - uis(4) },
                lfs, 0.5, gfx.Color{ 200, 175, 60, 200 })
            right_x -= lsz.x + uis(4)
        }

        if slot.trait_col.a > 0 {
            dot_r := uis(4)
            dot_x := bb.x + bb.width - dot_r*2 - uis(5)
            dot_y := bb.y + uis(4) + dot_r
            gfx.draw_circle(i32(dot_x + dot_r), i32(dot_y), dot_r, slot.trait_col)
        }
    }

    if slot.is_target {
        glow := gfx.Color{ 215, 175, 28, 200 } if !slot.has_item \
                else gfx.Color{ 235, 120, 20, 200 }
        gfx.draw_rect_lines({ bb.x, bb.y, bb.width, bb.height }, 2, glow)
    }
}
