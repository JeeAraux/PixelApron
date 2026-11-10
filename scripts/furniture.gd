extends RefCounted
## Möbel und Ausstattung für das Terminal, fein aus dem Mesh-Baukasten gebaut.
## Vorderseite ist +Z (dorthin schauen Bildschirme, Automaten, Schalter). Bewegliche Teile
## sind eigene Knoten mit sprechenden Namen; deco_anim.gd bewegt sie (Uhr, Fische, Fontänen …).

const Kit = preload("res://scripts/mesh_kit.gd")
const Models = preload("res://scripts/models.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")
const BeltAnim = preload("res://scripts/belt_anim.gd")
const DecoAnim = preload("res://scripts/deco_anim.gd")
const SCREEN_SHADER = preload("res://shaders/screen.gdshader")

const CHROME := Color(0.72, 0.74, 0.77)
const STEEL := Color(0.38, 0.42, 0.45)
const DARK := Color(0.12, 0.12, 0.13)
const WHITE := Color(0.92, 0.91, 0.88)
const OAK := Color(0.62, 0.45, 0.28)
const WALNUT := Color(0.38, 0.26, 0.17)
const LEAF := Color(0.24, 0.45, 0.2, 0.8)       # Alpha 0.8: wiegt sich (kit.gdshader)
const LEAF2 := Color(0.32, 0.55, 0.24, 0.8)
const SOIL := Color(0.25, 0.18, 0.12)
const LAMP := Color(1.0, 0.92, 0.72, 0.3)
const GLASS := Color(0.55, 0.72, 0.8, 0.6)
const WATER := Color(0.35, 0.62, 0.8)

const IDS := ["uhr", "snackautomat", "getraenkeautomat", "infoschalter", "lounge", "bistrotisch", "trinkbrunnen",
	"rollsteig", "werbebildschirm", "spielecke", "ladestation", "geldautomat", "kofferwagen", "kiosk", "aquarium",
	"palme", "baumbeet", "flugzeugmodell", "fahnen", "fluegel", "massagesessel", "muelltrennung", "gruenwand", "springbrunnen"]


static func build(n: Node3D, id: String) -> bool:
	if not (id in IDS):
		return false
	var k := Kit.new()
	var anim := false
	match id:
		"uhr":
			anim = _clock(n, k)
		"snackautomat":
			_vending(n, k, false)
			anim = true
		"getraenkeautomat":
			_vending(n, k, true)
			anim = true
		"infoschalter":
			_info_desk(n, k)
		"lounge":
			_lounge(k)
		"bistrotisch":
			_bistro(k)
		"trinkbrunnen":
			_drinking(n, k)
			anim = true
		"rollsteig":
			_walkway(n, k)
		"werbebildschirm":
			_screen(n, k)
		"spielecke":
			_play(n, k)
			anim = true
		"ladestation":
			_charging(n, k)
			anim = true
		"geldautomat":
			_atm(n, k)
		"kofferwagen":
			_trolleys(k)
		"kiosk":
			_kiosk(n, k)
		"aquarium":
			_aquarium(n, k)
		"palme":
			_palm(k, Vector3.ZERO, 1.0)
			k.cyl(Vector3(0, 0, 0), Vector3(0, 0.6, 0), 0.5, 0.42, Color(0.85, 0.84, 0.8), 14)
			k.cyl(Vector3(0, 0.55, 0), Vector3(0, 0.6, 0), 0.4, 0.4, SOIL, 14)
		"baumbeet":
			_tree_bed(k)
		"flugzeugmodell":
			_model_plane(n, k)
			anim = true
		"fahnen":
			_flags(k)
		"fluegel":
			_piano(n, k)
		"massagesessel":
			_massage(n, k)
			anim = true
		"muelltrennung":
			_bins(k)
		"gruenwand":
			_green_wall(k)
		"springbrunnen":
			_fountain(n, k)
			anim = true
	if k.count > 0:
		n.add_child(k.instance("Moebel"))
	if anim:
		var a := Node.new()
		a.name = "Anim"
		a.set_script(DecoAnim)
		n.add_child(a)
	return true


