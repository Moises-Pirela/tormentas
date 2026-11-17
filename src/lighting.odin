package main

import gfx "gfx"
import "core:math"
import im "../deps/imgui/imgui"

g_light_widget_open: bool

g_light_sun_dir_x: f32 = 0.84
g_light_sun_dir_y: f32 = 0.54
g_light_sun_elevation: f32 = 55.0

SHADOW_NEAR_ALPHA :: 215
SHADOW_FAR_ALPHA  :: 135

g_light_cloud_freq:      f32 = 0.0032
g_light_cloud_freq_fine: f32 = 0.0075
g_light_cloud_drift_x:   f32 = 12.0
g_light_cloud_drift_y:   f32 = 6.5
g_light_cloud_cell:      f32 = 28.0
g_light_cloud_thresh_lo: f32 = 0.42
g_light_cloud_thresh_hi: f32 = 0.68
g_light_cloud_alpha_min: f32 = 30.0
g_light_cloud_alpha_max: f32 = 124.0
g_light_cloud_contrast:  f32 = 1.35
g_light_cloud_tint_r:    f32 = 18.0
g_light_cloud_tint_g:    f32 = 30.0
g_light_cloud_tint_b:    f32 = 14.0

g_light_god_ray_spacing: f32 = 130.0
g_light_god_ray_width:   f32 = 82.0
g_light_god_ray_thresh:  f32 = 0.60
g_light_god_ray_alpha:   f32 = 1.0

g_light_sun_intensity: f32 = 0.55
g_light_ambient:       f32 = 0.72
g_light_shadow_alpha:  f32 = 0.82
g_light_sun_color_r:   f32 = 244.0
g_light_sun_color_g:   f32 = 228.0
g_light_sun_color_b:   f32 = 184.0
g_light_sprite_min_brightness: f32 = 0.68
g_light_sprite_outline:        f32 = 1.8
g_light_sprite_diffuse:        f32 = 0.70
g_light_sprite_rim:            f32 = 0.45
g_light_sprite_shadow_response:f32 = 0.65

LevelLightingConfig :: struct #packed {
    sun_dir_x:              f32,
    sun_dir_y:              f32,
    sun_elevation:          f32,
    cloud_freq:             f32,
    cloud_freq_fine:        f32,
    cloud_drift_x:          f32,
    cloud_drift_y:          f32,
    cloud_cell:             f32,
    cloud_thresh_lo:        f32,
    cloud_thresh_hi:        f32,
    cloud_alpha_min:        f32,
    cloud_alpha_max:        f32,
    cloud_contrast:         f32,
    cloud_tint_r:           f32,
    cloud_tint_g:           f32,
    cloud_tint_b:           f32,
    god_ray_spacing:        f32,
    god_ray_width:          f32,
    god_ray_thresh:         f32,
    god_ray_alpha:          f32,
    sun_intensity:          f32,
    ambient:                f32,
    shadow_alpha:           f32,
    sun_color_r:            f32,
    sun_color_g:            f32,
    sun_color_b:            f32,
    sprite_min_brightness:  f32,
    sprite_outline:         f32,
    sprite_diffuse:         f32,
    sprite_rim:             f32,
    sprite_shadow_response: f32,
    fog_color_r:            f32,
    fog_color_g:            f32,
    fog_color_b:            f32,
    fog_density:            f32,
    fog_scatter:            f32,
}

LIGHTING_CONFIG_DEFAULT :: LevelLightingConfig{
    sun_dir_x              = 0.84,
    sun_dir_y              = 0.54,
    sun_elevation          = 55.0,
    cloud_freq             = 0.0032,
    cloud_freq_fine        = 0.0075,
    cloud_drift_x          = 12.0,
    cloud_drift_y          = 6.5,
    cloud_cell             = 28.0,
    cloud_thresh_lo        = 0.42,
    cloud_thresh_hi        = 0.68,
    cloud_alpha_min        = 30.0,
    cloud_alpha_max        = 124.0,
    cloud_contrast         = 1.35,
    cloud_tint_r           = 18.0,
    cloud_tint_g           = 30.0,
    cloud_tint_b           = 14.0,
    god_ray_spacing        = 130.0,
    god_ray_width          = 82.0,
    god_ray_thresh         = 0.60,
    god_ray_alpha          = 1.0,
    sun_intensity          = 0.55,
    ambient                = 0.72,
    shadow_alpha           = 0.82,
    sun_color_r            = 244.0,
    sun_color_g            = 228.0,
    sun_color_b            = 184.0,
    sprite_min_brightness  = 0.68,
    sprite_outline         = 1.8,
    sprite_diffuse         = 0.70,
    sprite_rim             = 0.45,
    sprite_shadow_response = 0.65,
    fog_color_r            = 8.0,
    fog_color_g            = 10.0,
    fog_color_b            = 14.0,
    fog_density            = 0.55,
    fog_scatter            = 1.35,
}

