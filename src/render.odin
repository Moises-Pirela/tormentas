package main

// =============================================================================
// RENDER — world draw procs + Clay HUD lifecycle
//
// World rendering:  draw_player, draw_floor
// Text HUD:         draw_hud  (position, corruption, controls)
// Clay HUD:         draw_hud_clay  (HP + Energy bars)
//   └ init_clay / shutdown_clay / update_clay_input  (called from main)
//
// All draw procs read from ECS; none write back.
// Clay command execution lives in clay_renderer.odin.
// =============================================================================

import rl       "vendor:raylib"
import          "core:math"
import          "core:c"
import          "core:fmt"
import          "core:strings"
import          "base:runtime"
import cw       "clockwork"
import clay     "../clay"

// g_font and g_ui_scale are package-visible so editor.odin and other HUD files
// can draw text without duplicating the helpers.
g_font: rl.Font

@(private = "file")
FONT_PATH :: cstring("data/fonts/cinzel.ttf")

// g_ui_scale is recomputed every frame in update_clay_input.
// All HUD draw procs call uis() so they stay readable at any resolution.
g_ui_scale: f32 = 1.0

uis :: proc(base: f32) -> f32 { return base * g_ui_scale }

// g_levelup_flash counts down from LEVELUP_FLASH_TIME to 0 after a level-up.
// Written by damage_system; decremented in main's game loop; read by draw_levelup_flash.
g_levelup_flash: f32

// ── Floating damage numbers ───────────────────────────────────────────────
// Spawned by push_dmg_number (called from damage_system).
// Drawn in world space inside BeginMode2D via update_draw_dmg_numbers.
MAX_DMGNUM   :: 48
DMGNUM_LIFE  :: f32(1.3)
DMGNUM_SPEED :: f32(30)    // world pixels per second (upward = decreasing y)

DmgNum :: struct {
    x, y:     f32,
    value:    f32,
    lifetime: f32,
    is_enemy: bool,   // false = player took the hit (red tint)
    is_crit:  bool,   // crit: larger text, white→gold fade
}

g_dmgnums: [MAX_DMGNUM]DmgNum

push_dmg_number :: proc(x, y, value: f32, is_enemy: bool, is_crit: bool = false) {
    if value <= 0 { return }
    best := 0
    for i in 1..<MAX_DMGNUM {
        if g_dmgnums[i].lifetime <= 0 { best = i; break }
        if g_dmgnums[i].lifetime < g_dmgnums[best].lifetime { best = i }
    }
    iso := world_to_iso_xy(x, y)
    g_dmgnums[best] = DmgNum{
        x        = iso.x,
        y        = iso.y,
        value    = value,
        lifetime = DMGNUM_LIFE,
        is_enemy = is_enemy,
        is_crit  = is_crit,
    }
}

// update_draw_dmg_numbers ticks lifetimes, floats numbers upward, and draws them.
// Call inside BeginMode2D each frame.
update_draw_dmg_numbers :: proc(dt: f32) {
    for i in 0..<MAX_DMGNUM {
        n := &g_dmgnums[i]
        if n.lifetime <= 0 { continue }
        n.lifetime -= dt
        n.y        -= DMGNUM_SPEED * dt
        if n.lifetime <= 0 { continue }

        frac  := clamp(n.lifetime / DMGNUM_LIFE, 0, 1)
        alpha := u8(frac * 255)

        col: rl.Color
        fs:  f32
        if n.is_crit {
            // Crits: white → gold as they fade. Larger font.
            fs = 22
            white := clamp(frac * 3.0 - 1.5, 0, 1)   // white in the first half
            col = rl.Color{255, u8(160 + white * 95), u8(white * 200), alpha}
        } else if n.is_enemy {
            col = rl.Color{255, 220, 60, alpha}        // gold
            fs  = 15
        } else {
            col = rl.Color{255, 70, 70, alpha}         // red (player hit)
            fs  = 15
        }

        num_buf: [16]u8
        num_s := fmt.bprintf(num_buf[:15], "%.0f", n.value)
        num_buf[len(num_s)] = 0

        tsz := rl.MeasureTextEx(g_font, cstring(&num_buf[0]), fs, 0.5)
        rl.DrawTextEx(g_font, cstring(&num_buf[0]),
            { n.x - tsz.x*0.5, n.y - tsz.y*0.5 }, fs, 0.5, col)
    }
}


draw_extraction_zones :: proc(w: ^cw.World) {
    if g_hub_active { return }   

    time := f32(rl.GetTime())

    ids := cw.world_query(w, cw.query_mask(.Extraction, .Transform))
    defer delete(ids)

    pid := w.player_id

    for eid in ids {
        ext := cw.world_get_extraction(w, eid)
        if ext.activated { continue }

        pos := cw.world_get_transform(w, eid).position
        cx  := pos[0]
        cy  := pos[1]
        r   := ext.interact_radius

        center := rl.Vector2{ cx, cy }
        draw_world_circle(center, r, rl.Color{ 55, 220, 85, 18 })

        pulse := f32(0.5) + f32(0.5) * math.sin(time * 2.6)
        ring_r   := r * (1.0 + 0.04 * pulse)
        ring_col := rl.Color{ 55, 220, 85, u8(80 + i32(pulse * 60)) }
        draw_world_circle_lines(center, ring_r, ring_col)

        draw_world_circle_lines(center, r * 0.72, rl.Color{ 55, 220, 85, 45 })

        SPOKES :: 3
        for i in 0..<SPOKES {
            angle := time * 0.7 + f32(i) * (f32(math.TAU) / SPOKES)
            ep := rl.Vector2{
                cx + math.cos(angle) * r * 0.88,
                cy + math.sin(angle) * r * 0.88,
            }
            draw_world_line(center, ep, 1.5, rl.Color{ 55, 220, 85, 55 })
        }

        cs := f32(10)
        draw_world_line({ cx - cs, cy }, { cx + cs, cy }, 2.0, rl.Color{ 55, 220, 85, 255 })
        draw_world_line({ cx, cy - cs }, { cx, cy + cs }, 2.0, rl.Color{ 55, 220, 85, 255 })

        lbl_fs  := f32(14)
        lbl     := t(.HUD_EXTRACT)
        lbl_sz  := rl.MeasureTextEx(g_font, lbl, lbl_fs, 0.5)
        lbl_blink := u8(180 + i32(pulse * 60))
        center_iso := world_to_iso_v(center)
        rl.DrawTextEx(g_font, lbl,
            { center_iso.x - lbl_sz.x * 0.5, center_iso.y - r * 0.55 - lbl_sz.y - 6 },
            lbl_fs, 0.5,
            rl.Color{ 100, 240, 110, lbl_blink })

        if !cw.world_is_valid(w, pid) { continue }
        if !cw.world_has_component(w, pid, .Transform) { continue }
        pt  := cw.world_get_transform(w, pid).position
        dx  := pt[0] - cx
        dy  := pt[1] - cy
        in_zone := (dx*dx + dy*dy) <= r*r

        if ext.timer > 0 && in_zone {
            progress  := clamp(ext.timer / ext.activate_time, 0, 1)
            arc_r     := r * 0.56
            arc_steps := 48
            arc_span  := progress * f32(math.TAU)
            arc_start := f32(-math.PI) * 0.5

            for i in 0..<arc_steps {
                t0 := arc_start + f32(i)   / f32(arc_steps) * arc_span
                t1 := arc_start + f32(i+1) / f32(arc_steps) * arc_span
                p0 := rl.Vector2{ cx + math.cos(t0) * arc_r, cy + math.sin(t0) * arc_r }
                p1 := rl.Vector2{ cx + math.cos(t1) * arc_r, cy + math.sin(t1) * arc_r }
                a  := u8(160 + i32(progress * 95))
                draw_world_line(p0, p1, 3.0, rl.Color{ 80, 245, 100, a })
            }

            secs_left := ext.activate_time - ext.timer
            secs_buf: [16]u8
            secs_s := fmt.bprintf(secs_buf[:15], "%.0f", math.ceil(secs_left))
            secs_buf[len(secs_s)] = 0
            s_fs  := f32(18)
            s_sz  := rl.MeasureTextEx(g_font, cstring(&secs_buf[0]), s_fs, 0.5)
            rl.DrawTextEx(g_font, cstring(&secs_buf[0]),
                { center_iso.x - s_sz.x * 0.5, center_iso.y - s_sz.y * 0.5 },
                s_fs, 0.5,
                rl.Color{ 130, 255, 140, 230 })
        }
    }
}

// draw_loot_filter_hud shows the current loot filter level in the top-left corner.
// Only visible when the filter is active (non-Normal). Hold ALT to see filtered items.
draw_loot_filter_hud :: proc() {
    if g_loot_filter_rarity == .Normal { return }

    filter_labels := [cw.ItemRarity]cstring{
        .Normal    = t(.HUD_FILTER_ALL),
        .Rare      = t(.HUD_FILTER_RARE),
        .Epic      = t(.HUD_FILTER_EPIC),
        .Legendary = t(.HUD_FILTER_LEGENDARY),
        .Unique    = t(.HUD_FILTER_UNIQUE),
    }
    lbl := filter_labels[g_loot_filter_rarity]

    sw  := f32(rl.GetScreenWidth())
    _   = sw
    fs  := uis(9)
    prefix    := t(.HUD_LOOT_FILTER)
    psz       := rl.MeasureTextEx(g_font, prefix, fs, 0.5)
    lsz       := rl.MeasureTextEx(g_font, lbl, fs, 0.5)
    total_w   := psz.x + lsz.x + uis(16)
    total_h   := fs + uis(10)
    bx        := i32(uis(12))
    by        := i32(uis(12))

    rl.DrawRectangle(bx, by, i32(total_w), i32(total_h), rl.Color{ 8, 6, 4, 210 })
    rl.DrawRectangleLinesEx({ f32(bx), f32(by), total_w, total_h }, 1, COL_RULE)
    rl.DrawTextEx(g_font, prefix,
        { f32(bx) + uis(8), f32(by) + uis(5) }, fs, 0.5, COL_MUTED)
    rc := rarity_color(g_loot_filter_rarity)
    rl.DrawTextEx(g_font, lbl,
        { f32(bx) + uis(8) + psz.x, f32(by) + uis(5) }, fs, 0.5,
        rl.Color{ rc.r, rc.g, rc.b, 230 })
}

draw_raid_timer :: proc() {
    if g_raid_timer <= 0 { return }

    mins := int(g_raid_timer) / 60
    secs := int(g_raid_timer) % 60

    buf: [32]u8
    s   := fmt.bprintf(buf[:31], "%d:%02d", mins, secs)
    buf[len(s)] = 0

    col: rl.Color
    if g_raid_timer < 120 {
        flash := f32(0.5) + f32(0.5) * math.sin(f32(rl.GetTime()) * 5.0)
        col = rl.Color{ 255, u8(80 + i32(flash * 80)), 60, 255 }
    } else if g_raid_timer < 300 {
        col = rl.Color{ 240, 180, 60, 255 }   // orange under 5 min
    } else {
        col = rl.Color{ 170, 235, 145, 220 }  // normal green
    }

    sw := f32(rl.GetScreenWidth())
    fs := uis(15)

    icon := t(.HUD_RAID_TIMER)
    lbl  := cstring(&buf[0])

    icon_sz := rl.MeasureTextEx(g_font, icon, uis(8), 0.5)
    lbl_sz  := rl.MeasureTextEx(g_font, lbl, fs, 0.5)

    x := sw - max(icon_sz.x, lbl_sz.x) - uis(20)
    rl.DrawTextEx(g_font, icon, { x, uis(12) }, uis(8), 0.5, rl.Color{ 150, 200, 130, 180 })
    rl.DrawTextEx(g_font, lbl,  { x, uis(23) }, fs, 0.5, col)
}

draw_boss_warning :: proc() {
    if (g_hub_active) {return}
    if g_boss_warning_timer <= 0 { return }

    tt    := f32(rl.GetTime())
    pulse := f32(0.5) + f32(0.5) * math.sin(tt * 6.0)
    sw    := f32(rl.GetScreenWidth())
    sh    := f32(rl.GetScreenHeight())

    overlay_alpha := u8(35 + i32(pulse * 35))
    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{ 180, 0, 0, overlay_alpha })

    warn_fs := uis(22)
    warn1   := t(.HUD_WARNING)
    warn2   := t(.HUD_BOSS_APPROACHES)
    w1sz    := rl.MeasureTextEx(g_font, warn1, warn_fs, 1)
    w2sz    := rl.MeasureTextEx(g_font, warn2, warn_fs * 0.65, 1)
    cy      := sh * 0.5 - uis(40)

    text_alpha := u8(160 + i32(pulse * 95))
    rl.DrawTextEx(g_font, warn1,
        { sw * 0.5 - w1sz.x * 0.5, cy },
        warn_fs, 1, rl.Color{ 255, 60, 60, text_alpha })
    rl.DrawTextEx(g_font, warn2,
        { sw * 0.5 - w2sz.x * 0.5, cy + warn_fs + uis(4) },
        warn_fs * 0.65, 1, rl.Color{ 220, 100, 100, text_alpha })

    secs_left := int(g_boss_warning_timer) + 1
    buf: [16]u8
    s := fmt.bprintf(buf[:15], "%ds", secs_left)
    buf[len(s)] = 0
    cd_fs := uis(14)
    cd_sz := rl.MeasureTextEx(g_font, cstring(&buf[0]), cd_fs, 0.5)
    rl.DrawTextEx(g_font, cstring(&buf[0]),
        { sw * 0.5 - cd_sz.x * 0.5, cy + warn_fs + uis(4) + warn_fs * 0.65 + uis(6) },
        cd_fs, 0.5, rl.Color{ 200, 140, 140, u8(180 + i32(pulse * 75)) })
}

// g_inspected_entity is set each frame by update_entity_hover to whichever
// non-player entity the mouse is currently over (INVALID_ENTITY if none).
g_inspected_entity: int = cw.INVALID_ENTITY

// update_entity_hover hit-tests non-player entities in world space and stores
// the nearest one under the cursor in g_inspected_entity.
// Call once per rendered frame, before draw_entity_inspect_hud.
update_entity_hover :: proc(w: ^cw.World) {
    if g_playing_state != .Gameplay || ui_any() {
        g_inspected_entity = cw.INVALID_ENTITY
        return
    }

    mp         := screen_to_world_cartesian(rl.GetMousePosition())
    best_dist2 := f32(1e30)
    g_inspected_entity = cw.INVALID_ENTITY

    ids := cw.world_query(w, cw.query_mask(.Transform, .Health), context.temp_allocator)
    for id in ids {
        if is_player_entity(w, id) { continue }
        if is_fog_hidden(w, id)    { continue }

        tr  := cw.world_get_transform(w, id)
        dx  := tr.position[0] - mp.x
        dy  := tr.position[1] - mp.y
        d2  := dx*dx + dy*dy

        hit_r := f32(28)
        if cw.world_has_component(w, id, .Collider) {
            hit_r = max(cw.world_get_collider(w, id).radius, 20)
        }
        if d2 < hit_r * hit_r && d2 < best_dist2 {
            best_dist2         = d2
            g_inspected_entity = id
        }
    }
}

