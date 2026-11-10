extends RefCounted
## Bauten ab 0.13 im feinen Stil: Frachtterminal, Winterdienst, S-Bahnhof, Taxistand, Kiss & Fly,
## Mietwagenzentrum und im Terminal Airline-Lounge, Gepäckermittlung und Gepäckdurchleuchtung.
## Vorderseite +Z. Fenster Alpha 0.6, Lampen Alpha 0.3 (leuchten nachts).

const Kit = preload("res://scripts/mesh_kit.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")
const Models = preload("res://scripts/models.gd")
const Landmarks = preload("res://scripts/landmarks.gd")

const CONCRETE := Color(0.62, 0.61, 0.57)
const ASPHALT := Color(0.3, 0.3, 0.29)
const ROOF := Color(0.34, 0.34, 0.32)
const STEEL := Color(0.4, 0.44, 0.47)
const CHROME := Color(0.74, 0.76, 0.79)
const DARK := Color(0.12, 0.12, 0.13)
const WIN := Color(0.22, 0.32, 0.38, 0.6)
const LAMP := Color(1.0, 0.92, 0.72, 0.3)
const YELLOW := Color(0.9, 0.72, 0.16)
const WHITE := Color(0.94, 0.94, 0.92)
const CLAD := Color(0.66, 0.7, 0.74)
const WOOD := Color(0.55, 0.4, 0.26)
const CARPET := Color(0.3, 0.26, 0.38)

const IDS := ["frachtterminal", "winterdienst", "bahnhof", "taxistand", "kissandfly", "mietwagen",
	"airline_lounge", "gepaeckermittlung", "gepaeckroentgen"]


static func build(n: Node3D, id: String) -> bool:
	if not (id in IDS):
		return false
	var k := Kit.new()
	match id:
		"frachtterminal":
			_cargo(n, k)
		"winterdienst":
			_winter(n, k)
		"bahnhof":
			_station(n, k)
		"taxistand":
			_taxi(n, k)
		"kissandfly":
			_kiss(n, k)
		"mietwagen":
			_rental(n, k)
		"airline_lounge":
			_lounge(k)
		"gepaeckermittlung":
			_lost_found(k)
		"gepaeckroentgen":
			_eds(k)
	n.add_child(k.instance("Bau"))
	return true


## Ribbed cladding: waagrechte Profile auf einer Fassadenfläche (Normale ±X oder ±Z).
static func _ribs(k: Kit, a: Vector3, b: Vector3, h0: float, h1: float, step: float, col: Color) -> void:
	var y := h0
	while y < h1:
		k.box(Vector3(a.x, y, a.z), Vector3(b.x, y + 0.06, b.z), col)
		y += step