lighting_config_capture :: proc() -> LevelLightingConfig {
    return LevelLightingConfig{
        sun_dir_x              = g_light_sun_dir_x,
        sun_dir_y              = g_light_sun_dir_y,
        sun_elevation          = g_light_sun_elevation,
        cloud_freq             = g_light_cloud_freq,
        cloud_freq_fine        = g_light_cloud_freq_fine,
        cloud_drift_x          = g_light_cloud_drift_x,
        cloud_drift_y          = g_light_cloud_drift_y,
        cloud_cell             = g_light_cloud_cell,
        cloud_thresh_lo        = g_light_cloud_thresh_lo,
        cloud_thresh_hi        = g_light_cloud_thresh_hi,
        cloud_alpha_min        = g_light_cloud_alpha_min,
        cloud_alpha_max        = g_light_cloud_alpha_max,
        cloud_contrast         = g_light_cloud_contrast,
        cloud_tint_r           = g_light_cloud_tint_r,
        cloud_tint_g           = g_light_cloud_tint_g,
        cloud_tint_b           = g_light_cloud_tint_b,
        god_ray_spacing        = g_light_god_ray_spacing,
        god_ray_width          = g_light_god_ray_width,
        god_ray_thresh         = g_light_god_ray_thresh,
        god_ray_alpha          = g_light_god_ray_alpha,
        sun_intensity          = g_light_sun_intensity,
        ambient                = g_light_ambient,
        shadow_alpha           = g_light_shadow_alpha,
        sun_color_r            = g_light_sun_color_r,
        sun_color_g            = g_light_sun_color_g,
        sun_color_b            = g_light_sun_color_b,
        sprite_min_brightness  = g_light_sprite_min_brightness,
        sprite_outline         = g_light_sprite_outline,
        sprite_diffuse         = g_light_sprite_diffuse,
        sprite_rim             = g_light_sprite_rim,
        sprite_shadow_response = g_light_sprite_shadow_response,
        fog_color_r            = g_fog_color[0],
        fog_color_g            = g_fog_color[1],
        fog_color_b            = g_fog_color[2],
        fog_density            = g_fog_density,
        fog_scatter            = g_fog_scatter,
    }
}

lighting_config_apply :: proc(c: LevelLightingConfig) {
    g_light_sun_dir_x              = c.sun_dir_x
    g_light_sun_dir_y              = c.sun_dir_y
    g_light_sun_elevation          = c.sun_elevation
    g_light_cloud_freq             = c.cloud_freq
    g_light_cloud_freq_fine        = c.cloud_freq_fine
    g_light_cloud_drift_x          = c.cloud_drift_x
    g_light_cloud_drift_y          = c.cloud_drift_y
    g_light_cloud_cell             = c.cloud_cell
    g_light_cloud_thresh_lo        = c.cloud_thresh_lo
    g_light_cloud_thresh_hi        = c.cloud_thresh_hi
    g_light_cloud_alpha_min        = c.cloud_alpha_min
    g_light_cloud_alpha_max        = c.cloud_alpha_max
    g_light_cloud_contrast         = c.cloud_contrast
    g_light_cloud_tint_r           = c.cloud_tint_r
    g_light_cloud_tint_g           = c.cloud_tint_g
    g_light_cloud_tint_b           = c.cloud_tint_b
    g_light_god_ray_spacing        = c.god_ray_spacing
    g_light_god_ray_width          = c.god_ray_width
    g_light_god_ray_thresh         = c.god_ray_thresh
    g_light_god_ray_alpha          = c.god_ray_alpha
    g_light_sun_intensity          = c.sun_intensity
    g_light_ambient                = c.ambient
    g_light_shadow_alpha           = c.shadow_alpha
    g_light_sun_color_r            = c.sun_color_r
    g_light_sun_color_g            = c.sun_color_g
    g_light_sun_color_b            = c.sun_color_b
    g_light_sprite_min_brightness  = c.sprite_min_brightness
    g_light_sprite_outline         = c.sprite_outline
    g_light_sprite_diffuse         = c.sprite_diffuse
    g_light_sprite_rim             = c.sprite_rim
    g_light_sprite_shadow_response = c.sprite_shadow_response
    g_fog_color[0]                 = c.fog_color_r
    g_fog_color[1]                 = c.fog_color_g
    g_fog_color[2]                 = c.fog_color_b
    g_fog_density                  = c.fog_density
    g_fog_scatter                  = c.fog_scatter
}