// draw_entity_inspect_hud draws a centred top-of-screen panel for the hovered
// entity (if any), falling back to the boss when nothing is hovered.
// Replaces the old draw_boss_hud; call it in the same place.
draw_entity_inspect_hud :: proc(w: ^cw.World) {
    // Stale boss cleanup (mirrors old draw_boss_hud).
    if g_boss_id != cw.INVALID_ENTITY && !cw.world_is_valid(w, g_boss_id) {
        g_boss_id = cw.INVALID_ENTITY
    }

    // Priority: hovered entity → boss → nothing.
    show_id := g_inspected_entity
    if show_id == cw.INVALID_ENTITY || !cw.world_is_valid(w, show_id) {
        show_id = g_boss_id
    }
    if show_id == cw.INVALID_ENTITY                  { return }
    if !cw.world_is_valid(w, show_id)                { return }
    if !cw.world_has_component(w, show_id, .Health)  { return }

    h    := cw.world_get_health(w, show_id)
    if h.max <= 0 { return }
    frac := clamp(h.current / h.max, 0, 1)

    sw := f32(rl.GetScreenWidth())
    bw := sw * 0.42
    bh := uis(14)
    bx := sw * 0.5 - bw * 0.5
    by := uis(14)

    // ── Background + fill ─────────────────────────────────────────────────────
    rl.DrawRectangleRec({ bx - 2, by - 2, bw + 4, bh + 4 }, rl.Color{  8,  4,  4, 220 })
    rl.DrawRectangleRec({ bx, by, bw, bh },                  rl.Color{ 45, 12, 12, 200 })
    if frac > 0 {
        fill_col: rl.Color
        if frac > 0.5 {
            fill_col = rl.Color{ 200, 40, 40, 230 }
        } else if frac > 0.25 {
            fill_col = rl.Color{ 220, 90, 30, 230 }
        } else {
            t        := f32(0.5) + f32(0.5) * math.sin(f32(rl.GetTime()) * 8.0)
            fill_col = rl.Color{ 255, u8(30 + i32(t * 40)), 20, 255 }
        }
        rl.DrawRectangleRec({ bx, by, bw * frac, bh }, fill_col)
    }
    rl.DrawRectangleLinesEx({ bx - 2, by - 2, bw + 4, bh + 4 }, 1, rl.Color{ 140, 40, 40, 200 })

    // ── HP numbers (right-aligned inside bar) ─────────────────────────────────
    hp_str := rl.TextFormat("%d / %d", i32(h.current), i32(h.max))
    hp_fs  := uis(8)
    hp_sz  := rl.MeasureTextEx(g_font, hp_str, hp_fs, 0.4)
    rl.DrawTextEx(g_font, hp_str,
        { bx + bw - hp_sz.x - uis(3), by + (bh - hp_fs) * 0.5 },
        hp_fs, 0.4, rl.Color{ 220, 200, 200, 130 })

    // ── Entity name ───────────────────────────────────────────────────────────
    name_lbl := cstring("ENEMY")
    if cw.world_has_component(w, show_id, .RenderConfig) {
        rc := cw.world_get_render_config(w, show_id)
        cs := loc_lookup(cw.render_config_name_cstr(rc))
        if cs != nil && len(cs) > 0 { name_lbl = cs }
    }
    name_fs := uis(9)
    name_sz := rl.MeasureTextEx(g_font, name_lbl, name_fs, 0.5)
    name_y  := by + bh + uis(3)
    rl.DrawTextEx(g_font, name_lbl,
        { sw * 0.5 - name_sz.x * 0.5, name_y },
        name_fs, 0.5, rl.Color{ 200, 120, 120, 200 })

    // ── Mutation badges (centered row below name) ─────────────────────────────
    if cw.world_has_component(w, show_id, .MutationContainer) {
        mc := cw.world_get_mutation(w, show_id)

        // First pass — collect valid mutations and measure total row width.
        badge_fs  := uis(8)
        dot_r     := f32(3.5)
        gap       := uis(12)
        b_mt      : [cw.MAX_MUTATION_SLOTS]cw.MutationType
        b_name    : [cw.MAX_MUTATION_SLOTS]cstring
        b_sz      : [cw.MAX_MUTATION_SLOTS]rl.Vector2
        n_b       := 0
        total_w   := f32(0)

        for i in 0..<mc.entity_count {
            meid := mc.entities[i]
            if !cw.world_is_valid(w, meid)            { continue }
            if !cw.world_has_component(w, meid, .Mut) { continue }
            mt   := cw.world_get_mut(w, meid).type_id
            name := mutation_short_name(mt)
            sz   := rl.MeasureTextEx(g_font, name, badge_fs, 0.4)
            b_mt[n_b]   = mt
            b_name[n_b] = name
            b_sz[n_b]   = sz
            item_w      := dot_r * 2 + uis(5) + sz.x
            total_w     += item_w + (gap if n_b > 0 else 0)
            n_b         += 1
        }

        if n_b > 0 {
            badge_y  := name_y + name_fs + uis(4)
            x        := sw * 0.5 - total_w * 0.5

            for i in 0..<n_b {
                col := mutation_visual_color(b_mt[i])
                rl.DrawCircleV(
                    { x + dot_r, badge_y + badge_fs * 0.5 },
                    dot_r, rl.Color{ col.r, col.g, col.b, 230 })
                rl.DrawTextEx(g_font, b_name[i],
                    { x + dot_r * 2 + uis(5), badge_y },
                    badge_fs, 0.4, rl.Color{ col.r, col.g, col.b, 195 })
                item_w := dot_r * 2 + uis(5) + b_sz[i].x
                x += item_w + gap
            }
        }
    }
}

// draw_boss_hud kept as a thin wrapper so any call sites outside main.odin still compile.
draw_boss_hud :: proc(w: ^cw.World) {
    draw_entity_inspect_hud(w)
}

@(private = "file")
FONT_SIZE :: i32(64)

init_font :: proc() {
    if rl.FileExists(FONT_PATH) {
        g_font = rl.LoadFontEx(FONT_PATH, FONT_SIZE, nil, 0)
        rl.SetTextureFilter(g_font.texture, .BILINEAR)
    } else {
        g_font = rl.GetFontDefault()
    }
}

shutdown_font :: proc() {
    if rl.FileExists(FONT_PATH) {
        rl.UnloadFont(g_font)
    }
}

HIT_FLASH_DURATION :: f32(0.12)

@(private = "file")
MAX_HIT_FLASHES :: 64

@(private = "file")
HitFlashEntry :: struct { entity_id: int, timer: f32}

@(private = "file")
g_hit_flashes: [MAX_HIT_FLASHES]HitFlashEntry

push_hit_flash :: proc(entity_id: int) {
    for &e in g_hit_flashes {
        if e.entity_id == entity_id {
            e.timer = HIT_FLASH_DURATION
            return
        }
    }
    for &e in g_hit_flashes {
        if e.timer <= 0 {
            e = HitFlashEntry{entity_id, HIT_FLASH_DURATION}
            return
        }
    }
    oldest := 0
    for i in 1..<MAX_HIT_FLASHES {
        if g_hit_flashes[i].timer < g_hit_flashes[oldest].timer { oldest = i }
    }
    g_hit_flashes[oldest] = HitFlashEntry{entity_id, HIT_FLASH_DURATION}
}

get_hit_flash_intensity :: proc(entity_id: int) -> f32 {
    for e in g_hit_flashes {
        if e.entity_id == entity_id && e.timer > 0 {
            return clamp(e.timer / HIT_FLASH_DURATION, 0, 1)
        }
    }
    return 0
}

tick_hit_flashes :: proc(dt: f32) {
    for &e in g_hit_flashes {
        if e.timer > 0 { e.timer -= dt }
    }
}

@(private = "file")
g_clay_memory: []u8

init_clay :: proc() {
    min_mem       := cast(int)clay.MinMemorySize()
    g_clay_memory  = make([]u8, min_mem)
    arena := clay.CreateArenaWithCapacityAndMemory(
        cast(c.size_t)min_mem, raw_data(g_clay_memory))
    clay.Initialize(
        arena,
        { SCREEN_WIDTH, SCREEN_HEIGHT },
        { handler = clay_error_handler })
    clay.SetMeasureTextFunction(clay_measure_text, nil)
}

shutdown_clay :: proc() {
    delete(g_clay_memory)
}

update_clay_input :: proc() {
    mp := rl.GetMousePosition()
    clay.SetPointerState({ mp.x, mp.y }, rl.IsMouseButtonDown(.LEFT))
    clay.SetLayoutDimensions({ f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) })
    g_ui_scale = f32(rl.GetScreenHeight()) / 720.0
    g_inv = InvLayout{
        panel_w       = i32(uis(420)),
        panel_h       = i32(uis(720)),  
        pad           = i32(uis(16)),
        col_gap       = i32(uis(12)),
        title_y       = i32(uis(14)),
        rule1_y       = i32(uis(38)),
        slots_y       = i32(uis(50)),
        slot_h        = i32(uis(46)),
        slot_gap      = i32(uis(6)),
        slot_w        = i32(uis(388)),  
        sec_y         = i32(uis(212)),
        wep_y         = i32(uis(232)),
        wep_h         = i32(uis(60)),
        wep_w         = i32(uis(188)),  
        ability_sec_y = i32(uis(306)),
        ability_y     = i32(uis(326)),
        ability_h     = i32(uis(46)),
        ability_w     = i32(uis(88)),   
        pack_sec_y    = i32(uis(430)),
        pack_y        = i32(uis(452)),
        hint_y        = i32(uis(692)),
        cell_sz       = i32(uis(36)),
    }
}

@(private = "file")
clay_error_handler :: proc "c" (data: clay.ErrorData) {
    context = runtime.default_context()
}

@(private = "file")
clay_measure_text :: proc "c" (text: clay.StringSlice, config: ^clay.TextElementConfig, userData: rawptr) -> clay.Dimensions {
    context = runtime.default_context()
    if text.length <= 0 {
        return { 0, 0 }
    }

    font_size := f32(config.fontSize)
    if font_size <= 0 {
        font_size = 12
    }
    spacing := f32(config.letterSpacing)
    raw_text := string(text.chars[:text.length])
    lines := strings.split(raw_text, "\n")
    max_w := f32(0)
    for line in lines {
        line_cs := strings.clone_to_cstring(line, context.temp_allocator)
        sz := rl.MeasureTextEx(g_font, line_cs, font_size, spacing)
        if sz.x > max_w { max_w = sz.x }
    }
    line_h := font_size
    if config.lineHeight > 0 {
        line_h = f32(config.lineHeight)
    }
    return { max_w, max(line_h * f32(max(len(lines), 1)), font_size) }
}

@(private = "file")
PLAYER_SLOT_COLORS := [cw.MAX_PLAYERS][3]rl.Color{
    { {  55,  55,  70, 255 }, { 100, 100, 120, 255 }, {255,  60,  60, 255} },  // slot 0 — grey/red
    { {  28,  80,  28, 255 }, {  55, 145,  55, 255 }, { 80, 230,  80, 255} },  // slot 1 — green
    { {  28,  55, 100, 255 }, {  55, 100, 180, 255 }, { 80, 170, 255, 255} },  // slot 2 — blue
    { { 100,  55,  10, 255 }, { 180, 110,  30, 255 }, {255, 180,  40, 255} },  // slot 3 — orange
}

EntityVisualInfo :: struct {
    sprite_key:   cstring,
    world_size:   f32,
    sprite_scale: f32,
    ok:           bool,
}

draw_world_circle :: proc(pos: rl.Vector2, radius: f32, color: rl.Color) {
    ip := world_to_iso_v(pos)
    rl.DrawEllipse(i32(ip.x), i32(ip.y), radius, max(radius * 0.55, 1), color)
}

draw_world_circle_lines :: proc(pos: rl.Vector2, radius: f32, color: rl.Color) {
    ip := world_to_iso_v(pos)
    rl.DrawEllipseLines(i32(ip.x), i32(ip.y), max(radius, 1), max(radius * 0.55, 1), color)
}

draw_world_line :: proc(a, b: rl.Vector2, thick: f32, color: rl.Color) {
    rl.DrawLineEx(world_to_iso_v(a), world_to_iso_v(b), thick, color)
}

is_player_entity :: proc(w: ^cw.World, id: int) -> bool {
    for pid in w.player_ids {
        if pid == id { return true }
    }
    return false
}

player_slot_for_id :: proc(w: ^cw.World, id: int) -> int {
    for slot in 0..<cw.MAX_PLAYERS {
        if w.player_ids[slot] == id { return slot }
    }
    return -1
}

draw_entity_visual_info :: proc(w: ^cw.World, id: int) -> EntityVisualInfo {
    info := EntityVisualInfo{sprite_scale = 1.0}

    if cw.world_has_component(w, id, .RenderConfig) {
        rc := cw.world_get_render_config(w, id)
        if rc.sprite_len > 0 {
            info.sprite_key = cw.render_config_sprite_cstr(rc)
        }
        if rc.world_size > 0 {
            info.world_size = rc.world_size
        }
        if rc.sprite_scale > 0 {
            info.sprite_scale = rc.sprite_scale
        }
    }

    if info.world_size <= 0 {
        if cw.world_has_component(w, id, .Collider) {
            info.world_size = cw.world_get_collider(w, id).radius * 4.2
        }
        if is_player_entity(w, id) {
            info.world_size = PLAYER_RADIUS * 4.4
        }
        if cw.world_has_component(w, id, .NPC) {
            npc := cw.world_get_npc(w, id)
            switch npc.npc_type {
            case .Shopkeeper:        info.world_size = 64
            case .MutationWorkbench: info.world_size = 78
            case .Stash:             info.world_size = 70
            }
        }
    }

    if info.sprite_key == nil {
        if is_player_entity(w, id) {
            info.sprite_key = cstring("player_wanderer")
        } else if cw.world_has_component(w, id, .NPC) {
            npc := cw.world_get_npc(w, id)
            switch npc.npc_type {
            case .Shopkeeper:        info.sprite_key = cstring("npc_shopkeeper")
            case .MutationWorkbench: info.sprite_key = cstring("mutation_workbench")
            case .Stash:             info.sprite_key = cstring("mutation_workbench")
            }
        } else if cw.world_has_component(w, id, .AIAgent) {
            ai := cw.world_get_ai(w, id)
            info.sprite_key = cstring("enemy_ranged") if ai.ai_type == .Ranged else cstring("enemy_melee")
        }
    }

    if info.sprite_key != nil && info.world_size > 0 {
        info.world_size *= info.sprite_scale
        info.ok = true
    }
    return info
}

entity_render_layer :: proc(w: ^cw.World, id: int) -> cw.RenderLayer {
    if cw.world_has_component(w, id, .RenderConfig) {
        rc := cw.world_get_render_config(w, id)
        if rc.render_layer != .None { return rc.render_layer }
    }
    if cw.world_has_component(w, id, .GroundItem) ||
       cw.world_has_component(w, id, .ProjectileTag) ||
       cw.world_has_component(w, id, .MeleeArc) {
        return .WorldFX
    }
    if is_player_entity(w, id) ||
       cw.world_has_component(w, id, .AIAgent) ||
       cw.world_has_component(w, id, .NPC) {
        return .Sprite
    }
    return .None
}

entity_blindfire_hidden :: proc(w: ^cw.World, id: int) -> bool {
    if !cw.world_has_component(w, id, .AIAgent) { return false }
    if !player_has_mutation_effect(w, w.player_id, .MutHideEnemySprites) { return false }
    if !cw.world_has_component(w, w.player_id, .Transform) || !cw.world_has_component(w, id, .Transform) {
        return false
    }

    radius := f32(0)
    if cw.world_has_component(w, w.player_id, .MutationContainer) {
        mc := cw.world_get_mutation(w, w.player_id)
        for i in 0..<mc.entity_count {
            mid := mc.entities[i]
            if !cw.world_is_valid(w, mid) { continue }
            if !cw.world_has_component(w, mid, .MutUnseenDamageMult) { continue }
            radius = cw.world_get_mut_unseen_damage_mult(w, mid).vision_radius
            break
        }
    }
    if radius <= 0 { return true }
    pp := cw.world_get_transform(w, w.player_id).position
    ep := cw.world_get_transform(w, id).position
    dx := ep[0] - pp[0]
    dy := ep[1] - pp[1]
    return dx*dx + dy*dy > radius*radius
}

draw_iso_arc :: proc(center: rl.Vector2, radius, angle, spread: f32, width: f32, color: rl.Color) {
    STEPS :: 20
    for i in 0..<STEPS {
        t0 := angle - spread + (f32(i) / STEPS) * (spread * 2)
        t1 := angle - spread + (f32(i + 1) / STEPS) * (spread * 2)
        p0 := rl.Vector2{ center.x + math.cos(t0) * radius, center.y + math.sin(t0) * radius }
        p1 := rl.Vector2{ center.x + math.cos(t1) * radius, center.y + math.sin(t1) * radius }
        draw_world_line(p0, p1, width, color)
    }
}