static func _part(n: Node3D, name: String, k: Kit, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := k.instance(name)
	mi.position = at
	mi.set_meta("no_bake", true)
	n.add_child(mi)
	return mi


static func _person(n: Node3D, shirt: Color, at: Vector3, face: Vector3, skin: int = -1) -> void:
	var Factory = load("res://scripts/factory.gd")
	var p: Node3D = Factory.make_staff(shirt, Color(0.15, 0.16, 0.2), skin if skin >= 0 else randi() % 4)
	p.position = at
	p.basis = Basis.looking_at(face, Vector3.UP)
	n.add_child(p)


# ---------------------------------------------------------------- Einzelstücke

## Bahnhofsuhr an einer Säule, zwei Zifferblätter, Zeiger laufen mit der Spielzeit.
static func _clock(n: Node3D, k: Kit) -> bool:
	k.cyl(Vector3(0, 0, 0), Vector3(0, 0.05, 0), 0.32, 0.32, STEEL, 16)
	k.cyl(Vector3(0, 0.05, 0), Vector3(0, 2.75, 0), 0.07, 0.07, STEEL, 10)
	k.box(Vector3(-0.08, 2.75, -0.12), Vector3(0.08, 2.95, 0.12), STEEL)
	for sz: float in [-1.0, 1.0]:
		var c := Vector3(0, 3.25, sz * 0.09)
		k.cyl(c - Vector3(0, 0, sz * 0.06), c + Vector3(0, 0, sz * 0.02), 0.42, 0.42, DARK, 24)
		k.cyl(c + Vector3(0, 0, sz * 0.02), c + Vector3(0, 0, sz * 0.03), 0.38, 0.38, Color(0.97, 0.97, 0.95), 24)
		for i in range(12):
			var a := float(i) / 12.0 * TAU
			var r := 0.32
			var tick := 0.06 if i % 3 == 0 else 0.03
			k.box(Vector3(-0.012, -tick, -0.005), Vector3(0.012, tick * 0.2, 0.005), DARK,
				Transform3D(Basis(Vector3(0, 0, 1), -a), c + Vector3(sin(a) * r, cos(a) * r, sz * 0.035)))
		var face := 0 if sz > 0.0 else 1
		for hand: Array in [["Zeiger_h", 0.2, 0.025], ["Zeiger_m", 0.3, 0.016]]:
			var hk := Kit.new()
			hk.box(Vector3(-float(hand[2]), -0.04, -0.005), Vector3(float(hand[2]), float(hand[1]), 0.005), DARK)
			var mi := _part(n, "%s%d" % [String(hand[0]), face], hk, c + Vector3(0, 0, sz * 0.045))
			mi.set_meta("dir", sz)
		# roter Sekundenzeiger mit Kelle (läuft in echter Zeit)
		var sk := Kit.new()
		sk.box(Vector3(-0.006, -0.05, -0.004), Vector3(0.006, 0.3, 0.004), Color(0.85, 0.1, 0.08))
		sk.cyl(Vector3(0, 0.26, -0.004), Vector3(0, 0.26, 0.004), 0.035, 0.035, Color(0.85, 0.1, 0.08), 10)
		var sec := _part(n, "Zeiger_s%d" % face, sk, c + Vector3(0, 0, sz * 0.05))
		sec.set_meta("dir", sz)
	return true


## Snack- oder Getränkeautomat mit beleuchteter Front, Fächern und blinkender Taste.
static func _vending(n: Node3D, k: Kit, drinks: bool) -> void:
	var body := Color(0.75, 0.15, 0.12) if drinks else Color(0.18, 0.22, 0.3)
	k.rounded_box(Vector3(-0.55, 0.05, -0.4), Vector3(0.55, 1.95, 0.4), 0.04, body, 2)
	k.box(Vector3(-0.5, 0.0, -0.38), Vector3(0.5, 0.06, 0.38), DARK)
	k.box(Vector3(-0.45, 0.55, 0.39), Vector3(0.18, 1.85, 0.41), Color(0.85, 0.9, 0.95, 0.3))
	for row in range(5):
		var y := 0.7 + float(row) * 0.23
		k.box(Vector3(-0.44, y - 0.01, 0.38), Vector3(0.17, y + 0.01, 0.4), STEEL)
		for col in range(4):
			var x := -0.37 + float(col) * 0.15
			var c := Color.from_hsv(fmod(float(row * 4 + col) * 0.137, 1.0), 0.65, 0.85)
			if drinks:
				k.cyl(Vector3(x, y + 0.01, 0.3), Vector3(x, y + 0.17, 0.3), 0.035, 0.035, c, 8)
			else:
				k.box(Vector3(x - 0.05, y + 0.01, 0.28), Vector3(x + 0.05, y + 0.15, 0.33), c)
	k.box(Vector3(0.23, 1.1, 0.39), Vector3(0.48, 1.6, 0.41), DARK)
	for i in range(9):
		k.box(Vector3(0.26 + float(i % 3) * 0.07, 1.15 + float(i / 3) * 0.08, 0.41), Vector3(0.31 + float(i % 3) * 0.07, 1.2 + float(i / 3) * 0.08, 0.42), CHROME)
	k.box(Vector3(0.25, 0.85, 0.39), Vector3(0.46, 0.98, 0.41), Color(0.2, 0.9, 0.4, 0.3))
	k.box(Vector3(-0.4, 0.2, 0.39), Vector3(0.15, 0.45, 0.41), DARK)
	k.box(Vector3(-0.5, 1.88, 0.4), Vector3(0.5, 1.95, 0.42), LAMP)
	PixelFont.draw(k, "COLA" if drinks else "SNACKS", Vector3(-0.15, 1.72, 0.415), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.022, WHITE)
	var bk := Kit.new()
	bk.box(Vector3(-0.03, -0.03, 0), Vector3(0.03, 0.03, 0.02), Color(1.0, 0.85, 0.2, 0.3))
	var b := _part(n, "BlinkTaste", bk, Vector3(0.36, 1.02, 0.41))
	b.set_meta("period", 1.6)


## Info-Schalter: runder Tresen, zwei Mitarbeiter, schwebendes i-Schild mit Licht.
static func _info_desk(n: Node3D, k: Kit) -> void:
	var desk := Color(0.86, 0.85, 0.82)
	var lathe := []
	for i in range(13):
		var a := lerpf(-PI * 0.75, PI * 0.75, float(i) / 12.0)
		lathe.append(Vector3(sin(a) * 1.5, 0, cos(a) * 1.0 + 0.2))
	for i in range(12):
		var a: Vector3 = lathe[i]
		var b: Vector3 = lathe[i + 1]
		var d := b - a
		var bas := Basis.looking_at(d.normalized(), Vector3.UP)
		k.box(Vector3(-0.15, 0, -d.length() * 0.52), Vector3(0.15, 1.05, d.length() * 0.52), desk, Transform3D(bas, (a + b) * 0.5))
		k.box(Vector3(-0.22, 1.05, -d.length() * 0.52), Vector3(0.22, 1.1, d.length() * 0.52), WALNUT, Transform3D(bas, (a + b) * 0.5))
		k.box(Vector3(-0.155, 0.15, -d.length() * 0.52), Vector3(0.155, 0.22, d.length() * 0.52), Color(0.2, 0.45, 0.75), Transform3D(bas, (a + b) * 0.5))
	k.box(Vector3(-1.2, 0.72, -0.6), Vector3(1.2, 0.76, 0.4), WALNUT)
	for x: float in [-0.6, 0.6]:
		k.box(Vector3(x - 0.25, 0.76, -0.2), Vector3(x + 0.25, 1.08, -0.17), DARK)
		k.box(Vector3(x - 0.23, 0.78, -0.165), Vector3(x + 0.23, 1.06, -0.16), Color(0.4, 0.6, 0.8, 0.3))
	k.cyl(Vector3(0, 0, -0.8), Vector3(0, 3.4, -0.8), 0.05, 0.05, STEEL, 8)
	k.box(Vector3(-0.5, 3.0, -0.88), Vector3(0.5, 3.6, -0.72), Color(0.2, 0.45, 0.75))
	PixelFont.draw(k, "I", Vector3(0, 3.3, -0.71), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.07, Color(1, 1, 1, 0.3))
	PixelFont.draw(k, "INFO", Vector3(0, 3.1, -0.71), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.025, WHITE)
	_person(n, Color(0.2, 0.45, 0.75), Vector3(-0.6, 0, -0.55), Vector3(0, 0, 1), 1)
	_person(n, Color(0.2, 0.45, 0.75), Vector3(0.6, 0, -0.55), Vector3(0, 0, 1), 2)


## Lounge: zwei Sofas mit Kissen, Sessel, runder Couchtisch mit Zeitschriften, Stehlampe, Teppich.
static func _lounge(k: Kit) -> void:
	var fabric := Color(0.32, 0.5, 0.48)
	k.box(Vector3(-1.8, 0, -1.6), Vector3(1.8, 0.02, 1.6), Color(0.72, 0.62, 0.48))
	k.box(Vector3(-1.7, 0.02, -1.5), Vector3(1.7, 0.025, 1.5), Color(0.62, 0.5, 0.38))
	for sz: float in [-1.0, 1.0]:
		var z := sz * 1.15
		k.rounded_box(Vector3(-1.3, 0.12, z - 0.4), Vector3(1.3, 0.45, z + 0.4), 0.06, fabric, 2)
		k.rounded_box(Vector3(-1.3, 0.45, z + sz * 0.22), Vector3(1.3, 0.95, z + sz * 0.4), 0.06, fabric.darkened(0.12), 2)
		for sx: float in [-1.0, 1.0]:
			k.rounded_box(Vector3(sx * 1.3 - 0.15, 0.12, z - 0.4), Vector3(sx * 1.3 + 0.15, 0.68, z + 0.4), 0.05, fabric.darkened(0.08), 2)
		for x: float in [-0.65, 0.0, 0.65]:
			k.rounded_box(Vector3(x - 0.3, 0.45, z - 0.33), Vector3(x + 0.3, 0.55, z + 0.25), 0.04, fabric.lightened(0.08), 2)
		k.rounded_box(Vector3(-0.95, 0.55, z + sz * 0.05), Vector3(-0.6, 0.85, z + sz * 0.2), 0.05, Color(0.9, 0.75, 0.3), 2)
		for x: float in [-1.2, 1.2]:
			k.cyl(Vector3(x, 0.0, z - 0.3), Vector3(x, 0.12, z - 0.3), 0.03, 0.03, WALNUT, 6)
			k.cyl(Vector3(x, 0.0, z + 0.3), Vector3(x, 0.12, z + 0.3), 0.03, 0.03, WALNUT, 6)
	k.cyl(Vector3(0, 0.0, 0), Vector3(0, 0.38, 0), 0.06, 0.06, CHROME, 8)
	k.cyl(Vector3(0, 0.38, 0), Vector3(0, 0.43, 0), 0.5, 0.5, Color(0.85, 0.88, 0.9, 0.6), 18)
	k.box(Vector3(-0.2, 0.43, -0.15), Vector3(0.1, 0.45, 0.08), Color(0.85, 0.3, 0.25))
	k.box(Vector3(0.05, 0.43, 0.0), Vector3(0.3, 0.46, 0.18), Color(0.2, 0.35, 0.6))
	k.cyl(Vector3(-0.15, 0.43, 0.2), Vector3(-0.15, 0.53, 0.2), 0.04, 0.035, WHITE, 8)
	k.cyl(Vector3(1.65, 0, -1.4), Vector3(1.65, 0.03, -1.4), 0.18, 0.18, DARK, 10)
	k.cyl(Vector3(1.65, 0.03, -1.4), Vector3(1.65, 1.55, -1.4), 0.02, 0.02, DARK, 6)
	k.cyl(Vector3(1.65, 1.45, -1.4), Vector3(1.65, 1.75, -1.4), 0.22, 0.14, Color(0.98, 0.9, 0.7, 0.3), 12)


## Zwei Bistrotische mit je zwei Stühlen, Tassen und Tellern.
static func _bistro(k: Kit) -> void:
	for c: Vector3 in [Vector3(-0.75, 0, -0.6), Vector3(0.75, 0, 0.6)]:
		k.cyl(c, c + Vector3(0, 0.03, 0), 0.25, 0.25, DARK, 12)
		k.cyl(c, c + Vector3(0, 0.72, 0), 0.03, 0.03, DARK, 8)
		k.cyl(c + Vector3(0, 0.72, 0), c + Vector3(0, 0.75, 0), 0.38, 0.38, Color(0.92, 0.9, 0.85), 18)
		k.cyl(c + Vector3(0.12, 0.75, 0.05), c + Vector3(0.12, 0.82, 0.05), 0.04, 0.035, WHITE, 8)
		k.cyl(c + Vector3(-0.12, 0.75, -0.08), c + Vector3(-0.12, 0.76, -0.08), 0.09, 0.09, WHITE, 10)
		for sx: float in [-1.0, 1.0]:
			var p := c + Vector3(sx * 0.62, 0, 0)
			for lx: float in [-0.16, 0.16]:
				for lz: float in [-0.16, 0.16]:
					k.cyl(p + Vector3(lx, 0, lz), p + Vector3(lx * 0.9, 0.45, lz * 0.9), 0.015, 0.015, CHROME, 5)
			k.rounded_box(p + Vector3(-0.2, 0.45, -0.2), p + Vector3(0.2, 0.5, 0.2), 0.02, OAK, 1)
			k.rounded_box(p + Vector3(sx * 0.17 - 0.03, 0.5, -0.19), p + Vector3(sx * 0.17 + 0.03, 0.88, 0.19), 0.02, OAK, 1)


## Trinkbrunnen aus Edelstahl mit kleiner Wasserfontäne.
static func _drinking(n: Node3D, k: Kit) -> void:
	k.rounded_box(Vector3(-0.3, 0, -0.3), Vector3(0.3, 0.85, 0.2), 0.04, CHROME, 2)
	k.box(Vector3(-0.32, 0.85, -0.32), Vector3(0.32, 0.92, 0.3), Color(0.82, 0.84, 0.86))
	k.cyl(Vector3(0, 0.88, 0.0), Vector3(0, 0.92, 0.0), 0.18, 0.18, Color(0.5, 0.55, 0.6), 14)
	k.box(Vector3(-0.3, 0.3, 0.2), Vector3(0.3, 0.32, 0.22), DARK)
	k.box(Vector3(-0.05, 0.5, 0.2), Vector3(0.05, 0.6, 0.23), Color(0.2, 0.5, 0.85))
	var wk := Kit.new()
	wk.cyl(Vector3(0, 0, 0), Vector3(0.05, 0.12, 0.0), 0.015, 0.012, Color(0.7, 0.85, 1.0, 0.3), 6)
	var w := _part(n, "HubWasser", wk, Vector3(0, 0.92, 0))
	w.set_meta("speed", 6.0)


## Rollsteig: Kammplatten, Glasbalustraden mit Handlauf, laufende Paletten.
static func _walkway(n: Node3D, k: Kit) -> void:
	var half := 7.0
	k.box(Vector3(-1.0, 0, -half), Vector3(1.0, 0.12, half), Color(0.5, 0.52, 0.55))
	for sz: float in [-1.0, 1.0]:
		k.box(Vector3(-0.75, 0.12, sz * half - 0.4), Vector3(0.75, 0.16, sz * half + 0.0 * sz), CHROME)
		k.box(Vector3(-0.75, 0.16, sz * (half - 0.4) - 0.02), Vector3(0.75, 0.17, sz * (half - 0.4) + 0.02), Color(0.9, 0.75, 0.2))
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 0.85 - 0.08, 0.12, -half), Vector3(sx * 0.85 + 0.08, 0.3, half), Color(0.62, 0.64, 0.66))
		k.box(Vector3(sx * 0.85 - 0.02, 0.3, -half + 0.3), Vector3(sx * 0.85 + 0.02, 1.0, half - 0.3), GLASS)
		k.rounded_box(Vector3(sx * 0.85 - 0.06, 1.0, -half + 0.2), Vector3(sx * 0.85 + 0.06, 1.08, half - 0.2), 0.03, DARK, 2)
		k.box(Vector3(sx * 0.85 - 0.04, 0.2, -half - 0.1), Vector3(sx * 0.85 + 0.04, 0.25, -half + 0.4), Color(0.2, 0.8, 0.3, 0.3))
	var pk := Kit.new()
	pk.box(Vector3(-0.72, 0.0, -0.18), Vector3(0.72, 0.03, 0.18), Color(0.42, 0.44, 0.47))
	for i in range(8):
		pk.box(Vector3(-0.7 + float(i) * 0.19, 0.03, -0.17), Vector3(-0.66 + float(i) * 0.19, 0.04, 0.17), Color(0.3, 0.31, 0.33))
	var slats := MultiMeshInstance3D.new()
	slats.name = "Paletten"
	slats.set_script(BeltAnim)
	n.add_child(slats)
	slats.call("setup", PackedVector3Array([Vector3(0, 0.12, -half + 0.5), Vector3(0, 0.12, half - 0.5)]), pk.commit(), 0.75, 0.4)


