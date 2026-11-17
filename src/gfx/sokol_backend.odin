package gfx

// The sokol backend (docs/BACKEND_SWAP_PLAN.md §3). It owns the window, input, timing and all
// drawing. Game code never sees any of this.
//
// The shape of a frame
// --------------------
// Game code draws in one flat stream, switching render targets as it goes and returning to the
// screen in between. sokol cannot do that directly: passes do not nest, and you cannot come back
// to the swapchain mid-frame. So draws are *recorded* and replayed as passes at frame_end:
//
//   - A `Segment` is a run of draws into one target. Screen draws go into an offscreen main
//     target, which is the backbuffer raylib used to give us.
//   - Each segment holds items in order: ranges of sokol_gl commands (one layer each) and custom
//     draws (the lighting passes and ImGui), which need their own pipelines.
//   - `clear` at the start of a segment becomes that pass's clear action.
//   - At frame_end the segments replay in order, then the main target is presented.

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"

import sapp  "sokol:app"
import sg    "sokol:gfx"
import sgl   "sokol:gl"
import sglue "sokol:glue"
import slog  "sokol:log"
import stm   "sokol:time"

import stbi "vendor:stb/image"

Backend_Texture :: struct {
    img:  sg.Image,
    view: sg.View,
    smp:  sg.Sampler,
}

Backend_Render_Texture :: struct {
    img:      sg.Image,
    attach:   sg.View,
}

// ---- lifecycle -------------------------------------------------------------------------------

Run_Desc :: struct {
    window:  Window_Desc,
    init:    proc(),
    frame:   proc(),
    cleanup: proc(),
}

@(private) _app: struct {
    desc:          Run_Desc,
    shutdown_done: bool,
    quit_wanted:   bool,
    resized:       bool,
    fullscreen:    bool,
    focused:       bool,
    frame_count:   u64,
}

// Runs the app. sokol_app owns the loop, so on macOS this never returns: everything after it must
// live in `cleanup`.
run :: proc(desc: Run_Desc) {
    _app.desc = desc
    sapp.run({
        init_cb      = _init_cb,
        frame_cb     = _frame_cb,
        cleanup_cb   = _cleanup_cb,
        event_cb     = _event_cb,
        width        = desc.window.width,
        height       = desc.window.height,
        fullscreen   = desc.window.fullscreen,
        window_title = desc.window.title,
        // High-DPI stays off (decision D1): the lighting composites and every render target are
        // sized in screen coordinates, so turning it on is its own task.
        high_dpi         = false,
        sample_count     = 1,
        swap_interval    = 1,
        enable_clipboard = true,
        clipboard_size   = 8192,
        icon             = { sokol_default = true },
        logger           = { func = slog.func },
    })
}

// Asks the app to quit. The quit path runs `cleanup` either way.
request_quit :: proc() { sapp.request_quit() }

@(private)
_init_cb :: proc "c" () {
    context = runtime.default_context()
    stm.setup()
    sg.setup({ environment = sglue.environment(), logger = { func = slog.func } })
    sgl.setup({
        max_vertices = 1 << 18,
        max_commands = 1 << 16,
        logger       = { func = slog.func },
    })
    _gl_setup()
    _text_setup()
    _lighting_setup()
    _app.fullscreen = sapp.is_fullscreen()
    _app.focused = true
    if _app.desc.init != nil { _app.desc.init() }
}

@(private)
_frame_cb :: proc "c" () {
    context = runtime.default_context()
    _app.frame_count += 1
    if _app.desc.frame != nil { _app.desc.frame() }
    _input_end_frame()
    _app.resized = false
}

@(private)
_cleanup_cb :: proc "c" () {
    context = runtime.default_context()
    _shutdown_once()
}

@(private)
_shutdown_once :: proc() {
    if _app.shutdown_done { return }
    _app.shutdown_done = true
    if _app.desc.cleanup != nil { _app.desc.cleanup() }
    _text_shutdown()
    sgl.shutdown()
    sg.shutdown()
}

// ---- events and input ------------------------------------------------------------------------

@(private) _input: struct {
    down:      [512]bool,
    pressed:   [512]bool,
    released:  [512]bool,
    mouse_down:     [8]bool,
    mouse_pressed:  [8]bool,
    mouse_released: [8]bool,
    mouse_pos:   Vec2,
    mouse_delta: Vec2,
    wheel:       Vec2,
    key_queue:   [16]Key,
    key_count:   int,
    char_queue:  [32]rune,
    char_count:  int,
    char_read:   int,
    key_read:    int,
}