draw_entity_world_fx :: proc(w: ^cw.World, id: int) {
    if !cw.world_has_component(w, id, .Transform) || is_fog_hidden(w, id) { return }
    tr := cw.world_get_transform(w, id)
    pos := rl.Vector2{ tr.position[0], tr.position[1] }

    if cw.world_has_component(w, id, .GroundItem) && cw.world_has_component(w, id, .Item) {
        item := cw.world_get_item(w, id)
        // Hide circles for filtered-out items (ALT overrides).
        alt_held := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)
        if !alt_held && item.rarity < g_loot_filter_rarity { return }
        t     := f32(rl.GetTime())
        pulse := (math.sin(t * 3.2) + 1) * 0.5
        rc    := rarity_color(item.rarity)
        draw_world_circle(pos, 12, rl.Color{ rc.r, rc.g, rc.b, u8(70 + pulse * 90) })
        draw_world_circle(pos, 6,  rl.Color{ rc.r, rc.g, rc.b, u8(170 + pulse * 85) })
        draw_world_circle(pos, 2,  rl.Color{ 255, 255, 255, 200 })
        return
    }

    if cw.world_has_component(w, id, .ProjectileTag) {
        p := cw.world_get_projectile(w, id)
        switch p.visual {
        case .Standard:
            draw_world_circle(pos, 4, rl.Color{ 220, 190, 60, 255 })
        case .Smoke:
            fade := f32(1)
            if p.max_lifetime > 0 { fade = clamp(p.lifetime / p.max_lifetime, 0, 1) }
            draw_world_circle(pos, 7, rl.Color{ 130, 122, 118, u8(clamp(fade * 55, 0, 255)) })
            draw_world_circle(pos, 4, rl.Color{ 178, 168, 162, u8(clamp(fade * 130, 0, 255)) })
            draw_world_circle(pos, 2, rl.Color{ 215, 208, 204, u8(clamp(fade * 200, 0, 255)) })
        }
        return
    }

    if cw.world_has_component(w, id, .MeleeArc) {
        arc := cw.world_get_melee_arc(w, id)
        fade := f32(1)
        if cw.world_has_component(w, id, .SelfDestruct) && arc.lifetime > 0 {
            fade = cw.world_get_self_destruct(w, id).timer / arc.lifetime
        }
        draw_iso_arc(pos, arc.radius - 2, arc.angle, arc.arc_spread, 5, rl.Color{ 215, 90, 20, u8(clamp(fade, 0, 1) * 210) })
        draw_iso_arc(pos, arc.radius, arc.angle, arc.arc_spread, 2, rl.Color{ 255, 165, 60, u8(clamp(fade, 0, 1) * 255) })
        return
    }
}

// draw_ground_item_labels draws floating item names above every visible ground item.
// Must be called inside BeginMode2D so world_to_iso_v maps correctly.
// Called in the final screen-space pass (after lighting composites) so labels are
// unaffected by fog/shadow shaders.
draw_ground_item_labels :: proc(w: ^cw.World) {
    ids := cw.world_query(w, cw.query_mask(.GroundItem, .Item, .Transform),
        context.temp_allocator)

    alt_held := rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT)
    tt       := f32(rl.GetTime())

    for id in ids {
        if is_fog_hidden(w, id)                             { continue }
        if !cw.world_has_component(w, id, .RenderConfig)   { continue }

        item := cw.world_get_item(w, id)

        // Respect loot filter (ALT reveals everything).
        if !alt_held && item.rarity < g_loot_filter_rarity { continue }

        tr  := cw.world_get_transform(w, id)
        pos := rl.Vector2{ tr.position[0], tr.position[1] }
        iso := world_to_iso_v(pos)

        rcc  := cw.world_get_render_config(w, id)
        name := loc_lookup(cw.render_config_name_cstr(rcc))
        if len(name) == 0 { continue }

        rc    := rarity_color(item.rarity)
        pulse := (math.sin(tt * 3.2 + f32(id) * 0.37) + 1) * 0.5

        nfs  := uis(9)
        nsz  := rl.MeasureTextEx(g_font, name, nfs, 0.4)
        name_a := u8(160 + pulse * 95)
        rl.DrawTextEx(g_font, name,
            { iso.x - nsz.x * 0.5, iso.y - uis(20) - nsz.y },
            nfs, 0.4, rl.Color{ rc.r, rc.g, rc.b, name_a })

        // Ability items get an ACTIVE / PASSIVE tag above the name.
        if item.ability_type != .None {
            def := ABILITY_DEFS[item.ability_type]
            tag := t(.HUD_ITEM_PASSIVE) if def.is_passive else t(.HUD_ITEM_ACTIVE)
            tfs := uis(8)
            tsz := rl.MeasureTextEx(g_font, tag, tfs, 0.4)
            rl.DrawTextEx(g_font, tag,
                { iso.x - tsz.x * 0.5, iso.y - uis(20) - nsz.y - tfs - uis(1) },
                tfs, 0.4, rl.Color{ 200, 170, 100, u8(130 + pulse * 60) })
        }
    }
}

draw_entity_sprite_overlays :: proc(w: ^cw.World, id: int, pos: rl.Vector2, base_size: f32, rot: f32) {
    slot := player_slot_for_id(w, id)
    is_player := slot >= 0
    show_hp := false
    show_tip := false
    if cw.world_has_component(w, id, .RenderConfig) {
        rc := cw.world_get_render_config(w, id)
        show_hp = rc.show_hp_bar
        show_tip = rc.show_dir_tip
    }
    if is_player { show_tip = true }
    if cw.world_has_component(w, id, .AIAgent) {
        show_hp = true
        show_tip = true
    }

    if show_tip {
        line_col := rl.Color{ 200, 55, 55, 200 }
        if is_player {
            line_col = PLAYER_SLOT_COLORS[slot][2]
        } else if cw.world_has_component(w, id, .AIAgent) && cw.world_get_ai(w, id).ai_type == .Ranged {
            line_col = rl.Color{ 80, 128, 205, 200 }
        }
        tip := rl.Vector2{
            pos.x + math.cos(rot) * (base_size * 0.22 + 8),
            pos.y + math.sin(rot) * (base_size * 0.22 + 8),
        }
        draw_world_line(pos, tip, 2, line_col)
        draw_world_circle(tip, 5, line_col)
    }

    // After ISO_SPRITE_Y squish the sprite's visual half-height in screen space
    // is base_size * ISO_SPRITE_Y * 0.5 = base_size * 0.25.
    // All vertical offsets below are relative to that compressed top edge.
    sprite_top := base_size * ISO_SPRITE_Y * 0.5   // screen px above iso centre

    if show_hp && cw.world_has_component(w, id, .Health) {
        h := cw.world_get_health(w, id)
        if h.max > 0 {
            iso   := world_to_iso_v(pos)
            bar_w := base_size * 0.65
            bx    := iso.x - bar_w * 0.5
            by    := iso.y - sprite_top - 5
            rl.DrawRectangle(i32(bx - 1), i32(by - 1), i32(bar_w + 2), 5, rl.Color{ 10, 8, 8, 200 })
            rl.DrawRectangle(i32(bx), i32(by), i32(bar_w), 3, rl.Color{ 30, 14, 14, 200 })
            frac   := clamp(h.current / h.max, 0, 1)
            fill_r := u8(60 + (1 - frac) * 180)
            fill_g := u8(200 - (1 - frac) * 170)
            rl.DrawRectangle(i32(bx), i32(by), i32(bar_w * frac), 3, rl.Color{ fill_r, fill_g, 30, 240 })
        }
    }

    // ── Enemy mutation overlay ─────────────────────────────────────────────────
    // Badge dots below the HP bar + mutation name label above it.
    // Only for non-player entities that carry at least one mutation.
    if !is_player && cw.world_has_component(w, id, .MutationContainer) {
        mc := cw.world_get_mutation(w, id)
        if mc.entity_count > 0 {
            iso   := world_to_iso_v(pos)
            bar_w := base_size * 0.65

            // Name label (first mutation only, centred above the HP bar).
            label_fs := f32(9)
            for i in 0..<mc.entity_count {
                meid := mc.entities[i]
                if !cw.world_is_valid(w, meid)            { continue }
                if !cw.world_has_component(w, meid, .Mut) { continue }
                mt   := cw.world_get_mut(w, meid).type_id
                col  := mutation_visual_color(mt)
                name := mutation_short_name(mt)
                lsz  := rl.MeasureTextEx(g_font, name, label_fs, 0.4)
                rl.DrawTextEx(g_font, name,
                    { iso.x - lsz.x * 0.5, iso.y - sprite_top - 14 },
                    label_fs, 0.4, rl.Color{ col.r, col.g, col.b, 175 })
                break  // show first mutation name only; dots below cover the rest
            }

            // Coloured dot per mutation, left-aligned beneath the HP bar.
            dot_x0 := iso.x - bar_w * 0.5 + 3
            dot_y  := iso.y - sprite_top + 3
            n      := 0
            for i in 0..<mc.entity_count {
                meid := mc.entities[i]
                if !cw.world_is_valid(w, meid)            { continue }
                if !cw.world_has_component(w, meid, .Mut) { continue }
                mt  := cw.world_get_mut(w, meid).type_id
                col := mutation_visual_color(mt)
                rl.DrawCircleV({ dot_x0 + f32(n) * 7, dot_y }, 2.5, col)
                n += 1
            }
        }
    }

    if is_player {
        name_str: cstring
        if g_player_names[slot][0] != 0 {
            name_str = cstring(&g_player_names[slot][0])
        } else {
            placeholder: [4]u8 = {'P', u8('1' + slot), 0, 0}
            name_str = cstring(&placeholder[0])
        }
        iso      := world_to_iso_v(pos)
        name_fs  := f32(11)
        name_sz  := rl.MeasureTextEx(g_font, name_str, name_fs, 0.5)
        line_col := PLAYER_SLOT_COLORS[slot][2]
        rl.DrawTextEx(g_font, name_str,
            { iso.x - name_sz.x * 0.5, iso.y - sprite_top - name_fs - 3 },
            name_fs, 0.5, rl.Color{ line_col.r, line_col.g, line_col.b, 210 })

        // ── HeartCage visual ─────────────────────────────────────────────────
        if cw.world_has_component(w, id, .MutationContainer) {
            mc_hc := cw.world_get_mutation(w, id)
            for hi in 0..<mc_hc.entity_count {
                hmeid := mc_hc.entities[hi]
                if !cw.world_is_valid(w, hmeid)                     { continue }
                if !cw.world_has_component(w, hmeid, .MutHeartCage) { continue }
                hc    := cw.world_get_mut_heart_cage(w, hmeid)
                t_now := f32(rl.GetTime())
                hrad  := f32(12.0)   // larger, more visible heart

                // Authoritative world position is the orbit entity; fall back
                // to analytic orbit if entity was somehow destroyed.
                hworld: rl.Vector2
                if cw.world_is_valid(w, hc.heart_id) &&
                   cw.world_has_component(w, hc.heart_id, .Transform) {
                    ht    := cw.world_get_transform(w, hc.heart_id)
                    hworld = { ht.position[0], ht.position[1] }
                } else {
                    r      := cw.HEART_CAGE_ORBIT_RADIUS
                    hworld  = { pos.x + math.cos(hc.orbit_angle) * r,
                                 pos.y + math.sin(hc.orbit_angle) * r }
                }

                heart_alive := cw.world_is_valid(w, hc.heart_id) &&
                               cw.world_has_component(w, hc.heart_id, .Health) &&
                               cw.world_get_health(w, hc.heart_id).current > 0
                if heart_alive {
                    hh     := cw.world_get_health(w, hc.heart_id)
                    hiso   := world_to_iso_v(hworld)
                    hp_pct := hh.current / hh.max
                    pulse  := f32(0.8) + f32(0.2) * math.sin(t_now * 5.0)
                    alpha  := u8(160 + int(95.0 * pulse))
                    // Outer glow layers → bright core → rim
                    draw_world_circle(hworld, hrad + 8, rl.Color{200, 40, 60, 25})
                    draw_world_circle(hworld, hrad + 4, rl.Color{200, 40, 60, 55})
                    draw_world_circle(hworld, hrad,     rl.Color{220, 55, 70, alpha})
                    draw_world_circle_lines(hworld, hrad, rl.Color{255, 130, 150, 220})
                    // HP bar above the heart in screen space
                    bw  := f32(30);  bh := f32(4)
                    bx  := hiso.x - bw * 0.5
                    by  := hiso.y - hrad * 0.55 - 8
                    rl.DrawRectangleRec({bx - 1, by - 1, bw + 2, bh + 2}, rl.Color{20, 8, 10, 200})
                    rl.DrawRectangleRec({bx, by, bw, bh},                  rl.Color{50, 14, 18, 180})
                    fill_c := rl.Color{ u8(80 + int((1-hp_pct)*140)), u8(int(hp_pct*180)), 30, 240 }
                    rl.DrawRectangleRec({bx, by, bw * hp_pct, bh}, fill_c)
                }
                break
            }
        }
    }
}

draw_entity_sprite_visual :: proc(w: ^cw.World, id: int) {
    if !cw.world_has_component(w, id, .Transform) || is_fog_hidden(w, id) || entity_blindfire_hidden(w, id) { return }
    // Open doors are invisible — player walks through the empty frame.
    if cw.world_has_component(w, id, .Openable) && cw.world_get_openable(w, id).is_open { return }
    tr := cw.world_get_transform(w, id)
    pos := rl.Vector2{ tr.position[0], tr.position[1] }
    rot := tr.rotation

    if cw.world_has_component(w, id, .Respawn) {
        rsp := cw.world_get_respawn(w, id)
        if rsp.timer > 0 && math.sin(rsp.timer * math.PI * 10) <= 0 {
            return
        }
    }

    vis := draw_entity_visual_info(w, id)
    if !vis.ok { return }

    tint := rl.WHITE
    if is_player_entity(w, id) && cw.world_has_component(w, id, .DodgeState) && cw.world_get_dodge(w, id).active {
        tint = rl.Color{ 180, 220, 255, 255 }
    } else if cw.world_has_component(w, id, .AIAgent) && cw.world_get_ai(w, id).ai_type == .Ranged {
        tint = color_mix(rl.Color{ 230, 238, 255, 255 }, rl.Color{ 255, 245, 235, 255 }, 0.18)
    } else if cw.world_has_component(w, id, .NPC) && cw.world_get_npc(w, id).npc_type == .MutationWorkbench {
        tint = rl.Color{ 250, 242, 255, 255 }
    }
    tint = color_mix(tint, rl.WHITE, get_hit_flash_intensity(id) * 0.75)

    if entry, ok := get_or_load_entity_sprite(vis.sprite_key); ok {
        src := anim_source_rect(w, id, entry.src, string(vis.sprite_key)) if !entry.from_rt else entry.src
        draw_entity_sprite_quad_ex(entry.tex, src, pos, vis.world_size, rot, tint)
    }
    draw_entity_sprite_overlays(w, id, pos, vis.world_size, rot)
}

draw_entities :: proc(w: ^cw.World, pass: cw.RenderLayer) {
    ids := cw.world_query(w, cw.query_mask(.Transform))
    defer delete(ids)

    if pass == .Sprite {
        for i in 1..<len(ids) {
            key := ids[i]
            key_t := cw.world_get_transform(w, key).position
            key_sort := iso_depth_sort_y(key_t[0], key_t[1])
            j := i
            for j > 0 {
                prev := ids[j - 1]
                prev_t := cw.world_get_transform(w, prev).position
                if iso_depth_sort_y(prev_t[0], prev_t[1]) <= key_sort { break }
                ids[j] = prev
                j -= 1
            }
            ids[j] = key
        }
    }

    for id in ids {
        if entity_render_layer(w, id) != pass { continue }
        #partial switch pass {
        case .WorldFX:
            draw_entity_world_fx(w, id)
        case .Sprite:
            draw_entity_sprite_visual(w, id)
        }
    }
}

draw_player :: proc(w: ^cw.World) {
    // Legacy entry point retired. Use draw_entities(w, .Sprite).
}

draw_floor :: proc() {
    // Retired with tilemap sprite rendering.
}

draw_enemies :: proc(w: ^cw.World) {
    // Legacy entry point retired. Use draw_entities(w, .Sprite).
}

draw_world_npcs :: proc(w: ^cw.World) {
    // Legacy entry point retired. Use draw_entities(w, .Sprite).
}

draw_melee_arcs :: proc(w: ^cw.World) {
    // Legacy entry point retired. Use draw_entities(w, .WorldFX).
}

draw_projectiles :: proc(w: ^cw.World) {
    // Legacy entry point retired. Use draw_entities(w, .WorldFX).
}

draw_ground_items :: proc(w: ^cw.World) {
    // Legacy entry point retired. Use draw_entities(w, .WorldFX).
}

rarity_color :: proc(rarity: cw.ItemRarity) -> rl.Color {
    switch rarity {
    case .Normal:    return rl.Color{ 160, 155, 148, 255 }
    case .Rare:      return rl.Color{  75, 135, 210, 255 }
    case .Epic:      return rl.Color{ 148,  55, 198, 255 }
    case .Legendary: return rl.Color{ 205,  90,  18, 255 }
    case .Unique:    return rl.Color{ 215, 175,  28, 255 }
    }
    return rl.Color{ 160, 155, 148, 255 }
}

