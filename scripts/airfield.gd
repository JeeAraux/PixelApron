extends Node3D
## Flugfeld nach ICAO Annex 14: Befeuerung (Piste, Rollwege, Anflug mit Lauffeuer, PAPI),
## Rollhalteorte mit Markierung Muster A, Haltebalken, Pistenwarnlichtern und Schildern,
## Richtungsschilder an Rollweg-Kreuzungen, Einrolllinien und Standnummern, Windsäcke.
## Baut sich neu auf, wenn sich Wege oder Stände ändern.

const Catalog = preload("res://scripts/catalog.gd")
const Kit = preload("res://scripts/mesh_kit.gd")
const PixelFont = preload("res://scripts/pixel_font.gd")
const Airside = preload("res://scripts/airside.gd")
const Factory = preload("res://scripts/factory.gd")
const Models = preload("res://scripts/models.gd")
const GameState = preload("res://scripts/game_state.gd")

const BLUE := Color(0.3, 0.5, 1.0)
const GREEN := Color(0.25, 1.0, 0.5)
const AMBER := Color(1.0, 0.78, 0.2)
const RED := Color(1.0, 0.18, 0.12)
const LAMP_WHITE := Color(1.0, 0.98, 0.88)
const SIGN_RED := Color(0.72, 0.1, 0.08)
const SIGN_YELLOW := Color(0.95, 0.78, 0.15)
const SIGN_BLACK := Color(0.07, 0.07, 0.07)
const MARK_YELLOW := Color(0.88, 0.70, 0.18)
const MARK_WHITE := Color(0.88, 0.88, 0.85)
const POST := Color(0.85, 0.72, 0.2)
const TAXI_LETTERS := ["A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "P", "Q", "R", "S", "T", "U", "W", "Y", "Z"]

var game: GameState
var graph := Airside.new()
var dirty := true
var names: Dictionary = {}          # Linienindex -> Rollwegname
var stand_numbers: Dictionary = {}  # Instanz-ID des Stand-Knotens -> Nummer
var wigwag: Array = []              # zwei Gruppen Pistenwarnlichter, abwechselnd an
var flashers: Array = []            # je Anflugbefeuerung die Lauffeuer, zur Schwelle hin geordnet
var cur_lit := true                 # beim Bauen: leuchten die Feuer (Befeuerungsstation mit Strom)?
var socks: Array = []               # Windsäcke
var t := 0.0
var _pave: Dictionary = {}          # Raster für "liegt auf einem anderen Belag?"

static var _lamp_mat: ShaderMaterial
static var _halo_mat: ShaderMaterial
var halos: Array = []               # [Position, Farbe, Größe] für die Lichthöfe
var night_lights: Array = []        # echte Lichtquellen (Laternen, Flutlicht), nachts an
const LAMP_SHADER = preload("res://shaders/lamp.gdshader")
const HALO_SHADER = preload("res://shaders/halo.gdshader")


func setup(g: GameState) -> void:
	game = g
	game.network_changed.connect(_mark)
	game.items_changed.connect(_mark)


func _mark() -> void:
	dirty = true


static func lamp_material() -> ShaderMaterial:
	if _lamp_mat == null:
		_lamp_mat = ShaderMaterial.new()
		_lamp_mat.shader = LAMP_SHADER
	return _lamp_mat


static func halo_material() -> ShaderMaterial:
	if _halo_mat == null:
		_halo_mat = ShaderMaterial.new()
		_halo_mat.shader = HALO_SHADER
	return _halo_mat


func _process(delta: float) -> void:
	if dirty:
		rebuild()
	t += delta
	var night: float = game.night
	for l: Light3D in night_lights:
		if is_instance_valid(l):
			l.visible = night > 0.05
			l.light_energy = float(l.get_meta("energy", 1.0)) * night
	if wigwag.size() == 2:
		var on := fmod(t, 1.0) < 0.5
		(wigwag[0] as Node3D).visible = on
		(wigwag[1] as Node3D).visible = not on
	for group: Array in flashers:
		# zweimal pro Sekunde läuft ein Blitz zur Schwelle
		var phase := fmod(t, 0.5) / 0.5
		var lit := int(phase * float(group.size() + 3))
		for i in range(group.size()):
			(group[i] as Node3D).visible = i == lit
	for s: Node3D in socks:
		if is_instance_valid(s):
			# zeigt mit dem Wind (vom Wind weg), pendelt leicht; bei wenig Wind hängt er schlaffer
			s.rotation.y = -deg_to_rad(game.wind_dir) + sin(t * 0.37 + float(s.get_meta("seed", 0.0))) * 0.12
			s.rotation.x = -lerpf(0.5, 0.0, clampf(game.wind_kt / 15.0, 0.0, 1.0))
			s.rotation.z = sin(t * 2.3) * 0.04


## Name jedes Rollwegs (A, B, C … in Bauzeitfolge).
static func taxi_names(lines: Array) -> Dictionary:
	var out := {}
	var n := 0
	for i in range(lines.size()):
		if lines[i]["kind"] == "rollweg" or lines[i]["kind"] == "rollweg_breit":
			var letter: String = TAXI_LETTERS[n % TAXI_LETTERS.size()]
			out[i] = letter if n < TAXI_LETTERS.size() else letter + str(n / TAXI_LETTERS.size())
			n += 1
	return out


func rebuild() -> void:
	dirty = false
	for c in get_children():
		c.queue_free()
	wigwag = []
	flashers = []
	socks = []
	halos = []
	night_lights = []
	graph.build(game.lines, game.stands(), game.items_of("rollhalt") + game.items_of("wendeplatte"))
	# Rollwege mit selbst gezeichneten Linien verlieren ihre automatische Mittellinie
	for li in range(game.lines.size()):
		var gl: Dictionary = game.lines[li]
		if not (gl["kind"] in ["rollweg", "rollweg_breit", "vorfeld"]) or not is_instance_valid(gl.get("node")):
			continue
		var gm := (gl["node"] as GeometryInstance3D).material_override as ShaderMaterial
		if gm != null:
			# Vorfeld ohne gezeichnete Linien: die Flugzeuge rollen auf der Mittellinie, also wird sie gemalt
			if gl["kind"] == "vorfeld":
				gm.set_shader_parameter("mark", 5 if graph.guided.has(li) else 13)
			else:
				gm.set_shader_parameter("mark", 11 if graph.guided.has(li) else 2)
	names = taxi_names(game.lines)
	_index_pavement()
	var k := Kit.new()       # Masten, Gehäuse, Schilder
	var km := Kit.new()      # Bodenmarkierungen
	var lamps := {}          # Farbe -> Kit (leuchtend, unbeleuchtet)
	var taxi_lit := game.legacy_lights or _any_station()
	var wa := Kit.new()
	var wb := Kit.new()
	for li in range(game.lines.size()):
		var l: Dictionary = game.lines[li]
		if l["kind"] == "piste":
			_runway(l, k, lamps)
		elif l["kind"] == "rollweg" or l["kind"] == "rollweg_breit":
			cur_lit = taxi_lit
			_taxi_lights(li, l, k, lamps)
			cur_lit = true
	cur_lit = taxi_lit
	_holds(k, km, lamps, wa, wb)
	cur_lit = true
	_junction_signs(k)
	_taxi_junctions(km)
	_apron_edges(km)
	_turn_pad_marks(km)
	_stands(k, km, lamps)
	_add(k, "Flugfeld", false)
	_add(km, "Markierung", false)
	for key: String in lamps:
		_add(lamps[key], "Licht", true)
	if wa.count > 0:
		wigwag = [_add(wa, "WarnA", true), _add(wb, "WarnB", true)]
	_street_lights()
	_build_halos()


## Laternen und Flutlichtmasten: nachts echte Lichtkegel und Lichthöfe.
func _street_lights() -> void:
	for it: Dictionary in game.items:
		var id: String = it["id"]
		if id != "laterne" and id != "flutlicht":
			continue
		var node: Node3D = it["node"]
		var b := node.global_transform.basis
		var heads := [[Vector3(0, 6.7, 1.2), 15.0, 1.1, Color(1.0, 0.85, 0.6)]]
		if id == "flutlicht":
			heads = []
			for sx: float in [-1.6, -0.55, 0.55, 1.6]:
				heads.append([Vector3(sx, 24.6, 0.6), 120.0, 16.0, Color(1.0, 0.96, 0.88)])
		for h: Array in heads:
			var p: Vector3 = (it["pos"] as Vector3) + b * (h[0] as Vector3)
			var sl := SpotLight3D.new()
			sl.position = p
			sl.basis = Basis.looking_at(Vector3(0, -1, 0.001) if id == "laterne" else (b * Vector3(0, -0.8, 0.6)).normalized(), Vector3.UP)
			sl.spot_range = float(h[1])
			sl.spot_angle = 62.0 if id == "laterne" else 48.0
			sl.light_color = h[3]
			sl.shadow_enabled = false
			sl.visible = false
			sl.set_meta("energy", float(h[2]))
			add_child(sl)
			night_lights.append(sl)
			halos.append([p, h[3], 5.0 if id == "laterne" else 9.0])


## Lichthöfe aller Lampen in einem Mesh: vier Ecken je Lampe am selben Punkt, der Shader spannt sie auf.
func _build_halos() -> void:
	var groups := {}
	for h: Array in halos:
		var key := snappedf(float(h[2]), 0.5)
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(h)
	for key: float in groups:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for h: Array in groups[key]:
			var p: Vector3 = h[0]
			var c: Color = h[1]
			for uv: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
				st.set_color(c)
				st.set_uv(uv)
				st.add_vertex(p)
		var mi := MeshInstance3D.new()
		mi.name = "Lichthof"
		mi.mesh = st.commit()
		var m := halo_material().duplicate() as ShaderMaterial
		m.set_shader_parameter("size", key)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16.0
		add_child(mi)


func _add(k: Kit, nm: String, lit: bool) -> MeshInstance3D:
	var mi := k.instance(nm)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lit else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if lit:
		mi.material_override = lamp_material()
	add_child(mi)
	return mi


func _lk(lamps: Dictionary, col: Color) -> Kit:
	var key := col.to_html()
	if not lamps.has(key):
		lamps[key] = Kit.new()
	return lamps[key]


## Unterflurfeuer (bündig im Belag) oder Überflurfeuer auf einem Knickmast.
func _lamp(k: Kit, lamps: Dictionary, p: Vector3, col: Color, elevated: bool, top: float = 0.1) -> void:
	if not cur_lit:
		# ohne Befeuerungsstation: nur die Gehäuse, dunkel
		if elevated:
			k.box(p + Vector3(-0.06, 0.0, -0.06), p + Vector3(0.06, 0.42, 0.06), POST)
			k.cyl(p + Vector3(0, 0.42, 0), p + Vector3(0, 0.74, 0), 0.17, 0.12, col.darkened(0.6), 8)
		else:
			k.cyl(p, p + Vector3(0, top + 0.05, 0), 0.24, 0.24, Color(0.35, 0.36, 0.37), 8)
		return
	var kl := _lk(lamps, col)
	if elevated:
		k.box(p + Vector3(-0.06, 0.0, -0.06), p + Vector3(0.06, 0.42, 0.06), POST)
		kl.cyl(p + Vector3(0, 0.42, 0), p + Vector3(0, 0.74, 0), 0.17, 0.12, col, 8)
		halos.append([p + Vector3(0, 0.6, 0), col, 3.0])
	else:
		kl.cyl(p, p + Vector3(0, top + 0.05, 0), 0.24, 0.24, col, 8)
		halos.append([p + Vector3(0, top + 0.1, 0), col, 2.5])


# ---------------------------------------------------------------- Beläge

func _index_pavement() -> void:
	_pave = {}
	for li in range(game.lines.size()):
		var l: Dictionary = game.lines[li]
		var kind: String = l["kind"]
		if not (kind in ["piste", "rollweg", "rollweg_breit", "vorfeld"]):
			continue
		var hw := float(Catalog.LINES[kind]["width"]) * 0.5
		var s: PackedVector3Array = l["samples"]
		for i in range(0, s.size(), 2):
			var key := Vector2i(floori(s[i].x / 20.0), floori(s[i].z / 20.0))
			if not _pave.has(key):
				_pave[key] = []
			(_pave[key] as Array).append([s[i].x, s[i].z, hw, li, kind])


## Liegt p auf einem anderen Belag als Linie li? kinds leer = alle.
func _on_other(p: Vector3, li: int, kinds: Array = []) -> bool:
	var c := Vector2i(floori(p.x / 20.0), floori(p.z / 20.0))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for e: Array in _pave.get(c + Vector2i(dx, dz), []):
				if int(e[3]) == li:
					continue
				if not kinds.is_empty() and not (String(e[4]) in kinds):
					continue
				var d := Vector2(p.x - float(e[0]), p.z - float(e[1])).length()
				if d < float(e[2]) - 0.3:
					return true
	return false


# ---------------------------------------------------------------- Piste

func _runway(l: Dictionary, k: Kit, lamps: Dictionary) -> void:
	var s: PackedVector3Array = l["samples"]
	var a := Vector3(s[0].x, 0, s[0].z)
	var b := Vector3(s[s.size() - 1].x, 0, s[s.size() - 1].z)
	var length := a.distance_to(b)
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP).normalized()   # rechts in Landerichtung
	var hw := float(Catalog.LINES["piste"]["width"]) * 0.5
	var at := func(dv: float, dx: float) -> Vector3: return a + dir * dv + side * dx
	# Befeuerung leuchtet nur mit einer Befeuerungsstation mit Strom (alte Spielstände: immer)
	cur_lit = game.legacy_lights or _station_near(a, b)
	# Randfeuer alle 60 m, die letzten 600 m gelb
	var v := 0.0
	while v <= length + 0.1:
		var col := AMBER if length - v < 600.0 else LAMP_WHITE
		for sx: float in [-1.0, 1.0]:
			_lamp(k, lamps, at.call(v, sx * (hw + 1.5)), col, true)
		v += 60.0
	# Schwellenfeuer grün (Anfang), Endfeuer rot (Ende), mit Flügelbalken
	var x := -hw + 1.5
	while x <= hw - 1.4:
		_lamp(k, lamps, at.call(0.6, x), GREEN, false, 0.09)
		_lamp(k, lamps, at.call(length - 0.6, x), RED, false, 0.09)
		x += 3.0
	for sx: float in [-1.0, 1.0]:
		for i in range(5):
			_lamp(k, lamps, at.call(0.0, sx * (hw + 3.0 + float(i) * 1.5)), GREEN, true)
	# Mittellinienfeuer alle 15 m: weiß, ab 900 m vor dem Ende rot/weiß, die letzten 300 m rot
	v = 15.0
	var n := 0
	while v < length - 10.0:
		var rest := length - v
		var col := LAMP_WHITE
		if rest < 300.0:
			col = RED
		elif rest < 900.0 and n % 2 == 1:
			col = RED
		_lamp(k, lamps, at.call(v, 0.6), col, false, 0.09)
		v += 15.0
		n += 1
	# Aufsetzzonenfeuer: Dreierreihen beidseitig auf den ersten 900 m
	v = 60.0
	while v <= minf(900.0, length * 0.5):
		for sx: float in [-1.0, 1.0]:
			for i in range(3):
				_lamp(k, lamps, at.call(v, sx * (9.0 + float(i) * 1.5)), LAMP_WHITE, false, 0.09)
		v += 30.0
	# Anflugbefeuerung und PAPI: selbst gebaut an den Pistenenden (alte Spielstände: an der Schwelle a)
	for e in range(2):
		var thr := a if e == 0 else b
		var inward := dir if e == 0 else -dir
		if (game.legacy_lights and e == 0) or _marker_at("anflugbefeuerung", thr - inward * 12.0, 30.0):
			_approach_lights(k, lamps, thr, inward)
		var aim := 400.0 if length >= 2400.0 else 300.0 if length >= 1500.0 else 250.0
		var left := Vector3.UP.cross(inward).normalized()
		if (game.legacy_lights and e == 0) or _marker_at("papi", thr + inward * aim + left * (hw + 28.0), 30.0):
			_papi(k, lamps, thr + inward * aim, inward, hw)
	cur_lit = true
	# Windsäcke an beiden Enden
	for e: Array in [[300.0, 1.0], [length - 300.0, -1.0]]:
		var q: Vector3 = at.call(float(e[0]), float(e[1]) * (hw + 75.0))
		_windsock(k, q)


