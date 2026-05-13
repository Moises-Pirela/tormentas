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

// Render pass selector:
//   0 = fog layer   — draw with BLEND_ALPHA   (darkens the scene, lights carve holes)
//   1 = light halos — draw with BLEND_ADDITIVE (warm glow on ground & through fog)
uniform int u_pass;

// ---------------------------------------------------------------------------
// Ray-march from `pos` toward `light_pos` through the wall mask.
// Returns 0.0 if a wall blocks the ray, 1.0 if unobstructed.
// ---------------------------------------------------------------------------
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
    // Reconstruct world-space position from screen pixel.
    vec2 screen_px = vec2(gl_FragCoord.x, u_screen_size.y - gl_FragCoord.y);
    vec2 iso_pos   = u_camera_target + (screen_px - u_camera_offset) / u_camera_zoom;
    // Invert isometric transform: world_x = iso_x*0.5 + iso_y, world_y = iso_y - iso_x*0.5
    vec2 world_pos = vec2(iso_pos.x * 0.5 + iso_pos.y, iso_pos.y - iso_pos.x * 0.5);

    // ── PASS 1: Additive light halos ──────────────────────────────────────
    // Drawn with BLEND_ADDITIVE after the fog pass.  Adds warm colour on top
    // of the already-composited scene (world tiles + sprites) without making
    // anything invisible.  Wall-occluded pixels receive no glow.
    if (u_pass == 1) {
        vec3 halo = vec3(0.0);

        for (int i = 0; i < MAX_LIGHTS; i++) {
            if (i >= u_light_count) break;

            vec2  delta = world_pos - u_light_pos[i];
            float dist  = length(delta);
            float r     = u_light_radius[i];

            // Halo extends a bit beyond the core radius for volumetric feel.
            float halo_r = r * u_fog_scatter;
            if (dist >= halo_r) continue;

            float occl = wall_occlusion(world_pos, u_light_pos[i]);
            if (occl <= 0.0) continue;

            // Sharp core falloff — same as fog pass
            float t    = dist / r;
            float core = max(0.0, 1.0 - t * t);
            core = core * core;

            // Softer scatter beyond core radius
            float st      = dist / halo_r;
            float scatter = max(0.0, 1.0 - st);
            scatter = scatter * scatter * 0.35;

            // Keep the halo dim — sprites are already lit by sprite_light.fs.
            // This just warms the ground/fog, not blinds everything.
            float combined = (core * 0.25 + scatter * 0.5) * u_light_intensity[i] * occl;

            vec3 col = u_light_color[i] / 255.0;
            halo += col * combined;
        }

        // Output RGB only; alpha is ignored with BLEND_ADDITIVE (GL_ONE / GL_ONE).
        finalColor = vec4(halo, 1.0);
        return;
    }

    // ── PASS 0: Fog layer (BLEND_ALPHA) ───────────────────────────────────
    // Alpha = fog density.  Lights and player vision carve holes in the fog,
    // making the scene visible.  No light colour leaks into out_a, so sprites
    // are never hidden by an opaque coloured quad.

    float fog = u_fog_density;

    // Player vision carves a clear window
    float player_dist = length(world_pos - u_player_pos);
    float vision_hole = smoothstep(u_vision_radius, u_vision_radius + u_vision_fade, player_dist);
    fog *= vision_hole;

    // Point lights further thin the fog inside their radius
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

        // Carve fog proportional to light strength
        fog -= core * u_light_intensity[i] * occl * 0.85;
    }

    fog = clamp(fog, 0.0, 1.0);

    // Output: fog colour at fog opacity only.
    // Alpha never exceeds `fog` — lights cannot make the overlay opaque.
    vec3 fog_rgb = u_fog_color / 255.0;
    finalColor = vec4(fog_rgb, fog);
}
