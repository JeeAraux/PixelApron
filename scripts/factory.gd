extends RefCounted
## Baut die sichtbaren Formen: Wege-Bänder, Gebäude, Deko und Fahrzeuge
## aus einfachen Grundkörpern (Low-Poly, später durch Blender-Modelle ersetzbar).

const Catalog = preload("res://scripts/catalog.gd")
const Spline = preload("res://scripts/spline.gd")
const LINE_SHADER = preload("res://shaders/line.gdshader")
const Models = preload("res://scripts/models.gd")
const Kit = preload("res://scripts/mesh_kit.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")

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
const YELLOW_SIGN := Color(0.95, 0.78, 0.15)
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
	if kind == "piste":
		var nums := runway_numbers(samples)
		sm.set_shader_parameter("num_a", nums[0])
		sm.set_shader_parameter("num_b", nums[1])
	mi.material_override = sm
	# Schultern neben Rollweg und Piste (liegen unter allen anderen Belägen)
	if kind == "rollweg" or kind == "piste":
		var sh := 3.5 if kind == "rollweg" else 7.5
		var smi := MeshInstance3D.new()
		smi.name = "Schulter"
		smi.mesh = Spline.ribbon(samples, w + sh * 2.0, 0.018 if kind == "rollweg" else 0.016)
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shm := ShaderMaterial.new()
		shm.shader = LINE_SHADER
		shm.set_shader_parameter("base_color", Color(0.34, 0.34, 0.31))
		shm.set_shader_parameter("mark", 8)
		shm.set_shader_parameter("width", w + sh * 2.0)
		shm.set_shader_parameter("len", Spline.length(samples))
		smi.material_override = shm
		mi.add_child(smi)
	return mi


## Pistenkennzahlen (missweisender Kurs / 10) für beide Enden; Norden = -Z.
static func runway_numbers(s: PackedVector3Array) -> Array:
	var d := s[s.size() - 1] - s[0]
	var bearing := fposmod(rad_to_deg(atan2(d.x, -d.z)), 360.0)
	var a := roundi(bearing / 10.0)
	if a <= 0:
		a = 36
	if a > 36:
		a -= 36
	var b := a + 18
	if b > 36:
		b -= 36
	return [a, b]


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
		for gx in range(3):
			blk(roof, Vector3(ux - 1.6 + float(gx) * 1.2, 10.9, uz - 1.2), Vector3(ux - 0.8 + float(gx) * 1.2, 11.0, uz + 1.2), Color(0.3, 0.32, 0.33))
	# Attika und Schriftzug TERMINAL über der Landseite
	blk(roof, Vector3(-hw - 0.4, 9.6, hd + 0.1), Vector3(hw + 0.4, 10.1, hd + 0.4), WALL)
	blk(roof, Vector3(-hw - 0.4, 9.6, -hd - 0.4), Vector3(hw + 0.4, 10.1, -hd - 0.1), WALL)
	if w >= 30.0:
		_letters(high, "TERMINAL", Vector3(0, 7.55, hd + 0.02), 0.27, Color(0.16, 0.25, 0.45))
	bake(n)
	return n


const FONT := {
	"T": ["111", "010", "010", "010", "010"], "E": ["111", "100", "110", "100", "111"],
	"R": ["110", "101", "110", "101", "101"], "M": ["10001", "11011", "10101", "10001", "10001"],
	"I": ["1", "1", "1", "1", "1"], "N": ["1001", "1101", "1011", "1001", "1001"],
	"A": ["010", "101", "111", "101", "101"], "L": ["100", "100", "100", "100", "111"],
	"P": ["110", "101", "110", "100", "100"], "O": ["111", "101", "101", "101", "111"],
	"W": ["10001", "10001", "10101", "11011", "10001"], "F": ["111", "100", "110", "100", "100"],
	"H": ["101", "101", "111", "101", "101"], "G": ["111", "100", "101", "101", "111"],
	"U": ["101", "101", "101", "101", "111"], "C": ["111", "100", "100", "100", "111"],
}


## Klötzchenschrift an einer Fassade (zeigt nach +z), Mitte bei c.
static func _letters(parent: Node3D, text: String, c: Vector3, px: float, col: Color, facing: float = 1.0) -> void:
	var widths := []
	var total := 0.0
	for ch in text:
		var rows: Array = FONT.get(ch, ["1"])
		widths.append(String(rows[0]).length())
		total += float(String(rows[0]).length() + 1) * px
	var x := c.x - total * 0.5
	for i in range(text.length()):
		var rows: Array = FONT.get(text[i], ["1"])
		for r in range(rows.size()):
			var row: String = rows[r]
			for k in range(row.length()):
				if row[k] == "1":
					var y := c.y + float(rows.size() - 1 - r) * px
					var xa := x + float(k) * px
					var xb := xa + px
					if facing < 0.0:
						xa = 2.0 * c.x - xa
						xb = 2.0 * c.x - xb
					blk(parent, Vector3(xa, y, c.z), Vector3(xb, y + px, c.z + 0.12 * facing), col)
		x += float(int(widths[i]) + 1) * px


## Fasst alle einfarbigen Teile eines Modells zu einem Mesh zusammen (ein Draw-Call).
## Benannte Gruppen (Dach, Schranken ...) bleiben eigene Knoten, Glas und Leuchtteile bleiben einzeln.
static func bake(root: Node3D) -> void:
	var kit := Kit.new()
	var merged := []
	for c in root.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var m := mi.material_override as StandardMaterial3D
			if m == null or mi.mesh == null or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.emission_enabled:
				continue
			_bake_mesh(kit, mi.mesh, mi.transform, m.albedo_color)
			merged.append(mi)
		elif c is Node3D and (c as Node).get_child_count() > 0 and not (c as Node).has_meta("no_bake"):
			bake(c as Node3D)
	if merged.size() < 2:
		return
	for mi: MeshInstance3D in merged:
		root.remove_child(mi)
		mi.free()
	var out := kit.instance("Gebacken")
	root.add_child(out)
	out.owner = null


static func _bake_mesh(kit: Kit, mesh: Mesh, xf: Transform3D, col: Color) -> void:
	for si in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for i in range(verts.size()):
				idx.append(i)
		for t in range(0, idx.size() - 2, 3):
			var a := xf * verts[idx[t]]
			var b := xf * verts[idx[t + 1]]
			var c := xf * verts[idx[t + 2]]
			var n := (xf.basis * norms[idx[t]]).normalized() if norms.size() > 0 else Vector3.UP
			kit.tri_raw(a, b, c, n, col)


static func make_item(id: String) -> Node3D:
	if id == "halle":
		return make_hall(24.0, 16.0)
	var n := _make_item_raw(id)
	bake(n)
	return n


