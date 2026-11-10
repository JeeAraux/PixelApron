// Werbe- und Infobildschirm: wechselt alle paar Sekunden das Motiv, leuchtet nachts heller.
shader_type spatial;
render_mode unshaded;

global uniform float night;
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.18 + seed;
	float slide = floor(t);
	float f = fract(t);
	vec3 a = vec3(hash(vec2(slide, 1.0)), hash(vec2(slide, 2.0)), hash(vec2(slide, 3.0)));
	vec3 b = vec3(hash(vec2(slide, 4.0)), hash(vec2(slide, 5.0)), hash(vec2(slide, 6.0)));
	vec3 col = mix(a * 0.8 + 0.1, b * 0.7 + 0.2, uv.y);
	// Schriftzeilen und ein Bildblock in Pixeln
	vec2 px = floor(uv * vec2(48.0, 27.0));
	float line = step(0.55, hash(px + slide)) * step(mod(px.y, 4.0), 0.5) * step(px.x, 30.0) * step(4.0, px.x);
	col = mix(col, vec3(0.97), line * step(uv.y, 0.6));
	float pic = step(0.62, uv.x) * step(uv.x, 0.92) * step(0.15, uv.y) * step(uv.y, 0.55);
	col = mix(col, b.zxy * 0.9 + 0.1 * sin(TIME * 2.0 + uv.x * 10.0), pic);
	// Überblendung beim Motivwechsel
	col *= smoothstep(0.0, 0.06, f) * smoothstep(1.0, 0.94, f) * 0.9 + 0.1;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	col = pow(col, vec3(2.2));
#endif
	ALBEDO = col * (0.85 + night * 0.9);
}
