extends RefCounted
## Versorgungsbauten und Vorfelddepot im feinen Stil: Trafostation, Heizzentrale,
## Wasseranschluss und Vorfelddepot. Vorderseite +Z. Fenster Alpha 0.6 (leuchten nachts),
## Lampen Alpha 0.3; Lüfter drehen sich (deco_anim.gd, Knoten Dreh*), Rauch steigt (Hub*).

const Kit = preload("res://scripts/mesh_kit.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")
const DecoAnim = preload("res://scripts/deco_anim.gd")

const CONCRETE := Color(0.62, 0.61, 0.57)
const ROOF := Color(0.34, 0.34, 0.32)
const STEEL := Color(0.4, 0.44, 0.47)
const DARK := Color(0.12, 0.12, 0.13)
const BRICK := Color(0.55, 0.26, 0.2)
const WIN := Color(0.22, 0.32, 0.38, 0.6)
const LAMP := Color(1.0, 0.92, 0.72, 0.3)
const YELLOW := Color(0.9, 0.72, 0.16)

const IDS := ["trafo", "heizzentrale", "wasseranschluss", "vorfelddepot", "tanklager", "busgarage", "catering", "personalgebaeude", "rettungswache", "wohngebiet"]
const Landmarks = preload("res://scripts/landmarks.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Models = preload("res://scripts/models.gd")
const CLAD := Color(0.7, 0.73, 0.74)
const RENDER := Color(0.88, 0.87, 0.83)
const GREEN := Color(0.15, 0.9, 0.35, 0.3)
const FRAME_C := Color(0.24, 0.26, 0.28)
const GRAVEL_C := Color(0.55, 0.53, 0.49)
const CHROME_C := Color(0.74, 0.76, 0.79)


static func build(n: Node3D, id: String) -> bool:
	if not (id in IDS):
		return false
	var k := Kit.new()
	match id:
		"trafo":
			_trafo(n, k)
		"heizzentrale":
			_heating(n, k)
		"wasseranschluss":
			_water(n, k)
		"vorfelddepot":
			_depot(n, k)
		"tanklager":
			_fuel_farm(n, k)
		"busgarage":
			if Catalog.tore_of("busgarage", n.get_meta("opts", {})) > 0:
				Landmarks.sized_hall(n, "busgarage", n.get_meta("opts", {}))
			else:
				_bus_depot(n, k)
		"catering":
			_catering(n, k)
		"personalgebaeude":
			_staff_building(n, k)
		"rettungswache":
			_rescue_station(n, k)
		"wohngebiet":
			_village(k)
	n.add_child(k.instance("Bau"))
	var a := Node.new()
	a.name = "Anim"
	a.set_script(DecoAnim)
	n.add_child(a)
	return true


static func _part(n: Node3D, name: String, k: Kit, at: Vector3) -> MeshInstance3D:
	var mi := k.instance(name)
	mi.position = at
	mi.set_meta("no_bake", true)
	n.add_child(mi)
	return mi


## Lüfter mit Gitter (das Flügelrad dreht sich).
static func _fan(n: Node3D, k: Kit, at: Vector3, r: float, speed: float) -> void:
	k.cyl(at, at + Vector3(0, 0.35, 0), r + 0.08, r + 0.08, Color(0.55, 0.57, 0.58), 16, false)
	k.cyl(at + Vector3(0, 0.33, 0), at + Vector3(0, 0.36, 0), r + 0.1, r + 0.1, Color(0.45, 0.47, 0.48), 16)
	var fk := Kit.new()
	for i in range(5):
		var a := float(i) / 5.0 * TAU
		var tip := Vector3(cos(a), 0, sin(a)) * r * 0.92
		var side := Vector3(-sin(a), 0, cos(a)) * r * 0.22
		fk.quad(Vector3.ZERO, tip - side, tip + side, side * 0.3, DARK, Vector3(0, -1, 0))
	fk.cyl(Vector3(0, -0.02, 0), Vector3(0, 0.04, 0), r * 0.18, r * 0.18, Color(0.3, 0.3, 0.32), 10)
	var f := _part(n, "DrehLuefter%d" % int(at.x * 10.0 + at.z), fk, at + Vector3(0, 0.38, 0))
	f.set_meta("speed", speed)
	for i in range(6):
		var x := -r + float(i) * r * 0.4
		k.box(at + Vector3(x - 0.01, 0.42, -r), at + Vector3(x + 0.01, 0.43, r), STEEL)


## Trafostation: Betonhaus mit Lüftungsgittern und Warnschild, zwei Transformatoren mit
## Kühlrippen und Durchführungen in einem Gitterzaun, Kabelpritsche.
static func _trafo(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-5.2, 0, -3.7), Vector3(4.8, 0.12, 3.7), Color(0.5, 0.5, 0.48))
	k.rounded_box(Vector3(-5, 0.12, -3.5), Vector3(0.5, 3.4, 3.5), 0.05, CONCRETE, 2)
	k.box(Vector3(-5.2, 3.4, -3.7), Vector3(0.7, 3.62, 3.7), ROOF)
	k.box(Vector3(-5.25, 3.3, -3.75), Vector3(0.75, 3.4, 3.75), CONCRETE.darkened(0.1))
	for x: float in [-4.2, -2.0]:
		k.box(Vector3(x, 0.12, 3.5), Vector3(x + 1.6, 2.4, 3.56), Color(0.45, 0.5, 0.52))
		for i in range(12):
			var y := 0.3 + float(i) * 0.17
			k.box(Vector3(x + 0.1, y, 3.56), Vector3(x + 1.5, y + 0.05, 3.6), Color(0.3, 0.33, 0.35))
		k.box(Vector3(x + 1.35, 1.1, 3.6), Vector3(x + 1.45, 1.3, 3.65), CONCRETE)
	# Warnschild Blitz
	k.prism([Vector3(-0.8, 2.6, 3.51), Vector3(-0.2, 2.6, 3.51), Vector3(-0.5, 3.12, 3.51)],
		[Vector3(-0.8, 2.6, 3.56), Vector3(-0.2, 2.6, 3.56), Vector3(-0.5, 3.12, 3.56)], YELLOW)
	k.box(Vector3(-0.53, 2.68, 3.56), Vector3(-0.47, 2.95, 3.58), DARK)
	PixelFont.draw(k, "TRAFO", Vector3(-2.3, 2.95, 3.57), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.05, DARK)
	k.box(Vector3(-2.5, 3.0, 3.5), Vector3(-2.1, 3.15, 3.6), LAMP)
	# Transformatoren
	var tcol := Color(0.42, 0.48, 0.45)
	for z: float in [-1.8, 1.8]:
		k.box(Vector3(1.3, 0.12, z - 1.25), Vector3(3.9, 0.4, z + 1.25), CONCRETE)
		k.rounded_box(Vector3(1.8, 0.4, z - 0.9), Vector3(3.4, 2.2, z + 0.9), 0.06, tcol, 2)
		for i in range(9):
			var fz := z - 0.85 + float(i) * 0.21
			k.box(Vector3(1.55, 0.5, fz), Vector3(1.8, 2.0, fz + 0.05), tcol.darkened(0.12))
			k.box(Vector3(3.4, 0.5, fz), Vector3(3.65, 2.0, fz + 0.05), tcol.darkened(0.12))
		k.cyl(Vector3(2.6, 2.2, z - 0.5), Vector3(2.6, 2.55, z - 0.5), 0.35, 0.35, tcol, 14)
		for ix: float in [2.05, 2.6, 3.15]:
			for j in range(5):
				k.cyl(Vector3(ix, 2.2 + float(j) * 0.14, z + 0.4), Vector3(ix, 2.27 + float(j) * 0.14, z + 0.4), 0.09, 0.09, Color(0.82, 0.62, 0.45), 10)
			k.cyl(Vector3(ix, 2.9, z + 0.4), Vector3(ix, 3.0, z + 0.4), 0.03, 0.03, Color(0.7, 0.45, 0.25), 6)
	# Kabelpritsche vom Haus zu den Trafos
	k.box(Vector3(0.5, 2.9, -2.0), Vector3(1.6, 2.95, 2.0), STEEL)
	# Zaun mit Pfosten, oberem Rohr, Maschen und Tor
	for pr: Array in [[Vector3(-5.3, 0, -3.9), Vector3(4.6, 0, -3.9)], [Vector3(4.6, 0, -3.9), Vector3(4.6, 0, 3.9)], [Vector3(0.7, 0, 3.9), Vector3(4.6, 0, 3.9)]]:
		var a: Vector3 = pr[0]
		var b: Vector3 = pr[1]
		var d := b - a
		var bas := Basis.looking_at(d.normalized(), Vector3.UP)
		var mid := (a + b) * 0.5
		var l := d.length()
		k.box(Vector3(-0.025, 1.8, -l * 0.5), Vector3(0.025, 1.86, l * 0.5), STEEL, Transform3D(bas, mid))
		k.box(Vector3(-0.02, 0.1, -l * 0.5), Vector3(0.02, 0.14, l * 0.5), STEEL, Transform3D(bas, mid))
		var bars := int(l / 0.15)
		for i in range(bars):
			var z := -l * 0.5 + (float(i) + 0.5) * l / float(bars)
			k.box(Vector3(-0.006, 0.12, z - 0.006), Vector3(0.006, 1.82, z + 0.006), Color(0.48, 0.52, 0.54), Transform3D(bas, mid))
		var steps := int(l / 2.0)
		for i in range(steps + 1):
			var q := a.lerp(b, float(i) / float(maxi(steps, 1)))
			k.cyl(q, q + Vector3(0, 1.95, 0), 0.04, 0.04, STEEL, 6)


