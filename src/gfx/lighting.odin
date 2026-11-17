package gfx

// The 2D lighting passes (docs/BACKEND_SWAP_PLAN.md §3.7, decision D6).
//
// Game code fills typed parameters and calls one procedure per pass; the shader plumbing lives
// here. That keeps uniform layouts, texture bindings and blend modes on this side of the boundary,
// which is what makes the sokol port a change to this file only.
//
// P1b replaces this whole stack with 3D lighting.

MAX_LIGHTS :: 32

// Point lights, in world units. Colours are 0..255, as the shaders expect.
Lights :: struct {
    count:     i32,
    pos:       [MAX_LIGHTS][2]f32,
    color:     [MAX_LIGHTS][3]f32,
    radius:    [MAX_LIGHTS]f32,
    intensity: [MAX_LIGHTS]f32,
}

// The camera, as the screen-space reconstruction in the shaders needs it.
View_Params :: struct {
    cam_target: [2]f32,
    cam_offset: [2]f32,
    cam_zoom:   f32,
}

Directional_Params :: struct {
    sun_dir:       [2]f32,
    sun_color:     [3]f32, // 0..1
    sun_intensity: f32,
    ambient:       f32,
    shadow_alpha:  f32,
}

Sprite_Light_Params :: struct {
    view:            View_Params,
    sun_dir:         [2]f32,
    sun_color:       [3]f32, // 0..1
    sun_intensity:   f32,
    ambient:         f32,
    shadow_alpha:    f32,
    min_brightness:  f32,
    outline:         f32,
    diffuse:         f32,
    rim:             f32,
    shadow_response: f32,
    fog_scatter:     f32,
    wall_origin:     [2]f32,
    wall_size:       [2]f32,
    tile_size:       f32,
    lights:          Lights,
}

Fog_Params :: struct {
    view:          View_Params,
    fog_color:     [3]f32, // 0..1
    fog_density:   f32,
    fog_scatter:   f32,
    player_pos:    [2]f32,
    vision_radius: f32,
    vision_fade:   f32,
    wall_origin:   [2]f32,
    wall_size:     [2]f32,
    tile_size:     f32,
    lights:        Lights,
}

Cloud_Params :: struct {
    view:        View_Params,
    time:        f32,
    freq:        f32,
    freq_fine:   f32,
    drift:       [2]f32,
    thresh_lo:   f32,
    thresh_hi:   f32,
    alpha_min:   f32,
    alpha_max:   f32,
    contrast:    f32,
    tint:        [3]f32, // 0..1
}

God_Ray_Params :: struct {
    view:        View_Params,
    time:        f32,
    sun_dir:     [2]f32,
    ray_spacing: f32,
    ray_width:   f32,
    ray_thresh:  f32,
    ray_alpha:   f32,
    freq:        f32,
    freq_fine:   f32,
    drift:       [2]f32,
    thresh_lo:   f32,
    thresh_hi:   f32,
    contrast:    f32,
}

// ---- raylib implementation --------------------------------------------------------------------

@(private = "file") _directional: struct {
    shader: Backend_Shader,
    shadow_tex, screen_size, sun_dir, sun_intensity, ambient, shadow_alpha, sun_color: i32,
}

@(private = "file") _sprite: struct {
    shader: Backend_Shader,
    shadow_tex, screen_size, sun_dir, sun_color, sun_intensity, ambient, shadow_alpha: i32,
    min_brightness, outline, diffuse, rim, shadow_response:                            i32,
    cam_target, cam_offset, cam_zoom, fog_scatter:                                     i32,
    light_count, light_pos, light_color, light_radius, light_intensity:                i32,
    wall_mask, wall_origin, wall_size, tile_size:                                      i32,
}

@(private = "file") _fog: struct {
    shader: Backend_Shader,
    screen_size, cam_target, cam_offset, cam_zoom:                      i32,
    fog_color, fog_density, fog_scatter:                                i32,
    player_pos, vision_radius, vision_fade:                             i32,
    light_count, light_pos, light_color, light_radius, light_intensity: i32,
    wall_mask, wall_origin, wall_size, tile_size, pass:                 i32,
}

