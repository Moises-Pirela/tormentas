package main

import "core:math"
import rl "vendor:raylib"
import cw "clockwork"

// =============================================================================
// stealth_system — vision cones, noise propagation, AI suspicion meter
//
// Pipeline per tick:
//   EarlyUpdate  emit per-frame movement noise from moving players
//   Update       run AI perception (cone sight + noise events) and update states
//   LateUpdate   flush the per-frame noise event buffer
//
// Any system that wants to alert enemies calls  emit_noise(pos, radius, strength).
// weapon_system calls it on every player shot with STEALTH_NOISE_LOUD.
//
// AI state machine (stored in AIAgentComp.state):
//   AI_STATE_IDLE        0 — standing still, passive cone scan
//   AI_STATE_SUSPICIOUS  1 — something noticed; "?" icon; suspicion builds
//   AI_STATE_SEARCHING   2 — fully alerted; "!" amber; moving to last known pos
//   AI_STATE_CHASE       3 — visual lock; "!" red; full-speed pursuit
//   AI_STATE_ATTACK      4 — in attack range; handled exclusively by ai_system
// =============================================================================

AI_STATE_IDLE       :: u8(0)
AI_STATE_SUSPICIOUS :: u8(1)
AI_STATE_SEARCHING  :: u8(2)
AI_STATE_CHASE      :: u8(3)
AI_STATE_ATTACK     :: u8(4)

// ── Tuning ─────────────────────────────────────────────────────────────────────

STEALTH_CONE_HALF   :: f32(math.PI / 2.8) // ≈ 64° half-angle; wide feels fair
STEALTH_RATE_LIT    :: f32(2.0)            // full detection in 0.5 s  (bright room)
STEALTH_RATE_DARK   :: f32(0.55)           // full detection in ~1.8 s (dark room)
STEALTH_DECAY       :: f32(0.45)           // suspicion lost per second when idle
STEALTH_NOISE_LOUD  :: f32(1.0)            // gunshot  → instant full alert
STEALTH_NOISE_MED   :: f32(0.45)           // heavy movement / impact
STEALTH_DARK_THRESH :: f32(0.40)           // g_light_ambient below this = dark level
STEALTH_SEARCH_TIME :: f32(4.5)            // seconds to search before giving up

// ── Noise event buffer ──────────────────────────────────────────────────────────

NoiseEvent :: struct {
    pos:      [3]f32,
    radius:   f32,
    strength: f32,   // suspicion added to any AI that hears it
}

g_noise_events: [dynamic]NoiseEvent

// emit_noise queues a sound event that AI will hear this frame.
// Use STEALTH_NOISE_LOUD for gunshots, STEALTH_NOISE_MED for impacts/footsteps.
emit_noise :: proc(pos: [3]f32, radius: f32, strength: f32) {
    append(&g_noise_events, NoiseEvent{ pos = pos, radius = radius, strength = strength })
}

// ── System entry ────────────────────────────────────────────────────────────────

stealth_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    #partial switch event {
    case .EarlyUpdate: _stealth_movement_noise(w)
    case .Update:      _stealth_perception(w, dt)
    case .LateUpdate:  clear(&g_noise_events)
    }
}

// ── Movement noise emission ─────────────────────────────────────────────────────

@(private = "file")
_stealth_movement_noise :: proc(w: ^cw.World) {
    for slot in 0..<cw.MAX_PLAYERS {
        pid := w.player_ids[slot]
        if !cw.world_is_valid(w, pid)                { continue }
        if !cw.world_has_component(w, pid, .Velocity) { continue }

        vel := cw.world_get_velocity(w, pid)
        spd := math.sqrt(vel.value[0]*vel.value[0] + vel.value[1]*vel.value[1])
        if spd < 8 { continue }  // stationary players make no noise

        pos      := cw.world_get_transform(w, pid).position
        radius   := spd * 0.6                                    // walk ≈ 75, sprint ≈ 150
        strength := STEALTH_NOISE_MED * (spd / f32(MOVE_SPEED)) // scales with speed
        emit_noise(pos, radius, strength)
    }
}

// ── Per-frame AI perception ─────────────────────────────────────────────────────

