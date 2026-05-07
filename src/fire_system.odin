package main

// =============================================================================
// fire_system.odin — Fire, water, oil, and barrel hazard system
//
// Barrels:
//   ECS entities (Health + Collider) tracked in g_barrel_registry.
//   Fire barrel  → chain explosion + radial fire ring on death.
//   Water barrel → splash + water puddles; instantly extinguishes nearby fire.
//
// Fire patches:
//   Flat world-space hazard zones.  Damage any entity with Health+Collider.
//   Extinguished by water puddles or Water tiles.
//   Spread to adjacent Oil tiles via BFS flood-fill.
//
// Water puddles:
//   Created by water barrel explosions.  Evaporate over time.
//   Extinguish any overlapping fire patch.
//
// Oil overlays (TileOverlay.Oil on Floor tiles):
//   Walkable but flammable.  First fire patch to reach an oil overlay triggers a
//   BFS flood that removes the whole connected oil cluster from g_overlay_map and
//   spawns a long-lived fire patch on each consumed tile.
//
// Rendering:
//   draw_fire_patches()  — call inside BeginMode2D
//   draw_water_puddles() — call inside BeginMode2D
//   draw_barrels()       — call inside BeginMode2D (uses screen-space Raylib calls
//                          after computing iso position via world_to_iso_xy)
// =============================================================================

import cw "clockwork"
import rl  "vendor:raylib"
import     "core:math"

// ── Barrel registry ───────────────────────────────────────────────────────────
//
// Barrels are plain ECS entities (Health + Collider).  The registry maps
// entity ID → BarrelType so barrel_system can identify and react on death
// without adding a new ECS component type.

BarrelType :: enum { Fire, Water }

g_barrel_registry: map[int]BarrelType

// ── Fire patches ──────────────────────────────────────────────────────────────

FIRE_PATCH_CAP      :: 64
FIRE_DMG_PER_SEC    :: f32(20)      // raw HP/s dealt to entities inside radius
FIRE_SPREAD_CD      :: f32(1.6)     // seconds between spread-to-oil attempts
FIRE_PATCH_LIFE     :: f32(6.0)     // normal fire lifetime
FIRE_OIL_LIFE       :: f32(9.0)     // oil-sourced fire burns longer

@(private = "file")
FirePatch :: struct {
    pos:      [2]f32,
    radius:   f32,
    lifetime: f32,
    sprd_cd:  f32,
    from_oil: bool,
}

@(private = "file")
g_fire:   [FIRE_PATCH_CAP]FirePatch

@(private = "file")
g_fire_n: int

// ── Water puddles ─────────────────────────────────────────────────────────────

WATER_PUDDLE_CAP  :: 32
WATER_PUDDLE_LIFE :: f32(5.0)
WATER_PUDDLE_RAD  :: f32(TILE_SIZE) * 0.85

@(private = "file")
WaterPuddle :: struct {
    pos:      [2]f32,
    radius:   f32,
    lifetime: f32,
}

@(private = "file")
g_water:   [WATER_PUDDLE_CAP]WaterPuddle

@(private = "file")
g_water_n: int

// ── Fire-tile respawn timer ───────────────────────────────────────────────────
//
// Every FIRE_TILE_RESPAWN_CD seconds, fire_patch_system scans all TileOverlay.Fire
// tiles and spawns a fresh fire patch on any that are currently uncovered.
// This makes fire-pit tiles permanently burning: water can briefly extinguish
// them, but they reignite within half a second.

FIRE_TILE_RESPAWN_CD :: f32(0.5)

@(private = "file")
g_fire_tile_cd: f32

// ── Init / reset / destroy ────────────────────────────────────────────────────

fire_system_init :: proc() {
    g_barrel_registry = make(map[int]BarrelType)
    g_fire_n       = 0
    g_water_n      = 0
    g_fire_tile_cd = 0
}

