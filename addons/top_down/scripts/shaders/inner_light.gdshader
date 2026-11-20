// Light bursting out from inside a sprite: cracks of light spread with
// `progress`, the body whitens, and at the end it dissolves into light.
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 light_color : source_color = vec4(1.0, 0.92, 0.6, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_nearest;
// how many crack cells across the texture
uniform float noise_scale = 1.0;
uniform float crack_width : hint_range(0.0, 0.5) = 0.06;
// share of `progress` that whitens the whole body
uniform float whiten : hint_range(0.0, 1.0) = 0.7;
// progress where dissolving starts
uniform float dissolve_from : hint_range(0.0, 1.0) = 0.9;
// pixels per texel snap (keeps cracks pixel-art)
uniform vec2 texel_snap = vec2(64.0, 64.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 snapped = floor(UV * texel_snap) / texel_snap;
	float n = texture(noise_tex, snapped * noise_scale).r;
	// cracks open from bright noise down as progress grows
	float threshold = 1.0 - progress;
	float crack = smoothstep(threshold - crack_width, threshold, n);
	vec3 col = mix(base.rgb, light_color.rgb, crack);
	col = mix(col, light_color.rgb, pow(progress, 2.0) * whiten);
	float alpha = base.a;
	if (progress > dissolve_from) {
		float d = (progress - dissolve_from) / max(1.0 - dissolve_from, 0.001);
		alpha *= step(d, n);
	}
	COLOR = vec4(col, alpha) * COLOR;
}