@(private = "file") _cloud: struct {
    shader: Backend_Shader,
    screen_size, cam_target, cam_offset, cam_zoom, time:                 i32,
    freq, freq_fine, drift, thresh_lo, thresh_hi:                        i32,
    alpha_min, alpha_max, contrast, tint:                                i32,
}

@(private = "file") _god: struct {
    shader: Backend_Shader,
    screen_size, cam_target, cam_offset, cam_zoom, time, sun_dir:        i32,
    ray_spacing, ray_width, ray_thresh, ray_alpha:                       i32,
    freq, freq_fine, drift, thresh_lo, thresh_hi, contrast:              i32,
}

lighting_init :: proc() {
    s := _b_load_shader_fs("data/shaders/directional_light.fs")
    _directional.shader        = s
    _directional.shadow_tex    = _b_shader_loc(s, "u_shadow_tex")
    _directional.screen_size   = _b_shader_loc(s, "u_screen_size")
    _directional.sun_dir       = _b_shader_loc(s, "u_sun_dir")
    _directional.sun_intensity = _b_shader_loc(s, "u_sun_intensity")
    _directional.ambient       = _b_shader_loc(s, "u_ambient")
    _directional.shadow_alpha  = _b_shader_loc(s, "u_shadow_alpha")
    _directional.sun_color     = _b_shader_loc(s, "u_sun_color")

    s = _b_load_shader_fs("data/shaders/sprite_light.fs")
    _sprite.shader          = s
    _sprite.shadow_tex      = _b_shader_loc(s, "u_shadow_tex")
    _sprite.screen_size     = _b_shader_loc(s, "u_screen_size")
    _sprite.sun_dir         = _b_shader_loc(s, "u_sun_dir")
    _sprite.sun_color       = _b_shader_loc(s, "u_sun_color")
    _sprite.sun_intensity   = _b_shader_loc(s, "u_sun_intensity")
    _sprite.ambient         = _b_shader_loc(s, "u_ambient")
    _sprite.shadow_alpha    = _b_shader_loc(s, "u_shadow_alpha")
    _sprite.min_brightness  = _b_shader_loc(s, "u_min_brightness")
    _sprite.outline         = _b_shader_loc(s, "u_outline_strength")
    _sprite.diffuse         = _b_shader_loc(s, "u_diffuse_strength")
    _sprite.rim             = _b_shader_loc(s, "u_rim_strength")
    _sprite.shadow_response = _b_shader_loc(s, "u_shadow_response")
    _sprite.cam_target      = _b_shader_loc(s, "u_camera_target")
    _sprite.cam_offset      = _b_shader_loc(s, "u_camera_offset")
    _sprite.cam_zoom        = _b_shader_loc(s, "u_camera_zoom")
    _sprite.fog_scatter     = _b_shader_loc(s, "u_fog_scatter")
    _sprite.light_count     = _b_shader_loc(s, "u_light_count")
    _sprite.light_pos       = _b_shader_loc(s, "u_light_pos")
    _sprite.light_color     = _b_shader_loc(s, "u_light_color")
    _sprite.light_radius    = _b_shader_loc(s, "u_light_radius")
    _sprite.light_intensity = _b_shader_loc(s, "u_light_intensity")
    _sprite.wall_mask       = _b_shader_loc(s, "u_wall_mask")
    _sprite.wall_origin     = _b_shader_loc(s, "u_wall_origin")
    _sprite.wall_size       = _b_shader_loc(s, "u_wall_size")
    _sprite.tile_size       = _b_shader_loc(s, "u_tile_size")

    s = _b_load_shader_fs("data/shaders/fog_lights.fs")
    _fog.shader          = s
    _fog.screen_size     = _b_shader_loc(s, "u_screen_size")
    _fog.cam_target      = _b_shader_loc(s, "u_camera_target")
    _fog.cam_offset      = _b_shader_loc(s, "u_camera_offset")
    _fog.cam_zoom        = _b_shader_loc(s, "u_camera_zoom")
    _fog.fog_color       = _b_shader_loc(s, "u_fog_color")
    _fog.fog_density     = _b_shader_loc(s, "u_fog_density")
    _fog.fog_scatter     = _b_shader_loc(s, "u_fog_scatter")
    _fog.player_pos      = _b_shader_loc(s, "u_player_pos")
    _fog.vision_radius   = _b_shader_loc(s, "u_vision_radius")
    _fog.vision_fade     = _b_shader_loc(s, "u_vision_fade")
    _fog.light_count     = _b_shader_loc(s, "u_light_count")
    _fog.light_pos       = _b_shader_loc(s, "u_light_pos")
    _fog.light_color     = _b_shader_loc(s, "u_light_color")
    _fog.light_radius    = _b_shader_loc(s, "u_light_radius")
    _fog.light_intensity = _b_shader_loc(s, "u_light_intensity")
    _fog.wall_mask       = _b_shader_loc(s, "u_wall_mask")
    _fog.wall_origin     = _b_shader_loc(s, "u_wall_origin")
    _fog.wall_size       = _b_shader_loc(s, "u_wall_size")
    _fog.tile_size       = _b_shader_loc(s, "u_tile_size")
    _fog.pass            = _b_shader_loc(s, "u_pass")

    s = _b_load_shader_fs("data/shaders/cloud_shadow.fs")
    _cloud.shader      = s
    _cloud.screen_size = _b_shader_loc(s, "u_screen_size")
    _cloud.cam_target  = _b_shader_loc(s, "u_camera_target")
    _cloud.cam_offset  = _b_shader_loc(s, "u_camera_offset")
    _cloud.cam_zoom    = _b_shader_loc(s, "u_camera_zoom")
    _cloud.time        = _b_shader_loc(s, "u_time")
    _cloud.freq        = _b_shader_loc(s, "u_cloud_freq")
    _cloud.freq_fine   = _b_shader_loc(s, "u_cloud_freq_fine")
    _cloud.drift       = _b_shader_loc(s, "u_cloud_drift")
    _cloud.thresh_lo   = _b_shader_loc(s, "u_cloud_thresh_lo")
    _cloud.thresh_hi   = _b_shader_loc(s, "u_cloud_thresh_hi")
    _cloud.alpha_min   = _b_shader_loc(s, "u_cloud_alpha_min")
    _cloud.alpha_max   = _b_shader_loc(s, "u_cloud_alpha_max")
    _cloud.contrast    = _b_shader_loc(s, "u_cloud_contrast")
    _cloud.tint        = _b_shader_loc(s, "u_cloud_tint")

    s = _b_load_shader_fs("data/shaders/god_rays.fs")
    _god.shader      = s
    _god.screen_size = _b_shader_loc(s, "u_screen_size")
    _god.cam_target  = _b_shader_loc(s, "u_camera_target")
    _god.cam_offset  = _b_shader_loc(s, "u_camera_offset")
    _god.cam_zoom    = _b_shader_loc(s, "u_camera_zoom")
    _god.time        = _b_shader_loc(s, "u_time")
    _god.sun_dir     = _b_shader_loc(s, "u_sun_dir")
    _god.ray_spacing = _b_shader_loc(s, "u_ray_spacing")
    _god.ray_width   = _b_shader_loc(s, "u_ray_width")
    _god.ray_thresh  = _b_shader_loc(s, "u_ray_thresh")
    _god.ray_alpha   = _b_shader_loc(s, "u_ray_alpha")
    _god.freq        = _b_shader_loc(s, "u_cloud_freq")
    _god.freq_fine   = _b_shader_loc(s, "u_cloud_freq_fine")
    _god.drift       = _b_shader_loc(s, "u_cloud_drift")
    _god.thresh_lo   = _b_shader_loc(s, "u_cloud_thresh_lo")
    _god.thresh_hi   = _b_shader_loc(s, "u_cloud_thresh_hi")
    _god.contrast    = _b_shader_loc(s, "u_cloud_contrast")
}

