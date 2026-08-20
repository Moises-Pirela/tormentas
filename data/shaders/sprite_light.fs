#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

#define MAX_LIGHTS 32

uniform sampler2D texture0;
uniform sampler2D u_shadow_tex;
uniform vec2  u_screen_size;
uniform vec2  u_sun_dir;
uniform vec3  u_sun_color;
uniform float u_sun_intensity;
uniform float u_ambient;
uniform float u_shadow_alpha;
uniform float u_min_brightness;
uniform float u_outline_strength;
uniform float u_diffuse_strength;
uniform float u_rim_strength;
uniform float u_shadow_response;

uniform vec2  u_camera_target;
uniform vec2  u_camera_offset;
uniform float u_camera_zoom;

uniform int   u_light_count;
uniform vec2  u_light_pos[MAX_LIGHTS];
uniform vec3  u_light_color[MAX_LIGHTS];
uniform float u_light_radius[MAX_LIGHTS];
uniform float u_light_intensity[MAX_LIGHTS];
uniform float u_fog_scatter;

uniform sampler2D u_wall_mask;
uniform vec2  u_wall_origin;
uniform vec2  u_wall_size;
uniform float u_tile_size;

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
    vec4 sprite = texture(texture0, fragTexCoord);
    if (sprite.a <= 0.001) {
        discard;
    }

    vec4 shadow = texture(u_shadow_tex, fragTexCoord);
    vec2 px = 1.0 / u_screen_size;

    float aL = texture(texture0, fragTexCoord + vec2(-px.x, 0.0)).a;
    float aR = texture(texture0, fragTexCoord + vec2( px.x, 0.0)).a;
    float aU = texture(texture0, fragTexCoord + vec2(0.0, -px.y)).a;
    float aD = texture(texture0, fragTexCoord + vec2(0.0,  px.y)).a;

    float aTR = texture(texture0, fragTexCoord + vec2( px.x, -px.y)).a;
    float aTL = texture(texture0, fragTexCoord + vec2(-px.x, -px.y)).a;
    float aBR = texture(texture0, fragTexCoord + vec2( px.x,  px.y)).a;
    float aBL = texture(texture0, fragTexCoord + vec2(-px.x,  px.y)).a;

    vec2 grad = vec2(aL - aR, aD - aU);
    vec3 normal = normalize(vec3(grad * 2.1, 0.55));
    vec3 light_dir = normalize(vec3(-u_sun_dir.x, -u_sun_dir.y, 0.75));

    float diffuse = max(dot(normal, light_dir), 0.0);
    diffuse = 0.5 + diffuse * 0.5;
    diffuse = mix(1.0, diffuse, u_diffuse_strength);

    float shadow_term = 1.0 - shadow.a * u_shadow_alpha * u_shadow_response;
    float lit = max(u_min_brightness, u_ambient + diffuse * u_sun_intensity);
    lit *= shadow_term;

    float minNeighborAlpha = min(min(aL, aR), min(aU, aD));
    minNeighborAlpha = min(minNeighborAlpha, min(min(aTR, aTL), min(aBR, aBL)));
    float outline = clamp((sprite.a - minNeighborAlpha) * u_outline_strength, 0.0, 1.0);

    float rim = pow(clamp(1.0 - max(dot(normal, vec3(0.0, 0.0, 1.0)), 0.0), 0.0, 1.0), 1.4) * u_rim_strength;

    vec3 rgb = sprite.rgb * lit;
    rgb += sprite.rgb * u_sun_color * diffuse * u_sun_intensity * 0.22;
    rgb += u_sun_color * rim * 0.35;

    vec2 screen_px = vec2(gl_FragCoord.x, u_screen_size.y - gl_FragCoord.y);
    vec2 iso_pos   = u_camera_target + (screen_px - u_camera_offset) / u_camera_zoom;
    vec2 world_pos = vec2(iso_pos.x * 0.5 + iso_pos.y, iso_pos.y - iso_pos.x * 0.5);

    vec3 light_accum = vec3(0.0);
    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (i >= u_light_count) break;

        vec2  delta = world_pos - u_light_pos[i];
        float dist  = length(delta);
        float r     = u_light_radius[i];

        if (dist >= r * u_fog_scatter) continue;

        float occl = wall_occlusion(world_pos, u_light_pos[i]);
        if (occl <= 0.0) continue;

        float t = dist / r;
        float core = max(0.0, 1.0 - t * t);
        core = core * core;

        float scatter_r = r * u_fog_scatter;
        float scatter_t = dist / scatter_r;
        float scatter = max(0.0, 1.0 - scatter_t);
        scatter = scatter * scatter * 0.4;

        float combined = (core + scatter) * u_light_intensity[i] * occl;
        vec3 col = u_light_color[i] / 255.0;
        light_accum += col * combined;
    }

    rgb += sprite.rgb * light_accum * 0.7;
    rgb += light_accum * 0.15;

    rgb = mix(rgb, vec3(0.01, 0.01, 0.02), outline * 0.82);

    finalColor = vec4(rgb, max(sprite.a, outline * 0.8));
}
