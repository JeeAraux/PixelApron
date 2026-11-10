extends RefCounted
## Landschaft und Außenanlagen: Büsche, Hecken, Blumenbeete, Teich mit Enten, Felsen,
## Picknicktisch, feinere Laterne, Bank und Kübel, ebenerdiger Parkplatz und der Zaun.
## Laub hat Alpha 0.8 und wiegt sich im Wind (kit.gdshader).

const Kit = preload("res://scripts/mesh_kit.gd")
const Models = preload("res://scripts/models.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")
const BeltAnim = preload("res://scripts/belt_anim.gd")

const STEEL := Color(0.36, 0.41, 0.44)
const DARK := Color(0.12, 0.12, 0.13)
const WOOD := Color(0.48, 0.34, 0.22)
const STONE := Color(0.6, 0.59, 0.56)
const SOIL := Color(0.27, 0.2, 0.13)

const IDS := ["busch", "hecke", "blumenbeet", "teich", "felsen", "picknick", "laterne", "bank", "kuebel", "parkplatz"]


static func build(n: Node3D, id: String) -> bool:
	if not (id in IDS):
		return false
	var k := Kit.new()
	match id:
		"busch":
			_bush(k, Vector3.ZERO, 1.0)
		"hecke":
			_hedge(k)
		"blumenbeet":
			_flowers(k)
		"teich":
			_pond(n, k)
		"felsen":
			_rocks(k)
		"picknick":
			_picnic(k)
		"laterne":
			_lamp(k)
		"bank":
			_bench(k)
		"kuebel":
			_planter(k)
		"parkplatz":
			_parking(n, k)
	if k.count > 0:
		n.add_child(k.instance("Landschaft"))
	return true


static func _leaf(h: float, s: float, v: float) -> Color:
	var c := Color.from_hsv(h, s, v)
	return Color(c.r, c.g, c.b, 0.8)


static func _bush(k: Kit, at: Vector3, s: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(at.x * 13.0 + at.z * 7.0)) + 3
	for i in range(7):
		var a := float(i) / 7.0 * TAU + rng.randf() * 0.4
		var r := rng.randf_range(0.2, 0.55) * s
		var c := _leaf(rng.randf_range(0.22, 0.3), rng.randf_range(0.45, 0.65), rng.randf_range(0.32, 0.48))
		k.sphere(at + Vector3(cos(a) * r, (0.45 + rng.randf() * 0.35) * s, sin(a) * r), rng.randf_range(0.38, 0.55) * s, c, 8, 5)
	k.sphere(at + Vector3(0, 0.85 * s, 0), 0.5 * s, _leaf(0.26, 0.55, 0.45), 8, 5)
	if rng.randf() < 0.5:
		for i in range(6):
			var a := rng.randf() * TAU
			k.sphere(at + Vector3(cos(a) * 0.6 * s, (0.6 + rng.randf() * 0.5) * s, sin(a) * 0.6 * s), 0.07 * s,
				Color.from_hsv([0.95, 0.12, 0.6][i % 3], 0.6, 0.95, 0.8), 6, 4)


static func _hedge(k: Kit) -> void:
	k.box(Vector3(-3.0, 0, -0.6), Vector3(3.0, 0.12, 0.6), SOIL)
	var c1 := _leaf(0.27, 0.6, 0.36)
	var c2 := _leaf(0.25, 0.55, 0.42)
	k.rounded_box(Vector3(-2.9, 0.1, -0.5), Vector3(2.9, 1.5, 0.5), 0.18, c1, 3)
	for i in range(24):
		var x := -2.7 + float(i) * 0.235
		k.sphere(Vector3(x, 1.45 + float(i % 3) * 0.04, float(i % 2) * 0.2 - 0.1), 0.2, c2, 6, 4)
		k.sphere(Vector3(x + 0.1, 0.8, 0.48), 0.16, c2, 6, 4)
		k.sphere(Vector3(x - 0.05, 0.6, -0.48), 0.16, c2, 6, 4)


