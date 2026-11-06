package main

import rl "vendor:raylib"
import "core:math"
import "core:c"
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

@(private = "file") g_cloud_shader: rl.Shader
@(private = "file") g_cloud_locs: struct {
    screen_size:     c.int,
    camera_target:   c.int,
    camera_offset:   c.int,
    camera_zoom:     c.int,
    time:            c.int,
    cloud_freq:      c.int,
    cloud_freq_fine: c.int,
    cloud_drift:     c.int,
    cloud_thresh_lo: c.int,
    cloud_thresh_hi: c.int,
    cloud_alpha_min: c.int,
    cloud_alpha_max: c.int,
    cloud_contrast:  c.int,
    cloud_tint:      c.int,
}

init_cloud_shader :: proc() {
    g_cloud_shader = rl.LoadShader(nil, "data/shaders/cloud_shadow.fs")
    g_cloud_locs.screen_size     = rl.GetShaderLocation(g_cloud_shader, "u_screen_size")
    g_cloud_locs.camera_target   = rl.GetShaderLocation(g_cloud_shader, "u_camera_target")
    g_cloud_locs.camera_offset   = rl.GetShaderLocation(g_cloud_shader, "u_camera_offset")
    g_cloud_locs.camera_zoom     = rl.GetShaderLocation(g_cloud_shader, "u_camera_zoom")
    g_cloud_locs.time            = rl.GetShaderLocation(g_cloud_shader, "u_time")
    g_cloud_locs.cloud_freq      = rl.GetShaderLocation(g_cloud_shader, "u_cloud_freq")
    g_cloud_locs.cloud_freq_fine = rl.GetShaderLocation(g_cloud_shader, "u_cloud_freq_fine")
    g_cloud_locs.cloud_drift     = rl.GetShaderLocation(g_cloud_shader, "u_cloud_drift")
    g_cloud_locs.cloud_thresh_lo = rl.GetShaderLocation(g_cloud_shader, "u_cloud_thresh_lo")
    g_cloud_locs.cloud_thresh_hi = rl.GetShaderLocation(g_cloud_shader, "u_cloud_thresh_hi")
    g_cloud_locs.cloud_alpha_min = rl.GetShaderLocation(g_cloud_shader, "u_cloud_alpha_min")
    g_cloud_locs.cloud_alpha_max = rl.GetShaderLocation(g_cloud_shader, "u_cloud_alpha_max")
    g_cloud_locs.cloud_contrast  = rl.GetShaderLocation(g_cloud_shader, "u_cloud_contrast")
    g_cloud_locs.cloud_tint      = rl.GetShaderLocation(g_cloud_shader, "u_cloud_tint")
}

shutdown_cloud_shader :: proc() {
    rl.UnloadShader(g_cloud_shader)
}

@(private = "file")
world_view_bounds :: proc(pad: f32 = 0) -> (min_x, min_y, max_x, max_y: f32) {
    return cartesian_view_bounds(pad)
}

@(private = "file") g_godray_shader: rl.Shader
@(private = "file") g_godray_locs: struct {
    screen_size:      c.int,
    camera_target:    c.int,
    camera_offset:    c.int,
    camera_zoom:      c.int,
    time:             c.int,
    sun_dir:          c.int,
    ray_spacing:      c.int,
    ray_width:        c.int,
    ray_thresh:       c.int,
    ray_alpha:        c.int,
    cloud_freq:       c.int,
    cloud_freq_fine:  c.int,
    cloud_drift:      c.int,
    cloud_thresh_lo:  c.int,
    cloud_thresh_hi:  c.int,
    cloud_contrast:   c.int,
}