@(private = "file")
world_view_bounds :: proc(pad: f32 = 0) -> (min_x, min_y, max_x, max_y: f32) {
    return cam_view_bounds(pad)
}


g_world_rt: gfx.RenderTexture
g_shadow_rt: gfx.RenderTexture
g_sprite_rt: gfx.RenderTexture
@(private = "file") g_light_rt_w: i32
@(private = "file") g_light_rt_h: i32

g_wall_mask:       gfx.Texture
g_wall_mask_dirty: bool = true
@(private = "file") g_wall_mask_origin: [2]f32
@(private = "file") g_wall_mask_size:   [2]f32

init_lighting :: proc() {
    gfx.lighting_init()
}

shutdown_lighting :: proc() {
    if g_world_rt.id != 0  { gfx.unload_render_texture(g_world_rt) }
    if g_shadow_rt.id != 0 { gfx.unload_render_texture(g_shadow_rt) }
    if g_sprite_rt.id != 0 { gfx.unload_render_texture(g_sprite_rt) }
    gfx.lighting_shutdown()
}

init_wall_mask :: proc() {
    g_wall_mask_dirty = true
}

shutdown_wall_mask :: proc() {
    gfx.unload_texture(g_wall_mask)
    delete(g_wall_mask_pixels)
}

// One texel per tile, white where a wall stands. Built on the CPU and uploaded: drawing it into a
// render target would mean a pass in the middle of the frame, and texel-exact plotting
// (docs/BACKEND_SWAP_PLAN.md §3.8). The texture is upright, so the shaders sample it directly.
@(private = "file") g_wall_mask_pixels: [dynamic]u8

rebuild_wall_mask :: proc() {
    if !g_wall_mask_dirty { return }
    g_wall_mask_dirty = false

    tw, th     := 1, 1
    min_tx, min_ty := 0, 0
    if len(g_tilemap) > 0 {
        lo_x, lo_y := max(int), max(int)
        hi_x, hi_y := min(int), min(int)
        for k in g_tilemap {
            lo_x = min(lo_x, k[0]); lo_y = min(lo_y, k[1])
            hi_x = max(hi_x, k[0]); hi_y = max(hi_y, k[1])
        }
        min_tx, min_ty = lo_x, lo_y
        tw = clamp(hi_x - lo_x + 1, 1, 1024)
        th = clamp(hi_y - lo_y + 1, 1, 1024)
    }

    g_wall_mask_origin = { f32(min_tx), f32(min_ty) }
    g_wall_mask_size   = { f32(tw), f32(th) }

    resize(&g_wall_mask_pixels, tw * th * 4)
    for i in 0..<len(g_wall_mask_pixels) { g_wall_mask_pixels[i] = 255 if (i & 3) == 3 else 0 }

    if len(g_tilemap) > 0 {
        for k, v in g_tilemap {
            if tile_base(v) != .Wall { continue }
            px := k[0] - min_tx
            py := k[1] - min_ty
            if px < 0 || py < 0 || px >= tw || py >= th { continue }
            at := (py * tw + px) * 4
            g_wall_mask_pixels[at + 0] = 255
            g_wall_mask_pixels[at + 1] = 255
            g_wall_mask_pixels[at + 2] = 255
        }
    }

    if g_wall_mask.id == 0 || g_wall_mask.width != i32(tw) || g_wall_mask.height != i32(th) {
        gfx.unload_texture(g_wall_mask)
        g_wall_mask = gfx.load_texture_pixels(g_wall_mask_pixels[:], i32(tw), i32(th))
    } else {
        gfx.update_texture(g_wall_mask, g_wall_mask_pixels[:])
    }
}