// fire_system_reset clears all runtime state.  Call before every level load.
fire_system_reset :: proc() {
    clear(&g_barrel_registry)
    clear(&g_overlay_map)   // runtime oil/fire changes must not bleed into next level
    g_fire_n       = 0
    g_water_n      = 0
    g_fire_tile_cd = 0
}

// fire_patches_reset clears only the live fire and water patch arrays.
// Unlike fire_system_reset it does NOT touch g_barrel_registry or g_overlay_map,
// so active barrel entities keep their registry entries and the oil/fire overlay
// map is left for the subsequent level_load call to repopulate correctly.
// Use this on editor exit instead of the full reset.
fire_patches_reset :: proc() {
    g_fire_n       = 0
    g_water_n      = 0
    g_fire_tile_cd = FIRE_TILE_RESPAWN_CD   // don't burst-spawn patches on the very next tick
}

fire_system_destroy :: proc() {
    delete(g_barrel_registry)
    g_fire_n  = 0
    g_water_n = 0
}

// ── Public spawn helpers ──────────────────────────────────────────────────────

// spawn_barrel creates a barrel ECS entity and registers it by type.
// Returns the entity ID.
spawn_barrel :: proc(w: ^cw.World, wx, wy: f32, btype: BarrelType) -> int {
    id := cw.world_create_entity(w)
    cw.world_set_transform(w, id, cw.TransformComp{ position = {wx, wy, 0} })
    cw.world_set_health(w, id, cw.HealthComp{ current = 50, max = 50 })
    // faction = 2 (neutral) — hit by both player AND enemy projectiles
    cw.world_set_collider(w, id, cw.ColliderComp{ radius = 12, faction = 2 })
    g_barrel_registry[id] = btype
    return id
}

// ── Internal push helpers ─────────────────────────────────────────────────────

@(private = "file")
_push_fire :: proc(wx, wy, radius, lifetime: f32, from_oil: bool) {
    if g_fire_n >= FIRE_PATCH_CAP { return }
    g_fire[g_fire_n] = FirePatch{
        pos      = {wx, wy},
        radius   = radius,
        lifetime = lifetime,
        sprd_cd  = FIRE_SPREAD_CD,
        from_oil = from_oil,
    }
    g_fire_n += 1
}

@(private = "file")
_push_water :: proc(wx, wy, radius: f32) {
    if g_water_n >= WATER_PUDDLE_CAP { return }
    g_water[g_water_n] = WaterPuddle{
        pos      = {wx, wy},
        radius   = radius,
        lifetime = WATER_PUDDLE_LIFE,
    }
    g_water_n += 1
}

// ── Barrel explosion callbacks ────────────────────────────────────────────────

@(private = "file")
_explode_fire_barrel :: proc(w: ^cw.World, wx, wy: f32) {
    EXP_R :: f32(72)
    push_explosion(wx, wy, EXP_R, 255, 110, 20)

    for id in 0..<len(w.entities) {
        
        if !cw.world_is_valid(w, id)               { continue }
        
        if !cw.world_has_component(w, id, .Health) { continue }
        
       

        tr := cw.world_get_transform(w, id)
        dx := tr.position[0] - wx
        dy := tr.position[1] - wy
        d  := math.sqrt(dx*dx + dy*dy)
        if d < EXP_R {
            cw.world_push_damage(w, id, 60 * (1 - d/EXP_R), 0)

             if !cw.world_has_component(w, id, .Flammable) || cw.world_get_flammable(w, id).isImmune {
                continue
            }

             has_oiled := cw.world_has_component(w, id, .StatusEffect) &&
                cw.status_effect_is_active(cw.world_get_status_effects(w, id), .Oiled)
            burn_str := f32(0.10) * (2.0 if has_oiled else 1.0)
            if has_oiled {
                cw.world_get_status_effects(w, id).effects[int(cw.StatusEffectType.Oiled)].duration = 0
            }

            cw.status_effect_apply(w, id, cw.StatusEffect{
                type           = .Burn,
                duration       = 3.5,
                strength       = burn_str,
                stack_behavior = .Refresh,
                source_id      = 0,
            })
        }
    }

    // Ring of six fire patches around the blast
    for i in 0..<6 {
        a := f32(i) * (math.PI * 2 / 6)
        d := EXP_R * 0.52
        _push_fire(wx + math.cos(a)*d, wy + math.sin(a)*d,
                   f32(TILE_SIZE) * 0.52, FIRE_PATCH_LIFE, false)
    }
    _push_fire(wx, wy, f32(TILE_SIZE) * 0.42, FIRE_PATCH_LIFE, false)   // centre
}

