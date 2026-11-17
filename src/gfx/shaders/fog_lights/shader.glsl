// Fog, the player's vision radius and point-light scatter. Two passes: pass 0 lays down fog with
// alpha blending, pass 1 adds light halos additively. Port of data/shaders/fog_lights.fs.
@header package shd_fog_lights
@header import sg "sokol:gfx"

@block fullscreen_vs
const vec2 corners[3] = vec2[3]( vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0) );
out vec2 uv;
void main() {
    vec2 p = corners[gl_VertexIndex];
    gl_Position = vec4(p, 0.0, 1.0);
    uv = vec2((p.x + 1.0) * 0.5, (1.0 - p.y) * 0.5);
}
@end

@vs vs_fog_lights
@include_block fullscreen_vs
@end

@fs fs_fog_lights
#define MAX_LIGHTS 32

layout(binding=0) uniform fog_lights_params {
    vec4 screen_cam;        // xy = screen size (px), zw = camera target
    vec4 cam_offset_zoom;   // xy = camera offset, z = zoom, w = fog scatter
    vec4 fog;               // rgb = fog colour 0..255, a = density
    vec4 player_vision;     // xy = player position, z = vision radius, w = vision fade
    vec4 misc;              // x = light count, y = pass index, z = tile size, w unused
    vec4 wall;              // xy = wall origin (tiles), zw = wall size (tiles)
    vec4 light_pos_radius[MAX_LIGHTS];  // xy = position, z = radius, w = intensity
    vec4 light_color[MAX_LIGHTS];       // rgb 0..255
};

layout(binding=0) uniform texture2D tex_wall_mask;
layout(binding=0) uniform sampler smp;

in vec2 uv;
out vec4 frag_color;

float wall_occlusion(vec2 pos, vec2 light_pos) {
    vec2 dir = light_pos - pos;
    float dist = length(dir);
    if (dist < 1.0) return 1.0;
    dir /= dist;

    float tile = misc.z;
    float stride = tile * 0.5;
    int max_steps = int(min(dist / stride, 48.0));

    for (int s = 1; s <= 48; s++) {
        if (s > max_steps) break;
        vec2 sample_pos = pos + dir * (float(s) * stride);
        vec2 tile_coord = floor(sample_pos / tile) - wall.xy;
        vec2 muv = (tile_coord + 0.5) / wall.zw;
        if (muv.x < 0.0 || muv.x > 1.0 || muv.y < 0.0 || muv.y > 1.0) continue;
        if (texture(sampler2D(tex_wall_mask, smp), muv).r > 0.5) return 0.0;
    }
    return 1.0;
}

void main() {
    // gl_FragCoord has a top-left origin on Metal and D3D11, so no flip here.
    vec2 iso_pos   = screen_cam.zw + (gl_FragCoord.xy - cam_offset_zoom.xy) / cam_offset_zoom.z;
    vec2 world_pos = vec2(iso_pos.x * 0.5 + iso_pos.y, iso_pos.y - iso_pos.x * 0.5);

    int light_count = int(misc.x);
    float scatter_mul = cam_offset_zoom.w;

    if (int(misc.y) == 1) {
        vec3 halo = vec3(0.0);
        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= light_count) break;

            vec2  delta = world_pos - light_pos_radius[i].xy;
            float dist  = length(delta);
            float r     = light_pos_radius[i].z;

            float halo_r = r * scatter_mul;
            if (dist >= halo_r) continue;

            float occl = wall_occlusion(world_pos, light_pos_radius[i].xy);
            if (occl <= 0.0) continue;

            float t    = dist / r;
            float core = max(0.0, 1.0 - t * t);
            core = core * core;

            float st      = dist / halo_r;
            float scatter = max(0.0, 1.0 - st);
            scatter = scatter * scatter * 0.35;

            float combined = (core * 0.25 + scatter * 0.5) * light_pos_radius[i].w * occl;
            halo += (light_color[i].rgb / 255.0) * combined;
        }
        frag_color = vec4(halo, 1.0);
        return;
    }

    float density = fog.a;

    float player_dist = length(world_pos - player_vision.xy);
    density *= smoothstep(player_vision.z, player_vision.z + player_vision.w, player_dist);

    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (i >= light_count) break;

        vec2  delta = world_pos - light_pos_radius[i].xy;
        float dist  = length(delta);
        float r     = light_pos_radius[i].z;
        if (dist >= r * scatter_mul) continue;

        float occl = wall_occlusion(world_pos, light_pos_radius[i].xy);
        if (occl <= 0.0) continue;

        float t    = dist / r;
        float core = max(0.0, 1.0 - t * t);
        core = core * core;

        density -= core * light_pos_radius[i].w * occl * 0.85;
    }

    density = clamp(density, 0.0, 1.0);
    frag_color = vec4(fog.rgb / 255.0, density);
}
@end

@program fog_lights vs_fog_lights fs_fog_lights