## Frachtumschlaghalle: hohe Halle mit Blechfassade, sechs Ladetore mit Torabdichtung und Überladebrücke
## zum Vorfeld (+Z), Bürokopf mit Fensterband, Container (ULD) auf Dollys, Palettenregal, Schriftzug.
static func _cargo(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-30, 0, -18), Vector3(30, 0.15, 18), CONCRETE)
	k.box(Vector3(-28, 0.15, -15), Vector3(20, 11.0, 9), CLAD)
	_ribs(k, Vector3(-28.05, 0, 9.0), Vector3(20.05, 0, 9.06), 1.0, 10.8, 0.5, CLAD.darkened(0.1))
	_ribs(k, Vector3(-28.05, 0, -15.06), Vector3(20.05, 0, -15.0), 1.0, 10.8, 0.5, CLAD.darkened(0.1))
	k.box(Vector3(-28.3, 11.0, -15.3), Vector3(20.3, 11.5, 9.3), Color(0.5, 0.52, 0.55))
	k.box(Vector3(-27.8, 11.5, -14.8), Vector3(19.8, 11.6, 8.8), ROOF)
	# Oberlichter und Lüfter auf dem Dach
	for x: float in [-22.0, -12.0, -2.0, 8.0]:
		k.box(Vector3(x, 11.6, -10.0), Vector3(x + 5.0, 12.2, 4.0), Color(0.55, 0.7, 0.78, 0.6))
	for x: float in [-25.0, 15.0]:
		k.cyl(Vector3(x, 11.6, 6.0), Vector3(x, 12.4, 6.0), 0.6, 0.6, Color(0.7, 0.71, 0.72), 12)
	# Ladetore zum Vorfeld mit schwarzer Torabdichtung, Überladebrücke und Ampel
	for i in range(6):
		var x := -24.0 + float(i) * 7.6
		k.box(Vector3(x - 2.2, 0.15, 9.0), Vector3(x + 2.2, 5.2, 9.5), DARK)
		k.box(Vector3(x - 1.8, 0.15, 9.5), Vector3(x + 1.8, 4.8, 9.55), Color(0.82, 0.83, 0.84))
		for j in range(14):
			k.box(Vector3(x - 1.8, 0.3 + float(j) * 0.33, 9.55), Vector3(x + 1.8, 0.33 + float(j) * 0.33, 9.58), Color(0.62, 0.63, 0.65))
		k.box(Vector3(x - 1.6, 0.15, 9.5), Vector3(x + 1.6, 1.25, 11.5), Color(0.45, 0.46, 0.47))
		k.box(Vector3(x - 1.6, 1.25, 11.3), Vector3(x + 1.6, 1.3, 11.6), YELLOW)
		k.box(Vector3(x + 2.3, 3.0, 9.0), Vector3(x + 2.55, 3.6, 9.2), DARK)
		k.box(Vector3(x + 2.33, 3.35, 9.2), Vector3(x + 2.52, 3.55, 9.24), Color(0.2, 0.9, 0.3, 0.3))
		k.box(Vector3(x - 0.3, 5.5, 9.0), Vector3(x + 0.3, 5.7, 9.5), LAMP)
	# Bürokopf an der Ostseite mit Fensterbändern
	k.box(Vector3(20, 0.15, -15), Vector3(28, 12.5, 9), Color(0.85, 0.85, 0.82))
	for y: float in [1.4, 4.6, 7.8]:
		k.box(Vector3(28.0, y, -13.5), Vector3(28.05, y + 2.0, 7.5), WIN)
		k.box(Vector3(20.5, y, 9.0), Vector3(27.5, y + 2.0, 9.05), WIN)
	k.box(Vector3(19.8, 12.5, -15.2), Vector3(28.2, 12.9, 9.2), Color(0.5, 0.52, 0.55))
	PixelFont.draw(k, "CARGO", Vector3(-4.0, 9.2, 9.12), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.45, Color(0.16, 0.3, 0.55))
	# Container (LD3/AKE mit abgeschrägter Seite) auf Dollys vor den Toren
	var uld_cols := [Color(0.72, 0.74, 0.76), Color(0.65, 0.67, 0.7), Color(0.78, 0.6, 0.3)]
	for i in range(5):
		var x := -22.0 + float(i) * 8.5
		var z := 15.0
		k.box(Vector3(x - 1.0, 0.25, z - 1.0), Vector3(x + 1.0, 0.45, z + 1.0), DARK)
		for wx: float in [-0.75, 0.75]:
			for wz: float in [-0.75, 0.75]:
				k.cyl(Vector3(x + wx - 0.06, 0.15, z + wz), Vector3(x + wx + 0.06, 0.15, z + wz), 0.15, 0.15, Models.TYRE, 8)
		var c: Color = uld_cols[i % uld_cols.size()]
		k.prism([Vector3(x - 0.78, 0.45, z - 0.77), Vector3(x + 0.78, 0.45, z - 0.77), Vector3(x + 0.78, 0.45, z + 0.77), Vector3(x - 0.78, 0.45, z + 0.77)],
			[Vector3(x - 0.78, 2.08, z - 0.77), Vector3(x + 0.78, 2.08, z - 0.77), Vector3(x + 0.78, 2.08, z + 0.77), Vector3(x - 1.0, 1.4, z + 0.77)], c)
		k.box(Vector3(x - 0.6, 0.6, z + 0.78), Vector3(x + 0.6, 1.9, z + 0.8), c.darkened(0.15))
	# große Paletten mit Netz (PMC) und Palettenregal an der Westseite
	for i in range(3):
		var px := -26.0 + float(i) * 3.4
		k.box(Vector3(px, 0.15, -17.5), Vector3(px + 3.0, 0.3, -15.6), CHROME)
		k.box(Vector3(px + 0.1, 0.3, -17.4), Vector3(px + 2.9, 1.9, -15.7), Color(0.4, 0.33, 0.24))
		for j in range(4):
			k.box(Vector3(px + 0.08, 0.5 + float(j) * 0.4, -17.42), Vector3(px + 2.92, 0.53 + float(j) * 0.4, -15.68), Color(0.15, 0.15, 0.15))
	for i in range(4):
		var rz := -12.0 + float(i) * 5.0
		k.box(Vector3(-29.6, 0.15, rz), Vector3(-28.4, 6.0, rz + 0.15), Color(0.2, 0.35, 0.65))
		for y: float in [1.8, 3.6, 5.4]:
			k.box(Vector3(-29.6, y, rz), Vector3(-28.4, y + 0.12, rz + 5.0), Color(0.9, 0.5, 0.12))