## Werbebildschirm (Stele) mit wechselnden Motiven.
static func _screen(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-0.5, 0, -0.2), Vector3(0.5, 0.06, 0.2), DARK)
	k.box(Vector3(-0.08, 0.06, -0.06), Vector3(0.08, 0.6, 0.06), STEEL)
	k.rounded_box(Vector3(-0.7, 0.6, -0.08), Vector3(0.7, 2.55, 0.08), 0.03, DARK, 2)
	var mi := MeshInstance3D.new()
	mi.name = "Bild"
	var qm := QuadMesh.new()
	qm.size = Vector2(1.3, 1.85)
	mi.mesh = qm
	var sm := ShaderMaterial.new()
	sm.shader = SCREEN_SHADER
	sm.set_shader_parameter("seed", randf() * 10.0)
	mi.material_override = sm
	mi.position = Vector3(0, 1.575, 0.085)
	mi.set_meta("no_bake", true)
	n.add_child(mi)


## Spielecke: Rutsche, Schaukelpferd, Softbausteine, Teppich mit Straßen.
static func _play(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-2.4, 0, -2.4), Vector3(2.4, 0.04, 2.4), Color(0.35, 0.6, 0.45))
	for i in range(6):
		k.box(Vector3(-2.2 + float(i) * 0.8, 0.04, -0.06), Vector3(-1.9 + float(i) * 0.8, 0.045, 0.06), WHITE)
	k.box(Vector3(-0.06, 0.04, -2.2), Vector3(0.06, 0.045, 2.2), Color(0.3, 0.3, 0.32))
	# Rutsche mit Leiter und Plattform
	k.box(Vector3(0.8, 0, -2.0), Vector3(2.0, 1.2, -1.0), Color(0.95, 0.75, 0.2))
	for i in range(4):
		k.box(Vector3(0.85, 0.25 + float(i) * 0.25, -0.98), Vector3(1.95, 0.29 + float(i) * 0.25, -0.9), Color(0.2, 0.5, 0.85))
	var sl := Vector3(1.4, 1.15, -2.0)
	var se := Vector3(1.4, 0.1, -0.2 + 0.0)
	se = Vector3(-0.2, 0.08, -1.5)
	var d := se - sl
	var bas := Basis.looking_at(d.normalized(), Vector3.UP)
	k.box(Vector3(-0.35, -0.04, -d.length() * 0.5), Vector3(0.35, 0.02, d.length() * 0.5), Color(0.9, 0.25, 0.2), Transform3D(bas, (sl + se) * 0.5))
	for sx: float in [-0.37, 0.37]:
		k.box(Vector3(sx - 0.03, 0.0, -d.length() * 0.5), Vector3(sx + 0.03, 0.18, d.length() * 0.5), Color(0.9, 0.25, 0.2), Transform3D(bas, (sl + se) * 0.5))
	# Softbausteine
	var cols := [Color(0.9, 0.3, 0.25), Color(0.25, 0.55, 0.9), Color(0.95, 0.8, 0.2), Color(0.3, 0.75, 0.4)]
	for i in range(7):
		var p := Vector3(-1.8 + float(i % 4) * 0.5, 0.04 + float(i / 4) * 0.4, 1.4 + float(i % 2) * 0.1)
		k.rounded_box(p, p + Vector3(0.4, 0.4, 0.4), 0.06, cols[i % 4], 2)
	# Schaukelpferd (schaukelt)
	var hk := Kit.new()
	var horse := Color(0.85, 0.5, 0.25)
	for sx: float in [-0.18, 0.18]:
		for i in range(8):
			var a0 := lerpf(-0.9, 0.9, float(i) / 8.0)
			var a1 := lerpf(-0.9, 0.9, float(i + 1) / 8.0)
			var p0 := Vector3(sx, 0.55 - cos(a0) * 0.55, sin(a0) * 0.6)
			var p1 := Vector3(sx, 0.55 - cos(a1) * 0.55, sin(a1) * 0.6)
			var dd := p1 - p0
			hk.box(Vector3(-0.03, -0.02, -dd.length() * 0.55), Vector3(0.03, 0.02, dd.length() * 0.55), WALNUT, Transform3D(Basis.looking_at(dd.normalized(), Vector3.UP), (p0 + p1) * 0.5))
	hk.rounded_box(Vector3(-0.14, 0.38, -0.32), Vector3(0.14, 0.62, 0.3), 0.08, horse, 2)
	hk.rounded_box(Vector3(-0.1, 0.55, -0.48), Vector3(0.1, 0.9, -0.3), 0.06, horse, 2)
	hk.rounded_box(Vector3(-0.08, 0.78, -0.62), Vector3(0.08, 0.9, -0.44), 0.04, horse, 2)
	hk.box(Vector3(-0.03, 0.85, -0.42), Vector3(0.03, 0.95, -0.3), DARK)
	hk.box(Vector3(-0.15, 0.62, -0.1), Vector3(0.15, 0.66, 0.15), Color(0.8, 0.15, 0.15))
	for sx: float in [-0.12, 0.12]:
		hk.box(Vector3(sx - 0.03, 0.15, -0.25), Vector3(sx + 0.03, 0.4, -0.2), horse)
		hk.box(Vector3(sx - 0.03, 0.15, 0.2), Vector3(sx + 0.03, 0.4, 0.25), horse)
	var h := _part(n, "WippPferd", hk, Vector3(-1.3, 0.04, -0.9))
	h.set_meta("amp", 0.22)
	h.set_meta("speed", 2.4)


