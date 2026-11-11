extends RefCounted
## Baut die sichtbaren Formen: Wege-Bänder, Gebäude, Deko und Fahrzeuge
## aus einfachen Grundkörpern (Low-Poly, später durch Blender-Modelle ersetzbar).

const Catalog = preload("res://scripts/catalog.gd")
const Spline = preload("res://scripts/spline.gd")
const LINE_SHADER = preload("res://shaders/line.gdshader")
const Models = preload("res://scripts/models.gd")
const Kit = preload("res://scripts/mesh_kit.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")
const Extras = preload("res://scripts/extras.gd")
const BeltAnim = preload("res://scripts/belt_anim.gd")
const Furniture = preload("res://scripts/furniture.gd")
const Landscape = preload("res://scripts/landscape.gd")
const Interior = preload("res://scripts/interior.gd")
const Buildings = preload("res://scripts/buildings.gd")
const Landmarks = preload("res://scripts/landmarks.gd")

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
	if kind == "kofferband":
		return _baggage_belt(samples)
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


## Kofferband im Terminal: Stahlrahmen auf Stützen, schwarzes Gurtband mit Rollenstößen,
## Seitenführungen; Koffer laufen darauf (belt_anim.gd).
static func _baggage_belt(s: PackedVector3Array) -> Node3D:
	var n := Node3D.new()
	n.name = "kofferband"
	var k := Kit.new()
	var steel := Color(0.42, 0.45, 0.48)
	var chrome := Color(0.74, 0.76, 0.79)
	var rubber := Color(0.08, 0.08, 0.09)
	# Mittellinie mit Höhen; an Knicken auf Gehrung geschnitten, damit Bögen ohne Lücken laufen
	var pts := PackedVector3Array()
	for v: Vector3 in s:
		var p := Vector3(v.x, v.y if v.y > 0.1 else 0.62, v.z)
		if pts.is_empty() or Vector2(p.x - pts[pts.size() - 1].x, p.z - pts[pts.size() - 1].z).length() > 0.05:
			pts.append(p)
	var cnt := pts.size()
	if cnt < 2:
		n.add_child(k.instance("Band"))
		return n
	var perp := []
	for i in range(cnt - 1):
		var d := Vector3(pts[i + 1].x - pts[i].x, 0, pts[i + 1].z - pts[i].z).normalized()
		perp.append(d.cross(Vector3.UP))
	var side := []
	for i in range(cnt):
		var a: Vector3 = perp[maxi(i - 1, 0)]
		var b: Vector3 = perp[mini(i, cnt - 2)]
		var m := (a + b).normalized()
		if m.length_squared() < 0.5:
			m = b
		side.append(m / maxf(0.5, m.dot(b)))
	# Querschnitt: Wanne (Stahl), Gurt (Gummi), zwei Seitenbleche (Chrom)
	_sweep(k, pts, side, -0.5, 0.5, -0.14, -0.02, steel, steel)
	_sweep(k, pts, side, -0.42, 0.42, -0.02, 0.0, rubber, rubber)
	_sweep(k, pts, side, -0.5, -0.45, -0.02, 0.16, chrome, chrome)
	_sweep(k, pts, side, 0.45, 0.5, -0.02, 0.16, chrome, chrome)
	# Stützen bzw. Abhängungen alle 2,4 m
	var run := 0.0
	var next_leg := 0.0
	for i in range(cnt - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var flat := Vector2(d.x, d.z).length()
		var sd: Vector3 = perp[i]
		while next_leg <= run + flat:
			var f := (next_leg - run) / maxf(flat, 0.001)
			var p := a.lerp(b, f)
			if p.y > 1.5:
				# unter der Decke: Abhängung an zwei Stangen bis zur Decke der Ebene
				for sx: float in [-0.45, 0.45]:
					var q := p + sd * sx
					k.box(Vector3(q.x - 0.025, p.y - 0.14, q.z - 0.025), Vector3(q.x + 0.025, 4.3, q.z + 0.025), steel)
			else:
				for sx: float in [-0.4, 0.4]:
					var q := p + sd * sx
					k.box(Vector3(q.x - 0.04, 0.0, q.z - 0.04), Vector3(q.x + 0.04, p.y - 0.14, q.z + 0.04), steel)
			next_leg += 2.4
		run += flat
	n.add_child(k.instance("Band"))
	return n


## Rechteckiger Querschnitt [x0..x1] x [y0..y1] entlang einer Mittellinie (Gehrungsvektoren side).
static func _sweep(k: Kit, pts: PackedVector3Array, side: Array, x0: float, x1: float, y0: float, y1: float, top: Color, col: Color) -> void:
	var cnt := pts.size()
	var ring := func(i: int) -> Array:
		var sd: Vector3 = side[i]
		var p := pts[i]
		return [p + sd * x0 + Vector3(0, y0, 0), p + sd * x1 + Vector3(0, y0, 0), p + sd * x1 + Vector3(0, y1, 0), p + sd * x0 + Vector3(0, y1, 0)]
	var xm := (x0 + x1) * 0.5
	var ym := (y0 + y1) * 0.5
	for i in range(cnt - 1):
		var ra: Array = ring.call(i)
		var rb: Array = ring.call(i + 1)
		var cen := (pts[i] + pts[i + 1]) * 0.5 + ((side[i] as Vector3) + (side[i + 1] as Vector3)) * 0.5 * xm + Vector3(0, ym, 0)
		k.quad(ra[3], rb[3], rb[2], ra[2], top, cen)
		k.quad(ra[0], ra[1], rb[1], rb[0], col, cen)
		k.quad(ra[1], ra[2], rb[2], rb[1], col, cen)
		k.quad(ra[0], rb[0], rb[3], ra[3], col, cen)
	for e: int in [0, cnt - 1]:
		var r: Array = ring.call(e)
		var c := pts[e] + (side[e] as Vector3) * xm + Vector3(0, ym, 0)
		var inward := (pts[1] - pts[0]) if e == 0 else (pts[cnt - 2] - pts[cnt - 1])
		k.quad(r[0], r[1], r[2], r[3], col, c + inward.normalized() * 0.5)


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
static func make_wall(kind: String, a: Vector3, b: Vector3, cuts: Array = []) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length := d.length()
	var mid := (a + b) * 0.5
	var basis := Basis.looking_at(d.normalized(), Vector3.UP) if length > 0.01 else Basis.IDENTITY
	var hl := length * 0.5 + 0.1
	# Türöffnungen: t ab dem Anfang a (lokal z = +L/2) → lokales z
	var holes := []
	var windows := []   # Öffnungen nur in einer Höhe (Kofferband): [z0, z1, y0, y1]
	for c: Array in cuts:
		holes.append([length * 0.5 - float(c[1]), length * 0.5 - float(c[0])])
		if c.size() >= 4:
			windows.append([length * 0.5 - float(c[1]), length * 0.5 - float(c[0]), float(c[2]), float(c[3])])
	holes.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
	var segs := []
	var z := -hl
	for hz: Array in holes:
		if float(hz[0]) > z + 0.02:
			segs.append([z, float(hz[0])])
		z = maxf(z, float(hz[1]))
	if z < hl - 0.02:
		segs.append([z, hl])
	var glass := kind == "glaswand"
	var wall_c := Color(0.9, 0.88, 0.83)
	var skirt := Color(0.4, 0.38, 0.35)
	var cap := Color(0.78, 0.77, 0.74)
	var rail := Color(0.62, 0.47, 0.3)
	var steel := Color(0.36, 0.39, 0.42)
	for part: Array in [["Hoch", 3.6], ["Tief", 1.2]]:
		var holder := Node3D.new()
		holder.name = String(part[0])
		holder.transform = Transform3D(basis, Vector3(mid.x, 0.0, mid.z))
		root.add_child(holder)
		var h: float = part[1]
		var k := Kit.new()
		var gk := Kit.new()
		for sg: Array in segs:
			var z0: float = sg[0]
			var z1: float = sg[1]
			if glass:
				k.box(Vector3(-0.08, 0, z0), Vector3(0.08, 0.12, z1), steel.darkened(0.2))
				k.box(Vector3(-0.07, h - 0.08, z0), Vector3(0.07, h, z1), steel)
				gk.box(Vector3(-0.02, 0.12, z0), Vector3(0.02, h - 0.08, z1), WHITE)
				for pz: float in [z0 + 0.03, z1 - 0.03]:
					k.box(Vector3(-0.05, 0.12, pz - 0.03), Vector3(0.05, h - 0.08, pz + 0.03), steel)
				var mz := z0 + 1.5
				while mz < z1 - 0.3:
					k.box(Vector3(-0.045, 0.12, mz - 0.025), Vector3(0.045, h - 0.08, mz + 0.025), steel)
					mz += 1.5
				if h > 1.6:
					# Sicherheitsmarkierung auf Augenhöhe (Pflicht bei Glaswänden)
					for my: float in [1.0, 1.55]:
						var dz := z0 + 0.15
						while dz < z1 - 0.15:
							k.box(Vector3(-0.025, my, dz), Vector3(0.025, my + 0.06, minf(dz + 0.18, z1 - 0.1)), Color(0.93, 0.93, 0.9))
							dz += 0.3
			else:
				k.box(Vector3(-0.1, 0, z0), Vector3(0.1, h, z1), wall_c)
				k.box(Vector3(-0.115, 0, z0), Vector3(0.115, 0.1, z1), skirt)
				k.box(Vector3(-0.11, h - 0.03, z0), Vector3(0.11, h, z1), cap)
				if h > 2.0:
					k.box(Vector3(-0.112, 0.95, z0), Vector3(0.112, 1.03, z1), rail)
					var jz := z0 + 1.25
					while jz < z1 - 0.3:
						k.box(Vector3(-0.102, 0.1, jz - 0.005), Vector3(0.102, h - 0.03, jz + 0.005), wall_c.darkened(0.06))
						jz += 1.25
		# Wandöffnung für ein Kofferband: unten und oben bleibt die Wand, Rahmen aus Stahl
		for wz: Array in windows:
			var z0: float = wz[0]
			var z1: float = wz[1]
			var y0: float = minf(float(wz[2]), h)
			var y1: float = minf(float(wz[3]), h)
			if glass:
				if y0 > 0.12:
					k.box(Vector3(-0.07, 0, z0), Vector3(0.07, 0.12, z1), steel.darkened(0.2))
					gk.box(Vector3(-0.02, 0.12, z0), Vector3(0.02, y0, z1), WHITE)
				if y1 < h:
					gk.box(Vector3(-0.02, y1, z0), Vector3(0.02, h - 0.08, z1), WHITE)
					k.box(Vector3(-0.07, h - 0.08, z0), Vector3(0.07, h, z1), steel)
			else:
				if y0 > 0.0:
					k.box(Vector3(-0.1, 0, z0), Vector3(0.1, y0, z1), wall_c)
					k.box(Vector3(-0.115, 0, z0), Vector3(0.115, minf(0.1, y0), z1), skirt)
				if y1 < h:
					k.box(Vector3(-0.1, y1, z0), Vector3(0.1, h, z1), wall_c)
					k.box(Vector3(-0.11, h - 0.03, z0), Vector3(0.11, h, z1), cap)
			if y0 < h:
				for zz: float in [z0, z1]:
					k.box(Vector3(-0.13, y0, zz - 0.04), Vector3(0.13, y1, zz + 0.04), steel)
				k.box(Vector3(-0.13, y0 - 0.04, z0), Vector3(0.13, y0, z1), steel)
				if y1 < h:
					k.box(Vector3(-0.13, y1, z0), Vector3(0.13, y1 + 0.04, z1), steel)
		# Sturz über den Türen (nur in voller Höhe)
		if h > 2.5:
			for hz: Array in holes:
				if windows.any(func(wz: Array) -> bool: return is_equal_approx(float(wz[0]), float(hz[0])) and is_equal_approx(float(wz[1]), float(hz[1]))):
					continue
				var z0: float = hz[0]
				var z1: float = hz[1]
				if glass:
					k.box(Vector3(-0.07, 2.4, z0), Vector3(0.07, 2.5, z1), steel)
					gk.box(Vector3(-0.02, 2.5, z0), Vector3(0.02, h - 0.08, z1), WHITE)
					k.box(Vector3(-0.07, h - 0.08, z0), Vector3(0.07, h, z1), steel)
				else:
					k.box(Vector3(-0.1, 2.4, z0), Vector3(0.1, h, z1), wall_c)
					k.box(Vector3(-0.11, h - 0.03, z0), Vector3(0.11, h, z1), cap)
		if k.count > 0:
			holder.add_child(k.instance("Wand"))
		if gk.count > 0:
			var gm := gk.instance("Glas")
			gm.material_override = glass_mat()
			gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(gm)
	return root


## Bodenbereich im Terminal: getönte Fläche mit gestricheltem Rand und Beschriftung.
static func make_zone(id: String, w: float, d: float) -> Node3D:
	var n := Node3D.new()
	n.name = id
	var zone := String(Catalog.ITEMS[id].get("zone", ""))
	var room := Catalog.room_of(id)
	var col: Color = {"oeffentlich": Color(0.35, 0.65, 0.95), "sicherheit": Color(0.98, 0.55, 0.15), "personal": Color(0.62, 0.42, 0.9)}.get(zone, Color.WHITE)
	if room != "":
		col = {"lager": Color(0.75, 0.6, 0.35), "kueche": Color(0.9, 0.35, 0.3), "sanitaet": Color(0.95, 0.95, 0.95),
			"pause": Color(0.45, 0.8, 0.45), "technik": Color(0.95, 0.85, 0.25)}.get(room, Color.WHITE)
	var k := Kit.new()
	var hw := w * 0.5
	var hd := d * 0.5
	var y := 0.125
	k.quad(Vector3(-hw, y, -hd), Vector3(hw, y, -hd), Vector3(hw, y, hd), Vector3(-hw, y, hd), Color(col.r, col.g, col.b, 0.3), Vector3(0, -1, 0))
	# gestrichelter Rand
	var e := 0.22
	for side: Array in [[Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd)], [Vector3(hw, 0, -hd), Vector3(hw, 0, hd)], [Vector3(hw, 0, hd), Vector3(-hw, 0, hd)], [Vector3(-hw, 0, hd), Vector3(-hw, 0, -hd)]]:
		var p0: Vector3 = side[0]
		var p1: Vector3 = side[1]
		var dir := (p1 - p0).normalized()
		var inward := Vector3(-dir.z, 0, dir.x)
		var length := p0.distance_to(p1)
		var t := 0.0
		while t < length:
			var t1 := minf(t + 0.8, length)
			var a := p0 + dir * t + Vector3(0, y + 0.004, 0)
			var b := p0 + dir * t1 + Vector3(0, y + 0.004, 0)
			k.quad(a, b, b + inward * e, a + inward * e, Color(col.r, col.g, col.b, 0.85), Vector3(0, -1, 0))
			t += 1.3
	var label: String = {"oeffentlich": "OEFFENTLICH", "sicherheit": "SICHERHEITSBEREICH", "personal": "NUR PERSONAL"}.get(zone, "")
	if room != "":
		label = {"lager": "LAGER", "kueche": "KUECHE", "sanitaet": "SANITAETSRAUM", "pause": "PAUSENRAUM", "technik": "TECHNIK"}.get(room, "")
	var px := minf(0.22, (w * 0.8) / maxf(float(PixelFont.width(label)), 1.0))
	if px > 0.04 and d > 1.5:
		PixelFont.draw_ground(k, label, Vector3(0, y + 0.006, 0), Vector3(0, 0, -1), px, Color(col.r, col.g, col.b, 0.7))
	var mi := k.instance("Flaeche")
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_is_srgb = true
	m.render_priority = 1
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	return n


