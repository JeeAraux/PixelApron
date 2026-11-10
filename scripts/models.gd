extends RefCounted
## Detaillierte Modelle aus dem Mesh-Baukasten: Flugzeuge (A320, B737-800), Menschen mit Laufposen,
## Autos verschiedener Bauart und Bodenfahrzeuge. Jedes Modell wird einmal gebaut und zwischengespeichert.
## Vorne ist immer -Z, oben +Y, Boden y = 0. Maße in Metern nach den echten Vorbildern.

const Kit = preload("res://scripts/mesh_kit.gd")

const WHITE := Color(0.93, 0.93, 0.91)
const BELLY := Color(0.79, 0.80, 0.81)
const WING := Color(0.74, 0.75, 0.76)
const WING_DARK := Color(0.58, 0.59, 0.61)
const GLASS := Color(0.09, 0.12, 0.16)
const WIN := Color(0.15, 0.18, 0.23)
const TYRE := Color(0.07, 0.07, 0.08)
const METAL := Color(0.62, 0.63, 0.65)
const DARK_METAL := Color(0.30, 0.31, 0.33)
const DOOR_LINE := Color(0.60, 0.61, 0.62)
const RED := Color(0.9, 0.12, 0.1)
const GREEN := Color(0.1, 0.85, 0.3)
const YELLOW := Color(0.88, 0.70, 0.18)

static var _cache: Dictionary = {}

## Bauweise der Flugzeuge. z vorne negativ. Werte nach A320ceo und 737-800.
const SPECS := {
	"a320": {
		"len": 37.6, "r": 1.98, "cy": 3.35, "nose_len": 5.2, "nose_drop": 0.32, "nose_pow": 2.2,
		"tail_start": 6.4, "tail_r": 0.40, "tail_drop": 0.35,
		"wing_z": -4.6, "wing_c": 6.4, "kink_c": 3.9, "tip_x": 16.9, "tip_c": 1.6, "sweep": 27.0, "dihedral": 5.0, "wing_y": 2.05,
		"winglet": [2.3, 0.25, 1.2, 0.55],
		"eng_x": 5.75, "eng_y": 1.62, "eng_r": 1.08, "eng_flat": 1.0, "eng_z": -7.5, "eng_len": 4.3,
		"stab_z": 14.4, "stab_c": 3.6, "stab_span": 6.3, "stab_y": 4.5, "stab_sweep": 32.0,
		"fin_z": 11.0, "fin_c": 6.4, "fin_h": 6.4, "fin_sweep": 35.0, "fin_tip_c": 2.3, "dorsal": false,
		"nose_gear_z": -13.9, "main_gear_z": 1.3, "main_gear_x": 3.8, "main_wheel_r": 0.58, "nose_wheel_r": 0.36,
		"doors": [-15.2, 12.7], "exits": [-1.5, -0.6], "win_from": -13.6, "win_to": 11.3, "win_dy": 0.52,
	},
	"b737": {
		"len": 39.5, "r": 1.88, "cy": 3.0, "nose_len": 6.4, "nose_drop": 0.58, "nose_pow": 3.0,
		"tail_start": 8.4, "tail_r": 0.20, "tail_drop": 0.55,
		"wing_z": -4.3, "wing_c": 7.2, "kink_c": 4.2, "tip_x": 17.0, "tip_c": 1.5, "sweep": 25.0, "dihedral": 6.0, "wing_y": 1.75,
		"winglet": [2.5, 0.6, 1.5, 0.45],
		"eng_x": 4.95, "eng_y": 1.50, "eng_r": 1.02, "eng_flat": 0.84, "eng_z": -8.3, "eng_len": 3.9,
		"stab_z": 15.2, "stab_c": 3.9, "stab_span": 7.0, "stab_y": 4.0, "stab_sweep": 30.0,
		"fin_z": 12.2, "fin_c": 6.6, "fin_h": 7.4, "fin_sweep": 35.0, "fin_tip_c": 2.0, "dorsal": true,
		"nose_gear_z": -15.6, "main_gear_z": 1.8, "main_gear_x": 2.86, "main_wheel_r": 0.56, "nose_wheel_r": 0.34,
		"doors": [-16.2, 14.6], "exits": [-0.3, 0.6], "win_from": -14.6, "win_to": 13.2, "win_dy": 0.48,
	},
}


# ================================================================== Flugzeuge

static func plane_mesh(kind: String, livery: Color) -> ArrayMesh:
	var key := "plane_%s_%s" % [kind, livery.to_html()]
	if _cache.has(key):
		return _cache[key]
	var s: Dictionary = SPECS.get(kind, SPECS["a320"])
	var k := Kit.new()
	_fuselage(k, s, livery)
	_wings(k, s, livery)
	_tail(k, s, livery)
	for side: float in [-1.0, 1.0]:
		_engine(k, s, livery, side)
	_lights(k, s)
	_wordmark(k, s, livery)
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh


## Fahrwerk als eigenes Mesh, damit es nach dem Start einfahren kann.
static func gear_mesh(kind: String) -> ArrayMesh:
	var key := "gear_" + kind
	if _cache.has(key):
		return _cache[key]
	var k := Kit.new()
	_gear(k, SPECS.get(kind, SPECS["a320"]))
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh


## Fan mit Schaufeln und Spinner, dreht sich um die eigene z-Achse.
static func fan_mesh(kind: String) -> ArrayMesh:
	var key := "fan_" + kind
	if _cache.has(key):
		return _cache[key]
	var s: Dictionary = SPECS.get(kind, SPECS["a320"])
	var r: float = float(s["eng_r"]) * 0.84
	var flat: float = s["eng_flat"]
	var k := Kit.new()
	k.cyl(Vector3(0, 0, 0.0), Vector3(0, 0, 0.06), r, r, Color(0.12, 0.13, 0.15), 20)
	for i in range(18):
		var a := TAU * float(i) / 18.0
		var dir := Vector3(cos(a), sin(a) * flat, 0)
		var tang := Vector3(-sin(a), cos(a) * flat, 0).normalized()
		var p0 := dir * 0.3
		var p1 := dir * r * 0.97
		k.quad(p0 - tang * 0.05 + Vector3(0, 0, -0.02), p1 - tang * 0.11 + Vector3(0, 0, -0.02),
			p1 + tang * 0.11 + Vector3(0, 0, -0.06), p0 + tang * 0.05 + Vector3(0, 0, -0.06), Color(0.42, 0.44, 0.47), Vector3(0, 0, 1))
	k.cyl(Vector3(0, 0, -0.38), Vector3(0, 0, -0.02), 0.02, 0.3, METAL, 12)
	k.panel(Vector3(0.12, 0.05, -0.2), Vector3(0.05, 0.0, 0.0), Vector3(0, 0.05, 0.05), Color(0.2, 0.2, 0.22), Vector3(0, 0, -1))
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh


## Schriftzug der Airline als Pixelmuster über den Fenstern (aus der Hausfarbe abgeleitet).
static func _wordmark(k: Kit, s: Dictionary, livery: Color) -> void:
	var pattern := absi(livery.to_html().hash())
	var dy: float = float(s["win_dy"]) + 0.52
	var z := -11.8
	for i in range(22):
		var bits := (pattern >> (i % 24)) & 3
		if bits != 0 and i % 4 != 3:
			for side: float in [-1.0, 1.0]:
				_on_skin(k, s, side, z, dy + (0.08 if bits == 2 else 0.0), 0.11, 0.17 if bits != 2 else 0.1, livery.darkened(0.15), 0.03)
		z += 0.27