## Steht eine Befeuerungsstation mit Strom höchstens 450 m von der Piste a–b?
func _station_near(a: Vector3, b: Vector3) -> bool:
	for st: Dictionary in game.items_of("befeuerungsstation"):
		if game.supplied(st, "strom") and GameState.seg_dist(st["pos"], a, b) <= 450.0:
			return true
	return false


func _any_station() -> bool:
	for st: Dictionary in game.items_of("befeuerungsstation"):
		if game.supplied(st, "strom"):
			return true
	return false


func _marker_at(id: String, p: Vector3, r: float) -> bool:
	for it: Dictionary in game.items_of(id):
		if Vector2((it["pos"] as Vector3).x - p.x, (it["pos"] as Vector3).z - p.z).length() < r:
			return true
	return false


## Anflugbefeuerung (CAT I) vor der Schwelle thr: Querbalken alle 30 m über 900 m auf Masten,
## Querbalken bei 300 m, Lauffeuer zur Schwelle hin.
func _approach_lights(k: Kit, lamps: Dictionary, thr: Vector3, inward: Vector3) -> void:
	var side := inward.cross(Vector3.UP).normalized()
	var at := func(dv: float, dx: float) -> Vector3: return thr + inward * dv + side * dx
	var order := []
	var v := -30.0
	while v >= -900.0:
		var p0: Vector3 = at.call(v, 0.0)
		var mast := clampf(-v / 300.0, 0.3, 2.5)
		for i in range(5):
			var q: Vector3 = at.call(v, -2.0 + float(i))
			k.box(q + Vector3(-0.07, 0, -0.07), q + Vector3(0.07, mast, 0.07), Color(0.5, 0.5, 0.5))
			if cur_lit:
				_lk(lamps, LAMP_WHITE).box(q + Vector3(-0.22, mast, -0.22), q + Vector3(0.22, mast + 0.35, 0.22), LAMP_WHITE)
			else:
				k.box(q + Vector3(-0.22, mast, -0.22), q + Vector3(0.22, mast + 0.35, 0.22), Color(0.55, 0.55, 0.52))
		k.box(p0 - side * 2.2 + Vector3(0, mast - 0.1, -0.05) - inward * 0.05, p0 + side * 2.2 + Vector3(0, mast, 0.05) + inward * 0.05, Color(0.5, 0.5, 0.5))
		if absf(v + 300.0) < 1.0:
			for i in range(-10, 11):
				if absi(i) <= 2:
					continue
				_lamp(k, lamps, at.call(v, float(i) * 1.5), LAMP_WHITE, true)
		if v <= -330.0:
			order.append(p0 + Vector3(0, mast + 0.9, 0))
		v -= 30.0
	if not cur_lit:
		return
	order.reverse()   # vom äußersten Feuer zur Schwelle
	var group := []
	for q: Vector3 in order:
		var fk := Kit.new()
		fk.box(q + Vector3(-0.45, -0.3, -0.45), q + Vector3(0.45, 0.3, 0.45), Color(1, 1, 1))
		var fl := _add(fk, "Lauffeuer", true)
		fl.visible = false
		group.append(fl)
	flashers.append(group)