// mutation_visual_color returns the canonical display colour for a mutation type.
mutation_visual_color :: proc(mt: cw.MutationType) -> rl.Color {
    #partial switch mt {
    case .LivingBomb:  return rl.Color{ 255, 120,  30, 255 }  // ember orange
    case .ToxicFlesh:  return rl.Color{  80, 200,  60, 255 }  // toxic green
    case .ThornPact:   return rl.Color{ 180, 160, 255, 255 }  // silver-purple
    case .BlackLung:   return rl.Color{  80, 160, 130, 255 }  // teal
    }
    return rl.Color{ 180, 180, 180, 255 }                     // grey fallback
}

// mutation_short_name returns a short uppercase display name for HUD labels.
@(private = "file")
mutation_short_name :: proc(mt: cw.MutationType) -> cstring {
    #partial switch mt {
    case .LivingBomb:  return "LIVING BOMB"
    case .ToxicFlesh:  return "TOXIC FLESH"
    case .ThornPact:   return "THORN PACT"
    case .BlackLung:   return "BLACK LUNG"
    }
    return "MUTANT"
}

// draw_hud, draw_ammo_ring, draw_ability_hud, and draw_hud_clay have been
// consolidated into draw_hud() — see ui_hud.odin.

@(private = "file")
InvLayout :: struct {
    panel_w, panel_h,
    pad,              
    col_gap,          
    title_y,
    rule1_y,
    slots_y, slot_h, slot_gap, slot_w,
    sec_y,
    wep_y, wep_h, wep_w,
    ability_sec_y,    
    ability_y,        
    ability_h,        
    ability_w,        
    pack_sec_y, pack_y,
    hint_y,
    cell_sz: i32,
}

g_inv: InvLayout  

PauseResolution :: struct { w, h: i32, label: cstring }

PAUSE_RESOLUTIONS := [?]PauseResolution{
    { 1280,  720, "1280 x 720"  },
    { 1600,  900, "1600 x 900"  },
    { 1920, 1080, "1920 x 1080" },
    { 2560, 1440, "2560 x 1440" },
}

g_pause_res_idx: int
g_borderless:    bool

// lang_name returns the native name of a language, always in that language
// regardless of the current g_lang setting.
@(private = "file")
lang_name :: proc(lang: Language) -> cstring {
    switch lang {
    case .EN: return t(.LANG_EN)
    case .ES: return t(.LANG_ES)
    case .PT: return t(.LANG_PT)
    }
    return "?"
}

// _apply_lang changes the active language, syncs it to config and saves.
@(private = "file")
_apply_lang :: proc(lang: Language) {
    g_lang           = lang
    g_binds.language = u8(lang)
    save_config()
}

PAUSE_W_BASE      :: f32(340)
PAUSE_H_BASE      :: f32(668)
PAUSE_BTN_W_BASE  :: f32(200)
PAUSE_BTN_H_BASE  :: f32(42)

PAUSE_Y_RESUME_BASE   :: f32(62)
PAUSE_Y_RES_BASE      :: f32(140)
PAUSE_Y_MODE_BASE     :: f32(222)
PAUSE_Y_LANG_BASE     :: f32(304)   // language selector row
PAUSE_Y_VOL_BASE      :: f32(398)
PAUSE_VOL_ROW_H_BASE  :: f32(34)
PAUSE_Y_KEYBINDS_BASE :: f32(566)
PAUSE_Y_QUIT_BASE     :: f32(616)

pause_W          :: proc() -> i32 { return i32(uis(PAUSE_W_BASE))           }
pause_H          :: proc() -> i32 { return i32(uis(PAUSE_H_BASE))           }
pause_btn_w      :: proc() -> i32 { return i32(uis(PAUSE_BTN_W_BASE))       }
pause_btn_h      :: proc() -> i32 { return i32(uis(PAUSE_BTN_H_BASE))       }
pause_y_resume   :: proc() -> i32 { return i32(uis(PAUSE_Y_RESUME_BASE))    }
pause_y_res      :: proc() -> i32 { return i32(uis(PAUSE_Y_RES_BASE))       }
pause_y_mode     :: proc() -> i32 { return i32(uis(PAUSE_Y_MODE_BASE))      }
pause_y_lang     :: proc() -> i32 { return i32(uis(PAUSE_Y_LANG_BASE))      }
pause_y_vol      :: proc() -> i32 { return i32(uis(PAUSE_Y_VOL_BASE))       }
pause_vol_row_h  :: proc() -> i32 { return i32(uis(PAUSE_VOL_ROW_H_BASE))   }
pause_y_keybinds :: proc() -> i32 { return i32(uis(PAUSE_Y_KEYBINDS_BASE))  }
pause_y_quit     :: proc() -> i32 { return i32(uis(PAUSE_Y_QUIT_BASE))      }

g_rebind_idx: int = -1

init_pause_menu :: proc() {
    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()
    for i in 0..<len(PAUSE_RESOLUTIONS) {
        if PAUSE_RESOLUTIONS[i].w == sw && PAUSE_RESOLUTIONS[i].h == sh {
            g_pause_res_idx = i
            break
        }
    }
    g_borderless = rl.IsWindowState(rl.ConfigFlags{.BORDERLESS_WINDOWED_MODE})
}

apply_resolution :: proc(idx: int) {
    res := PAUSE_RESOLUTIONS[idx]
    rl.SetWindowSize(res.w, res.h)
    if g_camera != nil {
        g_camera.offset = { f32(res.w) * 0.5, f32(res.h) * 0.5 }
    }
}

set_window_mode :: proc(borderless: bool) {
    if borderless {
        rl.SetWindowState(rl.ConfigFlags{.BORDERLESS_WINDOWED_MODE})
    } else {
        rl.ClearWindowState(rl.ConfigFlags{.BORDERLESS_WINDOWED_MODE})
        apply_resolution(g_pause_res_idx)
    }
    g_borderless = borderless
}

draw_pause_btn :: proc(rect: rl.Rectangle, label: cstring, mp: rl.Vector2, enabled := true) -> bool {
    hot     := enabled && rl.CheckCollisionPointRec(mp, rect)
    bg      := rl.Color{ 28, 22, 16, 240 } if !hot else rl.Color{ 52, 38, 20, 255 }
    border  := COL_RULE if !hot else COL_BRASS
    txt_col: rl.Color
    if !enabled      { txt_col = rl.Color{ 80, 72, 55, 140 }
    } else if !hot   { txt_col = COL_PARCH
    } else           { txt_col = COL_BRASS }
    if !enabled { bg = rl.Color{ 16, 13, 10, 200 }; border = rl.Color{ 60, 50, 32, 100 } }
    rl.DrawRectangleRec(rect, bg)
    rl.DrawRectangleLinesEx(rect, 1, border)
    btn_fs := uis(18)
    lsz := rl.MeasureTextEx(g_font, label, btn_fs, 1)
    rl.DrawTextEx(g_font, label,
        { rect.x + rect.width * 0.5 - lsz.x * 0.5, rect.y + rect.height * 0.5 - btn_fs * 0.5 },
        btn_fs, 1, txt_col)
    return hot && rl.IsMouseButtonPressed(.LEFT)
}

pause_arrow_row :: proc(
    px, row_y: i32,
    header, value: cstring,
    mp: rl.Vector2,
    enabled := true,
) -> int {
    pW        := pause_W()
    arrow_sz  := f32(pause_btn_h())
    lrect := rl.Rectangle{ f32(px + 16), f32(row_y), arrow_sz, arrow_sz }
    rrect := rl.Rectangle{ f32(px + pW - 16) - arrow_sz, f32(row_y), arrow_sz, arrow_sz }

    rl.DrawLineEx(
        { f32(px) + 16, f32(row_y) - 10 },
        { f32(px + pW) - 16, f32(row_y) - 10 }, 1, COL_RULE)
    hdr_fs := uis(13)
    hsz    := rl.MeasureTextEx(g_font, header, hdr_fs, 1)
    rl.DrawTextEx(g_font, header,
        { f32(px) + f32(pW) * 0.5 - hsz.x * 0.5, f32(row_y) - uis(22) },
        hdr_fs, 1, COL_MUTED)

    l_clicked := draw_pause_btn(lrect, "<", mp, enabled)
    r_clicked := draw_pause_btn(rrect, ">", mp, enabled)

    val_fs := uis(18)
    vcol   := COL_PARCH if enabled else rl.Color{ 80, 72, 55, 140 }
    vsz    := rl.MeasureTextEx(g_font, value, val_fs, 1)
    rl.DrawTextEx(g_font, value,
        { f32(px) + f32(pW) * 0.5 - vsz.x * 0.5, f32(row_y) + arrow_sz * 0.5 - val_fs * 0.5 },
        val_fs, 1, vcol)

    if l_clicked { return -1 }
    if r_clicked { return  1 }
    return 0
}

vol_bar_dims :: proc(px, row_y: i32) -> (bar_x, bar_y, bar_w: i32, hit: rl.Rectangle) {
    pW    := pause_W()
    pad   := i32(uis(16))
    lbl_w := i32(uis(58))
    gap   := i32(uis(8))
    val_w := i32(uis(46))
    bh    := i32(uis(14))
    bx    := px + pad + lbl_w + gap
    by    := row_y + i32(uis(10))
    bw    := pW - pad*2 - lbl_w - gap - val_w - gap
    r     := rl.Rectangle{ f32(bx), f32(by) - uis(5), f32(bw), f32(bh) + uis(10) }
    return bx, by, bw, r
}

draw_vol_slider :: proc(px, row_y: i32, label: cstring, value: f32, mp: rl.Vector2) {
    bx, by, bw, hit := vol_bar_dims(px, row_y)
    pW    := pause_W()
    pad   := i32(uis(16))
    bh    := i32(uis(14))

    lbl_fs := uis(13)
    rl.DrawTextEx(g_font, label, { f32(px + pad), f32(row_y) + uis(8) }, lbl_fs, 1, COL_MUTED)

    rl.DrawRectangle(bx, by, bw, bh, rl.Color{ 18, 14, 10, 255 })
    rl.DrawRectangleLinesEx({ f32(bx), f32(by), f32(bw), f32(bh) }, 1, COL_RULE)

    fill_w := i32(f32(bw) * clamp(value, 0, 1))
    if fill_w > 0 {
        rl.DrawRectangle(bx, by, fill_w, bh, COL_BRASS)
    }

    thumb_x := bx + fill_w
    rl.DrawRectangle(thumb_x - 1, by - 2, 3, bh + 4, rl.Color{ 230, 205, 105, 245 })

    if rl.CheckCollisionPointRec(mp, hit) {
        rl.DrawRectangleLinesEx(hit, 1, rl.Color{ 215, 175, 28, 90 })
    }

    pct_buf: [8]u8
    pct := fmt.bprintf(pct_buf[:7], "%d%%", int(value * 100 + 0.5))
    pct_buf[len(pct)] = 0
    vsz := rl.MeasureTextEx(g_font, cstring(&pct_buf[0]), lbl_fs, 1)
    rl.DrawTextEx(g_font, cstring(&pct_buf[0]),
        { f32(px + pW - pad) - vsz.x, f32(row_y) + uis(8) }, lbl_fs, 1, COL_PARCH)
}

update_pause_menu :: proc() -> (quit: bool) {
    sw   := rl.GetScreenWidth()
    sh   := rl.GetScreenHeight()
    pW   := pause_W()
    pH   := pause_H()
    pBW  := pause_btn_w()
    pBH  := pause_btn_h()
    px   := sw / 2 - pW / 2
    py   := sh / 2 - pH / 2
    mp   := rl.GetMousePosition()
    bx   := f32(px) + f32(pW - pBW) / 2

    if rl.CheckCollisionPointRec(mp,
        { bx, f32(py + pause_y_resume()), f32(pBW), f32(pBH) }) &&
       rl.IsMouseButtonPressed(.LEFT) {
        ui_close_top()  // _ui_on_close(.PauseMenu) clears g_paused
        return false
    }

    if !g_borderless {
        arrow_sz := f32(pBH)
        res_y    := f32(py + pause_y_res())
        l_rect   := rl.Rectangle{ f32(px + 16), res_y, arrow_sz, arrow_sz }
        r_rect   := rl.Rectangle{ f32(px + pW - 16) - arrow_sz, res_y, arrow_sz, arrow_sz }
        if rl.CheckCollisionPointRec(mp, l_rect) && rl.IsMouseButtonPressed(.LEFT) {
            g_pause_res_idx = (g_pause_res_idx - 1 + len(PAUSE_RESOLUTIONS)) % len(PAUSE_RESOLUTIONS)
            apply_resolution(g_pause_res_idx)
        }
        if rl.CheckCollisionPointRec(mp, r_rect) && rl.IsMouseButtonPressed(.LEFT) {
            g_pause_res_idx = (g_pause_res_idx + 1) % len(PAUSE_RESOLUTIONS)
            apply_resolution(g_pause_res_idx)
        }
    }

    {
        arrow_sz := f32(pBH)
        mode_y   := f32(py + pause_y_mode())
        l_rect   := rl.Rectangle{ f32(px + 16), mode_y, arrow_sz, arrow_sz }
        r_rect   := rl.Rectangle{ f32(px + pW - 16) - arrow_sz, mode_y, arrow_sz, arrow_sz }
        if (rl.CheckCollisionPointRec(mp, l_rect) || rl.CheckCollisionPointRec(mp, r_rect)) &&
            rl.IsMouseButtonPressed(.LEFT) {
            set_window_mode(!g_borderless)
        }
    }

    {
        arrow_sz := f32(pBH)
        lang_y   := f32(py + pause_y_lang())
        l_rect   := rl.Rectangle{ f32(px + 16), lang_y, arrow_sz, arrow_sz }
        r_rect   := rl.Rectangle{ f32(px + pW - 16) - arrow_sz, lang_y, arrow_sz, arrow_sz }
        lp := rl.CheckCollisionPointRec(mp, l_rect) && rl.IsMouseButtonPressed(.LEFT)
        rp := rl.CheckCollisionPointRec(mp, r_rect) && rl.IsMouseButtonPressed(.LEFT)
        if lp { _apply_lang(Language((int(g_lang) - 1 + LANG_COUNT) % LANG_COUNT)) }
        if rp { _apply_lang(Language((int(g_lang) + 1)              % LANG_COUNT)) }
    }

    if rl.IsMouseButtonDown(.LEFT) {
        vol_ys := [4]i32{
            py + pause_y_vol(),
            py + pause_y_vol() + pause_vol_row_h(),
            py + pause_y_vol() + pause_vol_row_h() * 2,
            py + pause_y_vol() + pause_vol_row_h() * 3,
        }
        vol_ptrs := [4]^f32{ &g_vol_sfx, &g_vol_music, &g_vol_ambience, &g_vol_voice }
        changed := false
        for i in 0..<4 {
            bx_i, _, bw_i, hit := vol_bar_dims(px, vol_ys[i])
            if rl.CheckCollisionPointRec(mp, hit) {
                vol_ptrs[i]^ = clamp((mp.x - f32(bx_i)) / f32(bw_i), 0, 1)
                changed = true
                break
            }
        }
        if changed { apply_bus_volumes() }
    }

    if rl.CheckCollisionPointRec(mp,
        { bx, f32(py + pause_y_keybinds()), f32(pBW), f32(pBH) }) &&
       rl.IsMouseButtonPressed(.LEFT) {
        ui_open(.Keybinds)
    }

    if rl.CheckCollisionPointRec(mp,
        { bx, f32(py + pause_y_quit()), f32(pBW), f32(pBH) }) &&
       rl.IsMouseButtonPressed(.LEFT) {
        return true
    }

    return false
}