init_godray_shader :: proc() {
    g_godray_shader = rl.LoadShader(nil, "data/shaders/god_rays.fs")
    g_godray_locs.screen_size   = rl.GetShaderLocation(g_godray_shader, "u_screen_size")
    g_godray_locs.camera_target = rl.GetShaderLocation(g_godray_shader, "u_camera_target")
    g_godray_locs.camera_offset = rl.GetShaderLocation(g_godray_shader, "u_camera_offset")
    g_godray_locs.camera_zoom   = rl.GetShaderLocation(g_godray_shader, "u_camera_zoom")
    g_godray_locs.time          = rl.GetShaderLocation(g_godray_shader, "u_time")
    g_godray_locs.sun_dir       = rl.GetShaderLocation(g_godray_shader, "u_sun_dir")
    g_godray_locs.ray_spacing   = rl.GetShaderLocation(g_godray_shader, "u_ray_spacing")
    g_godray_locs.ray_width     = rl.GetShaderLocation(g_godray_shader, "u_ray_width")
    g_godray_locs.ray_thresh    = rl.GetShaderLocation(g_godray_shader, "u_ray_thresh")
    g_godray_locs.ray_alpha     = rl.GetShaderLocation(g_godray_shader, "u_ray_alpha")
    g_godray_locs.cloud_freq      = rl.GetShaderLocation(g_godray_shader, "u_cloud_freq")
    g_godray_locs.cloud_freq_fine = rl.GetShaderLocation(g_godray_shader, "u_cloud_freq_fine")
    g_godray_locs.cloud_drift     = rl.GetShaderLocation(g_godray_shader, "u_cloud_drift")
    g_godray_locs.cloud_thresh_lo = rl.GetShaderLocation(g_godray_shader, "u_cloud_thresh_lo")
    g_godray_locs.cloud_thresh_hi = rl.GetShaderLocation(g_godray_shader, "u_cloud_thresh_hi")
    g_godray_locs.cloud_contrast  = rl.GetShaderLocation(g_godray_shader, "u_cloud_contrast")
}

shutdown_godray_shader :: proc() {
    rl.UnloadShader(g_godray_shader)
}

g_world_rt: rl.RenderTexture2D
g_shadow_rt: rl.RenderTexture2D
g_sprite_rt: rl.RenderTexture2D
@(private = "file") g_light_rt_w: i32
@(private = "file") g_light_rt_h: i32

g_wall_mask:       rl.RenderTexture2D
g_wall_mask_dirty: bool = true
@(private = "file") g_wall_mask_origin: [2]f32
@(private = "file") g_wall_mask_size:   [2]f32

@(private = "file") g_directional_shader: rl.Shader
@(private = "file") g_directional_locs: struct {
    shadow_tex:      c.int,
    screen_size:     c.int,
    sun_dir:         c.int,
    sun_intensity:   c.int,
    ambient:         c.int,
    shadow_alpha:    c.int,
    sun_color:       c.int,
}

@(private = "file") g_spritelight_shader: rl.Shader
@(private = "file") g_spritelight_locs: struct {
    shadow_tex:       c.int,
    screen_size:      c.int,
    sun_dir:          c.int,
    sun_color:        c.int,
    sun_intensity:    c.int,
    ambient:          c.int,
    shadow_alpha:     c.int,
    min_brightness:   c.int,
    outline_strength: c.int,
    diffuse_strength: c.int,
    rim_strength:     c.int,
    shadow_response:  c.int,
    camera_target:    c.int,
    camera_offset:    c.int,
    camera_zoom:      c.int,
    fog_scatter:      c.int,
    light_count:      c.int,
    light_pos:        c.int,
    light_color:      c.int,
    light_radius:     c.int,
    light_intensity:  c.int,
    wall_mask:        c.int,
    wall_origin:      c.int,
    wall_size:        c.int,
    tile_size:        c.int,
}

