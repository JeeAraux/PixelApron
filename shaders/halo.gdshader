// Lichthof um Lampen: Billboard-Quad (alle vier Ecken an der Lampe, Ausdehnung über UV), additiv.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float night;
uniform float size = 3.0;
uniform float day_strength = 0.12;

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	c.xy += (UV - 0.5) * size * (0.6 + 0.4 * night);
	POSITION = PROJECTION_MATRIX * c;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 2.2);
	ALBEDO = COLOR.rgb * a * mix(day_strength, 1.4, night);
}