## Ladesäule für Handys mit blinkenden Ladeanzeigen.
static func _charging(n: Node3D, k: Kit) -> void:
	k.cyl(Vector3(0, 0, 0), Vector3(0, 0.05, 0), 0.4, 0.4, DARK, 16)
	k.cyl(Vector3(0, 0.05, 0), Vector3(0, 1.1, 0), 0.18, 0.18, WHITE, 14)
	k.cyl(Vector3(0, 1.1, 0), Vector3(0, 1.15, 0), 0.45, 0.45, Color(0.2, 0.45, 0.75), 18)
	for i in range(6):
		var a := float(i) / 6.0 * TAU
		var p := Vector3(sin(a) * 0.19, 0.85, cos(a) * 0.19)
		k.box(p - Vector3(0.03, 0.04, 0.03), p + Vector3(0.03, 0.04, 0.03), DARK)
		k.box(Vector3(sin(a) * 0.36 - 0.05, 1.15, cos(a) * 0.36 - 0.08), Vector3(sin(a) * 0.36 + 0.05, 1.16, cos(a) * 0.36 + 0.08), DARK)
		var bk := Kit.new()
		bk.box(Vector3(-0.015, -0.015, -0.015), Vector3(0.015, 0.015, 0.015), Color(0.2, 1.0, 0.4, 0.3))
		var b := _part(n, "Blink%d" % i, bk, Vector3(sin(a) * 0.2, 0.97, cos(a) * 0.2))
		b.set_meta("period", 0.8 + float(i) * 0.17)
		b.set_meta("phase", float(i) * 0.3)
	PixelFont.draw(k, "USB", Vector3(0, 0.6, 0.185), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.02, Color(0.2, 0.45, 0.75))


