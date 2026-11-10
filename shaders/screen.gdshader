// Werbe- und Infobildschirm: wechselt alle paar Sekunden das Motiv, leuchtet nachts heller.
shader_type spatial;
render_mode unshaded;

global uniform float night;
uniform float seed = 0.0;
uniform int mode = 0;   // 0 Werbung, 1 Abflugtafel (Zeilen in Gelb und Weiß auf Dunkelblau), 2 Gate-Anzeige

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 board(vec2 uv, float rows) {
	// Fluginformationsanzeige: Kopfzeile, Zeilen mit Zeit, Ziel, Gate, Status; blättert langsam
	vec3 bg = vec3(0.04, 0.07, 0.18);
	float r = floor(uv.y * rows);
	float page = floor(TIME * 0.08 + seed);
	vec2 cell = vec2(floor(uv.x * 46.0), r);
	float fy = fract(uv.y * rows);
	float glyph = step(0.2, fy) * step(fy, 0.8);
	float on = step(0.35, hash(cell + vec2(page * 3.1, floor(fract(uv.y * rows * 3.0) * 3.0))));
	float col_x = uv.x * 46.0;
	float gap = step(5.0, col_x) * step(col_x, 6.0) + step(25.0, col_x) * step(col_x, 27.0) + step(32.0, col_x) * step(col_x, 34.0);
	vec3 ink = col_x < 5.0 ? vec3(1.0, 0.82, 0.25) : (col_x > 34.0 ? vec3(0.4, 0.95, 0.5) : vec3(0.95));
	if (r == rows - 1.0) {
		bg = vec3(0.95, 0.75, 0.15);
		ink = vec3(0.04, 0.07, 0.18);
	}
	if (mod(r, 2.0) == 1.0 && r < rows - 1.0) {
		bg *= 1.35;
	}
	return mix(bg, ink, glyph * on * (1.0 - gap));
}

void fragment() {
	vec2 uv = UV;
	if (mode >= 1) {
		vec3 c = board(vec2(uv.x, 1.0 - uv.y), mode == 1 ? 9.0 : 4.0);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
		c = pow(c, vec3(2.2));
#endif
		ALBEDO = c * (0.9 + night * 0.8);
	} else {
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
}