## Terminalhalle w × d mit Bauformen (opts): Ebenen 1–3, Keller, Fassade (Glas, Beton, Holz),
## Ecken (eckig, abgerundet, rund), Dach (flach, Tonnendach, Sheddach).
## Knoten: "Ebene-1" … "Ebene2" (Böden), "Hoch" (volle Fassade), "Tief" (Brüstung für die Innenansicht), "Dach".
static func make_hall(w: float, d: float, opts: Dictionary = {}, cuts: Array = [], holes: Array = []) -> Node3D:
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
	# eigener Grundriss je Obergeschoss (kleiner als das Erdgeschoss möglich)
	var frs: Array = floor_rects(w, d, opts, levels)
	var rings: Array = []
	var ctrs: Array = []
	var stepped := false
	for f in range(levels):
		var fr: Rect2 = frs[f]
		if f > 0 and not fr.is_equal_approx(frs[0]):
			stepped = true
		rings.append(ring if fr.is_equal_approx(frs[0]) else _rect_ring(fr, radius))
		ctrs.append(fr.get_center())
	# Böden je Ebene mit Fugenraster
	for f in range(-1 if cellar else 0, levels):
		var slab := Node3D.new()
		slab.name = "Ebene%d" % f
		n.add_child(slab)
		var k := Kit.new()
		var y0 := float(f) * fh
		var fc := FLOOR if f != -1 else Color(0.6, 0.6, 0.58)
		# Deckenöffnungen über Rolltreppen und Treppen aus der Ebene darunter
		var hs: Array = []
		for hole: Array in holes:
			if int(hole[0]) == f:
				hs.append(hole[1])
		var fring: PackedVector2Array = rings[f] if f >= 0 else ring
		var frr: Rect2 = frs[f] if f >= 0 else frs[0]
		for piece: PackedVector2Array in _cut_holes(fring, hs):
			_polygon(k, piece, y0 - (0.25 if f != 0 else 0.0), y0 + 0.1, fc)
		var x := snappedf(frr.position.x + 2.0, 4.0) if f > 0 else -hw + 4.0
		while x < frr.end.x - 0.5:
			for seg: Vector2 in _free_spans(frr.position.y + radius * 0.3, frr.end.y - radius * 0.3, x, hs, true):
				k.box(Vector3(x - 0.04, y0 + 0.1, seg.x), Vector3(x + 0.04, y0 + 0.11, seg.y), fc.darkened(0.08))
			x += 4.0
		var z := snappedf(frr.position.y + 2.0, 4.0) if f > 0 else -hd + 4.0
		while z < frr.end.y - 0.5:
			for seg: Vector2 in _free_spans(frr.position.x + radius * 0.3, frr.end.x - radius * 0.3, z, hs, false):
				k.box(Vector3(seg.x, y0 + 0.1, z - 0.04), Vector3(seg.y, y0 + 0.11, z + 0.04), fc.darkened(0.08))
			z += 4.0
		# Glasbrüstung an den Längsseiten der Öffnung (die Stirnseiten bleiben für den Ein- und Ausstieg frei)
		for hole: Array in holes:
			if int(hole[0]) != f:
				continue
			var hr: Rect2 = hole[1]
			var along_x := int(hole[2]) % 2 == 1
			var sides := [[Vector2(hr.position.x, hr.position.y), Vector2(hr.end.x, hr.position.y)], [Vector2(hr.position.x, hr.end.y), Vector2(hr.end.x, hr.end.y)]] if along_x \
				else [[Vector2(hr.position.x, hr.position.y), Vector2(hr.position.x, hr.end.y)], [Vector2(hr.end.x, hr.position.y), Vector2(hr.end.x, hr.end.y)]]
			for sd: Array in sides:
				var a: Vector2 = sd[0]
				var b: Vector2 = sd[1]
				var lo := Vector3(minf(a.x, b.x) - 0.04, y0 + 0.1, minf(a.y, b.y) - 0.04)
				var hi := Vector3(maxf(a.x, b.x) + 0.04, y0 + 1.05, maxf(a.y, b.y) + 0.04)
				k.box(lo, hi, Color(0.62, 0.8, 0.88, 0.5))
				k.box(Vector3(lo.x - 0.02, hi.y, lo.z - 0.02), Vector3(hi.x + 0.02, hi.y + 0.06, hi.z + 0.02), Color(0.7, 0.72, 0.74))
			# Deckenstirn: dunkle Kante, damit die Öffnung als Loch erkennbar ist
			k.box(Vector3(hr.position.x, y0 - 0.25, hr.position.y), Vector3(hr.end.x, y0 - 0.2, hr.end.y), Color(0.3, 0.3, 0.32))
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
	_wall_ring(hk, ring, 0.0, 0.6, CONCRETE, 0.32, cuts)
	for f in range(levels):
		var y0 := 0.6 + float(f) * fh
		var y1 := float(f + 1) * fh + (4.6 - fh if f == levels - 1 else 0.0) - 1.4
		var fc: Array = cuts if f == 0 else []
		var rg: PackedVector2Array = rings[f]
		var cc: Vector2 = ctrs[f]
		if f > 0 and not (frs[f] as Rect2).is_equal_approx(frs[f - 1]):
			# zurückgesetztes Geschoss: Sockel über der Terrasse
			_wall_ring(hk, rg, float(f) * fh, y0, band, 0.3, [], cc)
		if facade == "glas":
			_wall_ring(hk, rg, y0, y1, GLASS, 0.24, fc, cc)
			_mullions(hk, rg, y0, y1, 2.0, Color(0.34, 0.38, 0.4), fc, cc)
			# Riegel der Pfosten-Riegel-Fassade
			var ty := y0 + 1.15
			while ty < y1 - 0.3:
				_wall_ring(hk, rg, ty, ty + 0.08, Color(0.36, 0.4, 0.42), 0.27, fc, cc)
				ty += 1.25
		else:
			_wall_ring(hk, rg, y0, y1, wall_col, 0.3, fc, cc)
			_wall_ring(hk, rg, y0 + 0.9, minf(y0 + 3.2, y1 - 0.2), GLASS, 0.34, fc, cc)
			_mullions(hk, rg, y0 + 0.9, minf(y0 + 3.2, y1 - 0.2), 1.6, band, fc, cc)
			if facade == "holz":
				_mullions(hk, rg, y1 - 0.9, y1, 0.5, band, fc, cc)
		var last := f == levels - 1
		var terrace := not last and not (frs[f + 1] as Rect2).is_equal_approx(frs[f])
		_wall_ring(hk, rg, y1, top if last else float(f + 1) * fh, band, 0.3, fc, cc)
		if terrace:
			# Dachterrasse über dem größeren Geschoss: Platte, Abdeckblech, Glasgeländer
			var tn := Node3D.new()
			tn.name = "Terrasse%d" % f
			n.add_child(tn)
			var tk := Kit.new()
			var ty0 := float(f + 1) * fh
			_polygon(tk, rg, ty0 - 0.35, ty0 + 0.04, ROOF)
			_wall_ring(tk, rg, ty0, ty0 + 0.12, Color(0.72, 0.73, 0.74), 0.34, [], cc)
			_wall_ring(tk, rg, ty0 + 0.12, ty0 + 1.05, Color(0.62, 0.8, 0.88, 0.5), 0.08, [], cc)
			_wall_ring(tk, rg, ty0 + 1.05, ty0 + 1.12, Color(0.7, 0.72, 0.74), 0.1, [], cc)
			tn.add_child(tk.instance("Terrasse"))
	# Laibungen und Stürze der Öffnungen (Eingänge, Brückenköpfe)
	for c: Array in cuts:
		var q: Vector2 = c[0]
		var nrm := _edge_normal(q, hw, hd)
		var along := Vector2(-nrm.y, nrm.x)
		var cw := float(c[1]) * 0.5
		var ch := float(c[2])
		for sgn: float in [-1.0, 1.0]:
			var e := q + along * (cw + 0.06) * sgn
			k_post(hk, Vector3(e.x, 0.0, e.y), nrm, ch + 0.15, Color(0.3, 0.33, 0.35))
		var l0 := q - along * (cw + 0.12)
		var l1 := q + along * (cw + 0.12)
		var inn := -nrm * 0.36
		hk.box(Vector3(minf(l0.x, l1.x + inn.x), ch, minf(l0.y, l1.y + inn.y)) - Vector3(0.02, 0, 0.02),
			Vector3(maxf(l0.x, l1.x + inn.x), ch + 0.18, maxf(l0.y, l1.y + inn.y)) + Vector3(0.02, 0, 0.02), Color(0.3, 0.33, 0.35))
	# Attika mit Abdeckblech, Schriftzug in feinen Pixeln
	var trr: Rect2 = frs[levels - 1]
	var tc := trr.get_center()
	_wall_ring(hk, rings[levels - 1], top - 0.08, top + 0.02, Color(0.72, 0.73, 0.74), 0.36, [], tc)
	if trr.size.x >= 30.0:
		var px := clampf(trr.size.x / 260.0, 0.12, 0.34) + 0.03 * float(levels - 1)
		PixelFont.draw(hk, "TERMINAL", Vector3(tc.x, top - 0.75, trr.end.y + 0.31), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), px, Color(0.14, 0.24, 0.45))
		if trr.size.x >= 120.0:
			PixelFont.draw(hk, "GATES", Vector3(tc.x, top - 0.75, trr.position.y - 0.31), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), px * 0.8, Color(0.14, 0.24, 0.45))
	high.add_child(hk.instance("Fassade"))
	if bool(opts.get("vordach", false)) and radius < 0.1:
		_canopy(n, hw, hd)
	# niedrige Brüstung für die Innenansicht
	var low := Node3D.new()
	low.name = "Tief"
	n.add_child(low)
	var lk := Kit.new()
	_wall_ring(lk, ring, 0.0, 0.6, CONCRETE, 0.3, cuts)
	_wall_ring(lk, ring, 0.6, 1.3, Color(0.55, 0.75, 0.85, 0.6), 0.32, cuts)
	_wall_ring(lk, ring, 1.3, 1.45, WALL, 0.34, cuts)
	for c: Array in cuts:
		var q2: Vector2 = c[0]
		var nrm2 := _edge_normal(q2, hw, hd)
		var along2 := Vector2(-nrm2.y, nrm2.x)
		for sgn: float in [-1.0, 1.0]:
			var e2 := q2 + along2 * (float(c[1]) * 0.5 + 0.06) * sgn
			k_post(lk, Vector3(e2.x, 0.0, e2.y), nrm2, 1.6, Color(0.3, 0.33, 0.35))
	low.add_child(lk.instance("Bruestung"))
	if stepped:
		# eigene Brüstung je abweichendem Obergeschoss (feste Höhe; die Halle blendet sie je Ebene ein)
		for f in range(1, levels):
			var tl := Node3D.new()
			tl.name = "TiefE%d" % f
			tl.position.y = float(f) * fh
			tl.visible = false
			n.add_child(tl)
			var tk2 := Kit.new()
			var rg2: PackedVector2Array = rings[f]
			var c2: Vector2 = ctrs[f]
			_wall_ring(tk2, rg2, 0.0, 0.6, CONCRETE, 0.3, [], c2)
			_wall_ring(tk2, rg2, 0.6, 1.3, Color(0.55, 0.75, 0.85, 0.6), 0.32, [], c2)
			_wall_ring(tk2, rg2, 1.3, 1.45, WALL, 0.34, [], c2)
			tl.add_child(tk2.instance("Bruestung"))
	# Dach
	var roof := Node3D.new()
	roof.name = "Dach"
	n.add_child(roof)
	var rk := Kit.new()
	if stepped:
		roof.position = Vector3(tc.x, 0, tc.y)
		hw = trr.size.x * 0.5
		hd = trr.size.y * 0.5
		w = trr.size.x
		d = trr.size.y
		radius = minf(radius, minf(w, d) * 0.45)
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