@(private = "file")
_explode_water_barrel :: proc(w: ^cw.World, wx, wy: f32) {
    SPLASH_R :: f32(85)
    push_explosion(wx, wy, SPLASH_R * 0.55, 70, 150, 220)

    // Immediately extinguish nearby fire
    _extinguish_radius(wx, wy, SPLASH_R)

    // Scatter five puddles in a ring plus one in the centre
    for i in 0..<5 {
        a := f32(i) * (math.PI * 2 / 5)
        d := SPLASH_R * 0.44
        _push_water(wx + math.cos(a)*d, wy + math.sin(a)*d, WATER_PUDDLE_RAD)
    }
    _push_water(wx, wy, WATER_PUDDLE_RAD * 1.25)

    // Soak nearby entities: apply Wet (which immediately strips Burn and Oiled)
    for eid in 0..<len(w.entities) {
        if !cw.world_is_valid(w, eid)               { continue }
        if !cw.world_has_component(w, eid, .Health) { continue }
        tr := cw.world_get_transform(w, eid)
        dx := tr.position[0] - wx
        dy := tr.position[1] - wy
        if math.sqrt(dx*dx + dy*dy) < SPLASH_R {
            cw.status_effect_apply(w, eid, cw.StatusEffect{
                type           = .Wet,
                duration       = 5.0,
                strength       = 1.0,
                stack_behavior = .Refresh,
            })
        }
    }
}

@(private = "file")
_extinguish_radius :: proc(cx, cy, radius: f32) {
    i := 0
    for i < g_fire_n {
        fp := g_fire[i]
        dx := fp.pos[0] - cx
        dy := fp.pos[1] - cy
        if math.sqrt(dx*dx + dy*dy) < radius + fp.radius {
            push_explosion(fp.pos[0], fp.pos[1], fp.radius * 0.55, 90, 170, 230)
            g_fire[i] = g_fire[g_fire_n - 1]
            g_fire_n -= 1
        } else {
            i += 1
        }
    }
}

// ── Oil ignition — BFS flood-fill ─────────────────────────────────────────────
//
// Converts the entire connected oil cluster starting at (start_tx, start_ty)
// to Floor tiles and spawns a long-lived fire patch at each consumed tile.
// Iterative BFS avoids stack overflow on large clusters.

@(private = "file")
_ignite_oil :: proc(start_tx, start_ty: int) {
    if overlay_at(start_tx, start_ty) != .Oil { return }

    OIL_Q_CAP :: 128
    queue:       [OIL_Q_CAP][2]int
    head, tail  := 0, 0

    delete_key(&g_overlay_map, [2]int{start_tx, start_ty})   // consume / mark visited
    queue[tail] = {start_tx, start_ty}
    tail += 1

    offsets := [4][2]int{ {1,0}, {-1,0}, {0,1}, {0,-1} }

    for head < tail {
        tx := queue[head][0]
        ty := queue[head][1]
        head += 1

        // Spawn fire at the centre of this tile
        wx := f32(tx)*f32(TILE_SIZE) + f32(TILE_SIZE)*0.5
        wy := f32(ty)*f32(TILE_SIZE) + f32(TILE_SIZE)*0.5
        _push_fire(wx, wy, f32(TILE_SIZE)*0.72, FIRE_OIL_LIFE, true)

        // Flood to adjacent oil tiles
        for off in offsets {
            nx, ny := tx + off[0], ty + off[1]
            if overlay_at(nx, ny) == .Oil && tail < OIL_Q_CAP {
                delete_key(&g_overlay_map, [2]int{nx, ny})   // consume before enqueuing
                queue[tail] = {nx, ny}
                tail += 1
            }
        }
    }
}

