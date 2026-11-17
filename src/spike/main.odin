// P1a step 1: sokol spike (docs/BUILD_PLAN.md). Throwaway: proves the toolchain and the patterns
// the real `gfx` backend will use, in isolation from the game. Delete once P1a step 7 lands.
//
// What it exercises, in the same pass order as the game's draw_playing (main.odin):
//   world RT -> main target -> sprite RT -> main target again -> present
//   - sokol_gl as the immediate-mode batcher, with one *layer per pass*, so draw calls can be
//     recorded in game order and replayed into whichever sokol pass they belong to
//   - an offscreen "main" target standing in for raylib's backbuffer, since sokol can't return to
//     the swapchain mid-frame; it is presented once, at the end
//   - render-target sampling with no y-flip (Metal/D3D11 have a top-left origin)
//   - a texture loaded with stb_image
//   - fontstash text, its atlas uploaded through a staging buffer + sg_copy_buffer_to_image
//   - a sokol-shdc shader: the port of data/shaders/point_lights.fs, drawn additively
//   - scissor clipping
//   - screenshot readback through the native Metal helper (sokol_gfx has no readback API)
//
// usage: bin/tormentas_spike [--shot out.png] [--frames N]
//   --shot   save the main target as PNG after N frames (default 10) and quit
//   keys     F11 toggles fullscreen, Esc quits
package spike

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"

import sapp  "sokol:app"
import sg    "sokol:gfx"
import sgl   "sokol:gl"
import sglue "sokol:glue"
import slog  "sokol:log"

import fs   "vendor:fontstash"
import stbi "vendor:stb/image"

when ODIN_OS == .Darwin {
    when ODIN_ARCH == .arm64 {
        foreign import native { "native/capture_metal_arm64.a", "system:Metal.framework", "system:Foundation.framework" }
    } else {
        foreign import native { "native/capture_metal_x64.a", "system:Metal.framework", "system:Foundation.framework" }
    }
    @(default_calling_convention = "c")
    foreign native {
        tormentas_mtl_read_rgba8 :: proc(queue, texture: rawptr, width, height: c.int, out: [^]u8) -> c.int ---
    }
}

ATLAS_SIZE :: 512
FONT_PATH  :: "data/fonts/body.ttf"
SPRITE     :: "data/sprites/entities/enemy_brute.png"

// One sgl layer per pass segment, in frame order.
Layer :: enum c.int {
    World,       // -> world RT
    Main_A,      // -> main target: world composite, shadows
    Sprites,     // -> sprite RT
    Main_B,      // -> main target: sprite composite (point lights are drawn after this)
    Main_UI,     // -> main target: text and UI, on top of the lights
}

Target :: struct {
    img:    sg.Image,
    attach: sg.View, // color attachment view
    tex:    sg.View, // texture view, for sampling
    w, h:   i32,
}

state: struct {
    ctx_rgba:     sgl.Context,  // offscreen targets are RGBA8; the swapchain is BGRA8 on Metal
    pip_alpha:    sgl.Pipeline, // alpha blending, in ctx_rgba
    world, sprite, main: Target,
    smp_linear:   sg.Sampler,
    smp_nearest:  sg.Sampler,

    sprite_tex:   sg.View,
    sprite_w, sprite_h: f32,

    font:         fs.FontContext,
    font_id:      int,
    atlas_img:    sg.Image,
    atlas_tex:    sg.View,
    atlas_w, atlas_h: int,
    staging:      sg.Buffer,
    staging_size: int,
    atlas_rgba:   []u8,

    light_pip:    sg.Pipeline,

    shot_path:    string,
    shot_target:  string, // main (default), world or sprite
    shot_frame:   u64,
    frame:        u64,
}

// ---- targets ---------------------------------------------------------------------------------

make_target :: proc(w, h: i32, label: cstring) -> Target {
    img := sg.make_image({
        usage        = { color_attachment = true },
        width        = w,
        height       = h,
        pixel_format = .RGBA8,
        sample_count = 1,
        label        = label,
    })
    return {
        img    = img,
        attach = sg.make_view({ color_attachment = { image = img } }),
        tex    = sg.make_view({ texture = { image = img } }),
        w      = w,
        h      = h,
    }
}

destroy_target :: proc(t: ^Target) {
    if t.img.id == 0 { return }
    sg.destroy_view(t.attach)
    sg.destroy_view(t.tex)
    sg.destroy_image(t.img)
    t^ = {}
}

