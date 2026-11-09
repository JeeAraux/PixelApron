extends RefCounted
## Baut die sichtbaren Formen: Wege-Bänder, Gebäude, Deko und Fahrzeuge
## aus einfachen Grundkörpern (Low-Poly, später durch Blender-Modelle ersetzbar).

const Catalog = preload("res://scripts/catalog.gd")
const Spline = preload("res://scripts/spline.gd")
const LINE_SHADER = preload("res://shaders/line.gdshader")

const WALL := Color(0.78, 0.75, 0.67)
const GLASS := Color(0.17, 0.24, 0.29)
const ROOF := Color(0.32, 0.32, 0.30)
const STEEL := Color(0.36, 0.41, 0.44)
const CONCRETE := Color(0.58, 0.57, 0.53)
const BRICK := Color(0.52, 0.24, 0.19)
const DARK := Color(0.12, 0.12, 0.13)
const WOOD := Color(0.42, 0.31, 0.21)
const TERRACOTTA := Color(0.56, 0.31, 0.21)
const FLOOR := Color(0.72, 0.70, 0.65)
const WHITE := Color(0.90, 0.89, 0.86)
const SEAT := Color(0.22, 0.35, 0.55)
const YELLOW := Color(0.86, 0.69, 0.22)
const SHIRTS := [Color(0.75, 0.24, 0.2), Color(0.22, 0.38, 0.62), Color(0.9, 0.88, 0.82), Color(0.2, 0.2, 0.22),
	Color(0.36, 0.55, 0.32), Color(0.85, 0.66, 0.22), Color(0.55, 0.32, 0.55), Color(0.4, 0.6, 0.75)]
const SKINS := [Color(0.93, 0.78, 0.65), Color(0.80, 0.6, 0.45), Color(0.55, 0.38, 0.27), Color(0.36, 0.25, 0.18)]

const CAR_COLORS := [Color(0.72, 0.72, 0.70), Color(0.86, 0.85, 0.81), Color(0.13, 0.13, 0.14),
	Color(0.20, 0.27, 0.40), Color(0.55, 0.17, 0.14), Color(0.41, 0.42, 0.43), Color(0.21, 0.32, 0.25),
	Color(0.62, 0.56, 0.43), Color(0.30, 0.36, 0.44)]

static var _mats: Dictionary = {}


static func car_color() -> Color:
	return CAR_COLORS[randi() % CAR_COLORS.size()]


static func mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic_specular = 0.0
	_mats[key] = m
	return m


## Durchsichtiges Material (Glaswände), wirft keinen Schatten.
static func glass_mat() -> StandardMaterial3D:
	var key := "glass_alpha"
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.82, 0.92, 0.38)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.2
	_mats[key] = m
	return m


