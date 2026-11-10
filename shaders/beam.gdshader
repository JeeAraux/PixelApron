// Lichtkegel von Scheinwerfern auf dem Boden: Trapez vor dem Fahrzeug, additiv, nur nachts.
// UV.y = 0 an der Lampe, 1 am fernen Ende; UV.x quer.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

global uniform float night;
uniform vec4 tint : source_color = vec4(1.0, 0.92, 0.75, 1.0);
uniform float strength = 0.55;

void fragment() {
	float along = UV.y;
	float across = abs(UV.x - 0.5) * 2.0;
	float a = (1.0 - along) * (1.0 - along) * (1.0 - smoothstep(0.55, 1.0, across)) * smoothstep(0.0, 0.1, along);
	ALBEDO = tint.rgb * a * strength * smoothstep(0.3, 0.8, night);
}
