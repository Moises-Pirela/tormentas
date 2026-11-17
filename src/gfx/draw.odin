package gfx

// Drawing API (docs/BUILD_PLAN.md, P1a step 4). Game code calls these; only this package knows
// which backend draws them. Argument order follows raylib's for now, because that made the
// 1,100-call migration a rename; step 7 is free to tidy it once sokol is underneath.

import "core:c"
import rl "vendor:raylib"

TextureFilter :: rl.TextureFilter
TextureWrap   :: rl.TextureWrap
BlendMode     :: rl.BlendMode

// ---- frame and targets -------------------------------------------------------------------------

frame_begin :: proc() { rl.BeginDrawing() }
frame_end   :: proc() { rl.EndDrawing() }

clear :: proc(col: Color) { rl.ClearBackground(col) }

// Draw into an offscreen target until target_end. Under sokol these become passes, which cannot
// nest, so keep these pairs flat (the spike's layer scheme is the replacement).
target_begin :: proc(rt: RenderTexture) { rl.BeginTextureMode(rt) }
target_end   :: proc()                  { rl.EndTextureMode() }

camera_begin :: proc(cam: Camera2D) { rl.BeginMode2D(cam) }
camera_end   :: proc()              { rl.EndMode2D() }

shader_begin :: proc(s: Shader) { rl.BeginShaderMode(s) }
shader_end   :: proc()          { rl.EndShaderMode() }

blend_begin :: proc(mode: BlendMode) { rl.BeginBlendMode(mode) }
blend_end   :: proc()                { rl.EndBlendMode() }

scissor_begin :: proc(#any_int x, y, w, h: c.int) { rl.BeginScissorMode(x, y, w, h) }
scissor_end   :: proc()                           { rl.EndScissorMode() }

// ---- shapes --------------------------------------------------------------------------------

draw_rect         :: proc(#any_int x, y, w, h: c.int, col: Color) { rl.DrawRectangle(x, y, w, h, col) }
draw_rect_rec     :: proc(r: Rect, col: Color)                    { rl.DrawRectangleRec(r, col) }
draw_rect_v       :: proc(pos, size: Vec2, col: Color)            { rl.DrawRectangleV(pos, size, col) }
draw_rect_lines   :: proc(r: Rect, thick: f32, col: Color)        { rl.DrawRectangleLinesEx(r, thick, col) }
draw_rect_rounded :: proc(r: Rect, roundness: f32, #any_int segments: c.int, col: Color) {
    rl.DrawRectangleRounded(r, roundness, segments, col)
}

draw_circle         :: proc(#any_int x, y: c.int, radius: f32, col: Color) { rl.DrawCircle(x, y, radius, col) }
draw_circle_v       :: proc(center: Vec2, radius: f32, col: Color)         { rl.DrawCircleV(center, radius, col) }
draw_circle_lines   :: proc(#any_int x, y: c.int, radius: f32, col: Color) { rl.DrawCircleLines(x, y, radius, col) }
draw_circle_lines_v :: proc(center: Vec2, radius: f32, col: Color)         { rl.DrawCircleLinesV(center, radius, col) }

draw_ellipse       :: proc(#any_int x, y: c.int, rh, rv: f32, col: Color) { rl.DrawEllipse(x, y, rh, rv, col) }
draw_ellipse_lines :: proc(#any_int x, y: c.int, rh, rv: f32, col: Color) { rl.DrawEllipseLines(x, y, rh, rv, col) }

draw_ring :: proc(center: Vec2, inner, outer, start_angle, end_angle: f32, #any_int segments: c.int, col: Color) {
    rl.DrawRing(center, inner, outer, start_angle, end_angle, segments, col)
}

draw_line    :: proc(#any_int x1, y1, x2, y2: c.int, col: Color) { rl.DrawLine(x1, y1, x2, y2, col) }
draw_line_v  :: proc(a, b: Vec2, col: Color)                     { rl.DrawLineV(a, b, col) }
draw_line_ex :: proc(a, b: Vec2, thick: f32, col: Color)         { rl.DrawLineEx(a, b, thick, col) }

draw_triangle       :: proc(a, b, c: Vec2, col: Color) { rl.DrawTriangle(a, b, c, col) }
draw_triangle_lines :: proc(a, b, c: Vec2, col: Color) { rl.DrawTriangleLines(a, b, c, col) }

draw_pixel :: proc(#any_int x, y: c.int, col: Color) { rl.DrawPixel(x, y, col) }

// ---- text ----------------------------------------------------------------------------------

draw_text :: proc(font: Font, text: cstring, pos: Vec2, size, spacing: f32, tint: Color) {
    rl.DrawTextEx(font, text, pos, size, spacing, tint)
}

measure_text :: proc(font: Font, text: cstring, size, spacing: f32) -> Vec2 {
    return rl.MeasureTextEx(font, text, size, spacing)
}

// ---- textures ------------------------------------------------------------------------------

draw_texture_pro :: proc(tex: Texture, src, dst: Rect, origin: Vec2, rotation: f32, tint: Color) {
    rl.DrawTexturePro(tex, src, dst, origin, rotation, tint)
}

draw_texture_ex :: proc(tex: Texture, pos: Vec2, rotation, scale: f32, tint: Color) {
    rl.DrawTextureEx(tex, pos, rotation, scale, tint)
}

// ---- immediate-mode quads --------------------------------------------------------------------

// A stream of quads: quads_begin, then four (colour, uv, position) vertices per quad, then
// quads_end. Used by the greybox and sprite-shadow renderers. Maps to sokol_gl in step 7.
quads_begin :: proc() {
    rlgl_set_texture(rlgl_default_texture())
    rlgl_begin_quads()
}

quads_begin_textured :: proc(tex: Texture) {
    rlgl_set_texture(tex.id)
    rlgl_begin_quads()
}

quads_end :: proc() {
    rlgl_end()
    rlgl_set_texture(0)
}

quad_color  :: proc(col: Color)   { rlgl_color(col) }
quad_uv     :: proc(u, v: f32)    { rlgl_uv(u, v) }
quad_vertex :: proc(p: Vec2)      { rlgl_vertex(p) }

// ---- misc ----------------------------------------------------------------------------------

point_in_rect :: proc(p: Vec2, r: Rect) -> bool { return rl.CheckCollisionPointRec(p, r) }

world_to_screen :: proc(pos: Vec2, cam: Camera2D) -> Vec2 { return rl.GetWorldToScreen2D(pos, cam) }
screen_to_world :: proc(pos: Vec2, cam: Camera2D) -> Vec2 { return rl.GetScreenToWorld2D(pos, cam) }
