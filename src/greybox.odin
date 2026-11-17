package main

import gfx "gfx"

GREYBOX_Z :: f32(0.75)

@(private = "file")
gb_p :: proc(wx, wy, h: f32) -> [2]f32 {
    iso := cam_world_to_view_xy(wx, wy)
    return { iso.x, iso.y - h * GREYBOX_Z }
}

@(private = "file")
gb_quad :: proc(a, b, c, d: [2]f32, col: gfx.Color) {
    gfx.quad_color(col)
    gfx.quad_vertex(a)
    gfx.quad_vertex(b)
    gfx.quad_vertex(c)
    gfx.quad_vertex(d)
}

@(private = "file")
gb_shade :: proc(r, g, b: u8, f: f32, a: u8) -> gfx.Color {
    return gfx.Color{
        u8(clamp(f32(r) * f, 0, 255)),
        u8(clamp(f32(g) * f, 0, 255)),
        u8(clamp(f32(b) * f, 0, 255)),
        a,
    }
}

draw_greybox_volume :: proc(w: ^World, id: int) {
    if !world_has_component(w, id, .Transform) { return }

    t  := comp_get(w, id, .Transform, TransformComp)
    gb := comp_get(w, id, .Greybox, GreyboxComp)

    gfx.quads_begin()
    {
        hx := max(gb.size[0], 1) * 0.5
        hy := max(gb.size[1], 1) * 0.5
        hz := max(gb.size[2], 0)

        cx := t.position[0]
        cy := t.position[1]

        n := gb_p(cx - hx, cy - hy, 0)
        e := gb_p(cx + hx, cy - hy, 0)
        s := gb_p(cx + hx, cy + hy, 0)
        v := gb_p(cx - hx, cy + hy, 0)

        top_n := gb_p(cx - hx, cy - hy, hz)
        top_e := gb_p(cx + hx, cy - hy, hz)
        top_s := gb_p(cx + hx, cy + hy, hz)
        top_v := gb_p(cx - hx, cy + hy, hz)

        a := u8(215)

        switch gb.shape {
        case .Box, .Cylinder, .Platform:
            h := hz
            if gb.shape == .Platform { h = min(hz, f32(TILE_SIZE) * 0.25) }
            if gb.shape != .Box {
                top_n = gb_p(cx - hx, cy - hy, h)
                top_e = gb_p(cx + hx, cy - hy, h)
                top_s = gb_p(cx + hx, cy + hy, h)
                top_v = gb_p(cx - hx, cy + hy, h)
            }
            gb_quad(v, s, top_s, top_v, gb_shade(gb.r, gb.g, gb.b, 0.55, a))
            gb_quad(s, e, top_e, top_s, gb_shade(gb.r, gb.g, gb.b, 0.72, a))
            gb_quad(top_n, top_e, top_s, top_v, gb_shade(gb.r, gb.g, gb.b, 1.0, a))

        case .Ramp:

            gb_quad(v, s, top_s, v, gb_shade(gb.r, gb.g, gb.b, 0.55, a))
            gb_quad(s, e, top_e, top_s, gb_shade(gb.r, gb.g, gb.b, 0.72, a))
            gb_quad(n, e, top_e, top_s, gb_shade(gb.r, gb.g, gb.b, 0.92, a))
            gb_quad(n, top_s, v, v, gb_shade(gb.r, gb.g, gb.b, 0.92, a))

        case .Wedge:

            gb_quad(v, s, top_s, top_v, gb_shade(gb.r, gb.g, gb.b, 0.55, a))
            gb_quad(top_v, top_s, s, v, gb_shade(gb.r, gb.g, gb.b, 0.92, a))
            gb_quad(n, top_v, top_s, n, gb_shade(gb.r, gb.g, gb.b, 1.0, a))
        }
    }
    gfx.quads_end()

    fhx := max(gb.size[0], 1) * 0.5
    fhy := max(gb.size[1], 1) * 0.5
    fn := gb_p(t.position[0] - fhx, t.position[1] - fhy, 0)
    fe := gb_p(t.position[0] + fhx, t.position[1] - fhy, 0)
    fs := gb_p(t.position[0] + fhx, t.position[1] + fhy, 0)
    fv := gb_p(t.position[0] - fhx, t.position[1] + fhy, 0)

    oc := gfx.Color{18, 20, 24, 170}
    gfx.draw_line_ex({fn[0], fn[1]}, {fe[0], fe[1]}, 1.5, oc)
    gfx.draw_line_ex({fe[0], fe[1]}, {fs[0], fs[1]}, 1.5, oc)
    gfx.draw_line_ex({fs[0], fs[1]}, {fv[0], fv[1]}, 1.5, oc)
    gfx.draw_line_ex({fv[0], fv[1]}, {fn[0], fn[1]}, 1.5, oc)
}
