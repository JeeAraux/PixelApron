extends RefCounted
## Detaillierte Modelle aus dem Mesh-Baukasten: Flugzeuge (A320, B737-800), Menschen mit Laufposen,
## Autos verschiedener Bauart und Bodenfahrzeuge. Jedes Modell wird einmal gebaut und zwischengespeichert.
## Vorne ist immer -Z, oben +Y, Boden y = 0. Maße in Metern nach den echten Vorbildern.

const Kit = preload("res://scripts/mesh_kit.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")

const WHITE := Color(0.93, 0.93, 0.91)
const BELLY := Color(0.79, 0.80, 0.81)
const WING := Color(0.74, 0.75, 0.76)
const WING_DARK := Color(0.58, 0.59, 0.61)
const GLASS := Color(0.09, 0.12, 0.16, 0.6)
const WIN := Color(0.15, 0.18, 0.23, 0.6)
const LAMP := Color(0.98, 0.95, 0.8, 0.3)
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
		"len": 37.6, "r": 1.98, "cy": 3.35, "nose_len": 5.6, "nose_tip": 0.26,
		"tail_start": 6.4, "tail_r": 0.40, "tail_drop": 0.35,
		"wing_z": -4.6, "wing_c": 6.4, "kink_c": 3.9, "tip_x": 16.9, "tip_c": 1.6, "sweep": 27.0, "dihedral": 5.0, "wing_y": 2.05,
		"winglet": [2.3, 0.25, 1.2, 0.55],
		"eng_x": 5.75, "eng_y": 1.62, "eng_r": 1.08, "eng_flat": 1.0, "eng_z": -7.5, "eng_len": 4.3,
		"stab_z": 14.4, "stab_c": 3.6, "stab_span": 6.3, "stab_y": 4.5, "stab_sweep": 32.0,
		"fin_z": 11.0, "fin_c": 6.4, "fin_h": 6.4, "fin_sweep": 35.0, "fin_tip_c": 2.3, "dorsal": false,
		"nose_gear_z": -13.9, "main_gear_z": 1.3, "main_gear_x": 3.8, "main_wheel_r": 0.58, "nose_wheel_r": 0.36,
		"doors": [-15.2, 12.7], "exits": [-1.5, -0.6], "win_from": -13.6, "win_to": 11.3, "win_dy": 0.52,
	},
	"a321": {
		"len": 44.5, "r": 1.98, "cy": 3.35, "nose_len": 5.6, "nose_tip": 0.26,
		"tail_start": 9.85, "tail_r": 0.40, "tail_drop": 0.35,
		"wing_z": -5.25, "wing_c": 6.6, "kink_c": 4.0, "tip_x": 17.0, "tip_c": 1.6, "sweep": 27.0, "dihedral": 5.0, "wing_y": 2.05,
		"winglet": [2.4, 0.25, 1.2, 0.55],
		"eng_x": 5.75, "eng_y": 1.62, "eng_r": 1.1, "eng_flat": 1.0, "eng_z": -8.1, "eng_len": 4.4,
		"stab_z": 17.85, "stab_c": 3.6, "stab_span": 6.3, "stab_y": 4.5, "stab_sweep": 32.0,
		"fin_z": 14.45, "fin_c": 6.4, "fin_h": 6.4, "fin_sweep": 35.0, "fin_tip_c": 2.3, "dorsal": false,
		"nose_gear_z": -17.3, "main_gear_z": 0.7, "main_gear_x": 3.8, "main_wheel_r": 0.6, "nose_wheel_r": 0.36,
		"doors": [-18.6, 16.1], "exits": [-7.0, -0.6, 8.6], "win_from": -17.0, "win_to": 14.8, "win_dy": 0.52,
	},
	"b737": {
		"len": 39.5, "r": 1.88, "cy": 3.0, "nose_len": 6.6, "nose_tip": 0.36,
		"tail_start": 8.4, "tail_r": 0.20, "tail_drop": 0.55,
		"wing_z": -4.3, "wing_c": 7.2, "kink_c": 4.2, "tip_x": 17.0, "tip_c": 1.5, "sweep": 25.0, "dihedral": 6.0, "wing_y": 1.75,
		"winglet": [2.5, 0.6, 1.5, 0.45],
		"eng_x": 4.95, "eng_y": 1.50, "eng_r": 1.02, "eng_flat": 0.84, "eng_z": -8.3, "eng_len": 3.9,
		"stab_z": 15.2, "stab_c": 3.9, "stab_span": 7.0, "stab_y": 4.0, "stab_sweep": 30.0,
		"fin_z": 12.2, "fin_c": 6.6, "fin_h": 7.4, "fin_sweep": 35.0, "fin_tip_c": 2.0, "dorsal": true,
		"nose_gear_z": -15.6, "main_gear_z": 1.8, "main_gear_x": 2.86, "main_wheel_r": 0.56, "nose_wheel_r": 0.34,
		"doors": [-16.2, 14.6], "exits": [-0.3, 0.6], "win_from": -14.6, "win_to": 13.2, "win_dy": 0.48,
	},
	"e190": {
		"len": 36.2, "r": 1.5, "cy": 2.75, "nose_len": 4.8, "nose_tip": 0.3,
		"tail_start": 7.0, "tail_r": 0.30, "tail_drop": 0.3,
		"wing_z": -3.6, "wing_c": 5.4, "kink_c": 3.2, "tip_x": 14.3, "tip_c": 1.2, "sweep": 25.0, "dihedral": 5.0, "wing_y": 1.5,
		"winglet": [1.6, 0.2, 0.9, 0.45],
		"eng_x": 4.9, "eng_y": 1.12, "eng_r": 0.84, "eng_flat": 1.0, "eng_z": -6.3, "eng_len": 3.6,
		"stab_z": 14.3, "stab_c": 2.8, "stab_span": 5.0, "stab_y": 3.6, "stab_sweep": 30.0,
		"fin_z": 10.6, "fin_c": 5.4, "fin_h": 5.8, "fin_sweep": 38.0, "fin_tip_c": 2.0, "dorsal": true,
		"nose_gear_z": -13.6, "main_gear_z": 1.2, "main_gear_x": 2.9, "main_wheel_r": 0.5, "nose_wheel_r": 0.3,
		"doors": [-14.9, 13.2], "exits": [-1.0], "win_from": -13.3, "win_to": 11.8, "win_dy": 0.38,
	},
	"atr72": {
		"len": 27.2, "r": 1.4, "cy": 2.35, "nose_len": 3.9, "nose_tip": 0.32,
		"tail_start": 4.8, "tail_r": 0.26, "tail_drop": 0.55,
		"high": true, "root_f": 0.22,
		"wing_z": -1.9, "wing_c": 2.6, "kink_c": 2.35, "tip_x": 13.5, "tip_c": 1.3, "sweep": 2.0, "dihedral": -1.0, "wing_y": 3.68,
		"winglet": [0.0, 0.0, 0.0, 0.0],
		"props": true, "prop_r": 1.95,
		"eng_x": 4.1, "eng_y": 3.05, "eng_r": 0.62, "eng_flat": 1.35, "eng_z": -4.4, "eng_len": 6.2,
		"stab_z": 11.4, "stab_c": 2.0, "stab_span": 3.9, "stab_y": 8.3, "stab_sweep": 8.0,
		"fin_z": 8.4, "fin_c": 4.4, "fin_h": 5.2, "fin_sweep": 30.0, "fin_tip_c": 2.0, "dorsal": true,
		"nose_gear_z": -10.6, "main_gear_z": 0.6, "main_gear_x": 2.05, "main_wheel_r": 0.45, "nose_wheel_r": 0.3,
		"doors": [-10.4, 10.0], "exits": [], "win_from": -9.0, "win_to": 8.6, "win_dy": 0.3,
	},
	"a330": {
		"len": 63.7, "r": 2.82, "cy": 4.5, "nose_len": 7.4, "nose_tip": 0.28,
		"tail_start": 15.0, "tail_r": 0.5, "tail_drop": 0.6,
		"wing_z": -6.0, "wing_c": 10.5, "kink_c": 6.4, "tip_x": 30.0, "tip_c": 2.1, "sweep": 30.0, "dihedral": 5.5, "wing_y": 2.75,
		"winglet": [3.0, 0.3, 1.6, 0.8],
		"eng_x": 9.6, "eng_y": 2.35, "eng_r": 1.55, "eng_flat": 1.0, "eng_z": -11.5, "eng_len": 6.0,
		"stab_z": 25.5, "stab_c": 5.5, "stab_span": 9.8, "stab_y": 6.3, "stab_sweep": 32.0,
		"fin_z": 20.0, "fin_c": 9.0, "fin_h": 9.2, "fin_sweep": 42.0, "fin_tip_c": 3.0, "dorsal": false,
		"nose_gear_z": -25.0, "main_gear_z": 1.5, "main_gear_x": 5.3, "bogie": 2, "main_wheel_r": 0.66, "nose_wheel_r": 0.5,
		"doors": [-27.0, 22.0], "exits": [-12.0, 2.0], "win_from": -26.0, "win_to": 21.0, "win_dy": 0.75,
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
	if bool(s.get("props", false)):
		# Sechsblatt-Propeller mit Spinner (dreht um z)
		var pr: float = s["prop_r"]
		k.cyl(Vector3(0, 0, -0.9), Vector3(0, 0, 0.1), 0.02, 0.42, WHITE, 16)
		for i in range(6):
			var a := TAU * float(i) / 6.0
			var dir := Vector3(cos(a), sin(a), 0)
			var tng := Vector3(-sin(a), cos(a), 0)
			k.quad(dir * 0.35 - tng * 0.13, dir * pr - tng * 0.09 + Vector3(0, 0, 0.04), dir * pr + tng * 0.09 - Vector3(0, 0, 0.04), dir * 0.35 + tng * 0.13,
				Color(0.16, 0.17, 0.19), Vector3(0, 0, 1))
			k.quad(dir * (pr - 0.25) - tng * 0.09, dir * pr - tng * 0.09, dir * pr + tng * 0.09, dir * (pr - 0.25) + tng * 0.09,
				Color(0.9, 0.75, 0.15), Vector3(0, 0, 1))
		var pm := k.commit()
		_cache[key] = pm
		return pm
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


## Schriftzug der Airline über den vorderen Fenstern (Name aus der Hausfarbe abgeleitet).
const BRANDS := ["WIESENAIR", "AEROLUNA", "ALPENFLUG", "BALTIKO", "SKYVIA", "NORDLUFT", "HANSALUX", "SONNJET"]


static func _wordmark(k: Kit, s: Dictionary, livery: Color) -> void:
	var brand: String = BRANDS[absi(livery.to_html().hash()) % BRANDS.size()]
	var length: float = s["len"]
	var z0 := -length * 0.5
	var px: float = clampf(float(s["r"]) * 0.062, 0.07, 0.16)
	var total := float(PixelFont.width(brand)) * px
	var zc := z0 + float(s["nose_len"]) + 1.6 + total * 0.5
	var y := float(s["cy"]) + float(s["win_dy"]) + px * 6.0
	var a := _skin_angle(s, zc, y)
	for side: float in [-1.0, 1.0]:
		var sk := _skin(s, zc, a, side)
		var n: Vector3 = sk[1]
		var up := (Vector3.UP - n * n.dot(Vector3.UP)).normalized()
		PixelFont.draw(k, brand, (sk[0] as Vector3) + n * 0.03, Vector3(0, 0, -side), up, n, px, livery.darkened(0.2))


## Querschnitt des Rumpfs an der Stelle z: [Höhe der größten Breite, halbe Breite, Oberkante, Unterkante].
## Nase nach dem Vorbild: Radomspitze unter der Mittellinie, Oberseite steigt über die Frontscheibe
## zum Scheitel, Unterseite läuft flach zum Bauch; Heck mit hochgezogenem Unterteil zum APU-Auslass.
static func _section(s: Dictionary, z: float) -> Array:
	var length: float = s["len"]
	var r: float = s["r"]
	var cy: float = s["cy"]
	var z0 := -length * 0.5
	var z1 := length * 0.5
	var nose_len: float = s["nose_len"]
	var ts: float = s["tail_start"]
	var top_r := r * 1.03
	var bot_r := r * 1.05
	if z < z0 + nose_len:
		var t := clampf((z - z0) / nose_len, 0.0, 1.0)
		var tip_y := cy - r * float(s.get("nose_tip", 0.28))
		var ft := 1.0 - pow(1.0 - t, 2.4)
		var top := tip_y + (cy + top_r - tip_y) * pow(ft, 0.78)
		var bot := tip_y - (tip_y - (cy - bot_r)) * pow(1.0 - pow(1.0 - t, 3.0), 0.55)
		var hw := r * pow(1.0 - pow(1.0 - t, 2.2), 0.55)
		var yw := lerpf(tip_y, cy, pow(t, 0.7))
		return [yw, maxf(hw, 0.02), maxf(top, yw + 0.02), minf(bot, yw - 0.02)]
	if z > ts:
		var t := clampf((z - ts) / (z1 - ts), 0.0, 1.0)
		var tr: float = s["tail_r"]
		var end_y := cy + r * 0.42 - float(s["tail_drop"]) * 0.3
		var hw := lerpf(r, tr, pow(t, 1.25))
		var top := lerpf(cy + top_r, end_y + tr, pow(t, 1.9))
		var bot := lerpf(cy - bot_r, end_y - tr, pow(smoothstep(0.0, 1.0, t), 0.85))
		var yw := lerpf(cy, end_y, pow(t, 1.4))
		yw = clampf(yw, bot + 0.02, top - 0.02)
		return [yw, maxf(hw, 0.02), top, bot]
	return [cy, r, cy + top_r, cy - bot_r]


## Alte Form für Helfer: [Mitte y, Radius quer, Radius hoch]
static func _profile(s: Dictionary, z: float) -> Array:
	var q := _section(s, z)
	return [(float(q[2]) + float(q[3])) * 0.5, q[1], (float(q[2]) - float(q[3])) * 0.5]


## Punkt und Normale auf der Rumpfhaut: Seite side, Winkel a von oben (0) über die Seite (PI/2) nach unten (PI).
static func _skin(s: Dictionary, z: float, a: float, side: float = 1.0) -> Array:
	var q := _section(s, z)
	var yw: float = q[0]
	var hw: float = q[1]
	var ry := (float(q[2]) - yw) if cos(a) >= 0.0 else (yw - float(q[3]))
	var p := Vector3(side * hw * sin(a), yw + ry * cos(a), z)
	var n := Vector3(side * sin(a) / maxf(hw, 0.01), cos(a) / maxf(ry, 0.01), 0.0).normalized()
	return [p, n]


## Winkel auf der Haut, unter dem die Höhe y erreicht wird (für Fenster, Türen, Streifen).
static func _skin_angle(s: Dictionary, z: float, y: float) -> float:
	var q := _section(s, z)
	var yw: float = q[0]
	if y >= yw:
		return acos(clampf((y - yw) / maxf(float(q[2]) - yw, 0.01), -1.0, 1.0))
	return acos(clampf((y - yw) / maxf(yw - float(q[3]), 0.01), -1.0, 1.0))


static func _fuselage(k: Kit, s: Dictionary, livery: Color) -> void:
	var length: float = s["len"]
	var z0 := -length * 0.5
	var z1 := length * 0.5
	var nose_len: float = s["nose_len"]
	var ts: float = s["tail_start"]
	var cy: float = s["cy"]
	var r: float = s["r"]
	var zs := []
	for i in range(1, 34):
		zs.append(z0 + nose_len * pow(float(i) / 33.0, 1.7))
	var z := z0 + nose_len + 0.9
	while z < ts - 0.3:
		zs.append(z)
		z += 0.9
	for i in range(0, 28):
		zs.append(lerpf(ts, z1, float(i) / 27.0))
	var n := 56
	var rings := []
	var tip := _section(s, z0)
	var tip_ring := PackedVector3Array()
	for j in range(n):
		tip_ring.append(Vector3(0, float(tip[0]), z0))
	rings.append(tip_ring)
	for zz: float in zs:
		var ring := PackedVector3Array()
		for j in range(n):
			var a := TAU * float(j) / float(n)
			var sd := 1.0 if a <= PI else -1.0
			var aa := a if a <= PI else TAU - a
			ring.append(_skin(s, zz, aa, sd)[0])
		rings.append(ring)
	var col_fn := func(m: Vector3, i: int, _j: int) -> Color:
		if m.z > z1 - 0.25:
			return DARK_METAL   # APU-Auslass
		var q := _section(s, m.z)
		var t := (m.z - z0) / nose_len
		if t < 0.24:
			return Color(0.86, 0.86, 0.85)   # Radom etwas grauer
		if m.y < float(q[0]) - (float(q[0]) - float(q[3])) * 0.42:
			return BELLY
		return WHITE
	k.loft(rings, col_fn, true, false, true)
	# Cockpitscheiben: vorn zwei, seitlich je zwei, schwarz gerahmt, der Wölbung folgend
	var panes := [[0.6, 0.71, 0.05, 0.5], [0.72, 0.8, 0.62, 0.98], [0.81, 0.87, 0.66, 0.98]]
	for side: float in [-1.0, 1.0]:
		for pn: Array in panes:
			var za := z0 + nose_len * float(pn[0])
			var zb := z0 + nose_len * float(pn[1])
			_skin_patch(k, s, side, za, zb, float(pn[2]), float(pn[3]), Color(0.17, 0.18, 0.2), 0.008)
			_skin_patch(k, s, side, za + 0.05, zb - 0.05, float(pn[2]) + 0.04, float(pn[3]) - 0.04, GLASS, 0.014)
	# Zierstreifen in Hausfarbe unter den Fenstern, Fenster, Türen, Notausstiege
	var wdy: float = s["win_dy"]
	var doors: Array = s["doors"]
	var exits: Array = s["exits"]
	for side: float in [-1.0, 1.0]:
		var sz := z0 + nose_len * 0.95
		while sz < ts + 2.0:
			var se := minf(sz + 0.9, ts + 2.0)
			var a_hi := _skin_angle(s, sz, cy - r * 0.18)
			var a_lo := _skin_angle(s, sz, cy - r * 0.3)
			_skin_patch(k, s, side, sz, se, a_hi, a_lo, livery, 0.006)
			sz = se
		var wz: float = s["win_from"]
		while wz <= float(s["win_to"]):
			var blocked := false
			for e: float in exits:
				blocked = blocked or absf(wz - e) < 0.32
			if not blocked:
				_window(k, s, side, wz, cy + wdy, 0.115, 0.165, WIN)
			wz += 0.535
		for d: float in doors:
			_door(k, s, side, d, cy - 0.05, 0.43, 0.95)
			_window(k, s, side, d, cy + wdy - 0.05, 0.11, 0.13, WIN)
		for e: float in exits:
			_door(k, s, side, e, cy + 0.12, 0.26, 0.48)
			_window(k, s, side, e, cy + wdy, 0.1, 0.13, WIN)
	# Frachttüren rechts unten, Antennen und Ablaufmasten am Bauch
	for cz: float in [float(s["wing_z"]) - 5.5, float(s["tail_start"]) - 1.0]:
		_door(k, s, 1.0, cz, cy - r * 0.55, 0.85, 0.6)
	var by := cy - r * 1.05
	for az: float in [-10.0, -3.0, 8.0]:
		k.cyl(Vector3(0, by + 0.05, az), Vector3(0, by - 0.3, az + 0.25), 0.05, 0.02, DARK_METAL, 6)
	# Staurohre seitlich an der Nase
	for side: float in [-1.0, 1.0]:
		var sk := _skin(s, z0 + nose_len * 0.55, PI * 0.55, side)
		var pp: Vector3 = sk[0]
		k.cyl(pp, pp + Vector3(side * 0.12, -0.02, -0.18), 0.025, 0.012, METAL, 6)
	# Rumpf-Flügel-Verkleidung: flacher Bauch unter dem Mittelrumpf
	var wz0: float = s["wing_z"]
	var wc: float = s["wing_c"]
	if not bool(s.get("high", false)):
		k.sphere(Vector3(0, cy - r * 0.62, wz0 + wc * 0.5), 1.0, BELLY, 28, 14, Vector3(r * 0.96, r * 0.5, wc * 1.05))
	else:
		# Schulterdecker: Fahrwerksgondeln seitlich, Flügelbuckel oben
		k.sphere(Vector3(0, cy + r * 0.82, float(s["wing_z"]) + float(s["wing_c"]) * 0.45), 1.0, WHITE, 24, 12, Vector3(r * 0.7, r * 0.32, float(s["wing_c"]) * 1.1))


## Fläche auf der Rumpfhaut zwischen za und zb und den Winkeln a0..a1 (von oben gemessen), leicht abgehoben.
static func _skin_patch(k: Kit, s: Dictionary, side: float, za: float, zb: float, a0: float, a1: float, col: Color, lift: float) -> void:
	var nz := maxi(1, ceili((zb - za) / 0.35))
	var na := maxi(1, ceili(absf(a1 - a0) / 0.12))
	for iz in range(nz):
		for ia in range(na):
			var pts := []
			for e: Array in [[iz, ia], [iz + 1, ia], [iz + 1, ia + 1], [iz, ia + 1]]:
				var zz := lerpf(za, zb, float(e[0]) / float(nz))
				var aa := lerpf(a0, a1, float(e[1]) / float(na))
				var sk := _skin(s, zz, aa, side)
				pts.append([(sk[0] as Vector3) + (sk[1] as Vector3) * lift, sk[1]])
			var c := ((pts[0][0] as Vector3) + (pts[2][0] as Vector3)) * 0.5
			var nn: Vector3 = pts[0][1]
			k.quad_n(pts[0][0], pts[1][0], pts[2][0], pts[3][0], pts[0][1], pts[1][1], pts[2][1], pts[3][1], col, c - nn)


## Kabinenfenster: abgerundetes Rechteck auf der Haut (Mitte z, Höhe y).
static func _window(k: Kit, s: Dictionary, side: float, z: float, y: float, hw: float, hh: float, col: Color) -> void:
	var a := _skin_angle(s, z, y)
	var sk := _skin(s, z, a, side)
	var c: Vector3 = (sk[0] as Vector3) + (sk[1] as Vector3) * 0.012
	var nrm: Vector3 = sk[1]
	var up := Vector3(0, 1, 0) - nrm * nrm.y
	up = up.normalized()
	var fw := Vector3(0, 0, 1)
	var pts := []
	for i in range(12):
		var t := TAU * float(i) / 12.0
		var ex := cos(t)
		var ey := sin(t)
		var sx := signf(ex) * pow(absf(ex), 0.6)
		var sy := signf(ey) * pow(absf(ey), 0.6)
		pts.append(c + fw * sx * hw + up * sy * hh)
	for i in range(12):
		k.tri(c, pts[i], pts[(i + 1) % 12], col, c - nrm)


## Türumriss: dunkle Fuge als Rahmen auf der Haut.
static func _door(k: Kit, s: Dictionary, side: float, z: float, y: float, hw: float, hh: float) -> void:
	var a_top := _skin_angle(s, z, y + hh)
	var a_bot := _skin_angle(s, z, y - hh)
	var a_t2 := _skin_angle(s, z, y + hh - 0.05)
	var a_b2 := _skin_angle(s, z, y - hh + 0.05)
	_skin_patch(k, s, side, z - hw, z - hw + 0.05, a_top, a_bot, DOOR_LINE, 0.008)
	_skin_patch(k, s, side, z + hw - 0.05, z + hw, a_top, a_bot, DOOR_LINE, 0.008)
	_skin_patch(k, s, side, z - hw, z + hw, a_top, a_t2, DOOR_LINE, 0.008)
	_skin_patch(k, s, side, z - hw, z + hw, a_b2, a_bot, DOOR_LINE, 0.008)


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
	var bottom := [a - dir * tha * 0.5, a + z * ca - dir * tha * 0.12, b + z * cb - dir * thb * 0.12, b - dir * thb * 0.5]
	var top := [a + dir * tha * 0.5, a + z * ca + dir * tha * 0.12, b + z * cb + dir * thb * 0.12, b + dir * thb * 0.5]
	k.prism(bottom, top, col, side_col)
	# gerundete Vorderkante (Nase des Profils) statt einer scharfen Kante
	k.cyl(a + z * tha * 0.02, b + z * thb * 0.02, tha * 0.5, thb * 0.5, col, 10, true)


static func _wing_at(s: Dictionary, ax: float) -> Array:
	var root_x: float = float(s["r"]) * float(s.get("root_f", 0.82))
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


## Profilschnitt (NACA-Dicke, leichte Wölbung) als geschlossener Ring: Hinterkante oben → Nase →
## Hinterkante unten (die Hinterkante steht doppelt und bleibt scharf).
static func _airfoil(le: Vector3, chord_dir: Vector3, up: Vector3, c: float, tr: float, camber: float = 0.02, n: int = 12) -> PackedVector3Array:
	var up_pts := []
	var lo_pts := []
	for k in range(n + 1):
		var u := (1.0 - cos(PI * float(k) / float(n))) * 0.5
		var yt := 5.0 * tr * (0.2969 * sqrt(u) - 0.126 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1036 * u * u * u * u)
		var yc := camber * 4.0 * u * (1.0 - u)
		up_pts.append(le + chord_dir * (u * c) + up * ((yc + yt) * c))
		lo_pts.append(le + chord_dir * (u * c) + up * ((yc - yt) * c))
	var ring := PackedVector3Array()
	for k in range(n, -1, -1):
		ring.append(up_pts[k])
	for k in range(1, n + 1):
		ring.append(lo_pts[k])
	return ring


## Halbe Profildicke bei Sehnenanteil u (für Aufkleber auf Leitwerken).
static func _half_thick(tr: float, u: float) -> float:
	return 5.0 * tr * (0.2969 * sqrt(u) - 0.126 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1036 * u * u * u * u)


## Farbe je Viereck eines Profil-Lofts nach Sehnenanteil: Vorflügel heller, Klappen dunkler.
static func _wing_col(j: int, n: int, base: Color) -> Color:
	# Ring: 0..n oben (Hinterkante→Nase), n..2n unten (Nase→Hinterkante)
	var u := 0.0
	if j < n:
		u = (1.0 - cos(PI * float(n - j - 0.5) / float(n))) * 0.5
	else:
		u = (1.0 - cos(PI * float(j - n + 0.5) / float(n))) * 0.5
	if u < 0.07:
		return base.lightened(0.08)
	if u > 0.74:
		return base.darkened(0.07)
	return base


static func _wings(k: Kit, s: Dictionary, livery: Color) -> void:
	var r: float = s["r"]
	var kink_x := float(s["eng_x"]) + 1.4
	var tip_x: float = s["tip_x"]
	var dih := deg_to_rad(float(s["dihedral"]))
	var high := bool(s.get("high", false))
	var nf := 12
	for side: float in [-1.0, 1.0]:
		var up := Vector3(-side * sin(dih), cos(dih), 0.0)
		var xs := [r * 0.45, r * 1.05, (r + kink_x) * 0.5, kink_x, lerpf(kink_x, tip_x, 0.5), tip_x - 0.25, tip_x]
		var trs := [0.15, 0.15, 0.14, 0.125, 0.11, 0.1, 0.1]
		var rings := []
		for q in range(xs.size()):
			var w := _wing_at(s, xs[q])
			var le := Vector3(side * float(xs[q]), float(w[1]), float(w[0]))
			rings.append(_airfoil(le, Vector3(0, 0, 1), up, float(w[2]), float(trs[q]), 0.02 if not high else 0.03, nf))
		# Winglet: der Flügel biegt sich in einem Bogen nach oben (Sharklet / Blended Winglet)
		var wl: Array = s["winglet"]
		var n_wing := rings.size()
		if float(wl[0]) > 0.0:
			var tip := _wing_at(s, tip_x)
			var base := Vector3(side * tip_x, float(tip[1]), float(tip[0]))
			var rad := 0.75
			var tip_c: float = tip[2]
			for q in range(1, 6):
				var f := float(q) / 5.0
				var ph := dih + (deg_to_rad(78.0) - dih) * f
				var pos := base + Vector3(side * rad * (sin(ph) - sin(dih)), rad * ((1.0 - cos(ph)) - (1.0 - cos(dih))), 0.0)
				pos.z += float(wl[2]) * 0.18 * f
				var upq := Vector3(-side * sin(ph), cos(ph), 0.0)
				rings.append(_airfoil(pos, Vector3(0, 0, 1), upq, lerpf(tip_c, (tip_c + float(wl[3])) * 0.5, f), lerpf(0.1, 0.09, f), 0.0, nf))
			var last: PackedVector3Array = rings[rings.size() - 1]
			var lpos := Vector3(base.x + side * (rad * (sin(deg_to_rad(78.0)) - sin(dih)) + float(wl[1])), base.y + rad + float(wl[0]) - 0.4, base.z + float(wl[2]))
			var phl := deg_to_rad(84.0)
			rings.append(_airfoil(lpos, Vector3(0, 0, 1), Vector3(-side * sin(phl), cos(phl), 0), float(wl[3]), 0.08, 0.0, nf))
		var nw := n_wing
		var col_fn := func(_m: Vector3, i: int, jj: int) -> Color:
			if i >= nw - 1 and float(wl[0]) > 0.0:
				return livery if i >= nw + 1 else WING
			return _wing_col(jj, nf, WING)
		k.loft(rings, col_fn, true, false, true)
		# Klappenschienen-Verkleidungen unter der Hinterkante (Kanus)
		if not high:
			for fx: float in [kink_x - 1.6, kink_x + 2.2, kink_x + 5.2, kink_x + 8.0]:
				if fx > tip_x - 2.0:
					continue
				var w := _wing_at(s, fx)
				var te: float = float(w[0]) + float(w[2])
				var wy: float = float(w[1]) - 0.02
				k.sphere(Vector3(side * fx, wy - 0.18, te - 0.4), 1.0, WING_DARK, 10, 6, Vector3(0.17, 0.2, 1.5))
		# Querruder-Fuge oben
		var ail_a := tip_x - 6.5
		var ail_b := tip_x - 1.2
		var wa2 := _wing_at(s, ail_a)
		var wb2 := _wing_at(s, ail_b)
		var ha := 0.1 * float(wa2[2]) * _half_thick(1.0, 0.8) + 0.012
		var hb := 0.1 * float(wb2[2]) * _half_thick(1.0, 0.8) + 0.012
		k.quad(Vector3(side * ail_a, float(wa2[1]) + ha, float(wa2[0]) + float(wa2[2]) * 0.79),
			Vector3(side * ail_b, float(wb2[1]) + hb, float(wb2[0]) + float(wb2[2]) * 0.79),
			Vector3(side * ail_b, float(wb2[1]) + hb, float(wb2[0]) + float(wb2[2]) * 0.81),
			Vector3(side * ail_a, float(wa2[1]) + ha, float(wa2[0]) + float(wa2[2]) * 0.81), WING_DARK, Vector3(side * ail_a, -10, 0))


## Landeklappe innen (Wurzel bis Knick) oder außen (Knick bis Querruder) einer Seite.
## Rückgabe [Mesh, Drehpunkt an der Vorderkante, Drehachse, Sehne] in Flugzeugkoordinaten;
## das Mesh liegt relativ zum Drehpunkt. Eingefahren steckt sie in der Hinterkante.
static func flap_part(kind: String, side: float, inner: bool) -> Array:
	var key := "flap_%s_%d_%d" % [kind, int(side), int(inner)]
	var s: Dictionary = SPECS.get(kind, SPECS["a320"])
	var root_x: float = float(s["r"]) * float(s.get("root_f", 0.82))
	var kink_x := float(s["eng_x"]) + 1.4
	var ail_a := float(s["tip_x"]) - 6.5
	var x0 := root_x + 0.25 if inner else kink_x + 0.1
	var x1 := kink_x - 0.1 if inner else ail_a - 0.2
	var wa := _wing_at(s, x0)
	var wb := _wing_at(s, x1)
	var ha := Vector3(side * x0, float(wa[1]) - 0.01, float(wa[0]) + float(wa[2]) * 0.78)
	var hb := Vector3(side * x1, float(wb[1]) - 0.01, float(wb[0]) + float(wb[2]) * 0.78)
	var ta := Vector3(side * x0, float(wa[1]) - 0.04, float(wa[0]) + float(wa[2]) * 0.995)
	var tb := Vector3(side * x1, float(wb[1]) - 0.04, float(wb[0]) + float(wb[2]) * 0.995)
	var axis := (hb - ha).normalized() * side
	if not _cache.has(key):
		var k := Kit.new()
		var up := Vector3(0, 0.035, 0)
		var up2 := Vector3(0, 0.014, 0)
		k.prism([ha - up - ha, hb - up - ha, tb - up2 - ha, ta - up2 - ha], [ha + up - ha, hb + up - ha, tb + up2 - ha, ta + up2 - ha], WING, WING_DARK)
		_cache[key] = k.commit()
	return [_cache[key], ha, axis, float(wa[2])]


## Spoiler-Paket einer Seite (vier Klappen oben auf dem Flügel hinter dem Triebwerk), Drehachse an der Vorderkante.
static func spoiler_part(kind: String, side: float) -> Array:
	var key := "spoiler_%s_%d" % [kind, int(side)]
	var s: Dictionary = SPECS.get(kind, SPECS["a320"])
	var x0 := float(s["eng_x"]) + 0.4
	var x1 := x0 + 4.0 * 1.6 - 0.2
	var wa := _wing_at(s, x0)
	var wb := _wing_at(s, x1)
	var ha := Vector3(side * x0, float(wa[1]) + 0.2, float(wa[0]) + float(wa[2]) * 0.55)
	var hb := Vector3(side * x1, float(wb[1]) + 0.18, float(wb[0]) + float(wb[2]) * 0.55)
	var axis := (hb - ha).normalized() * side
	if not _cache.has(key):
		var k := Kit.new()
		for i in range(4):
			var sx0 := x0 + float(i) * 1.6
			var w0 := _wing_at(s, sx0)
			var w1 := _wing_at(s, sx0 + 1.4)
			var a0 := Vector3(side * sx0, float(w0[1]) + 0.2, float(w0[0]) + float(w0[2]) * 0.55) - ha
			var a1 := Vector3(side * (sx0 + 1.4), float(w1[1]) + 0.19, float(w1[0]) + float(w1[2]) * 0.55) - ha
			var b0 := Vector3(side * sx0, float(w0[1]) + 0.2, float(w0[0]) + float(w0[2]) * 0.7) - ha
			var b1 := Vector3(side * (sx0 + 1.4), float(w1[1]) + 0.19, float(w1[0]) + float(w1[2]) * 0.7) - ha
			var t := Vector3(0, 0.03, 0)
			k.prism([a0, a1, b1, b0], [a0 + t, a1 + t, b1 + t, b0 + t], WING.darkened(0.06), WING_DARK)
		_cache[key] = k.commit()
	return [_cache[key], ha, axis]


static func _tail(k: Kit, s: Dictionary, livery: Color) -> void:
	var nf := 10
	# Höhenleitwerk: gepfeilte Profile mit leichter V-Stellung
	var sz: float = s["stab_z"]
	var sy: float = s["stab_y"]
	var span: float = s["stab_span"]
	var stc: float = s["stab_c"]
	var sw := tan(deg_to_rad(float(s["stab_sweep"])))
	for side: float in [-1.0, 1.0]:
		var rings := []
		for f: float in [0.0, 0.08, 0.4, 0.8, 0.97, 1.0]:
			var x := lerpf(0.2, span, f)
			var c := lerpf(stc, stc * 0.38, f) * (0.96 if f >= 1.0 else 1.0)
			var le := Vector3(side * x, sy + (x - 0.2) * 0.09, sz + (x - 0.2) * sw + (0.03 if f >= 1.0 else 0.0))
			rings.append(_airfoil(le, Vector3(0, 0, 1), Vector3(-side * 0.09, 1, 0).normalized(), c, lerpf(0.11, 0.09, f), 0.0, nf))
		k.loft(rings, func(_m: Vector3, _i: int, jj: int) -> Color: return _wing_col(jj, nf, WING), true, false, true)
	# Seitenleitwerk in Airline-Farbe: dünnes symmetrisches Profil, gepfeilt
	var fz: float = s["fin_z"]
	var fc: float = s["fin_c"]
	var fh: float = s["fin_h"]
	var ftc: float = s["fin_tip_c"]
	var fsw := tan(deg_to_rad(float(s["fin_sweep"])))
	var q := _section(s, fz + fc * 0.5)
	var base_y: float = float(q[2]) - 0.25
	var frings := []
	for f: float in [-0.04, 0.0, 0.3, 0.65, 0.95, 1.0]:
		var h := fh * f
		var c := lerpf(fc, ftc, clampf(f, 0.0, 1.0)) * (0.97 if f >= 1.0 else 1.0)
		var le := Vector3(0, base_y + h, fz + h * fsw)
		frings.append(_airfoil(le, Vector3(0, 0, 1), Vector3(1, 0, 0), c, 0.11, 0.0, nf))
	k.loft(frings, func(m: Vector3, _i: int, _jj: int) -> Color:
		return livery if m.y > base_y + 0.15 else WHITE, true, false, true)
	if bool(s["dorsal"]):
		var drings := []
		for f: float in [0.0, 0.5, 1.0]:
			var le := Vector3(0, base_y - 0.1 + f * 1.0, lerpf(fz - 3.8, fz - 0.4, f))
			drings.append(_airfoil(le, Vector3(0, 0, 1), Vector3(1, 0, 0), lerpf(3.9, 0.6, f) + 0.3, 0.12, 0.0, nf))
		k.loft(drings, func(_m: Vector3, _i: int, _jj: int) -> Color: return livery, true, false, true)
	# Ruderfugen und Emblem
	var tip_z := fz + fh * fsw
	for side: float in [-1.0, 1.0]:
		var rz0 := fz + fc * 0.7
		var rz1 := tip_z + ftc * 0.7
		var x0 := side * (_half_thick(0.11, 0.7) * fc + 0.01)
		var x1 := side * (_half_thick(0.11, 0.7) * ftc + 0.01)
		k.quad(Vector3(x0, base_y + 0.3, rz0), Vector3(x1, base_y + fh * 0.96, rz1),
			Vector3(x1, base_y + fh * 0.96, rz1 + 0.05), Vector3(x0, base_y + 0.3, rz0 + 0.05),
			livery.darkened(0.3), Vector3(-side * 10.0, base_y + fh * 0.5, (rz0 + rz1) * 0.5))
	var mid_f := 0.5
	var mid_y := base_y + fh * mid_f
	var mid_c := lerpf(fc, ftc, mid_f)
	var mid_z := fz + fh * mid_f * fsw + mid_c * 0.45
	var thx := _half_thick(0.11, 0.45) * mid_c + 0.012
	for side: float in [-1.0, 1.0]:
		var n := Vector3(side, 0, 0)
		var em := mid_c * 0.22
		_disc(k, Vector3(side * thx, mid_y, mid_z), n, em, WHITE)
		_disc(k, Vector3(side * (thx + 0.004), mid_y, mid_z), n, em * 0.62, livery.lightened(0.35))


## Runde Scheibe (Emblem, Lampe) mit Blickrichtung n.
static func _disc(k: Kit, c: Vector3, n: Vector3, rad: float, col: Color, seg: int = 20) -> void:
	var a := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var b := n.cross(a).normalized()
	for i in range(seg):
		var t0 := TAU * float(i) / float(seg)
		var t1 := TAU * float(i + 1) / float(seg)
		k.tri(c, c + (a * cos(t0) + b * sin(t0)) * rad, c + (a * cos(t1) + b * sin(t1)) * rad, col, c - n)


static func _engine(k: Kit, s: Dictionary, livery: Color, side: float) -> void:
	var ex := side * float(s["eng_x"])
	var ey: float = s["eng_y"]
	var r: float = s["eng_r"]
	var flat: float = s["eng_flat"]
	var z0: float = s["eng_z"]
	var ln: float = s["eng_len"]
	var w := _wing_at(s, absf(ex))
	if bool(s.get("props", false)):
		# Turboprop-Gondel (PW127): Spinner vorn, Lufteinlass darunter, schlanker Körper bis hinter den Flügel
		var prings := [[z0 + 0.15, ey, r * 0.55, r * 0.55], [z0 + 0.5, ey, r * 0.86, r * 0.9 * flat], [z0 + 1.4, ey, r, r * flat],
			[z0 + ln * 0.5, ey + 0.05, r * 0.98, r * flat], [z0 + ln * 0.8, ey + 0.2, r * 0.72, r * 0.75 * flat], [z0 + ln, ey + 0.38, r * 0.2, r * 0.2]]
		k.lathe(prings, 28, func(_fz: float, _fx: float, _dy: float, _ry: float) -> Color: return WHITE.darkened(0.03), true, true, ex)
		k.sphere(Vector3(ex, ey - r * flat * 0.75, z0 + 0.9), 1.0, WHITE.darkened(0.06), 14, 8, Vector3(r * 0.45, r * 0.35, 0.7))
		k.cyl(Vector3(ex, ey - r * flat * 0.75, z0 + 0.25), Vector3(ex, ey - r * flat * 0.75, z0 + 0.3), r * 0.32, r * 0.22, Color(0.1, 0.1, 0.11), 14)
		for sd: float in [-1.0, 1.0]:
			k.cyl(Vector3(ex + sd * r * 0.8, ey + 0.1, z0 + 2.2), Vector3(ex + sd * r * 0.95, ey + 0.2, z0 + 2.9), 0.12, 0.09, DARK_METAL, 8)
		return
	# Turbofan (CFM56 / LEAP / CF6): Lippe, Fan-Gehäuse, Schubumkehrer, Kerntriebwerk mit Düse und Konus
	var ring := func(zz: float, rr: float, dy: float = 0.0) -> Array: return [zz, ey + dy, rr, rr * flat]
	var rings := [ring.call(z0, r * 0.84), ring.call(z0 + 0.04, r * 0.93), ring.call(z0 + 0.14, r * 0.985), ring.call(z0 + 0.35, r * 1.02),
		ring.call(z0 + ln * 0.3, r * 1.03), ring.call(z0 + ln * 0.5, r * 1.0), ring.call(z0 + ln * 0.62, r * 0.95), ring.call(z0 + ln * 0.74, r * 0.86)]
	var col_fn := func(fz: float, _fx: float, _dy: float, _ry: float) -> Color:
		if fz < z0 + 0.1:
			return Color(0.78, 0.79, 0.8)
		if fz > z0 + ln * 0.5 and fz < z0 + ln * 0.52:
			return livery.darkened(0.35)
		return livery
	k.lathe(rings, 36, col_fn, false, false, ex)
	# Innenwand des Einlaufs (dunkel), damit man nicht ins Leere schaut
	k.lathe([[z0 + 0.02, ey, r * 0.83, r * 0.83 * flat], [z0 + 0.5, ey, r * 0.85, r * 0.85 * flat]], 32,
		func(_a: float, _b: float, _c: float, _d: float) -> Color: return Color(0.2, 0.21, 0.23), false, false, ex)
	# Kerntriebwerk mit Düse, Abgaskonus
	var core := [[z0 + ln * 0.7, ey, r * 0.7, r * 0.7 * flat], [z0 + ln * 0.85, ey, r * 0.66, r * 0.66 * flat], [z0 + ln + 0.4, ey, r * 0.5, r * 0.5 * flat],
		[z0 + ln + 0.55, ey, r * 0.45, r * 0.45 * flat]]
	k.lathe(core, 28, func(fz: float, _b: float, _c: float, _d: float) -> Color:
		return Color(0.55, 0.56, 0.58) if fz < z0 + ln + 0.35 else DARK_METAL, false, false, ex)
	k.lathe([[z0 + ln + 0.4, ey, r * 0.3, r * 0.3], [z0 + ln + 0.9, ey, r * 0.18, r * 0.18], [z0 + ln + 1.25, ey, 0.03, 0.03]], 16,
		func(_a: float, _b: float, _c: float, _d: float) -> Color: return Color(0.42, 0.4, 0.38), true, false, ex)
	# Pylon: schlankes Profil vom Triebwerk nach oben unter den Flügel
	var top_y := ey + r * flat * 0.92
	var prings := []
	for f: float in [0.0, 0.5, 1.0]:
		var y := lerpf(top_y - 0.2, float(w[1]) + 0.05, f)
		var zl := lerpf(z0 + 0.8, float(w[0]) - 0.3, f)
		var zt := lerpf(z0 + ln + 0.3, float(w[0]) + float(w[2]) * 0.75, f)
		var pr := _airfoil(Vector3(ex, y, zl), Vector3(0, 0, 1), Vector3(1, 0, 0), zt - zl, 0.08, 0.0, 8)
		prings.append(pr)
	k.loft(prings, func(_m: Vector3, _i: int, _j: int) -> Color: return WHITE.darkened(0.05), true, false, false)


static func _gear(k: Kit, s: Dictionary) -> void:
	var cy: float = s["cy"]
	var r: float = s["r"]
	var bot := cy - r
	var nz: float = s["nose_gear_z"]
	var nr: float = s["nose_wheel_r"]
	var nb := float(_profile(s, nz)[0]) - float(_profile(s, nz)[2])
	k.cyl(Vector3(0, nb + 0.2, nz), Vector3(0, nr, nz + 0.12), 0.09, 0.09, METAL, 8)
	for side: float in [-1.0, 1.0]:
		_wheel(k, Vector3(side * 0.21, nr, nz + 0.12), nr, 0.24, side, METAL, 0)
		k.box(Vector3(side * 0.42, nb - 0.9, nz - 0.9), Vector3(side * 0.46, nb + 0.1, nz + 0.4), WHITE)
	var mz: float = s["main_gear_z"]
	var mx: float = s["main_gear_x"]
	var mr: float = s["main_wheel_r"]
	var high := bool(s.get("high", false))
	var rows: Array = [0.0] if int(s.get("bogie", 1)) < 2 else [-0.78, 0.78]
	for side: float in [-1.0, 1.0]:
		var w := _wing_at(s, mx)
		var x := side * mx
		var strut_top: float = (bot + 0.5) if high else float(w[1]) - 0.1
		k.cyl(Vector3(x, strut_top, mz - 0.2), Vector3(x, mr, mz), 0.14, 0.12, METAL, 10)
		k.box(Vector3(x - 0.5, mr - 0.06, mz + float(rows[0]) - 0.06), Vector3(x + 0.5, mr + 0.06, mz + float(rows[rows.size() - 1]) + 0.06), METAL)
		for wz: float in rows:
			for off: float in [-0.48, 0.48]:
				_wheel(k, Vector3(x + off, mr, mz + wz), mr, 0.38, signf(off), METAL, 0)
		# Stoßdämpfer und Drehmomentstützen
		k.cyl(Vector3(x, mr + 0.25, mz), Vector3(x, mr + 1.0, mz - 0.1), 0.09, 0.09, Color(0.85, 0.86, 0.88), 8)
		k.cyl(Vector3(x, mr + 0.35, mz + 0.05), Vector3(x, mr + 0.75, mz + 0.35), 0.04, 0.04, DARK_METAL, 6)
		k.cyl(Vector3(x, mr + 0.75, mz + 0.35), Vector3(x, mr + 1.05, mz + 0.05), 0.04, 0.04, DARK_METAL, 6)
		if high:
			# Fahrwerksverkleidung seitlich am Rumpf
			k.box(Vector3(x - 0.55, bot + 0.1, mz - 1.6), Vector3(x + 0.55, bot + 1.0, mz + 1.6), WHITE.darkened(0.03))
		else:
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


## Pose: 0 stehen, 5 sitzen, 1–4 und 10–17 Gangphasen (4 bzw. 8 je Doppelschritt).
const WALK_FRAMES := 8


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
	var skirt := bool(look["skirt"])
	var sit := pose == 5
	var walking := pose != 0 and not sit
	var phase := 0.0
	if pose >= 10:
		phase = TAU * float(pose - 10) / float(WALK_FRAMES)
	elif walking:
		phase = TAU * float(pose - 1) / 4.0
	# Gelenkwinkel: Oberschenkel pendelt, Knie beugt sich beim Durchschwingen, Arme gegengleich
	var hip_y := 0.9
	var legs := []
	for side: float in [-1.0, 1.0]:
		var ph := phase + (0.0 if side > 0.0 else PI)
		var a := 0.42 * sin(ph) if walking else 0.0
		var kb := 0.75 * maxf(0.0, sin(ph + 1.1)) * 0.8 if walking else 0.0
		if sit:
			a = PI * 0.5
			kb = PI * 0.5
		legs.append([side, a, kb])
	# Becken so hoch, dass der tiefste Fuß den Boden berührt (natürliches Wippen beim Gehen)
	var low := INF
	for l: Array in legs:
		var a: float = l[1]
		var kb: float = l[2]
		var ankle_y := -0.45 * cos(a) - 0.43 * cos(a - kb)
		low = minf(low, ankle_y)
	if sit:
		hip_y = 0.5
	else:
		hip_y = 0.075 - low
	var y0 := hip_y - 0.9
	var leg_col := skin if skirt else pants
	for l: Array in legs:
		var side: float = l[0]
		var a: float = l[1]
		var kb: float = l[2]
		var hip := Vector3(side * 0.095, hip_y, 0.0)
		var d1 := Vector3(0, -cos(a), -sin(a))
		var knee := hip + d1 * 0.45
		var d2 := Vector3(0, -cos(a - kb), -sin(a - kb))
		var ankle := knee + d2 * 0.43
		k.cyl(hip, knee, 0.078, 0.06, leg_col, 7)
		k.cyl(knee, ankle, 0.058, 0.045, leg_col, 7)
		# Schuh: flach, vorne gerundet
		var fz := ankle.z
		var fy := ankle.y - 0.035
		k.soft_box(Vector3(side * 0.095 - 0.055, fy - 0.04, fz - 0.17), Vector3(side * 0.095 + 0.055, fy + 0.045, fz + 0.06), 0.04, shoes, 12, 6)
	if skirt:
		k.cyl(Vector3(0, hip_y + 0.08, 0), Vector3(0, hip_y - 0.38, 0), 0.17, 0.25, pants, 10)
	# Becken, Gürtel, Oberkörper (Taille schmal, Brust und Schultern breiter)
	k.soft_box(Vector3(-0.17, hip_y - 0.07, -0.1), Vector3(0.17, hip_y + 0.08, 0.1), 0.06, pants, 12, 6)
	k.soft_box(Vector3(-0.168, hip_y + 0.05, -0.102), Vector3(0.168, hip_y + 0.09, 0.102), 0.06, Color(0.12, 0.1, 0.08), 12, 6)
	var sy := hip_y + 0.5
	k.prism([Vector3(-0.16, hip_y + 0.06, -0.095), Vector3(0.16, hip_y + 0.06, -0.095), Vector3(0.16, hip_y + 0.06, 0.095), Vector3(-0.16, hip_y + 0.06, 0.095)],
		[Vector3(-0.2, sy - 0.12, -0.12), Vector3(0.2, sy - 0.12, -0.12), Vector3(0.2, sy - 0.12, 0.11), Vector3(-0.2, sy - 0.12, 0.11)], top)
	k.prism([Vector3(-0.2, sy - 0.12, -0.12), Vector3(0.2, sy - 0.12, -0.12), Vector3(0.2, sy - 0.12, 0.11), Vector3(-0.2, sy - 0.12, 0.11)],
		[Vector3(-0.15, sy, -0.08), Vector3(0.15, sy, -0.08), Vector3(0.15, sy, 0.09), Vector3(-0.15, sy, 0.09)], top)
	if jacket != null and not bool(look["vest"]):
		k.panel(Vector3(0, sy - 0.22, -0.122), Vector3(0.04, 0, 0), Vector3(0, 0.2, -0.02), shirt, Vector3(0, 0, -1))
	if bool(look["vest"]):
		for vy: float in [hip_y + 0.17, hip_y + 0.34]:
			k.box(Vector3(-0.185, vy, -0.123), Vector3(0.185, vy + 0.045, 0.118), Color(0.82, 0.84, 0.86))
	# Arme: Schulterkugel, Ober- und Unterarm, Hand
	for side: float in [-1.0, 1.0]:
		var ph := phase + (PI if side > 0.0 else 0.0)
		var b := 0.38 * sin(ph) if walking else 0.0
		var eb := 0.25 + (0.25 * maxf(0.0, sin(ph)) if walking else 0.0)
		if sit:
			b = 0.35
			eb = 0.9
		var sh := Vector3(side * 0.205, sy - 0.04, 0.0)
		k.sphere(sh, 0.068, top.darkened(0.03), 8, 5)
		var u := Vector3(side * 0.03, -cos(b), -sin(b)).normalized()
		var elbow := sh + u * 0.29
		var f := Vector3(side * 0.02, -cos(b + eb), -sin(b + eb)).normalized()
		var wrist := elbow + f * 0.26
		k.cyl(sh, elbow, 0.058, 0.048, top.darkened(0.03), 7)
		k.cyl(elbow, wrist, 0.046, 0.036, top.darkened(0.03) if jacket != null or bool(look["vest"]) else skin, 7)
		k.sphere(wrist + f * 0.04, 0.042, skin, 6, 4)
	# Hals und Kopf
	k.cyl(Vector3(0, sy - 0.02, 0.0), Vector3(0, sy + 0.08, 0.0), 0.045, 0.042, skin, 8)
	var hc := Vector3(0, sy + 0.18, -0.005)
	k.sphere(hc, 0.105, skin, 10, 7, Vector3(0.92, 1.08, 1.0))
	for ex: float in [-0.038, 0.038]:
		k.box(Vector3(ex - 0.014, hc.y + 0.012, -0.104), Vector3(ex + 0.014, hc.y + 0.03, -0.094), Color(0.08, 0.07, 0.07))
	k.box(Vector3(-0.013, hc.y - 0.035, -0.115), Vector3(0.013, hc.y + 0.01, -0.095), skin.darkened(0.08))
	k.box(Vector3(-0.03, hc.y - 0.065, -0.1), Vector3(0.03, hc.y - 0.055, -0.092), skin.darkened(0.25))
	_hair(k, int(look["style"]), hair, hc, top)
	# Tasche
	match int(look["bag"]):
		1:
			k.soft_box(Vector3(-0.15, sy - 0.42, 0.1), Vector3(0.15, sy - 0.06, 0.27), 0.05, JACKETS[(int(str(hair.to_html()).hash()) & 0x7fffffff) % JACKETS.size()], 12, 6)
		2:
			k.soft_box(Vector3(0.24, hip_y - 0.12, -0.08), Vector3(0.31, hip_y + 0.1, 0.12), 0.03, Color(0.35, 0.2, 0.12), 12, 6)
			k.box(Vector3(0.265, hip_y + 0.1, 0.0), Vector3(0.285, sy - 0.05, 0.03), Color(0.3, 0.18, 0.1))
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh


## Frisuren auf dem Kopf (Mitte hc): 0 kurz, 1 lang, 2 Zopf, 3 Glatze mit Haarkranz, sonst Mütze.
static func _hair(k: Kit, style: int, hair: Color, hc: Vector3, cap_col: Color) -> void:
	match style:
		0:
			k.sphere(hc + Vector3(0, 0.035, 0.018), 0.108, hair, 10, 6, Vector3(0.96, 0.85, 0.98))
		1:
			k.sphere(hc + Vector3(0, 0.03, 0.02), 0.112, hair, 10, 6, Vector3(0.98, 0.9, 1.0))
			k.soft_box(Vector3(-0.1, hc.y - 0.2, 0.0), Vector3(0.1, hc.y + 0.04, 0.115), 0.05, hair, 12, 6)
		2:
			k.sphere(hc + Vector3(0, 0.035, 0.018), 0.108, hair, 10, 6, Vector3(0.96, 0.85, 0.98))
			k.cyl(hc + Vector3(0, 0.02, 0.1), hc + Vector3(0, -0.16, 0.15), 0.035, 0.02, hair, 6)
		3:
			k.sphere(hc + Vector3(0, -0.01, 0.03), 0.1, hair, 10, 5, Vector3(1.0, 0.55, 0.85))
		_:
			k.sphere(hc + Vector3(0, 0.05, 0.01), 0.112, cap_col.darkened(0.2), 10, 5, Vector3(1.0, 0.7, 1.0))
			k.box(Vector3(-0.09, hc.y + 0.03, -0.2), Vector3(0.09, hc.y + 0.05, -0.08), cap_col.darkened(0.2))


# ================================================================== Autos

## Bauarten: kompakt, limousine, kombi, suv, transporter, taxi
# ================================================================== Karosserien aus Querschnitten

## Station einer Karosserie: [z, unten, Schulter (größte Breite), oben, halbe Breite, halbe Breite oben,
## Eckigkeit oben, Eckigkeit unten] (2 = rund, 8 = fast kastig). Zwischen den Stationen monoton kubisch.
static func _st_at(st: Array, z: float) -> Array:
	var n := st.size()
	z = clampf(z, float(st[0][0]), float(st[n - 1][0]))
	var i := 0
	while i < n - 2 and float(st[i + 1][0]) <= z:
		i += 1
	var za: float = st[i][0]
	var zb: float = st[i + 1][0]
	var h := maxf(zb - za, 1e-4)
	var t := clampf((z - za) / h, 0.0, 1.0)
	var t2 := t * t
	var t3 := t2 * t
	var out := [z]
	for p in range(1, (st[0] as Array).size()):
		var ya: float = st[i][p]
		var yb: float = st[i + 1][p]
		var ma := _st_slope(st, i, p)
		var mb := _st_slope(st, i + 1, p)
		out.append((2.0 * t3 - 3.0 * t2 + 1.0) * ya + (t3 - 2.0 * t2 + t) * h * ma + (-2.0 * t3 + 3.0 * t2) * yb + (t3 - t2) * h * mb)
	return out


static func _st_slope(st: Array, i: int, p: int) -> float:
	var n := st.size()
	if i <= 0 or i >= n - 1:
		return 0.0
	var dp := (float(st[i][p]) - float(st[i - 1][p])) / maxf(float(st[i][0]) - float(st[i - 1][0]), 1e-4)
	var dn := (float(st[i + 1][p]) - float(st[i][p])) / maxf(float(st[i + 1][0]) - float(st[i][0]), 1e-4)
	if dp * dn <= 0.0:
		return 0.0
	var lim := 3.0 * minf(absf(dp), absf(dn))
	return clampf((dp + dn) * 0.5, -lim, lim)


## Punkt des Querschnitts p unter dem Winkel th (0 = oben, PI/2 = rechts, PI = unten).
static func _st_point(p: Array, th: float) -> Vector3:
	var c := cos(th)
	var sn := sin(th)
	var up := c >= 0.0
	var e: float = p[6] if up else p[7]
	var ux := signf(sn) * pow(absf(sn), 2.0 / e)
	var uy := signf(c) * pow(absf(c), 2.0 / e)
	var y: float
	var w: float
	if up:
		y = lerpf(float(p[2]), float(p[3]), uy)
		w = lerpf(float(p[4]), float(p[5]), uy)
	else:
		y = lerpf(float(p[2]), float(p[1]), -uy)
		w = p[4]
	return Vector3(w * ux, y, float(p[0]))


## Glatte Hülle (Front -Z) aus Stationen; col_fn(Mitte, Querschnitt an der Stelle) -> Farbe.
## cuts: zusätzliche Schnitte für scharfe Farbgrenzen (Türfugen, Scheibenkanten).
static func _shell(k: Kit, st: Array, col_fn: Callable, n: int = 32, step: float = 0.15, cuts: Array = [], caps: bool = true, off: Vector3 = Vector3.ZERO, cap_col: Variant = null) -> void:
	var za: float = st[0][0]
	var zb: float = st[st.size() - 1][0]
	var zs: Array = []
	var z := za
	while z < zb - 0.02:
		zs.append(z)
		z += step
	zs.append(zb)
	for s: Array in st:
		zs.append(float(s[0]))
	for c: float in cuts:
		if c > za + 0.01 and c < zb - 0.01:
			zs.append(c)
	zs.sort()
	var rings := []
	var last := -INF
	for zz: float in zs:
		if zz - last < 0.008:
			continue
		last = zz
		var p := _st_at(st, zz)
		var ring := PackedVector3Array()
		for j in range(n):
			ring.append(_st_point(p, TAU * float(j) / float(n)) + off)
		rings.append(ring)
	var fn := func(m: Vector3, _i: int, _j: int) -> Color:
		if _j < 0 and cap_col != null:
			return cap_col
		return col_fn.call(m - off, _st_at(st, m.z - off.z))
	k.loft(rings, fn, true, caps, caps)


## Rad (Achse x) mit gerundeter Reifenflanke, Felge mit Speichen und Nabe. side: Außenseite (+1 / -1).
static func _wheel(k: Kit, c: Vector3, r: float, w: float, side: float, rim: Color = METAL, spokes: int = 5) -> void:
	var o := Vector3(side, 0, 0)
	var inner := c - o * w * 0.5
	var outer := c + o * w * 0.5
	var sh := minf(0.045, w * 0.2)
	k.cyl(inner, outer - o * sh, r, r, TYRE, 18, true, TYRE)
	k.cyl(outer - o * sh, outer, r, r * 0.9, TYRE, 18, false)
	var rr := r * 0.64
	_disc(k, outer + o * 0.001, o, r * 0.9, Color(0.1, 0.1, 0.11), 18)
	_disc(k, outer + o * 0.004, o, rr, rim.darkened(0.55), 16)
	var u := Vector3(0, 1, 0)
	var v := Vector3(0, 0, 1)
	var fc := outer + o * 0.008
	for i in range(16):
		var a0 := TAU * float(i) / 16.0
		var a1 := TAU * float(i + 1) / 16.0
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		k.quad(fc + d0 * rr * 0.84, fc + d1 * rr * 0.84, fc + d1 * rr, fc + d0 * rr, rim, fc - o)
	if spokes > 0:
		for i in range(spokes):
			var a := TAU * float(i) / float(spokes) + 0.3
			var d := u * cos(a) + v * sin(a)
			var t := d.cross(o).normalized()
			var hub := fc + d * rr * 0.22
			var tip := fc + d * rr * 0.86
			k.quad(hub - t * rr * 0.11, hub + t * rr * 0.11, tip + t * rr * 0.17, tip - t * rr * 0.17, rim, fc - o)
	else:
		_disc(k, fc - o * 0.002, o, rr * 0.84, rim.darkened(0.12), 16)
		for i in range(6):
			var a := TAU * float(i) / 6.0
			_disc(k, fc + o * 0.002 + (u * cos(a) + v * sin(a)) * rr * 0.55, o, rr * 0.09, rim.darkened(0.5), 6)
	_disc(k, fc + o * 0.004, o, rr * 0.26, rim.lightened(0.15), 10)


# ================================================================== Autos

const CAR_TYPES := ["kompakt", "limousine", "kombi", "suv", "transporter", "taxi"]
const CITY_BUS_DOORS := [-5.0, -0.4, 3.9]

## Maße nach Vorbild [Länge, Breite, Höhe]: Golf, Passat/3er, Octavia Combi, Tiguan, Transporter, E-Klasse-Taxi.
const CAR_DIMS := {
	"kompakt": [4.28, 1.79, 1.46], "limousine": [4.76, 1.83, 1.45], "kombi": [4.69, 1.83, 1.48],
	"suv": [4.51, 1.84, 1.67], "transporter": [5.3, 2.0, 2.35], "taxi": [4.92, 1.85, 1.47],
	"linienbus": [12.0, 2.55, 3.1],
}
## Form je Typ: Haube, Frontscheibe (waagrecht), Gürtellinie, Nasenhöhe, Boden, Radradius, Überhang vorn, Radstand, Heckform
const CAR_FORM := {
	"kompakt": {"hood": 0.98, "ws": 0.82, "belt": 0.97, "nose": 0.74, "bot": 0.19, "wr": 0.315, "fo": 0.86, "wb": 2.64, "rear": "heck"},
	"limousine": {"hood": 1.2, "ws": 0.9, "belt": 0.96, "nose": 0.72, "bot": 0.18, "wr": 0.325, "fo": 0.9, "wb": 2.79, "rear": "stufe"},
	"kombi": {"hood": 1.12, "ws": 0.86, "belt": 0.97, "nose": 0.73, "bot": 0.18, "wr": 0.32, "fo": 0.92, "wb": 2.69, "rear": "kombi"},
	"suv": {"hood": 1.05, "ws": 0.74, "belt": 1.1, "nose": 0.88, "bot": 0.24, "wr": 0.36, "fo": 0.9, "wb": 2.68, "rear": "suv"},
	"transporter": {"hood": 0.62, "ws": 0.62, "belt": 1.12, "nose": 0.98, "bot": 0.3, "wr": 0.34, "fo": 0.95, "wb": 3.4, "rear": "kasten"},
	"taxi": {"hood": 1.25, "ws": 0.92, "belt": 0.96, "nose": 0.72, "bot": 0.18, "wr": 0.33, "fo": 0.88, "wb": 2.94, "rear": "stufe"},
}


## Höhe der Rücklichter (für die leuchtenden Bremslichter in Factory.make_car).
static func car_light_y(kind: String) -> float:
	if kind == "linienbus":
		return 0.84
	return float(CAR_FORM.get(kind, CAR_FORM["kompakt"])["belt"]) - 0.1


## lod: vereinfachte Fassung für eingebackene, geparkte Autos (Parkhaus, Parkplatz).
static func car_mesh(kind: String, color: Color, lod: bool = false) -> ArrayMesh:
	var key := "car_%s_%s_%s" % [kind, color.to_html(), lod]
	if _cache.has(key):
		return _cache[key]
	var d: Array = CAR_DIMS[kind]
	var f: Dictionary = CAR_FORM[kind]
	var L: float = d[0]
	var W: float = d[1]
	var H: float = d[2]
	var hl := L * 0.5
	var hw := W * 0.5
	var bot: float = f["bot"]
	var belt: float = f["belt"]
	var nose: float = f["nose"]
	var rear: String = f["rear"]
	var body := color
	if kind == "taxi":
		body = Color(0.94, 0.89, 0.68)
	var zf := -hl
	var ze := hl
	var zws := zf + float(f["hood"])
	var zrf := zws + float(f["ws"])
	var trim := Color(0.09, 0.09, 0.1)
	var eu := 6.0 if rear == "kasten" else 3.3
	var tumble := 0.35 if rear == "kasten" else 1.0
	var st := []
	st.append([zf - 0.035, bot + 0.2, nose - 0.17, nose - 0.11, hw - 0.3, hw - 0.42, 3.0, 4.0])
	st.append([zf, bot + 0.12, nose - 0.15, nose - 0.04, hw - 0.12, hw - 0.24, 3.2, 4.0])
	st.append([zf + 0.09, bot + 0.04, nose - 0.08, nose + 0.01, hw - 0.04, hw - 0.16, 3.2, 4.4])
	st.append([zf + 0.38, bot, nose - 0.02, nose + 0.07, hw - 0.01, hw - 0.12, 3.2, 5.0])
	st.append([zws - 0.05, bot, belt - 0.03, belt + 0.03, hw, hw - 0.1, 3.2, 5.0])
	var zrr := 0.0
	var glass_end := 0.0
	var trunk_z := ze
	match rear:
		"heck":
			zrr = ze - 0.42
			glass_end = ze - 0.1
		"stufe":
			trunk_z = ze - 0.62
			zrr = trunk_z - 0.78
			glass_end = trunk_z - 0.04
		"kombi":
			zrr = ze - 0.2
			glass_end = ze - 0.07
		"suv":
			zrr = ze - 0.32
			glass_end = ze - 0.08
		"kasten":
			zrr = ze - 0.06
			glass_end = zrf + 0.75
	st.append([zrf, bot, belt, H - 0.02, hw, hw - 0.27 * tumble, eu, 5.0])
	st.append([lerpf(zrf, zrr, 0.5), bot, belt + 0.01, H, hw, hw - 0.26 * tumble, eu, 5.0])
	st.append([zrr, bot, belt + 0.02, H - 0.04, hw, hw - 0.27 * tumble, eu, 5.0])
	match rear:
		"heck":
			st.append([ze - 0.1, bot + 0.02, belt + 0.02, belt + 0.26, hw - 0.03, hw - 0.22, 3.4, 5.0])
			st.append([ze, bot + 0.09, belt - 0.05, belt + 0.14, hw - 0.09, hw - 0.26, 3.4, 4.5])
		"stufe":
			st.append([trunk_z, bot, belt + 0.03, belt + 0.11, hw - 0.01, hw - 0.14, 3.4, 5.0])
			st.append([ze - 0.1, bot + 0.03, belt, belt + 0.08, hw - 0.04, hw - 0.16, 3.4, 5.0])
			st.append([ze, bot + 0.1, belt - 0.07, belt + 0.02, hw - 0.1, hw - 0.22, 3.4, 4.5])
		"kombi", "suv":
			st.append([ze - 0.07, bot + 0.02, belt, H - 0.12, hw - 0.03, hw - 0.28, 3.4, 5.0])
			st.append([ze, bot + 0.09, belt - 0.04, H - 0.17, hw - 0.09, hw - 0.32, 3.4, 4.5])
		"kasten":
			st.append([ze, bot + 0.04, belt, H - 0.05, hw - 0.03, hw - 0.1, eu, 6.0])
	# kleine Endstation: das Heck rundet sich zur Mitte, die Kappe bleibt klein
	var last_st: Array = st[st.size() - 1]
	st.append([ze + 0.03, float(last_st[1]) + 0.06, float(last_st[2]), float(last_st[3]) - 0.05, float(last_st[4]) - 0.2, float(last_st[5]) - 0.12, float(last_st[6]), float(last_st[7])])
	var wz := [zf + float(f["fo"]), zf + float(f["fo"]) + float(f["wb"])]
	var wr: float = f["wr"]
	var zb_pillar := lerpf(zrf, zrr, 0.42) if rear != "kasten" else zrf + 0.78
	var seams := [zws + 0.02, zb_pillar - 0.05, float(wz[1]) - wr - 0.12]
	if rear == "kasten":
		seams = [zws + 0.02, zrf + 0.8, zrf + 2.0]
	var cuts := [zws + 0.03, zrf, glass_end, zb_pillar - 0.05, zb_pillar + 0.05, ze - 0.24, zf + 0.24, trunk_z]
	for sz: float in seams:
		cuts.append(sz - 0.012)
		cuts.append(sz + 0.012)
	var col_fn := func(m: Vector3, p: Array) -> Color:
		var sh: float = p[2]
		var top: float = p[3]
		var ax := absf(m.x)
		var u := (m.y - sh) / maxf(top - sh, 0.01)
		var wl := lerpf(float(p[4]), float(p[5]), clampf(u, 0.0, 1.0))
		var rx := ax / maxf(wl, 0.01)
		# Radkästen
		for z0: float in wz:
			if Vector2(m.z - z0, m.y - wr).length() < wr + 0.07 and ax > hw * 0.72:
				return Color(0.05, 0.05, 0.055)
		# Schweller, Stoßfänger unten, beim SUV Beplankung
		if m.y < bot + (0.17 if kind == "suv" else 0.09):
			return trim
		if m.y > sh + 0.035:
			# Scheiben
			if m.z > zws + 0.03 and m.z < zrf and rx < 0.8 and u > 0.12:
				return GLASS
			var side_win := m.z > zws + 0.1 and m.z < glass_end and rx > 0.74 and u > 0.08 and u < 0.84
			if rear == "kasten":
				side_win = m.z > zws + 0.15 and m.z < glass_end and rx > 0.74 and u > 0.08 and u < 0.8
			if side_win:
				if absf(m.z - zb_pillar) < 0.05 and rear != "kasten":
					return trim
				if rear == "stufe" and m.z > zrr - 0.1:
					return body
				if (rear == "kombi" or rear == "suv") and absf(m.z - (zrr - 0.55)) < 0.06:
					return trim
				return GLASS
			if m.z > zrr + 0.02 and m.z < glass_end and rx < 0.78 and u > 0.12 and u < 0.95 and rear != "kasten":
				return GLASS
			return body
		# Front: Scheinwerfer, Blinker, Grill, Kennzeichen
		var fx := ax / hw
		if m.z < zf + 0.24:
			if m.y > nose - 0.17 and m.y < nose - 0.04 and fx > 0.52 and fx < 0.92:
				return Color(0.8, 0.84, 0.88) if fx < 0.84 else Color(0.95, 0.6, 0.15)
			if m.y > bot + 0.14 and m.y < nose - 0.1 and fx < 0.42:
				if absf(m.y - (bot + 0.3)) < 0.07 and fx < 0.25:
					return Color(0.92, 0.92, 0.9)
				return Color(0.07, 0.07, 0.08)
			if m.y < bot + 0.14:
				return trim
		# Heck: Rückleuchten, Kennzeichen
		if m.z > ze - 0.24:
			if m.y > belt - 0.21 and m.y < belt + 0.03 and fx > 0.52:
				return Color(0.72, 0.06, 0.05)
			if absf(m.y - (bot + 0.36)) < 0.07 and fx < 0.25:
				return Color(0.92, 0.92, 0.9)
			if m.y < bot + 0.16:
				return trim
		# Türfugen
		for sz: float in seams:
			if absf(m.z - sz) < 0.013 and m.y > bot + 0.1 and ax > hw * 0.7:
				return body.darkened(0.4)
		return body
	var k := Kit.new()
	_shell(k, st, col_fn, 20 if lod else 36, 0.3 if lod else 0.12, cuts)
	if lod:
		for z0: float in wz:
			for sx: float in [-1.0, 1.0]:
				k.cyl(Vector3(sx * (hw - 0.24), wr, z0), Vector3(sx * (hw - 0.03), wr, z0), wr, wr, TYRE, 10, true, METAL)
		var lm := k.commit()
		_cache[key] = lm
		return lm
	# Räder
	for z0: float in wz:
		for sx: float in [-1.0, 1.0]:
			var rim := Color(0.78, 0.79, 0.8) if kind != "transporter" else Color(0.6, 0.61, 0.62)
			_wheel(k, Vector3(sx * (hw - 0.14), wr, z0), wr, 0.21, sx, rim, 5 if kind != "transporter" else 0)
	# Außenspiegel, Türgriffe
	for sx: float in [-1.0, 1.0]:
		var mz := zws + 0.22
		var mx := _st_point(_st_at(st, mz), PI * 0.5 - 0.25).x
		k.box(Vector3(sx * (mx - 0.02), belt + 0.05, mz - 0.03), Vector3(sx * (mx + 0.08), belt + 0.09, mz + 0.03), trim)
		k.box(Vector3(sx * (mx + 0.06), belt + 0.04, mz - 0.05), Vector3(sx * (mx + 0.2), belt + 0.15, mz + 0.07), body)
		k.box(Vector3(sx * (mx + 0.07), belt + 0.05, mz + 0.07), Vector3(sx * (mx + 0.19), belt + 0.14, mz + 0.075), Color(0.55, 0.6, 0.65))
		var hz := [zws + 0.55, zb_pillar + 0.45] if rear != "kasten" else [zws + 0.55]
		for z0: float in hz:
			var p := _st_at(st, z0)
			var x := _st_point(p, PI * 0.5 + 0.15).x
			k.box(Vector3(sx * (x - 0.01), belt - 0.11, z0 - 0.09), Vector3(sx * (x + 0.012), belt - 0.08, z0 + 0.09), body.darkened(0.25))
	if kind == "taxi":
		k.soft_box(Vector3(-0.3, H - 0.03, -0.15), Vector3(0.3, H + 0.16, 0.05), 0.04, Color(0.98, 0.9, 0.45, 0.3), 8, 3)
		for sz: float in [-1.0, 1.0]:
			PixelFont.draw(k, "TAXI", Vector3(0, H + 0.065, -0.05 + sz * 0.101), Vector3(sz, 0, 0), Vector3.UP, Vector3(0, 0, sz), 0.017, Color(0.08, 0.08, 0.08))
	if kind == "suv":
		for sx: float in [-1.0, 1.0]:
			k.box(Vector3(sx * (hw - 0.34) - 0.025, H - 0.01, zrf + 0.15), Vector3(sx * (hw - 0.34) + 0.025, H + 0.05, zrr - 0.05), Color(0.25, 0.25, 0.26))
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh


## Stadtbus nach dem Vorbild eines 12-m-Niederflurbusses (Front -Z): glatte Hülle, Fensterband mit
## schwarzen Holmen, drei Doppeltüren rechts, Zielanzeige vorn, Klimaanlage und Dachluken.
static func city_bus_mesh(livery: Color) -> ArrayMesh:
	var key := "linienbus_" + livery.to_html()
	if _cache.has(key):
		return _cache[key]
	var k := Kit.new()
	var white := Color(0.94, 0.94, 0.92)
	var dark := Color(0.1, 0.1, 0.11)
	var hl := 6.0
	var hw := 1.275
	var st := [
		[-hl - 0.05, 0.42, 1.4, 2.92, hw - 0.14, hw - 0.18, 8.0, 8.0],
		[-hl + 0.02, 0.32, 1.4, 3.0, hw - 0.04, hw - 0.08, 8.0, 8.0],
		[-hl + 0.18, 0.3, 1.4, 3.05, hw, hw - 0.04, 8.0, 8.0],
		[hl - 0.18, 0.3, 1.4, 3.05, hw, hw - 0.04, 8.0, 8.0],
		[hl - 0.02, 0.32, 1.4, 3.0, hw - 0.04, hw - 0.08, 8.0, 8.0],
		[hl + 0.05, 0.42, 1.4, 2.92, hw - 0.14, hw - 0.18, 8.0, 8.0],
	]
	var axles := [-3.3, 2.58]
	var cuts := []
	for dz: float in CITY_BUS_DOORS:
		cuts.append(dz - 0.68)
		cuts.append(dz + 0.68)
	var posts := []
	var z := -4.2
	while z < 5.6:
		var free := true
		for dz: float in CITY_BUS_DOORS:
			free = free and absf(z - dz) > 0.9
		if free:
			posts.append(z)
			cuts.append(z - 0.05)
			cuts.append(z + 0.05)
		z += 1.45
	var col_fn := func(m: Vector3, p: Array) -> Color:
		var ax := absf(m.x)
		for az: float in axles:
			if Vector2(m.z - az, m.y - 0.5).length() < 0.62 and ax > hw * 0.8:
				return Color(0.05, 0.05, 0.055)
		if m.y < 0.4:
			return dark
		# vorn: Scheibe bis unten, Zielanzeige, Scheinwerfer
		if m.z < -hl + 0.1:
			if m.y > 2.66 and m.y < 2.95 and ax < hw - 0.15:
				return Color(0.05, 0.05, 0.05)
			if m.y > 0.95 and m.y < 2.62:
				return GLASS
			if m.y > 0.55 and m.y < 0.75 and ax > hw - 0.45:
				return LAMP
			return livery
		# hinten: Heckscheibe, Motorklappe mit Gitter, Rückleuchten
		if m.z > hl - 0.1:
			if m.y > 1.95 and m.y < 2.65 and ax < hw - 0.12:
				return GLASS
			if m.y > 0.55 and m.y < 1.4 and ax > hw - 0.3:
				return Color(0.72, 0.06, 0.05)
			if m.y > 0.6 and m.y < 1.5 and ax < 0.8 and int(m.y * 12.0) % 2 == 0:
				return livery.darkened(0.3)
			return livery
		# Türen rechts (die Flügel sind eigene Knoten)
		if m.x > 0.0 and ax > hw * 0.85:
			for dz: float in CITY_BUS_DOORS:
				if absf(m.z - dz) < 0.68 and m.y < 2.62:
					return Color(0.2, 0.21, 0.23)
		if m.y > 2.98:
			return white
		if m.y > 1.12 and m.y < 2.72 and ax > hw * 0.85:
			for pz: float in posts:
				if absf(m.z - pz) < 0.05:
					return dark
			if m.z < -hl + 0.35 or m.z > hl - 0.3:
				return livery
			return GLASS
		if m.y > 2.72:
			return white
		return livery
	_shell(k, st, col_fn, 40, 0.3, cuts, true, Vector3.ZERO, livery)
	# Stirnseiten: Frontscheibe, Zielanzeige, Scheinwerfer; Heckscheibe, Rückleuchten, Motorklappe
	var zf := -hl - 0.055
	var zr := hl + 0.055
	k.panel(Vector3(0, 1.8, zf), Vector3(1.07, 0, 0), Vector3(0, 0.82, 0), GLASS, Vector3(0, 0, -1))
	k.panel(Vector3(0, 2.79, zf), Vector3(0.98, 0, 0), Vector3(0, 0.12, 0), Color(0.05, 0.05, 0.05), Vector3(0, 0, -1))
	k.panel(Vector3(0, 0.85, zf), Vector3(0.45, 0, 0), Vector3(0, 0.08, 0), dark, Vector3(0, 0, -1))
	k.panel(Vector3(0, 2.3, zr), Vector3(1.0, 0, 0), Vector3(0, 0.32, 0), GLASS, Vector3(0, 0, 1))
	for i in range(6):
		k.panel(Vector3(0, 0.75 + float(i) * 0.13, zr), Vector3(0.7, 0, 0), Vector3(0, 0.03, 0), livery.darkened(0.35), Vector3(0, 0, 1))
	for sx: float in [-1.0, 1.0]:
		k.panel(Vector3(sx * 0.88, 0.62, zf), Vector3(0.2, 0, 0), Vector3(0, 0.07, 0), LAMP, Vector3(0, 0, -1))
		k.panel(Vector3(sx * 0.98, 1.1, zr), Vector3(0.09, 0, 0), Vector3(0, 0.36, 0), Color(0.72, 0.06, 0.05), Vector3(0, 0, 1))
	# Räder: vorn einfach, hinten Zwillingsräder
	for az: float in axles:
		for sx: float in [-1.0, 1.0]:
			_wheel(k, Vector3(sx * (hw - 0.2), 0.5, az), 0.5, 0.3, sx, Color(0.75, 0.76, 0.78), 0)
	# Dach: Klimaanlage, Luken, Rammschutzspiegel vorn
	k.soft_box(Vector3(-0.95, 3.0, -2.2), Vector3(0.95, 3.32, 0.9), 0.12, Color(0.84, 0.85, 0.86), 12, 6)
	for i in range(3):
		k.box(Vector3(-0.85 + float(i) * 0.62, 3.32, -1.6), Vector3(-0.35 + float(i) * 0.62, 3.34, 0.3), Color(0.55, 0.56, 0.58))
	for lz: float in [2.2, 4.2]:
		k.box(Vector3(-0.4, 3.04, lz - 0.35), Vector3(0.4, 3.1, lz + 0.35), Color(0.4, 0.42, 0.45))
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(minf(sx * (hw - 0.1), sx * (hw + 0.28)), 2.84, -hl + 0.18), Vector3(maxf(sx * (hw - 0.1), sx * (hw + 0.28)), 2.88, -hl + 0.24), dark)
		k.box(Vector3(minf(sx * (hw + 0.22), sx * (hw + 0.32)), 2.2, -hl + 0.12), Vector3(maxf(sx * (hw + 0.22), sx * (hw + 0.32)), 2.86, -hl + 0.3), dark)
	PixelFont.draw(k, "FLUGHAFEN", Vector3(0, 2.8, -hl - 0.062), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.026, Color(0.98, 0.65, 0.15, 0.3))
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh


# ================================================================== Bodenfahrzeuge (GSE)

## Koffer (weiß, die Farbe kommt pro Exemplar aus dem MultiMesh): Schale, Griff, Rollen.
static func bag_mesh() -> ArrayMesh:
	if _cache.has("bag"):
		return _cache["bag"]
	var k := Kit.new()
	var w := Color(1, 1, 1)
	k.soft_box(Vector3(-0.22, 0.04, -0.34), Vector3(0.22, 0.5, 0.34), 0.05, w, 12, 6)
	k.box(Vector3(-0.23, 0.2, -0.35), Vector3(0.23, 0.24, 0.35), w.darkened(0.25))
	k.box(Vector3(-0.08, 0.5, -0.03), Vector3(0.08, 0.55, 0.03), Color(0.12, 0.12, 0.12))
	for sx: float in [-0.16, 0.16]:
		k.box(Vector3(sx - 0.03, 0.0, 0.26), Vector3(sx + 0.03, 0.05, 0.32), Color(0.1, 0.1, 0.1))
	var m := k.commit()
	_cache["bag"] = m
	return m


## Koffer in fester Farbe (für die Ladung auf den Gepäckwagen).
static func bag_mesh_col(c: Color) -> ArrayMesh:
	var key := "bag_" + c.to_html()
	if _cache.has(key):
		return _cache[key]
	var k := Kit.new()
	k.soft_box(Vector3(-0.22, 0.0, -0.32), Vector3(0.22, 0.62, 0.32), 0.05, c, 12, 6)
	k.box(Vector3(-0.23, 0.28, -0.33), Vector3(0.23, 0.31, 0.33), c.darkened(0.25))
	k.box(Vector3(-0.07, 0.62, -0.03), Vector3(0.07, 0.67, 0.03), Color(0.12, 0.12, 0.12))
	var m := k.commit()
	_cache[key] = m
	return m


