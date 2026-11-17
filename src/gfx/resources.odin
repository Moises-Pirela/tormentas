package gfx

// Textures, render targets, fonts, images and shaders (docs/BUILD_PLAN.md, P1a step 4).
// The handle types are raylib's for now; step 7 replaces them with sokol handles. Game code only
// passes them around and reads a few fields (texture size, image pixels), so that swap is contained.

import "core:c"
import rl "vendor:raylib"

Texture       :: rl.Texture2D
RenderTexture :: rl.RenderTexture2D
Font          :: rl.Font
Shader        :: rl.Shader
Image         :: rl.Image
PixelFormat   :: rl.PixelFormat
Camera2D      :: rl.Camera2D

// ---- textures ------------------------------------------------------------------------------

load_texture        :: proc(path: cstring) -> Texture              { return rl.LoadTexture(path) }
unload_texture      :: proc(t: Texture)                            { rl.UnloadTexture(t) }
texture_set_filter  :: proc(t: Texture, filter: TextureFilter)     { rl.SetTextureFilter(t, filter) }
texture_set_wrap    :: proc(t: Texture, wrap: TextureWrap)         { rl.SetTextureWrap(t, wrap) }
texture_gen_mipmaps :: proc(t: ^Texture)                           { rl.GenTextureMipmaps(t) }

// ---- render targets ------------------------------------------------------------------------

load_render_texture   :: proc(#any_int w, h: c.int) -> RenderTexture { return rl.LoadRenderTexture(w, h) }
unload_render_texture :: proc(rt: RenderTexture)                     { rl.UnloadRenderTexture(rt) }

// ---- fonts ---------------------------------------------------------------------------------

load_font    :: proc(path: cstring, #any_int size: c.int) -> Font { return rl.LoadFontEx(path, size, nil, 0) }
unload_font  :: proc(f: Font)                                     { rl.UnloadFont(f) }
font_default :: proc() -> Font                                    { return rl.GetFontDefault() }

// ---- images (CPU-side pixels) ----------------------------------------------------------------

load_image   :: proc(path: cstring) -> Image               { return rl.LoadImage(path) }
unload_image :: proc(img: Image)                           { rl.UnloadImage(img) }
image_format :: proc(img: ^Image, format: PixelFormat)     { rl.ImageFormat(img, format) }

// ---- shaders -------------------------------------------------------------------------------

// Fragment-only shader; the backend supplies the vertex stage.
load_shader_fs  :: proc(path: cstring) -> Shader               { return rl.LoadShader(nil, path) }
unload_shader   :: proc(s: Shader)                             { rl.UnloadShader(s) }
shader_location :: proc(s: Shader, name: cstring) -> i32       { return i32(rl.GetShaderLocation(s, name)) }

shader_set_f32  :: proc(s: Shader, loc: i32, v: f32)      { v := v; rl.SetShaderValue(s, loc, &v, .FLOAT) }
shader_set_i32  :: proc(s: Shader, loc: i32, v: i32)      { v := v; rl.SetShaderValue(s, loc, &v, .INT) }
shader_set_vec2 :: proc(s: Shader, loc: i32, v: [2]f32)   { v := v; rl.SetShaderValue(s, loc, &v, .VEC2) }
shader_set_vec3 :: proc(s: Shader, loc: i32, v: [3]f32)   { v := v; rl.SetShaderValue(s, loc, &v, .VEC3) }

// Array uniforms. `count` is the number of elements actually in use, which is usually fewer than
// the backing array's length (light counts, for instance).
shader_set_f32_array :: proc(s: Shader, loc: i32, v: []f32, #any_int count: c.int) {
    v := v
    rl.SetShaderValueV(s, loc, raw_data(v), .FLOAT, count)
}
shader_set_vec2_array :: proc(s: Shader, loc: i32, v: [][2]f32, #any_int count: c.int) {
    v := v
    rl.SetShaderValueV(s, loc, raw_data(v), .VEC2, count)
}
shader_set_vec3_array :: proc(s: Shader, loc: i32, v: [][3]f32, #any_int count: c.int) {
    v := v
    rl.SetShaderValueV(s, loc, raw_data(v), .VEC3, count)
}

shader_set_texture :: proc(s: Shader, loc: i32, tex: Texture) { rl.SetShaderValueTexture(s, loc, tex) }
