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
    // Find an expired slot; fall back to the one closest to expiry.
    best := 0
    for i in 1..<MAX_DMGNUM {
        if g_dmgnums[i].lifetime <= 0 { best = i; break }
        if g_dmgnums[i].lifetime < g_dmgnums[best].lifetime { best = i }
    }
    g_dmgnums[best] = DmgNum{
        x        = x,
        y        = y,
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
        lbl     := cstring("EXTRACT")
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

    icon := cstring("RAID TIMER")
    lbl  := cstring(&buf[0])

    icon_sz := rl.MeasureTextEx(g_font, icon, uis(8), 0.5)
    lbl_sz  := rl.MeasureTextEx(g_font, lbl, fs, 0.5)

    x := sw - max(icon_sz.x, lbl_sz.x) - uis(20)
    rl.DrawTextEx(g_font, icon, { x, uis(12) }, uis(8), 0.5, rl.Color{ 150, 200, 130, 180 })
    rl.DrawTextEx(g_font, lbl,  { x, uis(23) }, fs, 0.5, col)
}

draw_boss_warning :: proc() {
    if g_boss_warning_timer <= 0 { return }

    t     := f32(rl.GetTime())
    pulse := f32(0.5) + f32(0.5) * math.sin(t * 6.0)
    sw    := f32(rl.GetScreenWidth())
    sh    := f32(rl.GetScreenHeight())

    overlay_alpha := u8(35 + i32(pulse * 35))
    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.Color{ 180, 0, 0, overlay_alpha })

    warn_fs := uis(22)
    warn1   := cstring("WARNING")
    warn2   := cstring("EL VERDUGO APPROACHES")
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

draw_boss_hud :: proc(w: ^cw.World) {
    if g_boss_id == cw.INVALID_ENTITY { return }
    if !cw.world_is_valid(w, g_boss_id) {
        g_boss_id = cw.INVALID_ENTITY
        return
    }
    if !cw.world_has_component(w, g_boss_id, .Health) { return }

    h    := cw.world_get_health(w, g_boss_id)
    frac := clamp(h.current / h.max, 0, 1)

    sw    := f32(rl.GetScreenWidth())
    bw    := sw * 0.42
    bh    := uis(14)
    bx    := sw * 0.5 - bw * 0.5
    by    := uis(14)

    rl.DrawRectangleRec({ bx - 2, by - 2, bw + 4, bh + 4 }, rl.Color{ 8, 4, 4, 220 })
    rl.DrawRectangleRec({ bx, by, bw, bh }, rl.Color{ 45, 12, 12, 200 })
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

    name_lbl := cstring("EL VERDUGO")
    name_fs  := uis(9)
    name_sz  := rl.MeasureTextEx(g_font, name_lbl, name_fs, 0.5)
    rl.DrawTextEx(g_font, name_lbl,
        { sw * 0.5 - name_sz.x * 0.5, by + bh + uis(3) },
        name_fs, 0.5, rl.Color{ 200, 120, 120, 200 })
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
        t := f32(rl.GetTime())
        pulse := (math.sin(t * 3.2) + 1) * 0.5
        item := cw.world_get_item(w, id)
        rc := rarity_color(item.rarity)
        draw_world_circle(pos, 12, rl.Color{ rc.r, rc.g, rc.b, u8(70 + pulse * 90) })
        draw_world_circle(pos, 6, rl.Color{ rc.r, rc.g, rc.b, u8(170 + pulse * 85) })
        draw_world_circle(pos, 2, rl.Color{ 255, 255, 255, 200 })
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
                hrad  := f32(7.0)

                if hc.heart_hp > 0 {
                    hworld: rl.Vector2
                    if cw.world_is_valid(w, hc.heart_id) &&
                       cw.world_has_component(w, hc.heart_id, .Transform) {
                        ht     := cw.world_get_transform(w, hc.heart_id)
                        hworld  = { ht.position[0], ht.position[1] }
                    } else {
                        hworld = { pos.x + 24, pos.y }
                    }
                    hiso   := world_to_iso_v(hworld)
                    hp_pct := hc.heart_hp / hc.heart_max_hp
                    pulse  := f32(0.8) + f32(0.2) * math.sin(t_now * 5.0)
                    alpha  := u8(180 + int(40.0 * pulse))
                    // Draw using world helpers so ellipse matches iso projection
                    draw_world_circle(hworld, hrad + 4, rl.Color{200, 40, 60, 50})
                    draw_world_circle(hworld, hrad, rl.Color{210, 50, 65, alpha})
                    draw_world_circle_lines(hworld, hrad, rl.Color{255, 120, 140, 200})
                    // HP bar in screen space above the heart ellipse
                    bw  := f32(22);  bh := f32(3)
                    bx  := hiso.x - bw * 0.5
                    by  := hiso.y - hrad * 0.55 - 6
                    rl.DrawRectangleRec({bx, by, bw, bh},          rl.Color{50, 10, 15, 180})
                    rl.DrawRectangleRec({bx, by, bw * hp_pct, bh}, rl.Color{220, 60, 80, 240})
                } else if hc.respawn_timer > 0 {
                    hworld   := rl.Vector2{pos.x + 24, pos.y}
                    time_pct := hc.respawn_timer / cw.HEART_CAGE_RESPAWN
                    ring_a   := u8(20 + int(40.0 * (1.0 - time_pct)))
                    draw_world_circle_lines(hworld, hrad,     rl.Color{160, 40, 60, ring_a})
                    draw_world_circle_lines(hworld, hrad + 3, rl.Color{100, 20, 40, ring_a / 2})
                }
                break
            }
        }
    }
}