## Querschnitt des Rumpfs an der Stelle z: [Mitte y, Radius quer, Radius hoch]
static func _profile(s: Dictionary, z: float) -> Array:
	var length: float = s["len"]
	var r: float = s["r"]
	var cy: float = s["cy"]
	var z0 := -length * 0.5
	var z1 := length * 0.5
	var nose_len: float = s["nose_len"]
	var ts: float = s["tail_start"]
	if z < z0 + nose_len:
		var t := clampf((z - z0) / nose_len, 0.0, 1.0)
		var rr := r * pow(1.0 - pow(1.0 - t, float(s["nose_pow"])), 0.55)
		var drop := float(s["nose_drop"]) * pow(1.0 - t, 2.0)
		return [cy - drop, maxf(rr, 0.04), maxf(rr * (1.0 - 0.06 * (1.0 - t)), 0.04)]
	if z > ts:
		var t := clampf((z - ts) / (z1 - ts), 0.0, 1.0)
		var rr := lerpf(r, float(s["tail_r"]), pow(t, 1.15))
		var top := cy + r - float(s["tail_drop"]) * t * t
		return [top - rr, rr, rr]
	return [cy, r, r]


static func _fuselage(k: Kit, s: Dictionary, livery: Color) -> void:
	var length: float = s["len"]
	var z0 := -length * 0.5
	var z1 := length * 0.5
	var nose_len: float = s["nose_len"]
	var ts: float = s["tail_start"]
	var zs := []
	for i in range(16):
		zs.append(z0 + nose_len * pow(float(i) / 15.0, 1.6))
	var z := z0 + nose_len + 0.8
	while z < ts:
		zs.append(z)
		z += 0.8
	for i in range(15):
		zs.append(lerpf(ts, z1, float(i) / 14.0))
	var rings := []
	for zz: float in zs:
		var p := _profile(s, zz)
		rings.append([zz, p[0], p[1], p[2]])
	var cock_a := z0 + nose_len * 0.55
	var cock_b := z0 + nose_len * 0.80
	var col_fn := func(fz: float, fx: float, dy: float, ry: float) -> Color:
		if fz < z0 + 0.45:
			return Color(0.80, 0.80, 0.79)
		if fz > z1 - 0.35:
			return DARK_METAL
		if fz > cock_a and fz < cock_b and dy > ry * 0.2 and dy < ry * (0.6 - 0.25 * (fz - cock_a) / (cock_b - cock_a)):
			var ax := absf(fx) / maxf(ry, 0.01)
			if absf(fx) < 0.05 or (ax > 0.36 and ax < 0.43) or (ax > 0.72 and ax < 0.79) or ax > 0.95:
				return Color(0.25, 0.26, 0.28)
			return GLASS
		if dy < -ry * 0.48:
			return BELLY
		if dy > -ry * 0.34 and dy < -ry * 0.14 and fz > z0 + nose_len * 0.9 and fz < ts + 4.0:
			return livery
		return WHITE
	k.lathe(rings, 24, col_fn, true, true)
	# Fenster, Türen und Notausstiege auf beiden Seiten
	var wdy: float = s["win_dy"]
	var doors: Array = s["doors"]
	var exits: Array = s["exits"]
	for side: float in [-1.0, 1.0]:
		var wz: float = s["win_from"]
		while wz <= float(s["win_to"]):
			var blocked := false
			for e: float in exits:
				blocked = blocked or absf(wz - e) < 0.32
			if not blocked:
				_on_skin(k, s, side, wz, wdy, 0.12, 0.16, WIN, 0.02)
			wz += 0.535
		for d: float in doors:
			_on_skin(k, s, side, d, -0.02, 0.44, 0.98, DOOR_LINE, 0.015)
			_on_skin(k, s, side, d, -0.02, 0.38, 0.92, WHITE, 0.025)
			_on_skin(k, s, side, d, wdy - 0.05, 0.12, 0.14, WIN, 0.035)
		for e: float in exits:
			_on_skin(k, s, side, e, 0.12, 0.27, 0.5, DOOR_LINE, 0.015)
			_on_skin(k, s, side, e, 0.12, 0.23, 0.46, WHITE, 0.025)
			_on_skin(k, s, side, e, wdy, 0.1, 0.13, WIN, 0.035)
	# Frachttüren rechts unten, Antennen und Ablaufmasten am Bauch
	for cz: float in [float(s["wing_z"]) - 5.5, float(s["tail_start"]) - 1.0]:
		_on_skin(k, s, 1.0, cz, -float(s["r"]) * 0.5, 0.9, 0.62, DOOR_LINE, 0.015)
		_on_skin(k, s, 1.0, cz, -float(s["r"]) * 0.5, 0.84, 0.56, BELLY, 0.025)
	var by := float(s["cy"]) - float(s["r"])
	for az: float in [-10.0, -3.0, 8.0]:
		k.box(Vector3(-0.03, by - 0.35, az), Vector3(0.03, by + 0.05, az + 0.4), DARK_METAL)
	# Rumpf-Flügel-Verkleidung unter dem Mittelrumpf
	var cy: float = s["cy"]
	var r: float = s["r"]
	var wz0: float = s["wing_z"]
	var wc: float = s["wing_c"]
	var bot := cy - r
	var a := [Vector3(-r * 0.78, bot - 0.15, wz0 - 0.8), Vector3(r * 0.78, bot - 0.15, wz0 - 0.8),
		Vector3(r * 0.7, bot - 0.15, wz0 + wc + 1.8), Vector3(-r * 0.7, bot - 0.15, wz0 + wc + 1.8)]
	var b := [Vector3(-r * 0.92, bot + 0.7, wz0 - 1.6), Vector3(r * 0.92, bot + 0.7, wz0 - 1.6),
		Vector3(r * 0.85, bot + 0.7, wz0 + wc + 2.8), Vector3(-r * 0.85, bot + 0.7, wz0 + wc + 2.8)]
	k.prism(a, b, BELLY)


## Fläche (Fenster, Tür) auf der Rumpfhaut: Mitte bei Höhe dy über der Mittellinie, folgt der Wölbung.
static func _on_skin(k: Kit, s: Dictionary, side: float, z: float, dy: float, half_w: float, half_h: float, col: Color, lift: float) -> void:
	var p := _profile(s, z)
	var cy: float = p[0]
	var rx: float = p[1]
	var ry: float = p[2]
	var yy := clampf(dy / ry, -0.98, 0.98)
	var x := rx * sqrt(1.0 - yy * yy)
	var n := Vector3(side * x / (rx * rx), dy / (ry * ry), 0.0).normalized()
	var up := Vector3(-n.y * side, absf(n.x), 0.0).normalized()
	if up.y < 0.0:
		up = -up
	var c := Vector3(side * x, cy + dy, z) + n * lift
	k.panel(c, Vector3(0, 0, half_w), up * half_h, col, n)


## Fläche aus zwei Profilschnitten: Vorderkante a mit Tiefe ca, Vorderkante b mit Tiefe cb.
## dir = Richtung der Dicke (Flügel: oben, Leitwerk: seitlich).
static func _surface(k: Kit, a: Vector3, ca: float, b: Vector3, cb: float, dir: Vector3, tha: float, thb: float, col: Color, side_col: Variant = null) -> void:
	var z := Vector3(0, 0, 1)
	var bottom := [a - dir * tha * 0.5, a + z * ca - dir * tha * 0.2, b + z * cb - dir * thb * 0.2, b - dir * thb * 0.5]
	var top := [a + dir * tha * 0.5, a + z * ca + dir * tha * 0.2, b + z * cb + dir * thb * 0.2, b + dir * thb * 0.5]
	k.prism(bottom, top, col, side_col)


static func _wing_at(s: Dictionary, ax: float) -> Array:
	var root_x: float = float(s["r"]) * 0.82
	var d := ax - root_x
	var le := float(s["wing_z"]) + d * tan(deg_to_rad(float(s["sweep"])))
	var y := float(s["wing_y"]) + d * tan(deg_to_rad(float(s["dihedral"])))
	var kink_x := float(s["eng_x"]) + 1.4
	var chord := 0.0
	if ax <= kink_x:
		chord = lerpf(float(s["wing_c"]), float(s["kink_c"]), (ax - root_x) / (kink_x - root_x))
	else:
		chord = lerpf(float(s["kink_c"]), float(s["tip_c"]), (ax - kink_x) / (float(s["tip_x"]) - kink_x))
	return [le, y, chord]


