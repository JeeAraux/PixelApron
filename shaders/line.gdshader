// Belag und Markierungen für Wege. UV.x = quer (0..1), UV.y = Meter entlang des Weges.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.2, 0.2, 0.19);
uniform int mark = 0; // 1 Straße, 2 Rollweg, 3 Piste, 4 Gehweg, 5 Vorfeld, 6 vierspurig, 7 Einbahn, 8 Schulter, 9 Förderband, 10 Betriebsstraße
uniform float width = 7.5;
uniform float len = 100.0;
uniform int flip = 0;
uniform int num_a = 9;    // Pistenkennzahl am Anfang (Richtung Anfang → Ende)
uniform int num_b = 27;   // Kennzahl am Ende
uniform float core = 0.0; // Schulter: Breite der tragfähigen Fläche in der Mitte

// Ziffern 5 × 7, je Zeile 5 Bit (links = höchstes Bit)
const int DIGITS[70] = {
	14, 17, 19, 21, 25, 17, 14,
	4, 12, 4, 4, 4, 4, 14,
	14, 17, 1, 2, 4, 8, 31,
	31, 2, 4, 2, 1, 17, 14,
	2, 6, 10, 18, 31, 2, 2,
	31, 16, 30, 1, 1, 17, 14,
	6, 8, 16, 30, 17, 17, 14,
	31, 1, 2, 4, 8, 8, 8,
	14, 17, 17, 14, 17, 17, 14,
	14, 17, 17, 15, 1, 2, 12
};

// Ist das Pixel (cx, cy) der Ziffer d gesetzt? cy = 0 oben.
bool digit_px(int d, int cx, int cy) {
	if (cx < 0 || cx > 4 || cy < 0 || cy > 6) {
		return false;
	}
	int row = DIGITS[d * 7 + cy];
	return ((row >> (4 - cx)) & 1) == 1;
}

// Zweistellige Kennzahl: x quer (Meter, Mitte 0), y = 0..9 m von unten nach oben
bool rwy_number(int num, float x, float y) {
	float pw = 0.6;
	float ph = 9.0 / 7.0;
	int cy = 6 - int(floor(y / ph));
	int tens = num / 10;
	int ones = num - tens * 10;
	if (x > -3.75 && x < -0.75) {
		return digit_px(tens, int(floor((x + 3.75) / pw)), cy);
	}
	if (x > 0.75 && x < 3.75) {
		return digit_px(ones, int(floor((x - 0.75) / pw)), cy);
	}
	return false;
}

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
	} else if (mark == 10) {
		// Betriebsstraße auf der Luftseite: weiße Randlinien, gestrichelte Mitte, Zebra-Kanten alle 40 m
		if (abs(ax - (half_w - 0.35)) < 0.12) {
			col = white;
		}
		if (ax < 0.1 && mod(v, 5.0) < 2.5) {
			col = white * 0.95;
		}
		if (ax > half_w - 0.12) {
			col = vec3(0.5, 0.49, 0.46);
		}
		float zv = mod(v, 40.0);
		if (zv < 3.0 && ax < half_w - 0.5 && mod(v + x, 1.2) < 0.6 && ax > half_w - 1.4) {
			col = white * 0.9;
		}
	} else if (mark == 2) {
		// ICAO: durchgehende gelbe Mittellinie, doppelte gelbe Randlinie am Rand der tragfähigen Fläche
		if (ax < 0.18) {
			col = yellow;
		}
		if (abs(ax - (half_w - 0.3)) < 0.15 || abs(ax - (half_w - 0.8)) < 0.15) {
			col = yellow * 0.95;
		}
	} else if (mark == 8) {
		// Schulter neben Rollweg und Piste: heller, rauer Belag, nicht tragfähig
		col = base_color * (0.88 + 0.16 * hash(floor(wpos.xz * 1.3)));
		if (ax > half_w - 0.35) {
			col *= 0.82;
		}
	} else if (mark == 3) {
		// ICAO-Pistenmarkierung, von beiden Enden her gleich aufgebaut
		bool far_end = v > len * 0.5;
		float d = far_end ? len - v : v;
		float xx = far_end ? -x : x;
		float dt = d - 6.0;   // Abstand von der Schwelle (6 m vom Pistenende)
		// Seitenstreifen
		if (ax > half_w - 1.2 && ax < half_w - 0.3) {
			col = white;
		}
		// Schwellenbalken: 30 m lang, 12 Balken
		if (dt > 0.0 && dt < 30.0 && ax > 1.5 && ax < half_w - 3.0 && mod(ax - 1.5, 3.05) < 1.75) {
			col = white;
		}
		// Kennzahl 12 m hinter den Balken, 9 m hoch
		float ny = dt - 42.0;
		if (ny >= 0.0 && ny < 9.0 && rwy_number(far_end ? num_b : num_a, xx, ny)) {
			col = white;
		}
		// Mittellinie: 30 m Strich, 20 m Lücke
		if (ax < 0.45 && dt > 63.0 && mod(v - 69.0, 50.0) < 30.0) {
			col = white;
		}
		// Zielpunktmarkierung
		float aim = len >= 2400.0 ? 400.0 : (len >= 1500.0 ? 300.0 : 250.0);
		if (dt > aim && dt < aim + 45.0 && ax > 9.0 && ax < 15.0) {
			col = white;
		}
		// Aufsetzzone: Streifenpaare alle 150 m (3, 3, 2, 2, 1, 1 Streifen)
		int pairs = len >= 2400.0 ? 6 : (len >= 1500.0 ? 4 : (len >= 900.0 ? 3 : 2));
		for (int k = 1; k <= 6; k++) {
			if (k > pairs) {
				break;
			}
			float z0 = 150.0 * float(k);
			if (z0 > aim - 60.0 && z0 < aim + 60.0) {
				continue;
			}
			if (dt > z0 && dt < z0 + 22.5) {
				int stripes = k <= 2 ? 3 : (k <= 4 ? 2 : 1);
				for (int q = 0; q < 3; q++) {
					if (q >= stripes) {
						break;
					}
					float a0 = 9.0 + float(q) * 4.5;
					if (ax > a0 && ax < a0 + 3.0) {
						col = white;
					}
				}
			}
		}
		// Reifenabrieb in der Aufsetzzone
		if (dt > 250.0 && dt < 700.0 && abs(ax - 4.5) < 2.5) {
			col *= 0.82 + 0.1 * hash(floor(vec2(v * 0.2, x * 2.0)));
		}
	} else if (mark == 4) {
		if (fract(v) < 0.1 || fract(UV.x * width) < 0.1) {
			col *= 0.82;
		}
		if (ax > half_w - 0.2) {
			col *= 0.75;
		}
	} else if (mark == 5) {
		// Betonplatten 5 × 5 m mit Fugen, leicht unterschiedlich gealtert, vereinzelt Ölflecken
		vec2 cell = floor(wpos.xz / 5.0);
		vec2 g = fract(wpos.xz / 5.0);
		col = base_color * (0.95 + 0.08 * hash(cell));
		if (g.x < 0.025 || g.y < 0.025) {
			col *= 0.84;
		}
		vec2 o = g - vec2(hash(cell + 3.1), hash(cell + 7.7));
		if (hash(cell + 1.3) > 0.93 && dot(o, o) < 0.03) {
			col *= 0.78;
		}
	} else if (mark == 9) {
		// Gepäckförderband: Gummiband mit Querrillen, das sich bewegt; seitlich Stahlrahmen
		float run = v - TIME * 1.6;
		col = vec3(0.13, 0.13, 0.14) * (0.9 + 0.2 * step(0.5, fract(run * 2.5)));
		if (ax > 0.55) {
			col = vec3(0.45, 0.47, 0.5);
		}
		if (ax > 0.95) {
			col = vec3(0.86, 0.69, 0.22);
		}
	}
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