init_directional_shader :: proc() {
    g_directional_shader = rl.LoadShader(nil, "data/shaders/directional_light.fs")
    g_directional_locs.shadow_tex    = rl.GetShaderLocation(g_directional_shader, "u_shadow_tex")
    g_directional_locs.screen_size   = rl.GetShaderLocation(g_directional_shader, "u_screen_size")
    g_directional_locs.sun_dir       = rl.GetShaderLocation(g_directional_shader, "u_sun_dir")
    g_directional_locs.sun_intensity = rl.GetShaderLocation(g_directional_shader, "u_sun_intensity")
    g_directional_locs.ambient       = rl.GetShaderLocation(g_directional_shader, "u_ambient")
    g_directional_locs.shadow_alpha  = rl.GetShaderLocation(g_directional_shader, "u_shadow_alpha")
    g_directional_locs.sun_color     = rl.GetShaderLocation(g_directional_shader, "u_sun_color")

    g_spritelight_shader = rl.LoadShader(nil, "data/shaders/sprite_light.fs")
    g_spritelight_locs.shadow_tex        = rl.GetShaderLocation(g_spritelight_shader, "u_shadow_tex")
    g_spritelight_locs.screen_size       = rl.GetShaderLocation(g_spritelight_shader, "u_screen_size")
    g_spritelight_locs.sun_dir           = rl.GetShaderLocation(g_spritelight_shader, "u_sun_dir")
    g_spritelight_locs.sun_color         = rl.GetShaderLocation(g_spritelight_shader, "u_sun_color")
    g_spritelight_locs.sun_intensity     = rl.GetShaderLocation(g_spritelight_shader, "u_sun_intensity")
    g_spritelight_locs.ambient           = rl.GetShaderLocation(g_spritelight_shader, "u_ambient")
    g_spritelight_locs.shadow_alpha      = rl.GetShaderLocation(g_spritelight_shader, "u_shadow_alpha")
    g_spritelight_locs.min_brightness    = rl.GetShaderLocation(g_spritelight_shader, "u_min_brightness")
    g_spritelight_locs.outline_strength  = rl.GetShaderLocation(g_spritelight_shader, "u_outline_strength")
    g_spritelight_locs.diffuse_strength  = rl.GetShaderLocation(g_spritelight_shader, "u_diffuse_strength")
    g_spritelight_locs.rim_strength      = rl.GetShaderLocation(g_spritelight_shader, "u_rim_strength")
    g_spritelight_locs.shadow_response   = rl.GetShaderLocation(g_spritelight_shader, "u_shadow_response")
    g_spritelight_locs.camera_target     = rl.GetShaderLocation(g_spritelight_shader, "u_camera_target")
    g_spritelight_locs.camera_offset     = rl.GetShaderLocation(g_spritelight_shader, "u_camera_offset")
    g_spritelight_locs.camera_zoom       = rl.GetShaderLocation(g_spritelight_shader, "u_camera_zoom")
    g_spritelight_locs.fog_scatter       = rl.GetShaderLocation(g_spritelight_shader, "u_fog_scatter")
    g_spritelight_locs.light_count       = rl.GetShaderLocation(g_spritelight_shader, "u_light_count")
    g_spritelight_locs.light_pos         = rl.GetShaderLocation(g_spritelight_shader, "u_light_pos")
    g_spritelight_locs.light_color       = rl.GetShaderLocation(g_spritelight_shader, "u_light_color")
    g_spritelight_locs.light_radius      = rl.GetShaderLocation(g_spritelight_shader, "u_light_radius")
    g_spritelight_locs.light_intensity   = rl.GetShaderLocation(g_spritelight_shader, "u_light_intensity")
    g_spritelight_locs.wall_mask         = rl.GetShaderLocation(g_spritelight_shader, "u_wall_mask")
    g_spritelight_locs.wall_origin       = rl.GetShaderLocation(g_spritelight_shader, "u_wall_origin")
    g_spritelight_locs.wall_size         = rl.GetShaderLocation(g_spritelight_shader, "u_wall_size")
    g_spritelight_locs.tile_size         = rl.GetShaderLocation(g_spritelight_shader, "u_tile_size")
}

shutdown_directional_shader :: proc() {
    if g_world_rt.id != 0 { rl.UnloadRenderTexture(g_world_rt) }
    if g_shadow_rt.id != 0 { rl.UnloadRenderTexture(g_shadow_rt) }
    if g_sprite_rt.id != 0 { rl.UnloadRenderTexture(g_sprite_rt) }
    rl.UnloadShader(g_directional_shader)
    rl.UnloadShader(g_spritelight_shader)
}

init_wall_mask :: proc() {
    g_wall_mask_dirty = true
}

shutdown_wall_mask :: proc() {
    if g_wall_mask.id != 0 { rl.UnloadRenderTexture(g_wall_mask) }
}

rebuild_wall_mask :: proc() {
    if !g_wall_mask_dirty { return }
    g_wall_mask_dirty = false

    if len(g_tilemap) == 0 {
        g_wall_mask_origin = { 0, 0 }
        g_wall_mask_size   = { 1, 1 }
        if g_wall_mask.id != 0 { rl.UnloadRenderTexture(g_wall_mask) }
        g_wall_mask = rl.LoadRenderTexture(1, 1)
        rl.BeginTextureMode(g_wall_mask)
        rl.ClearBackground(rl.BLACK)
        rl.EndTextureMode()
        return
    }

    min_tx, min_ty := max(int), max(int)
    max_tx, max_ty := min(int), min(int)
    for k in g_tilemap {
        min_tx = min(min_tx, k[0])
        min_ty = min(min_ty, k[1])
        max_tx = max(max_tx, k[0])
        max_ty = max(max_ty, k[1])
    }

    tw := max_tx - min_tx + 1
    th := max_ty - min_ty + 1

    tw = clamp(tw, 1, 1024)
    th = clamp(th, 1, 1024)

    if g_wall_mask.id == 0 || i32(tw) != g_wall_mask.texture.width || i32(th) != g_wall_mask.texture.height {
        if g_wall_mask.id != 0 { rl.UnloadRenderTexture(g_wall_mask) }
        g_wall_mask = rl.LoadRenderTexture(i32(tw), i32(th))
    }

    g_wall_mask_origin = { f32(min_tx), f32(min_ty) }
    g_wall_mask_size   = { f32(tw), f32(th) }

    rl.BeginTextureMode(g_wall_mask)
    rl.ClearBackground(rl.BLACK)
    for k, v in g_tilemap {
        if tile_base(v) != .Wall { continue }
        px := i32(k[0] - min_tx)
        py := i32(k[1] - min_ty)
        rl.DrawPixel(px, py, rl.WHITE)
    }
    rl.EndTextureMode()
}

