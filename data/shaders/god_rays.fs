#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform vec2  u_screen_size;
uniform vec2  u_camera_target;
uniform vec2  u_camera_offset;
uniform float u_camera_zoom;
uniform float u_time;
uniform vec2  u_sun_dir;
uniform float u_ray_spacing;
uniform float u_ray_width;
uniform float u_ray_thresh;
uniform float u_ray_alpha;

uniform float u_cloud_freq;
uniform float u_cloud_freq_fine;
uniform vec2  u_cloud_drift;
uniform float u_cloud_thresh_lo;
uniform float u_cloud_thresh_hi;
uniform float u_cloud_contrast;

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

float cloud_density(vec2 world_pos) {
    vec2 n = (world_pos + u_time * u_cloud_drift) * u_cloud_freq;
    float coarse = fbm2(n);
    float fine   = fbm2(n * (u_cloud_freq_fine / u_cloud_freq) + vec2(12.7, -4.1));
    float cover  = coarse * 0.78 + fine * 0.22;
    cover = clamp((cover - 0.5) * u_cloud_contrast + 0.5, 0.0, 1.0);
    return smoothstep(u_cloud_thresh_lo, u_cloud_thresh_hi, cover);
}

void main() {
    vec2 screen_px = vec2(gl_FragCoord.x, u_screen_size.y - gl_FragCoord.y);
    vec2 world_pos = u_camera_target + (screen_px - u_camera_offset) / u_camera_zoom;

    float cloud = cloud_density(world_pos);
    float gap   = 1.0 - cloud;
    float gap_boost = smoothstep(0.1, 0.7, gap);

    if (gap_boost <= 0.0) {
        finalColor = vec4(0.0);
        return;
    }

    vec2 dir    = u_sun_dir;
    vec2 normal = vec2(-dir.y, dir.x);

    float lane_coord = dot(world_pos, normal);

    float lane_index = floor(lane_coord / u_ray_spacing + 0.5);
    float lane_center = lane_index * u_ray_spacing;

    float dist_to_lane = abs(lane_coord - lane_center);

    float lane_noise = fbm2(vec2(lane_center * 0.005 + u_time * 0.03, 7.31));

    if (lane_noise < u_ray_thresh) {
        finalColor = vec4(0.0);
        return;
    }

    float ray_w = u_ray_width * (0.75 + lane_noise * 0.7);

    float width_factor = 1.0 - smoothstep(ray_w * 0.3, ray_w * 0.55, dist_to_lane);
    if (width_factor <= 0.0) {
        finalColor = vec4(0.0);
        return;
    }

    float alpha_scale = smoothstep(u_ray_thresh, 0.92, lane_noise) * u_ray_alpha;

    float sun_coord = dot(world_pos, dir);
    float seg_scale = u_screen_size.y / u_camera_zoom;
    float seg_t = sun_coord / (seg_scale * 0.18);
    float seg_id = floor(seg_t);

    float seg_noise = fbm2(
        vec2(lane_center * 0.004 + seg_id * 0.37 + u_time * 0.08,
             18.0 + seg_id * 0.21)
    );
    float seg_alpha = alpha_scale * smoothstep(0.42, 0.82, seg_noise);

    float seg_frac = fract(seg_t);
    float seg_edge = smoothstep(0.0, 0.08, seg_frac) * smoothstep(1.0, 0.92, seg_frac);

    float a = seg_alpha * width_factor * seg_edge;
    a = clamp(a, 0.0, 1.0);

    float seg_taper = clamp(1.0 - seg_id * 0.008, 0.4, 1.0);
    a *= seg_taper;

    a *= gap_boost;

    vec3 ray_col = vec3(96.0, 110.0, 72.0) / 255.0;
    float final_a = clamp((18.0 + a * 54.0) / 255.0, 0.0, 1.0);

    finalColor = vec4(ray_col * final_a, final_a);
}