static func _flowers(k: Kit) -> void:
	k.box(Vector3(-2.0, 0, -1.0), Vector3(2.0, 0.25, 1.0), Color(0.62, 0.6, 0.56))
	k.box(Vector3(-1.85, 0.2, -0.85), Vector3(1.85, 0.3, 0.85), SOIL)
	var hues := [0.0, 0.08, 0.14, 0.83, 0.6, 0.95]
	for i in range(60):
		var x := -1.7 + float(i % 12) * 0.31
		var z := -0.7 + float(i / 12) * 0.35
		var stem := Color(0.2, 0.42, 0.18, 0.8)
		k.cyl(Vector3(x, 0.3, z), Vector3(x, 0.55 + float(i % 3) * 0.05, z), 0.015, 0.015, stem, 4)
		var hue: float = hues[(i / 12 + i % 2) % hues.size()]
		k.sphere(Vector3(x, 0.58 + float(i % 3) * 0.05, z), 0.07, Color.from_hsv(hue, 0.65, 0.95, 0.8), 6, 4)
		if i % 4 == 0:
			k.sphere(Vector3(x + 0.12, 0.38, z + 0.1), 0.1, _leaf(0.28, 0.6, 0.4), 6, 4)


## Teich: unregelmäßiges Ufer mit Steinen, Schilf, Seerosen und zwei Enten, die Kreise ziehen.
static func _pond(n: Node3D, k: Kit) -> void:
	var water := Color(0.3, 0.52, 0.62)
	var pts := []
	for i in range(20):
		var a := float(i) / 20.0 * TAU
		var r := 1.0 + 0.12 * sin(a * 3.0) + 0.08 * cos(a * 5.0)
		pts.append(Vector3(cos(a) * 5.5 * r, 0, sin(a) * 3.6 * r))
	for i in range(20):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % 20]
		k.tri(Vector3(0, 0.08, 0), a + Vector3(0, 0.08, 0), b + Vector3(0, 0.08, 0), water, Vector3(0, -1, 0))
		k.tri(Vector3(0, 0.0, 0), a, b, water.darkened(0.3), Vector3(0, 1, 0))
		# Ufer: Kiesring und Steine
		var out_a := a * 1.12
		var out_b := b * 1.12
		k.quad(a + Vector3(0, 0.09, 0), b + Vector3(0, 0.09, 0), out_b + Vector3(0, 0.12, 0), out_a + Vector3(0, 0.12, 0), Color(0.68, 0.64, 0.55), Vector3(0, -1, 0))
		if i % 2 == 0:
			k.sphere(out_a + Vector3(0, 0.15, 0), 0.28 + 0.08 * float(i % 3), STONE.darkened(0.05 * float(i % 4)), 7, 4, Vector3(1.2, 0.6, 1.0))
	# Schilf am Westufer
	for i in range(18):
		var a := PI * 0.8 + float(i) * 0.04
		var p := Vector3(cos(a) * 5.0, 0.08, sin(a) * 3.2) + Vector3(float(i % 3) * 0.15, 0, float(i % 2) * 0.2)
		k.cyl(p, p + Vector3(0.05, 1.3 + float(i % 4) * 0.15, 0), 0.025, 0.012, Color(0.45, 0.55, 0.25, 0.8), 4)
		if i % 3 == 0:
			k.cyl(p + Vector3(0.04, 1.1, 0), p + Vector3(0.05, 1.35, 0), 0.05, 0.05, Color(0.42, 0.28, 0.15, 0.8), 6)
	# Seerosen
	for i in range(6):
		var p := Vector3(1.5 + float(i % 3) * 0.9, 0.1, -1.0 + float(i / 3) * 1.2)
		k.cyl(p, p + Vector3(0, 0.02, 0), 0.32, 0.32, Color(0.25, 0.5, 0.25), 10)
		if i % 2 == 0:
			k.sphere(p + Vector3(0.05, 0.08, 0), 0.08, Color(0.98, 0.8, 0.88), 6, 4)
	# Enten (eigenes Mesh), ziehen langsame Kreise
	var dk := Kit.new()
	dk.sphere(Vector3(0, 0.12, 0), 0.16, Color(0.55, 0.45, 0.32), 8, 5, Vector3(0.9, 0.7, 1.4))
	dk.sphere(Vector3(0, 0.3, -0.18), 0.08, Color(0.15, 0.4, 0.25), 8, 5)
	dk.box(Vector3(-0.025, 0.27, -0.3), Vector3(0.025, 0.3, -0.22), Color(0.95, 0.7, 0.15))
	dk.box(Vector3(-0.14, 0.18, -0.02), Vector3(0.14, 0.2, 0.1), Color(0.95, 0.95, 0.92))
	var path := PackedVector3Array()
	for i in range(32):
		var a := float(i) / 32.0 * TAU
		path.append(Vector3(cos(a) * 3.0, 0.08, sin(a) * 1.8 + 0.3))
	var ducks := MultiMeshInstance3D.new()
	ducks.name = "Enten"
	ducks.set_script(BeltAnim)
	n.add_child(ducks)
	ducks.call("setup", path, dk.commit(), 0.35, 4.5, true)