## Geldautomat in Wandverkleidung mit leuchtendem Bildschirm.
static func _atm(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-0.55, 0, -0.35), Vector3(0.55, 2.2, 0.25), Color(0.18, 0.32, 0.55))
	k.box(Vector3(-0.45, 0.9, 0.25), Vector3(0.45, 1.45, 0.4), Color(0.75, 0.76, 0.78))
	k.box(Vector3(-0.25, 1.15, 0.36), Vector3(0.25, 1.4, 0.41), Color(0.3, 0.6, 0.9, 0.3))
	for i in range(12):
		k.box(Vector3(-0.15 + float(i % 3) * 0.1, 0.96 + float(i / 3) * 0.035, 0.39), Vector3(-0.08 + float(i % 3) * 0.1, 0.985 + float(i / 3) * 0.035, 0.42), CHROME)
	k.box(Vector3(0.15, 1.08, 0.38), Vector3(0.38, 1.1, 0.42), DARK)
	k.box(Vector3(-0.5, 1.95, 0.25), Vector3(0.5, 2.15, 0.27), Color(1, 1, 1, 0.3))
	PixelFont.draw(k, "EC", Vector3(0, 2.05, 0.28), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.03, Color(0.18, 0.32, 0.55))


## Kofferwagen ineinander geschoben, mit Bügel und Pfand-Schild.
static func _trolleys(k: Kit) -> void:
	k.box(Vector3(-1.5, 0, -0.55), Vector3(1.5, 0.02, 0.55), Color(0.45, 0.47, 0.5))
	for i in range(6):
		var z := -0.4 + float(i) * 0.0
		var x := -1.2 + float(i) * 0.45
		var c := Vector3(x, 0, z)
		k.box(c + Vector3(-0.28, 0.12, -0.3), c + Vector3(0.28, 0.16, 0.45), CHROME)
		for sx: float in [-0.25, 0.25]:
			k.box(c + Vector3(sx - 0.02, 0.12, 0.42), c + Vector3(sx + 0.02, 1.05, 0.46), CHROME)
			k.cyl(c + Vector3(sx, 0.07, -0.25), c + Vector3(sx, 0.07, -0.25), 0.07, 0.07, DARK, 8)
			k.cyl(c + Vector3(sx - 0.02, 0.07, 0.4), c + Vector3(sx + 0.02, 0.07, 0.4), 0.07, 0.07, DARK, 8)
		k.box(c + Vector3(-0.28, 1.02, 0.44), c + Vector3(0.28, 1.08, 0.5), Color(0.85, 0.15, 0.12))
		k.box(c + Vector3(-0.27, 0.16, 0.38), c + Vector3(0.27, 0.6, 0.41), Color(0.55, 0.57, 0.6))
	k.box(Vector3(1.35, 0, 0.3), Vector3(1.45, 1.6, 0.4), STEEL)
	k.box(Vector3(1.2, 1.3, 0.38), Vector3(1.6, 1.6, 0.42), Color(0.95, 0.75, 0.2))


## Zeitungskiosk: Theke, Regale mit bunten Zeitschriften, Kühlschrank, Verkäuferin.
static func _kiosk(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-1.5, 0, -1.0), Vector3(1.5, 0.04, 1.0), Color(0.75, 0.7, 0.62))
	k.box(Vector3(-1.4, 0, 0.3), Vector3(1.4, 1.0, 0.9), WALNUT)
	k.box(Vector3(-1.45, 1.0, 0.25), Vector3(1.45, 1.05, 0.95), Color(0.9, 0.88, 0.84))
	for side: float in [-1.0, 1.0]:
		k.box(Vector3(side * 1.45 - 0.05, 0, -1.0), Vector3(side * 1.45 + 0.05, 2.6, 1.0), WALNUT)
	k.box(Vector3(-1.45, 0, -1.0), Vector3(1.45, 2.4, -0.85), WALNUT)
	for row in range(5):
		var y := 0.4 + float(row) * 0.4
		k.box(Vector3(-1.4, y, -0.85), Vector3(1.4, y + 0.03, -0.55), Color(0.85, 0.82, 0.76))
		for i in range(12):
			var x := -1.3 + float(i) * 0.22
			var c := Color.from_hsv(fmod(float(i * 5 + row * 3) * 0.091, 1.0), 0.6, 0.85)
			k.box(Vector3(x, y + 0.03, -0.82), Vector3(x + 0.18, y + 0.3, -0.79), c)
	k.box(Vector3(-1.5, 2.6, -1.1), Vector3(1.5, 2.85, 1.1), Color(0.2, 0.35, 0.55))
	k.box(Vector3(-1.2, 2.62, 1.1), Vector3(1.2, 2.83, 1.12), Color(1, 1, 1, 0.3))
	PixelFont.draw(k, "PRESSE", Vector3(0, 2.72, 1.125), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.035, Color(0.2, 0.35, 0.55))
	k.box(Vector3(0.7, 1.05, 0.4), Vector3(1.2, 1.4, 0.8), Color(0.85, 0.9, 0.95, 0.3))
	k.box(Vector3(-0.9, 1.05, 0.5), Vector3(-0.5, 1.12, 0.8), DARK)
	_person(n, Color(0.75, 0.3, 0.3), Vector3(0, 0, -0.2), Vector3(0, 0, 1), 0)