ensure_lighting_render_targets :: proc() {
    sw := rl.GetScreenWidth()
    sh := rl.GetScreenHeight()
    if sw <= 0 || sh <= 0 { return }
    if g_light_rt_w == sw && g_light_rt_h == sh && g_world_rt.id != 0 && g_shadow_rt.id != 0 && g_sprite_rt.id != 0 { return }

    if g_world_rt.id != 0 { rl.UnloadRenderTexture(g_world_rt) }
    if g_shadow_rt.id != 0 { rl.UnloadRenderTexture(g_shadow_rt) }
    if g_sprite_rt.id != 0 { rl.UnloadRenderTexture(g_sprite_rt) }

    g_world_rt = rl.LoadRenderTexture(sw, sh)
    g_shadow_rt = rl.LoadRenderTexture(sw, sh)
    g_sprite_rt = rl.LoadRenderTexture(sw, sh)
    g_light_rt_w = sw
    g_light_rt_h = sh
}

MAX_POINT_LIGHTS :: 32

g_fog_color:   [3]f32 = { 8, 10, 14 }
g_fog_density: f32    = 0.55
g_fog_scatter: f32    = 1.35

@(private = "file") g_foglight_shader: rl.Shader
@(private = "file") g_foglight_locs: struct {
    screen_size:      c.int,
    camera_target:    c.int,
    camera_offset:    c.int,
    camera_zoom:      c.int,
    fog_color:        c.int,
    fog_density:      c.int,
    fog_scatter:      c.int,
    player_pos:       c.int,
    vision_radius:    c.int,
    vision_fade:      c.int,
    light_count:      c.int,
    light_pos:        c.int,
    light_color:      c.int,
    light_radius:     c.int,
    light_intensity:  c.int,
    wall_mask:        c.int,
    wall_origin:      c.int,
    wall_size:        c.int,
    tile_size:        c.int,
    pass:             c.int,
}

init_foglight_shader :: proc() {
    g_foglight_shader = rl.LoadShader(nil, "data/shaders/fog_lights.fs")
    g_foglight_locs.screen_size     = rl.GetShaderLocation(g_foglight_shader, "u_screen_size")
    g_foglight_locs.camera_target   = rl.GetShaderLocation(g_foglight_shader, "u_camera_target")
    g_foglight_locs.camera_offset   = rl.GetShaderLocation(g_foglight_shader, "u_camera_offset")
    g_foglight_locs.camera_zoom     = rl.GetShaderLocation(g_foglight_shader, "u_camera_zoom")
    g_foglight_locs.fog_color       = rl.GetShaderLocation(g_foglight_shader, "u_fog_color")
    g_foglight_locs.fog_density     = rl.GetShaderLocation(g_foglight_shader, "u_fog_density")
    g_foglight_locs.fog_scatter     = rl.GetShaderLocation(g_foglight_shader, "u_fog_scatter")
    g_foglight_locs.player_pos      = rl.GetShaderLocation(g_foglight_shader, "u_player_pos")
    g_foglight_locs.vision_radius   = rl.GetShaderLocation(g_foglight_shader, "u_vision_radius")
    g_foglight_locs.vision_fade     = rl.GetShaderLocation(g_foglight_shader, "u_vision_fade")
    g_foglight_locs.light_count     = rl.GetShaderLocation(g_foglight_shader, "u_light_count")
    g_foglight_locs.light_pos       = rl.GetShaderLocation(g_foglight_shader, "u_light_pos")
    g_foglight_locs.light_color     = rl.GetShaderLocation(g_foglight_shader, "u_light_color")
    g_foglight_locs.light_radius    = rl.GetShaderLocation(g_foglight_shader, "u_light_radius")
    g_foglight_locs.light_intensity = rl.GetShaderLocation(g_foglight_shader, "u_light_intensity")
    g_foglight_locs.wall_mask       = rl.GetShaderLocation(g_foglight_shader, "u_wall_mask")
    g_foglight_locs.wall_origin     = rl.GetShaderLocation(g_foglight_shader, "u_wall_origin")
    g_foglight_locs.wall_size       = rl.GetShaderLocation(g_foglight_shader, "u_wall_size")
    g_foglight_locs.tile_size       = rl.GetShaderLocation(g_foglight_shader, "u_tile_size")
    g_foglight_locs.pass            = rl.GetShaderLocation(g_foglight_shader, "u_pass")
}