static func _make_item_raw(id: String) -> Node3D:
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
			_stand(n, false)
		"stand_aussen":
			_stand(n, true)
		"bushalt":
			_bus_stop(n)
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
	var clad := Color(0.62, 0.66, 0.68)
	blk(n, Vector3(-22, 0, -18), Vector3(22, 12, 18), clad)
	# Tonnendach in Stufen (Achse quer zum Tor)
	for i in range(6):
		var t := float(i) / 6.0
		var hz := 18.3 * sqrt(1.0 - t * t)
		blk(n, Vector3(-22.3, 12.0 + float(i) * 0.45, -hz), Vector3(22.3, 12.45 + float(i) * 0.45, hz),
			Color(0.44, 0.47, 0.49).lightened(float(i) * 0.02))
	# Faltschiebetor mit Paneelen, Fensterreihe und Toranzeige
	blk(n, Vector3(-20, 0, -18.25), Vector3(20, 11.2, -17.95), Color(0.40, 0.44, 0.47))
	for x in range(-19, 20, 2):
		blk(n, Vector3(float(x) - 0.06, 0, -18.4), Vector3(float(x) + 0.06, 11.2, -18.2), Color(0.30, 0.33, 0.36))
	blk(n, Vector3(-20, 8.0, -18.42), Vector3(20, 9.0, -18.3), GLASS)
	blk(n, Vector3(-20.6, 0, -18.6), Vector3(-20.0, 11.6, -17.8), Color(0.75, 0.62, 0.15))
	blk(n, Vector3(20.0, 0, -18.6), Vector3(20.6, 11.6, -17.8), Color(0.75, 0.62, 0.15))
	blk(n, Vector3(-20.6, 11.2, -18.6), Vector3(20.6, 11.8, -17.8), Color(0.75, 0.62, 0.15))
	# Seitenfenster, Nebengebäude mit Werkstatt, Rolltor
	for side: float in [-1.0, 1.0]:
		blk(n, Vector3(side * 22.05 - 0.05, 7.5, -14), Vector3(side * 22.05 + 0.05, 9.5, 14), GLASS)
	blk(n, Vector3(-22, 0, 18), Vector3(-6, 6.5, 24), Color(0.78, 0.76, 0.7))
	blk(n, Vector3(-22.2, 6.5, 17.8), Vector3(-5.8, 6.9, 24.2), ROOF)
	for x in range(-20, -7, 3):
		blk(n, Vector3(float(x), 2.5, 24.0), Vector3(float(x) + 1.8, 4.5, 24.1), GLASS)
	blk(n, Vector3(4, 0, 17.95), Vector3(10, 4.5, 18.15), STEEL)
	_letters(n, "HANGAR", Vector3(0, 9.4, -18.45), 0.42, Color(0.92, 0.92, 0.9), -1.0)