## PAPI links am Zielpunkt: vier Kästen, die zwei inneren rot, die äußeren weiß (auf dem Gleitpfad).
func _papi(k: Kit, lamps: Dictionary, aim_pt: Vector3, inward: Vector3, hw: float) -> void:
	var side := inward.cross(Vector3.UP).normalized()
	for i in range(4):
		var q: Vector3 = aim_pt - side * (hw + 15.0 + float(i) * 9.0)
		k.box(q + Vector3(-0.6, 0, -0.6), q + Vector3(0.6, 0.35, 0.6), Color(0.3, 0.3, 0.3))
		var box_c := q + Vector3(0, 0.85, 0)
		k.box(box_c - side * 0.7 - inward * 0.4 + Vector3(0, -0.45, 0), box_c + side * 0.7 + inward * 0.4 + Vector3(0, 0.45, 0), Color(0.9, 0.6, 0.15))
		var lens := RED if i < 2 else LAMP_WHITE
		for j in range(3):
			var lc := box_c - inward * 0.42 + side * (-0.42 + float(j) * 0.42)
			if cur_lit:
				_lk(lamps, lens).box(lc + Vector3(-0.15, -0.15, -0.15), lc + Vector3(0.15, 0.15, 0.15), lens)
			else:
				k.box(lc + Vector3(-0.15, -0.15, -0.15), lc + Vector3(0.15, 0.15, 0.15), Color(0.35, 0.3, 0.3))


