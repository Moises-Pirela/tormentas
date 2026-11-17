// Port of data/shaders/point_lights.fs to sokol-shdc: the pattern every P1a shader port follows.
//
// Differences from the raylib GLSL 330 original:
//   - Uniforms live in one std140 block. std140 pads every array element to 16 bytes, so the
//     original vec2/vec3/float arrays are packed into vec4 arrays (pos.xy, radius, intensity)
//     instead of being padded silently.
//   - gl_FragCoord has a top-left origin on Metal and D3D11 (the two decided backends), so the
//     original's `u_screen_size.y - gl_FragCoord.y` flip is gone.
//   - The vertex stage is a fullscreen triangle from gl_VertexIndex; no vertex buffer.
@header package spike
@header import sg "sokol:gfx"

@vs vs_point_lights
const vec2 corners[3] = { vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0) };

void main() {
    gl_Position = vec4(corners[gl_VertexIndex], 0.0, 1.0);
}
@end

@fs fs_point_lights
#define MAX_LIGHTS 32

layout(binding=0) uniform fs_point_lights_params {
    vec4 cam_target_offset;              // xy = camera target (world), zw = camera offset (px)
    vec4 cam_zoom_count;                 // x = zoom, y = light count
    vec4 light_pos_radius[MAX_LIGHTS];   // xy = position (world), z = radius, w = intensity
    vec4 light_color[MAX_LIGHTS];        // rgb in 0..255, as the original
};

out vec4 frag_color;

void main() {
    vec2 screen_px = gl_FragCoord.xy;
    vec2 world_pos = cam_target_offset.xy + (screen_px - cam_target_offset.zw) / cam_zoom_count.x;
    int  count     = int(cam_zoom_count.y);

    vec3 accum = vec3(0.0);
    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (i >= count) break;

        float dist = length(world_pos - light_pos_radius[i].xy);
        float r    = light_pos_radius[i].z;
        if (dist >= r) continue;

        float t       = dist / r;
        float falloff = 1.0 - t * t;
        falloff       = falloff * falloff;

        accum += (light_color[i].rgb / 255.0) * falloff * light_pos_radius[i].w;
    }

    float a = min(length(accum), 1.0);
    frag_color = vec4(accum, a);
}
@end

@program point_lights vs_point_lights fs_point_lights
