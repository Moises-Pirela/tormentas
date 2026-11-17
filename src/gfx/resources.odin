package gfx

// Textures, render targets, fonts and CPU images (docs/BACKEND_SWAP_PLAN.md §3.5).

// ---- textures ------------------------------------------------------------------------------

load_texture :: proc(path: cstring, filter := TextureFilter.Point, wrap := TextureWrap.Repeat) -> Texture {
    t := _b_load_texture(path)
    if t.id == 0 { return t }
    if filter != .Point { _b_texture_set_filter(t, filter) }
    if wrap != .Repeat  { _b_texture_set_wrap(t, wrap) }
    return t
}

// Uploads 8-bit RGBA pixels, tightly packed, top row first.
load_texture_pixels :: proc(pixels: []u8, w, h: i32, filter := TextureFilter.Point) -> Texture {
    t := _b_load_texture_pixels(pixels, w, h)
    if t.id != 0 && filter != .Point { _b_texture_set_filter(t, filter) }
    return t
}

// Replaces a texture's pixels; the size must not change.
update_texture :: proc(t: Texture, pixels: []u8) { _b_update_texture(t, pixels) }

unload_texture     :: proc(t: Texture)                     { if t.id != 0 { _b_unload_texture(t) } }
texture_set_filter :: proc(t: Texture, f: TextureFilter)   { _b_texture_set_filter(t, f) }
texture_set_wrap   :: proc(t: Texture, w: TextureWrap)     { _b_texture_set_wrap(t, w) }

// ---- render targets ------------------------------------------------------------------------

load_render_texture   :: proc(#any_int w, h: i32) -> RenderTexture { return _b_load_render_texture(w, h) }
unload_render_texture :: proc(rt: RenderTexture)                   { if rt.id != 0 { _b_unload_render_texture(rt) } }

// ---- fonts ---------------------------------------------------------------------------------

// Loads a font. `size` is the base size the backend bakes at; text can be drawn at any size.
load_font :: proc(path: cstring, #any_int size: i32) -> (Font, bool) { return _b_load_font(path, size) }

font_default :: proc() -> Font  { return _b_font_default() }
unload_font  :: proc(f: Font)   { if f.id != 0 { _b_unload_font(f) } }

// ---- images (CPU pixels) ---------------------------------------------------------------------

// Loads an image as 8-bit RGBA. The caller owns `pixels` and frees it with unload_image.
load_image :: proc(path: cstring) -> (Image, bool) { return _b_load_image(path) }

unload_image :: proc(img: Image) {
    if img.pixels != nil { delete(img.pixels) }
}

// Alpha of one pixel, 0 when out of range.
image_alpha_at :: proc(img: Image, x, y: i32) -> u8 {
    if x < 0 || y < 0 || x >= img.width || y >= img.height { return 0 }
    return img.pixels[(int(y) * int(img.width) + int(x)) * 4 + 3]
}