draw_entity_sprite_visual :: proc(w: ^cw.World, id: int) {
    if !cw.world_has_component(w, id, .Transform) || is_fog_hidden(w, id) || entity_blindfire_hidden(w, id) { return }
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

COL_PARCH   :: rl.Color{ 222, 207, 162, 245 }
COL_CRIMSON :: rl.Color{ 178,  40,  36, 255 }
COL_BRASS   :: rl.Color{ 188, 150,  55, 235 }
COL_MUTED   :: rl.Color{ 128, 118,  88, 195 }
COL_PANEL   :: rl.Color{  10,   7,   5, 210 }
COL_RULE    :: rl.Color{ 130, 100,  38, 150 }

rarity_color :: proc(rarity: cw.ItemRarity) -> rl.Color {
    switch rarity {
    case .Normal:    return rl.Color{ 160, 155, 148, 255 }   // weathered stone
    case .Rare:      return rl.Color{  75, 135, 210, 255 }   // steel blue
    case .Epic:      return rl.Color{ 148,  55, 198, 255 }   // deep violet
    case .Legendary: return rl.Color{ 205,  90,  18, 255 }   // forge orange
    case .Unique:    return rl.Color{ 215, 175,  28, 255 }   // ancient gold
    }
    return rl.Color{ 160, 155, 148, 255 }
}

draw_ammo_ring :: proc(w: ^cw.World) {
    if !cw.world_is_valid(w, w.player_id) { return }
    if !cw.world_has_component(w, w.player_id, .Equipment) { return }

    equip := cw.world_get_equipment(w, w.player_id)
    wid   := equip.weapon_entity_id
    if !cw.world_is_valid(w, wid)               { return }
    if !cw.world_has_component(w, wid, .Weapon) { return }

    wp := cw.world_get_weapon_data(w, wid)
    if wp.ammo_max <= 0 { return }   // infinite ammo — nothing to show

    center := rl.Vector2{ uis(144), f32(rl.GetScreenHeight()) - uis(172) }
    INNER  := uis(16)   // inner radius → 32 px hole, fits a 20 pt glyph
    OUTER  := uis(28)   // outer radius → 12 px thick ring
    SEGS   :: i32(48)
    LBL_FS := uis(20)
    NAME_FS:= uis(24)
    SPC    := f32(1)

    rl.DrawRing(center, INNER, OUTER, 0, 360, SEGS, { 18, 14, 10, 225 })

    if wp.is_reloading {
        reload_ratio: f32 = 1
        if wp.reload_time > 0 {
            reload_ratio = 1 - wp.reload_timer / wp.reload_time
        }
        end_angle := f32(-90) + 360 * reload_ratio
        if reload_ratio > 0 {
            rl.DrawRing(center, INNER, OUTER, -90, end_angle, SEGS,
                rl.Color{ 100, 158, 210, 255 })  // aged silver-blue
        }
        lbl      := cstring("R")
        lbl_sz   := rl.MeasureTextEx(g_font, lbl, LBL_FS, SPC)
        lbl_pos  := rl.Vector2{ center.x - lbl_sz.x * 0.5, center.y - lbl_sz.y * 0.5 }
        rl.DrawTextEx(g_font, lbl, lbl_pos, LBL_FS, SPC, COL_PARCH)
    } else {
        ammo_ratio := f32(wp.ammo_current) / f32(wp.ammo_max)
        end_angle  := f32(-90) + 360 * ammo_ratio
        arc_col    := rl.Color{ 192, 152, 44, 255 }      // antique brass
        if ammo_ratio <= 0.334 {
            arc_col = COL_CRIMSON                         // blood-red when critical
        }
        if ammo_ratio > 0 {
            rl.DrawRing(center, INNER, OUTER, -90, end_angle, SEGS, arc_col)
        }
        lbl     := rl.TextFormat("%d", wp.ammo_current)
        lbl_sz  := rl.MeasureTextEx(g_font, lbl, LBL_FS, SPC)
        lbl_pos := rl.Vector2{ center.x - lbl_sz.x * 0.5, center.y - lbl_sz.y * 0.5 }
        rl.DrawTextEx(g_font, lbl, lbl_pos, LBL_FS, SPC, COL_PARCH)
    }

    if cw.world_has_component(w, wid, .RenderConfig) {
        rc       := cw.world_get_render_config(w, wid)
        name_cs  := cw.render_config_name_cstr(rc)
        name_sz  := rl.MeasureTextEx(g_font, name_cs, NAME_FS, SPC)
        name_pos := rl.Vector2{
            center.x - name_sz.x * 0.5,
            center.y + OUTER + 6,
        }
        rl.DrawTextEx(g_font, name_cs, name_pos, NAME_FS, SPC, COL_BRASS)
    }
}

draw_ability_hud :: proc(w: ^cw.World) {
    if !cw.world_is_valid(w, w.player_id)                { return }
    if !cw.world_has_component(w, w.player_id, .Ability) { return }

    ab := cw.world_get_ability(w, w.player_id)
    sw := rl.GetScreenWidth()

    BOX := i32(uis(54))
    GAP := i32(uis(6))

    labels := [cw.ABILITY_SLOT_COUNT]cstring{ "Q", "E", "F", "G" }

    total_w := BOX * cw.ABILITY_SLOT_COUNT + GAP * (cw.ABILITY_SLOT_COUNT - 1)
    start_x := sw - 8 - total_w

    for i in 0..<cw.ABILITY_SLOT_COUNT {
        bx      := start_x + i32(i) * (BOX + GAP)
        by      := i32(8)
        st      := ab.slots[i]
        ab_type := player_ability_in_slot(w, w.player_id, i)
        has_ab  := ab_type != .None

        cd  : f32 = 0
        cdm : f32 = 0
        name_str : string
        if has_ab {
            def      := &ABILITY_DEFS[ab_type]
            cd        = st.cooldown
            cdm       = def.cd_max
            name_str  = def.name
        }

        ready        := has_ab && cd <= 0
        charge_glow  := ab_type == .DeathShot  && st.charging
        dance_glow   := ab_type == .DevilsDance && st.dance_ready

        bg_col := rl.Color{ 10, 7, 5, 220 } if has_ab else rl.Color{ 8, 6, 4, 160 }
        rl.DrawRectangle(bx, by, BOX, BOX, bg_col)

        if cdm > 0 && cd > 0 {
            ratio  := clamp(cd / cdm, 0, 1)
            fill_h := i32(f32(BOX) * ratio)
            rl.DrawRectangle(bx, by + BOX - fill_h, BOX, fill_h,
                rl.Color{ 0, 0, 0, 160 })
        }

        // DeathShot red glow while charging; DevilsDance cyan glow when primed
        if charge_glow {
            rl.DrawRectangle(bx, by, BOX, BOX, rl.Color{ 200, 40, 20, 70 })
            ready = true
        }
        if dance_glow {
            rl.DrawRectangle(bx, by, BOX, BOX, rl.Color{ 20, 200, 200, 65 })
            ready = true
        }

        border  := COL_BRASS if ready else COL_RULE
        rl.DrawRectangleLinesEx({ f32(bx), f32(by), f32(BOX), f32(BOX) }, 1, border)

        key_col := COL_PARCH if ready else (COL_MUTED if has_ab else rl.Color{ 55, 50, 40, 140 })
        key_fs  := uis(16)
        name_fs := uis(10)
        rl.DrawTextEx(g_font, labels[i], { f32(bx) + uis(5), f32(by) + uis(4) }, key_fs, 1, key_col)

        if has_ab {
            ns := strings.clone_to_cstring(name_str, context.temp_allocator)
            nsz := rl.MeasureTextEx(g_font, ns, name_fs, 0.5)
            rl.DrawTextEx(g_font, ns,
                { f32(bx) + f32(BOX)*0.5 - nsz.x*0.5, f32(by) + f32(BOX) - uis(15) },
                name_fs, 0.5, key_col)
        }
    }
}

draw_hud_clay :: proc(w: ^cw.World) {
    clay.BeginLayout()

    if cw.world_is_valid(w, w.player_id) {
        h        := cw.world_get_health(w, w.player_id)
        hp_ratio := clamp(h.current / h.max,        0, 1) if h.max        > 0 else f32(0)
        en_ratio := clamp(h.energy  / h.max_energy, 0, 1) if h.max_energy > 0 else f32(0)

        xp_ratio: f32 = 0
        if cw.world_has_component(w, w.player_id, .Stats) {
            st := cw.world_get_stats(w, w.player_id)
            xp_ratio = clamp(st.xp / st.xp_next, 0, 1) if st.xp_next > 0 else 0
        }

        panel_w  := uis(256)
        bar_h    := uis(14)
        xp_bar_h := uis(8)
        bar_off  := uis(38)
        if clay.UI(clay.ID("HUDPanel"))({
            layout = {
                layoutDirection = .TopToBottom,
                sizing          = { clay.SizingFixed(panel_w), clay.SizingFit() },
                padding         = {
                    left   = u16(uis(14)),
                    right  = u16(uis(14)),
                    top    = u16(uis(12)),
                    bottom = u16(uis(12)),
                },
                childGap        = u16(uis(8)),
            },
            floating = {
                offset     = { 16, -bar_off },
                attachment = { element = .LeftBottom, parent = .LeftBottom },
                attachTo   = .Root,
            },
            backgroundColor = { 10, 7, 5, 215 },
            cornerRadius    = clay.CornerRadiusAll(6),
            border          = { color = { 130, 100, 38, 140 }, width = { 1, 1, 1, 1, 0 } },
        }) {
            if clay.UI(clay.ID("HPTrack"))({
                layout          = { sizing = { clay.SizingGrow(), clay.SizingFixed(bar_h) } },
                backgroundColor = { 45, 10, 10, 255 },
                cornerRadius    = clay.CornerRadiusAll(3),
            }) {
                if clay.UI(clay.ID("HPFill"))({
                    layout          = { sizing = { clay.SizingPercent(hp_ratio), clay.SizingGrow() } },
                    backgroundColor = { 172, 36, 36, 255 },
                    cornerRadius    = clay.CornerRadiusAll(3),
                }) {}
            }

            if clay.UI(clay.ID("ENTrack"))({
                layout          = { sizing = { clay.SizingGrow(), clay.SizingFixed(bar_h) } },
                backgroundColor = { 10, 16, 44, 255 },
                cornerRadius    = clay.CornerRadiusAll(3),
            }) {
                if clay.UI(clay.ID("ENFill"))({
                    layout          = { sizing = { clay.SizingPercent(en_ratio), clay.SizingGrow() } },
                    backgroundColor = { 38, 78, 158, 255 },
                    cornerRadius    = clay.CornerRadiusAll(3),
                }) {}
            }

            if clay.UI(clay.ID("XPTrack"))({
                layout          = { sizing = { clay.SizingGrow(), clay.SizingFixed(xp_bar_h) } },
                backgroundColor = { 30, 24, 10, 255 },
                cornerRadius    = clay.CornerRadiusAll(2),
            }) {
                if clay.UI(clay.ID("XPFill"))({
                    layout          = { sizing = { clay.SizingPercent(xp_ratio), clay.SizingGrow() } },
                    backgroundColor = { 180, 148, 36, 255 },
                    cornerRadius    = clay.CornerRadiusAll(2),
                }) {}
            }

        }
    }

    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)
}

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

PAUSE_W_BASE      :: f32(340)
PAUSE_H_BASE      :: f32(586)   
PAUSE_BTN_W_BASE  :: f32(200)
PAUSE_BTN_H_BASE  :: f32(42)

PAUSE_Y_RESUME_BASE   :: f32(62)
PAUSE_Y_RES_BASE      :: f32(140)
PAUSE_Y_MODE_BASE     :: f32(222)
PAUSE_Y_VOL_BASE      :: f32(316)   
PAUSE_VOL_ROW_H_BASE  :: f32(34)    
PAUSE_Y_KEYBINDS_BASE :: f32(484)   
PAUSE_Y_QUIT_BASE     :: f32(534)   

pause_W          :: proc() -> i32 { return i32(uis(PAUSE_W_BASE))           }
pause_H          :: proc() -> i32 { return i32(uis(PAUSE_H_BASE))           }
pause_btn_w      :: proc() -> i32 { return i32(uis(PAUSE_BTN_W_BASE))       }
pause_btn_h      :: proc() -> i32 { return i32(uis(PAUSE_BTN_H_BASE))       }
pause_y_resume   :: proc() -> i32 { return i32(uis(PAUSE_Y_RESUME_BASE))    }
pause_y_res      :: proc() -> i32 { return i32(uis(PAUSE_Y_RES_BASE))       }
pause_y_mode     :: proc() -> i32 { return i32(uis(PAUSE_Y_MODE_BASE))      }
pause_y_vol      :: proc() -> i32 { return i32(uis(PAUSE_Y_VOL_BASE))       }
pause_vol_row_h  :: proc() -> i32 { return i32(uis(PAUSE_VOL_ROW_H_BASE))   }
pause_y_keybinds :: proc() -> i32 { return i32(uis(PAUSE_Y_KEYBINDS_BASE))  }
pause_y_quit     :: proc() -> i32 { return i32(uis(PAUSE_Y_QUIT_BASE))      }

g_keybinds_open: bool
g_rebind_idx:    int = -1

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
        g_paused = false
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
        g_keybinds_open = true
        g_rebind_idx    = -1
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

    title    := cstring("P A U S E D")
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
        "Resume", mp)

    res_label := PAUSE_RESOLUTIONS[g_pause_res_idx].label
    pause_arrow_row(px, py + pause_y_res(), "RESOLUTION", res_label, mp,
        enabled = !g_borderless)

    mode_label: cstring = "Borderless" if g_borderless else "Windowed"
    pause_arrow_row(px, py + pause_y_mode(), "WINDOW MODE", mode_label, mp)

    {
        vol_hdr    := cstring("VOLUME")
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
        draw_vol_slider(px, py + pause_y_vol() + rh * 0, "SFX",      g_vol_sfx,      mp)
        draw_vol_slider(px, py + pause_y_vol() + rh * 1, "MUSIC",    g_vol_music,    mp)
        draw_vol_slider(px, py + pause_y_vol() + rh * 2, "AMBIENCE", g_vol_ambience, mp)
        draw_vol_slider(px, py + pause_y_vol() + rh * 3, "VOICE",    g_vol_voice,    mp)
    }

    rl.DrawLineEx(
        { f32(px) + 16, f32(py + pause_y_keybinds()) - 12 },
        { f32(px + pW) - 16, f32(py + pause_y_keybinds()) - 12 }, 1, COL_RULE)
    draw_pause_btn(
        { bx, f32(py + pause_y_keybinds()), f32(pBW), f32(pBH) },
        "Keybinds", mp)

    rl.DrawLineEx(
        { f32(px) + 16, f32(py + pause_y_quit()) - 12 },
        { f32(px + pW) - 16, f32(py + pause_y_quit()) - 12 }, 1, COL_RULE)
    draw_pause_btn(
        { bx, f32(py + pause_y_quit()), f32(pBW), f32(pBH) },
        "Quit", mp)
}