@(private = "file")
_stealth_perception :: proc(w: ^cw.World, dt: f32) {
    dark := g_light_ambient <= STEALTH_DARK_THRESH

    ids := cw.world_query(w, cw.query_mask(.AIAgent, .Transform))
    defer delete(ids)

    for id in ids {
        ai := cw.world_get_ai(w, id)
        t  := cw.world_get_transform(w, id)

        // ai_system owns the Attack state — don't interfere
        if ai.state == AI_STATE_ATTACK { continue }

        player_pos, _, has_player := nearest_player_pos(w, t.position)

        // ── Noise check ─────────────────────────────────────────────────────────
        for &evt in g_noise_events {
            dx := evt.pos[0] - t.position[0]
            dy := evt.pos[1] - t.position[1]
            if dx*dx + dy*dy > evt.radius*evt.radius { continue }
            if ai.state < AI_STATE_CHASE {
                ai.suspicion      = min(1.0, ai.suspicion + evt.strength)
                ai.last_known_pos = evt.pos
            }
        }

        // ── Vision cone check ────────────────────────────────────────────────────
        if has_player && ai.state < AI_STATE_CHASE {
            dx := player_pos[0] - t.position[0]
            dy := player_pos[1] - t.position[1]
            d  := math.sqrt(dx*dx + dy*dy)
            if d <= ai.aggro_range && d > 0.5 {
                adiff := math.abs(_stealth_angle_diff(t.rotation, math.atan2(dy, dx)))
                if adiff <= STEALTH_CONE_HALF {
                    rate              := STEALTH_RATE_LIT if !dark else STEALTH_RATE_DARK
                    ai.suspicion       = min(1.0, ai.suspicion + rate * dt)
                    ai.last_known_pos  = player_pos
                }
            }
        }

        // ── Chase: keep last_known_pos fresh; drop to Searching if player escapes ──
        if ai.state == AI_STATE_CHASE {
            if has_player {
                dx := player_pos[0] - t.position[0]
                dy := player_pos[1] - t.position[1]
                d  := math.sqrt(dx*dx + dy*dy)
                if d <= ai.aggro_range * 1.6 {
                    ai.last_known_pos = player_pos
                } else {
                    ai.state        = AI_STATE_SEARCHING
                    ai.search_timer = STEALTH_SEARCH_TIME
                }
            } else {
                ai.state        = AI_STATE_SEARCHING
                ai.search_timer = STEALTH_SEARCH_TIME
            }
        }

        // ── State transitions ───────────────────────────────────────────────────
        switch ai.state {
        case AI_STATE_IDLE:
            if ai.suspicion >= 0.25 { ai.state = AI_STATE_SUSPICIOUS }

        case AI_STATE_SUSPICIOUS:
            if ai.suspicion >= 1.0 {
                // Fully detected — go directly to Chase if player is visible
                if has_player {
                    dx := player_pos[0] - t.position[0]
                    dy := player_pos[1] - t.position[1]
                    d  := math.sqrt(dx*dx + dy*dy)
                    ai.state = AI_STATE_CHASE if d <= ai.aggro_range else AI_STATE_SEARCHING
                } else {
                    ai.state = AI_STATE_SEARCHING
                }
                ai.search_timer = STEALTH_SEARCH_TIME
            } else if ai.suspicion <= 0 {
                ai.state = AI_STATE_IDLE
            }

        case AI_STATE_SEARCHING:
            ai.search_timer -= dt
            // Spot player while searching → immediately chase
            if has_player {
                dx := player_pos[0] - t.position[0]
                dy := player_pos[1] - t.position[1]
                d  := math.sqrt(dx*dx + dy*dy)
                if d <= ai.aggro_range {
                    ai.state     = AI_STATE_CHASE
                    ai.suspicion = 1.0
                }
            }
            // Give up after timer expires and suspicion has mostly decayed
            if ai.search_timer <= 0 && ai.suspicion < 0.5 {
                ai.state     = AI_STATE_IDLE
                ai.suspicion = 0
            }
        }

        // ── Suspicion decay (not while actively chasing) ─────────────────────────
        if ai.state < AI_STATE_CHASE {
            ai.suspicion = max(0, ai.suspicion - STEALTH_DECAY * dt)
        }
    }
}

@(private = "file")
_stealth_angle_diff :: proc(a, b: f32) -> f32 {
    diff := b - a
    for diff >  math.PI { diff -= 2 * math.PI }
    for diff < -math.PI { diff += 2 * math.PI }
    return diff
}

// ── Suspicion HUD ───────────────────────────────────────────────────────────────
//
// draw_stealth_indicators renders "?" / "!" icons and a suspicion bar above
// enemies that are in a non-idle, non-attack state.
// Must be called inside  rl.BeginMode2D(g_camera^).

draw_stealth_indicators :: proc(w: ^cw.World) {
    ids := cw.world_query(w, cw.query_mask(.AIAgent, .Transform))
    defer delete(ids)

    ICON_FS :: f32(15)
    BAR_W   :: f32(22)
    BAR_H   :: f32(4)
    LIFT    :: f32(30)  // iso-space units above entity centre

    for id in ids {
        if is_fog_hidden(w, id) { continue }

        ai := cw.world_get_ai(w, id)
        if ai.state == AI_STATE_IDLE || ai.state == AI_STATE_ATTACK { continue }

        t   := cw.world_get_transform(w, id)
        iso := world_to_iso_xy(t.position[0], t.position[1])

        bx  := iso.x - BAR_W * 0.5
        by  := iso.y - LIFT

        switch ai.state {
        case AI_STATE_SUSPICIOUS:
            // Gold suspicion bar
            rl.DrawRectangleRec({ bx, by, BAR_W, BAR_H },
                rl.Color{ 30, 25, 10, 160 })
            rl.DrawRectangleRec({ bx, by, BAR_W * ai.suspicion, BAR_H },
                rl.Color{ 220, 185, 40, 220 })
            rl.DrawRectangleLinesEx({ bx, by, BAR_W, BAR_H }, 0.8,
                rl.Color{ 120, 100, 30, 140 })
            // "?" icon above bar
            isz := rl.MeasureTextEx(g_font, "?", ICON_FS, 0.5)
            rl.DrawTextEx(g_font, "?",
                { iso.x - isz.x * 0.5, by - ICON_FS - 2 },
                ICON_FS, 0.5,
                rl.Color{ u8(180 + u32(ai.suspicion * 40)), 185, 40, 230 })

        case AI_STATE_SEARCHING:
            isz := rl.MeasureTextEx(g_font, "!", ICON_FS, 0.5)
            rl.DrawTextEx(g_font, "!",
                { iso.x - isz.x * 0.5, by - ICON_FS - 2 },
                ICON_FS, 0.5, rl.Color{ 255, 140, 20, 240 })

        case AI_STATE_CHASE:
            isz := rl.MeasureTextEx(g_font, "!", ICON_FS, 0.5)
            rl.DrawTextEx(g_font, "!",
                { iso.x - isz.x * 0.5, by - ICON_FS - 2 },
                ICON_FS, 0.5, rl.Color{ 255, 50, 30, 255 })
        }
    }
}