lighting_shutdown :: proc() {
    _b_unload_shader(_directional.shader)
    _b_unload_shader(_sprite.shader)
    _b_unload_shader(_fog.shader)
    _b_unload_shader(_cloud.shader)
    _b_unload_shader(_god.shader)
}

@(private = "file")
_screen_size :: proc() -> [2]f32 {
    return { f32(screen_width()), f32(screen_height()) }
}

@(private = "file")
_set_view :: proc(s: Backend_Shader, target_loc, offset_loc, zoom_loc: i32, v: View_Params) {
    _b_set_vec2(s, target_loc, v.cam_target)
    _b_set_vec2(s, offset_loc, v.cam_offset)
    _b_set_f32(s, zoom_loc, v.cam_zoom)
}

@(private = "file")
_set_lights :: proc(s: Backend_Shader, count_loc, pos_loc, color_loc, radius_loc, intensity_loc: i32, l: Lights) {
    _b_set_i32(s, count_loc, l.count)
    if l.count <= 0 { return }
    pos, color, radius, intensity := l.pos, l.color, l.radius, l.intensity
    _b_set_vec2_array(s, pos_loc, pos[:], l.count)
    _b_set_vec3_array(s, color_loc, color[:], l.count)
    _b_set_f32_array(s, radius_loc, radius[:], l.count)
    _b_set_f32_array(s, intensity_loc, intensity[:], l.count)
}