ensure_targets :: proc() {
    w, h := sapp.width(), sapp.height()
    if state.main.w == w && state.main.h == h { return }
    destroy_target(&state.world)
    destroy_target(&state.sprite)
    destroy_target(&state.main)
    state.world  = make_target(w, h, "world-rt")
    state.sprite = make_target(w, h, "sprite-rt")
    state.main   = make_target(w, h, "main-rt")
}

target_pass :: proc(t: Target, action: sg.Pass_Action) -> sg.Pass {
    p := sg.Pass{ action = action }
    p.attachments.colors[0] = t.attach
    return p
}

clear_action :: proc(r, g, b, a: f32) -> sg.Pass_Action {
    return { colors = { 0 = { load_action = .CLEAR, clear_value = { r, g, b, a } } } }
}

LOAD_ACTION :: sg.Pass_Action{ colors = { 0 = { load_action = .LOAD } } }

// ---- font atlas ------------------------------------------------------------------------------

make_atlas :: proc(w, h: int) {
    if state.atlas_img.id != 0 {
        sg.destroy_view(state.atlas_tex)
        sg.destroy_image(state.atlas_img)
        sg.destroy_buffer(state.staging)
        delete(state.atlas_rgba)
    }
    state.atlas_w, state.atlas_h = w, h
    state.atlas_img = sg.make_image({
        usage        = { copy_dst = true },
        width        = c.int(w),
        height       = c.int(h),
        pixel_format = .RGBA8,
        label        = "font-atlas",
    })
    state.atlas_tex    = sg.make_view({ texture = { image = state.atlas_img } })
    state.staging_size = w * h * 4
    state.staging      = sg.make_buffer({
        usage = { staging_buffer = true, write_transient = true, copy_src = true },
        size  = c.size_t(state.staging_size),
        label = "font-staging",
    })
    state.atlas_rgba = make([]u8, state.staging_size)
}

// fontstash rasterizes into a 1-channel atlas. Expand the dirty region to white RGBA with
// alpha = coverage, so text renders through sokol_gl's stock pipeline (color * texel).
// Must run outside a pass: sg_copy_* calls are not allowed inside one.
upload_atlas :: proc() {
    if state.font.width != state.atlas_w || state.font.height != state.atlas_h {
        make_atlas(state.font.width, state.font.height)
        state.font.dirtyRect = { 0, 0, f32(state.atlas_w), f32(state.atlas_h) }
    }
    dirty: [4]f32
    if !fs.ValidateTexture(&state.font, &dirty) { return }
    x0, y0 := int(dirty[0]), int(dirty[1])
    x1, y1 := int(dirty[2]), int(dirty[3])
    rw, rh := x1 - x0, y1 - y0
    if rw <= 0 || rh <= 0 { return }

    i := 0
    for y in y0 ..< y1 {
        for x in x0 ..< x1 {
            a := state.font.textureData[y * state.atlas_w + x]
            state.atlas_rgba[i + 0] = 255
            state.atlas_rgba[i + 1] = 255
            state.atlas_rgba[i + 2] = 255
            state.atlas_rgba[i + 3] = a
            i += 4
        }
    }
    sg.write_buffer_transient({
        src = { data = { ptr = raw_data(state.atlas_rgba), size = c.size_t(i) } },
        dst = { buffer = state.staging },
    })
    sg.copy_buffer_to_image({
        src  = { buffer = state.staging, bytes_per_row = c.int(rw * 4), bytes_per_slice = c.int(rw * rh * 4) },
        dst  = { image = state.atlas_img, x = c.int(x0), y = c.int(y0) },
        size = { width = c.int(rw), height = c.int(rh), num_slices = 1 },
    })
}

draw_text :: proc(text: string, x, y, size: f32, col: [4]u8) {
    fs.SetFont(&state.font, state.font_id)
    fs.SetSize(&state.font, size)
    fs.SetAlignVertical(&state.font, .TOP)
    sgl.enable_texture()
    sgl.texture(state.atlas_tex, state.smp_linear)
    sgl.begin_quads()
    it := fs.TextIterInit(&state.font, x, y, text)
    q: fs.Quad
    for fs.TextIterNext(&state.font, &it, &q) {
        sgl.v2f_t2f_c4b(q.x0, q.y0, q.s0, q.t0, col.r, col.g, col.b, col.a)
        sgl.v2f_t2f_c4b(q.x1, q.y0, q.s1, q.t0, col.r, col.g, col.b, col.a)
        sgl.v2f_t2f_c4b(q.x1, q.y1, q.s1, q.t1, col.r, col.g, col.b, col.a)
        sgl.v2f_t2f_c4b(q.x0, q.y1, q.s0, q.t1, col.r, col.g, col.b, col.a)
    }
    sgl.end()
    sgl.disable_texture()
}