## Heizzentrale: Klinkerbau mit Sprossenfenstern, Rolltoren, Attika, Schornstein mit Leiter
## und Bühnen, drei Dachlüfter (drehen sich), Rohrbrücke mit Vor- und Rücklauf, Rauch.
static func _heating(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-11, 0, -7.5), Vector3(11, 7.5, 7.5), BRICK)
	# Ziegelfugen und Sockel
	for y in range(1, 30):
		k.box(Vector3(-11.01, float(y) * 0.25, 7.5), Vector3(11.01, float(y) * 0.25 + 0.02, 7.51), BRICK.darkened(0.18))
	k.box(Vector3(-11.05, 0, -7.55), Vector3(11.05, 0.6, 7.55), CONCRETE)
	k.box(Vector3(-11.2, 7.5, -7.7), Vector3(11.2, 8.0, 7.7), CONCRETE)
	k.box(Vector3(-10.9, 7.5, -7.4), Vector3(10.9, 7.62, 7.4), ROOF)
	# Fensterband mit Sprossen
	for x in range(-9, 10, 3):
		k.box(Vector3(float(x) - 0.08, 4.7, 7.5), Vector3(float(x) + 1.48, 6.5, 7.56), CONCRETE)
		k.box(Vector3(float(x), 4.8, 7.52), Vector3(float(x) + 1.4, 6.4, 7.6), WIN)
		k.box(Vector3(float(x) + 0.68, 4.8, 7.6), Vector3(float(x) + 0.72, 6.4, 7.62), CONCRETE)
		k.box(Vector3(float(x), 5.58, 7.6), Vector3(float(x) + 1.4, 5.62, 7.62), CONCRETE)
	# zwei Rolltore mit Lamellen und Leuchte
	for x: float in [-6.0, 1.0]:
		k.box(Vector3(x - 0.15, 0, 7.5), Vector3(x + 4.15, 4.4, 7.58), CONCRETE)
		k.box(Vector3(x, 0, 7.55), Vector3(x + 4.0, 4.2, 7.62), Color(0.62, 0.64, 0.66))
		for i in range(18):
			k.box(Vector3(x, 0.2 + float(i) * 0.22, 7.62), Vector3(x + 4.0, 0.24 + float(i) * 0.22, 7.65), Color(0.52, 0.54, 0.56))
		k.box(Vector3(x + 1.7, 4.45, 7.55), Vector3(x + 2.3, 4.6, 7.75), LAMP)
	PixelFont.draw(k, "HEIZZENTRALE", Vector3(4.5, 6.95, 7.52), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.07, Color(0.92, 0.9, 0.85))
	# Schornstein
	var sc := Vector3(8, 8.0, -4)
	k.cyl(sc, sc + Vector3(0, 15.0, 0), 1.0, 0.82, Color(0.62, 0.62, 0.6), 18)
	for y: float in [3.0, 8.0, 13.2]:
		k.cyl(sc + Vector3(0, y, 0), sc + Vector3(0, y + 0.3, 0), 1.12, 1.12, Color(0.85, 0.15, 0.12) if y > 12.0 else DARK, 18)
	k.cyl(sc + Vector3(0, 14.6, 0), sc + Vector3(0, 15.0, 0), 0.9, 0.9, DARK, 18)
	for y in range(0, 30):
		k.box(sc + Vector3(0.95, float(y) * 0.5, -0.22), sc + Vector3(1.0, float(y) * 0.5 + 0.04, 0.22), STEEL)
	for sz: float in [-0.22, 0.22]:
		k.box(sc + Vector3(0.95, 0, sz - 0.02), sc + Vector3(1.0, 15.0, sz + 0.02), STEEL)
	k.box(sc + Vector3(-1.4, 7.9, -1.4), sc + Vector3(1.4, 8.0, 1.4), STEEL)
	k.box(sc + Vector3(-0.03, 15.0, -0.03), sc + Vector3(0.03, 15.8, 0.03), STEEL)
	k.box(sc + Vector3(-0.08, 15.75, -0.08), sc + Vector3(0.08, 15.9, 0.08), Color(1.0, 0.2, 0.15, 0.3))
	# Rauchwolken steigen auf
	var smoke := Kit.new()
	for i in range(4):
		smoke.sphere(Vector3(float(i) * 0.5, float(i) * 1.1, float(i) * 0.2), 0.7 + float(i) * 0.25, Color(0.86, 0.86, 0.86, 0.6), 8, 5)
	var sm := _part(n, "HubRauch", smoke, sc + Vector3(0, 15.6, 0))
	sm.set_meta("speed", 0.8)
	# Dachlüfter
	for x: float in [-6.0, -2.0, 2.0]:
		_fan(n, k, Vector3(x, 8.0, 0), 0.85, 2.5)
	# Rohrbrücke links mit Vor- (rot) und Rücklauf (blau), Isolierung
	for z: float in [3.0, 4.2]:
		var c := Color(0.85, 0.35, 0.2) if z < 4.0 else Color(0.25, 0.45, 0.75)
		k.cyl(Vector3(-11.0, 3.0, z), Vector3(-11.6, 3.0, z), 0.25, 0.25, c, 12)
		k.cyl(Vector3(-11.6, 3.0, z), Vector3(-11.6, 0.0, z), 0.25, 0.25, c, 12)
		k.sphere(Vector3(-11.6, 3.0, z), 0.25, c, 10, 6)
		k.cyl(Vector3(-11.2, 3.0, z), Vector3(-11.3, 3.0, z), 0.32, 0.32, STEEL, 12)
	k.box(Vector3(-11.9, 0, 2.5), Vector3(-11.3, 0.25, 4.7), CONCRETE)


