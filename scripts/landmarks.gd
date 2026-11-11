extends RefCounted
## Große Bauten im feinen Stil: Hangar, Tower, Feuerwache und Parkhaus. Alles aus dem
## Baukasten (mesh_kit.gd) als ein Mesh mit Vertexfarben. Bewegliche Teile sind eigene
## Knoten, die deco_anim.gd nach ihrem Namen bewegt (Dreh*, Blink*, Schwenk*).
## Fenster Alpha 0.6 (nachts erleuchtet), Lampen Alpha 0.3 (leuchten nachts hell).

const Kit = preload("res://scripts/mesh_kit.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")
const DecoAnim = preload("res://scripts/deco_anim.gd")
const Models = preload("res://scripts/models.gd")
const Catalog = preload("res://scripts/catalog.gd")

const CONCRETE := Color(0.66, 0.65, 0.61)
const RENDER := Color(0.88, 0.87, 0.83)
const ROOF := Color(0.36, 0.36, 0.35)
const GRAVEL := Color(0.55, 0.53, 0.49)
const STEEL := Color(0.42, 0.45, 0.48)
const DARK := Color(0.12, 0.12, 0.13)
const FRAME := Color(0.24, 0.26, 0.28)
const BRICK := Color(0.6, 0.27, 0.2)
const WIN := Color(0.2, 0.3, 0.36, 0.6)
const LAMP := Color(1.0, 0.92, 0.72, 0.3)
const RED_LAMP := Color(1.0, 0.15, 0.1, 0.3)
const BLUE_LAMP := Color(0.25, 0.45, 1.0, 0.3)
const GREEN_LAMP := Color(0.15, 0.9, 0.35, 0.3)
const YELLOW := Color(0.9, 0.72, 0.16)
const WHITE := Color(0.93, 0.93, 0.91)
const FIRE_RED := Color(0.78, 0.12, 0.09)
const LEAF := Color(0.27, 0.45, 0.22, 0.8)

const IDS := ["hangar", "tower", "feuerwache", "parkhaus"]

static var _truck: ArrayMesh = null
static var _glass_mat: StandardMaterial3D = null
static var _serial := 0


static func build(n: Node3D, id: String) -> bool:
	if not (id in IDS):
		return false
	var opts: Dictionary = n.get_meta("opts", {})
	var k := Kit.new()
	match id:
		"hangar":
			_hangar(n, k, opts)
		"tower":
			_tower(n, k, opts)
		"feuerwache":
			if Catalog.tore_of("feuerwache", opts) > 0:
				sized_hall(n, "feuerwache", opts)
			else:
				_fire_station(n, k)
		"parkhaus":
			_car_park(n, k, opts)
	n.add_child(k.instance("Bau"))
	var a := Node.new()
	a.name = "Anim"
	a.set_script(DecoAnim)
	n.add_child(a)
	return true


# ------------------------------------------------------------------ Helfer

static func _part(n: Node3D, name: String, k: Kit, at: Vector3) -> MeshInstance3D:
	_serial += 1
	var mi := k.instance("%s%d" % [name, _serial])
	mi.position = at
	mi.set_meta("no_bake", true)
	n.add_child(mi)
	return mi


## Durchsichtiges Glas (eigener Knoten, damit man hineinsieht).
static func glass_mat() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.albedo_color = Color(0.55, 0.72, 0.8, 0.28)
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glass_mat.roughness = 0.05
		_glass_mat.metallic_specular = 0.9
	return _glass_mat


static func _glass_part(n: Node3D, k: Kit) -> void:
	var mi := k.instance("Glas")
	mi.material_override = glass_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_bake", true)
	n.add_child(mi)


## Warnleuchte, die blinkt.
static func _blinker(n: Node3D, at: Vector3, col: Color, r: float, period: float, phase: float) -> void:
	var bk := Kit.new()
	bk.sphere(Vector3.ZERO, r, col, 8, 5)
	var mi := _part(n, "Blink", bk, at)
	mi.set_meta("period", period)
	mi.set_meta("phase", phase)


## Fenster mit Rahmen, Sprossen und Bank. c = Mitte auf der Fassade, right/up = halbe Größe.
static func _window(k: Kit, c: Vector3, right: Vector3, up: Vector3, nrm: Vector3, bars: int = 1, sill: bool = true) -> void:
	var rn := right.normalized()
	var un := up.normalized()
	k.panel(c + nrm * 0.02, right + rn * 0.08, up + un * 0.08, FRAME, nrm)
	k.panel(c + nrm * 0.035, right, up, WIN, nrm)
	for i in range(1, bars + 1):
		var x := -1.0 + 2.0 * float(i) / float(bars + 1)
		k.panel(c + right * x + nrm * 0.05, rn * 0.035, up, FRAME, nrm)
	if sill:
		k.box(c - up - un * 0.14 - right - rn * 0.12, c - up - un * 0.06 + right + rn * 0.12 + nrm * 0.14, CONCRETE.lightened(0.12))


## Wandleuchte (nachts hell).
static func _wall_lamp(k: Kit, at: Vector3, nrm: Vector3) -> void:
	var side := nrm.cross(Vector3.UP).normalized()
	k.box(at - side * 0.08 - Vector3(0, 0.1, 0), at + side * 0.08 + Vector3(0, 0.1, 0) + nrm * 0.12, FRAME)
	k.box(at - side * 0.16 + nrm * 0.1 - Vector3(0, 0.12, 0), at + side * 0.16 + nrm * 0.36 - Vector3(0, 0.02, 0), FRAME)
	k.box(at - side * 0.13 + nrm * 0.12 - Vector3(0, 0.15, 0), at + side * 0.13 + nrm * 0.34 - Vector3(0, 0.1, 0), LAMP)


## Horizontale Fugen auf einer Wandfläche (a, b = Ecken in der Fläche, nrm nach außen).
static func _joints(k: Kit, a: Vector3, b: Vector3, nrm: Vector3, step: float, col: Color) -> void:
	var y := minf(a.y, b.y) + step
	var lo := Vector3(minf(a.x, b.x), 0, minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), 0, maxf(a.z, b.z))
	while y < maxf(a.y, b.y) - 0.05:
		k.box(Vector3(lo.x, y, lo.z) + nrm * 0.0, Vector3(hi.x, y + 0.025, hi.z) + nrm * 0.015, col)
		y += step


## Dachlüfter mit Gitter, das Flügelrad dreht sich.
static func _fan(n: Node3D, k: Kit, at: Vector3, r: float, speed: float) -> void:
	k.cyl(at, at + Vector3(0, 0.35, 0), r + 0.08, r + 0.08, Color(0.58, 0.6, 0.61), 16, false)
	k.cyl(at + Vector3(0, 0.33, 0), at + Vector3(0, 0.37, 0), r + 0.12, r + 0.12, Color(0.45, 0.47, 0.48), 16)
	var fk := Kit.new()
	for i in range(5):
		var a := float(i) / 5.0 * TAU
		var tip := Vector3(cos(a), 0, sin(a)) * r * 0.92
		var side := Vector3(-sin(a), 0, cos(a)) * r * 0.22
		fk.quad(Vector3.ZERO, tip - side, tip + side, side * 0.3, DARK, Vector3(0, -1, 0))
	fk.cyl(Vector3(0, -0.02, 0), Vector3(0, 0.05, 0), r * 0.18, r * 0.18, Color(0.3, 0.3, 0.32), 10)
	var f := _part(n, "DrehLuefter", fk, at + Vector3(0, 0.4, 0))
	f.set_meta("speed", speed)
	for i in range(6):
		var x := -r + float(i) * r * 0.4
		k.box(at + Vector3(x - 0.012, 0.44, -r), at + Vector3(x + 0.012, 0.46, r), STEEL)


## Brüstung (Attika) um ein Flachdach.
static func _parapet(k: Kit, x0: float, z0: float, x1: float, z1: float, y: float, h: float, col: Color) -> void:
	var t := 0.25
	k.box(Vector3(x0, y, z0), Vector3(x1, y + h, z0 + t), col)
	k.box(Vector3(x0, y, z1 - t), Vector3(x1, y + h, z1), col)
	k.box(Vector3(x0, y, z0), Vector3(x0 + t, y + h, z1), col)
	k.box(Vector3(x1 - t, y, z0), Vector3(x1, y + h, z1), col)
	var cap := CONCRETE.lightened(0.15)
	k.box(Vector3(x0 - 0.05, y + h, z0 - 0.05), Vector3(x1 + 0.05, y + h + 0.08, z0 + t + 0.05), cap)
	k.box(Vector3(x0 - 0.05, y + h, z1 - t - 0.05), Vector3(x1 + 0.05, y + h + 0.08, z1 + 0.05), cap)
	k.box(Vector3(x0 - 0.05, y + h, z0 - 0.05), Vector3(x0 + t + 0.05, y + h + 0.08, z1 + 0.05), cap)
	k.box(Vector3(x1 - t - 0.05, y + h, z0 - 0.05), Vector3(x1 + 0.05, y + h + 0.08, z1 + 0.05), cap)


## Klimagerät auf dem Dach mit Lüftergittern.
static func _ac_unit(k: Kit, at: Vector3, w: float, d: float) -> void:
	k.rounded_box(at + Vector3(-w * 0.5, 0, -d * 0.5), at + Vector3(w * 0.5, 0.9, d * 0.5), 0.06, Color(0.78, 0.79, 0.78), 2)
	for i in range(int(w / 0.9)):
		var c := at + Vector3(-w * 0.5 + 0.45 + float(i) * 0.9, 0.91, 0)
		k.cyl(c, c + Vector3(0, 0.03, 0), 0.34, 0.34, Color(0.3, 0.31, 0.32), 12)
		k.box(c + Vector3(-0.34, 0.03, -0.01), c + Vector3(0.34, 0.05, 0.01), STEEL)
	k.box(at + Vector3(-w * 0.5, 0, -d * 0.5 - 0.02), at + Vector3(w * 0.5, 0.06, d * 0.5 + 0.02), DARK)


## Pflanztrog mit Laub, an der Außenseite hängen Ranken herab (Laub wiegt sich im Wind).
static func _planter(k: Kit, a: Vector3, b: Vector3, out: Vector3, rng: RandomNumberGenerator) -> void:
	var dir := (b - a).normalized()
	var length := a.distance_to(b)
	k.box(a - out * 0.2 - Vector3(0, 0, 0), b + out * 0.2 + Vector3(0, 0.32, 0), Color(0.3, 0.3, 0.31))
	var s := 0.4
	while s < length - 0.3:
		var p := a + dir * s + Vector3(0, 0.32, 0)
		var g := Color.from_hsv(rng.randf_range(0.24, 0.32), rng.randf_range(0.45, 0.65), rng.randf_range(0.32, 0.48), 0.8)
		k.sphere(p + Vector3(0, 0.12, 0), rng.randf_range(0.28, 0.4), g, 7, 4, Vector3(1.0, 0.75, 1.0))
		if rng.randf() < 0.3:
			var flower := [Color(0.92, 0.45, 0.6, 0.8), Color(0.98, 0.85, 0.3, 0.8), Color(0.95, 0.95, 0.95, 0.8)][rng.randi() % 3] as Color
			k.sphere(p + Vector3(rng.randf_range(-0.15, 0.15), 0.38, rng.randf_range(-0.1, 0.1)), 0.09, flower, 6, 3)
		# Ranken außen
		var hang := rng.randf_range(0.6, 1.8)
		var side := dir * rng.randf_range(0.12, 0.2)
		k.quad(p + out * 0.3 - side, p + out * 0.3 + side, p + out * 0.33 + side - Vector3(0, hang, 0),
			p + out * 0.33 - side - Vector3(0, hang * 0.85, 0), Color(g.r * 0.9, g.g * 0.95, g.b * 0.9, 0.8), p)
		s += rng.randf_range(0.5, 0.75)


## Rolltor: Führungsschienen, Wickelkasten und Vorhang mit Lamellen und Fensterreihe. Der Vorhang
## ist ein eigener Knoten "Rolltor<i>" mit Drehpunkt an der Oberkante (ground_ops.gd rollt ihn auf),
## darüber die Warnleuchte "Warnlicht<i>", die blinkt, solange sich das Tor bewegt.
## c = Mitte der Torunterkante (Vorhang liegt in der Ebene z = c.z), Außenseite +Z.
static func roll_door(n: Node3D, k: Kit, idx: int, c: Vector3, w: float, h: float, col: Color, windows: int = 3) -> void:
	var hw := w * 0.5
	for sx: float in [-1.0, 1.0]:
		k.box(c + Vector3(sx * hw - 0.1, 0, -0.12), c + Vector3(sx * hw + 0.1, h, 0.12), STEEL)
		k.box(c + Vector3(sx * hw - 0.13, 0, 0.12), c + Vector3(sx * hw + 0.13, 0.9, 0.16), YELLOW)
	k.box(c + Vector3(-hw - 0.2, h, -0.2), c + Vector3(hw + 0.2, h + 0.55, 0.32), Color(0.56, 0.58, 0.6))
	k.box(c + Vector3(-hw - 0.2, h + 0.5, -0.2), c + Vector3(hw + 0.2, h + 0.55, 0.34), Color(0.46, 0.48, 0.5))
	var vk := Kit.new()
	var slat := 0.22
	var y := -h
	while y < -0.03:
		var top := minf(y + slat, 0.0)
		vk.box(Vector3(-hw + 0.08, y, -0.03), Vector3(hw - 0.08, top - 0.03, 0.03), col)
		vk.box(Vector3(-hw + 0.08, top - 0.03, -0.022), Vector3(hw - 0.08, top, 0.022), col.darkened(0.3))
		y += slat
	if windows > 0:
		var wy := -h * 0.36
		var span := (w - 0.6) / float(windows)
		for i in range(windows):
			var x0 := -hw + 0.3 + float(i) * span
			vk.box(Vector3(x0 + 0.06, wy - 0.32, 0.028), Vector3(x0 + span - 0.06, wy + 0.32, 0.04), WIN)
	vk.box(Vector3(-hw + 0.08, -h, -0.05), Vector3(hw - 0.08, -h + 0.1, 0.05), DARK)
	vk.box(Vector3(-0.25, -h + 0.75, 0.03), Vector3(0.25, -h + 0.82, 0.07), STEEL)
	var holder := Node3D.new()
	holder.name = "Rolltor%d" % idx
	holder.position = c + Vector3(0, h, 0)
	holder.set_meta("no_bake", true)
	n.add_child(holder)
	holder.add_child(vk.instance("Vorhang"))
	var lk := Kit.new()
	lk.sphere(Vector3.ZERO, 0.13, Color(1.0, 0.6, 0.1, 0.3), 8, 4)
	var lamp := lk.instance("Warnlicht%d" % idx)
	lamp.position = c + Vector3(hw - 0.35, h + 0.72, 0.28)
	lamp.visible = false
	lamp.set_meta("no_bake", true)
	n.add_child(lamp)
	k.cyl(c + Vector3(hw - 0.35, h + 0.55, 0.28), c + Vector3(hw - 0.35, h + 0.62, 0.28), 0.1, 0.1, DARK, 8)


# ================================================================== Hangar

const H_X := 22.0
const H_Z0 := -18.0
const H_Z1 := 11.0
const H_EAVE := 10.0
const H_RISE := 4.0


## Höhe des Bogendachs über x (Segmentbogen über die ganze Breite).
static func _hy(x: float) -> float:
	var r := (H_X * H_X + H_RISE * H_RISE) / (2.0 * H_RISE)
	return H_EAVE + sqrt(maxf(r * r - x * x, 0.0)) - (r - H_RISE)