// ---- 2D helpers (the shape of the future gfx API) ----------------------------------------------

begin_layer :: proc(l: Layer) {
    sgl.set_context(state.ctx_rgba)
    sgl.layer(c.int(l))
    sgl.defaults()
    sgl.load_pipeline(state.pip_alpha)
    sgl.matrix_mode_projection()
    sgl.ortho(0, f32(state.main.w), f32(state.main.h), 0, -1, 1)
}

rect :: proc(x, y, w, h: f32, col: [4]u8) {
    sgl.begin_quads()
    sgl.v2f_c4b(x,     y,     col.r, col.g, col.b, col.a)
    sgl.v2f_c4b(x + w, y,     col.r, col.g, col.b, col.a)
    sgl.v2f_c4b(x + w, y + h, col.r, col.g, col.b, col.a)
    sgl.v2f_c4b(x,     y + h, col.r, col.g, col.b, col.a)
    sgl.end()
}

textured_rect :: proc(tex: sg.View, smp: sg.Sampler, x, y, w, h: f32, tint := [4]u8{ 255, 255, 255, 255 }) {
    sgl.enable_texture()
    sgl.texture(tex, smp)
    sgl.begin_quads()
    // uv (0,0) is the top-left texel on Metal/D3D11, render targets included: no flip.
    sgl.v2f_t2f_c4b(x,     y,     0, 0, tint.r, tint.g, tint.b, tint.a)
    sgl.v2f_t2f_c4b(x + w, y,     1, 0, tint.r, tint.g, tint.b, tint.a)
    sgl.v2f_t2f_c4b(x + w, y + h, 1, 1, tint.r, tint.g, tint.b, tint.a)
    sgl.v2f_t2f_c4b(x,     y + h, 0, 1, tint.r, tint.g, tint.b, tint.a)
    sgl.end()
    sgl.disable_texture()
}

// ---- point lights (raw sokol_gfx, shdc shader) ----------------------------------------------

Light :: struct { pos: [2]f32, radius, intensity: f32, color: [3]f32 }

draw_point_lights :: proc(lights: []Light) {
    p: Fs_Point_Lights_Params
    p.cam_target_offset = { 0, 0, 0, 0 } // identity camera: world == main-target pixels
    p.cam_zoom_count    = { 1, f32(min(len(lights), 32)), 0, 0 }
    for l, i in lights[:min(len(lights), 32)] {
        p.light_pos_radius[i] = { l.pos.x, l.pos.y, l.radius, l.intensity }
        p.light_color[i]      = { l.color.r, l.color.g, l.color.b, 0 }
    }
    sg.apply_pipeline(state.light_pip)
    sg.apply_uniforms(UB_fs_point_lights_params, { ptr = &p, size = size_of(p) })
    sg.draw(0, 3, 1)
}

// ---- sokol_app callbacks ----------------------------------------------------------------------