static func _rocks(k: Kit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in range(6):
		var p := Vector3(rng.randf_range(-1.1, 1.1), 0, rng.randf_range(-1.1, 1.1))
		var r := rng.randf_range(0.25, 0.7)
		k.sphere(p + Vector3(0, r * 0.45, 0), r, STONE.darkened(rng.randf() * 0.2), 7, 4, Vector3(1.0 + rng.randf() * 0.4, 0.75, 1.0))
	for i in range(8):
		var p := Vector3(rng.randf_range(-1.4, 1.4), 0, rng.randf_range(-1.4, 1.4))
		k.sphere(p + Vector3(0, 0.1, 0), 0.18, _leaf(0.25, 0.5, 0.4), 6, 4)


static func _picnic(k: Kit) -> void:
	k.box(Vector3(-1.0, 0.72, -0.4), Vector3(1.0, 0.78, 0.4), WOOD)
	for sz: float in [-0.75, 0.75]:
		k.box(Vector3(-1.0, 0.42, sz - 0.15), Vector3(1.0, 0.47, sz + 0.15), WOOD)
	for sx: float in [-0.8, 0.8]:
		for d: float in [-1.0, 1.0]:
			var a := Vector3(sx, 0, d * 0.9)
			var b := Vector3(sx, 0.75, 0)
			var dd := b - a
			k.box(Vector3(-0.05, -0.05, -dd.length() * 0.5), Vector3(0.05, 0.05, dd.length() * 0.5), WOOD.darkened(0.15),
				Transform3D(Basis.looking_at(dd.normalized(), Vector3.UP), (a + b) * 0.5))


## Mastleuchte mit gebogenem Ausleger und LED-Kopf (Lampe leuchtet nachts).
static func _lamp(k: Kit) -> void:
	k.cyl(Vector3(0, 0, 0), Vector3(0, 0.25, 0), 0.16, 0.14, STEEL.darkened(0.2), 10)
	k.cyl(Vector3(0, 0.25, 0), Vector3(0, 6.6, 0), 0.08, 0.055, STEEL, 10)
	var prev := Vector3(0, 6.6, 0)
	for i in range(1, 7):
		var a := float(i) / 6.0 * PI * 0.5
		var p := Vector3(0, 6.6 + sin(a) * 0.45, 0.45 - cos(a) * 0.45 + float(i) * 0.1)
		k.cyl(prev, p, 0.05, 0.05, STEEL, 8)
		prev = p
	k.cyl(prev, prev + Vector3(0, 0, 0.5), 0.05, 0.05, STEEL, 8)
	k.rounded_box(prev + Vector3(-0.2, -0.12, 0.3), prev + Vector3(0.2, 0.04, 1.0), 0.04, Color(0.3, 0.32, 0.34), 2)
	k.box(prev + Vector3(-0.16, -0.14, 0.36), prev + Vector3(0.16, -0.12, 0.95), Color(0.98, 0.9, 0.66, 0.3))


## Parkbank aus Holzlatten mit Gusseisenfüßen.
static func _bench(k: Kit) -> void:
	for x: float in [-0.85, 0.85]:
		k.box(Vector3(x - 0.04, 0, -0.28), Vector3(x + 0.04, 0.42, -0.2), DARK)
		k.box(Vector3(x - 0.04, 0, 0.18), Vector3(x + 0.04, 0.42, 0.26), DARK)
		k.box(Vector3(x - 0.04, 0.4, -0.28), Vector3(x + 0.04, 0.46, 0.26), DARK)
		k.box(Vector3(x - 0.04, 0.42, 0.2), Vector3(x + 0.04, 0.95, 0.28), DARK)
		k.box(Vector3(x - 0.04, 0.6, -0.25), Vector3(x + 0.04, 0.64, 0.2), DARK)
	for i in range(4):
		var z := -0.26 + float(i) * 0.13
		k.box(Vector3(-1.1, 0.46, z), Vector3(1.1, 0.5, z + 0.1), WOOD)
	for i in range(3):
		var y := 0.58 + float(i) * 0.12
		k.box(Vector3(-1.1, y, 0.26), Vector3(1.1, y + 0.09, 0.3), WOOD)


static func _planter(k: Kit) -> void:
	k.cyl(Vector3(0, 0, 0), Vector3(0, 0.7, 0), 0.5, 0.62, Color(0.56, 0.31, 0.21), 14)
	k.cyl(Vector3(0, 0.7, 0), Vector3(0, 0.76, 0), 0.66, 0.66, Color(0.5, 0.28, 0.19), 14)
	k.cyl(Vector3(0, 0.68, 0), Vector3(0, 0.74, 0), 0.58, 0.58, SOIL, 14)
	_bush(k, Vector3(0, 0.55, 0), 0.75)


## Ebenerdiger Parkplatz: Asphalt mit Stellplätzen, Bordstein, Bäumen, Schranke an der Zufahrt.
## Die geparkten Autos sind eigene Knoten "Platz0..": traffic.gd zeigt so viele, wie belegt sind.
static func _parking(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-16, 0, -12), Vector3(16, 0.05, 12), Color(0.24, 0.24, 0.23))
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 16 - 0.2, 0, -12), Vector3(sx * 16 + 0.2, 0.18, 12), Color(0.66, 0.65, 0.61))
	k.box(Vector3(-16, 0, 11.8), Vector3(16, 0.18, 12.2), Color(0.66, 0.65, 0.61))
	var white := Color(0.85, 0.85, 0.82)
	var Factory = load("res://scripts/factory.gd")
	var slot := 0
	for row: float in [-8.5, 7.5]:
		for i in range(12):
			var x := -14.0 + float(i) * 2.55
			k.box(Vector3(x - 0.05, 0.05, row - 2.5), Vector3(x + 0.05, 0.06, row + 2.5), white)
			if i < 11:
				var car: Node3D = Factory.make_car(Factory.car_color())
				car.name = "Platz%d" % slot
				car.position = Vector3(x + 1.27, 0.05, row)
				car.rotation.y = 0.0 if row < 0.0 else PI
				car.visible = false
				car.set_meta("no_bake", true)
				n.add_child(car)
				slot += 1
	# Fahrgasse mit Pfeilen
	for x: float in [-8.0, 0.0, 8.0]:
		PixelFont.draw_ground(k, ">", Vector3(x, 0.06, -1.0), Vector3(1, 0, 0), 0.25, white)
		PixelFont.draw_ground(k, "<", Vector3(x, 0.06, 1.0), Vector3(1, 0, 0), 0.25, white)
	# Bäume im Grünstreifen
	for x: float in [-10.0, 0.0, 10.0]:
		k.box(Vector3(x - 1.0, 0.05, 11.0), Vector3(x + 1.0, 0.2, 11.8), Color(0.3, 0.45, 0.22))
	# Schranke und Schild an der Zufahrt (vorn, -Z)
	k.box(Vector3(-7.0, 0, -12.6), Vector3(-6.4, 1.1, -12.0), Color(0.9, 0.75, 0.15))
	k.box(Vector3(6.4, 0, -12.6), Vector3(7.0, 1.1, -12.0), Color(0.9, 0.75, 0.15))
	k.box(Vector3(-15.5, 0, -12.4), Vector3(-15.3, 2.6, -12.2), STEEL)
	k.box(Vector3(-16.2, 1.9, -12.45), Vector3(-14.6, 2.7, -12.25), Color(0.15, 0.35, 0.7))
	PixelFont.draw(k, "P", Vector3(-15.4, 2.3, -12.46), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.09, white)
	for side: Array in [["SchrankeEin", -6.7], ["SchrankeAus", 6.7]]:
		var arm := Node3D.new()
		arm.name = side[0]
		arm.position = Vector3(float(side[1]), 1.0, -12.3)
		arm.set_meta("no_bake", true)
		var ak := Kit.new()
		var dir := 1.0 if float(side[1]) < 0.0 else -1.0
		for j in range(6):
			ak.box(Vector3(dir * float(j) * 0.8, -0.05, -0.05), Vector3(dir * (float(j) * 0.8 + 0.8), 0.05, 0.05), Color(0.9, 0.15, 0.1) if j % 2 == 0 else Color(0.95, 0.95, 0.92))
		arm.add_child(ak.instance("Arm"))
		n.add_child(arm)
	for x: float in [-10.0, 0.0, 10.0]:
		var tree: Node3D = Factory.make_item("baum", {"stil": "laub"})
		tree.position = Vector3(x, 0.2, 11.4)
		tree.scale = Vector3(0.8, 0.8, 0.8)
		n.add_child(tree)