## Wasseranschluss: Schacht mit Deckel, Pumpe, Rohre, Schieber mit Handrad und Hinweisschild.
static func _water(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-2, 0, -2), Vector3(2, 0.35, 2), CONCRETE)
	k.box(Vector3(-1.9, 0.35, -1.9), Vector3(1.9, 0.38, 1.9), CONCRETE.darkened(0.1))
	k.cyl(Vector3(-1.0, 0.38, 1.0), Vector3(-1.0, 0.42, 1.0), 0.45, 0.45, Color(0.25, 0.25, 0.27), 16)
	for i in range(4):
		k.box(Vector3(-1.4 + float(i) * 0.2, 0.42, 0.98), Vector3(-1.32 + float(i) * 0.2, 0.43, 1.02), Color(0.35, 0.35, 0.37))
	# Pumpe mit Motor
	var blue := Color(0.22, 0.45, 0.72)
	k.rounded_box(Vector3(-0.5, 0.38, -1.3), Vector3(0.7, 1.1, -0.5), 0.08, blue, 2)
	k.cyl(Vector3(0.7, 0.75, -0.9), Vector3(1.5, 0.75, -0.9), 0.3, 0.3, Color(0.55, 0.57, 0.6), 14)
	for i in range(6):
		k.cyl(Vector3(0.8 + float(i) * 0.12, 0.75, -0.9), Vector3(0.84 + float(i) * 0.12, 0.75, -0.9), 0.34, 0.34, Color(0.45, 0.47, 0.5), 14)
	k.cyl(Vector3(0.1, 1.1, -0.9), Vector3(0.1, 1.5, -0.9), 0.14, 0.14, blue, 12)
	k.cyl(Vector3(0.1, 1.5, -0.9), Vector3(0.1, 1.5, 0.6), 0.14, 0.14, blue, 12)
	k.cyl(Vector3(0.1, 1.5, 0.6), Vector3(0.1, 0.38, 0.6), 0.14, 0.14, blue, 12)
	for p: Vector3 in [Vector3(0.1, 1.5, -0.6), Vector3(0.1, 1.5, 0.3)]:
		k.cyl(p - Vector3(0, 0, 0.05), p + Vector3(0, 0, 0.05), 0.2, 0.2, blue.darkened(0.2), 12)
	# Schieber mit Handrad
	k.cyl(Vector3(0.1, 1.5, -0.15), Vector3(0.1, 1.85, -0.15), 0.05, 0.05, STEEL, 8)
	for i in range(12):
		var a0 := float(i) / 12.0 * TAU
		var a1 := float(i + 1) / 12.0 * TAU
		k.cyl(Vector3(0.1 + cos(a0) * 0.25, 1.87, -0.15 + sin(a0) * 0.25), Vector3(0.1 + cos(a1) * 0.25, 1.87, -0.15 + sin(a1) * 0.25), 0.025, 0.025, Color(0.85, 0.15, 0.12), 6, false)
	# Hinweisschild
	k.cyl(Vector3(1.6, 0.35, 1.6), Vector3(1.6, 1.6, 1.6), 0.03, 0.03, STEEL, 6)
	k.box(Vector3(1.35, 1.3, 1.62), Vector3(1.85, 1.6, 1.66), blue)
	PixelFont.draw(k, "H2O", Vector3(1.6, 1.45, 1.67), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.03, Color(1, 1, 1))


## Gerätehalle (Vorfelddepot): geschlossene Halle mit vier Rolltoren; dahinter parken Schlepper,
## Bodenstromgerät und Förderbandwagen. Die Fahrzeuge für die Abfertigung fahren hier los.
static func _depot(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-13, 0, -8), Vector3(13, 0.1, 8), Color(0.45, 0.45, 0.43))
	_shed(k, -13.0, -8.0, 13.0, 8.0, 6.2, CLAD, [[-9.0, 4.6, 4.4], [-3.0, 4.6, 4.4], [3.0, 4.6, 4.4], [9.0, 4.6, 4.4]])
	for x: float in [-9.0, -3.0, 3.0, 9.0]:
		Landmarks.roll_door(n, k, [-9.0, -3.0, 3.0, 9.0].find(x), Vector3(x, 0, 8.0), 4.6, 4.4, Color(0.62, 0.66, 0.7), 2)
	_ribs(k, Vector3(-13, 0.6, 8.0), Vector3(13, 6.0, 8.0), Vector3(0, 0, 1), CLAD.darkened(0.14), [[-11.5, -6.5], [-5.5, -0.5], [0.5, 5.5], [6.5, 11.5]], 4.95)
	k.box(Vector3(-12.0, 5.05, 8.02), Vector3(12.0, 5.75, 8.12), Color(0.16, 0.24, 0.38))
	PixelFont.draw(k, "GERAETEHALLE", Vector3(0, 5.4, 8.13), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.07, Color(0.95, 0.85, 0.3))
	for sx: float in [-1.0, 1.0]:
		var xo := sx * 13.0
		k.box(Vector3(xo, 3.4, -6.0), Vector3(xo + sx * 0.06, 4.6, 6.0), FRAME_C)
		k.box(Vector3(xo, 3.5, -5.9), Vector3(xo + sx * 0.09, 4.5, 5.9), WIN)
		for wz in range(-5, 7, 2):
			k.box(Vector3(xo, 3.4, float(wz) - 0.04), Vector3(xo + sx * 0.12, 4.6, float(wz) + 0.04), FRAME_C)
		_ribs(k, Vector3(xo, 0.6, -8.0), Vector3(xo, 3.3, 8.0), Vector3(sx, 0, 0), CLAD.darkened(0.14), [], 0.0)
	# Innen: Stellplätze, Werkbank, Reifenregal, abgestellte Geräte
	for x: float in [-6.0, 0.0, 6.0]:
		k.box(Vector3(x - 0.06, 0.1, -7.0), Vector3(x + 0.06, 0.11, 7.5), YELLOW)
	k.box(Vector3(-12.6, 0.1, -7.6), Vector3(-9.6, 0.95, -6.8), Color(0.35, 0.45, 0.6))
	k.box(Vector3(-12.65, 0.95, -7.65), Vector3(-9.55, 1.0, -6.75), Color(0.45, 0.32, 0.2))
	for i in range(4):
		k.cyl(Vector3(10.5, 0.45 + float(i) * 0.85, -7.2), Vector3(12.2, 0.45 + float(i) * 0.85, -7.2), 0.4, 0.4, DARK, 14)
	var Factory = load("res://scripts/factory.gd")
	for e: Array in [["schlepper", -9.0], ["gpu", -3.0], ["schlepper", 3.0], ["gpu", 9.0]]:
		var v: Node3D = Factory.make_gse(String(e[0]))
		v.position = Vector3(float(e[1]), 0.1, -4.6)
		v.rotation.y = PI
		n.add_child(v)
	_fan(n, k, Vector3(-6, 6.45, -2), 0.7, 2.4)
	_fan(n, k, Vector3(6, 6.45, -2), 0.7, 2.2)