init :: proc "c" () {
    context = runtime.default_context()
    sg.setup({ environment = sglue.environment(), logger = { func = slog.func } })
    sgl.setup({ max_vertices = 1 << 16, max_commands = 1 << 14, logger = { func = slog.func } })
    fmt.println("[spike] backend:", sg.query_backend())

    state.ctx_rgba = sgl.make_context({
        max_vertices = 1 << 16, max_commands = 1 << 14,
        color_format = .RGBA8, depth_format = .NONE, sample_count = 1,
    })
    // sokol_gl turns a DEFAULT write mask into RGB (sokol_gl.h, _sgl_init_pipeline), so without an
    // explicit RGBA mask nothing it draws writes alpha. Offscreen targets that get composited later
    // then come out fully transparent.
    state.pip_alpha = sgl.context_make_pipeline(state.ctx_rgba, {
        colors = { 0 = { write_mask = .RGBA, blend = {
            enabled = true,
            src_factor_rgb = .SRC_ALPHA, dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            src_factor_alpha = .ONE,     dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
        } } },
    })
    state.smp_linear  = sg.make_sampler({ min_filter = .LINEAR,  mag_filter = .LINEAR,  wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE })
    state.smp_nearest = sg.make_sampler({ min_filter = .NEAREST, mag_filter = .NEAREST, wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE })

    // Texture via stb_image.
    w, h, n: c.int
    px := stbi.load(SPRITE, &w, &h, &n, 4)
    if px == nil { fmt.eprintln("[spike] failed to load", SPRITE); os.exit(1) }
    img := sg.make_image({ width = w, height = h, pixel_format = .RGBA8, data = { ptr = px, size = c.size_t(w * h * 4) } })
    stbi.image_free(px)
    state.sprite_tex = sg.make_view({ texture = { image = img } })
    state.sprite_w, state.sprite_h = f32(w), f32(h)

    // Text via fontstash.
    fs.Init(&state.font, ATLAS_SIZE, ATLAS_SIZE, .TOPLEFT)
    state.font_id = fs.AddFontPath(&state.font, "body", FONT_PATH)
    make_atlas(ATLAS_SIZE, ATLAS_SIZE)

    // shdc shader, additive like rl.BeginBlendMode(.ADDITIVE) (SRC_ALPHA, ONE).
    state.light_pip = sg.make_pipeline({
        shader = sg.make_shader(point_lights_shader_desc(sg.query_backend())),
        colors = { 0 = {
            pixel_format = .RGBA8,
            blend = {
                enabled = true,
                src_factor_rgb = .SRC_ALPHA,   dst_factor_rgb = .ONE,
                src_factor_alpha = .SRC_ALPHA, dst_factor_alpha = .ONE,
            },
        } },
        depth        = { pixel_format = .NONE },
        sample_count = 1,
        label        = "point-lights",
    })
}

frame :: proc "c" () {
    context = runtime.default_context()
    ensure_targets()
    W, H := f32(state.main.w), f32(state.main.h)
    t := f32(state.frame) / 60

    // 1. Record everything in game order; each layer is replayed into its own pass below.
    begin_layer(.World)
    TILE :: f32(64)
    for ty := f32(0); ty < H; ty += TILE {
        for tx := f32(0); tx < W; tx += TILE {
            even := (int(tx / TILE) + int(ty / TILE)) % 2 == 0
            rect(tx, ty, TILE, TILE, { 46, 58, 40, 255 } if even else { 38, 48, 34, 255 })
        }
    }
    // Orientation markers: red top-left, blue bottom-right. If RT sampling were flipped, they'd swap.
    rect(16, 16, 48, 48, { 220, 40, 40, 255 })
    rect(W - 64, H - 64, 48, 48, { 40, 80, 220, 255 })

    begin_layer(.Main_A)
    textured_rect(state.world.tex, state.smp_nearest, 0, 0, W, H)
    rect(W * 0.5 - 70, H * 0.5 + 40, 140, 24, { 0, 0, 0, 110 }) // stand-in for sprite shadows

    begin_layer(.Sprites)
    s := f32(3)
    textured_rect(state.sprite_tex, state.smp_nearest, W * 0.5 - state.sprite_w * s * 0.5, H * 0.5 - state.sprite_h * s * 0.5 + 8 * f32(1 + int(t * 2) % 2), state.sprite_w * s, state.sprite_h * s)

    begin_layer(.Main_B)
    textured_rect(state.sprite.tex, state.smp_nearest, 0, 0, W, H)

    begin_layer(.Main_UI)
    rect(24, H - 150, 520, 126, { 10, 10, 14, 200 })
    draw_text("Las Tormentas - sokol spike", 40, H - 140, 34, { 240, 220, 170, 255 })
    draw_text(fmt.tprintf("backend %v   %dx%d   frame %d", sg.query_backend(), state.main.w, state.main.h, state.frame), 40, H - 96, 20, { 200, 200, 200, 255 })
    draw_text("F11 fullscreen   Esc quit", 40, H - 66, 20, { 150, 150, 150, 255 })
    // Scissor: only the left half of this line survives.
    sgl.scissor_rect(i32(W) - 300, 24, 140, 60, true)
    draw_text("SCISSOR CLIPPED", f32(i32(W) - 300), 30, 30, { 255, 255, 255, 255 })
    sgl.scissor_rect(0, 0, i32(W), i32(H), true)

    // Swapchain: present the main target. Recorded in the default (swapchain-format) context.
    sgl.set_context(sgl.default_context())
    sgl.defaults()
    sgl.matrix_mode_projection()
    sgl.ortho(0, W, H, 0, -1, 1)
    textured_rect(state.main.tex, state.smp_nearest, 0, 0, W, H)

    // 2. Uploads, outside any pass.
    upload_atlas()

    // 3. Passes, in the game's order.
    sg.begin_pass(target_pass(state.world, clear_action(0, 0, 0, 0)))
    sgl.context_draw_layer(state.ctx_rgba, c.int(Layer.World))
    sg.end_pass()

    sg.begin_pass(target_pass(state.main, clear_action(0.05, 0.05, 0.07, 1)))
    sgl.context_draw_layer(state.ctx_rgba, c.int(Layer.Main_A))
    sg.end_pass()

    sg.begin_pass(target_pass(state.sprite, clear_action(0, 0, 0, 0)))
    sgl.context_draw_layer(state.ctx_rgba, c.int(Layer.Sprites))
    sg.end_pass()

    sg.begin_pass(target_pass(state.main, LOAD_ACTION)) // back to the main target, keeping its contents
    sgl.context_draw_layer(state.ctx_rgba, c.int(Layer.Main_B))
    lights := []Light{
        { pos = { 140, 140 },               radius = 220, intensity = 0.9, color = { 255, 170, 90 } },  // top-left
        { pos = { W - 200, H * 0.5 },       radius = 300, intensity = 0.7, color = { 90, 160, 255 } },  // right
        { pos = { W * 0.5 + 220 * math.cos(t), H * 0.5 }, radius = 160, intensity = 0.8, color = { 120, 255, 120 } },
    }
    draw_point_lights(lights)
    sgl.context_draw_layer(state.ctx_rgba, c.int(Layer.Main_UI))
    sg.end_pass()

    sg.begin_pass({ action = clear_action(0, 0, 0, 1), swapchain = sglue.swapchain() })
    sgl.context_draw(sgl.default_context())
    sg.end_pass()
    sg.commit()

    // 4. Readback, after commit so our blit is queued behind this frame's work.
    if state.shot_path != "" && state.frame == state.shot_frame {
        save_main_target(state.shot_path)
        sapp.request_quit()
    }
    state.frame += 1
}