draw_pause_menu :: proc() {
    sw  := rl.GetScreenWidth()
    sh  := rl.GetScreenHeight()
    pW  := pause_W()
    pH  := pause_H()
    pBW := pause_btn_w()
    pBH := pause_btn_h()
    px  := sw / 2 - pW / 2
    py  := sh / 2 - pH / 2
    mp  := rl.GetMousePosition()
    bx  := f32(px) + f32(pW - pBW) / 2

    rl.DrawRectangle(0, 0, sw, sh, rl.Color{ 0, 0, 0, 175 })

    rl.DrawRectangle(px, py, pW, pH, rl.Color{ 8, 6, 4, 252 })
    rl.DrawRectangle(px, py, pW, 3, COL_BRASS)
    rl.DrawRectangleLinesEx(
        { f32(px), f32(py), f32(pW), f32(pH) }, 2, COL_RULE)

    title    := t(.PAUSE_TITLE)
    title_fs := uis(24)
    title_sz := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title,
        { f32(px) + f32(pW) * 0.5 - title_sz.x * 0.5, f32(py) + uis(16) },
        title_fs, 1, COL_PARCH)
    rl.DrawLineEx(
        { f32(px) + 16, f32(py) + uis(52) },
        { f32(px + pW) - 16, f32(py) + uis(52) }, 1, COL_RULE)

    draw_pause_btn(
        { bx, f32(py + pause_y_resume()), f32(pBW), f32(pBH) },
        t(.PAUSE_BTN_RESUME), mp)

    res_label := PAUSE_RESOLUTIONS[g_pause_res_idx].label
    pause_arrow_row(px, py + pause_y_res(), t(.SETTINGS_RESOLUTION), res_label, mp,
        enabled = !g_borderless)

    mode_label := t(.SETTINGS_BORDERLESS) if g_borderless else t(.SETTINGS_WINDOWED)
    pause_arrow_row(px, py + pause_y_mode(), t(.SETTINGS_WINDOW_MODE), mode_label, mp)

    pause_arrow_row(px, py + pause_y_lang(), t(.SETTINGS_LANGUAGE), lang_name(g_lang), mp)

    {
        vol_hdr    := t(.SETTINGS_VOLUME)
        vol_hdr_fs := uis(13)
        vol_hdr_sz := rl.MeasureTextEx(g_font, vol_hdr, vol_hdr_fs, 1)
        vol_row_y  := f32(py + pause_y_vol())
        rl.DrawLineEx(
            { f32(px) + 16, vol_row_y - uis(10) },
            { f32(px + pW) - 16, vol_row_y - uis(10) }, 1, COL_RULE)
        rl.DrawTextEx(g_font, vol_hdr,
            { f32(px) + f32(pW) * 0.5 - vol_hdr_sz.x * 0.5, vol_row_y - uis(22) },
            vol_hdr_fs, 1, COL_MUTED)

        rh := pause_vol_row_h()
        draw_vol_slider(px, py + pause_y_vol() + rh * 0, t(.SETTINGS_SFX),      g_vol_sfx,      mp)
        draw_vol_slider(px, py + pause_y_vol() + rh * 1, t(.SETTINGS_MUSIC),    g_vol_music,    mp)
        draw_vol_slider(px, py + pause_y_vol() + rh * 2, t(.SETTINGS_AMBIENCE), g_vol_ambience, mp)
        draw_vol_slider(px, py + pause_y_vol() + rh * 3, t(.SETTINGS_VOICE),    g_vol_voice,    mp)
    }

    rl.DrawLineEx(
        { f32(px) + 16, f32(py + pause_y_keybinds()) - 12 },
        { f32(px + pW) - 16, f32(py + pause_y_keybinds()) - 12 }, 1, COL_RULE)
    draw_pause_btn(
        { bx, f32(py + pause_y_keybinds()), f32(pBW), f32(pBH) },
        t(.PAUSE_BTN_KEYBINDS), mp)

    rl.DrawLineEx(
        { f32(px) + 16, f32(py + pause_y_quit()) - 12 },
        { f32(px + pW) - 16, f32(py + pause_y_quit()) - 12 }, 1, COL_RULE)
    draw_pause_btn(
        { bx, f32(py + pause_y_quit()), f32(pBW), f32(pBH) },
        t(.PAUSE_BTN_QUIT), mp)
}


// ── Keybinds screen ──────────────────────────────────────────────────────────
//
// Rows are grouped by InputMode with a visual section header between them.
// Adding a new mode: add its xxx_bind_rows() call to all_bind_rows() (config.odin)
// and add a header at the section boundary below.
//
// Row index layout inside all_bind_rows():
//   [0 .. GAMEPLAY_BIND_COUNT)   → Gameplay section
//   [GAMEPLAY_BIND_COUNT .. TOTAL_BIND_COUNT) → UI section
//   … future modes continue after UI_BIND_COUNT …

@(private = "file") BIND_ROW_H :: f32(30)   // compact enough to fit 17 rows at 720 p
@(private = "file") BIND_HDR_H :: f32(22)   // section label row height

// Returns the Y offset (from the top of the bind content area) for flat
// row index i, accounting for section-header rows inserted between groups.
@(private = "file")
_bind_row_y :: proc(i: int) -> f32 {
    // Section 0: Gameplay  (rows 0 .. GAMEPLAY_BIND_COUNT-1)
    //   → preceded by one header
    // Section 1: UI        (rows GAMEPLAY_BIND_COUNT .. TOTAL_BIND_COUNT-1)
    //   → preceded by one header after the gameplay rows
    if i < GAMEPLAY_BIND_COUNT {
        return BIND_HDR_H + f32(i) * BIND_ROW_H
    }
    j := i - GAMEPLAY_BIND_COUNT
    return BIND_HDR_H + f32(GAMEPLAY_BIND_COUNT) * BIND_ROW_H +
           BIND_HDR_H + f32(j) * BIND_ROW_H
}

// Total height of the scrollable bind content.
@(private = "file")
_bind_content_h :: proc() -> f32 {
    return _bind_row_y(TOTAL_BIND_COUNT - 1) + BIND_ROW_H
}

update_keybinds_screen :: proc() {
    if !ui_has(.Keybinds) { return }

    rows := all_bind_rows()

    PW :: f32(480)
    PH := f32(56) + _bind_content_h() + f32(80)
    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()
    px := f32(sw) * 0.5 - uis(PW) * 0.5
    py := f32(sh) * 0.5 - uis(PH) * 0.5
    mp := rl.GetMousePosition()

    // While waiting for a key press, eat the next key.
    // ESC cancels the rebind and is consumed so the universal close handler
    // does not also close the whole Keybinds panel on the same frame.
    if g_rebind_idx >= 0 {
        k := rl.GetKeyPressed()
        if k == .ESCAPE {
            g_rebind_idx = -1
            input_consume_key(.ESCAPE)
        } else if k != .KEY_NULL {
            rows[g_rebind_idx].ptr^ = i32(k)
            g_rebind_idx = -1
            save_config()
        }
        return
    }

    if rl.IsMouseButtonPressed(.LEFT) {
        content_y := py + uis(56)
        for i in 0..<TOTAL_BIND_COUNT {
            ry := content_y + uis(_bind_row_y(i))
            r  := rl.Rectangle{ px + uis(8), ry, uis(PW - 16), uis(BIND_ROW_H - 4) }
            if rl.CheckCollisionPointRec(mp, r) {
                g_rebind_idx = i
                return
            }
        }

        footer_y := py + uis(56) + uis(_bind_content_h()) + uis(16)
        reset_r  := rl.Rectangle{ px + uis(8), footer_y, uis(PW * 0.5 - 16), uis(36) }
        if rl.CheckCollisionPointRec(mp, reset_r) {
            g_binds = default_binds()
            save_config()
            return
        }

        close_r := rl.Rectangle{ px + uis(PW * 0.5 + 8), footer_y, uis(PW * 0.5 - 16), uis(36) }
        if rl.CheckCollisionPointRec(mp, close_r) {
            ui_close_top()
            return
        }
    }
}

draw_keybinds_screen :: proc() {
    if !ui_has(.Keybinds) { return }

    rows := all_bind_rows()

    PW :: f32(480)
    PH := f32(56) + _bind_content_h() + f32(80)
    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()
    px := f32(sw) * 0.5 - uis(PW) * 0.5
    py := f32(sh) * 0.5 - uis(PH) * 0.5
    mp := rl.GetMousePosition()

    rl.DrawRectangle(i32(px), i32(py), i32(uis(PW)), i32(uis(PH)), rl.Color{ 8, 6, 4, 252 })
    rl.DrawRectangle(i32(px), i32(py), i32(uis(PW)), i32(uis(3)), COL_BRASS)
    rl.DrawRectangleLinesEx({ px, py, uis(PW), uis(PH) }, 2, COL_RULE)

    title    := t(.KEYBINDS_TITLE)
    title_fs := uis(15)
    tsz      := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title,
        { px + uis(PW)*0.5 - tsz.x*0.5, py + uis(10) }, title_fs, 1, COL_BRASS)
    rl.DrawLineEx(
        { px + uis(16), py + uis(34) },
        { px + uis(PW) - uis(16), py + uis(34) }, 1, COL_RULE)

    content_y := py + uis(56)
    hdr_fs    := uis(10)
    name_buf  : [16]u8

    // ── Section headers ──────────────────────────────────────────────────────
    // Gameplay header (before row 0)
    _draw_bind_section_header(px, content_y, uis(PW), hdr_fs, t(.KEYBINDS_SECTION_GAMEPLAY))

    // UI header (before row GAMEPLAY_BIND_COUNT)
    ui_hdr_y := content_y + uis(BIND_HDR_H + f32(GAMEPLAY_BIND_COUNT) * BIND_ROW_H)
    _draw_bind_section_header(px, ui_hdr_y, uis(PW), hdr_fs, t(.KEYBINDS_SECTION_UI))

    // ── Bind rows ────────────────────────────────────────────────────────────
    lfs := uis(13)
    for i in 0..<TOTAL_BIND_COUNT {
        ry           := content_y + uis(_bind_row_y(i))
        row_r        := rl.Rectangle{ px + uis(8), ry, uis(PW - 16), uis(BIND_ROW_H - 4) }
        is_hot       := rl.CheckCollisionPointRec(mp, row_r) && g_rebind_idx < 0
        is_listening := g_rebind_idx == i

        row_bg: rl.Color
        if is_listening  { row_bg = rl.Color{ 50, 38, 14, 230 }
        } else if is_hot { row_bg = rl.Color{ 30, 24, 14, 220 }
        } else           { row_bg = rl.Color{ 18, 14, 10, 200 } }
        rl.DrawRectangleRec(row_r, row_bg)
        rl.DrawRectangleLinesEx(row_r, 1,
            COL_BRASS if is_listening else (COL_RULE if is_hot else rl.Color{ 55, 48, 34, 80 }))

        rl.DrawTextEx(g_font, rows[i].label,
            { px + uis(20), ry + uis(BIND_ROW_H)*0.5 - lfs*0.5 },
            lfs, 0.5, COL_PARCH if !is_listening else COL_BRASS)

        key_str: cstring
        if is_listening {
            key_str = t(.KEYBINDS_PRESS_KEY)
        } else {
            key_str = key_name(rl.KeyboardKey(rows[i].ptr^), name_buf[:])
        }
        kcol := COL_BRASS if is_listening else rl.Color{ 180, 160, 90, 220 }
        ksz  := rl.MeasureTextEx(g_font, key_str, lfs, 0.5)
        rl.DrawTextEx(g_font, key_str,
            { px + uis(PW) - uis(20) - ksz.x, ry + uis(BIND_ROW_H)*0.5 - lfs*0.5 },
            lfs, 0.5, kcol)
    }

    // ── Footer buttons ───────────────────────────────────────────────────────
    footer_y  := content_y + uis(_bind_content_h()) + uis(16)
    rlbl_fs   := uis(13)

    reset_r   := rl.Rectangle{ px + uis(8), footer_y, uis(PW * 0.5 - 16), uis(36) }
    reset_hot := rl.CheckCollisionPointRec(mp, reset_r) && g_rebind_idx < 0
    rl.DrawRectangleRec(reset_r, rl.Color{ 28, 14, 10, 240 } if reset_hot else rl.Color{ 18, 10, 8, 220 })
    rl.DrawRectangleLinesEx(reset_r, 1, COL_RULE)
    reset_lbl := t(.KEYBINDS_BTN_RESET)
    rlbl_sz   := rl.MeasureTextEx(g_font, reset_lbl, rlbl_fs, 0.5)
    rl.DrawTextEx(g_font, reset_lbl,
        { reset_r.x + reset_r.width*0.5 - rlbl_sz.x*0.5,
          reset_r.y + reset_r.height*0.5 - rlbl_fs*0.5 },
        rlbl_fs, 0.5, rl.Color{ 200, 120, 80, 220 } if reset_hot else COL_MUTED)

    close_r   := rl.Rectangle{ px + uis(PW * 0.5 + 8), footer_y, uis(PW * 0.5 - 16), uis(36) }
    close_hot := rl.CheckCollisionPointRec(mp, close_r) && g_rebind_idx < 0
    rl.DrawRectangleRec(close_r, rl.Color{ 28, 22, 16, 240 } if close_hot else rl.Color{ 18, 14, 10, 220 })
    rl.DrawRectangleLinesEx(close_r, 1, COL_RULE if !close_hot else COL_BRASS)
    close_lbl := t(.KEYBINDS_BTN_CLOSE)
    clbl_sz   := rl.MeasureTextEx(g_font, close_lbl, rlbl_fs, 0.5)
    rl.DrawTextEx(g_font, close_lbl,
        { close_r.x + close_r.width*0.5 - clbl_sz.x*0.5,
          close_r.y + close_r.height*0.5 - rlbl_fs*0.5 },
        rlbl_fs, 0.5, COL_BRASS if close_hot else COL_PARCH)

    if g_rebind_idx >= 0 {
        hint    := t(.KEYBINDS_ESC_CANCEL)
        hint_fs := uis(11)
        hsz     := rl.MeasureTextEx(g_font, hint, hint_fs, 0.5)
        rl.DrawTextEx(g_font, hint,
            { px + uis(PW)*0.5 - hsz.x*0.5, footer_y + uis(44) },
            hint_fs, 0.5, COL_MUTED)
    }
}

@(private = "file")
_draw_bind_section_header :: proc(px, ry, pw, fs: f32, label: cstring) {
    rl.DrawLineEx(
        { px + uis(8),      ry + fs * 0.5 },
        { px + uis(48),     ry + fs * 0.5 }, 1, COL_RULE)
    lsz := rl.MeasureTextEx(g_font, label, fs, 0.5)
    rl.DrawTextEx(g_font, label,
        { px + uis(54), ry }, fs, 0.5, COL_MUTED)
    rl.DrawLineEx(
        { px + uis(60) + lsz.x, ry + fs * 0.5 },
        { px + pw - uis(8),     ry + fs * 0.5 }, 1, COL_RULE)
}
SETTINGS_H_BASE          :: f32(648)
SETTINGS_Y_RES_BASE       :: f32(80)
SETTINGS_Y_MODE_BASE      :: f32(162)
SETTINGS_Y_LANG_BASE      :: f32(244)   // language selector row
SETTINGS_Y_VOL_BASE       :: f32(338)   // first slider row_y
SETTINGS_VOL_ROW_H_BASE   :: f32(34)
SETTINGS_Y_KEYBINDS_BASE  :: f32(490)
SETTINGS_Y_CLOSE_BASE     :: f32(542)
SETTINGS_Y_EXIT_BASE      :: f32(596)

settings_H          :: proc() -> i32 { return i32(uis(SETTINGS_H_BASE))         }
settings_y_res      :: proc() -> i32 { return i32(uis(SETTINGS_Y_RES_BASE))     }
settings_y_mode     :: proc() -> i32 { return i32(uis(SETTINGS_Y_MODE_BASE))    }
settings_y_lang     :: proc() -> i32 { return i32(uis(SETTINGS_Y_LANG_BASE))    }
settings_y_vol      :: proc() -> i32 { return i32(uis(SETTINGS_Y_VOL_BASE))     }
settings_vol_row_h  :: proc() -> i32 { return i32(uis(SETTINGS_VOL_ROW_H_BASE)) }
settings_y_keybinds :: proc() -> i32 { return i32(uis(SETTINGS_Y_KEYBINDS_BASE))}
settings_y_close    :: proc() -> i32 { return i32(uis(SETTINGS_Y_CLOSE_BASE))   }
settings_y_exit     :: proc() -> i32 { return i32(uis(SETTINGS_Y_EXIT_BASE))    }

