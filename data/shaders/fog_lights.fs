#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

#define MAX_LIGHTS 32

uniform vec2  u_screen_size;
uniform vec2  u_camera_target;
uniform vec2  u_camera_offset;
uniform float u_camera_zoom;

uniform vec3  u_fog_color;
uniform float u_fog_density;
uniform float u_fog_scatter;

uniform vec2  u_player_pos;
uniform float u_vision_radius;
uniform float u_vision_fade;

uniform int   u_light_count;
uniform vec2  u_light_pos[MAX_LIGHTS];
uniform vec3  u_light_color[MAX_LIGHTS];
uniform float u_light_radius[MAX_LIGHTS];
uniform float u_light_intensity[MAX_LIGHTS];

uniform sampler2D u_wall_mask;
uniform vec2  u_wall_origin;
uniform vec2  u_wall_size;
uniform float u_tile_size;

uniform int u_pass;

float wall_occlusion(vec2 pos, vec2 light_pos) {
    vec2 dir = light_pos - pos;
    float dist = length(dir);
    if (dist < 1.0) return 1.0;

    dir /= dist;

    float step = u_tile_size * 0.5;
    int max_steps = int(min(dist / step, 48.0));

    for (int s = 1; s <= 48; s++) {
        if (s > max_steps) break;

        vec2 sample_pos = pos + dir * (float(s) * step);

        vec2 tile_coord = floor(sample_pos / u_tile_size) - u_wall_origin;

        vec2 uv = (tile_coord + 0.5) / u_wall_size;
        uv.y = 1.0 - uv.y;

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) continue;

        float wall = texture(u_wall_mask, uv).r;
        if (wall > 0.5) return 0.0;
    }
    return 1.0;
}

void main() {
    vec2 screen_px = vec2(gl_FragCoord.x, u_screen_size.y - gl_FragCoord.y);
    vec2 iso_pos   = u_camera_target + (screen_px - u_camera_offset) / u_camera_zoom;

    vec2 world_pos = vec2(iso_pos.x * 0.5 + iso_pos.y, iso_pos.y - iso_pos.x * 0.5);

    if (u_pass == 1) {
        vec3 halo = vec3(0.0);

        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= u_light_count) break;

            vec2  delta = world_pos - u_light_pos[i];
            float dist  = length(delta);
            float r     = u_light_radius[i];

            float halo_r = r * u_fog_scatter;
            if (dist >= halo_r) continue;

            float occl = wall_occlusion(world_pos, u_light_pos[i]);
            if (occl <= 0.0) continue;

            float t    = dist / r;
            float core = max(0.0, 1.0 - t * t);
            core = core * core;

            float st      = dist / halo_r;
            float scatter = max(0.0, 1.0 - st);
            scatter = scatter * scatter * 0.35;

            float combined = (core * 0.25 + scatter * 0.5) * u_light_intensity[i] * occl;

            vec3 col = u_light_color[i] / 255.0;
            halo += col * combined;
        }

        finalColor = vec4(halo, 1.0);
        return;
    }

    float fog = u_fog_density;

    float player_dist = length(world_pos - u_player_pos);
    float vision_hole = smoothstep(u_vision_radius, u_vision_radius + u_vision_fade, player_dist);
    fog *= vision_hole;

    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (i >= u_light_count) break;

        vec2  delta = world_pos - u_light_pos[i];
        float dist  = length(delta);
        float r     = u_light_radius[i];

        if (dist >= r * u_fog_scatter) continue;

        float occl = wall_occlusion(world_pos, u_light_pos[i]);
        if (occl <= 0.0) continue;

        float t    = dist / r;
        float core = max(0.0, 1.0 - t * t);
        core = core * core;

        fog -= core * u_light_intensity[i] * occl * 0.85;
    }

    fog = clamp(fog, 0.0, 1.0);

    vec3 fog_rgb = u_fog_color / 255.0;
    finalColor = vec4(fog_rgb, fog);
}
