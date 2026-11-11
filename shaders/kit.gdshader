// Detailmodelle aus dem Baukasten: Vertexfarben (sRGB), weiche oder flache Normalen.
// Alpha der Vertexfarbe markiert Leuchtflächen: 0.6 = Fenster (nachts warm erleuchtet), 0.5 = Glas ohne Licht,
// 0.3 = Lampe (nachts hell), 0.8 = Laub (wiegt im Wind), 1.0 = normale Oberfläche.
shader_type spatial;
render_mode cull_disabled;

global uniform float night;
global uniform float snow;
global uniform float wet;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (COLOR.a > 0.75 && COLOR.a < 0.85) {
		// Laub wiegt im Wind, oben stärker als unten
		float h = max(VERTEX.y - 2.0, 0.0);
		float t = TIME * 1.4 + wpos.x * 0.15 + wpos.z * 0.11;
		VERTEX.x += sin(t) * 0.035 * h + sin(t * 2.7) * 0.012 * h;
		VERTEX.z += cos(t * 0.8) * 0.03 * h;
	}
}

void fragment() {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 base = COLOR.rgb;   // Kompatibilitäts-Renderer rechnet im sRGB-Raum
#else
	vec3 base = to_linear(COLOR.rgb);
#endif
	ALBEDO = base;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	if (COLOR.a > 0.95 && (snow > 0.01 || wet > 0.01)) {
		// Schnee auf Dächern und Oberseiten, Nässe macht Flächen dunkler und glänzend
		float up = smoothstep(0.6, 0.92, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
		ALBEDO = mix(ALBEDO, vec3(0.86, 0.88, 0.92), snow * up * 0.85);
		ALBEDO *= 1.0 - 0.12 * wet * (1.0 - snow);
		ROUGHNESS = mix(ROUGHNESS, 0.3, wet * up);
	}
	if (COLOR.a < 0.45) {
		// Lampe: nachts hell leuchtend
		EMISSION = base * night * 6.0 + base * 0.15;
	} else if (COLOR.a > 0.47 && COLOR.a < 0.53) {
		// Glas ohne Licht dahinter (Balustraden, Geländer): glatt und spiegelnd
		ROUGHNESS = 0.12;
		SPECULAR = 0.7;
	} else if (COLOR.a < 0.7) {
		// Fenster: nachts zu gut zwei Dritteln warm erleuchtet, tagsüber leicht spiegelnd
		// Fenster: nachts warm erleuchtet, leicht unregelmäßig (keine harten Blöcke); Oberlichter im Dach schwächer
		float on = 0.7 + 0.3 * hash(floor(wpos.xz * 0.25) + floor(wpos.y * 0.25));
		float up = smoothstep(0.5, 0.9, (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y);
		EMISSION = vec3(1.0, 0.8, 0.56) * night * on * mix(0.85, 0.22, up);
		ROUGHNESS = 0.25;
		SPECULAR = 0.6;
	}
}