// ── ECS system procs (registered in main.odin) ────────────────────────────────

// barrel_system detects barrel entities whose health hits zero, triggers the
// appropriate explosion, then destroys the entity.
barrel_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .LateUpdate { return }
    for id in 0..<len(w.entities) {
        if !cw.world_is_valid(w, id)              { continue }
        btype, is_barrel := g_barrel_registry[id]
        if !is_barrel                             { continue }
        if !cw.world_has_component(w, id, .Health){ continue }

        h  := cw.world_get_health(w, id)
        tr := cw.world_get_transform(w, id)
        if h.current > 0                          { continue }

        delete_key(&g_barrel_registry, id)
        wx, wy := tr.position[0], tr.position[1]
        switch btype {
        case .Fire:  _explode_fire_barrel(w, wx, wy)
        case .Water: _explode_water_barrel(w, wx, wy)
        }
        cw.world_destroy_entity(w, id)
    }
}

fire_patch_system :: proc(w: ^cw.World, event: cw.SystemEvent, dt: f32) {
    if event != .Update { return }

    {
        i := 0
        for i < g_water_n {
            g_water[i].lifetime -= dt
            if g_water[i].lifetime <= 0 {
                g_water[i] = g_water[g_water_n - 1]
                g_water_n -= 1
            } else { i += 1 }
        }
    }

    g_fire_tile_cd -= dt
    if g_fire_tile_cd <= 0 {
        g_fire_tile_cd = FIRE_TILE_RESPAWN_CD
        for k, v in g_overlay_map {
            if v != .Fire { continue }
            wx := f32(k[0])*f32(TILE_SIZE) + f32(TILE_SIZE)*0.5
            wy := f32(k[1])*f32(TILE_SIZE) + f32(TILE_SIZE)*0.5
            covered := false
            for fi in 0..<g_fire_n {
                fp := g_fire[fi]
                dx := fp.pos[0] - wx
                dy := fp.pos[1] - wy
                if math.sqrt(dx*dx + dy*dy) < fp.radius { covered = true; break }
            }
            if !covered {
                _push_fire(wx, wy, f32(TILE_SIZE)*0.62, 999.0, false)
            }
        }
    }

    for eid in 0..<len(w.entities) {
        if !cw.world_is_valid(w, eid)                 { continue }
        if !cw.world_has_component(w, eid, .Health)   { continue }
        if !cw.world_has_component(w, eid, .Collider) { continue }
        _, is_barrel := g_barrel_registry[eid]
        if is_barrel { continue }

        tr := cw.world_get_transform(w, eid)
        cl := cw.world_get_collider(w, eid)

        // Water puddle contact → WET (status_effect_apply will Refresh duration)
        for wi in 0..<g_water_n {
            wp := g_water[wi]
            dx := tr.position[0] - wp.pos[0]
            dy := tr.position[1] - wp.pos[1]
            if math.sqrt(dx*dx + dy*dy) < wp.radius + cl.radius {
                cw.status_effect_apply(w, eid, cw.StatusEffect{
                    type           = .Wet,
                    duration       = 4.0,
                    strength       = 1.0,
                    stack_behavior = .Refresh,
                })
                break
            }
        }

        // Oil tile contact → OILED (refreshed every tick while standing on oil)
        etx, ety := world_to_tile(tr.position[0], tr.position[1])
        if overlay_at(etx, ety) == .Oil {
            cw.status_effect_apply(w, eid, cw.StatusEffect{
                type           = .Oiled,
                duration       = 3.0,
                strength       = 1.0,
                stack_behavior = .Refresh,
            })
        }
    }

    i := 0
    for i < g_fire_n {
        fp := &g_fire[i]
        fp.lifetime -= dt

        extinguished := false

        for wi in 0..<g_water_n {
            wp := g_water[wi]
            dx := fp.pos[0] - wp.pos[0]
            dy := fp.pos[1] - wp.pos[1]
            if math.sqrt(dx*dx + dy*dy) < wp.radius + fp.radius * 0.5 {
                extinguished = true
                break
            }
        }
        if !extinguished {
            tx, ty := world_to_tile(fp.pos[0], fp.pos[1])
            if tile_at(tx, ty) == .Water { extinguished = true }
        }

        if fp.lifetime <= 0 || extinguished {
            if extinguished {
                push_explosion(fp.pos[0], fp.pos[1], fp.radius * 0.5, 110, 165, 215)
            }
            g_fire[i] = g_fire[g_fire_n - 1]
            g_fire_n -= 1
            continue
        }

        // ── Apply damage + BURN to entities in range ────────────────────
        for eid in 0..<len(w.entities) {
            if !cw.world_is_valid(w, eid)                { continue }
            if !cw.world_has_component(w, eid, .Health)  { continue }
            if !cw.world_has_component(w, eid, .Collider){ continue }
            if (!cw.world_has_component(w, eid, .Flammable) || cw.world_get_flammable(w, eid).isImmune) {
                continue
            }
            _, is_barrel := g_barrel_registry[eid]
            if is_barrel { continue }   // barrels die from projectiles, not fire
            tr := cw.world_get_transform(w, eid)
            cl := cw.world_get_collider(w, eid)
            dx := tr.position[0] - fp.pos[0]
            dy := tr.position[1] - fp.pos[1]
            if math.sqrt(dx*dx + dy*dy) < fp.radius + cl.radius {
                cw.world_push_damage(w, eid, FIRE_DMG_PER_SEC * dt, 0)

                has_oiled := cw.world_has_component(w, eid, .StatusEffect) &&
                    cw.status_effect_is_active(cw.world_get_status_effects(w, eid), .Oiled)
                burn_str := f32(0.06) * (2.0 if has_oiled else 1.0)
                if has_oiled {
                    cw.world_get_status_effects(w, eid).effects[int(cw.StatusEffectType.Oiled)].duration = 0
                }
                cw.status_effect_apply(w, eid, cw.StatusEffect{
                    type           = .Burn,
                    duration       = 2.5,
                    strength       = burn_str,
                    stack_behavior = .Refresh,
                    source_id      = 0,
                })
            }
        }

        fp.sprd_cd -= dt
        if fp.sprd_cd <= 0 {
            fp.sprd_cd = FIRE_SPREAD_CD
            tx, ty := world_to_tile(fp.pos[0], fp.pos[1])
            for off in ([4][2]int{ {1,0},{-1,0},{0,1},{0,-1} }) {
                if overlay_at(tx+off[0], ty+off[1]) == .Oil {
                    _ignite_oil(tx+off[0], ty+off[1])
                }
            }
        }

        i += 1
    }
}