static func _wings(k: Kit, s: Dictionary, livery: Color) -> void:
	var root_x: float = float(s["r"]) * 0.82
	var kink_x := float(s["eng_x"]) + 1.4
	var tip_x: float = s["tip_x"]
	var stations := [root_x, kink_x, tip_x]
	var thick := [0.62, 0.38, 0.13]
	for side: float in [-1.0, 1.0]:
		for i in range(2):
			var wa := _wing_at(s, stations[i])
			var wb := _wing_at(s, stations[i + 1])
			_surface(k, Vector3(side * stations[i], wa[1], wa[0]), wa[2], Vector3(side * stations[i + 1], wb[1], wb[0]), wb[2],
				Vector3.UP, thick[i], thick[i + 1], WING, WING_DARK)
		# Landeklappen-Linie und Vorflügel als feine Streifen oben auf dem Flügel
		for i in range(2):
			var wa := _wing_at(s, stations[i] + 0.2)
			var wb := _wing_at(s, stations[i + 1] - (0.6 if i == 1 else 0.0))
			var ya: float = float(wa[1]) + float(thick[i]) * 0.22
			var yb: float = float(wb[1]) + float(thick[i + 1]) * 0.22
			k.quad(Vector3(side * (stations[i] + 0.2), ya + 0.01, float(wa[0]) + float(wa[2]) * 0.72),
				Vector3(side * (stations[i + 1] - (0.6 if i == 1 else 0.0)), yb + 0.01, float(wb[0]) + float(wb[2]) * 0.72),
				Vector3(side * (stations[i + 1] - (0.6 if i == 1 else 0.0)), yb + 0.01, float(wb[0]) + float(wb[2]) * 0.76),
				Vector3(side * (stations[i] + 0.2), ya + 0.01, float(wa[0]) + float(wa[2]) * 0.76),
				WING_DARK, Vector3(0, -10, 0))
		# Querruder außen und Vorflügel-Linie
		var ail_a := tip_x - 6.5
		var ail_b := tip_x - 1.2
		var wa2 := _wing_at(s, ail_a)
		var wb2 := _wing_at(s, ail_b)
		for f: Array in [[0.8, 0.97, WING_DARK.lightened(0.08)], [0.09, 0.12, WING_DARK]]:
			k.quad(Vector3(side * ail_a, float(wa2[1]) + 0.06, float(wa2[0]) + float(wa2[2]) * float(f[0])),
				Vector3(side * ail_b, float(wb2[1]) + 0.04, float(wb2[0]) + float(wb2[2]) * float(f[0])),
				Vector3(side * ail_b, float(wb2[1]) + 0.04, float(wb2[0]) + float(wb2[2]) * float(f[1])),
				Vector3(side * ail_a, float(wa2[1]) + 0.06, float(wa2[0]) + float(wa2[2]) * float(f[1])), f[2], Vector3(0, -10, 0))
		var wr2 := _wing_at(s, float(s["r"]) * 0.9)
		k.quad(Vector3(side * float(s["r"]) * 0.9, float(wr2[1]) + 0.3, float(wr2[0]) + float(wr2[2]) * 0.09),
			Vector3(side * ail_a, float(wa2[1]) + 0.08, float(wa2[0]) + float(wa2[2]) * 0.09),
			Vector3(side * ail_a, float(wa2[1]) + 0.08, float(wa2[0]) + float(wa2[2]) * 0.12),
			Vector3(side * float(s["r"]) * 0.9, float(wr2[1]) + 0.3, float(wr2[0]) + float(wr2[2]) * 0.12), WING_DARK, Vector3(0, -10, 0))
		# Spoiler
		for i in range(4):
			var sx0 := float(s["eng_x"]) + 0.4 + float(i) * 1.6
			var sw0 := _wing_at(s, sx0)
			var sw1 := _wing_at(s, sx0 + 1.4)
			k.quad(Vector3(side * sx0, float(sw0[1]) + 0.2, float(sw0[0]) + float(sw0[2]) * 0.55),
				Vector3(side * (sx0 + 1.4), float(sw1[1]) + 0.19, float(sw1[0]) + float(sw1[2]) * 0.55),
				Vector3(side * (sx0 + 1.4), float(sw1[1]) + 0.19, float(sw1[0]) + float(sw1[2]) * 0.7),
				Vector3(side * sx0, float(sw0[1]) + 0.2, float(sw0[0]) + float(sw0[2]) * 0.7), WING.darkened(0.06), Vector3(0, -10, 0))
		# Klappenschienen-Verkleidungen unter der Hinterkante
		for fx: float in [kink_x - 1.6, kink_x + 2.2, kink_x + 5.2, kink_x + 8.0]:
			var w := _wing_at(s, fx)
			var te: float = float(w[0]) + float(w[2])
			var wy: float = w[1]
			k.prism([Vector3(side * fx - 0.15, wy - 0.05, te - 1.6), Vector3(side * fx + 0.15, wy - 0.05, te - 1.6),
				Vector3(side * fx + 0.12, wy - 0.05, te + 0.9), Vector3(side * fx - 0.12, wy - 0.05, te + 0.9)],
				[Vector3(side * fx - 0.15, wy - 0.4, te - 1.0), Vector3(side * fx + 0.15, wy - 0.4, te - 1.0),
				Vector3(side * fx + 0.08, wy - 0.25, te + 0.9), Vector3(side * fx - 0.08, wy - 0.25, te + 0.9)], WING_DARK)
		# Winglet
		var wl: Array = s["winglet"]
		var tip := _wing_at(s, tip_x)
		var base := Vector3(side * tip_x, float(tip[1]), float(tip[0]))
		var top := base + Vector3(side * float(wl[1]), float(wl[0]), float(wl[2]))
		_surface(k, base, float(tip[2]), top, float(wl[3]), Vector3(1, 0, 0), 0.14, 0.06, livery, WING_DARK)


