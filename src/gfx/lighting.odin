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

// ---- public API ------------------------------------------------------------------------------

@(private)
_screen_size :: proc() -> [2]f32 {
    return { f32(screen_width()), f32(screen_height()) }
}

lighting_init     :: proc() { /* pipelines are built with the rest of the GPU state */ }
lighting_shutdown :: proc() {}

// Composites the lit world: `world` through the directional shader, shadowed by `shadow`.
lighting_directional :: proc(world, shadow: Texture, p: Directional_Params) {
    _b_lighting_directional(world, shadow, p)
}

// Composites the sprite layer: lighting, outline and rim, shadowed by `shadow` and occluded by
// `wall_mask` (pass a zero Texture for none).
lighting_sprite :: proc(sprite, shadow, wall_mask: Texture, p: Sprite_Light_Params) {
    _b_lighting_sprite(sprite, shadow, wall_mask, p)
}

// Fog, vision radius and point lights over the whole screen.
lighting_fog :: proc(wall_mask: Texture, p: Fog_Params) {
    _b_lighting_fog(wall_mask, p)
}

// Drifting cloud shadows. Stubbed on sokol until P1b (decision D6).
lighting_clouds :: proc(p: Cloud_Params) { _b_lighting_clouds(p) }

// Sun shafts. Stubbed on sokol until P1b (decision D6).
lighting_god_rays :: proc(p: God_Ray_Params) { _b_lighting_god_rays(p) }
