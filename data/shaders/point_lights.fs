#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

#define MAX_LIGHTS 32

uniform vec2  u_screen_size;
uniform vec2  u_camera_target;
uniform vec2  u_camera_offset;
uniform float u_camera_zoom;
uniform int   u_light_count;
uniform vec2  u_light_pos[MAX_LIGHTS];
uniform vec3  u_light_color[MAX_LIGHTS];
uniform float u_light_radius[MAX_LIGHTS];
uniform float u_light_intensity[MAX_LIGHTS];

void main() {
    vec2 screen_px = vec2(gl_FragCoord.x, u_screen_size.y - gl_FragCoord.y);
    vec2 world_pos = u_camera_target + (screen_px - u_camera_offset) / u_camera_zoom;

    vec3 accum = vec3(0.0);

    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (i >= u_light_count) break;

        vec2  delta = world_pos - u_light_pos[i];
        float dist  = length(delta);
        float r     = u_light_radius[i];

        if (dist >= r) continue;

        float t = dist / r;
        float falloff = (1.0 - t * t);
        falloff = falloff * falloff;

        vec3 col = u_light_color[i] / 255.0;
        accum += col * falloff * u_light_intensity[i];
    }

    float a = min(length(accum), 1.0);
    finalColor = vec4(accum, a);
}