## Winterdienst: Halle mit drei Toren, Salzsilo, Glykoltanks; davor stehen Schneepflug und Enteiser.
static func _winter(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-17, 0, -10), Vector3(17, 0.12, 10), CONCRETE)
	k.box(Vector3(-16, 0.12, -9), Vector3(6, 8.0, 3.5), Color(0.82, 0.8, 0.74))
	k.box(Vector3(-16.3, 8.0, -9.3), Vector3(6.3, 8.4, 3.8), Color(0.55, 0.3, 0.12))
	k.box(Vector3(-15.8, 8.4, -8.8), Vector3(5.8, 8.5, 3.3), ROOF)
	for i in range(3):
		var c := Vector3(-12.0 + float(i) * 7.0, 0.12, 3.5)
		Landmarks.roll_door(n, k, i, c, 5.0, 5.2, Color(0.9, 0.55, 0.12), 2)
	PixelFont.draw(k, "WINTERDIENST", Vector3(-5.0, 6.8, 3.56), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.12, DARK)
	# Salzsilo auf Stelzen mit Trichter, Glykoltanks
	for leg: Vector2 in [Vector2(9.5, -6.5), Vector2(12.5, -6.5), Vector2(9.5, -3.5), Vector2(12.5, -3.5)]:
		k.box(Vector3(leg.x - 0.12, 0.12, leg.y - 0.12), Vector3(leg.x + 0.12, 4.2, leg.y + 0.12), STEEL)
	k.cyl(Vector3(11, 4.2, -5), Vector3(11, 5.6, -5), 0.3, 2.0, Color(0.8, 0.81, 0.82), 18)
	k.cyl(Vector3(11, 5.6, -5), Vector3(11, 11.0, -5), 2.0, 2.0, Color(0.85, 0.86, 0.87), 18)
	k.cyl(Vector3(11, 11.0, -5), Vector3(11, 11.8, -5), 2.0, 0.4, Color(0.8, 0.81, 0.82), 18)
	for z: float in [1.0, 4.5]:
		k.cyl(Vector3(8.5, 1.4, z), Vector3(15.5, 1.4, z), 1.25, 1.25, Color(0.3, 0.55, 0.3), 16, true, Color(0.25, 0.48, 0.25))
		for x: float in [9.5, 14.5]:
			k.box(Vector3(x - 0.15, 0.12, z - 1.0), Vector3(x + 0.15, 0.4, z + 1.0), STEEL)
	# davor geparkt: Schneepflug und Enteiser
	k.add_mesh(Models.plow_mesh(), Transform3D(Basis.IDENTITY, Vector3(-12.0, 0.12, 13.0)), true)
	k.add_mesh(Models.deicer_mesh(), Transform3D(Basis.IDENTITY, Vector3(-5.0, 0.12, 13.0)), true)