## Vordach über der Vorfahrt (Landseite +Z): schlanke Platte mit Stirnblech, Stützen, Downlights,
## Glaskante und Regenrinne. Bleibt auch in der Innenansicht stehen.
static func _canopy(n: Node3D, hw: float, hd: float) -> void:
	var k := Kit.new()
	var x0 := -hw + 3.0
	var x1 := hw - 3.0
	var z0 := hd
	var z1 := hd + 8.0
	var y := 4.6
	k.box(Vector3(x0, y, z0), Vector3(x1, y + 0.35, z1), Color(0.86, 0.87, 0.87))
	k.box(Vector3(x0 - 0.05, y + 0.05, z1 - 0.05), Vector3(x1 + 0.05, y + 0.55, z1 + 0.05), Color(0.18, 0.28, 0.45))
	k.box(Vector3(x0, y - 0.02, z0 + 0.3), Vector3(x1, y, z1 - 0.3), Color(0.8, 0.8, 0.79))
	var cx := x0 + 2.0
	while cx < x1 - 1.0:
		k.cyl(Vector3(cx, 0, z1 - 0.8), Vector3(cx, y, z1 - 0.8), 0.16, 0.14, Color(0.7, 0.72, 0.74), 12)
		k.cyl(Vector3(cx, 0, z1 - 0.8), Vector3(cx, 0.25, z1 - 0.8), 0.24, 0.24, Color(0.4, 0.42, 0.44), 12)
		cx += 12.0
	var lx := x0 + 1.0
	while lx < x1:
		for lz: float in [z0 + 2.5, z0 + 5.5]:
			k.cyl(Vector3(lx, y - 0.04, lz), Vector3(lx, y - 0.01, lz), 0.18, 0.18, Color(1.0, 0.93, 0.74, 0.3), 10)
		lx += 4.0
	k.box(Vector3(x0, y + 0.35, z1 - 0.5), Vector3(x1, y + 0.75, z1 - 0.35), Color(0.6, 0.78, 0.86, 0.6))
	for sx: float in [x0, x1]:
		k.cyl(Vector3(sx, y + 0.3, z1 - 0.3), Vector3(sx, 0.05, z1 - 0.3), 0.06, 0.06, Color(0.5, 0.52, 0.54), 8)
	var mi := k.instance("Vordach")
	mi.set_meta("no_bake", true)
	n.add_child(mi)


