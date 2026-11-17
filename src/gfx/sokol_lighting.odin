package gfx

// The lighting passes on sokol (docs/BACKEND_SWAP_PLAN.md §3.7, decision D6).
//
// Each is a fullscreen triangle with its own pipeline and one std140 uniform block, recorded as a
// custom draw so it lands in the right pass in the right order (sokol_backend.odin).
//
// Clouds and god rays are stubs until P1b replaces this whole stack with 3D lighting.

import "core:c"

import sg  "sokol:gfx"
import shd_dir    "shaders/directional"
import shd_sprite "shaders/sprite_light"
import shd_fog    "shaders/fog_lights"

Directional_GPU :: shd_dir.Directional_Params
Sprite_GPU      :: shd_sprite.Sprite_Light_Params
Fog_GPU         :: shd_fog.Fog_Lights_Params

@(private) _light: struct {
    pip_directional: sg.Pipeline,
    pip_sprite:      sg.Pipeline,
    pip_fog_alpha:   sg.Pipeline,
    pip_fog_add:     sg.Pipeline,
    smp:             sg.Sampler,
}

@(private)
_lighting_setup :: proc() {
    // Point sampling, as raylib's render targets had: the sprite shader derives its outline from
    // neighbouring texels, and filtering them would soften it.
    _light.smp = sg.make_sampler({
        min_filter = .NEAREST, mag_filter = .NEAREST,
        wrap_u = .CLAMP_TO_EDGE, wrap_v = .CLAMP_TO_EDGE,
    })

    alpha := sg.Blend_State{
        enabled = true,
        src_factor_rgb = .SRC_ALPHA, dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
        src_factor_alpha = .SRC_ALPHA, dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
    }
    additive := sg.Blend_State{
        enabled = true,
        src_factor_rgb = .SRC_ALPHA, dst_factor_rgb = .ONE,
        src_factor_alpha = .SRC_ALPHA, dst_factor_alpha = .ONE,
    }

    make_pip :: proc(shader: sg.Shader, blend: sg.Blend_State) -> sg.Pipeline {
        return sg.make_pipeline({
            shader       = shader,
            colors       = { 0 = { pixel_format = MAIN_FORMAT, write_mask = .RGBA, blend = blend } },
            depth        = { pixel_format = .NONE },
            sample_count = 1,
        })
    }

    _light.pip_directional = make_pip(sg.make_shader(shd_dir.directional_shader_desc(sg.query_backend())), alpha)
    _light.pip_sprite      = make_pip(sg.make_shader(shd_sprite.sprite_light_shader_desc(sg.query_backend())), alpha)
    fog_shader := sg.make_shader(shd_fog.fog_lights_shader_desc(sg.query_backend()))
    _light.pip_fog_alpha = make_pip(fog_shader, alpha)
    _light.pip_fog_add   = make_pip(fog_shader, additive)
}

// Replays one recorded lighting (or ImGui) draw inside the pass it belongs to.
@(private)
_draw_custom :: proc(item: Custom_Item) {
    switch item.kind {
    case .Directional:
        p := item.dir
        bind: sg.Bindings
        bind.views[shd_dir.VIEW_tex_world]  = item.tex[0]._h.view
        bind.views[shd_dir.VIEW_tex_shadow] = item.tex[1]._h.view
        bind.samplers[shd_dir.SMP_smp]      = _light.smp
        sg.apply_pipeline(_light.pip_directional)
        sg.apply_bindings(bind)
        sg.apply_uniforms(shd_dir.UB_directional_params, { ptr = &p, size = size_of(p) })
        sg.draw(0, 3, 1)

    case .Sprite_Light:
        p := item.sprite
        mask := item.tex[2] if item.tex[2].id != 0 else _gl.white
        bind: sg.Bindings
        bind.views[shd_sprite.VIEW_tex_sprite]    = item.tex[0]._h.view
        bind.views[shd_sprite.VIEW_tex_shadow]    = item.tex[1]._h.view
        bind.views[shd_sprite.VIEW_tex_wall_mask] = mask._h.view
        bind.samplers[shd_sprite.SMP_smp]         = _light.smp
        sg.apply_pipeline(_light.pip_sprite)
        sg.apply_bindings(bind)
        sg.apply_uniforms(shd_sprite.UB_sprite_light_params, { ptr = &p, size = size_of(p) })
        sg.draw(0, 3, 1)

    case .Fog:
        p := item.fog
        mask := item.tex[0] if item.tex[0].id != 0 else _gl.white
        bind: sg.Bindings
        bind.views[shd_fog.VIEW_tex_wall_mask] = mask._h.view
        bind.samplers[shd_fog.SMP_smp]         = _light.smp
        sg.apply_pipeline(_light.pip_fog_add if item.blend == .Additive else _light.pip_fog_alpha)
        sg.apply_bindings(bind)
        sg.apply_uniforms(shd_fog.UB_fog_lights_params, { ptr = &p, size = size_of(p) })
        sg.draw(0, 3, 1)

    case .User:
        if item.fn != nil { item.fn(item.user) }
    }
}