shutdown_foglight_shader :: proc() {
    rl.UnloadShader(g_foglight_shader)
}

@(private = "file")
sun_dir :: proc() -> [2]f32 {
    inv_len := f32(1.0 / math.sqrt(g_light_sun_dir_x*g_light_sun_dir_x + g_light_sun_dir_y*g_light_sun_dir_y))
    return { g_light_sun_dir_x * inv_len, g_light_sun_dir_y * inv_len }
}

draw_cloud_shadow_field :: proc() {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    time        := f32(rl.GetTime())
    screen_size := [2]f32{ sw, sh }
    cam_target  := [2]f32{ g_camera.target.x, g_camera.target.y }
    cam_offset  := [2]f32{ g_camera.offset.x, g_camera.offset.y }
    cam_zoom    := g_camera.zoom
    drift       := [2]f32{ g_light_cloud_drift_x, g_light_cloud_drift_y }
    tint        := [3]f32{ g_light_cloud_tint_r, g_light_cloud_tint_g, g_light_cloud_tint_b }

    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.screen_size,     &screen_size,               .VEC2)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.camera_target,   &cam_target,                .VEC2)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.camera_offset,   &cam_offset,                .VEC2)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.camera_zoom,     &cam_zoom,                  .FLOAT)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.time,            &time,                      .FLOAT)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.cloud_freq,      &g_light_cloud_freq,        .FLOAT)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.cloud_freq_fine, &g_light_cloud_freq_fine,   .FLOAT)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.cloud_drift,     &drift,                     .VEC2)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.cloud_thresh_lo, &g_light_cloud_thresh_lo,   .FLOAT)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.cloud_thresh_hi, &g_light_cloud_thresh_hi,   .FLOAT)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.cloud_alpha_min, &g_light_cloud_alpha_min,   .FLOAT)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.cloud_alpha_max, &g_light_cloud_alpha_max,   .FLOAT)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.cloud_contrast,  &g_light_cloud_contrast,    .FLOAT)
    rl.SetShaderValue(g_cloud_shader, g_cloud_locs.cloud_tint,      &tint,                      .VEC3)

    rl.BeginShaderMode(g_cloud_shader)
    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.WHITE)
    rl.EndShaderMode()
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
            center := world_to_iso_xy(x + f32(TILE_SIZE) * 0.5 + dir[0] * off, y + f32(TILE_SIZE) * 0.5 + dir[1] * off)
            iso_draw_shadow_diamond(center, ISO_TILE_W * 2 * (1.0 + t * 0.08), ISO_TILE_H * 2 * (1.0 + t * 0.04), rl.Color{ 10, 10, 10, a })
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
    feet := world_to_iso_v({ tr.position[0], tr.position[1] })

    near_a := u8(clamp(f32(SHADOW_NEAR_ALPHA) * g_light_shadow_alpha, 0, 255))
    far_a  := u8(clamp(f32(SHADOW_FAR_ALPHA)  * g_light_shadow_alpha, 0, 255))

    draw_projected_sprite_shadow(
        frame.tex, frame.src, feet,
        frame.world_size, frame.aspect, frame.anchor, frame.ground, frame.flip_x,
        sun_dir(), g_light_sun_elevation,
        near_a, far_a, rl.Color{ 6, 7, 5, 255 },
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
        pos := rl.Vector2{ tr.position[0], tr.position[1] }
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
            cp := rl.Vector2{
                pos.x + dir[0] * off,
                pos.y + dir[1] * off,
            }
            r := radius * (0.9 - t_frac * 0.18)
            a := u8(clamp(180 * (1.0 - t_frac * 0.42), 0, 255))
            icp := world_to_iso_v(cp)
            rl.DrawEllipse(i32(icp.x), i32(icp.y), r * 1.08, max(r * 0.42, 1), rl.Color{ 6, 6, 4, a })
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

            shadow_pos := rl.Vector2{
                pos.x + dir[0] * offset,
                pos.y + dir[1] * offset,
            }
            if top_down {
                draw_player_sprite(entry.tex, src, shadow_pos, world_size, rl.Color{ 8, 10, 6, a }, anchor)
            } else {
                draw_entity_sprite_quad_ex(entry.tex, src, shadow_pos, world_size, rot, rl.Color{ 8, 10, 6, a }, ISO_SPRITE_Y, anchor)
            }
        }
    }
}