static func _tower(n: Node3D) -> void:
	# Sockelbau mit Fensterbändern und Eingang
	blk(n, Vector3(-6, 0, -6), Vector3(6, 5, 6), WALL)
	for y: float in [1.2, 3.2]:
		blk(n, Vector3(-6.05, y, -5), Vector3(6.05, y + 1.1, 5), GLASS)
	blk(n, Vector3(-1.2, 0, 5.95), Vector3(1.2, 2.4, 6.1), GLASS)
	blk(n, Vector3(-6.3, 5, -6.3), Vector3(6.3, 5.5, 6.3), ROOF)
	# Schaft mit Treppenhausfenstern
	cyl(n, Vector3(0, 5.5, 0), 2.4, 2.2, 23.0, Color(0.84, 0.82, 0.76), 12)
	for i in range(9):
		blk(n, Vector3(-0.35, 7.0 + float(i) * 2.4, 2.2), Vector3(0.35, 7.9 + float(i) * 2.4, 2.45), GLASS)
	blk(n, Vector3(-2.6, 18.0, -2.6), Vector3(2.6, 18.3, 2.6), ROOF)
	# Kanzel: Unterbau, Galerie mit Geländer, schräg gestellte Scheiben mit Pfosten, Dach
	cyl(n, Vector3(0, 28.5, 0), 3.4, 4.8, 1.0, ROOF, 12)
	cyl(n, Vector3(0, 29.5, 0), 5.3, 5.3, 0.15, ROOF, 12)
	for i in range(24):
		var a := TAU * float(i) / 24.0
		var p := Vector3(cos(a), 0, sin(a)) * 5.15
		blk(n, p + Vector3(-0.04, 29.65, -0.04), p + Vector3(0.04, 30.6, 0.04), STEEL)
	cyl(n, Vector3(0, 30.55, 0), 5.2, 5.2, 0.06, STEEL, 24)
	cyl(n, Vector3(0, 29.6, 0), 4.3, 4.7, 3.6, GLASS, 12)
	for i in range(12):
		var a := TAU * float(i) / 12.0
		var p := Vector3(cos(a), 0, sin(a)) * 4.55
		blk(n, p + Vector3(-0.08, 29.6, -0.08), p + Vector3(0.08, 33.2, 0.08), Color(0.35, 0.37, 0.4))
	cyl(n, Vector3(0, 33.2, 0), 5.2, 4.4, 0.9, ROOF, 12)
	cyl(n, Vector3(0, 34.1, 0), 2.0, 1.6, 0.6, Color(0.6, 0.6, 0.58), 10)
	# Antennen und Radarkuppel
	blk(n, Vector3(-0.12, 34.7, -0.12), Vector3(0.12, 40.0, 0.12), DARK)
	blk(n, Vector3(-0.8, 38.6, -0.04), Vector3(0.8, 38.7, 0.04), DARK)
	blk(n, Vector3(1.0, 34.7, -0.06), Vector3(1.12, 37.0, 0.06), DARK)
	ball(n, Vector3(-1.1, 35.4, 0.5), 0.75, Color(0.92, 0.92, 0.9), 8)
	blk(n, Vector3(-0.1, 39.9, -0.1), Vector3(0.1, 40.2, 0.1), Color(0.9, 0.15, 0.1))


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
	# Ein- und Ausfahrt an der Vorderseite (-z): Zufahrt, Kassenhäuschen, Schranken, Schilder
	blk(n, Vector3(-11, 0.0, -31), Vector3(11, 0.05, -22), Color(0.25, 0.245, 0.23))
	blk(n, Vector3(-0.15, 0.05, -30), Vector3(0.15, 0.06, -22), Color(0.86, 0.85, 0.8))
	blk(n, Vector3(-1.2, 0, -23.6), Vector3(1.2, 0.25, -21.0), CONCRETE)
	blk(n, Vector3(-0.9, 0.25, -23.3), Vector3(0.9, 2.5, -21.4), Color(0.85, 0.84, 0.8))
	blk(n, Vector3(-0.92, 1.2, -23.32), Vector3(0.92, 2.1, -21.38), GLASS)
	blk(n, Vector3(-1.1, 2.5, -23.5), Vector3(1.1, 2.7, -21.2), ROOF)
	for gate: Array in [["SchrankeEin", -9.2], ["SchrankeAus", 2.8]]:
		var x0: float = gate[1]
		blk(n, Vector3(x0 - 0.3, 0, -22.9), Vector3(x0 + 0.3, 1.1, -22.3), Color(0.85, 0.7, 0.15))
		var pivot := Node3D.new()
		pivot.name = gate[0]
		pivot.position = Vector3(x0, 1.0, -22.6)
		n.add_child(pivot)
		for k in range(6):
			blk(pivot, Vector3(0.2 + float(k) * 0.95, -0.06, -0.06), Vector3(0.2 + float(k + 1) * 0.95, 0.06, 0.06),
				Color(0.9, 0.15, 0.12) if k % 2 == 0 else Color(0.95, 0.95, 0.92))
	for arrow: Array in [[-6.0, 1.0], [6.0, -1.0]]:
		var ax: float = arrow[0]
		var dirz: float = arrow[1]
		blk(n, Vector3(ax - 0.15, 0.05, -28.5), Vector3(ax + 0.15, 0.06, -25.5), Color(0.86, 0.85, 0.8))
		blk(n, Vector3(ax - 0.6, 0.05, -27.0 + dirz * 1.6), Vector3(ax + 0.6, 0.06, -26.6 + dirz * 1.6), Color(0.86, 0.85, 0.8))
	blk(n, Vector3(-12.2, 0, -24.2), Vector3(-12.0, 4.2, -24.0), STEEL)
	blk(n, Vector3(-12.9, 3.0, -24.3), Vector3(-11.3, 4.6, -24.18), Color(0.12, 0.3, 0.62))
	blk(n, Vector3(-12.5, 3.3, -24.32), Vector3(-12.2, 4.3, -24.3), Color(0.95, 0.95, 0.95))
	blk(n, Vector3(-12.5, 4.0, -24.32), Vector3(-11.7, 4.3, -24.3), Color(0.95, 0.95, 0.95))
	blk(n, Vector3(-11.9, 3.6, -24.32), Vector3(-11.7, 4.3, -24.3), Color(0.95, 0.95, 0.95))
	blk(n, Vector3(-12.5, 3.6, -24.32), Vector3(-11.7, 3.85, -24.3), Color(0.95, 0.95, 0.95))
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
	# drei Fahrzeughallentore mit Fensterreihe, das mittlere offen
	for i in range(3):
		var x := -9.0 + float(i) * 9.0
		blk(n, Vector3(x - 3.6, 0, 10.0), Vector3(x + 3.6, 5.6, 10.1), Color(0.85, 0.84, 0.8))
		if i == 1:
			blk(n, Vector3(x - 3.3, 0, 10.05), Vector3(x + 3.3, 5.3, 10.2), Color(0.1, 0.1, 0.11))
		else:
			blk(n, Vector3(x - 3.3, 0, 10.05), Vector3(x + 3.3, 5.3, 10.2), Color(0.72, 0.16, 0.12))
			for y: float in [1.3, 2.6, 3.9]:
				blk(n, Vector3(x - 3.3, y, 10.2), Vector3(x + 3.3, y + 0.06, 10.25), Color(0.55, 0.12, 0.1))
			blk(n, Vector3(x - 3.0, 4.2, 10.2), Vector3(x + 3.0, 4.9, 10.26), GLASS)
	blk(n, Vector3(-15.05, 4.5, -8), Vector3(15.05, 6.0, -6), GLASS)
	# Schlauchturm mit Fenstern, Sirene, Blaulicht
	blk(n, Vector3(11, 0, -10), Vector3(15, 13.5, -6), BRICK)
	blk(n, Vector3(10.8, 13.5, -10.2), Vector3(15.2, 14.0, -5.8), ROOF)
	for y: float in [3.0, 6.5, 10.0]:
		blk(n, Vector3(12.3, y, -5.95), Vector3(13.7, y + 1.4, -5.85), GLASS)
	blk(n, Vector3(12.6, 14.0, -8.4), Vector3(13.4, 14.6, -7.6), DARK)
	blk(n, Vector3(-13, 7.6, 6.5), Vector3(-11, 8.2, 8.5), Color(0.2, 0.35, 0.9))
	_letters(n, "FEUERWEHR", Vector3(0, 6.0, 10.12), 0.18, Color(0.95, 0.95, 0.92))
	# Flugfeldlöschfahrzeuge vor der Halle
	for i in range(2):
		var t := _fire_truck()
		t.position = Vector3(-9.0 + float(i) * 18.0, 0, 16.5)
		t.rotation.y = PI
		n.add_child(t)


## Großes Flugfeldlöschfahrzeug (8x8, Wasserwerfer auf dem Dach)
static func _fire_truck() -> Node3D:
	var t := Node3D.new()
	var red := Color(0.82, 0.14, 0.1)
	var k := Kit.new()
	k.box(Vector3(-1.4, 0.7, -5.5), Vector3(1.4, 3.3, 5.5), red)
	k.box(Vector3(-1.42, 2.2, -5.5), Vector3(1.42, 3.0, -3.6), Models.GLASS)
	k.box(Vector3(-1.45, 1.4, -5.5), Vector3(1.45, 1.6, 5.5), Color(0.95, 0.85, 0.15))
	k.box(Vector3(-0.6, 3.3, -3.0), Vector3(0.6, 3.7, -2.0), Color(0.2, 0.2, 0.22))
	k.cyl(Vector3(0, 3.7, -2.5), Vector3(0, 3.8, -5.0), 0.15, 0.1, Color(0.5, 0.5, 0.52), 8)
	k.box(Vector3(-0.5, 3.3, -5.0), Vector3(0.5, 3.45, -4.6), Color(0.2, 0.35, 0.95))
	for z: float in [-3.8, -1.6, 1.8, 4.0]:
		for sx: float in [-1.0, 1.0]:
			k.cyl(Vector3(sx * 1.05, 0.65, z), Vector3(sx * 1.5, 0.65, z), 0.65, 0.65, Models.TYRE, 12, true, Models.METAL)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	t.add_child(mi)
	return t