update_settings_overlay :: proc() {
    sw  := rl.GetScreenWidth()
    sh  := rl.GetScreenHeight()
    pW  := pause_W()   // same width as pause panel
    pH  := settings_H()
    pBW := pause_btn_w()
    pBH := pause_btn_h()
    px  := sw / 2 - pW / 2
    py  := sh / 2 - pH / 2
    mp  := rl.GetMousePosition()
    bx  := f32(px) + f32(pW - pBW) / 2

    if !g_borderless {
        arrow_sz := f32(pBH)
        res_y    := f32(py + settings_y_res())
        l_rect   := rl.Rectangle{ f32(px + 16), res_y, arrow_sz, arrow_sz }
        r_rect   := rl.Rectangle{ f32(px + pW - 16) - arrow_sz, res_y, arrow_sz, arrow_sz }
        if rl.CheckCollisionPointRec(mp, l_rect) && rl.IsMouseButtonPressed(.LEFT) {
            g_pause_res_idx = (g_pause_res_idx - 1 + len(PAUSE_RESOLUTIONS)) % len(PAUSE_RESOLUTIONS)
            apply_resolution(g_pause_res_idx)
        }
        if rl.CheckCollisionPointRec(mp, r_rect) && rl.IsMouseButtonPressed(.LEFT) {
            g_pause_res_idx = (g_pause_res_idx + 1) % len(PAUSE_RESOLUTIONS)
            apply_resolution(g_pause_res_idx)
        }
    }

    {
        arrow_sz := f32(pBH)
        mode_y   := f32(py + settings_y_mode())
        l_rect   := rl.Rectangle{ f32(px + 16), mode_y, arrow_sz, arrow_sz }
        r_rect   := rl.Rectangle{ f32(px + pW - 16) - arrow_sz, mode_y, arrow_sz, arrow_sz }
        if (rl.CheckCollisionPointRec(mp, l_rect) || rl.CheckCollisionPointRec(mp, r_rect)) &&
            rl.IsMouseButtonPressed(.LEFT) {
            set_window_mode(!g_borderless)
        }
    }

    {
        arrow_sz := f32(pBH)
        lang_y   := f32(py + settings_y_lang())
        l_rect   := rl.Rectangle{ f32(px + 16), lang_y, arrow_sz, arrow_sz }
        r_rect   := rl.Rectangle{ f32(px + pW - 16) - arrow_sz, lang_y, arrow_sz, arrow_sz }
        lp := rl.CheckCollisionPointRec(mp, l_rect) && rl.IsMouseButtonPressed(.LEFT)
        rp := rl.CheckCollisionPointRec(mp, r_rect) && rl.IsMouseButtonPressed(.LEFT)
        if lp { _apply_lang(Language((int(g_lang) - 1 + LANG_COUNT) % LANG_COUNT)) }
        if rp { _apply_lang(Language((int(g_lang) + 1)              % LANG_COUNT)) }
    }

    if rl.IsMouseButtonDown(.LEFT) {
        rh := settings_vol_row_h()
        vol_ys := [4]i32{
            py + settings_y_vol() + rh * 0,
            py + settings_y_vol() + rh * 1,
            py + settings_y_vol() + rh * 2,
            py + settings_y_vol() + rh * 3,
        }
        vol_ptrs := [4]^f32{ &g_vol_sfx, &g_vol_music, &g_vol_ambience, &g_vol_voice }
        changed := false
        for i in 0..<4 {
            bx_i, _, bw_i, hit := vol_bar_dims(px, vol_ys[i])
            if rl.CheckCollisionPointRec(mp, hit) {
                vol_ptrs[i]^ = clamp((mp.x - f32(bx_i)) / f32(bw_i), 0, 1)
                changed = true
                break
            }
        }
        if changed { apply_bus_volumes() }
    }

    if rl.CheckCollisionPointRec(mp,
        { bx, f32(py + settings_y_keybinds()), f32(pBW), f32(pBH) }) &&
       rl.IsMouseButtonPressed(.LEFT) {
        ui_open(.Keybinds)
    }

    if rl.CheckCollisionPointRec(mp,
        { bx, f32(py + settings_y_close()), f32(pBW), f32(pBH) }) &&
       rl.IsMouseButtonPressed(.LEFT) {
        ui_close_top()
        return
    }

    if rl.CheckCollisionPointRec(mp,
        { bx, f32(py + settings_y_exit()), f32(pBW), f32(pBH) }) &&
       rl.IsMouseButtonPressed(.LEFT) {
        g_should_exit = true
        return
    }
}

draw_settings_overlay :: proc() {
    sw  := rl.GetScreenWidth()
    sh  := rl.GetScreenHeight()
    pW  := pause_W()
    pH  := settings_H()
    pBW := pause_btn_w()
    pBH := pause_btn_h()
    px  := sw / 2 - pW / 2
    py  := sh / 2 - pH / 2
    mp  := rl.GetMousePosition()
    bx  := f32(px) + f32(pW - pBW) / 2

    rl.DrawRectangle(0, 0, sw, sh, rl.Color{ 0, 0, 0, 165 })

    rl.DrawRectangle(px, py, pW, pH, rl.Color{ 8, 6, 4, 252 })
    rl.DrawRectangle(px, py, pW, 3, COL_BRASS)
    rl.DrawRectangleLinesEx({ f32(px), f32(py), f32(pW), f32(pH) }, 2, COL_RULE)

    title    := t(.SETTINGS_TITLE)
    title_fs := uis(24)
    title_sz := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title,
        { f32(px) + f32(pW) * 0.5 - title_sz.x * 0.5, f32(py) + uis(16) },
        title_fs, 1, COL_PARCH)
    rl.DrawLineEx(
        { f32(px) + 16, f32(py) + uis(52) },
        { f32(px + pW) - 16, f32(py) + uis(52) }, 1, COL_RULE)

    res_label := PAUSE_RESOLUTIONS[g_pause_res_idx].label
    pause_arrow_row(px, py + settings_y_res(), t(.SETTINGS_RESOLUTION), res_label, mp,
        enabled = !g_borderless)

    mode_label := t(.SETTINGS_BORDERLESS) if g_borderless else t(.SETTINGS_WINDOWED)
    pause_arrow_row(px, py + settings_y_mode(), t(.SETTINGS_WINDOW_MODE), mode_label, mp)

    pause_arrow_row(px, py + settings_y_lang(), t(.SETTINGS_LANGUAGE), lang_name(g_lang), mp)

    {
        vol_hdr    := t(.SETTINGS_VOLUME)
        vol_hdr_fs := uis(13)
        vol_hdr_sz := rl.MeasureTextEx(g_font, vol_hdr, vol_hdr_fs, 1)
        vol_row_y  := f32(py + settings_y_vol())
        rl.DrawLineEx(
            { f32(px) + 16, vol_row_y - uis(10) },
            { f32(px + pW) - 16, vol_row_y - uis(10) }, 1, COL_RULE)
        rl.DrawTextEx(g_font, vol_hdr,
            { f32(px) + f32(pW) * 0.5 - vol_hdr_sz.x * 0.5, vol_row_y - uis(22) },
            vol_hdr_fs, 1, COL_MUTED)

        rh := settings_vol_row_h()
        draw_vol_slider(px, py + settings_y_vol() + rh * 0, t(.SETTINGS_SFX),      g_vol_sfx,      mp)
        draw_vol_slider(px, py + settings_y_vol() + rh * 1, t(.SETTINGS_MUSIC),    g_vol_music,    mp)
        draw_vol_slider(px, py + settings_y_vol() + rh * 2, t(.SETTINGS_AMBIENCE), g_vol_ambience, mp)
        draw_vol_slider(px, py + settings_y_vol() + rh * 3, t(.SETTINGS_VOICE),    g_vol_voice,    mp)
    }

    rl.DrawLineEx(
        { f32(px) + 16, f32(py + settings_y_keybinds()) - 12 },
        { f32(px + pW) - 16, f32(py + settings_y_keybinds()) - 12 }, 1, COL_RULE)
    draw_pause_btn(
        { bx, f32(py + settings_y_keybinds()), f32(pBW), f32(pBH) },
        t(.SETTINGS_BTN_KEYBINDS), mp)

    rl.DrawLineEx(
        { f32(px) + 16, f32(py + settings_y_close()) - 12 },
        { f32(px + pW) - 16, f32(py + settings_y_close()) - 12 }, 1, COL_RULE)
    draw_pause_btn(
        { bx, f32(py + settings_y_close()), f32(pBW), f32(pBH) },
        t(.SETTINGS_BTN_CLOSE), mp)

    rl.DrawLineEx(
        { f32(px) + 16, f32(py + settings_y_exit()) - 10 },
        { f32(px + pW) - 16, f32(py + settings_y_exit()) - 10 }, 1, COL_RULE)
    {
        exit_r   := rl.Rectangle{ bx, f32(py + settings_y_exit()), f32(pBW), f32(pBH) }
        exit_hot := rl.CheckCollisionPointRec(mp, exit_r)
        exit_bg  := rl.Color{ 48, 16, 12, 240 } if exit_hot else rl.Color{ 28, 10, 8, 240 }
        exit_bdr := rl.Color{ 200, 70, 50, 220 } if exit_hot else rl.Color{ 100, 35, 25, 180 }
        exit_txt := rl.Color{ 235, 100, 75, 255 } if exit_hot else rl.Color{ 160, 60, 45, 220 }
        rl.DrawRectangleRec(exit_r, exit_bg)
        rl.DrawRectangleLinesEx(exit_r, 1, exit_bdr)
        exit_lbl := t(.SETTINGS_BTN_EXIT)
        exit_fs  := uis(18)
        exit_sz  := rl.MeasureTextEx(g_font, exit_lbl, exit_fs, 1)
        rl.DrawTextEx(g_font, exit_lbl,
            { exit_r.x + exit_r.width * 0.5 - exit_sz.x * 0.5,
              exit_r.y + exit_r.height * 0.5 - exit_fs * 0.5 },
            exit_fs, 1, exit_txt)
    }
}

@(private = "file")
g_icon_cache: map[string]rl.Texture2D

@(private = "file")
EntitySpriteEntry :: struct {
    tex:     rl.Texture2D,
    src:     rl.Rectangle,
    rt:      rl.RenderTexture2D,
    from_rt: bool,
}

@(private = "file")
g_entity_sprite_cache: map[string]EntitySpriteEntry

init_icon_cache :: proc() {
    g_icon_cache = make(map[string]rl.Texture2D)
    g_entity_sprite_cache = make(map[string]EntitySpriteEntry)
}

shutdown_icon_cache :: proc() {
    for key, tex in g_icon_cache {
        if tex.id != 0 { rl.UnloadTexture(tex) }
        delete(key)   // free the strings.clone'd key
    }
    delete(g_icon_cache)

    for key, entry in g_entity_sprite_cache {
        if entry.from_rt {
            rl.UnloadRenderTexture(entry.rt)
        } else if entry.tex.id != 0 {
            rl.UnloadTexture(entry.tex)
        }
        delete(key)
    }
    delete(g_entity_sprite_cache)
}

get_or_load_icon :: proc(stem: cstring) -> (tex: rl.Texture2D, ok: bool) {
    key := string(stem)
    if cached, found := g_icon_cache[key]; found {
        return cached, cached.id != 0
    }
    path_buf: [256]u8
    n  := copy(path_buf[:], "data/sprites/items/")
    n  += copy(path_buf[n:], key)
    n  += copy(path_buf[n:], ".png")
    path_buf[n] = 0

    loaded := rl.LoadTexture(cstring(&path_buf[0]))
    owned_key := strings.clone(key)
    g_icon_cache[owned_key] = loaded
    return loaded, loaded.id != 0
}

@(private = "file")
color_mix :: proc(a, b: rl.Color, t: f32) -> rl.Color {
    tt := clamp(t, 0, 1)
    return rl.Color{
        u8(math.lerp(f32(a.r), f32(b.r), tt)),
        u8(math.lerp(f32(a.g), f32(b.g), tt)),
        u8(math.lerp(f32(a.b), f32(b.b), tt)),
        u8(math.lerp(f32(a.a), f32(b.a), tt)),
    }
}

