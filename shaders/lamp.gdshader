// Befeuerung und Signallichter: unbeleuchtet, nachts heller (Glow).
shader_type spatial;
render_mode unshaded, cull_disabled;

global uniform float night;
uniform float boost = 1.0;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ALBEDO = COLOR.rgb * (1.0 + night * 3.5 * boost);
#else
	ALBEDO = to_linear(COLOR.rgb) * (1.0 + night * 3.5 * boost);
#endif
}