@(private)
_event_cb :: proc "c" (e: ^sapp.Event) {
    context = runtime.default_context()
    #partial switch e.type {
    case .KEY_DOWN:
        k := int(e.key_code)
        // Cmd+Q: sokol_app installs no menu, so the shortcut has to be handled here.
        when ODIN_OS == .Darwin {
            if e.key_code == .Q && (e.modifiers & sapp.MODIFIER_SUPER) != 0 {
                sapp.request_quit()
                return
            }
        }
        if k >= 0 && k < len(_input.down) {
            // `pressed` means a fresh press: auto-repeat must not re-trigger actions.
            if !e.key_repeat {
                _input.pressed[k] = true
                if _input.key_count < len(_input.key_queue) {
                    _input.key_queue[_input.key_count] = Key(k)
                    _input.key_count += 1
                }
            }
            _input.down[k] = true
        }
    case .KEY_UP:
        k := int(e.key_code)
        if k >= 0 && k < len(_input.down) {
            _input.down[k] = false
            _input.released[k] = true
        }
    case .CHAR:
        if _input.char_count < len(_input.char_queue) {
            _input.char_queue[_input.char_count] = rune(e.char_code)
            _input.char_count += 1
        }
    case .MOUSE_DOWN:
        b := int(e.mouse_button)
        if b >= 0 && b < len(_input.mouse_down) {
            _input.mouse_down[b] = true
            _input.mouse_pressed[b] = true
        }
    case .MOUSE_UP:
        b := int(e.mouse_button)
        if b >= 0 && b < len(_input.mouse_down) {
            _input.mouse_down[b] = false
            _input.mouse_released[b] = true
        }
    case .MOUSE_MOVE:
        _input.mouse_pos = { e.mouse_x, e.mouse_y }
        _input.mouse_delta += { e.mouse_dx, e.mouse_dy }
    case .MOUSE_SCROLL:
        _input.wheel += { e.scroll_x, e.scroll_y }
    case .RESIZED:
        _app.resized = true
    case .FOCUSED:
        _app.focused = true
    case .UNFOCUSED:
        _app.focused = false
        // Otherwise keys held when the window loses focus stay down forever.
        _input.down = {}
        _input.mouse_down = {}
    case .QUIT_REQUESTED:
        // sokol does not guarantee cleanup_cb runs, so shut down here, where we know it does.
        _shutdown_once()
    }
}

@(private)
_input_end_frame :: proc() {
    _input.pressed  = {}
    _input.released = {}
    _input.mouse_pressed  = {}
    _input.mouse_released = {}
    _input.mouse_delta = {}
    _input.wheel = {}
    _input.key_count, _input.key_read = 0, 0
    _input.char_count, _input.char_read = 0, 0
}

@(private) _b_key_down     :: proc(k: Key) -> bool { i := int(k); return i >= 0 && i < len(_input.down) && _input.down[i] }
@(private) _b_key_pressed  :: proc(k: Key) -> bool { i := int(k); return i >= 0 && i < len(_input.pressed) && _input.pressed[i] }
@(private) _b_key_released :: proc(k: Key) -> bool { i := int(k); return i >= 0 && i < len(_input.released) && _input.released[i] }

@(private)
_b_key_queue :: proc() -> Key {
    if _input.key_read >= _input.key_count { return .KEY_NULL }
    k := _input.key_queue[_input.key_read]
    _input.key_read += 1
    return k
}

@(private)
_b_char_queue :: proc() -> rune {
    if _input.char_read >= _input.char_count { return 0 }
    r := _input.char_queue[_input.char_read]
    _input.char_read += 1
    return r
}

@(private) _b_mouse_pos   :: proc() -> Vec2 { return _input.mouse_pos }
@(private) _b_mouse_delta :: proc() -> Vec2 { return _input.mouse_delta }
@(private) _b_mouse_wheel :: proc() -> f32  { return _input.wheel.y if abs(_input.wheel.y) >= abs(_input.wheel.x) else _input.wheel.x }

@(private) _b_mouse_down     :: proc(b: MouseButton) -> bool { i := int(b); return i >= 0 && i < len(_input.mouse_down) && _input.mouse_down[i] }
@(private) _b_mouse_pressed  :: proc(b: MouseButton) -> bool { i := int(b); return i >= 0 && i < len(_input.mouse_pressed) && _input.mouse_pressed[i] }
@(private) _b_mouse_released :: proc(b: MouseButton) -> bool { i := int(b); return i >= 0 && i < len(_input.mouse_released) && _input.mouse_released[i] }

// Scroll on both axes, for ImGui.
mouse_wheel_xy :: proc() -> Vec2 { return 0 if !real_input_enabled() else _input.wheel }

// Modifier state, for ImGui.
key_modifiers :: proc() -> (ctrl, shift, alt, super: bool) {
    if !real_input_enabled() { return }
    ctrl  = _b_key_down(.LEFT_CONTROL) || _b_key_down(.RIGHT_CONTROL)
    shift = _b_key_down(.LEFT_SHIFT)   || _b_key_down(.RIGHT_SHIFT)
    alt   = _b_key_down(.LEFT_ALT)     || _b_key_down(.RIGHT_ALT)
    super = _b_key_down(.LEFT_SUPER)   || _b_key_down(.RIGHT_SUPER)
    return
}

// ---- time ------------------------------------------------------------------------------------

@(private) _b_time       :: proc() -> f64 { return stm.sec(stm.now()) }
@(private) _b_frame_time :: proc() -> f32 { return f32(sapp.frame_duration()) }
@(private) _b_set_fps    :: proc(fps: i32) { /* vsync paces the frame; see decision D2 */ }

// ---- window ----------------------------------------------------------------------------------

@(private) _b_window_init          :: proc(w, h: i32, title: cstring, fullscreen: bool) { /* sapp.run owns creation */ }
@(private) _b_window_close         :: proc() { sapp.request_quit() }
@(private) _b_window_should_close  :: proc() -> bool { return _app.quit_wanted }
@(private) _b_window_is_fullscreen :: proc() -> bool { return sapp.is_fullscreen() }
@(private) _b_window_toggle_fullscreen :: proc() { sapp.toggle_fullscreen() }
@(private) _b_window_resized :: proc() -> bool { return _app.resized }