## Teile der Bodenfahrzeuge, die sich bewegen (Förderband, Catering-Kasten, Schere).
## Alle mit Front -Z.
static func gse_part(kind: String) -> ArrayMesh:
	var key := "part_" + kind
	if _cache.has(key):
		return _cache[key]
	var k := Kit.new()
	k.bevel = 0.05
	match kind:
		"band":
			# Förderband: Drehpunkt hinten bei z = 0, 7,6 m nach vorn (-Z), 0,8 m breit
			k.box(Vector3(-0.42, -0.12, -7.6), Vector3(0.42, 0.06, 0.2), Color(0.86, 0.69, 0.22))
			k.box(Vector3(-0.36, 0.06, -7.55), Vector3(0.36, 0.1, 0.15), Color(0.12, 0.12, 0.13))
			for i in range(16):
				var z := -7.4 + float(i) * 0.48
				k.box(Vector3(-0.36, 0.1, z), Vector3(0.36, 0.115, z + 0.06), Color(0.2, 0.2, 0.21))
			for sx: float in [-1.0, 1.0]:
				k.box(Vector3(sx * 0.42 - 0.03, 0.06, -7.6), Vector3(sx * 0.42 + 0.03, 0.32, 0.2), METAL)
				for i in range(5):
					var z := -7.2 + float(i) * 1.7
					k.box(Vector3(sx * 0.44 - 0.025, 0.32, z), Vector3(sx * 0.44 + 0.025, 1.05, z + 0.05), Color(0.85, 0.7, 0.2))
				k.box(Vector3(sx * 0.44 - 0.03, 1.02, -7.25), Vector3(sx * 0.44 + 0.03, 1.07, -0.2), Color(0.85, 0.7, 0.2))
			# Gummipuffer vorn
			k.box(Vector3(-0.45, -0.1, -7.75), Vector3(0.45, 0.12, -7.6), Color(0.1, 0.1, 0.1))
		"kasten":
			# Catering-Kasten, Unterkante bei y = 0, mit Rolltor hinten und Firmenstreifen
			k.box(Vector3(-1.25, 0.0, -1.8), Vector3(1.25, 2.4, 3.7), Color(0.93, 0.93, 0.91))
			k.box(Vector3(-1.27, 1.0, -1.8), Vector3(1.27, 1.3, 3.7), Color(0.2, 0.4, 0.65))
			k.box(Vector3(-1.0, 0.2, 3.7), Vector3(1.0, 2.2, 3.74), Color(0.7, 0.71, 0.72))
			for i in range(9):
				k.box(Vector3(-1.0, 0.25 + float(i) * 0.22, 3.74), Vector3(1.0, 0.27 + float(i) * 0.22, 3.76), Color(0.6, 0.61, 0.62))
			k.box(Vector3(-1.3, -0.12, -1.85), Vector3(1.3, 0.0, 3.75), DARK_METAL)
			k.box(Vector3(-0.3, 2.4, 0.5), Vector3(0.3, 2.55, 1.0), Color(0.98, 0.55, 0.08))
		"buehne":
			# ausfahrbare Brücke vorn am Kasten (zeigt nach -Z), Geländer seitlich
			k.box(Vector3(-0.8, -0.1, -3.0), Vector3(0.8, 0.0, 0.0), Color(0.55, 0.56, 0.58))
			for sx: float in [-1.0, 1.0]:
				k.box(Vector3(sx * 0.8 - 0.03, 0.0, -2.9), Vector3(sx * 0.8 + 0.03, 1.05, -2.85), Color(0.85, 0.7, 0.2))
				k.box(Vector3(sx * 0.8 - 0.03, 1.0, -2.9), Vector3(sx * 0.8 + 0.03, 1.06, 0.0), Color(0.85, 0.7, 0.2))
			k.box(Vector3(-0.85, -0.15, -3.1), Vector3(0.85, 0.02, -3.0), Color(0.1, 0.1, 0.1))
		"schere":
			# Scherenhub, Höhe 1 (wird skaliert)
			for sx: float in [-0.95, 0.95]:
				for i in range(2):
					var a := Vector3(sx, 0.0, -1.4 if i == 0 else 3.2)
					var b := Vector3(sx, 1.0, 3.2 if i == 0 else -1.4)
					var d := b - a
					k.box(Vector3(-0.05, -0.05, -d.length() * 0.5), Vector3(0.05, 0.05, d.length() * 0.5), METAL,
						Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), (a + b) * 0.5))
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh


static func gse_mesh(kind: String) -> ArrayMesh:
	var key := "gse_" + kind
	if _cache.has(key):
		return _cache[key]
	var k := Kit.new()
	k.bevel = 0.05
	var cab := YELLOW
	match kind:
		"tank":
			# Flugfeldtankwagen: elliptischer Tank mit Laufsteg und Geländer, Schlauchtrommel und Zapfstand hinten
			_truck_cab(k, Color(0.93, 0.93, 0.91), -4.7, 2.3)
			k.box(Vector3(-0.55, 0.5, -2.7), Vector3(0.55, 0.85, 4.6), DARK_METAL)
			var band := Color(0.16, 0.32, 0.58)
			var tst := [
				[-2.42, 1.15, 1.95, 2.72, 0.7, 0.62, 2.2, 2.2],
				[-2.28, 0.95, 1.95, 2.92, 1.06, 0.98, 2.6, 2.6],
				[-2.0, 0.9, 1.95, 2.98, 1.15, 1.06, 2.8, 2.8],
				[3.7, 0.9, 1.95, 2.98, 1.15, 1.06, 2.8, 2.8],
				[3.98, 0.95, 1.95, 2.92, 1.06, 0.98, 2.6, 2.6],
				[4.12, 1.15, 1.95, 2.72, 0.7, 0.62, 2.2, 2.2],
			]
			var tank_col := func(m: Vector3, _p: Array) -> Color:
				if m.y > 1.62 and m.y < 1.8:
					return band
				if m.y > 1.82 and m.y < 1.86:
					return Color(0.9, 0.7, 0.15)
				return Color(0.95, 0.95, 0.93)
			_shell(k, tst, tank_col, 36, 0.3)
			for sx: float in [-1.0, 1.0]:
				PixelFont.draw(k, "JET A-1", Vector3(sx * 1.16, 2.2, 0.8), Vector3(0, 0, -sx), Vector3.UP, Vector3(sx, 0, 0), 0.07, band)
				# Kotflügel und Seitenschutz
				k.box(Vector3(minf(sx * 0.9, sx * 1.22), 1.0, -1.9), Vector3(maxf(sx * 0.9, sx * 1.22), 1.06, 4.2), Color(0.25, 0.25, 0.27))
				k.box(Vector3(minf(sx * 1.1, sx * 1.2), 0.45, 0.2), Vector3(maxf(sx * 1.1, sx * 1.2), 0.6, 1.0), Color(0.9, 0.7, 0.15))
			# Laufsteg und Klappgeländer
			k.box(Vector3(-0.45, 2.98, -1.5), Vector3(0.45, 3.04, 3.4), Color(0.45, 0.46, 0.48))
			for sx: float in [-1.0, 1.0]:
				k.cyl(Vector3(sx * 0.45, 3.5, -1.4), Vector3(sx * 0.45, 3.5, 3.3), 0.025, 0.025, Color(0.9, 0.7, 0.15), 6)
				for pz: float in [-1.4, 0.0, 1.6, 3.3]:
					k.cyl(Vector3(sx * 0.45, 3.0, pz), Vector3(sx * 0.45, 3.5, pz), 0.02, 0.02, Color(0.9, 0.7, 0.15), 5, false)
			for dz: float in [-0.6, 1.2, 2.8]:
				k.cyl(Vector3(0, 2.97, dz), Vector3(0, 3.1, dz), 0.25, 0.25, METAL, 12)
			# Heck: Zapfstand, Schlauchtrommel, Leiter, Gefahrguttafel
			k.soft_box(Vector3(-1.1, 0.6, 4.15), Vector3(1.1, 1.75, 4.75), 0.06, Color(0.82, 0.83, 0.84), 12, 4)
			k.cyl(Vector3(-0.7, 1.2, 4.8), Vector3(0.5, 1.2, 4.8), 0.38, 0.38, Color(0.15, 0.15, 0.16), 14, true, Color(0.75, 0.1, 0.08))
			k.box(Vector3(-0.3, 0.7, 4.75), Vector3(0.3, 0.92, 4.78), Color(0.95, 0.5, 0.1))
			for i in range(6):
				k.box(Vector3(0.75, 0.75 + float(i) * 0.38, 4.2), Vector3(1.05, 0.78 + float(i) * 0.38, 4.28), METAL)
			for sx: float in [0.75, 1.05]:
				k.box(Vector3(sx - 0.02, 0.7, 4.2), Vector3(sx + 0.02, 3.05, 4.26), METAL)
			for sx: float in [-1.0, 1.0]:
				k.box(Vector3(minf(sx * 0.8, sx * 1.1), 1.8, 4.7), Vector3(maxf(sx * 0.8, sx * 1.1), 1.95, 4.76), Color(0.75, 0.08, 0.06))
			_wheels(k, 1.2, 0.48, [-3.6, 1.6, 3.0])
		"catering":
			_truck_cab(k, cab, -3.9, 2.2)
			k.box(Vector3(-1.1, 0.55, -1.7), Vector3(1.1, 0.8, 3.6), DARK_METAL)
			# Scherenhub: gekreuzte Streben unter dem Kasten
			for sx: float in [-0.95, 0.95]:
				for ang: float in [0.36, -0.36]:
					k.box(Vector3(-0.05, -0.06, -2.6), Vector3(0.05, 0.06, 2.6), METAL, Transform3D(Basis(Vector3(1, 0, 0), ang), Vector3(sx, 1.85, 0.95)))
			k.soft_box(Vector3(-1.25, 2.9, -1.8), Vector3(1.25, 5.3, 3.7), 0.12, Color(0.92, 0.92, 0.9), 12, 6)
			k.box(Vector3(-1.27, 3.9, -1.8), Vector3(1.27, 4.2, 3.7), Color(0.2, 0.4, 0.65))
			k.box(Vector3(-1.0, 2.9, -2.6), Vector3(1.0, 3.0, -1.8), METAL)
			_wheels(k, 1.15, 0.45, [-3.0, 2.6])
		"schlepper":
			_tug(k)
		"bandlader":
			# Förderbandwagen: flaches Fahrgestell, Fahrersitz rechts, Band als eigenes Teil (Drehpunkt z = 2,6)
			var bst := [
				[-4.26, 0.42, 0.62, 0.8, 0.85, 0.8, 4.0, 5.0],
				[-4.12, 0.35, 0.62, 0.86, 0.95, 0.9, 6.0, 6.0],
				[3.2, 0.35, 0.62, 0.86, 0.95, 0.9, 6.0, 6.0],
				[3.34, 0.42, 0.62, 0.8, 0.85, 0.8, 4.0, 5.0],
			]
			var loader_col := func(m: Vector3, _p: Array) -> Color:
				if m.y > 0.6 and m.y < 0.7:
					return DARK_METAL
				for wz: float in [-3.0, 2.2]:
					if Vector2(m.z - wz, m.y - 0.38).length() < 0.46 and absf(m.x) > 0.75:
						return Color(0.06, 0.06, 0.07)
				return YELLOW
			_shell(k, bst, loader_col, 32, 0.3)
			k.box(Vector3(0.15, 0.85, 1.6), Vector3(0.95, 1.05, 3.2), DARK_METAL)
			k.box(Vector3(0.3, 1.05, 2.4), Vector3(0.85, 1.6, 2.6), Color(0.15, 0.15, 0.16))
			k.box(Vector3(0.3, 1.05, 1.9), Vector3(0.85, 1.15, 2.6), Color(0.15, 0.15, 0.16))
			k.cyl(Vector3(0.55, 1.4, 1.75), Vector3(0.55, 1.4, 1.8), 0.22, 0.22, Color(0.1, 0.1, 0.1), 10)
			for p: Vector3 in [Vector3(0.2, 1.05, 1.65), Vector3(0.9, 1.05, 1.65), Vector3(0.2, 1.05, 3.1), Vector3(0.9, 1.05, 3.1)]:
				k.box(p - Vector3(0.03, 0, 0.03), p + Vector3(0.03, 1.2, 0.03), DARK_METAL)
			k.box(Vector3(0.15, 2.25, 1.6), Vector3(0.95, 2.32, 3.2), YELLOW)
			# Hubzylinder unter dem Band
			k.cyl(Vector3(0, 0.85, -1.2), Vector3(0, 1.0, -1.2), 0.12, 0.12, METAL, 8)
			for sx: float in [-1.0, 1.0]:
				k.box(Vector3(sx * 0.8 - 0.2, 0.75, -4.25), Vector3(sx * 0.8 + 0.2, 0.9, -4.2), LAMP)
			k.cyl(Vector3(0.9, 2.32, 2.4), Vector3(0.9, 2.5, 2.4), 0.11, 0.09, Color(0.98, 0.55, 0.08), 8)
			_wheels(k, 0.95, 0.38, [-3.0, 2.2])
		"catering_basis":
			# Fahrgestell mit Kabine vorn; Kasten, Schere und Bühne kommen als eigene Teile dazu
			_truck_cab(k, Color(0.93, 0.93, 0.91), -3.9, 1.85)
			k.box(Vector3(-1.1, 0.55, -1.9), Vector3(1.1, 0.8, 3.6), DARK_METAL)
			k.box(Vector3(-1.15, 0.8, -1.5), Vector3(1.15, 0.92, 3.4), Color(0.4, 0.41, 0.43))
			_wheels(k, 1.15, 0.45, [-3.0, 2.6])
		"gpu":
			# Bodenstromaggregat auf Anhänger: Generatorkasten, Kabeltrommel, Deichsel
			k.box(Vector3(-0.75, 0.45, -1.2), Vector3(0.75, 0.6, 1.3), DARK_METAL)
			k.soft_box(Vector3(-0.7, 0.6, -1.1), Vector3(0.7, 1.55, 1.2), 0.08, Color(0.88, 0.89, 0.86), 12, 6)
			k.box(Vector3(-0.71, 0.75, -0.6), Vector3(0.71, 1.35, 0.6), Color(0.3, 0.32, 0.34))
			for i in range(6):
				k.box(Vector3(-0.72, 0.8 + float(i) * 0.09, -0.55), Vector3(0.72, 0.83 + float(i) * 0.09, 0.55), Color(0.5, 0.51, 0.52))
			k.cyl(Vector3(-0.45, 1.75, 0.5), Vector3(0.45, 1.75, 0.5), 0.3, 0.3, Color(0.15, 0.15, 0.16), 12)
			k.box(Vector3(-0.06, 0.4, -2.3), Vector3(0.06, 0.48, -1.2), DARK_METAL)
			k.box(Vector3(-0.3, 1.55, -1.1), Vector3(0.3, 1.6, -0.7), Color(0.85, 0.7, 0.2))
			_wheels(k, 0.8, 0.3, [0.0])
		"gepaeckschlepper":
			# Gepäckschlepper (Front -Z), Kupplung hinten bei z = 1,5
			var gst := [
				[-1.47, 0.42, 0.62, 0.86, 0.6, 0.52, 3.5, 5.0],
				[-1.38, 0.32, 0.66, 0.98, 0.71, 0.62, 4.0, 6.0],
				[-0.5, 0.3, 0.66, 1.06, 0.72, 0.64, 4.5, 6.0],
				[-0.36, 0.3, 0.66, 0.88, 0.72, 0.68, 5.0, 6.0],
				[1.36, 0.3, 0.66, 0.88, 0.72, 0.68, 5.0, 6.0],
				[1.42, 0.36, 0.66, 0.84, 0.66, 0.62, 5.0, 6.0],
			]
			var tractor_col := func(m: Vector3, _p: Array) -> Color:
				if m.y < 0.42:
					return Color(0.15, 0.15, 0.16)
				if m.z < -1.3 and m.y > 0.66 and m.y < 0.78 and absf(m.x) > 0.35:
					return LAMP
				if m.z < -1.3 and m.y > 0.5 and m.y < 0.85 and absf(m.x) < 0.25:
					return Color(0.15, 0.15, 0.16)
				for wz: float in [-0.9, 0.9]:
					if Vector2(m.z - wz, m.y - 0.33).length() < 0.42 and absf(m.x) > 0.55:
						return Color(0.06, 0.06, 0.07)
				return YELLOW
			_shell(k, gst, tractor_col, 32, 0.15)
			# Lenkrad und Sitzlehne
			k.cyl(Vector3(0, 1.15, -0.45), Vector3(0, 1.3, -0.35), 0.03, 0.03, Color(0.15, 0.15, 0.15), 6)
			k.cyl(Vector3(0, 1.3, -0.37), Vector3(0, 1.33, -0.33), 0.18, 0.18, Color(0.12, 0.12, 0.12), 12)
			k.box(Vector3(-0.65, 0.85, -0.3), Vector3(0.65, 1.2, 1.2), Color(0.15, 0.15, 0.16))
			k.box(Vector3(-0.3, 1.2, 0.7), Vector3(0.3, 1.6, 0.9), Color(0.15, 0.15, 0.16))
			for p: Vector3 in [Vector3(-0.66, 0.85, -0.35), Vector3(0.6, 0.85, -0.35), Vector3(-0.66, 0.85, 1.15), Vector3(0.6, 0.85, 1.15)]:
				k.box(p, p + Vector3(0.06, 1.15, 0.06), DARK_METAL)
			k.box(Vector3(-0.72, 2.0, -0.4), Vector3(0.72, 2.07, 1.25), YELLOW)
			k.box(Vector3(-0.08, 0.35, 1.4), Vector3(0.08, 0.45, 1.6), DARK_METAL)
			k.cyl(Vector3(0, 2.07, 0.4), Vector3(0, 2.22, 0.4), 0.1, 0.08, Color(0.98, 0.55, 0.08), 8)
			_wheels(k, 0.72, 0.33, [-0.9, 0.9])
		"wagen":
			# Gepäckwagen ohne Ladung (Front -Z mit Deichsel), Plane und Pfosten
			k.box(Vector3(-0.85, 0.42, -1.3), Vector3(0.85, 0.55, 1.3), DARK_METAL)
			k.box(Vector3(-0.8, 0.55, -1.25), Vector3(0.8, 0.58, 1.25), Color(0.42, 0.43, 0.44))
			# offener Wagen: Eckpfosten, Stirnwände, niedriges Seitengitter
			for p: Vector3 in [Vector3(-0.85, 0, -1.3), Vector3(0.78, 0, -1.3), Vector3(-0.85, 0, 1.23), Vector3(0.78, 0, 1.23)]:
				k.box(p + Vector3(0, 0.55, 0), p + Vector3(0.07, 1.25, 0.07), DARK_METAL)
			for sz: float in [-1.3, 1.25]:
				k.box(Vector3(-0.85, 0.58, sz), Vector3(0.85, 1.25, sz + 0.05), Color(0.3, 0.42, 0.32))
			for sx: float in [-0.87, 0.82]:
				k.box(Vector3(sx, 0.85, -1.3), Vector3(sx + 0.05, 0.9, 1.3), DARK_METAL)
			k.box(Vector3(-0.05, 0.35, -2.4), Vector3(0.05, 0.42, -1.3), DARK_METAL)
			k.box(Vector3(-0.07, 0.4, 1.3), Vector3(0.07, 0.48, 1.5), DARK_METAL)
			# Dach mit Plane, seitlich aufgerollte Planen
			k.soft_box(Vector3(-0.9, 1.9, -1.35), Vector3(0.9, 2.0, 1.35), 0.06, Color(0.3, 0.42, 0.32), 12, 6)
			for p: Vector3 in [Vector3(-0.85, 0, -1.3), Vector3(0.78, 0, -1.3), Vector3(-0.85, 0, 1.23), Vector3(0.78, 0, 1.23)]:
				k.box(p + Vector3(0, 1.25, 0), p + Vector3(0.07, 1.9, 0.07), DARK_METAL)
			for sx: float in [-0.9, 0.9]:
				k.cyl(Vector3(sx, 1.82, -1.3), Vector3(sx, 1.82, 1.3), 0.07, 0.07, Color(0.26, 0.36, 0.28), 8)
			k.box(Vector3(-0.3, 1.45, -1.33), Vector3(0.3, 1.7, -1.3), Color(0.95, 0.95, 0.92))
			_wheels(k, 0.85, 0.22, [-0.95, 0.95])
		"pylon":
			k.box(Vector3(-0.2, 0.0, -0.2), Vector3(0.2, 0.04, 0.2), Color(0.12, 0.12, 0.12))
			k.cyl(Vector3(0, 0.04, 0), Vector3(0, 0.72, 0), 0.15, 0.025, Color(0.98, 0.42, 0.08), 10, true)
			k.cyl(Vector3(0, 0.36, 0), Vector3(0, 0.48, 0), 0.1, 0.085, Color(0.95, 0.95, 0.92), 10, false)
		"keil":
			for sz: float in [-1.0, 1.0]:
				k.prism([Vector3(-0.25, 0, sz * 0.18), Vector3(0.25, 0, sz * 0.18), Vector3(0.25, 0, sz * 0.42), Vector3(-0.25, 0, sz * 0.42)],
					[Vector3(-0.25, 0.22, sz * 0.18), Vector3(0.25, 0.22, sz * 0.18), Vector3(0.25, 0.02, sz * 0.42), Vector3(-0.25, 0.02, sz * 0.42)],
					Color(0.95, 0.78, 0.12))
			k.box(Vector3(-0.02, 0.02, -0.3), Vector3(0.02, 0.05, 0.3), Color(0.9, 0.9, 0.88))
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