## S-Bahnhof: Bahnsteig mit Glasdach auf Stützen, zwei Gleise dahinter, Empfangspavillon mit S-Logo,
## Fahrkartenautomaten, Anzeiger. Der Zug ("Zug") wird von der Landseite bewegt.
static func _station(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-24, 0, -9), Vector3(24, 0.1, 9), Color(0.5, 0.48, 0.44))
	# Gleisbett mit zwei Gleisen
	# die Gleise laufen über das Grundstück hinaus weiter (Ein- und Ausfahrt der Züge)
	for gz: float in [-6.6, -2.4]:
		k.box(Vector3(-70, 0.02, gz - 1.4), Vector3(70, 0.3, gz + 1.4), Color(0.45, 0.43, 0.4))
		var x := -69.8
		while x < 70.0:
			k.box(Vector3(x, 0.3, gz - 1.2), Vector3(x + 0.26, 0.42, gz + 1.2), Color(0.42, 0.36, 0.3))
			x += 0.65
		for rz: float in [-0.72, 0.72]:
			k.box(Vector3(-70, 0.42, gz + rz - 0.04), Vector3(70, 0.56, gz + rz + 0.04), Color(0.55, 0.53, 0.5))
	# Oberleitung
	for x: float in [-20.0, -6.0, 8.0, 22.0]:
		k.box(Vector3(x - 0.12, 0.1, -8.8), Vector3(x + 0.12, 6.6, -8.5), STEEL)
		k.box(Vector3(x - 0.06, 6.2, -8.6), Vector3(x + 0.06, 6.3, -1.4), STEEL)
	for gz: float in [-6.6, -2.4]:
		k.box(Vector3(-70, 5.6, gz - 0.02), Vector3(70, 5.63, gz + 0.02), DARK)
	# Bahnsteig mit weißer Sicherheitslinie und Glasdach
	k.box(Vector3(-23, 0.1, -1.0), Vector3(23, 0.96, 4.0), CONCRETE)
	k.box(Vector3(-23, 0.96, -0.9), Vector3(23, 0.98, -0.75), WHITE)
	for x: float in [-20.0, -12.0, -4.0, 4.0, 12.0, 20.0]:
		k.cyl(Vector3(x, 0.96, 2.4), Vector3(x, 4.6, 2.4), 0.14, 0.14, CHROME, 10)
	k.box(Vector3(-22.5, 4.6, -0.6), Vector3(22.5, 4.75, 4.6), STEEL)
	k.box(Vector3(-22.3, 4.75, -0.4), Vector3(22.3, 4.8, 4.4), Color(0.6, 0.75, 0.82, 0.6))
	for x: float in [-15.0, 0.0, 15.0]:
		k.box(Vector3(x - 1.2, 3.4, 1.2), Vector3(x + 1.2, 3.9, 1.3), DARK)
		k.box(Vector3(x - 1.1, 3.45, 1.31), Vector3(x + 1.1, 3.85, 1.33), Color(0.95, 0.65, 0.15, 0.3))
		k.box(Vector3(x - 0.04, 3.9, 1.22), Vector3(x + 0.04, 4.6, 1.28), STEEL)
		k.box(Vector3(x - 0.6, 0.96, 3.0), Vector3(x + 0.6, 1.4, 3.4), WOOD)
	# Empfangspavillon mit Glasfront und S-Logo
	k.box(Vector3(-6, 0.1, 4.0), Vector3(6, 4.2, 8.6), Color(0.88, 0.87, 0.83))
	k.box(Vector3(-5.6, 0.3, 8.6), Vector3(5.6, 3.6, 8.65), WIN)
	k.box(Vector3(-6.2, 4.2, 3.8), Vector3(6.2, 4.6, 8.9), Color(0.5, 0.52, 0.55))
	k.cyl(Vector3(0, 3.0, 8.7), Vector3(0, 3.0, 8.95), 0.9, 0.9, Color(0.2, 0.62, 0.3), 24)
	PixelFont.draw(k, "S", Vector3(0, 3.0, 8.97), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.16, WHITE)
	k.cyl(Vector3(-8, 0.1, 8.0), Vector3(-8, 5.5, 8.0), 0.08, 0.08, STEEL, 8)
	k.cyl(Vector3(-8, 5.5, 8.0), Vector3(-8, 5.5, 8.25), 0.7, 0.7, Color(0.2, 0.62, 0.3), 20)
	for x: float in [-4.5, -3.3]:
		k.box(Vector3(x, 0.1, 8.7), Vector3(x + 0.9, 1.8, 9.2), Color(0.85, 0.15, 0.12))
		k.box(Vector3(x + 0.15, 1.0, 9.2), Vector3(x + 0.75, 1.5, 9.22), Color(0.3, 0.6, 0.9, 0.3))
	# Zug als eigener Knoten (Front -X), Landseite fährt ihn ein und aus
	var z := MeshInstance3D.new()
	z.name = "Zug"
	z.mesh = Models.train_mesh()
	z.rotation.y = PI * 0.5
	z.position = Vector3(0, 0.42, -2.4)
	z.set_meta("no_bake", true)
	z.visible = false
	n.add_child(z)