@(private = "file")
build_fallback_entity_sprite :: proc(key: string) -> EntitySpriteEntry {
    size :: 64
    rt := rl.LoadRenderTexture(size, size)
    rl.BeginTextureMode(rt)
    rl.ClearBackground(rl.BLANK)

    base  := rl.Color{ 116, 38, 34, 255 }
    shade := rl.Color{ 68, 18, 16, 255 }
    glow  := rl.Color{ 220, 160, 100, 220 }
    eye   := rl.Color{ 236, 240, 214, 255 }

    switch key {
    case "player_wanderer":
        base  = rl.Color{ 82, 96, 118, 255 }
        shade = rl.Color{ 44, 52, 68, 255 }
        glow  = rl.Color{ 218, 112, 72, 220 }
    case "enemy_brute":
        base  = rl.Color{ 90, 40, 26, 255 }
        shade = rl.Color{ 48, 18, 14, 255 }
        glow  = rl.Color{ 210, 130, 46, 220 }
    case "enemy_hunter":
        base  = rl.Color{ 46, 88, 68, 255 }
        shade = rl.Color{ 20, 42, 32, 255 }
        glow  = rl.Color{ 120, 220, 148, 210 }
    case "enemy_ranged", "enemy_sniper":
        base  = rl.Color{ 44, 74, 112, 255 }
        shade = rl.Color{ 18, 30, 56, 255 }
        glow  = rl.Color{ 120, 180, 235, 220 }
    case "npc_shopkeeper":
        base  = rl.Color{ 108, 84, 54, 255 }
        shade = rl.Color{ 52, 36, 22, 255 }
        glow  = rl.Color{ 212, 190, 92, 220 }
    case "mutation_workbench":
        rl.DrawRectangle(14, 20, 36, 28, rl.Color{ 50, 26, 58, 255 })
        rl.DrawRectangle(18, 24, 28, 20, rl.Color{ 84, 44, 94, 255 })
        rl.DrawRectangle(10, 16, 44, 8, rl.Color{ 122, 76, 50, 255 })
        rl.DrawRectangle(16, 10, 32, 8, rl.Color{ 90, 52, 112, 255 })
        rl.DrawRectangle(22, 6, 20, 6, rl.Color{ 208, 108, 255, 220 })
        rl.DrawRectangle(24, 2, 16, 6, rl.Color{ 255, 210, 120, 220 })
        rl.DrawRectangle(8, 48, 10, 10, rl.Color{ 66, 38, 24, 255 })
        rl.DrawRectangle(46, 48, 10, 10, rl.Color{ 66, 38, 24, 255 })
        rl.DrawRectangle(20, 44, 24, 6, rl.Color{ 40, 18, 46, 255 })
        rl.EndTextureMode()
        return EntitySpriteEntry{
            tex     = rt.texture,
            src     = { 0, 0, f32(size), -f32(size) },
            rt      = rt,
            from_rt = true,
        }
    case "env_door":
        // Wooden door with frame and knob
        rl.DrawRectangle(10,  6, 44, 52, rl.Color{ 60, 36, 14, 255})  // frame
        rl.DrawRectangle(12,  8, 40, 48, rl.Color{ 96, 58, 22, 255})  // door face
        rl.DrawRectangle(14, 10, 16, 20, rl.Color{ 80, 48, 18, 255})  // upper-left panel
        rl.DrawRectangle(34, 10, 16, 20, rl.Color{ 80, 48, 18, 255})  // upper-right panel
        rl.DrawRectangle(14, 34, 16, 18, rl.Color{ 80, 48, 18, 255})  // lower-left panel
        rl.DrawRectangle(34, 34, 16, 18, rl.Color{ 80, 48, 18, 255})  // lower-right panel
        rl.DrawCircle(37, 28, 3, rl.Color{200, 158, 50, 255})         // knob
        rl.DrawCircle(37, 28, 2, rl.Color{220, 180, 80, 255})         // knob highlight
        rl.DrawRectangle( 8, 56,  48, 4, rl.Color{ 48, 28, 10, 255}) // threshold
        rl.EndTextureMode()
        return EntitySpriteEntry{
            tex = rt.texture, src = {0, 0, f32(size), -f32(size)}, rt = rt, from_rt = true,
        }
    case "env_switch":
        // Wall-mounted lever
        rl.DrawRectangle(18, 36, 28, 22, rl.Color{ 50, 50, 60, 255}) // base plate
        rl.DrawRectangle(20, 38, 24, 18, rl.Color{ 68, 68, 80, 255}) // plate face
        rl.DrawRectangle(22, 40,  8,  4, rl.Color{ 80,180, 70, 255}) // indicator light
        rl.DrawRectangle(30, 14,  4, 30, rl.Color{130, 80, 26, 255}) // lever shaft
        rl.DrawCircle(32, 14, 6, rl.Color{180, 116, 40, 255})        // handle ball
        rl.DrawCircle(32, 14, 4, rl.Color{210, 150, 60, 255})        // ball highlight
        rl.EndTextureMode()
        return EntitySpriteEntry{
            tex = rt.texture, src = {0, 0, f32(size), -f32(size)}, rt = rt, from_rt = true,
        }
    case "env_chest":
        // Treasure chest with iron bands
        rl.DrawRectangle( 8, 34, 48, 26, rl.Color{ 88, 54, 20, 255}) // body
        rl.DrawRectangle(10, 36, 44, 22, rl.Color{108, 68, 26, 255}) // body face
        rl.DrawRectangle( 8, 22, 48, 14, rl.Color{ 72, 44, 16, 255}) // lid
        rl.DrawRectangle(10, 24, 44, 11, rl.Color{ 90, 56, 20, 255}) // lid face
        rl.DrawRectangle( 8, 44, 48,  4, rl.Color{168, 130, 50, 255}) // horizontal band
        rl.DrawRectangle(28, 36,  8,  8, rl.Color{180, 148, 52, 255}) // clasp
        rl.DrawRectangle(30, 38,  4,  4, rl.Color{220, 188, 90, 255}) // clasp gem
        rl.EndTextureMode()
        return EntitySpriteEntry{
            tex = rt.texture, src = {0, 0, f32(size), -f32(size)}, rt = rt, from_rt = true,
        }
    case "env_crate":
        // Wooden crate with cross-brace planks
        rl.DrawRectangle( 8, 10, 48, 48, rl.Color{ 90, 58, 24, 255}) // box
        rl.DrawRectangle(10, 12, 44, 44, rl.Color{112, 72, 28, 255}) // face
        rl.DrawRectangle( 8, 10, 48,  4, rl.Color{ 70, 42, 16, 255}) // top edge
        rl.DrawRectangle( 8, 54, 48,  4, rl.Color{ 70, 42, 16, 255}) // bottom edge
        rl.DrawRectangle( 8, 10,  4, 48, rl.Color{ 70, 42, 16, 255}) // left edge
        rl.DrawRectangle(52, 10,  4, 48, rl.Color{ 70, 42, 16, 255}) // right edge
        rl.DrawRectangle( 8, 30, 48,  4, rl.Color{ 70, 42, 16, 255}) // mid horiz
        rl.DrawRectangle(30, 10,  4, 48, rl.Color{ 70, 42, 16, 255}) // mid vert
        rl.EndTextureMode()
        return EntitySpriteEntry{
            tex = rt.texture, src = {0, 0, f32(size), -f32(size)}, rt = rt, from_rt = true,
        }
    case "env_lore_item":
        // Folded parchment document
        rl.DrawRectangle(14,  6, 36, 48, rl.Color{198, 176, 126, 255}) // paper
        rl.DrawRectangle(16,  8, 32, 44, rl.Color{210, 192, 146, 255}) // paper face
        rl.DrawRectangle(14,  6, 12, 12, rl.Color{180, 158, 108, 255}) // fold triangle bg
        rl.DrawRectangle(16,  8,  4,  8, rl.Color{198, 176, 126, 255}) // fold detail
        rl.DrawRectangle(19, 18, 26,  2, rl.Color{120, 100,  60, 160}) // text line 1
        rl.DrawRectangle(19, 24, 26,  2, rl.Color{120, 100,  60, 160}) // text line 2
        rl.DrawRectangle(19, 30, 26,  2, rl.Color{120, 100,  60, 160}) // text line 3
        rl.DrawRectangle(19, 36, 18,  2, rl.Color{120, 100,  60, 160}) // text line 4 (short)
        rl.EndTextureMode()
        return EntitySpriteEntry{
            tex = rt.texture, src = {0, 0, f32(size), -f32(size)}, rt = rt, from_rt = true,
        }
    case "env_phonograph":
        // Wax cylinder phonograph with horn
        rl.DrawRectangle( 8, 36, 28, 16, rl.Color{ 72, 44, 18, 255}) // cabinet
        rl.DrawRectangle(10, 38, 24, 12, rl.Color{ 92, 56, 22, 255}) // cabinet face
        rl.DrawRectangle(10, 40, 24,  8, rl.Color{ 78, 48, 20, 255}) // cylinder slot
        rl.DrawEllipse(22, 44, 10, 4, rl.Color{ 40, 40, 40, 220})    // cylinder end
        rl.DrawEllipseLines(22, 44, 10, 4, rl.Color{100, 100,110,255})
        // Horn: triangular shape pointing up-right
        rl.DrawTriangle(
            {36, 52}, {54, 10}, {54, 52},
            rl.Color{180, 130, 50, 200})
        rl.DrawTriangleLines(
            {36, 52}, {54, 10}, {54, 52},
            rl.Color{220, 170, 70, 220})
        rl.DrawEllipse(45, 10, 9, 4, rl.Color{200, 160, 60, 160})   // horn mouth
        rl.EndTextureMode()
        return EntitySpriteEntry{
            tex = rt.texture, src = {0, 0, f32(size), -f32(size)}, rt = rt, from_rt = true,
        }
    case "env_key":
        // Ornate key: ring head + shaft + teeth
        rl.DrawCircle(20, 24, 14, rl.Color{180, 148, 40, 255})       // ring outer
        rl.DrawCircle(20, 24, 10, rl.Color{130,  96, 22, 255})       // ring inner (hole)
        rl.DrawCircle(20, 24,  5, rl.Color{180, 148, 40, 255})       // center hub
        rl.DrawRectangle(30, 21, 26,  6, rl.Color{200, 162, 48, 255}) // shaft
        rl.DrawRectangle(48, 27,  4,  8, rl.Color{200, 162, 48, 255}) // tooth 1
        rl.DrawRectangle(42, 27,  4,  6, rl.Color{200, 162, 48, 255}) // tooth 2
        rl.DrawRectangle(36, 27,  4,  4, rl.Color{200, 162, 48, 255}) // tooth 3
        rl.EndTextureMode()
        return EntitySpriteEntry{
            tex = rt.texture, src = {0, 0, f32(size), -f32(size)}, rt = rt, from_rt = true,
        }
    }

    rl.DrawRectangle(22, 6, 20, 8, glow)
    rl.DrawRectangle(18, 14, 28, 12, shade)
    rl.DrawRectangle(20, 16, 24, 10, base)
    rl.DrawRectangle(16, 24, 32, 18, shade)
    rl.DrawRectangle(18, 24, 28, 16, base)
    rl.DrawRectangle(22, 40, 8, 16, shade)
    rl.DrawRectangle(34, 40, 8, 16, shade)
    rl.DrawRectangle(24, 40, 4, 14, base)
    rl.DrawRectangle(36, 40, 4, 14, base)
    rl.DrawRectangle(12, 28, 6, 10, shade)
    rl.DrawRectangle(46, 28, 6, 10, shade)
    rl.DrawRectangle(14, 28, 4, 8, base)
    rl.DrawRectangle(46, 28, 4, 8, base)
    rl.DrawRectangle(24, 18, 4, 4, eye)
    rl.DrawRectangle(36, 18, 4, 4, eye)
    rl.DrawRectangle(28, 22, 8, 3, rl.Color{ 26, 18, 16, 180 })

    rl.EndTextureMode()
    return EntitySpriteEntry{
        tex     = rt.texture,
        src     = { 0, 0, f32(size), -f32(size) },
        rt      = rt,
        from_rt = true,
    }
}

get_or_load_entity_sprite :: proc(stem: cstring) -> (entry: EntitySpriteEntry, ok: bool) {
    key := string(stem)
    if cached, found := g_entity_sprite_cache[key]; found {
        return cached, true
    }

    path_buf: [256]u8
    n := copy(path_buf[:], "data/sprites/entities/")
    n += copy(path_buf[n:], key)
    n += copy(path_buf[n:], ".png")
    path_buf[n] = 0

    loaded := rl.LoadTexture(cstring(&path_buf[0]))
    if loaded.id != 0 {
        rl.SetTextureFilter(loaded, .POINT)
        entry = EntitySpriteEntry{
            tex = loaded,
            src = { 0, 0, f32(loaded.width), f32(loaded.height) },
        }
    } else {
        entry = build_fallback_entity_sprite(key)
    }

    owned_key := strings.clone(key)
    g_entity_sprite_cache[owned_key] = entry
    return entry, true
}

draw_entity_sprite_quad :: proc(entry: EntitySpriteEntry, pos: rl.Vector2, world_size: f32, rotation_rad: f32, tint: rl.Color) {
    draw_entity_sprite_quad_ex(entry.tex, entry.src, pos, world_size, rotation_rad, tint)
}

// ISO_SPRITE_Y is the vertical scale applied to all entity sprite quads so
// that their screen footprint matches the 2:1 isometric projection.
// (ISO_TILE_H / ISO_TILE_W = 0.5)
ISO_SPRITE_Y :: ISO_TILE_H / ISO_TILE_W   // = 0.5

draw_entity_sprite_quad_ex :: proc(tex: rl.Texture2D, src: rl.Rectangle, pos: rl.Vector2, world_size: f32, rotation_rad: f32, tint: rl.Color) {
    iso     := world_to_iso_v(pos)
    iso_h   := world_size * ISO_SPRITE_Y
    dst     := rl.Rectangle{ iso.x, iso.y, world_size, iso_h }
    origin  := rl.Vector2{ world_size * 0.5, iso_h * 0.5 }
    iso_rot := world_rot_to_iso(rotation_rad)
    rl.DrawTexturePro(tex, src, dst, origin, math.to_degrees(iso_rot) + 90.0, tint)
}







shop_panel_origin :: proc() -> (px, py: i32) {
    shop_w   := i32(uis(480))
    shop_h   := i32(uis(520))
    game_w   := rl.GetScreenWidth() - g_inv.panel_w   // usable left area
    left_x   := (game_w - shop_w) / 2
    top_y    := rl.GetScreenHeight() / 2 - shop_h / 2
    return left_x, top_y
}



@(private = "file")
draw_text_wrapped :: proc(
    font: rl.Font, text: cstring,
    x, y, fs, max_w, spacing: f32,
    color: rl.Color,
) -> f32 {
    str        := string(text)
    line_h     := fs + uis(3)
    cur_y      := y
    line_start := 0
    last_space := -1
    for i := 0; i <= len(str); i += 1 {
        ch := str[i] if i < len(str) else ' '
        if ch == ' ' || i == len(str) {
            seg    := str[line_start:i]
            seg_cs := strings.clone_to_cstring(seg, context.temp_allocator)
            sz     := rl.MeasureTextEx(font, seg_cs, fs, spacing)
            if sz.x > max_w && last_space > line_start {
                line := strings.clone_to_cstring(str[line_start:last_space], context.temp_allocator)
                rl.DrawTextEx(font, line, { x, cur_y }, fs, spacing, color)
                cur_y      += line_h
                line_start  = last_space + 1
            }
            last_space = i
        }
    }
    if line_start < len(str) {
        rl.DrawTextEx(font,
            strings.clone_to_cstring(str[line_start:], context.temp_allocator),
            { x, cur_y }, fs, spacing, color)
        cur_y += line_h
    }
    return cur_y - y
}