## Hangar: Halle mit Segmentbogendach (Stehfalz, Lichtband, Lüfter), Faltschiebetor mit
## zwei geöffneten Flügelpaaren, drinnen eine ATR 72 in der Wartung mit Arbeitsbühne. Hinten
## Bürotrakt mit Fensterbändern und Werkstatt mit Rolltor, Windsack auf dem Dach.
static func _hangar(n: Node3D, k: Kit, opts: Dictionary) -> void:
	var clad: Color = {"grau": Color(0.62, 0.66, 0.68), "blau": Color(0.3, 0.45, 0.62), "weiss": Color(0.86, 0.87, 0.86)}.get(String(opts.get("farbe", "grau")), Color(0.62, 0.66, 0.68))
	var rib := clad.darkened(0.14)
	var roof := Color(0.56, 0.58, 0.6)
	var inner := Color(0.8, 0.8, 0.78)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	# Hallenboden mit Leitlinie und roten Sicherheitslinien
	k.box(Vector3(-22.2, 0, -18.6), Vector3(22.2, 0.1, 11.1), Color(0.72, 0.72, 0.7))
	k.box(Vector3(-0.1, 0.1, -18.6), Vector3(0.1, 0.115, 8.0), YELLOW)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 17.0 - 0.06, 0.1, -16.0), Vector3(sx * 17.0 + 0.06, 0.115, 9.0), Color(0.85, 0.2, 0.15))
	# Seitenwände: Trapezblech, Sockel, Fensterband, Traufe, Fallrohre, Notausgänge
	for sx: float in [-1.0, 1.0]:
		var xo := sx * H_X
		k.box(Vector3(xo - sx * 0.25, 0, H_Z0), Vector3(xo, H_EAVE, H_Z1), clad)
		k.box(Vector3(xo - sx * 0.1, 0, H_Z0 - 0.1), Vector3(xo + sx * 0.09, 0.9, H_Z1 + 0.05), CONCRETE)
		var exits := [-10.0, 4.0]
		var z := H_Z0 + 0.35
		while z < H_Z1 - 0.2:
			var near_exit := false
			for ez: float in exits:
				if absf(z - ez) < 0.85:
					near_exit = true
			k.box(Vector3(xo, 0.9 if not near_exit else 2.55, z - 0.05), Vector3(xo + sx * 0.07, 6.0, z + 0.05), rib)
			k.box(Vector3(xo, 8.0, z - 0.05), Vector3(xo + sx * 0.07, H_EAVE - 0.12, z + 0.05), rib)
			z += 0.6
		k.box(Vector3(xo, 6.0, H_Z0 + 1.5), Vector3(xo + sx * 0.06, 8.0, H_Z1 - 1.5), FRAME)
		k.box(Vector3(xo, 6.12, H_Z0 + 1.6), Vector3(xo + sx * 0.09, 7.88, H_Z1 - 1.6), WIN)
		var wz := H_Z0 + 1.6
		while wz < H_Z1 - 1.4:
			k.box(Vector3(xo, 6.0, wz - 0.05), Vector3(xo + sx * 0.12, 8.0, wz + 0.05), FRAME)
			wz += 2.0
		k.box(Vector3(xo, 5.9, H_Z0 + 1.4), Vector3(xo + sx * 0.2, 6.02, H_Z1 - 1.4), CONCRETE.lightened(0.12))
		k.box(Vector3(xo - sx * 0.1, H_EAVE - 0.18, H_Z0 - 0.45), Vector3(xo + sx * 0.45, H_EAVE + 0.06, H_Z1 + 0.45), STEEL)
		for dz: float in [H_Z0 + 0.6, -3.0, H_Z1 - 0.6]:
			k.cyl(Vector3(xo + sx * 0.3, H_EAVE - 0.15, dz), Vector3(xo + sx * 0.3, 0.1, dz), 0.09, 0.09, STEEL, 8)
			k.cyl(Vector3(xo + sx * 0.3, 0.1, dz), Vector3(xo + sx * 0.55, 0.05, dz), 0.09, 0.09, STEEL, 8)
		for ez: float in exits:
			k.box(Vector3(xo, 0.1, ez - 0.7), Vector3(xo + sx * 0.06, 2.4, ez + 0.7), FRAME)
			k.box(Vector3(xo, 0.12, ez - 0.6), Vector3(xo + sx * 0.1, 2.3, ez + 0.6), Color(0.3, 0.42, 0.36))
			k.box(Vector3(xo, 1.0, ez + 0.32), Vector3(xo + sx * 0.16, 1.08, ez + 0.5), STEEL)
			k.box(Vector3(xo, 2.5, ez - 0.32), Vector3(xo + sx * 0.1, 2.76, ez + 0.32), GREEN_LAMP)
			k.box(Vector3(xo + sx * 0.05, 0, ez - 0.9), Vector3(xo + sx * 1.2, 0.12, ez + 0.9), CONCRETE)
		for dz: float in [-14.0, -6.0, 1.0, 8.0]:
			_wall_lamp(k, Vector3(xo + sx * 0.07, 5.3, dz), Vector3(sx, 0, 0))
	# Bogendach: Blech mit Stehfalzen, Untersicht, Ortgang
	var segs := 24
	var z0 := H_Z0 - 0.55
	var z1 := H_Z1 + 0.5
	for i in range(segs):
		var xa := -H_X - 0.5 + (2.0 * H_X + 1.0) * float(i) / float(segs)
		var xb := -H_X - 0.5 + (2.0 * H_X + 1.0) * float(i + 1) / float(segs)
		var ya := _hy(xa)
		var yb := _hy(xb)
		var mid := Vector3((xa + xb) * 0.5, (ya + yb) * 0.5 - 4.0, (z0 + z1) * 0.5)
		k.quad(Vector3(xa, ya, z0), Vector3(xb, yb, z0), Vector3(xb, yb, z1), Vector3(xa, ya, z1), roof, mid)
		k.quad(Vector3(xa, ya - 0.4, z0 + 0.5), Vector3(xb, yb - 0.4, z0 + 0.5), Vector3(xb, yb - 0.4, z1 - 0.5), Vector3(xa, ya - 0.4, z1 - 0.5), inner, mid + Vector3(0, 12.0, 0))
		for e: Array in [[z0, -1.0], [z1, 1.0]]:
			var ze: float = e[0]
			var sz: float = e[1]
			k.quad(Vector3(xa, ya + 0.05, ze), Vector3(xb, yb + 0.05, ze), Vector3(xb, yb - 0.45, ze), Vector3(xa, ya - 0.45, ze), STEEL,
				Vector3((xa + xb) * 0.5, (ya + yb) * 0.5 - 0.2, ze - sz))
		var zf := z0 + 0.45
		while zf < z1 - 0.3:
			k.quad(Vector3(xa, ya + 0.045, zf - 0.04), Vector3(xb, yb + 0.045, zf - 0.04), Vector3(xb, yb + 0.045, zf + 0.04),
				Vector3(xa, ya + 0.045, zf + 0.04), roof.darkened(0.16), mid)
			zf += 0.9
	# Lichtbänder am First und Dachlüfter
	for zs: float in [-15.5, -10.0, -4.5, 1.0, 6.5]:
		k.box(Vector3(-1.8, 13.92, zs), Vector3(1.8, 14.22, zs + 3.2), FRAME)
		k.box(Vector3(-1.6, 14.2, zs + 0.15), Vector3(1.6, 14.3, zs + 3.05), WIN)
		k.box(Vector3(-0.03, 14.3, zs + 0.15), Vector3(0.03, 14.34, zs + 3.05), FRAME)
	for p: Vector2 in [Vector2(-8, -9), Vector2(8, -9), Vector2(-8, 4), Vector2(8, 4)]:
		var fy := _hy(p.x)
		k.box(Vector3(p.x - 0.95, fy - 0.3, p.y - 0.95), Vector3(p.x + 0.95, fy + 0.25, p.y + 0.95), STEEL)
		_fan(n, k, Vector3(p.x, fy + 0.25, p.y), 0.75, 2.2)
	# Giebel vorn (über dem Tor) und hinten
	for i in range(segs):
		var xa := -H_X + 2.0 * H_X * float(i) / float(segs)
		var xb := -H_X + 2.0 * H_X * float(i + 1) / float(segs)
		k.quad(Vector3(xa, H_EAVE, H_Z0), Vector3(xb, H_EAVE, H_Z0), Vector3(xb, _hy(xb), H_Z0), Vector3(xa, _hy(xa), H_Z0), clad,
			Vector3((xa + xb) * 0.5, 11.0, H_Z0 + 2.0))
		k.quad(Vector3(xa, 0.0, H_Z1), Vector3(xb, 0.0, H_Z1), Vector3(xb, _hy(xb), H_Z1), Vector3(xa, _hy(xa), H_Z1), clad,
			Vector3((xa + xb) * 0.5, 6.0, H_Z1 - 2.0))
	var gx := -H_X + 0.4
	while gx < H_X - 0.2:
		var top := _hy(gx) - 0.08
		k.box(Vector3(gx - 0.05, H_EAVE + 0.05, H_Z0 - 0.07), Vector3(gx + 0.05, top, H_Z0), rib)
		k.box(Vector3(gx - 0.05, 7.95 if gx < 4.0 else 5.95, H_Z1), Vector3(gx + 0.05, top, H_Z1 + 0.07), rib)
		gx += 0.6
	# Torpfeiler und Sturz mit Warnstreifen
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 20.4, 0, H_Z0 - 0.05), Vector3(sx * H_X, H_EAVE, H_Z0 + 0.25), clad)
		var px := sx * 20.4
		k.box(Vector3(px - 0.2, 0, H_Z0 - 0.35), Vector3(px + 0.2, 9.4, H_Z0 + 0.05), YELLOW)
		for j in range(6):
			k.box(Vector3(px - 0.21, float(j) * 0.4, H_Z0 - 0.36), Vector3(px + 0.21, float(j) * 0.4 + 0.2, H_Z0 + 0.06), DARK)
		var gxx := sx * 21.2
		while absf(gxx) < H_X - 0.1:
			k.box(Vector3(gxx - 0.05, 0.9, H_Z0 - 0.12), Vector3(gxx + 0.05, H_EAVE - 0.1, H_Z0 - 0.05), rib)
			gxx += sx * 0.6
	k.box(Vector3(-20.6, 9.4, H_Z0 - 0.4), Vector3(20.6, H_EAVE + 0.05, H_Z0 + 0.3), YELLOW)
	var hx := -20.4
	while hx < 20.2:
		k.quad(Vector3(hx, 9.42, H_Z0 - 0.41), Vector3(hx + 0.45, 9.42, H_Z0 - 0.41), Vector3(hx + 0.85, H_EAVE, H_Z0 - 0.41),
			Vector3(hx + 0.4, H_EAVE, H_Z0 - 0.41), DARK, Vector3(hx, 9.7, H_Z0 + 1.0))
		hx += 0.9
	# Schild und Strahler über dem Tor
	k.box(Vector3(-8.2, 10.4, H_Z0 - 0.2), Vector3(8.2, 12.9, H_Z0 - 0.05), Color(0.13, 0.2, 0.32))
	k.box(Vector3(-8.3, 10.3, H_Z0 - 0.22), Vector3(8.3, 10.4, H_Z0 - 0.04), STEEL)
	PixelFont.draw(k, "HANGAR", Vector3(0, 11.65, H_Z0 - 0.21), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.3, WHITE)
	for lx: float in [-16.0, -11.0, 11.0, 16.0]:
		k.box(Vector3(lx - 0.1, 10.5, H_Z0 - 0.5), Vector3(lx + 0.1, 10.7, H_Z0), FRAME)
		k.box(Vector3(lx - 0.35, 10.3, H_Z0 - 0.75), Vector3(lx + 0.35, 10.55, H_Z0 - 0.4), FRAME)
		k.box(Vector3(lx - 0.3, 10.27, H_Z0 - 0.72), Vector3(lx + 0.3, 10.3, H_Z0 - 0.43), LAMP)
	_blinker(n, Vector3(0, _hy(0.0) + 0.25, H_Z0 - 0.4), RED_LAMP, 0.16, 2.2, 0.0)
	_blinker(n, Vector3(0, _hy(0.0) + 0.25, H_Z1 + 0.4), RED_LAMP, 0.16, 2.2, 1.1)
	# Faltschiebetor: je drei Flügel zu, das mittlere Feld offen, Flügelpaare gefaltet
	var lw := 40.8 / 10.0
	var a := deg_to_rad(78.0)
	for i in [0, 1, 2, 7, 8, 9]:
		_leaf(k, Transform3D(Basis.IDENTITY, Vector3(-20.4 + float(i) * lw, 0, H_Z0 - 0.1)), lw, i == 1)
	var hl := Vector3(-20.4 + 3.0 * lw, 0, H_Z0 - 0.1)
	_leaf(k, Transform3D(Basis(Vector3.UP, -a), hl), lw, false)
	_leaf(k, Transform3D(Basis(Vector3.UP, a), hl + Vector3(cos(a), 0, sin(a)) * lw), lw, false)
	var hr := Vector3(-20.4 + 7.0 * lw, 0, H_Z0 - 0.1)
	_leaf(k, Transform3D(Basis(Vector3.UP, PI + a), hr), lw, false)
	_leaf(k, Transform3D(Basis(Vector3.UP, PI - a), hr + Vector3(-cos(a), 0, sin(a)) * lw), lw, false)
	k.box(Vector3(-20.4, 9.25, H_Z0 - 0.3), Vector3(20.4, 9.4, H_Z0 + 4.4), STEEL)
	# Innen: Hallenleuchten, Werkbänke, Teileregale, Werkzeugwagen
	for lx: float in [-14.0, -7.0, 0.0, 7.0, 14.0]:
		for lz: float in [-12.0, -4.0, 4.0]:
			var ly := _hy(lx) - 0.4
			k.cyl(Vector3(lx, ly, lz), Vector3(lx, ly - 1.4, lz), 0.02, 0.02, DARK, 4, false)
			k.cyl(Vector3(lx, ly - 1.4, lz), Vector3(lx, ly - 1.85, lz), 0.12, 0.42, Color(0.5, 0.52, 0.55), 12, false)
			k.cyl(Vector3(lx, ly - 1.85, lz), Vector3(lx, ly - 1.87, lz), 0.4, 0.4, LAMP, 12)
	for sx: float in [-1.0, 1.0]:
		var wx := sx * 21.2
		for rz: float in [-14.0, -8.0, -2.0]:
			k.box(Vector3(wx - 0.45, 0.1, rz), Vector3(wx + 0.45, 3.2, rz + 4.5), Color(0.2, 0.4, 0.68))
			for sh in range(4):
				var sy := 0.4 + float(sh) * 0.75
				k.box(Vector3(wx - 0.5, sy, rz + 0.05), Vector3(wx + 0.5, sy + 0.05, rz + 4.45), STEEL)
				var bz := rz + 0.2
				while bz < rz + 4.2:
					var bc := [Color(0.7, 0.55, 0.35), Color(0.3, 0.5, 0.75), Color(0.8, 0.3, 0.2), Color(0.6, 0.6, 0.58)][rng.randi() % 4] as Color
					k.box(Vector3(wx - 0.35, sy + 0.05, bz), Vector3(wx + 0.35, sy + rng.randf_range(0.25, 0.55), bz + rng.randf_range(0.4, 0.8)), bc)
					bz += 0.9
		k.box(Vector3(wx - 0.4, 0.1, 3.0), Vector3(wx + 0.4, 0.95, 8.0), Color(0.75, 0.2, 0.15))
		k.box(Vector3(wx - 0.45, 0.95, 2.95), Vector3(wx + 0.45, 1.0, 8.05), Color(0.5, 0.36, 0.22))
		for t in range(5):
			k.box(Vector3(wx - 0.2, 1.0, 3.3 + float(t) * 0.9), Vector3(wx + 0.1, 1.15, 3.6 + float(t) * 0.9), Color.from_hsv(float(t) * 0.2, 0.5, 0.7))
	for cart: Vector3 in [Vector3(-4.5, 0.1, -12.0), Vector3(6.0, 0.1, -3.5)]:
		k.rounded_box(cart + Vector3(-0.4, 0.25, -0.6), cart + Vector3(0.4, 1.05, 0.6), 0.04, Color(0.8, 0.18, 0.14), 2)
		for dr in range(4):
			k.box(cart + Vector3(0.4, 0.35 + float(dr) * 0.17, -0.5), cart + Vector3(0.43, 0.48 + float(dr) * 0.17, 0.5), Color(0.6, 0.12, 0.1))
		for w: Vector2 in [Vector2(-0.3, -0.5), Vector2(0.3, -0.5), Vector2(-0.3, 0.5), Vector2(0.3, 0.5)]:
			k.cyl(cart + Vector3(w.x, 0.12, w.y), cart + Vector3(w.x, 0.0, w.y), 0.07, 0.07, DARK, 8)
	# Arbeitsbühne am rechten Triebwerk und Bugbühne
	_work_stand(k, Vector3(6.6, 0.1, -7.6), 2.2, 2.0, 2.4)
	_work_stand(k, Vector3(-2.6, 0.1, -13.3), 1.6, 1.6, 2.6)
	# Flugzeug in der Wartung
	var Factory = load("res://scripts/factory.gd")
	var plane: Node3D = Factory.make_plane("atr72", Color(0.18, 0.42, 0.66))
	plane.position = Vector3(0, 0.1, -3.0)
	var beacon := plane.get_node_or_null("Beacon")
	if beacon != null:
		(beacon as Node3D).visible = false
	n.add_child(plane)
	var tug: Node3D = Factory.make_gse("schlepper")
	tug.position = Vector3(3.5, 0.1, -15.0)
	tug.rotation.y = 0.6
	n.add_child(tug)
	for e: Array in [[Vector3(6.4, 2.3, -7.4), 1], [Vector3(-1.2, 0.1, -12.6), 3], [Vector3(-12.0, 0.1, 6.0), 0]]:
		var mech: Node3D = Factory.make_person(Color(0.2, 0.32, 0.55), -1)
		mech.position = e[0]
		mech.rotation.y = rng.randf_range(0, TAU)
		Factory.set_pose(mech, int(e[1]))
		n.add_child(mech)
	# Hinten: Bürotrakt (zwei Geschosse) und Werkstatt
	_hangar_annex(n, k, clad, rib, rng)


## Ein Flügel des Faltschiebetors (lokal x entlang des Flügels, Außenseite -z).
static func _leaf(k: Kit, xf: Transform3D, w: float, door: bool) -> void:
	var h := 9.25
	var col := Color(0.5, 0.54, 0.57)
	var edge := col.darkened(0.25)
	k.box(Vector3(0, 0, -0.08), Vector3(w, h, 0.08), col, xf)
	k.box(Vector3(0, 0, -0.12), Vector3(0.09, h, 0.0), edge, xf)
	k.box(Vector3(w - 0.09, 0, -0.12), Vector3(w, h, 0.0), edge, xf)
	var y := 0.9
	while y < h - 0.3:
		if y < 7.4 or y > 8.8:
			k.box(Vector3(0.09, y, -0.11), Vector3(w - 0.09, y + 0.06, -0.08), edge, xf)
		y += 0.7
	k.box(Vector3(0.2, 7.5, -0.11), Vector3(w - 0.2, 8.7, -0.08), FRAME, xf)
	var pw := (w - 0.5) / 3.0
	for i in range(3):
		var xa := 0.25 + float(i) * pw
		k.box(Vector3(xa + 0.05, 7.58, -0.13), Vector3(xa + pw - 0.05, 8.62, -0.1), WIN, xf)
	k.box(Vector3(0, 0, -0.13), Vector3(w, 0.3, -0.08), DARK, xf)
	k.box(Vector3(0.15, 0.0, 0.08), Vector3(w - 0.15, 0.15, 0.1), STEEL, xf)
	if door:
		k.box(Vector3(1.4, 0.3, -0.14), Vector3(2.5, 2.3, -0.1), col.lightened(0.15), xf)
		k.box(Vector3(2.25, 1.05, -0.2), Vector3(2.4, 1.12, -0.13), STEEL, xf)
		k.box(Vector3(1.5, 2.45, -0.14), Vector3(2.4, 2.65, -0.1), GREEN_LAMP, xf)