func _windsock(k: Kit, q: Vector3) -> void:
	k.box(q + Vector3(-1.5, 0, -1.5), q + Vector3(1.5, 0.15, 1.5), Color(0.55, 0.54, 0.5))
	k.cyl(q, q + Vector3(0, 6.5, 0), 0.12, 0.08, Color(0.85, 0.85, 0.82), 8)
	var holder := Node3D.new()
	holder.name = "Windsack"
	holder.position = q + Vector3(0, 6.3, 0)
	holder.set_meta("base", randf() * TAU)
	holder.set_meta("seed", randf() * 10.0)
	var sk := Kit.new()
	sk.cyl(Vector3(0, -0.1, 0), Vector3(0, 0.1, 0), 0.6, 0.6, Color(0.3, 0.3, 0.3), 10)
	for i in range(5):
		var z0 := float(i) * 0.75
		var r0 := 0.55 - float(i) * 0.07
		var r1 := 0.55 - float(i + 1) * 0.07
		var c := Color(0.98, 0.45, 0.1) if i % 2 == 0 else Color(0.95, 0.95, 0.93)
		sk.cyl(Vector3(0, -0.05 * float(i), z0), Vector3(0, -0.05 * float(i + 1), z0 + 0.75), r0, r1, c, 10, false)
	holder.add_child(sk.instance("Sack"))
	add_child(holder)
	socks.append(holder)


# ---------------------------------------------------------------- Rollwege

func _taxi_lights(li: int, l: Dictionary, k: Kit, lamps: Dictionary) -> void:
	var s: PackedVector3Array = l["samples"]
	if s.size() < 3:
		return
	var hw := float(Catalog.LINES[String(l["kind"])]["width"]) * 0.5
	var acc_edge := 0.0
	var acc_c := 0.0
	var alt := 0
	for i in range(1, s.size() - 1):
		var seg := s[i].distance_to(s[i - 1])
		acc_edge += seg
		acc_c += seg
		var t0 := s[maxi(i - 4, 0)]
		var t1 := s[mini(i + 4, s.size() - 1)]
		var tng := Vector3(t1.x - t0.x, 0, t1.z - t0.z).normalized()
		var tb := s[mini(i + 1, s.size() - 1)] - s[maxi(i - 1, 0)]
		var ta := s[i] - s[maxi(i - 5, 0)]
		var bend := 0.0
		if ta.length() > 0.1 and tb.length() > 0.1:
			bend = absf(Vector2(ta.x, ta.z).angle_to(Vector2(tb.x, tb.z))) / maxf(ta.length(), 0.1)
		var curved := bend > 0.004
		var right := tng.cross(Vector3.UP)
		var p := Vector3(s[i].x, 0, s[i].z)
		if acc_c >= (7.5 if curved else 15.0):
			acc_c = 0.0
			if not _on_other(p, li, ["piste", "vorfeld"]):
				var col := GREEN
				if graph.runway_distance(p) < Airside.HOLD_DIST:
					col = GREEN if alt % 2 == 0 else AMBER
					alt += 1
				_lamp(k, lamps, p, col, false, 0.04)
		if acc_edge >= (15.0 if curved else 30.0):
			acc_edge = 0.0
			for sx: float in [-1.0, 1.0]:
				var q := p + right * sx * (hw + 1.2)
				if not _on_other(q, li):
					_lamp(k, lamps, q, BLUE, true)


