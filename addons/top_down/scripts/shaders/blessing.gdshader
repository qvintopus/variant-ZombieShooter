// Room-cleared "blessing": warm glow around the player, soft god-rays from the
// top, sparkles drifting up. Additive; `progress` 0 = invisible, 1 = full.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 center = vec2(0.5, 0.5);
uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform vec4 ray_color : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform vec4 sparkle_color : source_color = vec4(1.0, 1.0, 0.85, 1.0);
uniform float glow_radius : hint_range(0.0, 2.0) = 0.45;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.6;
uniform float ray_strength : hint_range(0.0, 2.0) = 0.35;
uniform float ray_count = 9.0;
uniform float ray_speed = 0.15;
uniform float sparkle_strength : hint_range(0.0, 3.0) = 1.0;
uniform float sparkle_density = 40.0;
uniform float sparkle_speed = 0.12;
uniform float edge_brighten : hint_range(0.0, 1.0) = 0.12;
// screen width / height, keeps the glow round
uniform float aspect = 1.7778;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 d = (uv - center) * vec2(aspect, 1.0);
	float dist = length(d);
	float glow = smoothstep(glow_radius, 0.0, dist) * glow_strength;

	// rays: columns slanting from the top, fading downward
	float slant = uv.x + (1.0 - uv.y) * 0.25;
	float cols = sin(slant * ray_count * 6.2831 + TIME * ray_speed * 6.2831) * 0.5 + 0.5;
	cols *= sin(slant * ray_count * 2.7 - TIME * ray_speed * 4.0) * 0.5 + 0.5;
	float rays = pow(cols, 3.0) * smoothstep(1.0, 0.0, uv.y) * ray_strength;

	// sparkles drifting up
	vec2 grid = vec2(uv.x * aspect, uv.y + TIME * sparkle_speed) * sparkle_density;
	vec2 cell = floor(grid);
	vec2 local = fract(grid) - 0.5;
	float rnd = hash(cell);
	vec2 offset = vec2(hash(cell + 1.3), hash(cell + 7.1)) - 0.5;
	float twinkle = 0.5 + 0.5 * sin(TIME * 6.0 + rnd * 40.0);
	float sparkle = step(0.86, rnd) * smoothstep(0.12, 0.0, length(local - offset * 0.6)) * twinkle * sparkle_strength;
	sparkle *= smoothstep(glow_radius * 2.5, 0.0, dist) + 0.2;

	float edge = smoothstep(0.35, 0.75, length(uv - 0.5)) * edge_brighten;

	vec3 col = glow_color.rgb * glow + ray_color.rgb * rays + sparkle_color.rgb * sparkle + glow_color.rgb * edge;
	COLOR = vec4(col * progress, 1.0);
}