draw_directional_shadow_mask :: proc(w: ^World) {
    ensure_lighting_render_targets()
    if g_shadow_rt.id == 0 { return }

    rl.BeginTextureMode(g_shadow_rt)
    rl.ClearBackground(rl.BLANK)
    rl.BeginMode2D(g_camera^)
    draw_wall_sun_shadows()
    rl.EndMode2D()
    rl.EndTextureMode()
}

draw_directional_world_composite :: proc() {
    ensure_lighting_render_targets()
    if g_world_rt.id == 0 || g_shadow_rt.id == 0 { return }

    screen_size := [2]f32{ f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) }
    sd := sun_dir()
    sun_color := [3]f32{ g_light_sun_color_r / 255.0, g_light_sun_color_g / 255.0, g_light_sun_color_b / 255.0 }

    rl.SetShaderValue(g_directional_shader, g_directional_locs.screen_size,   &screen_size,            .VEC2)
    rl.SetShaderValue(g_directional_shader, g_directional_locs.sun_dir,       &sd,                     .VEC2)
    rl.SetShaderValue(g_directional_shader, g_directional_locs.sun_intensity, &g_light_sun_intensity,  .FLOAT)
    rl.SetShaderValue(g_directional_shader, g_directional_locs.ambient,       &g_light_ambient,        .FLOAT)
    rl.SetShaderValue(g_directional_shader, g_directional_locs.shadow_alpha,  &g_light_shadow_alpha,   .FLOAT)
    rl.SetShaderValue(g_directional_shader, g_directional_locs.sun_color,     &sun_color,              .VEC3)

    world_src := rl.Rectangle{ 0, 0, f32(g_world_rt.texture.width), -f32(g_world_rt.texture.height) }
    dst       := rl.Rectangle{ 0, 0, screen_size[0], screen_size[1] }

    rl.BeginShaderMode(g_directional_shader)
    rl.SetShaderValueTexture(g_directional_shader, g_directional_locs.shadow_tex, g_shadow_rt.texture)
    rl.DrawTexturePro(g_world_rt.texture, world_src, dst, { 0, 0 }, 0, rl.WHITE)
    rl.EndShaderMode()
}