## Lkw-Fahrerhaus nach dem Vorbild eines Verteiler-Lkw (Front bei z0, 2,3 m breit): glatte Hülle mit
## großer Frontscheibe, Seitenfenster und Tür, Grill mit Lamellen, Stoßfänger, Spiegel an Auslegern,
## Trittstufen und Rundumleuchte. h: Höhe der Fensterunterkante plus 0,6 m.
static func _truck_cab(k: Kit, col: Color, z0: float, h: float) -> void:
	var top := h + 0.4
	var dark := Color(0.12, 0.12, 0.13)
	var grey := Color(0.24, 0.24, 0.26)
	var hw := 1.15
	var st := [
		[z0 - 0.02, 0.62, 1.3, top - 0.12, hw - 0.14, hw - 0.18, 6.0, 6.0],
		[z0 + 0.06, 0.52, 1.3, top - 0.03, hw - 0.03, hw - 0.07, 6.0, 6.0],
		[z0 + 0.3, 0.5, 1.3, top, hw, hw - 0.05, 6.0, 7.0],
		[z0 + 1.96, 0.5, 1.3, top, hw, hw - 0.05, 7.0, 7.0],
		[z0 + 2.02, 0.56, 1.3, top - 0.06, hw - 0.06, hw - 0.1, 7.0, 7.0],
	]
	var ws_lo := h - 0.58
	var col_fn := func(m: Vector3, p: Array) -> Color:
		var ax := absf(m.x)
		if m.z < z0 + 0.12:
			if m.y > ws_lo and m.y < top - 0.14 and ax < hw - 0.1:
				return GLASS
			if m.y > ws_lo - 0.1 and m.y < ws_lo:
				return col.darkened(0.25)
			if m.y > 0.95 and m.y < ws_lo - 0.2 and ax < 0.62:
				return dark if int((m.y - 0.95) * 14.0) % 2 == 0 else grey
			if m.y > 0.78 and m.y < 0.96 and ax > 0.62 and ax < hw - 0.08:
				return LAMP if ax < hw - 0.22 else Color(1.0, 0.62, 0.12, 0.3)
			if m.y < 0.74:
				return grey
			return col
		if m.y < 0.62:
			return grey
		if ax > hw * 0.8:
			if m.y > ws_lo + 0.05 and m.y < top - 0.2 and m.z > z0 + 0.25 and m.z < z0 + 1.32:
				return GLASS
			if absf(m.z - (z0 + 1.38)) < 0.02 and m.y < top - 0.15:
				return col.darkened(0.35)
			if absf(m.z - (z0 + 0.2)) < 0.02 and m.y < top - 0.15:
				return col.darkened(0.35)
		return col
	_shell(k, st, col_fn, 36, 0.25, [z0 + 0.12, z0 + 0.25, z0 + 1.32, z0 + 1.36, z0 + 1.4, z0 + 0.18, z0 + 0.22], true, Vector3.ZERO, col)
	var fz := z0 - 0.025
	var nf := Vector3(0, 0, -1)
	k.panel(Vector3(0, (ws_lo + top - 0.16) * 0.5, fz), Vector3(hw - 0.2, 0, 0), Vector3(0, (top - 0.16 - ws_lo) * 0.5, 0), GLASS, nf)
	for i in range(4):
		k.panel(Vector3(0, 1.0 + float(i) * 0.13, fz), Vector3(0.55, 0, 0), Vector3(0, 0.04, 0), dark, nf)
	for sx: float in [-1.0, 1.0]:
		k.panel(Vector3(sx * 0.8, 0.86, fz), Vector3(0.14, 0, 0), Vector3(0, 0.07, 0), LAMP, nf)
	for sx: float in [-1.0, 1.0]:
		# Spiegel an Auslegern, Griff, Trittstufen
		var x0 := sx * hw
		k.box(Vector3(minf(x0, x0 + sx * 0.32), h - 0.42, z0 + 0.28), Vector3(maxf(x0, x0 + sx * 0.32), h - 0.39, z0 + 0.32), dark)
		k.soft_box(Vector3(minf(x0 + sx * 0.26, x0 + sx * 0.38), h - 0.75, z0 + 0.22), Vector3(maxf(x0 + sx * 0.26, x0 + sx * 0.38), h - 0.2, z0 + 0.34), 0.03, dark, 8, 2)
		k.box(Vector3(minf(x0, x0 + sx * 0.03), h - 0.75, z0 + 1.15), Vector3(maxf(x0, x0 + sx * 0.03), h - 0.7, z0 + 1.3), Color(0.2, 0.2, 0.2))
		for sy: float in [0.45, 0.72]:
			k.box(Vector3(minf(sx * (hw - 0.2), sx * (hw + 0.02)), sy, z0 + 1.45), Vector3(maxf(sx * (hw - 0.2), sx * (hw + 0.02)), sy + 0.05, z0 + 1.9), grey)
	# Stoßfänger, Sonnenblende, Rundumleuchte
	k.soft_box(Vector3(-hw - 0.03, 0.42, z0 - 0.1), Vector3(hw + 0.03, 0.72, z0 + 0.25), 0.07, grey, 12, 4)
	k.box(Vector3(-hw + 0.08, top - 0.1, z0 - 0.06), Vector3(hw - 0.08, top - 0.04, z0 + 0.12), col.darkened(0.15))
	k.cyl(Vector3(0, top, z0 + 1.2), Vector3(0, top + 0.18, z0 + 1.2), 0.13, 0.11, Color(0.98, 0.55, 0.08, 0.3), 10)
	k.box(Vector3(-0.3, top - 0.02, z0 + 0.8), Vector3(0.3, top + 0.1, z0 + 1.0), Color(0.95, 0.55, 0.1))