## Aquarium mit Fischschwarm, Pflanzen, Steinen und Luftblasen.
static func _aquarium(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-2.0, 0, -0.6), Vector3(2.0, 0.8, 0.6), WALNUT)
	k.box(Vector3(-2.0, 0.8, -0.6), Vector3(2.0, 0.85, 0.6), DARK)
	k.box(Vector3(-1.95, 0.85, -0.55), Vector3(1.95, 0.95, 0.55), Color(0.85, 0.78, 0.6))
	for i in range(9):
		var p := Vector3(-1.7 + float(i) * 0.42, 0.95, -0.3 + float(i % 3) * 0.25)
		k.sphere(p, 0.08 + float(i % 3) * 0.04, Color(0.5, 0.48, 0.45), 8, 5)
	for i in range(7):
		var p := Vector3(-1.6 + float(i) * 0.55, 0.95, 0.1 - float(i % 2) * 0.35)
		for j in range(3):
			k.box(p + Vector3(float(j) * 0.05 - 0.05, 0, 0), p + Vector3(float(j) * 0.05 - 0.02, 0.4 + float((i + j) % 3) * 0.2, 0.03), LEAF2)
	k.box(Vector3(-1.98, 0.85, -0.58), Vector3(1.98, 2.05, -0.55), Color(0.25, 0.5, 0.65))
	k.box(Vector3(-2.0, 2.05, -0.6), Vector3(2.0, 2.18, 0.6), DARK)
	for x: float in [-2.0, 1.95]:
		k.box(Vector3(x, 0.85, -0.6), Vector3(x + 0.05, 2.05, 0.6), DARK)
	# Glas und Wasser durchsichtig, damit man die Fische sieht
	var glass := MeshInstance3D.new()
	glass.name = "Glas"
	var bm := BoxMesh.new()
	bm.size = Vector3(3.9, 1.18, 1.12)
	glass.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.72, 0.85, 0.28)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.1
	gm.metallic_specular = 0.8
	glass.material_override = gm
	glass.position = Vector3(0, 1.45, 0)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.set_meta("no_bake", true)
	n.add_child(glass)
	k.box(Vector3(-1.8, 2.0, -0.1), Vector3(1.8, 2.04, 0.1), LAMP)
	var fk := Kit.new()
	fk.sphere(Vector3.ZERO, 0.06, Color(1, 1, 1), 8, 5, Vector3(0.6, 1.0, 1.6))
	fk.tri(Vector3(0, 0.0, 0.08), Vector3(0, 0.06, 0.16), Vector3(0, -0.06, 0.16), Color(1, 1, 1), Vector3(0.1, 0, 0.1))
	fk.tri(Vector3(0, 0.0, 0.08), Vector3(0, -0.06, 0.16), Vector3(0, 0.06, 0.16), Color(1, 1, 1), Vector3(-0.1, 0, 0.1))
	var fish_mesh := fk.commit()
	for sw in range(2):
		var pts := PackedVector3Array()
		for i in range(24):
			var a := float(i) / 24.0 * TAU
			pts.append(Vector3(cos(a) * (1.6 - float(sw) * 0.4), 1.3 + float(sw) * 0.35 + sin(a * 2.0) * 0.12, sin(a) * (0.35 - float(sw) * 0.1)))
		var fish := MultiMeshInstance3D.new()
		fish.name = "Fische%d" % sw
		fish.set_script(BeltAnim)
		n.add_child(fish)
		fish.call("setup", pts, fish_mesh, 0.35 + float(sw) * 0.15, 0.7, true)
	var bk := Kit.new()
	for i in range(5):
		bk.sphere(Vector3(0, float(i) * 0.2, 0), 0.025, Color(0.85, 0.95, 1.0, 0.6), 6, 4)
	var b := _part(n, "HubBlasen", bk, Vector3(1.5, 1.0, 0.2))
	b.set_meta("speed", 1.5)


## Zimmerpalme: geschwungener Stamm mit Ringen, gefiederte Wedel (wiegen sich).
static func _palm(k: Kit, at: Vector3, s: float) -> void:
	var prev := at + Vector3(0, 0.55, 0)
	for i in range(8):
		var t := float(i + 1) / 8.0
		var p := at + Vector3(sin(t * 1.4) * 0.15 * s, (0.55 + t * 1.9) * s, 0)
		k.cyl(prev, p, (0.11 - t * 0.03) * s, (0.1 - t * 0.03) * s, Color(0.5, 0.38, 0.25), 8)
		k.cyl(p - Vector3(0, 0.02, 0), p + Vector3(0, 0.01, 0), (0.12 - t * 0.03) * s, (0.12 - t * 0.03) * s, Color(0.42, 0.32, 0.2), 8, true)
		prev = p
	for f in range(9):
		var a := float(f) / 9.0 * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var droop := 0.35 + float(f % 3) * 0.12
		var base := prev
		for seg in range(5):
			var t0 := float(seg) / 5.0
			var t1 := float(seg + 1) / 5.0
			var p0 := base + dir * t0 * 1.3 * s + Vector3(0, (0.25 * t0 - droop * t0 * t0) * s, 0)
			var p1 := base + dir * t1 * 1.3 * s + Vector3(0, (0.25 * t1 - droop * t1 * t1) * s, 0)
			var side := dir.cross(Vector3.UP) * (0.22 * (1.0 - t0 * 0.6)) * s
			k.quad(p0 - side, p0 + side, p1 + side * 0.8, p1 - side * 0.8, LEAF if f % 2 == 0 else LEAF2, (p0 + p1) * 0.5 + Vector3(0, -1, 0))