## Hallenhülle mit Attika: Wände, Dach, Dachrand.
static func _shed(k: Kit, x0: float, z0: float, x1: float, z1: float, h: float, col: Color, doors: Array = []) -> void:
	k.box(Vector3(x0, 0, z0), Vector3(x1, h, z0 + 0.3), col)
	k.box(Vector3(x0, 0, z0), Vector3(x0 + 0.3, h, z1), col)
	k.box(Vector3(x1 - 0.3, 0, z0), Vector3(x1, h, z1), col)
	# Front: Pfeiler zwischen den Toren, Sturz darüber
	var cur := x0
	for d: Array in doors:
		var a := float(d[0]) - float(d[1]) * 0.5 - 0.12
		var b := float(d[0]) + float(d[1]) * 0.5 + 0.12
		if a > cur:
			k.box(Vector3(cur, 0, z1 - 0.3), Vector3(a, h, z1), col)
		k.box(Vector3(a, float(d[2]), z1 - 0.3), Vector3(b, h, z1), col)
		cur = b
	if cur < x1:
		k.box(Vector3(cur, 0, z1 - 0.3), Vector3(x1, h, z1), col)
	k.box(Vector3(x0 - 0.05, 0, z0 - 0.05), Vector3(x1 + 0.05, 0.6, z1 + 0.05), CONCRETE)
	k.box(Vector3(x0, h - 0.25, z0), Vector3(x1, h, z1), ROOF)
	k.box(Vector3(x0 - 0.1, h, z0 - 0.1), Vector3(x1 + 0.1, h + 0.45, z0 + 0.2), col.darkened(0.08))
	k.box(Vector3(x0 - 0.1, h, z1 - 0.2), Vector3(x1 + 0.1, h + 0.45, z1 + 0.1), col.darkened(0.08))
	k.box(Vector3(x0 - 0.1, h, z0 - 0.1), Vector3(x0 + 0.2, h + 0.45, z1 + 0.1), col.darkened(0.08))
	k.box(Vector3(x1 - 0.2, h, z0 - 0.1), Vector3(x1 + 0.1, h + 0.45, z1 + 0.1), col.darkened(0.08))
	k.box(Vector3(x0 + 0.2, h, z0 + 0.2), Vector3(x1 - 0.2, h + 0.04, z1 - 0.2), GRAVEL_C)


## Senkrechte Trapezblech-Rippen auf einer Wand (Lücken für Tore: [von, bis] entlang der Wand).
static func _ribs(k: Kit, a: Vector3, b: Vector3, nrm: Vector3, col: Color, gaps: Array, gap_top: float) -> void:
	var along := Vector3(1, 0, 0) if absf(nrm.z) > 0.5 else Vector3(0, 0, 1)
	var t0 := minf(a.dot(along), b.dot(along))
	var t1 := maxf(a.dot(along), b.dot(along))
	var t := t0 + 0.3
	while t < t1 - 0.2:
		var y0 := a.y
		for g: Array in gaps:
			if t > float(g[0]) and t < float(g[1]):
				y0 = gap_top
		var p := a - along * a.dot(along) + along * t
		k.box(Vector3(p.x, y0, p.z) - along * 0.04, Vector3(p.x, b.y, p.z) + along * 0.04 + nrm * 0.06, col)
		t += 0.55


