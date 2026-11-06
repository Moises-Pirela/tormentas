package main

import    "core:math"
import rl "vendor:raylib"

HPBAR_HOLD      :: f32(2.5)
HPBAR_FADE      :: f32(0.6)
HPBAR_CHIP_WAIT :: f32(0.35)
HPBAR_CHIP_RATE :: f32(1.4)
HPBAR_MIN_W     :: f32(34)
HPBAR_H         :: f32(4)

TELEGRAPH_TINT  :: rl.Color{ 255, 110, 60, 255 }
TELEGRAPH_MELEE :: rl.Color{ 255, 80, 40, 255 }
TELEGRAPH_AIM   :: rl.Color{ 255, 205, 70, 255 }
TELEGRAPH_LOCK  :: rl.Color{ 255, 55, 45, 255 }

EnemyOverlayAnchor :: struct {
    id:        int,
    pos:       rl.Vector2,
    base_size: f32,
    top:       f32,
}

HpBarState :: struct {
    last_frac: f32,
    chip_frac: f32,
    since_hit: f32,
    chip_wait: f32,
    seen:      bool,
}

g_enemy_overlays: [dynamic]EnemyOverlayAnchor
g_hpbar_state:    map[int]HpBarState

g_enemy_overlay_frame: f64

enemy_overlay_queue :: proc(id: int, pos: rl.Vector2, base_size, top: f32) {
    now := rl.GetTime()
    if now != g_enemy_overlay_frame {
        clear(&g_enemy_overlays)
        g_enemy_overlay_frame = now
    }
    for o in g_enemy_overlays { if o.id == id { return } }
    append(&g_enemy_overlays, EnemyOverlayAnchor{ id, pos, base_size, top })
}

enemy_windup_progress :: proc(ai: AIAgentComp) -> f32 {
    if ai.windup <= 0 || ai.windup_max <= 0 { return 0 }
    return clamp(1 - ai.windup / ai.windup_max, 0, 1)
}

hpbar_alpha :: proc(since_hit: f32, hovered, pinned: bool) -> f32 {
    if hovered || pinned { return 1 }
    if since_hit <= HPBAR_HOLD { return 1 }
    a := clamp(1 - (since_hit - HPBAR_HOLD) / HPBAR_FADE, 0, 1)
    return a if a > 0.001 else 0
}

hpbar_step :: proc(st: ^HpBarState, frac, dt: f32) {
    if !st.seen || frac > st.last_frac + 0.001 {
        if !st.seen { st.since_hit = HPBAR_HOLD + HPBAR_FADE + 1 }
        st.seen      = true
        st.chip_frac = frac
        st.last_frac = frac
        return
    }
    if frac < st.last_frac - 0.0005 {
        st.since_hit = 0
        st.chip_wait = HPBAR_CHIP_WAIT
        st.last_frac = frac
    } else {
        st.since_hit += dt
    }
    if st.chip_wait > 0 {
        st.chip_wait -= dt
    } else if st.chip_frac > frac {
        st.chip_frac = max(frac, st.chip_frac - HPBAR_CHIP_RATE * dt)
    }
    st.chip_frac = max(st.chip_frac, frac)
}

@(private = "file")
_fade :: proc(c: rl.Color, a: f32) -> rl.Color {
    return { c.r, c.g, c.b, u8(f32(c.a) * clamp(a, 0, 1)) }
}

@(private = "file")
_tri :: proc(a, b, c: rl.Vector2, col: rl.Color) {
    cross := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    if cross >= 0 { rl.DrawTriangle(a, b, c, col) } else { rl.DrawTriangle(a, c, b, col) }
}

draw_world_sector :: proc(center: rl.Vector2, radius, angle, half_spread: f32, col: rl.Color) {
    SEG :: 14
    c := world_to_iso_v(center)
    prev := world_to_iso_v({ center.x + math.cos(angle - half_spread) * radius,
                             center.y + math.sin(angle - half_spread) * radius })
    for i in 1..=SEG {
        a  := angle - half_spread + 2 * half_spread * f32(i) / SEG
        nx := world_to_iso_v({ center.x + math.cos(a) * radius, center.y + math.sin(a) * radius })
        _tri(c, prev, nx, col)
        prev = nx
    }
}

draw_world_sector_outline :: proc(center: rl.Vector2, radius, angle, half_spread, thick: f32, col: rl.Color) {
    SEG :: 14
    c := world_to_iso_v(center)
    first := world_to_iso_v({ center.x + math.cos(angle - half_spread) * radius,
                              center.y + math.sin(angle - half_spread) * radius })
    rl.DrawLineEx(c, first, thick, col)
    prev := first
    for i in 1..=SEG {
        a  := angle - half_spread + 2 * half_spread * f32(i) / SEG
        nx := world_to_iso_v({ center.x + math.cos(a) * radius, center.y + math.sin(a) * radius })
        rl.DrawLineEx(prev, nx, thick, col)
        prev = nx
    }
    rl.DrawLineEx(prev, c, thick, col)
}

