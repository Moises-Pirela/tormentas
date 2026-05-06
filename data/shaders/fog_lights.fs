#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

#define MAX_LIGHTS 32

uniform vec2  u_screen_size;
uniform vec2  u_camera_target;
uniform vec2  u_camera_offset;
uniform float u_camera_zoom;

// Fog parameters
uniform vec3  u_fog_color;       // RGB 0..255
uniform float u_fog_density;     // 0..1 base fog opacity
uniform float u_fog_scatter;     // scatter halo size multiplier (e.g. 1.3)

// Player vision (fog-of-war hole centred on player)
uniform vec2  u_player_pos;      // world-space position
uniform float u_vision_radius;   // clear radius (world units)
uniform float u_vision_fade;     // fade ring width (world units)

// Point lights
uniform int   u_light_count;
uniform vec2  u_light_pos[MAX_LIGHTS];
uniform vec3  u_light_color[MAX_LIGHTS];     // RGB 0..255
uniform float u_light_radius[MAX_LIGHTS];
uniform float u_light_intensity[MAX_LIGHTS];

// Wall mask — 1 pixel = 1 tile.  White = wall (occludes light).
uniform sampler2D u_wall_mask;
uniform vec2  u_wall_origin;   // tile-coordinate origin (min_tx, min_ty)
uniform vec2  u_wall_size;     // size in tiles (width, height)
uniform float u_tile_size;     // world units per tile (e.g. 40)

// ---------------------------------------------------------------------------
// Ray-march from `pos` toward `light_pos` through the wall mask.
// Returns 0.0 if a wall blocks the ray, 1.0 if unobstructed.
// ---------------------------------------------------------------------------
float wall_occlusion(vec2 pos, vec2 light_pos) {
    vec2 dir = light_pos - pos;
    float dist = length(dir);
    if (dist < 1.0) return 1.0;

    dir /= dist;

    // Step size = half a tile for reasonable quality
    float step = u_tile_size * 0.5;
    int max_steps = int(min(dist / step, 48.0));

    for (int s = 1; s <= 48; s++) {
        if (s > max_steps) break;

        vec2 sample_pos = pos + dir * (float(s) * step);

        // World → tile coordinate
        vec2 tile_coord = floor(sample_pos / u_tile_size) - u_wall_origin;

        // Normalise to UV.  Render textures are Y-flipped (OpenGL), so flip V.
        vec2 uv = (tile_coord + 0.5) / u_wall_size;
        uv.y = 1.0 - uv.y;

        // Out of bounds = no wall
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) continue;

        float wall = texture(u_wall_mask, uv).r;
        if (wall > 0.5) return 0.0;
    }
    return 1.0;
}

void main() {
    // Reconstruct world-space position (see sprite_light.fs for derivation).
    vec2 screen_px = vec2(gl_FragCoord.x, u_screen_size.y - gl_FragCoord.y);
    vec2 iso_pos   = u_camera_target + (screen_px - u_camera_offset) / u_camera_zoom;
    vec2 world_pos = vec2(iso_pos.x * 0.5 + iso_pos.y, iso_pos.y - iso_pos.x * 0.5);

    // ── Base fog ──────────────────────────────────────────────────────────
    float fog = u_fog_density;

    // Player vision carves a hole in the fog
    float player_dist = length(world_pos - u_player_pos);
    float vision_hole = smoothstep(u_vision_radius, u_vision_radius + u_vision_fade, player_dist);
    fog *= vision_hole;

    // ── Point lights ─────────────────────────────────────────────────────
    vec3 light_accum = vec3(0.0);

    for (int i = 0; i < MAX_LIGHTS; i++) {
        if (i >= u_light_count) break;

        vec2  delta = world_pos - u_light_pos[i];
        float dist  = length(delta);
        float r     = u_light_radius[i];

        if (dist >= r * u_fog_scatter) continue;

        // Wall occlusion — ray-march from pixel toward light source
        float occl = wall_occlusion(world_pos, u_light_pos[i]);
        if (occl <= 0.0) continue;

        // Core light falloff — smooth quadratic
        float t = dist / r;
        float core = max(0.0, 1.0 - t * t);
        core = core * core;

        // Volumetric scatter halo — extends beyond core radius into fog
        float scatter_r = r * u_fog_scatter;
        float scatter_t = dist / scatter_r;
        float scatter = max(0.0, 1.0 - scatter_t);
        scatter = scatter * scatter * 0.4;  // subtle outer glow

        float combined = (core + scatter) * u_light_intensity[i] * occl;

        // Light carves through fog
        fog -= core * u_light_intensity[i] * occl * 0.85;

        // Accumulate light colour
        vec3 col = u_light_color[i] / 255.0;
        light_accum += col * combined;
    }

    fog = clamp(fog, 0.0, 1.0);

    // ── Composite ────────────────────────────────────────────────────────
    // Fog darkens the scene, lights add colour on top.
    vec3 fog_rgb = u_fog_color / 255.0;

    // Final: fog tint at fog opacity + additive light glow
    vec3 out_rgb = fog_rgb * fog + light_accum;
    float out_a  = max(fog, min(length(light_accum), 1.0));

    finalColor = vec4(out_rgb, out_a);
}
