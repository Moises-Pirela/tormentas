// Directional (sun) composite of the world layer. Port of data/shaders/directional_light.fs.
// std140 packs array elements to 16 bytes, so related scalars share a vec4.
@header package shd_directional
@header import sg "sokol:gfx"

@block fullscreen_vs
// A fullscreen triangle with top-left-origin UVs, matching upright render targets.
const vec2 corners[3] = vec2[3]( vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0) );
out vec2 uv;
void main() {
    vec2 p = corners[gl_VertexIndex];
    gl_Position = vec4(p, 0.0, 1.0);
    uv = vec2((p.x + 1.0) * 0.5, (1.0 - p.y) * 0.5);
}
@end

@vs vs_directional
@include_block fullscreen_vs
@end

@fs fs_directional
layout(binding=0) uniform directional_params {
    vec4 sun_dir_intensity;  // xy = sun direction, z = sun intensity, w = ambient
    vec4 sun_color_shadow;   // rgb = sun colour 0..1, a = shadow alpha
};

layout(binding=0) uniform texture2D tex_world;
layout(binding=1) uniform texture2D tex_shadow;
layout(binding=0) uniform sampler smp;

in vec2 uv;
out vec4 frag_color;

void main() {
    vec4 world  = texture(sampler2D(tex_world, smp), uv);
    vec4 shadow = texture(sampler2D(tex_shadow, smp), uv);

    float light_facing = clamp(dot(normalize(sun_dir_intensity.xy), normalize(vec2(0.55, 0.85))), 0.0, 1.0);
    float sunlight     = sun_dir_intensity.w + light_facing * sun_dir_intensity.z;
    float shadow_term  = 1.0 - shadow.a * sun_color_shadow.a;

    vec3 lit = world.rgb * sunlight;
    lit *= shadow_term;
    lit += world.rgb * (sun_color_shadow.rgb * 0.12 * sun_dir_intensity.z);

    frag_color = vec4(lit, world.a);
}
@end

@program directional vs_directional fs_directional