draw_enemy_telegraphs :: proc(w: ^World) {
    for o in g_enemy_overlays {
        if !world_is_valid(w, o.id) || !world_has_component(w, o.id, .AIAgent) { continue }
        ai := comp_get(w, o.id, .AIAgent, AIAgentComp)^
        p  := enemy_windup_progress(ai)
        if p <= 0 { continue }

        switch ai.ai_type {
        case .Melee:
            reach := ai.attack_range + PLAYER_RADIUS
            draw_world_sector(o.pos, reach, ai.windup_angle, ARC_SPREAD, _fade(TELEGRAPH_MELEE, 0.16 + 0.12 * p))
            draw_world_sector(o.pos, reach * p, ai.windup_angle, ARC_SPREAD, _fade(TELEGRAPH_MELEE, 0.30 + 0.30 * p))
            edge := TELEGRAPH_MELEE if p < 0.85 else rl.Color{ 255, 235, 210, 255 }
            draw_world_sector_outline(o.pos, reach, ai.windup_angle, ARC_SPREAD, 1.5 + p, _fade(edge, 0.55 + 0.45 * p))

        case .Ranged:
            count, spread := ai_pellet_layout(ai)
            speed, life   := ai_projectile_reach(ai)
            length        := speed * life
            locked        := p >= AI_RANGED_AIM_LOCK_AT
            col           := TELEGRAPH_LOCK if locked else TELEGRAPH_AIM
            thick         := 1.0 + 2.0 * p
            for i in 0..<count {
                off := f32(0)
                if count > 1 { off = spread * (f32(i) / f32(count - 1) - 0.5) }
                a   := ai.windup_angle + off
                end := rl.Vector2{ o.pos.x + math.cos(a) * length, o.pos.y + math.sin(a) * length }
                if t := raycast_walls_t(o.pos.x, o.pos.y, end.x, end.y); t < 1 {
                    end = { o.pos.x + (end.x - o.pos.x) * t, o.pos.y + (end.y - o.pos.y) * t }
                }
                draw_world_line(o.pos, end, thick + 2, _fade(rl.Color{ 10, 6, 6, 255 }, 0.25 + 0.35 * p))
                draw_world_line(o.pos, end, thick, _fade(col, 0.35 + 0.6 * p))
            }
        }
    }
}

@(private = "file")
_hovered :: proc(o: EnemyOverlayAnchor, bar_w: f32) -> bool {
    m   := rl.GetScreenToWorld2D(rl.GetMousePosition(), g_camera^)
    iso := world_to_iso_v(o.pos)
    hw  := max(bar_w, o.base_size * 0.5) * 0.5 + 6
    return m.x >= iso.x - hw && m.x <= iso.x + hw && m.y >= iso.y - o.top - 10 && m.y <= iso.y + 8
}

draw_enemy_health_bars :: proc(w: ^World, dt: f32) {
    defer clear(&g_enemy_overlays)

    for id in g_hpbar_state {
        if !world_is_valid(w, id) || !world_has_component(w, id, .Health) {
            delete_key(&g_hpbar_state, id)
        }
    }

    for o in g_enemy_overlays {
        if !world_is_valid(w, o.id) || !world_has_component(w, o.id, .Health) { continue }
        h := comp_get(w, o.id, .Health, HealthComp)
        if h.max <= 0 { continue }
        frac := clamp(h.current / h.max, 0, 1)

        st := g_hpbar_state[o.id]
        hpbar_step(&st, frac, dt)
        g_hpbar_state[o.id] = st

        bar_w   := max(o.base_size * 0.7, HPBAR_MIN_W)
        hovered := _hovered(o, bar_w)
        pinned  := o.id == g_boss_id || frac <= 0
        if frac <= 0 { continue }
        alpha := hpbar_alpha(st.since_hit, hovered, pinned)
        if alpha <= 0.01 { continue }

        border := rl.Color{ 10, 8, 8, 220 }
        if world_has_component(w, o.id, .AIAgent) {
            #partial switch comp_get(w, o.id, .AIAgent, AIAgentComp).tier {
            case .Rare:      border = rl.Color{ 110, 160, 255, 235 }
            case .Legendary: border = rl.Color{ 240, 195,  50, 235 }
            }
        }

        iso := world_to_iso_v(o.pos)
        bx  := iso.x - bar_w * 0.5
        by  := iso.y - o.top - 8
        rl.DrawRectangleRec({ bx - 1.5, by - 1.5, bar_w + 3, HPBAR_H + 3 }, _fade(border, alpha))
        rl.DrawRectangleRec({ bx, by, bar_w, HPBAR_H }, _fade(rl.Color{ 34, 14, 14, 235 }, alpha))
        rl.DrawRectangleRec({ bx, by, bar_w * st.chip_frac, HPBAR_H }, _fade(rl.Color{ 245, 225, 190, 230 }, alpha))
        fill := rl.Color{ 215, 45, 40, 255 }
        if frac <= 0.25 { fill = _mix(fill, rl.Color{ 255, 140, 60, 255 }, 0.5 + 0.5 * math.sin(f32(rl.GetTime()) * 10)) }
        rl.DrawRectangleRec({ bx, by, bar_w * frac, HPBAR_H }, _fade(fill, alpha))
    }
}

@(private = "file")
_mix :: proc(a, b: rl.Color, k: f32) -> rl.Color {
    t := clamp(k, 0, 1)
    return {
        u8(f32(a.r) + (f32(b.r) - f32(a.r)) * t), u8(f32(a.g) + (f32(b.g) - f32(a.g)) * t),
        u8(f32(a.b) + (f32(b.b) - f32(a.b)) * t), u8(f32(a.a) + (f32(b.a) - f32(a.a)) * t),
    }
}