## Baum im Hochbeet mit Sitzrand aus Holz.
static func _tree_bed(k: Kit) -> void:
	k.box(Vector3(-1.9, 0, -1.9), Vector3(1.9, 0.5, 1.9), Color(0.82, 0.8, 0.76))
	k.box(Vector3(-2.0, 0.5, -2.0), Vector3(2.0, 0.56, 2.0), OAK)
	k.box(Vector3(-1.7, 0.5, -1.7), Vector3(1.7, 0.57, 1.7), SOIL)
	for i in range(14):
		var a := float(i) / 14.0 * TAU
		k.sphere(Vector3(cos(a) * 1.3, 0.62, sin(a) * 1.3), 0.18, Color.from_hsv(0.9 + float(i % 3) * 0.05, 0.5, 0.9, 0.8), 6, 4)
	k.cyl(Vector3(0, 0.55, 0), Vector3(0.1, 2.6, 0.05), 0.16, 0.1, Color(0.45, 0.35, 0.25), 10)
	for b in range(4):
		var a := float(b) / 4.0 * TAU + 0.4
		k.cyl(Vector3(0.05, 2.2, 0.0), Vector3(cos(a) * 0.9, 3.0, sin(a) * 0.9), 0.06, 0.03, Color(0.45, 0.35, 0.25), 6)
	for i in range(12):
		var a := float(i) / 12.0 * TAU
		var r := 0.9 + float(i % 3) * 0.25
		k.sphere(Vector3(cos(a) * r * 0.8, 3.0 + float(i % 4) * 0.25, sin(a) * r * 0.8), 0.55 + float(i % 2) * 0.15, LEAF if i % 2 == 0 else LEAF2, 8, 5)
	k.sphere(Vector3(0, 3.6, 0), 0.8, LEAF2, 9, 6)


## Hängendes Flugzeugmodell (dreht sich langsam) an Stahlseilen.
static func _model_plane(n: Node3D, k: Kit) -> void:
	for p: Vector3 in [Vector3(-1.2, 0, -1.2), Vector3(1.2, 0, 1.2)]:
		k.box(p + Vector3(-0.15, 0, -0.15), p + Vector3(0.15, 0.02, 0.15), Color(0.85, 0.65, 0.2))
	var pk := Kit.new()
	var pm: ArrayMesh = Models.plane_mesh("a320", Color(0.62, 0.22, 0.18))
	var holder := Node3D.new()
	holder.name = "DrehModell"
	holder.position = Vector3(0, 4.2, 0)
	holder.set_meta("speed", 0.12)
	holder.set_meta("no_bake", true)
	n.add_child(holder)
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.scale = Vector3(0.09, 0.09, 0.09)
	mi.rotation = Vector3(0.08, 0, 0.12)
	holder.add_child(mi)
	pk.cyl(Vector3(0, 0.3, 0), Vector3(0, 1.2, 0), 0.008, 0.008, CHROME, 4)
	var cable := pk.instance("Seil")
	holder.add_child(cable)


## Fahnenreihe: vier Masten mit wehenden Flaggen in Airline-Farben.
static func _flags(k: Kit) -> void:
	var cols := [Color(0.62, 0.22, 0.18), Color(0.18, 0.3, 0.52), Color(0.16, 0.42, 0.4), Color(0.85, 0.55, 0.12)]
	for i in range(4):
		var x := -1.5 + float(i)
		k.cyl(Vector3(x, 0, 0), Vector3(x, 0.05, 0), 0.15, 0.15, DARK, 10)
		k.cyl(Vector3(x, 0.05, 0), Vector3(x, 4.4, 0), 0.025, 0.02, CHROME, 6)
		k.sphere(Vector3(x, 4.43, 0), 0.04, Color(0.85, 0.7, 0.2), 6, 4)
		var c: Color = cols[i]
		c.a = 0.8
		for j in range(6):
			var y0 := 4.25 - float(j) * 0.28
			k.box(Vector3(x + 0.02, y0 - 0.28, -0.01), Vector3(x + 0.62, y0, 0.01), c if j % 3 != 1 else Color(0.95, 0.95, 0.92, 0.8))


## Konzertflügel mit Pianistin und Notenständer.
static func _piano(n: Node3D, k: Kit) -> void:
	var black := Color(0.05, 0.05, 0.06)
	var bottom := [Vector3(-0.75, 0.62, 0.55), Vector3(0.75, 0.62, 0.55), Vector3(0.75, 0.62, -0.6), Vector3(0.3, 0.62, -1.3), Vector3(-0.3, 0.62, -1.15), Vector3(-0.75, 0.62, -0.3)]
	var top := []
	for p: Vector3 in bottom:
		top.append(p + Vector3(0, 0.36, 0))
	k.prism(bottom, top, black)
	for p: Vector3 in [Vector3(-0.6, 0, 0.45), Vector3(0.6, 0, 0.45), Vector3(0.15, 0, -1.0)]:
		k.cyl(p, p + Vector3(0, 0.62, 0), 0.05, 0.06, black, 8)
	k.box(Vector3(-0.72, 0.75, 0.55), Vector3(0.72, 0.8, 0.78), black)
	for i in range(26):
		k.box(Vector3(-0.7 + float(i) * 0.054, 0.8, 0.56), Vector3(-0.65 + float(i) * 0.054, 0.82, 0.76), WHITE)
	for i in range(26):
		if i % 7 in [2, 6]:
			continue
		k.box(Vector3(-0.68 + float(i) * 0.054, 0.82, 0.62), Vector3(-0.65 + float(i) * 0.054, 0.84, 0.76), black)
	k.box(Vector3(-0.5, 1.0, 0.4), Vector3(0.5, 1.3, 0.45), black)
	k.box(Vector3(-0.3, 1.02, 0.39), Vector3(0.3, 1.25, 0.4), WHITE)
	var lid := [Vector3(-0.73, 0.98, 0.5), Vector3(0.73, 0.98, 0.5), Vector3(0.6, 1.7, -0.4), Vector3(-0.6, 1.5, -0.2)]
	k.quad(lid[0], lid[1], lid[2], lid[3], black, Vector3(0, 0.5, 0.5))
	k.box(Vector3(-0.45, 0.45, 1.05), Vector3(0.45, 0.52, 1.35), black)
	_person(n, Color(0.55, 0.15, 0.3), Vector3(0, 0, 1.25), Vector3(0, 0, -1), 0)