static func _trafo(n: Node3D) -> void:
	# Betonhaus mit Lüftungsgittern, daneben zwei Transformatoren mit Kühlrippen, Zaun
	blk(n, Vector3(-5, 0, -3.5), Vector3(0.5, 3.4, 3.5), CONCRETE)
	blk(n, Vector3(-5.2, 3.4, -3.7), Vector3(0.7, 3.7, 3.7), ROOF)
	for x: float in [-4.2, -2.0]:
		blk(n, Vector3(x, 0, 3.5), Vector3(x + 1.6, 2.4, 3.62), STEEL)
		for y: float in [0.4, 0.8, 1.2, 1.6, 2.0]:
			blk(n, Vector3(x + 0.1, y, 3.62), Vector3(x + 1.5, y + 0.08, 3.66), DARK)
	blk(n, Vector3(-0.8, 2.6, 3.5), Vector3(-0.2, 3.1, 3.64), Color(0.82, 0.68, 0.2))
	for z: float in [-1.8, 1.8]:
		blk(n, Vector3(1.4, 0, z - 1.2), Vector3(3.8, 0.3, z + 1.2), CONCRETE)
		blk(n, Vector3(1.8, 0.3, z - 0.9), Vector3(3.4, 2.2, z + 0.9), Color(0.42, 0.48, 0.45))
		for i in range(6):
			var fz := z - 0.8 + float(i) * 0.32
			blk(n, Vector3(1.6, 0.4, fz), Vector3(3.6, 2.0, fz + 0.06), Color(0.36, 0.42, 0.39))
		for ix: float in [2.1, 2.6, 3.1]:
			cyl(n, Vector3(ix, 2.2, z), 0.08, 0.06, 0.7, Color(0.75, 0.55, 0.4), 6)
	for pr: Array in [[Vector3(-5.3, 0, -3.9), Vector3(4.6, 0, -3.9)], [Vector3(4.6, 0, -3.9), Vector3(4.6, 0, 3.9)], [Vector3(0.7, 0, 3.9), Vector3(4.6, 0, 3.9)]]:
		var a: Vector3 = pr[0]
		var b: Vector3 = pr[1]
		var lo := Vector3(minf(a.x, b.x) - 0.03, 1.8, minf(a.z, b.z) - 0.03)
		var hi := Vector3(maxf(a.x, b.x) + 0.03, 1.85, maxf(a.z, b.z) + 0.03)
		blk(n, lo, hi, STEEL)
		blk(n, Vector3(lo.x, 0.1, lo.z), Vector3(hi.x, 0.15, hi.z), STEEL)
		var steps := int(a.distance_to(b) / 1.2)
		for i in range(steps + 1):
			var q := a.lerp(b, float(i) / float(maxi(steps, 1)))
			blk(n, q + Vector3(-0.03, 0, -0.03), q + Vector3(0.03, 1.85, 0.03), STEEL)


static func _heizzentrale(n: Node3D) -> void:
	blk(n, Vector3(-11, 0, -7.5), Vector3(11, 7.5, 7.5), BRICK)
	blk(n, Vector3(-11.2, 7.5, -7.7), Vector3(11.2, 7.9, 7.7), ROOF)
	for x: float in [-6.0, 1.0]:
		blk(n, Vector3(x, 0, 7.5), Vector3(x + 4.0, 4.2, 7.65), STEEL)
	for x in range(-9, 10, 3):
		blk(n, Vector3(x, 4.8, 7.5), Vector3(x + 1.4, 6.4, 7.6), GLASS)
	# Schornstein mit Steigleiter und Ringen, Lüfter auf dem Dach, Rohrleitungen
	cyl(n, Vector3(8, 7.9, -4), 0.9, 0.8, 15.0, STEEL, 10)
	for y: float in [12.0, 17.0, 21.5]:
		cyl(n, Vector3(8, y, -4), 0.95, 0.95, 0.25, DARK, 10)
	blk(n, Vector3(8.85, 8.0, -4.2), Vector3(8.95, 22.5, -3.8), DARK)
	for x: float in [-6.0, -2.0, 2.0]:
		cyl(n, Vector3(x, 7.9, 0), 0.9, 0.9, 0.9, Color(0.5, 0.52, 0.54), 10)
		blk(n, Vector3(x - 0.7, 8.8, -0.05), Vector3(x + 0.7, 8.85, 0.05), DARK)
	for z: float in [3.0, 4.2]:
		blk(n, Vector3(-11.1, 2.75, z - 0.25), Vector3(-11.0, 3.25, z + 0.25), DARK)
		blk(n, Vector3(-11.5, 2.8, z - 0.2), Vector3(-11.0, 3.2, z + 0.2), Color(0.85, 0.35, 0.2) if z < 4.0 else Color(0.25, 0.45, 0.75))


static func _baum(n: Node3D) -> void:
	var green := Color.from_hsv(randf_range(0.22, 0.3), randf_range(0.45, 0.6), randf_range(0.26, 0.36))
	cyl(n, Vector3.ZERO, 0.38, 0.3, 3.2, Color(0.25, 0.19, 0.13), 6)
	ball(n, Vector3(0, 5.2, 0), 2.6, green, 7)
	for i in range(2):
		var off := Vector3(randf_range(-1.3, 1.3), randf_range(5.4, 6.4), randf_range(-1.3, 1.3))
		ball(n, off, 1.8, green.lightened(0.06 * float(i)), 6)