ensure_lighting_render_targets :: proc() {
    sw := gfx.screen_width()
    sh := gfx.screen_height()
    if sw <= 0 || sh <= 0 { return }
    if g_light_rt_w == sw && g_light_rt_h == sh && g_world_rt.id != 0 && g_shadow_rt.id != 0 && g_sprite_rt.id != 0 { return }

    if g_world_rt.id != 0 { gfx.unload_render_texture(g_world_rt) }
    if g_shadow_rt.id != 0 { gfx.unload_render_texture(g_shadow_rt) }
    if g_sprite_rt.id != 0 { gfx.unload_render_texture(g_sprite_rt) }

    g_world_rt = gfx.load_render_texture(sw, sh)
    g_shadow_rt = gfx.load_render_texture(sw, sh)
    g_sprite_rt = gfx.load_render_texture(sw, sh)
    g_light_rt_w = sw
    g_light_rt_h = sh
}

MAX_POINT_LIGHTS :: 32

g_fog_color:   [3]f32 = { 8, 10, 14 }
g_fog_density: f32    = 0.55
g_fog_scatter: f32    = 1.35


@(private = "file")
sun_dir :: proc() -> [2]f32 {
    inv_len := f32(1.0 / math.sqrt(g_light_sun_dir_x*g_light_sun_dir_x + g_light_sun_dir_y*g_light_sun_dir_y))
    return { g_light_sun_dir_x * inv_len, g_light_sun_dir_y * inv_len }
}

@(private = "file")
light_view :: proc() -> gfx.View_Params {
    return {
        cam_target = { cam_target().x, cam_target().y },
        cam_offset = { cam_offset().x, cam_offset().y },
        cam_zoom   = cam_zoom(),
    }
}

@(private = "file")
cloud_shape :: proc() -> (freq, freq_fine: f32, drift: [2]f32, lo, hi, contrast: f32) {
    return g_light_cloud_freq, g_light_cloud_freq_fine,
           { g_light_cloud_drift_x, g_light_cloud_drift_y },
           g_light_cloud_thresh_lo, g_light_cloud_thresh_hi, g_light_cloud_contrast
}

@(private = "file")
sun_color_01 :: proc() -> [3]f32 {
    return { g_light_sun_color_r / 255.0, g_light_sun_color_g / 255.0, g_light_sun_color_b / 255.0 }
}

// Point lights in the world, in the form the lighting passes take.
@(private = "file")
collect_lights :: proc(w: ^World) -> gfx.Lights {
    out: gfx.Lights
    ids := world_query(w, query_mask(.PointLight, .Transform))
    defer delete(ids)
    n := min(len(ids), MAX_POINT_LIGHTS)
    out.count = i32(n)
    for i in 0..<n {
        id := ids[i]
        t  := comp_get(w, id, .Transform, TransformComp)
        pl := comp_get(w, id, .PointLight, PointLightComp)
        out.pos[i]       = { t.position[0], t.position[1] }
        out.color[i]     = pl.color
        out.radius[i]    = pl.radius
        out.intensity[i] = pl.intensity
    }
    return out
}

draw_cloud_shadow_field :: proc() {
    freq, freq_fine, drift, lo, hi, contrast := cloud_shape()
    gfx.lighting_clouds({
        view      = light_view(),
        time      = f32(gfx.time()),
        freq      = freq,
        freq_fine = freq_fine,
        drift     = drift,
        thresh_lo = lo,
        thresh_hi = hi,
        alpha_min = g_light_cloud_alpha_min,
        alpha_max = g_light_cloud_alpha_max,
        contrast  = contrast,
        tint      = { g_light_cloud_tint_r, g_light_cloud_tint_g, g_light_cloud_tint_b },
    })
}

draw_wall_sun_shadows :: proc() {
    dir := sun_dir()
    min_x, min_y, max_x, max_y := world_view_bounds(f32(TILE_SIZE) * 2)

    for k, v in g_tilemap {
        if tile_base(v) != .Wall { continue }

        x := f32(k[0] * TILE_SIZE)
        y := f32(k[1] * TILE_SIZE)
        if x < min_x - TILE_SIZE || x > max_x + TILE_SIZE ||
           y < min_y - TILE_SIZE || y > max_y + TILE_SIZE { continue }

        shadow_len := f32(TILE_SIZE) * 2.1
        for i in 0..<5 {
            t := f32(i) / 5.0
            off := shadow_len * t
            a   := u8(clamp(72 * (1.0 - t), 0, 255))
            center := cam_world_to_view_xy(x + f32(TILE_SIZE) * 0.5 + dir[0] * off, y + f32(TILE_SIZE) * 0.5 + dir[1] * off)
            cam_draw_shadow_diamond(center, ISO_TILE_W * 2 * (1.0 + t * 0.08), ISO_TILE_H * 2 * (1.0 + t * 0.04), gfx.Color{ 10, 10, 10, a })
        }
    }
}