static func blk(parent: Node3D, a: Vector3, b: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = (b - a).abs()
	mi.mesh = bm
	mi.position = (a + b) * 0.5
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, base: Vector3, r_bottom: float, r_top: float, h: float, c: Color, seg: int = 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r_bottom
	cm.top_radius = r_top
	cm.height = h
	cm.radial_segments = seg
	cm.rings = 1
	mi.mesh = cm
	mi.position = base + Vector3(0.0, h * 0.5, 0.0)
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi


static func ball(parent: Node3D, center: Vector3, r: float, c: Color, seg: int = 7) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = seg
	sm.rings = 4
	mi.mesh = sm
	mi.position = center
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- Wege

static func make_line(kind: String, samples: PackedVector3Array, y: float) -> Node3D:
	var def: Dictionary = Catalog.LINES[kind]
	if bool(def.get("wall", false)):
		return make_wall(kind, samples[0], samples[samples.size() - 1])
	var w: float = def["width"]
	var mi := MeshInstance3D.new()
	mi.name = kind
	mi.mesh = Spline.ribbon(samples, w, y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if String(def.get("utility", "")) != "":
		var um := StandardMaterial3D.new()
		um.albedo_color = def["color"]
		um.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		um.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = um
		return mi
	var sm := ShaderMaterial.new()
	sm.shader = LINE_SHADER
	sm.set_shader_parameter("base_color", def["color"])
	sm.set_shader_parameter("mark", def["mark"])
	sm.set_shader_parameter("width", w)
	sm.set_shader_parameter("len", Spline.length(samples))
	mi.material_override = sm
	return mi


# ---------------------------------------------------------------- Gebäude und Deko

## Wand im Terminal: hohe Fassung ("Hoch") und niedrige für die Innenansicht ("Tief").
static func make_wall(kind: String, a: Vector3, b: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := d.length()
	var mid := (a + b) * 0.5
	var basis := Basis.looking_at(d.normalized(), Vector3.UP) if length > 0.01 else Basis.IDENTITY
	for part: Array in [["Hoch", 3.6], ["Tief", 1.2]]:
		var holder := Node3D.new()
		holder.name = String(part[0])
		holder.transform = Transform3D(basis, Vector3(mid.x, 0.0, mid.z))
		root.add_child(holder)
		var h: float = part[1]
		var hl := length * 0.5 + 0.15
		if kind == "glaswand":
			blk(holder, Vector3(-0.15, 0, -hl), Vector3(0.15, 0.3, hl), STEEL)
			var g := blk(holder, Vector3(-0.06, 0.3, -hl), Vector3(0.06, h - 0.12, hl), WHITE)
			g.material_override = glass_mat()
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			blk(holder, Vector3(-0.12, h - 0.12, -hl), Vector3(0.12, h, hl), STEEL)
			var z := -hl
			while z < hl:
				blk(holder, Vector3(-0.08, 0.3, z), Vector3(0.08, h - 0.12, z + 0.1), STEEL)
				z += 2.0
		else:
			blk(holder, Vector3(-0.15, 0, -hl), Vector3(0.15, h, hl), Color(0.88, 0.86, 0.80))
			blk(holder, Vector3(-0.16, 0, -hl), Vector3(0.16, 0.12, hl), Color(0.55, 0.53, 0.49))
	return root


## Terminalhalle w × d: Boden, Glasfassade (hoch und niedrig) und Dach als eigene Knoten.
static func make_hall(w: float, d: float) -> Node3D:
	var n := Node3D.new()
	n.name = "halle"
	var hw := w * 0.5
	var hd := d * 0.5
	blk(n, Vector3(-hw, 0, -hd), Vector3(hw, 0.1, hd), FLOOR)
	var line_c := Color(0.72, 0.70, 0.64)
	var x := -hw + 4.0
	while x < hw - 0.5:
		blk(n, Vector3(x - 0.05, 0.1, -hd), Vector3(x + 0.05, 0.11, hd), line_c)
		x += 4.0
	var z := -hd + 4.0
	while z < hd - 0.5:
		blk(n, Vector3(-hw, 0.1, z - 0.05), Vector3(hw, 0.11, z + 0.05), line_c)
		z += 4.0
	var high := Node3D.new()
	high.name = "Hoch"
	n.add_child(high)
	var low := Node3D.new()
	low.name = "Tief"
	n.add_child(low)
	# vier Seiten: [Mitte, halbe Länge, entlang x?]
	for side: Array in [[Vector3(0, 0, hd - 0.15), hw, true], [Vector3(0, 0, -hd + 0.15), hw, true],
			[Vector3(hw - 0.15, 0, 0), hd, false], [Vector3(-hw + 0.15, 0, 0), hd, false]]:
		var c: Vector3 = side[0]
		var half: float = side[1]
		var along: bool = side[2]
		var ext := func(l: float, t: float) -> Vector3: return Vector3(l, 0, t) if along else Vector3(t, 0, l)
		var e1: Vector3 = ext.call(half, 0.15)
		blk(high, c - e1, c + e1 + Vector3(0, 0.6, 0), CONCRETE)
		blk(high, c - e1 + Vector3(0, 0.6, 0), c + e1 + Vector3(0, 7.4, 0), GLASS)
		blk(high, c - e1 + Vector3(0, 7.4, 0), c + e1 + Vector3(0, 9.0, 0), WALL)
		var t := -half + 4.0
		while t < half - 0.5:
			var m: Vector3 = c + ext.call(t, 0.0)
			var e2: Vector3 = ext.call(0.2, 0.2)
			blk(high, m - e2 + Vector3(0, 0.6, 0), m + e2 + Vector3(0, 7.4, 0), WALL)
			t += 4.0
		blk(low, c - e1, c + e1 + Vector3(0, 0.6, 0), CONCRETE)
		var gl := blk(low, c - e1 + Vector3(0, 0.6, 0), c + e1 + Vector3(0, 1.3, 0), WHITE)
		gl.material_override = glass_mat()
		blk(low, c - e1 + Vector3(0, 1.3, 0), c + e1 + Vector3(0, 1.45, 0), WALL)
	var roof := Node3D.new()
	roof.name = "Dach"
	n.add_child(roof)
	blk(roof, Vector3(-hw - 0.4, 9.0, -hd - 0.4), Vector3(hw + 0.4, 9.6, hd + 0.4), ROOF)
	var sx := -hw + 6.0
	while sx < hw - 4.0:
		blk(roof, Vector3(sx - 1.0, 9.6, -hd + 3.0), Vector3(sx + 1.0, 9.9, hd - 3.0), Color(0.36, 0.46, 0.52))
		sx += 12.0
	var units := clampi(int(w * d / 500.0), 1, 12)
	for i in range(units):
		var ux := -hw + (float(i) + 0.5) * w / float(units)
		var uz := (hd * 0.45) * (1.0 if i % 2 == 0 else -1.0)
		blk(roof, Vector3(ux - 2.0, 9.6, uz - 1.5), Vector3(ux + 2.0, 10.9, uz + 1.5), Color(0.45, 0.47, 0.47))
	return n


static func make_item(id: String) -> Node3D:
	if id == "halle":
		return make_hall(24.0, 16.0)
	var n := Node3D.new()
	n.name = id
	if Catalog.is_inside(id):
		_inside(n, id)
		return n
	match id:
		"hangar":
			_hangar(n)
		"tower":
			_tower(n)
		"parkhaus":
			_parkhaus(n)
		"feuerwache":
			_feuerwache(n)
		"trafo":
			_trafo(n)
		"heizzentrale":
			_heizzentrale(n)
		"baum":
			_baum(n)
		"stand":
			_stand(n)
		"vorfelddepot":
			_depot(n)
		"wasseranschluss":
			blk(n, Vector3(-2, 0, -2), Vector3(2, 0.4, 2), CONCRETE)
			cyl(n, Vector3(0, 0.4, 0), 0.7, 0.7, 0.9, Color(0.25, 0.48, 0.72), 8)
			cyl(n, Vector3(0, 1.3, 0), 0.9, 0.9, 0.3, Color(0.2, 0.38, 0.6), 8)
		"kuebel":
			cyl(n, Vector3.ZERO, 0.55, 0.65, 0.75, TERRACOTTA, 8)
			ball(n, Vector3(0, 1.15, 0), 0.62, Color(0.25, 0.36, 0.17), 6)
		"laterne":
			blk(n, Vector3(-0.1, 0, -0.1), Vector3(0.1, 7.0, 0.1), STEEL)
			blk(n, Vector3(-0.1, 6.8, -0.1), Vector3(0.1, 7.0, 1.3), STEEL)
			blk(n, Vector3(-0.25, 6.6, 0.9), Vector3(0.25, 6.85, 1.5), Color(0.9, 0.86, 0.66))
		"bank":
			blk(n, Vector3(-1.1, 0.4, -0.3), Vector3(1.1, 0.5, 0.3), WOOD)
			blk(n, Vector3(-1.1, 0.5, 0.2), Vector3(1.1, 0.95, 0.3), WOOD)
			for x: float in [-0.9, 0.9]:
				blk(n, Vector3(x - 0.08, 0, -0.25), Vector3(x + 0.08, 0.4, 0.25), DARK)
	return n


static func _terminal_old(n: Node3D) -> void:
	blk(n, Vector3(-24, 0, -14), Vector3(24, 9, 14), WALL)
	blk(n, Vector3(-24.15, 2.0, -14.15), Vector3(24.15, 7.4, 14.15), GLASS)
	for x in range(-22, 23, 4):
		blk(n, Vector3(x - 0.2, 2.0, 14.1), Vector3(x + 0.2, 7.4, 14.25), WALL)
		blk(n, Vector3(x - 0.2, 2.0, -14.25), Vector3(x + 0.2, 7.4, -14.1), WALL)
	blk(n, Vector3(-24.4, 9, -14.4), Vector3(24.4, 9.7, 14.4), ROOF)
	for p: Vector3 in [Vector3(-14, 0, -6), Vector3(-4, 0, 5), Vector3(11, 0, -3)]:
		blk(n, p + Vector3(-2.5, 9.7, -2), p + Vector3(2.5, 11.0, 2), Color(0.45, 0.47, 0.47))
	# Vordach auf der Landseite (+z) und Schriftband
	blk(n, Vector3(-14, 4.6, 14.2), Vector3(14, 5.1, 19.5), STEEL)
	for x: float in [-13.0, 0.0, 13.0]:
		blk(n, Vector3(x - 0.25, 0, 18.9), Vector3(x + 0.25, 4.6, 19.4), STEEL)
	blk(n, Vector3(-9, 7.6, 14.2), Vector3(9, 8.7, 14.45), DARK)
	blk(n, Vector3(-8, 7.9, 14.3), Vector3(8, 8.4, 14.5), Color(0.93, 0.9, 0.78))


static func _hangar(n: Node3D) -> void:
	blk(n, Vector3(-22, 0, -18), Vector3(22, 13, 18), Color(0.62, 0.66, 0.68))
	blk(n, Vector3(-22.3, 13, -18.3), Vector3(22.3, 14.2, 18.3), Color(0.44, 0.47, 0.49))
	blk(n, Vector3(-19, 0, -18.25), Vector3(19, 11.5, -17.95), Color(0.38, 0.42, 0.45))
	for x in range(-17, 18, 4):
		blk(n, Vector3(x - 0.12, 0, -18.4), Vector3(x + 0.12, 11.5, -18.2), Color(0.28, 0.31, 0.34))
	blk(n, Vector3(-22.1, 9, -14), Vector3(22.1, 10.2, 14), GLASS)


static func _tower(n: Node3D) -> void:
	blk(n, Vector3(-6, 0, -6), Vector3(6, 5, 6), WALL)
	blk(n, Vector3(-6.3, 5, -6.3), Vector3(6.3, 5.5, 6.3), ROOF)
	cyl(n, Vector3(0, 5.5, 0), 2.4, 2.2, 23.0, Color(0.84, 0.82, 0.76), 10)
	cyl(n, Vector3(0, 28.5, 0), 3.4, 4.6, 1.0, ROOF, 8)
	cyl(n, Vector3(0, 29.5, 0), 4.4, 4.4, 3.8, GLASS, 8)
	cyl(n, Vector3(0, 33.3, 0), 5.0, 4.6, 0.8, ROOF, 8)
	blk(n, Vector3(-0.15, 34.1, -0.15), Vector3(0.15, 39.0, 0.15), DARK)


static func _parkhaus(n: Node3D) -> void:
	for lvl in range(1, 5):
		var y := float(lvl) * 3.0
		blk(n, Vector3(-16, y, -22), Vector3(16, y + 0.4, 22), CONCRETE)
		for side: float in [-1.0, 1.0]:
			blk(n, Vector3(-16, y + 0.4, side * 21.85 - 0.15), Vector3(16, y + 1.3, side * 21.85 + 0.15), CONCRETE)
			blk(n, Vector3(side * 15.85 - 0.15, y + 0.4, -22), Vector3(side * 15.85 + 0.15, y + 1.3, 22), CONCRETE)
	for x: float in [-15.6, -5.2, 5.2, 15.6]:
		for z: float in [-21.6, -7.2, 7.2, 21.6]:
			blk(n, Vector3(x - 0.3, 0, z - 0.3), Vector3(x + 0.3, 12.0, z + 0.3), CONCRETE)
	blk(n, Vector3(10.5, 0, -22), Vector3(16, 14.5, -16.5), CONCRETE)
	blk(n, Vector3(16.0, 9.5, -21.5), Vector3(16.15, 13.5, -17.0), Color(0.16, 0.32, 0.55))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for row: float in [-17.0, -11.0, -1.0, 5.0, 15.0]:
		for k in range(11):
			if rng.randf() < 0.18:
				continue
			var car := make_car(CAR_COLORS[rng.randi() % CAR_COLORS.size()])
			car.position = Vector3(-13.0 + float(k) * 2.6, 12.4, row)
			n.add_child(car)


static func _feuerwache(n: Node3D) -> void:
	blk(n, Vector3(-15, 0, -10), Vector3(15, 7, 10), BRICK)
	blk(n, Vector3(-15.3, 7, -10.3), Vector3(15.3, 7.6, 10.3), ROOF)
	for x: float in [-9.0, 0.0, 9.0]:
		blk(n, Vector3(x - 3.5, 0, 10.0), Vector3(x + 3.5, 5.4, 10.18), Color(0.70, 0.16, 0.12))
	blk(n, Vector3(11, 0, -10), Vector3(15, 12.5, -6), BRICK)
	blk(n, Vector3(10.8, 12.5, -10.2), Vector3(15.2, 13.0, -5.8), ROOF)


static func _trafo(n: Node3D) -> void:
	blk(n, Vector3(-5, 0, -3.5), Vector3(5, 3.4, 3.5), CONCRETE)
	blk(n, Vector3(-5.2, 3.4, -3.7), Vector3(5.2, 3.7, 3.7), ROOF)
	for x: float in [-2.8, 0.6]:
		blk(n, Vector3(x, 0, 3.5), Vector3(x + 2.2, 2.5, 3.62), STEEL)
	blk(n, Vector3(3.2, 2.6, 3.5), Vector3(3.8, 3.1, 3.64), Color(0.82, 0.68, 0.2))


static func _heizzentrale(n: Node3D) -> void:
	blk(n, Vector3(-11, 0, -7.5), Vector3(11, 7.5, 7.5), BRICK)
	blk(n, Vector3(-11.2, 7.5, -7.7), Vector3(11.2, 7.9, 7.7), ROOF)
	for x: float in [-6.0, 1.0]:
		blk(n, Vector3(x, 0, 7.5), Vector3(x + 4.0, 4.2, 7.65), STEEL)
	for x in range(-9, 10, 3):
		blk(n, Vector3(x, 4.8, 7.5), Vector3(x + 1.4, 6.4, 7.6), GLASS)
	cyl(n, Vector3(8, 7.9, -4), 0.9, 0.8, 15.0, STEEL, 8)


static func _baum(n: Node3D) -> void:
	var green := Color.from_hsv(randf_range(0.22, 0.3), randf_range(0.45, 0.6), randf_range(0.26, 0.36))
	cyl(n, Vector3.ZERO, 0.38, 0.3, 3.2, Color(0.25, 0.19, 0.13), 6)
	ball(n, Vector3(0, 5.2, 0), 2.6, green, 7)
	for i in range(2):
		var off := Vector3(randf_range(-1.3, 1.3), randf_range(5.4, 6.4), randf_range(-1.3, 1.3))
		ball(n, off, 1.8, green.lightened(0.06 * float(i)), 6)


static func _stand(n: Node3D) -> void:
	var yellow := Color(0.86, 0.69, 0.22)
	var red := Color(0.7, 0.2, 0.15)
	blk(n, Vector3(-0.2, 0.0, -23.0), Vector3(0.2, 0.12, 14.0), yellow)
	blk(n, Vector3(-2.5, 0.0, 14.0), Vector3(2.5, 0.12, 14.4), yellow)
	for side: float in [-1.0, 1.0]:
		blk(n, Vector3(side * 20.0 - 0.15, 0.0, -23.0), Vector3(side * 20.0 + 0.15, 0.12, 23.0), red)
	blk(n, Vector3(-20.0, 0.0, 22.7), Vector3(20.0, 0.12, 23.0), red)


static func _depot(n: Node3D) -> void:
	blk(n, Vector3(-13, 0, -8), Vector3(13, 6.0, -6.5), CONCRETE)
	blk(n, Vector3(-13, 0, -8), Vector3(-11.5, 6.0, 8), CONCRETE)
	blk(n, Vector3(11.5, 0, -8), Vector3(13, 6.0, 8), CONCRETE)
	blk(n, Vector3(-13.3, 6.0, -8.3), Vector3(13.3, 6.6, 8.3), ROOF)
	for x: float in [-4.0, 4.0]:
		blk(n, Vector3(x - 0.3, 0, 7.5), Vector3(x + 0.3, 6.0, 8.0), STEEL)
	var v1 := make_gse("tank")
	v1.position = Vector3(-7, 0, 0)
	n.add_child(v1)
	var v2 := make_gse("catering")
	v2.position = Vector3(0, 0, 0)
	n.add_child(v2)
	var v3 := make_gse("gepaeck")
	v3.position = Vector3(7, 0, 0)
	n.add_child(v3)


# ---------------------------------------------------------------- Fahrzeuge (Front zeigt nach -Z)

static func make_gse(kind: String) -> Node3D:
	var n := Node3D.new()
	var yellow := Color(0.86, 0.69, 0.22)
	match kind:
		"tank":
			blk(n, Vector3(-1.2, 0.4, -4.5), Vector3(1.2, 2.6, -2.3), yellow)
			blk(n, Vector3(-1.1, 1.4, -4.3), Vector3(1.1, 2.3, -3.6), GLASS)
			var t := cyl(n, Vector3.ZERO, 1.15, 1.15, 6.0, Color(0.85, 0.85, 0.82), 10)
			t.rotation_degrees = Vector3(90, 0, 0)
			t.position = Vector3(0, 1.75, 0.9)
		"catering":
			blk(n, Vector3(-1.1, 0.4, -3.6), Vector3(1.1, 2.4, -1.8), yellow)
			blk(n, Vector3(-1.3, 2.0, -1.6), Vector3(1.3, 4.6, 3.4), Color(0.88, 0.87, 0.84))
			blk(n, Vector3(-1.2, 0.5, -1.8), Vector3(1.2, 2.0, 3.4), DARK)
		_:
			blk(n, Vector3(-0.8, 0.3, -1.4), Vector3(0.8, 1.4, 0.6), yellow)
			for i in range(2):
				var z := 2.2 + float(i) * 3.4
				blk(n, Vector3(-0.85, 0.4, z - 1.4), Vector3(0.85, 1.9, z + 1.4), Color(0.24, 0.34, 0.45))
	return n




static func make_car(c: Color) -> Node3D:
	var n := Node3D.new()
	blk(n, Vector3(-0.9, 0.25, -2.2), Vector3(0.9, 0.95, 2.2), c)
	blk(n, Vector3(-0.8, 0.95, -1.0), Vector3(0.8, 1.45, 1.1), c.darkened(0.55))
	return n


static func make_plane(kind: String, livery: Color) -> Node3D:
	var n := Node3D.new()
	var white := Color(0.86, 0.85, 0.82)
	var grey := Color(0.74, 0.74, 0.72)
	var big := kind == "a320"
	var r := 2.0 if big else 1.45
	var length := 37.0 if big else 27.0
	var zc := 3.2 if big else 2.4
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = r
	cap.height = length
	cap.radial_segments = 10
	cap.rings = 2
	body.mesh = cap
	body.material_override = mat(white)
	body.rotation_degrees = Vector3(90, 0, 0)
	body.position = Vector3(0, zc, 0)
	n.add_child(body)
	var half := length * 0.5
	blk(n, Vector3(-r - 0.02, zc - 0.7, -half + 3.5), Vector3(r + 0.02, zc - 0.25, half - 4.0), livery)
	if big:
		blk(n, Vector3(-17, 2.3, -2.0), Vector3(17, 2.7, 3.5), grey)
		for x: float in [-5.8, 5.8]:
			var eng := cyl(n, Vector3.ZERO, 1.0, 1.0, 4.5, livery, 8)
			eng.rotation_degrees = Vector3(90, 0, 0)
			eng.position = Vector3(x, 1.4, -1.5)
		blk(n, Vector3(-0.25, 4.5, 13.0), Vector3(0.25, 11.5, 18.0), livery)
		blk(n, Vector3(-6.0, 4.6, 15.0), Vector3(6.0, 4.9, 18.0), grey)
	else:
		blk(n, Vector3(-13.5, 3.75, -2.5), Vector3(13.5, 4.1, 0.2), grey)
		for x: float in [-4.1, 4.1]:
			var eng := cyl(n, Vector3.ZERO, 0.7, 0.7, 5.0, white, 8)
			eng.rotation_degrees = Vector3(90, 0, 0)
			eng.position = Vector3(x, 3.4, -2.0)
			blk(n, Vector3(x - 1.9, 3.4 - 1.9, -4.62), Vector3(x + 1.9, 3.4 + 1.9, -4.52), Color(0.2, 0.2, 0.2, 1.0))
		blk(n, Vector3(-0.2, 3.3, 9.5), Vector3(0.2, 7.6, 13.4), livery)
		blk(n, Vector3(-3.7, 7.35, 11.5), Vector3(3.7, 7.6, 13.6), grey)
	return n


## Kleines Wegstück auf einem Wiesenstück, für die Vorschaubilder im Baumenü.
static func make_line_thumb(kind: String) -> Node3D:
	var def: Dictionary = Catalog.LINES[kind]
	var w: float = def["width"]
	var k := clampf(w * 1.6, 8.0, 70.0)
	var n := Node3D.new()
	blk(n, Vector3(-k, -0.3, -k), Vector3(k, 0.0, k), Color(0.27, 0.29, 0.15))
	var pts: Array = [Vector3(-k, 0, k * 0.35), Vector3(0, 0, -k * 0.15), Vector3(k, 0, k * 0.2)]
	if bool(def["straight"]):
		pts = [Vector3(-k, 0, k * 0.2), Vector3(k, 0, -k * 0.2)]
	var samples := Spline.path(pts, bool(def["straight"]))
	n.add_child(make_line(kind, samples, 0.05))
	return n


## Umhüllender Quader aller Meshes unterhalb von node (in dessen Koordinaten).
static func bounds_of(node: Node3D) -> AABB:
	var acc := [AABB(), false]
	_collect(node, Transform3D.IDENTITY, acc)
	return acc[0]


static func _collect(n: Node, xf: Transform3D, acc: Array) -> void:
	for c in n.get_children():
		if not (c is Node3D):
			continue
		var c3 := c as Node3D
		var cx := xf * c3.transform
		if c3 is MeshInstance3D and (c3 as MeshInstance3D).mesh != null:
			var box: AABB = cx * (c3 as MeshInstance3D).mesh.get_aabb()
			if acc[1]:
				acc[0] = (acc[0] as AABB).merge(box)
			else:
				acc[0] = box
				acc[1] = true
		_collect(c3, cx, acc)


# ---------------------------------------------------------------- Terminal-Einrichtung (Vorderseite +Z)

static func _inside(n: Node3D, id: String) -> void:
	match id:
		"eingang":
			blk(n, Vector3(-3, 0, -1), Vector3(3, 0.12, 1), DARK)
			blk(n, Vector3(-3, 0, -0.25), Vector3(-2.6, 3.2, 0.25), STEEL)
			blk(n, Vector3(2.6, 0, -0.25), Vector3(3, 3.2, 0.25), STEEL)
			blk(n, Vector3(-3, 2.9, -0.3), Vector3(3, 3.4, 0.3), STEEL)
			for x: float in [-1.7, 1.7]:
				var g := blk(n, Vector3(x - 0.9, 0.05, -0.06), Vector3(x + 0.9, 2.9, 0.06), WHITE)
				g.material_override = glass_mat()
			# Vordach außen
			blk(n, Vector3(-3.6, 3.5, 1.0), Vector3(3.6, 3.8, 3.8), STEEL)
			for x: float in [-3.3, 3.3]:
				blk(n, Vector3(x - 0.1, 0, 3.5), Vector3(x + 0.1, 3.5, 3.7), STEEL)
			blk(n, Vector3(-1.2, 3.8, 1.1), Vector3(1.2, 4.3, 1.3), Color(0.2, 0.45, 0.3))
		"checkin":
			for x: float in [-1.5, 1.5]:
				blk(n, Vector3(x - 1.2, 0, -0.2), Vector3(x + 1.2, 1.05, 0.5), WHITE)
				blk(n, Vector3(x - 1.25, 1.05, -0.25), Vector3(x + 1.25, 1.12, 0.55), DARK)
				var staff := make_person(Color(0.2, 0.28, 0.45), 0)
				staff.position = Vector3(x, 0, -0.75)
				n.add_child(staff)
			blk(n, Vector3(-0.3, 0, -0.2), Vector3(0.3, 0.45, 0.5), DARK)
			blk(n, Vector3(-3, 0, -1.5), Vector3(3, 0.5, -1.15), DARK)
			blk(n, Vector3(-3, 0, -1.5), Vector3(3, 2.9, -1.38), Color(0.24, 0.34, 0.45))
			blk(n, Vector3(-2.2, 2.3, -1.38), Vector3(2.2, 2.6, -1.32), Color(0.95, 0.85, 0.4))
			var px := -2.8
			while px <= 2.85:
				cyl(n, Vector3(px, 0, 1.35), 0.05, 0.05, 0.95, STEEL, 5)
				px += 1.4
			blk(n, Vector3(-2.8, 0.85, 1.32), Vector3(2.8, 0.9, 1.38), Color(0.6, 0.15, 0.15))
		"gepaeckanlage":
			blk(n, Vector3(-4, 0, -3), Vector3(4, 0.15, 3), Color(0.55, 0.55, 0.52))
			for e: Array in [[Vector3(-3.5, 0.8, -2.5), Vector3(3.5, 1.1, -1.7)], [Vector3(-3.5, 0.8, 1.7), Vector3(3.5, 1.1, 2.5)],
					[Vector3(-3.5, 0.8, -2.5), Vector3(-2.7, 1.1, 2.5)], [Vector3(2.7, 0.8, -2.5), Vector3(3.5, 1.1, 2.5)]]:
				blk(n, e[0], e[1], DARK)
				blk(n, (e[0] as Vector3) + Vector3(0, 0.3, 0), (e[1] as Vector3) + Vector3(0, 0.12, 0), YELLOW)
			for p: Vector3 in [Vector3(-3.1, 0, -2.1), Vector3(3.1, 0, -2.1), Vector3(-3.1, 0, 2.1), Vector3(3.1, 0, 2.1)]:
				blk(n, p - Vector3(0.1, 0, 0.1), p + Vector3(0.1, 0.8, 0.1), STEEL)
			blk(n, Vector3(-1.5, 0, -1.0), Vector3(1.5, 2.4, 1.0), Color(0.62, 0.64, 0.62))
			blk(n, Vector3(-1.0, 0.8, 0.98), Vector3(1.0, 1.4, 1.04), DARK)
			var k := 0
			for p: Vector3 in [Vector3(-2.0, 1.1, -2.1), Vector3(0.5, 1.1, -2.1), Vector3(3.1, 1.1, 0.4), Vector3(1.2, 1.1, 2.1), Vector3(-1.8, 1.1, 2.1), Vector3(-3.1, 1.1, -0.8)]:
				blk(n, p - Vector3(0.35, 0, 0.25), p + Vector3(0.35, 0.3, 0.25), SHIRTS[k % SHIRTS.size()])
				k += 3
		"sicherheit":
			blk(n, Vector3(-3, 0, -4), Vector3(3, 0.06, 4), Color(0.25, 0.27, 0.3))
			for x: float in [-1.6, 1.6]:
				blk(n, Vector3(x + 0.1, 0, -2.6), Vector3(x + 1.1, 0.78, 3.2), STEEL)
				blk(n, Vector3(x + 0.15, 0.78, -2.6), Vector3(x + 1.05, 0.82, 3.2), DARK)
				blk(n, Vector3(x - 0.05, 0, -0.6), Vector3(x + 1.25, 1.7, 1.0), Color(0.7, 0.72, 0.72))
				blk(n, Vector3(x + 0.15, 0.82, 0.98), Vector3(x + 1.05, 1.3, 1.04), DARK)
				blk(n, Vector3(x - 1.05, 0, -0.2), Vector3(x - 0.9, 2.2, 0.2), WHITE)
				blk(n, Vector3(x - 0.3, 0, -0.2), Vector3(x - 0.15, 2.2, 0.2), WHITE)
				blk(n, Vector3(x - 1.05, 2.1, -0.2), Vector3(x - 0.15, 2.3, 0.2), WHITE)
				var officer := make_person(Color(0.15, 0.2, 0.3), 1)
				officer.position = Vector3(x - 0.6, 0, -1.4)
				n.add_child(officer)
				for i in range(3):
					blk(n, Vector3(x + 0.2, 0.82 + float(i) * 0.06, 2.6), Vector3(x + 1.0, 0.86 + float(i) * 0.06, 3.1), Color(0.5, 0.52, 0.55))
			blk(n, Vector3(-0.08, 0, -3.6), Vector3(0.08, 1.0, 3.6), STEEL)
		"gate":
			blk(n, Vector3(-5, 0, -4), Vector3(5, 0.06, 4), Color(0.30, 0.33, 0.42))
			blk(n, Vector3(-1.5, 0, -3.3), Vector3(1.5, 1.05, -2.5), WHITE)
			blk(n, Vector3(-1.55, 1.05, -3.35), Vector3(1.55, 1.12, -2.45), DARK)
			var agent := make_person(Color(0.24, 0.34, 0.45), 2)
			agent.position = Vector3(0, 0, -3.7)
			n.add_child(agent)
			blk(n, Vector3(2.4, 0, -4.0), Vector3(4.6, 2.7, -3.75), STEEL)
			blk(n, Vector3(2.6, 0, -3.9), Vector3(4.4, 2.5, -3.7), DARK)
			blk(n, Vector3(-4.7, 0, -3.6), Vector3(-4.5, 3.0, -3.4), STEEL)
			blk(n, Vector3(-4.95, 2.4, -3.62), Vector3(-3.2, 3.1, -3.44), Color(0.12, 0.15, 0.22))
			blk(n, Vector3(-4.8, 2.6, -3.44), Vector3(-3.4, 2.85, -3.4), YELLOW)
			for z: float in [-1.0, 0.6, 2.4]:
				var flip := 1.0 if z > 0.0 else -1.0
				blk(n, Vector3(-3.7, 0.42, z - 0.3), Vector3(3.7, 0.52, z + 0.3), SEAT)
				blk(n, Vector3(-3.7, 0.52, z + 0.2 * flip - 0.05), Vector3(3.7, 0.95, z + 0.2 * flip + 0.05), SEAT.darkened(0.15))
				for x: float in [-3.4, 0.0, 3.4]:
					blk(n, Vector3(x - 0.08, 0, z - 0.2), Vector3(x + 0.08, 0.42, z + 0.2), STEEL)
		"gepaeckband":
			blk(n, Vector3(-4.5, 0, -1.8), Vector3(4.5, 0.55, 1.8), STEEL)
			blk(n, Vector3(-4.3, 0.55, -1.6), Vector3(4.3, 0.6, 1.6), DARK)
			blk(n, Vector3(-3.6, 0, -0.75), Vector3(3.6, 0.85, 0.75), Color(0.62, 0.64, 0.64))
			var k := 1
			for p: Vector3 in [Vector3(-3.4, 0.6, 1.2), Vector3(-0.8, 0.6, 1.2), Vector3(2.4, 0.6, 1.2), Vector3(3.95, 0.6, 0.0),
					Vector3(1.2, 0.6, -1.2), Vector3(-2.2, 0.6, -1.2)]:
				blk(n, p - Vector3(0.35, 0, 0.22), p + Vector3(0.35, 0.32, 0.22), SHIRTS[k % SHIRTS.size()])
				k += 3
			blk(n, Vector3(4.6, 0, -0.15), Vector3(4.8, 2.2, 0.15), STEEL)
			blk(n, Vector3(4.5, 1.6, -0.7), Vector3(4.9, 2.3, 0.7), DARK)
			blk(n, Vector3(4.9, 1.9, -0.5), Vector3(4.93, 2.05, 0.5), YELLOW)
		"wc":
			var tile := Color(0.80, 0.84, 0.86)
			blk(n, Vector3(-3, 0, -2.5), Vector3(3, 0.07, 2.5), Color(0.86, 0.88, 0.89))
			blk(n, Vector3(-3, 0, -2.5), Vector3(3, 2.6, -2.35), tile)
			blk(n, Vector3(-3, 0, -2.5), Vector3(-2.85, 2.6, 2.5), tile)
			blk(n, Vector3(2.85, 0, -2.5), Vector3(3, 2.6, 2.5), tile)
			for seg: Vector2 in [Vector2(-3, -2.0), Vector2(-0.6, 0.6), Vector2(2.0, 3)]:
				blk(n, Vector3(seg.x, 0, 2.35), Vector3(seg.y, 2.6, 2.5), tile)
			blk(n, Vector3(-0.08, 0, -2.5), Vector3(0.08, 2.6, 2.35), tile)
			for side: float in [-1.0, 1.0]:
				for i in range(3):
					var x := side * (0.6 + float(i) * 0.75)
					blk(n, Vector3(x - 0.04, 0, -2.35), Vector3(x + 0.04, 2.0, -1.0), Color(0.55, 0.62, 0.68))
					blk(n, Vector3(x + side * 0.2 - 0.18, 0, -2.35), Vector3(x + side * 0.2 + 0.18, 0.45, -1.9), WHITE)
				blk(n, Vector3(side * 2.85 - 0.3 * side - 0.25, 0.8, -0.4), Vector3(side * 2.85 - 0.3 * side + 0.25, 0.95, 1.2), WHITE)
			blk(n, Vector3(-0.7, 2.62, 2.32), Vector3(0.7, 3.1, 2.52), Color(0.2, 0.4, 0.75))
			blk(n, Vector3(-0.08, 2.7, 2.52), Vector3(0.08, 3.0, 2.55), WHITE)
		"heizkoerper":
			blk(n, Vector3(-1, 0.15, -0.1), Vector3(1, 0.85, 0.1), WHITE)
			var x := -0.8
			while x < 0.85:
				blk(n, Vector3(x - 0.03, 0.18, 0.1), Vector3(x + 0.03, 0.82, 0.13), Color(0.75, 0.75, 0.73))
				x += 0.2
			blk(n, Vector3(-1.1, 0.1, -0.05), Vector3(-0.98, 0.25, 0.08), Color(0.75, 0.2, 0.15))
		"cafe":
			blk(n, Vector3(-4, 0, -3), Vector3(4, 0.06, 3), Color(0.55, 0.42, 0.29))
			blk(n, Vector3(-3.8, 0, -2.8), Vector3(3.8, 1.05, -1.9), Color(0.35, 0.24, 0.17))
			blk(n, Vector3(-3.85, 1.05, -2.85), Vector3(3.85, 1.12, -1.85), DARK)
			blk(n, Vector3(-3.0, 1.12, -2.7), Vector3(-2.2, 1.6, -2.2), STEEL)
			blk(n, Vector3(-1.8, 1.12, -2.6), Vector3(-0.4, 1.4, -2.0), Color(0.85, 0.75, 0.55))
			blk(n, Vector3(-3.8, 1.2, -3.0), Vector3(3.8, 2.6, -2.88), DARK)
			for i in range(3):
				blk(n, Vector3(-3.4 + float(i) * 2.5, 1.9, -2.88), Vector3(-1.8 + float(i) * 2.5, 2.3, -2.85), Color(0.9, 0.85, 0.7))
			blk(n, Vector3(-4, 2.6, -3.0), Vector3(4, 2.85, -2.5), Color(0.6, 0.25, 0.2))
			for t: Vector3 in [Vector3(-2.6, 0, 0.6), Vector3(0.2, 0, 1.6), Vector3(2.7, 0, 0.3)]:
				cyl(n, t, 0.06, 0.06, 0.72, DARK, 5)
				cyl(n, t + Vector3(0, 0.72, 0), 0.5, 0.5, 0.05, WHITE, 8)
				for side: float in [-1.0, 1.0]:
					blk(n, t + Vector3(side * 0.85 - 0.22, 0, -0.22), t + Vector3(side * 0.85 + 0.22, 0.45, 0.22), Color(0.6, 0.25, 0.2))
		"shop":
			blk(n, Vector3(-4, 0, -3), Vector3(4, 0.06, 3), Color(0.82, 0.80, 0.75))
			var k := 0
			for z: float in [-2.6, -0.6, 1.2]:
				blk(n, Vector3(-3.4, 0, z - 0.3), Vector3(1.8, 1.6, z + 0.3), WHITE)
				for y: float in [0.35, 0.75, 1.15]:
					for side: float in [-1.0, 1.0]:
						blk(n, Vector3(-3.3, y, z + side * 0.3 - 0.03), Vector3(1.7, y + 0.28, z + side * 0.3 + 0.03), SHIRTS[k % SHIRTS.size()])
						k += 1
			blk(n, Vector3(2.6, 0, 0.8), Vector3(3.8, 1.0, 2.6), DARK)
			blk(n, Vector3(-4, 2.4, -3), Vector3(4, 2.8, -2.8), Color(0.2, 0.5, 0.45))
		"sitzreihe":
			blk(n, Vector3(-2.5, 0.3, -0.1), Vector3(2.5, 0.38, 0.1), STEEL)
			for x: float in [-2.2, 2.2]:
				blk(n, Vector3(x - 0.06, 0, -0.3), Vector3(x + 0.06, 0.32, 0.3), STEEL)
			for i in range(5):
				var x := -2.0 + float(i)
				blk(n, Vector3(x - 0.42, 0.38, -0.3), Vector3(x + 0.42, 0.48, 0.3), SEAT)
				blk(n, Vector3(x - 0.42, 0.48, -0.42), Vector3(x + 0.42, 0.95, -0.32), SEAT.darkened(0.15))
		"pflanze":
			cyl(n, Vector3.ZERO, 0.42, 0.48, 0.65, WHITE, 8)
			ball(n, Vector3(0, 1.15, 0), 0.6, Color(0.24, 0.42, 0.2), 6)
			ball(n, Vector3(0.15, 1.65, -0.1), 0.38, Color(0.3, 0.5, 0.24), 6)
		"anzeige":
			for x: float in [-1.2, 1.2]:
				blk(n, Vector3(x - 0.06, 0, -0.06), Vector3(x + 0.06, 1.8, 0.06), STEEL)
			blk(n, Vector3(-1.5, 1.8, -0.2), Vector3(1.5, 3.4, 0.2), DARK)
			var lens := [2.4, 1.8, 2.2, 1.4, 2.0]
			for side: float in [-1.0, 1.0]:
				blk(n, Vector3(-1.35, 3.1, side * 0.2), Vector3(1.35, 3.25, side * 0.215), Color(0.94, 0.65, 0.2))
				for i in range(5):
					var y := 2.9 - float(i) * 0.2
					var l: float = lens[(i + (1 if side > 0 else 0)) % 5]
					blk(n, Vector3(-1.3, y, side * 0.2), Vector3(-1.3 + l, y + 0.09, side * 0.215), Color(0.95, 0.88, 0.5) if i % 2 == 0 else WHITE)
		"kunst":
			cyl(n, Vector3.ZERO, 1.4, 1.45, 0.4, Color(0.7, 0.68, 0.64), 10)
			var a := blk(n, Vector3(-0.3, 0.4, -0.3), Vector3(0.3, 2.6, 0.3), Color(0.75, 0.25, 0.18))
			a.rotation_degrees = Vector3(0, 0, 18)
			var b := blk(n, Vector3(-0.25, 0.4, -0.25), Vector3(0.25, 3.3, 0.25), Color(0.2, 0.4, 0.65))
			b.rotation_degrees = Vector3(-14, 30, 0)
			ball(n, Vector3(0.4, 2.9, 0.2), 0.45, YELLOW, 7)


## Passagier oder Personal, etwa 1,7 m groß. skin_i wählt die Hautfarbe.
static func make_person(shirt: Color, skin_i: int = -1) -> Node3D:
	var n := Node3D.new()
	var skin: Color = SKINS[(skin_i if skin_i >= 0 else randi()) % SKINS.size()]
	blk(n, Vector3(-0.17, 0, -0.1), Vector3(0.17, 0.82, 0.1), Color(0.18, 0.18, 0.22))
	blk(n, Vector3(-0.22, 0.82, -0.13), Vector3(0.22, 1.42, 0.13), shirt)
	ball(n, Vector3(0, 1.58, 0), 0.15, skin, 5)
	return n