@(private) _b_screen_width  :: proc() -> i32 { return sapp.width() }
@(private) _b_screen_height :: proc() -> i32 { return sapp.height() }
@(private) _b_render_width  :: proc() -> i32 { return sapp.width() }
@(private) _b_render_height :: proc() -> i32 { return sapp.height() }
@(private) _b_dpi_scale     :: proc() -> f32 { return sapp.dpi_scale() }
@(private) _b_window_focused :: proc() -> bool { return _app.focused }

@(private) _b_clipboard_text     :: proc "c" () -> cstring { return sapp.get_clipboard_string() }
@(private) _b_set_clipboard_text :: proc "c" (text: cstring) { sapp.set_clipboard_string(text) }

@(private)
_b_set_mouse_cursor :: proc(c: Cursor) {
    cursor: sapp.Mouse_Cursor
    switch c {
    case .Default:     cursor = .DEFAULT
    case .Text:        cursor = .IBEAM
    case .Resize_All:  cursor = .RESIZE_ALL
    case .Resize_NS:   cursor = .RESIZE_NS
    case .Resize_EW:   cursor = .RESIZE_EW
    case .Resize_NESW: cursor = .RESIZE_NESW
    case .Resize_NWSE: cursor = .RESIZE_NWSE
    case .Hand:        cursor = .POINTING_HAND
    case .Not_Allowed: cursor = .NOT_ALLOWED
    }
    sapp.set_mouse_cursor(cursor)
}

@(private) _b_window_handle :: proc() -> rawptr {
    when ODIN_OS == .Darwin { return sapp.macos_get_window() }
    else                    { return nil }
}

@(private)
_b_set_window_icon :: proc(img: Image) {
    // sokol takes icon pixels at creation; sapp.set_icon can update them later.
    pixels := img.pixels
    desc: sapp.Icon_Desc
    desc.images[0] = { width = img.width, height = img.height, pixels = { ptr = raw_data(pixels), size = c.size_t(len(pixels)) } }
    sapp.set_icon(desc)
}

// ---- GPU state -------------------------------------------------------------------------------

MAIN_FORMAT :: sg.Pixel_Format.RGBA8

@(private) _gl: struct {
    ctx:          sgl.Context,   // everything offscreen, including the main target
    pip_alpha:    sgl.Pipeline,
    pip_additive: sgl.Pipeline,
    pip_opaque:   sgl.Pipeline,
    present_smp:  sg.Sampler,
    smp_point:    sg.Sampler,
    smp_linear:   sg.Sampler,
    smp_clamp:    sg.Sampler,
    white:        Texture,
    main:         RenderTexture,
    main_w, main_h: i32,
}

@(private)
_gl_setup :: proc() {
    _gl.ctx = sgl.make_context({
        max_vertices = 1 << 18,
        max_commands = 1 << 16,
        color_format = MAIN_FORMAT,
        depth_format = .NONE,
        sample_count = 1,
    })

    // sokol_gl turns a DEFAULT write mask into RGB, which would leave every offscreen target
    // transparent. Alpha blending matches raylib's: the same factors for colour and alpha.
    blend_alpha := sg.Blend_State{
        enabled = true,
        src_factor_rgb = .SRC_ALPHA, dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        src_factor_alpha = .SRC_ALPHA, dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
    }
    blend_add := sg.Blend_State{
        enabled = true,
        src_factor_rgb = .SRC_ALPHA, dst_factor_rgb = .ONE,
        src_factor_alpha = .SRC_ALPHA, dst_factor_alpha = .ONE,
    }
    _gl.pip_alpha    = sgl.context_make_pipeline(_gl.ctx, { colors = { 0 = { write_mask = .RGBA, blend = blend_alpha } } })
    _gl.pip_additive = sgl.context_make_pipeline(_gl.ctx, { colors = { 0 = { write_mask = .RGBA, blend = blend_add } } })
    _gl.pip_opaque   = sgl.context_make_pipeline(_gl.ctx, { colors = { 0 = { write_mask = .RGBA } } })

    _gl.smp_point  = sg.make_sampler({ min_filter = .NEAREST, mag_filter = .NEAREST, wrap_u = .REPEAT, wrap_v = .REPEAT })
    _gl.smp_linear = sg.make_sampler({ min_filter = .LINEAR,  mag_filter = .LINEAR,  wrap_u = .REPEAT, wrap_v = .REPEAT })
    _gl.smp_clamp  = sg.make_sampler({ min_filter = .LINEAR,  mag_filter = .LINEAR,  wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE })
    _gl.present_smp = _gl.smp_point

    white := [4]u8{ 255, 255, 255, 255 }
    _gl.white = _make_texture(white[:], 1, 1, _gl.smp_point)
}

@(private)
_ensure_main_target :: proc() {
    w, h := max(sapp.width(), 1), max(sapp.height(), 1)
    if _gl.main.id != 0 && _gl.main_w == w && _gl.main_h == h { return }
    if _gl.main.id != 0 { _b_unload_render_texture(_gl.main) }
    _gl.main = _b_load_render_texture(w, h)
    _gl.main_w, _gl.main_h = w, h
}

@(private)
_make_texture :: proc(pixels: []u8, w, h: i32, smp: sg.Sampler) -> Texture {
    img := sg.make_image({
        width        = w,
        height       = h,
        pixel_format = .RGBA8,
        usage        = { copy_dst = true },
        data         = { ptr = raw_data(pixels), size = c.size_t(len(pixels)) },
    })
    view := sg.make_view({ texture = { image = img } })
    return { id = img.id, width = w, height = h, _h = { img = img, view = view, smp = smp } }
}