// ── Drawing ───────────────────────────────────────────────────────────────────
//
// All three procs must be called inside BeginMode2D.

draw_fire_patches :: proc() {
    tt := f32(rl.GetTime())
    for i in 0..<g_fire_n {
        fp    := g_fire[i]
        max_l := FIRE_OIL_LIFE if fp.from_oil else FIRE_PATCH_LIFE
        life  := fp.lifetime / max_l
        ab    := u8(clamp(200 * life, 40, 200))
        pulse := f32(math.sin(f64(tt)*4.0 + f64(fp.pos[0])*0.1 + f64(fp.pos[1])*0.07)*0.5 + 0.5)
        p     := rl.Vector2{fp.pos[0], fp.pos[1]}

        // Outer heat glow
        draw_world_circle(p, fp.radius * 1.22,
            rl.Color{175, 45, 8, u8(f32(ab) * 0.40)})
        // Core flame body
        draw_world_circle(p, fp.radius,
            rl.Color{255, u8(85 + 75*pulse), 12, u8(f32(ab) * (0.68 + 0.32*pulse))})
        // Bright inner core
        draw_world_circle(p, fp.radius * 0.38,
            rl.Color{255, 222, 80, u8(f32(ab) * 0.72 * pulse)})

        // Flickering radial tongues
        for fi in 0..<5 {
            a := f32(fi)*(math.PI*2/5) + math.sin(tt*3 + f32(fi))*0.42
            d := fp.radius * (0.46 + math.sin(tt*5 + f32(fi)*1.35) * 0.20)
            p0 := rl.Vector2{fp.pos[0], fp.pos[1]}
            p1 := rl.Vector2{fp.pos[0] + math.cos(a)*d, fp.pos[1] + math.sin(a)*d}
            draw_world_line(p0, p1, 2.0, rl.Color{255, 145, 25, u8(f32(ab) * 0.52 * pulse)})
        }
    }
}

