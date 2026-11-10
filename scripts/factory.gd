extends RefCounted
## Baut die sichtbaren Formen: Wege-Bänder, Gebäude, Deko und Fahrzeuge
## aus einfachen Grundkörpern (Low-Poly, später durch Blender-Modelle ersetzbar).

const Catalog = preload("res://scripts/catalog.gd")
const Spline = preload("res://scripts/spline.gd")
const LINE_SHADER = preload("res://shaders/line.gdshader")
const Models = preload("res://scripts/models.gd")
const Kit = preload("res://scripts/mesh_kit.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")
const BeltAnim = preload("res://scripts/belt_anim.gd")
const Furniture = preload("res://scripts/furniture.gd")
const Landscape = preload("res://scripts/landscape.gd")

const WALL := Color(0.78, 0.75, 0.67)
const GLASS := Color(0.2, 0.3, 0.36, 0.6)      # Alpha 0.6: nachts erleuchtet
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
	if bool(def.get("fence", false)):
		var fm := Landscape.fence(samples)
		fm.name = kind
		return fm
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
	if kind == "tunnel":
		mi.add_child(_tunnel_build(samples, w))
	elif kind == "foerderband":
		mi.add_child(_belt_build(samples, w))
	# Schultern neben Rollweg und Piste (liegen unter allen anderen Belägen)
	if kind == "rollweg" or kind == "rollweg_breit" or kind == "piste":
		var sh := 3.5 if kind == "rollweg" else (5.0 if kind == "rollweg_breit" else 7.5)
		var smi := MeshInstance3D.new()
		smi.name = "Schulter"
		smi.mesh = Spline.ribbon(samples, w + sh * 2.0, 0.016 if kind == "piste" else 0.018)
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


## Bauwerk eines Straßentunnels: Stützwände der offenen Rampen mit Geländer, Portale mit Sturz
## und Schild, im geschlossenen Teil Wände mit Fliesen und Leuchtbändern (ohne Decke, damit man
## in der Ansicht Untergeschoss hineinsieht).
static func _tunnel_build(s: PackedVector3Array, w: float) -> MeshInstance3D:
	var k := Kit.new()
	var conc := Color(0.6, 0.59, 0.55)
	var tile := Color(0.84, 0.83, 0.78)
	var walk := Color(0.5, 0.5, 0.48)
	var rail := Color(0.55, 0.58, 0.6)
	var lamp := Color(1.0, 0.93, 0.75, 0.3)
	var n := s.size()
	var portals := []
	for i in range(0, n - 2, 2):
		var a := s[i]
		var b := s[i + 2]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if dir.length() < 0.01:
			continue
		dir = dir.normalized()
		var bas := Basis.looking_at(dir, Vector3.UP)
		var mid := (a + b) * 0.5
		var ylow := minf(a.y, b.y)
		var seg := a.distance_to(b) * 0.5 + 0.08
		var covered := mid.y < Catalog.TUNNEL_COVER
		if (a.y >= Catalog.TUNNEL_COVER) != (b.y >= Catalog.TUNNEL_COVER):
			portals.append([mid, dir, ylow])
		if mid.y > -0.03:
			continue
		for sx: float in [-1.0, 1.0]:
			var ox := sx * (w * 0.5 + 0.35)
			# im geschlossenen Teil als Schnitt: niedrige Wände, damit man in der Ansicht Untergeschoss hineinsieht
			var top := minf(ylow + 1.8, -0.06) if covered else 0.55
			k.box(Vector3(ox - 0.35, ylow - 0.4, -seg), Vector3(ox + 0.35, top, seg), conc, Transform3D(bas, Vector3(mid.x, 0.0, mid.z)))
			# Notgehweg mit Bordstein
			var ow := sx * (w * 0.5 - 0.35)
			k.box(Vector3(ow - 0.35, mid.y - 0.05, -seg), Vector3(ow + 0.35, mid.y + 0.2, seg), walk, Transform3D(bas, Vector3(mid.x, 0.0, mid.z)))
			if covered:
				var fx := sx * (w * 0.5 + 0.0)
				k.box(Vector3(fx - 0.02, mid.y + 0.3, -seg), Vector3(fx + 0.02, mid.y + 1.5, seg), tile, Transform3D(bas, Vector3(mid.x, 0.0, mid.z)))
				if i % 6 == 0:
					k.box(Vector3(fx - 0.06, mid.y + 1.55, -0.9), Vector3(fx + 0.06, mid.y + 1.7, 0.9), lamp, Transform3D(bas, Vector3(mid.x, 0.0, mid.z)))
				if i % 60 == 0:
					# Notrufnische mit grünem Schild
					k.box(Vector3(fx - 0.04, mid.y + 1.0, -0.5), Vector3(fx + 0.04, mid.y + 2.2, 0.5), Color(0.9, 0.45, 0.12), Transform3D(bas, Vector3(mid.x, 0.0, mid.z)))
					k.box(Vector3(fx - 0.05, mid.y + 2.5, -0.35), Vector3(fx + 0.05, mid.y + 2.9, 0.35), Color(0.15, 0.6, 0.3, 0.3), Transform3D(bas, Vector3(mid.x, 0.0, mid.z)))
			else:
				# Geländer auf der Stützwand
				k.box(Vector3(ox - 0.03, 0.55, -seg), Vector3(ox + 0.03, 1.55, -seg + 0.08), rail, Transform3D(bas, Vector3(mid.x, 0.0, mid.z)))
				k.box(Vector3(ox - 0.04, 1.5, -seg), Vector3(ox + 0.04, 1.58, seg), rail, Transform3D(bas, Vector3(mid.x, 0.0, mid.z)))
				k.box(Vector3(ox - 0.03, 1.0, -seg), Vector3(ox + 0.03, 1.05, seg), rail, Transform3D(bas, Vector3(mid.x, 0.0, mid.z)))
	# Portale: Sturz über der Fahrbahn, Stirnwand bis knapp über den Boden, Schild
	for pt: Array in portals:
		var c: Vector3 = pt[0]
		var dir: Vector3 = pt[1]
		var y0: float = pt[2]
		var bas := Basis.looking_at(dir, Vector3.UP)
		var xf := Transform3D(bas, Vector3(c.x, 0.0, c.z))
		var hw := w * 0.5 + 0.7
		k.box(Vector3(-hw, y0 + 4.9, -0.7), Vector3(hw, 0.65, 0.7), conc, xf)
		k.box(Vector3(-hw - 0.2, 0.55, -0.8), Vector3(hw + 0.2, 0.75, 0.8), conc.darkened(0.1), xf)
		k.box(Vector3(-hw, y0 + 4.75, -0.75), Vector3(hw, y0 + 4.95, 0.75), Color(0.86, 0.69, 0.22), xf)
		var face := -dir if c.distance_to(s[0]) < c.distance_to(s[n - 1]) else dir
		var side := face.cross(Vector3.UP).normalized()
		var sc := Vector3(c.x, (y0 + 4.9 + 0.65) * 0.5, c.z) + face * 0.75
		k.box(Vector3(-1.6, -0.35, -0.04), Vector3(1.6, 0.35, 0.04), Color(0.1, 0.2, 0.45), Transform3D(Basis.looking_at(face, Vector3.UP), sc))
		PixelFont.draw(k, "TUNNEL", sc + face * 0.06, -side, Vector3.UP, face, 0.09, Color(0.95, 0.95, 0.92))
		for sx: float in [-1.0, 1.0]:
			k.box(Vector3(sx * (w * 0.5 - 0.1) - 0.08, y0 + 4.3, -0.8), Vector3(sx * (w * 0.5 - 0.1) + 0.08, y0 + 4.7, -0.7), lamp, xf)
	var mi := k.instance("Bauwerk")
	return mi