## Gelbe Arbeitsbühne mit Geländer und Treppe.
static func _work_stand(k: Kit, at: Vector3, w: float, d: float, h: float) -> void:
	var y := YELLOW
	for c: Vector2 in [Vector2(-w, -d), Vector2(w, -d), Vector2(-w, d), Vector2(w, d)]:
		k.box(at + Vector3(c.x * 0.5 - 0.05, 0, c.y * 0.5 - 0.05), at + Vector3(c.x * 0.5 + 0.05, h + 1.0, c.y * 0.5 + 0.05), y)
	k.box(at + Vector3(-w * 0.5, h - 0.08, -d * 0.5), at + Vector3(w * 0.5, h, d * 0.5), Color(0.45, 0.47, 0.48))
	for e: Array in [[Vector3(-w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, 0, -d * 0.5)], [Vector3(-w * 0.5, 0, d * 0.5), Vector3(w * 0.5, 0, d * 0.5)],
			[Vector3(w * 0.5, 0, -d * 0.5), Vector3(w * 0.5, 0, d * 0.5)]]:
		var p0: Vector3 = e[0]
		var p1: Vector3 = e[1]
		for yy: float in [h + 0.5, h + 1.0]:
			k.cyl(at + p0 + Vector3(0, yy, 0), at + p1 + Vector3(0, yy, 0), 0.03, 0.03, y, 6, false)
	# Treppe an der offenen Seite
	var steps := int(h / 0.25)
	for s in range(steps):
		var sy := float(s) * 0.25
		var sx := -w * 0.5 - (h - sy) * 0.6
		k.box(at + Vector3(sx, sy, -0.45), at + Vector3(sx + 0.3, sy + 0.05, 0.45), Color(0.45, 0.47, 0.48))
	for sz: float in [-0.48, 0.48]:
		k.cyl(at + Vector3(-w * 0.5 - h * 0.6, 0, sz), at + Vector3(-w * 0.5, h, sz), 0.04, 0.04, y, 6)
	for wc: Vector2 in [Vector2(-w, -d), Vector2(w, -d), Vector2(-w, d), Vector2(w, d)]:
		k.cyl(at + Vector3(wc.x * 0.5, 0.1, wc.y * 0.5), at + Vector3(wc.x * 0.5, 0.0, wc.y * 0.5), 0.1, 0.1, DARK, 8)


static func _hangar_annex(n: Node3D, k: Kit, clad: Color, rib: Color, rng: RandomNumberGenerator) -> void:
	var zb := H_Z1
	var zf := 18.0
	# Bürotrakt x -22..4
	k.box(Vector3(-22.0, 0, zb), Vector3(4.0, 7.4, zf), RENDER)
	k.box(Vector3(-22.08, 0, zb), Vector3(4.08, 0.6, zf + 0.08), CONCRETE)
	k.box(Vector3(-22.02, 3.55, zb), Vector3(4.02, 3.75, zf + 0.04), RENDER.darkened(0.08))
	_parapet(k, -22.0, zb, 4.0, zf, 7.4, 0.5, RENDER)
	k.box(Vector3(-21.75, 7.38, zb + 0.25), Vector3(3.75, 7.45, zf - 0.25), ROOF)
	for i in range(11):
		var cx := -20.4 + float(i) * 2.2
		_window(k, Vector3(cx, 5.4, zf), Vector3(0.8, 0, 0), Vector3(0, 0.75, 0), Vector3(0, 0, 1), 1)
		if i != 5:
			_window(k, Vector3(cx, 1.95, zf), Vector3(0.8, 0, 0), Vector3(0, 0.75, 0), Vector3(0, 0, 1), 1)
	for wz: float in [13.0, 16.0]:
		for wy: float in [1.95, 5.4]:
			_window(k, Vector3(-22.0, wy, wz), Vector3(0, 0, 0.7), Vector3(0, 0.75, 0), Vector3(-1, 0, 0), 1)
	# Eingang mit Vordach, Leuchte und Schild
	var ex := -20.4 + 5.0 * 2.2
	k.box(Vector3(ex - 0.85, 0.15, zf), Vector3(ex + 0.85, 2.55, zf + 0.06), FRAME)
	k.box(Vector3(ex - 0.75, 0.2, zf + 0.04), Vector3(ex - 0.03, 2.45, zf + 0.09), WIN)
	k.box(Vector3(ex + 0.03, 0.2, zf + 0.04), Vector3(ex + 0.75, 2.45, zf + 0.09), WIN)
	k.box(Vector3(ex - 1.6, 2.85, zf), Vector3(ex + 1.6, 3.05, zf + 1.5), CONCRETE.lightened(0.1))
	k.box(Vector3(ex - 0.4, 2.8, zf + 0.6), Vector3(ex + 0.4, 2.85, zf + 1.0), LAMP)
	k.box(Vector3(ex - 1.3, 0, zf), Vector3(ex + 1.3, 0.15, zf + 1.2), CONCRETE)
	PixelFont.draw(k, "FLUGZEUGWARTUNG", Vector3(-9.0, 9.6, zb + 0.09), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.2, WHITE)
	for b: float in [-17.0, -13.5, -5.5, -2.0]:
		k.box(Vector3(b - 0.12, 0, zf + 1.6), Vector3(b + 0.12, 0.9, zf + 1.84), YELLOW)
	_ac_unit(k, Vector3(-16.0, 7.45, 13.5), 2.7, 1.2)
	_ac_unit(k, Vector3(-4.0, 7.45, 13.5), 1.8, 1.0)
	# Windsack auf dem Dach
	var wm := Vector3(-20.6, 7.45, 16.8)
	k.cyl(wm, wm + Vector3(0, 6.2, 0), 0.07, 0.05, WHITE, 8)
	k.cyl(wm, wm + Vector3(0, 0.15, 0), 0.25, 0.25, STEEL, 8)
	var sk := Kit.new()
	var seg := 5
	for i in range(seg):
		var x0 := float(i) * 0.62
		var x1 := float(i + 1) * 0.62
		var drop0 := float(i * i) * 0.018
		var drop1 := float((i + 1) * (i + 1)) * 0.018
		sk.cyl(Vector3(x0 + 0.25, -drop0, 0), Vector3(x1 + 0.25, -drop1, 0), 0.42 - float(i) * 0.05, 0.42 - float(i + 1) * 0.05,
			Color(0.98, 0.45, 0.1) if i % 2 == 0 else WHITE, 12, false)
	sk.cyl(Vector3(0.2, 0, 0), Vector3(0.28, 0, 0), 0.45, 0.45, STEEL, 12, false)
	sk.box(Vector3(-0.05, -0.05, -0.05), Vector3(0.25, 0.05, 0.05), STEEL)
	var sock := _part(n, "SchwenkSack", sk, wm + Vector3(0, 5.9, 0))
	sock.set_meta("amp", 0.45)
	sock.set_meta("speed", 0.35)
	_blinker(n, wm + Vector3(0, 6.3, 0), RED_LAMP, 0.1, 2.0, 0.6)
	# Werkstatt x 4..22 mit Rolltor
	var wh := 5.6
	k.box(Vector3(4.0, 0, zb), Vector3(22.0, wh, zf), clad)
	k.box(Vector3(4.0, 0, zf - 0.05), Vector3(22.08, 0.7, zf + 0.08), CONCRETE)
	_parapet(k, 4.0, zb, 22.0, zf, wh, 0.35, clad.darkened(0.06))
	k.box(Vector3(4.25, wh - 0.02, zb + 0.25), Vector3(21.75, wh + 0.05, zf - 0.25), ROOF)
	var rx := 4.3
	while rx < 21.8:
		if rx < 9.0 or rx > 15.0:
			k.box(Vector3(rx - 0.05, 0.7, zf), Vector3(rx + 0.05, wh - 0.05, zf + 0.07), rib)
		else:
			k.box(Vector3(rx - 0.05, 4.8, zf), Vector3(rx + 0.05, wh - 0.05, zf + 0.07), rib)
		rx += 0.6
	var rz := zb + 0.3
	while rz < zf - 0.1:
		k.box(Vector3(22.0, 0.7, rz - 0.05), Vector3(22.07, wh - 0.05, rz + 0.05), rib)
		rz += 0.6
	k.box(Vector3(8.85, 0, zf), Vector3(15.15, 4.75, zf + 0.1), FRAME)
	k.box(Vector3(9.0, 0, zf + 0.06), Vector3(15.0, 4.6, zf + 0.12), Color(0.66, 0.68, 0.7))
	for i in range(20):
		k.box(Vector3(9.0, 0.15 + float(i) * 0.22, zf + 0.12), Vector3(15.0, 0.19 + float(i) * 0.22, zf + 0.15), Color(0.55, 0.57, 0.6))
	k.box(Vector3(11.2, 4.6, zf + 0.1), Vector3(12.8, 4.75, zf + 0.4), LAMP)
	k.box(Vector3(17.2, 0.1, zf), Vector3(18.4, 2.3, zf + 0.12), Color(0.45, 0.5, 0.55))
	k.box(Vector3(18.15, 1.0, zf + 0.12), Vector3(18.3, 1.08, zf + 0.2), STEEL)
	for wx: float in [18.6, 20.4]:
		_window(k, Vector3(wx + 0.5, 3.9, zf), Vector3(0.6, 0, 0), Vector3(0, 0.45, 0), Vector3(0, 0, 1), 1)
	_window(k, Vector3(22.0, 3.9, 14.5), Vector3(0, 0, 1.6), Vector3(0, 0.45, 0), Vector3(1, 0, 0), 3)
	_fan(n, k, Vector3(18.0, wh, 14.0), 0.7, 2.6)
	_ac_unit(k, Vector3(8.0, wh, 13.6), 1.8, 1.0)
	# Druckluftflaschen und Container neben der Werkstatt
	for i in range(4):
		k.cyl(Vector3(21.3 - float(i) * 0.4, 0.0, zf + 0.6), Vector3(21.3 - float(i) * 0.4, 1.5, zf + 0.6), 0.16, 0.16,
			[Color(0.2, 0.45, 0.8), Color(0.3, 0.6, 0.3), Color(0.6, 0.6, 0.62), Color(0.2, 0.45, 0.8)][i] as Color, 10)
		k.sphere(Vector3(21.3 - float(i) * 0.4, 1.5, zf + 0.6), 0.16, STEEL, 8, 4)
	k.box(Vector3(19.4, 1.1, zf + 0.35), Vector3(21.6, 1.15, zf + 0.85), STEEL)


# ================================================================== Tower

## Tower: Sockelbau mit Fensterbändern und Vordach, Schaft (klassisch mit Treppenhausfenstern
## oder modern schlank mit Glasstreifen), Betriebsgeschoss, Galerie mit Geländer und eine
## nach außen geneigte Kanzel aus durchsichtigem Glas mit Lotsen an den Pulten. Oben dreht
## sich das Radar, die Hindernisleuchte blinkt.
static func _tower(n: Node3D, k: Kit, opts: Dictionary) -> void:
	var modern := String(opts.get("stil", "klassisch")) == "modern"
	var shaft_col := Color(0.95, 0.95, 0.94) if modern else Color(0.84, 0.82, 0.76)
	# Sockelbau
	k.box(Vector3(-6.0, 0, -6.0), Vector3(6.0, 0.3, 6.0), CONCRETE)
	k.rounded_box(Vector3(-5.8, 0.3, -5.8), Vector3(5.8, 5.2, 5.8), 1.2, RENDER, 4)
	k.rounded_box(Vector3(-5.95, 5.2, -5.95), Vector3(5.95, 5.6, 5.95), 1.3, CONCRETE.lightened(0.12), 4)
	k.rounded_box(Vector3(-5.6, 5.6, -5.6), Vector3(5.6, 5.64, 5.6), 1.1, ROOF, 4)
	k.rounded_box(Vector3(-5.84, 0.3, -5.84), Vector3(5.84, 0.75, 5.84), 1.22, CONCRETE, 4)
	var faces := [[Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0)], [Vector3(1, 0, 0), Vector3(0, 0, -1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1)]]
	for f: Array in faces:
		var nrm: Vector3 = f[0]
		var right: Vector3 = f[1]
		for wy: float in [1.75, 3.95]:
			for cx: float in [-3.3, -1.1, 1.1, 3.3]:
				if nrm.z > 0.5 and wy < 2.5 and absf(cx) < 2.0:
					continue
				_window(k, nrm * 5.8 + right * cx + Vector3(0, wy, 0), right * 0.95, Vector3(0, 0.62, 0), nrm, 1)
	# Eingang mit Glastür, Vordach und Schrift
	k.box(Vector3(-1.4, 0.3, 5.8), Vector3(1.4, 2.7, 5.88), FRAME)
	k.box(Vector3(-1.3, 0.35, 5.86), Vector3(-0.03, 2.6, 5.92), WIN)
	k.box(Vector3(0.03, 0.35, 5.86), Vector3(1.3, 2.6, 5.92), WIN)
	k.box(Vector3(-0.15, 1.2, 5.92), Vector3(-0.1, 1.8, 6.0), STEEL)
	k.box(Vector3(0.1, 1.2, 5.92), Vector3(0.15, 1.8, 6.0), STEEL)
	k.box(Vector3(-2.3, 2.95, 5.8), Vector3(2.3, 3.15, 7.7), CONCRETE.lightened(0.12))
	k.box(Vector3(-2.3, 2.8, 7.55), Vector3(2.3, 3.2, 7.7), Color(0.2, 0.3, 0.45))
	PixelFont.draw(k, "FLUGSICHERUNG", Vector3(0, 3.0, 7.71), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.042, WHITE)
	for lx: float in [-1.2, 1.2]:
		k.box(Vector3(lx - 0.25, 2.9, 6.6), Vector3(lx + 0.25, 2.95, 7.0), LAMP)
	k.box(Vector3(-2.0, 0.0, 5.8), Vector3(2.0, 0.3, 7.4), CONCRETE.lightened(0.05))
	for b: float in [-3.2, 3.2]:
		k.cyl(Vector3(b, 0, 7.2), Vector3(b, 0.9, 7.2), 0.12, 0.12, STEEL, 8)
		k.cyl(Vector3(b, 0.75, 7.2), Vector3(b, 0.82, 7.2), 0.125, 0.125, WHITE, 8)
	_ac_unit(k, Vector3(-3.4, 5.64, -3.2), 1.8, 1.0)
	_ac_unit(k, Vector3(3.2, 5.64, -3.6), 1.8, 1.0)
	k.cyl(Vector3(3.8, 5.64, 3.4), Vector3(3.8, 6.4, 3.4), 0.05, 0.05, STEEL, 6)
	k.sphere(Vector3(3.8, 6.6, 3.4), 0.42, WHITE, 10, 5, Vector3(1.0, 1.0, 0.35))
	# Schaft
	var y0 := 5.6
	var y1 := 27.4
	if modern:
		k.cyl(Vector3(0, y0, 0), Vector3(0, y1, 0), 2.15, 1.55, shaft_col, 28, false)
		var steps := 22
		for i in range(steps):
			var ya := y0 + (y1 - y0) * float(i) / float(steps)
			var yb := y0 + (y1 - y0) * float(i + 1) / float(steps)
			var ra := lerpf(2.15, 1.55, float(i) / float(steps)) + 0.02
			var rb := lerpf(2.15, 1.55, float(i + 1) / float(steps)) + 0.02
			k.quad(Vector3(-0.42, ya, ra - 0.04), Vector3(0.42, ya, ra - 0.04), Vector3(0.42, yb, rb - 0.04), Vector3(-0.42, yb, rb - 0.04), WIN, Vector3(0, (ya + yb) * 0.5, 0))
			k.quad(Vector3(ra - 0.04, ya, -0.3), Vector3(ra - 0.04, ya, 0.3), Vector3(rb - 0.04, yb, 0.3), Vector3(rb - 0.04, yb, -0.3), WIN, Vector3(0, (ya + yb) * 0.5, 0))
		for fx: float in [-0.55, 0.55]:
			k.cyl(Vector3(fx, y0, 2.15), Vector3(fx, y1, 1.55), 0.06, 0.06, Color(0.75, 0.76, 0.78), 6)
		for fz: float in [-0.43, 0.43]:
			k.cyl(Vector3(2.15, y0, fz), Vector3(1.55, y1, fz), 0.06, 0.06, Color(0.75, 0.76, 0.78), 6)
		# Kelch unter der Kanzel
		k.cyl(Vector3(0, 24.6, 0), Vector3(0, 28.4, 0), 1.6, 4.1, shaft_col, 28, false)
		k.cyl(Vector3(0, 28.4, 0), Vector3(0, 29.0, 0), 4.1, 4.2, Color(0.82, 0.83, 0.85), 28)
		for i in range(14):
			var ang := TAU * float(i) / 14.0
			var d := Vector3(cos(ang), 0, sin(ang))
			k.cyl(d * 1.75 + Vector3(0, 25.0, 0), d * 3.9 + Vector3(0, 28.2, 0), 0.04, 0.04, WIN, 4, false)
	else:
		k.cyl(Vector3(0, y0, 0), Vector3(0, y1, 0), 2.4, 2.2, shaft_col, 28, false)
		var jy := y0 + 2.2
		while jy < y1 - 0.5:
			var rr := lerpf(2.4, 2.2, (jy - y0) / (y1 - y0)) + 0.015
			k.cyl(Vector3(0, jy, 0), Vector3(0, jy + 0.05, 0), rr, rr, shaft_col.darkened(0.12), 28, false)
			jy += 2.2
		for i in range(10):
			var wy := 7.0 + float(i) * 2.0
			var rr := lerpf(2.4, 2.2, (wy - y0) / (y1 - y0))
			var ang := PI * 0.5 + (0.35 if i % 2 == 0 else -0.35)
			var d := Vector3(cos(ang), 0, sin(ang))
			var tang := Vector3(-sin(ang), 0, cos(ang))
			_window(k, d * (rr + 0.01) + Vector3(0, wy, 0), tang * 0.28, Vector3(0, 0.5, 0), d, 0, false)
		# Steigschacht mit Kabelleiter
		k.box(Vector3(-3.0, y0, -0.8), Vector3(-2.1, y1, 0.8), shaft_col.darkened(0.06))
		var ly := y0 + 0.5
		while ly < y1:
			k.box(Vector3(-3.06, ly, -0.3), Vector3(-3.0, ly + 0.04, 0.3), STEEL)
			ly += 0.5
		# Betriebsgeschoss mit kleinen Fenstern
		k.cyl(Vector3(0, y1, 0), Vector3(0, 29.0, 0), 3.5, 3.5, Color(0.8, 0.79, 0.74), 28)
		k.cyl(Vector3(0, y1 - 0.15, 0), Vector3(0, y1, 0), 2.2, 3.5, CONCRETE, 28, false)
		for i in range(16):
			var ang := TAU * float(i) / 16.0
			var d := Vector3(cos(ang), 0, sin(ang))
			_window(k, d * 3.51 + Vector3(0, 28.2, 0), Vector3(-sin(ang), 0, cos(ang)) * 0.35, Vector3(0, 0.32, 0), d, 0, false)
	# Galerie mit Geländer
	k.cyl(Vector3(0, 29.0, 0), Vector3(0, 29.22, 0), 5.7, 5.7, CONCRETE.lightened(0.05), 32)
	k.cyl(Vector3(0, 28.85, 0), Vector3(0, 29.0, 0), 4.0, 5.65, CONCRETE.darkened(0.08), 32, false)
	var posts := 32
	for i in range(posts):
		var a0 := TAU * float(i) / float(posts)
		var a1 := TAU * float(i + 1) / float(posts)
		var p0 := Vector3(cos(a0), 0, sin(a0)) * 5.55
		var p1 := Vector3(cos(a1), 0, sin(a1)) * 5.55
		k.box(p0 + Vector3(-0.03, 29.22, -0.03), p0 + Vector3(0.03, 30.25, 0.03), STEEL)
		k.cyl(p0 + Vector3(0, 30.25, 0), p1 + Vector3(0, 30.25, 0), 0.04, 0.04, STEEL, 6, false)
		k.cyl(p0 + Vector3(0, 29.75, 0), p1 + Vector3(0, 29.75, 0), 0.02, 0.02, STEEL, 4, false)
	# Kanzel: Brüstung, schräg nach außen geneigte Scheiben (durchsichtig), Pfosten
	var sides := 16
	var cb := 30.0
	var ct := 33.2
	var rb := 4.45
	var rt := 4.95
	k.cyl(Vector3(0, 29.22, 0), Vector3(0, cb, 0), 4.4, rb, Color(0.3, 0.32, 0.35), sides)
	k.cyl(Vector3(0, 29.24, 0), Vector3(0, 29.26, 0), 4.2, 4.2, Color(0.42, 0.44, 0.47), sides)
	var gk := Kit.new()
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		gk.quad(d0 * rb + Vector3(0, cb, 0), d1 * rb + Vector3(0, cb, 0), d1 * rt + Vector3(0, ct, 0), d0 * rt + Vector3(0, ct, 0), WHITE, Vector3(0, (cb + ct) * 0.5, 0))
		k.cyl(d0 * rb + Vector3(0, cb, 0), d0 * rt + Vector3(0, ct, 0), 0.07, 0.07, FRAME, 6)
	_glass_part(n, gk)
	k.cyl(Vector3(0, ct, 0), Vector3(0, ct + 0.25, 0), rt + 0.05, rt + 0.05, FRAME, sides)
	# Pulte mit Bildschirmen, Kern mit Treppe, Lotsen
	for i in range(12):
		if i == 9:
			continue
		var ang := TAU * (float(i) + 0.5) / 12.0
		var d := Vector3(cos(ang), 0, sin(ang))
		var tang := Vector3(-sin(ang), 0, cos(ang))
		var c := d * 3.75 + Vector3(0, 29.26, 0)
		k.box(c - tang * 0.85 - d * 0.35, c + tang * 0.85 + d * 0.35 + Vector3(0, 0.95, 0), Color(0.26, 0.27, 0.3))
		var sc := c - d * 0.12 + Vector3(0, 1.22, 0)
		k.panel(sc - tang * 0.35, tang * 0.25, Vector3(0, 0.18, 0) + d * 0.05, Color(0.3, 0.75, 0.9, 0.3), -d)
		k.panel(sc + tang * 0.35, tang * 0.25, Vector3(0, 0.18, 0) + d * 0.05, Color(0.35, 0.85, 0.5, 0.3), -d)
		k.box(sc - tang * 0.62 - Vector3(0, 0.22, 0) - d * 0.03, sc + tang * 0.62 - Vector3(0, 0.18, 0) + d * 0.03, DARK)
	k.cyl(Vector3(0, 29.26, 0), Vector3(0, ct, 0), 1.1, 1.1, Color(0.7, 0.7, 0.68), 16)
	var Factory = load("res://scripts/factory.gd")
	for e: Array in [[0.3, 0], [2.4, 2], [4.4, 0]]:
		var ang: float = e[0]
		var ctl: Node3D = Factory.make_person([Color(0.92, 0.92, 0.9), Color(0.2, 0.3, 0.5), Color(0.55, 0.6, 0.68)][int(e[1]) % 3] as Color, -1)
		ctl.position = Vector3(cos(ang), 0, sin(ang)) * 2.85 + Vector3(0, 29.26, 0)
		ctl.rotation.y = -ang - PI * 0.5
		n.add_child(ctl)
	# Kanzeldach mit Technikraum, Radar, Radom und Antennenmast
	k.cyl(Vector3(0, ct + 0.25, 0), Vector3(0, ct + 0.75, 0), rt + 0.45, rt - 0.2, ROOF, 32)
	k.cyl(Vector3(0, ct + 0.2, 0), Vector3(0, ct + 0.25, 0), rt + 0.45, rt + 0.45, STEEL, 32)
	k.cyl(Vector3(0, ct + 0.75, 0), Vector3(0, ct + 1.7, 0), 2.1, 2.0, Color(0.8, 0.8, 0.78), 20)
	k.cyl(Vector3(0, ct + 1.7, 0), Vector3(0, ct + 1.8, 0), 2.15, 2.15, ROOF, 20)
	for i in range(8):
		var ang := TAU * float(i) / 8.0
		var d := Vector3(cos(ang), 0, sin(ang))
		k.box(d * 2.09 + Vector3(-0.12, ct + 1.1, -0.12), d * 2.11 + Vector3(0.12, ct + 1.4, 0.12), Color(0.5, 0.52, 0.54))
	var rp := Vector3(0, ct + 1.8, 0)
	k.cyl(rp, rp + Vector3(0, 0.9, 0), 0.35, 0.25, STEEL, 12)
	var rk := Kit.new()
	var cols := 9
	for i in range(cols):
		var xa := -1.7 + 3.4 * float(i) / float(cols)
		var xb := -1.7 + 3.4 * float(i + 1) / float(cols)
		var za := -0.32 * (1.0 - pow(xa / 1.7, 2.0))
		var zb := -0.32 * (1.0 - pow(xb / 1.7, 2.0))
		rk.quad(Vector3(xa, 0.15, za), Vector3(xb, 0.15, zb), Vector3(xb, 1.05, zb), Vector3(xa, 1.05, za), Color(0.86, 0.87, 0.88), Vector3(0, 0.6, 1.0))
		for sy: float in [0.35, 0.6, 0.85]:
			rk.quad(Vector3(xa, sy, za - 0.01), Vector3(xb, sy, zb - 0.01), Vector3(xb, sy + 0.03, zb - 0.01), Vector3(xa, sy + 0.03, za - 0.01), STEEL, Vector3(0, sy, 1.0))
	rk.box(Vector3(-0.15, 0.0, -0.1), Vector3(0.15, 0.2, 0.25), STEEL)
	rk.cyl(Vector3(0, 0.25, 0.0), Vector3(0, 0.3, -0.9), 0.04, 0.04, STEEL, 6)
	rk.box(Vector3(-0.12, 0.2, -1.02), Vector3(0.12, 0.42, -0.86), DARK)
	var radar := _part(n, "DrehRadar", rk, rp + Vector3(0, 0.9, 0))
	radar.set_meta("speed", 1.25)
	k.cyl(Vector3(1.55, ct + 1.8, 1.1), Vector3(1.55, ct + 2.1, 1.1), 0.35, 0.35, STEEL, 10)
	k.sphere(Vector3(1.55, ct + 2.75, 1.1), 0.72, WHITE, 14, 8)
	var mp := Vector3(-1.2, ct + 1.8, -1.1)
	k.cyl(mp, mp + Vector3(0, 4.3, 0), 0.07, 0.05, Color(0.85, 0.2, 0.15), 6)
	for i in range(4):
		k.box(mp + Vector3(-0.02, 0.6 + float(i) * 1.0, -0.02), mp + Vector3(0.02, 0.62 + float(i) * 1.0, 0.02), WHITE)
	k.box(mp + Vector3(-0.6, 3.2, -0.02), mp + Vector3(0.6, 3.25, 0.02), DARK)
	k.box(mp + Vector3(-0.6, 3.0, -0.02), mp + Vector3(-0.56, 3.5, 0.02), DARK)
	k.box(mp + Vector3(0.56, 3.0, -0.02), mp + Vector3(0.6, 3.5, 0.02), DARK)
	k.cyl(Vector3(1.4, ct + 1.8, -1.2), Vector3(1.4, ct + 3.6, -1.2), 0.03, 0.02, DARK, 5)
	_blinker(n, mp + Vector3(0, 4.4, 0), RED_LAMP, 0.13, 1.6, 0.0)


