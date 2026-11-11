// Nebelschwaden: waagrechte Schichten knapp über dem Boden, wolkig aus Rauschen in Weltkoordinaten,
// ziehen langsam mit dem Wind. Höhere Bauten ragen heraus.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float amount = 0.0;
uniform vec4 col : source_color = vec4(0.86, 0.88, 0.9, 1.0);
uniform vec2 drift = vec2(1.0, 0.3);
uniform float seed = 0.0;

varying vec3 wpos;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz / 90.0 + drift * TIME * 0.004 + vec2(seed * 7.3, seed * 3.1);
	float n = fbm(p);
	float a = smoothstep(0.38, 0.78, n) * amount;
	ALBEDO = col.rgb;
	ALPHA = clamp(a, 0.0, 0.85);
}