draw_player_projected_shadow :: proc(w: ^World) {
    pid := w.player_id
    if !world_is_valid(w, pid) { return }
    if is_fog_hidden(w, pid) { return }

    if world_has_component(w, pid, .Respawn) &&
       comp_get(w, pid, .Respawn, RespawnComp).timer > 0 { return }

    frame, ok := sprite_frame_for(w, pid)
    if !ok { return }

    tr   := comp_get(w, pid, .Transform, TransformComp)
    feet := cam_world_to_view({ tr.position[0], tr.position[1] })

    near_a := u8(clamp(f32(SHADOW_NEAR_ALPHA) * g_light_shadow_alpha, 0, 255))
    far_a  := u8(clamp(f32(SHADOW_FAR_ALPHA)  * g_light_shadow_alpha, 0, 255))

    draw_projected_sprite_shadow(
        frame.tex, frame.src, feet,
        frame.world_size, frame.aspect, frame.anchor, frame.ground, frame.flip_x,
        sun_dir(), g_light_sun_elevation,
        near_a, far_a, gfx.Color{ 6, 7, 5, 255 },
    )
}

draw_entity_sprite_shadows :: proc(w: ^World) {
    dir := sun_dir()
    ids := world_query(w, query_mask(.Transform))
    defer delete(ids)

    for id in ids {
        if world_has_component(w, id, .ProjectileTag) { continue }
        if world_has_component(w, id, .MeleeArc)      { continue }
        if world_has_component(w, id, .GroundItem)    { continue }
        if world_has_component(w, id, .PointLight)    { continue }
        if is_fog_hidden(w, id)                           { continue }

        tr := comp_get(w, id, .Transform, TransformComp)
        pos := gfx.Vec2{ tr.position[0], tr.position[1] }
        rot := tr.rotation

        vis := draw_entity_visual_info(w, id)
        if !vis.ok {
            continue
        }
        radius := vis.world_size * 0.22

        if world_has_component(w, id, .Respawn) &&
           comp_get(w, id, .Respawn, RespawnComp).timer > 0 {
            continue
        }

        if is_player_entity(w, id) { continue }

        contact_offset := radius * 0.6
        for ci in 0..<4 {
            t_frac := f32(ci) / 3.0
            off := contact_offset + radius * t_frac * 0.9
            cp := gfx.Vec2{
                pos.x + dir[0] * off,
                pos.y + dir[1] * off,
            }
            r := radius * (0.9 - t_frac * 0.18)
            a := u8(clamp(180 * (1.0 - t_frac * 0.42), 0, 255))
            icp := cam_world_to_view(cp)
            gfx.draw_ellipse(i32(icp.x), i32(icp.y), r * 1.08, max(r * 0.42, 1), gfx.Color{ 6, 6, 4, a })
        }

        entry, sprite_ok := get_or_load_entity_sprite(vis.sprite_key)
        if !sprite_ok { continue }

        stem := string(vis.sprite_key)
        src := anim_source_rect(w, id, entry.src, stem) if !entry.from_rt else entry.src
        world_size := vis.world_size

        anchor := [2]f32{ 0.5, 1.0 }
        if def, aok := get_or_load_anim_def(stem); aok && def.frame_width > 0 && def.frame_height > 0 {
            anchor = {
                f32(def.anchor_px_x) / f32(def.frame_width),
                f32(def.anchor_px_y) / f32(def.frame_height),
            }
        }

        top_down := world_has_component(w, id, .RenderConfig) &&
            comp_get(w, id, .RenderConfig, RenderConfigComp).top_down_sprite

        for i in 0..<4 {
            t_frac := f32(i) / 3.0
            offset := radius * (0.45 + t_frac * 0.95)
            a      := u8(clamp(155 * (1.0 - t_frac * 0.48), 0, 255))

            shadow_pos := gfx.Vec2{
                pos.x + dir[0] * offset,
                pos.y + dir[1] * offset,
            }
            if top_down {
                draw_player_sprite(entry.tex, src, shadow_pos, world_size, gfx.Color{ 8, 10, 6, a }, anchor)
            } else {
                draw_entity_sprite_quad_ex(entry.tex, src, shadow_pos, world_size, rot, gfx.Color{ 8, 10, 6, a }, ISO_SPRITE_Y, anchor)
            }
        }
    }
}