# ================================================================== Feuerwache

## Feuerwache: Fahrzeughalle aus Klinker mit drei Sektionaltoren (zwei offen, drinnen
## Schutzkleidung, Abgasabsaugung, Schlauchlager), Bürotrakt mit Eingang und Notrufschild,
## Schlauchturm mit Sirene und Blaulicht, Solardach, Fahne, zwei Flugfeldlöschfahrzeuge.
static func _fire_station(n: Node3D, k: Kit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 112
	var joint := BRICK.darkened(0.22)
	# Hof mit Markierungen
	k.box(Vector3(-15.0, 0, 4.0), Vector3(15.0, 0.06, 10.0), Color(0.62, 0.62, 0.59))
	for bx: float in [-15.0, -8.0, -1.0, 6.0]:
		k.box(Vector3(bx - 0.07, 0.06, 4.2), Vector3(bx + 0.07, 0.07, 9.8), YELLOW)
	k.box(Vector3(-15.0, 0.06, 9.75), Vector3(6.0, 0.07, 9.88), YELLOW)
	PixelFont.draw_ground(k, "FREIHALTEN", Vector3(-4.5, 0.075, 7.6), Vector3(0, 0, -1), 0.1, WHITE)
	# Fahrzeughalle x -15..6, z -10..4
	var hh := 7.5
	var bays := [[-11.5, true], [-4.5, false], [2.5, true]]
	k.box(Vector3(-15.0, 0, -10.0), Vector3(6.0, 0.08, 4.0), Color(0.56, 0.57, 0.56))
	k.box(Vector3(-15.0, 0, -10.0), Vector3(6.0, hh, -9.7), BRICK)
	k.box(Vector3(-15.0, 0, -10.0), Vector3(-14.7, hh, 4.0), BRICK)
	k.box(Vector3(5.7, 0, -10.0), Vector3(6.0, hh, 4.0), BRICK)
	k.box(Vector3(-15.0, 5.4, 3.7), Vector3(6.0, hh, 4.0), BRICK)
	for pier: Vector2 in [Vector2(-15.0, -14.2), Vector2(-8.8, -7.2), Vector2(-1.8, -0.2), Vector2(5.2, 6.0)]:
		k.box(Vector3(pier.x, 0, 3.7), Vector3(pier.y, 5.4, 4.0), BRICK)
		_joints(k, Vector3(pier.x, 0.4, 4.0), Vector3(pier.y, 5.4, 4.0), Vector3(0, 0, 1), 0.27, joint)
	_joints(k, Vector3(-15.0, 5.4, 4.0), Vector3(6.0, hh, 4.0), Vector3(0, 0, 1), 0.27, joint)
	_joints(k, Vector3(-15.0, 0.4, -10.0), Vector3(6.0, hh, -10.0), Vector3(0, 0, -1), 0.27, joint)
	_joints(k, Vector3(-15.0, 0.4, -10.0), Vector3(-15.0, hh, 4.0), Vector3(-1, 0, 0), 0.27, joint)
	k.box(Vector3(-15.05, 0, -10.05), Vector3(6.0, 0.4, 4.05), CONCRETE)
	k.box(Vector3(-15.0, hh - 0.3, -10.0), Vector3(6.0, hh, 4.0), CONCRETE)
	k.box(Vector3(-14.7, hh, -9.7), Vector3(5.7, hh + 0.04, 3.7), GRAVEL)
	_parapet(k, -15.0, -10.0, 6.0, 4.0, hh, 0.55, BRICK)
	for i in range(4):
		var wx := -12.5 + float(i) * 5.0
		_window(k, Vector3(wx, 4.6, -10.0), Vector3(1.2, 0, 0), Vector3(0, 0.55, 0), Vector3(0, 0, -1), 2)
	for wz: float in [-6.5, -1.5]:
		_window(k, Vector3(-15.0, 4.6, wz), Vector3(0, 0, 1.2), Vector3(0, 0.55, 0), Vector3(-1, 0, 0), 2)
	PixelFont.draw(k, "FEUERWEHR", Vector3(-4.5, 6.5, 4.02), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.12, WHITE)
	# Tore
	for b: Array in bays:
		var cx: float = b[0]
		k.box(Vector3(cx - 3.0, 5.4, 4.0), Vector3(cx + 3.0, 5.75, 4.14), CONCRETE.lightened(0.08))
		k.box(Vector3(cx - 2.78, 0, 3.72), Vector3(cx - 2.66, 5.4, 4.06), FRAME)
		k.box(Vector3(cx + 2.66, 0, 3.72), Vector3(cx + 2.78, 5.4, 4.06), FRAME)
		for sx: float in [-1.0, 1.0]:
			var bp := Vector3(cx + sx * 3.25, 0, 4.45)
			k.cyl(bp, bp + Vector3(0, 1.0, 0), 0.13, 0.13, YELLOW, 10)
			for j in range(2):
				k.cyl(bp + Vector3(0, 0.25 + float(j) * 0.4, 0), bp + Vector3(0, 0.45 + float(j) * 0.4, 0), 0.135, 0.135, DARK, 10)
		# Rolltor (geht auf, bevor ein Fahrzeug ausrückt) und Löschfahrzeug dahinter
		roll_door(n, k, bays.find(b), Vector3(cx, 0, 3.86), 5.4, 5.3, FIRE_RED, 4)
		var lf := MeshInstance3D.new()
		lf.name = "LF%d" % bays.find(b)
		lf.mesh = fire_truck_mesh()
		lf.position = Vector3(cx, 0.08, -1.6)
		lf.rotation.y = PI
		lf.set_meta("no_bake", true)
		n.add_child(lf)
		# Innen: Spinde mit Schutzkleidung und Helmen, Abgasschlauch, Leuchten
		k.box(Vector3(cx - 2.5, 0.08, -9.7), Vector3(cx + 2.5, 2.3, -9.25), STEEL)
		for i in range(8):
			var jx := cx - 2.3 + float(i) * 0.58
			k.box(Vector3(jx, 1.0, -9.25), Vector3(jx + 0.42, 1.95, -9.05), Color(0.72, 0.6, 0.36))
			k.box(Vector3(jx, 1.3, -9.06), Vector3(jx + 0.42, 1.36, -9.03), Color(0.85, 0.85, 0.3))
			k.sphere(Vector3(jx + 0.21, 2.15, -9.3), 0.14, Color(0.9, 0.9, 0.85), 8, 4)
			k.box(Vector3(jx + 0.05, 0.08, -9.2), Vector3(jx + 0.37, 0.4, -8.95), DARK)
		k.cyl(Vector3(cx, hh - 0.3, -4.5), Vector3(cx, 3.9, -4.5), 0.13, 0.13, DARK, 8)
		k.cyl(Vector3(cx, 3.9, -4.5), Vector3(cx, 3.5, -4.5), 0.18, 0.2, Color(0.8, 0.2, 0.15), 8)
		k.box(Vector3(cx - 0.05, hh - 0.4, -9.5), Vector3(cx + 0.05, hh - 0.3, 3.5), STEEL)
		for lz: float in [-6.5, -1.0]:
			k.box(Vector3(cx - 0.9, hh - 0.44, lz), Vector3(cx + 0.9, hh - 0.36, lz + 0.3), LAMP)
	# Schlauchlager an der linken Innenwand
	for r in range(3):
		for c in range(4):
			var hp := Vector3(-14.55, 0.5 + float(r) * 0.62, -8.0 + float(c) * 0.7)
			k.cyl(hp, hp + Vector3(0.22, 0, 0), 0.3, 0.3, Color(0.88, 0.86, 0.8), 12, true, Color(0.75, 0.72, 0.65))
	# Solardach auf der Halle
	var pn := Vector3(0, 1.4, 0.6).normalized()
	for r in range(5):
		var zf := -9.1 + float(r) * 2.45
		var x0 := -14.2
		var x1 := 5.2
		var lo := Vector3(0, hh + 0.3, zf + 1.4)
		var hi := Vector3(0, hh + 0.9, zf)
		k.quad(Vector3(x0, lo.y, lo.z), Vector3(x1, lo.y, lo.z), Vector3(x1, hi.y, hi.z), Vector3(x0, hi.y, hi.z), Color(0.12, 0.17, 0.32), Vector3((x0 + x1) * 0.5, hh, zf + 0.3))
		var gxp := x0
		while gxp <= x1 + 0.01:
			k.quad(Vector3(gxp - 0.025, lo.y, lo.z) + pn * 0.01, Vector3(gxp + 0.025, lo.y, lo.z) + pn * 0.01, Vector3(gxp + 0.025, hi.y, hi.z) + pn * 0.01,
				Vector3(gxp - 0.025, hi.y, hi.z) + pn * 0.01, Color(0.7, 0.72, 0.75), Vector3(gxp, hh, zf + 0.3))
			gxp += 1.0
		var mid := (lo + hi) * 0.5
		k.quad(Vector3(x0, mid.y - 0.02, mid.z) + pn * 0.01, Vector3(x1, mid.y - 0.02, mid.z) + pn * 0.01, Vector3(x1, mid.y + 0.02, mid.z) + pn * 0.01,
			Vector3(x0, mid.y + 0.02, mid.z) + pn * 0.01, Color(0.7, 0.72, 0.75), Vector3(0, hh, zf + 0.3))
		for sx: float in [x0 + 0.5, (x0 + x1) * 0.5, x1 - 0.5]:
			k.box(Vector3(sx - 0.05, hh, zf + 0.05), Vector3(sx + 0.05, hh + 0.88, zf + 0.15), STEEL)
	# Bürotrakt x 6..15 (zwei Geschosse) mit Eingang
	var oh := 7.6
	k.box(Vector3(6.0, 0, -5.0), Vector3(15.0, oh, 4.0), RENDER)
	k.box(Vector3(6.0, 0, -10.0), Vector3(10.0, oh, -5.0), RENDER)
	k.box(Vector3(6.0, 0, -10.05), Vector3(15.05, 0.5, 4.05), CONCRETE)
	k.box(Vector3(6.0, 3.6, 3.99), Vector3(15.02, 3.8, 4.04), RENDER.darkened(0.08))
	k.box(Vector3(14.99, 3.6, -5.0), Vector3(15.04, 3.8, 4.0), RENDER.darkened(0.08))
	k.box(Vector3(6.0, oh - 0.55, 3.99), Vector3(15.03, oh, 4.06), FIRE_RED)
	k.box(Vector3(14.98, oh - 0.55, -5.0), Vector3(15.06, oh, 4.06), FIRE_RED)
	_parapet(k, 6.0, -10.0, 15.0, 4.0, oh, 0.4, RENDER)
	k.box(Vector3(6.25, oh - 0.02, -9.75), Vector3(14.75, oh + 0.04, 3.75), GRAVEL)
	for wx: float in [7.6, 9.8, 12.0, 14.0]:
		_window(k, Vector3(wx, 5.35, 4.0), Vector3(0.7, 0, 0), Vector3(0, 0.7, 0), Vector3(0, 0, 1), 1)
		if absf(wx - 12.0) > 0.1:
			_window(k, Vector3(wx, 1.85, 4.0), Vector3(0.7, 0, 0), Vector3(0, 0.7, 0), Vector3(0, 0, 1), 1)
	for wz: float in [-3.2, -0.6, 2.2]:
		for wy: float in [1.85, 5.35]:
			_window(k, Vector3(15.0, wy, wz), Vector3(0, 0, -0.75), Vector3(0, 0.7, 0), Vector3(1, 0, 0), 1)
	for wx: float in [7.2, 8.8]:
		_window(k, Vector3(wx, 5.35, -10.0), Vector3(-0.55, 0, 0), Vector3(0, 0.6, 0), Vector3(0, 0, -1), 0)
	k.box(Vector3(11.1, 0.5, 4.0), Vector3(12.9, 2.7, 4.06), FRAME)
	k.box(Vector3(11.2, 0.55, 4.04), Vector3(11.97, 2.6, 4.1), WIN)
	k.box(Vector3(12.03, 0.55, 4.04), Vector3(12.8, 2.6, 4.1), WIN)
	k.box(Vector3(10.6, 2.9, 4.0), Vector3(13.4, 3.1, 5.6), CONCRETE.lightened(0.12))
	k.box(Vector3(11.6, 2.85, 4.8), Vector3(12.4, 2.9, 5.2), LAMP)
	k.box(Vector3(10.8, 0, 4.0), Vector3(13.2, 0.5, 5.3), CONCRETE.lightened(0.05))
	k.box(Vector3(13.4, 2.2, 4.0), Vector3(14.75, 3.0, 4.07), FIRE_RED)
	PixelFont.draw(k, "112", Vector3(14.07, 2.6, 4.08), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.08, WHITE)
	_wall_lamp(k, Vector3(10.4, 2.4, 4.0), Vector3(0, 0, 1))
	_ac_unit(k, Vector3(8.0, oh, 1.0), 1.8, 1.0)
	# Schlauchturm x 10..15, z -10..-5
	var th := 13.0
	k.box(Vector3(10.0, 0, -10.0), Vector3(15.0, th, -5.0), BRICK)
	_joints(k, Vector3(10.0, 0.5, -10.0), Vector3(15.0, th, -10.0), Vector3(0, 0, -1), 0.27, joint)
	_joints(k, Vector3(15.0, 0.5, -10.0), Vector3(15.0, th, -5.0), Vector3(1, 0, 0), 0.27, joint)
	_joints(k, Vector3(10.0, oh + 0.1, -5.0), Vector3(15.0, th, -5.0), Vector3(0, 0, 1), 0.27, joint)
	_joints(k, Vector3(10.0, oh + 0.1, -10.0), Vector3(10.0, th, -5.0), Vector3(-1, 0, 0), 0.27, joint)
	for wy: float in [2.0, 5.4, 9.2]:
		_window(k, Vector3(15.0, wy, -7.5), Vector3(0, 0, -0.5), Vector3(0, 0.75, 0), Vector3(1, 0, 0), 0)
	_window(k, Vector3(12.5, 9.2, -5.0), Vector3(0.5, 0, 0), Vector3(0, 0.75, 0), Vector3(0, 0, 1), 0)
	for f: Array in [[Vector3(1, 0, 0), Vector3(15.0, 0, -7.5), Vector3(0, 0, 1)], [Vector3(0, 0, 1), Vector3(12.5, 0, -5.0), Vector3(1, 0, 0)],
			[Vector3(0, 0, -1), Vector3(12.5, 0, -10.0), Vector3(1, 0, 0)], [Vector3(-1, 0, 0), Vector3(10.0, 0, -7.5), Vector3(0, 0, 1)]]:
		var nrm: Vector3 = f[0]
		var c: Vector3 = f[1]
		var side: Vector3 = f[2]
		k.box(c + Vector3(0, 11.0, 0) - side * 1.6, c + Vector3(0, 12.4, 0) + side * 1.6 + nrm * 0.03, DARK)
		for s in range(6):
			var sy := 11.1 + float(s) * 0.22
			k.box(c + Vector3(0, sy, 0) - side * 1.6 + nrm * 0.03, c + Vector3(0, sy + 0.06, 0) + side * 1.6 + nrm * 0.1, BRICK.lightened(0.15))
	k.box(Vector3(9.8, th, -10.2), Vector3(15.2, th + 0.35, -4.8), CONCRETE.lightened(0.1))
	# Sirene, Blaulicht, Antenne
	var sp := Vector3(12.5, th + 0.35, -7.5)
	for leg: Vector3 in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0, 0, 0.6)]:
		k.cyl(sp + leg, sp + Vector3(0, 1.6, 0), 0.04, 0.04, STEEL, 6)
	k.cyl(sp + Vector3(0, 1.6, 0), sp + Vector3(0, 2.2, 0), 0.32, 0.32, Color(0.75, 0.76, 0.77), 14)
	k.cyl(sp + Vector3(0, 1.75, 0), sp + Vector3(0, 2.05, 0), 0.34, 0.34, DARK, 14, false)
	k.cyl(sp + Vector3(0, 2.2, 0), sp + Vector3(0, 2.32, 0), 0.5, 0.42, Color(0.75, 0.76, 0.77), 14)
	_blinker(n, Vector3(14.5, th + 0.6, -5.5), BLUE_LAMP, 0.18, 0.8, 0.0)
	_blinker(n, Vector3(10.5, th + 0.6, -9.5), BLUE_LAMP, 0.18, 0.8, 0.4)
	k.cyl(Vector3(14.5, th + 0.35, -5.5), Vector3(14.5, th + 0.45, -5.5), 0.2, 0.2, DARK, 8)
	k.cyl(Vector3(10.5, th + 0.35, -9.5), Vector3(10.5, th + 0.45, -9.5), 0.2, 0.2, DARK, 8)
	k.cyl(Vector3(14.6, th + 0.35, -9.6), Vector3(14.6, th + 3.4, -9.6), 0.03, 0.02, DARK, 5)
	# Fahnenmast mit Fahne, Hydrant
	var fp := Vector3(14.3, 0, 8.8)
	k.cyl(fp, fp + Vector3(0, 0.25, 0), 0.25, 0.25, CONCRETE, 10)
	k.cyl(fp, fp + Vector3(0, 9.2, 0), 0.07, 0.05, WHITE, 8)
	k.sphere(fp + Vector3(0, 9.25, 0), 0.09, YELLOW, 8, 4)
	var fk := Kit.new()
	var strips := 6
	for i in range(strips):
		var xa := 0.08 + float(i) * 0.28
		var xb := xa + 0.28
		var za := sin(float(i) * 1.3) * 0.08
		var zb := sin(float(i + 1) * 1.3) * 0.08
		fk.quad(Vector3(xa, -1.05, za), Vector3(xb, -1.05, zb), Vector3(xb, 0, zb), Vector3(xa, 0, za), FIRE_RED, Vector3((xa + xb) * 0.5, -0.5, 1.0))
		fk.quad(Vector3(xa, -0.6, za + 0.005), Vector3(xb, -0.6, zb + 0.005), Vector3(xb, -0.45, zb + 0.005), Vector3(xa, -0.45, za + 0.005), WHITE, Vector3((xa + xb) * 0.5, -0.5, 1.0))
		fk.quad(Vector3(xa, -0.6, za - 0.005), Vector3(xb, -0.6, zb - 0.005), Vector3(xb, -0.45, zb - 0.005), Vector3(xa, -0.45, za - 0.005), WHITE, Vector3((xa + xb) * 0.5, -0.5, -1.0))
	var flag := _part(n, "SchwenkFahne", fk, fp + Vector3(0, 9.1, 0))
	flag.set_meta("amp", 0.35)
	flag.set_meta("speed", 0.7)
	var hy := Vector3(-14.3, 0, 9.3)
	k.cyl(hy, hy + Vector3(0, 0.8, 0), 0.14, 0.14, FIRE_RED, 10)
	k.sphere(hy + Vector3(0, 0.8, 0), 0.14, FIRE_RED, 10, 5)
	k.cyl(hy + Vector3(-0.25, 0.5, 0), hy + Vector3(0.25, 0.5, 0), 0.06, 0.06, Color(0.85, 0.85, 0.82), 8)
	# Kommandowagen auf dem Hof
	k.add_mesh(Models.car_mesh("suv", FIRE_RED), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(9.0, 0.06, 7.8)), true)
	k.box(Vector3(8.45, 1.72, 7.5), Vector3(9.55, 1.82, 8.1), DARK)
	k.box(Vector3(8.4, 1.74, 7.55), Vector3(8.7, 1.86, 8.05), BLUE_LAMP)
	k.box(Vector3(9.3, 1.74, 7.55), Vector3(9.6, 1.86, 8.05), BLUE_LAMP)