static func _wheels(k: Kit, half_track: float, r: float, zs: Array) -> void:
	for z: float in zs:
		for sx: float in [-1.0, 1.0]:
			_wheel(k, Vector3(sx * (half_track - 0.15), r, z), r, 0.3, sx, Color(0.72, 0.73, 0.75), 0)


## Stangenloser Pushback-Schlepper (Front -Z): flacher Körper, vorn eine U-Gabel für das Bugrad,
## Kabine seitlich, Rundumleuchte. Das Bugrad sitzt bei z = -2.8.
static func _tug(k: Kit) -> void:
	var body := Color(0.92, 0.78, 0.16)
	var dark := Color(0.16, 0.16, 0.17)
	var tug_col := func(m: Vector3, _p: Array) -> Color:
		if m.y < 0.5:
			return dark
		if m.y > 0.86 and m.y < 0.98:
			return dark
		for wz: float in [-3.3, 2.8]:
			if Vector2(m.z - wz, m.y - 0.55).length() < 0.66 and absf(m.x) > 1.55:
				return Color(0.06, 0.06, 0.07)
		if m.z > 3.8 and m.y > 1.0 and m.y < 1.2 and absf(m.x) > 1.2:
			return Color(0.8, 0.1, 0.08)
		return body
	# Heckteil mit Motor, rundum gerundet
	var rst := [
		[-0.95, 0.42, 0.95, 1.3, 1.74, 1.7, 6.0, 6.0],
		[-0.85, 0.35, 0.95, 1.36, 1.8, 1.76, 7.0, 7.0],
		[3.8, 0.35, 0.95, 1.36, 1.8, 1.76, 7.0, 7.0],
		[3.95, 0.42, 0.95, 1.28, 1.72, 1.68, 6.0, 6.0],
	]
	_shell(k, rst, tug_col, 36, 0.3)
	# Gabelarme mit gerundeten Enden und Warnstreifen
	for sx: float in [-1.0, 1.0]:
		var ast := [
			[-4.28, 0.45, 0.85, 1.08, 0.42, 0.4, 4.0, 5.0],
			[-4.1, 0.35, 0.85, 1.16, 0.53, 0.5, 6.0, 6.0],
			[-0.8, 0.35, 0.85, 1.16, 0.53, 0.5, 6.0, 6.0],
		]
		var arm_col := func(m: Vector3, p: Array) -> Color:
			if m.z < -3.3 and m.y > 0.45 and m.y < 0.85 and int((m.z + m.y) * 3.0) % 2 == 0:
				return dark
			return tug_col.call(m + Vector3(sx * 1.27, 0, 0), p)
		_shell(k, ast, arm_col, 28, 0.3, [], true, Vector3(sx * 1.27, 0, 0))
	# Gabel: Rampe und Klemmbacken
	k.box(Vector3(-0.75, 0.2, -3.2), Vector3(0.75, 0.32, -0.9), DARK_METAL)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(minf(sx * 0.75, sx * 0.55), 0.32, -3.3), Vector3(maxf(sx * 0.75, sx * 0.55), 0.95, -2.4), METAL)
	k.box(Vector3(-0.75, 0.32, -1.1), Vector3(0.75, 1.1, -0.9), METAL)
	# Kabine rechts hinten: verglast, gerundetes Dach
	var cst := [
		[-1.32, 1.4, 1.75, 2.5, 0.6, 0.5, 4.0, 6.0],
		[-1.22, 1.33, 1.75, 2.66, 0.67, 0.58, 4.5, 6.0],
		[1.22, 1.33, 1.75, 2.66, 0.67, 0.58, 4.5, 6.0],
		[1.32, 1.4, 1.75, 2.5, 0.6, 0.5, 4.0, 6.0],
	]
	var cab_col := func(m: Vector3, _p: Array) -> Color:
		if m.y > 1.62 and m.y < 2.5:
			if absf(m.z) > 1.15 and absf(m.z) < 1.25 and absf(m.x) > 0.5:
				return body.darkened(0.2)
			return GLASS
		return body
	_shell(k, cst, cab_col, 32, 0.2, [], true, Vector3(1.08, 0, 2.3))
	k.cyl(Vector3(1.1, 2.66, 2.3), Vector3(1.1, 2.86, 2.3), 0.14, 0.12, Color(0.98, 0.55, 0.08, 0.3), 10)
	# Motorhaube mit Lüftungsgitter, Scheinwerfer an den Gabelenden
	for i in range(5):
		k.box(Vector3(-1.5, 1.35, 1.3 + float(i) * 0.45), Vector3(0.1, 1.38, 1.5 + float(i) * 0.45), dark)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(minf(sx * 1.6, sx * 1.1), 0.9, -4.3), Vector3(maxf(sx * 1.6, sx * 1.1), 1.05, -4.24), LAMP)
	_wheels(k, 1.95, 0.55, [-3.3, 2.8])


