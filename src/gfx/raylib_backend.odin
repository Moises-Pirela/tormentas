package gfx

// The raylib backend: every raylib call in the game lives here or in the files that include its
// helpers. docs/BACKEND_SWAP_PLAN.md stage S7 deletes this file once the sokol backend is in.
//
// Game-facing types stay raylib-free (types.odin); this file holds the payloads and the
// conversions.

import "core:c"
import rl   "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

Backend_Texture        :: rl.Texture2D
Backend_Render_Texture :: rl.RenderTexture2D
Backend_Font           :: rl.Font
Backend_Shader         :: rl.Shader

@(private) _rl_color :: proc(c: Color) -> rl.Color { return rl.Color(c) }
@(private) _rl_rect  :: proc(r: Rect) -> rl.Rectangle {
    return { r.x, r.y, r.width, r.height }
}

// Source rectangle as raylib wants it: a render target is stored bottom-up, so sampling it
// upright needs a negative height. Game code never sees this.
@(private) _rl_src :: proc(t: Texture, src: Rect) -> rl.Rectangle {
    if t.flipped {
        return { src.x, src.y + src.height, src.width, -src.height }
    }
    return _rl_rect(src)
}

@(private) _rl_filter :: proc(f: TextureFilter) -> rl.TextureFilter {
    switch f {
    case .Point:     return .POINT
    case .Bilinear:  return .BILINEAR
    case .Trilinear: return .TRILINEAR
    }
    return .POINT
}

@(private) _rl_wrap :: proc(w: TextureWrap) -> rl.TextureWrap {
    return .CLAMP if w == .Clamp else .REPEAT
}

@(private) _wrap_texture :: proc(t: rl.Texture2D, flipped := false) -> Texture {
    return { id = t.id, width = t.width, height = t.height, flipped = flipped, _h = t }
}

// ---- immediate-mode quads -------------------------------------------------------------------

@(private) _b_quads_begin :: proc(tex: Texture, textured: bool) {
    rlgl.SetTexture(tex._h.id if textured else rlgl.GetTextureIdDefault())
    rlgl.Begin(rlgl.QUADS)
}

@(private) _b_quads_end :: proc() {
    rlgl.End()
    rlgl.SetTexture(0)
}

@(private) _b_quad_color  :: proc(col: Color) { rlgl.Color4ub(col.r, col.g, col.b, col.a) }
@(private) _b_quad_uv     :: proc(u, v: f32)  { rlgl.TexCoord2f(u, v) }
@(private) _b_quad_vertex :: proc(p: Vec2)    { rlgl.Vertex2f(p[0], p[1]) }

// ---- frame and passes -----------------------------------------------------------------------

@(private) _b_frame_begin :: proc() { rl.BeginDrawing() }
@(private) _b_frame_end   :: proc() { rl.EndDrawing() }
@(private) _b_clear       :: proc(col: Color) { rl.ClearBackground(_rl_color(col)) }

@(private) _b_target_begin :: proc(rt: RenderTexture) { rl.BeginTextureMode(rt._h) }
@(private) _b_target_end   :: proc()                  { rl.EndTextureMode() }

@(private) _b_camera_begin :: proc(cam: Camera2D) {
    rl.BeginMode2D(rl.Camera2D{
        offset   = cam.offset,
        target   = cam.target,
        rotation = cam.rotation,
        zoom     = cam.zoom,
    })
}
@(private) _b_camera_end :: proc() { rl.EndMode2D() }

@(private) _b_blend_begin :: proc(mode: BlendMode) {
    rl.BeginBlendMode(.ADDITIVE if mode == .Additive else .ALPHA)
}
@(private) _b_blend_end :: proc() { rl.EndBlendMode() }

@(private) _b_scissor_begin :: proc(x, y, w, h: i32) { rl.BeginScissorMode(x, y, w, h) }
@(private) _b_scissor_end   :: proc()                { rl.EndScissorMode() }

// ---- shapes ---------------------------------------------------------------------------------