## Großes Flugfeldlöschfahrzeug (6x6, Front -z): Kabine mit großer Scheibe, Dach- und
## Frontwerfer, Rollläden, Laufsteg mit Geländer, Blaulichter, Warnmarkierung hinten.
## Rettungswagen: Fahrerhaus mit Haube, Kofferaufbau, rot-gelbe Warnmarkierung, Schriftzug,
## Blaulichtbalken. Front -Z (Fahrtrichtung). Die blinkenden Blaulichter baut rtw_node() dazu.
static func rtw_mesh() -> ArrayMesh:
	var k := Kit.new()
	var white := Color(0.95, 0.95, 0.93)
	var red := Color(0.85, 0.1, 0.08)
	var yellow := Color(0.98, 0.85, 0.1)
	var glass := Color(0.15, 0.2, 0.25)
	# Räder
	for z: float in [-2.35, 2.0]:
		for sx: float in [-1.0, 1.0]:
			k.cyl(Vector3(sx * 0.95, 0.38, z), Vector3(sx * 1.12, 0.38, z), 0.38, 0.38, Color(0.08, 0.08, 0.08), 12)
			k.cyl(Vector3(sx * 1.1, 0.38, z), Vector3(sx * 1.13, 0.38, z), 0.22, 0.22, Color(0.7, 0.71, 0.72), 10)
	# Fahrgestell, Haube, Fahrerhaus
	k.box(Vector3(-0.95, 0.35, -3.4), Vector3(0.95, 0.55, 3.3), Color(0.2, 0.2, 0.22))
	k.box(Vector3(-1.0, 0.55, -3.45), Vector3(1.0, 1.25, -2.75), white)
	k.box(Vector3(-0.95, 0.55, -3.5), Vector3(0.95, 0.85, -3.45), Color(0.15, 0.15, 0.16))
	for sx: float in [-0.7, 0.7]:
		k.box(Vector3(sx - 0.2, 0.95, -3.48), Vector3(sx + 0.2, 1.12, -3.44), Color(1.0, 0.98, 0.85, 0.3))
	k.box(Vector3(-1.02, 0.55, -2.75), Vector3(1.02, 2.3, -1.75), white)
	k.box(Vector3(-0.92, 1.4, -2.78), Vector3(0.92, 2.15, -2.74), glass)
	for sx: float in [-1.03, 1.03]:
		k.box(Vector3(sx - 0.01, 1.35, -2.6), Vector3(sx + 0.01, 2.1, -1.9), glass)
		k.box(Vector3(sx * 1.12 - 0.04, 1.6, -2.75), Vector3(sx * 1.12 + 0.04, 1.95, -2.6), Color(0.15, 0.15, 0.16))
	# Kofferaufbau
	k.box(Vector3(-1.12, 0.6, -1.75), Vector3(1.12, 2.9, 3.35), white)
	k.box(Vector3(-1.13, 2.9, -1.75), Vector3(1.13, 2.95, 3.36), Color(0.85, 0.85, 0.83))
	# rote Bauchbinde und gelbe Leuchtstreifen rundum
	for sx: float in [-1.13, 1.13]:
		k.box(Vector3(sx - 0.005, 1.15, -1.75), Vector3(sx + 0.005, 1.45, 3.35), red)
		k.box(Vector3(sx - 0.005, 0.95, -1.75), Vector3(sx + 0.005, 1.15, 3.35), yellow)
		k.box(Vector3(sx - 0.005, 1.15, -2.75), Vector3(sx + 0.005, 1.45, -1.75), red)
		# Fenster im Aufbau
		k.box(Vector3(sx - 0.006, 1.75, 0.6), Vector3(sx + 0.006, 2.4, 1.6), glass)
	# Heck: Warnmarkierung (rot-gelb), Türen
	for i in range(6):
		var x := -1.05 + float(i) * 0.35
		k.box(Vector3(x, 0.65, 3.35), Vector3(x + 0.35, 1.3, 3.37), red if i % 2 == 0 else yellow)
	k.box(Vector3(-0.02, 1.3, 3.35), Vector3(0.02, 2.85, 3.38), Color(0.6, 0.6, 0.6))
	k.box(Vector3(-0.9, 1.9, 3.35), Vector3(-0.15, 2.5, 3.37), glass)
	k.box(Vector3(0.15, 1.9, 3.35), Vector3(0.9, 2.5, 3.37), glass)
	PixelFont.draw(k, "RETTUNGSDIENST", Vector3(-1.14, 2.15, 0.7), Vector3(0, 0, -1), Vector3.UP, Vector3(-1, 0, 0), 0.045, red)
	PixelFont.draw(k, "RETTUNGSDIENST", Vector3(1.14, 2.15, 0.7), Vector3(0, 0, 1), Vector3.UP, Vector3(1, 0, 0), 0.045, red)
	PixelFont.draw(k, "112", Vector3(0, 2.62, 3.38), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.06, red)
	# Blaulichtbalken (Gehäuse; Lichter als eigene Knoten)
	k.box(Vector3(-0.8, 2.3, -2.45), Vector3(0.8, 2.36, -2.05), Color(0.2, 0.2, 0.22))
	return k.commit()


## Rettungswagen-Knoten mit Karosserie ("Body") und vier Blaulichtern "Blau0".."Blau3" (blinken im Einsatz).
static func rtw_node() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = rtw_mesh()
	n.add_child(mi)
	var spots := [Vector3(-0.55, 2.42, -2.25), Vector3(0.55, 2.42, -2.25), Vector3(-1.0, 2.98, 3.25), Vector3(1.0, 2.98, 3.25)]
	for i in range(spots.size()):
		var lk := Kit.new()
		lk.box(Vector3(-0.16, -0.06, -0.12), Vector3(0.16, 0.06, 0.12), Color(0.2, 0.45, 1.0, 0.3))
		var l := lk.instance("Blau%d" % i)
		l.position = spots[i]
		l.visible = false
		mi.add_child(l)
	return n


