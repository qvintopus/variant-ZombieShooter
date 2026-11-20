shader_type canvas_item;

uniform vec3 overlay:source_color = vec3(1.0);
uniform float blend:hint_range(0.0, 1.0);
// Second flash channel (pickup blink) so it doesn't fight the hit flash animation
uniform float extra_blend:hint_range(0.0, 1.0) = 0.0;

void fragment(){
	COLOR.rgb = mix(COLOR.rgb, overlay, max(blend, extra_blend));
}