@(private) _b_draw_rect :: proc(x, y, w, h: i32, col: Color) {
    rl.DrawRectangle(x, y, w, h, _rl_color(col))
}
@(private) _b_draw_rect_rec :: proc(r: Rect, col: Color) {
    rl.DrawRectangleRec(_rl_rect(r), _rl_color(col))
}
@(private) _b_draw_rect_v :: proc(pos, size: Vec2, col: Color) {
    rl.DrawRectangleV(pos, size, _rl_color(col))
}
@(private) _b_draw_rect_lines :: proc(r: Rect, thick: f32, col: Color) {
    rl.DrawRectangleLinesEx(_rl_rect(r), thick, _rl_color(col))
}
@(private) _b_draw_rect_rounded :: proc(r: Rect, roundness: f32, segments: i32, col: Color) {
    rl.DrawRectangleRounded(_rl_rect(r), roundness, segments, _rl_color(col))
}
@(private) _b_draw_circle :: proc(x, y: i32, radius: f32, col: Color) {
    rl.DrawCircle(x, y, radius, _rl_color(col))
}
@(private) _b_draw_circle_v :: proc(center: Vec2, radius: f32, col: Color) {
    rl.DrawCircleV(center, radius, _rl_color(col))
}
@(private) _b_draw_circle_lines :: proc(x, y: i32, radius: f32, col: Color) {
    rl.DrawCircleLines(x, y, radius, _rl_color(col))
}
@(private) _b_draw_circle_lines_v :: proc(center: Vec2, radius: f32, col: Color) {
    rl.DrawCircleLinesV(center, radius, _rl_color(col))
}
@(private) _b_draw_ellipse :: proc(x, y: i32, rh, rv: f32, col: Color) {
    rl.DrawEllipse(x, y, rh, rv, _rl_color(col))
}
@(private) _b_draw_ellipse_lines :: proc(x, y: i32, rh, rv: f32, col: Color) {
    rl.DrawEllipseLines(x, y, rh, rv, _rl_color(col))
}
@(private) _b_draw_ring :: proc(center: Vec2, inner, outer, a0, a1: f32, segments: i32, col: Color) {
    rl.DrawRing(center, inner, outer, a0, a1, segments, _rl_color(col))
}
@(private) _b_draw_line :: proc(x1, y1, x2, y2: i32, col: Color) {
    rl.DrawLine(x1, y1, x2, y2, _rl_color(col))
}
@(private) _b_draw_line_v :: proc(a, b: Vec2, col: Color) {
    rl.DrawLineV(a, b, _rl_color(col))
}
@(private) _b_draw_line_ex :: proc(a, b: Vec2, thick: f32, col: Color) {
    rl.DrawLineEx(a, b, thick, _rl_color(col))
}
@(private) _b_draw_triangle :: proc(a, b, c: Vec2, col: Color) {
    rl.DrawTriangle(a, b, c, _rl_color(col))
}
@(private) _b_draw_triangle_lines :: proc(a, b, c: Vec2, col: Color) {
    rl.DrawTriangleLines(a, b, c, _rl_color(col))
}
@(private) _b_draw_pixel :: proc(x, y: i32, col: Color) {
    rl.DrawPixel(x, y, _rl_color(col))
}

// ---- text -----------------------------------------------------------------------------------

@(private) _b_draw_text :: proc(font: Font, text: cstring, pos: Vec2, size, spacing: f32, tint: Color) {
    rl.DrawTextEx(font._h, text, pos, size, spacing, _rl_color(tint))
}
@(private) _b_measure_text :: proc(font: Font, text: cstring, size, spacing: f32) -> Vec2 {
    return rl.MeasureTextEx(font._h, text, size, spacing)
}

// ---- textures -------------------------------------------------------------------------------

@(private) _b_draw_texture_pro :: proc(t: Texture, src, dst: Rect, origin: Vec2, rotation: f32, tint: Color) {
    rl.DrawTexturePro(t._h, _rl_src(t, src), _rl_rect(dst), origin, rotation, _rl_color(tint))
}
@(private) _b_draw_texture_ex :: proc(t: Texture, pos: Vec2, rotation, scale: f32, tint: Color) {
    rl.DrawTextureEx(t._h, pos, rotation, scale, _rl_color(tint))
}

@(private) _b_load_texture :: proc(path: cstring) -> Texture {
    return _wrap_texture(rl.LoadTexture(path))
}
@(private) _b_load_texture_pixels :: proc(pixels: []u8, w, h: i32) -> Texture {
    img := rl.Image{
        data    = raw_data(pixels),
        width   = w,
        height  = h,
        mipmaps = 1,
        format  = .UNCOMPRESSED_R8G8B8A8,
    }
    return _wrap_texture(rl.LoadTextureFromImage(img))
}
@(private) _b_update_texture :: proc(t: Texture, pixels: []u8) {
    rl.UpdateTexture(t._h, raw_data(pixels))
}
@(private) _b_unload_texture :: proc(t: Texture) { rl.UnloadTexture(t._h) }