static func fire_truck_mesh() -> ArrayMesh:
	if _truck != null:
		return _truck
	var k := Kit.new()
	var red := Color(0.84, 0.13, 0.1)
	var silver := Color(0.74, 0.75, 0.77)
	k.box(Vector3(-1.15, 0.72, -5.2), Vector3(1.15, 1.08, 5.3), Color(0.15, 0.15, 0.16))
	for z: float in [-3.5, 1.6, 3.65]:
		for sx: float in [-1.0, 1.0]:
			k.cyl(Vector3(sx * 0.95, 0.68, z), Vector3(sx * 1.47, 0.68, z), 0.68, 0.68, Models.TYRE, 16, true, Models.TYRE)
			k.cyl(Vector3(sx * 1.46, 0.68, z), Vector3(sx * 1.49, 0.68, z), 0.38, 0.38, silver, 14)
			k.cyl(Vector3(sx * 1.48, 0.68, z), Vector3(sx * 1.54, 0.68, z), 0.13, 0.1, Models.DARK_METAL, 8)
			k.box(Vector3(sx * 1.0, 1.42, z - 0.85), Vector3(sx * 1.5, 1.5, z + 0.85), DARK)
	# Kabine
	# Kabine nach dem Vorbild der großen Flugfeldlöschfahrzeuge: weit nach vorn geneigte Panoramascheibe
	var cst := [
		[-5.64, 1.12, 1.9, 2.25, 1.18, 1.08, 4.0, 5.0],
		[-5.52, 1.0, 1.9, 2.5, 1.4, 1.3, 5.0, 6.0],
		[-5.05, 1.0, 1.9, 3.12, 1.45, 1.36, 6.0, 7.0],
		[-4.55, 1.0, 1.9, 3.25, 1.45, 1.38, 7.0, 7.0],
		[-2.98, 1.0, 1.9, 3.25, 1.45, 1.38, 7.0, 7.0],
		[-2.9, 1.05, 1.9, 3.18, 1.4, 1.32, 7.0, 7.0],
	]
	var cab_col := func(m: Vector3, _p: Array) -> Color:
		var ax := absf(m.x)
		if m.z < -4.55 and m.y > 2.0 and m.y < 3.18:
			return DARK if absf(m.x) < 0.035 else Models.GLASS
		if m.z > -4.5 and m.z < -3.35 and m.y > 2.05 and m.y < 3.05 and ax > 1.2:
			return Models.GLASS
		if absf(m.z + 3.3) < 0.025 and ax > 1.2 and m.y > 1.1:
			return red.darkened(0.35)
		if m.y < 1.2:
			return DARK
		return red
	Models._shell(k, cst, cab_col, 36, 0.2, [-4.55, -4.5, -3.35, -3.325, -3.275])
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(minf(sx * 1.45, sx * 1.47), 1.9, -3.25), Vector3(maxf(sx * 1.45, sx * 1.47), 1.95, -3.0), STEEL)
		PixelFont.draw(k, "FEUERWEHR", Vector3(sx * 1.462, 1.8, -4.25), Vector3(0, 0, -sx), Vector3.UP, Vector3(sx, 0, 0), 0.04, WHITE)
		# Spiegel
		k.box(Vector3(sx * 1.45, 2.6, -5.3), Vector3(sx * 1.75, 2.64, -5.25), DARK)
		k.box(Vector3(sx * 1.7, 2.2, -5.32), Vector3(sx * 1.8, 2.75, -5.2), DARK)
		# Tritte
		k.box(Vector3(sx * 1.35, 0.95, -4.6), Vector3(sx * 1.55, 1.0, -3.6), STEEL)
		k.box(Vector3(sx * 1.35, 1.45, -4.6), Vector3(sx * 1.55, 1.5, -3.6), STEEL)
	# Front: Stoßfänger, Scheinwerfer, Blitzer, Frontwerfer
	k.box(Vector3(-1.48, 0.8, -5.66), Vector3(1.48, 1.18, -5.42), DARK)
	k.box(Vector3(-0.7, 1.3, -5.53), Vector3(0.7, 1.85, -5.5), Color(0.2, 0.2, 0.21))
	for i in range(5):
		k.box(Vector3(-0.66, 1.36 + float(i) * 0.1, -5.56), Vector3(0.66, 1.39 + float(i) * 0.1, -5.52), STEEL)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.9, 1.3, -5.56), Vector3(sx * 1.32, 1.5, -5.5), LAMP)
		k.box(Vector3(sx * 0.75, 1.6, -5.56), Vector3(sx * 0.9, 1.75, -5.5), BLUE_LAMP)
	k.box(Vector3(-0.15, 1.1, -5.7), Vector3(0.15, 1.3, -5.55), STEEL)
	k.cyl(Vector3(0, 1.22, -5.7), Vector3(0, 1.28, -6.15), 0.07, 0.05, silver, 8)
	# Dach der Kabine: Blaulichtbalken und Dachwerfer
	k.box(Vector3(-1.15, 3.25, -4.45), Vector3(1.15, 3.36, -4.05), DARK)
	k.box(Vector3(-1.12, 3.27, -4.48), Vector3(-0.55, 3.45, -4.02), BLUE_LAMP)
	k.box(Vector3(0.55, 3.27, -4.48), Vector3(1.12, 3.45, -4.02), BLUE_LAMP)
	k.box(Vector3(-0.3, 3.3, -4.48), Vector3(0.3, 3.4, -4.35), LAMP)
	k.cyl(Vector3(0, 3.25, -3.9), Vector3(0, 3.5, -3.9), 0.32, 0.28, silver, 12)
	k.cyl(Vector3(0, 3.62, -3.9), Vector3(0, 3.78, -5.6), 0.13, 0.08, silver, 10)
	k.sphere(Vector3(0, 3.6, -3.9), 0.17, silver, 8, 4)
	# Aufbau mit Rollläden
	var bst := [
		[-2.86, 1.06, 2.2, 3.38, 1.38, 1.3, 7.0, 8.0],
		[-2.78, 1.0, 2.2, 3.45, 1.45, 1.38, 8.0, 8.0],
		[5.42, 1.0, 2.2, 3.45, 1.45, 1.38, 8.0, 8.0],
		[5.5, 1.06, 2.2, 3.38, 1.38, 1.3, 7.0, 8.0],
	]
	var body_col := func(m: Vector3, _p: Array) -> Color:
		if m.y < 1.12:
			return DARK
		return red
	Models._shell(k, bst, body_col, 36, 0.4)
	for sx: float in [-1.0, 1.0]:
		for cz: Vector2 in [Vector2(-2.6, -0.35), Vector2(-0.15, 2.4), Vector2(2.6, 5.25)]:
			var cz0 := cz.x
			var cz1 := cz.y
			var c := Vector3(sx * 1.452, 2.4, (cz0 + cz1) * 0.5)
			k.panel(c, Vector3(0, 0, (cz1 - cz0) * 0.5), Vector3(0, 0.82, 0), silver, Vector3(sx, 0, 0))
			var gy := 1.62
			while gy < 3.2:
				k.panel(Vector3(sx * 1.455, gy, (cz0 + cz1) * 0.5), Vector3(0, 0, (cz1 - cz0) * 0.5), Vector3(0, 0.012, 0), Color(0.58, 0.6, 0.62), Vector3(sx, 0, 0))
				gy += 0.14
			k.panel(Vector3(sx * 1.456, 1.62, (cz0 + cz1) * 0.5), Vector3(0, 0, 0.3), Vector3(0, 0.04, 0), DARK, Vector3(sx, 0, 0))
		k.panel(Vector3(sx * 1.453, 1.3, 1.3), Vector3(0, 0, 4.1), Vector3(0, 0.07, 0), WHITE, Vector3(sx, 0, 0))
		# Geländer auf dem Laufsteg
		k.cyl(Vector3(sx * 1.28, 3.9, -2.5), Vector3(sx * 1.28, 3.9, 5.1), 0.03, 0.03, silver, 6)
		var pz := -2.5
		while pz < 5.2:
			k.cyl(Vector3(sx * 1.28, 3.45, pz), Vector3(sx * 1.28, 3.9, pz), 0.025, 0.025, silver, 5, false)
			pz += 1.27
	k.box(Vector3(-1.2, 3.45, -2.6), Vector3(1.2, 3.5, 5.25), Color(0.5, 0.52, 0.54))
	k.cyl(Vector3(-0.6, 3.75, 2.0), Vector3(0.6, 3.75, 2.0), 0.28, 0.28, Color(0.86, 0.84, 0.78), 12, true, Color(0.8, 0.15, 0.1))
	k.cyl(Vector3(-0.25, 3.5, 4.4), Vector3(-0.25, 3.62, 4.4), 0.4, 0.4, DARK, 10)
	# Heck: Warnmarkierung, Leuchten
	for i in range(8):
		var x0 := -1.4 + float(i) * 0.35
		k.panel(Vector3(x0 + 0.175, 2.0, 5.51), Vector3(0.175, 0, 0), Vector3(0, 0.75, 0), YELLOW if i % 2 == 0 else red, Vector3(0, 0, 1))
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 1.05, 1.15, 5.5), Vector3(sx * 1.38, 1.45, 5.56), Color(0.85, 0.1, 0.08))
		k.box(Vector3(sx * 1.0, 3.3, 5.35), Vector3(sx * 1.35, 3.55, 5.6), BLUE_LAMP)
	_truck = k.commit()
	return _truck


# ================================================================== Parkhaus

## Parkhaus: Decks mit Rampen, Stützenraster, Brüstungen in der Fassadenfarbe mit
## Lamellen und bepflanzten Trögen, geparkte Autos auf allen Ebenen, Deckenleuchten,
## Treppenhaus aus Glas mit Treppenläufen und Aufzug, Solardach auf dem Oberdeck, Zufahrt
## mit Kassenhäuschen, Ticketsäulen, Schranken (Knoten SchrankeEin/SchrankeAus) und
## Höhenbegrenzung, Anzeige freier Plätze.
static func _car_park(n: Node3D, k: Kit, opts: Dictionary) -> void:
	var levels := int(opts.get("etagen", 4))
	var tint: Color = {"grau": Color(0.72, 0.71, 0.67), "rot": Color(0.62, 0.3, 0.24), "blau": Color(0.36, 0.48, 0.62), "holz": Color(0.6, 0.44, 0.28)}.get(String(opts.get("farbe", "grau")), Color(0.72, 0.71, 0.67))
	var top := float(levels) * 3.0
	var asphalt := Color(0.36, 0.36, 0.35)
	var paint := Color(0.88, 0.87, 0.82)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + levels * 13
	k.box(Vector3(-16.0, 0, -22.0), Vector3(16.0, 0.08, 22.0), asphalt)
	var holes := [[-16.0, -22.0, -5.0, 22.0], [0.0, -22.0, 16.0, 22.0], [-5.0, -22.0, 0.0, -7.0], [-5.0, 7.0, 0.0, 22.0]]
	var rows := [[13.2, 10.8, 15.6, -PI * 0.5], [2.6, 0.2, 5.0, PI * 0.5], [-13.2, -15.6, -10.8, PI * 0.5]]
	var kinds := ["kompakt", "limousine", "kombi", "suv", "kompakt", "limousine", "kombi", "transporter"]
	var Factory = load("res://scripts/factory.gd")
	var car_cols: Array = Factory.CAR_COLORS
	for l in range(levels + 1):
		var y := float(l) * 3.0
		var fy := y + (0.08 if l == 0 else 0.03)
		if l > 0:
			for r: Array in holes:
				k.box(Vector3(float(r[0]), y - 0.35, float(r[1])), Vector3(float(r[2]), y, float(r[3])), CONCRETE)
				k.box(Vector3(float(r[0]) + 0.02, y, float(r[1]) + 0.02), Vector3(float(r[2]) - 0.02, fy, float(r[3]) - 0.02), asphalt)
			# Geländer an der Rampenöffnung
			for hx: float in [-5.0, 0.0]:
				k.box(Vector3(hx - 0.1, y, -7.0), Vector3(hx + 0.1, y + 0.9, 7.0), CONCRETE.lightened(0.05))
				k.box(Vector3(hx - 0.12, y + 0.85, -7.0), Vector3(hx + 0.12, y + 0.95, 7.0), YELLOW)
			# Rampe von der Ebene darunter
			var ang := atan(3.0 / 14.0)
			var xf := Transform3D(Basis(Vector3.RIGHT, -ang), Vector3(-2.5, y - 1.5, 0))
			var half := sqrt(49.0 + 2.25)
			k.box(Vector3(-2.5, -0.32, -half), Vector3(2.5, 0.0, half), CONCRETE, xf)
			k.box(Vector3(-2.3, 0.0, -half), Vector3(2.3, 0.02, half), asphalt, xf)
			for sx: float in [-1.0, 1.0]:
				k.box(Vector3(sx * 2.5 - 0.2, 0.0, -half), Vector3(sx * 2.5, 0.3, half), CONCRETE.lightened(0.05), xf)
			for az: float in [-3.5, 2.5]:
				k.box(Vector3(-0.08, 0.02, az), Vector3(0.08, 0.03, az + 1.6), paint, xf)
				k.box(Vector3(-0.45, 0.02, az + 1.6), Vector3(0.45, 0.03, az + 1.8), paint, xf)
			# Deckenleuchten unter dieser Platte
			for lx: float in [-7.9, 7.9]:
				var lz := -18.0
				while lz <= 18.1:
					k.box(Vector3(lx - 0.1, y - 0.44, lz - 0.6), Vector3(lx + 0.1, y - 0.35, lz + 0.6), LAMP)
					lz += 6.0
		# Stellplätze, Fahrgassen, geparkte Autos
		for row: Array in rows:
			var rx0: float = row[1]
			var rx1: float = row[2]
			var j := 0
			while j <= 16:
				var lz := -20.8 + float(j) * 2.6
				if not (rx0 > 10.0 and lz < -16.0):
					k.box(Vector3(rx0, fy, lz - 0.05), Vector3(rx1, fy + 0.012, lz + 0.05), paint)
				j += 1
		for ax: float in [-7.9, 7.9]:
			var dz := -19.0
			while dz < 19.0:
				k.box(Vector3(ax - 0.06, fy, dz), Vector3(ax + 0.06, fy + 0.012, dz + 1.5), paint)
				dz += 3.0
		PixelFont.draw_ground(k, ("%d" % l) if l > 0 else "E", Vector3(-7.9, fy + 0.015, -14.0), Vector3(0, 0, 1), 0.28, Color(0.95, 0.8, 0.25))
		var fill := 0.55 if l == levels else 0.72
		for row: Array in rows:
			var cx: float = row[0]
			var rot: float = row[3]
			for j in range(16):
				var cz := -19.5 + float(j) * 2.6
				if cx > 10.0 and cz < -15.5:
					continue
				if rng.randf() > fill:
					continue
				var kind: String = kinds[rng.randi() % kinds.size()]
				var col: Color = car_cols[rng.randi() % car_cols.size()]
				var r2 := rot + (PI if rng.randf() < 0.3 else 0.0) + rng.randf_range(-0.04, 0.04)
				var off := Vector3(-sin(rot) * 0.1 + rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.1, 0.1))
				k.add_mesh(Models.car_mesh(kind, col, true), Transform3D(Basis(Vector3.UP, r2), Vector3(cx, fy, cz) + off), true)
	# Stützen
	var col_x := [-15.75, -10.6, 5.1, 10.6, 15.75]
	for cx: float in col_x:
		for cz: float in [-20.8, -13.0, -5.2, 5.2, 13.0, 20.8]:
			k.rounded_box(Vector3(cx - 0.25, 0, cz - 0.25), Vector3(cx + 0.25, top, cz + 0.25), 0.06, CONCRETE.lightened(0.04), 2)
			k.box(Vector3(cx - 0.27, 0.0, cz - 0.27), Vector3(cx + 0.27, 0.9, cz + 0.27), YELLOW)
			k.box(Vector3(cx - 0.275, 0.3, cz - 0.275), Vector3(cx + 0.275, 0.6, cz + 0.275), DARK)
	for cx: float in [-10.6, -5.0, 0.0, 5.1, 10.6]:
		for cz: float in [-21.75, 21.75]:
			k.rounded_box(Vector3(cx - 0.25, 0, cz - 0.25), Vector3(cx + 0.25, top, cz + 0.25), 0.06, CONCRETE.lightened(0.04), 2)
	# Fassade: Brüstungen, Lamellen, Pflanztröge
	var perim := [[Vector3(-16, 0, -22), Vector3(16, 0, -22), Vector3(0, 0, -1)], [Vector3(16, 0, -22), Vector3(16, 0, 22), Vector3(1, 0, 0)],
		[Vector3(16, 0, 22), Vector3(-16, 0, 22), Vector3(0, 0, 1)], [Vector3(-16, 0, 22), Vector3(-16, 0, -22), Vector3(-1, 0, 0)]]
	for l in range(levels + 1):
		var y := float(l) * 3.0
		for e: Array in perim:
			var a: Vector3 = e[0]
			var b: Vector3 = e[1]
			var out: Vector3 = e[2]
			var dir := (b - a).normalized()
			var length := a.distance_to(b)
			var segs: Array = [[0.0, length]]
			if out.z < -0.5:
				segs = [[0.0, 6.5], [25.5, 26.6]] if l == 0 else [[0.0, 26.6]]
			if out.x > 0.5:
				segs = [[5.6, length]]
			for sg: Array in segs:
				var s0: float = sg[0]
				var s1: float = sg[1]
				if s1 - s0 < 0.2:
					continue
				var p0 := a + dir * s0
				var p1 := a + dir * s1
				k.box(p0 + Vector3(0, y, 0) - out * 0.02, p1 + Vector3(0, y + 1.05, 0) + out * 0.2, tint)
				k.box(p0 + Vector3(0, y + 1.05, 0) - out * 0.05, p1 + Vector3(0, y + 1.13, 0) + out * 0.25, CONCRETE.lightened(0.15))
				k.box(p0 + Vector3(0, y + 0.5, 0) + out * 0.2, p1 + Vector3(0, y + 0.55, 0) + out * 0.22, tint.darkened(0.15))
				if l > 0:
					_planter(k, p0 + Vector3(0, y + 1.13, 0) + out * 0.05 + dir * 0.3, p1 + Vector3(0, y + 1.13, 0) + out * 0.05 - dir * 0.3, out, rng)
			if l < levels:
				var s := 1.2
				while s < length - 0.6:
					var p := a + dir * s
					var skip := (l == 0 and out.z < -0.5 and s > 6.4 and s < 25.6) or (out.z < -0.5 and s > 26.5) or (out.x > 0.5 and s < 5.7)
					if not skip:
						k.box(p - dir * 0.06 + Vector3(0, y + 1.13, 0) + out * 0.05, p + dir * 0.06 + Vector3(0, y + 2.65, 0) + out * 0.4, tint.darkened(0.12))
					s += 2.4
		if l > 0:
			for e: Array in perim:
				var a: Vector3 = e[0]
				var b: Vector3 = e[1]
				var out: Vector3 = e[2]
				k.box(a + Vector3(0, y - 0.35, 0) - out * 0.0, b + Vector3(0, y, 0) + out * 0.12, CONCRETE.lightened(0.08))
	# Oberdeck: Lichtmasten und Solardach über der rechten Reihe
	for lp: Vector3 in [Vector3(-15.2, 0, -15.0), Vector3(-15.2, 0, 0.0), Vector3(-15.2, 0, 15.0), Vector3(15.2, 0, -12.0), Vector3(15.2, 0, 2.0),
			Vector3(15.2, 0, 16.0), Vector3(-8.0, 0, 21.2), Vector3(8.0, 0, 21.2), Vector3(-8.0, 0, -21.2)]:
		var b := lp + Vector3(0, top, 0)
		k.cyl(b, b + Vector3(0, 0.3, 0), 0.18, 0.18, CONCRETE, 8)
		k.cyl(b, b + Vector3(0, 5.0, 0), 0.07, 0.05, STEEL, 8)
		var inward := Vector3(-signf(lp.x), 0, 0) if absf(lp.x) > 14.0 else Vector3(0, 0, -signf(lp.z))
		k.cyl(b + Vector3(0, 5.0, 0), b + Vector3(0, 5.0, 0) + inward * 0.8, 0.04, 0.04, STEEL, 6)
		k.box(b + Vector3(0, 4.88, 0) + inward * 0.6 - Vector3(0.25, 0, 0.25), b + Vector3(0, 5.02, 0) + inward * 1.1 + Vector3(0.25, 0, 0.25), FRAME)
		k.box(b + Vector3(0, 4.85, 0) + inward * 0.65 - Vector3(0.2, 0, 0.2), b + Vector3(0, 4.88, 0) + inward * 1.05 + Vector3(0.2, 0, 0.2), LAMP)
	var pv_lo := top + 2.5
	var pv_hi := top + 3.1
	for pz: float in [-13.0, -5.2, 5.2, 13.0]:
		k.cyl(Vector3(10.9, top, pz), Vector3(10.9, pv_hi, pz), 0.1, 0.1, STEEL, 8)
		k.cyl(Vector3(15.3, top, pz), Vector3(15.3, pv_lo, pz), 0.1, 0.1, STEEL, 8)
		k.box(Vector3(10.7, pv_lo - 0.1, pz - 0.06), Vector3(15.5, pv_hi - 0.05, pz + 0.06), STEEL)
	k.quad(Vector3(10.6, pv_hi, -14.2), Vector3(15.6, pv_lo, -14.2), Vector3(15.6, pv_lo, 19.4), Vector3(10.6, pv_hi, 19.4), Color(0.12, 0.17, 0.32), Vector3(13.0, top, 2.0))
	var pnorm := Vector3(0.6, 5.0, 0).normalized()
	var gz := -14.2
	while gz <= 19.45:
		k.quad(Vector3(10.6, pv_hi, gz - 0.03) + pnorm * 0.01, Vector3(15.6, pv_lo, gz - 0.03) + pnorm * 0.01, Vector3(15.6, pv_lo, gz + 0.03) + pnorm * 0.01,
			Vector3(10.6, pv_hi, gz + 0.03) + pnorm * 0.01, Color(0.7, 0.72, 0.75), Vector3(13.0, top, gz))
		gz += 1.05
	for f: float in [0.33, 0.66]:
		var py := lerpf(pv_hi, pv_lo, f)
		var px := lerpf(10.6, 15.6, f)
		k.quad(Vector3(px - 0.03, py, -14.2) + pnorm * 0.01, Vector3(px + 0.03, py, -14.2) + pnorm * 0.01, Vector3(px + 0.03, py, 19.4) + pnorm * 0.01,
			Vector3(px - 0.03, py, 19.4) + pnorm * 0.01, Color(0.7, 0.72, 0.75), Vector3(13.0, top, 2.0))
	# Ladesäulen im Erdgeschoss
	for cz: float in [6.5, 9.1, 11.7]:
		k.rounded_box(Vector3(-15.85, 0.08, cz - 0.2), Vector3(-15.45, 1.5, cz + 0.2), 0.05, Color(0.85, 0.87, 0.86), 2)
		k.box(Vector3(-15.46, 1.0, cz - 0.12), Vector3(-15.43, 1.35, cz + 0.12), GREEN_LAMP)
		k.box(Vector3(-15.6, 0.081, cz - 1.25), Vector3(-10.8, 0.095, cz + 1.25), Color(0.2, 0.5, 0.3))
	_car_park_stairs(n, k, top, levels)
	_car_park_entry(n, k, top)