static func _tail(k: Kit, s: Dictionary, livery: Color) -> void:
	# Höhenleitwerk
	var sz: float = s["stab_z"]
	var sy: float = s["stab_y"]
	var span: float = s["stab_span"]
	var sw := tan(deg_to_rad(float(s["stab_sweep"])))
	for side: float in [-1.0, 1.0]:
		_surface(k, Vector3(side * 0.3, sy, sz), float(s["stab_c"]), Vector3(side * span, sy + span * 0.09, sz + (span - 0.3) * sw),
			float(s["stab_c"]) * 0.38, Vector3.UP, 0.3, 0.1, WING, WING_DARK)
	# Höhenruder-Linie
	for side: float in [-1.0, 1.0]:
		var ez0 := sz + float(s["stab_c"]) * 0.7
		var ez1 := sz + (span - 0.3) * sw + float(s["stab_c"]) * 0.38 * 0.7
		k.quad(Vector3(side * 0.6, sy + 0.1, ez0), Vector3(side * span * 0.95, sy + span * 0.09 + 0.05, ez1),
			Vector3(side * span * 0.95, sy + span * 0.09 + 0.05, ez1 + 0.08), Vector3(side * 0.6, sy + 0.1, ez0 + 0.1),
			WING_DARK, Vector3(0, -10, 0))
	# Seitenleitwerk in Airline-Farbe mit Emblem
	var fz: float = s["fin_z"]
	var fc: float = s["fin_c"]
	var fh: float = s["fin_h"]
	var prof := _profile(s, fz + fc * 0.5)
	var base_y: float = float(prof[0]) + float(prof[2]) - 0.15
	var tip_z := fz + fh * tan(deg_to_rad(float(s["fin_sweep"])))
	_surface(k, Vector3(0, base_y, fz), fc, Vector3(0, base_y + fh, tip_z), float(s["fin_tip_c"]), Vector3(1, 0, 0), 0.42, 0.16, livery)
	if bool(s["dorsal"]):
		_surface(k, Vector3(0, base_y - 0.1, fz - 3.6), 3.6, Vector3(0, base_y + 1.2, fz - 0.3), 0.3, Vector3(1, 0, 0), 0.3, 0.2, livery)
	for side: float in [-1.0, 1.0]:
		var rz0 := fz + fc * 0.68
		var rz1 := tip_z + float(s["fin_tip_c"]) * 0.68
		k.quad(Vector3(side * 0.135, base_y + 0.3, rz0), Vector3(side * 0.06, base_y + fh * 0.97, rz1),
			Vector3(side * 0.06, base_y + fh * 0.97, rz1 + 0.07), Vector3(side * 0.135, base_y + 0.3, rz0 + 0.07),
			livery.darkened(0.3), Vector3(-side * 10.0, base_y + fh * 0.5, (rz0 + rz1) * 0.5))
	var mid_y := base_y + fh * 0.48
	var mid_z := lerpf(fz, tip_z, 0.48) + lerpf(fc, float(s["fin_tip_c"]), 0.48) * 0.5
	for side: float in [-1.0, 1.0]:
		var n := Vector3(side, 0, 0)
		k.panel(Vector3(side * 0.17, mid_y, mid_z), Vector3(0, 0.62, 0.62), Vector3(0, 0.62, -0.62), WHITE, n)
		k.panel(Vector3(side * 0.18, mid_y, mid_z), Vector3(0, 0.34, 0.34), Vector3(0, 0.34, -0.34), livery.lightened(0.35), n)


static func _engine(k: Kit, s: Dictionary, livery: Color, side: float) -> void:
	var ex := side * float(s["eng_x"])
	var ey: float = s["eng_y"]
	var r: float = s["eng_r"]
	var flat: float = s["eng_flat"]
	var z0: float = s["eng_z"]
	var ln: float = s["eng_len"]
	var rings := [[z0, ey, r * 0.86, r * 0.86 * flat], [z0 + 0.12, ey, r * 0.97, r * 0.97 * flat],
		[z0 + ln * 0.3, ey, r * 1.03, r * 1.03 * flat], [z0 + ln * 0.75, ey, r * 0.94, r * 0.94 * flat], [z0 + ln, ey, r * 0.72, r * 0.72 * flat]]
	var col_fn := func(fz: float, _fx: float, _dy: float, _ry: float) -> Color:
		if fz < z0 + 0.14:
			return METAL
		if fz > z0 + ln * 0.8:
			return WHITE.darkened(0.08)
		if fz > z0 + ln * 0.55 and fz < z0 + ln * 0.6:
			return livery.darkened(0.3)
		return livery
	k.lathe(rings, 18, col_fn, false, false, ex)
	# Fan, Spinner, Schubdüse
	k.cyl(Vector3(ex, ey, z0 + 0.5), Vector3(ex, ey, z0 + 0.56), r * 0.86, r * 0.86 * flat, Color(0.1, 0.1, 0.12), 18)
	k.cyl(Vector3(ex, ey, z0 + ln - 0.05), Vector3(ex, ey, z0 + ln + 0.9), r * 0.55, 0.12, DARK_METAL, 12)
	# Pylon zum Flügel
	var w := _wing_at(s, absf(ex))
	var top_y := ey + r * flat * 0.85
	_surface(k, Vector3(ex, top_y, z0 + 0.9), ln - 0.6, Vector3(ex, float(w[1]) - 0.05, float(w[0]) - 0.4), float(w[2]) * 0.75,
		Vector3(1, 0, 0), 0.34, 0.3, WHITE.darkened(0.06))


static func _gear(k: Kit, s: Dictionary) -> void:
	var cy: float = s["cy"]
	var r: float = s["r"]
	var bot := cy - r
	var nz: float = s["nose_gear_z"]
	var nr: float = s["nose_wheel_r"]
	var nb := float(_profile(s, nz)[0]) - float(_profile(s, nz)[2])
	k.cyl(Vector3(0, nb + 0.2, nz), Vector3(0, nr, nz + 0.12), 0.09, 0.09, METAL, 8)
	for side: float in [-1.0, 1.0]:
		k.cyl(Vector3(side * 0.08, nr, nz + 0.12), Vector3(side * 0.34, nr, nz + 0.12), nr, nr, TYRE, 12, true, DARK_METAL)
		k.box(Vector3(side * 0.42, nb - 0.9, nz - 0.9), Vector3(side * 0.46, nb + 0.1, nz + 0.4), WHITE)
	var mz: float = s["main_gear_z"]
	var mx: float = s["main_gear_x"]
	var mr: float = s["main_wheel_r"]
	for side: float in [-1.0, 1.0]:
		var w := _wing_at(s, mx)
		var x := side * mx
		k.cyl(Vector3(x, float(w[1]) - 0.1, mz - 0.2), Vector3(x, mr, mz), 0.14, 0.12, METAL, 8)
		k.box(Vector3(x - 0.5, mr - 0.06, mz - 0.06), Vector3(x + 0.5, mr + 0.06, mz + 0.06), METAL)
		for off: float in [-0.48, 0.48]:
			k.cyl(Vector3(x + off - 0.19, mr, mz), Vector3(x + off + 0.19, mr, mz), mr, mr, TYRE, 14, true, DARK_METAL)
		k.box(Vector3(x + side * 0.25, mr + 0.5, mz - 0.7), Vector3(x + side * 0.3, float(w[1]) - 0.2, mz + 0.6), WHITE)
	# Fahrwerksschacht dunkel unter dem Rumpf
	k.box(Vector3(-mx + 0.6, bot - 0.16, mz - 1.0), Vector3(mx - 0.6, bot - 0.12, mz + 1.0), Color(0.35, 0.36, 0.38))


static func _lights(k: Kit, s: Dictionary) -> void:
	var cy: float = s["cy"]
	var r: float = s["r"]
	k.box(Vector3(-0.1, cy + r - 0.02, -1.15), Vector3(0.1, cy + r + 0.08, -0.95), Color(0.4, 0.1, 0.1))
	var tip := _wing_at(s, float(s["tip_x"]))
	for side: float in [-1.0, 1.0]:
		var x := side * float(s["tip_x"])
		k.box(Vector3(x - 0.12, float(tip[1]) - 0.1, float(tip[0]) + 0.05), Vector3(x + 0.12, float(tip[1]) + 0.1, float(tip[0]) + 0.35),
			GREEN if side > 0.0 else RED)
	# Antennen
	for az: float in [-6.0, 4.0]:
		k.box(Vector3(-0.04, cy + r - 0.05, az), Vector3(0.04, cy + r + 0.35, az + 0.3), DARK_METAL)


# ================================================================== Menschen

const HAIR := [Color(0.15, 0.10, 0.07), Color(0.32, 0.21, 0.12), Color(0.72, 0.58, 0.32), Color(0.06, 0.06, 0.06),
	Color(0.62, 0.62, 0.62), Color(0.55, 0.25, 0.12), Color(0.85, 0.78, 0.6)]
const PANTS := [Color(0.16, 0.18, 0.24), Color(0.22, 0.30, 0.45), Color(0.28, 0.26, 0.22), Color(0.12, 0.12, 0.13),
	Color(0.55, 0.50, 0.40), Color(0.35, 0.38, 0.30)]
const JACKETS := [Color(0.2, 0.22, 0.28), Color(0.45, 0.32, 0.2), Color(0.15, 0.15, 0.16), Color(0.55, 0.15, 0.15),
	Color(0.2, 0.35, 0.3), Color(0.75, 0.72, 0.65)]