const APRON_BUS_DOORS := [-4.6, 0.0, 4.6]


## Ein Flügel einer Bustür (Glas mit Rahmen, Griffleiste), Mitte im Ursprung, 0,9 m breit.
static func bus_door_leaf(h: float = 1.95, w: float = 0.9) -> ArrayMesh:
	var key := "busdoor_%.2f_%.2f" % [h, w]
	if _cache.has(key):
		return _cache[key]
	var k := Kit.new()
	var frame := Color(0.22, 0.23, 0.25)
	var hw := w * 0.5
	k.box(Vector3(-0.03, 0.0, -hw), Vector3(0.03, h, hw), GLASS)
	k.box(Vector3(-0.04, 0.0, -hw), Vector3(0.04, 0.08, hw), frame)
	k.box(Vector3(-0.04, h - 0.08, -hw), Vector3(0.04, h, hw), frame)
	for z: float in [-hw, hw]:
		k.box(Vector3(-0.04, 0.0, z - 0.035), Vector3(0.04, h, z + 0.035), frame)
	k.box(Vector3(-0.05, h * 0.45, -0.02), Vector3(0.05, h * 0.55, 0.02), Color(0.7, 0.72, 0.74))
	var mesh := k.commit()
	_cache[key] = mesh
	return mesh