static func _car_park_stairs(n: Node3D, k: Kit, top: float, levels: int) -> void:
	var x0 := 10.6
	var x1 := 16.0
	var z0 := -22.0
	var z1 := -16.4
	var h := top + 2.8
	var gk := Kit.new()
	gk.quad(Vector3(x0 + 0.3, 0.3, z0), Vector3(x1 - 0.3, 0.3, z0), Vector3(x1 - 0.3, h - 0.1, z0), Vector3(x0 + 0.3, h - 0.1, z0), WHITE, Vector3(13.0, h * 0.5, -19.0))
	gk.quad(Vector3(x1, 0.3, z0 + 0.3), Vector3(x1, 0.3, z1 - 0.3), Vector3(x1, h - 0.1, z1 - 0.3), Vector3(x1, h - 0.1, z0 + 0.3), WHITE, Vector3(13.0, h * 0.5, -19.0))
	_glass_part(n, gk)
	for c: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)]:
		k.rounded_box(Vector3(c.x - 0.25, 0, c.y - 0.25), Vector3(c.x + 0.25, h, c.y + 0.25), 0.08, CONCRETE.lightened(0.06), 2)
	k.box(Vector3(x0 - 0.3, h, z0 - 0.3), Vector3(x1 + 0.3, h + 0.35, z1 + 0.3), CONCRETE.lightened(0.1))
	k.box(Vector3(x0, 0, z1 - 0.2), Vector3(x1, h, z1), CONCRETE)
	k.box(Vector3(x0, 0, z0), Vector3(x0 + 0.2, h, z1), CONCRETE)
	var gx := x0 + 1.4
	while gx < x1 - 0.3:
		k.box(Vector3(gx - 0.04, 0.3, z0 - 0.05), Vector3(gx + 0.04, h - 0.1, z0 + 0.02), FRAME)
		gx += 1.35
	var gzz := z0 + 1.4
	while gzz < z1 - 0.3:
		k.box(Vector3(x1 - 0.02, 0.3, gzz - 0.04), Vector3(x1 + 0.05, h - 0.1, gzz + 0.04), FRAME)
		gzz += 1.4
	# Aufzug
	k.box(Vector3(14.1, 0, -21.7), Vector3(15.7, h, -19.3), CONCRETE.darkened(0.05))
	for l in range(levels + 1):
		var y := float(l) * 3.0
		if l == 0:
			k.box(Vector3(x0, 0.0, z0), Vector3(x1, 0.1, z1), CONCRETE)
		else:
			k.box(Vector3(x0, y - 0.25, z0), Vector3(x1, y, -21.0), CONCRETE)
			k.box(Vector3(x0, y - 0.25, -16.6), Vector3(x1, y, z1), CONCRETE)
			k.box(Vector3(14.0, y - 0.25, -21.0), Vector3(x1, y, -16.6), CONCRETE)
		k.box(Vector3(x0 - 0.02, y + 0.15, z1 - 0.3), Vector3(x0 + 0.04, y + 0.2, z1 + 0.02), FRAME)
		k.box(Vector3(x0 + 1.0, y + 0.02, z1 + 0.0), Vector3(x0 + 2.1, y + 2.1, z1 + 0.06), Color(0.45, 0.5, 0.55))
		k.box(Vector3(x0 + 1.2, y + 2.25, z1), Vector3(x0 + 1.9, y + 2.45, z1 + 0.08), GREEN_LAMP)
		k.box(Vector3(14.4, y + 0.02, -19.3), Vector3(15.4, y + 2.1, -19.26), Color(0.7, 0.72, 0.74))
		k.box(Vector3(14.88, y + 0.02, -19.28), Vector3(14.92, y + 2.1, -19.24), DARK)
		if l < levels:
			var t := 3.0 / 9.0
			for s in range(9):
				var sy := y + 1.5 * float(s + 1) / 9.0
				k.box(Vector3(10.9, sy - 0.17, -21.0 + float(s) * t), Vector3(12.3, sy, -21.0 + float(s + 1) * t), Color(0.6, 0.6, 0.58))
				k.box(Vector3(12.45, sy + 1.5 - 0.17, -18.0 - float(s + 1) * t), Vector3(13.85, sy + 1.5, -18.0 - float(s) * t), Color(0.6, 0.6, 0.58))
			k.box(Vector3(10.9, y + 1.35, -18.0), Vector3(13.85, y + 1.5, -16.6), CONCRETE)
			k.cyl(Vector3(12.38, y + 0.9, -21.0), Vector3(12.38, y + 2.4, -18.0), 0.03, 0.03, YELLOW, 5)
	# Blaues P-Schild (nachts beleuchtet)
	var sb := Color(0.12, 0.32, 0.72, 0.3)
	k.box(Vector3(x1 + 0.02, h - 2.3, -21.4), Vector3(x1 + 0.2, h - 0.3, -19.6), sb)
	PixelFont.draw(k, "P", Vector3(x1 + 0.21, h - 1.3, -20.5), Vector3(0, 0, -1), Vector3.UP, Vector3(1, 0, 0), 0.22, Color(0.98, 0.98, 0.98, 0.3))
	k.box(Vector3(11.4, h - 2.3, z0 - 0.2), Vector3(13.2, h - 0.3, z0 - 0.02), sb)
	PixelFont.draw(k, "P", Vector3(12.3, h - 1.3, z0 - 0.21), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.22, Color(0.98, 0.98, 0.98, 0.3))


static func _car_park_entry(n: Node3D, k: Kit, top: float) -> void:
	var asphalt := Color(0.27, 0.27, 0.26)
	var paint := Color(0.88, 0.87, 0.82)
	k.box(Vector3(-11.0, 0.0, -31.0), Vector3(11.0, 0.05, -22.0), asphalt)
	k.box(Vector3(-0.12, 0.05, -30.5), Vector3(0.12, 0.06, -25.4), paint)
	for arrow: Array in [[-6.0, 1.0, "EIN"], [6.0, -1.0, "AUS"]]:
		var ax: float = arrow[0]
		var dirz: float = arrow[1]
		k.box(Vector3(ax - 0.15, 0.05, -28.6), Vector3(ax + 0.15, 0.06, -25.4), paint)
		var tip := -27.0 + dirz * 1.9
		k.quad(Vector3(ax - 0.7, 0.061, tip - dirz * 0.8), Vector3(ax + 0.7, 0.061, tip - dirz * 0.8), Vector3(ax, 0.061, tip + dirz * 0.2), Vector3(ax, 0.061, tip + dirz * 0.2), paint, Vector3(ax, -1.0, tip))
		PixelFont.draw_ground(k, String(arrow[2]), Vector3(ax, 0.062, -30.0), Vector3(0, 0, dirz), 0.16, paint)
	# Insel mit Kassenhäuschen
	k.box(Vector3(-1.5, 0, -25.4), Vector3(1.5, 0.22, -22.0), CONCRETE)
	for i in range(5):
		k.box(Vector3(-1.5 + float(i) * 0.6, 0.0, -25.45), Vector3(-1.2 + float(i) * 0.6, 0.23, -25.38), YELLOW)
	k.rounded_box(Vector3(-1.0, 0.22, -24.6), Vector3(1.0, 2.55, -22.4), 0.3, RENDER, 3)
	k.box(Vector3(-1.02, 1.15, -24.62), Vector3(1.02, 2.1, -22.38), WIN)
	for wx: float in [-0.35, 0.35]:
		k.box(Vector3(wx - 0.03, 1.15, -24.65), Vector3(wx + 0.03, 2.1, -24.6), FRAME)
	k.box(Vector3(-1.3, 2.55, -24.9), Vector3(1.3, 2.75, -22.1), ROOF)
	k.box(Vector3(-0.3, 2.5, -24.75), Vector3(0.3, 2.55, -24.6), LAMP)
	# Schranken mit Pfosten und Ticketsäulen
	for gate: Array in [["SchrankeEin", -9.2], ["SchrankeAus", 2.8]]:
		var x0: float = gate[1]
		k.rounded_box(Vector3(x0 - 0.28, 0, -22.95), Vector3(x0 + 0.28, 1.15, -22.35), 0.06, Color(0.92, 0.75, 0.15), 2)
		k.box(Vector3(x0 - 0.3, 1.15, -22.97), Vector3(x0 + 0.3, 1.22, -22.33), DARK)
		k.box(Vector3(x0 + 0.29, 0.7, -22.75), Vector3(x0 + 0.31, 0.9, -22.55), RED_LAMP)
		var pivot := Node3D.new()
		pivot.name = gate[0]
		pivot.position = Vector3(x0, 1.0, -22.65)
		n.add_child(pivot)
		var ak := Kit.new()
		for s in range(6):
			ak.box(Vector3(0.2 + float(s) * 0.95, -0.06, -0.05), Vector3(0.2 + float(s + 1) * 0.95, 0.06, 0.05), Color(0.9, 0.15, 0.12) if s % 2 == 0 else WHITE)
		ak.cyl(Vector3(0, 0, -0.1), Vector3(0, 0, 0.1), 0.12, 0.12, DARK, 10)
		ak.box(Vector3(-0.5, -0.12, -0.07), Vector3(-0.05, 0.08, 0.07), DARK)
		ak.box(Vector3(5.85, -0.3, -0.03), Vector3(5.9, 0.0, 0.03), DARK)
		var arm := ak.instance("Arm")
		arm.set_meta("no_bake", true)
		pivot.add_child(arm)
	for m: Vector3 in [Vector3(-2.55, 0, -23.4), Vector3(2.15, 0, -23.4)]:
		k.rounded_box(m + Vector3(-0.3, 0, -0.25), m + Vector3(0.3, 1.45, 0.25), 0.06, Color(0.3, 0.33, 0.36), 2)
		k.box(m + Vector3(-0.31, 0.95, -0.2), m + Vector3(0.31, 1.3, 0.2), Color(0.35, 0.65, 0.9, 0.3))
		k.box(m + Vector3(-0.32, 0.7, -0.08), m + Vector3(0.32, 0.75, 0.08), DARK)
		k.box(m + Vector3(-0.32, 0.5, -0.06), m + Vector3(0.32, 0.6, 0.06), YELLOW)
	# Höhenbegrenzung
	for sx: float in [-1.0, 1.0]:
		k.cyl(Vector3(sx * 10.4, 0, -24.0), Vector3(sx * 10.4, 2.6, -24.0), 0.12, 0.12, STEEL, 8)
	for s in range(14):
		var xa := -10.4 + float(s) * (20.8 / 14.0)
		k.box(Vector3(xa, 2.2, -24.08), Vector3(xa + 20.8 / 14.0, 2.42, -23.92), YELLOW if s % 2 == 0 else DARK)
	PixelFont.draw(k, "2.1 M", Vector3(-6.0, 2.31, -24.1), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.025, WHITE)
	# Anzeige freier Plätze und P-Schild
	var sp := Vector3(-12.2, 0, -24.4)
	k.cyl(sp, sp + Vector3(0, 4.6, 0), 0.08, 0.08, STEEL, 8)
	k.box(sp + Vector3(-0.85, 3.4, -0.12), sp + Vector3(0.85, 4.6, -0.04), Color(0.12, 0.32, 0.72, 0.3))
	PixelFont.draw(k, "P", sp + Vector3(0, 4.0, -0.13), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.13, Color(0.98, 0.98, 0.98, 0.3))
	k.box(sp + Vector3(-0.85, 2.5, -0.12), sp + Vector3(0.85, 3.3, -0.04), DARK)
	PixelFont.draw(k, "FREI", sp + Vector3(0, 2.9, -0.13), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.065, GREEN_LAMP)


# ================================================================== Hallen mit wählbarer Torzahl