const SKIN_TONES := [Color(0.93, 0.78, 0.65), Color(0.82, 0.62, 0.47), Color(0.58, 0.40, 0.28), Color(0.38, 0.26, 0.18)]
const HIVIS := Color(0.95, 0.85, 0.1)

## Posen: 0 stehen, 1 bis 4 Gangzyklus, 5 sitzen.
const POSES := 6


static func random_look(shirt: Color, skin_i: int = -1) -> Dictionary:
	var skirt := randf() < 0.18
	return {
		"shirt": shirt, "pants": PANTS[randi() % PANTS.size()],
		"skin": SKIN_TONES[(skin_i if skin_i >= 0 else randi()) % SKIN_TONES.size()],
		"hair": HAIR[randi() % HAIR.size()], "style": randi() % 5 if randf() < 0.9 else 3,
		"jacket": JACKETS[randi() % JACKETS.size()] if randf() < 0.4 else null,
		"skirt": skirt, "shoes": [Color(0.1, 0.09, 0.08), Color(0.9, 0.9, 0.88), Color(0.35, 0.22, 0.12)][randi() % 3],
		"bag": randi() % 3 if randf() < 0.55 else 0, "vest": false,
	}


## Uniform für Personal: Hemd und Hose fest, ohne Tasche. vest = Warnweste (Vorfeld).
static func staff_look(shirt: Color, pants: Color, skin_i: int, vest: bool = false) -> Dictionary:
	return {"shirt": shirt, "pants": pants, "skin": SKIN_TONES[skin_i % SKIN_TONES.size()], "hair": HAIR[skin_i % HAIR.size()],
		"style": 4 if vest else skin_i % 3, "jacket": null, "skirt": false, "shoes": Color(0.08, 0.08, 0.08), "bag": 0, "vest": vest}


static func person_mesh(look: Dictionary, pose: int) -> ArrayMesh:
	var key := "p_%s_%d" % [str(look.values()), pose]
	if _cache.has(key):
		return _cache[key]
	var k := Kit.new()
	var shirt: Color = look["shirt"]
	var pants: Color = look["pants"]
	var skin: Color = look["skin"]
	var hair: Color = look["hair"]
	var shoes: Color = look["shoes"]
	var jacket: Variant = look["jacket"]
	var top: Color = jacket if jacket != null else shirt
	if bool(look["vest"]):
		top = HIVIS
	var sit := pose == 5
	var stride: float = [0.0, 0.17, 0.05, -0.17, -0.05, 0.0][pose]
	var lift: float = [0.0, 0.0, 0.05, 0.0, 0.05, 0.0][pose]
	var y0 := -0.4 if sit else 0.0   # Oberkörper beim Sitzen tiefer
	# Beine
	for side: float in [-1.0, 1.0]:
		var x0 := side * 0.025
		var x1 := side * 0.16
		if sit:
			k.box(Vector3(x0, 0.42, -0.42), Vector3(x1, 0.54, 0.05), pants)
			k.box(Vector3(x0, 0.08, -0.44), Vector3(x1, 0.48, -0.32), pants if not bool(look["skirt"]) else skin)
			k.box(Vector3(x0 - side * 0.005, 0.0, -0.56), Vector3(x1 + side * 0.005, 0.08, -0.3), shoes)
			continue
		var dz := stride * side
		var ly := lift if dz < 0.0 else 0.0
		k.box(Vector3(x0 - side * 0.005, ly, -0.15 + dz), Vector3(x1 + side * 0.005, 0.08 + ly, 0.08 + dz), shoes)
		var leg_col := skin if bool(look["skirt"]) else pants
		k.box(Vector3(x0, 0.08 + ly, -0.075 + dz * 0.85), Vector3(x1, 0.5, 0.065 + dz * 0.85), leg_col)
		k.box(Vector3(x0, 0.48, -0.08 + dz * 0.4), Vector3(x1, 0.9, 0.07 + dz * 0.4), leg_col)
	if bool(look["skirt"]):
		k.prism([Vector3(-0.24, 0.5 + y0 * 0.0, -0.15), Vector3(0.24, 0.5, -0.15), Vector3(0.24, 0.5, 0.15), Vector3(-0.24, 0.5, 0.15)],
			[Vector3(-0.18, 0.95 + y0, -0.11), Vector3(0.18, 0.95 + y0, -0.11), Vector3(0.18, 0.95 + y0, 0.11), Vector3(-0.18, 0.95 + y0, 0.11)],
			pants)
	else:
		k.box(Vector3(-0.175, 0.84 + y0, -0.1), Vector3(0.175, 0.92 + y0, 0.1), Color(0.12, 0.1, 0.08))
	# Oberkörper: unten Hüfte, oben breite Schultern
	k.prism([Vector3(-0.18, 0.9 + y0, -0.105), Vector3(0.18, 0.9 + y0, -0.105), Vector3(0.18, 0.9 + y0, 0.105), Vector3(-0.18, 0.9 + y0, 0.105)],
		[Vector3(-0.235, 1.42 + y0, -0.12), Vector3(0.235, 1.42 + y0, -0.12), Vector3(0.235, 1.42 + y0, 0.12), Vector3(-0.235, 1.42 + y0, 0.12)], top)
	if jacket != null and not bool(look["vest"]):
		k.panel(Vector3(0, 1.17 + y0, -0.118), Vector3(0.045, 0, 0), Vector3(0, 0.24, 0.0), shirt, Vector3(0, 0, -1))
	if bool(look["vest"]):
		for vy: float in [1.04, 1.24]:
			k.box(Vector3(-0.215, vy + y0, -0.125), Vector3(0.215, vy + 0.05 + y0, 0.125), Color(0.82, 0.84, 0.86))
	k.box(Vector3(-0.08, 1.4 + y0, -0.09), Vector3(0.08, 1.45 + y0, 0.07), shirt.lightened(0.1))
	# Arme schwingen gegengleich
	for side: float in [-1.0, 1.0]:
		var dz := -stride * side * 0.9
		if sit:
			dz = -0.18
		k.box(Vector3(side * 0.235, 1.12 + y0, -0.06 + dz * 0.4), Vector3(side * 0.32, 1.42 + y0, 0.06 + dz * 0.4), top.darkened(0.05))
		k.box(Vector3(side * 0.24, 0.92 + y0, -0.055 + dz), Vector3(side * 0.315, 1.14 + y0, 0.055 + dz), top.darkened(0.05))
		k.box(Vector3(side * 0.245, 0.84 + y0, -0.045 + dz), Vector3(side * 0.31, 0.93 + y0, 0.045 + dz), skin)
	# Kopf mit Augen und Nase
	k.box(Vector3(-0.055, 1.44 + y0, -0.05), Vector3(0.055, 1.5 + y0, 0.05), skin)
	k.box(Vector3(-0.1, 1.49 + y0, -0.11), Vector3(0.1, 1.73 + y0, 0.11), skin)
	for ex: float in [-0.045, 0.045]:
		k.box(Vector3(ex - 0.018, 1.61 + y0, -0.114), Vector3(ex + 0.018, 1.64 + y0, -0.108), Color(0.08, 0.07, 0.07))
	k.box(Vector3(-0.02, 1.56 + y0, -0.13), Vector3(0.02, 1.61 + y0, -0.105), skin.darkened(0.08))
	_hair(k, int(look["style"]), hair, y0, top)
	# Tasche
	match int(look["bag"]):
		1:
			k.box(Vector3(-0.17, 1.0 + y0, 0.12), Vector3(0.17, 1.38 + y0, 0.28), JACKETS[(int(str(hair.to_html()).hash()) & 0x7fffffff) % JACKETS.size()])
		2:
			k.box(Vector3(0.3, 0.85 + y0, -0.08), Vector3(0.38, 1.05 + y0, 0.12), Color(0.35, 0.2, 0.12))
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh


static func _hair(k: Kit, style: int, hair: Color, y0: float, cap_col: Color) -> void:
	match style:
		0:
			k.box(Vector3(-0.11, 1.68 + y0, -0.12), Vector3(0.11, 1.77 + y0, 0.12), hair)
			k.box(Vector3(-0.11, 1.56 + y0, 0.06), Vector3(0.11, 1.74 + y0, 0.125), hair)
		1:
			k.box(Vector3(-0.115, 1.68 + y0, -0.12), Vector3(0.115, 1.78 + y0, 0.125), hair)
			k.box(Vector3(-0.115, 1.38 + y0, 0.04), Vector3(0.115, 1.74 + y0, 0.14), hair)
			for side: float in [-1.0, 1.0]:
				k.box(Vector3(side * 0.1, 1.42 + y0, -0.06), Vector3(side * 0.12, 1.74 + y0, 0.12), hair)
		2:
			k.box(Vector3(-0.112, 1.68 + y0, -0.12), Vector3(0.112, 1.77 + y0, 0.125), hair)
			k.box(Vector3(-0.11, 1.55 + y0, 0.06), Vector3(0.11, 1.74 + y0, 0.13), hair)
			k.box(Vector3(-0.04, 1.42 + y0, 0.13), Vector3(0.04, 1.66 + y0, 0.2), hair)
		3:
			k.box(Vector3(-0.105, 1.55 + y0, 0.05), Vector3(0.105, 1.64 + y0, 0.115), hair)
		_:
			k.box(Vector3(-0.115, 1.7 + y0, -0.12), Vector3(0.115, 1.8 + y0, 0.12), cap_col.darkened(0.2))
			k.box(Vector3(-0.1, 1.7 + y0, -0.24), Vector3(0.1, 1.73 + y0, -0.11), cap_col.darkened(0.2))
			k.box(Vector3(-0.11, 1.56 + y0, 0.06), Vector3(0.11, 1.7 + y0, 0.12), hair)


# ================================================================== Autos

## Bauarten: kompakt, limousine, kombi, suv, transporter, taxi
const CAR_TYPES := ["kompakt", "limousine", "kombi", "suv", "transporter", "taxi"]
const CAR_DIMS := {
	"kompakt": [3.9, 1.75, 1.48, 1.0, 0.55], "limousine": [4.75, 1.82, 1.45, 1.35, 0.95], "kombi": [4.8, 1.82, 1.5, 1.3, 0.35],
	"suv": [4.6, 1.9, 1.72, 1.2, 0.5], "transporter": [5.3, 2.0, 2.35, 0.75, 0.15], "taxi": [4.75, 1.82, 1.45, 1.35, 0.95],
}


static func car_mesh(kind: String, color: Color) -> ArrayMesh:
	var key := "car_%s_%s" % [kind, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var d: Array = CAR_DIMS[kind]
	var L: float = d[0]
	var W: float = d[1]
	var H: float = d[2]
	var hood: float = d[3]
	var trunk: float = d[4]
	var k := Kit.new()
	var body := color
	if kind == "taxi":
		body = Color(0.94, 0.89, 0.68)
	var hl := L * 0.5
	var hw := W * 0.5
	var belt := 0.92 if kind != "transporter" else 1.05
	# Räder
	var wr := 0.33 if kind != "transporter" else 0.36
	for sx: float in [-1.0, 1.0]:
		for wz: float in [-hl + 0.8, hl - 0.75]:
			k.cyl(Vector3(sx * (hw - 0.26), wr, wz), Vector3(sx * (hw + 0.01), wr, wz), wr, wr, TYRE, 12, true, METAL)
	# Unterbau und Karosserie bis zur Gürtellinie
	k.box(Vector3(-hw + 0.04, 0.22, -hl), Vector3(hw - 0.04, 0.42, hl), Color(0.12, 0.12, 0.13))
	k.box(Vector3(-hw, 0.36, -hl + 0.05), Vector3(hw, belt, hl - 0.05), body)
	k.box(Vector3(-hw + 0.05, 0.4, -hl - 0.02), Vector3(hw - 0.05, 0.55, hl + 0.02), Color(0.16, 0.16, 0.17))
	# Lichter
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * (hw - 0.42), belt - 0.22, -hl - 0.03), Vector3(sx * (hw - 0.1), belt - 0.08, -hl + 0.02), Color(0.98, 0.95, 0.8))
		k.box(Vector3(sx * (hw - 0.4), belt - 0.24, hl - 0.02), Vector3(sx * (hw - 0.08), belt - 0.08, hl + 0.03), Color(0.75, 0.08, 0.06))
		k.box(Vector3(sx * (hw + 0.0), belt + 0.05, -hl + hood + 0.05), Vector3(sx * (hw + 0.12), belt + 0.14, -hl + hood + 0.22), body.darkened(0.2))
	# Kabine mit schrägen Scheiben
	var zf := -hl + hood
	var zb := hl - trunk
	var inset := 0.12
	var bottom := [Vector3(-hw + 0.06, belt, zf), Vector3(hw - 0.06, belt, zf), Vector3(hw - 0.06, belt, zb), Vector3(-hw + 0.06, belt, zb)]
	var slope_f := 0.75 if kind != "transporter" else 0.35
	var slope_b := 0.45 if kind in ["limousine", "taxi", "kompakt"] else 0.12
	var top := [Vector3(-hw + inset + 0.06, H - 0.06, zf + slope_f), Vector3(hw - inset - 0.06, H - 0.06, zf + slope_f),
		Vector3(hw - inset - 0.06, H - 0.06, zb - slope_b), Vector3(-hw + inset + 0.06, H - 0.06, zb - slope_b)]
	k.prism(bottom, top, GLASS)
	k.box(Vector3(-hw + inset + 0.04, H - 0.07, zf + slope_f - 0.05), Vector3(hw - inset - 0.04, H, zb - slope_b + 0.05), body)
	# Säulen in Wagenfarbe
	var mid := (zf + zb) * 0.5 + 0.1
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * (hw - 0.07) - 0.04, belt, mid - 0.07), Vector3(sx * (hw - 0.07 - inset) + 0.04, H - 0.06, mid + 0.07), body)
	if kind == "transporter":
		k.box(Vector3(-hw, belt - 0.02, zf + 1.2), Vector3(hw, H - 0.06, zb), body)
		k.box(Vector3(-hw - 0.01, belt + 0.25, zf + 0.7), Vector3(hw + 0.01, H - 0.3, zf + 1.15), GLASS)
	if kind == "taxi":
		k.box(Vector3(-0.35, H, -0.12), Vector3(0.35, H + 0.18, 0.12), Color(0.98, 0.92, 0.5))
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh


# ================================================================== Bodenfahrzeuge (GSE)