save_main_target :: proc(path: string) {
    t := state.main
    switch state.shot_target {
    case "world":  t = state.world
    case "sprite": t = state.sprite
    }
    w, h := t.w, t.h
    pixels := make([]u8, int(w * h * 4))
    defer delete(pixels)
    ok := false
    when ODIN_OS == .Darwin {
        info := sg.mtl_query_image_info(t.img)
        ok = tormentas_mtl_read_rgba8(sg.mtl_command_queue(), info.tex[info.active_slot], w, h, raw_data(pixels)) == 1
    }
    if !ok { fmt.eprintln("[spike] readback failed (Metal only so far)"); return }
    cpath := strings.clone_to_cstring(path, context.temp_allocator)
    if stbi.write_png(cpath, w, h, 4, raw_data(pixels), w * 4) == 0 {
        fmt.eprintln("[spike] failed to write", path)
        return
    }
    fmt.printfln("[spike] saved %s (%dx%d)", path, w, h)
}

event :: proc "c" (e: ^sapp.Event) {
    context = runtime.default_context()
    #partial switch e.type {
    case .KEY_DOWN:
        #partial switch e.key_code {
        case .ESCAPE: sapp.request_quit()
        case .F11:    sapp.toggle_fullscreen()
        }
    }
}

cleanup :: proc "c" () {
    context = runtime.default_context()
    fs.Destroy(&state.font)
    sgl.shutdown()
    sg.shutdown()
}

main :: proc() {
    state.shot_frame = 10
    for a, i in os.args {
        if a == "--shot" && i + 1 < len(os.args) { state.shot_path = os.args[i + 1] }
        if a == "--target" && i + 1 < len(os.args) { state.shot_target = os.args[i + 1] }
        if a == "--frames" && i + 1 < len(os.args) {
            if n, ok := strconv.parse_u64(os.args[i + 1]); ok { state.shot_frame = n }
        }
    }
    sapp.run({
        init_cb       = init,
        frame_cb      = frame,
        cleanup_cb    = cleanup,
        event_cb      = event,
        width         = 1280,
        height        = 720,
        sample_count  = 1,
        high_dpi      = false,
        window_title  = "Las Tormentas - sokol spike",
        icon          = { sokol_default = true },
        logger        = { func = slog.func },
    })
}