draw_water_puddles :: proc() {
    tt := f32(rl.GetTime())
    for i in 0..<g_water_n {
        wp    := g_water[i]
        t     := wp.lifetime / WATER_PUDDLE_LIFE
        alpha := u8(clamp(150 * t * t, 15, 150))
        wave  := f32(math.sin(f64(tt)*2.5 + f64(wp.pos[0])*0.08 + f64(wp.pos[1])*0.06)*0.5 + 0.5)
        p     := rl.Vector2{wp.pos[0], wp.pos[1]}

        draw_world_circle(p, wp.radius,
            rl.Color{48, 108, 182, alpha})
        draw_world_circle(p, wp.radius * 0.55,
            rl.Color{128, 192, 238, u8(f32(alpha) * 0.58 * wave)})
        draw_world_circle_lines(p, wp.radius * (0.36 + wave*0.30),
            rl.Color{172, 218, 255, u8(f32(alpha) * 0.42)})
    }
}

// draw_status_effects renders world-space halos for BURN, WET, and OILED on
// every entity that carries those active status effects.
// Must be called inside BeginMode2D.
draw_status_effects :: proc(w: ^cw.World) {
    tt := f32(rl.GetTime())
    for id in 0..<len(w.entities) {
        if !cw.world_is_valid(w, id)                     { continue }
        if !cw.world_has_component(w, id, .StatusEffect) { continue }
        if !cw.world_has_component(w, id, .Transform)    { continue }

        sec := cw.world_get_status_effects(w, id)
        tr  := cw.world_get_transform(w, id)
        p   := rl.Vector2{ tr.position[0], tr.position[1] }
        r   := f32(PLAYER_RADIUS)
        if cw.world_has_component(w, id, .Collider) {
            r = cw.world_get_collider(w, id).radius
        }

        pulse := f32(math.sin(f64(tt)*6.0)*0.5 + 0.5)

        // ── BURN ─────────────────────────────────────────────────────────
        if cw.status_effect_is_active(sec, .Burn) {
            ef  := cw.status_effect_get(sec, .Burn)
            frac := clamp(ef.duration / 2.5, 0, 1)
            ab  := u8(clamp(170 * frac, 30, 170))
            // outer heat ring
            draw_world_circle_lines(p, r + 2 + 2*pulse,
                rl.Color{ 255, u8(60 + 80*pulse), 15, u8(f32(ab)*(0.55 + 0.45*pulse)) })
            // inner ember core
            draw_world_circle(p, r * 0.32 * pulse,
                rl.Color{ 255, 150, 25, u8(f32(ab) * 0.42 * pulse) })
        }

        // ── WET ──────────────────────────────────────────────────────────
        if cw.status_effect_is_active(sec, .Wet) {
            ef   := cw.status_effect_get(sec, .Wet)
            frac := clamp(ef.duration / 4.0, 0, 1)
            ab   := u8(clamp(140 * frac, 25, 140))
            wave := f32(math.sin(f64(tt)*3.5 + f64(tr.position[0])*0.05)*0.5 + 0.5)
            // ripple ring
            draw_world_circle_lines(p, r + 3 + 2*wave,
                rl.Color{ 80, 180, 255, u8(f32(ab)*(0.45 + 0.55*wave)) })
            // translucent fill
            draw_world_circle(p, r * 1.08,
                rl.Color{ 40, 115, 200, u8(f32(ab) * 0.18) })
        }

        // ── OILED ─────────────────────────────────────────────────────────
        if cw.status_effect_is_active(sec, .Oiled) {
            ef    := cw.status_effect_get(sec, .Oiled)
            frac  := clamp(ef.duration / 3.0, 0, 1)
            ab    := u8(clamp(155 * frac, 25, 155))
            sheen := f32(math.sin(f64(tt)*2.2 + f64(tr.position[0])*0.07)*0.5 + 0.5)
            // iridescent ring (shifts between green, blue, purple)
            draw_world_circle_lines(p, r + 2,
                rl.Color{
                    u8(25 + u8(sheen * 45)),
                    u8(18 + u8(sheen * 28)),
                    u8(45 + u8(sheen * 65)),
                    u8(f32(ab)*(0.45 + 0.55*sheen)),
                })
            draw_world_circle(p, r * 1.04,
                rl.Color{ 14, 8, 34, u8(f32(ab) * 0.15) })
        }
    }
}

