package gfx

// raylib-specific glue: the immediate-mode quad stream, which is the only place the game reaches
// below raylib's public API (rlgl). Step 7 replaces this file's body with sokol_gl.

import rlgl "vendor:raylib/rlgl"

@(private) rlgl_default_texture :: proc() -> u32 { return rlgl.GetTextureIdDefault() }
@(private) rlgl_set_texture     :: proc(id: u32) { rlgl.SetTexture(id) }
@(private) rlgl_begin_quads     :: proc()        { rlgl.Begin(rlgl.QUADS) }
@(private) rlgl_end             :: proc()        { rlgl.End() }

@(private) rlgl_color  :: proc(col: Color) { rlgl.Color4ub(col.r, col.g, col.b, col.a) }
@(private) rlgl_uv     :: proc(u, v: f32)  { rlgl.TexCoord2f(u, v) }
@(private) rlgl_vertex :: proc(p: Vec2)    { rlgl.Vertex2f(p[0], p[1]) }