## Umriss eines Rechtecks mit gerundeten Ecken (gegen den Uhrzeigersinn), radius 0 = eckig.
## Grundriss je Ebene (lokal zur Hallenmitte): Ebene 0 ist die ganze Halle, höhere Ebenen aus opts "ebenen"
## {"1": [x0, z0, x1, z1], …}; ohne eigenen Eintrag erbt eine Ebene den Umriss darunter, nie größer als dieser.
static func floor_rects(w: float, d: float, opts: Dictionary, levels: int) -> Array:
	var out: Array = []
	var prev := Rect2(-w * 0.5, -d * 0.5, w, d)
	var eb: Dictionary = opts.get("ebenen", {})
	for f in range(maxi(levels, 1)):
		var r := prev
		if f > 0 and eb.has(str(f)):
			var a: Array = eb[str(f)]
			var cand := Rect2(float(a[0]), float(a[1]), float(a[2]) - float(a[0]), float(a[3]) - float(a[1])).intersection(prev)
			if cand.size.x >= 4.0 and cand.size.y >= 4.0:
				r = cand
		out.append(r)
		prev = r
	return out


static func _rect_ring(r: Rect2, radius: float) -> PackedVector2Array:
	var c := r.get_center()
	var out := PackedVector2Array()
	for q: Vector2 in _perimeter(r.size.x * 0.5, r.size.y * 0.5, minf(radius, minf(r.size.x, r.size.y) * 0.45)):
		out.append(q + c)
	return out


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


## Umriss ohne die Rechtecke holes: in einfache Teilstücke zerlegt (je Loch vier Streifen drumherum).
static func _cut_holes(ring: PackedVector2Array, holes: Array) -> Array:
	var pieces: Array = [ring]
	var big := 1e5
	for h: Rect2 in holes:
		var next: Array = []
		for pc: PackedVector2Array in pieces:
			var bb := Rect2(pc[0], Vector2.ZERO)
			for q: Vector2 in pc:
				bb = bb.expand(q)
			if not bb.intersects(h):
				next.append(pc)
				continue
			var regions := [Rect2(-big, -big, big * 2.0, h.position.y + big), Rect2(-big, h.end.y, big * 2.0, big),
				Rect2(-big, h.position.y, h.position.x + big, h.size.y), Rect2(h.end.x, h.position.y, big, h.size.y)]
			for rg: Rect2 in regions:
				var poly := PackedVector2Array([rg.position, Vector2(rg.end.x, rg.position.y), rg.end, Vector2(rg.position.x, rg.end.y)])
				for res: PackedVector2Array in Geometry2D.intersect_polygons(pc, poly):
					if res.size() >= 3:
						next.append(res)
		pieces = next
	return pieces


## Teilstrecken von a bis b auf der Linie bei c (quer = true: Linie entlang z bei x = c), ohne die Löcher.
static func _free_spans(a: float, b: float, c: float, holes: Array, quer: bool) -> Array:
	var spans: Array = [Vector2(a, b)]
	for h: Rect2 in holes:
		var lo := h.position.y if quer else h.position.x
		var hi := h.end.y if quer else h.end.x
		var cl := h.position.x if quer else h.position.y
		var ch := h.end.x if quer else h.end.y
		if c < cl or c > ch:
			continue
		var next: Array = []
		for sp: Vector2 in spans:
			if hi <= sp.x or lo >= sp.y:
				next.append(sp)
				continue
			if lo > sp.x:
				next.append(Vector2(sp.x, lo))
			if hi < sp.y:
				next.append(Vector2(hi, sp.y))
		spans = next
	return spans


## Wandring entlang des Umrisses (Dicke t, nach innen).
static func _wall_ring(k: Kit, ring: PackedVector2Array, y0: float, y1: float, col: Color, t: float, cuts: Array = [], ctr: Vector2 = Vector2.ZERO) -> void:
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
		var inward := Vector3(ctr.x - mid.x, 0, ctr.y - mid.y).normalized()
		var side := dir.cross(Vector3.UP)
		if side.dot(inward) < 0.0:
			side = -side
		var bas := Basis(dir, Vector3.UP, side)
		var xf := Transform3D(bas, Vector3(mid.x, 0, mid.y))
		var holes := _seg_cuts(a, b, cuts, y0)
		if holes.is_empty():
			k.box(Vector3(-len * 0.5 - 0.02, y0, 0.0), Vector3(len * 0.5 + 0.02, y1, t), col, xf)
			continue
		# Wand mit Öffnungen: volle Stücke dazwischen, über jeder Öffnung der Sturz
		var x := -len * 0.5 - 0.02
		for hole: Array in holes:
			var h0: float = float(hole[0]) - len * 0.5
			var h1: float = float(hole[1]) - len * 0.5
			if h0 > x:
				k.box(Vector3(x, y0, 0.0), Vector3(h0, y1, t), col, xf)
			if float(hole[2]) < y1:
				k.box(Vector3(h0, maxf(y0, float(hole[2])), 0.0), Vector3(h1, y1, t), col, xf)
			x = maxf(x, h1)
		if x < len * 0.5 + 0.02:
			k.box(Vector3(x, y0, 0.0), Vector3(len * 0.5 + 0.02, y1, t), col, xf)


## Außennormale der Hallenwand, auf der der lokale Punkt q liegt.
static func _edge_normal(q: Vector2, hw: float, hd: float) -> Vector2:
	var dx := hw - absf(q.x)
	var dz := hd - absf(q.y)
	if dz < dx:
		return Vector2(0, signf(q.y) if q.y != 0.0 else 1.0)
	return Vector2(signf(q.x) if q.x != 0.0 else 1.0, 0)


## Pfosten einer Laibung (0,24 m tief, bündig mit der Wand nach innen).
static func k_post(k: Kit, p: Vector3, nrm: Vector2, h: float, col: Color) -> void:
	var inn := Vector3(-nrm.x, 0, -nrm.y) * 0.4
	var a := p + Vector3(nrm.x, 0, nrm.y) * 0.04
	var b := p + inn
	k.box(Vector3(minf(a.x, b.x) - 0.08, 0.0, minf(a.z, b.z) - 0.08), Vector3(maxf(a.x, b.x) + 0.08, h, maxf(a.z, b.z) + 0.08), col)


## Öffnungen auf dem Wandstück a–b: [von, bis (Abstand ab a), Höhe], nur die, die über y0 hinausreichen.
## cuts: [Mitte (lokal, auf der Wand), Breite, Höhe].
static func _seg_cuts(a: Vector2, b: Vector2, cuts: Array, y0: float) -> Array:
	var out := []
	if cuts.is_empty():
		return out
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return out
	var dn := d / len
	for c: Array in cuts:
		if float(c[2]) <= y0 + 0.01:
			continue
		var q: Vector2 = c[0]
		var s := (q - a).dot(dn)
		var off := absf((q - a).dot(Vector2(-dn.y, dn.x)))
		if off > 0.6 or s < 0.0 or s > len:
			continue
		var hw := float(c[1]) * 0.5
		out.append([clampf(s - hw, 0.0, len), clampf(s + hw, 0.0, len), float(c[2])])
	out.sort_custom(func(u: Array, v: Array) -> bool: return float(u[0]) < float(v[0]))
	return out


## Senkrechte Sprossen alle step Meter entlang des Umrisses.
static func _mullions(k: Kit, ring: PackedVector2Array, y0: float, y1: float, step: float, col: Color, cuts: Array = [], ctr: Vector2 = Vector2.ZERO) -> void:
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var len := a.distance_to(b)
		var nseg := maxi(1, int(len / step))
		var holes := _seg_cuts(a, b, cuts, y0)
		for j in range(nseg + 1):
			var sj := len * float(j) / float(nseg)
			var cut := false
			for hole: Array in holes:
				if sj > float(hole[0]) - 0.1 and sj < float(hole[1]) + 0.1:
					cut = true
			if cut:
				continue
			var p := a.lerp(b, float(j) / float(nseg))
			var outv := (p - ctr).normalized()
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
	if Catalog.is_zone(id):
		return make_zone(id, 4.0, 4.0)
	var n := _make_item_raw(id, opts)
	bake(n)
	return n


static func _make_item_raw(id: String, opts: Dictionary = {}) -> Node3D:
	var n := Node3D.new()
	n.name = id
	n.set_meta("opts", opts)
	if Extras.build(n, id):
		return n
	if Catalog.is_inside(id):
		_inside(n, id)
		return n
	if Landscape.build(n, id):
		return n
	if Buildings.build(n, id) or Landmarks.build(n, id):
		return n
	match id:
		"baum":
			_baum(n)
		"stand":
			_stand(n, false, "stand")
		"stand_aussen":
			_stand(n, true, "stand_aussen")
		"stand_gross":
			_stand(n, false, "stand_gross")
		"stand_f":
			_stand(n, false, "stand_f")
		"bushalt":
			_bus_stop(n)
		"haltestelle":
			_city_stop(n)
		"vorfeldflaeche":
			_apron_area(n, float(opts.get("w", 20.0)), float(opts.get("d", 20.0)))
		"gepaeckumschlag":
			if Catalog.tore_of("gepaeckumschlag", opts) > 0:
				Landmarks.sized_hall(n, "gepaeckumschlag", opts)
			else:
				_baggage_hall(n)
		"flutlicht":
			_floodlight(n)
		"fluggastbruecke":
			_bridge_base(n)
		"befeuerungsstation":
			_light_station(n)
		"rollhalt", "papi", "anflugbefeuerung", "wendeplatte":
			_marker_base(n, id)
	return n