// draw_barrels renders all registered barrel entities using screen-space Raylib
// calls (no iso-projection needed for DrawEllipse/DrawRectangle).
draw_barrels :: proc() {
    w := &g_sim.world
    for id, btype in g_barrel_registry {
        if !cw.world_is_valid(w, id)                      { continue }
        if !cw.world_has_component(w, id, .Transform)     { continue }

        tr  := cw.world_get_transform(w, id)
        iso := world_to_iso_xy(tr.position[0], tr.position[1])
        ix  := i32(iso.x)
        iy  := i32(iso.y)

        // ── Shadow ──────────────────────────────────────────────────────
        rl.DrawEllipse(ix, iy + 5, 15, 6, rl.Color{0, 0, 0, 65})

        // ── Barrel body ─────────────────────────────────────────────────
        // Bottom cap
        rl.DrawEllipse(ix, iy + 7, 13, 5, rl.Color{55, 38, 24, 245})
        // Cylindrical body
        rl.DrawRectangle(ix - 13, iy - 12, 26, 19, rl.Color{70, 48, 28, 245})
        // Wood-grain bands
        rl.DrawRectangle(ix - 13, iy - 5,  26, 3,  rl.Color{95, 70, 44, 245})
        rl.DrawRectangle(ix - 13, iy + 3,  26, 3,  rl.Color{95, 70, 44, 245})
        // Top cap — coloured by barrel type
        top_col: rl.Color
        switch btype {
        case .Fire:  top_col = rl.Color{210, 72, 16, 245}
        case .Water: top_col = rl.Color{38,  112, 195, 245}
        }
        rl.DrawEllipse(ix, iy - 12, 13, 5, top_col)
        rl.DrawEllipseLines(ix, iy - 12, 13, 5, rl.Color{0, 0, 0, 160})

        // Small type icon: flame dot or water dot
        dot_col: rl.Color
        switch btype {
        case .Fire:  dot_col = rl.Color{255, 200, 60, 230}
        case .Water: dot_col = rl.Color{180, 230, 255, 230}
        }
        rl.DrawCircle(ix, iy - 12, 3, dot_col)

        // ── HP bar ──────────────────────────────────────────────────────
        if cw.world_has_component(w, id, .Health) {
            h      := cw.world_get_health(w, id)
            pct    := h.current / h.max
            bar_w  := i32(30)
            bar_x  := ix - bar_w / 2
            bar_y  := iy - 28
            rl.DrawRectangle(bar_x, bar_y, bar_w, 4, rl.Color{15, 15, 15, 180})
            hp_col := rl.Color{220, 55, 18, 220} if pct > 0.5 else rl.Color{200, 175, 18, 220}
            rl.DrawRectangle(bar_x, bar_y, i32(f32(bar_w) * pct), 4, hp_col)
        }
    }
}