## Rollhalteorte: Markierung Muster A (zwei durchgezogene, zwei unterbrochene Linien), Haltebalken (rot),
## Pistenwarnlichter (gelb, abwechselnd), Gebotsschild (rot, Pistenbezeichnung) mit Ortsschild (Rollwegname).
func _holds(k: Kit, km: Kit, lamps: Dictionary, wa: Kit, wb: Kit) -> void:
	var hw := 9.0
	for h: Dictionary in graph.holds:
		hw = float(Catalog.LINES[String(game.lines[int(h["line"])]["kind"])]["width"]) * 0.5
		var c: Vector3 = h["pos"]
		var dir: Vector3 = h["dir"]
		var right := dir.cross(Vector3.UP).normalized()
		var bas := Basis.looking_at(dir, Vector3.UP)
		for off: float in [-1.35, -0.75]:
			km.box(Vector3(-hw + 0.4, 0, -0.15), Vector3(hw - 0.4, 0.068, 0.15), MARK_YELLOW, Transform3D(bas, c + dir * off))
		for off: float in [-0.15, 0.45]:
			var x := -hw + 0.4
			while x < hw - 0.4:
				km.box(Vector3(x, 0, -0.15), Vector3(minf(x + 1.0, hw - 0.4), 0.068, 0.15), MARK_YELLOW, Transform3D(bas, c + dir * off))
				x += 2.0
		# Haltebalken
		var x2 := -hw + 1.5
		while x2 <= hw - 1.5:
			_lamp(k, lamps, c - dir * 2.4 + right * x2, RED, false, 0.04)
			x2 += 3.0
		# Pistenwarnlichter beidseitig
		for sx: float in [-1.0, 1.0]:
			var q := c - dir * 2.0 + right * sx * (hw + 3.2)
			k.box(q + Vector3(-0.08, 0, -0.08), q + Vector3(0.08, 0.7, 0.08), POST)
			k.box(q - right * 0.6 + Vector3(0, 0.7, 0) - dir * 0.15, q + right * 0.6 + Vector3(0, 1.15, 0) + dir * 0.15, SIGN_BLACK)
			for side_i in range(2):
				var lc := q + right * (-0.3 + float(side_i) * 0.6) + Vector3(0, 0.93, 0) - dir * 0.17
				(wa if side_i == 0 else wb).box(lc + Vector3(-0.17, -0.17, -0.08), lc + Vector3(0.17, 0.17, 0.08), AMBER)
		# Schilder: links [Ort][Gebot], rechts [Gebot][Ort]
		var rw := _runway_text(c, dir)
		var nm: String = names.get(int(h["line"]), "")
		for sx: float in [-1.0, 1.0]:
			var base := c - dir * 4.0 + right * sx * (hw + 3.5 + 3.5)
			var signs := [[rw, "gebot"]]
			if nm != "":
				if sx < 0.0:
					signs.push_front([nm, "ort"])
				else:
					signs.append([nm, "ort"])
			_sign_array(k, base, dir, signs)


## Text des Gebotsschilds: Kennzahl der Schwelle links zuerst (vom Rollhalt aus gesehen).
func _runway_text(c: Vector3, dir: Vector3) -> String:
	var best: Dictionary = {}
	var bd := INF
	for l: Dictionary in game.lines:
		if l["kind"] != "piste":
			continue
		var s: PackedVector3Array = l["samples"]
		var d := Airside._seg_dist(c, s[0], s[s.size() - 1])
		if d < bd:
			bd = d
			best = l
	if best.is_empty():
		return "RWY"
	var s: PackedVector3Array = best["samples"]
	var nums := Factory.runway_numbers(s)
	var left := Vector3.UP.cross(dir).normalized()
	var a_left := (s[0] - c).dot(left) > (s[s.size() - 1] - c).dot(left)
	if a_left:
		return "%02d-%02d" % [nums[0], nums[1]]
	return "%02d-%02d" % [nums[1], nums[0]]


## Schilderreihe quer zur Fahrtrichtung, lesbar für jemanden, der in Richtung dir darauf zurollt.
## Arten: "gebot" (rot, weiße Schrift), "ort" (schwarz, gelbe Schrift und Rahmen), "richtung" (gelb, schwarze Schrift).
func _sign_array(k: Kit, center: Vector3, dir: Vector3, signs: Array) -> void:
	var px := 0.13
	var right := dir.cross(Vector3.UP).normalized()
	var face := -dir
	var widths := []
	var total := 0.0
	for sg: Array in signs:
		var w := float(PixelFont.width(String(sg[0])) + 4) * px
		widths.append(w)
		total += w
	var x := -total * 0.5
	var y0 := 0.45
	var hgt := 7.0 * px + 4.0 * px
	for i in range(signs.size()):
		var sg: Array = signs[i]
		var w: float = widths[i]
		var mid := center + right * (x + w * 0.5)
		var bg := SIGN_RED
		var fg := Color(0.97, 0.97, 0.95)
		match String(sg[1]):
			"ort":
				bg = SIGN_BLACK
				fg = SIGN_YELLOW
			"richtung":
				bg = SIGN_YELLOW
				fg = SIGN_BLACK
		var bas := Basis.looking_at(dir, Vector3.UP)
		k.box(Vector3(-w * 0.5, y0, -0.12), Vector3(w * 0.5, y0 + hgt, 0.12), bg, Transform3D(bas, mid))
		if String(sg[1]) == "ort":
			# gelber Rahmen
			for e: Array in [[Vector2(-w * 0.5 + 0.05, y0 + 0.05), Vector2(w * 0.5 - 0.05, y0 + 0.11)],
					[Vector2(-w * 0.5 + 0.05, y0 + hgt - 0.11), Vector2(w * 0.5 - 0.05, y0 + hgt - 0.05)],
					[Vector2(-w * 0.5 + 0.05, y0 + 0.05), Vector2(-w * 0.5 + 0.11, y0 + hgt - 0.05)],
					[Vector2(w * 0.5 - 0.11, y0 + 0.05), Vector2(w * 0.5 - 0.05, y0 + hgt - 0.05)]]:
				var lo: Vector2 = e[0]
				var hi: Vector2 = e[1]
				k.box(Vector3(lo.x, lo.y, 0.12), Vector3(hi.x, hi.y, 0.14), fg, Transform3D(bas, mid))
		PixelFont.draw(k, String(sg[0]), mid + Vector3(0, y0 + hgt * 0.5, 0) + face * 0.15, right, Vector3.UP, face, px, fg)
		x += w
	# zwei Beine
	for sx: float in [-1.0, 1.0]:
		var q := center + right * sx * (total * 0.5 - 0.2)
		k.box(q + Vector3(-0.06, 0, -0.06), q + Vector3(0.06, y0, 0.06), Color(0.4, 0.4, 0.42))
		k.box(q + Vector3(-0.25, 0, -0.25), q + Vector3(0.25, 0.08, 0.25), Color(0.55, 0.54, 0.5))


## Richtungsschilder vor Kreuzungen zweier Rollwege: [Ort][Richtung mit Pfeil].
func _junction_signs(k: Kit) -> void:
	var hw := float(Catalog.LINES["rollweg"]["width"]) * 0.5
	var found := {}   # "X|Y" -> Array [Knoten X, Knoten Y]
	for i in range(graph.pos.size()):
		if not (graph.kind[i] in ["rollweg", "rollweg_breit"]):
			continue
		var lx := graph.line_idx[i]
		for nb: int in graph.adj[i]:
			if not (graph.kind[nb] in ["rollweg", "rollweg_breit"]) or graph.line_idx[nb] == lx:
				continue
			var key := "%d|%d" % [lx, graph.line_idx[nb]]
			var list: Array = found.get(key, [])
			var dup := false
			for e: Array in list:
				if graph.pos[int(e[0])].distance_to(graph.pos[i]) < 60.0:
					dup = true
			if not dup:
				list.append([i, nb])
			found[key] = list
	for key: String in found:
		var parts := key.split("|")
		var lx := int(parts[0])
		var ly := int(parts[1])
		hw = float(Catalog.LINES[String(game.lines[lx]["kind"])]["width"]) * 0.5
		if not names.has(lx) or not names.has(ly):
			continue
		var nodes_x: Array = graph.line_nodes.get(lx, [])
		var nodes_y: Array = graph.line_nodes.get(ly, [])
		for e: Array in found[key]:
			var jx: int = e[0]
			var jy: int = e[1]
			var ix := nodes_x.find(jx)
			var iy := nodes_y.find(jy)
			if ix < 0 or iy < 0:
				continue
			var jp := graph.pos[jx]
			if graph.runway_distance(jp) < Airside.HOLD_DIST + 10.0:
				continue
			# Äste von Y an der Kreuzung
			var branches := []
			for step: int in [-4, 4]:
				var q := iy + step
				if q >= 0 and q < nodes_y.size():
					branches.append(graph.pos[nodes_y[q]] - graph.pos[jy])
			# Auf X aus beiden Richtungen 45 m vor der Kreuzung
			for step: int in [-9, 9]:
				var q := ix + step
				if q < 0 or q >= nodes_x.size():
					continue
				var from := graph.pos[nodes_x[q]]
				var travel := (jp - from).normalized()
				var right := travel.cross(Vector3.UP).normalized()
				var signs := [[String(names[lx]), "ort"]]
				for b: Vector3 in branches:
					if b.length() < 1.0 or b.normalized().dot(travel) < -0.7:
						continue
					var side := travel.cross(b).y
					var txt := String(names[ly]) + ">" if side < 0.0 else "<" + String(names[ly])
					signs.append([txt, "richtung"])
				if signs.size() < 2:
					continue
				var pos := from - right * (hw + 3.5 + 3.0)
				if _on_other(pos, lx):
					continue
				_sign_array(k, pos, travel, signs)


## Rollweg-Kreuzungen wie auf echten Flughäfen: eine gemeinsame Belagfläche mit ausgerundeten Ecken
## (Ausrundungen) deckt die Überlappung der beiden Rollwege ab, die Randlinien folgen den Rundungen,
## und die gelben Mittellinien gehen als Bögen von jedem Ast in jeden anderen (nicht bei geführten Rollwegen).
func _taxi_junctions(km: Kit) -> void:
	var pk := Kit.new()
	var done := []
	for i in range(graph.pos.size()):
		if not (graph.kind[i] in ["rollweg", "rollweg_breit"]):
			continue
		var lx := graph.line_idx[i]
		for nb: int in graph.adj[i]:
			if not (graph.kind[nb] in ["rollweg", "rollweg_breit"]) or graph.line_idx[nb] == lx:
				continue
			var j := _junction_point(i, nb)
			var dup := false
			for q: Vector3 in done:
				if q.distance_to(j) < 30.0:
					dup = true
			if dup or graph.runway_distance(j) < 40.0:
				continue
			done.append(j)
			_junction_patch(pk, km, j, [i, nb])
	if pk.count == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Kreuzungsflaechen"
	mi.mesh = pk.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/line.gdshader")
	mat.set_shader_parameter("base_color", Color(0.2, 0.2, 0.19))
	mat.set_shader_parameter("mark", 0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Vorfeldflächen: doppelte gelbe Randlinie am Außenrand der zusammenhängenden Fläche (Kanten, an die eine
## andere Vorfeldfläche anschließt, bleiben frei).
func _apron_edges(km: Kit) -> void:
	var rects := []
	for a: Dictionary in game.items_of("vorfeldflaeche"):
		rects.append(a["rect"])
	for r: Rect2 in rects:
		var edges := [[r.position, Vector2(r.end.x, r.position.y), Vector2(0, -1)], [Vector2(r.position.x, r.end.y), r.end, Vector2(0, 1)],
			[r.position, Vector2(r.position.x, r.end.y), Vector2(-1, 0)], [Vector2(r.end.x, r.position.y), r.end, Vector2(1, 0)]]
		for e: Array in edges:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var out: Vector2 = e[2]
			var len := a.distance_to(b)
			var dir := (b - a) / maxf(len, 0.01)
			var t := 0.0
			var run_start := -1.0
			while t <= len + 0.01:
				var q := a + dir * minf(t, len) + out * 0.6
				var covered := false
				for r2: Rect2 in rects:
					if r2 != r and r2.has_point(q):
						covered = true
						break
				if not covered and run_start < 0.0:
					run_start = t
				if (covered or t >= len) and run_start >= 0.0:
					var t1 := minf(t, len)
					for inset: float in [0.3, 0.75]:
						var p0 := a + dir * run_start - out * inset
						var p1 := a + dir * t1 - out * inset
						_strip(km, PackedVector3Array([Vector3(p0.x, 0, p0.y), Vector3(p1.x, 0, p1.y)]), 0.075, MARK_YELLOW)
					run_start = -1.0
				t += 1.0


## Wendeplatten: Belag neben dem Pistenende und gelbe Wendespur (Knoten legt airside.gd an).
func _turn_pad_marks(km: Kit) -> void:
	var pk := Kit.new()
	var y := 0.035
	for pd: Dictionary in graph.pads:
		var thr: Vector3 = pd["thr"]
		var inward: Vector3 = pd["inward"]
		var lat: Vector3 = pd["side"]
		var hw := float(Catalog.LINES["piste"]["width"]) * 0.5
		var w := hw + 24.0
		var mid := thr + inward * 32.0 + lat * w * 0.5
		var r2 := w * 0.5 + 9.0
		var poly := PackedVector3Array()
		# weicher Übergang vom Pistenrand auf die Platte, dann der Bogen um den Wendekreis
		var s0 := thr + inward * 150.0 + lat * (hw - 2.0)
		var s1 := thr + inward * 32.0 + lat * (w + 9.0)
		for i in range(0, 10):
			var t := float(i) / 10.0
			var u := 1.0 - t
			var cc := thr + inward * 60.0 + lat * (w + 9.0)
			poly.append(s0 * (u * u) + cc * (2.0 * u * t) + s1 * (t * t))
		for i in range(0, 25):
			var ph := PI * float(i) / 24.0
			poly.append(mid + lat * r2 * cos(ph) - inward * r2 * sin(ph))
		poly.append(thr + inward * 32.0 - lat * 2.0)
		var c := thr + inward * 50.0 + lat * w * 0.55
		for n in range(poly.size()):
			var p0 := poly[n]
			var p1 := poly[(n + 1) % poly.size()]
			pk.tri(Vector3(c.x, y, c.z), Vector3(p0.x, y, p0.z), Vector3(p1.x, y, p1.z), Color(1, 1, 1), Vector3(c.x, y - 1.0, c.z))
		_strip(km, pd["pts"], 0.18, MARK_YELLOW)
		# Randlinie (gelb, doppelt) um den Bogen
		var edge := PackedVector3Array()
		for i in range(1, 24):
			var ph := PI * float(i) / 24.0
			edge.append(mid + lat * (r2 - 1.0) * cos(ph) - inward * (r2 - 1.0) * sin(ph))
		_strip(km, edge, 0.075, MARK_YELLOW)
	if pk.count == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "Wendeplatten"
	mi.mesh = pk.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/line.gdshader")
	mat.set_shader_parameter("base_color", Color(0.2, 0.2, 0.19))
	mat.set_shader_parameter("mark", 0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Schnittpunkt der beiden Rollweg-Mittellinien bei den Knoten a und b (sonst die Mitte zwischen ihnen).
func _junction_point(a: int, b: int) -> Vector3:
	var ta := _tangent(a)
	var tb := _tangent(b)
	var pa := graph.pos[a]
	var pb := graph.pos[b]
	var den := ta.x * tb.z - ta.z * tb.x
	if absf(den) < 0.15:
		return (pa + pb) * 0.5
	var w := pb - pa
	var t := (w.x * tb.z - w.z * tb.x) / den
	var j := pa + ta * t
	if j.distance_to((pa + pb) * 0.5) > 12.0:
		return (pa + pb) * 0.5
	return Vector3(j.x, 0, j.z)


func _tangent(i: int) -> Vector3:
	var nodes: Array = graph.line_nodes.get(graph.line_idx[i], [])
	var k := nodes.find(i)
	if k < 0:
		return Vector3(1, 0, 0)
	var p0 := graph.pos[nodes[maxi(k - 1, 0)]]
	var p1 := graph.pos[nodes[mini(k + 1, nodes.size() - 1)]]
	var t := Vector3(p1.x - p0.x, 0, p1.z - p0.z)
	return t.normalized() if t.length() > 0.01 else Vector3(1, 0, 0)


## Äste einer Kreuzung bei j: [Richtung, halbe Breite, geführt] je Rollweg und Richtung, in der er von j
## weggeht (aus den Stützpunkten des Wegs: 20 m vor und hinter der Kreuzung, falls er dort weitergeht).
func _junction_legs(j: Vector3, seeds: Array) -> Array:
	var legs := []
	var seen := []
	for sd: int in seeds:
		var li := graph.line_idx[sd]
		if li in seen:
			continue
		seen.append(li)
		var kind := String(game.lines[li]["kind"])
		var hw := float(Catalog.LINES[kind]["width"]) * 0.5
		var sm: PackedVector3Array = game.lines[li]["samples"]
		var best := 0
		var bd := INF
		for q in range(sm.size()):
			var dd := Vector2(sm[q].x - j.x, sm[q].z - j.z).length()
			if dd < bd:
				bd = dd
				best = q
		for dir: int in [-1, 1]:
			var run := 0.0
			var q := best
			while q + dir >= 0 and q + dir < sm.size() and run < 20.0:
				run += sm[q].distance_to(sm[q + dir])
				q += dir
			var d := sm[q] - j
			d.y = 0.0
			if run < 6.0 or d.length() < hw * 0.6:
				continue
			legs.append([d.normalized(), hw, graph.guided.has(li)])
	legs.sort_custom(func(a: Array, b: Array) -> bool: return atan2((a[0] as Vector3).z, (a[0] as Vector3).x) < atan2((b[0] as Vector3).z, (b[0] as Vector3).x))
	return legs


func _junction_patch(pk: Kit, km: Kit, j: Vector3, seeds: Array) -> void:
	var legs := _junction_legs(j, seeds)
	if OS.get_cmdline_user_args().has("--kreuzungen"):
		print("Kreuzung ", j, " Äste ", legs)
	if legs.size() < 2:
		return
	var max_hw := 0.0
	for lg: Array in legs:
		max_hw = maxf(max_hw, float(lg[1]))
	var reach := max_hw + 10.0      # so weit reicht die gemeinsame Fläche in jeden Ast
	var y := 0.052
	var ring := []                  # Umriss gegen den Uhrzeigersinn: je Ast zwei Kantenpunkte, dazwischen Ausrundungen
	var fillets := []
	for n in range(legs.size()):
		var d: Vector3 = legs[n][0]
		var hw := float(legs[n][1])
		var side := Vector3(-d.z, 0, d.x)    # links der Astrichtung (gegen den Uhrzeigersinn)
		ring.append(j + d * reach - side * hw)
		ring.append(j + d * reach + side * hw)
	var poly := PackedVector3Array()
	for n in range(legs.size()):
		var a: Vector3 = ring[n * 2]
		var b: Vector3 = ring[n * 2 + 1]
		poly.append(a)
		poly.append(b)
		# Ausrundung von der linken Kante dieses Asts zur rechten Kante des nächsten
		var dn: Vector3 = legs[n][0]
		var dm: Vector3 = legs[(n + 1) % legs.size()][0]
		var c: Vector3 = ring[((n + 1) % legs.size()) * 2]
		var ctrl := _edge_cross(b, dn, c, dm, j)
		var arc := PackedVector3Array()
		for t_i in range(1, 12):
			var t := float(t_i) / 12.0
			var u := 1.0 - t
			var q := b * (u * u) + ctrl * (2.0 * u * t) + c * (t * t)
			poly.append(q)
			arc.append(q)
		fillets.append([b, arc, c, bool(legs[n][2]) or bool(legs[(n + 1) % legs.size()][2])])
	for n in range(poly.size()):
		var p0 := poly[n]
		var p1 := poly[(n + 1) % poly.size()]
		pk.tri_raw(Vector3(j.x, y, j.z), Vector3(p1.x, y, p1.z), Vector3(p0.x, y, p0.z), Vector3.UP, Color(1, 1, 1))
	# doppelte gelbe Randlinie entlang der Ausrundungen (0,3 und 0,8 m innen)
	for fl: Array in fillets:
		var pts := PackedVector3Array([fl[0]])
		pts.append_array(fl[1])
		pts.append(fl[2])
		for inset: float in [0.3, 0.8]:
			var off := PackedVector3Array()
			for q2: Vector3 in pts:
				var to_j := j - q2
				to_j.y = 0.0
				off.append(q2 + to_j.normalized() * inset)
			_strip(km, off, 0.075, MARK_YELLOW)
	# Mittellinien: von jedem Ast in jeden anderen (keine Wende), nur auf Rollwegen ohne eigene Linien
	for a_i in range(legs.size()):
		for b_i in range(legs.size()):
			if a_i == b_i or bool(legs[a_i][2]) or bool(legs[b_i][2]):
				continue
			var da: Vector3 = legs[a_i][0]
			var db: Vector3 = legs[b_i][0]
			if (-da).dot(db) < -0.2 or b_i < a_i:
				continue
			var s0 := j + da * reach
			var s1 := j + db * reach
			var cl := PackedVector3Array()
			for t_i in range(25):
				var t := float(t_i) / 24.0
				var u := 1.0 - t
				cl.append(s0 * (u * u) + j * (2.0 * u * t) + s1 * (t * t))
			_strip(km, cl, 0.18, MARK_YELLOW)


## Schnittpunkt der Kante a (Richtung da, nach außen) mit der Kante b (Richtung db); sonst ein Punkt nahe j.
static func _edge_cross(a: Vector3, da: Vector3, b: Vector3, db: Vector3, j: Vector3) -> Vector3:
	var den := da.x * db.z - da.z * db.x
	if absf(den) < 0.05:
		return (a + b) * 0.5
	var w := b - a
	var t := (w.x * db.z - w.z * db.x) / den
	var q := a + da * t
	if q.distance_to(j) > a.distance_to(j) * 1.5:
		return (a + b) * 0.5
	return q


# ---------------------------------------------------------------- Stände

## Standnummern (am Boden und auf der Andockanzeige) und Einrolllinien vom Rollweg in den Stand.
func _stands(k: Kit, km: Kit, lamps: Dictionary) -> void:
	var list := game.stands().duplicate()
	list.sort_custom(_stand_order)
	stand_numbers = {}
	var num := 0
	for st: Dictionary in list:
		num += 1
		var node: Node3D = st["node"]
		var bas := node.global_transform.basis.orthonormalized()
		var fwd := bas.z
		var sp: Vector3 = st["pos"]
		var hd: float = (Catalog.ITEMS[st["id"]]["size"] as Vector2).y * 0.5
		var label := str(num)
		stand_numbers[node.get_instance_id()] = label
		st["number"] = label
		# Nummer am Boden auf schwarzem Grund, lesbar beim Einrollen
		var c := sp + bas * Vector3(-5.5, 0, -hd + 5.5)
		var tw := float(PixelFont.width(label)) * 0.55 + 1.2
		km.box(Vector3(-tw * 0.5, 0, -2.6), Vector3(tw * 0.5, 0.06, 2.6), SIGN_BLACK, Transform3D(Basis.looking_at(fwd, Vector3.UP), c))
		PixelFont.draw_ground(km, label, c + Vector3(0, 0.07, 0), fwd, 0.55, MARK_YELLOW)
		# Nummer auf der Andockanzeige (leuchtend)
		var disp := sp + bas * Vector3(0, 5.55, hd - 1.07)
		PixelFont.draw(_lk(lamps, AMBER), label, disp, bas * Vector3(1, 0, 0), Vector3.UP, -fwd, 0.13, AMBER)
		# Einrolllinien (nicht bei Markierung "eigene" oder "aus": dort zeichnet der Spieler die Linien selbst)
		if String((st.get("opts", {}) as Dictionary).get("markierung", "voll")) != "voll":
			continue
		var sid: int = graph.stand_node.get(node.get_instance_id(), -1)
		if sid < 0 or not graph.lead_of.has(sid):
			continue
		var lid: int = graph.lead_of[sid]
		var bnode := -1
		var bd := INF
		for nb: int in graph.adj[lid]:
			if nb == sid:
				continue
			var lateral := absf((graph.pos[nb] - sp).dot(bas.x))
			if lateral < bd:
				bd = lateral
				bnode = nb
		if bnode < 0:
			continue
		var nodes: Array = graph.line_nodes.get(graph.line_idx[bnode], [])
		var bi := nodes.find(bnode)
		if bi < 0:
			continue
		var p0 := graph.pos[nodes[maxi(bi - 1, 0)]]
		var p1 := graph.pos[nodes[mini(bi + 1, nodes.size() - 1)]]
		var tng := Vector3(p1.x - p0.x, 0, p1.z - p0.z).normalized()
		var bp := graph.pos[bnode]
		var end := sp + fwd * (hd - 11.0)
		var dout := (end - bp).normalized()
		var span := bp.distance_to(end)
		for sgn: float in [-1.0, 1.0]:
			var din := tng * sgn
			var theta := PI - acos(clampf((-din).dot(dout), -1.0, 1.0))
			var cut := minf(35.0 * tan(theta * 0.5), span * 0.6)
			var s1 := bp - din * cut
			var e := bp + dout * cut
			var pts := PackedVector3Array()
			for i in range(25):
				var tt := float(i) / 24.0
				pts.append(s1 * ((1.0 - tt) * (1.0 - tt)) + bp * (2.0 * (1.0 - tt) * tt) + e * (tt * tt))
			pts.append(end)
			_strip(km, pts, 0.18, MARK_YELLOW)


static func _stand_order(a: Dictionary, b: Dictionary) -> bool:
	var pa: Vector3 = a["pos"]
	var pb: Vector3 = b["pos"]
	return pa.x < pb.x if absf(pa.x - pb.x) > 1.0 else pa.z < pb.z


## Linie aus flachen Quadern entlang eines Polygonzugs.
func _strip(km: Kit, pts: PackedVector3Array, half: float, col: Color) -> void:
	for i in range(pts.size() - 1):
		var a := Vector3(pts[i].x, 0, pts[i].z)
		var b := Vector3(pts[i + 1].x, 0, pts[i + 1].z)
		var d := b - a
		var seg_len := d.length()
		if seg_len < 0.05:
			continue
		km.box(Vector3(-half, 0, -seg_len * 0.5 - half), Vector3(half, 0.066, seg_len * 0.5 + half), col,
			Transform3D(Basis.looking_at(d / seg_len, Vector3.UP), (a + b) * 0.5))