## Taxistand: Bordsteininsel mit Unterstand, Schild und drei wartenden Taxis.
static func _taxi(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-12, 0, -2.5), Vector3(12, 0.15, 2.5), CONCRETE)
	k.box(Vector3(-12, 0, -2.6), Vector3(12, 0.18, -2.45), Color(0.85, 0.84, 0.8))
	for x: float in [-11.0, 11.0]:
		k.cyl(Vector3(x, 0.15, 1.6), Vector3(x, 3.2, 1.6), 0.06, 0.06, STEEL, 8)
		k.box(Vector3(x - 0.7, 2.6, 1.55), Vector3(x + 0.7, 3.2, 1.65), Color(0.95, 0.85, 0.2))
		PixelFont.draw(k, "TAXI", Vector3(x, 2.9, 1.67), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.07, DARK)
		PixelFont.draw(k, "TAXI", Vector3(x, 2.9, 1.53), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.07, DARK)
	k.box(Vector3(-4, 0.15, 1.2), Vector3(4, 0.25, 2.3), STEEL)
	for x: float in [-3.8, 3.8]:
		k.box(Vector3(x - 0.05, 0.25, 1.9), Vector3(x + 0.05, 2.6, 2.0), STEEL)
	k.box(Vector3(-4.1, 2.6, 0.9), Vector3(4.1, 2.7, 2.4), Color(0.6, 0.75, 0.82, 0.6))
	k.box(Vector3(-3.9, 0.6, 2.0), Vector3(3.9, 2.4, 2.05), Color(0.6, 0.75, 0.82, 0.6))
	k.box(Vector3(-2.5, 0.25, 1.4), Vector3(2.5, 0.7, 1.8), WOOD)
	# wartende Taxis auf der Fahrbahn vor der Insel (Front in Fahrtrichtung -X)
	for i in range(3):
		k.add_mesh(Models.car_mesh("taxi", Color.WHITE), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-7.0 + float(i) * 6.2, 0.0, -4.4)), true)


## Kiss & Fly: rot markierte Haltezone mit Schildern.
static func _kiss(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-15, 0, -2.5), Vector3(15, 0.15, 2.5), CONCRETE)
	k.box(Vector3(-15, 0.15, 1.0), Vector3(15, 0.7, 2.5), Color(0.35, 0.5, 0.28))
	for x: float in [-13.5, 0.0, 13.5]:
		k.cyl(Vector3(x, 0.15, 0.6), Vector3(x, 3.0, 0.6), 0.06, 0.06, STEEL, 8)
		k.box(Vector3(x - 1.1, 2.3, 0.55), Vector3(x + 1.1, 3.0, 0.65), Color(0.85, 0.2, 0.3))
		PixelFont.draw(k, "KISS+FLY", Vector3(x, 2.65, 0.67), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.05, WHITE)
		PixelFont.draw(k, "KISS+FLY", Vector3(x, 2.65, 0.53), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.05, WHITE)
	# rote Fahrbahnmarkierung auf der Straße davor
	k.box(Vector3(-14.5, 0.0, -5.6), Vector3(14.5, 0.08, -3.2), Color(0.62, 0.2, 0.2))
	PixelFont.draw_ground(k, "KISS+FLY", Vector3(0, 0.09, -4.4), Vector3(-1, 0, 0), 0.12, WHITE)
	for x: float in [-9.0, -3.0, 3.0, 9.0]:
		k.box(Vector3(x - 0.4, 0.15, -0.4), Vector3(x + 0.4, 0.6, 0.4), Color(0.5, 0.5, 0.48))