// ---- the frame recorder ------------------------------------------------------------------------

@(private)
Custom_Kind :: enum { Directional, Sprite_Light, Fog, User }

@(private)
Custom_Item :: struct {
    kind:   Custom_Kind,
    blend:  BlendMode,
    tex:    [3]Texture,
    dir:    Directional_GPU,
    sprite: Sprite_GPU,
    fog:    Fog_GPU,
    fn:     proc(user: rawptr),
    user:   rawptr,
}

@(private)
Item :: struct {
    layer:  i32,          // sokol_gl layer, when custom is not set
    custom: Maybe(Custom_Item),
}

@(private)
Segment :: struct {
    target: RenderTexture, // id 0 means the main target
    clear:  Maybe(Color),
    drawn:  bool,
    items:  [dynamic]Item,
}

@(private) _rec: struct {
    segments:  [dynamic]Segment,
    stack:     [dynamic]RenderTexture,
    layer:     i32,
    recording: bool,
}

@(private)
_cur_segment :: proc() -> ^Segment {
    if len(_rec.segments) == 0 { _open_segment({}, nil) }
    return &_rec.segments[len(_rec.segments) - 1]
}

@(private)
_open_segment :: proc(target: RenderTexture, clear: Maybe(Color)) {
    append(&_rec.segments, Segment{ target = target, clear = clear })
    seg := &_rec.segments[len(_rec.segments) - 1]
    _rec.layer += 1
    append(&seg.items, Item{ layer = _rec.layer })
    _begin_layer(target)
}

// Starts recording sokol_gl commands for the current layer, with a projection matching the target.
@(private)
_begin_layer :: proc(target: RenderTexture) {
    w := f32(target.texture.width) if target.id != 0 else f32(max(sapp.width(), 1))
    h := f32(target.texture.height) if target.id != 0 else f32(max(sapp.height(), 1))
    sgl.set_context(_gl.ctx)
    sgl.layer(_rec.layer)
    sgl.defaults()
    sgl.load_pipeline(_gl.pip_alpha)
    sgl.matrix_mode_projection()
    sgl.ortho(0, w, h, 0, -1, 1)
    sgl.matrix_mode_modelview()
}

// Splits the current layer so something that is not a sokol_gl draw can run in between.
@(private)
_push_custom :: proc(item: Custom_Item) {
    seg := _cur_segment()
    append(&seg.items, Item{ custom = item })
    seg.drawn = true
    _rec.layer += 1
    append(&seg.items, Item{ layer = _rec.layer })
    _begin_layer(seg.target)
}

@(private) _mark_drawn :: proc() { _cur_segment().drawn = true }

// Records a draw that needs its own pipeline, to run inside whichever pass it belongs to. The
// callback runs during frame_end, inside an active sokol pass, and may issue sg calls freely.
// ImGui uses this; the lighting passes have their own kinds.
record_draw :: proc(fn: proc(user: rawptr), user: rawptr) {
    _push_custom({ kind = .User, fn = fn, user = user })
}

@(private)
_b_frame_begin :: proc() {
    _drain_graveyard()
    _ensure_main_target()
    for &seg in _rec.segments { delete(seg.items) }
    // `clear` here is this package's screen clear, so resize to empty instead.
    resize(&_rec.segments, 0)
    resize(&_rec.stack, 0)
    _rec.layer = 0
    _rec.recording = true
    _open_segment({}, nil)
}

@(private)
_b_clear :: proc(col: Color) {
    seg := _cur_segment()
    if !seg.drawn {
        seg.clear = col
        return
    }
    // Nothing in the game does this today; cover it anyway with an opaque full-target quad.
    w := f32(seg.target.texture.width) if seg.target.id != 0 else f32(sapp.width())
    h := f32(seg.target.texture.height) if seg.target.id != 0 else f32(sapp.height())
    sgl.load_pipeline(_gl.pip_opaque)
    _quad(0, 0, w, h, col)
    sgl.load_pipeline(_gl.pip_alpha)
}

@(private)
_b_target_begin :: proc(rt: RenderTexture) {
    append(&_rec.stack, _cur_segment().target)
    _open_segment(rt, nil)
}

@(private)
_b_target_end :: proc() {
    prev: RenderTexture
    if len(_rec.stack) > 0 {
        prev = pop(&_rec.stack)
    }
    _open_segment(prev, nil)  // reopened with no clear: the pass loads what is already there
}