## Standmarkierung nach ICAO (Nase zeigt nach +Z): gelbe Mittellinie, Haltebalken je Muster mit
## Beschriftung, rote Sicherheitslinien (Flügelspitzen und Geräte-Sperrfläche), weiße Geräteabstellflächen,
## Unterflur-Betankung und Bodenstrom, Andockanzeige vorn. Außenposition: Busparkfläche und Fußwege.
## Einrolllinien und Standnummer zeichnet airfield.gd, weil sie vom Rollweg dahinter abhängen.
static func _stand(n: Node3D, remote: bool) -> void:
	var k := Kit.new()
	var yellow := Color(0.88, 0.70, 0.18)
	var red := Color(0.72, 0.18, 0.13)
	var white := Color(0.88, 0.88, 0.85)
	var y := 0.05
	var flat := func(a: Vector2, b: Vector2, c: Color) -> void:
		k.box(Vector3(minf(a.x, b.x), 0.0, minf(a.y, b.y)), Vector3(maxf(a.x, b.x), y, maxf(a.y, b.y)), c)
	# Mittellinie bis hinter die Haltebalken
	flat.call(Vector2(-0.18, -23.0), Vector2(0.18, 13.9), yellow)
	# Haltebalken: A320 (Bugrad 12,1 m), B737-800 (12,85 m), beschriftet links vom Piloten aus gesehen
	for e: Array in [[12.1, "A320"], [12.85, "B738"]]:
		var z: float = e[0]
		flat.call(Vector2(-1.6, z - 0.15), Vector2(1.6, z + 0.15), yellow)
		PixelFont.draw_ground(k, String(e[1]), Vector3(4.6, y + 0.01, z), Vector3(0, 0, 1), 0.16, yellow)
	# Sicherheitslinien: Standgrenzen (rot), Kopf des Stands
	for side: float in [-1.0, 1.0]:
		flat.call(Vector2(side * 20.0 - 0.15, -23.0), Vector2(side * 20.0 + 0.15, 23.0), red)
	flat.call(Vector2(-20.0, 22.7), Vector2(20.0, 23.0), red)
	# Geräte-Sperrfläche um die Nase: rote Umrandung mit Schraffur
	for x0: float in [-3.5, 3.0]:
		flat.call(Vector2(x0, 13.6), Vector2(x0 + 0.5, 20.0), red)
	flat.call(Vector2(-3.5, 19.6), Vector2(3.5, 20.0), red)
	for i in range(5):
		var z := 15.3 + float(i) * 1.0
		k.box(Vector3(-3.0, 0.0, -0.1), Vector3(3.0, y, 0.1), red, Transform3D(Basis(Vector3.UP, 0.45), Vector3(0, 0, z)))
	# Geräteabstellflächen (weiß) an den vorderen Ecken, mit "GSE" beschriftet
	for side: float in [-1.0, 1.0]:
		var x0 := side * 13.0
		var x1 := side * 19.2
		for zz: Array in [[16.0, 22.2]]:
			flat.call(Vector2(x0, zz[0]), Vector2(x1, float(zz[0]) + 0.2), white)
			flat.call(Vector2(x0, float(zz[1]) - 0.2), Vector2(x1, zz[1]), white)
			flat.call(Vector2(x0, zz[0]), Vector2(x0 + side * 0.2, zz[1]), white)
			flat.call(Vector2(x1 - side * 0.2, zz[0]), Vector2(x1, zz[1]), white)
		PixelFont.draw_ground(k, "GSE", Vector3((x0 + x1) * 0.5, y + 0.01, 19.1), Vector3(0, 0, -1), 0.3, white)
	# Unterflur-Betankung an beiden Flügeln, Bodenstrom an der Nase
	for side: float in [-1.0, 1.0]:
		k.cyl(Vector3(side * 7.5, 0.0, -2.5), Vector3(side * 7.5, y + 0.02, -2.5), 0.55, 0.55, yellow, 12)
		k.cyl(Vector3(side * 7.5, 0.0, -2.5), Vector3(side * 7.5, y + 0.04, -2.5), 0.35, 0.35, Color(0.2, 0.2, 0.21), 12)
	k.box(Vector3(1.6, 0.0, 9.0), Vector3(2.4, y + 0.03, 9.8), Color(0.25, 0.26, 0.28))
	# Andockanzeige (VDGS) auf einem Mast am Kopf des Stands
	k.box(Vector3(-0.15, 0.0, 22.3), Vector3(0.15, 4.6, 22.6), Color(0.36, 0.41, 0.44))
	k.box(Vector3(-0.9, 4.6, 22.0), Vector3(0.9, 6.4, 22.7), Color(0.12, 0.12, 0.13))
	k.box(Vector3(-0.7, 4.8, 21.95), Vector3(0.7, 6.2, 22.0), Color(0.05, 0.05, 0.06))
	if remote:
		# Busparkfläche links vom Flugzeug (Seite der Türen L1/L2) vor dem Flügel, Fußweg zur hinteren Treppe
		var bx0 := 8.7
		var bx1 := 12.3
		for zz: float in [5.0, 19.4]:
			flat.call(Vector2(bx0, zz), Vector2(bx1, zz + 0.2), white)
		for xx: float in [bx0, bx1 - 0.2]:
			var z := 5.0
			while z < 19.4:
				flat.call(Vector2(xx, z), Vector2(xx + 0.2, minf(z + 1.0, 19.6)), white)
				z += 2.0
		PixelFont.draw_ground(k, "BUS", Vector3((bx0 + bx1) * 0.5, y + 0.01, 12.2), Vector3(0, 0, -1), 0.3, white)
		var wz := -13.0
		while wz < 4.4:
			flat.call(Vector2(8.6, wz), Vector2(11.4, wz + 0.5), white)
			wz += 1.0
		# Treppenposition: gelbe Winkel an den Türen
		for dz: float in [13.4, -14.5]:
			flat.call(Vector2(2.4, dz - 1.0), Vector2(2.6, dz + 1.0), yellow)
			flat.call(Vector2(2.4, dz - 1.0), Vector2(3.4, dz - 0.8), yellow)
	n.add_child(k.instance("Markierung"))


## Vorfeld-Haltestelle: Haltebucht mit Bordstein, Wartedach mit Glaswänden, Haltestellenschild.
static func _bus_stop(n: Node3D) -> void:
	var k := Kit.new()
	var white := Color(0.88, 0.88, 0.85)
	var y := 0.05
	# Haltebucht markiert (zwei Busse hintereinander), Zickzacklinie
	k.box(Vector3(-14.0, 0.0, -2.2), Vector3(14.0, y, -2.0), white)
	k.box(Vector3(-14.0, 0.0, 2.0), Vector3(14.0, y, 2.2), Color(0.88, 0.70, 0.18))
	var x := -13.0
	var flip := 1.0
	while x < 13.0:
		k.box(Vector3(-0.62, 0.0, -0.08), Vector3(0.62, y, 0.08), Color(0.88, 0.70, 0.18), Transform3D(Basis(Vector3.UP, 0.5 * flip), Vector3(x + 0.5, 0, 1.5)))
		x += 1.0
		flip = -flip
	PixelFont.draw_ground(k, "BUS", Vector3(-6.5, y + 0.01, 0.0), Vector3(-1, 0, 0), 0.45, white)
	PixelFont.draw_ground(k, "BUS", Vector3(6.5, y + 0.01, 0.0), Vector3(-1, 0, 0), 0.45, white)
	# Bordstein und Wartefläche
	k.box(Vector3(-14.0, 0.0, 2.2), Vector3(14.0, 0.2, 3.5), Color(0.62, 0.61, 0.57))
	# Wartedach auf Stützen, Rückwand aus Glas
	for sx in range(-12, 13, 6):
		k.box(Vector3(float(sx) - 0.1, 0.2, 3.2), Vector3(float(sx) + 0.1, 3.0, 3.4), Color(0.36, 0.41, 0.44))
	k.box(Vector3(-12.6, 3.0, 2.4), Vector3(12.6, 3.25, 3.6), Color(0.85, 0.85, 0.83))
	k.box(Vector3(-12.4, 0.4, 3.35), Vector3(12.4, 2.7, 3.42), Color(0.55, 0.72, 0.8))
	for sx: float in [-6.0, 6.0]:
		k.box(Vector3(sx - 1.5, 0.2, 2.9), Vector3(sx + 1.5, 0.65, 3.3), Color(0.42, 0.31, 0.21))
	# Haltestellenschild
	k.box(Vector3(13.3, 0.2, 2.7), Vector3(13.45, 3.2, 2.85), Color(0.36, 0.41, 0.44))
	k.box(Vector3(13.0, 2.4, 2.65), Vector3(13.8, 3.3, 2.9), Color(0.16, 0.42, 0.25))
	PixelFont.draw(k, "BUS", Vector3(13.4, 2.85, 2.64), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.1, white)
	n.add_child(k.instance("Haltestelle"))


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
	var mi := MeshInstance3D.new()
	mi.mesh = Models.gse_mesh(kind)
	n.add_child(mi)
	return n