// Composites the lit world: `world` through the directional shader, shadowed by `shadow`.
lighting_directional :: proc(world, shadow: Texture, p: Directional_Params) {
    ss := _screen_size()
    s  := _directional.shader
    _b_set_vec2(s, _directional.screen_size, ss)
    _b_set_vec2(s, _directional.sun_dir, p.sun_dir)
    _b_set_f32(s, _directional.sun_intensity, p.sun_intensity)
    _b_set_f32(s, _directional.ambient, p.ambient)
    _b_set_f32(s, _directional.shadow_alpha, p.shadow_alpha)
    _b_set_vec3(s, _directional.sun_color, p.sun_color)

    _b_shader_begin(s)
    _b_set_texture(s, _directional.shadow_tex, shadow)
    draw_texture_pro(world, texture_src(world), { 0, 0, ss[0], ss[1] }, { 0, 0 }, 0, WHITE)
    _b_shader_end()
}

// Composites the sprite layer: lighting, outline and rim, shadowed by `shadow` and occluded by
// `wall_mask` (pass a zero Texture for none).
lighting_sprite :: proc(sprite, shadow, wall_mask: Texture, p: Sprite_Light_Params) {
    ss := _screen_size()
    s  := _sprite.shader
    _b_set_vec2(s, _sprite.screen_size, ss)
    _b_set_vec2(s, _sprite.sun_dir, p.sun_dir)
    _b_set_vec3(s, _sprite.sun_color, p.sun_color)
    _b_set_f32(s, _sprite.sun_intensity, p.sun_intensity)
    _b_set_f32(s, _sprite.ambient, p.ambient)
    _b_set_f32(s, _sprite.shadow_alpha, p.shadow_alpha)
    _b_set_f32(s, _sprite.min_brightness, p.min_brightness)
    _b_set_f32(s, _sprite.outline, p.outline)
    _b_set_f32(s, _sprite.diffuse, p.diffuse)
    _b_set_f32(s, _sprite.rim, p.rim)
    _b_set_f32(s, _sprite.shadow_response, p.shadow_response)
    _set_view(s, _sprite.cam_target, _sprite.cam_offset, _sprite.cam_zoom, p.view)
    _b_set_f32(s, _sprite.fog_scatter, p.fog_scatter)
    _set_lights(s, _sprite.light_count, _sprite.light_pos, _sprite.light_color, _sprite.light_radius, _sprite.light_intensity, p.lights)
    _b_set_vec2(s, _sprite.wall_origin, p.wall_origin)
    _b_set_vec2(s, _sprite.wall_size, p.wall_size)
    _b_set_f32(s, _sprite.tile_size, p.tile_size)

    _b_shader_begin(s)
    _b_set_texture(s, _sprite.shadow_tex, shadow)
    if wall_mask.id != 0 { _b_set_texture(s, _sprite.wall_mask, wall_mask) }
    draw_texture_pro(sprite, texture_src(sprite), { 0, 0, ss[0], ss[1] }, { 0, 0 }, 0, WHITE)
    _b_shader_end()
}