## Befeuerungsstation: Betonbau mit Lüftungsgittern, Stahltüren, Klimageräten, Kabelschacht und Schild.
static func _light_station(n: Node3D) -> void:
	var k := Kit.new()
	var wall := Color(0.78, 0.77, 0.73)
	var dark := Color(0.3, 0.31, 0.33)
	k.box(Vector3(-6.2, 0, -3.7), Vector3(6.2, 0.25, 3.7), CONCRETE)
	k.box(Vector3(-6.0, 0.25, -3.5), Vector3(6.0, 3.6, 3.5), wall)
	k.box(Vector3(-6.15, 3.6, -3.65), Vector3(6.15, 3.85, 3.65), Color(0.55, 0.56, 0.57))
	k.box(Vector3(-6.0, 3.85, -3.5), Vector3(6.0, 3.95, 3.5), ROOF)
	# zwei Stahltüren, Lüftungsgitter, Schild mit Warnsymbol
	for x: float in [-3.5, 2.0]:
		k.box(Vector3(x - 0.6, 0.25, 3.5), Vector3(x + 0.6, 2.45, 3.56), Color(0.42, 0.46, 0.5))
		k.box(Vector3(x + 0.35, 1.2, 3.56), Vector3(x + 0.45, 1.3, 3.6), Color(0.8, 0.8, 0.8))
	for x: float in [-1.2, 4.3]:
		for i in range(6):
			k.box(Vector3(x - 0.6, 2.2 + float(i) * 0.18, 3.5), Vector3(x + 0.6, 2.28 + float(i) * 0.18, 3.6), dark)
	k.box(Vector3(-0.6, 2.7, 3.51), Vector3(0.6, 3.3, 3.58), Color(0.95, 0.8, 0.15))
	k.prism([Vector3(-0.25, 2.8, 3.585), Vector3(0.25, 2.8, 3.585), Vector3(0.25, 2.8, 3.6), Vector3(-0.25, 2.8, 3.6)],
		[Vector3(-0.02, 3.2, 3.585), Vector3(0.02, 3.2, 3.585), Vector3(0.02, 3.2, 3.6), Vector3(-0.02, 3.2, 3.6)], Color(0.1, 0.1, 0.1))
	# Klimageräte auf dem Dach, Kabelschacht, Lampe über der Tür
	for x: float in [-3.0, 0.5]:
		k.box(Vector3(x - 1.0, 3.95, -1.5), Vector3(x + 1.0, 4.7, -0.3), Color(0.82, 0.83, 0.84))
		k.cyl(Vector3(x, 4.7, -0.9), Vector3(x, 4.75, -0.9), 0.45, 0.45, dark, 12)
	k.box(Vector3(-5.5, 0.0, 3.7), Vector3(-4.3, 0.12, 5.2), Color(0.4, 0.4, 0.42))
	for x: float in [-3.5, 2.0]:
		k.box(Vector3(x - 0.2, 2.6, 3.56), Vector3(x + 0.2, 2.75, 3.75), Color(1.0, 0.92, 0.7, 0.3))
	PixelFont.draw(k, "BEFEUERUNG", Vector3(0, 3.42, 3.62), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.07, Color(0.15, 0.2, 0.35))
	n.add_child(k.instance("Station"))


## Rollhalt, PAPI und Anflugbefeuerung zeichnet das Flugfeld (ausgerichtet an Piste oder Rollweg).
## Hier nur ein kleiner Sockel, damit man das Teil anklicken und in der Vorschau sehen kann.
static func _marker_base(n: Node3D, id: String) -> void:
	var k := Kit.new()
	match id:
		"rollhalt":
			k.cyl(Vector3(0, 0, 0), Vector3(0, 0.07, 0), 1.2, 1.2, Color(0.88, 0.7, 0.18), 16)
			k.cyl(Vector3(0, 0.07, 0), Vector3(0, 0.08, 0), 0.6, 0.6, Color(0.72, 0.1, 0.08), 16)
		"papi":
			k.box(Vector3(-1.5, 0, -1.5), Vector3(1.5, 0.3, 1.5), CONCRETE)
		"wendeplatte":
			# Belag und Markierung zeichnet airfield.gd; hier nur ein flacher Griff zum Anklicken
			k.cyl(Vector3(0, 0, 0), Vector3(0, 0.03, 0), 2.0, 2.0, Color(0.3, 0.3, 0.29), 16)
		_:
			k.box(Vector3(-2.0, 0, -2.0), Vector3(2.0, 0.3, 2.0), CONCRETE)
			k.box(Vector3(-0.6, 0.3, -0.6), Vector3(0.6, 1.6, 0.6), Color(0.85, 0.85, 0.82))
	n.add_child(k.instance("Sockel"))


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
	# Markierung "voll": wie bisher; "eigene": keine gelbe Mittellinie (Rollführungslinien zeichnet der
	# Spieler mit dem Werkzeug Rolllinie); "aus": nur Andockanzeige, Betankung und Bodenstrom
	var mark := String((n.get_meta("opts", {}) as Dictionary).get("markierung", "eigene"))
	var flat := func(a: Vector2, b: Vector2, c: Color) -> void:
		if mark == "aus":
			return
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
		if mark != "aus":
			PixelFont.draw_ground(k, txt, Vector3(sx * (2.4 + float(PixelFont.width(txt)) * 0.08), y + 0.01, z), Vector3(0, 0, 1), 0.16, yellow)
		side_i += 1
	# Mittellinie bis hinter die Haltebalken
	if mark == "voll":
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
		if mark != "aus":
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
		if mark != "aus":
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
	var steg := float(int((n.get_meta("opts", {}) as Dictionary).get("steg", 0)))
	var k := Kit.new()
	var grey := Color(0.74, 0.75, 0.76)
	var dark := Color(0.26, 0.27, 0.29)
	var glass := Color(0.22, 0.32, 0.38, 0.6)
	var steel := Color(0.36, 0.38, 0.4)
	# Rotunde auf Säule: Drehpunkt des Teleskoptunnels
	k.cyl(Vector3(0, 0, 0), Vector3(0, 0.4, 0), 1.2, 1.1, CONCRETE, 16)
	k.cyl(Vector3(0, 0.4, 0), Vector3(0, 3.0, 0), 0.75, 0.7, dark, 16)
	k.cyl(Vector3(0, 3.0, 0), Vector3(0, 6.1, 0), 2.1, 2.1, grey, 24)
	k.cyl(Vector3(0, 6.1, 0), Vector3(0, 6.35, 0), 2.2, 2.0, dark, 24)
	k.cyl(Vector3(0, 4.0, 0), Vector3(0, 5.1, 0), 2.12, 2.12, glass, 24, false)
	var rot_k := k
	# Treppenturm direkt an der Fassade (lokal -Z = Wand bei z = -4,8 - Steg): Glaskasten mit Treppe
	# und Aufzug, unten offen zur Halle. Er füllt die Öffnung in der Hallenwand.
	k = Kit.new()
	var z0 := -4.85
	var z1 := -2.2
	k.box(Vector3(-2.0, 0.0, z0), Vector3(2.0, 0.12, z1), CONCRETE)
	for c: Vector2 in [Vector2(-1.95, z1 + 0.05), Vector2(1.95, z1 + 0.05), Vector2(-1.95, z0 + 0.05), Vector2(1.95, z0 + 0.05)]:
		k.box(Vector3(c.x - 0.08, 0.0, c.y - 0.08), Vector3(c.x + 0.08, 6.4, c.y + 0.08), steel)
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 1.95 - 0.03, 0.12, z0 + 0.1), Vector3(sx * 1.95 + 0.03, 6.0, z1 - 0.1), glass)
		for yy: float in [1.5, 3.0, 4.5]:
			k.box(Vector3(sx * 1.95 - 0.05, yy, z0), Vector3(sx * 1.95 + 0.05, yy + 0.07, z1), steel)
	# Vorderseite zur Rotunde: unten Glas, oben der Übergang
	k.box(Vector3(-1.9, 0.12, z1 - 0.04), Vector3(1.9, 3.0, z1 + 0.02), glass)
	k.box(Vector3(-2.05, 6.0, z0 - 0.05), Vector3(2.05, 6.45, z1 + 0.1), grey)
	k.box(Vector3(-2.1, 6.45, z0 - 0.1), Vector3(2.1, 6.55, z1 + 0.15), dark)
	# Zwischenpodest auf Höhe des Tunnels und Treppe hinunter zur Halle
	k.box(Vector3(-1.9, 2.9, -3.3), Vector3(1.9, 3.05, z1), Color(0.55, 0.56, 0.57))
	for i in range(11):
		var x := -1.7 + float(i) * 0.27
		var y := 0.12 + float(i + 1) * 0.255
		k.box(Vector3(x, y - 0.06, -4.6), Vector3(x + 0.3, y, -3.4), Color(0.6, 0.6, 0.6))
	k.box(Vector3(-1.75, 0.12, -3.42), Vector3(1.3, 1.1, -3.38), steel)
	# Aufzugsschacht mit Kabine, die auf und ab fährt
	k.box(Vector3(0.95, 0.12, -4.75), Vector3(1.85, 6.0, -4.72), Color(0.3, 0.32, 0.34))
	var lift := Kit.new()
	lift.box(Vector3(-0.42, 0.0, -0.4), Vector3(0.42, 2.2, 0.4), Color(0.78, 0.8, 0.82))
	lift.box(Vector3(-0.38, 0.4, 0.4), Vector3(0.38, 2.0, 0.42), glass)
	var cab := lift.instance("HubAufzug")
	cab.position = Vector3(1.4, 0.15, -4.25 - steg)
	cab.set_meta("lift", 2.85)
	cab.set_meta("speed", 0.25)
	cab.set_meta("no_bake", true)
	n.add_child(cab)
	# Schriftfeld GATE über der Öffnung, Notausgangsleuchte
	k.box(Vector3(-1.2, 5.2, z1 + 0.02), Vector3(1.2, 5.8, z1 + 0.08), Color(0.14, 0.24, 0.45))
	k.box(Vector3(-0.9, 5.35, z1 + 0.08), Vector3(0.9, 5.65, z1 + 0.1), Color(1.0, 0.95, 0.8, 0.3))
	k.box(Vector3(-0.3, 2.55, z0 - 0.06), Vector3(0.3, 2.75, z0), Color(0.2, 0.85, 0.4, 0.3))
	rot_k.add_mesh(k.commit(), Transform3D(Basis(), Vector3(0, 0, -steg)))
	k = rot_k
	# Übergang Turm – Rotunde; mit Steg ein Fachwerk-Glasgang über Straße oder Betriebsstraße
	var za := z1 - steg
	k.box(Vector3(-1.45, 3.05, za), Vector3(1.45, 6.0, -1.6), grey)
	k.box(Vector3(-1.47, 4.0, za + 0.05), Vector3(1.47, 5.1, -1.7), glass)
	if steg > 0.0:
		k.box(Vector3(-1.5, 2.75, za), Vector3(1.5, 3.05, -1.6), dark)
		var zz := za
		while zz < -1.9:
			var zn := minf(zz + 3.0, -1.6)
			for sx: float in [-1.5, 1.5]:
				k.cyl(Vector3(sx, 2.9, zz), Vector3(sx, 4.0, zn), 0.05, 0.05, steel, 5)
			zz = zn
	# Personaltreppe von der Rotunde hinunter aufs Vorfeld mit Geländer
	for i in range(8):
		var yy := 3.0 - float(i) * 0.375
		k.box(Vector3(2.15, yy - 0.06, -1.2 + float(i) * 0.33), Vector3(3.05, yy, -0.87 + float(i) * 0.33), dark)
	k.box(Vector3(3.05, 0.0, -1.2), Vector3(3.11, 3.9, 1.5), Color(0.85, 0.7, 0.15))
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
	# nachts: Lichtfeld auf dem Vorfeld vor den Scheinwerfern
	var pool := light_pool(62.0, 8.0, 52.0, 0.42)
	pool.rotation.y = PI
	pool.position = Vector3(0, 0.14, 1.0)
	n.add_child(pool)