draw_directional_sprite_composite :: proc(w: ^World) {
    ensure_lighting_render_targets()
    if g_sprite_rt.id == 0 || g_shadow_rt.id == 0 { return }

    light_ids := world_query(w, query_mask(.PointLight, .Transform))
    defer delete(light_ids)

    light_count := min(len(light_ids), MAX_POINT_LIGHTS)

    positions:   [MAX_POINT_LIGHTS][2]f32
    colors:      [MAX_POINT_LIGHTS][3]f32
    radii:       [MAX_POINT_LIGHTS]f32
    intensities: [MAX_POINT_LIGHTS]f32

    for i in 0..<light_count {
        id := light_ids[i]
        t  := comp_get(w, id, .Transform, TransformComp)
        pl := comp_get(w, id, .PointLight, PointLightComp)
        positions[i]   = { t.position[0], t.position[1] }
        colors[i]      = pl.color
        radii[i]       = pl.radius
        intensities[i] = pl.intensity
    }

    screen_size := [2]f32{ f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight()) }
    sprite_src  := rl.Rectangle{ 0, 0, f32(g_sprite_rt.texture.width), -f32(g_sprite_rt.texture.height) }
    dst         := rl.Rectangle{ 0, 0, screen_size[0], screen_size[1] }
    sd          := sun_dir()
    sun_color   := [3]f32{ g_light_sun_color_r / 255.0, g_light_sun_color_g / 255.0, g_light_sun_color_b / 255.0 }
    cam_target  := [2]f32{ g_camera.target.x, g_camera.target.y }
    cam_offset  := [2]f32{ g_camera.offset.x, g_camera.offset.y }
    cam_zoom    := g_camera.zoom
    lc          := c.int(light_count)

    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.screen_size,      &screen_size,                   .VEC2)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.sun_dir,          &sd,                            .VEC2)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.sun_color,        &sun_color,                     .VEC3)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.sun_intensity,    &g_light_sun_intensity,         .FLOAT)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.ambient,          &g_light_ambient,               .FLOAT)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.shadow_alpha,     &g_light_shadow_alpha,          .FLOAT)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.min_brightness,   &g_light_sprite_min_brightness, .FLOAT)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.outline_strength, &g_light_sprite_outline,        .FLOAT)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.diffuse_strength, &g_light_sprite_diffuse,        .FLOAT)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.rim_strength,     &g_light_sprite_rim,            .FLOAT)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.shadow_response,  &g_light_sprite_shadow_response,.FLOAT)

    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.camera_target,    &cam_target,                    .VEC2)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.camera_offset,    &cam_offset,                    .VEC2)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.camera_zoom,      &cam_zoom,                      .FLOAT)

    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.fog_scatter,      &g_fog_scatter,                 .FLOAT)

    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.light_count,      &lc,                            .INT)
    if light_count > 0 {
        rl.SetShaderValueV(g_spritelight_shader, g_spritelight_locs.light_pos,       &positions,   .VEC2,  c.int(light_count))
        rl.SetShaderValueV(g_spritelight_shader, g_spritelight_locs.light_color,     &colors,      .VEC3,  c.int(light_count))
        rl.SetShaderValueV(g_spritelight_shader, g_spritelight_locs.light_radius,    &radii,       .FLOAT, c.int(light_count))
        rl.SetShaderValueV(g_spritelight_shader, g_spritelight_locs.light_intensity, &intensities, .FLOAT, c.int(light_count))
    }

    tile_size_f := f32(TILE_SIZE)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.wall_origin,  &g_wall_mask_origin, .VEC2)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.wall_size,    &g_wall_mask_size,   .VEC2)
    rl.SetShaderValue(g_spritelight_shader, g_spritelight_locs.tile_size,    &tile_size_f,        .FLOAT)

    rl.BeginShaderMode(g_spritelight_shader)
    rl.SetShaderValueTexture(g_spritelight_shader, g_spritelight_locs.shadow_tex, g_shadow_rt.texture)
    if g_wall_mask.id != 0 {
        rl.SetShaderValueTexture(g_spritelight_shader, g_spritelight_locs.wall_mask, g_wall_mask.texture)
    }
    rl.DrawTexturePro(g_sprite_rt.texture, sprite_src, dst, { 0, 0 }, 0, rl.WHITE)
    rl.EndShaderMode()
}

draw_world_god_rays :: proc() {
    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())

    time        := f32(rl.GetTime())
    screen_size := [2]f32{ sw, sh }
    cam_target  := [2]f32{ g_camera.target.x, g_camera.target.y }
    cam_offset  := [2]f32{ g_camera.offset.x, g_camera.offset.y }
    cam_zoom    := g_camera.zoom
    sd          := sun_dir()

    rl.SetShaderValue(g_godray_shader, g_godray_locs.screen_size,   &screen_size,                .VEC2)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.camera_target, &cam_target,                 .VEC2)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.camera_offset, &cam_offset,                 .VEC2)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.camera_zoom,   &cam_zoom,                   .FLOAT)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.time,          &time,                       .FLOAT)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.sun_dir,       &sd,                         .VEC2)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.ray_spacing,   &g_light_god_ray_spacing,    .FLOAT)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.ray_width,     &g_light_god_ray_width,      .FLOAT)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.ray_thresh,    &g_light_god_ray_thresh,     .FLOAT)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.ray_alpha,     &g_light_god_ray_alpha,      .FLOAT)

    drift := [2]f32{ g_light_cloud_drift_x, g_light_cloud_drift_y }
    rl.SetShaderValue(g_godray_shader, g_godray_locs.cloud_freq,      &g_light_cloud_freq,        .FLOAT)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.cloud_freq_fine, &g_light_cloud_freq_fine,   .FLOAT)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.cloud_drift,     &drift,                     .VEC2)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.cloud_thresh_lo, &g_light_cloud_thresh_lo,   .FLOAT)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.cloud_thresh_hi, &g_light_cloud_thresh_hi,   .FLOAT)
    rl.SetShaderValue(g_godray_shader, g_godray_locs.cloud_contrast,  &g_light_cloud_contrast,    .FLOAT)

    rl.BeginBlendMode(.ADDITIVE)
    rl.BeginShaderMode(g_godray_shader)
    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.WHITE)
    rl.EndShaderMode()
    rl.EndBlendMode()
}