## Vorfeldbus nach dem Vorbild der großen Flughafenbusse (14 m, 3 m breit, Front -Z): rundum verglast,
## gerundete Front und Heck mit großer Scheibe, je drei Doppeltüren links und rechts, Dachaufbau.
static func _apron_bus(k: Kit) -> void:
	var body := Color(0.93, 0.93, 0.9)
	var stripe := Color(0.18, 0.36, 0.62)
	var dark := Color(0.12, 0.12, 0.13)
	var hl := 7.0
	var hw := 1.5
	var st := [
		[-hl - 0.03, 0.55, 1.25, 2.6, hw - 0.42, hw - 0.5, 4.0, 4.0],
		[-hl + 0.12, 0.36, 1.25, 2.84, hw - 0.12, hw - 0.18, 5.0, 5.0],
		[-hl + 0.45, 0.3, 1.25, 2.95, hw, hw - 0.06, 7.0, 7.0],
		[hl - 0.45, 0.3, 1.25, 2.95, hw, hw - 0.06, 7.0, 7.0],
		[hl - 0.12, 0.36, 1.25, 2.84, hw - 0.12, hw - 0.18, 5.0, 5.0],
		[hl + 0.03, 0.55, 1.25, 2.6, hw - 0.42, hw - 0.5, 4.0, 4.0],
	]
	var axles := [-4.8, 4.8]
	var cuts := []
	for dz: float in APRON_BUS_DOORS:
		cuts.append(dz - 0.98)
		cuts.append(dz + 0.98)
	var posts := [-6.1, -2.3, 2.3, 6.1]
	for pz: float in posts:
		cuts.append(pz - 0.06)
		cuts.append(pz + 0.06)
	var col_fn := func(m: Vector3, p: Array) -> Color:
		var ax := absf(m.x)
		for az: float in axles:
			if Vector2(m.z - az, m.y - 0.48).length() < 0.6 and ax > hw * 0.8:
				return Color(0.05, 0.05, 0.055)
		if m.y < 0.42:
			return dark
		var endz := absf(m.z) > hl - 0.42
		if endz:
			# Front- und Heckscheibe gehen um die Ecken herum
			if m.y > 1.0 and m.y < 2.55:
				return GLASS
			if m.y > 2.6 and m.y < 2.8 and ax < 0.9 and m.z < 0.0:
				return Color(0.05, 0.05, 0.05)
			if m.y > 0.62 and m.y < 0.82 and ax > hw - 0.55:
				return LAMP if m.z < 0.0 else Color(0.72, 0.06, 0.05)
			if m.y > 0.75 and m.y < 0.9:
				return stripe
			return body
		if ax > hw * 0.85:
			for dz: float in APRON_BUS_DOORS:
				if absf(m.z - dz) < 0.98 and m.y < 2.62:
					return Color(0.2, 0.21, 0.23)
		if m.y > 1.08 and m.y < 2.6 and ax > hw * 0.85:
			for pz: float in posts:
				if absf(m.z - pz) < 0.06:
					return body
			return GLASS
		if m.y > 0.75 and m.y < 0.9:
			return stripe
		return body
	_shell(k, st, col_fn, 40, 0.3, cuts, true, Vector3.ZERO, body)
	for sz: float in [-1.0, 1.0]:
		var ez := sz * (hl + 0.035)
		var nz := Vector3(0, 0, sz)
		k.panel(Vector3(0, 1.75, ez), Vector3(0.98, 0, 0), Vector3(0, 0.72, 0), GLASS, nz)
		for sx: float in [-1.0, 1.0]:
			k.panel(Vector3(sx * 0.82, 0.72, ez), Vector3(0.16, 0, 0), Vector3(0, 0.07, 0), LAMP if sz < 0.0 else Color(0.72, 0.06, 0.05), nz)
		k.panel(Vector3(0, 0.82, ez), Vector3(1.0, 0, 0), Vector3(0, 0.06, 0), stripe, nz)
	k.panel(Vector3(0, 2.66, -hl - 0.04), Vector3(0.9, 0, 0), Vector3(0, 0.1, 0), Color(0.05, 0.05, 0.05), Vector3(0, 0, -1))
	for az: float in axles:
		for sx: float in [-1.0, 1.0]:
			_wheel(k, Vector3(sx * (hw - 0.2), 0.48, az), 0.48, 0.3, sx, Color(0.75, 0.76, 0.78), 0)
	# Türschwellen innen, Dachaufbau mit Klimaanlage, Rundumleuchte, Spiegel
	for sx: float in [-1.0, 1.0]:
		for dz: float in APRON_BUS_DOORS:
			k.box(Vector3(minf(sx * 1.15, sx * 1.46), 0.3, dz - 0.9), Vector3(maxf(sx * 1.15, sx * 1.46), 0.36, dz + 0.9), Color(0.3, 0.3, 0.32))
		k.box(Vector3(minf(sx * (hw - 0.05), sx * (hw + 0.3)), 2.6, -hl + 0.5), Vector3(maxf(sx * (hw - 0.05), sx * (hw + 0.3)), 2.64, -hl + 0.56), dark)
		k.box(Vector3(minf(sx * (hw + 0.24), sx * (hw + 0.34)), 1.95, -hl + 0.44), Vector3(maxf(sx * (hw + 0.24), sx * (hw + 0.34)), 2.62, -hl + 0.62), dark)
	k.soft_box(Vector3(-1.15, 2.92, -3.6), Vector3(1.15, 3.18, 1.8), 0.12, Color(0.82, 0.83, 0.84), 12, 6)
	k.cyl(Vector3(0, 3.18, -1.0), Vector3(0, 3.36, -1.0), 0.13, 0.11, Color(0.98, 0.55, 0.08, 0.3), 10)
	PixelFont.draw(k, "VORFELD", Vector3(0, 2.66, -hl - 0.045), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.024, Color(0.98, 0.65, 0.15, 0.3))


## Treppenwagen (Front -Z) mit Plattform vorn auf Höhe h (Türschwelle), Treppe fällt nach hinten ab.
static func stairs_mesh(h: float) -> ArrayMesh:
	var key := "treppe_%.2f" % h
	if _cache.has(key):
		return _cache[key]
	var k := Kit.new()
	k.bevel = 0.05
	var body := Color(0.92, 0.92, 0.9)
	var rail := Color(0.85, 0.7, 0.15)
	# Fahrgestell mit Kabine hinten links
	k.box(Vector3(-1.1, 0.35, -3.6), Vector3(1.1, 0.75, 3.8), DARK_METAL)
	var cst := [
		[-1.08, 0.82, 1.4, 2.2, 0.48, 0.42, 4.0, 6.0],
		[-0.98, 0.75, 1.4, 2.32, 0.55, 0.49, 5.0, 6.0],
		[0.98, 0.75, 1.4, 2.32, 0.55, 0.49, 5.0, 6.0],
		[1.06, 0.82, 1.4, 2.22, 0.5, 0.44, 4.0, 6.0],
	]
	var stairs_cab := func(m: Vector3, _p: Array) -> Color:
		if m.y > 1.5 and m.y < 2.18 and (m.z < -0.9 or absf(m.x) > 0.4) and m.z < 0.5:
			return GLASS
		return YELLOW
	_shell(k, cst, stairs_cab, 28, 0.2, [-0.9, 0.5], true, Vector3(-0.6, 0, 2.85), YELLOW)
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