static func gse_mesh(kind: String) -> ArrayMesh:
	var key := "gse_" + kind
	if _cache.has(key):
		return _cache[key]
	var k := Kit.new()
	var cab := YELLOW
	match kind:
		"tank":
			_truck_cab(k, cab, -4.7, 2.3)
			k.box(Vector3(-1.1, 0.55, -2.4), Vector3(1.1, 0.85, 4.6), DARK_METAL)
			k.cyl(Vector3(0, 1.85, -2.2), Vector3(0, 1.85, 4.3), 1.1, 1.1, Color(0.9, 0.9, 0.88), 16, true, Color(0.8, 0.8, 0.78))
			k.box(Vector3(-1.15, 1.6, -2.2), Vector3(1.15, 1.8, 4.3), Color(0.2, 0.45, 0.25))
			k.box(Vector3(-0.5, 2.9, 0.2), Vector3(0.5, 3.05, 2.5), DARK_METAL)
			k.cyl(Vector3(-0.6, 1.0, 4.4), Vector3(0.6, 1.0, 4.4), 0.42, 0.42, DARK_METAL, 10)
			for i in range(5):
				k.box(Vector3(0.9, 0.9 + float(i) * 0.4, 4.35), Vector3(1.0, 0.95 + float(i) * 0.4, 4.6), METAL)
			_wheels(k, 1.2, 0.48, [-3.6, 1.6, 3.2])
		"catering":
			_truck_cab(k, cab, -3.9, 2.2)
			k.box(Vector3(-1.1, 0.55, -1.7), Vector3(1.1, 0.8, 3.6), DARK_METAL)
			# Scherenhub: gekreuzte Streben unter dem Kasten
			for sx: float in [-0.95, 0.95]:
				for ang: float in [0.36, -0.36]:
					k.box(Vector3(-0.05, -0.06, -2.6), Vector3(0.05, 0.06, 2.6), METAL, Transform3D(Basis(Vector3(1, 0, 0), ang), Vector3(sx, 1.85, 0.95)))
			k.box(Vector3(-1.25, 2.9, -1.8), Vector3(1.25, 5.3, 3.7), Color(0.92, 0.92, 0.9))
			k.box(Vector3(-1.27, 3.9, -1.8), Vector3(1.27, 4.2, 3.7), Color(0.2, 0.4, 0.65))
			k.box(Vector3(-1.0, 2.9, -2.6), Vector3(1.0, 3.0, -1.8), METAL)
			_wheels(k, 1.15, 0.45, [-3.0, 2.6])
		"schlepper":
			_tug(k)
		"bus":
			_apron_bus(k)
		_:
			# Gepäckschlepper mit zwei Wagen
			k.box(Vector3(-0.75, 0.3, -1.5), Vector3(0.75, 0.9, 0.5), cab)
			k.box(Vector3(-0.7, 0.9, -0.4), Vector3(0.7, 1.0, 0.45), cab.darkened(0.1))
			for p: Vector3 in [Vector3(-0.68, 0, -0.4), Vector3(0.6, 0, -0.4), Vector3(-0.68, 0, 0.37), Vector3(0.6, 0, 0.37)]:
				k.box(p + Vector3(0, 0.9, 0), p + Vector3(0.08, 1.9, 0.08), DARK_METAL)
			k.box(Vector3(-0.75, 1.9, -0.45), Vector3(0.75, 1.98, 0.5), DARK_METAL)
			k.box(Vector3(-0.3, 0.9, -0.2), Vector3(0.3, 1.25, 0.25), Color(0.15, 0.15, 0.16))
			_wheels(k, 0.72, 0.32, [-1.1, 0.2])
			var cases := [Color(0.7, 0.2, 0.18), Color(0.2, 0.32, 0.55), Color(0.15, 0.15, 0.16), Color(0.55, 0.45, 0.3), Color(0.3, 0.5, 0.35)]
			for c in range(2):
				var z0 := 1.2 + float(c) * 3.2
				k.box(Vector3(-0.05, 0.35, z0 - 0.5), Vector3(0.05, 0.42, z0 + 0.1), DARK_METAL)
				k.box(Vector3(-0.85, 0.4, z0 + 0.1), Vector3(0.85, 0.55, z0 + 2.7), DARK_METAL)
				for i in range(6):
					var cx := -0.55 + float(i % 2) * 1.1
					var cz := z0 + 0.5 + float(i / 2) * 0.8
					k.box(Vector3(cx - 0.3, 0.55, cz - 0.3), Vector3(cx + 0.3, 1.0 + 0.1 * float(i % 3), cz + 0.3), cases[(i + c) % cases.size()])
				for p: Vector3 in [Vector3(-0.85, 0, z0 + 0.1), Vector3(0.78, 0, z0 + 0.1), Vector3(-0.85, 0, z0 + 2.62), Vector3(0.78, 0, z0 + 2.62)]:
					k.box(p + Vector3(0, 0.55, 0), p + Vector3(0.07, 1.6, 0.07), DARK_METAL)
				k.box(Vector3(-0.88, 1.6, z0 + 0.08), Vector3(0.88, 1.68, z0 + 2.72), Color(0.3, 0.42, 0.32))
				_wheels(k, 0.85, 0.22, [z0 + 0.5, z0 + 2.3])
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh


static func _truck_cab(k: Kit, col: Color, z0: float, h: float) -> void:
	k.box(Vector3(-1.15, 0.5, z0), Vector3(1.15, h + 0.4, z0 + 2.0), col)
	k.box(Vector3(-1.1, h - 0.6, z0 - 0.02), Vector3(1.1, h + 0.25, z0 + 0.1), GLASS)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 1.16 - 0.01, h - 0.55, z0 + 0.2), Vector3(sx * 1.16 + 0.01, h + 0.2, z0 + 1.2), GLASS)
		k.box(Vector3(sx * 0.8 - 0.15, 0.8, z0 - 0.03), Vector3(sx * 0.8 + 0.15, 0.95, z0), Color(0.98, 0.95, 0.8))
	k.box(Vector3(-0.3, h + 0.4, z0 + 0.8), Vector3(0.3, h + 0.55, z0 + 1.1), Color(0.95, 0.55, 0.1))


static func _wheels(k: Kit, half_track: float, r: float, zs: Array) -> void:
	for z: float in zs:
		for sx: float in [-1.0, 1.0]:
			k.cyl(Vector3(sx * (half_track - 0.3), r, z), Vector3(sx * half_track, r, z), r, r, TYRE, 10, true, METAL)


## Stangenloser Pushback-Schlepper (Front -Z): flacher Körper, vorn eine U-Gabel für das Bugrad,
## Kabine seitlich, Rundumleuchte. Das Bugrad sitzt bei z = -2.8.
static func _tug(k: Kit) -> void:
	var body := Color(0.92, 0.78, 0.16)
	var dark := Color(0.16, 0.16, 0.17)
	# Rahmen hinten und zwei Gabelarme vorn
	k.box(Vector3(-1.8, 0.35, -0.9), Vector3(1.8, 1.35, 3.9), body)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 1.8, 0.35, -4.2), Vector3(sx * 0.75, 1.15, -0.9), body)
		k.box(Vector3(sx * 1.82, 0.9, -4.2), Vector3(sx * 0.73, 1.0, -0.9), dark)
		# Warnstreifen schwarz-gelb an den Gabelenden
		for i in range(3):
			var z0 := -4.2 + float(i) * 0.5
			k.box(Vector3(sx * 1.83, 0.45, z0), Vector3(sx * 1.6, 0.85, z0 + 0.25), dark)
	# Gabel: Rampe und Klemmbacken
	k.box(Vector3(-0.75, 0.2, -3.2), Vector3(0.75, 0.32, -0.9), DARK_METAL)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.75, 0.32, -3.3), Vector3(sx * 0.55, 0.95, -2.4), METAL)
	k.box(Vector3(-0.75, 0.32, -1.1), Vector3(0.75, 1.1, -0.9), METAL)
	# Kabine rechts hinten, verglast
	k.box(Vector3(0.4, 1.35, 1.0), Vector3(1.75, 1.45, 3.6), dark)
	k.box(Vector3(0.45, 1.45, 1.1), Vector3(1.7, 2.55, 3.5), GLASS)
	for p: Vector3 in [Vector3(0.45, 1.45, 1.1), Vector3(1.6, 1.45, 1.1), Vector3(0.45, 1.45, 3.4), Vector3(1.6, 1.45, 3.4)]:
		k.box(p, p + Vector3(0.1, 1.15, 0.1), body.darkened(0.15))
	k.box(Vector3(0.35, 2.55, 1.0), Vector3(1.8, 2.7, 3.6), body)
	k.cyl(Vector3(1.1, 2.7, 2.3), Vector3(1.1, 2.9, 2.3), 0.14, 0.12, Color(0.98, 0.55, 0.08), 8)
	# Motorhaube mit Gitter, Rücklichter
	k.box(Vector3(-1.6, 1.35, 1.2), Vector3(0.2, 1.6, 3.8), body.darkened(0.08))
	for i in range(5):
		k.box(Vector3(-1.5, 1.6, 1.5 + float(i) * 0.45), Vector3(0.1, 1.63, 1.7 + float(i) * 0.45), dark)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 1.5 - 0.2, 0.9, 3.9), Vector3(sx * 1.5 + 0.2, 1.15, 3.95), Color(0.8, 0.1, 0.08))
		k.box(Vector3(sx * 1.5 - 0.2, 0.9, -4.25), Vector3(sx * 1.5 + 0.2, 1.1, -4.2), Color(0.98, 0.95, 0.8))
	_wheels(k, 1.95, 0.55, [-3.3, 2.8])