@(private = "file") BIND_ROW_H :: f32(36)

update_keybinds_screen :: proc() {
    if !g_keybinds_open { return }

    rows := bind_rows()
    N    :: BIND_ROW_COUNT

    PW    :: f32(480)
    PH    := f32(56) + f32(N) * BIND_ROW_H + f32(80)   
    sw    := rl.GetScreenWidth()
    sh    := rl.GetScreenHeight()
    px    := f32(sw) * 0.5 - uis(PW) * 0.5
    py    := f32(sh) * 0.5 - uis(PH) * 0.5
    mp    := rl.GetMousePosition()

    if g_rebind_idx >= 0 {
        k := rl.GetKeyPressed()
        if k != .KEY_NULL {
            if k == .ESCAPE {
                g_rebind_idx = -1
            } else {
                rows[g_rebind_idx].ptr^ = i32(k)
                g_rebind_idx = -1
                save_config()
            }
        }
        return   
    }

    if rl.IsMouseButtonPressed(.LEFT) {
        for i in 0..<N {
            ry := py + uis(f32(56) + f32(i) * BIND_ROW_H)
            r  := rl.Rectangle{ px + uis(8), ry, uis(PW - 16), uis(BIND_ROW_H - 4) }
            if rl.CheckCollisionPointRec(mp, r) {
                g_rebind_idx = i
                return
            }
        }

        footer_y := py + uis(f32(56) + f32(N) * BIND_ROW_H + f32(16))
        reset_r  := rl.Rectangle{ px + uis(8), footer_y, uis(PW * 0.5 - 16), uis(36) }
        if rl.CheckCollisionPointRec(mp, reset_r) {
            g_binds = default_binds()
            save_config()
            return
        }

        close_r := rl.Rectangle{ px + uis(PW * 0.5 + 8), footer_y, uis(PW * 0.5 - 16), uis(36) }
        if rl.CheckCollisionPointRec(mp, close_r) {
            g_keybinds_open = false
            g_rebind_idx    = -1
            return
        }
    }
}

draw_keybinds_screen :: proc() {
    if !g_keybinds_open { return }

    rows := bind_rows()
    N    :: 13

    PW   :: f32(480)
    PH   := f32(56) + f32(N) * BIND_ROW_H + f32(80)
    sw   := rl.GetScreenWidth()
    sh   := rl.GetScreenHeight()
    px   := f32(sw) * 0.5 - uis(PW) * 0.5
    py   := f32(sh) * 0.5 - uis(PH) * 0.5
    mp   := rl.GetMousePosition()

    rl.DrawRectangle(i32(px), i32(py), i32(uis(PW)), i32(uis(PH)), rl.Color{ 8, 6, 4, 252 })
    rl.DrawRectangle(i32(px), i32(py), i32(uis(PW)), i32(uis(3)), COL_BRASS)
    rl.DrawRectangleLinesEx({ px, py, uis(PW), uis(PH) }, 2, COL_RULE)

    title    := cstring("K E Y B I N D S")
    title_fs := uis(15)
    tsz      := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title,
        { px + uis(PW)*0.5 - tsz.x*0.5, py + uis(10) }, title_fs, 1, COL_BRASS)
    rl.DrawLineEx(
        { px + uis(16), py + uis(34) },
        { px + uis(PW) - uis(16), py + uis(34) }, 1, COL_RULE)

    name_buf: [16]u8
    for i in 0..<N {
        ry      := py + uis(f32(56) + f32(i) * BIND_ROW_H)
        row_r   := rl.Rectangle{ px + uis(8), ry, uis(PW - 16), uis(BIND_ROW_H - 4) }
        is_hot  := rl.CheckCollisionPointRec(mp, row_r) && g_rebind_idx < 0
        is_listening := g_rebind_idx == i

        row_bg: rl.Color
        if is_listening     { row_bg = rl.Color{ 50, 38, 14, 230 }
        } else if is_hot    { row_bg = rl.Color{ 30, 24, 14, 220 }
        } else              { row_bg = rl.Color{ 18, 14, 10, 200 } }

        rl.DrawRectangleRec(row_r, row_bg)
        rl.DrawRectangleLinesEx(row_r, 1,
            COL_BRASS if is_listening else (COL_RULE if is_hot else rl.Color{ 55, 48, 34, 80 }))

        lfs := uis(13)
        rl.DrawTextEx(g_font, rows[i].label,
            { px + uis(20), ry + uis(BIND_ROW_H)*0.5 - lfs*0.5 },
            lfs, 0.5, COL_PARCH if !is_listening else COL_BRASS)

        key_str: cstring
        if is_listening {
            key_str = "[ press a key ]"
        } else {
            key_str = key_name(rl.KeyboardKey(rows[i].ptr^), name_buf[:])
        }
        kcol := COL_BRASS if is_listening else rl.Color{ 180, 160, 90, 220 }
        ksz  := rl.MeasureTextEx(g_font, key_str, lfs, 0.5)
        rl.DrawTextEx(g_font, key_str,
            { px + uis(PW) - uis(20) - ksz.x, ry + uis(BIND_ROW_H)*0.5 - lfs*0.5 },
            lfs, 0.5, kcol)
    }

    footer_y := py + uis(f32(56) + f32(N) * BIND_ROW_H + f32(16))

    reset_r := rl.Rectangle{ px + uis(8), footer_y, uis(PW * 0.5 - 16), uis(36) }
    reset_hot := rl.CheckCollisionPointRec(mp, reset_r) && g_rebind_idx < 0
    rl.DrawRectangleRec(reset_r, rl.Color{ 28, 14, 10, 240 } if reset_hot else rl.Color{ 18, 10, 8, 220 })
    rl.DrawRectangleLinesEx(reset_r, 1, COL_RULE)
    reset_lbl := cstring("Reset Defaults")
    rlbl_fs   := uis(13)
    rlbl_sz   := rl.MeasureTextEx(g_font, reset_lbl, rlbl_fs, 0.5)
    rl.DrawTextEx(g_font, reset_lbl,
        { reset_r.x + reset_r.width*0.5 - rlbl_sz.x*0.5,
          reset_r.y + reset_r.height*0.5 - rlbl_fs*0.5 },
        rlbl_fs, 0.5, rl.Color{ 200, 120, 80, 220 } if reset_hot else COL_MUTED)

    close_r := rl.Rectangle{ px + uis(PW * 0.5 + 8), footer_y, uis(PW * 0.5 - 16), uis(36) }
    close_hot := rl.CheckCollisionPointRec(mp, close_r) && g_rebind_idx < 0
    rl.DrawRectangleRec(close_r, rl.Color{ 28, 22, 16, 240 } if close_hot else rl.Color{ 18, 14, 10, 220 })
    rl.DrawRectangleLinesEx(close_r, 1, COL_RULE if !close_hot else COL_BRASS)
    close_lbl := cstring("Close")
    clbl_sz   := rl.MeasureTextEx(g_font, close_lbl, rlbl_fs, 0.5)
    rl.DrawTextEx(g_font, close_lbl,
        { close_r.x + close_r.width*0.5 - clbl_sz.x*0.5,
          close_r.y + close_r.height*0.5 - rlbl_fs*0.5 },
        rlbl_fs, 0.5, COL_BRASS if close_hot else COL_PARCH)

    if g_rebind_idx >= 0 {
        hint    := cstring("Esc to cancel")
        hint_fs := uis(11)
        hsz     := rl.MeasureTextEx(g_font, hint, hint_fs, 0.5)
        rl.DrawTextEx(g_font, hint,
            { px + uis(PW)*0.5 - hsz.x*0.5, footer_y + uis(44) },
            hint_fs, 0.5, COL_MUTED)
    }
}
SETTINGS_H_BASE          :: f32(510)
SETTINGS_Y_RES_BASE       :: f32(80)
SETTINGS_Y_MODE_BASE      :: f32(162)
SETTINGS_Y_VOL_BASE       :: f32(256)   // first slider row_y
SETTINGS_VOL_ROW_H_BASE   :: f32(34)
SETTINGS_Y_KEYBINDS_BASE  :: f32(408)
SETTINGS_Y_CLOSE_BASE     :: f32(460)

settings_H          :: proc() -> i32 { return i32(uis(SETTINGS_H_BASE))         }
settings_y_res      :: proc() -> i32 { return i32(uis(SETTINGS_Y_RES_BASE))     }
settings_y_mode     :: proc() -> i32 { return i32(uis(SETTINGS_Y_MODE_BASE))    }
settings_y_vol      :: proc() -> i32 { return i32(uis(SETTINGS_Y_VOL_BASE))     }
settings_vol_row_h  :: proc() -> i32 { return i32(uis(SETTINGS_VOL_ROW_H_BASE)) }
settings_y_keybinds :: proc() -> i32 { return i32(uis(SETTINGS_Y_KEYBINDS_BASE))}
settings_y_close    :: proc() -> i32 { return i32(uis(SETTINGS_Y_CLOSE_BASE))   }

update_settings_overlay :: proc() -> (closed: bool) {
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
        g_keybinds_open = true
        g_rebind_idx    = -1
    }

    if rl.CheckCollisionPointRec(mp,
        { bx, f32(py + settings_y_close()), f32(pBW), f32(pBH) }) &&
       rl.IsMouseButtonPressed(.LEFT) {
        return true
    }

    return false
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

    title    := cstring("S E T T I N G S")
    title_fs := uis(24)
    title_sz := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title,
        { f32(px) + f32(pW) * 0.5 - title_sz.x * 0.5, f32(py) + uis(16) },
        title_fs, 1, COL_PARCH)
    rl.DrawLineEx(
        { f32(px) + 16, f32(py) + uis(52) },
        { f32(px + pW) - 16, f32(py) + uis(52) }, 1, COL_RULE)

    res_label := PAUSE_RESOLUTIONS[g_pause_res_idx].label
    pause_arrow_row(px, py + settings_y_res(), "RESOLUTION", res_label, mp,
        enabled = !g_borderless)

    mode_label: cstring = "Borderless" if g_borderless else "Windowed"
    pause_arrow_row(px, py + settings_y_mode(), "WINDOW MODE", mode_label, mp)

    {
        vol_hdr    := cstring("VOLUME")
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
        draw_vol_slider(px, py + settings_y_vol() + rh * 0, "SFX",      g_vol_sfx,      mp)
        draw_vol_slider(px, py + settings_y_vol() + rh * 1, "MUSIC",    g_vol_music,    mp)
        draw_vol_slider(px, py + settings_y_vol() + rh * 2, "AMBIENCE", g_vol_ambience, mp)
        draw_vol_slider(px, py + settings_y_vol() + rh * 3, "VOICE",    g_vol_voice,    mp)
    }

    rl.DrawLineEx(
        { f32(px) + 16, f32(py + settings_y_keybinds()) - 12 },
        { f32(px + pW) - 16, f32(py + settings_y_keybinds()) - 12 }, 1, COL_RULE)
    draw_pause_btn(
        { bx, f32(py + settings_y_keybinds()), f32(pBW), f32(pBH) },
        "Keybinds", mp)

    rl.DrawLineEx(
        { f32(px) + 16, f32(py + settings_y_close()) - 12 },
        { f32(px + pW) - 16, f32(py + settings_y_close()) - 12 }, 1, COL_RULE)
    draw_pause_btn(
        { bx, f32(py + settings_y_close()), f32(pBW), f32(pBH) },
        "Close", mp)
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

@(private = "file")
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
    iso    := world_to_iso_v(pos)
    iso_h  := world_size * ISO_SPRITE_Y
    dst    := rl.Rectangle{ iso.x, iso.y, world_size, iso_h }
    origin := rl.Vector2{ world_size * 0.5, iso_h * 0.5 }
    rl.DrawTexturePro(tex, src, dst, origin, math.to_degrees(rotation_rad) + 90.0, tint)
}

@(private = "file") g_drag_item_id:      int          = -1                  
@(private = "file") g_drag_origin_x:     int          = -1                  
@(private = "file") g_drag_origin_y:     int          = -1                  
@(private = "file") g_drag_from_equip:   bool         = false               
@(private = "file") g_drag_origin_equip: cw.EquipSlot = cw.EquipSlot(0)     
@(private = "file") g_hover_item_id:     int          = cw.INVALID_ENTITY   

@(private = "file")
equip_slot_rect :: proc(px, py: i32, slot: cw.EquipSlot) -> (rect: rl.Rectangle, ok: bool) {
    x  := f32(px + g_inv.pad)
    x2 := f32(px + g_inv.pad + g_inv.wep_w  + g_inv.col_gap)  // right column for weapons
    sw := f32(g_inv.slot_w)
    sh := f32(g_inv.slot_h)
    wh := f32(g_inv.wep_h)
    ww := f32(g_inv.wep_w)
    aw := f32(g_inv.ability_w)
    ah := f32(g_inv.ability_h)
    ab_step := f32(g_inv.ability_w + g_inv.col_gap)

    #partial switch slot {
    case .Head:
        return { x, f32(py + g_inv.slots_y), sw, sh }, true
    case .Chest:
        return { x, f32(py + g_inv.slots_y + g_inv.slot_h + g_inv.slot_gap), sw, sh }, true
    case .Boots:
        return { x, f32(py + g_inv.slots_y + (g_inv.slot_h + g_inv.slot_gap) * 2), sw, sh }, true
    case .WeaponPrimary:
        return { x,  f32(py + g_inv.wep_y), ww, wh }, true
    case .WeaponOffhand:
        return { x2, f32(py + g_inv.wep_y), ww, wh }, true
    case .Ability1:
        return { x + 0 * ab_step, f32(py + g_inv.ability_y), aw, ah }, true
    case .Ability2:
        return { x + 1 * ab_step, f32(py + g_inv.ability_y), aw, ah }, true
    case .Ability3:
        return { x + 2 * ab_step, f32(py + g_inv.ability_y), aw, ah }, true
    case .Ability4:
        return { x + 3 * ab_step, f32(py + g_inv.ability_y), aw, ah }, true
    }
    return {}, false
}

@(private = "file")
item_fits_slot :: proc(item_slot: cw.EquipSlot, target: cw.EquipSlot) -> bool {
    is_wep_item   := item_slot == .WeaponPrimary || item_slot == .WeaponOffhand
    is_wep_target := target   == .WeaponPrimary || target   == .WeaponOffhand
    if is_wep_item { return is_wep_target }

    is_ab_item   := item_slot == .Ability1 || item_slot == .Ability2 ||
                    item_slot == .Ability3 || item_slot == .Ability4
    is_ab_target := target   == .Ability1 || target   == .Ability2 ||
                    target   == .Ability3 || target   == .Ability4
    if is_ab_item { return is_ab_target }

    return item_slot == target
}

@(private = "file")
inv_slot_name :: proc(w: ^cw.World, inv: ^cw.InventoryComp, slot: cw.EquipSlot) -> (cstring, bool) {
    if inv == nil { return "unequipped", false }
    eid := inv.equipped[int(slot)]
    if !cw.world_is_valid(w, eid) { return "unequipped", false }
    if cw.world_has_component(w, eid, .RenderConfig) {
        return cw.render_config_name_cstr(cw.world_get_render_config(w, eid)), true
    }
    return "???", true
}

@(private = "file")
draw_equip_slot_h :: proc(x, y, w, h: i32, label: cstring, item_name: cstring, has_item: bool) {
    rl.DrawRectangle(x, y, w, h, rl.Color{ 20, 16, 12, 240 })
    rl.DrawRectangleLinesEx({ f32(x), f32(y), f32(w), f32(h) }, 1, COL_RULE)

    fs      := uis(18)
    label_y := f32(y) + f32(h) * 0.5 - fs * 0.5
    rl.DrawTextEx(g_font, label, { f32(x) + uis(14), label_y }, fs, 1, COL_BRASS)

    div_x := f32(x) + uis(122)
    rl.DrawLineEx({ div_x, f32(y) + uis(8) }, { div_x, f32(y) + f32(h) - uis(8) }, 1, COL_RULE)

    item_col := COL_PARCH if has_item else rl.Color{ 95, 88, 68, 155 }
    rl.DrawTextEx(g_font, item_name, { div_x + uis(14), label_y }, fs, 1, item_col)
}

@(private = "file")
draw_weapon_slot_box :: proc(x, y, w, h: i32, label: cstring, item_name: cstring, has_item: bool, blocked: bool = false) {
    bg_col     := rl.Color{ 20, 16, 12, 240 } if !blocked else rl.Color{ 14, 8, 8, 245 }
    border_col := COL_RULE                    if !blocked else rl.Color{ 70, 28, 28, 200 }
    lbl_col    := COL_BRASS                   if !blocked else rl.Color{ 72, 52, 38, 180 }

    rl.DrawRectangle(x, y, w, h, bg_col)
    rl.DrawRectangleLinesEx({ f32(x), f32(y), f32(w), f32(h) }, 1, border_col)

    lbl_fs := uis(16)
    lsz    := rl.MeasureTextEx(g_font, label, lbl_fs, 1)
    rl.DrawTextEx(g_font, label,
        { f32(x) + f32(w) * 0.5 - lsz.x * 0.5, f32(y) + uis(7) }, lbl_fs, 1, lbl_col)

    rl.DrawLineEx(
        { f32(x) + uis(10), f32(y) + uis(27) },
        { f32(x) + f32(w) - uis(10), f32(y) + uis(27) }, 1, border_col)

    name_fs := uis(18)
    if blocked {
        // Red overlay + "2H" lock indicator
        rl.DrawRectangle(x, y, w, h, rl.Color{ 60, 0, 0, 55 })
        lock_lbl := cstring("— 2H —")
        lksz := rl.MeasureTextEx(g_font, lock_lbl, name_fs, 1)
        rl.DrawTextEx(g_font, lock_lbl,
            { f32(x) + f32(w) * 0.5 - lksz.x * 0.5, f32(y) + uis(34) },
            name_fs, 1, rl.Color{ 150, 50, 50, 210 })
    } else {
        item_col := COL_PARCH if has_item else rl.Color{ 95, 88, 68, 155 }
        nsz      := rl.MeasureTextEx(g_font, item_name, name_fs, 1)
        rl.DrawTextEx(g_font, item_name,
            { f32(x) + f32(w) * 0.5 - nsz.x * 0.5, f32(y) + uis(34) }, name_fs, 1, item_col)
    }
}

@(private = "file")
_INV_SHOP_GAP :: f32(16)

@(private = "file")
inv_panel_origin :: proc() -> (px, py: i32) {
    return rl.GetScreenWidth() - g_inv.panel_w, 0
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
inv_mouse_to_cell :: proc(px, py: i32, mx, my: f32) -> (col, row: int, ok: bool) {
    gx := int(px) + int(g_inv.pad)
    gy := int(py) + int(g_inv.pack_y)
    c  := (int(mx) - gx) / int(g_inv.cell_sz)
    r  := (int(my) - gy) / int(g_inv.cell_sz)
    if c < 0 || c >= cw.BACKPACK_COLS { return 0, 0, false }
    if r < 0 || r >= cw.BACKPACK_ROWS { return 0, 0, false }
    return c, r, true
}

@(private = "file")
draw_item_glyph :: proc(slot: cw.EquipSlot, x, y, sz: i32, tint: rl.Color) {
    cx  := f32(x) + f32(sz) * 0.5
    cy  := f32(y) + f32(sz) * 0.5
    col := rl.Color{ tint.r, tint.g, tint.b, 200 }
    dim := rl.Color{ tint.r / 2, tint.g / 2, tint.b / 2, 180 }
    r   := f32(sz) * 0.5

    switch slot {
    case .Head:
        rl.DrawCircleV({ cx, cy - r * 0.1 }, r * 0.42, dim)
        rl.DrawCircleV({ cx, cy - r * 0.1 }, r * 0.28, col)
        rl.DrawRectangle(x + sz/4, y + sz*3/4 - 2, sz/2, sz/8 + 1, col)

    case .Chest:
        bw := i32(r * 0.9)
        bh := i32(r * 1.1)
        bx := x + (sz - bw) / 2
        by := y + (sz - bh) / 2 + 2
        rl.DrawRectangle(bx, by, bw, bh, dim)
        rl.DrawRectangle(bx + 2, by + 2, bw - 4, bh - 4, col)
        nub := i32(r * 0.25)
        rl.DrawRectangle(bx - nub, by, nub, nub * 2, col)
        rl.DrawRectangle(bx + bw, by, nub, nub * 2, col)

    case .Boots:
        bw := i32(r * 0.38)
        bh := i32(r * 0.7)
        gap := i32(r * 0.1)
        total := bw * 2 + gap
        lx  := x + (sz - total) / 2
        by  := y + (sz - bh) / 2 + i32(r * 0.15)
        rl.DrawRectangle(lx,        by, bw, bh, col)
        rl.DrawRectangle(lx + bw + gap, by, bw, bh, col)
        rl.DrawRectangle(lx,        by, bw, bh / 4, dim)
        rl.DrawRectangle(lx + bw + gap, by, bw, bh / 4, dim)

    case .WeaponPrimary:
        blen := i32(r * 0.9)
        bx   := x + (sz - blen) / 2
        by   := y + sz / 2 - 3
        rl.DrawRectangle(bx, by, blen, 5, col)          // barrel
        grip_x := bx + blen / 2
        rl.DrawRectangle(grip_x, by + 5, 6, i32(r * 0.5), dim)  // grip

    case .WeaponOffhand:
        sw := i32(r * 0.7)
        sh := i32(r * 0.9)
        sx := x + (sz - sw) / 2
        sy := y + (sz - sh) / 2
        rl.DrawRectangle(sx, sy, sw, sh, dim)
        rl.DrawRectangle(sx + 2, sy + 2, sw - 4, sh - 4, col)
        rl.DrawRectangle(sx + sw/2 - 1, sy + 4, 2, sh - 8, dim)
        rl.DrawRectangle(sx + 4, sy + sh/3, sw - 8, 2, dim)

    case .Consumable:
        rl.DrawCircleV({ cx, cy }, r * 0.38, dim)
        rl.DrawCircleV({ cx, cy }, r * 0.26, col)

    case .Ability1, .Ability2, .Ability3, .Ability4:
        hw := i32(r * 0.28)
        rl.DrawRectangle(x + sz/2 - hw/2, y + sz/4,     hw, i32(r * 0.6), col)
        rl.DrawRectangle(x + sz/2,        y + sz/2 - 2,  hw, i32(r * 0.6), dim)

    }
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

@(private = "file")
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
            desc_str = cw.render_config_desc_cstr(rcc)
        }
    }

    affix_count := int(item.affix_count)
    req_count   := (1 if item.req_str > 0 else 0) +
                   (1 if item.req_dex > 0 else 0) +
                   (1 if item.req_sci > 0 else 0)

    TW := i32(uis(238))
    TH := i32(uis(108)) +
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
        name := cw.render_config_name_cstr(rcc)
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

    slot_labels := [cw.EquipSlot]cstring{
        .Head          = "Slot: Head",
        .Chest         = "Slot: Chest",
        .Boots         = "Slot: Boots",
        .WeaponPrimary = "Slot: Weapon I",
        .WeaponOffhand = "Slot: Weapon II",
        .Consumable    = "Consumable",
        .Ability1      = "Ability: Q",
        .Ability2      = "Ability: E",
        .Ability3      = "Ability: F",
        .Ability4      = "Ability: G",
    }
    rl.DrawTextEx(g_font, slot_labels[item.slot], { tx2, ty2 + uis(42) }, fs13, 0.5, COL_MUTED)

    size_buf: [32]u8
    size_str := fmt.bprintf(size_buf[:31], "%d x %d", item.grid_w, item.grid_h)
    size_buf[len(size_str)] = 0
    rl.DrawTextEx(g_font, cstring(&size_buf[0]), { tx2, ty2 + uis(60) }, fs13, 0.5, COL_MUTED)

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
        req_y_base := ty2 + uis(78)
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
        .None            = "",
        .BonusHP         = "Max HP",
        .Armor           = "Armor",
        .BonusMoveSpeed  = "Move Speed",
        .BonusEnergy     = "Max Energy",
        .BonusDamage     = "Damage",
        .BonusFireRate   = "Fire Rate",
        .BonusReloadSpeed = "Reload Speed",
    }
    COL_AFFIX :: rl.Color{ 195, 168, 72, 235 }
    affix_base_y := ty2 + uis(78) + uis(17) * f32(req_count)
    for i in 0..<affix_count {
        a   := item.affixes[i]
        ay  := affix_base_y + uis(17) * f32(i)
        abuf: [32]u8
        as  := fmt.bprintf(abuf[:31], "+%.0f%%  %s", a.value * 100, affix_type_labels[a.type])
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

@(private = "file")
draw_section_header :: proc(px, py, sec_y_off, panel_w: i32, label: cstring, fs: f32) {
    lbl_sz := rl.MeasureTextEx(g_font, label, fs, 1)
    lbl_x  := f32(px) + f32(panel_w) * 0.5 - lbl_sz.x * 0.5
    mid_y  := f32(py + sec_y_off) + uis(9)
    rl.DrawLineEx({ f32(px) + uis(12), mid_y }, { lbl_x - uis(8), mid_y }, 1, COL_RULE)
    rl.DrawLineEx({ lbl_x + lbl_sz.x + uis(8), mid_y },
        { f32(px + panel_w) - uis(12), mid_y }, 1, COL_RULE)
    rl.DrawTextEx(g_font, label, { lbl_x, f32(py + sec_y_off) }, fs, 1, COL_MUTED)
}

update_inventory :: proc(w: ^cw.World) {
    if !cw.world_is_valid(w, w.player_id) { return }
    if !cw.world_has_component(w, w.player_id, .Inventory) { return }

    inv := cw.world_get_inventory(w, w.player_id)
    mp  := rl.GetMousePosition()
    px, py := inv_panel_origin()

    if g_playing_state == .Shop && rl.IsMouseButtonPressed(.RIGHT) && g_drag_item_id == -1 {
        col, row, in_grid := inv_mouse_to_cell(px, py, mp.x, mp.y)
        if in_grid {
            cell_id := inv.backpack[row * cw.BACKPACK_COLS + col]
            if cell_id != cw.INVALID_ENTITY {
                g_sell_item_id = cell_id
            }
        }
    }

    if rl.IsMouseButtonPressed(.LEFT) && g_drag_item_id == -1 {
        col, row, in_grid := inv_mouse_to_cell(px, py, mp.x, mp.y)
        if in_grid {
            cell_id := inv.backpack[row * cw.BACKPACK_COLS + col]
            if cell_id != cw.INVALID_ENTITY {
                item             := cw.world_get_item(w, cell_id)
                g_drag_origin_x   = item.pack_x
                g_drag_origin_y   = item.pack_y
                g_drag_from_equip = false
                backpack_remove(inv, item)
                g_drag_item_id    = cell_id
            }
        }
        if g_drag_item_id == -1 {
            for i in 0..<cw.EQUIP_SLOT_COUNT {
                slot := cw.EquipSlot(i)
                eid  := inv.equipped[i]
                if eid == cw.INVALID_ENTITY                         { continue }
                if !cw.world_has_component(w, eid, .Item)           { continue }
                rect, ok := equip_slot_rect(px, py, slot)
                if !ok { continue }
                if !rl.CheckCollisionPointRec(mp, rect) { continue }
                inv.equipped[i]     = cw.INVALID_ENTITY
                g_drag_item_id      = eid
                g_drag_from_equip   = true
                g_drag_origin_equip = slot
                break
            }
        }
    }

    if rl.IsMouseButtonReleased(.LEFT) && g_drag_item_id != -1 {
        item    := cw.world_get_item(w, g_drag_item_id)
        placed  := false

        for i in 0..<cw.EQUIP_SLOT_COUNT {
            slot := cw.EquipSlot(i)
            if !item_fits_slot(item.slot, slot)     { continue }
            if inv.equipped[i] != cw.INVALID_ENTITY { continue }  // slot occupied
            rect, ok := equip_slot_rect(px, py, slot)
            if !ok { continue }
            if !rl.CheckCollisionPointRec(mp, rect) { continue }
            // Stat requirement check — block equip if player lacks required stats
            if cw.world_has_component(w, w.player_id, .Stats) {
                st := cw.world_get_stats(w, w.player_id)
                if item.req_str > 0 && st.strength  < int(item.req_str) { break }
                if item.req_dex > 0 && st.dexterity < int(item.req_dex) { break }
                if item.req_sci > 0 && st.science   < int(item.req_sci) { break }
            }
            // Two-handed blocking:
            //   • Can't equip a 2H weapon in WeaponPrimary while offhand is occupied.
            //   • Can't equip anything in WeaponOffhand while a 2H weapon is in primary.
            if slot == .WeaponPrimary && item.is_two_handed {
                offhand_id := inv.equipped[int(cw.EquipSlot.WeaponOffhand)]
                if offhand_id != cw.INVALID_ENTITY { break }
            }
            if slot == .WeaponOffhand {
                prim_id := inv.equipped[int(cw.EquipSlot.WeaponPrimary)]
                if prim_id != cw.INVALID_ENTITY &&
                   cw.world_has_component(w, prim_id, .Item) &&
                   cw.world_get_item(w, prim_id).is_two_handed { break }
            }
            inv.equipped[i] = g_drag_item_id
            item.pack_x     = -1
            item.pack_y     = -1
            placed = true
            play_sfx("equip")
            break
        }

        if !placed {
            col, row, in_grid := inv_mouse_to_cell(px, py, mp.x, mp.y)
            if in_grid && backpack_can_place(inv, item, col, row) {
                backpack_place(inv, item, g_drag_item_id, col, row)
                placed = true
            }
        }

        if !placed {
            if g_drag_from_equip && inv.equipped[int(g_drag_origin_equip)] == cw.INVALID_ENTITY {
                inv.equipped[int(g_drag_origin_equip)] = g_drag_item_id
                item.pack_x = -1
                item.pack_y = -1
                placed = true
            } else if backpack_can_place(inv, item, g_drag_origin_x, g_drag_origin_y) {
                backpack_place(inv, item, g_drag_item_id, g_drag_origin_x, g_drag_origin_y)
                placed = true
            }
        }
        if !placed {
            c, r, ok := backpack_find_free(inv, item)
            if ok { backpack_place(inv, item, g_drag_item_id, c, r) }
        }

        g_drag_item_id      = -1
        g_drag_origin_x     = -1
        g_drag_origin_y     = -1
        g_drag_from_equip   = false
    }

    if g_drag_item_id == -1 {
        col, row, in_grid := inv_mouse_to_cell(px, py, mp.x, mp.y)
        if in_grid {
            g_hover_item_id = inv.backpack[row * cw.BACKPACK_COLS + col]
        } else {
            g_hover_item_id = cw.INVALID_ENTITY
            for i in 0..<cw.EQUIP_SLOT_COUNT {
                eid := inv.equipped[i]
                if eid == cw.INVALID_ENTITY { continue }
                rect, ok := equip_slot_rect(px, py, cw.EquipSlot(i))
                if !ok { continue }
                if rl.CheckCollisionPointRec(mp, rect) {
                    g_hover_item_id = eid
                    break
                }
            }
        }
    } else {
        g_hover_item_id = cw.INVALID_ENTITY
    }
}

draw_inventory :: proc(w: ^cw.World) {
    if !cw.world_is_valid(w, w.player_id) { return }

    px, py := inv_panel_origin()
    sec_fs := uis(15)

    clay.BeginLayout()
    panel_wf := f32(g_inv.panel_w)
    panel_hf := f32(rl.GetScreenHeight())
    if clay.UI(clay.ID("InvPanel"))({
        layout = {
            sizing = { clay.SizingFixed(panel_wf), clay.SizingFixed(panel_hf) },
        },
        floating = {
            offset     = { f32(px), 0 },
            attachment = { element = .LeftTop, parent = .LeftTop },
            attachTo   = .Root,
        },
        backgroundColor = { 10, 7, 5, 252 },
        border          = { color = { 90, 68, 28, 210 }, width = { 0, 0, 0, 2, 0 } },
    }) {}
    cmds := clay.EndLayout()
    clay_raylib_render(&cmds)

    rl.DrawRectangle(px, 0, g_inv.panel_w, i32(uis(2)), COL_BRASS)

    title    := cstring("E Q U I P M E N T")
    title_fs := uis(20)
    title_sz := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title, {
        f32(px) + f32(g_inv.panel_w) * 0.5 - title_sz.x * 0.5,
        f32(py + g_inv.title_y),
    }, title_fs, 1, COL_PARCH)
    rl.DrawLineEx(
        { f32(px) + uis(12), f32(py + g_inv.rule1_y) },
        { f32(px + g_inv.panel_w) - uis(12), f32(py + g_inv.rule1_y) }, 1, COL_RULE)

    var_inv: ^cw.InventoryComp
    if cw.world_has_component(w, w.player_id, .Inventory) {
        var_inv = cw.world_get_inventory(w, w.player_id)
    }

    drag_item_slot: cw.EquipSlot
    has_drag := g_drag_item_id != -1 && cw.world_is_valid(w, g_drag_item_id)
    if has_drag && cw.world_has_component(w, g_drag_item_id, .Item) {
        drag_item_slot = cw.world_get_item(w, g_drag_item_id).slot
    }
    slot_is_target :: proc(
        inv: ^cw.InventoryComp, has_drag: bool,
        drag_item_slot: cw.EquipSlot, slot: cw.EquipSlot,
    ) -> bool {
        if !has_drag { return false }
        if !item_fits_slot(drag_item_slot, slot) { return false }
        if inv == nil { return false }
        return inv.equipped[int(slot)] == cw.INVALID_ENTITY
    }

    armor_labels := [3]cstring{ "HEAD", "CHEST", "BOOTS" }
    armor_slots  := [3]cw.EquipSlot{ .Head, .Chest, .Boots }
    for i in 0..<3 {
        sy  := py + g_inv.slots_y + i32(i) * (g_inv.slot_h + g_inv.slot_gap)
        n, has := inv_slot_name(w, var_inv, armor_slots[i])
        draw_equip_slot_h(px + g_inv.pad, sy, g_inv.slot_w, g_inv.slot_h, armor_labels[i], n, has)
        if slot_is_target(var_inv, has_drag, drag_item_slot, armor_slots[i]) {
            rl.DrawRectangleLinesEx(
                { f32(px + g_inv.pad), f32(sy), f32(g_inv.slot_w), f32(g_inv.slot_h) },
                2, rl.Color{ 215, 175, 28, 200 })
        }
    }

    draw_section_header(px, py, g_inv.sec_y, g_inv.panel_w, "WEAPONS", sec_fs)

    wy := py + g_inv.wep_y

    wep_label1: cstring = "WEAPON I"
    if cw.world_has_component(w, w.player_id, .Equipment) {
        eq := cw.world_get_equipment(w, w.player_id)
        if cw.world_is_valid(w, eq.weapon_entity_id) &&
           cw.world_has_component(w, eq.weapon_entity_id, .RenderConfig) {
            wep_label1 = cw.render_config_name_cstr(
                cw.world_get_render_config(w, eq.weapon_entity_id))
        }
    }

    offhand_blocked := false
    if var_inv != nil {
        prim_id := var_inv.equipped[int(cw.EquipSlot.WeaponPrimary)]
        if prim_id != cw.INVALID_ENTITY && cw.world_has_component(w, prim_id, .Item) {
            offhand_blocked = cw.world_get_item(w, prim_id).is_two_handed
        }
    }

    wn1, whas1 := inv_slot_name(w, var_inv, .WeaponPrimary)
    wn2, whas2 := inv_slot_name(w, var_inv, .WeaponOffhand)
    draw_weapon_slot_box(px + g_inv.pad,
        wy, g_inv.wep_w, g_inv.wep_h, wep_label1, wn1, whas1)
    draw_weapon_slot_box(px + g_inv.pad + g_inv.wep_w + g_inv.col_gap,
        wy, g_inv.wep_w, g_inv.wep_h, "OFFHAND MOD", wn2, whas2, offhand_blocked)
    for wslot in ([]cw.EquipSlot{ .WeaponPrimary, .WeaponOffhand }) {
        if wslot == .WeaponOffhand && offhand_blocked { continue }
        if slot_is_target(var_inv, has_drag, drag_item_slot, wslot) {
            r, _ := equip_slot_rect(px, py, wslot)
            rl.DrawRectangleLinesEx(r, 2, rl.Color{ 215, 175, 28, 200 })
        }
    }

    draw_section_header(px, py, g_inv.ability_sec_y, g_inv.panel_w, "ABILITIES", sec_fs)

    ab_labels := [4]cstring{ "Q", "E", "F", "G" }
    ab_slots  := [4]cw.EquipSlot{ .Ability1, .Ability2, .Ability3, .Ability4 }
    for i in 0..<4 {
        ar, _ := equip_slot_rect(px, py, ab_slots[i])
        n, has := inv_slot_name(w, var_inv, ab_slots[i])
        rl.DrawRectangle(i32(ar.x), i32(ar.y), i32(ar.width), i32(ar.height),
            rl.Color{ 20, 16, 12, 240 })
        rl.DrawRectangleLinesEx(ar, 1, COL_RULE)
        rl.DrawTextEx(g_font, ab_labels[i],
            { ar.x + uis(5), ar.y + uis(4) }, uis(13), 1, COL_BRASS)
        name_col := COL_PARCH if has else rl.Color{ 80, 74, 58, 130 }
        ab_name_str := n if has else cstring("empty")
        rl.DrawTextEx(g_font, ab_name_str,
            { ar.x + uis(5), ar.y + uis(22) }, uis(11), 0.5, name_col)
        if slot_is_target(var_inv, has_drag, drag_item_slot, ab_slots[i]) {
            rl.DrawRectangleLinesEx(ar, 2, rl.Color{ 215, 175, 28, 200 })
        }
    }

    draw_section_header(px, py, g_inv.pack_sec_y, g_inv.panel_w, "B A C K P A C K", sec_fs)

    gx := px + g_inv.pad
    gy := py + g_inv.pack_y

    grid_w := i32(cw.BACKPACK_COLS) * g_inv.cell_sz
    grid_h := i32(cw.BACKPACK_ROWS) * g_inv.cell_sz

    for r in 0..<i32(cw.BACKPACK_ROWS) {
        for c in 0..<i32(cw.BACKPACK_COLS) {
            cx := gx + c * g_inv.cell_sz
            cy := gy + r * g_inv.cell_sz
            cs := g_inv.cell_sz
            rl.DrawRectangle(cx, cy, cs, cs, rl.Color{ 8, 6, 4, 255 })
            rl.DrawRectangle(cx + 1, cy + 1, cs - 2, cs - 2, rl.Color{ 18, 14, 10, 255 })
            rl.DrawLineEx({ f32(cx + 1), f32(cy + 1) }, { f32(cx + cs - 1), f32(cy + 1) },
                1, rl.Color{ 0, 0, 0, 80 })
            rl.DrawLineEx({ f32(cx + 1), f32(cy + 1) }, { f32(cx + 1), f32(cy + cs - 1) },
                1, rl.Color{ 0, 0, 0, 80 })
        }
    }

    if var_inv != nil {
        for row in 0..<cw.BACKPACK_ROWS {
            for col in 0..<cw.BACKPACK_COLS {
                cell_id := var_inv.backpack[row * cw.BACKPACK_COLS + col]
                if cell_id == cw.INVALID_ENTITY  { continue }
                if cell_id == g_drag_item_id      { continue }
                if !cw.world_is_valid(w, cell_id) { continue }
                item := cw.world_get_item(w, cell_id)
                if item.pack_x != col || item.pack_y != row { continue }

                rc := rarity_color(item.rarity)
                ix := gx + i32(col) * g_inv.cell_sz + 2
                iy := gy + i32(row) * g_inv.cell_sz + 2
                iw := i32(item.grid_w) * g_inv.cell_sz - 4
                ih := i32(item.grid_h) * g_inv.cell_sz - 4

                rl.DrawRectangle(ix, iy, iw, ih,
                    rl.Color{ rc.r / 5, rc.g / 5, rc.b / 5, 230 })
                rl.DrawRectangleLinesEx({ f32(ix), f32(iy), f32(iw), f32(ih) }, 1,
                    rl.Color{ rc.r, rc.g, rc.b, 220 })

                icon_margin :: i32(3)
                icon_sz     := min(iw, ih) - icon_margin * 2
                icon_drawn  := false

                if cw.world_has_component(w, cell_id, .RenderConfig) {
                    rcc := cw.world_get_render_config(w, cell_id)
                    if rcc.icon_len > 0 {
                        tex, ok := get_or_load_icon(cw.render_config_icon_cstr(rcc))
                        if ok {
                            iicon_x := ix + (iw - icon_sz) / 2
                            iicon_y := iy + icon_margin
                            src := rl.Rectangle{ 0, 0, f32(tex.width), f32(tex.height) }
                            dst := rl.Rectangle{ f32(iicon_x), f32(iicon_y), f32(icon_sz), f32(icon_sz) }
                            rl.DrawTexturePro(tex, src, dst, {0, 0}, 0,
                                rl.Color{ rc.r, rc.g, rc.b, 210 })
                            icon_drawn = true
                        }
                    }
                }
                if !icon_drawn {
                    draw_item_glyph(item.slot,
                        ix + (iw - icon_sz) / 2, iy + icon_margin, icon_sz, rc)
                }
                if cw.world_has_component(w, cell_id, .RenderConfig) {
                    rcc  := cw.world_get_render_config(w, cell_id)
                    name := cw.render_config_name_cstr(rcc)
                    rl.DrawTextEx(g_font, name,
                        { f32(ix) + uis(3), f32(iy + icon_margin + icon_sz + 2) },
                        uis(11), 0.4, rl.Color{ rc.r, rc.g, rc.b, 200 })
                }
            }
        }
    }

    for c in 0..=i32(cw.BACKPACK_COLS) {
        lx := f32(gx + c * g_inv.cell_sz)
        rl.DrawLineEx({ lx, f32(gy) }, { lx, f32(gy + grid_h) }, 1, COL_RULE)
    }
    for r in 0..=i32(cw.BACKPACK_ROWS) {
        ly := f32(gy + r * g_inv.cell_sz)
        rl.DrawLineEx({ f32(gx), ly }, { f32(gx + grid_w), ly }, 1, COL_RULE)
    }

    if g_drag_item_id != -1 && cw.world_is_valid(w, g_drag_item_id) {
        mp   := rl.GetMousePosition()
        item := cw.world_get_item(w, g_drag_item_id)

        col, row, in_grid := inv_mouse_to_cell(px, py, mp.x, mp.y)
        if in_grid {
            can    := backpack_can_place(var_inv, item, col, row)
            hi_col := rl.Color{ 60, 180, 60, 80 } if can else rl.Color{ 180, 40, 40, 80 }
            for dy in 0..<item.grid_h {
                for dx in 0..<item.grid_w {
                    if col+dx < cw.BACKPACK_COLS && row+dy < cw.BACKPACK_ROWS {
                        rl.DrawRectangle(
                            gx + i32(col+dx) * g_inv.cell_sz,
                            gy + i32(row+dy) * g_inv.cell_sz,
                            g_inv.cell_sz, g_inv.cell_sz, hi_col)
                    }
                }
            }
        }

        iw := i32(item.grid_w) * g_inv.cell_sz - 4
        ih := i32(item.grid_h) * g_inv.cell_sz - 4
        fx := i32(mp.x) - iw / 2
        fy := i32(mp.y) - ih / 2
        drag_rc := rarity_color(item.rarity)
        rl.DrawRectangle(fx, fy, iw, ih,
            rl.Color{ drag_rc.r / 5, drag_rc.g / 5, drag_rc.b / 5, 230 })
        rl.DrawRectangleLinesEx({ f32(fx), f32(fy), f32(iw), f32(ih) }, 1,
            rl.Color{ drag_rc.r, drag_rc.g, drag_rc.b, 240 })

        drag_icon_sz    := min(iw, ih) - 6
        drag_icon_x     := fx + (iw - drag_icon_sz) / 2
        drag_icon_y     := fy + (ih - drag_icon_sz) / 2
        drag_icon_drawn := false
        if cw.world_has_component(w, g_drag_item_id, .RenderConfig) {
            rcc := cw.world_get_render_config(w, g_drag_item_id)
            if rcc.icon_len > 0 {
                tex, ok := get_or_load_icon(cw.render_config_icon_cstr(rcc))
                if ok {
                    src := rl.Rectangle{ 0, 0, f32(tex.width), f32(tex.height) }
                    dst := rl.Rectangle{
                        f32(drag_icon_x), f32(drag_icon_y),
                        f32(drag_icon_sz), f32(drag_icon_sz) }
                    rl.DrawTexturePro(tex, src, dst, {0, 0}, 0,
                        rl.Color{ drag_rc.r, drag_rc.g, drag_rc.b, 210 })
                    drag_icon_drawn = true
                }
            }
        }
        if !drag_icon_drawn {
            draw_item_glyph(item.slot, drag_icon_x, drag_icon_y, drag_icon_sz, drag_rc)
        }
    }

    // ── Tooltip ───────────────────────────────────────────────────────────
    if g_hover_item_id != cw.INVALID_ENTITY && g_drag_item_id == -1 {
        mp2 := rl.GetMousePosition()
        draw_item_tooltip(w, g_hover_item_id, mp2.x, mp2.y)
    }

    // ── Close hint ────────────────────────────────────────────────────────
    hint    := cstring("[I]  Close")
    hint_sz := rl.MeasureTextEx(g_font, hint, sec_fs, 1)
    rl.DrawTextEx(g_font, hint, {
        f32(px) + f32(g_inv.panel_w) * 0.5 - hint_sz.x * 0.5,
        f32(py + g_inv.hint_y),
    }, sec_fs, 1, COL_MUTED)
}


@(private = "file")
STATS_W_BASE :: f32(360)
@(private = "file")
STATS_H_BASE :: f32(582)

update_stats_screen :: proc(w: ^cw.World) {
    if !cw.world_is_valid(w, w.player_id) { return }
    if !cw.world_has_component(w, w.player_id, .Stats) { return }
    if !rl.IsMouseButtonPressed(.LEFT) { return }

    st := cw.world_get_stats(w, w.player_id)
    if st.stat_points <= 0 { return }

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    PW := i32(uis(STATS_W_BASE))
    PH := i32(uis(STATS_H_BASE))
    px := i32(sw * 0.5) - PW / 2
    py := i32(sh * 0.5) - PH / 2

    mp    := rl.GetMousePosition()
    btn_w := i32(uis(28))
    btn_h := i32(uis(24))

    for i in 0..<3 {
        row_y := i32(uis(144)) + i32(uis(72)) * i32(i)
        rh    := i32(uis(60))
        rw    := PW - i32(uis(48))
        rx    := px + i32(uis(24))
        ry    := py + row_y
        btn_x := rx + rw - btn_w - i32(uis(8))
        btn_y := ry + (rh - btn_h) / 2
        btn_r := rl.Rectangle{ f32(btn_x), f32(btn_y), f32(btn_w), f32(btn_h) }
        if rl.CheckCollisionPointRec(mp, btn_r) {
            switch i {
            case 0: st.strength   += 1
            case 1: st.dexterity  += 1
            case 2: st.science    += 1
            }
            st.stat_points -= 1
            play_sfx("stat_up")
            if cw.world_is_valid(w, w.player_id) {
                save_player(w, w.player_id)
            }
            return
        }
    }
}

draw_stats_screen :: proc(w: ^cw.World) {
    if !cw.world_is_valid(w, w.player_id) { return }
    if !cw.world_has_component(w, w.player_id, .Stats) { return }

    st := cw.world_get_stats(w, w.player_id)

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    PW := i32(uis(STATS_W_BASE))
    PH := i32(uis(STATS_H_BASE))
    px := i32(sw * 0.5) - PW / 2
    py := i32(sh * 0.5) - PH / 2

    rl.DrawRectangle(px, py, PW, PH, COL_PANEL)
    rl.DrawRectangleLinesEx({ f32(px), f32(py), f32(PW), f32(PH) }, 1, COL_RULE)

    title    := cstring("C H A R A C T E R")
    title_fs := uis(22)
    tsz := rl.MeasureTextEx(g_font, title, title_fs, 1)
    rl.DrawTextEx(g_font, title,
        { f32(px) + f32(PW)*0.5 - tsz.x*0.5, f32(py) + uis(14) },
        title_fs, 1, COL_PARCH)
    rl.DrawLineEx(
        { f32(px) + uis(16), f32(py) + uis(48) },
        { f32(px) + f32(PW) - uis(16), f32(py) + uis(48) },
        1, COL_RULE)

    lfs   := uis(18)
    lvbuf : [32]u8
    lvs   := fmt.bprintf(lvbuf[:31], "Level  %d", st.level)
    lvbuf[len(lvs)] = 0
    rl.DrawTextEx(g_font, cstring(&lvbuf[0]),
        { f32(px) + uis(24), f32(py) + uis(58) }, lfs, 1, COL_PARCH)

    xp_ratio := clamp(st.xp / st.xp_next, 0, 1) if st.xp_next > 0 else f32(0)
    bar_x := px + i32(uis(24))
    bar_y := py + i32(uis(82))
    bar_w := PW - i32(uis(48))
    bar_h := i32(uis(12))
    rl.DrawRectangle(bar_x, bar_y, bar_w, bar_h, { 30, 24, 10, 255 })
    rl.DrawRectangle(bar_x, bar_y, i32(f32(bar_w) * xp_ratio), bar_h, { 180, 148, 36, 255 })
    rl.DrawRectangleLinesEx({ f32(bar_x), f32(bar_y), f32(bar_w), f32(bar_h) }, 1, COL_RULE)

    xpbuf : [48]u8
    xps   := fmt.bprintf(xpbuf[:47], "%.0f / %.0f xp", st.xp, st.xp_next)
    xpbuf[len(xps)] = 0
    xpsz := rl.MeasureTextEx(g_font, cstring(&xpbuf[0]), uis(12), 0.5)
    rl.DrawTextEx(g_font, cstring(&xpbuf[0]),
        { f32(bar_x) + f32(bar_w)*0.5 - xpsz.x*0.5, f32(bar_y) + uis(15) },
        uis(12), 0.5, COL_MUTED)

    rl.DrawLineEx(
        { f32(px) + uis(16), f32(py) + uis(110) },
        { f32(px) + f32(PW) - uis(16), f32(py) + uis(110) },
        1, COL_RULE)

    sfs := uis(14)
    rl.DrawTextEx(g_font, "STATS",
        { f32(px) + uis(24), f32(py) + uis(118) }, sfs, 1, COL_MUTED)

    if st.stat_points > 0 {
        ptbuf : [32]u8
        pts   := fmt.bprintf(ptbuf[:31], "%d  point%s  available",
            st.stat_points, "s" if st.stat_points != 1 else "")
        ptbuf[len(pts)] = 0
        ptsz := rl.MeasureTextEx(g_font, cstring(&ptbuf[0]), sfs, 0.5)
        rl.DrawTextEx(g_font, cstring(&ptbuf[0]),
            { f32(px) + f32(PW) - uis(24) - ptsz.x, f32(py) + uis(118) },
            sfs, 0.5, { 200, 175, 60, 230 })
    }

    stat_names  := [3]cstring{ "Strength", "Dexterity", "Science" }
    stat_values := [3]int{ st.strength, st.dexterity, st.science }

    for i in 0..<3 {
        row_y := i32(uis(144)) + i32(uis(72)) * i32(i)
        rh    := i32(uis(60))
        rw    := PW - i32(uis(48))
        rx    := px + i32(uis(24))
        ry    := py + row_y

        rl.DrawRectangle(rx, ry, rw, rh, { 18, 14, 10, 200 })
        rl.DrawRectangleLinesEx({ f32(rx), f32(ry), f32(rw), f32(rh) }, 1,
            { 80, 65, 42, 130 })

        nfs := uis(18)
        rl.DrawTextEx(g_font, stat_names[i],
            { f32(rx) + uis(12), f32(ry) + uis(10) }, nfs, 1, COL_PARCH)

        vbuf : [8]u8
        vs   := fmt.bprintf(vbuf[:7], "%d", stat_values[i])
        vbuf[len(vs)] = 0
        rl.DrawTextEx(g_font, cstring(&vbuf[0]),
            { f32(rx) + uis(12), f32(ry) + uis(33) }, nfs, 1, COL_BRASS)

        dfs  := uis(13)
        dbuf : [32]u8
        ds   : string
        switch i {
        case 0: ds = fmt.bprintf(dbuf[:31], "+%.0f%%  HP", f32(stat_values[i]-1)*15)
        case 1: ds = fmt.bprintf(dbuf[:31], "+%.0f%%  Speed", f32(stat_values[i]-1)*8)
        case 2: ds = fmt.bprintf(dbuf[:31], "+%.0f%%  Energy", f32(stat_values[i]-1)*12)
        }
        dbuf[len(ds)] = 0
        dsz := rl.MeasureTextEx(g_font, cstring(&dbuf[0]), dfs, 0.5)

        btn_w := i32(uis(28))
        btn_h := i32(uis(24))
        btn_x := rx + rw - btn_w - i32(uis(8))
        btn_y := ry + (rh - btn_h) / 2

        rl.DrawTextEx(g_font, cstring(&dbuf[0]),
            { f32(btn_x) - dsz.x - uis(10), f32(ry) + uis(35) },
            dfs, 0.5, COL_MUTED)

        btn_active := st.stat_points > 0
        btn_bg  := rl.Color{ 55, 44, 18, 200 } if btn_active else rl.Color{ 28, 22, 12, 140 }
        btn_brd := COL_RULE                     if btn_active else rl.Color{ 55, 48, 32, 80  }
        btn_tc  := COL_PARCH                    if btn_active else rl.Color{ 80, 70, 45, 100 }
        rl.DrawRectangle(btn_x, btn_y, btn_w, btn_h, btn_bg)
        rl.DrawRectangleLinesEx({ f32(btn_x), f32(btn_y), f32(btn_w), f32(btn_h) }, 1, btn_brd)
        plus_fs := uis(16)
        plsz := rl.MeasureTextEx(g_font, "+", plus_fs, 1)
        rl.DrawTextEx(g_font, "+",
            { f32(btn_x) + f32(btn_w)*0.5 - plsz.x*0.5,
              f32(btn_y) + f32(btn_h)*0.5 - plsz.y*0.5 },
            plus_fs, 1, btn_tc)
    }

    rl.DrawLineEx(
        { f32(px) + uis(16), f32(py) + uis(358) },
        { f32(px) + f32(PW) - uis(16), f32(py) + uis(358) },
        1, COL_RULE)
    rl.DrawTextEx(g_font, "HISTORY",
        { f32(px) + uis(24), f32(py) + uis(366) }, sfs, 1, COL_MUTED)

    hist_rows := [4][2]string{
        { "Raids completed",  fmt.tprintf("%d",  g_lifetime_stats.successful_raids) },
        { "Enemies killed",   fmt.tprintf("%d",  g_lifetime_stats.enemies_killed)   },
        { "Deaths",           fmt.tprintf("%d",  g_lifetime_stats.deaths)           },
        { "Best extract",     fmt.tprintf("%d g",int(g_lifetime_stats.max_extract_gold)) },
    }
    hfs := uis(14)
    for row, ri in hist_rows {
        hy := f32(py) + uis(390) + f32(ri) * uis(34)
        rl.DrawTextEx(g_font, strings.clone_to_cstring(row[0], context.temp_allocator),
            { f32(px) + uis(24), hy }, hfs, 0.5, COL_MUTED)
        vsz := rl.MeasureTextEx(g_font, strings.clone_to_cstring(row[1], context.temp_allocator), hfs, 0.5)
        rl.DrawTextEx(g_font, strings.clone_to_cstring(row[1], context.temp_allocator),
            { f32(px) + f32(PW) - uis(24) - vsz.x, hy }, hfs, 0.5, COL_PARCH)
    }

    rl.DrawLineEx(
        { f32(px) + uis(16), f32(py) + f32(PH) - uis(32) },
        { f32(px) + f32(PW) - uis(16), f32(py) + f32(PH) - uis(32) },
        1, COL_RULE)
    rl.DrawTextEx(g_font, "[C]  Close",
        { f32(px) + uis(24), f32(py) + f32(PH) - uis(22) }, uis(13), 0.5, COL_MUTED)
}

draw_levelup_flash :: proc() {
    if g_levelup_flash <= 0 { return }

    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()

    alpha := u8(clamp(g_levelup_flash / LEVELUP_FLASH_TIME, 0, 1) * 230)
    fs    := uis(52)
    text  := cstring("LEVEL  UP!")
    tsz   := rl.MeasureTextEx(g_font, text, fs, 2)
    rl.DrawTextEx(g_font, text,
        { f32(sw)*0.5 - tsz.x*0.5, f32(sh)*0.36 - tsz.y*0.5 },
        fs, 2, { 220, 196, 58, alpha })

    sfs  := uis(18)
    sub  := cstring("Stat point earned!")
    ssz  := rl.MeasureTextEx(g_font, sub, sfs, 1)
    salp := u8(clamp(g_levelup_flash / LEVELUP_FLASH_TIME, 0, 1) * 180)
    rl.DrawTextEx(g_font, sub,
        { f32(sw)*0.5 - ssz.x*0.5, f32(sh)*0.36 + tsz.y*0.5 + uis(6) },
        sfs, 1, { 200, 180, 120, salp })
}