## Tanklager: drei Kerosintanks mit Treppe und Geländer in einer Auffangwanne, Rohrbrücke,
## Pumpenhaus, Füllstation mit Ladearmen, Wagenhalle mit zwei Rolltoren für die Tankwagen.
static func _fuel_farm(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-22, 0, -16), Vector3(22, 0.08, 16), Color(0.5, 0.5, 0.47))
	# Auffangwanne
	k.box(Vector3(-21, 0.08, -15.5), Vector3(13, 0.12, 3.0), Color(0.58, 0.57, 0.53))
	for e: Array in [[Vector3(-21, 0, -15.5), Vector3(13, 1.2, -15.1)], [Vector3(-21, 0, 2.6), Vector3(13, 1.2, 3.0)],
			[Vector3(-21, 0, -15.5), Vector3(-20.6, 1.2, 3.0)], [Vector3(12.6, 0, -15.5), Vector3(13, 1.2, 3.0)]]:
		k.box(e[0], e[1], CONCRETE)
	for tx: float in [-15.0, -4.0, 7.0]:
		var c := Vector3(tx, 0.12, -6.5)
		k.cyl(c, c + Vector3(0, 11.0, 0), 4.8, 4.8, Color(0.92, 0.92, 0.9), 32, false)
		k.cyl(c + Vector3(0, 11.0, 0), c + Vector3(0, 12.2, 0), 4.85, 1.0, Color(0.86, 0.86, 0.84), 32)
		k.cyl(c + Vector3(0, 7.6, 0), c + Vector3(0, 8.4, 0), 4.82, 4.82, Color(0.2, 0.36, 0.62), 32, false)
		k.cyl(c + Vector3(0, 0.0, 0), c + Vector3(0, 0.25, 0), 4.95, 4.95, CONCRETE, 32)
		PixelFont.draw(k, "JET A-1", c + Vector3(0, 5.5, 4.83), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.16, Color(0.2, 0.36, 0.62))
		# Wendeltreppe außen am Tank
		for i in range(22):
			var a0 := PI * 0.15 + float(i) * 0.12
			var y := 0.4 + float(i) * 0.5
			var d := Vector3(cos(a0), 0, sin(a0))
			var p0 := c + d * 4.85 + Vector3(0, y, 0)
			k.box(p0 + Vector3(-0.35, -0.03, -0.35), p0 + Vector3(0.35, 0.03, 0.35), STEEL)
			k.cyl(c + d * 5.5 + Vector3(0, y, 0), c + d * 5.5 + Vector3(0, y + 1.0, 0), 0.025, 0.025, YELLOW, 4, false)
		# Geländer oben
		for i in range(16):
			var a0 := float(i) / 16.0 * TAU
			var a1 := float(i + 1) / 16.0 * TAU
			var p0 := c + Vector3(cos(a0), 0, sin(a0)) * 4.6 + Vector3(0, 11.3, 0)
			var p1 := c + Vector3(cos(a1), 0, sin(a1)) * 4.6 + Vector3(0, 11.3, 0)
			k.cyl(p0 + Vector3(0, 1.0, 0), p1 + Vector3(0, 1.0, 0), 0.03, 0.03, YELLOW, 4, false)
			k.cyl(p0, p0 + Vector3(0, 1.0, 0), 0.025, 0.025, YELLOW, 4, false)
		k.cyl(c + Vector3(0, 12.2, 0), c + Vector3(0, 12.8, 0), 0.25, 0.25, STEEL, 10)
		# Leitung zur Rohrbrücke
		k.cyl(c + Vector3(0, 0.8, 4.8), c + Vector3(0, 0.8, 8.0), 0.22, 0.22, Color(0.75, 0.75, 0.72), 10)
		k.cyl(c + Vector3(-0.3, 0.8, 5.6), c + Vector3(0.3, 0.8, 5.6), 0.12, 0.12, Color(0.85, 0.15, 0.12), 8)
	k.cyl(Vector3(-15, 0.8, 1.5), Vector3(18, 0.8, 1.5), 0.25, 0.25, Color(0.75, 0.75, 0.72), 12)
	for x in range(-14, 18, 4):
		k.box(Vector3(float(x) - 0.12, 0.08, 1.3), Vector3(float(x) + 0.12, 0.65, 1.7), CONCRETE)
	# Pumpenhaus
	k.box(Vector3(14.5, 0, -14), Vector3(21.5, 4.2, -6), RENDER)
	k.box(Vector3(14.3, 4.2, -14.2), Vector3(21.7, 4.5, -5.8), ROOF)
	k.box(Vector3(17, 0, -6.02), Vector3(19, 2.6, -5.94), Color(0.5, 0.55, 0.6))
	_fan(n, k, Vector3(18, 4.5, -10), 0.6, 3.0)
	PixelFont.draw(k, "PUMPEN", Vector3(18, 3.4, -5.93), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.08, DARK)
	# Füllstation mit Dach und Ladearmen
	k.box(Vector3(14.5, 0.08, -3), Vector3(21.5, 0.2, 7), CONCRETE)
	for c: Vector2 in [Vector2(15, -2.5), Vector2(21, -2.5), Vector2(15, 6.5), Vector2(21, 6.5)]:
		k.box(Vector3(c.x - 0.2, 0.2, c.y - 0.2), Vector3(c.x + 0.2, 6.0, c.y + 0.2), STEEL)
	k.box(Vector3(14.2, 6.0, -3.2), Vector3(21.8, 6.5, 7.2), Color(0.85, 0.85, 0.83))
	k.box(Vector3(14.2, 5.8, -3.2), Vector3(21.8, 6.0, 7.2), Color(0.2, 0.36, 0.62))
	for z: float in [0.0, 4.0]:
		k.box(Vector3(17.6, 0.2, z - 0.4), Vector3(18.4, 1.6, z + 0.4), Color(0.55, 0.57, 0.6))
		k.cyl(Vector3(18, 1.6, z), Vector3(18, 4.6, z), 0.12, 0.12, YELLOW, 8)
		k.cyl(Vector3(18, 4.6, z), Vector3(16.6, 4.2, z), 0.1, 0.1, YELLOW, 8)
		k.cyl(Vector3(16.6, 4.2, z), Vector3(16.6, 2.6, z), 0.08, 0.08, DARK, 8)
		k.box(Vector3(17.5, 1.0, z - 0.42), Vector3(18.5, 1.4, z - 0.4), Color(1.0, 0.92, 0.72, 0.3))
	for lx: float in [16.0, 20.0]:
		k.box(Vector3(lx - 0.5, 5.7, 1.5), Vector3(lx + 0.5, 5.8, 2.5), LAMP)
	# Wagenhalle für die Tankwagen
	_shed(k, -13.0, 4.0, 13.0, 16.0, 6.0, Color(0.82, 0.83, 0.82), [[-7.0, 5.0, 4.6], [7.0, 5.0, 4.6]])
	for i in range(2):
		Landmarks.roll_door(n, k, i, Vector3(-7.0 + float(i) * 14.0, 0, 16.0), 5.0, 4.6, Color(0.62, 0.66, 0.7), 2)
	_ribs(k, Vector3(-13, 0.6, 16.0), Vector3(13, 6.0, 16.0), Vector3(0, 0, 1), Color(0.7, 0.71, 0.7), [[-9.8, -4.2], [4.2, 9.8]], 5.15)
	k.box(Vector3(-3.0, 3.2, 16.02), Vector3(3.0, 4.4, 16.1), Color(0.2, 0.36, 0.62))
	PixelFont.draw(k, "FUEL", Vector3(0, 3.8, 16.11), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.13, Color(0.98, 0.98, 0.95))
	# Warnschilder, Feuerlöscher, Notausschalter
	for x: float in [-11.5, 11.5]:
		k.box(Vector3(x - 0.5, 1.6, 16.02), Vector3(x + 0.5, 2.4, 16.08), Color(0.95, 0.8, 0.15))
		k.cyl(Vector3(x, 0.0, 16.4), Vector3(x, 0.7, 16.4), 0.12, 0.12, Color(0.85, 0.12, 0.1), 8)
	k.box(Vector3(19.5, 0.2, 7.2), Vector3(20.3, 1.5, 7.5), Color(0.85, 0.12, 0.1))


