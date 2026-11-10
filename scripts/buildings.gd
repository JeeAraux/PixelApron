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

const IDS := ["trafo", "heizzentrale", "wasseranschluss", "vorfelddepot"]


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


## Vorfelddepot: offene Halle mit Stahlstützen, Lichtband, Wartungsgrube, Werkbank,
## Reifenregal und drei Fahrzeugen (Tank, Catering, Gepäckschlepper).
static func _depot(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-13, 0, -8), Vector3(13, 0.1, 8), Color(0.42, 0.42, 0.4))
	k.box(Vector3(-13, 0, -8), Vector3(13, 6.0, -6.6), CONCRETE)
	for x in range(-12, 13, 2):
		k.box(Vector3(float(x) - 0.02, 0.6, -6.6), Vector3(float(x) + 0.02, 5.8, -6.58), CONCRETE.darkened(0.08))
	k.box(Vector3(-13, 0, -8), Vector3(-11.6, 6.0, 8), CONCRETE)
	k.box(Vector3(11.6, 0, -8), Vector3(13, 6.0, 8), CONCRETE)
	k.box(Vector3(-13.3, 6.0, -8.3), Vector3(13.3, 6.45, 8.3), ROOF)
	k.box(Vector3(-13.35, 5.7, -8.35), Vector3(13.35, 6.0, 8.35), STEEL)
	for x in range(-11, 12, 3):
		k.box(Vector3(float(x) - 0.6, 6.45, -6.0), Vector3(float(x) + 0.6, 6.7, 6.0), Color(0.6, 0.75, 0.82, 0.6))
	# offene Front mit Stützen, Schutzanstrich, Lampen
	for x: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		k.box(Vector3(x - 0.25, 0.1, 7.6), Vector3(x + 0.25, 5.7, 8.0), STEEL)
		for i in range(4):
			k.box(Vector3(x - 0.27, 0.1 + float(i) * 0.3, 7.58), Vector3(x + 0.27, 0.25 + float(i) * 0.3, 8.02), YELLOW if i % 2 == 0 else DARK)
		k.box(Vector3(x - 0.4, 5.2, 7.4), Vector3(x + 0.4, 5.35, 7.6), LAMP)
	k.box(Vector3(-11.6, 5.3, 7.6), Vector3(11.6, 5.7, 8.0), STEEL)
	PixelFont.draw(k, "GSE DEPOT", Vector3(0, 5.5, 8.02), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.07, Color(0.95, 0.85, 0.3))
	# Bodenmarkierungen der Stellplätze, Grube, Werkbank, Reifenregal
	for x: float in [-10.5, -3.5, 3.5, 10.5]:
		k.box(Vector3(x - 0.06, 0.1, -6.0), Vector3(x + 0.06, 0.11, 7.0), YELLOW)
	k.box(Vector3(5.0, 0.1, -5.0), Vector3(6.0, 0.11, 2.0), Color(0.2, 0.2, 0.2))
	k.box(Vector3(-11.4, 0.1, -6.4), Vector3(-8.0, 0.95, -5.6), Color(0.35, 0.45, 0.6))
	k.box(Vector3(-11.45, 0.95, -6.45), Vector3(-7.95, 1.0, -5.55), Color(0.45, 0.32, 0.2))
	for i in range(5):
		k.box(Vector3(-11.2 + float(i) * 0.6, 1.0, -6.3), Vector3(-10.9 + float(i) * 0.6, 1.25, -6.0), Color.from_hsv(float(i) * 0.2, 0.6, 0.7))
	for i in range(4):
		k.cyl(Vector3(9.5, 0.45 + float(i) * 0.85, -6.2), Vector3(11.2, 0.45 + float(i) * 0.85, -6.2), 0.4, 0.4, DARK, 14)
	# Fahrzeuge
	var Factory = load("res://scripts/factory.gd")
	for e: Array in [["tank", -7.0], ["catering", 0.0], ["gepaeck", 7.0]]:
		var v: Node3D = Factory.make_gse(String(e[0]))
		v.position = Vector3(float(e[1]), 0.1, 0)
		n.add_child(v)