## Mietwagenzentrum: Pavillon mit vier farbigen Schaltern, Stellflächen mit Mietwagen, Waschplatz.
static func _rental(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-18, 0, -13), Vector3(18, 0.12, 13), ASPHALT)
	k.box(Vector3(-16, 0.12, 4.0), Vector3(16, 4.0, 11.5), Color(0.88, 0.87, 0.83))
	k.box(Vector3(-16.3, 4.0, 3.7), Vector3(16.3, 4.4, 11.8), Color(0.5, 0.52, 0.55))
	var brands := [["RENTA", Color(0.95, 0.75, 0.1)], ["CARGO", Color(0.2, 0.6, 0.3)], ["DRIVE", Color(0.8, 0.15, 0.15)], ["MOBIL", Color(0.2, 0.35, 0.7)]]
	for i in range(4):
		var x := -12.0 + float(i) * 8.0
		var b: Array = brands[i]
		k.box(Vector3(x - 3.6, 0.3, 3.98), Vector3(x + 3.6, 3.0, 4.0), WIN)
		k.box(Vector3(x - 3.6, 3.1, 3.9), Vector3(x + 3.6, 3.85, 3.96), b[1])
		PixelFont.draw(k, String(b[0]), Vector3(x, 3.47, 3.88), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.09, WHITE)
	var cols := [Color(0.85, 0.85, 0.83), Color(0.12, 0.12, 0.13), Color(0.55, 0.57, 0.6), Color(0.2, 0.3, 0.5), Color(0.7, 0.12, 0.1)]
	var kinds := ["kompakt", "limousine", "kombi", "suv", "kompakt"]
	for row in range(2):
		for i in range(10):
			var x := -15.75 + float(i) * 3.5
			var z := -9.5 + float(row) * 7.0
			k.box(Vector3(x - 1.75, 0.12, z - 0.05), Vector3(x - 1.65, 0.14, z + 2.6), WHITE)
			if (i + row * 3) % 7 == 3:
				continue
			k.add_mesh(Models.car_mesh(kinds[(i + row) % kinds.size()], cols[(i * 3 + row) % cols.size()], true),
				Transform3D(Basis(Vector3.UP, 0.0 if row == 0 else PI), Vector3(x, 0.12, z + (1.3 if row == 0 else -1.3) + (0.0 if row == 0 else 2.6))), true)


# ------------------------------------------------------------------ im Terminal

## Airline-Lounge: Teppich, Empfangstresen, Buffet, Sesselgruppen, Glaswand mit Schriftzug, Pflanzen.
static func _lounge(k: Kit) -> void:
	k.box(Vector3(-6, 0.0, -4), Vector3(6, 0.04, 4), CARPET)
	k.box(Vector3(-6, 0.0, -4.0), Vector3(6, 2.9, -3.85), Color(0.55, 0.42, 0.3))
	k.box(Vector3(-6, 0.0, 3.85), Vector3(-1.5, 2.9, 4.0), Color(0.55, 0.75, 0.85, 0.6))
	k.box(Vector3(1.5, 0.0, 3.85), Vector3(6, 2.9, 4.0), Color(0.55, 0.75, 0.85, 0.6))
	k.box(Vector3(-6, 2.6, 3.8), Vector3(6, 2.9, 4.05), Color(0.2, 0.22, 0.25))
	PixelFont.draw(k, "LOUNGE", Vector3(0, 2.75, 4.07), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.04, Color(0.95, 0.8, 0.45))
	# Empfangstresen am Eingang
	k.box(Vector3(-1.2, 0.04, 2.4), Vector3(1.2, 1.1, 3.0), Color(0.3, 0.22, 0.16))
	k.box(Vector3(-1.25, 1.1, 2.35), Vector3(1.25, 1.15, 3.05), Color(0.85, 0.8, 0.7))
	# Buffet an der Rückwand
	k.box(Vector3(-5.6, 0.04, -3.8), Vector3(-0.5, 0.95, -3.0), Color(0.25, 0.2, 0.16))
	k.box(Vector3(-5.6, 0.95, -3.8), Vector3(-0.5, 1.0, -3.0), Color(0.88, 0.86, 0.82))
	for i in range(6):
		k.cyl(Vector3(-5.1 + float(i) * 0.85, 1.0, -3.4), Vector3(-5.1 + float(i) * 0.85, 1.08, -3.4), 0.25, 0.25, CHROME, 12)
	k.box(Vector3(0.5, 0.04, -3.8), Vector3(2.5, 1.9, -3.2), Color(0.2, 0.2, 0.22))
	k.box(Vector3(0.6, 1.0, -3.21), Vector3(2.4, 1.8, -3.19), Color(0.3, 0.6, 0.85, 0.3))
	# Sesselgruppen mit Couchtischen
	var seat := Color(0.62, 0.5, 0.34)
	for g: Vector3 in [Vector3(-3.5, 0, -0.5), Vector3(-3.5, 0, 2.0), Vector3(3.2, 0, -1.6), Vector3(3.2, 0, 1.4)]:
		k.cyl(g + Vector3(0, 0.04, 0), g + Vector3(0, 0.45, 0), 0.4, 0.4, Color(0.3, 0.22, 0.16), 14)
		for a: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			var d := Vector3(cos(a), 0, sin(a)) * 1.0
			var c := g + d
			k.soft_box(c + Vector3(-0.38, 0.04, -0.38), c + Vector3(0.38, 0.45, 0.38), 0.08, seat, 8, 3)
			k.soft_box(c + d.normalized() * 0.28 + Vector3(-0.38, 0.4, -0.38) * Vector3(absf(d.z) + 0.25, 1, absf(d.x) + 0.25),
				c + d.normalized() * 0.36 + Vector3(0.38, 0.95, 0.38) * Vector3(absf(d.z) + 0.25, 1, absf(d.x) + 0.25), 0.06, seat.darkened(0.1), 8, 3)
	for p: Vector3 in [Vector3(-5.4, 0, 3.3), Vector3(5.4, 0, -3.3), Vector3(5.4, 0, 3.3)]:
		k.cyl(p, p + Vector3(0, 0.5, 0), 0.3, 0.25, Color(0.3, 0.3, 0.32), 10)
		k.sphere(p + Vector3(0, 1.1, 0), 0.6, Color(0.22, 0.48, 0.25, 0.8), 10, 6)