@(private) _b_texture_set_filter :: proc(t: Texture, f: TextureFilter) {
    if f == .Trilinear {
        tex := t._h
        rl.GenTextureMipmaps(&tex)
    }
    rl.SetTextureFilter(t._h, _rl_filter(f))
}
@(private) _b_texture_set_wrap :: proc(t: Texture, w: TextureWrap) {
    rl.SetTextureWrap(t._h, _rl_wrap(w))
}

@(private) _b_load_render_texture :: proc(w, h: i32) -> RenderTexture {
    rt := rl.LoadRenderTexture(w, h)
    return { id = rt.id, texture = _wrap_texture(rt.texture, flipped = true), _h = rt }
}
@(private) _b_unload_render_texture :: proc(rt: RenderTexture) { rl.UnloadRenderTexture(rt._h) }

// ---- fonts ----------------------------------------------------------------------------------

@(private) _b_load_font :: proc(path: cstring, size: i32) -> (Font, bool) {
    f := rl.LoadFontEx(path, size, nil, 0)
    if f.texture.id == 0 { return {}, false }
    // The atlas is baked once at a large size and scaled down everywhere, so it needs mipmaps.
    tex := f.texture
    rl.GenTextureMipmaps(&tex)
    rl.SetTextureFilter(tex, .TRILINEAR)
    f.texture = tex
    return { id = f.texture.id, size = f32(size), _h = f }, true
}
@(private) _b_font_default :: proc() -> Font {
    f := rl.GetFontDefault()
    return { id = f.texture.id, size = f32(f.baseSize), _h = f }
}
@(private) _b_unload_font :: proc(f: Font) { rl.UnloadFont(f._h) }

// ---- images ---------------------------------------------------------------------------------

@(private) _b_load_image :: proc(path: cstring) -> (Image, bool) {
    img := rl.LoadImage(path)
    if img.data == nil { return {}, false }
    defer rl.UnloadImage(img)
    if img.format != .UNCOMPRESSED_R8G8B8A8 {
        rl.ImageFormat(&img, .UNCOMPRESSED_R8G8B8A8)
    }
    n := int(img.width) * int(img.height) * 4
    out := make([]u8, n)
    copy(out, ([^]u8)(img.data)[:n])
    return { pixels = out, width = img.width, height = img.height }, true
}

@(private) _b_set_window_icon :: proc(img: Image) {
    ri := rl.Image{
        data    = raw_data(img.pixels),
        width   = img.width,
        height  = img.height,
        mipmaps = 1,
        format  = .UNCOMPRESSED_R8G8B8A8,
    }
    rl.SetWindowIcon(ri)
}

// ---- shaders (used by lighting.odin) ---------------------------------------------------------

@(private) _b_load_shader_fs  :: proc(path: cstring) -> Backend_Shader { return rl.LoadShader(nil, path) }
@(private) _b_unload_shader   :: proc(s: Backend_Shader)               { rl.UnloadShader(s) }
@(private) _b_shader_loc      :: proc(s: Backend_Shader, name: cstring) -> i32 {
    return i32(rl.GetShaderLocation(s, name))
}
@(private) _b_shader_begin    :: proc(s: Backend_Shader) { rl.BeginShaderMode(s) }
@(private) _b_shader_end      :: proc()                  { rl.EndShaderMode() }

@(private) _b_set_f32  :: proc(s: Backend_Shader, loc: i32, v: f32)    { v := v; rl.SetShaderValue(s, loc, &v, .FLOAT) }
@(private) _b_set_i32  :: proc(s: Backend_Shader, loc: i32, v: i32)    { v := v; rl.SetShaderValue(s, loc, &v, .INT) }
@(private) _b_set_vec2 :: proc(s: Backend_Shader, loc: i32, v: [2]f32) { v := v; rl.SetShaderValue(s, loc, &v, .VEC2) }
@(private) _b_set_vec3 :: proc(s: Backend_Shader, loc: i32, v: [3]f32) { v := v; rl.SetShaderValue(s, loc, &v, .VEC3) }

