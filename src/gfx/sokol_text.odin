package gfx

// Text on fontstash (docs/BACKEND_SWAP_PLAN.md §3.6).
//
// raylib baked one 512 px atlas per font and scaled every size down from it, with mipmaps.
// fontstash rasterizes at the size actually drawn, which is sharper, and it grows its atlas as new
// sizes appear. Two consequences the rest of the code cares about:
//
//   - Sizes are rounded to whole pixels, so a sliding UI scale cannot fill the atlas with
//     near-identical variants.
//   - World-space text sits inside a scaled camera, so it is rasterized at `size x camera scale`
//     and emitted at 1/scale. That keeps editor text crisp at 6x zoom.

import "core:c"

import sg  "sokol:gfx"
import sgl "sokol:gl"
import fs  "vendor:fontstash"

ATLAS_START :: 1024

@(private) _text: struct {
    ctx:        fs.FontContext,
    atlas:      Texture,
    rgba:       [dynamic]u8,
    dirty:      bool,
    recreate:   bool,
    atlas_w:    int,
    atlas_h:    int,
    next_id:    u32,
}

@(private)
_text_setup :: proc() {
    fs.Init(&_text.ctx, ATLAS_START, ATLAS_START, .TOPLEFT)
    _text.ctx.userData       = nil
    _text.ctx.callbackResize = proc(data: rawptr, w, h: int) {
        _text.atlas_w, _text.atlas_h = w, h
        _text.recreate = true
    }
    _text.ctx.callbackUpdate = proc(data: rawptr, dirty_rect: [4]f32, texture_data: rawptr) {
        _text.dirty = true
    }
    _text.atlas_w, _text.atlas_h = ATLAS_START, ATLAS_START
    _text.next_id  = 1
    _recreate_atlas()
}

// The atlas texture exists from the start, so recorded draws always reference a live view.
@(private)
_recreate_atlas :: proc() {
    _b_unload_texture(_text.atlas)
    resize(&_text.rgba, _text.atlas_w * _text.atlas_h * 4)
    for i in 0..<len(_text.rgba) { _text.rgba[i] = 0 }
    _text.atlas = _make_texture(_text.rgba[:], i32(_text.atlas_w), i32(_text.atlas_h), _gl.smp_linear)
    _text.recreate = false
    _text.dirty = true
}

@(private)
_text_shutdown :: proc() {
    fs.Destroy(&_text.ctx)
    delete(_text.rgba)
    _b_unload_texture(_text.atlas)
}

@(private)
_b_load_font :: proc(path: cstring, size: i32) -> (Font, bool) {
    id := fs.AddFontPath(&_text.ctx, string(path), string(path))
    if id < 0 { return {}, false }
    _text.next_id += 1
    return { id = _text.next_id, size = f32(size), _h = { font = id } }, true
}

// fontstash has no built-in font; the caller falls back to whatever it loaded first.
@(private) _b_font_default :: proc() -> Font { return {} }
@(private) _b_unload_font  :: proc(f: Font)  { /* the atlas owns the glyphs */ }

Backend_Font :: struct {
    font: int,
}

// fontstash's atlas is one byte per pixel. Expand it to white RGBA so text goes through the same
// textured-quad pipeline as everything else.
@(private)
_text_upload_atlas :: proc() {
    if _text.recreate { _recreate_atlas() }

    // fontstash only reports through its update callback inside Begin/EndState, which this backend
    // does not use, so ask it directly whether new glyphs were rasterized.
    dirty_rect: [4]f32
    if fs.ValidateTexture(&_text.ctx, &dirty_rect) { _text.dirty = true }
    if !_text.dirty { return }
    _text.dirty = false

    src := _text.ctx.textureData
    n := min(len(src), _text.atlas_w * _text.atlas_h)
    for i in 0..<n {
        a := src[i]
        _text.rgba[i * 4 + 0] = 255
        _text.rgba[i * 4 + 1] = 255
        _text.rgba[i * 4 + 2] = 255
        _text.rgba[i * 4 + 3] = a
    }
    _b_update_texture(_text.atlas, _text.rgba[:])
}

@(private)
_text_prepare :: proc(font: Font, size, spacing: f32) -> f32 {
    scale := camera_scale()
    px    := max(1, f32(int(size * scale + 0.5)))  // whole pixels: fewer atlas variants
    fs.ClearState(&_text.ctx)
    fs.SetFont(&_text.ctx, font._h.font)
    fs.SetSize(&_text.ctx, px)
    fs.SetSpacing(&_text.ctx, spacing * scale)
    fs.SetAlignVertical(&_text.ctx, .TOP)
    return scale
}

@(private)
_b_draw_text :: proc(font: Font, text: cstring, pos: Vec2, size, spacing: f32, tint: Color) {
    str := string(text)
    if len(str) == 0 { return }
    scale := _text_prepare(font, size, spacing)
    inv   := 1.0 / scale

    sgl.enable_texture()
    sgl.texture(_text.atlas._h.view, _text.atlas._h.smp)
    sgl.begin_quads()
    iter := fs.TextIterInit(&_text.ctx, 0, 0, str)
    q: fs.Quad
    for fs.TextIterNext(&_text.ctx, &iter, &q) {
        x0 := pos.x + q.x0 * inv
        y0 := pos.y + q.y0 * inv
        x1 := pos.x + q.x1 * inv
        y1 := pos.y + q.y1 * inv
        sgl.v2f_t2f_c4b(x0, y0, q.s0, q.t0, tint.r, tint.g, tint.b, tint.a)
        sgl.v2f_t2f_c4b(x1, y0, q.s1, q.t0, tint.r, tint.g, tint.b, tint.a)
        sgl.v2f_t2f_c4b(x1, y1, q.s1, q.t1, tint.r, tint.g, tint.b, tint.a)
        sgl.v2f_t2f_c4b(x0, y1, q.s0, q.t1, tint.r, tint.g, tint.b, tint.a)
    }
    sgl.end()
    sgl.disable_texture()
    _mark_drawn()
}

// Width of the string, and a height of `size`, which is what the layout code expects of a single
// line (it mixes measured height with the font size when centring).
@(private)
_b_measure_text :: proc(font: Font, text: cstring, size, spacing: f32) -> Vec2 {
    str := string(text)
    if len(str) == 0 { return { 0, size } }
    scale := _text_prepare(font, size, spacing)
    w := fs.TextBounds(&_text.ctx, str, 0, 0, nil)
    return { w / scale, size }
}

_ :: c
_ :: sg