draw_directional_shadow_mask :: proc(w: ^World) {
    ensure_lighting_render_targets()
    if g_shadow_rt.id == 0 { return }

    gfx.target_begin(g_shadow_rt)
    gfx.clear(gfx.BLANK)
    cam_begin()
    draw_wall_sun_shadows()
    cam_end()
    gfx.target_end()
}

draw_directional_world_composite :: proc() {
    ensure_lighting_render_targets()
    if g_world_rt.id == 0 || g_shadow_rt.id == 0 { return }

    gfx.lighting_directional(g_world_rt.texture, g_shadow_rt.texture, {
        sun_dir       = sun_dir(),
        sun_color     = sun_color_01(),
        sun_intensity = g_light_sun_intensity,
        ambient       = g_light_ambient,
        shadow_alpha  = g_light_shadow_alpha,
    })
}

draw_directional_sprite_composite :: proc(w: ^World) {
    ensure_lighting_render_targets()
    if g_sprite_rt.id == 0 || g_shadow_rt.id == 0 { return }

    gfx.lighting_sprite(g_sprite_rt.texture, g_shadow_rt.texture, g_wall_mask, {
        view            = light_view(),
        sun_dir         = sun_dir(),
        sun_color       = sun_color_01(),
        sun_intensity   = g_light_sun_intensity,
        ambient         = g_light_ambient,
        shadow_alpha    = g_light_shadow_alpha,
        min_brightness  = g_light_sprite_min_brightness,
        outline         = g_light_sprite_outline,
        diffuse         = g_light_sprite_diffuse,
        rim             = g_light_sprite_rim,
        shadow_response = g_light_sprite_shadow_response,
        fog_scatter     = g_fog_scatter,
        wall_origin     = g_wall_mask_origin,
        wall_size       = g_wall_mask_size,
        tile_size       = f32(TILE_SIZE),
        lights          = collect_lights(w),
    })
}

draw_world_god_rays :: proc() {
    freq, freq_fine, drift, lo, hi, contrast := cloud_shape()
    gfx.lighting_god_rays({
        view        = light_view(),
        time        = f32(gfx.time()),
        sun_dir     = sun_dir(),
        ray_spacing = g_light_god_ray_spacing,
        ray_width   = g_light_god_ray_width,
        ray_thresh  = g_light_god_ray_thresh,
        ray_alpha   = g_light_god_ray_alpha,
        freq        = freq,
        freq_fine   = freq_fine,
        drift       = drift,
        thresh_lo   = lo,
        thresh_hi   = hi,
        contrast    = contrast,
    })
}

draw_fog_and_lights :: proc(w: ^World) {
    player_pos    := [2]f32{ 0, 0 }
    vision_radius := f32(0)
    vision_fade   := f32(0)
    if world_is_valid(w, w.player_id) && world_has_component(w, w.player_id, .Transform) {
        pp := comp_get(w, w.player_id, .Transform, TransformComp).position
        player_pos    = { pp[0], pp[1] }
        vision_radius = FOG_VISION_RADIUS
        vision_fade   = FOG_FADE_WIDTH
        if world_has_component(w, w.player_id, .Stats) {
            vision_radius += comp_get(w, w.player_id, .Stats, StatsComp).vision_bonus
        }
    }

    rebuild_wall_mask()

    gfx.lighting_fog(g_wall_mask, {
        view          = light_view(),
        fog_color     = g_fog_color,
        fog_density   = g_fog_density,
        fog_scatter   = g_fog_scatter,
        player_pos    = player_pos,
        vision_radius = vision_radius,
        vision_fade   = vision_fade,
        wall_origin   = g_wall_mask_origin,
        wall_size     = g_wall_mask_size,
        tile_size     = f32(TILE_SIZE),
        lights        = collect_lights(w),
    })
}

update_lighting_widget :: proc() {
    if !devui_wants_text() && gfx.key_pressed(.F2) {
        g_light_widget_open = !g_light_widget_open
    }
}