draw_item_tooltip :: proc(w: ^cw.World, item_id: int, mx, my: f32) {
    if !cw.world_is_valid(w, item_id)             { return }
    if !cw.world_has_component(w, item_id, .Item) { return }

    item := cw.world_get_item(w, item_id)
    rc   := rarity_color(item.rarity)

    has_desc := false
    desc_str: cstring = ""
    if cw.world_has_component(w, item_id, .RenderConfig) {
        rcc := cw.world_get_render_config(w, item_id)
        if rcc.desc_len > 0 {
            has_desc = true
            desc_str = loc_lookup(cw.render_config_desc_cstr(rcc))
        }
    }

    affix_count := int(item.affix_count)
    req_count   := (1 if item.req_str > 0 else 0) +
                   (1 if item.req_dex > 0 else 0) +
                   (1 if item.req_sci > 0 else 0)

    // Count stat display lines for tooltip height.
    stat_line_count := 0
    if item.weapon_archetype != .None && !item.is_melee {
        if item.base_damage > 0      { stat_line_count += 1 }
        if item.base_fire_rate > 0   { stat_line_count += 1 }
        if item.base_ammo_max > 0    { stat_line_count += 1 }
        if item.base_reload_time > 0 { stat_line_count += 1 }
    } else if item.is_melee {
        if item.melee_damage > 0       { stat_line_count += 1 }
        if item.melee_cooldown_max > 0 { stat_line_count += 1 }
    }
    if item.base_armor > 0  { stat_line_count += 1 }
    if item.base_shield > 0 { stat_line_count += 1 }
    stat_extra_h := i32(0)
    if stat_line_count > 0 {
        stat_extra_h = i32(uis(17)) * i32(stat_line_count) + i32(uis(6))
    }

    TW := i32(uis(238))
    TH := i32(uis(108)) +
          stat_extra_h +
          i32(uis(17)) * i32(req_count)   +
          i32(uis(17)) * i32(affix_count) +
          (i32(uis(30)) if has_desc else 0)
    IS := i32(uis(64))

    tx := i32(mx) + i32(uis(18))
    ty := i32(my) - TH / 2
    if tx + TW  > rl.GetScreenWidth()  { tx = i32(mx) - TW - i32(uis(10)) }
    if ty < 4                          { ty = 4 }
    if ty + TH  > rl.GetScreenHeight() { ty = rl.GetScreenHeight() - TH - 4 }

    rl.DrawRectangle(tx, ty, TW, TH, rl.Color{ 6, 4, 3, 252 })
    rl.DrawRectangle(tx, ty, TW, 3,  rl.Color{ rc.r, rc.g, rc.b, 230 })
    rl.DrawRectangleLinesEx({ f32(tx), f32(ty), f32(TW), f32(TH) }, 1,
        rl.Color{ rc.r, rc.g, rc.b, 160 })

    icon_x := tx + i32(uis(10))
    icon_y := ty + i32(uis(10))

    rl.DrawRectangle(icon_x - 2, icon_y - 2, IS + 4, IS + 4,
        rl.Color{ rc.r / 5, rc.g / 5, rc.b / 5, 200 })
    rl.DrawRectangleLinesEx(
        { f32(icon_x - 2), f32(icon_y - 2), f32(IS + 4), f32(IS + 4) }, 1,
        rl.Color{ rc.r, rc.g, rc.b, 100 })

    icon_drawn := false
    if cw.world_has_component(w, item_id, .RenderConfig) {
        rcc := cw.world_get_render_config(w, item_id)
        if rcc.icon_len > 0 {
            tex, ok := get_or_load_icon(cw.render_config_icon_cstr(rcc))
            if ok {
                src := rl.Rectangle{ 0, 0, f32(tex.width), f32(tex.height) }
                dst := rl.Rectangle{ f32(icon_x), f32(icon_y), f32(IS), f32(IS) }
                rl.DrawTexturePro(tex, src, dst, {0, 0}, 0,
                    rl.Color{ rc.r, rc.g, rc.b, 220 })
                icon_drawn = true
            }
        }
    }
    if !icon_drawn {
        draw_item_glyph(item.slot, icon_x, icon_y, IS, rc)
    }

    div_x := tx + IS + i32(uis(22))
    rl.DrawLineEx(
        { f32(div_x), f32(ty) + uis(8) },
        { f32(div_x), f32(ty + TH) - uis(8) },
        1, rl.Color{ rc.r, rc.g, rc.b, 80 })

    tx2  := f32(div_x) + uis(10)
    ty2  := f32(ty) + uis(12)
    fs15 := uis(15)
    fs13 := uis(13)
    text_w := f32(TW) - (tx2 - f32(tx)) - uis(8)

    if cw.world_has_component(w, item_id, .RenderConfig) {
        rcc  := cw.world_get_render_config(w, item_id)
        name := loc_lookup(cw.render_config_name_cstr(rcc))
        rl.DrawTextEx(g_font, name, { tx2, ty2 }, fs15, 0.5,
            rl.Color{ rc.r, rc.g, rc.b, 245 })
    }

    rarity_labels := [cw.ItemRarity]cstring{
        .Normal    = "Normal",
        .Rare      = "Rare",
        .Epic      = "Epic",
        .Legendary = "Legendary",
        .Unique    = "Unique",
    }
    rl.DrawTextEx(g_font, rarity_labels[item.rarity], { tx2, ty2 + uis(22) }, fs13, 0.5,
        rl.Color{ rc.r, rc.g, rc.b, 195 })

    if item.ability_type != .None {
        // Ability item: show type and cooldown instead of slot/size.
        def := ABILITY_DEFS[item.ability_type]
        type_lbl: cstring = "Passive Ability" if def.is_passive else "Active Ability"
        rl.DrawTextEx(g_font, type_lbl, { tx2, ty2 + uis(42) }, fs13, 0.5,
            rl.Color{ 200, 170, 100, 210 })
        cd_buf: [32]u8
        if def.is_passive {
            rl.DrawTextEx(g_font, "Passive", { tx2, ty2 + uis(60) }, fs13, 0.5, COL_MUTED)
        } else {
            cd_s := fmt.bprintf(cd_buf[:31], "Cooldown: %.0fs", def.cd_max)
            cd_buf[len(cd_s)] = 0
            rl.DrawTextEx(g_font, cstring(&cd_buf[0]), { tx2, ty2 + uis(60) }, fs13, 0.5, COL_MUTED)
        }
    } else {
        slot_labels := [cw.EquipSlot]cstring{
            .Head          = "Slot: Head",
            .Chest         = "Slot: Chest",
            .Boots         = "Slot: Boots",
            .WeaponPrimary = "Slot: Weapon I",
            .WeaponOffhand = "Slot: Weapon II",
            .Consumable    = "Consumable",
            .Ability1      = "Ability Skill",
            .Ability2      = "Ability Skill",
            .Ability3      = "Ability Skill",
            .Ability4      = "Ability Skill",
        }
        rl.DrawTextEx(g_font, slot_labels[item.slot], { tx2, ty2 + uis(42) }, fs13, 0.5, COL_MUTED)

        archetype_labels := [cw.WeaponArchetype]cstring{
            .None    = "",
            .Pistol  = "Pistol",
            .Rifle   = "Rifle",
            .Shotgun = "Shotgun",
            .Axe     = "Axe",
            .Knife   = "Knife",
            .Sword   = "Sword",
        }
        if item.weapon_archetype != .None {
            rl.DrawTextEx(g_font, archetype_labels[item.weapon_archetype],
                { tx2, ty2 + uis(60) }, fs13, 0.5, COL_MUTED)
        } else {
            size_buf: [32]u8
            size_str := fmt.bprintf(size_buf[:31], "%d x %d", item.grid_w, item.grid_h)
            size_buf[len(size_str)] = 0
            rl.DrawTextEx(g_font, cstring(&size_buf[0]), { tx2, ty2 + uis(60) }, fs13, 0.5, COL_MUTED)
        }
    }

    // ── Base stat block ───────────────────────────────────────────────────────
    // COL_STAT is the package-level constant defined in ui.odin
    stat_y := ty2 + uis(78)
    {
        sbuf: [48]u8
        if item.weapon_archetype != .None && !item.is_melee {
            if item.base_damage > 0 {
                s := fmt.bprintf(sbuf[:47], "DMG  %.0f", item.base_damage)
                sbuf[len(s)] = 0
                rl.DrawTextEx(g_font, cstring(&sbuf[0]), {tx2, stat_y}, fs13, 0.5, COL_STAT)
                stat_y += uis(17)
            }
            if item.base_fire_rate > 0 {
                s := fmt.bprintf(sbuf[:47], "RATE  %.1f/s", item.base_fire_rate)
                sbuf[len(s)] = 0
                rl.DrawTextEx(g_font, cstring(&sbuf[0]), {tx2, stat_y}, fs13, 0.5, COL_STAT)
                stat_y += uis(17)
            }
            if item.base_ammo_max > 0 {
                s := fmt.bprintf(sbuf[:47], "MAG  %d", int(item.base_ammo_max))
                sbuf[len(s)] = 0
                rl.DrawTextEx(g_font, cstring(&sbuf[0]), {tx2, stat_y}, fs13, 0.5, COL_STAT)
                stat_y += uis(17)
            }
            if item.base_reload_time > 0 {
                s := fmt.bprintf(sbuf[:47], "RELOAD  %.1fs", item.base_reload_time)
                sbuf[len(s)] = 0
                rl.DrawTextEx(g_font, cstring(&sbuf[0]), {tx2, stat_y}, fs13, 0.5, COL_STAT)
                stat_y += uis(17)
            }
        } else if item.is_melee {
            if item.melee_damage > 0 {
                s := fmt.bprintf(sbuf[:47], "DMG  %.0f", item.melee_damage)
                sbuf[len(s)] = 0
                rl.DrawTextEx(g_font, cstring(&sbuf[0]), {tx2, stat_y}, fs13, 0.5, COL_STAT)
                stat_y += uis(17)
            }
            if item.melee_cooldown_max > 0 {
                s := fmt.bprintf(sbuf[:47], "ATK SPD  %.1f/s", 1.0 / item.melee_cooldown_max)
                sbuf[len(s)] = 0
                rl.DrawTextEx(g_font, cstring(&sbuf[0]), {tx2, stat_y}, fs13, 0.5, COL_STAT)
                stat_y += uis(17)
            }
        }
        if item.base_armor > 0 {
            s := fmt.bprintf(sbuf[:47], "ARMOR  %.0f%%", item.base_armor * 100)
            sbuf[len(s)] = 0
            rl.DrawTextEx(g_font, cstring(&sbuf[0]), {tx2, stat_y}, fs13, 0.5, COL_STAT)
            stat_y += uis(17)
        }
        if item.base_shield > 0 {
            s := fmt.bprintf(sbuf[:47], "SHIELD  +%.0f", item.base_shield)
            sbuf[len(s)] = 0
            rl.DrawTextEx(g_font, cstring(&sbuf[0]), {tx2, stat_y}, fs13, 0.5, COL_STAT)
            stat_y += uis(17)
        }
        if stat_line_count > 0 { stat_y += uis(6) }
    }

    if req_count > 0 {
        player_str, player_dex, player_sci: int
        if cw.world_is_valid(w, w.player_id) &&
           cw.world_has_component(w, w.player_id, .Stats) {
            st         := cw.world_get_stats(w, w.player_id)
            player_str  = st.strength
            player_dex  = st.dexterity
            player_sci  = st.science
        }
        COL_REQ_MET   :: rl.Color{ 100, 210, 100, 220 }
        COL_REQ_UNMET :: rl.Color{ 220,  60,  60, 240 }
        req_row: int
        req_y_base := stat_y
        if item.req_str > 0 {
            col := COL_REQ_MET if player_str >= int(item.req_str) else COL_REQ_UNMET
            rbuf: [32]u8
            rs := fmt.bprintf(rbuf[:31], "STR %d required", item.req_str)
            rbuf[len(rs)] = 0
            rl.DrawTextEx(g_font, cstring(&rbuf[0]),
                { tx2, req_y_base + uis(17) * f32(req_row) }, fs13, 0.5, col)
            req_row += 1
        }
        if item.req_dex > 0 {
            col := COL_REQ_MET if player_dex >= int(item.req_dex) else COL_REQ_UNMET
            rbuf: [32]u8
            rs := fmt.bprintf(rbuf[:31], "DEX %d required", item.req_dex)
            rbuf[len(rs)] = 0
            rl.DrawTextEx(g_font, cstring(&rbuf[0]),
                { tx2, req_y_base + uis(17) * f32(req_row) }, fs13, 0.5, col)
            req_row += 1
        }
        if item.req_sci > 0 {
            col := COL_REQ_MET if player_sci >= int(item.req_sci) else COL_REQ_UNMET
            rbuf: [32]u8
            rs := fmt.bprintf(rbuf[:31], "SCI %d required", item.req_sci)
            rbuf[len(rs)] = 0
            rl.DrawTextEx(g_font, cstring(&rbuf[0]),
                { tx2, req_y_base + uis(17) * f32(req_row) }, fs13, 0.5, col)
        }
    }

    affix_type_labels := [cw.AffixType]string{
        .None             = "",
        .BonusHP          = "Max HP",
        .Armor            = "Armor",
        .BonusMoveSpeed   = "Move Speed",
        .BonusEnergy      = "Max Energy",
        .BonusDamage      = "Damage",
        .BonusFireRate    = "Fire Rate",
        .BonusReloadSpeed = "Reload Speed",
        .HealthRegen      = "HP Regen/s",
        .BonusProjSpeed   = "Proj Speed",
        .BonusPierce      = "Pierce",
        .BonusAmmo        = "Ammo",
        .BonusMeleeDamage = "Melee Damage",
        .BonusMeleeRange  = "Melee Range",
        .BonusMeleeSpeed  = "Attack Speed",
    }
    // COL_AFFIX is the package-level constant defined in ui.odin
    affix_base_y := stat_y + uis(17) * f32(req_count)
    for i in 0..<affix_count {
        a   := item.affixes[i]
        ay  := affix_base_y + uis(17) * f32(i)
        abuf: [32]u8
        as: string
        // BonusPierce is a flat count (1, 2, …) not a percentage.
        if a.type == .BonusPierce {
            as = fmt.bprintf(abuf[:31], "+%.0f  %s", a.value, affix_type_labels[a.type])
        } else {
            as = fmt.bprintf(abuf[:31], "+%.0f%%  %s", a.value * 100, affix_type_labels[a.type])
        }
        abuf[len(as)] = 0
        rl.DrawTextEx(g_font, cstring(&abuf[0]), { tx2, ay }, fs13, 0.5, COL_AFFIX)
    }

    if has_desc {
        rl.DrawLineEx(
            { f32(tx) + uis(10), f32(ty + TH) - uis(36) },
            { f32(tx + TW) - uis(10), f32(ty + TH) - uis(36) },
            1, rl.Color{ rc.r, rc.g, rc.b, 50 })
        draw_text_wrapped(g_font, desc_str,
            f32(tx) + uis(10), f32(ty + TH) - uis(30),
            fs13, text_w + (tx2 - f32(tx) - uis(10)), 0.5,
            rl.Color{ 200, 190, 160, 200 })
    }
}

equipped_item_for_compare :: proc(w: ^cw.World, item_id: int) -> int {
    if !cw.world_is_valid(w, w.player_id)                  { return cw.INVALID_ENTITY }
    if !cw.world_has_component(w, w.player_id, .Inventory) { return cw.INVALID_ENTITY }
    if !cw.world_is_valid(w, item_id)                      { return cw.INVALID_ENTITY }
    if !cw.world_has_component(w, item_id, .Item)          { return cw.INVALID_ENTITY }

    inv  := cw.world_get_inventory(w, w.player_id)
    item := cw.world_get_item(w, item_id)

    slot := item.slot
    if slot == .WeaponOffhand {
        eid := inv.equipped[int(cw.EquipSlot.WeaponOffhand)]
        return eid if eid != item_id else cw.INVALID_ENTITY
    }
    if slot == .WeaponPrimary {
        eid := inv.equipped[int(cw.EquipSlot.WeaponPrimary)]
        return eid if eid != item_id else cw.INVALID_ENTITY
    }
    if slot == .Ability1 || slot == .Ability2 || slot == .Ability3 || slot == .Ability4 {
        ability_slots := [4]cw.EquipSlot{ .Ability1, .Ability2, .Ability3, .Ability4 }
        for s in ability_slots {
            eid := inv.equipped[int(s)]
            if eid != cw.INVALID_ENTITY && eid != item_id {
                return eid
            }
        }
        return cw.INVALID_ENTITY
    }

    eid := inv.equipped[int(slot)]
    return eid if eid != item_id else cw.INVALID_ENTITY
}

draw_item_tooltip_or_compare :: proc(w: ^cw.World, item_id: int, mx, my: f32) {
    compare_key := rl.KeyboardKey(g_binds.ui.compare_tooltip)
    equipped_id := equipped_item_for_compare(w, item_id) if input_down(compare_key) else cw.INVALID_ENTITY

    if equipped_id == cw.INVALID_ENTITY {
        draw_item_tooltip(w, item_id, mx, my)
        return
    }

    gap := uis(264)
    if mx + gap + uis(238) < f32(rl.GetScreenWidth()) {
        draw_item_tooltip(w, item_id, mx, my)
        draw_item_tooltip(w, equipped_id, mx + gap, my)
    } else {
        draw_item_tooltip(w, equipped_id, mx, my)
        draw_item_tooltip(w, item_id, mx - gap, my)
    }
}

draw_levelup_flash :: proc() {
    if g_levelup_flash <= 0 { return }

    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()

    alpha := u8(clamp(g_levelup_flash / LEVELUP_FLASH_TIME, 0, 1) * 230)
    fs    := uis(52)
    text  := t(.HUD_LEVELUP)
    tsz   := rl.MeasureTextEx(g_font, text, fs, 2)
    rl.DrawTextEx(g_font, text,
        { f32(sw)*0.5 - tsz.x*0.5, f32(sh)*0.36 - tsz.y*0.5 },
        fs, 2, { 220, 196, 58, alpha })

    sfs  := uis(18)
    sub  := t(.HUD_STATPOINT)
    ssz  := rl.MeasureTextEx(g_font, sub, sfs, 1)
    salp := u8(clamp(g_levelup_flash / LEVELUP_FLASH_TIME, 0, 1) * 180)
    rl.DrawTextEx(g_font, sub,
        { f32(sw)*0.5 - ssz.x*0.5, f32(sh)*0.36 + tsz.y*0.5 + uis(6) },
        sfs, 1, { 200, 180, 120, salp })
}

// ── Enemy mutation auras ───────────────────────────────────────────────────────
//
// Draws world-space rings around non-player entities that carry mutations.
// Must be called inside BeginMode2D so draw_world_circle_lines applies the
// iso projection correctly.
//
// Visual language per mutation:
//   LivingBomb  — two concentric pulsing orange rings (breathing, ~1.4 Hz)
//   ToxicFlesh  — single slow-pulsing green ring at the proximity radius
//   ThornPact   — tight constant silver-purple double ring
//   BlackLung   — pressure-scaled teal ring; invisible at zero pressure
draw_enemy_mutation_auras :: proc(w: ^cw.World) {
    t   := f32(rl.GetTime())
    ids := cw.world_query(w, cw.query_mask(.MutationContainer, .Transform, .AIAgent),
                          context.temp_allocator)
    for id in ids {
        if is_player_entity(w, id) { continue }
        if is_fog_hidden(w, id)    { continue }

        tr  := cw.world_get_transform(w, id)
        pos := rl.Vector2{ tr.position[0], tr.position[1] }

        mc := cw.world_get_mutation(w, id)
        for i in 0..<mc.entity_count {
            meid := mc.entities[i]
            if !cw.world_is_valid(w, meid) { continue }

            // ── LivingBomb — pulsing orange rings ──
            if cw.world_has_component(w, meid, .MutOnDeathExplode) {
                pulse := f32(0.87) + f32(0.13) * math.sin(t * 1.4 * math.PI * 2)
                r     := f32(38) * pulse
                col   := mutation_visual_color(.LivingBomb)
                draw_world_circle_lines(pos, r,         rl.Color{ col.r, col.g, col.b, 130 })
                draw_world_circle_lines(pos, r * 0.58,  rl.Color{ col.r, col.g, col.b,  60 })
            }

            // ── ToxicFlesh — slow pulsing green ring at proximity radius ──
            if cw.world_has_component(w, meid, .MutProximityDamage) {
                pd    := cw.world_get_mut_proximity_damage(w, meid)
                pulse := f32(0.45) + f32(0.45) * math.sin(t * math.PI * 0.7)
                alpha := u8(clamp(pulse * 120, 0, 255))
                col   := mutation_visual_color(.ToxicFlesh)
                draw_world_circle_lines(pos, pd.radius, rl.Color{ col.r, col.g, col.b, alpha })
            }

            // ── ThornPact — tight constant double ring ──
            if cw.world_has_component(w, meid, .MutThornPact) {
                col := mutation_visual_color(.ThornPact)
                draw_world_circle_lines(pos, 40, rl.Color{ col.r, col.g, col.b, 115 })
                draw_world_circle_lines(pos, 47, rl.Color{ col.r, col.g, col.b,  42 })
            }

            // ── BlackLung — pressure-scaled teal ring ──
            if cw.world_has_component(w, meid, .MutBlackLung) {
                bl := cw.world_get_mut_black_lung(w, meid)
                if bl.pressure > 5 {
                    frac  := bl.pressure / 100.0
                    r     := bl.radius * frac
                    alpha := u8(clamp(frac * 155, 0, 155))
                    col   := mutation_visual_color(.BlackLung)
                    draw_world_circle_lines(pos, r,        rl.Color{ col.r, col.g, col.b, alpha })
                    draw_world_circle_lines(pos, r * 0.65, rl.Color{ col.r, col.g, col.b, alpha / 2 })
                }
            }
        }
    }
}