## Auto in zufälliger Bauart (Kleinwagen, Limousine, Kombi, SUV, Transporter, Taxi).
static func make_car(c: Color, kind: String = "") -> Node3D:
	if kind == "":
		var r := randf()
		kind = "kompakt" if r < 0.25 else "limousine" if r < 0.45 else "kombi" if r < 0.65 else "suv" if r < 0.82 else "transporter" if r < 0.93 else "taxi"
	var n := Node3D.new()
	n.set_meta("kind", kind)
	var mi := MeshInstance3D.new()
	mi.mesh = Models.car_mesh(kind, c)
	n.add_child(mi)
	# Bremslichter und Blinker als eigene leuchtende Teile, die der Verkehr ein- und ausschaltet
	var d: Array = Models.CAR_DIMS[kind]
	var hl: float = float(d[0]) * 0.5
	var hw: float = float(d[1]) * 0.5
	var belt := 0.92 if kind != "transporter" else 1.05
	var brake := Node3D.new()
	brake.name = "Bremslicht"
	brake.visible = false
	n.add_child(brake)
	for sx: float in [-1.0, 1.0]:
		_glow(brake, Vector3(sx * (hw - 0.24), belt - 0.16, hl + 0.04), Vector3(0.3, 0.14, 0.04), Color(1.0, 0.1, 0.05))
	for side: Array in [["BlinkerL", -1.0], ["BlinkerR", 1.0]]:
		var b := Node3D.new()
		b.name = side[0]
		b.visible = false
		n.add_child(b)
		var sx: float = side[1]
		_glow(b, Vector3(sx * (hw - 0.05), belt - 0.15, -hl - 0.03), Vector3(0.12, 0.1, 0.05), Color(1.0, 0.6, 0.05))
		_glow(b, Vector3(sx * (hw - 0.05), belt - 0.15, hl + 0.05), Vector3(0.12, 0.1, 0.05), Color(1.0, 0.6, 0.05))
	return n


static func _glow(parent: Node3D, pos: Vector3, size: Vector3, c: Color) -> void:
	var key := "glow_" + c.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.5
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats[key] = m
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## Flugzeug aus Rumpf-Mesh plus beweglichen Teilen: Fahrwerk, zwei Fans, Blinklichter.
static func make_plane(kind: String, livery: Color) -> Node3D:
	var n := Node3D.new()
	n.name = kind
	var s: Dictionary = Models.SPECS.get(kind, Models.SPECS["a320"])
	var mi := MeshInstance3D.new()
	mi.mesh = Models.plane_mesh(kind, livery)
	n.add_child(mi)
	var gear := MeshInstance3D.new()
	gear.name = "Fahrwerk"
	gear.mesh = Models.gear_mesh(kind)
	n.add_child(gear)
	for side: Array in [["FanL", -1.0], ["FanR", 1.0]]:
		var fan := MeshInstance3D.new()
		fan.name = side[0]
		fan.mesh = Models.fan_mesh(kind)
		fan.position = Vector3(float(side[1]) * float(s["eng_x"]), float(s["eng_y"]), float(s["eng_z"]) + 0.42)
		n.add_child(fan)
	var cy: float = s["cy"]
	var r: float = s["r"]
	var beacon := Node3D.new()
	beacon.name = "Beacon"
	n.add_child(beacon)
	_glow(beacon, Vector3(0, cy + r + 0.1, -1.05), Vector3(0.24, 0.18, 0.3), Color(1.0, 0.1, 0.05))
	_glow(beacon, Vector3(0, cy - r - 0.22, 2.55), Vector3(0.24, 0.18, 0.3), Color(1.0, 0.1, 0.05))
	var strobe := Node3D.new()
	strobe.name = "Strobe"
	strobe.visible = false
	n.add_child(strobe)
	var tip_x: float = s["tip_x"]
	var tip: Array = Models._wing_at(s, tip_x)
	for sx: float in [-1.0, 1.0]:
		_glow(strobe, Vector3(sx * (tip_x + 0.05), float(tip[1]), float(tip[0]) + 0.6), Vector3(0.25, 0.25, 0.25), Color(1, 1, 1))
	_glow(strobe, Vector3(0, cy + r - float(s["tail_drop"]) - 0.1, float(s["len"]) * 0.5 - 0.1), Vector3(0.25, 0.25, 0.25), Color(1, 1, 1))
	return n