// ---- parameter packing -------------------------------------------------------------------------

@(private)
_pack_lights :: proc(l: Lights, pos_radius: ^[32][4]f32, color: ^[32][4]f32) {
    n := int(clamp(l.count, 0, MAX_LIGHTS))
    for i in 0..<n {
        pos_radius[i] = { l.pos[i].x, l.pos[i].y, l.radius[i], l.intensity[i] }
        color[i]      = { l.color[i].r, l.color[i].g, l.color[i].b, 0 }
    }
}

@(private)
_b_lighting_directional :: proc(world, shadow: Texture, p: Directional_Params) {
    gpu: Directional_GPU
    gpu.sun_dir_intensity = { p.sun_dir.x, p.sun_dir.y, p.sun_intensity, p.ambient }
    gpu.sun_color_shadow  = { p.sun_color.r, p.sun_color.g, p.sun_color.b, p.shadow_alpha }
    _push_custom({ kind = .Directional, blend = .Alpha, tex = { world, shadow, {} }, dir = gpu })
}

@(private)
_b_lighting_sprite :: proc(sprite, shadow, wall_mask: Texture, p: Sprite_Light_Params) {
    ss := _screen_size()
    gpu: Sprite_GPU
    gpu.screen_cam        = { ss[0], ss[1], p.view.cam_target.x, p.view.cam_target.y }
    gpu.cam_offset_zoom   = { p.view.cam_offset.x, p.view.cam_offset.y, p.view.cam_zoom, p.fog_scatter }
    gpu.sun_dir_intensity = { p.sun_dir.x, p.sun_dir.y, p.sun_intensity, p.ambient }
    gpu.sun_color_shadow  = { p.sun_color.r, p.sun_color.g, p.sun_color.b, p.shadow_alpha }
    gpu.surface           = { p.min_brightness, p.outline, p.diffuse, p.rim }
    gpu.misc              = { p.shadow_response, f32(p.lights.count), p.tile_size, 0 }
    gpu.wall              = { p.wall_origin.x, p.wall_origin.y, p.wall_size.x, p.wall_size.y }
    _pack_lights(p.lights, &gpu.light_pos_radius, &gpu.light_color)
    _push_custom({ kind = .Sprite_Light, blend = .Alpha, tex = { sprite, shadow, wall_mask }, sprite = gpu })
}

@(private)
_b_lighting_fog :: proc(wall_mask: Texture, p: Fog_Params) {
    ss := _screen_size()
    gpu: Fog_GPU
    gpu.screen_cam      = { ss[0], ss[1], p.view.cam_target.x, p.view.cam_target.y }
    gpu.cam_offset_zoom = { p.view.cam_offset.x, p.view.cam_offset.y, p.view.cam_zoom, p.fog_scatter }
    gpu.fog             = { p.fog_color.r, p.fog_color.g, p.fog_color.b, p.fog_density }
    gpu.player_vision   = { p.player_pos.x, p.player_pos.y, p.vision_radius, p.vision_fade }
    gpu.misc            = { f32(p.lights.count), 0, p.tile_size, 0 }
    gpu.wall            = { p.wall_origin.x, p.wall_origin.y, p.wall_size.x, p.wall_size.y }
    _pack_lights(p.lights, &gpu.light_pos_radius, &gpu.light_color)

    // Pass 0: fog over the screen, alpha blended.
    _push_custom({ kind = .Fog, blend = .Alpha, tex = { wall_mask, {}, {} }, fog = gpu })

    // Pass 1: light halos, added on top.
    if p.lights.count > 0 {
        gpu.misc[1] = 1
        _push_custom({ kind = .Fog, blend = .Additive, tex = { wall_mask, {}, {} }, fog = gpu })
    }
}

// Stubbed until P1b (decision D6): ambience only, and the whole stack is replaced there.
@(private) _b_lighting_clouds    :: proc(p: Cloud_Params)   {}
@(private) _b_lighting_god_rays  :: proc(p: God_Ray_Params) {}

_ :: c
