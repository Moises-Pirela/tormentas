// Lit sprite composite: diffuse from the alpha gradient, outline, rim, point lights and wall
// occlusion. Port of data/shaders/sprite_light.fs.
@header package shd_sprite_light
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

@vs vs_sprite_light
@include_block fullscreen_vs
@end

@fs fs_sprite_light
#define MAX_LIGHTS 32

layout(binding=0) uniform sprite_light_params {
    vec4 screen_cam;         // xy = screen size (px), zw = camera target
    vec4 cam_offset_zoom;    // xy = camera offset, z = zoom, w = fog scatter
    vec4 sun_dir_intensity;  // xy = sun direction, z = sun intensity, w = ambient
    vec4 sun_color_shadow;   // rgb = sun colour 0..1, a = shadow alpha
    vec4 surface;            // x = min brightness, y = outline, z = diffuse, w = rim
    vec4 misc;               // x = shadow response, y = light count, z = tile size, w unused
    vec4 wall;               // xy = wall origin (tiles), zw = wall size (tiles)
    vec4 light_pos_radius[MAX_LIGHTS];  // xy = position, z = radius, w = intensity
    vec4 light_color[MAX_LIGHTS];       // rgb 0..255
};

layout(binding=0) uniform texture2D tex_sprite;
layout(binding=1) uniform texture2D tex_shadow;
layout(binding=2) uniform texture2D tex_wall_mask;
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
    vec4 sprite = texture(sampler2D(tex_sprite, smp), uv);
    if (sprite.a <= 0.001) {
        discard;
    }

    vec4 shadow = texture(sampler2D(tex_shadow, smp), uv);
    vec2 px = 1.0 / screen_cam.xy;

    float aL = texture(sampler2D(tex_sprite, smp), uv + vec2(-px.x, 0.0)).a;
    float aR = texture(sampler2D(tex_sprite, smp), uv + vec2( px.x, 0.0)).a;
    float aU = texture(sampler2D(tex_sprite, smp), uv + vec2(0.0, -px.y)).a;
    float aD = texture(sampler2D(tex_sprite, smp), uv + vec2(0.0,  px.y)).a;

    float aTR = texture(sampler2D(tex_sprite, smp), uv + vec2( px.x, -px.y)).a;
    float aTL = texture(sampler2D(tex_sprite, smp), uv + vec2(-px.x, -px.y)).a;
    float aBR = texture(sampler2D(tex_sprite, smp), uv + vec2( px.x,  px.y)).a;
    float aBL = texture(sampler2D(tex_sprite, smp), uv + vec2(-px.x,  px.y)).a;

    vec2 grad = vec2(aL - aR, aD - aU);
    vec3 normal = normalize(vec3(grad * 2.1, 0.55));
    vec3 light_dir = normalize(vec3(-sun_dir_intensity.x, -sun_dir_intensity.y, 0.75));

    float diffuse = max(dot(normal, light_dir), 0.0);
    diffuse = 0.5 + diffuse * 0.5;
    diffuse = mix(1.0, diffuse, surface.z);

    float shadow_term = 1.0 - shadow.a * sun_color_shadow.a * misc.x;
    float lit = max(surface.x, sun_dir_intensity.w + diffuse * sun_dir_intensity.z);
    lit *= shadow_term;

    float min_neighbour = min(min(aL, aR), min(aU, aD));
    min_neighbour = min(min_neighbour, min(min(aTR, aTL), min(aBR, aBL)));
    float outline = clamp((sprite.a - min_neighbour) * surface.y, 0.0, 1.0);

    float rim = pow(clamp(1.0 - max(dot(normal, vec3(0.0, 0.0, 1.0)), 0.0), 0.0, 1.0), 1.4) * surface.w;

    vec3 rgb = sprite.rgb * lit;
    rgb += sprite.rgb * sun_color_shadow.rgb * diffuse * sun_dir_intensity.z * 0.22;
    rgb += sun_color_shadow.rgb * rim * 0.35;

    // gl_FragCoord has a top-left origin on Metal and D3D11, so no flip here.
    vec2 iso_pos   = screen_cam.zw + (gl_FragCoord.xy - cam_offset_zoom.xy) / cam_offset_zoom.z;
    vec2 world_pos = vec2(iso_pos.x * 0.5 + iso_pos.y, iso_pos.y - iso_pos.x * 0.5);

    int light_count = int(misc.y);
    vec3 light_accum = vec3(0.0);
    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (i >= light_count) break;

        vec2  delta = world_pos - light_pos_radius[i].xy;
        float dist  = length(delta);
        float r     = light_pos_radius[i].z;
        if (dist >= r * cam_offset_zoom.w) continue;

        float occl = wall_occlusion(world_pos, light_pos_radius[i].xy);
        if (occl <= 0.0) continue;

        float t = dist / r;
        float core = max(0.0, 1.0 - t * t);
        core = core * core;

        float scatter_r = r * cam_offset_zoom.w;
        float scatter_t = dist / scatter_r;
        float scatter = max(0.0, 1.0 - scatter_t);
        scatter = scatter * scatter * 0.4;

        float combined = (core + scatter) * light_pos_radius[i].w * occl;
        light_accum += (light_color[i].rgb / 255.0) * combined;
    }

    rgb += sprite.rgb * light_accum * 0.7;
    rgb += light_accum * 0.15;
    rgb = mix(rgb, vec3(0.01, 0.01, 0.02), outline * 0.82);

    frag_color = vec4(rgb, max(sprite.a, outline * 0.8));
}
@end

@program sprite_light vs_sprite_light fs_sprite_light