## Busgarage, Feuerwache und Gepäckumschlag in frei wählbarer Größe (Catalog.SIZED, Bauform "tore"):
## Fahrzeughalle mit Rolltoren vorn (+Z), Seitenteil links (Büro, Waschhalle, Leitstand), Dach als eigener
## Knoten "Dach" (in der Innenansicht ausgeblendet, damit man hineinsieht). Drinnen je Tor ein Stellplatz:
## Feuerwehr mit Löschfahrzeug (LF0, LF1 …) und Spinden, Busse mit Arbeitsgrube und Werkbank,
## Gepäckumschlag mit Entladeband je Spur, Sammelband zum Förderbandtunnel an der Rückwand.
static func sized_hall(n: Node3D, id: String, opts: Dictionary) -> void:
	var sz: Dictionary = Catalog.SIZED[id]
	var s := Catalog.size_of(id, opts)
	var doors := Catalog.doors_of(id, opts)
	var w := s.x
	var d := s.y
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var z0 := -d * 0.5
	var z1 := d * 0.5
	var xs := x0 + float(sz["side"])    # Beginn der Fahrzeughalle
	var hh := 8.0 if id == "gepaeckumschlag" else 7.5
	var k := Kit.new()
	var rk := Kit.new()                 # Dach
	var wall := {"feuerwache": BRICK, "busgarage": Color(0.78, 0.79, 0.78), "gepaeckumschlag": Color(0.62, 0.68, 0.74)}[id] as Color
	var door_col := {"feuerwache": FIRE_RED, "busgarage": Color(0.95, 0.75, 0.2), "gepaeckumschlag": Color(0.86, 0.87, 0.88)}[id] as Color
	# Boden der Halle und Vorplatz-Kante
	k.box(Vector3(x0, 0, z0), Vector3(x1, 0.08, z1), Color(0.56, 0.57, 0.56))
	# Wände: hinten, links, rechts; vorn Pfeiler zwischen den Toren und Sturz darüber
	k.box(Vector3(x0, 0, z0), Vector3(x1, hh, z0 + 0.3), wall)
	k.box(Vector3(x0, 0, z0), Vector3(x0 + 0.3, hh, z1), wall)
	k.box(Vector3(x1 - 0.3, 0, z0), Vector3(x1, hh, z1), wall)
	k.box(Vector3(xs - 0.15, 0, z0), Vector3(xs + 0.15, hh, z1), wall.darkened(0.05))   # Trennwand Seitenteil
	var edges := [xs]
	for e: Array in doors:
		var cx := (e[0] as Vector3).x
		var dw := float(e[1])
		edges.append(cx - dw * 0.5 - 0.12)
		edges.append(cx + dw * 0.5 + 0.12)
	edges.append(x1)
	for i in range(0, edges.size() - 1, 2):
		var a := float(edges[i])
		var b := float(edges[i + 1])
		if b - a > 0.05:
			k.box(Vector3(a, 0, z1 - 0.3), Vector3(b, hh, z1), wall)
	var dh := float(sz["dh"])
	k.box(Vector3(xs, dh + 0.3, z1 - 0.3), Vector3(x1, hh, z1), wall)
	# Sockel, Traufe, Fugen bei Klinker
	k.box(Vector3(x0 - 0.05, 0, z0 - 0.05), Vector3(x1 + 0.05, 0.4, z0 + 0.05), CONCRETE)
	var eave := CONCRETE if id == "feuerwache" else STEEL
	for e: Array in [[Vector3(x0 - 0.05, hh - 0.35, z0 - 0.05), Vector3(x1 + 0.05, hh, z0 + 0.35)], [Vector3(x0 - 0.05, hh - 0.35, z1 - 0.35), Vector3(x1 + 0.05, hh, z1 + 0.05)],
			[Vector3(x0 - 0.05, hh - 0.35, z0), Vector3(x0 + 0.35, hh, z1)], [Vector3(x1 - 0.35, hh - 0.35, z0), Vector3(x1 + 0.05, hh, z1)]]:
		k.box(e[0], e[1], eave)
	if id == "feuerwache":
		_joints(k, Vector3(x0, 0.4, z0), Vector3(x1, hh - 0.35, z0), Vector3(0, 0, -1), 0.27, BRICK.darkened(0.22))
	else:
		# Trapezblech: senkrechte Rippen auf der Rückwand und den Seiten
		var rx := x0 + 0.4
		while rx < x1 - 0.3:
			k.box(Vector3(rx, 0.4, z0 - 0.04), Vector3(rx + 0.12, hh - 0.35, z0), wall.darkened(0.12))
			rx += 0.9
	# Fensterband hinten
	var wx := xs + 2.5
	while wx < x1 - 2.0:
		_window(k, Vector3(wx, hh - 2.2, z0), Vector3(1.4, 0, 0), Vector3(0, 0.5, 0), Vector3(0, 0, -1), 2)
		wx += 4.5
	# Tore mit Anfahrschutz und Stellplätze dahinter
	for i in range(doors.size()):
		var e: Array = doors[i]
		var c: Vector3 = e[0]
		var dw := float(e[1])
		var dd := float(e[3])
		roll_door(n, k, i, Vector3(c.x, 0, z1 - 0.16), dw, dh, door_col, 4 if id == "feuerwache" else 3)
		for sx: float in [-1.0, 1.0]:
			var bp := Vector3(c.x + sx * (dw * 0.5 + 0.45), 0, z1 + 0.45)
			k.cyl(bp, bp + Vector3(0, 1.0, 0), 0.13, 0.13, YELLOW, 10)
			k.box(Vector3(c.x + sx * (float(sz["sp"]) * 0.5) - 0.07, 0.08, z1 - dd - 0.5), Vector3(c.x + sx * (float(sz["sp"]) * 0.5) + 0.07, 0.09, z1 - 0.4), YELLOW)
		# Licht über jedem Stellplatz
		for lz: float in [z1 - dd * 0.3, z1 - dd * 0.75]:
			k.box(Vector3(c.x - 0.9, hh - 0.6, lz), Vector3(c.x + 0.9, hh - 0.52, lz + 0.3), LAMP)
		match id:
			"feuerwache":
				var lf := MeshInstance3D.new()
				lf.name = "LF%d" % i
				lf.mesh = fire_truck_mesh()
				lf.position = Vector3(c.x, 0.08, z1 - 6.0)
				lf.rotation.y = PI
				lf.set_meta("no_bake", true)
				n.add_child(lf)
				# Spinde mit Schutzkleidung und Helmen, Abgasabsaugung
				k.box(Vector3(c.x - 2.5, 0.08, z0 + 0.3), Vector3(c.x + 2.5, 2.3, z0 + 0.75), STEEL)
				for j in range(7):
					var jx := c.x - 2.3 + float(j) * 0.65
					k.box(Vector3(jx, 1.0, z0 + 0.75), Vector3(jx + 0.45, 1.95, z0 + 0.95), Color(0.72, 0.6, 0.36))
					k.sphere(Vector3(jx + 0.22, 2.15, z0 + 0.7), 0.14, Color(0.9, 0.9, 0.85), 8, 4)
				k.cyl(Vector3(c.x, hh - 0.35, z1 - 8.0), Vector3(c.x, 3.9, z1 - 8.0), 0.13, 0.13, DARK, 8)
			"busgarage":
				# Stellplatz für einen Gelenk-/Solobus, im ersten Platz eine Arbeitsgrube mit Geländer
				if i == 0:
					k.box(Vector3(c.x - 0.6, 0.0, z1 - dd + 2.0), Vector3(c.x + 0.6, 0.09, z1 - 2.0), Color(0.15, 0.15, 0.16))
					for sx2: float in [-0.75, 0.75]:
						k.box(Vector3(c.x + sx2 - 0.03, 0.08, z1 - dd + 2.0), Vector3(c.x + sx2 + 0.03, 0.12, z1 - 2.0), YELLOW)
				k.box(Vector3(c.x - 2.0, 0.08, z0 + 0.3), Vector3(c.x + 2.0, 0.95, z0 + 1.0), Color(0.3, 0.45, 0.62))
				k.box(Vector3(c.x - 2.0, 0.95, z0 + 0.3), Vector3(c.x + 2.0, 1.0, z0 + 1.0), Color(0.55, 0.42, 0.28))
				k.box(Vector3(c.x - 1.8, 1.3, z0 + 0.3), Vector3(c.x + 1.8, 2.6, z0 + 0.36), Color(0.5, 0.52, 0.55))
			"gepaeckumschlag":
				# Entladeband längs der Spur (Koffer vom Gepäckzug), am Spurende ein Steilförderer hinauf
				# zum Sammelband unter der Decke. Dahinter bleibt der Quergang frei: dort wendet der Zug.
				var bx := c.x + dw * 0.5 + 1.2
				var bz0 := z1 - dd + 2.5
				var bz1 := z1 - 2.0
				k.box(Vector3(bx - 0.5, 0.0, bz0), Vector3(bx + 0.5, 0.75, bz1), Color(0.45, 0.47, 0.5))
				k.box(Vector3(bx - 0.42, 0.75, bz0), Vector3(bx + 0.42, 0.8, bz1), Color(0.13, 0.13, 0.14))
				var rz := bz0 + 1.0
				while rz < bz1:
					k.box(Vector3(bx - 0.55, 0.0, rz), Vector3(bx + 0.55, 0.85, rz + 0.12), Color(0.85, 0.7, 0.2))
					rz += 3.0
				for q in range(6):
					var bz := bz0 + 1.5 + float(q) * 3.4
					if bz < bz1 - 1.0:
						k.box(Vector3(bx - 0.25, 0.8, bz), Vector3(bx + 0.25, 1.2, bz + 0.6), [Color(0.15, 0.2, 0.45), Color(0.6, 0.1, 0.1), Color(0.1, 0.1, 0.1), Color(0.3, 0.55, 0.35)][(q + i) % 4])
				# Steilförderer am Spurende bis unter die Decke
				k.box(Vector3(bx - 0.55, 0.0, bz0 - 1.1), Vector3(bx + 0.55, 4.3, bz0), Color(0.42, 0.44, 0.47))
				k.box(Vector3(bx - 0.45, 0.8, bz0 - 0.02), Vector3(bx + 0.45, 4.2, bz0 + 0.02), Color(0.13, 0.13, 0.14))
				k.box(Vector3(bx - 0.6, 1.6, bz0 - 1.15), Vector3(bx + 0.6, 1.75, bz0 + 0.05), YELLOW)
				# Gehweg zwischen Spur und Band
				k.box(Vector3(c.x + dw * 0.5 + 0.3, 0.08, bz0 + 1.2), Vector3(bx - 0.6, 0.18, bz1), Color(0.62, 0.62, 0.6))
				# Leitlinie in der Spurmitte
				var lz := z1 - 1.0
				while lz > z1 - dd + 0.5:
					k.box(Vector3(c.x - 0.07, 0.08, lz - 1.2), Vector3(c.x + 0.07, 0.09, lz), Color(0.92, 0.92, 0.9))
					lz -= 2.4
	if id == "gepaeckumschlag":
		# Sammelband unter der Decke quer über die Spurenden (Züge passen darunter durch), im Seitenteil
		# hinab zum Förderbandtunnel
		var dd0 := float(sz["dd"])
		var cz := z1 - dd0 + 1.4
		k.box(Vector3(xs - 2.6, 4.3, cz - 0.5), Vector3(x1 - 1.0, 4.65, cz + 0.5), Color(0.45, 0.47, 0.5))
		k.box(Vector3(xs - 2.6, 4.65, cz - 0.42), Vector3(x1 - 1.0, 4.7, cz + 0.42), Color(0.13, 0.13, 0.14))
		var hx := xs + 1.0
		while hx < x1 - 1.0:
			k.box(Vector3(hx - 0.04, 4.65, cz - 0.04), Vector3(hx + 0.04, hh - 0.3, cz + 0.04), STEEL)
			hx += 4.5
		for q2 in range(int((x1 - xs) / 2.2)):
			var kx := xs + 0.8 + float(q2) * 2.2
			k.box(Vector3(kx, 4.7, cz - 0.25), Vector3(kx + 0.6, 5.05, cz + 0.25), [Color(0.15, 0.2, 0.45), Color(0.6, 0.1, 0.1), Color(0.1, 0.1, 0.1), Color(0.3, 0.55, 0.35)][q2 % 4])
		# im Seitenteil: Schräge vom Sammelband hinab zum Tunnelmund an der Rückwand
		var sx0 := xs - 2.6
		var sx1 := xs - 1.6
		var steps := 10
		for q3 in range(steps):
			var t0 := float(q3) / float(steps)
			var t1 := float(q3 + 1) / float(steps)
			var za := lerpf(cz, z0 + 3.8, t0)
			var zb := lerpf(cz, z0 + 3.8, t1)
			var ya := lerpf(4.3, 0.9, t1)
			k.box(Vector3(sx0, ya - 0.35, minf(za, zb)), Vector3(sx1, ya, maxf(za, zb)), Color(0.45, 0.47, 0.5))
		k.box(Vector3(x0 + 1.2, 0.0, z0 + 0.3), Vector3(xs - 1.2, 3.0, z0 + 3.6), Color(0.08, 0.08, 0.09))     # Tunnelmund
		# Quergang hinter den Spuren: Wendebögen in Gelb zwischen benachbarten Spuren, Schraffur an der Rückwand
		for i2 in range(doors.size() - 1):
			var xa := ((doors[i2] as Array)[0] as Vector3).x
			var xb := ((doors[i2 + 1] as Array)[0] as Vector3).x
			var shp := uturn_shape(xb - xa, dd0 - 2.0)
			for q4 in range(0, shp.size() - 1, 2):
				var u0: Vector2 = shp[q4]
				var u1: Vector2 = shp[q4 + 1]
				_floor_strip(k, Vector3(xa + u0.x, 0.0, z1 - u0.y), Vector3(xa + u1.x, 0.0, z1 - u1.y), 0.16, YELLOW)
		var hz := xs + 0.5
		while hz < x1 - 1.0:
			_floor_strip(k, Vector3(hz, 0.0, z0 + 0.6), Vector3(hz + 1.2, 0.0, z0 + 1.8), 0.22, YELLOW)
			hz += 1.6
		k.box(Vector3(xs + 0.2, 0.08, z0 + 2.2), Vector3(x1 - 0.5, 0.09, z0 + 2.36), YELLOW)
		k.box(Vector3(x0 + 1.0, 3.0, z0 + 0.3), Vector3(xs - 2.4, 3.4, z0 + 3.8), CONCRETE)
		PixelFont.draw(k, "GEPAECK", Vector3((xs + x1) * 0.5, hh - 1.0, z1 + 0.02), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.16, Color(0.14, 0.24, 0.45))
		# Leitstand mit Glasfront
		k.box(Vector3(x0 + 0.3, 0.08, z1 - 9.0), Vector3(xs - 0.2, 3.4, z1 - 0.3), Color(0.82, 0.83, 0.82))
		k.box(Vector3(x0 + 1.0, 1.0, z1 - 0.32), Vector3(xs - 1.0, 2.8, z1 - 0.26), WIN)
	elif id == "busgarage":
		# Waschhalle im Seitenteil: Portal mit zwei Bürsten, Büro hinten
		var wcx := (x0 + xs) * 0.5
		roll_door(n, k, doors.size(), Vector3(wcx, 0, z1 - 0.16), float(sz["side"]) - 3.0, 4.6, Color(0.3, 0.55, 0.85), 2)
		k.box(Vector3(x0 + 0.3, 0.08, z0 + 0.3), Vector3(xs - 0.2, 0.12, z1 - 0.3), Color(0.38, 0.4, 0.42))
		for z: float in [-2.0, 2.0]:
			for sx3: float in [x0 + 1.2, xs - 1.2]:
				k.box(Vector3(sx3 - 0.15, 0.1, z - 0.15), Vector3(sx3 + 0.15, 4.4, z + 0.15), Color(0.2, 0.45, 0.8))
			k.box(Vector3(x0 + 1.0, 4.4, z - 0.25), Vector3(xs - 1.0, 4.7, z + 0.25), Color(0.2, 0.45, 0.8))
		for e2: Array in [[x0 + 2.4, 1.5], [xs - 2.4, -1.5]]:
			var bk := Kit.new()
			bk.cyl(Vector3(0, 0, 0), Vector3(0, 3.6, 0), 0.07, 0.07, STEEL, 6)
			for j in range(10):
				var a := float(j) / 10.0 * TAU
				bk.box(Vector3(cos(a) * 0.1 - 0.03, 0.2, sin(a) * 0.1 - 0.03), Vector3(cos(a) * 0.55 + 0.03, 3.5, sin(a) * 0.55 + 0.03), Color(0.25, 0.55, 0.95) if j % 2 == 0 else Color(0.85, 0.2, 0.2))
			var br := _part(n, "DrehBuerste%d" % j_hash(e2[0]), bk, Vector3(float(e2[0]), 0.4, 0))
			br.set_meta("speed", float(e2[1]) * 2.0)
		k.box(Vector3(x0 + 0.3, 0.0, z0 + 0.3), Vector3(xs - 0.2, hh - 0.4, z0 + 7.0), RENDER)
		for wy: float in [1.8, 4.8]:
			_window(k, Vector3(x0, wy, z0 + 3.6), Vector3(0, 0, 2.2), Vector3(0, 0.6, 0), Vector3(-1, 0, 0), 2)
		k.box(Vector3(x0 + 1.0, hh - 2.0, z1 + 0.01), Vector3(x0 + 5.0, hh - 0.9, z1 + 0.08), Color(0.16, 0.24, 0.38))
		PixelFont.draw(k, "BUS", Vector3(x0 + 3.0, hh - 1.45, z1 + 0.09), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.12, Color(0.98, 0.85, 0.3))
	elif id == "feuerwache":
		# Bürotrakt mit Leitstelle (zwei Geschosse) und Schlauchturm mit Sirene und Blaulicht
		var oh := hh + 0.4
		k.box(Vector3(x0, 0, z0), Vector3(xs - 0.15, oh, z1), RENDER)
		k.box(Vector3(x0, oh - 0.55, z1 - 0.01), Vector3(xs, oh, z1 + 0.06), FIRE_RED)
		for wyy: float in [1.85, 5.35]:
			var wx2 := x0 + 1.6
			while wx2 < xs - 1.0:
				_window(k, Vector3(wx2, wyy, z1), Vector3(0.7, 0, 0), Vector3(0, 0.7, 0), Vector3(0, 0, 1), 1)
				wx2 += 2.4
		k.box(Vector3(x0 + 1.0, 0, z1), Vector3(x0 + 3.0, 2.7, z1 + 0.06), FRAME)
		k.box(Vector3(x0 + 1.1, 0.1, z1 + 0.04), Vector3(x0 + 2.9, 2.6, z1 + 0.1), WIN)
		var th := 18.0
		k.box(Vector3(x0 + 0.5, 0, z0 + 0.5), Vector3(x0 + 4.0, th, z0 + 4.0), BRICK)
		_joints(k, Vector3(x0 + 0.5, 0.4, z0 + 0.5), Vector3(x0 + 4.0, th, z0 + 0.5), Vector3(0, 0, -1), 0.27, BRICK.darkened(0.22))
		k.box(Vector3(x0 + 0.3, th, z0 + 0.3), Vector3(x0 + 4.2, th + 0.4, z0 + 4.2), CONCRETE)
		k.cyl(Vector3(x0 + 2.25, th + 0.4, z0 + 2.25), Vector3(x0 + 2.25, th + 1.4, z0 + 2.25), 0.12, 0.12, STEEL, 6)
		k.box(Vector3(x0 + 1.6, th + 1.4, z0 + 1.6), Vector3(x0 + 2.9, th + 1.9, z0 + 2.9), Color(0.75, 0.76, 0.78))
		_blinker(n, Vector3(x0 + 2.25, th + 2.1, z0 + 2.25), BLUE_LAMP, 0.18, 0.8, 0.0)
		PixelFont.draw(k, "FEUERWEHR", Vector3((xs + x1) * 0.5, hh - 1.0, z1 + 0.02), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.13, WHITE)
	# Dach: Flachdach mit Attika, Lichtbändern und Lüftern; bei der Feuerwache Solarmodule
	rk.box(Vector3(x0, hh - 0.05, z0), Vector3(x1, hh + 0.1, z1), ROOF)
	_parapet(rk, x0, z0, x1, z1, hh + 0.1, 0.5, wall if id == "feuerwache" else STEEL)
	var sx4 := xs + 3.0
	while sx4 < x1 - 3.0:
		if id == "feuerwache":
			rk.box(Vector3(sx4 - 1.4, hh + 0.12, z0 + 2.0), Vector3(sx4 + 1.4, hh + 0.5, z1 - 2.0), Color(0.12, 0.17, 0.32))
		else:
			rk.box(Vector3(sx4 - 0.8, hh + 0.1, z0 + 2.5), Vector3(sx4 + 0.8, hh + 0.45, z1 - 2.5), Color(0.55, 0.7, 0.8, 0.6))
		sx4 += 6.0
	rk.box(Vector3(x0 + 2.0, hh + 0.1, z0 + 6.0), Vector3(x0 + 4.0, hh + 1.2, z0 + 8.0), Color(0.7, 0.72, 0.74))
	var roof := MeshInstance3D.new()
	roof.name = "Dach"
	roof.mesh = rk.commit()
	roof.material_override = Kit.material()
	roof.set_meta("no_bake", true)
	n.add_child(roof)
	n.add_child(k.instance("Halle"))


## Wendeschleife im Gepäckumschlag von einer Spur in die Nachbarspur (seitlicher Abstand dx), ab Tiefe d0
## hinter dem Tor: erst 1,5 m zur Gegenseite ausholen, dann im Halbkreis (Radius |dx|/2 + 1,5 m) hinüber
## und zurück in die Spur. Punkte als (seitlich, Tiefe hinter dem Tor).
static func uturn_shape(dx: float, d0: float) -> Array:
	var sg := signf(dx)
	var sw := 1.5
	var r := absf(dx) * 0.5 + sw
	var dc := d0 + 4.0
	var out := []
	for k in range(7):
		var t := float(k) / 6.0
		out.append(Vector2(-sg * sw * smoothstep(0.0, 1.0, t), d0 + 4.0 * t))
	for k in range(1, 16):
		var a := PI * float(k) / 16.0
		out.append(Vector2(dx * 0.5 - sg * r * cos(a), dc + r * sin(a)))
	for k in range(1, 7):
		var t2 := float(k) / 6.0
		out.append(Vector2(dx + sg * sw * (1.0 - smoothstep(0.0, 1.0, t2)), dc - 4.0 * t2))
	return out


## Bodenmarkierung als flacher Streifen von a nach b (Breite w).
static func _floor_strip(k: Kit, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	d.y = 0.0
	if d.length() < 0.01:
		return
	var s := d.normalized().cross(Vector3.UP) * (w * 0.5)
	var y := Vector3(0, 0.09, 0)
	k.quad(a - s + y, b - s + y, b + s + y, a + s + y, col, (a + b) * 0.5 - Vector3(0, 1, 0))


static func j_hash(x: Variant) -> int:
	return absi(int(float(x) * 10.0)) % 997