## Vorfeld-Haltestelle: Haltebucht mit Bordstein, Wartedach mit Glaswänden, Haltestellenschild.
static func _bus_stop(n: Node3D) -> void:
	var k := Kit.new()
	var white := Color(0.88, 0.88, 0.85)
	var y := 0.05
	# Belag der Bucht mit schrägen Ein- und Ausfahrten (auch neben einer Betriebsstraße auf Rasen)
	k.prism([Vector3(-19.0, 0.0, -3.6), Vector3(19.0, 0.0, -3.6), Vector3(14.5, 0.0, 2.2), Vector3(-14.5, 0.0, 2.2)],
		[Vector3(-19.0, 0.035, -3.6), Vector3(19.0, 0.035, -3.6), Vector3(14.5, 0.035, 2.2), Vector3(-14.5, 0.035, 2.2)], Color(0.26, 0.255, 0.24))
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
	# Rückseite und Giebel: Paneelfugen, Fensterband, Notausgänge, Fallrohre, Sockel
	k.box(Vector3(-15.05, 0, -9.05), Vector3(15.05, 0.5, 9.05), Color(0.55, 0.55, 0.53))
	for x in range(-14, 15, 2):
		k.box(Vector3(float(x) - 0.04, 0.5, 9.0), Vector3(float(x) + 0.04, 6.6, 9.03), wall.darkened(0.1))
	for z in range(-8, 9, 2):
		for sx: float in [-15.03, 15.0]:
			k.box(Vector3(sx, 0.5, float(z) - 0.04), Vector3(sx + 0.03, 6.6, float(z) + 0.04), wall.darkened(0.1))
	k.box(Vector3(-14.0, 4.6, 9.0), Vector3(14.0, 5.6, 9.05), Color(0.2, 0.3, 0.36, 0.6))
	for x in range(-13, 14, 3):
		k.box(Vector3(float(x) - 0.05, 4.6, 9.05), Vector3(float(x) + 0.05, 5.6, 9.07), wall)
	for x: float in [-10.0, 10.0]:
		k.box(Vector3(x - 0.6, 0.5, 9.0), Vector3(x + 0.6, 2.7, 9.08), Color(0.25, 0.5, 0.35))
		k.box(Vector3(x - 0.4, 2.8, 9.05), Vector3(x + 0.4, 3.0, 9.1), Color(0.15, 0.75, 0.35, 0.3))
	for x: float in [-14.6, -5.0, 5.0, 14.6]:
		k.box(Vector3(x - 0.09, 0.0, 9.03), Vector3(x + 0.09, 7.0, 9.2), Color(0.5, 0.52, 0.54))
	k.box(Vector3(-15.3, 6.6, 9.1), Vector3(15.3, 6.9, 9.35), Color(0.5, 0.52, 0.54))
	# Lüftung und Oberlichter auf dem Dach
	for x: float in [-9.0, 0.0, 9.0]:
		k.box(Vector3(x - 1.5, 7.3, -2.0), Vector3(x + 1.5, 8.2, 2.0), Color(0.6, 0.62, 0.63))
		for i in range(6):
			k.box(Vector3(x - 1.45, 7.45 + float(i) * 0.12, 2.0), Vector3(x + 1.45, 7.5 + float(i) * 0.12, 2.04), Color(0.4, 0.42, 0.44))
	for x: float in [-12.0, -5.0, 5.0, 12.0]:
		k.box(Vector3(x - 1.0, 7.3, 4.0), Vector3(x + 1.0, 7.6, 7.5), Color(0.6, 0.75, 0.82, 0.6))
	n.add_child(k.instance("Halle"))
	var belt := make_gse("gepaeck")
	belt.position = Vector3(-6, 0, -12.5)
	belt.rotation.y = PI * 0.5
	n.add_child(belt)


static func make_gse(kind: String) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Models.gse_mesh(kind)
	n.add_child(mi)
	return n


## Auto in zufälliger Bauart (Kleinwagen, Limousine, Kombi, SUV, Transporter, Taxi).
## Türflügel eines Busses stellen (0 zu, 1 offen): erst ausschwenken, dann auseinandergleiten.
static func set_bus_doors(node: Node3D, open: float) -> void:
	var body := node.get_node_or_null("Body")
	if body == null:
		return
	var e := smoothstep(0.0, 1.0, open)
	var out := clampf(e * 3.0, 0.0, 1.0)
	var slide := clampf(e * 1.5 - 0.5, 0.0, 1.0)
	for leaf: Node in body.get_children():
		if leaf.name.begins_with("Tuer") and leaf.has_meta("slide"):
			var sl: Vector3 = leaf.get_meta("slide")
			(leaf as Node3D).position = (leaf.get_meta("base") as Vector3) + Vector3(sl.x * out, 0, sl.z * slide)


