#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;
uniform sampler2D u_shadow_tex;
uniform vec2  u_screen_size;
uniform vec2  u_sun_dir;
uniform float u_sun_intensity;
uniform float u_ambient;
uniform float u_shadow_alpha;
uniform vec3  u_sun_color;

void main() {
    vec4 world = texture(texture0, fragTexCoord);
    vec4 shadow = texture(u_shadow_tex, fragTexCoord);

    float light_facing = clamp(dot(normalize(u_sun_dir), normalize(vec2(0.55, 0.85))), 0.0, 1.0);
    float sunlight = u_ambient + light_facing * u_sun_intensity;
    float shadow_term = 1.0 - shadow.a * u_shadow_alpha;

    vec3 lit = world.rgb * sunlight;
    lit *= shadow_term;
    lit += world.rgb * (u_sun_color * 0.12 * u_sun_intensity);

    finalColor = vec4(lit, world.a);
}