## Busgarage: Halle mit drei Rolltoren, Büroanbau, Waschanlage mit drehenden Bürsten, Wegweiser.
static func _bus_depot(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-18, 0, -11), Vector3(18, 0.08, 11), Color(0.46, 0.46, 0.44))
	_shed(k, -18.0, -11.0, 14.0, 11.0, 7.0, Color(0.8, 0.8, 0.78), [[-11.0, 5.0, 4.6], [0.0, 5.0, 4.6], [11.0, 5.0, 4.6]])
	for i in range(3):
		Landmarks.roll_door(n, k, i, Vector3(-11.0 + float(i) * 11.0, 0, 11.0), 5.0, 4.6, Color(0.95, 0.75, 0.2), 3)
	_ribs(k, Vector3(-18, 0.6, 11.0), Vector3(14, 7.0, 11.0), Vector3(0, 0, 1), Color(0.68, 0.68, 0.66), [[-13.8, -8.2], [-2.8, 2.8], [8.2, 13.8]], 5.15)
	k.box(Vector3(-17.0, 5.6, 11.02), Vector3(-14.0, 6.6, 11.1), Color(0.16, 0.24, 0.38))
	PixelFont.draw(k, "BUS", Vector3(-15.5, 6.1, 11.11), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.12, Color(0.98, 0.85, 0.3))
	for x in range(-15, 13, 4):
		k.box(Vector3(float(x), 7.0, -8.0), Vector3(float(x) + 2.2, 7.35, 8.0), Color(0.55, 0.7, 0.8, 0.6))
	# Waschanlage an der Seite: Portal mit zwei drehenden Bürsten
	k.box(Vector3(14.2, 0.08, -10.5), Vector3(17.8, 0.12, 10.5), Color(0.38, 0.4, 0.42))
	for z: float in [-2.0, 2.0]:
		for sx: float in [14.4, 17.6]:
			k.box(Vector3(sx - 0.15, 0.1, z - 0.15), Vector3(sx + 0.15, 4.4, z + 0.15), Color(0.2, 0.45, 0.8))
		k.box(Vector3(14.2, 4.4, z - 0.25), Vector3(17.8, 4.7, z + 0.25), Color(0.2, 0.45, 0.8))
	for e: Array in [[14.9, 1.5], [17.1, -1.5]]:
		var bk := Kit.new()
		bk.cyl(Vector3(0, 0, 0), Vector3(0, 3.6, 0), 0.07, 0.07, STEEL, 6)
		for i in range(10):
			var a := float(i) / 10.0 * TAU
			bk.box(Vector3(cos(a) * 0.1 - 0.03, 0.2, sin(a) * 0.1 - 0.03), Vector3(cos(a) * 0.55 + 0.03, 3.5, sin(a) * 0.55 + 0.03), Color(0.25, 0.55, 0.95) if i % 2 == 0 else Color(0.85, 0.2, 0.2))
		var br := _part(n, "DrehBuerste%d" % int(e[0]), bk, Vector3(float(e[0]), 0.4, 0))
		br.set_meta("speed", float(e[1]) * 2.0)
	# Büroanbau
	k.box(Vector3(-18, 0, -11), Vector3(-12, 7.0, -5), RENDER)
	for y: float in [1.6, 4.8]:
		_window_strip(k, Vector3(-18.0, y, -8.0), Vector3(0, 0, 2.4), Vector3(-1, 0, 0))
	_fan(n, k, Vector3(-4, 7.0, -4), 0.7, 2.0)
	k.add_mesh(Models.gse_mesh("bus"), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(16.0, 0.12, 6.0)), true)


## Rettungswache: Fahrzeughalle mit zwei roten Rolltoren, Bürotrakt, rote Bauchbinde, Schild,
## im Hof ein geparkter RTW.
static func _rescue_station(n: Node3D, k: Kit) -> void:
	var red := Color(0.82, 0.12, 0.1)
	k.box(Vector3(-9, 0, -7), Vector3(9, 0.08, 7), Color(0.46, 0.46, 0.44))
	k.box(Vector3(-7, 0, -6), Vector3(7, 5.6, 7), RENDER)
	k.box(Vector3(-7.05, 3.9, -6.05), Vector3(7.05, 4.5, 7.05), red)
	k.box(Vector3(-7.2, 5.6, -6.2), Vector3(7.2, 5.9, 7.2), Color(0.8, 0.8, 0.78))
	k.box(Vector3(-6.8, 5.9, -5.8), Vector3(6.8, 5.95, 6.8), ROOF)
	for i in range(2):
		Landmarks.roll_door(n, k, i, Vector3(-3.5 + float(i) * 7.0, 0, 7.0), 4.2, 3.8, Color(0.85, 0.15, 0.12), 2)
	# Bürotrakt mit Fensterband
	k.box(Vector3(-9, 0, -7), Vector3(-7, 6.4, 3), RENDER)
	_window_strip(k, Vector3(-9.0, 1.6, -2.0), Vector3(0, 0, 4.0), Vector3(-1, 0, 0))
	_window_strip(k, Vector3(-9.0, 4.4, -2.0), Vector3(0, 0, 4.0), Vector3(-1, 0, 0))
	k.box(Vector3(-3.0, 4.55, 7.05), Vector3(3.0, 5.45, 7.15), Color(0.95, 0.95, 0.93))
	PixelFont.draw(k, "RETTUNGSWACHE", Vector3(0, 5.0, 7.16), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.07, red)
	# Stern des Lebens als blaues Kreuz-Schild
	k.box(Vector3(5.2, 4.6, 7.05), Vector3(6.4, 5.4, 7.15), Color(0.95, 0.95, 0.93))
	k.box(Vector3(5.7, 4.7, 7.16), Vector3(5.9, 5.3, 7.18), Color(0.15, 0.35, 0.75))
	k.box(Vector3(5.5, 4.9, 7.16), Vector3(6.1, 5.1, 7.18), Color(0.15, 0.35, 0.75))
	# Stellplatz an der Seite: geparkter Reserve-RTW
	k.box(Vector3(7.0, 0.08, -6.5), Vector3(9.0, 0.1, 6.5), Color(0.38, 0.4, 0.42))
	k.add_mesh(Landmarks.rtw_mesh(), Transform3D(Basis.IDENTITY, Vector3(8.0, 0.1, 0.5)), true)