@(private) _b_set_vec2_array :: proc(s: Backend_Shader, loc: i32, v: [][2]f32, count: i32) {
    v := v
    rl.SetShaderValueV(s, loc, raw_data(v), .VEC2, c.int(count))
}
@(private) _b_set_vec3_array :: proc(s: Backend_Shader, loc: i32, v: [][3]f32, count: i32) {
    v := v
    rl.SetShaderValueV(s, loc, raw_data(v), .VEC3, c.int(count))
}
@(private) _b_set_f32_array :: proc(s: Backend_Shader, loc: i32, v: []f32, count: i32) {
    v := v
    rl.SetShaderValueV(s, loc, raw_data(v), .FLOAT, c.int(count))
}
@(private) _b_set_texture :: proc(s: Backend_Shader, loc: i32, t: Texture) {
    rl.SetShaderValueTexture(s, loc, t._h)
}

// ---- window ---------------------------------------------------------------------------------

@(private) _b_window_init :: proc(w, h: i32, title: cstring, fullscreen: bool) {
    rl.SetConfigFlags({ .WINDOW_RESIZABLE, .VSYNC_HINT })
    rl.InitWindow(w, h, title)
    rl.SetExitKey(.KEY_NULL)
    if fullscreen && !rl.IsWindowState({ .BORDERLESS_WINDOWED_MODE }) {
        rl.ToggleBorderlessWindowed()
    }
}
@(private) _b_window_close        :: proc()         { rl.CloseWindow() }
@(private) _b_window_should_close :: proc() -> bool { return rl.WindowShouldClose() }
@(private) _b_window_is_fullscreen :: proc() -> bool {
    return rl.IsWindowState({ .BORDERLESS_WINDOWED_MODE })
}
@(private) _b_window_toggle_fullscreen :: proc() { rl.ToggleBorderlessWindowed() }
@(private) _b_window_resized :: proc() -> bool { return rl.IsWindowResized() }

@(private) _b_screen_width   :: proc() -> i32 { return rl.GetScreenWidth() }
@(private) _b_screen_height  :: proc() -> i32 { return rl.GetScreenHeight() }
@(private) _b_render_width   :: proc() -> i32 { return rl.GetRenderWidth() }
@(private) _b_render_height  :: proc() -> i32 { return rl.GetRenderHeight() }
@(private) _b_dpi_scale      :: proc() -> f32 { return rl.GetWindowScaleDPI().x }

@(private) _b_screenshot :: proc(path: cstring) -> bool {
    img := rl.LoadImageFromScreen()
    defer rl.UnloadImage(img)
    return rl.ExportImage(img, path)
}

// ---- input ----------------------------------------------------------------------------------

@(private) _b_key_down     :: proc(k: Key) -> bool { return rl.IsKeyDown(rl.KeyboardKey(k)) }
@(private) _b_key_pressed  :: proc(k: Key) -> bool { return rl.IsKeyPressed(rl.KeyboardKey(k)) }
@(private) _b_key_released :: proc(k: Key) -> bool { return rl.IsKeyReleased(rl.KeyboardKey(k)) }
@(private) _b_key_queue    :: proc() -> Key        { return Key(rl.GetKeyPressed()) }
@(private) _b_char_queue   :: proc() -> rune       { return rl.GetCharPressed() }

@(private) _b_mouse_pos    :: proc() -> Vec2 { return rl.GetMousePosition() }
@(private) _b_mouse_delta  :: proc() -> Vec2 { return rl.GetMouseDelta() }
@(private) _b_mouse_wheel  :: proc() -> f32  { return rl.GetMouseWheelMove() }
@(private) _b_mouse_down     :: proc(b: MouseButton) -> bool { return rl.IsMouseButtonDown(rl.MouseButton(b)) }
@(private) _b_mouse_pressed  :: proc(b: MouseButton) -> bool { return rl.IsMouseButtonPressed(rl.MouseButton(b)) }
@(private) _b_mouse_released :: proc(b: MouseButton) -> bool { return rl.IsMouseButtonReleased(rl.MouseButton(b)) }

@(private) _b_time       :: proc() -> f64 { return rl.GetTime() }
@(private) _b_frame_time :: proc() -> f32 { return rl.GetFrameTime() }
@(private) _b_set_fps    :: proc(fps: i32) { rl.SetTargetFPS(fps) }

// Native window handle (NSWindow on macOS). Used by platform_darwin.odin.
@(private) _b_window_handle :: proc() -> rawptr { return rl.GetWindowHandle() }