@(private)
_b_frame_end :: proc() {
    _rec.recording = false
    _text_upload_atlas()

    for &seg in _rec.segments {
        pass: sg.Pass
        if col, has := seg.clear.?; has {
            pass.action.colors[0] = {
                load_action = .CLEAR,
                clear_value = { f32(col.r) / 255, f32(col.g) / 255, f32(col.b) / 255, f32(col.a) / 255 },
            }
        } else {
            pass.action.colors[0] = { load_action = .LOAD }
        }
        target := seg.target if seg.target.id != 0 else _gl.main
        pass.attachments.colors[0] = target._h.attach

        sg.begin_pass(pass)
        for &item in seg.items {
            if custom, has := item.custom.?; has {
                _draw_custom(custom)
            } else {
                sgl.context_draw_layer(_gl.ctx, item.layer)
            }
        }
        sg.end_pass()
    }

    // Present: the main target, drawn once into the swapchain through the default context, which
    // matches the swapchain's pixel format.
    sw, sh := f32(max(sapp.width(), 1)), f32(max(sapp.height(), 1))
    sgl.set_context(sgl.default_context())
    sgl.defaults()
    sgl.matrix_mode_projection()
    sgl.ortho(0, sw, sh, 0, -1, 1)
    sgl.enable_texture()
    sgl.texture(_gl.main.texture._h.view, _gl.present_smp)
    sgl.begin_quads()
    sgl.v2f_t2f_c4b(0,  0,  0, 0, 255, 255, 255, 255)
    sgl.v2f_t2f_c4b(sw, 0,  1, 0, 255, 255, 255, 255)
    sgl.v2f_t2f_c4b(sw, sh, 1, 1, 255, 255, 255, 255)
    sgl.v2f_t2f_c4b(0,  sh, 0, 1, 255, 255, 255, 255)
    sgl.end()
    sgl.disable_texture()

    sg.begin_pass({ action = { colors = { 0 = { load_action = .CLEAR, clear_value = { 0, 0, 0, 1 } } } }, swapchain = sglue.swapchain() })
    sgl.context_draw(sgl.default_context())
    sg.end_pass()
    sg.commit()

    if _capture.pending { _capture_run() }
}

// ---- 2D drawing ---------------------------------------------------------------------------------

@(private)
_quad :: proc(x, y, w, h: f32, col: Color) {
    sgl.begin_quads()
    sgl.v2f_c4b(x,     y,     col.r, col.g, col.b, col.a)
    sgl.v2f_c4b(x + w, y,     col.r, col.g, col.b, col.a)
    sgl.v2f_c4b(x + w, y + h, col.r, col.g, col.b, col.a)
    sgl.v2f_c4b(x,     y + h, col.r, col.g, col.b, col.a)
    sgl.end()
    _mark_drawn()
}

@(private)
_tri :: proc(a, b, c: Vec2, col: Color) {
    sgl.begin_triangles()
    sgl.v2f_c4b(a.x, a.y, col.r, col.g, col.b, col.a)
    sgl.v2f_c4b(b.x, b.y, col.r, col.g, col.b, col.a)
    sgl.v2f_c4b(c.x, c.y, col.r, col.g, col.b, col.a)
    sgl.end()
    _mark_drawn()
}

// A thick line as a quad, matching raylib's DrawLineEx.
@(private)
_thick_line :: proc(a, b: Vec2, thick: f32, col: Color) {
    dx, dy := b.x - a.x, b.y - a.y
    len_sq := dx*dx + dy*dy
    if len_sq <= 0 { return }
    inv := 1.0 / _sqrt(len_sq)
    nx, ny := -dy * inv * thick * 0.5, dx * inv * thick * 0.5
    sgl.begin_quads()
    sgl.v2f_c4b(a.x + nx, a.y + ny, col.r, col.g, col.b, col.a)
    sgl.v2f_c4b(b.x + nx, b.y + ny, col.r, col.g, col.b, col.a)
    sgl.v2f_c4b(b.x - nx, b.y - ny, col.r, col.g, col.b, col.a)
    sgl.v2f_c4b(a.x - nx, a.y - ny, col.r, col.g, col.b, col.a)
    sgl.end()
    _mark_drawn()
}

@(private)
_sqrt :: proc(v: f32) -> f32 {
    // core:math is not imported here to keep the backend's dependencies small.
    x := v
    if x <= 0 { return 0 }
    g := x
    for _ in 0..<12 { g = 0.5 * (g + x / g) }
    return g
}

// raylib picked a segment count from the radius; match it so circles look the same.
@(private)
_circle_segments :: proc(radius: f32) -> int {
    return clamp(int(radius * 0.5) + 12, 12, 64)
}

@(private)
_b_draw_rect :: proc(x, y, w, h: i32, col: Color) { _quad(f32(x), f32(y), f32(w), f32(h), col) }
@(private) _b_draw_rect_rec :: proc(r: Rect, col: Color) { _quad(r.x, r.y, r.width, r.height, col) }
@(private) _b_draw_rect_v :: proc(pos, size: Vec2, col: Color) { _quad(pos.x, pos.y, size.x, size.y, col) }

@(private)
_b_draw_rect_lines :: proc(r: Rect, thick: f32, col: Color) {
    t := max(thick, 0.1)
    _quad(r.x, r.y, r.width, t, col)
    _quad(r.x, r.y + r.height - t, r.width, t, col)
    _quad(r.x, r.y + t, t, r.height - t * 2, col)
    _quad(r.x + r.width - t, r.y + t, t, r.height - t * 2, col)
}

@(private)
_b_draw_rect_rounded :: proc(r: Rect, roundness: f32, segments: i32, col: Color) {
    rad := clamp(roundness, 0, 1) * min(r.width, r.height) * 0.5
    if rad <= 0.5 {
        _quad(r.x, r.y, r.width, r.height, col)
        return
    }
    _quad(r.x + rad, r.y, r.width - rad * 2, r.height, col)
    _quad(r.x, r.y + rad, rad, r.height - rad * 2, col)
    _quad(r.x + r.width - rad, r.y + rad, rad, r.height - rad * 2, col)
    n := max(int(segments), 4)
    corners := [4]Vec2{
        { r.x + rad,            r.y + rad },
        { r.x + r.width - rad,  r.y + rad },
        { r.x + r.width - rad,  r.y + r.height - rad },
        { r.x + rad,            r.y + r.height - rad },
    }
    starts := [4]f32{ 180, 270, 0, 90 }
    for ci in 0..<4 {
        _arc_fan(corners[ci], rad, starts[ci], starts[ci] + 90, n, col)
    }
}

