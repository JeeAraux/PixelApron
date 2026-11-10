// Belag und Markierungen für Wege. UV.x = quer (0..1), UV.y = Meter entlang des Weges.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.2, 0.2, 0.19);
uniform int mark = 0; // 1 Straße, 2 Rollweg, 3 Piste, 4 Gehweg, 5 Vorfeld
uniform float width = 7.5;
uniform float len = 100.0;
uniform int flip = 0;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = base_color * (0.93 + 0.12 * hash(floor(wpos.xz * 2.0)));
	float x = (UV.x - 0.5) * width;
	float ax = abs(x);
	float v = UV.y;
	float half_w = width * 0.5;
	vec3 white = vec3(0.86, 0.85, 0.80);
	vec3 yellow = vec3(0.86, 0.69, 0.22);
	if (mark == 1) {
		if (ax < 0.16 && mod(v, 6.0) < 3.0) {
			col = white;
		}
		if (abs(ax - (half_w - 0.4)) < 0.15) {
			col = white * 0.92;
		}
		if (ax > half_w - 0.15) {
			col = vec3(0.55, 0.54, 0.5);
		}
	} else if (mark == 6) {
		// 4 Spuren: doppelte Mittellinie, gestrichelte Spurtrenner
		if (abs(ax - 0.22) < 0.1) {
			col = white;
		}
		if (abs(ax - width * 0.25) < 0.12 && mod(v, 6.0) < 3.0) {
			col = white;
		}
		if (abs(ax - (half_w - 0.4)) < 0.15) {
			col = white * 0.92;
		}
		if (ax > half_w - 0.15) {
			col = vec3(0.55, 0.54, 0.5);
		}
	} else if (mark == 7) {
		// Einbahnstraße: gestrichelte Mitte, Pfeile
		if (ax < 0.12 && mod(v, 6.0) < 3.0) {
			col = white;
		}
		if (abs(ax - (half_w - 0.4)) < 0.15) {
			col = white * 0.92;
		}
		if (ax > half_w - 0.15) {
			col = vec3(0.55, 0.54, 0.5);
		}
		float pv = mod(flip == 1 ? len - v : v, 30.0);
		float lx = abs(ax - width * 0.25);
		if (pv > 12.0 && pv < 15.0 && lx < 0.12 + (pv - 12.0) * 0.0) {
			col = white;
		}
		if (pv >= 15.0 && pv < 16.5 && lx < (16.5 - pv) * 0.45) {
			col = white;
		}
	} else if (mark == 2) {
		if (ax < 0.22) {
			col = yellow;
		}
		if (abs(ax - (half_w - 0.8)) < 0.2) {
			col = yellow * 0.9;
		}
	} else if (mark == 3) {
		if (abs(ax - (half_w - 1.2)) < 0.5) {
			col = white;
		}
		if (ax < 0.5 && mod(v, 50.0) < 30.0 && v > 70.0 && v < len - 70.0) {
			col = white;
		}
		bool thr = (v > 6.0 && v < 36.0) || (v > len - 36.0 && v < len - 6.0);
		if (thr && ax < half_w - 3.0 && mod(ax + 0.9, 3.6) < 1.8) {
			col = white;
		}
		bool aim = (v > 150.0 && v < 195.0) || (v > len - 195.0 && v < len - 150.0);
		if (aim && ax > 5.0 && ax < 10.0) {
			col = white;
		}
	} else if (mark == 4) {
		if (fract(v) < 0.1 || fract(UV.x * width) < 0.1) {
			col *= 0.82;
		}
		if (ax > half_w - 0.2) {
			col *= 0.75;
		}
	} else if (mark == 5) {
		vec2 g = fract(wpos.xz / 7.5);
		if (g.x < 0.04 || g.y < 0.04) {
			col *= 0.86;
		}
		if (hash(floor(wpos.xz / 7.5)) > 0.8) {
			col *= 1.05;
		}
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
