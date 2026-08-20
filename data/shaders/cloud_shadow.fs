#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform vec2  u_screen_size;
uniform vec2  u_camera_target;
uniform vec2  u_camera_offset;
uniform float u_camera_zoom;
uniform float u_time;
uniform float u_cloud_freq;
uniform float u_cloud_freq_fine;
uniform vec2  u_cloud_drift;
uniform float u_cloud_thresh_lo;
uniform float u_cloud_thresh_hi;
uniform float u_cloud_alpha_min;
uniform float u_cloud_alpha_max;
uniform float u_cloud_contrast;
uniform vec3  u_cloud_tint;

float fade5(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

float grad2(ivec2 ip, vec2 fp) {
    uint n = uint(ip.x) * 374761393u + uint(ip.y) * 668265263u;
    n = (n ^ (n >> 13u)) * 1274126177u;
    float angle = float(n & 255u) * (6.2831853 / 256.0);
    return cos(angle) * fp.x + sin(angle) * fp.y;
}

float perlin2(vec2 p) {
    ivec2 i0 = ivec2(floor(p));
    ivec2 i1 = i0 + ivec2(1);
    vec2  f  = p - vec2(i0);

    float sx = fade5(f.x);
    float sy = fade5(f.y);

    float n00 = grad2(i0,                    f);
    float n10 = grad2(ivec2(i1.x, i0.y),     f - vec2(1.0, 0.0));
    float n01 = grad2(ivec2(i0.x, i1.y),     f - vec2(0.0, 1.0));
    float n11 = grad2(i1,                    f - vec2(1.0, 1.0));

    float ix0 = mix(n00, n10, sx);
    float ix1 = mix(n01, n11, sx);
    return mix(ix0, ix1, sy) * 0.5 + 0.5;
}

float fbm2(vec2 p) {
    float value = 0.0;
    float amp   = 0.5;
    float freq  = 1.0;
    for (int i = 0; i < 4; i++) {
        value += perlin2(p * freq) * amp;
        freq  *= 2.0;
        amp   *= 0.5;
    }
    return value;
}

void main() {
    vec2 screen_px = vec2(gl_FragCoord.x, u_screen_size.y - gl_FragCoord.y);

    vec2 world_pos = u_camera_target + (screen_px - u_camera_offset) / u_camera_zoom;

    vec2 n = (world_pos + u_time * u_cloud_drift) * u_cloud_freq;

    float coarse = fbm2(n);
    float fine   = fbm2(
        n * (u_cloud_freq_fine / u_cloud_freq) + vec2(12.7, -4.1)
    );

    float cover = coarse * 0.78 + fine * 0.22;
    cover = clamp((cover - 0.5) * u_cloud_contrast + 0.5, 0.0, 1.0);

    float shadow = smoothstep(u_cloud_thresh_lo, u_cloud_thresh_hi, cover);

    float alpha = 0.0;
    if (shadow > 0.0) {
        alpha = clamp(u_cloud_alpha_min + shadow * u_cloud_alpha_max, 0.0, 255.0) / 255.0;
    }

    finalColor = vec4(u_cloud_tint / 255.0, alpha);
}