@(private)
_arc_fan :: proc(center: Vec2, radius, a0_deg, a1_deg: f32, segments: int, col: Color) {
    if radius <= 0 || segments <= 0 { return }
    step := (a1_deg - a0_deg) / f32(segments)
    for i in 0..<segments {
        a := a0_deg + step * f32(i)
        b := a + step
        _tri(center, _polar(center, radius, a), _polar(center, radius, b), col)
    }
}

@(private)
_polar :: proc(center: Vec2, radius, deg: f32) -> Vec2 {
    r := deg * 0.017453292
    return { center.x + _cos(r) * radius, center.y + _sin(r) * radius }
}

@(private)
_sin :: proc(x: f32) -> f32 {
    // Minimal sine for circle tessellation: wrap to [-pi, pi] and use a 7th-order polynomial.
    TAU :: 6.2831853
    PI  :: 3.14159265
    v := x
    for v >  PI { v -= TAU }
    for v < -PI { v += TAU }
    v2 := v * v
    return v * (1 - v2/6 + v2*v2/120 - v2*v2*v2/5040)
}
@(private) _cos :: proc(x: f32) -> f32 { return _sin(x + 1.57079633) }

@(private)
_b_draw_circle :: proc(x, y: i32, radius: f32, col: Color) {
    _arc_fan({ f32(x), f32(y) }, radius, 0, 360, _circle_segments(radius), col)
}
@(private)
_b_draw_circle_v :: proc(center: Vec2, radius: f32, col: Color) {
    _arc_fan(center, radius, 0, 360, _circle_segments(radius), col)
}

@(private)
_ring_outline :: proc(center: Vec2, radius, thick: f32, col: Color) {
    n := _circle_segments(radius)
    step := 360.0 / f32(n)
    for i in 0..<n {
        a := _polar(center, radius, step * f32(i))
        b := _polar(center, radius, step * f32(i + 1))
        _thick_line(a, b, thick, col)
    }
}

@(private) _b_draw_circle_lines   :: proc(x, y: i32, radius: f32, col: Color) { _ring_outline({ f32(x), f32(y) }, radius, 1, col) }
@(private) _b_draw_circle_lines_v :: proc(center: Vec2, radius: f32, col: Color) { _ring_outline(center, radius, 1, col) }

@(private)
_ellipse_fan :: proc(center: Vec2, rh, rv: f32, col: Color, outline: bool) {
    n := _circle_segments(max(rh, rv))
    step := 360.0 / f32(n)
    prev := Vec2{ center.x + rh, center.y }
    for i in 1..=n {
        a := step * f32(i) * 0.017453292
        p := Vec2{ center.x + _cos(a) * rh, center.y + _sin(a) * rv }
        if outline { _thick_line(prev, p, 1, col) } else { _tri(center, prev, p, col) }
        prev = p
    }
}

@(private) _b_draw_ellipse       :: proc(x, y: i32, rh, rv: f32, col: Color) { _ellipse_fan({ f32(x), f32(y) }, rh, rv, col, false) }
@(private) _b_draw_ellipse_lines :: proc(x, y: i32, rh, rv: f32, col: Color) { _ellipse_fan({ f32(x), f32(y) }, rh, rv, col, true) }

@(private)
_b_draw_ring :: proc(center: Vec2, inner, outer, a0, a1: f32, segments: i32, col: Color) {
    n := max(int(segments), 4)
    step := (a1 - a0) / f32(n)
    for i in 0..<n {
        p0 := _polar(center, outer, a0 + step * f32(i))
        p1 := _polar(center, outer, a0 + step * f32(i + 1))
        q0 := _polar(center, inner, a0 + step * f32(i))
        q1 := _polar(center, inner, a0 + step * f32(i + 1))
        sgl.begin_quads()
        sgl.v2f_c4b(q0.x, q0.y, col.r, col.g, col.b, col.a)
        sgl.v2f_c4b(p0.x, p0.y, col.r, col.g, col.b, col.a)
        sgl.v2f_c4b(p1.x, p1.y, col.r, col.g, col.b, col.a)
        sgl.v2f_c4b(q1.x, q1.y, col.r, col.g, col.b, col.a)
        sgl.end()
    }
    _mark_drawn()
}

@(private) _b_draw_line    :: proc(x1, y1, x2, y2: i32, col: Color) { _thick_line({ f32(x1), f32(y1) }, { f32(x2), f32(y2) }, 1, col) }
@(private) _b_draw_line_v  :: proc(a, b: Vec2, col: Color)          { _thick_line(a, b, 1, col) }
@(private) _b_draw_line_ex :: proc(a, b: Vec2, thick: f32, col: Color) { _thick_line(a, b, thick, col) }

@(private) _b_draw_triangle       :: proc(a, b, c: Vec2, col: Color) { _tri(a, b, c, col) }
@(private)
_b_draw_triangle_lines :: proc(a, b, c: Vec2, col: Color) {
    _thick_line(a, b, 1, col); _thick_line(b, c, 1, col); _thick_line(c, a, 1, col)
}
@(private) _b_draw_pixel :: proc(x, y: i32, col: Color) { _quad(f32(x), f32(y), 1, 1, col) }

// ---- camera, blend, scissor -------------------------------------------------------------------