## Vorfeldbus (Front -Z): 14 m lang, 3 m breit, Niederflur, rundum verglast, je drei Türen links und rechts.
static func _apron_bus(k: Kit) -> void:
	var body := Color(0.93, 0.93, 0.9)
	var stripe := Color(0.18, 0.36, 0.62)
	k.box(Vector3(-1.5, 0.3, -7.0), Vector3(1.5, 0.55, 7.0), Color(0.15, 0.15, 0.16))
	k.box(Vector3(-1.5, 0.55, -7.0), Vector3(1.5, 1.05, 7.0), body)
	k.box(Vector3(-1.51, 0.75, -7.0), Vector3(1.51, 0.92, 7.0), stripe)
	k.box(Vector3(-1.48, 1.05, -6.9), Vector3(1.48, 2.55, 6.9), GLASS)
	# Fensterholme
	for z in range(-6, 7, 2):
		for sx: float in [-1.0, 1.0]:
			k.box(Vector3(sx * 1.5 - 0.04, 1.05, float(z) - 0.06), Vector3(sx * 1.5 + 0.04, 2.55, float(z) + 0.06), body)
	k.box(Vector3(-1.5, 2.55, -7.0), Vector3(1.5, 2.95, 7.0), body)
	k.box(Vector3(-1.2, 2.95, -4.0), Vector3(1.2, 3.15, 2.0), Color(0.75, 0.76, 0.77))
	# Türen: dunkle Rahmen mit Glas, links und rechts
	for sx: float in [-1.0, 1.0]:
		for z: float in [-4.6, 0.0, 4.6]:
			k.box(Vector3(sx * 1.5 - 0.03, 0.4, z - 1.0), Vector3(sx * 1.5 + 0.03, 2.6, z + 1.0), Color(0.22, 0.23, 0.25))
			k.box(Vector3(sx * 1.5 - 0.05, 0.55, z - 0.9), Vector3(sx * 1.5 + 0.05, 2.5, z + 0.9), GLASS)
			k.box(Vector3(sx * 1.5 - 0.06, 0.55, z - 0.03), Vector3(sx * 1.5 + 0.06, 2.5, z + 0.03), Color(0.22, 0.23, 0.25))
	# Front und Heck: große Scheibe, Lichter, Zielanzeige
	k.box(Vector3(-1.45, 1.0, -7.03), Vector3(1.45, 2.5, -6.98), GLASS)
	k.box(Vector3(-1.2, 2.6, -7.04), Vector3(1.2, 2.85, -6.98), Color(0.05, 0.05, 0.05))
	k.box(Vector3(-0.9, 2.66, -7.06), Vector3(0.9, 2.79, -7.03), Color(0.98, 0.65, 0.15))
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 1.15 - 0.2, 0.65, -7.04), Vector3(sx * 1.15 + 0.2, 0.85, -7.0), Color(0.98, 0.95, 0.8))
		k.box(Vector3(sx * 1.15 - 0.2, 0.65, 7.0), Vector3(sx * 1.15 + 0.2, 0.85, 7.04), Color(0.75, 0.08, 0.06))
	k.cyl(Vector3(0, 3.15, -1.0), Vector3(0, 3.35, -1.0), 0.13, 0.11, Color(0.98, 0.55, 0.08), 8)
	_wheels(k, 1.5, 0.48, [-4.8, 4.8])


## Treppenwagen (Front -Z) mit Plattform vorn auf Höhe h (Türschwelle), Treppe fällt nach hinten ab.
static func stairs_mesh(h: float) -> ArrayMesh:
	var key := "treppe_%.2f" % h
	if _cache.has(key):
		return _cache[key]
	var k := Kit.new()
	var body := Color(0.92, 0.92, 0.9)
	var rail := Color(0.85, 0.7, 0.15)
	# Fahrgestell mit Kabine hinten links
	k.box(Vector3(-1.1, 0.35, -3.6), Vector3(1.1, 0.75, 3.8), DARK_METAL)
	k.box(Vector3(-1.15, 0.75, 1.8), Vector3(-0.05, 2.3, 3.9), YELLOW)
	k.box(Vector3(-1.1, 1.5, 1.75), Vector3(-0.1, 2.2, 1.8), GLASS)
	k.box(Vector3(-1.16, 1.5, 2.0), Vector3(-1.14, 2.2, 3.5), GLASS)
	k.cyl(Vector3(-0.6, 2.3, 2.8), Vector3(-0.6, 2.45, 2.8), 0.12, 0.1, Color(0.98, 0.55, 0.08), 8)
	# Plattform vorn mit Dach
	var top := maxf(h, 1.2)
	k.box(Vector3(-0.85, top - 0.15, -4.4), Vector3(0.85, top, -2.6), DARK_METAL)
	for p: Vector3 in [Vector3(-0.85, 0, -4.4), Vector3(0.75, 0, -4.4), Vector3(-0.85, 0, -2.7), Vector3(0.75, 0, -2.7)]:
		k.box(p + Vector3(0, 0.75, 0), p + Vector3(0.1, top - 0.15, 0.1), METAL)
	k.box(Vector3(-0.95, top + 2.0, -4.5), Vector3(0.95, top + 2.1, -2.4), body)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.9 - 0.04, top, -4.4), Vector3(sx * 0.9 + 0.04, top + 2.0, -4.3), METAL)
		k.box(Vector3(sx * 0.9 - 0.08, top, -4.3), Vector3(sx * 0.9 + 0.08, top + 2.0, -2.5), Color(0.75, 0.82, 0.86))
	# Stufen von der Plattform nach hinten hinunter
	var n := maxi(4, int(top / 0.2))
	var run := 4.2
	for i in range(n):
		var t := float(i) / float(n)
		var y := top - (float(i) + 1.0) * top / float(n)
		var z := -2.6 + t * run
		k.box(Vector3(-0.8, y + 0.0, z), Vector3(0.8, y + 0.12, z + run / float(n) + 0.02), Color(0.55, 0.56, 0.58))
	# Wangen und Handläufe
	for sx: float in [-1.0, 1.0]:
		var a := Vector3(sx * 0.85, top, -2.6)
		var b := Vector3(sx * 0.85, 0.75, -2.6 + run)
		var d := b - a
		var bas := Basis.looking_at(d.normalized(), Vector3.UP)
		k.box(Vector3(-0.05, -0.25, -d.length() * 0.5), Vector3(0.05, 0.05, d.length() * 0.5), body, Transform3D(bas, (a + b) * 0.5))
		k.box(Vector3(-0.04, -0.04, -d.length() * 0.5), Vector3(0.04, 0.04, d.length() * 0.5), rail, Transform3D(bas, (a + b) * 0.5 + Vector3(0, 1.0, 0)))
		for t: float in [0.15, 0.5, 0.85]:
			var q := a.lerp(b, t)
			k.box(q + Vector3(-0.03, 0, -0.03), q + Vector3(0.03, 1.0, 0.03), rail)
	_wheels(k, 1.15, 0.42, [-2.8, 2.9])
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh
