extends RefCounted
## Terminal-Einrichtung im feinen Stil (Eingang, Check-in, Kontrolle, Gates, Gepäckband, WC,
## Café, Laden, Sitzreihen, Anzeigen …). Vorderseite +Z. Die Lagen, an denen terminal.gd
## Fahrgäste entlangführt (Kontrollspuren, Sitzplätze am Gate, Gepäckband), bleiben wie bisher.
## Bewegte Teile heißen nach deco_anim.gd (Schieb*, Dreh*, Hub*, Blink*) oder laufen als
## MultiMesh über belt_anim.gd. Die Koffer auf dem Gepäckband ("Koffer"/K0..K8) bewegt terminal.gd.

const Kit = preload("res://scripts/mesh_kit.gd")
const Models = preload("res://scripts/models.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")
const BeltAnim = preload("res://scripts/belt_anim.gd")
const DecoAnim = preload("res://scripts/deco_anim.gd")
const Landmarks = preload("res://scripts/landmarks.gd")
const SCREEN_SHADER = preload("res://shaders/screen.gdshader")

const CHROME := Color(0.74, 0.76, 0.79)
const STEEL := Color(0.4, 0.44, 0.47)
const DARK := Color(0.12, 0.12, 0.13)
const WHITE := Color(0.93, 0.92, 0.89)
const OAK := Color(0.64, 0.47, 0.3)
const WALNUT := Color(0.38, 0.26, 0.17)
const SEAT := Color(0.22, 0.35, 0.55)
const YELLOW := Color(0.92, 0.74, 0.18)
const LAMP := Color(1.0, 0.93, 0.74, 0.3)
const LEAF := Color(0.24, 0.45, 0.2, 0.8)
const LEAF2 := Color(0.33, 0.56, 0.25, 0.8)
const BRAND := Color(0.18, 0.3, 0.52)
const BAG_COLS := [Color(0.62, 0.18, 0.16), Color(0.18, 0.28, 0.5), Color(0.14, 0.14, 0.15), Color(0.5, 0.4, 0.27),
	Color(0.25, 0.45, 0.3), Color(0.78, 0.75, 0.7), Color(0.85, 0.6, 0.15), Color(0.4, 0.22, 0.45)]

const IDS := ["eingang", "rolltor", "checkin", "gepaecklift", "gepaeckanlage", "sicherheit", "gate", "busgate", "gepaeckband", "wc", "sb_ausgang",
	"heizkoerper", "cafe", "shop", "sitzreihe", "pflanze", "anzeige", "kunst", "tuer", "personalraum"]

static var _glass: StandardMaterial3D


static func build(n: Node3D, id: String, opts: Dictionary) -> bool:
	if not (id in IDS):
		return false
	var k := Kit.new()
	var anim := false
	match id:
		"eingang":
			_entrance(n, k, String(opts.get("tuer", "schiebe")))
			anim = true
		"rolltor":
			_roll_gate(n, k)
		"checkin":
			_checkin(n, k)
		"gepaeckanlage":
			_sorter(n, k, int(opts.get("rutschen", 4)))
			anim = true
		"gepaecklift":
			_bag_lift(k)
		"sicherheit":
			_security(n, k, String(opts.get("technik", "klassisch")))
			if bool(opts.get("fastlane", false)):
				# Fast-Lane für Vielflieger: goldener Boden und Schild über der rechten Spur
				k.box(Vector3(0.2, 0.04, -4.0), Vector3(3.0, 0.05, 4.0), Color(0.62, 0.5, 0.24))
				k.box(Vector3(0.4, 2.3, 3.9), Vector3(2.9, 2.75, 4.0), Color(0.15, 0.13, 0.1))
				PixelFont.draw(k, "FAST LANE", Vector3(1.65, 2.52, 4.02), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.035, Color(0.95, 0.8, 0.4))
			anim = true
		"gate":
			_gate(n, k, String(opts.get("bereich", "schengen")), false)
			anim = true
		"busgate":
			_gate(n, k, String(opts.get("bereich", "schengen")), true)
			anim = true
		"gepaeckband":
			_claim(n, k, String(opts.get("stil", "oval")))
			anim = true
		"wc":
			_toilets(k)
		"sb_ausgang":
			_exit(n, k)
			anim = true
		"heizkoerper":
			_radiator(k)
		"cafe":
			_cafe(n, k, String(opts.get("stil", "cafe")))
			anim = true
		"shop":
			_shop(n, k, String(opts.get("stil", "kiosk")))
		"sitzreihe":
			_seat_row(k, Vector3.ZERO, 5, -1.0, SEAT)
		"pflanze":
			_plant(k)
		"anzeige":
			_board(n, k)
		"kunst":
			_art(n, k)
			anim = true
		"tuer":
			_door(n, k, String(opts.get("art", "automatik")))
		"personalraum":
			_staff_room(n, k)
			anim = true
	if k.count > 0:
		n.add_child(k.instance("Einrichtung"))
	if anim:
		var a := Node.new()
		a.name = "Anim"
		a.set_script(DecoAnim)
		n.add_child(a)
	return true


# ---------------------------------------------------------------- Hilfen

static func glass() -> StandardMaterial3D:
	if _glass == null:
		_glass = StandardMaterial3D.new()
		_glass.albedo_color = Color(0.62, 0.78, 0.86, 0.32)
		_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass.roughness = 0.08
		_glass.metallic_specular = 0.9
	return _glass


## Glasscheibe als eigener Knoten (durchsichtig), optional als Schiebetür.
static func _pane(n: Node3D, name: String, a: Vector3, b: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var bm := BoxMesh.new()
	bm.size = (b - a).abs()
	mi.mesh = bm
	mi.material_override = glass()
	mi.position = (a + b) * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_bake", true)
	n.add_child(mi)
	return mi


static func _part(n: Node3D, name: String, k: Kit, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := k.instance(name)
	mi.position = at
	mi.set_meta("no_bake", true)
	n.add_child(mi)
	return mi


static func _screen(n: Node3D, name: String, size: Vector2, at: Vector3, face: Vector3, mode: int) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var sm := ShaderMaterial.new()
	sm.shader = SCREEN_SHADER
	sm.set_shader_parameter("seed", randf() * 20.0)
	sm.set_shader_parameter("mode", mode)
	mi.material_override = sm
	mi.position = at
	mi.basis = Basis.looking_at(-face, Vector3.UP)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_bake", true)
	n.add_child(mi)


static func _staff(n: Node3D, shirt: Color, at: Vector3, skin: int, face: Vector3 = Vector3.ZERO) -> void:
	var Factory = load("res://scripts/factory.gd")
	var p: Node3D = Factory.make_staff(shirt, Color(0.12, 0.13, 0.18), skin)
	p.position = at
	if face != Vector3.ZERO:
		p.basis = Basis.looking_at(face, Vector3.UP)
	n.add_child(p)


static func _bag_mesh(c: Color) -> ArrayMesh:
	var k := Kit.new()
	k.rounded_box(Vector3(-0.34, -0.16, -0.22), Vector3(0.34, 0.16, 0.22), 0.05, c, 2)
	k.box(Vector3(-0.35, -0.02, -0.23), Vector3(0.35, 0.02, 0.23), c.darkened(0.25))
	k.box(Vector3(-0.1, 0.16, -0.03), Vector3(0.1, 0.21, 0.03), DARK)
	return k.commit()


## Gurtpfosten-Gasse im Zickzack (vorn vor dem Schalter).
static func _queue(k: Kit, x0: float, x1: float, z0: float, rows: int, dz: float) -> void:
	for row in range(rows):
		var z := z0 + float(row) * dz
		var px := x0
		while px <= x1 + 0.01:
			k.cyl(Vector3(px, 0, z), Vector3(px, 0.03, z), 0.17, 0.17, DARK, 12)
			k.cyl(Vector3(px, 0.03, z), Vector3(px, 0.95, z), 0.03, 0.03, CHROME, 8)
			k.cyl(Vector3(px, 0.95, z), Vector3(px, 1.0, z), 0.045, 0.045, CHROME, 8)
			px += 1.4
		var gap_left := row % 2 == 1
		var a := x0 if not gap_left else x0 + 1.4
		var b := x1 if gap_left else x1 - 1.4
		k.box(Vector3(a, 0.86, z - 0.012), Vector3(b, 0.94, z + 0.012), Color(0.62, 0.14, 0.14))


## Reihe von Einzelsitzen auf einem Träger; back = -1: Lehne hinten (−Z), +1: vorn.
static func _seat_row(k: Kit, c: Vector3, count: int, back: float, col: Color) -> void:
	var w := 0.93
	var x0 := -float(count - 1) * 0.5 * w
	k.box(c + Vector3(x0 - 0.4, 0.3, -0.06), c + Vector3(-x0 + 0.4, 0.36, 0.06), CHROME)
	for lx: float in [x0 + 0.2, -x0 - 0.2]:
		k.box(c + Vector3(lx - 0.04, 0, -0.28), c + Vector3(lx + 0.04, 0.32, 0.28), CHROME)
		k.box(c + Vector3(lx - 0.05, 0, -0.32), c + Vector3(lx + 0.05, 0.03, 0.32), DARK)
	for i in range(count):
		var x := x0 + float(i) * w
		k.rounded_box(c + Vector3(x - 0.42, 0.38, -0.27), c + Vector3(x + 0.42, 0.47, 0.27), 0.04, col, 2)
		k.rounded_box(c + Vector3(x - 0.42, 0.47, back * 0.36 - 0.05), c + Vector3(x + 0.42, 0.98, back * 0.36 + 0.05), 0.04, col.darkened(0.12), 2)
		if i < count - 1:
			var ax := x + w * 0.5
			k.box(c + Vector3(ax - 0.03, 0.36, -0.22), c + Vector3(ax + 0.03, 0.62, 0.22), DARK)
			k.box(c + Vector3(ax - 0.05, 0.62, -0.24), c + Vector3(ax + 0.05, 0.66, 0.24), DARK)


# ---------------------------------------------------------------- Eingang

## Rolltor in der Außenwand (Wand bei lokal +Z): Vorhang "Rolltor0" mit Drehpunkt oben, Warnlicht,
## innen Rollenbahn als Einlauf für die Koffer, gelb-schwarze Sperrfläche, Anfahrschutz, Bedienpult.
static func _roll_gate(n: Node3D, k: Kit) -> void:
	Landmarks.roll_door(n, k, 0, Vector3(0, 0, 0.82), 4.6, 3.9, Color(0.78, 0.8, 0.82), 2)
	# Sperrfläche innen (Schraffur)
	k.box(Vector3(-2.6, 0.0, -1.0), Vector3(2.6, 0.02, 0.7), Color(0.16, 0.16, 0.17))
	for i in range(13):
		var x := -2.5 + float(i) * 0.4
		k.box(Vector3(x, 0.02, -0.95), Vector3(x + 0.2, 0.025, 0.65), YELLOW)
	# Anfahrschutz-Poller an beiden Seiten
	for sx: float in [-2.75, 2.75]:
		k.cyl(Vector3(sx, 0, 0.35), Vector3(sx, 1.1, 0.35), 0.11, 0.11, YELLOW, 10)
		for y: float in [0.3, 0.7]:
			k.cyl(Vector3(sx, y, 0.35), Vector3(sx, y + 0.12, 0.35), 0.115, 0.115, DARK, 10)
	# Rollenbahn neben der Fahrspur: vom Tor nach innen (Einlauf für die Koffer), auf Bandhöhe
	var rx := 2.1
	k.box(Vector3(rx - 0.5, 0.48, -1.0), Vector3(rx + 0.5, 0.56, 0.62), STEEL)
	for i in range(9):
		var z := -0.95 + float(i) * 0.19
		k.cyl(Vector3(rx - 0.44, 0.6, z), Vector3(rx + 0.44, 0.6, z), 0.04, 0.04, CHROME, 8)
	for sx: float in [rx - 0.52, rx + 0.52]:
		k.box(Vector3(sx - 0.02, 0.48, -1.0), Vector3(sx + 0.02, 0.72, 0.62), STEEL)
		for z: float in [-0.8, 0.4]:
			k.box(Vector3(sx - 0.04, 0.0, z - 0.04), Vector3(sx + 0.04, 0.48, z + 0.04), STEEL)
	# Bedienpult mit Tastern (auf der anderen Seite)
	k.box(Vector3(-2.55, 0.0, -0.6), Vector3(-2.2, 1.2, -0.3), Color(0.5, 0.52, 0.55))
	k.box(Vector3(-2.6, 1.0, -0.62), Vector3(-2.15, 1.25, -0.28), Color(0.85, 0.85, 0.82))
	k.cyl(Vector3(-2.45, 1.25, -0.45), Vector3(-2.45, 1.29, -0.45), 0.04, 0.04, Color(0.2, 0.75, 0.3), 8)
	k.cyl(Vector3(-2.3, 1.25, -0.45), Vector3(-2.3, 1.29, -0.45), 0.04, 0.04, Color(0.85, 0.15, 0.12), 8)
	# Fahrspur der Gepäckzüge nach innen: gelbe Randlinien
	for sx: float in [-1.9, 1.5]:
		k.box(Vector3(sx, 0.0, -9.0), Vector3(sx + 0.12, 0.03, -1.0), YELLOW)
	PixelFont.draw_ground(k, "TOR", Vector3(-0.2, 0.035, -2.0), Vector3(0, 0, -1), 0.07, Color(0.95, 0.95, 0.9))


static func _entrance(n: Node3D, k: Kit, tuer: String) -> void:
	# Fußmatte innen, Rahmen, Oberlicht, Vordach mit Lichtern und Schriftzug
	k.box(Vector3(-2.9, 0, -1.0), Vector3(2.9, 0.03, 0.1), Color(0.2, 0.2, 0.22))
	for i in range(14):
		k.box(Vector3(-2.8 + float(i) * 0.4, 0.03, -0.95), Vector3(-2.65 + float(i) * 0.4, 0.035, 0.05), Color(0.28, 0.28, 0.3))
	for x: float in [-2.9, 2.9]:
		k.box(Vector3(x - 0.12, 0, -0.18), Vector3(x + 0.12, 3.3, 0.18), STEEL)
	k.box(Vector3(-3.0, 2.75, -0.2), Vector3(3.0, 2.9, 0.2), STEEL)
	k.box(Vector3(-3.0, 3.2, -0.2), Vector3(3.0, 3.35, 0.2), STEEL)
	_pane(n, "Oberlicht", Vector3(-2.78, 2.9, -0.03), Vector3(2.78, 3.2, 0.03))
	for x: float in [-1.25, 1.25]:
		k.box(Vector3(x - 0.05, 0, -0.08), Vector3(x + 0.05, 2.75, 0.08), STEEL)
	for side: float in [-1.0, 1.0]:
		_pane(n, "Seite%d" % int(side + 1.0), Vector3(side * 1.3, 0.05, -0.03), Vector3(side * 2.78, 2.75, 0.03))
	if tuer == "dreh":
		# Karusselltür: Glastrommel mit vier Flügeln, dreht sich langsam
		k.cyl(Vector3(0, 0, 0), Vector3(0, 0.04, 0), 1.25, 1.25, Color(0.3, 0.3, 0.32), 24)
		k.cyl(Vector3(0, 2.62, 0), Vector3(0, 2.75, 0), 1.3, 1.3, STEEL, 24)
		for side: float in [-1.0, 1.0]:
			for i in range(5):
				var a := PI * 0.5 * side + (float(i) - 2.0) * 0.28
				var p := Vector3(cos(a) * 1.22, 0, sin(a) * 1.22)
				k.box(p + Vector3(-0.03, 0.04, -0.03), p + Vector3(0.03, 2.62, 0.03), STEEL)
		var wing := Node3D.new()
		wing.name = "DrehTuer"
		wing.set_meta("speed", 0.5)
		wing.set_meta("no_bake", true)
		n.add_child(wing)
		k.cyl(Vector3(0, 0, 0), Vector3(0, 2.62, 0), 0.06, 0.06, STEEL, 8)
		for i in range(4):
			var g := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.12, 2.4, 0.04)
			g.mesh = bm
			g.material_override = glass()
			g.position = Vector3(cos(float(i) * PI * 0.5) * 0.6, 1.3, sin(float(i) * PI * 0.5) * 0.6)
			g.rotation.y = -float(i) * PI * 0.5
			wing.add_child(g)
	else:
		# Schiebetür mit zwei Flügeln, öffnet und schließt
		k.box(Vector3(-1.2, 2.55, -0.15), Vector3(1.2, 2.75, 0.15), Color(0.3, 0.32, 0.34))
		k.box(Vector3(-0.15, 2.6, 0.15), Vector3(0.15, 2.68, 0.17), Color(0.2, 0.9, 0.4, 0.3))
		for side: float in [-1.0, 1.0]:
			var leaf := _pane(n, "Schieb%d" % int(side + 1.0), Vector3(side * 0.02, 0.05, -0.05), Vector3(side * 1.2, 2.55, 0.05))
			leaf.set_meta("dx", side * 1.1)
			var fk := Kit.new()
			fk.box(Vector3(-0.6, -1.25, -0.06), Vector3(0.6, -1.17, 0.06), STEEL)
			fk.box(Vector3(-0.6, 1.17, -0.06), Vector3(0.6, 1.25, 0.06), STEEL)
			fk.box(Vector3(-side * 0.6 - 0.03, -1.25, -0.06), Vector3(-side * 0.6 + 0.03, 1.25, 0.06), STEEL)
			fk.box(Vector3(-0.2, 0.0, 0.06), Vector3(0.2, 0.03, 0.07), Color(0.9, 0.3, 0.2))
			leaf.add_child(fk.instance("Rahmen"))
	# Laibung bis zur Fassade (Wand bei z = +1): Seitenwangen und Sturz, die Halle hat dort eine Öffnung
	for x: float in [-3.0, 3.0]:
		k.box(Vector3(x - 0.08, 0, 0.18), Vector3(x + 0.08, 3.35, 1.05), Color(0.3, 0.33, 0.35))
	k.box(Vector3(-3.08, 3.35, -0.2), Vector3(3.08, 3.5, 1.05), Color(0.3, 0.33, 0.35))
	k.box(Vector3(-2.9, 0, 0.18), Vector3(2.9, 0.025, 1.0), Color(0.24, 0.24, 0.26))
	# Vordach außen (+Z)
	k.box(Vector3(-3.7, 3.5, 0.9), Vector3(3.7, 3.72, 4.0), Color(0.82, 0.83, 0.84))
	k.box(Vector3(-3.75, 3.72, 0.9), Vector3(3.75, 3.78, 4.05), STEEL)
	for i in range(5):
		var x := -2.8 + float(i) * 1.4
		k.box(Vector3(x - 0.2, 3.46, 2.2), Vector3(x + 0.2, 3.5, 2.6), LAMP)
	for x: float in [-3.4, 3.4]:
		k.cyl(Vector3(x, 0, 3.6), Vector3(x, 3.5, 3.6), 0.12, 0.12, STEEL, 12)
		k.cyl(Vector3(x, 0, 3.6), Vector3(x, 0.08, 3.6), 0.22, 0.22, DARK, 12)
	k.box(Vector3(-1.8, 3.78, 3.9), Vector3(1.8, 4.35, 4.0), BRAND)
	PixelFont.draw(k, "ABFLUG", Vector3(0, 4.06, 4.02), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.07, Color(1, 1, 1, 0.3))
	PixelFont.draw_ground(k, "EINGANG", Vector3(0, 0.02, 2.2), Vector3(0, 0, -1), 0.12, Color(0.9, 0.9, 0.86))


# ---------------------------------------------------------------- Check-in

static func _checkin(n: Node3D, k: Kit) -> void:
	# Hinten: Sammelband auf Stahlgestell, das die Koffer seitlich zum Kofferband (Gepäcksortierung) bringt
	k.box(Vector3(-3.0, 0.0, -1.42), Vector3(3.0, 0.06, -0.9), Color(0.3, 0.31, 0.33))
	for x: float in [-2.85, -1.0, 1.0, 2.85]:
		for z: float in [-1.36, -0.96]:
			k.box(Vector3(x - 0.04, 0.06, z - 0.04), Vector3(x + 0.04, 0.4, z + 0.04), STEEL)
	k.box(Vector3(-3.0, 0.38, -1.4), Vector3(3.0, 0.43, -0.92), STEEL)
	k.box(Vector3(-3.0, 0.43, -1.34), Vector3(3.0, 0.45, -0.98), Color(0.1, 0.1, 0.11))
	for x in range(-5, 6):
		k.box(Vector3(float(x) * 0.55 - 0.02, 0.45, -1.34), Vector3(float(x) * 0.55 + 0.02, 0.452, -0.98), Color(0.2, 0.2, 0.21))
	for z: float in [-1.4, -0.92]:
		k.box(Vector3(-3.0, 0.45, z - 0.025), Vector3(3.0, 0.58, z + 0.025), CHROME)
	# Lichtportal: zwei schlanke Stelen mit Leuchtkasten und Fluginfo-Bildschirmen
	for x: float in [-2.92, 2.92]:
		k.rounded_box(Vector3(x - 0.08, 0.0, -0.86), Vector3(x + 0.08, 2.75, -0.7), 0.03, Color(0.24, 0.25, 0.27), 2)
	k.rounded_box(Vector3(-3.0, 2.28, -0.88), Vector3(3.0, 2.78, -0.68), 0.04, Color(0.2, 0.21, 0.23), 2)
	k.box(Vector3(-2.85, 2.34, -0.68), Vector3(2.85, 2.72, -0.665), BRAND)
	k.box(Vector3(-2.85, 2.34, -0.665), Vector3(-1.2, 2.72, -0.66), Color(0.95, 0.95, 0.92, 0.3))
	PixelFont.draw(k, "CHECK-IN", Vector3(-2.02, 2.53, -0.655), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.035, BRAND)
	_screen(n, "Fluginfo1", Vector2(1.15, 0.32), Vector3(-0.05, 2.53, -0.655), Vector3(0, 0, 1), 2)
	_screen(n, "Fluginfo2", Vector2(1.15, 0.32), Vector3(1.55, 2.53, -0.655), Vector3(0, 0, 1), 2)
	# Teppichläufer vor den Schaltern
	k.box(Vector3(-2.9, 0.0, 0.55), Vector3(2.9, 0.012, 1.5), Color(0.22, 0.26, 0.36))
	k.box(Vector3(-2.9, 0.012, 0.55), Vector3(2.9, 0.014, 0.6), YELLOW.darkened(0.2))
	for x: float in [-1.55, 1.55]:
		# Schalter: weiße, vorn gerundete Theke mit Holzblende und Markenstreifen
		k.rounded_box(Vector3(x - 1.12, 0.0, -0.3), Vector3(x + 1.12, 1.0, 0.45), 0.12, WHITE, 3)
		k.box(Vector3(x - 1.0, 0.1, 0.45), Vector3(x + 1.0, 0.82, 0.48), OAK)
		for i in range(9):
			k.box(Vector3(x - 0.96 + float(i) * 0.24, 0.12, 0.48), Vector3(x - 0.93 + float(i) * 0.24, 0.8, 0.49), OAK.darkened(0.18))
		k.box(Vector3(x - 1.0, 0.84, 0.46), Vector3(x + 1.0, 0.9, 0.485), BRAND)
		# Glasblende auf der Theke
		k.box(Vector3(x - 1.05, 1.0, 0.3), Vector3(x + 1.05, 1.18, 0.34), Color(0.62, 0.78, 0.85, 0.6))
		k.box(Vector3(x - 1.15, 1.0, -0.32), Vector3(x + 1.15, 1.04, 0.47), Color(0.2, 0.2, 0.22))
		# Arbeitsplatz: flacher Bildschirm, Drucker für Bordkarten und Banderolen, Kartenleser
		var sx := x - 0.35 if x < 0.0 else x + 0.35
		k.box(Vector3(sx - 0.02, 1.04, -0.12), Vector3(sx + 0.02, 1.32, -0.08), CHROME)
		k.box(Vector3(sx - 0.3, 1.18, -0.1), Vector3(sx + 0.3, 1.52, -0.07), DARK)
		k.box(Vector3(sx - 0.27, 1.21, -0.07), Vector3(sx + 0.27, 1.49, -0.065), Color(0.4, 0.65, 0.9, 0.3))
		var px := x + 0.55 if x < 0.0 else x - 0.55
		k.rounded_box(Vector3(px - 0.18, 1.04, -0.05), Vector3(px + 0.18, 1.2, 0.22), 0.03, Color(0.82, 0.82, 0.8), 2)
		k.box(Vector3(px - 0.12, 1.2, 0.02), Vector3(px + 0.12, 1.205, 0.15), Color(0.97, 0.97, 0.95))
		k.box(Vector3(x - 0.05, 1.04, 0.2), Vector3(x + 0.08, 1.12, 0.3), Color(0.16, 0.16, 0.17))
		k.box(Vector3(x - 0.03, 1.12, 0.21), Vector3(x + 0.06, 1.13, 0.27), Color(0.3, 0.9, 0.5, 0.3))
		# Bürostuhl
		k.cyl(Vector3(x, 0, -0.62), Vector3(x, 0.45, -0.62), 0.04, 0.04, CHROME, 6)
		k.cyl(Vector3(x, 0.45, -0.62), Vector3(x, 0.5, -0.62), 0.24, 0.24, DARK, 10)
		_staff(n, BRAND, Vector3(x, 0, -0.62), 0 if x < 0.0 else 2)
	# Gepäckaufgabe in der Mitte: Waage mit Edelstahlplatte, Einzugsband nach hinten, Gewichtsanzeige
	k.rounded_box(Vector3(-0.36, 0.0, -0.95), Vector3(0.36, 0.34, 0.62), 0.04, STEEL, 2)
	k.box(Vector3(-0.32, 0.34, 0.05), Vector3(0.32, 0.37, 0.58), CHROME)
	k.box(Vector3(-0.32, 0.34, -0.95), Vector3(0.32, 0.38, 0.05), Color(0.1, 0.1, 0.11))
	for i in range(4):
		k.box(Vector3(-0.32, 0.38, -0.9 + float(i) * 0.24), Vector3(0.32, 0.385, -0.87 + float(i) * 0.24), Color(0.22, 0.22, 0.23))
	k.box(Vector3(-0.36, 0.34, -0.95), Vector3(-0.32, 0.6, 0.6), CHROME)
	k.box(Vector3(0.32, 0.34, -0.95), Vector3(0.36, 0.6, 0.6), CHROME)
	# Gummivorhang in die Rückwand
	for i in range(5):
		k.box(Vector3(-0.3 + float(i) * 0.12, 0.4, -0.86), Vector3(-0.2 + float(i) * 0.12, 0.85, -0.84), Color(0.08, 0.08, 0.08))
	k.box(Vector3(-0.38, 0.85, -0.9), Vector3(0.38, 0.95, -0.8), Color(0.25, 0.26, 0.28))
	k.cyl(Vector3(0.48, 0.0, 0.55), Vector3(0.48, 1.25, 0.55), 0.03, 0.03, CHROME, 6)
	k.box(Vector3(0.36, 1.2, 0.5), Vector3(0.6, 1.36, 0.58), DARK)
	k.box(Vector3(0.38, 1.22, 0.58), Vector3(0.58, 1.34, 0.585), Color(0.3, 1.0, 0.5, 0.3))
	var bk := Kit.new()
	bk.rounded_box(Vector3(-0.2, 0.0, -0.3), Vector3(0.2, 0.45, 0.3), 0.04, BAG_COLS[1], 2)
	bk.box(Vector3(-0.06, 0.45, -0.02), Vector3(0.06, 0.5, 0.02), DARK)
	_part(n, "Koffer_Waage", bk, Vector3(0, 0.37, 0.3)).visible = false
	_queue(k, -2.8, 2.8, 1.85, 3, 0.95)


## Gepäcklift: Senkrechtförderer durch zwei Ebenen, Stahlgerüst mit Gitter, Schalen innen,
## unten und oben ein Bandanschluss (Ein- und Auslauf).
static func _bag_lift(k: Kit) -> void:
	var top := 5.0 + 0.9
	k.box(Vector3(-1.0, 0.0, -1.0), Vector3(1.0, 0.08, 1.0), Color(0.3, 0.31, 0.33))
	for c: Vector2 in [Vector2(-0.92, -0.92), Vector2(0.92, -0.92), Vector2(0.92, 0.92), Vector2(-0.92, 0.92)]:
		k.box(Vector3(c.x - 0.06, 0.0, c.y - 0.06), Vector3(c.x + 0.06, top, c.y + 0.06), YELLOW)
	var y := 0.6
	while y < top - 0.3:
		k.box(Vector3(-0.95, y, -0.95), Vector3(0.95, y + 0.05, -0.9), STEEL)
		k.box(Vector3(-0.95, y, 0.9), Vector3(0.95, y + 0.05, 0.95), STEEL)
		k.box(Vector3(-0.95, y, -0.95), Vector3(-0.9, y + 0.05, 0.95), STEEL)
		k.box(Vector3(0.9, y, -0.95), Vector3(0.95, y + 0.05, 0.95), STEEL)
		y += 0.7
	# Gitter an drei Seiten, Schalen innen
	for sx: float in [-0.93, 0.93]:
		k.box(Vector3(sx - 0.01, 0.1, -0.88), Vector3(sx + 0.01, top - 0.1, 0.88), Color(0.5, 0.53, 0.56, 0.6))
	k.box(Vector3(-0.88, 0.1, -0.94), Vector3(0.88, top - 0.1, -0.92), Color(0.5, 0.53, 0.56, 0.6))
	var ty := 0.5
	while ty < top - 0.4:
		k.box(Vector3(-0.6, ty, -0.6), Vector3(0.6, ty + 0.06, 0.6), Color(0.62, 0.64, 0.67))
		ty += 1.1
	k.box(Vector3(-0.95, top, -0.95), Vector3(0.95, top + 0.5, 0.95), Color(0.28, 0.3, 0.33))
	k.box(Vector3(0.3, top + 0.5, -0.4), Vector3(0.8, top + 0.85, 0.4), Color(0.2, 0.35, 0.6))
	# Bandanschlüsse vorn (unten) und oben
	for yy: float in [0.62, 5.62]:
		k.box(Vector3(-0.45, yy - 0.12, 0.95), Vector3(0.45, yy, 1.0), STEEL)
		k.box(Vector3(-0.42, yy, 0.6), Vector3(0.42, yy + 0.02, 1.0), DARK)
	k.box(Vector3(-0.9, 0.08, 1.0), Vector3(0.9, 0.09, 1.3), YELLOW)


# ---------------------------------------------------------------- Gepäcksortierung

static func _sorter(n: Node3D, k: Kit, chutes: int = 4) -> void:
	k.box(Vector3(-4, 0, -3), Vector3(4, 0.1, 3), Color(0.5, 0.5, 0.48))
	for i in range(8):
		k.box(Vector3(-4, 0.1, -3.0 + float(i) * 0.8), Vector3(4, 0.105, -2.92 + float(i) * 0.8), YELLOW)
	# Ringförderer auf Stützen mit Kippschalen, darauf laufen Koffer
	var loop := PackedVector3Array()
	for i in range(28):
		var a := float(i) / 28.0 * TAU
		loop.append(Vector3(cos(a) * 3.2, 1.22, sin(a) * 2.2))
	for i in range(28):
		var a: Vector3 = loop[i]
		var b: Vector3 = loop[(i + 1) % 28]
		var d := b - a
		var bas := Basis.looking_at(d.normalized(), Vector3.UP)
		var mid := (a + b) * 0.5
		k.box(Vector3(-0.45, -0.2, -d.length() * 0.52), Vector3(0.45, -0.02, d.length() * 0.52), Color(0.3, 0.31, 0.33), Transform3D(bas, mid))
		k.box(Vector3(-0.5, -0.02, -d.length() * 0.52), Vector3(-0.44, 0.15, d.length() * 0.52), CHROME, Transform3D(bas, mid))
		k.box(Vector3(0.44, -0.02, -d.length() * 0.52), Vector3(0.5, 0.15, d.length() * 0.52), CHROME, Transform3D(bas, mid))
		k.box(Vector3(-0.4, -0.02, -0.18), Vector3(0.4, 0.0, 0.18), Color(0.55, 0.57, 0.6), Transform3D(bas, mid))
		if i % 4 == 0:
			k.box(mid + Vector3(-0.06, -1.2, -0.06), mid + Vector3(0.06, -0.2, 0.06), STEEL)
	var bags := MultiMeshInstance3D.new()
	bags.name = "Ringkoffer"
	bags.set_script(BeltAnim)
	n.add_child(bags)
	var path := PackedVector3Array()
	for p: Vector3 in loop:
		path.append(p + Vector3(0, 0.0, 0))
	bags.call("setup", path, Models.bag_mesh(), 0.9, 1.3, true)
	bags.visible = false   # erst, wenn Koffer über die Bänder ankommen (terminal.gd)
	# Make-up-Rutschen: vom Ring schräg nach außen zu den Verladestellen, je mit Fluganzeige
	for i in range(chutes):
		var ang := (float(i) + 0.5) / float(chutes) * TAU
		var ring := Vector3(cos(ang) * 3.2, 1.05, sin(ang) * 2.2)
		var outp := Vector3(cos(ang) * 3.75, 0.72, sin(ang) * 2.75)
		outp.x = clampf(outp.x, -3.65, 3.65)
		outp.z = clampf(outp.z, -2.7, 2.7)
		var dd := outp - ring
		var bas := Basis.looking_at(dd.normalized(), Vector3.UP)
		var hl := dd.length() * 0.5 + 0.1
		k.box(Vector3(-0.32, -0.04, -hl), Vector3(0.32, 0.0, hl), CHROME, Transform3D(bas, (ring + outp) * 0.5))
		for sx: float in [-0.34, 0.34]:
			k.box(Vector3(sx - 0.02, -0.04, -hl), Vector3(sx + 0.02, 0.16, hl), STEEL, Transform3D(bas, (ring + outp) * 0.5))
		k.box(outp + Vector3(-0.35, -0.72, -0.35), outp + Vector3(0.35, 0.0, 0.35), Color(0.62, 0.63, 0.65))
		k.box(outp + Vector3(-0.3, 0.0, -0.3), outp + Vector3(0.3, 0.05, 0.3), DARK)
		var sc := outp + Vector3(cos(ang) * 0.3, 0, sin(ang) * 0.3)
		k.box(sc + Vector3(-0.03, -0.72, -0.03), sc + Vector3(0.03, 0.9, 0.03), STEEL)
		k.box(sc + Vector3(-0.2, 0.75, -0.2), sc + Vector3(0.2, 1.0, 0.2), Color(0.12, 0.3, 0.18, 0.3))
	# Leitstand mit Bildschirmen und Mitarbeiter
	k.box(Vector3(-1.4, 0.1, -0.9), Vector3(1.4, 2.5, 0.9), Color(0.7, 0.72, 0.72))
	k.box(Vector3(-1.45, 2.5, -0.95), Vector3(1.45, 2.6, 0.95), STEEL)
	k.box(Vector3(-1.2, 1.2, 0.9), Vector3(1.2, 2.2, 0.92), Color(0.55, 0.72, 0.82, 0.6))
	for x: float in [-0.7, 0.0, 0.7]:
		k.box(Vector3(x - 0.3, 0.95, 0.75), Vector3(x + 0.3, 1.3, 0.8), DARK)
		k.box(Vector3(x - 0.27, 0.98, 0.8), Vector3(x + 0.27, 1.27, 0.81), Color(0.3, 0.8, 0.5, 0.3))
	var bl := Kit.new()
	bl.cyl(Vector3(0, 0, 0), Vector3(0, 0.25, 0), 0.12, 0.1, Color(1.0, 0.55, 0.1, 0.3), 10)
	var b := _part(n, "BlinkWarn", bl, Vector3(1.2, 2.6, 0.7))
	b.set_meta("period", 0.9)
	_staff(n, Color(0.95, 0.75, 0.15), Vector3(-2.6, 0.1, 0.0), 3, Vector3(1, 0, 0))


# ---------------------------------------------------------------- Sicherheitskontrolle

## Rollwagen mit Kartons (Warenlieferung vom Lager in die Läden).
static func goods_cart_mesh() -> ArrayMesh:
	var k := Kit.new()
	k.box(Vector3(-0.35, 0.18, -0.5), Vector3(0.35, 0.22, 0.5), Color(0.35, 0.38, 0.42))
	for p: Vector2 in [Vector2(-0.3, -0.45), Vector2(0.3, -0.45), Vector2(-0.3, 0.45), Vector2(0.3, 0.45)]:
		k.cyl(Vector3(p.x - 0.03, 0.08, p.y), Vector3(p.x + 0.03, 0.08, p.y), 0.08, 0.08, DARK, 8)
	k.box(Vector3(-0.35, 0.22, 0.45), Vector3(0.35, 1.0, 0.5), Color(0.35, 0.38, 0.42))
	k.box(Vector3(-0.3, 0.22, -0.45), Vector3(0.28, 0.55, 0.0), Color(0.68, 0.52, 0.32))
	k.box(Vector3(-0.28, 0.22, 0.02), Vector3(0.3, 0.7, 0.42), Color(0.6, 0.45, 0.27))
	k.box(Vector3(-0.2, 0.55, -0.4), Vector3(0.2, 0.8, -0.05), Color(0.72, 0.56, 0.35))
	return k.commit()


static func _security(n: Node3D, k: Kit, technik: String = "klassisch") -> void:
	k.box(Vector3(-3, 0, -4), Vector3(3, 0.04, 4), Color(0.26, 0.28, 0.32))
	k.box(Vector3(-0.06, 0, -3.6), Vector3(0.06, 1.05, 3.6), CHROME)
	_pane(n, "Trenner", Vector3(-0.03, 0.2, -3.5), Vector3(0.03, 1.0, 3.5))
	for x: float in [-1.6, 1.6]:
		var bx := x + 0.6
		# Rollenbahn: vorn Wannen auflegen, Röntgentunnel, hinten Wannen abnehmen
		k.box(Vector3(bx - 0.5, 0, -2.6), Vector3(bx + 0.5, 0.72, 3.2), Color(0.55, 0.57, 0.6))
		k.box(Vector3(bx - 0.48, 0.72, -2.6), Vector3(bx + 0.48, 0.76, 3.2), DARK)
		var rz := -2.55
		while rz < 3.15:
			k.cyl(Vector3(bx - 0.46, 0.79, rz), Vector3(bx + 0.46, 0.79, rz), 0.035, 0.035, CHROME, 6)
			rz += 0.18
		for sx: float in [-0.5, 0.5]:
			k.box(Vector3(bx + sx - 0.03, 0.76, -2.6), Vector3(bx + sx + 0.03, 0.9, 3.2), CHROME)
		# Röntgengerät: Gehäuse mit Bleivorhang und Monitor (CT: großes Gantry-Gehäuse)
		if technik == "klassisch":
			k.rounded_box(Vector3(bx - 0.75, 0.05, -0.6), Vector3(bx + 0.75, 1.75, 1.0), 0.06, Color(0.78, 0.8, 0.8), 2)
		else:
			k.rounded_box(Vector3(bx - 0.65, 0.05, -1.0), Vector3(bx + 0.9, 1.95, 1.4), 0.12, Color(0.9, 0.91, 0.92), 3)
			k.box(Vector3(bx - 0.66, 1.4, -0.4), Vector3(bx + 0.91, 1.55, 0.8), Color(0.15, 0.45, 0.8))
			PixelFont.draw(k, "CT", Vector3(bx, 1.7, 1.41), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.05, Color(0.15, 0.35, 0.6))
		if technik == "express":
			# automatische Wannenrückführung unter dem Band und Abschiebeplatz mit drei Stationen
			k.box(Vector3(bx - 0.48, 0.15, -2.6), Vector3(bx + 0.48, 0.35, 3.2), Color(0.42, 0.45, 0.48))
			for i in range(3):
				var zz := -2.5 + float(i) * 0.45
				k.box(Vector3(bx + 0.55, 0.0, zz), Vector3(bx + 1.3, 0.8, zz + 0.38), Color(0.6, 0.62, 0.65))
				k.box(Vector3(bx + 1.25, 0.8, zz + 0.1), Vector3(bx + 1.3, 1.0, zz + 0.28), Color(0.2, 0.8, 0.4, 0.3))
		k.box(Vector3(bx - 0.45, 0.82, -0.62), Vector3(bx + 0.45, 1.3, -0.58), Color(0.15, 0.15, 0.16))
		k.box(Vector3(bx - 0.45, 0.82, 0.98), Vector3(bx + 0.45, 1.3, 1.02), Color(0.15, 0.15, 0.16))
		for i in range(6):
			k.box(Vector3(bx - 0.45 + float(i) * 0.15, 0.82, 1.02), Vector3(bx - 0.33 + float(i) * 0.15, 1.3, 1.03), Color(0.3, 0.3, 0.32))
		k.box(Vector3(bx - 0.6, 1.75, 0.0), Vector3(bx + 0.6, 1.8, 0.4), Color(0.2, 0.45, 0.75))
		k.box(Vector3(bx + 0.8, 0.85, -0.2), Vector3(bx + 1.3, 1.25, 0.3), DARK)
		k.box(Vector3(bx + 0.82, 0.9, -0.21), Vector3(bx + 1.28, 1.2, -0.2), Color(0.85, 0.55, 0.2, 0.3))
		# Wannen laufen durch das Gerät (vorn nach hinten)
		var trays := MultiMeshInstance3D.new()
		trays.name = "Wannen%d" % int(x)
		trays.set_script(BeltAnim)
		n.add_child(trays)
		var tk := Kit.new()
		tk.box(Vector3(-0.38, 0.0, -0.27), Vector3(0.38, 0.03, 0.27), Color(0.55, 0.57, 0.6))
		for sx: float in [-0.38, 0.34]:
			tk.box(Vector3(sx, 0.03, -0.27), Vector3(sx + 0.04, 0.12, 0.27), Color(0.55, 0.57, 0.6))
		for sz: float in [-0.27, 0.23]:
			tk.box(Vector3(-0.38, 0.03, sz), Vector3(0.38, 0.12, sz + 0.04), Color(0.55, 0.57, 0.6))
		tk.rounded_box(Vector3(-0.2, 0.03, -0.12), Vector3(0.2, 0.15, 0.14), 0.03, Color(0.3, 0.3, 0.32), 1)
		trays.call("setup", PackedVector3Array([Vector3(bx, 0.82, 3.0), Vector3(bx, 0.82, -2.4)]), tk.commit(), 0.35, 1.2)
		# Wannenstapel vorn, Ablagetisch hinten
		for i in range(4):
			k.box(Vector3(bx - 0.38, 0.76 + float(i) * 0.05, 2.6), Vector3(bx + 0.38, 0.8 + float(i) * 0.05, 3.15), Color(0.55, 0.57, 0.6))
		k.box(Vector3(bx + 0.55, 0, -2.4), Vector3(bx + 1.3, 0.85, -1.2), Color(0.62, 0.63, 0.65))
		if x < 0.0:
			# Torsonde
			var gx := x - 0.6
			for sx: float in [-0.45, 0.45]:
				k.rounded_box(Vector3(gx + sx - 0.08, 0, -0.3), Vector3(gx + sx + 0.08, 2.2, 0.3), 0.04, Color(0.85, 0.86, 0.88), 2)
			k.rounded_box(Vector3(gx - 0.53, 2.05, -0.3), Vector3(gx + 0.53, 2.3, 0.3), 0.04, Color(0.85, 0.86, 0.88), 2)
			var lk := Kit.new()
			lk.box(Vector3(-0.1, 0, -0.04), Vector3(0.1, 0.06, 0.04), Color(0.2, 1.0, 0.4, 0.3))
			var l := _part(n, "BlinkSonde", lk, Vector3(gx, 2.3, 0.3))
			l.set_meta("period", 2.6)
		else:
			# Körperscanner: Glaskabine, Drehsäulen
			var gx := x - 0.6
			k.cyl(Vector3(gx, 0, 0), Vector3(gx, 0.08, 0), 0.8, 0.8, Color(0.6, 0.62, 0.65), 20)
			k.cyl(Vector3(gx, 2.2, 0), Vector3(gx, 2.4, 0), 0.8, 0.8, Color(0.88, 0.89, 0.9), 20)
			for side: float in [-1.0, 1.0]:
				k.rounded_box(Vector3(gx + side * 0.66 - 0.1, 0.08, -0.5), Vector3(gx + side * 0.66 + 0.1, 2.2, 0.5), 0.05, Color(0.88, 0.89, 0.9), 2)
			var sk := Kit.new()
			sk.box(Vector3(0.5, 0.0, -0.06), Vector3(0.6, 2.0, 0.06), Color(0.35, 0.55, 0.8, 0.3))
			sk.box(Vector3(-0.6, 0.0, -0.06), Vector3(-0.5, 2.0, 0.06), Color(0.35, 0.55, 0.8, 0.3))
			var arm := _part(n, "DrehScanner", sk, Vector3(gx, 0.1, 0))
			arm.set_meta("speed", 1.2)
		_staff(n, Color(0.82, 0.84, 0.88), Vector3(x - 0.6, 0, -1.4), 1 if x < 0.0 else 3, Vector3(0, 0, 1))
		_staff(n, Color(0.82, 0.84, 0.88), Vector3(bx + 1.0, 0, 0.6), 2, Vector3(-1, 0, 0))
	k.box(Vector3(-2.9, 2.35, 3.7), Vector3(2.9, 2.75, 3.8), Color(0.15, 0.2, 0.3))
	PixelFont.draw(k, "SICHERHEITSKONTROLLE", Vector3(0, 2.55, 3.81), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.035, Color(1, 1, 1, 0.3))
	for x: float in [-2.85, 2.85]:
		k.box(Vector3(x - 0.04, 0, 3.72), Vector3(x + 0.04, 2.35, 3.78), STEEL)


# ---------------------------------------------------------------- Gate und Bus-Gate

static func _gate(n: Node3D, k: Kit, bereich: String, bus: bool) -> void:
	var non := bereich == "non_schengen"
	var carpet := Color(0.36, 0.3, 0.26) if non else Color(0.28, 0.32, 0.42)
	if bus:
		carpet = Color(0.22, 0.36, 0.36)
	var accent := Color(0.92, 0.55, 0.15) if non else Color(0.25, 0.5, 0.85)
	k.box(Vector3(-5, 0, -4), Vector3(5, 0.035, 4), carpet)
	for i in range(10):
		k.box(Vector3(-5, 0.035, -3.6 + float(i) * 0.8), Vector3(5, 0.04, -3.56 + float(i) * 0.8), carpet.darkened(0.12))
	k.box(Vector3(-5, 0.035, -4), Vector3(5, 0.045, -3.9), accent)
	# Gate-Schalter mit zwei Bildschirmen, Bordkartenleser, Mitarbeiterin
	k.rounded_box(Vector3(-1.5, 0, -3.3), Vector3(1.5, 1.04, -2.5), 0.04, WHITE, 2)
	k.box(Vector3(-1.45, 0.1, -2.5), Vector3(1.45, 0.95, -2.48), accent)
	k.box(Vector3(-1.55, 1.04, -3.35), Vector3(1.55, 1.1, -2.45), Color(0.22, 0.22, 0.24))
	for mx: float in [-0.8, 0.8]:
		k.box(Vector3(mx - 0.32, 1.1, -3.0), Vector3(mx + 0.32, 1.48, -2.96), DARK)
		k.box(Vector3(mx - 0.29, 1.13, -2.96), Vector3(mx + 0.29, 1.45, -2.95), Color(0.4, 0.62, 0.85, 0.3))
	k.box(Vector3(-0.15, 1.1, -2.65), Vector3(0.15, 1.2, -2.5), DARK)
	k.box(Vector3(-0.1, 1.2, -2.6), Vector3(0.1, 1.21, -2.52), Color(0.3, 1.0, 0.5, 0.3))
	_staff(n, BRAND, Vector3(0, 0, -3.7), 2 if not bus else 1, Vector3(0, 0, 1))
	if bus:
		# Glastür zum Vorfeld mit Treppe hinab, darüber "BUS"
		k.box(Vector3(1.6, 0, -4.0), Vector3(1.8, 2.95, -3.8), STEEL)
		k.box(Vector3(4.6, 0, -4.0), Vector3(4.8, 2.95, -3.8), STEEL)
		k.box(Vector3(1.6, 2.7, -4.0), Vector3(4.8, 2.95, -3.8), STEEL)
		for side: float in [-1.0, 1.0]:
			var leaf := _pane(n, "Schieb%d" % int(side + 1.0), Vector3(3.2 + side * 0.02, 0.05, -3.94), Vector3(3.2 + side * 1.4, 2.7, -3.86))
			leaf.set_meta("dx", side * 1.25)
			leaf.set_meta("phase", 0.7)
		for i in range(4):
			k.box(Vector3(1.9, 0.0, -3.7 + float(i) * 0.3), Vector3(4.5, 0.04 + float(3 - i) * 0.04, -3.4 + float(i) * 0.3), Color(0.55, 0.55, 0.53))
		k.box(Vector3(1.8, 2.95, -3.98), Vector3(4.6, 3.4, -3.84), Color(0.08, 0.08, 0.1))
		PixelFont.draw(k, "BUS", Vector3(3.2, 3.17, -3.83), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.07, Color(1.0, 0.7, 0.2, 0.3))
		for gx: float in [1.9, 2.8]:
			k.rounded_box(Vector3(gx - 0.12, 0, -2.9), Vector3(gx + 0.12, 1.0, -2.2), 0.03, CHROME, 2)
	else:
		# Fluggastbrücken-Tür mit Boarding-Schleusen (Glasklappen gehen auf und zu)
		k.box(Vector3(2.4, 0, -4.0), Vector3(4.6, 2.75, -3.75), STEEL)
		k.box(Vector3(2.6, 0, -3.92), Vector3(4.4, 2.5, -3.74), Color(0.18, 0.2, 0.24))
		k.box(Vector3(2.6, 0.95, -3.74), Vector3(4.4, 1.0, -3.72), accent)
		for gx: float in [2.7, 3.5, 4.3]:
			k.rounded_box(Vector3(gx - 0.12, 0, -3.3), Vector3(gx + 0.12, 1.05, -2.6), 0.03, CHROME, 2)
			k.box(Vector3(gx - 0.08, 1.05, -3.2), Vector3(gx + 0.08, 1.07, -3.0), Color(0.3, 1.0, 0.5, 0.3))
			if gx < 4.0:
				var flap := _pane(n, "Schieb%d" % int(gx * 10.0), Vector3(gx + 0.12, 0.3, -2.98), Vector3(gx + 0.42, 0.95, -2.92))
				flap.set_meta("dz", -0.3)
				flap.set_meta("phase", gx)
	# Anzeige über der Tür (beim Bus-Gate steht dort "BUS")
	if not bus:
		_screen(n, "Gateanzeige", Vector2(1.7, 0.42), Vector3(3.5, 3.0, -3.8), Vector3(0, 0, 1), 2)
		k.box(Vector3(2.6, 2.76, -3.95), Vector3(4.4, 3.24, -3.82), DARK)
	# Gate-Schild an der Säule
	k.cyl(Vector3(-4.6, 0, -3.5), Vector3(-4.6, 3.2, -3.5), 0.06, 0.06, STEEL, 8)
	k.box(Vector3(-4.95, 2.45, -3.6), Vector3(-3.25, 3.15, -3.46), accent)
	PixelFont.draw(k, "GATE", Vector3(-4.1, 2.8, -3.45), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.06, Color(1, 1, 1, 0.3))
	# Sitzreihen: Sitzplätze bei x = -3.25 + k * 0.93, Reihen z = -1.0 (Lehne hinten), 0.6 und 2.4 (Lehne vorn)
	var seat_col := SEAT if not bus else Color(0.2, 0.45, 0.42)
	for row: float in [-1.0, 0.6, 2.4]:
		var back := -1.0 if row < 0.0 else 1.0
		_seat_row(k, Vector3(0.0, 0, row), 8, back, seat_col)
	# Steckdosensäule und Pflanze am Rand
	k.cyl(Vector3(4.6, 0, 1.6), Vector3(4.6, 1.0, 1.6), 0.15, 0.15, WHITE, 12)
	k.box(Vector3(4.45, 0.7, 1.45), Vector3(4.75, 0.85, 1.75), Color(0.2, 1.0, 0.4, 0.3))
	k.cyl(Vector3(-4.6, 0, 3.4), Vector3(-4.6, 0.55, 3.4), 0.3, 0.26, WHITE, 12)
	k.sphere(Vector3(-4.6, 0.95, 3.4), 0.45, LEAF, 8, 5)
	k.sphere(Vector3(-4.5, 1.35, 3.35), 0.3, LEAF2, 8, 5)


# ---------------------------------------------------------------- Gepäckband

## Bahn wie in terminal.gd: Geraden von x -3.6 bis 3.6 bei z ±1.17, Bögen mit r 1.17.
static func _track_point(d: float) -> Array:
	var straight := 7.2
	var r := 1.17
	var perim := 2.0 * straight + TAU * r
	d = fposmod(d, perim)
	if d < straight:
		return [Vector3(-3.6 + d, 0, r), Vector3(1, 0, 0)]
	if d < straight + PI * r:
		var a := (d - straight) / r
		return [Vector3(3.6 + sin(a) * r, 0, cos(a) * r), Vector3(cos(a), 0, -sin(a))]
	if d < 2.0 * straight + PI * r:
		return [Vector3(3.6 - (d - straight - PI * r), 0, -r), Vector3(-1, 0, 0)]
	var a := (d - 2.0 * straight - PI * r) / r
	return [Vector3(-3.6 - sin(a) * r, 0, -cos(a) * r), Vector3(-cos(a), 0, sin(a))]


static func _claim(n: Node3D, k: Kit, stil: String) -> void:
	var carousel := stil == "karussell"
	var perim := 2.0 * 7.2 + TAU * 1.17
	var segs := 64
	var plate := Color(0.32, 0.33, 0.35)
	for i in range(segs):
		var d := float(i) / float(segs) * perim
		var pa: Array = _track_point(d)
		var pb: Array = _track_point(d + perim / float(segs))
		var p0: Vector3 = pa[0]
		var p1: Vector3 = pb[0]
		var o0: Vector3 = (pa[1] as Vector3).cross(Vector3.UP)
		var o1: Vector3 = (pb[1] as Vector3).cross(Vector3.UP)
		# o zeigt nach außen (Bahn läuft gegen den Uhrzeigersinn von oben gesehen)
		var lift := 0.28 if carousel else 0.0
		var in0 := p0 - o0 * 0.48 + Vector3(0, 0.6 + lift, 0)
		var in1 := p1 - o1 * 0.48 + Vector3(0, 0.6 + lift, 0)
		var out0 := p0 + o0 * 0.48 + Vector3(0, 0.6, 0)
		var out1 := p1 + o1 * 0.48 + Vector3(0, 0.6, 0)
		var c := plate if i % 2 == 0 else plate.lightened(0.08)
		k.quad(in0, in1, out1, out0, c, (p0 + p1) * 0.5 + Vector3(0, -1, 0))
		# Außenschürze aus Edelstahl und Gummilippe
		var s0 := p0 + o0 * 0.52
		var s1 := p1 + o1 * 0.52
		k.quad(s0, s1, s1 + Vector3(0, 0.62, 0), s0 + Vector3(0, 0.62, 0), CHROME, (p0 + p1) * 0.5 - (o0 + o1) * 0.5)
		k.quad(s0 + Vector3(0, 0.62, 0), s1 + Vector3(0, 0.62, 0), out1 + Vector3(0, 0.03, 0), out0 + Vector3(0, 0.03, 0), DARK, (p0 + p1) * 0.5)
		# Fußleiste
		k.quad(s0 + o0 * 0.08, s1 + o1 * 0.08, s1 + o1 * 0.08 + Vector3(0, 0.1, 0), s0 + o0 * 0.08 + Vector3(0, 0.1, 0), Color(0.2, 0.2, 0.22), (p0 + p1) * 0.5 - (o0 + o1))
	# Mittelinsel (beim Karussell höher, mit Zuführrutsche von oben)
	var top := 1.0 if carousel else 0.8
	k.rounded_box(Vector3(-3.6, 0.0, -0.66), Vector3(3.6, top, 0.66), 0.08, Color(0.62, 0.64, 0.66), 2)
	k.box(Vector3(-3.5, top, -0.6), Vector3(3.5, top + 0.03, 0.6), Color(0.72, 0.74, 0.76))
	if carousel:
		var a := Vector3(2.4, 2.6, -0.2)
		var b := Vector3(1.2, top + 0.1, 0.4)
		var d := b - a
		k.box(Vector3(-0.45, -0.05, -d.length() * 0.5), Vector3(0.45, 0.02, d.length() * 0.5), CHROME, Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), (a + b) * 0.5))
		k.box(Vector3(1.8, 2.6, -1.0), Vector3(3.2, 3.2, 0.4), Color(0.55, 0.56, 0.58))
		k.box(Vector3(2.0, 2.65, 0.4), Vector3(3.0, 3.1, 0.42), Color(0.15, 0.15, 0.16))
	# Einlauf an der linken Schmalseite: hier endet das Kofferband aus der Sortierung (lokal -5,5 / 0),
	# ein Steilförderer hebt die Koffer, eine Rutsche mit Gummivorhang bringt sie über die Bahn auf die Insel
	var steel_dark := Color(0.5, 0.52, 0.55)
	k.box(Vector3(-5.75, 0.0, -0.58), Vector3(-5.2, 1.62, 0.58), steel_dark)
	k.box(Vector3(-5.78, 1.62, -0.62), Vector3(-5.17, 1.7, 0.62), CHROME)
	k.box(Vector3(-5.79, 0.5, -0.45), Vector3(-5.74, 0.85, 0.45), DARK)
	var ca := Vector3(-5.2, 1.42, 0)
	var cb := Vector3(-3.3, top + 0.04, 0)
	var cd := cb - ca
	var cx := Transform3D(Basis.looking_at(cd.normalized(), Vector3.UP), (ca + cb) * 0.5)
	var cl := cd.length() * 0.5
	k.box(Vector3(-0.48, -0.06, -cl), Vector3(0.48, 0.0, cl), CHROME, cx)
	for sx: float in [-0.5, 0.5]:
		k.box(Vector3(sx - 0.025, -0.06, -cl), Vector3(sx + 0.025, 0.22, cl), steel_dark, cx)
	for i in range(6):
		var z := -0.42 + float(i) * 0.17
		k.box(Vector3(-5.2, 1.0, z), Vector3(-5.17, 1.6, z + 0.14), Color(0.1, 0.1, 0.11))
	# Koffer: eigene Knoten, terminal.gd lässt sie umlaufen (Mittelpunkt 0,76 m hoch)
	var cases := Node3D.new()
	cases.name = "Koffer"
	cases.set_meta("no_bake", true)
	n.add_child(cases)
	for i in range(9):
		var mi := MeshInstance3D.new()
		mi.name = "K%d" % i
		mi.mesh = _bag_mesh(BAG_COLS[(i * 3 + 1) % BAG_COLS.size()])
		var start: Array = _track_point(float(i) * perim / 9.0)
		mi.position = (start[0] as Vector3) + Vector3(0, 0.76, 0)
		cases.add_child(mi)
	# Anzeigesäule mit Flugnummer und Rundumleuchte
	k.box(Vector3(4.65, 0, -0.12), Vector3(4.85, 2.2, 0.12), STEEL)
	k.box(Vector3(4.5, 1.65, -0.75), Vector3(4.95, 2.35, 0.75), DARK)
	_screen(n, "Bandanzeige", Vector2(1.36, 0.6), Vector3(4.96, 2.0, 0), Vector3(1, 0, 0), 2)
	var bl := Kit.new()
	bl.cyl(Vector3(0, 0, 0), Vector3(0, 0.2, 0), 0.1, 0.08, Color(1.0, 0.55, 0.1, 0.3), 10)
	var light := _part(n, "BlinkBand", bl, Vector3(4.75, 2.35, 0))
	light.set_meta("period", 1.1)
	PixelFont.draw_ground(k, "BAND", Vector3(0, 0.02, 2.2), Vector3(0, 0, -1), 0.09, Color(0.95, 0.8, 0.3))


# ---------------------------------------------------------------- Toiletten

static func _toilets(k: Kit) -> void:
	var tile := Color(0.82, 0.86, 0.88)
	var grout := Color(0.72, 0.76, 0.78)
	k.box(Vector3(-3, 0, -2.5), Vector3(3, 0.04, 2.5), Color(0.86, 0.88, 0.89))
	for i in range(12):
		k.box(Vector3(-3 + float(i) * 0.5, 0.04, -2.5), Vector3(-2.98 + float(i) * 0.5, 0.045, 2.5), grout)
	# Außenwände mit Fugen, Eingänge vorn links und rechts
	k.box(Vector3(-3, 0, -2.5), Vector3(3, 2.6, -2.35), tile)
	k.box(Vector3(-3, 0, -2.5), Vector3(-2.85, 2.6, 2.5), tile)
	k.box(Vector3(2.85, 0, -2.5), Vector3(3, 2.6, 2.5), tile)
	for seg: Vector2 in [Vector2(-3, -2.0), Vector2(-0.6, 0.6), Vector2(2.0, 3)]:
		k.box(Vector3(seg.x, 0, 2.35), Vector3(seg.y, 2.6, 2.5), tile)
	for y in range(1, 8):
		k.box(Vector3(-2.85, float(y) * 0.32, -2.36), Vector3(2.85, float(y) * 0.32 + 0.015, -2.34), grout)
	k.box(Vector3(-0.08, 0, -2.5), Vector3(0.08, 2.6, 2.35), tile)
	for side: float in [-1.0, 1.0]:
		var door := Color(0.85, 0.4, 0.45) if side < 0.0 else Color(0.3, 0.5, 0.75)
		for i in range(3):
			var x := side * (0.6 + float(i) * 0.75)
			# Kabinentrennwand, Tür, WC mit Spülkasten
			k.box(Vector3(x - 0.025, 0.12, -2.35), Vector3(x + 0.025, 2.0, -1.0), Color(0.6, 0.66, 0.72))
			k.box(Vector3(x + side * 0.05, 0.12, -1.02), Vector3(x + side * 0.7, 2.0, -0.98), door)
			k.box(Vector3(x + side * 0.6, 1.0, -0.97), Vector3(x + side * 0.65, 1.05, -0.95), CHROME)
			var cx := x + side * 0.375
			k.rounded_box(Vector3(cx - 0.18, 0, -2.3), Vector3(cx + 0.18, 0.42, -1.9), 0.08, WHITE, 2)
			k.rounded_box(Vector3(cx - 0.17, 0.42, -2.34), Vector3(cx + 0.17, 0.8, -2.2), 0.04, WHITE, 2)
		# Waschtisch mit Becken, Hähnen, Spiegel und Licht
		var wx := side * 2.55
		k.box(Vector3(wx - 0.3, 0.82, -0.6), Vector3(wx + 0.3, 0.9, 1.6), Color(0.3, 0.3, 0.32))
		for z: float in [-0.2, 0.5, 1.2]:
			k.cyl(Vector3(wx, 0.84, z), Vector3(wx, 0.92, z), 0.18, 0.2, WHITE, 12)
			k.box(Vector3(wx + side * 0.2, 0.9, z - 0.02), Vector3(wx + side * 0.25, 1.05, z + 0.02), CHROME)
		k.box(Vector3(wx + side * 0.26, 1.2, -0.6), Vector3(wx + side * 0.29, 1.9, 1.6), Color(0.7, 0.82, 0.9, 0.6))
		k.box(Vector3(wx + side * 0.2, 1.95, -0.6), Vector3(wx + side * 0.27, 2.02, 1.6), LAMP)
		k.box(Vector3(wx + side * 0.24, 1.0, 1.75), Vector3(wx + side * 0.29, 1.6, 2.05), CHROME)
	# Schild mit Piktogrammen
	k.box(Vector3(-0.75, 2.62, 2.5), Vector3(0.75, 3.15, 2.56), Color(0.18, 0.38, 0.72))
	for e: Array in [[-0.35, false], [0.35, true]]:
		var px: float = e[0]
		k.sphere(Vector3(px, 3.03, 2.58), 0.045, Color(1, 1, 1, 0.3), 8, 5)
		if bool(e[1]):
			k.prism([Vector3(px - 0.1, 2.72, 2.57), Vector3(px + 0.1, 2.72, 2.57), Vector3(px + 0.05, 2.97, 2.57), Vector3(px - 0.05, 2.97, 2.57)],
				[Vector3(px - 0.1, 2.72, 2.59), Vector3(px + 0.1, 2.72, 2.59), Vector3(px + 0.05, 2.97, 2.59), Vector3(px - 0.05, 2.97, 2.59)], Color(1, 1, 1, 0.3))
		else:
			k.box(Vector3(px - 0.06, 2.7, 2.57), Vector3(px + 0.06, 2.97, 2.59), Color(1, 1, 1, 0.3))
	k.box(Vector3(-0.015, 2.68, 2.57), Vector3(0.015, 3.1, 2.59), Color(1, 1, 1, 0.3))


# ---------------------------------------------------------------- Ausgang Sicherheitsbereich

static func _exit(n: Node3D, k: Kit) -> void:
	for x: float in [-2.0, 2.0]:
		k.box(Vector3(x - 0.12, 0, -0.2), Vector3(x + 0.12, 2.6, 0.2), STEEL)
	k.box(Vector3(-2.1, 2.42, -0.25), Vector3(2.1, 2.8, 0.25), STEEL)
	k.box(Vector3(-1.88, 2.3, -0.12), Vector3(1.88, 2.42, 0.12), Color(0.3, 0.32, 0.34))
	for side: float in [-1.0, 1.0]:
		var leaf := _pane(n, "Schieb%d" % int(side + 1.0), Vector3(side * 0.02, 0.05, -0.04), Vector3(side * 1.86, 2.3, 0.04))
		leaf.set_meta("dx", side * 1.6)
		leaf.set_meta("phase", 1.3)
	# vorn (Ausgang): grünes Schild, hinten: rotes Durchgang-verboten-Schild
	k.box(Vector3(-0.7, 2.48, 0.26), Vector3(0.7, 2.74, 0.3), Color(0.12, 0.6, 0.3))
	PixelFont.draw(k, "AUSGANG", Vector3(0, 2.61, 0.31), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.025, Color(1, 1, 1, 0.3))
	k.cyl(Vector3(0, 2.61, -0.26), Vector3(0, 2.61, -0.3), 0.14, 0.14, Color(0.85, 0.12, 0.1), 16)
	k.box(Vector3(-0.09, 2.59, -0.32), Vector3(0.09, 2.63, -0.3), WHITE)
	PixelFont.draw_ground(k, "^", Vector3(0, 0.02, 0.8), Vector3(0, 0, 1), 0.1, Color(0.2, 0.8, 0.4))


# ---------------------------------------------------------------- Heizkörper

static func _radiator(k: Kit) -> void:
	for i in range(16):
		var x := -0.9 + float(i) * 0.12
		k.rounded_box(Vector3(x - 0.045, 0.15, -0.07), Vector3(x + 0.045, 0.85, 0.07), 0.03, WHITE, 1)
	k.box(Vector3(-0.95, 0.2, -0.03), Vector3(0.95, 0.24, 0.03), WHITE.darkened(0.08))
	k.box(Vector3(-0.95, 0.76, -0.03), Vector3(0.95, 0.8, 0.03), WHITE.darkened(0.08))
	for x: float in [-1.02, 1.02]:
		k.cyl(Vector3(x, 0.0, 0), Vector3(x, 0.22, 0), 0.025, 0.025, CHROME, 8)
	k.cyl(Vector3(-1.05, 0.22, 0), Vector3(-1.05, 0.32, 0), 0.045, 0.045, WHITE, 10)
	k.cyl(Vector3(-1.05, 0.32, 0), Vector3(-1.05, 0.36, 0), 0.05, 0.05, Color(0.85, 0.3, 0.2), 10)


# ---------------------------------------------------------------- Café

static func _cafe(n: Node3D, k: Kit, stil: String) -> void:
	var floor_c: Color = {"cafe": Color(0.55, 0.42, 0.29), "baeckerei": Color(0.7, 0.58, 0.42), "bar": Color(0.22, 0.2, 0.2),
		"restaurant": Color(0.48, 0.34, 0.26)}.get(stil, Color(0.55, 0.42, 0.29))
	var wood := Color(0.35, 0.24, 0.17) if stil != "baeckerei" else Color(0.62, 0.48, 0.32)
	k.box(Vector3(-4, 0, -3), Vector3(4, 0.04, 3), floor_c)
	for i in range(16):
		k.box(Vector3(-4, 0.04, -3 + float(i) * 0.38), Vector3(4, 0.045, -2.98 + float(i) * 0.38), floor_c.darkened(0.12))
	# Theke mit Glasvitrine, Kaffeemaschine, Kasse
	k.rounded_box(Vector3(-3.8, 0, -2.8), Vector3(3.8, 1.02, -1.9), 0.03, wood, 2)
	for i in range(12):
		k.box(Vector3(-3.7 + float(i) * 0.63, 0.1, -1.9), Vector3(-3.64 + float(i) * 0.63, 0.95, -1.88), wood.darkened(0.2))
	k.box(Vector3(-3.85, 1.02, -2.85), Vector3(3.85, 1.08, -1.85), Color(0.85, 0.84, 0.8))
	# Vitrine mit Kuchen oder Brot
	k.box(Vector3(-0.2, 1.08, -2.6), Vector3(2.6, 1.12, -1.95), CHROME)
	for i in range(8):
		var x := 0.0 + float(i) * 0.32
		if stil == "baeckerei":
			k.sphere(Vector3(x, 1.2, -2.25), 0.13, Color(0.72, 0.5, 0.25), 8, 5, Vector3(1.4, 0.8, 1.0))
		elif stil == "bar":
			k.cyl(Vector3(x, 1.12, -2.25), Vector3(x, 1.4, -2.25), 0.05, 0.04, Color(0.25, 0.5, 0.3, 0.6), 8)
		else:
			k.cyl(Vector3(x, 1.12, -2.25), Vector3(x, 1.22, -2.25), 0.13, 0.13, [Color(0.95, 0.85, 0.7), Color(0.55, 0.3, 0.2), Color(0.9, 0.5, 0.55)][i % 3], 10)
	_pane(n, "Vitrine", Vector3(-0.2, 1.12, -1.97), Vector3(2.6, 1.55, -1.93))
	# Siebträgermaschine mit Dampf
	k.rounded_box(Vector3(-3.0, 1.08, -2.75), Vector3(-1.9, 1.62, -2.3), 0.05, CHROME, 2)
	for x: float in [-2.75, -2.45, -2.15]:
		k.box(Vector3(x - 0.04, 1.25, -2.32), Vector3(x + 0.04, 1.3, -2.18), DARK)
		k.cyl(Vector3(x, 1.12, -2.22), Vector3(x, 1.19, -2.22), 0.04, 0.035, WHITE, 8)
	k.cyl(Vector3(-1.6, 1.08, -2.5), Vector3(-1.6, 1.5, -2.5), 0.1, 0.1, DARK, 10)
	k.cyl(Vector3(-1.6, 1.5, -2.5), Vector3(-1.6, 1.65, -2.5), 0.13, 0.06, Color(0.4, 0.25, 0.15), 10)
	var sk := Kit.new()
	for i in range(3):
		sk.sphere(Vector3(float(i) * 0.04, float(i) * 0.12, 0), 0.06 + float(i) * 0.02, Color(0.95, 0.95, 0.95, 0.6), 6, 4)
	var steam := _part(n, "HubDampf", sk, Vector3(-2.45, 1.65, -2.4))
	steam.set_meta("speed", 2.0)
	k.box(Vector3(3.0, 1.08, -2.5), Vector3(3.5, 1.32, -2.1), DARK)
	k.box(Vector3(3.05, 1.32, -2.45), Vector3(3.45, 1.55, -2.42), Color(0.4, 0.7, 0.9, 0.3))
	# Rückwand: beleuchtete Tafeln, Regale mit Tassen oder Flaschen
	k.box(Vector3(-3.8, 1.1, -3.0), Vector3(3.8, 2.7, -2.88), wood.darkened(0.25))
	for i in range(3):
		var x0 := -3.4 + float(i) * 2.5
		k.box(Vector3(x0, 1.9, -2.88), Vector3(x0 + 1.6, 2.45, -2.86), Color(0.1, 0.1, 0.1))
		for r in range(4):
			k.box(Vector3(x0 + 0.1, 2.33 - float(r) * 0.11, -2.86), Vector3(x0 + 0.1 + 0.4 + float((r + i) % 3) * 0.3, 2.36 - float(r) * 0.11, -2.855), Color(0.95, 0.95, 0.9, 0.3))
	for y: float in [1.35, 1.65]:
		k.box(Vector3(-3.6, y, -2.88), Vector3(3.6, y + 0.03, -2.7), WALNUT)
		for i in range(18):
			var x := -3.4 + float(i) * 0.4
			if stil == "bar":
				k.cyl(Vector3(x, y + 0.03, -2.78), Vector3(x, y + 0.28, -2.78), 0.045, 0.03, Color.from_hsv(float(i % 5) * 0.12, 0.6, 0.6, 0.6), 8)
			elif stil == "baeckerei":
				k.sphere(Vector3(x, y + 0.1, -2.78), 0.1, Color(0.7, 0.48, 0.24), 6, 4, Vector3(1.6, 0.8, 1.0))
			else:
				k.cyl(Vector3(x, y + 0.03, -2.78), Vector3(x, y + 0.13, -2.78), 0.05, 0.045, WHITE, 8)
	# Hängeleuchten über der Theke
	for x: float in [-2.6, -0.4, 1.8]:
		k.cyl(Vector3(x, 2.6, -2.35), Vector3(x, 3.1, -2.35), 0.01, 0.01, DARK, 4)
		k.cyl(Vector3(x, 2.45, -2.35), Vector3(x, 2.62, -2.35), 0.24, 0.06, Color(0.15, 0.3, 0.28), 12)
		k.cyl(Vector3(x, 2.43, -2.35), Vector3(x, 2.46, -2.35), 0.2, 0.2, LAMP, 12)
	_staff(n, Color(0.95, 0.95, 0.92), Vector3(-1.2, 0, -2.4), 1, Vector3(0, 0, 1))
	# Gastraum
	var tables := [Vector3(-2.6, 0, 0.6), Vector3(0.2, 0, 1.6), Vector3(2.7, 0, 0.3)]
	for t: Vector3 in tables:
		if stil == "bar":
			k.cyl(t, t + Vector3(0, 0.03, 0), 0.3, 0.3, DARK, 12)
			k.cyl(t, t + Vector3(0, 1.05, 0), 0.04, 0.04, CHROME, 8)
			k.cyl(t + Vector3(0, 1.05, 0), t + Vector3(0, 1.09, 0), 0.4, 0.4, WALNUT, 16)
			for a in range(3):
				var ang := float(a) * TAU / 3.0
				var sp := t + Vector3(cos(ang) * 0.7, 0, sin(ang) * 0.7)
				k.cyl(sp, sp + Vector3(0, 0.75, 0), 0.03, 0.03, CHROME, 6)
				k.cyl(sp + Vector3(0, 0.75, 0), sp + Vector3(0, 0.8, 0), 0.2, 0.2, Color(0.55, 0.15, 0.15), 12)
			continue
		var cloth := stil == "restaurant"
		k.cyl(t, t + Vector3(0, 0.03, 0), 0.25, 0.25, DARK, 12)
		k.cyl(t, t + Vector3(0, 0.72, 0), 0.035, 0.035, DARK, 8)
		k.cyl(t + Vector3(0, 0.72, 0), t + Vector3(0, 0.76, 0), 0.5, 0.5, WHITE if cloth else OAK, 18)
		if cloth:
			k.cyl(t + Vector3(0, 0.55, 0), t + Vector3(0, 0.76, 0), 0.53, 0.52, WHITE, 18, false)
			k.cyl(t + Vector3(0.1, 0.76, 0), t + Vector3(0.1, 0.9, 0), 0.03, 0.03, Color(0.95, 0.95, 0.9, 0.3), 6)
		k.cyl(t + Vector3(0.15, 0.76, 0.1), t + Vector3(0.15, 0.83, 0.1), 0.04, 0.035, WHITE, 8)
		for side: float in [-1.0, 1.0]:
			var cp := t + Vector3(side * 0.85, 0, 0)
			for lx: float in [-0.17, 0.17]:
				for lz: float in [-0.17, 0.17]:
					k.cyl(cp + Vector3(lx, 0, lz), cp + Vector3(lx, 0.45, lz), 0.018, 0.018, DARK, 5)
			k.rounded_box(cp + Vector3(-0.21, 0.45, -0.21), cp + Vector3(0.21, 0.5, 0.21), 0.02, Color(0.6, 0.25, 0.2), 1)
			k.rounded_box(cp + Vector3(side * 0.18 - 0.03, 0.5, -0.2), cp + Vector3(side * 0.18 + 0.03, 0.9, 0.2), 0.02, wood, 1)
	k.cyl(Vector3(3.6, 0, 2.6), Vector3(3.6, 0.5, 2.6), 0.28, 0.24, WHITE, 12)
	k.sphere(Vector3(3.6, 0.9, 2.6), 0.42, LEAF, 8, 5)


# ---------------------------------------------------------------- Laden

static func _shop(n: Node3D, k: Kit, stil: String) -> void:
	var floor_c := Color(0.86, 0.84, 0.8) if stil != "dutyfree" else Color(0.82, 0.78, 0.84)
	k.box(Vector3(-4, 0, -3), Vector3(4, 0.04, 3), floor_c)
	for i in range(9):
		k.box(Vector3(-4 + float(i), 0.04, -3), Vector3(-3.98 + float(i), 0.045, 3), floor_c.darkened(0.08))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(stil)
	# Wandregal hinten
	k.box(Vector3(-3.9, 0, -3.0), Vector3(3.9, 2.4, -2.7), WHITE)
	for y: float in [0.3, 0.75, 1.2, 1.65, 2.1]:
		k.box(Vector3(-3.85, y, -2.7), Vector3(3.85, y + 0.03, -2.4), Color(0.8, 0.8, 0.78))
		_goods(k, rng, stil, Vector3(-3.7, y + 0.03, -2.55), 7.4, true)
	# zwei Gondelregale
	for z: float in [-0.9, 0.9]:
		k.rounded_box(Vector3(-3.2, 0, z - 0.32), Vector3(1.6, 1.5, z + 0.32), 0.03, WHITE, 2)
		for y: float in [0.25, 0.65, 1.05, 1.5]:
			for side: float in [-1.0, 1.0]:
				k.box(Vector3(-3.15, y, z + side * 0.3), Vector3(1.55, y + 0.03, z + side * 0.45), Color(0.82, 0.82, 0.8))
				if y < 1.4:
					_goods(k, rng, stil, Vector3(-3.0, y + 0.03, z + side * 0.4), 4.4, false)
		k.box(Vector3(-3.25, 1.5, z - 0.05), Vector3(-2.6, 1.75, z + 0.05), Color(0.85, 0.2, 0.2))
	# Kasse mit Verkäuferin
	k.rounded_box(Vector3(2.4, 0, 0.6), Vector3(3.8, 1.0, 2.6), 0.04, DARK, 2)
	k.box(Vector3(2.35, 1.0, 0.55), Vector3(3.85, 1.05, 2.65), Color(0.85, 0.85, 0.82))
	k.box(Vector3(2.6, 1.05, 1.0), Vector3(3.0, 1.35, 1.04), DARK)
	k.box(Vector3(2.62, 1.08, 1.04), Vector3(2.98, 1.32, 1.05), Color(0.4, 0.75, 0.9, 0.3))
	k.box(Vector3(3.2, 1.05, 1.6), Vector3(3.6, 1.1, 2.4), Color(0.3, 0.3, 0.32))
	_staff(n, Color(0.2, 0.5, 0.45), Vector3(3.4, 0, 0.3), 0, Vector3(-1, 0, 0))
	# Körbe am Eingang
	for i in range(3):
		k.box(Vector3(-3.6, float(i) * 0.12, 2.2), Vector3(-3.0, 0.1 + float(i) * 0.12, 2.6), Color(0.8, 0.15, 0.15))


static func _goods(k: Kit, rng: RandomNumberGenerator, stil: String, start: Vector3, width: float, wall: bool) -> void:
	var x := 0.0
	while x < width - 0.15:
		var p := start + Vector3(x, 0, 0)
		var w := 0.18
		match stil:
			"dutyfree":
				if rng.randf() < 0.6:
					var c := Color.from_hsv(rng.randf_range(0.05, 0.15), 0.5, rng.randf_range(0.4, 0.8), 0.6)
					k.cyl(p, p + Vector3(0, 0.3, 0), 0.05, 0.05, c, 8)
					k.cyl(p + Vector3(0, 0.3, 0), p + Vector3(0, 0.38, 0), 0.02, 0.02, DARK, 6)
				else:
					k.box(p + Vector3(-0.06, 0, -0.04), p + Vector3(0.06, 0.18, 0.04), Color.from_hsv(rng.randf_range(0.7, 0.95), 0.4, 0.9))
				w = 0.16
			"buecher":
				var bw := rng.randf_range(0.04, 0.08)
				k.box(p, p + Vector3(bw, rng.randf_range(0.22, 0.32), 0.18 if wall else 0.12), Color.from_hsv(rng.randf(), 0.5, rng.randf_range(0.35, 0.8)))
				w = bw + 0.01
			"elektronik":
				k.box(p + Vector3(0, 0, -0.06), p + Vector3(0.22, 0.14, 0.06), DARK)
				k.box(p + Vector3(0.02, 0.02, 0.06), p + Vector3(0.2, 0.12, 0.065), Color(0.3, 0.55, 0.9, 0.3))
				w = 0.3
			"apotheke":
				k.box(p + Vector3(0, 0, -0.05), p + Vector3(0.12, 0.16, 0.05), WHITE if rng.randf() < 0.6 else Color(0.3, 0.65, 0.4))
				w = 0.15
			"mode":
				k.cyl(p + Vector3(0, 0.35, 0), p + Vector3(0.0, 0.38, 0), 0.01, 0.01, CHROME, 4)
				k.box(p + Vector3(-0.07, -0.05, -0.12), p + Vector3(0.07, 0.35, 0.12), Color.from_hsv(rng.randf(), 0.45, rng.randf_range(0.4, 0.9)))
				w = 0.17
			_:
				k.box(p + Vector3(0, 0, -0.02), p + Vector3(0.2, 0.28, 0.02), Color.from_hsv(rng.randf(), 0.55, 0.85))
				w = 0.23
		x += w


# ---------------------------------------------------------------- Kleinteile

static func _plant(k: Kit) -> void:
	k.cyl(Vector3(0, 0, 0), Vector3(0, 0.6, 0), 0.38, 0.45, WHITE, 16)
	k.cyl(Vector3(0, 0.6, 0), Vector3(0, 0.64, 0), 0.47, 0.47, WHITE.darkened(0.06), 16)
	k.cyl(Vector3(0, 0.58, 0), Vector3(0, 0.62, 0), 0.42, 0.42, Color(0.27, 0.2, 0.13), 16)
	for i in range(3):
		var a := float(i) * 2.1
		k.cyl(Vector3(0, 0.6, 0), Vector3(cos(a) * 0.15, 1.2, sin(a) * 0.15), 0.02, 0.015, Color(0.3, 0.42, 0.2, 0.8), 5)
	# große Blätter (Monstera)
	for i in range(11):
		var a := float(i) / 11.0 * TAU
		var dir := Vector3(cos(a), 0, sin(a))
		var base := Vector3(0, 0.75 + float(i % 4) * 0.22, 0) + dir * 0.1
		var tip := base + dir * (0.55 + float(i % 3) * 0.1) + Vector3(0, 0.25 - float(i % 3) * 0.15, 0)
		var side := dir.cross(Vector3.UP) * 0.22
		var mid := (base + tip) * 0.5 + Vector3(0, 0.08, 0)
		var c := LEAF if i % 2 == 0 else LEAF2
		k.tri(base, mid + side, tip, c, mid + Vector3(0, -1, 0))
		k.tri(base, tip, mid - side, c, mid + Vector3(0, -1, 0))
		k.tri(base, tip, mid + side, c, mid + Vector3(0, 1, 0))
		k.tri(base, mid - side, tip, c, mid + Vector3(0, 1, 0))


static func _board(n: Node3D, k: Kit) -> void:
	for x: float in [-1.25, 1.25]:
		k.cyl(Vector3(x, 0, 0), Vector3(x, 0.04, 0), 0.25, 0.25, DARK, 12)
		k.cyl(Vector3(x, 0.04, 0), Vector3(x, 1.85, 0), 0.06, 0.06, STEEL, 10)
	k.rounded_box(Vector3(-1.55, 1.8, -0.17), Vector3(1.55, 3.45, 0.17), 0.04, DARK, 2)
	k.box(Vector3(-1.5, 3.3, -0.18), Vector3(1.5, 3.42, 0.18), Color(0.95, 0.75, 0.15))
	_screen(n, "TafelVorn", Vector2(2.9, 1.42), Vector3(0, 2.58, 0.175), Vector3(0, 0, 1), 1)
	_screen(n, "TafelHinten", Vector2(2.9, 1.42), Vector3(0, 2.58, -0.175), Vector3(0, 0, -1), 1)
	PixelFont.draw(k, "ABFLUG", Vector3(0, 3.36, 0.185), Vector3(1, 0, 0), Vector3.UP, Vector3(0, 0, 1), 0.022, DARK)
	PixelFont.draw(k, "ANKUNFT", Vector3(0, 3.36, -0.185), Vector3(-1, 0, 0), Vector3.UP, Vector3(0, 0, -1), 0.022, DARK)


## Kunstwerk: Sockel mit einer schwebenden Ringskulptur, die sich langsam dreht.
static func _art(n: Node3D, k: Kit) -> void:
	k.cyl(Vector3(0, 0, 0), Vector3(0, 0.45, 0), 1.35, 1.4, Color(0.78, 0.76, 0.72), 24)
	k.cyl(Vector3(0, 0.45, 0), Vector3(0, 0.5, 0), 1.3, 1.3, Color(0.86, 0.84, 0.8), 24)
	k.cyl(Vector3(0, 0.5, 0), Vector3(0, 1.4, 0), 0.06, 0.06, CHROME, 8)
	var sk := Kit.new()
	var cols := [Color(0.85, 0.3, 0.2), Color(0.2, 0.45, 0.75), Color(0.95, 0.75, 0.2)]
	for r in range(3):
		var rad := 0.55 + float(r) * 0.32
		var tilt := Basis(Vector3(1, 0, 0), 0.5 + float(r) * 0.55).rotated(Vector3.UP, float(r) * 1.1)
		for i in range(24):
			var a0 := float(i) / 24.0 * TAU
			var a1 := float(i + 1) / 24.0 * TAU
			var p0 := tilt * Vector3(cos(a0) * rad, 0, sin(a0) * rad)
			var p1 := tilt * Vector3(cos(a1) * rad, 0, sin(a1) * rad)
			sk.cyl(p0, p1, 0.05, 0.05, cols[r], 6, false)
	sk.sphere(Vector3.ZERO, 0.22, Color(0.92, 0.92, 0.9), 12, 8)
	var s := _part(n, "DrehRinge", sk, Vector3(0, 2.3, 0))
	s.set_meta("speed", 0.25)


# ---------------------------------------------------------------- Türen

## Tür in einer Innenwand (Öffnung 2,4 m quer zu lokal X, Wand liegt in lokal X).
## Bewegliche Flügel heißen TuerL/TuerR; terminal.gd öffnet sie, wenn jemand nah ist.
## Meta "door_kind": automatik (Schiebeflügel aus Glas), fluegel (Drehflügel), personal (Stahltür).
static func _door(n: Node3D, k: Kit, art: String) -> void:
	n.set_meta("door_kind", art)
	var post := STEEL if art != "fluegel" else WALNUT
	# Zarge und Schwelle
	for sx: float in [-1.0, 1.0]:
		k.box(Vector3(sx * 1.2 - 0.06, 0, -0.14), Vector3(sx * 1.2 + 0.06, 2.42, 0.14), post)
	k.box(Vector3(-1.26, 2.3, -0.14), Vector3(1.26, 2.45, 0.14), post)
	k.box(Vector3(-1.14, 0, -0.12), Vector3(1.14, 0.015, 0.12), Color(0.55, 0.56, 0.58))
	match art:
		"automatik":
			k.box(Vector3(-1.2, 2.45, -0.16), Vector3(1.2, 2.62, 0.16), Color(0.55, 0.58, 0.6))
			for sz: float in [-1.0, 1.0]:
				k.box(Vector3(-0.12, 2.48, sz * 0.165), Vector3(0.12, 2.56, sz * 0.18), DARK)
				k.box(Vector3(0.05, 2.5, sz * 0.18), Vector3(0.09, 2.54, sz * 0.185), Color(0.2, 1.0, 0.3, 0.3))
			for e: Array in [["TuerL", -0.56], ["TuerR", 0.56]]:
				var holder := Node3D.new()
				holder.name = String(e[0])
				holder.position = Vector3(float(e[1]), 0, 0)
				holder.set_meta("base_x", float(e[1]))
				holder.set_meta("no_bake", true)
				n.add_child(holder)
				var fk := Kit.new()
				fk.box(Vector3(-0.56, 0.0, -0.025), Vector3(0.56, 0.08, 0.025), STEEL)
				fk.box(Vector3(-0.56, 2.22, -0.025), Vector3(0.56, 2.3, 0.025), STEEL)
				for fx: float in [-0.53, 0.53]:
					fk.box(Vector3(fx - 0.03, 0.08, -0.025), Vector3(fx + 0.03, 2.22, 0.025), STEEL)
				fk.box(Vector3(-0.5, 1.0, -0.03), Vector3(0.5, 1.06, 0.03), Color(0.93, 0.93, 0.9))
				holder.add_child(fk.instance("Rahmen"))
				var gk := Kit.new()
				gk.box(Vector3(-0.5, 0.08, -0.01), Vector3(0.5, 2.22, 0.01), WHITE)
				var gm := gk.instance("Glas")
				gm.material_override = glass()
				gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				holder.add_child(gm)
		"fluegel":
			for e: Array in [["TuerL", -1.15, 1.0], ["TuerR", 1.15, -1.0]]:
				var holder := Node3D.new()
				holder.name = String(e[0])
				holder.position = Vector3(float(e[1]), 0, 0)
				holder.set_meta("no_bake", true)
				holder.set_meta("swing", -1.0 if float(e[2]) > 0.0 else 1.0)
				n.add_child(holder)
				var dir: float = e[2]
				var lk := Kit.new()
				var x0 := 0.02 * dir
				var x1 := 1.13 * dir
				lk.box(Vector3(minf(x0, x1), 0.02, -0.03), Vector3(maxf(x0, x1), 2.28, 0.03), OAK)
				lk.box(Vector3(minf(x0, x1) + 0.05, 0.02, -0.035), Vector3(maxf(x0, x1) - 0.05, 0.3, 0.035), CHROME)
				var vx := 0.57 * dir
				lk.box(Vector3(vx - 0.12, 1.3, -0.035), Vector3(vx + 0.12, 1.9, 0.035), Color(0.3, 0.4, 0.45))
				var hx := 1.0 * dir
				for sz: float in [-1.0, 1.0]:
					lk.box(Vector3(hx - 0.02, 1.0, sz * 0.035), Vector3(hx + 0.02, 1.2, sz * 0.05), CHROME)
					lk.box(Vector3(hx - 0.12 * dir - 0.02, 1.08, sz * 0.05), Vector3(hx + 0.02, 1.12, sz * 0.09), CHROME)
				holder.add_child(lk.instance("Fluegel"))
			for sz: float in [-1.0, 1.0]:
				k.box(Vector3(-0.3, 2.47, sz * 0.141), Vector3(0.3, 2.62, sz * 0.15), Color(0.1, 0.65, 0.3, 0.3))
		"personal":
			# feste Seitenwand mit Kartenleser, Stahltür links
			k.box(Vector3(0.05, 0, -0.1), Vector3(1.14, 2.3, 0.1), Color(0.86, 0.85, 0.8))
			k.box(Vector3(-0.02, 0, -0.13), Vector3(0.06, 2.3, 0.13), STEEL)
			for sz: float in [-1.0, 1.0]:
				var rz := sz * 0.1
				k.box(Vector3(0.3, 1.05, rz), Vector3(0.48, 1.35, rz + sz * 0.04), DARK)
				k.box(Vector3(0.34, 1.27, rz + sz * 0.04), Vector3(0.38, 1.31, rz + sz * 0.045), Color(1.0, 0.2, 0.15, 0.3))
				k.box(Vector3(0.4, 1.27, rz + sz * 0.04), Vector3(0.44, 1.31, rz + sz * 0.045), Color(0.2, 1.0, 0.3, 0.3))
				k.box(Vector3(-1.1, 2.48, sz * 0.141), Vector3(1.1, 2.75, sz * 0.15), Color(0.85, 0.15, 0.12))
				PixelFont.draw(k, "NUR PERSONAL", Vector3(0, 2.615, sz * 0.152), Vector3(-sz, 0, 0), Vector3.UP, Vector3(0, 0, sz), 0.028, WHITE)
			k.box(Vector3(-1.2, 2.45, -0.14), Vector3(1.2, 2.76, 0.14), Color(0.86, 0.85, 0.8))
			var holder := Node3D.new()
			holder.name = "TuerL"
			holder.position = Vector3(-1.15, 0, 0)
			holder.set_meta("no_bake", true)
			holder.set_meta("swing", -1.0)
			n.add_child(holder)
			var lk := Kit.new()
			lk.box(Vector3(0.02, 0.02, -0.035), Vector3(1.12, 2.28, 0.035), Color(0.55, 0.58, 0.62))
			lk.box(Vector3(0.08, 1.5, -0.04), Vector3(0.4, 2.0, 0.04), Color(0.3, 0.4, 0.45))
			for sz: float in [-1.0, 1.0]:
				lk.box(Vector3(0.95, 1.05, sz * 0.04), Vector3(1.05, 1.1, sz * 0.09), CHROME)
				lk.box(Vector3(0.95, 0.02, sz * 0.035), Vector3(1.1, 0.25, sz * 0.04), DARK)
			holder.add_child(lk.instance("Fluegel"))


# ---------------------------------------------------------------- Personalraum

## Personalraum: Spinde, Tisch mit Stühlen, Küchenzeile mit Kaffeemaschine (dampft), Kühlschrank,
## Sofa, Pinnwand und eine Mitarbeiterin in der Pause.
static func _staff_room(n: Node3D, k: Kit) -> void:
	k.box(Vector3(-3.0, 0, -2.0), Vector3(3.0, 0.02, 2.0), Color(0.62, 0.6, 0.56))
	# Spinde an der Rückwand
	for i in range(8):
		var x := -2.9 + float(i) * 0.5
		var c := Color(0.35, 0.5, 0.62) if i % 2 == 0 else Color(0.32, 0.46, 0.58)
		k.box(Vector3(x, 0.02, -1.95), Vector3(x + 0.48, 1.9, -1.5), c)
		k.box(Vector3(x + 0.04, 1.55, -1.5), Vector3(x + 0.44, 1.75, -1.49), c.darkened(0.25))
		for v in range(4):
			k.box(Vector3(x + 0.08, 1.58 + float(v) * 0.04, -1.495), Vector3(x + 0.4, 1.6 + float(v) * 0.04, -1.488), c.lightened(0.15))
		k.box(Vector3(x + 0.38, 0.95, -1.5), Vector3(x + 0.42, 1.1, -1.47), CHROME)
		k.box(Vector3(x + 0.16, 1.82, -1.5), Vector3(x + 0.32, 1.86, -1.49), WHITE)
	k.box(Vector3(-2.9, 0.02, -1.4), Vector3(1.1, 0.45, -1.1), OAK)
	# Tisch mit vier Stühlen
	k.cyl(Vector3(-0.6, 0.02, 0.3), Vector3(-0.6, 0.72, 0.3), 0.05, 0.05, CHROME, 8)
	k.cyl(Vector3(-0.6, 0.72, 0.3), Vector3(-0.6, 0.76, 0.3), 0.6, 0.6, WHITE, 18)
	for i in range(4):
		var a := float(i) / 4.0 * TAU + 0.4
		var cp := Vector3(-0.6 + cos(a) * 0.85, 0, 0.3 + sin(a) * 0.85)
		var inward := Vector3(-cos(a), 0, -sin(a))
		k.box(cp + Vector3(-0.2, 0.42, -0.2), cp + Vector3(0.2, 0.47, 0.2), Color(0.85, 0.3, 0.2))
		var back := cp - inward * 0.22
		k.cyl(back + Vector3(0, 0.47, 0), back + Vector3(0, 0.9, 0), 0.03, 0.03, CHROME, 6)
		k.sphere(back + Vector3(0, 0.88, 0), 0.16, Color(0.85, 0.3, 0.2), 8, 4, Vector3(1.0, 0.55, 1.0))
		k.cyl(cp, cp + Vector3(0, 0.42, 0), 0.025, 0.025, CHROME, 6)
	k.cyl(Vector3(-0.5, 0.76, 0.2), Vector3(-0.5, 0.86, 0.2), 0.045, 0.04, WHITE, 8)
	k.cyl(Vector3(-0.8, 0.76, 0.45), Vector3(-0.8, 0.86, 0.45), 0.045, 0.04, Color(0.3, 0.45, 0.7), 8)
	# Küchenzeile rechts
	k.box(Vector3(1.6, 0.02, -1.95), Vector3(2.95, 0.9, 1.2), WHITE)
	k.box(Vector3(1.55, 0.9, -1.98), Vector3(2.98, 0.95, 1.22), Color(0.3, 0.3, 0.32))
	for z: float in [-1.4, -0.6, 0.2]:
		k.box(Vector3(1.59, 0.1, z), Vector3(1.6, 0.85, z + 0.75), Color(0.85, 0.85, 0.82))
		k.box(Vector3(1.57, 0.7, z + 0.3), Vector3(1.59, 0.74, z + 0.45), CHROME)
	k.rounded_box(Vector3(2.2, 0.95, -1.7), Vector3(2.75, 1.45, -1.25), 0.04, DARK, 2)
	k.box(Vector3(2.19, 1.2, -1.6), Vector3(2.21, 1.38, -1.35), Color(0.3, 0.8, 1.0, 0.3))
	k.cyl(Vector3(2.1, 0.95, -1.47), Vector3(2.1, 1.05, -1.47), 0.05, 0.045, WHITE, 8)
	k.cyl(Vector3(2.4, 0.95, 0.6), Vector3(2.4, 1.1, 0.6), 0.12, 0.1, CHROME, 10)
	k.rounded_box(Vector3(2.3, 0.02, 1.3), Vector3(2.95, 1.85, 1.95), 0.04, Color(0.88, 0.88, 0.86), 2)
	k.box(Vector3(2.29, 0.9, 1.35), Vector3(2.3, 0.95, 1.9), Color(0.6, 0.6, 0.6))
	var steam := Kit.new()
	for i in range(3):
		steam.sphere(Vector3(0, float(i) * 0.12, 0), 0.05 + float(i) * 0.02, Color(0.95, 0.95, 0.95, 0.6), 6, 4)
	var st := _part(n, "HubDampf", steam, Vector3(2.1, 1.12, -1.47))
	st.set_meta("speed", 2.0)
	# Sofa links, Pinnwand
	k.rounded_box(Vector3(-2.95, 0.02, 0.4), Vector3(-2.2, 0.45, 1.9), 0.06, Color(0.42, 0.5, 0.36), 2)
	k.rounded_box(Vector3(-2.95, 0.45, 0.4), Vector3(-2.75, 0.9, 1.9), 0.06, Color(0.38, 0.46, 0.33), 2)
	for z: float in [0.42, 1.88]:
		k.rounded_box(Vector3(-2.95, 0.45, z - 0.1), Vector3(-2.2, 0.65, z + 0.1), 0.04, Color(0.38, 0.46, 0.33), 2)
	k.box(Vector3(-0.8, 1.2, -1.99), Vector3(0.6, 1.9, -1.96), Color(0.7, 0.55, 0.35))
	for i in range(6):
		var px := -0.7 + float(i % 3) * 0.42
		var py := 1.3 + float(i / 3) * 0.3
		k.box(Vector3(px, py, -1.96), Vector3(px + 0.3, py + 0.22, -1.955), [WHITE, Color(1.0, 0.95, 0.5), Color(0.6, 0.85, 1.0)][i % 3] as Color)
	_plant_small(k, Vector3(-2.6, 0.02, -0.6))
	_staff(n, Color(0.2, 0.32, 0.55), Vector3(-2.5, 0.0, 1.1), 1, Vector3(1, 0, 0))


static func _plant_small(k: Kit, at: Vector3) -> void:
	k.cyl(at, at + Vector3(0, 0.35, 0), 0.18, 0.22, Color(0.75, 0.72, 0.68), 10)
	for i in range(6):
		var a := float(i) / 6.0 * TAU
		k.sphere(at + Vector3(cos(a) * 0.12, 0.55 + float(i % 2) * 0.12, sin(a) * 0.12), 0.16, LEAF if i % 2 == 0 else LEAF2, 6, 4)


## Reinigungswagen (für die Reinigungskraft, die durchs Terminal läuft): Front +Z.
static func cleaning_cart_mesh() -> ArrayMesh:
	var k := Kit.new()
	k.box(Vector3(-0.3, 0.1, -0.45), Vector3(0.3, 0.14, 0.45), Color(0.25, 0.4, 0.75))
	k.box(Vector3(-0.28, 0.14, -0.4), Vector3(0.28, 0.6, -0.05), Color(0.85, 0.85, 0.82))
	k.cyl(Vector3(0.0, 0.14, 0.2), Vector3(0.0, 0.5, 0.2), 0.2, 0.18, Color(0.95, 0.8, 0.15), 12)
	k.box(Vector3(-0.3, 0.6, -0.45), Vector3(0.3, 0.64, -0.0), Color(0.25, 0.4, 0.75))
	k.cyl(Vector3(-0.25, 0.64, -0.45), Vector3(-0.25, 1.0, -0.45), 0.015, 0.015, CHROME, 6)
	k.cyl(Vector3(0.25, 0.64, -0.45), Vector3(0.25, 1.0, -0.45), 0.015, 0.015, CHROME, 6)
	k.cyl(Vector3(-0.25, 1.0, -0.45), Vector3(0.25, 1.0, -0.45), 0.02, 0.02, CHROME, 6)
	for i in range(3):
		k.cyl(Vector3(-0.15 + float(i) * 0.15, 0.64, -0.25), Vector3(-0.15 + float(i) * 0.15, 0.82, -0.25), 0.05, 0.05,
			[Color(0.2, 0.6, 0.9), Color(0.9, 0.3, 0.5), Color(0.3, 0.8, 0.4)][i] as Color, 8)
	k.cyl(Vector3(0.15, 0.5, 0.2), Vector3(0.05, 1.2, 0.35), 0.015, 0.015, Color(0.6, 0.4, 0.2), 5)
	for w: Vector2 in [Vector2(-0.25, -0.38), Vector2(0.25, -0.38), Vector2(-0.25, 0.38), Vector2(0.25, 0.38)]:
		k.cyl(Vector3(w.x - 0.02, 0.06, w.y), Vector3(w.x + 0.02, 0.06, w.y), 0.06, 0.06, DARK, 8)
	k.box(Vector3(-0.12, 0.0, 0.5), Vector3(0.12, 0.6, 0.52), Color(0.95, 0.8, 0.15))
	return k.commit()