## Gepäckermittlung: Schalter mit Schild, Regal mit liegengebliebenen Koffern.
static func _lost_found(k: Kit) -> void:
	k.box(Vector3(-2.4, 0, -0.2), Vector3(2.4, 1.1, 0.5), Color(0.25, 0.3, 0.4))
	k.box(Vector3(-2.45, 1.1, -0.25), Vector3(2.45, 1.15, 0.55), Color(0.85, 0.84, 0.8))
	k.box(Vector3(-2.4, 0, -1.5), Vector3(2.4, 2.5, -1.3), Color(0.82, 0.8, 0.76))
	k.box(Vector3(-1.6, 1.9, -1.31), Vector3(1.6, 2.45, -1.27), Color(0.95, 0.75, 0.1))
	PixelFont.draw(k, "LOST+FOUND", Vector3(0, 2.17, -1.25), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.03, DARK)
	var cols := [Color(0.6, 0.15, 0.12), Color(0.15, 0.25, 0.5), Color(0.1, 0.1, 0.1), Color(0.5, 0.4, 0.25), Color(0.25, 0.45, 0.3)]
	for i in range(5):
		var x := -2.0 + float(i) * 0.95
		k.soft_box(Vector3(x - 0.3, 0.0, -1.25), Vector3(x + 0.3, 0.75, -0.85), 0.05, cols[i], 8, 3)
	k.box(Vector3(-1.5, 1.15, 0.0), Vector3(-0.9, 1.5, 0.1), Color(0.1, 0.1, 0.12))
	k.box(Vector3(0.9, 1.15, 0.0), Vector3(1.5, 1.5, 0.1), Color(0.1, 0.1, 0.12))


## Gepäckdurchleuchtung (EDS): CT-Tunnel mit Förderbändern davor und dahinter, Kontrollplatz mit Monitoren.
static func _eds(k: Kit) -> void:
	k.box(Vector3(-4, 0.0, -0.5), Vector3(4, 0.8, 0.5), Color(0.25, 0.25, 0.27))
	k.box(Vector3(-4, 0.8, -0.45), Vector3(4, 0.84, 0.45), Color(0.12, 0.12, 0.13))
	k.soft_box(Vector3(-1.4, 0.0, -1.2), Vector3(1.4, 2.4, 1.2), 0.2, Color(0.86, 0.87, 0.88), 12, 6)
	k.box(Vector3(-1.45, 0.75, -0.55), Vector3(1.45, 1.6, 0.55), Color(0.1, 0.1, 0.11))
	k.box(Vector3(-1.2, 1.9, 1.2), Vector3(1.2, 2.1, 1.25), Color(0.2, 0.6, 0.9, 0.3))
	PixelFont.draw(k, "EDS", Vector3(0, 2.2, 1.24), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.06, Color(0.2, 0.3, 0.5))
	for x: float in [-3.0, 2.6]:
		k.soft_box(Vector3(x - 0.35, 0.84, -0.3), Vector3(x + 0.35, 1.3, 0.3), 0.05, Color(0.2, 0.25, 0.45), 8, 3)
	k.box(Vector3(1.8, 0, 1.5), Vector3(3.8, 0.75, 2.4), Color(0.75, 0.76, 0.77))
	for x: float in [2.2, 3.2]:
		k.box(Vector3(x - 0.35, 0.75, 1.6), Vector3(x + 0.35, 1.3, 1.65), DARK)
		k.box(Vector3(x - 0.3, 0.8, 1.66), Vector3(x + 0.3, 1.25, 1.68), Color(0.4, 0.7, 0.95, 0.3))