static func make_car(c: Color, kind: String = "") -> Node3D:
	if kind == "":
		var r := randf()
		kind = "kompakt" if r < 0.25 else "limousine" if r < 0.45 else "kombi" if r < 0.65 else "suv" if r < 0.82 else "transporter" if r < 0.93 else "taxi"
	var n := Node3D.new()
	n.set_meta("kind", kind)
	var mi := MeshInstance3D.new()
	mi.mesh = Models.city_bus_mesh(Color(0.86, 0.72, 0.16)) if kind == "linienbus" else Models.car_mesh(kind, c)
	mi.name = "Body"
	n.add_child(mi)
	if kind == "linienbus":
		# Doppeltüren rechts: Flügel schwenken an der Haltestelle nach außen und gleiten auf
		var li := 0
		for dz: float in Models.CITY_BUS_DOORS:
			for half: float in [-1.0, 1.0]:
				var leaf := MeshInstance3D.new()
				leaf.mesh = Models.bus_door_leaf(2.1, 0.62)
				leaf.name = "Tuer%d" % li
				li += 1
				leaf.position = Vector3(1.27, 0.4, dz + half * 0.31)
				leaf.set_meta("base", leaf.position)
				leaf.set_meta("slide", Vector3(0.14, 0, half * 0.34))
				mi.add_child(leaf)
	# Bremslichter und Blinker als eigene leuchtende Teile, die der Verkehr ein- und ausschaltet
	var d: Array = Models.CAR_DIMS[kind]
	var pool := light_pool(14.0 if kind != "linienbus" else 18.0, float(d[1]) * 0.8, float(d[1]) * 3.2)
	pool.position = Vector3(0, 0.08, -float(d[0]) * 0.5 - 0.3)
	n.add_child(pool)
	var hl: float = float(d[0]) * 0.5
	var hw: float = float(d[1]) * 0.5
	var belt := Models.car_light_y(kind) + 0.16
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
static func make_plane(kind: String, livery: Color, style: int = 0, cargo: bool = false) -> Node3D:
	var n := Node3D.new()
	n.name = kind
	var s: Dictionary = Models.SPECS.get(kind, Models.SPECS["a320"])
	var mi := MeshInstance3D.new()
	mi.name = "Rumpf"
	mi.mesh = Models.plane_mesh(kind, livery, style, cargo)
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
		if s.has("eng2"):
			var e2: Array = s["eng2"]
			var fan2 := MeshInstance3D.new()
			fan2.name = String(side[0]) + "2"
			fan2.mesh = Models.fan_mesh(kind)
			fan2.position = Vector3(float(side[1]) * float(e2[0]), float(e2[1]), float(e2[2]) + 0.42)
			n.add_child(fan2)
	# Landeklappen (je Seite innen und außen) und Spoiler als bewegliche Teile
	if true:
		for side: float in [-1.0, 1.0]:
			for inner: bool in [true, false]:
				var fp: Array = Models.flap_part(kind, side, inner)
				var fl := MeshInstance3D.new()
				fl.name = "Klappe%s%s" % ["L" if side < 0.0 else "R", "i" if inner else "a"]
				fl.mesh = fp[0]
				fl.position = fp[1]
				fl.set_meta("hinge", fp[1])
				fl.set_meta("axis", fp[2])
				fl.set_meta("chord", fp[3])
				n.add_child(fl)
			var sp: Array = Models.spoiler_part(kind, side)
			var spo := MeshInstance3D.new()
			spo.name = "Spoiler%s" % ("L" if side < 0.0 else "R")
			spo.mesh = sp[0]
			spo.position = sp[1]
			spo.set_meta("hinge", sp[1])
			spo.set_meta("axis", sp[2])
			n.add_child(spo)
	var cy: float = s["cy"]
	var r: float = s["r"]
	# Lande- und Rollscheinwerfer: an der Flügelwurzel und am Bugfahrwerk
	var land := Node3D.new()
	land.name = "Landelicht"
	land.visible = false
	n.add_child(land)
	var wr: Array = Models._wing_at(s, float(s["r"]) * 1.15)
	for sx: float in [-1.0, 1.0]:
		_glow(land, Vector3(sx * float(s["r"]) * 1.15, float(wr[1]) - 0.05, float(wr[0]) - 0.02), Vector3(0.35, 0.2, 0.1), Color(1.0, 0.97, 0.85))
	_glow(land, Vector3(0, cy - r + 0.05, float(s["nose_gear_z"]) - 0.3), Vector3(0.3, 0.2, 0.1), Color(1.0, 0.97, 0.85))
	# Lichtkegel in der Luft: von der Flügelwurzel nach vorn und 7° nach unten (flights.gd regelt die Stärke)
	var cone := MeshInstance3D.new()
	cone.name = "Lichtkegel"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 11.0
	cm.height = 110.0
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	cone.mesh = cm
	cone.material_override = cone_material()
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fwd := Vector3(0, -sin(deg_to_rad(7.0)), -cos(deg_to_rad(7.0)))
	var yax := -fwd
	var xax := Vector3(1, 0, 0)
	cone.basis = Basis(xax, yax, xax.cross(yax))
	cone.position = Vector3(0, float(wr[1]) - 0.1, float(wr[0]) - 0.5) + fwd * 55.0
	land.add_child(cone)
	# Positionslichter: links rot, rechts grün, hinten weiß (leuchten, solange das Flugzeug Strom hat)
	var nav := Node3D.new()
	nav.name = "Positionslichter"
	n.add_child(nav)
	var tip0: Array = Models._wing_at(s, float(s["tip_x"]))
	_glow(nav, Vector3(-(float(s["tip_x"]) + 0.08), float(tip0[1]) + 0.05, float(tip0[0]) + 0.15), Vector3(0.16, 0.12, 0.16), Color(1.0, 0.12, 0.08))
	_glow(nav, Vector3(float(s["tip_x"]) + 0.08, float(tip0[1]) + 0.05, float(tip0[0]) + 0.15), Vector3(0.16, 0.12, 0.16), Color(0.15, 1.0, 0.35))
	_glow(nav, Vector3(0, cy + r * 0.42 - float(s["tail_drop"]) * 0.3, float(s["len"]) * 0.5 + 0.05), Vector3(0.14, 0.12, 0.12), Color(1, 1, 1))
	var lp := light_pool(70.0, 6.0, 26.0, 0.7)
	lp.name = "Bodenlicht"
	lp.top_level = true
	lp.visible = false
	n.add_child(lp)
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
	if id == "kopieren":
		# zwei gleiche Gebäude: Original und Kopie mit gestricheltem Rahmen
		var c := Node3D.new()
		blk(c, Vector3(-9, -0.2, -6), Vector3(9, 0, 6), Color(0.27, 0.29, 0.15))
		for x: float in [-4.5, 4.5]:
			blk(c, Vector3(x - 3.2, 0, -3), Vector3(x + 3.2, 3.5, 3), Color(0.82, 0.8, 0.74))
			blk(c, Vector3(x - 3.4, 3.5, -3.2), Vector3(x + 3.4, 3.9, 3.2), Color(0.45, 0.47, 0.5))
			blk(c, Vector3(x - 2.4, 1.0, 3.0), Vector3(x + 2.4, 2.4, 3.1), Color(0.3, 0.45, 0.55))
		for i in range(5):
			var z := -4.6 + float(i) * 2.3
			blk(c, Vector3(0.6, 0.02, z), Vector3(8.6, 0.12, z + 1.0), Color(0.62, 0.86, 0.92))
		return c
	if id == "raum":
		# Grundriss: Boden, drei Wände und eine Tür
		var rm := Node3D.new()
		blk(rm, Vector3(-7, -0.2, -5), Vector3(7, 0, 5), FLOOR)
		blk(rm, Vector3(-4.5, 0, -3.5), Vector3(4.5, 0.05, 3.5), Color(0.62, 0.78, 0.68))
		blk(rm, Vector3(-4.6, 0, -3.6), Vector3(4.6, 2.6, -3.3), Color(0.88, 0.86, 0.8))
		blk(rm, Vector3(-4.6, 0, -3.6), Vector3(-4.3, 2.6, 3.6), Color(0.88, 0.86, 0.8))
		blk(rm, Vector3(4.3, 0, -3.6), Vector3(4.6, 2.6, 3.6), Color(0.88, 0.86, 0.8))
		blk(rm, Vector3(-4.6, 0, 3.3), Vector3(-1.2, 2.6, 3.6), Color(0.88, 0.86, 0.8))
		blk(rm, Vector3(1.2, 0, 3.3), Vector3(4.6, 2.6, 3.6), Color(0.88, 0.86, 0.8))
		blk(rm, Vector3(-1.2, 2.2, 3.3), Vector3(1.2, 2.6, 3.6), Color(0.3, 0.45, 0.6))
		return rm
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
	if Interior.build(n, id, opts):
		if id == "cafe":
			_shop_sign(n, String(opts.get("stil", "cafe")))
		elif id == "shop":
			_shop_sign(n, String(opts.get("stil", "kiosk")))
		return
	if id in ["rolltreppe", "aufzug", "treppe", "passkontrolle", "zoll"]:
		_inside_more(n, id)
		return


## Passagier oder Personal, etwa 1,75 m groß, mit Gelenken in Hüfte, Knie, Schulter und Ellbogen.
## Der Körper ist je Pose ein Mesh (stehen, sitzen, acht Gangphasen); walk() und set_pose() wechseln sie.
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


## Gehen: Gangphase aus der gelaufenen Strecke (ein Doppelschritt = 1,35 m, 8 Phasen) und
## weiches Eindrehen in die Laufrichtung statt eines harten Sprungs.
static func walk(person: Node3D, dist: float, dir: Vector3, dt: float) -> void:
	var frame := int(fposmod(dist, 1.35) / 1.35 * float(Models.WALK_FRAMES)) % Models.WALK_FRAMES
	set_pose(person, 10 + frame)
	face(person, dir, dt)


## Weich in Richtung dir drehen (höchstens 7 rad/s).
static func face(node: Node3D, dir: Vector3, dt: float) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	var want := atan2(-flat.x, -flat.z)
	var cur := node.rotation.y
	var diff := wrapf(want - cur, -PI, PI)
	var step := 7.0 * maxf(dt, 0.0)
	if absf(diff) <= step or dt <= 0.0:
		node.rotation = Vector3(0, want, 0)
	else:
		node.rotation = Vector3(0, cur + signf(diff) * step, 0)


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