## Vorschaubild für Werkzeuge: Spuren (Stück 4-spurige Straße mit Pfeil), Kreuzung (Ampel).
static func make_tool_thumb(id: String) -> Node3D:
	if id == "spuren":
		var n := make_line_thumb("strasse4")
		blk(n, Vector3(-1.5, 0.3, -5), Vector3(1.5, 0.6, 3), Color(0.95, 0.8, 0.2))
		blk(n, Vector3(-3.5, 0.3, -7), Vector3(3.5, 0.6, -5), Color(0.95, 0.8, 0.2))
		return n
	var t := Node3D.new()
	blk(t, Vector3(-3, -0.2, -3), Vector3(3, 0, 3), Color(0.23, 0.225, 0.21))
	blk(t, Vector3(-0.12, 0, -0.12), Vector3(0.12, 4.0, 0.12), STEEL)
	blk(t, Vector3(-0.45, 2.3, -0.3), Vector3(0.45, 4.3, 0.3), DARK)
	var lamp_cols := [Color(0.95, 0.15, 0.1), Color(0.95, 0.75, 0.1), Color(0.2, 0.9, 0.35)]
	for i in range(3):
		blk(t, Vector3(-0.28, 3.75 - float(i) * 0.62, 0.3), Vector3(0.28, 4.15 - float(i) * 0.62, 0.36), lamp_cols[i])
	return t


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
				var staff := make_staff(Color(0.2, 0.28, 0.45), Color(0.12, 0.14, 0.2), 0 if x < 0.0 else 2)
				staff.position = Vector3(x, 0, -0.75)
				n.add_child(staff)
			blk(n, Vector3(-0.3, 0, -0.2), Vector3(0.3, 0.45, 0.5), DARK)
			blk(n, Vector3(-3, 0, -1.5), Vector3(3, 0.5, -1.15), DARK)
			blk(n, Vector3(-3, 0, -1.5), Vector3(3, 2.9, -1.38), Color(0.24, 0.34, 0.45))
			blk(n, Vector3(-2.2, 2.3, -1.38), Vector3(2.2, 2.6, -1.32), Color(0.95, 0.85, 0.4))
			for x: float in [-1.5, 1.5]:
				blk(n, Vector3(x - 0.35, 1.12, -0.05), Vector3(x + 0.35, 1.5, 0.0), DARK)
				blk(n, Vector3(x - 0.05, 1.12, 0.0), Vector3(x + 0.05, 1.2, 0.12), STEEL)
				blk(n, Vector3(x + 0.55, 1.05, 0.1), Vector3(x + 0.95, 1.1, 0.45), STEEL)
			# Wartegasse im Zickzack mit Gurtpfosten
			for row in range(3):
				var z := 1.35 + float(row) * 0.95
				var px := -2.8
				while px <= 2.85:
					cyl(n, Vector3(px, 0, z), 0.05, 0.05, 0.95, STEEL, 5)
					cyl(n, Vector3(px, 0, z), 0.16, 0.16, 0.04, DARK, 6)
					px += 1.4
				var gap_left := row % 2 == 1
				blk(n, Vector3(-2.8 if not gap_left else -1.4, 0.85, z - 0.03), Vector3(2.8 if gap_left else 1.4, 0.9, z + 0.03), Color(0.6, 0.15, 0.15))
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
				if x < 0.0:
					blk(n, Vector3(x - 1.05, 0, -0.2), Vector3(x - 0.9, 2.2, 0.2), WHITE)
					blk(n, Vector3(x - 0.3, 0, -0.2), Vector3(x - 0.15, 2.2, 0.2), WHITE)
					blk(n, Vector3(x - 1.05, 2.1, -0.2), Vector3(x - 0.15, 2.3, 0.2), WHITE)
				else:
					# Körperscanner: runde Kabine mit Glasflügeln
					cyl(n, Vector3(x - 0.6, 0, 0), 0.75, 0.75, 0.12, Color(0.6, 0.62, 0.65), 12)
					cyl(n, Vector3(x - 0.6, 2.2, 0), 0.75, 0.75, 0.25, Color(0.85, 0.86, 0.88), 12)
					for side: float in [-1.0, 1.0]:
						blk(n, Vector3(x - 0.6 + side * 0.62 - 0.08, 0.12, -0.45), Vector3(x - 0.6 + side * 0.62 + 0.08, 2.2, 0.45), Color(0.85, 0.86, 0.88))
				# Rollenbahn und Wannen
				var rz := -2.5
				while rz < 3.1:
					blk(n, Vector3(x + 0.15, 0.82, rz), Vector3(x + 1.05, 0.84, rz + 0.04), Color(0.3, 0.31, 0.33))
					rz += 0.25
				for tz: float in [-2.2, 1.6, 2.4]:
					blk(n, Vector3(x + 0.2, 0.84, tz), Vector3(x + 1.0, 0.95, tz + 0.55), Color(0.55, 0.57, 0.6))
					blk(n, Vector3(x + 0.35, 0.95, tz + 0.1), Vector3(x + 0.75, 1.05, tz + 0.4), SHIRTS[int(absf(tz) * 10.0) % SHIRTS.size()].darkened(0.3))
				blk(n, Vector3(x + 1.3, 0, 1.2), Vector3(x + 2.0, 0.85, 2.2), STEEL)
				var officer := make_staff(Color(0.82, 0.84, 0.88), Color(0.1, 0.1, 0.12), 1 if x < 0.0 else 3)
				officer.position = Vector3(x - 0.6, 0, -1.4)
				n.add_child(officer)
				for i in range(3):
					blk(n, Vector3(x + 0.2, 0.82 + float(i) * 0.06, 2.6), Vector3(x + 1.0, 0.86 + float(i) * 0.06, 3.1), Color(0.5, 0.52, 0.55))
			blk(n, Vector3(-0.08, 0, -3.6), Vector3(0.08, 1.0, 3.6), STEEL)
		"gate":
			blk(n, Vector3(-5, 0, -4), Vector3(5, 0.06, 4), Color(0.30, 0.33, 0.42))
			blk(n, Vector3(-1.5, 0, -3.3), Vector3(1.5, 1.05, -2.5), WHITE)
			blk(n, Vector3(-1.55, 1.05, -3.35), Vector3(1.55, 1.12, -2.45), DARK)
			var agent := make_staff(Color(0.24, 0.34, 0.45), Color(0.12, 0.14, 0.2), 2)
			agent.position = Vector3(0, 0, -3.7)
			n.add_child(agent)
			blk(n, Vector3(2.4, 0, -4.0), Vector3(4.6, 2.7, -3.75), STEEL)
			blk(n, Vector3(2.6, 0, -3.9), Vector3(4.4, 2.5, -3.7), DARK)
			for mx: float in [-0.8, 0.8]:
				blk(n, Vector3(mx - 0.3, 1.12, -2.95), Vector3(mx + 0.3, 1.45, -2.9), DARK)
			# Boarding-Schleuse mit Glasklappen und Anzeige über der Tür
			for gx: float in [2.7, 3.5, 4.3]:
				blk(n, Vector3(gx - 0.12, 0, -3.3), Vector3(gx + 0.12, 1.0, -2.6), Color(0.75, 0.76, 0.78))
				blk(n, Vector3(gx + 0.12, 0.3, -2.98), Vector3(gx + 0.42, 0.95, -2.92), Color(0.6, 0.8, 0.9))
			blk(n, Vector3(2.6, 2.75, -3.9), Vector3(4.4, 3.2, -3.82), Color(0.08, 0.08, 0.1))
			blk(n, Vector3(2.75, 2.9, -3.83), Vector3(3.9, 3.05, -3.8), YELLOW_SIGN)
			blk(n, Vector3(-4.7, 0, -3.6), Vector3(-4.5, 3.0, -3.4), STEEL)
			blk(n, Vector3(-4.95, 2.4, -3.62), Vector3(-3.2, 3.1, -3.44), Color(0.12, 0.15, 0.22))
			blk(n, Vector3(-4.8, 2.6, -3.44), Vector3(-3.4, 2.85, -3.4), YELLOW)
			for z: float in [-1.0, 0.6, 2.4]:
				var flip := 1.0 if z > 0.0 else -1.0
				blk(n, Vector3(-3.7, 0.42, z - 0.3), Vector3(3.7, 0.52, z + 0.3), SEAT)
				blk(n, Vector3(-3.7, 0.52, z + 0.2 * flip - 0.05), Vector3(3.7, 0.95, z + 0.2 * flip + 0.05), SEAT.darkened(0.15))
				for x: float in [-3.4, 0.0, 3.4]:
					blk(n, Vector3(x - 0.08, 0, z - 0.2), Vector3(x + 0.08, 0.42, z + 0.2), STEEL)
		"busgate":
			blk(n, Vector3(-5, 0, -4), Vector3(5, 0.06, 4), Color(0.24, 0.38, 0.38))
			blk(n, Vector3(-1.5, 0, -3.3), Vector3(1.5, 1.05, -2.5), WHITE)
			blk(n, Vector3(-1.55, 1.05, -3.35), Vector3(1.55, 1.12, -2.45), DARK)
			var agent2 := make_staff(Color(0.24, 0.34, 0.45), Color(0.12, 0.14, 0.2), 1)
			agent2.position = Vector3(0, 0, -3.7)
			n.add_child(agent2)
			for mx: float in [-0.8, 0.8]:
				blk(n, Vector3(mx - 0.3, 1.12, -2.95), Vector3(mx + 0.3, 1.45, -2.9), DARK)
			# Glastür zum Vorfeld mit Treppe hinab, darüber "BUS"
			blk(n, Vector3(1.6, 0, -4.0), Vector3(4.8, 2.9, -3.8), STEEL)
			var gd := blk(n, Vector3(1.9, 0.05, -3.95), Vector3(4.5, 2.6, -3.85), WHITE)
			gd.material_override = glass_mat()
			for i in range(4):
				blk(n, Vector3(1.9, 0.0, -3.7 + float(i) * 0.3), Vector3(4.5, 0.05 + float(3 - i) * 0.04, -3.4 + float(i) * 0.3), Color(0.5, 0.5, 0.48))
			blk(n, Vector3(1.8, 2.9, -3.95), Vector3(4.6, 3.35, -3.85), Color(0.08, 0.08, 0.1))
			blk(n, Vector3(2.1, 3.0, -3.86), Vector3(4.3, 3.25, -3.83), Color(0.95, 0.65, 0.15))
			for gx: float in [1.9, 2.8]:
				blk(n, Vector3(gx - 0.1, 0, -2.9), Vector3(gx + 0.1, 1.0, -2.2), Color(0.75, 0.76, 0.78))
			for z: float in [-1.0, 0.6, 2.4]:
				var flip2 := 1.0 if z > 0.0 else -1.0
				blk(n, Vector3(-3.7, 0.42, z - 0.3), Vector3(3.7, 0.52, z + 0.3), Color(0.2, 0.45, 0.42))
				blk(n, Vector3(-3.7, 0.52, z + 0.2 * flip2 - 0.05), Vector3(3.7, 0.95, z + 0.2 * flip2 + 0.05), Color(0.16, 0.36, 0.34))
				for x: float in [-3.4, 0.0, 3.4]:
					blk(n, Vector3(x - 0.08, 0, z - 0.2), Vector3(x + 0.08, 0.42, z + 0.2), STEEL)
		"gepaeckband":
			blk(n, Vector3(-4.5, 0, -1.8), Vector3(4.5, 0.55, 1.8), STEEL)
			blk(n, Vector3(-4.3, 0.55, -1.6), Vector3(4.3, 0.6, 1.6), DARK)
			blk(n, Vector3(-3.6, 0, -0.75), Vector3(3.6, 0.85, 0.75), Color(0.62, 0.64, 0.64))
			# Koffer auf dem Band: eigene Knoten, terminal.gd lässt sie umlaufen
			var cases := Node3D.new()
			cases.name = "Koffer"
			cases.set_meta("no_bake", true)
			n.add_child(cases)
			for i in range(9):
				var bag := blk(cases, Vector3(-0.35, 0.6, -0.22), Vector3(0.35, 0.92, 0.22), SHIRTS[(i * 3 + 1) % SHIRTS.size()].darkened(0.25))
				bag.name = "K%d" % i
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
		"sb_ausgang":
			for x: float in [-2.0, 2.0]:
				blk(n, Vector3(x - 0.12, 0, -0.2), Vector3(x + 0.12, 2.6, 0.2), STEEL)
			blk(n, Vector3(-2.1, 2.45, -0.25), Vector3(2.1, 2.8, 0.25), STEEL)
			for x: float in [-0.95, 0.95]:
				var g := blk(n, Vector3(x - 0.9, 0.05, -0.05), Vector3(x + 0.9, 2.4, 0.05), WHITE)
				g.material_override = glass_mat()
			blk(n, Vector3(-0.6, 2.5, 0.26), Vector3(0.6, 2.75, 0.3), Color(0.15, 0.6, 0.3))
			blk(n, Vector3(-0.5, 2.5, -0.3), Vector3(0.5, 2.75, -0.26), Color(0.8, 0.12, 0.1))
			blk(n, Vector3(-0.08, 2.55, -0.32), Vector3(0.08, 2.7, -0.3), WHITE)
			blk(n, Vector3(-0.35, 2.6, -0.32), Vector3(0.35, 2.65, -0.3), WHITE)
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


## Passagier oder Personal, etwa 1,75 m groß. Der Körper ist ein Mesh in sechs Posen
## (stehen, vier Gangphasen, sitzen); set_pose() wechselt sie.
static func make_person(shirt: Color, skin_i: int = -1, look: Dictionary = {}) -> Node3D:
	var n := Node3D.new()
	if look.is_empty():
		look = Models.random_look(shirt, skin_i)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = Models.person_mesh(look, 0)
	n.add_child(mi)
	n.set_meta("look", look)
	n.set_meta("pose", 0)
	return n


static func make_staff(shirt: Color, pants: Color, skin_i: int, vest: bool = false) -> Node3D:
	return make_person(shirt, skin_i, Models.staff_look(shirt, pants, skin_i, vest))


static func set_pose(person: Node3D, pose: int) -> void:
	if int(person.get_meta("pose", -1)) == pose:
		return
	var mi := person.get_node_or_null("Body") as MeshInstance3D
	if mi != null and person.has_meta("look"):
		mi.mesh = Models.person_mesh(person.get_meta("look"), pose)
		person.set_meta("pose", pose)