## Massagesessel (zwei Stück) mit Münzautomat; die Lehnen arbeiten.
static func _massage(n: Node3D, k: Kit) -> void:
	for sx: float in [-0.75, 0.75]:
		k.rounded_box(Vector3(sx - 0.45, 0.0, -0.4), Vector3(sx + 0.45, 0.45, 0.55), 0.08, DARK, 2)
		k.rounded_box(Vector3(sx - 0.42, 0.45, -0.3), Vector3(sx + 0.42, 0.55, 0.5), 0.06, Color(0.35, 0.2, 0.15), 2)
		for side: float in [-1.0, 1.0]:
			k.rounded_box(Vector3(sx + side * 0.42 - 0.08, 0.45, -0.35), Vector3(sx + side * 0.42 + 0.08, 0.8, 0.5), 0.05, DARK, 2)
		var bk := Kit.new()
		bk.rounded_box(Vector3(-0.4, 0.0, -0.12), Vector3(0.4, 0.9, 0.08), 0.08, Color(0.35, 0.2, 0.15), 2)
		bk.rounded_box(Vector3(-0.25, 0.75, -0.1), Vector3(0.25, 1.0, 0.1), 0.06, Color(0.4, 0.24, 0.18), 2)
		var back := _part(n, "Wipp%d" % int(sx * 10.0 + 10.0), bk, Vector3(sx, 0.5, -0.35))
		back.rotation.x = -0.25
		back.set_meta("amp", 0.04)
		back.set_meta("speed", 5.0)
	k.box(Vector3(-0.15, 0, -0.5), Vector3(0.15, 1.1, -0.2), STEEL)
	k.box(Vector3(-0.12, 0.8, -0.2), Vector3(0.12, 1.0, -0.18), Color(0.3, 0.9, 0.5, 0.3))


## Mülltrennung: vier Fächer mit farbigen Deckeln und Symbolen.
static func _bins(k: Kit) -> void:
	var cols := [Color(0.25, 0.45, 0.85), Color(0.95, 0.8, 0.15), Color(0.3, 0.65, 0.35), Color(0.35, 0.35, 0.37)]
	k.box(Vector3(-0.8, 0, -0.3), Vector3(0.8, 0.95, 0.3), Color(0.82, 0.83, 0.84))
	for i in range(4):
		var x := -0.6 + float(i) * 0.4
		k.box(Vector3(x - 0.17, 0.95, -0.28), Vector3(x + 0.17, 1.0, 0.28), cols[i])
		k.box(Vector3(x - 0.12, 0.7, 0.3), Vector3(x + 0.12, 0.88, 0.32), cols[i])
		k.box(Vector3(x - 0.1, 0.9, 0.29), Vector3(x + 0.1, 0.95, 0.31), DARK)


## Grüne Wand: Rahmen mit vielen Pflanzentaschen (die Blätter wiegen sich).
static func _green_wall(k: Kit) -> void:
	k.box(Vector3(-2.0, 0, -0.25), Vector3(2.0, 3.3, -0.1), Color(0.3, 0.25, 0.2))
	k.box(Vector3(-2.05, 0, -0.25), Vector3(2.05, 0.3, 0.15), Color(0.82, 0.8, 0.76))
	for row in range(10):
		for col in range(13):
			var x := -1.85 + float(col) * 0.3 + float(row % 2) * 0.15
			var y := 0.45 + float(row) * 0.29
			if x > 1.9:
				continue
			var c := LEAF if (row + col) % 3 == 0 else (LEAF2 if (row + col) % 3 == 1 else Color(0.2, 0.38, 0.18, 0.8))
			k.sphere(Vector3(x, y, -0.02), 0.17 + 0.03 * float((row * 7 + col) % 3), c, 6, 4, Vector3(1.0, 0.85, 0.6))
			if (row * 5 + col) % 11 == 0:
				k.sphere(Vector3(x + 0.05, y + 0.05, 0.1), 0.06, Color(0.95, 0.4, 0.5, 0.8), 6, 4)


## Springbrunnen: rundes Becken, Wasser, drei Fontänen, die sich heben und senken.
static func _fountain(n: Node3D, k: Kit) -> void:
	k.cyl(Vector3(0, 0, 0), Vector3(0, 0.2, 0), 1.9, 1.9, Color(0.78, 0.76, 0.72), 28)
	# Beckenrand als Ring aus Steinen, darin das Wasser
	for i in range(28):
		var a0 := float(i) / 28.0 * TAU
		var a1 := float(i + 1) / 28.0 * TAU
		var p0 := Vector3(cos(a0), 0, sin(a0)) * 1.82
		var p1 := Vector3(cos(a1), 0, sin(a1)) * 1.82
		var d := p1 - p0
		k.box(Vector3(-0.13, 0.2, -d.length() * 0.55), Vector3(0.13, 0.56, d.length() * 0.55), Color(0.84, 0.82, 0.78),
			Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), (p0 + p1) * 0.5))
	k.cyl(Vector3(0, 0.2, 0), Vector3(0, 0.44, 0), 1.72, 1.72, WATER, 28, true, Color(0.42, 0.7, 0.88))
	for i in range(10):
		var a := float(i) * 2.4
		k.cyl(Vector3(cos(a) * float(i % 4) * 0.4, 0.44, sin(a) * float(i % 4) * 0.4), Vector3(cos(a) * float(i % 4) * 0.4, 0.445, sin(a) * float(i % 4) * 0.4), 0.18, 0.18, Color(0.6, 0.82, 0.95), 10)
	k.cyl(Vector3(0, 0.46, 0), Vector3(0, 0.9, 0), 0.35, 0.3, Color(0.78, 0.76, 0.72), 14)
	k.cyl(Vector3(0, 0.9, 0), Vector3(0, 0.95, 0), 0.7, 0.7, Color(0.85, 0.83, 0.8), 18)
	k.cyl(Vector3(0, 0.85, 0), Vector3(0, 0.93, 0), 0.62, 0.62, Color(0.4, 0.68, 0.85, 0.6), 18)
	for i in range(3):
		var jk := Kit.new()
		jk.cyl(Vector3(0, 0, 0), Vector3(0, 1.0, 0), 0.06, 0.03, Color(0.8, 0.92, 1.0, 0.6), 8)
		jk.sphere(Vector3(0, 1.0, 0), 0.12, Color(0.85, 0.95, 1.0, 0.6), 8, 5)
		var a := float(i) / 3.0 * TAU
		var at := Vector3(0, 0.95, 0) if i == 0 else Vector3(cos(a) * 1.1, 0.46, sin(a) * 1.1)
		var j := _part(n, "Hub%d" % i, jk, at)
		j.set_meta("speed", 2.0 + float(i) * 0.7)
		j.set_meta("phase", float(i) * 1.7)
		if i > 0:
			j.scale = Vector3(1, 0.7, 1)
	for i in range(8):
		var a := float(i) / 8.0 * TAU
		k.cyl(Vector3(cos(a) * 1.85, 0.5, sin(a) * 1.85), Vector3(cos(a) * 1.85, 0.57, sin(a) * 1.85), 0.08, 0.08, LAMP, 8)