## Wohngebiet (70 × 60 m): Straße mit Einfamilienhäusern, Gärten, Hecken und Bäumen.
static func _village(k: Kit) -> void:
	k.box(Vector3(-35, 0, -2.5), Vector3(35, 0.05, 2.5), Color(0.32, 0.33, 0.35))
	var roofs := [Color(0.62, 0.22, 0.15), Color(0.45, 0.25, 0.2), Color(0.3, 0.3, 0.33), Color(0.7, 0.35, 0.2)]
	var walls := [Color(0.93, 0.9, 0.82), Color(0.9, 0.85, 0.72), Color(0.85, 0.88, 0.9), Color(0.95, 0.93, 0.88)]
	var i := 0
	for row: float in [-1.0, 1.0]:
		for x: float in [-27.0, -13.5, 0.0, 13.5, 27.0]:
			var z := row * 16.0
			var w := 8.0 + float(i % 3)
			var d := 9.0
			var h := 5.5 + float(i % 2)
			k.box(Vector3(x - 6.2, 0.02, z - 12.0 * absf(row) * 0.0 - 11.0 * 0.5 - 2.5), Vector3(x + 6.2, 0.05, z + 11.0 * 0.5 + 2.5), Color(0.38, 0.55, 0.28))
			k.box(Vector3(x - w * 0.5, 0, z - d * 0.5), Vector3(x + w * 0.5, h, z + d * 0.5), walls[i % walls.size()])
			# Satteldach
			var rc: Color = roofs[i % roofs.size()]
			k.prism([Vector3(x - w * 0.5 - 0.4, h, z - d * 0.5 - 0.4), Vector3(x + w * 0.5 + 0.4, h, z - d * 0.5 - 0.4),
				Vector3(x + w * 0.5 + 0.4, h, z + d * 0.5 + 0.4), Vector3(x - w * 0.5 - 0.4, h, z + d * 0.5 + 0.4)],
				[Vector3(x - w * 0.5 - 0.4, h + 3.2, z), Vector3(x + w * 0.5 + 0.4, h + 3.2, z), Vector3(x + w * 0.5 + 0.4, h + 3.2, z), Vector3(x - w * 0.5 - 0.4, h + 3.2, z)], rc)
			for wx: float in [-w * 0.25, w * 0.25]:
				for wy: float in [1.4, 3.8]:
					k.box(Vector3(x + wx - 0.6, wy, z - row * d * 0.5 - row * 0.03), Vector3(x + wx + 0.6, wy + 1.1, z - row * d * 0.5 + row * 0.0 - row * 0.06), WIN)
			k.box(Vector3(x - 0.5, 0, z - row * d * 0.5 - row * 0.05), Vector3(x + 0.5, 2.1, z - row * d * 0.5 - row * 0.1), Color(0.4, 0.28, 0.18))
			# Hecke und Baum im Garten
			k.box(Vector3(x - 6.0, 0, z + row * 7.5 - 0.4), Vector3(x + 6.0, 1.2, z + row * 7.5 + 0.4), Color(0.2, 0.4, 0.18, 0.8))
			k.cyl(Vector3(x + 4.0, 0, z + row * 5.0), Vector3(x + 4.0, 2.4, z + row * 5.0), 0.18, 0.14, Color(0.4, 0.28, 0.18), 6)
			k.sphere(Vector3(x + 4.0, 3.6, z + row * 5.0), 1.7, Color(0.25, 0.48, 0.22, 0.8), 8, 5)
			i += 1


static func _window_strip(k: Kit, c: Vector3, half: Vector3, nrm: Vector3) -> void:
	k.box(c - half - Vector3(0, 0.6, 0), c + half + Vector3(0, 0.6, 0) + nrm * 0.05, FRAME_C)
	k.box(c - half * 0.97 - Vector3(0, 0.52, 0), c + half * 0.97 + Vector3(0, 0.52, 0) + nrm * 0.08, WIN)


## Cateringbetrieb: Großküche mit blauem Band, Laderampe mit zwei Rolltoren, Rollwagen voller
## Trolleys, Küchenabluft (dampft), Lüfter auf dem Dach, Personaleingang.
static func _catering(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-15, 0, -10), Vector3(15, 0.08, 10), Color(0.46, 0.46, 0.44))
	k.box(Vector3(-15, 0, -10), Vector3(15, 7.4, 4.0), RENDER)
	k.box(Vector3(-15.05, 0, -10.05), Vector3(15.05, 0.6, 4.05), CONCRETE)
	k.box(Vector3(-15.03, 5.6, -10.03), Vector3(15.03, 6.4, 4.03), Color(0.2, 0.42, 0.7))
	k.box(Vector3(-15.2, 7.4, -10.2), Vector3(15.2, 7.8, 4.2), Color(0.8, 0.8, 0.78))
	k.box(Vector3(-14.8, 7.4, -9.8), Vector3(14.8, 7.45, 3.8), ROOF)
	PixelFont.draw(k, "BORDKUECHE", Vector3(4.0, 6.0, 4.04), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.1, Color(0.98, 0.98, 0.95))
	# Ladezone vor der Halle: Vorbau mit zwei Toren
	_shed(k, -11.0, 3.8, 6.0, 10.0, 5.4, RENDER.darkened(0.04), [[-7.0, 4.0, 4.2], [2.0, 4.0, 4.2]])
	for i in range(2):
		Landmarks.roll_door(n, k, i, Vector3(-7.0 + float(i) * 9.0, 0, 10.0), 4.0, 4.2, Color(0.88, 0.88, 0.86), 2)
	for x: float in [-10.0, -4.4, 4.6]:
		k.box(Vector3(x - 0.3, 0.0, 10.0), Vector3(x + 0.3, 1.0, 10.3), DARK)
	# Fenster der Küche, Personaleingang, Trolleys
	for x in range(8, 15, 3):
		_window_strip(k, Vector3(float(x), 2.2, 4.0), Vector3(1.0, 0, 0), Vector3(0, 0, 1))
	k.box(Vector3(10.0, 0.6, 4.0), Vector3(11.4, 2.8, 4.08), Color(0.5, 0.55, 0.6))
	k.box(Vector3(9.6, 3.0, 4.0), Vector3(11.8, 3.15, 5.2), Color(0.8, 0.8, 0.78))
	for i in range(5):
		var tx := 7.2 + float(i) * 0.5
		k.box(Vector3(tx, 0.08, 6.0), Vector3(tx + 0.4, 1.05, 6.8), CHROME_C)
		k.box(Vector3(tx + 0.02, 0.6, 6.79), Vector3(tx + 0.38, 0.75, 6.81), Color(0.2, 0.42, 0.7))
	for sx: float in [-8.0, 0.0, 8.0]:
		_fan(n, k, Vector3(sx, 7.45, -3.0), 0.8, 2.6)
	var steam := Kit.new()
	for i in range(4):
		steam.sphere(Vector3(float(i) * 0.3, float(i) * 0.7, 0), 0.4 + float(i) * 0.15, Color(0.95, 0.95, 0.95, 0.6), 8, 5)
	k.cyl(Vector3(-12, 7.45, -7), Vector3(-12, 9.5, -7), 0.35, 0.35, STEEL, 12)
	var st := _part(n, "HubDampf", steam, Vector3(-12, 9.8, -7))
	st.set_meta("speed", 1.2)
	k.box(Vector3(12.5, 0.08, 7.0), Vector3(14.5, 1.3, 9.0), Color(0.25, 0.45, 0.3))
	k.box(Vector3(12.5, 1.3, 7.0), Vector3(14.5, 1.38, 9.0), Color(0.2, 0.35, 0.25))


