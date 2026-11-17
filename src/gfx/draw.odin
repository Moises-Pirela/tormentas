package gfx

// Drawing API (docs/BACKEND_SWAP_PLAN.md §3). Game code calls these; the backend decides how they
// are drawn. Source rectangles are always positive and top-left based: orientation is the
// backend's problem (types.odin, `Texture.flipped`).

import "core:c"

// ---- frame and targets -------------------------------------------------------------------------

frame_begin :: proc() { _b_frame_begin() }
frame_end   :: proc() { _b_frame_end() }

// Clears the current target. Must be the first operation after frame_begin or target_begin: under
// sokol this becomes the pass's load action, not a draw.
clear :: proc(col: Color) { _b_clear(col) }

// Draw into an offscreen target until target_end. These pairs must not nest.
target_begin :: proc(rt: RenderTexture) {
    assert(!_in_target, "gfx.target_begin inside another target: passes cannot nest")
    _in_target = true
    _b_target_begin(rt)
}
target_end :: proc() {
    _in_target = false
    _b_target_end()
}
@(private) _in_target: bool

// True while an offscreen target is bound. Lets lazy resource builders defer work that would
// otherwise open a nested target.
in_target :: proc() -> bool { return _in_target }

camera_begin :: proc(cam: Camera2D) {
    _active_camera, _camera_active = cam, true
    _b_camera_begin(cam)
}
camera_end :: proc() {
    _camera_active = false
    _b_camera_end()
}
@(private) _active_camera: Camera2D
@(private) _camera_active: bool

// Scale factor the active camera applies, 1 outside a camera block. Text uses it to rasterize
// world-space glyphs at their on-screen size.
camera_scale :: proc() -> f32 {
    return _active_camera.zoom if _camera_active && _active_camera.zoom > 0 else 1
}

blend_begin :: proc(mode: BlendMode) { _b_blend_begin(mode) }
blend_end   :: proc()                { _b_blend_end() }