@(private)
_b_camera_begin :: proc(cam: Camera2D) {
    sgl.matrix_mode_modelview()
    sgl.push_matrix()
    sgl.translate(cam.offset.x, cam.offset.y, 0)
    sgl.scale(cam.zoom, cam.zoom, 1)
    if cam.rotation != 0 { sgl.rotate(cam.rotation * 0.017453292, 0, 0, 1) }
    sgl.translate(-cam.target.x, -cam.target.y, 0)
}
@(private)
_b_camera_end :: proc() {
    sgl.matrix_mode_modelview()
    sgl.pop_matrix()
}

@(private)
_b_blend_begin :: proc(mode: BlendMode) {
    sgl.load_pipeline(_gl.pip_additive if mode == .Additive else _gl.pip_alpha)
}
@(private) _b_blend_end :: proc() { sgl.load_pipeline(_gl.pip_alpha) }

@(private)
_b_scissor_begin :: proc(x, y, w, h: i32) {
    sgl.scissor_rect(x, y, max(w, 0), max(h, 0), true)
}
@(private)
_b_scissor_end :: proc() {
    seg := _cur_segment()
    w := seg.target.texture.width if seg.target.id != 0 else sapp.width()
    h := seg.target.texture.height if seg.target.id != 0 else sapp.height()
    sgl.scissor_rect(0, 0, w, h, true)
}

// ---- textures ------------------------------------------------------------------------------

@(private)
_b_draw_texture_pro :: proc(t: Texture, src, dst: Rect, origin: Vec2, rotation: f32, tint: Color) {
    if t.id == 0 { return }
    uv0 := texture_uv(t, src.x, src.y)
    uv1 := texture_uv(t, src.x + src.width, src.y + src.height)

    sgl.enable_texture()
    sgl.texture(t._h.view, _sampler_for(t))
    sgl.push_matrix()
    sgl.translate(dst.x, dst.y, 0)
    if rotation != 0 { sgl.rotate(rotation * 0.017453292, 0, 0, 1) }
    sgl.translate(-origin.x, -origin.y, 0)
    sgl.begin_quads()
    sgl.v2f_t2f_c4b(0,         0,          uv0.x, uv0.y, tint.r, tint.g, tint.b, tint.a)
    sgl.v2f_t2f_c4b(dst.width, 0,          uv1.x, uv0.y, tint.r, tint.g, tint.b, tint.a)
    sgl.v2f_t2f_c4b(dst.width, dst.height, uv1.x, uv1.y, tint.r, tint.g, tint.b, tint.a)
    sgl.v2f_t2f_c4b(0,         dst.height, uv0.x, uv1.y, tint.r, tint.g, tint.b, tint.a)
    sgl.end()
    sgl.pop_matrix()
    sgl.disable_texture()
    _mark_drawn()
}

@(private)
_b_draw_texture_ex :: proc(t: Texture, pos: Vec2, rotation, scale: f32, tint: Color) {
    src := Rect{ 0, 0, f32(t.width), f32(t.height) }
    dst := Rect{ pos.x, pos.y, f32(t.width) * scale, f32(t.height) * scale }
    _b_draw_texture_pro(t, src, dst, { 0, 0 }, rotation, tint)
}

@(private)
_b_load_texture :: proc(path: cstring) -> Texture {
    w, h, comp: c.int
    pixels := stbi.load(path, &w, &h, &comp, 4)
    if pixels == nil { return {} }
    defer stbi.image_free(pixels)
    return _make_texture(pixels[:int(w) * int(h) * 4], w, h, _gl.smp_point)
}

@(private)
_b_load_texture_pixels :: proc(pixels: []u8, w, h: i32) -> Texture {
    return _make_texture(pixels, w, h, _gl.smp_point)
}

@(private)
_b_update_texture :: proc(t: Texture, pixels: []u8) {
    if t.id == 0 { return }
    _upload_pixels(t._h.img, pixels, t.width, t.height)
}

// Uploads whole-image pixels through a staging buffer, which is how sokol takes CPU data now.
@(private)
_upload_pixels :: proc(img: sg.Image, pixels: []u8, w, h: i32) {
    staging := sg.make_buffer({
        usage = { staging_buffer = true, write_transient = true, copy_src = true },
        size  = c.size_t(len(pixels)),
    })
    defer sg.destroy_buffer(staging)
    sg.write_buffer_transient({ src = { data = { ptr = raw_data(pixels), size = c.size_t(len(pixels)) } }, dst = { buffer = staging } })
    sg.copy_buffer_to_image({
        src  = { buffer = staging, bytes_per_row = w * 4, bytes_per_slice = w * h * 4 },
        dst  = { image = img },
        size = { width = w, height = h, num_slices = 1 },
    })
}

// Resources are destroyed at the start of the next frame, never in the middle of one.
//
// Draws are recorded and replayed at frame_end, so a view freed mid-frame would still be
// referenced by draws recorded before it (the wall mask is rebuilt between the sprite composite
// and the fog pass, and render targets are recreated on resize). Deferring also matches what the
// immediate-mode backend did: a draw issued before the swap kept the old contents.
@(private) _graveyard: struct {
    images: [dynamic]sg.Image,
    views:  [dynamic]sg.View,
}

@(private)
_drain_graveyard :: proc() {
    for v in _graveyard.views  { sg.destroy_view(v) }
    for i in _graveyard.images { sg.destroy_image(i) }
    resize(&_graveyard.views, 0)
    resize(&_graveyard.images, 0)
}

