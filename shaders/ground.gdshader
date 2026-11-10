// Wiese mit Pixel-Struktur und gemähten Streifen; zeigt beim Bauen ein Raster.
shader_type spatial;

uniform vec3 c_dark : source_color = vec3(0.29, 0.39, 0.20);
uniform vec3 c_mid : source_color = vec3(0.36, 0.47, 0.23);
uniform vec3 c_light : source_color = vec3(0.44, 0.55, 0.27);
uniform float grid = 0.0;
uniform float bound = 3000.0;   // halbe Kantenlänge des Spielfelds

// Offene Tunnelrampen: dort fehlt der Rasen. a = Mitte xz und Richtung, b = halbe Länge und Breite
uniform vec4 cut_a[48];
uniform vec2 cut_b[48];
uniform int cut_n = 0;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	for (int i = 0; i < cut_n; i++) {
		vec2 d = wpos.xz - cut_a[i].xy;
		vec2 f = cut_a[i].zw;
		float along = dot(d, f);
		float across = dot(d, vec2(-f.y, f.x));
		if (abs(along) < cut_b[i].x && abs(across) < cut_b[i].y) {
			discard;
		}
	}
	float band = mod(floor((wpos.x - wpos.z) / 10.0), 2.0);
	float patch = vnoise(wpos.xz / 14.0) * 0.6 + vnoise(wpos.xz / 5.0) * 0.4;
	vec3 col = mix(c_mid, c_light, band * 0.3);
	col = mix(col, c_dark, smoothstep(0.55, 0.8, patch) * 0.6);
	col = mix(col, c_light, smoothstep(0.35, 0.15, patch) * 0.4);
	float h = hash(floor(wpos.xz));
	if (h > 0.95) {
		col *= 1.08;
	} else if (h < 0.05) {
		col *= 0.9;
	}
	// feine Halme und vereinzelt Blüten (weiß, gelb, violett) in Wiesenflecken
	float fine = hash(floor(wpos.xz * 3.0));
	col *= 0.94 + 0.1 * fine;
	float meadow = vnoise(wpos.xz / 40.0 + 13.0);
	if (meadow > 0.62 && fine > 0.985) {
		float kind = hash(floor(wpos.xz * 3.0) + 7.0);
		col = kind < 0.4 ? vec3(0.95, 0.94, 0.86) : (kind < 0.75 ? vec3(0.95, 0.82, 0.25) : vec3(0.66, 0.5, 0.85));
	}
	// Wolkenschatten ziehen langsam über die Wiese
	float cloud = vnoise(wpos.xz / 260.0 + vec2(TIME * 0.012, TIME * 0.006)) * 0.65 + vnoise(wpos.xz / 90.0 + vec2(TIME * 0.02, 0.0)) * 0.35;
	col *= 1.0 - smoothstep(0.58, 0.75, cloud) * 0.16;
	if (grid > 0.5) {
		vec2 fw = fwidth(wpos.xz);
		float cell_px = 8.0 / max(max(fw.x, fw.y), 0.0001);
		float fade = clamp((cell_px - 10.0) / 20.0, 0.0, 1.0);
		vec2 g = abs(fract(wpos.xz / 8.0 + 0.5) - 0.5) * 8.0;
		if (g.x < fw.x * 0.6 || g.y < fw.y * 0.6) {
			col = mix(col, vec3(0.62, 0.86, 0.92), 0.22 * fade);
		}
	}
	// außerhalb des Spielfelds dunkler, am Rand eine Linie
	float edge = max(abs(wpos.x), abs(wpos.z)) - bound;
	if (edge > 0.0) {
		col = mix(col, vec3(0.13, 0.14, 0.11), 0.65);
	} else if (edge > -6.0) {
		col = mix(col, vec3(0.85, 0.8, 0.55), 0.35);
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
