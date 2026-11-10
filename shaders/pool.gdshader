// Lichtkreis einer Straßenleuchte auf dem Boden: additiv, nur nachts. UV 0..1 über das Quadrat.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

global uniform float night;
uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.6, 1.0);
uniform float strength = 0.32;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float a = 1.0 - smoothstep(0.0, 1.0, r);
	ALBEDO = tint.rgb * a * a * strength * smoothstep(0.3, 0.8, night);
}