@(private)
_b_unload_texture :: proc(t: Texture) {
    if t.id == 0 { return }
    append(&_graveyard.views, t._h.view)
    append(&_graveyard.images, t._h.img)
    delete_key(&_sampler_overrides, t.id)
}

@(private)
_b_texture_set_filter :: proc(t: Texture, f: TextureFilter) {
    // Samplers are immutable in sokol, so this swaps which one the texture uses. Mipmaps are not
    // generated: the only user was the font atlas, and fontstash rasterizes at the real size.
    tex := t
    tex._h.smp = _gl.smp_point if f == .Point else _gl.smp_linear
    _patch_texture(tex)
}

@(private)
_b_texture_set_wrap :: proc(t: Texture, w: TextureWrap) {
    tex := t
    if w == .Clamp { tex._h.smp = _gl.smp_clamp }
    _patch_texture(tex)
}

// Textures are values in game code, so a sampler change has to be written back through the
// registry that maps image ids to their current sampler.
@(private) _sampler_overrides: map[u32]sg.Sampler

@(private)
_patch_texture :: proc(t: Texture) {
    _sampler_overrides[t.id] = t._h.smp
}

@(private)
_sampler_for :: proc(t: Texture) -> sg.Sampler {
    if smp, has := _sampler_overrides[t.id]; has { return smp }
    return t._h.smp
}

@(private)
_b_load_render_texture :: proc(w, h: i32) -> RenderTexture {
    img := sg.make_image({
        usage        = { color_attachment = true },
        width        = max(w, 1),
        height       = max(h, 1),
        pixel_format = MAIN_FORMAT,
        sample_count = 1,
    })
    attach := sg.make_view({ color_attachment = { image = img } })
    view   := sg.make_view({ texture = { image = img } })
    tex := Texture{
        id = img.id, width = max(w, 1), height = max(h, 1),
        // sokol render targets sample upright, unlike raylib's.
        flipped = false,
        _h = { img = img, view = view, smp = _gl.smp_point },
    }
    return { id = img.id, texture = tex, _h = { img = img, attach = attach } }
}

@(private)
_b_unload_render_texture :: proc(rt: RenderTexture) {
    if rt.id == 0 { return }
    append(&_graveyard.views, rt._h.attach)
    append(&_graveyard.views, rt.texture._h.view)
    append(&_graveyard.images, rt._h.img)
}

// ---- images --------------------------------------------------------------------------------

@(private)
_b_load_image :: proc(path: cstring) -> (Image, bool) {
    w, h, comp: c.int
    pixels := stbi.load(path, &w, &h, &comp, 4)
    if pixels == nil { return {}, false }
    defer stbi.image_free(pixels)
    n := int(w) * int(h) * 4
    out := make([]u8, n)
    copy(out, pixels[:n])
    return { pixels = out, width = w, height = h }, true
}

// ---- immediate-mode quads --------------------------------------------------------------------

@(private)
_b_quads_begin :: proc(tex: Texture, textured: bool) {
    if textured && tex.id != 0 {
        sgl.enable_texture()
        sgl.texture(tex._h.view, _sampler_for(tex))
    } else {
        sgl.disable_texture()
    }
    sgl.begin_quads()
}
@(private) _b_quads_end :: proc() { sgl.end(); sgl.disable_texture(); _mark_drawn() }

@(private) _quad_col: Color = { 255, 255, 255, 255 }
@(private) _quad_uv_cur: Vec2

@(private)
_b_tris_begin :: proc(tex: Texture, textured: bool) {
    if textured && tex.id != 0 {
        sgl.enable_texture()
        sgl.texture(tex._h.view, _sampler_for(tex))
    } else {
        sgl.disable_texture()
    }
    sgl.begin_triangles()
}
@(private) _b_tris_end :: proc() { sgl.end(); sgl.disable_texture(); _mark_drawn() }
@(private)
_b_tri_vertex :: proc(p, uv: Vec2, col: Color) {
    sgl.v2f_t2f_c4b(p.x, p.y, uv.x, uv.y, col.r, col.g, col.b, col.a)
}

@(private) _b_quad_color  :: proc(col: Color) { _quad_col = col }
@(private) _b_quad_uv     :: proc(u, v: f32)  { _quad_uv_cur = { u, v } }
@(private)
_b_quad_vertex :: proc(p: Vec2) {
    sgl.v2f_t2f_c4b(p.x, p.y, _quad_uv_cur.x, _quad_uv_cur.y, _quad_col.r, _quad_col.g, _quad_col.b, _quad_col.a)
}

// ---- screenshots ------------------------------------------------------------------------------

@(private) _capture: struct {
    pending: bool,
    path:    string,
}

@(private)
_b_screenshot :: proc(path: cstring) -> bool {
    _capture.pending = true
    _capture.path = strings.clone(string(path))
    return true
}

@(private)
_capture_run :: proc() {
    defer {
        delete(_capture.path)
        _capture.pending = false
    }
    w, h := _gl.main_w, _gl.main_h
    pixels := make([]u8, int(w) * int(h) * 4)
    defer delete(pixels)
    if !_read_target_rgba8(_gl.main._h.img, w, h, pixels) {
        fmt.eprintln("[gfx] screenshot readback failed")
        return
    }
    cpath := strings.clone_to_cstring(_capture.path, context.temp_allocator)
    if stbi.write_png(cpath, w, h, 4, raw_data(pixels), w * 4) == 0 {
        fmt.eprintln("[gfx] failed to write", _capture.path)
    }
}

_ :: os