draw_fog_and_lights :: proc(w: ^World) {
    ids := world_query(w, query_mask(.PointLight, .Transform))
    defer delete(ids)

    count := min(len(ids), MAX_POINT_LIGHTS)

    positions:   [MAX_POINT_LIGHTS][2]f32
    colors:      [MAX_POINT_LIGHTS][3]f32
    radii:       [MAX_POINT_LIGHTS]f32
    intensities: [MAX_POINT_LIGHTS]f32

    for i in 0..<count {
        id := ids[i]
        t  := comp_get(w, id, .Transform, TransformComp)
        pl := comp_get(w, id, .PointLight, PointLightComp)
        positions[i]   = { t.position[0], t.position[1] }
        colors[i]      = pl.color
        radii[i]       = pl.radius
        intensities[i] = pl.intensity
    }

    sw := f32(rl.GetScreenWidth())
    sh := f32(rl.GetScreenHeight())
    screen_size := [2]f32{ sw, sh }
    cam_target  := [2]f32{ g_camera.target.x, g_camera.target.y }
    cam_offset  := [2]f32{ g_camera.offset.x, g_camera.offset.y }
    cam_zoom    := g_camera.zoom
    light_count := c.int(count)

    player_pos    := [2]f32{ 0, 0 }
    vision_radius := f32(0)
    vision_fade   := f32(0)
    if world_is_valid(w, w.player_id) &&
       world_has_component(w, w.player_id, .Transform) {
        pp := comp_get(w, w.player_id, .Transform, TransformComp).position
        player_pos = { pp[0], pp[1] }
        vision_radius = FOG_VISION_RADIUS
        vision_fade   = FOG_FADE_WIDTH
        if world_has_component(w, w.player_id, .Stats) {
            vision_radius += comp_get(w, w.player_id, .Stats, StatsComp).vision_bonus
        }
    }

    rebuild_wall_mask()

    tile_size_f := f32(TILE_SIZE)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.wall_origin,    &g_wall_mask_origin, .VEC2)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.wall_size,      &g_wall_mask_size,   .VEC2)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.tile_size,      &tile_size_f,        .FLOAT)

    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.screen_size,    &screen_size,   .VEC2)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.camera_target,  &cam_target,    .VEC2)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.camera_offset,  &cam_offset,    .VEC2)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.camera_zoom,    &cam_zoom,      .FLOAT)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.fog_color,      &g_fog_color,   .VEC3)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.fog_density,    &g_fog_density, .FLOAT)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.fog_scatter,    &g_fog_scatter, .FLOAT)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.player_pos,     &player_pos,    .VEC2)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.vision_radius,  &vision_radius, .FLOAT)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.vision_fade,    &vision_fade,   .FLOAT)
    rl.SetShaderValue(g_foglight_shader,  g_foglight_locs.light_count,    &light_count,   .INT)
    if count > 0 {
        rl.SetShaderValueV(g_foglight_shader, g_foglight_locs.light_pos,       &positions,   .VEC2,  c.int(count))
        rl.SetShaderValueV(g_foglight_shader, g_foglight_locs.light_color,     &colors,      .VEC3,  c.int(count))
        rl.SetShaderValueV(g_foglight_shader, g_foglight_locs.light_radius,    &radii,       .FLOAT, c.int(count))
        rl.SetShaderValueV(g_foglight_shader, g_foglight_locs.light_intensity, &intensities, .FLOAT, c.int(count))
    }

    pass := c.int(0)
    rl.SetShaderValue(g_foglight_shader, g_foglight_locs.pass, &pass, .INT)
    rl.BeginShaderMode(g_foglight_shader)
    if g_wall_mask.id != 0 {
        rl.SetShaderValueTexture(g_foglight_shader, g_foglight_locs.wall_mask, g_wall_mask.texture)
    }
    rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.WHITE)
    rl.EndShaderMode()

    if count > 0 {
        pass = c.int(1)
        rl.SetShaderValue(g_foglight_shader, g_foglight_locs.pass, &pass, .INT)
        rl.BeginBlendMode(.ADDITIVE)
        rl.BeginShaderMode(g_foglight_shader)
        if g_wall_mask.id != 0 {
            rl.SetShaderValueTexture(g_foglight_shader, g_foglight_locs.wall_mask, g_wall_mask.texture)
        }
        rl.DrawRectangle(0, 0, i32(sw), i32(sh), rl.WHITE)
        rl.EndShaderMode()
        rl.EndBlendMode()
    }
}

update_lighting_widget :: proc() {
    if !devui_wants_text() && rl.IsKeyPressed(.F2) {
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
