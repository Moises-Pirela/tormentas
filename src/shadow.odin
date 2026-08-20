package main

import "core:math"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

SHADOW_MAX_LEN   :: f32(3.2)
SHADOW_STRIPS    :: 8
SHADOW_FOOT_BIAS :: f32(1.7)
SHADOW_MIN_ELEV  :: f32(5)
SHADOW_MAX_ELEV  :: f32(89)

draw_projected_sprite_shadow :: proc(
    tex: rl.Texture2D,
    src: rl.Rectangle,
    feet: rl.Vector2,
    world_size: f32,
    aspect: f32,
    anchor: [2]f32,
    ground: f32,
    flip_x: bool,
    dir: [2]f32,
    elevation_deg: f32,
    near_a: u8,
    far_a: u8,
    tint: rl.Color,
) {
    if tex.id == 0 || src.width == 0 || src.height == 0 { return }
    if world_size <= 0 || aspect <= 0 { return }

    quad_w := world_size
    quad_h := world_size * aspect

    left  := feet.x - quad_w * anchor[0]
    right := left + quad_w

    gy    := feet.y + quad_h * (ground - anchor[1])
    above := quad_h * ground

    elev := math.to_radians(clamp(elevation_deg, SHADOW_MIN_ELEV, SHADOW_MAX_ELEV))
    sin_e := math.sin(elev)
    if sin_e <= 0.0001 { return }

    k := math.cos(elev) / sin_e
    if above > 0 { k = min(k, (quad_w * SHADOW_MAX_LEN) / above) }

    iso_d := world_to_iso_xy(dir[0], dir[1])

    tw := f32(tex.width)
    th := f32(tex.height)
    if tw <= 0 || th <= 0 { return }

    u0 := src.x / tw
    u1 := (src.x + src.width) / tw
    v0 := src.y / th
    v1 := (src.y + src.height) / th
    if flip_x { u0, u1 = u1, u0 }

    flip_winding := iso_d.y < 0

    rlgl.SetTexture(tex.id)
    rlgl.Begin(rlgl.QUADS)

    for i in 0 ..< SHADOW_STRIPS {
        fa := f32(i) / f32(SHADOW_STRIPS)
        fb := f32(i + 1) / f32(SHADOW_STRIPS)

        da := _shadow_offset(fa, ground, quad_h, k, iso_d)
        db := _shadow_offset(fb, ground, quad_h, k, iso_d)

        ta := v0 + (v1 - v0) * fa
        tb := v0 + (v1 - v0) * fb

        aa := _shadow_alpha(fa, near_a, far_a)
        ab := _shadow_alpha(fb, near_a, far_a)

        top_l := [2]f32{ left  + da[0], gy + da[1] }
        top_r := [2]f32{ right + da[0], gy + da[1] }
        bot_l := [2]f32{ left  + db[0], gy + db[1] }
        bot_r := [2]f32{ right + db[0], gy + db[1] }

        if flip_winding {
            _shadow_vert(top_l, u0, ta, tint, aa)
            _shadow_vert(bot_l, u0, tb, tint, ab)
            _shadow_vert(bot_r, u1, tb, tint, ab)
            _shadow_vert(top_r, u1, ta, tint, aa)
        } else {
            _shadow_vert(bot_l, u0, tb, tint, ab)
            _shadow_vert(top_l, u0, ta, tint, aa)
            _shadow_vert(top_r, u1, ta, tint, aa)
            _shadow_vert(bot_r, u1, tb, tint, ab)
        }
    }

    rlgl.End()
    rlgl.SetTexture(0)
}

@(private = "file")
_shadow_offset :: proc(f: f32, ground, quad_h, k: f32, iso_d: [2]f32) -> [2]f32 {
    t := clamp((ground - f) / max(ground, 0.0001), 0, 1)
    h := math.pow(t, SHADOW_FOOT_BIAS) * ground * quad_h * k
    return { iso_d.x * h, iso_d.y * h }
}

@(private = "file")
_shadow_alpha :: proc(f: f32, near_a, far_a: u8) -> u8 {
    return u8(clamp(f32(far_a) + (f32(near_a) - f32(far_a)) * f, 0, 255))
}

@(private = "file")
_shadow_vert :: proc(p: [2]f32, u, v: f32, tint: rl.Color, a: u8) {
    rlgl.Color4ub(tint.r, tint.g, tint.b, a)
    rlgl.TexCoord2f(u, v)
    rlgl.Vertex2f(p[0], p[1])
}