// Fog, vision radius and point lights over the whole screen. Two passes: fog (alpha) and, when
// there are lights, their contribution (additive).
lighting_fog :: proc(wall_mask: Texture, p: Fog_Params) {
    ss := _screen_size()
    s  := _fog.shader
    _b_set_vec2(s, _fog.screen_size, ss)
    _set_view(s, _fog.cam_target, _fog.cam_offset, _fog.cam_zoom, p.view)
    _b_set_vec3(s, _fog.fog_color, p.fog_color)
    _b_set_f32(s, _fog.fog_density, p.fog_density)
    _b_set_f32(s, _fog.fog_scatter, p.fog_scatter)
    _b_set_vec2(s, _fog.player_pos, p.player_pos)
    _b_set_f32(s, _fog.vision_radius, p.vision_radius)
    _b_set_f32(s, _fog.vision_fade, p.vision_fade)
    _set_lights(s, _fog.light_count, _fog.light_pos, _fog.light_color, _fog.light_radius, _fog.light_intensity, p.lights)
    _b_set_vec2(s, _fog.wall_origin, p.wall_origin)
    _b_set_vec2(s, _fog.wall_size, p.wall_size)
    _b_set_f32(s, _fog.tile_size, p.tile_size)

    _b_set_i32(s, _fog.pass, 0)
    _b_shader_begin(s)
    if wall_mask.id != 0 { _b_set_texture(s, _fog.wall_mask, wall_mask) }
    draw_rect(0, 0, i32(ss[0]), i32(ss[1]), WHITE)
    _b_shader_end()

    if p.lights.count > 0 {
        _b_set_i32(s, _fog.pass, 1)
        blend_begin(.Additive)
        _b_shader_begin(s)
        if wall_mask.id != 0 { _b_set_texture(s, _fog.wall_mask, wall_mask) }
        draw_rect(0, 0, i32(ss[0]), i32(ss[1]), WHITE)
        _b_shader_end()
        blend_end()
    }
}

// Drifting cloud shadows over the world. Stubbed on sokol until P1b (decision D6).
lighting_clouds :: proc(p: Cloud_Params) {
    ss := _screen_size()
    s  := _cloud.shader
    _b_set_vec2(s, _cloud.screen_size, ss)
    _set_view(s, _cloud.cam_target, _cloud.cam_offset, _cloud.cam_zoom, p.view)
    _b_set_f32(s, _cloud.time, p.time)
    _b_set_f32(s, _cloud.freq, p.freq)
    _b_set_f32(s, _cloud.freq_fine, p.freq_fine)
    _b_set_vec2(s, _cloud.drift, p.drift)
    _b_set_f32(s, _cloud.thresh_lo, p.thresh_lo)
    _b_set_f32(s, _cloud.thresh_hi, p.thresh_hi)
    _b_set_f32(s, _cloud.alpha_min, p.alpha_min)
    _b_set_f32(s, _cloud.alpha_max, p.alpha_max)
    _b_set_f32(s, _cloud.contrast, p.contrast)
    _b_set_vec3(s, _cloud.tint, p.tint)

    _b_shader_begin(s)
    draw_rect(0, 0, i32(ss[0]), i32(ss[1]), WHITE)
    _b_shader_end()
}

// Sun shafts, drawn additively. Stubbed on sokol until P1b (decision D6).
lighting_god_rays :: proc(p: God_Ray_Params) {
    ss := _screen_size()
    s  := _god.shader
    _b_set_vec2(s, _god.screen_size, ss)
    _set_view(s, _god.cam_target, _god.cam_offset, _god.cam_zoom, p.view)
    _b_set_f32(s, _god.time, p.time)
    _b_set_vec2(s, _god.sun_dir, p.sun_dir)
    _b_set_f32(s, _god.ray_spacing, p.ray_spacing)
    _b_set_f32(s, _god.ray_width, p.ray_width)
    _b_set_f32(s, _god.ray_thresh, p.ray_thresh)
    _b_set_f32(s, _god.ray_alpha, p.ray_alpha)
    _b_set_f32(s, _god.freq, p.freq)
    _b_set_f32(s, _god.freq_fine, p.freq_fine)
    _b_set_vec2(s, _god.drift, p.drift)
    _b_set_f32(s, _god.thresh_lo, p.thresh_lo)
    _b_set_f32(s, _god.thresh_hi, p.thresh_hi)
    _b_set_f32(s, _god.contrast, p.contrast)

    blend_begin(.Additive)
    _b_shader_begin(s)
    draw_rect(0, 0, i32(ss[0]), i32(ss[1]), WHITE)
    _b_shader_end()
    blend_end()
}