## Sicherheitszaun entlang der Stützpunkte: Pfosten alle 3 m, Stabgitter, oben Stacheldraht auf Y-Auslegern.
static func fence(s: PackedVector3Array) -> MeshInstance3D:
	var k := Kit.new()
	var post := Color(0.28, 0.33, 0.3)
	var wire := Color(0.35, 0.4, 0.37)
	var n := s.size()
	var run := 0.0
	var last := -10.0
	for i in range(n):
		if i > 0:
			run += s[i].distance_to(s[i - 1])
		if run - last < 3.0 and i != n - 1:
			continue
		var p := Vector3(s[i].x, 0, s[i].z)
		var dir := s[mini(i + 1, n - 1)] - s[maxi(i - 1, 0)]
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		var side := dir.cross(Vector3.UP)
		k.box(p + Vector3(-0.05, 0, -0.05), p + Vector3(0.05, 2.5, 0.05), post)
		k.box(p + Vector3(-0.12, 0, -0.12), p + Vector3(0.12, 0.12, 0.12), Color(0.55, 0.55, 0.52))
		for sd: float in [-1.0, 1.0]:
			var a := p + Vector3(0, 2.45, 0)
			var b := p + Vector3(0, 2.85, 0) + side * sd * 0.3
			var d := b - a
			k.box(Vector3(-0.02, -0.02, -d.length() * 0.5), Vector3(0.02, 0.02, d.length() * 0.5), post,
				Transform3D(Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT), (a + b) * 0.5))
		if last >= 0.0:
			# Gitterfeld zum vorigen Pfosten
			var q: Vector3 = k.get_meta("last_post", p) if k.has_meta("last_post") else p
			var seg := p - q
			var l := seg.length()
			if l > 0.5:
				var bas := Basis.looking_at(seg / l, Vector3.UP)
				var mid := (p + q) * 0.5
				for y: float in [0.15, 1.2, 2.3]:
					k.box(Vector3(-0.025, y - 0.025, -l * 0.5), Vector3(0.025, y + 0.025, l * 0.5), wire, Transform3D(bas, mid))
				var bars := int(l / 0.2)
				for j in range(bars):
					var z := -l * 0.5 + (float(j) + 0.5) * l / float(bars)
					k.box(Vector3(-0.008, 0.1, z - 0.008), Vector3(0.008, 2.35, z + 0.008), wire, Transform3D(bas, mid))
				for sd: float in [-1.0, 0.0, 1.0]:
					var o := Vector3(0, 2.6 + absf(sd) * 0.1, 0) + (seg / l).cross(Vector3.UP) * sd * 0.2
					k.box(Vector3(-0.012, -0.012, -l * 0.5), Vector3(0.012, 0.012, l * 0.5), Color(0.55, 0.57, 0.58), Transform3D(bas, mid + o))
		k.set_meta("last_post", p)
		last = run
	var mi := k.instance("Zaun")
	return mi