## Gepäcktunnel: Betonkanal unter der Erde, Stahlrahmen, Lampen und laufende Koffer.
static func _belt_build(s: PackedVector3Array, w: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Bauwerk"
	var k := Kit.new()
	var conc := Color(0.55, 0.54, 0.5)
	var n := s.size()
	for i in range(0, n - 2, 2):
		var a := s[i]
		var b := s[i + 2]
		var dir := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if dir.length() < 0.01:
			continue
		var bas := Basis.looking_at(dir.normalized(), Vector3.UP)
		var mid := (a + b) * 0.5
		var seg := a.distance_to(b) * 0.5 + 0.06
		var xf := Transform3D(bas, Vector3(mid.x, 0.0, mid.z))
		var y := mid.y
		k.box(Vector3(-w * 0.75 - 0.6, y - 0.75, -seg), Vector3(w * 0.75 + 0.6, y - 0.45, seg), conc.darkened(0.05), xf)
		for sx: float in [-1.0, 1.0]:
			k.box(Vector3(sx * (w * 0.75 + 0.3) - 0.3, y - 0.75, -seg), Vector3(sx * (w * 0.75 + 0.3) + 0.3, y + 0.55, seg), conc, xf)
			k.box(Vector3(sx * w * 0.5 - 0.06, y - 0.2, -seg), Vector3(sx * w * 0.5 + 0.06, y + 0.12, seg), Color(0.42, 0.45, 0.48), xf)
			if i % 6 == 0:
				k.box(Vector3(sx * w * 0.42 - 0.05, y - 0.45, -0.05), Vector3(sx * w * 0.42 + 0.05, y - 0.05, 0.05), Color(0.3, 0.32, 0.34), xf)
		if i % 16 == 0:
			k.box(Vector3(w * 0.75 + 0.05, y + 0.55, -0.1), Vector3(w * 0.75 + 0.15, y + 1.2, 0.1), Color(0.3, 0.32, 0.34), xf)
			k.box(Vector3(w * 0.75 - 0.15, y + 1.15, -0.5), Vector3(w * 0.75 + 0.15, y + 1.25, 0.5), Color(1.0, 0.92, 0.7, 0.3), xf)
	root.add_child(k.instance("Kanal"))
	var pts := PackedVector3Array()
	for v: Vector3 in s:
		pts.append(v + Vector3(0, 0.12, 0))
	var bags := MultiMeshInstance3D.new()
	bags.name = "Koffer"
	bags.set_script(BeltAnim)
	root.add_child(bags)
	bags.call("setup", pts, Models.bag_mesh(), 1.6, 2.6)
	return root


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


## Terminalhalle w × d mit Bauformen (opts): Ebenen 1–3, Keller, Fassade (Glas, Beton, Holz),
## Ecken (eckig, abgerundet, rund), Dach (flach, Tonnendach, Sheddach).
## Knoten: "Ebene-1" … "Ebene2" (Böden), "Hoch" (volle Fassade), "Tief" (Brüstung für die Innenansicht), "Dach".
static func make_hall(w: float, d: float, opts: Dictionary = {}) -> Node3D:
	var n := Node3D.new()
	n.name = "halle"
	var hw := w * 0.5
	var hd := d * 0.5
	var levels := int(opts.get("etagen", 1))
	var cellar := bool(opts.get("keller", false))
	var facade := String(opts.get("fassade", "glas"))
	var form := String(opts.get("form", "eckig"))
	var roof_t := String(opts.get("dach", "flach"))
	var fh := Catalog.FLOOR_H
	var top := 4.6 + float(levels) * fh       # Oberkante Fassade
	var radius := 0.0
	if form == "abgerundet":
		radius = minf(4.0, minf(hw, hd) * 0.4)
	elif form == "rund":
		radius = minf(hw, hd) * 0.45
	var ring := _perimeter(hw, hd, radius)
	# Böden je Ebene mit Fugenraster
	for f in range(-1 if cellar else 0, levels):
		var slab := Node3D.new()
		slab.name = "Ebene%d" % f
		n.add_child(slab)
		var k := Kit.new()
		var y0 := float(f) * fh
		var fc := FLOOR if f != -1 else Color(0.6, 0.6, 0.58)
		_polygon(k, ring, y0 - (0.25 if f != 0 else 0.0), y0 + 0.1, fc)
		var x := -hw + 4.0
		while x < hw - 0.5:
			k.box(Vector3(x - 0.04, y0 + 0.1, -hd + radius * 0.3), Vector3(x + 0.04, y0 + 0.11, hd - radius * 0.3), fc.darkened(0.08))
			x += 4.0
		var z := -hd + 4.0
		while z < hd - 0.5:
			k.box(Vector3(-hw + radius * 0.3, y0 + 0.1, z - 0.04), Vector3(hw - radius * 0.3, y0 + 0.11, z + 0.04), fc.darkened(0.08))
			z += 4.0
		if f == -1:
			_wall_ring(k, ring, -fh, -0.25, CONCRETE, 0.4)
		slab.add_child(k.instance("Boden"))
	# Fassade außen (volle Höhe)
	var high := Node3D.new()
	high.name = "Hoch"
	n.add_child(high)
	var hk := Kit.new()
	var band := WALL
	var wall_col := WALL
	match facade:
		"beton":
			wall_col = Color(0.66, 0.65, 0.62)
		"holz":
			wall_col = Color(0.55, 0.38, 0.22)
			band = Color(0.42, 0.29, 0.17)
	_wall_ring(hk, ring, 0.0, 0.6, CONCRETE, 0.32)
	for f in range(levels):
		var y0 := 0.6 + float(f) * fh
		var y1 := float(f + 1) * fh + (4.6 - fh if f == levels - 1 else 0.0) - 1.4
		if facade == "glas":
			_wall_ring(hk, ring, y0, y1, GLASS, 0.24)
			_mullions(hk, ring, y0, y1, 2.0, Color(0.34, 0.38, 0.4))
		else:
			_wall_ring(hk, ring, y0, y1, wall_col, 0.3)
			_wall_ring(hk, ring, y0 + 0.9, minf(y0 + 3.2, y1 - 0.2), GLASS, 0.34)
			_mullions(hk, ring, y0 + 0.9, minf(y0 + 3.2, y1 - 0.2), 1.6, band)
			if facade == "holz":
				_mullions(hk, ring, y1 - 0.9, y1, 0.5, band)
		_wall_ring(hk, ring, y1, y1 + 1.4 if f < levels - 1 else top, band, 0.3)
	high.add_child(hk.instance("Fassade"))
	if w >= 30.0:
		_letters(high, "TERMINAL", Vector3(0, top - 1.2, hd + 0.18), 0.27 + 0.05 * float(levels - 1), Color(0.16, 0.25, 0.45))
	# niedrige Brüstung für die Innenansicht
	var low := Node3D.new()
	low.name = "Tief"
	n.add_child(low)
	var lk := Kit.new()
	_wall_ring(lk, ring, 0.0, 0.6, CONCRETE, 0.3)
	_wall_ring(lk, ring, 0.6, 1.3, Color(0.55, 0.75, 0.85, 0.6), 0.32)
	_wall_ring(lk, ring, 1.3, 1.45, WALL, 0.34)
	low.add_child(lk.instance("Bruestung"))
	# Dach
	var roof := Node3D.new()
	roof.name = "Dach"
	n.add_child(roof)
	var rk := Kit.new()
	var ring_out := _perimeter(hw + 0.4, hd + 0.4, radius + (0.4 if radius > 0.0 else 0.0))
	_polygon(rk, ring_out, top - 0.6, top, ROOF)
	_wall_ring(rk, ring_out, top, top + 0.5, band, 0.35)
	if roof_t == "gewoelbt" and radius < 0.1:
		# Tonnendach quer zur Landseite: Bögen aus Blechbahnen
		var steps := 14
		var rise := minf(hd * 0.35, 6.0)
		for i in range(steps):
			var a0 := PI * float(i) / float(steps)
			var a1 := PI * float(i + 1) / float(steps)
			var z0 := -hd * cos(a0)
			var z1 := -hd * cos(a1)
			var y0 := top + rise * sin(a0)
			var y1 := top + rise * sin(a1)
			var col := Color(0.62, 0.64, 0.66) if i % 2 == 0 else Color(0.58, 0.6, 0.62)
			rk.quad(Vector3(-hw - 0.3, y0, z0), Vector3(hw + 0.3, y0, z0), Vector3(hw + 0.3, y1, z1), Vector3(-hw - 0.3, y1, z1), col, Vector3(0, top - 20.0, 0))
		for sx: float in [-1.0, 1.0]:
			for i in range(steps):
				var a0 := PI * float(i) / float(steps)
				var a1 := PI * float(i + 1) / float(steps)
				rk.tri(Vector3(sx * (hw + 0.3), top, 0), Vector3(sx * (hw + 0.3), top + rise * sin(a0), -hd * cos(a0)),
					Vector3(sx * (hw + 0.3), top + rise * sin(a1), -hd * cos(a1)), GLASS, Vector3(0, top + 2.0, 0))
	elif roof_t == "shed" and radius < 0.1:
		# Sheddach: Sägezahn, Glasflächen nach Norden (-z)
		var z := -hd
		while z < hd - 0.5:
			var z1 := minf(z + 6.0, hd)
			rk.quad(Vector3(-hw, top + 2.4, z), Vector3(hw, top + 2.4, z), Vector3(hw, top, z1), Vector3(-hw, top, z1), ROOF.lightened(0.15), Vector3(0, top - 10.0, z1 + 5.0))
			rk.box(Vector3(-hw, top, z - 0.05), Vector3(hw, top + 2.4, z + 0.05), GLASS)
			z = z1
	else:
		var sx := -hw + 6.0
		while sx < hw - 4.0:
			rk.box(Vector3(sx - 1.0, top, -hd + 3.0 + radius * 0.5), Vector3(sx + 1.0, top + 0.3, hd - 3.0 - radius * 0.5), Color(0.36, 0.46, 0.52, 0.6))
			sx += 12.0
		var units := clampi(int(w * d / 500.0), 1, 12)
		for i in range(units):
			var ux := -hw + (float(i) + 0.5) * w / float(units)
			var uz := (hd * 0.45) * (1.0 if i % 2 == 0 else -1.0)
			rk.box(Vector3(ux - 2.0, top, uz - 1.5), Vector3(ux + 2.0, top + 1.3, uz + 1.5), Color(0.45, 0.47, 0.47))
			for gx in range(3):
				rk.cyl(Vector3(ux - 1.2 + float(gx) * 1.2, top + 1.3, uz), Vector3(ux - 1.2 + float(gx) * 1.2, top + 1.4, uz), 0.5, 0.5, Color(0.3, 0.32, 0.33), 12)
	roof.add_child(rk.instance("Dachflaeche"))
	bake(n)
	return n


## Umriss eines Rechtecks mit gerundeten Ecken (gegen den Uhrzeigersinn), radius 0 = eckig.
static func _perimeter(hw: float, hd: float, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if radius < 0.05:
		return PackedVector2Array([Vector2(hw, hd), Vector2(-hw, hd), Vector2(-hw, -hd), Vector2(hw, -hd)])
	var steps := 6
	for c: Array in [[hw - radius, hd - radius, 0.0], [-hw + radius, hd - radius, PI * 0.5], [-hw + radius, -hd + radius, PI], [hw - radius, -hd + radius, PI * 1.5]]:
		for i in range(steps + 1):
			var a := float(c[2]) + PI * 0.5 * float(i) / float(steps)
			out.append(Vector2(float(c[0]) + cos(a) * radius, float(c[1]) + sin(a) * radius))
	return out


## Fläche (konvex) zwischen y0 und y1 über dem Umriss.
static func _polygon(k: Kit, ring: PackedVector2Array, y0: float, y1: float, col: Color) -> void:
	var top := []
	var bot := []
	for p: Vector2 in ring:
		top.append(Vector3(p.x, y1, p.y))
		bot.append(Vector3(p.x, y0, p.y))
	k.prism(bot, top, col)


## Wandring entlang des Umrisses (Dicke t, nach innen).
static func _wall_ring(k: Kit, ring: PackedVector2Array, y0: float, y1: float, col: Color, t: float) -> void:
	if y1 - y0 < 0.01:
		return
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var d := b - a
		var len := d.length()
		if len < 0.01:
			continue
		var mid := (a + b) * 0.5
		var dir := Vector3(d.x, 0, d.y) / len
		var inward := Vector3(-mid.x, 0, -mid.y).normalized()
		var side := dir.cross(Vector3.UP)
		if side.dot(inward) < 0.0:
			side = -side
		var bas := Basis(dir, Vector3.UP, side)
		k.box(Vector3(-len * 0.5 - 0.02, y0, 0.0), Vector3(len * 0.5 + 0.02, y1, t), col, Transform3D(bas, Vector3(mid.x, 0, mid.y)))


## Senkrechte Sprossen alle step Meter entlang des Umrisses.
static func _mullions(k: Kit, ring: PackedVector2Array, y0: float, y1: float, step: float, col: Color) -> void:
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var len := a.distance_to(b)
		var nseg := maxi(1, int(len / step))
		for j in range(nseg + 1):
			var p := a.lerp(b, float(j) / float(nseg))
			var outv := Vector2(p.x, p.y).normalized()
			var q := p + outv * 0.02
			k.box(Vector3(q.x - 0.07, y0, q.y - 0.07), Vector3(q.x + 0.07, y1, q.y + 0.07), col)


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


static func make_item(id: String, opts: Dictionary = {}) -> Node3D:
	if id == "halle":
		return make_hall(24.0, 16.0, opts)
	var n := _make_item_raw(id, opts)
	bake(n)
	return n


static func _make_item_raw(id: String, opts: Dictionary = {}) -> Node3D:
	var n := Node3D.new()
	n.name = id
	n.set_meta("opts", opts)
	if Catalog.is_inside(id):
		_inside(n, id)
		return n
	if Landscape.build(n, id):
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
			_stand(n, false, "stand")
		"stand_aussen":
			_stand(n, true, "stand_aussen")
		"stand_gross":
			_stand(n, false, "stand_gross")
		"bushalt":
			_bus_stop(n)
		"haltestelle":
			_city_stop(n)
		"gepaeckumschlag":
			_baggage_hall(n)
		"flutlicht":
			_floodlight(n)
		"fluggastbruecke":
			_bridge_base(n)
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
			blk(n, Vector3(-0.25, 6.6, 0.9), Vector3(0.25, 6.85, 1.5), Color(0.98, 0.9, 0.66, 0.3))
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
	var opts: Dictionary = n.get_meta("opts", {})
	var clad: Color = {"grau": Color(0.62, 0.66, 0.68), "blau": Color(0.3, 0.45, 0.62), "weiss": Color(0.86, 0.87, 0.86)}.get(String(opts.get("farbe", "grau")), Color(0.62, 0.66, 0.68))
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
	var modern := String((n.get_meta("opts", {}) as Dictionary).get("stil", "klassisch")) == "modern"
	if modern:
		# schlanker Schaft mit durchgehendem Glasstreifen
		cyl(n, Vector3(0, 5.5, 0), 2.0, 1.6, 23.0, Color(0.93, 0.93, 0.92), 16)
		blk(n, Vector3(-0.5, 6.0, 1.45), Vector3(0.5, 28.0, 1.95), GLASS)
	else:
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
	var opts: Dictionary = n.get_meta("opts", {})
	var levels := int(opts.get("etagen", 4))
	var tint: Color = {"grau": CONCRETE, "rot": Color(0.62, 0.3, 0.24), "blau": Color(0.36, 0.48, 0.62), "holz": Color(0.55, 0.4, 0.25)}.get(String(opts.get("farbe", "grau")), CONCRETE)
	var top := float(levels) * 3.0
	for lvl in range(1, levels + 1):
		var y := float(lvl) * 3.0
		blk(n, Vector3(-16, y, -22), Vector3(16, y + 0.4, 22), CONCRETE)
		for side: float in [-1.0, 1.0]:
			blk(n, Vector3(-16, y + 0.4, side * 21.85 - 0.15), Vector3(16, y + 1.3, side * 21.85 + 0.15), tint)
			blk(n, Vector3(side * 15.85 - 0.15, y + 0.4, -22), Vector3(side * 15.85 + 0.15, y + 1.3, 22), tint)
			# senkrechte Lamellen an der Fassade
			var lx := -15.0
			while lx < 15.5:
				blk(n, Vector3(lx - 0.06, y - 1.6, side * 22.05 - 0.06), Vector3(lx + 0.06, y + 1.3, side * 22.05 + 0.06), tint.darkened(0.15))
				lx += 1.5
		# Parkplatz-Markierungen auf jeder Ebene
		for k in range(12):
			blk(n, Vector3(-15.0 + float(k) * 2.6, y + 0.4, -20.0), Vector3(-14.9 + float(k) * 2.6, y + 0.41, -14.5), Color(0.86, 0.85, 0.8))
			blk(n, Vector3(-15.0 + float(k) * 2.6, y + 0.4, 14.5), Vector3(-14.9 + float(k) * 2.6, y + 0.41, 20.0), Color(0.86, 0.85, 0.8))
	for x: float in [-15.6, -5.2, 5.2, 15.6]:
		for z: float in [-21.6, -7.2, 7.2, 21.6]:
			blk(n, Vector3(x - 0.3, 0, z - 0.3), Vector3(x + 0.3, top, z + 0.3), CONCRETE)
	# Rampe innen, Treppenhaus mit Glas und blauem P
	for lvl in range(levels):
		var y0 := float(lvl) * 3.0
		var ramp := Transform3D(Basis(Vector3.RIGHT, -atan(3.0 / 14.0)), Vector3(-2.5, y0 + 1.7, 0))
		var rk := Kit.new()
		rk.box(Vector3(-2.5, -0.15, -7.2), Vector3(2.5, 0.15, 7.2), CONCRETE.darkened(0.05), ramp)
		var rmi := rk.instance("Rampe")
		n.add_child(rmi)
	blk(n, Vector3(10.5, 0, -22), Vector3(16, top + 2.5, -16.5), CONCRETE)
	blk(n, Vector3(10.4, 1.0, -22.05), Vector3(15.0, top + 1.8, -21.95), GLASS)
	blk(n, Vector3(16.0, top - 2.5, -21.5), Vector3(16.15, top + 1.5, -17.0), Color(0.16, 0.32, 0.55))
	blk(n, Vector3(16.1, top - 1.8, -20.4), Vector3(16.2, top + 0.8, -19.8), Color(0.95, 0.95, 0.95))
	blk(n, Vector3(16.1, top + 0.2, -20.4), Vector3(16.2, top + 0.8, -18.6), Color(0.95, 0.95, 0.95))
	blk(n, Vector3(16.1, top - 0.6, -20.4), Vector3(16.2, top - 0.1, -18.6), Color(0.95, 0.95, 0.95))
	blk(n, Vector3(16.1, top - 0.6, -19.2), Vector3(16.2, top + 0.8, -18.6), Color(0.95, 0.95, 0.95))
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
			car.position = Vector3(-13.0 + float(k) * 2.6, top + 0.4, row)
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


## Bäume in fünf Arten. Laub hat Alpha 0.8: der Shader lässt es im Wind wiegen.
static func _baum(n: Node3D) -> void:
	var stil := String((n.get_meta("opts", {}) as Dictionary).get("stil", ["laub", "laub", "nadel", "birke", "pappel", "obst"][randi() % 6]))
	var k := Kit.new()
	var bark := Color(0.3, 0.22, 0.15)
	var g := Color.from_hsv(randf_range(0.22, 0.3), randf_range(0.45, 0.6), randf_range(0.32, 0.42))
	var leaf := Color(g.r, g.g, g.b, 0.8)
	var s := randf_range(0.85, 1.2)
	match stil:
		"nadel":
			k.cyl(Vector3.ZERO, Vector3(0, 2.0 * s, 0), 0.3, 0.25, bark, 8)
			var dark := Color(0.16, 0.3, 0.2, 0.8)
			for i in range(4):
				var y := (1.6 + float(i) * 1.9) * s
				k.cyl(Vector3(0, y, 0), Vector3(0, y + 3.0 * s, 0), (2.6 - float(i) * 0.55) * s, 0.0, dark.lightened(float(i) * 0.04), 12, true)
		"birke":
			k.cyl(Vector3.ZERO, Vector3(0, 5.5 * s, 0), 0.22, 0.14, Color(0.9, 0.89, 0.85), 8)
			for i in range(4):
				var y := 0.8 + float(i) * 1.1
				k.box(Vector3(-0.23, y, -0.05), Vector3(0.0, y + 0.12, 0.05), Color(0.15, 0.15, 0.15))
			var lg := Color(0.5, 0.66, 0.3, 0.8)
			for i in range(5):
				var off := Vector3(randf_range(-1.0, 1.0), randf_range(4.5, 7.0) * s, randf_range(-1.0, 1.0))
				k.sphere(off, randf_range(1.0, 1.5) * s, lg.lightened(randf() * 0.08), 10, 6, Vector3(1.0, 1.3, 1.0))
		"pappel":
			k.cyl(Vector3.ZERO, Vector3(0, 3.0, 0), 0.3, 0.25, bark, 8)
			k.sphere(Vector3(0, 7.5 * s, 0), 1.7 * s, leaf, 12, 8, Vector3(1.0, 3.2, 1.0))
		"obst":
			k.cyl(Vector3.ZERO, Vector3(0, 1.8, 0), 0.25, 0.2, bark, 8)
			for i in range(4):
				var off := Vector3(randf_range(-0.9, 0.9), randf_range(2.8, 3.6), randf_range(-0.9, 0.9))
				k.sphere(off, randf_range(1.2, 1.6), leaf.lightened(0.05), 10, 6)
			for i in range(10):
				var a := randf() * TAU
				var p := Vector3(cos(a) * 1.7, randf_range(2.6, 4.0), sin(a) * 1.7)
				k.sphere(p, 0.12, Color(0.85, 0.15, 0.1) if i % 3 != 0 else Color(0.95, 0.75, 0.15), 6, 4)
		_:
			k.cyl(Vector3.ZERO, Vector3(0, 3.4 * s, 0), 0.4, 0.28, bark, 10)
			for b in range(3):
				var a := TAU * float(b) / 3.0 + randf()
				k.cyl(Vector3(0, 2.6 * s, 0), Vector3(cos(a) * 1.2, 4.2 * s, sin(a) * 1.2), 0.16, 0.08, bark, 6)
			k.sphere(Vector3(0, 5.2 * s, 0), 2.5 * s, leaf, 14, 8)
			for i in range(5):
				var off := Vector3(randf_range(-1.6, 1.6), randf_range(4.6, 6.6) * s, randf_range(-1.6, 1.6))
				k.sphere(off, randf_range(1.3, 1.9) * s, Color(leaf.r, leaf.g, leaf.b, 0.8).lightened(randf() * 0.07), 12, 7)
	n.add_child(k.instance("Baum"))


## Standmarkierung nach ICAO (Nase zeigt nach +Z): gelbe Mittellinie, Haltebalken je Muster mit
## Beschriftung, rote Sicherheitslinien (Flügelspitzen und Geräte-Sperrfläche), weiße Geräteabstellflächen,
## Unterflur-Betankung und Bodenstrom, Andockanzeige vorn. Außenposition: Busparkfläche und Fußwege.
## Einrolllinien und Standnummer zeichnet airfield.gd, weil sie vom Rollweg dahinter abhängen.
static func _stand(n: Node3D, remote: bool, id: String = "stand") -> void:
	var size: Vector2 = Catalog.ITEMS[id]["size"]
	var code := String(Catalog.ITEMS[id].get("code", "C"))
	var hw := size.x * 0.5
	var hd := size.y * 0.5
	var stop := hd - 6.0            # hier steht die Nase
	var k := Kit.new()
	var yellow := Color(0.88, 0.70, 0.18)
	var red := Color(0.72, 0.18, 0.13)
	var white := Color(0.88, 0.88, 0.85)
	var y := 0.05
	var flat := func(a: Vector2, b: Vector2, c: Color) -> void:
		k.box(Vector3(minf(a.x, b.x), 0.0, minf(a.y, b.y)), Vector3(maxf(a.x, b.x), y, maxf(a.y, b.y)), c)
	# Haltebalken je Flugzeugmuster am Bugrad, beschriftet (abwechselnd links und rechts der Linie)
	var max_bar := -INF
	var side_i := 0
	var bars := []
	for kind: String in Catalog.PLANES:
		var pl: Dictionary = Catalog.PLANES[kind]
		if code == "C" and String(pl["code"]) != "C":
			continue
		var sp: Dictionary = Models.SPECS.get(kind, Models.SPECS["a320"])
		var z: float = stop - float(pl["nose"]) - float(sp["nose_gear_z"])
		var label: String = {"atr72": "AT72", "e190": "E190", "a320": "A320", "b737": "B738", "a321": "A321", "a330": "A333"}.get(kind, kind.to_upper())
		var merged := false
		for b: Array in bars:
			if absf(float(b[0]) - z) < 0.35:
				b[1] = String(b[1]) + "/" + label
				merged = true
		if not merged:
			bars.append([z, label])
	for b: Array in bars:
		var z: float = b[0]
		max_bar = maxf(max_bar, z)
		flat.call(Vector2(-1.6, z - 0.15), Vector2(1.6, z + 0.15), yellow)
		var sx := 1.0 if side_i % 2 == 0 else -1.0
		var txt := String(b[1])
		PixelFont.draw_ground(k, txt, Vector3(sx * (2.4 + float(PixelFont.width(txt)) * 0.08), y + 0.01, z), Vector3(0, 0, 1), 0.16, yellow)
		side_i += 1
	# Mittellinie bis hinter die Haltebalken
	flat.call(Vector2(-0.18, -hd), Vector2(0.18, max_bar + 0.6), yellow)
	# Sicherheitslinien: Standgrenzen (rot), Kopf des Stands
	for side: float in [-1.0, 1.0]:
		flat.call(Vector2(side * hw - 0.15, -hd), Vector2(side * hw + 0.15, hd), red)
	flat.call(Vector2(-hw, hd - 0.3), Vector2(hw, hd), red)
	# Geräte-Sperrfläche um die Nase: rote Umrandung mit Schraffur
	for x0: float in [-3.5, 3.0]:
		flat.call(Vector2(x0, stop - 3.4), Vector2(x0 + 0.5, stop + 3.0), red)
	flat.call(Vector2(-3.5, stop + 2.6), Vector2(3.5, stop + 3.0), red)
	for i in range(5):
		var zz := stop - 1.7 + float(i) * 1.0
		k.box(Vector3(-3.0, 0.0, -0.1), Vector3(3.0, y, 0.1), red, Transform3D(Basis(Vector3.UP, 0.45), Vector3(0, 0, zz)))
	# Geräteabstellflächen (weiß) an den vorderen Ecken, mit "GSE" beschriftet
	for side: float in [-1.0, 1.0]:
		var x0 := side * (hw - 7.0)
		var x1 := side * (hw - 0.8)
		var z0 := hd - 7.0
		var z1 := hd - 0.8
		flat.call(Vector2(x0, z0), Vector2(x1, z0 + 0.2), white)
		flat.call(Vector2(x0, z1 - 0.2), Vector2(x1, z1), white)
		flat.call(Vector2(x0, z0), Vector2(x0 + side * 0.2, z1), white)
		flat.call(Vector2(x1 - side * 0.2, z0), Vector2(x1, z1), white)
		PixelFont.draw_ground(k, "GSE", Vector3((x0 + x1) * 0.5, y + 0.01, (z0 + z1) * 0.5), Vector3(0, 0, -1), 0.3, white)
	# Unterflur-Betankung an beiden Flügeln, Bodenstrom an der Nase
	var fuel_x := 7.5 if code == "C" else 12.5
	for side: float in [-1.0, 1.0]:
		k.cyl(Vector3(side * fuel_x, 0.0, -2.5), Vector3(side * fuel_x, y + 0.02, -2.5), 0.55, 0.55, yellow, 12)
		k.cyl(Vector3(side * fuel_x, 0.0, -2.5), Vector3(side * fuel_x, y + 0.04, -2.5), 0.35, 0.35, Color(0.2, 0.2, 0.21), 12)
	k.box(Vector3(1.6, 0.0, stop - 8.0), Vector3(2.4, y + 0.03, stop - 7.2), Color(0.25, 0.26, 0.28))
	# Andockanzeige (VDGS) auf einem Mast am Kopf des Stands
	k.box(Vector3(-0.15, 0.0, hd - 0.7), Vector3(0.15, 4.6, hd - 0.4), Color(0.36, 0.41, 0.44))
	k.box(Vector3(-0.9, 4.6, hd - 1.0), Vector3(0.9, 6.4, hd - 0.3), Color(0.12, 0.12, 0.13))
	k.box(Vector3(-0.7, 4.8, hd - 1.05), Vector3(0.7, 6.2, hd - 1.0), Color(0.05, 0.05, 0.06))
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


## Fluggastbrücke, fester Teil (lokal +Z zeigt vom Terminal weg): Brückenkopf an der Fassade,
## verglaster Verbindungsgang und Rotunde auf einer Säule. Tunnel, Kabine und Fahrwerk bewegt terminal.gd.
static func _bridge_base(n: Node3D) -> void:
	var k := Kit.new()
	var grey := Color(0.74, 0.75, 0.76)
	var dark := Color(0.26, 0.27, 0.29)
	var glass := Color(0.22, 0.32, 0.38, 0.6)
	# Säule und Rotunde
	k.cyl(Vector3(0, 0, 0), Vector3(0, 0.4, 0), 1.2, 1.1, CONCRETE, 16)
	k.cyl(Vector3(0, 0.4, 0), Vector3(0, 3.0, 0), 0.75, 0.7, dark, 16)
	k.cyl(Vector3(0, 3.0, 0), Vector3(0, 6.1, 0), 2.1, 2.1, grey, 24)
	k.cyl(Vector3(0, 6.1, 0), Vector3(0, 6.35, 0), 2.2, 2.0, dark, 24)
	k.cyl(Vector3(0, 4.0, 0), Vector3(0, 5.1, 0), 2.12, 2.12, glass, 24, false)
	# Verbindungsgang zur Fassade mit Fensterband, Brückenkopf (Türrahmen) an der Wand
	k.box(Vector3(-1.45, 3.1, -4.7), Vector3(1.45, 6.0, -1.6), grey)
	k.box(Vector3(-1.47, 4.0, -4.6), Vector3(1.47, 5.1, -1.7), glass)
	k.box(Vector3(-1.55, 5.95, -4.75), Vector3(1.55, 6.15, -1.55), dark)
	k.box(Vector3(-1.9, 2.9, -4.8), Vector3(1.9, 6.4, -4.5), dark)
	k.box(Vector3(-1.2, 3.15, -4.52), Vector3(1.2, 5.6, -4.48), Color(0.55, 0.62, 0.66, 0.6))
	# Treppe vom Gang hinunter aufs Vorfeld (Personal), Geländer
	for i in range(8):
		var yy := 3.0 - float(i) * 0.375
		k.box(Vector3(1.5, yy - 0.06, -4.0 + float(i) * 0.33), Vector3(2.4, yy, -3.67 + float(i) * 0.33), dark)
	k.box(Vector3(2.38, 0.0, -4.0), Vector3(2.44, 3.9, -1.3), Color(0.85, 0.7, 0.15))
	n.add_child(k.instance("Brueckenkopf"))


## Flutlichtmast: Betonsockel, Gittermast, Plattform mit vier Scheinwerfern (leuchten nachts).
static func _floodlight(n: Node3D) -> void:
	var k := Kit.new()
	var steel := Color(0.6, 0.62, 0.64)
	k.cyl(Vector3(0, 0, 0), Vector3(0, 0.6, 0), 1.0, 0.9, CONCRETE, 12)
	for c: Vector2 in [Vector2(-0.4, -0.4), Vector2(0.4, -0.4), Vector2(0.4, 0.4), Vector2(-0.4, 0.4)]:
		k.box(Vector3(c.x - 0.06, 0.6, c.y - 0.06), Vector3(c.x * 0.6 + 0.06, 24.0, c.y * 0.6 + 0.06), steel)
	var y := 1.5
	while y < 23.5:
		k.box(Vector3(-0.42, y, -0.42), Vector3(0.42, y + 0.06, 0.42), steel)
		y += 2.5
	k.box(Vector3(-2.2, 24.0, -0.6), Vector3(2.2, 24.15, 0.9), steel)
	k.box(Vector3(-2.2, 24.15, -0.6), Vector3(2.2, 24.6, -0.55), steel)
	for sx: float in [-1.6, -0.55, 0.55, 1.6]:
		k.box(Vector3(sx - 0.45, 24.2, 0.1), Vector3(sx + 0.45, 25.0, 0.8), Color(0.25, 0.26, 0.28))
		k.box(Vector3(sx - 0.38, 24.28, 0.78), Vector3(sx + 0.38, 24.92, 0.84), Color(1.0, 0.96, 0.85, 0.3))
	k.cyl(Vector3(0, 25.0, 0), Vector3(0, 25.6, 0), 0.04, 0.04, steel, 6)
	k.box(Vector3(-0.1, 25.6, -0.1), Vector3(0.1, 25.8, 0.1), Color(1.0, 0.15, 0.1, 0.3))
	n.add_child(k.instance("Mast"))


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


## Bushaltestelle an der Straße (Straße vor der Vorderseite, -Z): Wartehäuschen mit Glas,
## Bank, Fahrplan, Haltestellenschild (grünes H auf Gelb) und beleuchteter Abfahrtsanzeige.
static func _city_stop(n: Node3D) -> void:
	var k := Kit.new()
	var steel := Color(0.36, 0.41, 0.44)
	var glass := Color(0.55, 0.72, 0.8, 0.6)
	# Bordstein und gepflasterte Wartefläche mit taktilen Leitstreifen
	k.box(Vector3(-8.0, 0.0, -2.0), Vector3(8.0, 0.18, 2.0), Color(0.66, 0.65, 0.61))
	k.box(Vector3(-8.0, 0.0, -2.0), Vector3(8.0, 0.2, -1.75), Color(0.75, 0.74, 0.7))
	k.box(Vector3(-7.0, 0.18, -1.45), Vector3(7.0, 0.2, -1.15), Color(0.85, 0.85, 0.82))
	for x in range(-7, 8):
		k.box(Vector3(float(x) - 0.02, 0.18, -2.0), Vector3(float(x) + 0.02, 0.19, 2.0), Color(0.58, 0.57, 0.53))
	# Wartehäuschen
	for sx: float in [-3.0, 3.0]:
		k.box(Vector3(sx - 0.06, 0.18, 0.4), Vector3(sx + 0.06, 2.55, 0.52), steel)
		k.box(Vector3(sx - 0.06, 0.18, 1.6), Vector3(sx + 0.06, 2.55, 1.72), steel)
		k.box(Vector3(sx - 0.03, 0.35, 0.55), Vector3(sx + 0.03, 2.3, 1.6), glass)
	k.box(Vector3(-3.0, 0.35, 1.62), Vector3(3.0, 2.3, 1.68), glass)
	k.box(Vector3(-3.2, 2.55, 0.2), Vector3(3.2, 2.68, 1.85), Color(0.86, 0.86, 0.84))
	k.box(Vector3(-3.2, 2.5, 0.2), Vector3(3.2, 2.55, 0.26), Color(0.16, 0.42, 0.25))
	# Bank und Fahrplanvitrine
	k.box(Vector3(-2.2, 0.62, 1.1), Vector3(1.0, 0.7, 1.5), Color(0.42, 0.31, 0.21))
	k.box(Vector3(-2.2, 0.7, 1.45), Vector3(1.0, 1.1, 1.52), Color(0.42, 0.31, 0.21))
	for x: float in [-2.0, -0.6, 0.8]:
		k.box(Vector3(x - 0.04, 0.18, 1.15), Vector3(x + 0.04, 0.62, 1.45), steel)
	k.box(Vector3(1.6, 1.0, 1.58), Vector3(2.7, 2.0, 1.62), Color(0.95, 0.95, 0.9, 0.3))
	# Abfahrtsanzeige (leuchtet)
	k.box(Vector3(-1.6, 2.15, 0.28), Vector3(1.6, 2.48, 0.34), Color(0.05, 0.05, 0.05))
	PixelFont.draw(k, "3 MIN", Vector3(0, 2.33, 0.27), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.035, Color(1.0, 0.7, 0.2, 0.3))
	# Haltestellenschild: grünes H im gelben Kreis
	k.cyl(Vector3(5.5, 0.18, -1.0), Vector3(5.5, 3.2, -1.0), 0.05, 0.05, steel, 8)
	k.cyl(Vector3(5.5, 2.85, -1.05), Vector3(5.5, 2.85, -0.97), 0.38, 0.38, Color(0.95, 0.82, 0.15), 16)
	k.cyl(Vector3(5.5, 2.85, -1.07), Vector3(5.5, 2.85, -1.05), 0.32, 0.32, Color(0.95, 0.82, 0.15), 16)
	PixelFont.draw(k, "H", Vector3(5.5, 2.85, -1.08), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.07, Color(0.1, 0.5, 0.25))
	PixelFont.draw(k, "H", Vector3(5.5, 2.85, -0.95), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.07, Color(0.1, 0.5, 0.25))
	k.box(Vector3(5.15, 2.2, -1.06), Vector3(5.85, 2.42, -0.95), Color(0.95, 0.95, 0.92))
	# Mülleimer
	k.cyl(Vector3(-5.0, 0.18, 1.2), Vector3(-5.0, 1.0, 1.2), 0.25, 0.25, Color(0.85, 0.45, 0.12), 10)
	n.add_child(k.instance("Haltestelle"))


## Gepäckumschlag: flache Halle mit Rolltoren zum Vorfeld, Förderbändern und Gepäckwagen davor.
static func _baggage_hall(n: Node3D) -> void:
	var k := Kit.new()
	var wall := Color(0.72, 0.73, 0.72)
	k.box(Vector3(-15, 0, -9), Vector3(15, 6.8, 9), wall)
	k.box(Vector3(-15.3, 6.8, -9.3), Vector3(15.3, 7.3, 9.3), Color(0.35, 0.36, 0.36))
	for x in range(-14, 15, 2):
		k.box(Vector3(float(x) - 0.04, 0.2, -9.03), Vector3(float(x) + 0.04, 6.6, -9.0), wall.darkened(0.1))
	# fünf Rolltore zum Vorfeld (-Z), eines halb offen mit Förderband
	for i in range(5):
		var x := -12.0 + float(i) * 6.0
		k.box(Vector3(x - 2.0, 0.0, -9.05), Vector3(x + 2.0, 4.2, -9.0), Color(0.55, 0.56, 0.58))
		for j in range(14):
			k.box(Vector3(x - 2.0, 0.2 + float(j) * 0.29, -9.07), Vector3(x + 2.0, 0.24 + float(j) * 0.29, -9.05), Color(0.48, 0.49, 0.5))
		k.box(Vector3(x - 2.3, 4.2, -9.2), Vector3(x + 2.3, 4.5, -9.0), Color(0.86, 0.69, 0.22))
		k.box(Vector3(x - 0.15, 4.6, -9.1), Vector3(x + 0.15, 4.8, -9.0), Color(1.0, 0.92, 0.7, 0.3))
	# Lichtband und Schrift
	k.box(Vector3(-14, 5.2, -9.04), Vector3(14, 6.0, -9.0), Color(0.2, 0.3, 0.36, 0.6))
	PixelFont.draw(k, "BAGGAGE", Vector3(0, 6.4, -9.05), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.12, Color(0.15, 0.2, 0.3))
	# Lüftung und Oberlichter auf dem Dach
	for x: float in [-9.0, 0.0, 9.0]:
		k.box(Vector3(x - 1.5, 7.3, -2.0), Vector3(x + 1.5, 8.2, 2.0), Color(0.6, 0.62, 0.63))
	n.add_child(k.instance("Halle"))
	var belt := make_gse("gepaeck")
	belt.position = Vector3(-6, 0, -12.5)
	belt.rotation.y = PI * 0.5
	n.add_child(belt)


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
	mi.mesh = Models.city_bus_mesh(Color(0.86, 0.72, 0.16)) if kind == "linienbus" else Models.car_mesh(kind, c)
	n.add_child(mi)
	# Bremslichter und Blinker als eigene leuchtende Teile, die der Verkehr ein- und ausschaltet
	var d: Array = Models.CAR_DIMS[kind]
	var hl: float = float(d[0]) * 0.5
	var hw: float = float(d[1]) * 0.5
	var belt := 0.92 if kind != "transporter" else (1.05 if kind != "linienbus" else 1.0)
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
		fan.position = Vector3(float(side[1]) * float(s["eng_x"]), float(s["eng_y"]), float(s["eng_z"]) + (-0.15 if bool(s.get("props", false)) else 0.42))
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
	if Furniture.build(n, id):
		return
	var opts: Dictionary = n.get_meta("opts", {})
	if id in ["rolltreppe", "aufzug", "treppe", "passkontrolle", "zoll"]:
		_inside_more(n, id)
		return
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
			_shop_sign(n, String(opts.get("stil", "cafe")))
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
			_shop_sign(n, String(opts.get("stil", "kiosk")))
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


## Ladenschild über der Front (leuchtend) mit Markenfarbe und Vordach, je nach Ladenart.
static func _shop_sign(n: Node3D, stil: String) -> void:
	var looks := {"cafe": ["CAFE", Color(0.45, 0.28, 0.18)], "baeckerei": ["BACKSTUBE", Color(0.75, 0.55, 0.25)],
		"bar": ["BAR", Color(0.15, 0.15, 0.22)], "restaurant": ["RESTAURANT", Color(0.55, 0.15, 0.15)],
		"kiosk": ["PRESSE", Color(0.15, 0.4, 0.6)], "dutyfree": ["DUTY FREE", Color(0.5, 0.35, 0.6)],
		"buecher": ["BUECHER", Color(0.2, 0.45, 0.3)], "elektronik": ["TECHNIK", Color(0.2, 0.2, 0.25)],
		"apotheke": ["APOTHEKE", Color(0.75, 0.15, 0.15)], "mode": ["MODE", Color(0.85, 0.85, 0.82)]}
	var e: Array = looks.get(stil, looks["cafe"])
	var k := Kit.new()
	var col: Color = e[1]
	k.box(Vector3(-3.9, 2.85, 2.7), Vector3(3.9, 3.45, 2.95), col)
	var txt := String(e[0])
	PixelFont.draw(k, txt, Vector3(0, 3.15, 2.97), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), minf(0.075, 6.6 / float(PixelFont.width(txt) * 1.0) * 0.1), Color(1.0, 0.95, 0.8, 0.3))
	# Markise in Streifen
	for i in range(8):
		var x := -3.9 + float(i) * 0.975
		k.quad(Vector3(x, 2.85, 2.95), Vector3(x + 0.975, 2.85, 2.95), Vector3(x + 0.975, 2.35, 3.6), Vector3(x, 2.35, 3.6),
			col if i % 2 == 0 else Color(0.95, 0.94, 0.9), Vector3(0, 0, 0))
	n.add_child(k.instance("Schild"))


## Rolltreppe, Aufzug, Treppe (verbinden mit der Ebene darüber), Passkontrolle und Zoll.
static func _inside_more(n: Node3D, id: String) -> void:
	var k := Kit.new()
	var steel := Color(0.7, 0.72, 0.74)
	var glass := Color(0.6, 0.78, 0.86, 0.6)
	var fh := Catalog.FLOOR_H
	match id:
		"rolltreppe":
			# Fachwerk-Unterbau, gläserne Balustraden, Handläufe; Stufen bewegt terminal.gd
			var slope := Basis(Vector3.RIGHT, -atan(fh / 8.0))
			var len := sqrt(64.0 + fh * fh)
			var mid := Vector3(0, fh * 0.5, 0)
			k.box(Vector3(-1.0, -0.6, -len * 0.5), Vector3(1.0, -0.05, len * 0.5), steel, Transform3D(slope, mid))
			for sx: float in [-0.95, 0.95]:
				k.box(Vector3(sx - 0.04, 0.0, -len * 0.5), Vector3(sx + 0.04, 0.95, len * 0.5), glass, Transform3D(slope, mid))
				k.box(Vector3(sx - 0.07, 0.95, -len * 0.5), Vector3(sx + 0.07, 1.05, len * 0.5), Color(0.12, 0.12, 0.13), Transform3D(slope, mid))
			k.box(Vector3(-1.0, 0, -5.0), Vector3(1.0, 0.08, -4.0), steel)
			k.box(Vector3(-1.0, fh - 0.05, 4.0), Vector3(1.0, fh + 0.05, 5.0), steel)
			var steps := Node3D.new()
			steps.name = "Stufen"
			steps.set_meta("no_bake", true)
			n.add_child(steps)
			var sk := Kit.new()
			for i in range(24):
				var t := float(i) / 24.0
				var p := Vector3(0, lerpf(0.05, fh, t), lerpf(-4.0, 4.0, t))
				sk.box(p + Vector3(-0.85, 0, -0.16), p + Vector3(0.85, 0.06, 0.16), Color(0.3, 0.31, 0.33) if i % 2 == 0 else Color(0.36, 0.37, 0.4))
			steps.add_child(sk.instance("StufenModell"))
		"aufzug":
			for c: Vector2 in [Vector2(-1.4, -1.4), Vector2(1.4, -1.4), Vector2(1.4, 1.4), Vector2(-1.4, 1.4)]:
				k.box(Vector3(c.x - 0.08, 0, c.y - 0.08), Vector3(c.x + 0.08, fh + 0.4, c.y + 0.08), steel)
			for e: Array in [[Vector3(-1.4, 0, -1.4), Vector3(1.4, fh + 0.4, -1.36)], [Vector3(-1.4, 0, 1.36), Vector3(1.4, fh + 0.4, 1.4)], [Vector3(-1.4, 0, -1.4), Vector3(-1.36, fh + 0.4, 1.4)]]:
				k.box(e[0], e[1], glass)
			k.box(Vector3(-1.5, fh + 0.4, -1.5), Vector3(1.5, fh + 0.6, 1.5), steel)
			var cab := Node3D.new()
			cab.name = "Kabine"
			cab.set_meta("no_bake", true)
			n.add_child(cab)
			var ck := Kit.new()
			ck.box(Vector3(-1.2, 0.0, -1.2), Vector3(1.2, 0.12, 1.2), steel)
			ck.box(Vector3(-1.2, 2.3, -1.2), Vector3(1.2, 2.45, 1.2), steel)
			ck.box(Vector3(-1.15, 2.2, -1.15), Vector3(1.15, 2.3, 1.15), Color(1.0, 0.95, 0.8, 0.3))
			for c: Vector2 in [Vector2(-1.15, -1.15), Vector2(1.15, -1.15), Vector2(-1.15, 1.15)]:
				ck.box(Vector3(c.x - 0.05, 0.1, c.y - 0.05), Vector3(c.x + 0.05, 2.3, c.y + 0.05), steel)
			cab.add_child(ck.instance("KabineModell"))
		"treppe":
			var nst := int(fh / 0.18)
			for i in range(nst):
				var y := float(i + 1) * fh / float(nst)
				var z := -4.0 + float(i) * 8.0 / float(nst)
				k.box(Vector3(-1.4, y - 0.18, z), Vector3(1.4, y, z + 8.0 / float(nst) + 0.02), Color(0.62, 0.6, 0.56))
			for sx: float in [-1.45, 1.45]:
				var slope := Basis(Vector3.RIGHT, -atan(fh / 8.0))
				var len := sqrt(64.0 + fh * fh)
				k.box(Vector3(sx - 0.04, 0.9, -len * 0.5), Vector3(sx + 0.04, 1.0, len * 0.5), Color(0.15, 0.15, 0.16), Transform3D(slope, Vector3(0, fh * 0.5, 0)))
				k.box(Vector3(sx - 0.03, 0.0, -len * 0.5), Vector3(sx + 0.03, 0.9, len * 0.5), glass, Transform3D(slope, Vector3(0, fh * 0.5, 0)))
		"passkontrolle":
			k.box(Vector3(-3, 0, -3), Vector3(3, 0.05, 3), Color(0.32, 0.34, 0.4))
			for i in range(3):
				var x := -2.0 + float(i) * 2.0
				# Kabine mit Glasaufsatz, Beamter in Uniform
				k.box(Vector3(x + 0.35, 0, -0.9), Vector3(x + 0.95, 1.15, 0.9), Color(0.85, 0.85, 0.83))
				k.box(Vector3(x + 0.35, 1.15, -0.9), Vector3(x + 0.95, 2.1, 0.9), glass)
				k.box(Vector3(x + 0.3, 2.1, -0.95), Vector3(x + 1.0, 2.2, 0.95), Color(0.2, 0.3, 0.55))
				var off := make_staff(Color(0.12, 0.2, 0.42), Color(0.1, 0.12, 0.2), i)
				off.position = Vector3(x + 0.65, 0, 0.2)
				off.rotation.y = -PI * 0.5
				n.add_child(off)
				# Spur mit Gurtpfosten
				for z: float in [-2.6, -1.4, 1.4, 2.6]:
					k.cyl(Vector3(x - 0.6, 0, z), Vector3(x - 0.6, 0.95, z), 0.05, 0.05, Color(0.15, 0.15, 0.16), 8)
				k.box(Vector3(x - 0.62, 0.86, -2.6), Vector3(x - 0.58, 0.92, 2.6), Color(0.2, 0.3, 0.6))
			k.box(Vector3(-2.9, 2.5, 2.9), Vector3(2.9, 3.1, 3.0), Color(0.2, 0.3, 0.55))
			PixelFont.draw(k, "POLIZEI", Vector3(0, 2.8, 3.02), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.07, Color(1, 1, 1, 0.3))
		"zoll":
			k.box(Vector3(-3, 0, -2.5), Vector3(3, 0.05, 2.5), Color(0.4, 0.4, 0.38))
			for e: Array in [[-1.5, Color(0.2, 0.62, 0.3), "GRUEN"], [1.5, Color(0.75, 0.18, 0.15), "ROT"]]:
				var x: float = e[0]
				k.box(Vector3(x - 1.3, 0.05, -2.4), Vector3(x + 1.3, 0.07, 2.4), (e[1] as Color).darkened(0.3))
				k.box(Vector3(x - 0.06, 0, 2.2), Vector3(x + 0.06, 2.6, 2.32), Color(0.2, 0.2, 0.22))
				k.box(Vector3(x - 1.0, 2.2, 2.3), Vector3(x + 1.0, 2.8, 2.36), e[1])
				PixelFont.draw(k, String(e[2]), Vector3(x, 2.5, 2.38), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.06, Color(1, 1, 1, 0.3))
			k.box(Vector3(1.0, 0, -0.6), Vector3(2.8, 0.9, 0.6), Color(0.85, 0.85, 0.83))
			var off := make_staff(Color(0.25, 0.35, 0.3), Color(0.12, 0.14, 0.12), 1)
			off.position = Vector3(2.2, 0, -1.0)
			n.add_child(off)
	n.add_child(k.instance("Ausstattung"))