## Personalgebäude: drei Geschosse mit Fensterbändern, Vordach, Schiebetür, Fahrradständer mit
## Rädern, Raucherunterstand, Solardach, Schriftzug.
static func _staff_building(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-14, 0, -8), Vector3(14, 0.06, 8), Color(0.6, 0.6, 0.57))
	k.box(Vector3(-13, 0, -6.5), Vector3(13, 10.8, 5.5), RENDER)
	k.box(Vector3(-13.05, 0, -6.55), Vector3(13.05, 0.6, 5.55), CONCRETE)
	k.box(Vector3(-13.2, 10.8, -6.7), Vector3(13.2, 11.3, 5.7), Color(0.78, 0.78, 0.76))
	k.box(Vector3(-12.9, 10.8, -6.4), Vector3(12.9, 10.85, 5.4), ROOF)
	for f in range(3):
		var y := 1.8 + float(f) * 3.4
		for side: Array in [[Vector3(0, 0, 5.5), Vector3(1, 0, 0), 12.4], [Vector3(0, 0, -6.5), Vector3(-1, 0, 0), 12.4]]:
			var c: Vector3 = side[0]
			var r: Vector3 = side[1]
			var nrm := Vector3(0, 0, signf(c.z))
			k.box(c + Vector3(0, y - 0.75, 0) - r * float(side[2]), c + Vector3(0, y + 0.75, 0) + r * float(side[2]) + nrm * 0.05, FRAME_C)
			k.box(c + Vector3(0, y - 0.68, 0) - r * (float(side[2]) - 0.05), c + Vector3(0, y + 0.68, 0) + r * (float(side[2]) - 0.05) + nrm * 0.08, WIN)
			var mx := -12.0
			while mx < 12.5:
				k.box(c + Vector3(mx - 0.04, y - 0.75, 0), c + Vector3(mx + 0.04, y + 0.75, 0) + nrm * 0.11, FRAME_C)
				mx += 1.6
		k.box(Vector3(-13.02, y + 1.0, -6.52), Vector3(13.02, y + 1.12, 5.52), RENDER.darkened(0.08))
	# Eingang mit Schiebetür und Vordach
	k.box(Vector3(-1.6, 0.6, 5.5), Vector3(1.6, 3.0, 5.58), FRAME_C)
	for e: Array in [["SchiebTuerL", -0.75, -1.4], ["SchiebTuerR", 0.75, 1.4]]:
		var dk := Kit.new()
		dk.box(Vector3(-0.72, 0, -0.03), Vector3(0.72, 2.3, 0.03), Color(0.5, 0.62, 0.68, 0.6))
		dk.box(Vector3(-0.72, 0, -0.035), Vector3(0.72, 0.08, 0.035), STEEL)
		var door := _part(n, String(e[0]), dk, Vector3(float(e[1]), 0.62, 5.62))
		door.set_meta("dx", float(e[2]))
		door.set_meta("phase", 0.3)
	k.box(Vector3(-3.0, 3.2, 5.5), Vector3(3.0, 3.45, 8.0), Color(0.8, 0.8, 0.78))
	for x: float in [-2.8, 2.8]:
		k.cyl(Vector3(x, 0.06, 7.8), Vector3(x, 3.2, 7.8), 0.07, 0.07, STEEL, 8)
	k.box(Vector3(-0.6, 3.15, 6.6), Vector3(0.6, 3.2, 7.2), LAMP)
	k.box(Vector3(-5.0, 9.4, 5.52), Vector3(5.0, 10.4, 5.62), Color(0.16, 0.24, 0.38))
	PixelFont.draw(k, "PERSONAL", Vector3(0, 9.9, 5.63), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.12, Color(0.98, 0.98, 0.95))
	# Fahrradständer mit Rädern
	for i in range(7):
		var bx := -12.0 + float(i) * 0.9
		k.cyl(Vector3(bx, 0.06, 6.6), Vector3(bx, 0.7, 6.6), 0.02, 0.02, CHROME_C, 5)
		if i % 3 != 1:
			var col := [Color(0.8, 0.2, 0.15), Color(0.2, 0.4, 0.75), Color(0.15, 0.15, 0.16), Color(0.3, 0.6, 0.35)][i % 4] as Color
			for wz: float in [6.1, 7.2]:
				k.cyl(Vector3(bx - 0.03, 0.36, wz), Vector3(bx + 0.03, 0.36, wz), 0.34, 0.34, DARK, 14, true, Color(0.3, 0.3, 0.3))
			k.cyl(Vector3(bx, 0.36, 6.1), Vector3(bx, 0.75, 6.75), 0.025, 0.025, col, 5)
			k.cyl(Vector3(bx, 0.75, 6.75), Vector3(bx, 0.36, 7.2), 0.025, 0.025, col, 5)
			k.cyl(Vector3(bx, 0.75, 6.45), Vector3(bx, 0.75, 6.95), 0.025, 0.025, col, 5)
			k.box(Vector3(bx - 0.08, 0.85, 6.55), Vector3(bx + 0.08, 0.9, 6.8), DARK)
	k.box(Vector3(-12.4, 2.2, 5.9), Vector3(-6.0, 2.3, 7.6), Color(0.6, 0.75, 0.8, 0.6))
	for c: Vector2 in [Vector2(-12.3, 7.5), Vector2(-6.1, 7.5)]:
		k.cyl(Vector3(c.x, 0.06, c.y), Vector3(c.x, 2.2, c.y), 0.05, 0.05, STEEL, 6)
	# Raucherunterstand
	k.box(Vector3(8.0, 0.06, 6.2), Vector3(11.0, 2.4, 6.3), Color(0.6, 0.75, 0.8, 0.6))
	k.box(Vector3(7.9, 2.4, 6.0), Vector3(11.1, 2.5, 7.8), STEEL)
	k.box(Vector3(8.3, 0.06, 6.35), Vector3(10.7, 0.5, 6.7), Color(0.55, 0.4, 0.25))
	k.cyl(Vector3(11.3, 0.06, 7.0), Vector3(11.3, 0.95, 7.0), 0.15, 0.15, STEEL, 10)
	var Factory = load("res://scripts/factory.gd")
	for e: Array in [[Vector3(9.0, 0.06, 6.9), 0, Color(0.95, 0.85, 0.1)], [Vector3(10.0, 0.06, 7.2), 5, Color(0.2, 0.3, 0.52)]]:
		var per: Node3D = Factory.make_staff(e[2], Color(0.15, 0.16, 0.2), randi() % 4, true)
		per.position = e[0]
		per.rotation.y = randf_range(-0.6, 0.6)
		Factory.set_pose(per, int(e[1]))
		n.add_child(per)
	# Solardach und Lüfter
	for r in range(4):
		var z := -5.6 + float(r) * 2.6
		k.quad(Vector3(-12, 11.2, z + 1.6), Vector3(4, 11.2, z + 1.6), Vector3(4, 11.8, z), Vector3(-12, 11.8, z), Color(0.12, 0.17, 0.32), Vector3(-4, 10.0, z + 0.4))
	_fan(n, k, Vector3(8, 10.85, -2.0), 0.8, 2.3)
	_fan(n, k, Vector3(10.5, 10.85, 2.0), 0.6, 2.8)