scissor_begin :: proc(#any_int x, y, w, h: i32) { _b_scissor_begin(x, y, w, h) }
scissor_end   :: proc()                         { _b_scissor_end() }

// ---- shapes --------------------------------------------------------------------------------

draw_rect         :: proc(#any_int x, y, w, h: i32, col: Color) { _b_draw_rect(x, y, w, h, col) }
draw_rect_rec     :: proc(r: Rect, col: Color)                  { _b_draw_rect_rec(r, col) }
draw_rect_v       :: proc(pos, size: Vec2, col: Color)          { _b_draw_rect_v(pos, size, col) }
draw_rect_lines   :: proc(r: Rect, thick: f32, col: Color)      { _b_draw_rect_lines(r, thick, col) }
draw_rect_rounded :: proc(r: Rect, roundness: f32, #any_int segments: i32, col: Color) {
    _b_draw_rect_rounded(r, roundness, segments, col)
}

draw_circle         :: proc(#any_int x, y: i32, radius: f32, col: Color) { _b_draw_circle(x, y, radius, col) }
draw_circle_v       :: proc(center: Vec2, radius: f32, col: Color)       { _b_draw_circle_v(center, radius, col) }
draw_circle_lines   :: proc(#any_int x, y: i32, radius: f32, col: Color) { _b_draw_circle_lines(x, y, radius, col) }
draw_circle_lines_v :: proc(center: Vec2, radius: f32, col: Color)       { _b_draw_circle_lines_v(center, radius, col) }

draw_ellipse       :: proc(#any_int x, y: i32, rh, rv: f32, col: Color) { _b_draw_ellipse(x, y, rh, rv, col) }
draw_ellipse_lines :: proc(#any_int x, y: i32, rh, rv: f32, col: Color) { _b_draw_ellipse_lines(x, y, rh, rv, col) }

draw_ring :: proc(center: Vec2, inner, outer, start_angle, end_angle: f32, #any_int segments: i32, col: Color) {
    _b_draw_ring(center, inner, outer, start_angle, end_angle, segments, col)
}

draw_line    :: proc(#any_int x1, y1, x2, y2: i32, col: Color) { _b_draw_line(x1, y1, x2, y2, col) }
draw_line_v  :: proc(a, b: Vec2, col: Color)                   { _b_draw_line_v(a, b, col) }
draw_line_ex :: proc(a, b: Vec2, thick: f32, col: Color)       { _b_draw_line_ex(a, b, thick, col) }

draw_triangle       :: proc(a, b, c: Vec2, col: Color) { _b_draw_triangle(a, b, c, col) }
draw_triangle_lines :: proc(a, b, c: Vec2, col: Color) { _b_draw_triangle_lines(a, b, c, col) }

draw_pixel :: proc(#any_int x, y: i32, col: Color) { _b_draw_pixel(x, y, col) }

// ---- text ----------------------------------------------------------------------------------

draw_text :: proc(font: Font, text: cstring, pos: Vec2, size, spacing: f32, tint: Color) {
    _b_draw_text(font, text, pos, size, spacing, tint)
}

measure_text :: proc(font: Font, text: cstring, size, spacing: f32) -> Vec2 {
    return _b_measure_text(font, text, size, spacing)
}

// ---- textures ------------------------------------------------------------------------------

// `src` is in texture pixels with a top-left origin and a positive size.
draw_texture_pro :: proc(tex: Texture, src, dst: Rect, origin: Vec2, rotation: f32, tint: Color) {
    _b_draw_texture_pro(tex, src, dst, origin, rotation, tint)
}

draw_texture_ex :: proc(tex: Texture, pos: Vec2, rotation, scale: f32, tint: Color) {
    _b_draw_texture_ex(tex, pos, rotation, scale, tint)
}

// Draws a whole render target over `dst`, upright.
draw_target :: proc(rt: RenderTexture, dst: Rect, tint := WHITE) {
    draw_texture_pro(rt.texture, target_src(rt), dst, { 0, 0 }, 0, tint)
}

// ---- immediate-mode quads --------------------------------------------------------------------

// A stream of quads: quads_begin, then four (colour, uv, position) vertices per quad, then
// quads_end. Used by the greybox and sprite-shadow renderers.
quads_begin          :: proc()             { _b_quads_begin({}, false) }
quads_begin_textured :: proc(tex: Texture) { _b_quads_begin(tex, true) }
quads_end            :: proc()             { _b_quads_end() }

quad_color  :: proc(col: Color) { _b_quad_color(col) }
quad_uv     :: proc(u, v: f32)  { _b_quad_uv(u, v) }
quad_vertex :: proc(p: Vec2)    { _b_quad_vertex(p) }

// ---- immediate-mode triangles ------------------------------------------------------------------

// A stream of triangles with per-vertex colour and UV. ImGui draw lists use this.
tris_begin           :: proc()             { _b_tris_begin({}, false) }
tris_begin_textured  :: proc(tex: Texture) { _b_tris_begin(tex, true) }
tris_end             :: proc()             { _b_tris_end() }
tri_vertex           :: proc(p, uv: Vec2, col: Color) { _b_tri_vertex(p, uv, col) }

// ---- misc ----------------------------------------------------------------------------------

point_in_rect :: proc(p: Vec2, r: Rect) -> bool {
    return p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height
}

world_to_screen :: proc(pos: Vec2, cam: Camera2D) -> Vec2 {
    return { (pos.x - cam.target.x) * cam.zoom + cam.offset.x,
             (pos.y - cam.target.y) * cam.zoom + cam.offset.y }
}

screen_to_world :: proc(pos: Vec2, cam: Camera2D) -> Vec2 {
    z := cam.zoom if cam.zoom != 0 else 1
    return { (pos.x - cam.offset.x) / z + cam.target.x,
             (pos.y - cam.offset.y) / z + cam.target.y }
}

_ :: c