## Vorfeldfläche: Betonplatten (gleicher Shader wie das Vorfeld), doppelte gelbe Randlinie.
static func _apron_area(n: Node3D, w: float, d: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.03
	var pts := [Vector3(-w * 0.5, y, -d * 0.5), Vector3(w * 0.5, y, -d * 0.5), Vector3(w * 0.5, y, d * 0.5), Vector3(-w * 0.5, y, d * 0.5)]
	for i: int in [0, 2, 1, 0, 3, 2]:
		st.set_uv(Vector2(0.5, 0.0))
		st.set_normal(Vector3.UP)
		st.add_vertex(pts[i])
	var mi := MeshInstance3D.new()
	mi.name = "Belag"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/line.gdshader")
	mat.set_shader_parameter("base_color", Catalog.LINES["vorfeld"]["color"])
	mat.set_shader_parameter("mark", 5)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_bake", true)
	n.add_child(mi)
	# Randlinien zeichnet airfield.gd (nur am Außenrand, nicht zwischen aneinanderliegenden Flächen)


## Weg der Rolltreppenstufen (lokal, unten -Z, oben +Z): unten flach aus der Kammplatte, 30°-Steigung
## mit gerundeten Übergängen, oben flach. Wie bei Schindler/Kone: 1000-mm-Stufen, Glasbalustrade.
const ESC_FLAT := 1.1
static func escalator_path() -> PackedVector3Array:
	var fh := Catalog.FLOOR_H
	var z0 := -5.0 + 0.4
	var z1 := 5.0 - 0.4
	var ka := z0 + ESC_FLAT
	var kb := z1 - ESC_FLAT
	var out := PackedVector3Array()
	var n := 90
	for i in range(n + 1):
		var z := lerpf(z0, z1, float(i) / float(n))
		# weiche Rampe: smoothstep-artige Kurve zwischen den Knicken, gerade Mitte
		var y := 0.0
		var r := 0.85
		if z <= ka - r:
			y = 0.0
		elif z >= kb + r:
			y = fh
		else:
			var slope := fh / (kb - ka)
			var lin := clampf((z - ka) * slope, 0.0, fh)
			if z < ka + r:
				var u := (z - (ka - r)) / (2.0 * r)
				lin = slope * 2.0 * r * u * u * 0.5
			elif z > kb - r:
				var u2 := ((kb + r) - z) / (2.0 * r)
				lin = fh - slope * 2.0 * r * u2 * u2 * 0.5
			y = lin
		out.append(Vector3(0, y + 0.08, z))
	return out


## Punkt auf dem Pfad bei Bogenlänge s (Pfad und kumulierte Längen).
static func path_point(path: PackedVector3Array, cum: PackedFloat32Array, s: float) -> Vector3:
	var total := cum[cum.size() - 1]
	s = clampf(s, 0.0, total)
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var m := (lo + hi) / 2
		if cum[m] <= s:
			lo = m
		else:
			hi = m
	var seg := maxf(cum[hi] - cum[lo], 0.0001)
	return path[lo].lerp(path[hi], (s - cum[lo]) / seg)


static func path_cum(path: PackedVector3Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		cum.append(cum[i - 1] + path[i].distance_to(path[i - 1]))
	return cum


## Senkrechtes Band entlang des Pfads bei x (unten lo, oben hi über dem Pfad).
static func _ribbon(k: Kit, path: PackedVector3Array, x: float, lo: float, hi: float, col: Color, step: int = 3) -> void:
	var i := 0
	while i < path.size() - 1:
		var j := mini(i + step, path.size() - 1)
		var a := path[i]
		var b := path[j]
		k.quad(Vector3(x, a.y + lo, a.z), Vector3(x, b.y + lo, b.z), Vector3(x, b.y + hi, b.z), Vector3(x, a.y + hi, a.z), col, Vector3(0, (a.y + b.y) * 0.5 + (lo + hi) * 0.5, (a.z + b.z) * 0.5))
		i = j


## Waagrechtes Band entlang des Pfads von x0 bis x1 in Höhe dy über dem Pfad.
static func _deck(k: Kit, path: PackedVector3Array, x0: float, x1: float, dy: float, col: Color, step: int = 3) -> void:
	var i := 0
	while i < path.size() - 1:
		var j := mini(i + step, path.size() - 1)
		var a := path[i]
		var b := path[j]
		k.quad(Vector3(x0, a.y + dy, a.z), Vector3(x1, a.y + dy, a.z), Vector3(x1, b.y + dy, b.z), Vector3(x0, b.y + dy, b.z), col, Vector3((x0 + x1) * 0.5, (a.y + b.y) * 0.5 + dy - 1.0, (a.z + b.z) * 0.5))
		i = j


static func _escalator(n: Node3D, k: Kit) -> void:
	var path := escalator_path()
	var steel := Color(0.78, 0.79, 0.8)
	var steel_dark := Color(0.55, 0.56, 0.58)
	var glass := Color(0.62, 0.8, 0.88, 0.5)
	var rubber := Color(0.08, 0.08, 0.09)
	# Fachwerk mit Edelstahlverkleidung: Seiten, Unterseite, Abdeckung neben dem Handlauf
	for sx: float in [-0.82, 0.82]:
		_ribbon(k, path, sx, -1.05, 0.12, steel)
	_deck(k, path, -0.82, 0.82, -1.05, Color(0.84, 0.85, 0.86))
	for sx2: Array in [[-0.82, -0.6], [0.6, 0.82]]:
		_deck(k, path, sx2[0], sx2[1], 0.12, steel_dark)
	# Sockelleiste (Edelstahl) und Glasbalustrade mit Handlauf
	for sx3: float in [-0.53, 0.53]:
		_ribbon(k, path, sx3, -0.1, 0.12, Color(0.86, 0.87, 0.88))
	for sx4: float in [-0.6, 0.6]:
		_ribbon(k, path, sx4, 0.12, 0.98, glass, 2)
		var i := 0
		while i < path.size() - 2:
			var a := path[i] + Vector3(sx4, 1.0, 0)
			var b := path[i + 2] + Vector3(sx4, 1.0, 0)
			k.cyl(a, b, 0.045, 0.045, rubber, 6, false)
			i += 2
		# Handlaufköpfe: Bogen über die Kammplatten hinaus
		for e: Array in [[path[0], -1.0], [path[path.size() - 1], 1.0]]:
			var c: Vector3 = (e[0] as Vector3) + Vector3(sx4, 0.55, 0)
			var dir := float(e[1])
			var prev := c + Vector3(0, 0.45, 0)
			for q in range(1, 9):
				var ang := PI * float(q) / 8.0
				var pt := c + Vector3(0, cos(ang) * 0.45, dir * sin(ang) * 0.45)
				k.cyl(prev, pt, 0.045, 0.045, rubber, 6, false)
				prev = pt
			k.box(c + Vector3(-0.05, -0.55, -0.05 + dir * 0.0), c + Vector3(0.05, 0.4, 0.05) + Vector3(0, 0, dir * 0.4), glass)
	# Kammplatten (geriffeltes Aluminium) an beiden Enden, bündig mit dem Fußboden
	var fh := Catalog.FLOOR_H
	for e2: Array in [[-5.0, -5.0 + 0.45, 0.0], [5.0 - 0.45, 5.0, fh]]:
		var y := float(e2[2])
		k.box(Vector3(-0.62, y, float(e2[0])), Vector3(0.62, y + 0.1, float(e2[1])), Color(0.68, 0.69, 0.7))
		var zz := float(e2[0]) + 0.06
		while zz < float(e2[1]) - 0.05:
			k.box(Vector3(-0.55, y + 0.1, zz), Vector3(0.55, y + 0.115, zz + 0.03), Color(0.56, 0.57, 0.58))
			zz += 0.09
		# gelbe Kammzähne an der Kante zur Stufe
		var ze := float(e2[1]) if y < 0.5 else float(e2[0])
		k.box(Vector3(-0.5, y + 0.1, ze - 0.05), Vector3(0.5, y + 0.12, ze + 0.05), Color(0.95, 0.78, 0.1))
	# Stufen als MultiMesh, terminal.gd lässt sie den Pfad entlanglaufen
	var sk := Kit.new()
	sk.box(Vector3(-0.5, -0.04, -0.2), Vector3(0.5, 0.0, 0.2), Color(0.22, 0.23, 0.25))
	for gx: int in range(9):
		var x := -0.44 + float(gx) * 0.11
		sk.box(Vector3(x, 0.0, -0.19), Vector3(x + 0.05, 0.012, 0.19), Color(0.3, 0.31, 0.33))
	sk.box(Vector3(-0.5, 0.0, 0.16), Vector3(0.5, 0.014, 0.2), Color(0.95, 0.78, 0.1))     # gelbe Vorderkante
	sk.box(Vector3(-0.5, 0.0, -0.2), Vector3(-0.44, 0.014, 0.2), Color(0.95, 0.78, 0.1))   # gelbe Seitenränder
	sk.box(Vector3(0.44, 0.0, -0.2), Vector3(0.5, 0.014, 0.2), Color(0.95, 0.78, 0.1))
	sk.box(Vector3(-0.5, -0.3, -0.21), Vector3(0.5, -0.04, -0.18), Color(0.25, 0.26, 0.28))  # Setzstufe
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sk.commit()
	var cum := path_cum(path)
	var cnt := int(cum[cum.size() - 1] / 0.4)
	mm.instance_count = cnt
	for i2 in range(cnt):
		mm.set_instance_transform(i2, Transform3D(Basis.IDENTITY, path_point(path, cum, float(i2) * 0.4)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Stufen"
	mmi.multimesh = mm
	mmi.material_override = Kit.material()
	mmi.set_meta("no_bake", true)
	n.add_child(mmi)


## Treppe nach Vorbild: Betonläufe mit Natursteinstufen und Kantenschutz, Wangen, Glasgeländer, Handlauf.
static func _stairs(k: Kit) -> void:
	var fh := Catalog.FLOOR_H
	var nst := 28
	var run := 8.0 / float(nst)
	var rise := fh / float(nst)
	var stone := Color(0.74, 0.72, 0.68)
	for i in range(nst):
		var y := float(i + 1) * rise
		var z := -4.0 + float(i) * run
		k.box(Vector3(-1.3, y - 0.05, z), Vector3(1.3, y, z + run + 0.02), stone)
		k.box(Vector3(-1.3, y - rise, z - 0.01), Vector3(1.3, y - 0.05, z + 0.02), stone.darkened(0.12))
		k.box(Vector3(-1.3, y - 0.012, z), Vector3(1.3, y + 0.004, z + 0.04), Color(0.3, 0.3, 0.32))   # Kantenschutz
	var path := PackedVector3Array()
	for i3 in range(nst + 1):
		path.append(Vector3(0, float(i3) * rise, -4.0 + float(i3) * run))
	for sx: float in [-1.38, 1.38]:
		# Wange aus Sichtbeton unter dem Lauf
		_ribbon(k, path, sx, -0.55, 0.12, Color(0.66, 0.66, 0.64), 1)
		_ribbon(k, path, sx, 0.12, 0.98, Color(0.62, 0.8, 0.88, 0.5), 2)
		k.cyl(path[0] + Vector3(sx, 1.0, 0), path[path.size() - 1] + Vector3(sx, 1.0, 0), 0.03, 0.03, Color(0.75, 0.76, 0.78), 6, false)
	_deck(k, path, -1.38, 1.38, -0.55, Color(0.7, 0.7, 0.68), 1)


## Rolltreppe, Aufzug, Treppe (verbinden mit der Ebene darüber), Passkontrolle und Zoll.
static func _inside_more(n: Node3D, id: String) -> void:
	var k := Kit.new()
	var steel := Color(0.7, 0.72, 0.74)
	var glass := Color(0.6, 0.78, 0.86, 0.6)
	var fh := Catalog.FLOOR_H
	match id:
		"rolltreppe":
			_escalator(n, k)
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
			_stairs(k)
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


## Lichtkegel auf dem Boden (nachts sichtbar): Trapez von der Lampe (Breite w0) nach vorn (-Z) bis len (Breite w1).
static var _beam_mat: ShaderMaterial = null


static var _cone_mat: ShaderMaterial = null


## Gemeinsames Material der Lichtkegel (Stärke "vis" setzt flights.gd je Bild: Nacht, Nebel, Regen).
static func cone_material() -> ShaderMaterial:
	if _cone_mat == null:
		_cone_mat = ShaderMaterial.new()
		_cone_mat.shader = load("res://shaders/cone.gdshader")
	return _cone_mat


static func light_pool(length: float, w0: float, w1: float, strength: float = 0.55) -> MeshInstance3D:
	if _beam_mat == null:
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = load("res://shaders/beam.gdshader")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(-w0 * 0.5, 0, 0), Vector3(w0 * 0.5, 0, 0), Vector3(w1 * 0.5, 0, -length), Vector3(-w1 * 0.5, 0, -length)]
	var uvs := [Vector2(0.5 - 0.5 * w0 / w1, 0), Vector2(0.5 + 0.5 * w0 / w1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := _beam_mat
	if strength != 0.55:
		m = _beam_mat.duplicate()
		m.set_shader_parameter("strength", strength)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Lichtkegel"
	return mi