@(private = "file")
_light_slider :: proc(label: cstring, v: ^f32, lo, hi: f32) {
    fmt_str: cstring = "%.3f" if hi - lo < 4 else "%.1f"
    if hi - lo < 0.05 { fmt_str = "%.4f" }
    im.SliderFloat(label, v, lo, hi, fmt_str)
}

lighting_ui :: proc() {
    if !g_light_widget_open { return }
    im.SetNextWindowSize({ 360, 640 }, .FirstUseEver)
    defer im.End()
    if !im.Begin("Lighting", &g_light_widget_open) { return }
    im.PushItemWidth(-130)
    defer im.PopItemWidth()

    if im.CollapsingHeader("Sun and clouds", { .DefaultOpen }) {
        _light_slider("Sun dir X",      &g_light_sun_dir_x,       -1.2,  1.2)
        _light_slider("Sun dir Y",      &g_light_sun_dir_y,       -1.2,  1.2)
        _light_slider("Sun elevation",  &g_light_sun_elevation,    10,   80)
        _light_slider("Cloud scale",    &g_light_cloud_freq,       0.001, 0.008)
        _light_slider("Cloud detail",   &g_light_cloud_freq_fine,  0.002, 0.02)
        _light_slider("Cloud cell",     &g_light_cloud_cell,       12,    72)
        _light_slider("Cloud drift X",  &g_light_cloud_drift_x,   -32,    32)
        _light_slider("Cloud drift Y",  &g_light_cloud_drift_y,   -32,    32)
        _light_slider("Cloud low",      &g_light_cloud_thresh_lo,  0.10,  0.85)
        _light_slider("Cloud high",     &g_light_cloud_thresh_hi,  0.15,  0.95)
        _light_slider("Cloud contrast", &g_light_cloud_contrast,   0.4,   2.6)
        _light_slider("Cloud min alpha",&g_light_cloud_alpha_min,  0,     90)
        _light_slider("Cloud max alpha",&g_light_cloud_alpha_max,  0,     180)
        tint := [3]f32{ g_light_cloud_tint_r / 255, g_light_cloud_tint_g / 255, g_light_cloud_tint_b / 255 }
        if im.ColorEdit3("Cloud colour", &tint) {
            g_light_cloud_tint_r = tint[0] * 255
            g_light_cloud_tint_g = tint[1] * 255
            g_light_cloud_tint_b = tint[2] * 255
        }
    }
    if im.CollapsingHeader("God rays", { .DefaultOpen }) {
        _light_slider("Ray spacing",   &g_light_god_ray_spacing,  50,   220)
        _light_slider("Ray width",     &g_light_god_ray_width,    24,   180)
        _light_slider("Ray threshold", &g_light_god_ray_thresh,   0.15, 0.92)
        _light_slider("Ray alpha",     &g_light_god_ray_alpha,    0.0,  2.0)
    }
    if im.CollapsingHeader("Fog", { .DefaultOpen }) {
        _light_slider("Fog density", &g_fog_density, 0.0, 1.0)
        _light_slider("Fog scatter", &g_fog_scatter, 1.0, 2.0)
    }
    if im.CollapsingHeader("Sun and sprites", { .DefaultOpen }) {
        _light_slider("Sun intensity",  &g_light_sun_intensity,          0.0, 1.5)
        _light_slider("Ambient",        &g_light_ambient,                0.1, 1.2)
        _light_slider("Shadow alpha",   &g_light_shadow_alpha,           0.0, 1.0)
        _light_slider("Sprite min",     &g_light_sprite_min_brightness,  0.1, 1.2)
        _light_slider("Sprite outline", &g_light_sprite_outline,         0.0, 2.5)
        _light_slider("Sprite diffuse", &g_light_sprite_diffuse,         0.0, 1.2)
        _light_slider("Sprite rim",     &g_light_sprite_rim,             0.0, 1.0)
        _light_slider("Sprite shadow",  &g_light_sprite_shadow_response, 0.0, 0.8)
    }

    g_light_cloud_thresh_hi = max(g_light_cloud_thresh_hi, g_light_cloud_thresh_lo + 0.01)
    g_light_cloud_freq_fine = max(g_light_cloud_freq_fine, g_light_cloud_freq + 0.0001)
    g_light_cloud_cell      = max(g_light_cloud_cell, 4)
}
