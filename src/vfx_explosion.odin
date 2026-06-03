package main

import rl "vendor:raylib"
import    "core:math"


MAX_EXPLOSIONS     :: 16
VFX_EXPLOSION_LIFE :: f32(0.55)

@(private="file")
ExplosionVfx :: struct {
    pos:     rl.Vector2,
    radius:  f32,
    timer:   f32,
    r, g, b: u8,
}

@(private="file")
g_explosions: [MAX_EXPLOSIONS]ExplosionVfx

push_explosion :: proc(wx, wy, radius: f32, r, g, b: u8) {
    for &e in g_explosions {
        if e.timer > 0 { continue }
        e = ExplosionVfx{ pos = {wx, wy}, radius = radius, timer = VFX_EXPLOSION_LIFE, r = r, g = g, b = b }
        return
    }

    g_explosions[0] = ExplosionVfx{ pos = {wx, wy}, radius = radius, timer = VFX_EXPLOSION_LIFE, r = r, g = g, b = b }
}

tick_explosions :: proc(dt: f32) {
    for &e in g_explosions {
        if e.timer > 0 { e.timer = max(0, e.timer - dt) }
    }
}


draw_explosions :: proc() {
    for &e in g_explosions {
        if e.timer <= 0 { continue }

        t := 1.0 - e.timer / VFX_EXPLOSION_LIFE
        p := e.pos
        r := e.radius


        if t < 0.35 {
            ft      := t / 0.35
            inv     := 1.0 - ft
            flash_a := u8(clamp(220.0 * inv * inv, 0, 255))
            draw_world_circle(p, r * 0.32 * ft,       rl.Color{255, 230, 140, flash_a})
            draw_world_circle(p, r * 0.18 * ft,       rl.Color{255, 255, 210, u8(clamp(f32(flash_a) * 1.15, 0, 255))})
        }


        rr    := r * math.sqrt(t)
        inv_t := 1.0 - t
        ring_a := u8(clamp(210.0 * inv_t * inv_t, 0, 255))
        draw_world_circle_lines(p, rr,           rl.Color{e.r, e.g, e.b, ring_a})
        if rr > 6 {
            draw_world_circle_lines(p, rr - 5,   rl.Color{e.r, e.g, e.b, ring_a / 3})
        }


        if t < 0.65 {
            it      := t / 0.65
            inner_r := r * 0.52 * math.sqrt(it)
            inner_a := u8(clamp(160.0 * (1.0 - it), 0, 255))
            draw_world_circle_lines(p, inner_r, rl.Color{255, 200, 80, inner_a})
        }


        NSPARKS :: 8
        for i in 0..<NSPARKS {
            angle  := f32(i) * (math.PI * 2.0 / NSPARKS)
            ca     := math.cos(angle)
            sa     := math.sin(angle)
            dist   := r * 0.42 * t
            half   := r * 0.11
            p0 := rl.Vector2{ p[0] + ca*(dist - half), p[1] + sa*(dist - half) }
            p1 := rl.Vector2{ p[0] + ca*(dist + half), p[1] + sa*(dist + half) }
            spark_a := u8(clamp(200.0 * (1.0 - t * 1.7), 0, 255))
            draw_world_line(p0, p1, 2.5, rl.Color{255, 200, 80, spark_a})
        }


        scorch_a := u8(clamp(80.0 * math.sqrt(t) * (1.0 - t * 0.8), 0, 255))
        draw_world_circle(p, r * 0.38, rl.Color{20, 10, 5, scorch_a})
    }
}
