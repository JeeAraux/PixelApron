extends Node3D
## Vorfelddienste: Pushback-Schlepper mit Einweiser, Treppenwagen und Vorfeldbusse für
## Positionen ohne Fluggastbrücke, dazu die Passagiere zwischen Terminal, Bus und Treppe.
##
## Ankunft:  Treppen docken an, Bus fährt vor, Passagiere steigen die Treppe hinab in den Bus,
##           der Bus fährt zur Vorfeld-Haltestelle, die Passagiere gehen durch das Bus-Gate ins Terminal.
## Abflug:   Bus holt die Passagiere am Bus-Gate ab, fährt zum Flugzeug, sie steigen die Treppe hinauf.

const Factory = preload("res://scripts/factory.gd")
const Models = preload("res://scripts/models.gd")
const Catalog = preload("res://scripts/catalog.gd")
const GameState = preload("res://scripts/game_state.gd")

const BUS_V := 8.0
const TUG_V := 4.5
const STAIR_V := 4.0
const WALK := 1.5
const PAX_PER_FIGURE := 8
const GSE_V := 6.0            # Bodenfahrzeuge auf dem Stand (m/s)
const BeltAnim = preload("res://scripts/belt_anim.gd")
const ServiceNet = preload("res://scripts/servicenet.gd")
const Landmarks = preload("res://scripts/landmarks.gd")
const FIRE_V := 11.0           # Löschfahrzeuge

var game: GameState
var terminal: Variant = null
var jobs: Dictionary = {}     # Flug-ID -> Auftrag (Schlepper, Treppen, Busse)
var walkers: Array = []       # Passagiere unter freiem Himmel
var vehicles: Array = []      # alle Bodenfahrzeuge, damit sie einander ausweichen
var flights_ref: Variant = null   # flights.gd: rollende Flugzeuge, vor denen Fahrzeuge warten
var linked_baggage := false   # Gepäckförderband zum Umschlag vorhanden: Abfertigung schneller
var net := ServiceNet.new()      # Betriebsstraßen und Vorfelder
var fire_net := ServiceNet.new() # dazu Rollwege (Feuerwehr)
var net_dirty := true
var clock := 0.0
var door_want: Dictionary = {}   # "Gebäude:Tor" -> Uhrzeit, bis zu der das Tor offen sein soll
var door_open: Dictionary = {}   # "Gebäude:Tor" -> 0 (zu) … 1 (offen)
var door_rec: Dictionary = {}    # "Gebäude:Tor" -> [Gebäude, Torindex]
var returning: Array = []        # Fahrzeuge auf dem Weg zurück in ihre Garage
var missions: Array = []         # Einsätze der Feuerwehr
var fire_t := 120.0              # bis zur nächsten Kontrollfahrt (Simulationssekunden)
var unconnected: Array = []      # Garagen ohne Anschluss an das Vorfeld (für Hinweise)


func setup(g: GameState) -> void:
	game = g
	game.network_changed.connect(func() -> void: net_dirty = true)
	game.items_changed.connect(func() -> void: net_dirty = true)


# ---------------------------------------------------------------- Fahrzeuge

## Kubische Kurve von a (Richtung ha) nach b (Ankunftsrichtung hb), dicht abgetastet.
static func curve(a: Vector3, ha: Vector3, b: Vector3, hb: Vector3) -> PackedVector3Array:
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var lk := maxf(d * 0.38, 2.0)
	var c1 := a + ha.normalized() * lk
	var c2 := b - hb.normalized() * lk
	var n := maxi(8, int(d / 0.8))
	var out := PackedVector3Array()
	for i in range(n + 1):
		var t := float(i) / float(n)
		var u := 1.0 - t
		out.append(a * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + b * (t * t * t))
	return out


func _vehicle(kind: String, at: Vector3, heading: Vector3, h: float = 0.0) -> Dictionary:
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = Models.stairs_mesh(h) if kind == "treppe" else Models.gse_mesh(kind)
	node.add_child(mi)
	if kind == "bus":
		# Schwenkschiebetüren je Seite: zwei Flügel, die beim Öffnen ausschwenken und auseinandergleiten
		var li := 0
		for sx: float in [-1.0, 1.0]:
			for z: float in Models.APRON_BUS_DOORS:
				for half: float in [-1.0, 1.0]:
					var leaf := MeshInstance3D.new()
					leaf.mesh = Models.bus_door_leaf()
					leaf.name = "Tuer%d" % li
					li += 1
					leaf.position = Vector3(sx * 1.5, 0.55, z + half * 0.45)
					leaf.set_meta("base", leaf.position)
					leaf.set_meta("slide", Vector3(sx * 0.14, 0, half * 0.5))
					mi.add_child(leaf)
	if kind != "treppe":
		var lp := Factory.light_pool(10.0, 2.0, 7.0, 0.45)
		lp.position = Vector3(0, 0.08, -_length_of(kind) * 0.5 - 0.2)
		node.add_child(lp)
	add_child(node)
	var v := {"node": node, "pts": PackedVector3Array(), "i": 0, "v": 0.0, "vmax": BUS_V, "rev": false,
		"pos": at, "heading": heading.normalized(), "moving": false, "len": _length_of(kind), "wait": 0.0, "kind": kind}
	vehicles.append(v)
	_put(v)
	return v


static func _length_of(kind: String) -> float:
	match kind:
		"bus":
			return 14.0
		"schlepper":
			return 8.5
		"treppe":
			return 8.5
		"tank":
			return 9.4
		"catering":
			return 8.6
		"bandlader":
			return 7.6
		"gpu":
			return 3.6
		"zug":
			return 3.0
	return 5.0


## Fahrzeug aus einem fertigen Knoten (zusammengesetzte Fahrzeuge mit beweglichen Teilen).
func _vehicle_from(node: Node3D, kind: String, at: Vector3, heading: Vector3) -> Dictionary:
	add_child(node)
	var v := {"node": node, "pts": PackedVector3Array(), "i": 0, "v": 0.0, "vmax": GSE_V, "rev": false,
		"pos": at, "heading": heading.normalized(), "moving": false, "len": _length_of(kind), "wait": 0.0, "kind": kind}
	vehicles.append(v)
	_put(v)
	return v


## Fahrt entlang einer Kurve starten. rev = rückwärts (Blickrichtung bleibt entgegen der Fahrt).
func _go(v: Dictionary, pts: PackedVector3Array, vmax: float, rev: bool = false) -> void:
	v["pts"] = pts
	v["i"] = 0
	v["vmax"] = vmax
	v["rev"] = rev
	v["moving"] = pts.size() > 1


func _drive_to(v: Dictionary, b: Vector3, hb: Vector3, vmax: float) -> void:
	_go(v, curve(v["pos"], v["heading"], b, hb), vmax)


func _move(v: Dictionary, sim: float) -> void:
	if v["kind"] == "bus" and _bus_doors(v, sim):
		return
	if not bool(v["moving"]):
		_settle(v, sim)
		return
	var pts: PackedVector3Array = v["pts"]
	var i: int = v["i"]
	var left := 0.0
	for j in range(i, pts.size() - 1):
		left += pts[j].distance_to(pts[j + 1])
	var vmax: float = v["vmax"]
	var want := minf(vmax, sqrt(2.0 * 1.2 * maxf(left - 0.2, 0.0)) + 0.3)
	# Abstand halten: vor anderen Fahrzeugen und rollenden Flugzeugen warten; steht der andere
	# länger, wird seitlich vorbeigefahren (erst ganz zuletzt notfalls hindurch)
	if _blocked(v):
		v["wait"] = float(v.get("wait", 0.0)) + sim
		if float(v["wait"]) > 4.0 and not bool(v.get("dodged", false)) and _dodge(v):
			v["dodged"] = true
			v["wait"] = 0.0
			pts = v["pts"]
			i = v["i"]
		if float(v["wait"]) < 14.0:
			want = 0.0
	else:
		v["wait"] = 0.0
		if bool(v.get("dodged", false)) and int(v["i"]) > int(v.get("dodge_end", 0)):
			v["dodged"] = false
	var sp := move_toward(float(v["v"]), want, (3.0 if want < float(v["v"]) else 1.5) * sim)
	# Beschleunigung für das Nicken der Karosserie (bremsen: Nase taucht ein)
	v["acc"] = lerpf(float(v.get("acc", 0.0)), (sp - float(v["v"])) / maxf(sim, 0.001), clampf(sim * 4.0, 0.0, 1.0))
	v["v"] = sp
	var budget := sp * sim
	var pos: Vector3 = v["pos"]
	while budget > 0.0 and i < pts.size() - 1:
		var target := pts[i + 1]
		var d := pos.distance_to(target)
		if d <= budget:
			budget -= d
			pos = target
			i += 1
		else:
			pos += (target - pos) / d * budget
			budget = 0.0
		var seg := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i, 0)]
		seg.y = 0.0
		if seg.length() > 0.05:
			var want_h := -seg.normalized() if bool(v["rev"]) else seg.normalized()
			if v.has("cars"):
				# Schlepper mit Anhängern dreht nicht auf der Stelle (sonst knicken die Wagen ein)
				var cur_h: Vector3 = v["heading"]
				var ang := cur_h.signed_angle_to(want_h, Vector3.UP)
				var mx := 1.4 * sim
				v["heading"] = cur_h.rotated(Vector3.UP, clampf(ang, -mx, mx)).normalized()
			else:
				v["heading"] = want_h
	v["pos"] = pos
	v["i"] = i
	if i >= pts.size() - 1:
		v["moving"] = false
		v["v"] = 0.0
	if v.has("trail"):
		_trail_add(v)
	_put(v)


## Ausweichen: die nächsten Meter der Fahrt seitlich versetzen (zur Seite, auf der mehr Platz ist).
func _dodge(v: Dictionary) -> bool:
	var pts: PackedVector3Array = v["pts"]
	var i: int = v["i"]
	if i >= pts.size() - 2 or bool(v.get("rev", false)):
		return false
	var h: Vector3 = v["heading"]
	var side := h.cross(Vector3.UP).normalized()
	var best_side := 0.0
	for sgn: float in [1.0, -1.0]:
		var probe: Vector3 = (v["pos"] as Vector3) + side * sgn * 4.5 + h * 8.0
		var free := true
		for o: Dictionary in vehicles:
			if is_same(o, v):
				continue
			for q: Vector3 in _points_of(o):
				if Vector2(q.x - probe.x, q.z - probe.z).length() < 4.0:
					free = false
		if free:
			best_side = sgn
			break
	if best_side == 0.0:
		return false
	var out := PackedVector3Array()
	for j in range(pts.size()):
		out.append(pts[j])
	var run := 0.0
	var j0 := i + 1
	var end := j0
	for j in range(j0, pts.size() - 1):
		run += pts[j].distance_to(pts[j - 1])
		# hinein- und herausschwenken über je 8 m, dazwischen 4,5 m versetzt
		var f := clampf(run / 8.0, 0.0, 1.0) * clampf((30.0 - run) / 8.0, 0.0, 1.0)
		out[j] = pts[j] + side * best_side * 4.5 * smoothstep(0.0, 1.0, f)
		end = j
		if run > 30.0:
			break
	v["pts"] = out
	v["dodge_end"] = end
	return true


## Steht vor dem Fahrzeug (in Fahrtrichtung) ein anderes Fahrzeug oder rollt ein Flugzeug heran?
func _blocked(v: Dictionary) -> bool:
	var pos: Vector3 = v["pos"]
	var h: Vector3 = v["heading"]
	var dirm := -h if bool(v["rev"]) else h
	# Blickrichtung: zum Wegpunkt etwa 8 m voraus (nach einem Ausweichschwenk zeigt sie am Hindernis vorbei)
	var pts: PackedVector3Array = v.get("pts", PackedVector3Array())
	var i0: int = v.get("i", 0)
	if bool(v.get("moving", false)) and i0 < pts.size() - 1:
		var run := 0.0
		var j := i0 + 1
		while j < pts.size() - 1 and run + pts[j].distance_to(pts[j - 1]) < 8.0:
			run += pts[j].distance_to(pts[j - 1])
			j += 1
		var ahead_pt := pts[j] - pos
		ahead_pt.y = 0.0
		if ahead_pt.length() > 1.0:
			dirm = ahead_pt.normalized()
	dirm.y = 0.0
	if dirm.length_squared() < 0.001:
		return false
	dirm = dirm.normalized()
	var side := dirm.cross(Vector3.UP)
	var half := float(v.get("len", 5.0)) * 0.5
	var reach := half + 2.5 + float(v["v"]) * 1.1
	for o: Dictionary in vehicles:
		if is_same(o, v) or bool(o.get("ghost", false)):
			continue
		for q: Vector3 in _points_of(o):
			var d := q - pos
			d.y = 0.0
			var ahead := d.dot(dirm)
			if ahead < half * 0.3 or ahead > reach + float(o.get("len", 5.0)) * 0.5:
				continue
			if absf(d.dot(side)) < 2.6:
				return true
	if flights_ref != null:
		for pl: Dictionary in flights_ref.planes:
			if int(pl["id"]) == int(v.get("flight", -1)):
				continue
			var st: String = pl["state"]
			if not (st in ["rollt_ein", "rollt_aus", "pushback"]):
				continue
			if st != "pushback" and float(pl["speed"]) < 0.3:
				continue
			var d := (pl["pos"] as Vector3) - pos
			d.y = 0.0
			if d.length() < 42.0 and d.dot(dirm) > -5.0:
				return true
	return false


## Mittelpunkte eines Fahrzeugs (beim Gepäckzug auch die Wagen).
static func _points_of(o: Dictionary) -> Array:
	var out := [o["pos"]]
	for c: Variant in o.get("car_pos", []):
		out.append(c)
	return out


func _put(v: Dictionary) -> void:
	var node: Node3D = v["node"]
	if not is_instance_valid(node):
		return
	var pos: Vector3 = v["pos"]
	node.position = Vector3(pos.x, 0.0, pos.z)
	var h: Vector3 = v["heading"]
	if h.length_squared() > 0.001:
		# Karosserie nickt beim Anfahren und Bremsen und neigt sich in Kurven ein wenig
		var turn := 0.0
		if v.has("last_h"):
			turn = (v["last_h"] as Vector3).cross(h).y
		v["last_h"] = h
		v["roll"] = lerpf(float(v.get("roll", 0.0)), clampf(turn * float(v["v"]) * 6.0, -0.05, 0.05), 0.15)
		var pitch := clampf(float(v.get("acc", 0.0)) * 0.012, -0.03, 0.03)
		if bool(v.get("rev", false)):
			pitch = -pitch
		var body := node.get_node_or_null("Body") as Node3D
		node.basis = Basis.looking_at(h, Vector3.UP)
		if body != null:
			body.rotation = Vector3(pitch, 0, float(v["roll"]))
	if v.has("cars"):
		_place_cars(v)


## Stehendes Fahrzeug: Nicken und Neigung klingen aus.
func _settle(v: Dictionary, sim: float) -> void:
	if absf(float(v.get("acc", 0.0))) < 0.01 and absf(float(v.get("roll", 0.0))) < 0.001:
		return
	v["acc"] = move_toward(float(v.get("acc", 0.0)), 0.0, sim * 6.0)
	v["roll"] = move_toward(float(v.get("roll", 0.0)), 0.0, sim * 0.2)
	_put(v)


## Bustüren: öffnen, wenn der Bus eine Weile steht, schließen vor der Abfahrt (der Bus wartet so lange).
## Rückgabe true = Bus muss noch auf die Türen warten.
func _bus_doors(v: Dictionary, sim: float) -> bool:
	var moving := bool(v["moving"])
	v["still"] = 0.0 if moving else float(v.get("still", 0.0)) + sim
	var want := 1.0 if (not moving and float(v["still"]) > 1.2) else 0.0
	var cur := move_toward(float(v.get("door", 0.0)), want, sim * 1.1)
	if not is_equal_approx(cur, float(v.get("door", 0.0))):
		v["door"] = cur
		Factory.set_bus_doors(v["node"], cur)
	return moving and cur > 0.01


func _free(v: Variant) -> void:
	if v is Dictionary:
		vehicles.erase(v)
		var vd: Dictionary = v
		if is_instance_valid(vd.get("node")):
			(vd["node"] as Node).queue_free()
		for c: Variant in vd.get("cars", []):
			if is_instance_valid(c):
				(c as Node).queue_free()


func _job(p: Dictionary) -> Dictionary:
	var id: int = p["id"]
	if not jobs.has(id):
		jobs[id] = {"flight": p}
	return jobs[id]


## Punkt in Flugzeugkoordinaten (vorn = -Z, links = -X) in Weltkoordinaten.
static func plane_point(p: Dictionary, local: Vector3) -> Vector3:
	var h: Vector3 = p["heading"]
	h.y = 0.0
	var b := Basis.looking_at(h.normalized(), Vector3.UP)
	return (p["pos"] as Vector3) + b * local


static func plane_dir(p: Dictionary, local: Vector3) -> Vector3:
	var h: Vector3 = p["heading"]
	h.y = 0.0
	return Basis.looking_at(h.normalized(), Vector3.UP) * local


# ---------------------------------------------------------------- Pushback-Schlepper

## Abstellplatz der Bodenfahrzeuge eines Stands (vordere Ecke, neben der Flügelspitze).
static func stand_home(p: Dictionary, side: float, front: bool = true) -> Vector3:
	var st: Dictionary = p["stand"]
	if st.is_empty() or not is_instance_valid(st.get("node")):
		return (p["pos"] as Vector3) + Vector3(30, 0, 0)
	var node: Node3D = st["node"]
	var b := node.global_transform.basis
	return (st["pos"] as Vector3) + b.x.normalized() * side * 21.0 + b.z.normalized() * (19.0 if front else -21.0)


## Schlepper fährt vor die Nase und nimmt das Bugrad auf. ng = Abstand Bugrad zur Flugzeugmitte.
func call_tug(p: Dictionary, ng: float) -> void:
	var j := _job(p)
	if j.has("tug"):
		return
	var h: Vector3 = p["heading"]
	var nose: Vector3 = (p["pos"] as Vector3) + h * ng
	var home := stand_home(p, -1.0)
	var t := _vehicle("schlepper", home, (nose - home).normalized())
	var dock := nose + h * 2.8
	var pts := curve(home, (nose + h * 16.0 - home).normalized(), nose + h * 14.0, -h)
	pts.append_array(curve(nose + h * 14.0, -h, dock, -h).slice(1))
	_go(t, pts, TUG_V)
	j["tug"] = t
	# Einweiser mit Headset geht zur Nase
	var w := Factory.make_staff(Color(0.95, 0.85, 0.1), Color(0.15, 0.18, 0.28), 1, true)
	add_child(w)
	w.position = home + h * 2.0
	j["walker"] = {"node": w, "pos": home + h * 2.0, "walk": 0.0}


func tug_ready(p: Dictionary) -> bool:
	var t: Variant = _job(p).get("tug")
	return t is Dictionary and not bool((t as Dictionary)["moving"])


## Während des Pushbacks: Schlepper hält das Bugrad, Einweiser geht neben der Nase mit.
func tug_follow(p: Dictionary, nose: Vector3, h: Vector3, sim: float) -> void:
	var j := _job(p)
	var t: Variant = j.get("tug")
	if t is Dictionary:
		var td: Dictionary = t
		td["pos"] = nose + h * 2.8
		td["heading"] = -h
		td["moving"] = false
		_put(td)
	var w: Variant = j.get("walker")
	if w is Dictionary:
		var wd: Dictionary = w
		var side := h.cross(Vector3.UP).normalized()
		var goal := nose + side * 5.0 + h * 1.5
		_walk_to(wd, goal, sim, 2.2)


## Schlepper koppelt ab, setzt zurück und fährt zum Stand zurück.
func tug_leave(p: Dictionary) -> void:
	var j := _job(p)
	var t: Variant = j.get("tug")
	if not (t is Dictionary):
		return
	var td: Dictionary = t
	var h: Vector3 = -(td["heading"] as Vector3)   # Flugzeugrichtung
	var back: Vector3 = (td["pos"] as Vector3) + h * 7.0
	var pts := PackedVector3Array([td["pos"], back])
	var side := h.cross(Vector3.UP).normalized()
	var home := back + side * 20.0 - h * 4.0
	if (p.get("stand", {}) as Dictionary).has("pos"):
		home = (p["stand"]["pos"] as Vector3)
	var c := curve(back, side, home, (home - back).normalized())
	_go(td, pts, 1.5, true)
	td["then"] = c
	td["despawn"] = true
	j["tug_gone"] = td
	j.erase("tug")
	var w: Variant = j.get("walker")
	if w is Dictionary:
		(w as Dictionary)["despawn_at"] = back
	j.erase("walker")
	j["walker_gone"] = w


func _walk_to(wd: Dictionary, goal: Vector3, sim: float, speed: float) -> bool:
	var node: Node3D = wd["node"]
	if not is_instance_valid(node):
		return true
	var pos: Vector3 = wd["pos"]
	var to := goal - pos
	to.y = 0.0
	var d := to.length()
	var step := speed * sim
	var done := d <= step
	if done:
		pos = Vector3(goal.x, pos.y, goal.z)
	else:
		pos += to / d * step
	wd["walk"] = float(wd.get("walk", 0.0)) + minf(d, step)
	wd["pos"] = pos
	node.position = pos
	if d > 0.05:
		Factory.walk(node, float(wd["walk"]), to, sim)
	else:
		Factory.set_pose(node, 0)
	return done


# ---------------------------------------------------------------- Außenpositionen: Treppen und Busse

## Flugzeug steht auf einer Position ohne Brücke: Treppen und Ankunftsbus rücken an.
## stop = [Haltepunkt, Richtung] am Terminal, door = Punkt vor dem Bus-Gate (außen).
func remote_arrive(p: Dictionary, stop: Array, door: Vector3, with_arrivals: bool) -> void:
	var j := _job(p)
	j["stop"] = stop
	j["door"] = door
	j["boarded"] = false
	j["phase"] = "ankunft" if with_arrivals else "warten"
	var s: Dictionary = Models.SPECS.get(p["kind"], Models.SPECS["a320"])
	var r: float = s["r"]
	var sill: float = float(s["cy"]) - 0.85
	var stairs := []
	var doors: Array = s["doors"]
	for k in range(2):
		var dz: float = doors[k]
		var target := plane_point(p, Vector3(-(r + 0.25 + 4.4), 0, dz))
		var face := plane_dir(p, Vector3(1, 0, 0))
		var home := stand_home(p, 1.0, k == 0)
		var v := _vehicle("treppe", home, (target - home).normalized(), sill)
		_go(v, curve(home, (target - home).normalized(), target, face), STAIR_V)
		v["door"] = plane_point(p, Vector3(-(r - 0.2), sill, dz))
		v["top"] = plane_point(p, Vector3(-(r + 1.6), sill, dz))
		v["bottom"] = plane_point(p, Vector3(-(r + 6.4), 0, dz))
		v["foot"] = plane_point(p, Vector3(-(r + 8.0), 0, dz + 1.0))
		stairs.append(v)
	j["stairs"] = stairs
	j["n"] = ceili(float(Catalog.PLANES[p["kind"]]["pax"]) / float(PAX_PER_FIGURE))
	if with_arrivals:
		j["bus"] = _bus_to_plane(p, stop)
		j["in_bus"] = 0
		j["out"] = 0


func _bus_park(p: Dictionary) -> Array:
	var s: Dictionary = Models.SPECS.get(p["kind"], Models.SPECS["a320"])
	var doors: Array = s["doors"]
	return [plane_point(p, Vector3(-(float(s["r"]) + 8.5), 0, float(doors[0]) + 1.2)), plane_dir(p, Vector3(0, 0, 1))]


func _bus_to_plane(p: Dictionary, stop: Array) -> Dictionary:
	var at: Vector3 = stop[0]
	var dir: Vector3 = stop[1]
	var bus := _vehicle("bus", at, dir)
	var park := _bus_park(p)
	_go(bus, curve(at, dir, park[0], park[1]), BUS_V)
	return bus


## Abflug: zweiter Bus holt die Passagiere am Bus-Gate ab.
func remote_board(p: Dictionary) -> void:
	var j := _job(p)
	if j.has("dep_bus") or not j.has("stop"):
		return
	var stop: Array = j["stop"]
	var bus := _vehicle("bus", (stop[0] as Vector3) - (stop[1] as Vector3) * 30.0, stop[1])
	_go(bus, PackedVector3Array([bus["pos"], stop[0]]), BUS_V)
	j["dep_bus"] = bus
	j["dep_in"] = 0
	j["dep_out"] = 0
	j["dep_wanted"] = 0
	j["dep_called"] = false


func remote_done(p: Dictionary) -> bool:
	var j: Dictionary = jobs.get(int(p["id"]), {})
	return j.is_empty() or not j.has("stairs") or bool(j.get("boarded", false))


func is_remote(p: Dictionary) -> bool:
	return (jobs.get(int(p["id"]), {}) as Dictionary).has("stairs")


## Treppen und Busse fahren ab (Pushback beginnt).
func remote_leave(p: Dictionary) -> void:
	if not jobs.has(int(p["id"])):
		return
	var j: Dictionary = jobs[int(p["id"])]
	if not j.has("leaving"):
		j["leaving"] = []
	var leaving: Array = j["leaving"]
	var si := 0
	for v: Dictionary in j.get("stairs", []):
		var home := stand_home(p, 1.0, si == 0)
		si += 1
		var back: Vector3 = (v["pos"] as Vector3) - (v["heading"] as Vector3) * 6.0
		var pts := PackedVector3Array([v["pos"], back])
		_go(v, pts, 1.5, true)
		v["then"] = curve(back, -(v["heading"] as Vector3), home, (home - back).normalized())
		leaving.append(v)
	j.erase("stairs")
	for key: String in ["bus", "dep_bus"]:
		if j.has(key):
			var bus: Dictionary = j[key]
			var away: Vector3 = (bus["pos"] as Vector3) + (bus["heading"] as Vector3) * 40.0
			_go(bus, PackedVector3Array([bus["pos"], away]), BUS_V)
			leaving.append(bus)
			j.erase(key)


## Alles rund um diesen Flug sofort entfernen.
func release(p: Dictionary) -> void:
	var id: int = p["id"]
	if not jobs.has(id):
		return
	var j: Dictionary = jobs[id]
	for key: String in ["tug", "tug_gone", "bus", "dep_bus"]:
		_free(j.get(key))
	for key: String in ["walker", "walker_gone"]:
		var w: Variant = j.get(key)
		if w is Dictionary and is_instance_valid((w as Dictionary)["node"]):
			((w as Dictionary)["node"] as Node).queue_free()
	for v: Variant in j.get("stairs", []) + j.get("leaving", []):
		_free(v)
	for sv: Dictionary in j.get("svc", []):
		_undock(sv)
		var sv_v: Variant = sv.get("v")
		if sv_v is Dictionary and is_instance_valid((sv_v as Dictionary).get("node")):
			_send_home(sv_v, String(sv["kind"]))
		else:
			_free(sv_v)
		for c: Variant in sv.get("extra", []):
			if is_instance_valid(c):
				(c as Node).queue_free()
	for pr: Array in j.get("props", []):
		if is_instance_valid(pr[0]):
			(pr[0] as Node).queue_free()
	for wk: Dictionary in walkers.duplicate():
		if int(wk["flight"]) == id:
			_drop_walker(wk)
	jobs.erase(id)


func clear() -> void:
	for id: int in jobs.keys():
		release(jobs[id]["flight"])
	for wk: Dictionary in walkers.duplicate():
		_drop_walker(wk)
	jobs.clear()
	for v: Dictionary in returning:
		_free(v)
	returning.clear()
	for v: Dictionary in sorting:
		_free(v)
	sorting.clear()
	for m: Dictionary in missions:
		_free(m.get("v"))
		var parked: Variant = m.get("parked")
		if is_instance_valid(parked):
			(parked as Node3D).visible = true
	missions.clear()
	door_want.clear()
	chute_users.clear()


# ---------------------------------------------------------------- Passagiere draußen

func _walker(flight: int, pts: PackedVector3Array, action: String, data: Variant = null) -> void:
	var node := Factory.make_person(Factory.SHIRTS[randi() % Factory.SHIRTS.size()])
	node.position = pts[0]
	add_child(node)
	walkers.append({"node": node, "flight": flight, "pts": pts, "i": 0, "pos": pts[0], "walk": 0.0,
		"action": action, "data": data, "delay": 0.0})


func _drop_walker(wk: Dictionary) -> void:
	if is_instance_valid(wk["node"]):
		(wk["node"] as Node).queue_free()
	walkers.erase(wk)


func _step_walker(wk: Dictionary, sim: float) -> bool:
	if float(wk["delay"]) > 0.0:
		wk["delay"] = float(wk["delay"]) - sim
		(wk["node"] as Node3D).visible = false
		return false
	var node: Node3D = wk["node"]
	node.visible = true
	var pts: PackedVector3Array = wk["pts"]
	var i: int = wk["i"]
	var pos: Vector3 = wk["pos"]
	var budget := WALK * sim
	var look := Vector3.ZERO
	while budget > 0.0 and i < pts.size() - 1:
		var target := pts[i + 1]
		var d := pos.distance_to(target)
		look = target - pos
		if d <= budget:
			budget -= d
			pos = target
			i += 1
		else:
			pos += look / d * budget
			budget = 0.0
	wk["walk"] = float(wk["walk"]) + WALK * sim - budget
	wk["pos"] = pos
	wk["i"] = i
	node.position = pos
	look.y = 0.0
	Factory.walk(node, float(wk["walk"]), look, sim)
	return i >= pts.size() - 1


## Ein abfliegender Passagier hat im Terminal das Bus-Gate erreicht (Rückruf aus terminal.gd).
func pax_at_door(flight: int) -> void:
	if not jobs.has(flight):
		return
	var j: Dictionary = jobs[flight]
	var bus: Variant = j.get("dep_bus")
	if not (bus is Dictionary):
		return
	var door: Vector3 = j["door"]
	var bd: Dictionary = bus
	var ent := _bus_entry(bd, door)
	var entry: Vector3 = ent[0]
	_walker(flight, PackedVector3Array([door, door.lerp(entry, 0.5) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), entry, ent[1]]), "in_dep_bus")
	j["dep_out"] = int(j["dep_out"]) + 1


## Eine der drei Bustüren auf der Seite, die ref zugewandt ist.
func _bus_door(bus: Dictionary, ref: Vector3) -> Vector3:
	return _bus_entry(bus, ref)[0]


## Tür eines Busses auf der Seite zu ref: [Punkt vor der Tür, Punkt im Bus hinter der Tür].
func _bus_entry(bus: Dictionary, ref: Vector3) -> Array:
	var h: Vector3 = bus["heading"]
	var side := h.cross(Vector3.UP).normalized()
	var z: float = [-4.6, 0.0, 4.6][randi() % 3]
	var c: Vector3 = (bus["pos"] as Vector3) - h * z
	var sgn := 1.0 if (c + side * 1.9).distance_to(ref) < (c - side * 1.9).distance_to(ref) else -1.0
	return [c + side * sgn * 2.1, c + side * sgn * 0.6 + Vector3(0, 0.35, 0)]


## Eingestiegen: die Figur fährt im Bus mit (steht hinter den Scheiben) statt zu verschwinden.
func _ride(wk: Dictionary, bus: Variant) -> bool:
	if not (bus is Dictionary) or not is_instance_valid((bus as Dictionary).get("node")):
		return false
	var bd: Dictionary = bus
	var body := (bd["node"] as Node3D).get_node_or_null("Body") as Node3D
	if body == null:
		return false
	var node: Node3D = wk["node"]
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	body.add_child(node)
	var riders: Array = bd.get("riders", [])
	var k := riders.size()
	node.position = Vector3(-0.9 + float(k % 3) * 0.9 + randf_range(-0.15, 0.15), 0.35, -5.6 + float((k / 3) % 12) * 0.95)
	node.rotation = Vector3(0, randf() * TAU, 0)
	Factory.set_pose(node, 0)
	riders.append(node)
	bd["riders"] = riders
	walkers.erase(wk)
	return true


## Fahrgäste steigen aus: Mitfahrer verschwinden, dafür laufen sie durch die Türen hinaus.
func _clear_riders(bus: Dictionary) -> void:
	for r: Variant in bus.get("riders", []):
		if is_instance_valid(r):
			(r as Node).queue_free()
	bus["riders"] = []


var sorting: Array = []          # Gepäckzüge an der Sortierung


func step(sim: float) -> void:
	clock += sim
	if net_dirty:
		_rebuild_net()
	_step_returning(sim)
	_step_sorting(sim)
	_fire_tick(sim)
	_animate_doors(sim)
	for id: int in jobs.keys():
		var j: Dictionary = jobs[id]
		_step_job(j, sim)
	for wk: Dictionary in walkers.duplicate():
		if not _step_walker(wk, sim):
			continue
		var j: Dictionary = jobs.get(int(wk["flight"]), {})
		match String(wk["action"]):
			"in_bus":
				if not j.is_empty():
					j["in_bus"] = int(j["in_bus"]) + 1
					if _ride(wk, j.get("bus")):
						continue
			"to_terminal":
				if terminal != null and not j.is_empty():
					terminal.bus_arrivals(j["flight"], 1)
			"in_dep_bus":
				if not j.is_empty():
					j["dep_in"] = int(j["dep_in"]) + 1
					if _ride(wk, j.get("dep_bus")):
						continue
			"on_board":
				if not j.is_empty():
					j["on_board"] = int(j.get("on_board", 0)) + 1
		_drop_walker(wk)


func _step_job(j: Dictionary, sim: float) -> void:
	var p: Dictionary = j["flight"]
	for sv: Dictionary in j.get("svc", []):
		if String(sv["phase"]) != "anreise":
			continue
		var v: Variant = sv.get("v")
		if not (v is Dictionary):
			sv["phase"] = "warten"
			continue
		var vd: Dictionary = v
		if _door_step(vd):
			_move(vd, sim)
		if not vd.has("await_door") and not bool(vd["moving"]):
			if vd.has("load_then"):
				# an der Sortierung: Koffer aufladen, dann weiter zum Stand. Jeder Zug braucht eine
				# freie Make-up-Rutsche; Transferkoffer aus der Sortierung beschleunigen das Laden.
				var lt: Dictionary = vd["load_then"]
				if not _chute_free(vd):
					lt["wait"] = float(lt.get("wait", 0.0)) + sim
					continue
				var gd: Dictionary = vd.get("load_door", {})
				if not gd.is_empty() and is_instance_valid(gd.get("node")):
					var dk := _door_key(gd, 0)
					door_rec[dk] = [gd, 0]
					door_want[dk] = maxf(float(door_want.get(dk, 0.0)), clock + 2.0)
				var rate := 1.6
				if terminal != null and int(terminal.transfer_pool) > 0:
					rate = 2.4
				lt["t"] = float(lt["t"]) + sim
				var before := int(vd.get("bags", 0))
				_set_bags(vd, mini(24, int(float(lt["t"]) * rate)))
				var added := int(vd["bags"]) - before
				if added > 0 and terminal != null:
					terminal.take_transfer(added)
					if not gd.is_empty() and is_instance_valid(gd.get("node")):
						for k in range(added):
							terminal.gate_bag(gd["node"], true)
				if int(vd["bags"]) >= 24:
					_go(vd, lt["pts"], GSE_V * 1.4)
					vd.erase("load_then")
					vd.erase("load_door")
					chute_users.erase(vd)
				continue
			sv["phase"] = "bereit"
	if bool(j.get("turn_over", false)):
		for sv: Dictionary in j.get("svc", []):
			if String(sv["phase"]) == "ab":
				_service(p, sv, 2.0, sim)
	for key: String in ["tug", "bus", "dep_bus"]:
		var v: Variant = j.get(key)
		if v is Dictionary:
			_move(v, sim)
	for v: Dictionary in j.get("stairs", []):
		_move(v, sim)
	# abfahrende Fahrzeuge
	var gone := []
	for v: Dictionary in j.get("leaving", []):
		_move(v, sim)
		if not bool(v["moving"]):
			if v.has("then"):
				_go(v, v["then"], STAIR_V)
				v.erase("then")
			else:
				gone.append(v)
	for v: Dictionary in gone:
		(j["leaving"] as Array).erase(v)
		_send_home(v, String(v.get("kind", "")))
	var tg: Variant = j.get("tug_gone")
	if tg is Dictionary:
		var td: Dictionary = tg
		_move(td, sim)
		if not bool(td["moving"]):
			if td.has("then"):
				_go(td, td["then"], TUG_V)
				td.erase("then")
			else:
				j.erase("tug_gone")
				_send_home(td, "schlepper")
	var wg: Variant = j.get("walker_gone")
	if wg is Dictionary:
		var wd: Dictionary = wg
		if _walk_to(wd, wd.get("despawn_at", wd["pos"]), sim, 1.8):
			if is_instance_valid(wd["node"]):
				(wd["node"] as Node).queue_free()
			j.erase("walker_gone")
	var wk: Variant = j.get("walker")
	if wk is Dictionary and j.has("tug"):
		var t: Dictionary = j["tug"]
		if bool(t["moving"]):
			var wd: Dictionary = wk
			var side := (t["heading"] as Vector3).cross(Vector3.UP).normalized()
			_walk_to(wd, (t["pos"] as Vector3) + side * 3.5, sim, 2.0)
	if not j.has("stairs"):
		return
	var stairs: Array = j["stairs"]
	var docked := true
	for v: Dictionary in stairs:
		docked = docked and not bool(v["moving"])
	var n: int = j["n"]
	# Ankunft: aussteigen, sobald Treppen und Bus stehen
	if j.get("phase", "") == "ankunft":
		var bus: Dictionary = j["bus"]
		if docked and not bool(bus["moving"]) and not bool(j.get("unloading", false)):
			j["unloading"] = true
			for i in range(n):
				var v: Dictionary = stairs[i % stairs.size()]
				var foot: Vector3 = v["foot"]
				var ent := _bus_entry(bus, foot)
				var entry: Vector3 = ent[0]
				_walker(int(p["id"]), PackedVector3Array([v["door"], v["top"], v["bottom"], foot, foot.lerp(entry, 0.5), entry, ent[1]]), "in_bus")
				walkers[walkers.size() - 1]["delay"] = float(i / stairs.size()) * 1.1 + 0.4
		if bool(j.get("unloading", false)) and int(j["in_bus"]) >= n and not bool(j.get("bus_back", false)):
			j["bus_back"] = true
			var stop: Array = j["stop"]
			_go(bus, curve(bus["pos"], bus["heading"], stop[0], stop[1]), BUS_V)
		if bool(j.get("bus_back", false)) and not bool(bus["moving"]) and not bool(j.get("bus_empty", false)):
			j["bus_empty"] = true
			var door2: Vector3 = j["door"]
			_clear_riders(bus)
			for i in range(n):
				var ex := _bus_entry(bus, door2)
				var exitp: Vector3 = ex[0]
				_walker(int(p["id"]), PackedVector3Array([ex[1], exitp, exitp.lerp(door2, 0.5) + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), door2]), "to_terminal")
				walkers[walkers.size() - 1]["delay"] = float(i) * 0.35
			var away: Vector3 = (bus["pos"] as Vector3) + (bus["heading"] as Vector3) * 45.0
			bus["after"] = away
		if bool(j.get("bus_empty", false)) and bus.has("after"):
			var any := false
			for w: Dictionary in walkers:
				if int(w["flight"]) == int(p["id"]) and String(w["action"]) == "to_terminal" and int(w["i"]) == 0:
					any = true
			if not any:
				_go(bus, PackedVector3Array([bus["pos"], bus["after"]]), BUS_V)
				bus.erase("after")
				bus["despawn"] = true
				if not j.has("leaving"):
					j["leaving"] = []
				(j["leaving"] as Array).append(bus)
				j.erase("bus")
				j["phase"] = "warten"
	# Abflug: Bus wartet an der Haltestelle, Passagiere kommen aus dem Terminal
	if j.has("dep_bus"):
		var db: Dictionary = j["dep_bus"]
		if not bool(db["moving"]) and not bool(j["dep_called"]):
			j["dep_called"] = true
			var wanted := 0
			if terminal != null:
				wanted = terminal.board_bus(p)
			j["dep_wanted"] = wanted
		if bool(j["dep_called"]) and not bool(j.get("dep_driving", false)) and int(j["dep_in"]) >= int(j["dep_wanted"]):
			var waiting := false
			if terminal != null:
				waiting = terminal.bus_pax_pending(p)
			if not waiting:
				j["dep_driving"] = true
				var park := _bus_park(p)
				_go(db, curve(db["pos"], db["heading"], park[0], park[1]), BUS_V)
		if bool(j.get("dep_driving", false)) and not bool(db["moving"]) and docked and not bool(j.get("dep_unload", false)):
			j["dep_unload"] = true
			var cnt: int = j["dep_in"]
			j["dep_total"] = cnt
			j["on_board"] = 0
			_clear_riders(db)
			for i in range(cnt):
				var v: Dictionary = stairs[i % stairs.size()]
				var foot: Vector3 = v["foot"]
				var ex := _bus_entry(db, foot)
				var exitp: Vector3 = ex[0]
				_walker(int(p["id"]), PackedVector3Array([ex[1], exitp, exitp.lerp(foot, 0.5), foot, v["bottom"], v["top"], v["door"]]), "on_board")
				walkers[walkers.size() - 1]["delay"] = float(i) * 0.4
		if bool(j.get("dep_unload", false)) and int(j.get("on_board", 0)) >= int(j.get("dep_total", 0)):
			j["boarded"] = true
	elif bool(j.get("want_board", false)) and (j.get("phase", "") == "warten" or bool(j.get("bus_back", false))):
		remote_board(p)


## Abflug-Passagiere sollen jetzt zum Bus (sobald der Ankunftsbus weg ist).
func want_board(p: Dictionary) -> void:
	if jobs.has(int(p["id"])):
		jobs[int(p["id"])]["want_board"] = true


# ---------------------------------------------------------------- Abfertigung am Stand

## Plätze der Bodenfahrzeuge in Flugzeugkoordinaten (vorn -Z, rechts +X) nach der Bauart des Flugzeugs.
## Passagierseite ist links (Brücke, Treppen, Bus), Dienste rechts: Tankwagen vor der rechten Tragfläche,
## Förderbandwagen an den Frachttoren, Gepäckzüge parallel daneben, Catering an Tür R2, Bodenstrom an der Nase.
static func service_plan(kind: String) -> Dictionary:
	var s: Dictionary = Models.SPECS.get(kind, Models.SPECS["a320"])
	var pl: Dictionary = Catalog.PLANES.get(kind, Catalog.PLANES["a320"])
	var r: float = s["r"]
	var cy: float = s["cy"]
	var length: float = s["len"]
	var nose: float = pl["nose"]
	var span: float = pl["span"]
	var doors: Array = s["doors"]
	var eng_front := float(s["eng_z"]) - float(s["eng_len"]) * 0.5
	var zf := minf((float(s["nose_gear_z"]) + float(s["wing_z"])) * 0.5, eng_front - 2.0)
	zf = maxf(zf, float(s["nose_gear_z"]) + 2.2)
	var za := float(s["main_gear_z"]) + length * 0.17
	var tank_x := float(s["eng_x"]) + float(s["eng_r"]) * float(s.get("eng_flat", 1.0)) + 3.6
	var wa: Array = Models._wing_at(s, tank_x)
	return {"r": r, "len": length, "nose": nose, "tail": length - nose, "span": span, "zf": zf, "za": za,
		"hold": cy - r * 0.55, "sill": cy - 0.85, "r2": float(doors[1]), "tank_x": tank_x, "le": float(wa[0]),
		"wing_y": float(wa[1]), "nose_gear": float(s["nose_gear_z"]), "eng_x": float(s["eng_x"]),
		"eng_front": eng_front, "tip_z": float(Models._wing_at(s, float(s["tip_x"]))[0]),
		"lane": r + 10.5}


## Abfertigung beginnt: Unterlegkeile, Pylonen, dann rollen die Fahrzeuge nach Plan an.
func turn_start(p: Dictionary) -> void:
	var j := _job(p)
	var plan := service_plan(String(p["kind"]))
	j["plan"] = plan
	if not j.has("svc"):
		j["svc"] = _make_svc(plan)
	var train := false
	for sv: Dictionary in j["svc"]:
		train = train or (sv["kind"] == "zug" and not bool(sv.get("full", false)) and sv.get("v") is Dictionary)
	if not train and terminal != null:
		terminal.bags_arrived(int(p["id"]), 90.0)
	_props(p, j, plan)
	j["crew"] = []


## Dienste am Stand nach Plan; Tank und Catering nur, wenn es Tanklager und Cateringbetrieb gibt.
func _make_svc(plan: Dictionary) -> Array:
	var hf := Vector3(float(plan["span"]) * 0.5 + 5.0, 0, -float(plan["nose"]) - 2.0)   # vorn rechts
	var hr := Vector3(float(plan["span"]) * 0.5 + 5.0, 0, float(plan["tail"]) - 2.0)     # hinten rechts
	var lane: float = plan["lane"]
	var r: float = plan["r"]
	var svc := []
	# Bodenstrom an der Nase
	svc.append({"kind": "gpu", "in": 0.02, "out": 0.9, "home": hf, "spot": Vector3(3.4, 0, float(plan["nose_gear"]) - 3.0),
		"face": Vector3(0, 0, -1), "via": Vector3(7.0, 0, float(plan["nose_gear"]) - 9.0)})
	# Förderbandwagen an beiden Frachttoren (fahren schräg auf den Rumpf zu, Heck vom Triebwerk weg)
	for k in range(2):
		var z: float = plan["zf"] if k == 0 else plan["za"]
		var face := Vector3(-1.0, 0.0, 0.3 if k == 0 else -0.3).normalized()
		var door := Vector3(r + 0.15, 0, z)
		var back := 4.9
		svc.append({"kind": "bandlader", "in": 0.03 + 0.01 * float(k), "out": 0.84, "home": hf if k == 0 else hr,
			"spot": door - face * back, "face": face, "via": door - face * (back + 11.0), "door_y": plan["hold"], "hold": k})
	# Gepäckzüge: Ankunft (leer, wird beladen) und Abflug (voll, wird entladen), parallel zum Rumpf.
	# Beide kommen von vorn; der hintere Zug fährt auf der äußeren Spur am vorderen vorbei.
	var zf: float = plan["zf"]
	var za: float = plan["za"]
	var out_lane := lane + 3.6
	var exitp := hr + Vector3(4, 0, 8)
	for full: bool in [false, true]:
		var t_in := 0.04 if not full else 0.41
		var t_out := 0.38 if not full else 0.8
		svc.append({"kind": "zug", "in": t_in, "out": t_out, "home": hf, "full": full, "hold": 0,
			"way": [Vector3(lane, 0, zf - 16.0)], "spot": Vector3(lane, 0, zf - 1.0), "face": Vector3(0, 0, 1),
			"exit": [Vector3(out_lane, 0, zf + 6.0), Vector3(out_lane, 0, za - 4.0), exitp]})
		# hinterer Zug: in derselben Spur nur, wenn seine Wagen den vorderen Zug nicht berühren
		var lane1 := lane if za + 1.0 - 14.5 > zf - 0.5 else out_lane
		svc.append({"kind": "zug", "in": t_in + 0.02, "out": t_out, "home": hf, "full": full, "hold": 1,
			"way": [Vector3(out_lane, 0, zf - 16.0), Vector3(out_lane, 0, za - 13.0)], "spot": Vector3(lane1, 0, za + 1.0),
			"face": Vector3(0, 0, 1), "exit": [exitp]})
	# Catering an Tür R2 hinten rechts
	var r2: float = plan["r2"]
	var cface := Vector3(-1, 0, 0)
	svc.append({"kind": "catering", "in": 0.1, "out": 0.56, "home": hr, "spot": Vector3(r + 0.3, 0, r2) - cface * 4.9,
		"face": cface, "via": Vector3(r + 16.0, 0, r2 + 2.0), "door_y": plan["sill"]})
	# Tankwagen vor der rechten Tragfläche, Schlauch zum Tankanschluss
	var tx: float = plan["tank_x"]
	var le: float = plan["le"]
	var tface := Vector3(0.35, 0, -1).normalized()
	var tspot := Vector3(tx, 0, le - 5.4)
	svc.append({"kind": "tank", "in": 0.15, "out": 0.62, "home": hr, "spot": tspot, "face": tface,
		"way": [Vector3(float(plan["span"]) * 0.5 + 5.0, 0, le - 4.0), tspot + tface * 9.0], "reverse_in": true,
		"exit": [hf], "coupling": Vector3(tx - 0.6, float(plan["wing_y"]) - 0.3, le + 1.2)})
	var out := []
	for sv: Dictionary in svc:
		sv["phase"] = "warten"
		if (sv["kind"] == "tank" or sv["kind"] == "catering") and not has_garage(String(sv["kind"])):
			continue
		out.append(sv)
	# Wartepunkte am Rand des Stands auffächern: jedes Fahrzeug bekommt seinen eigenen Platz
	var seen := {}
	for sv: Dictionary in out:
		var hk := str(sv["home"])
		var n := int(seen.get(hk, 0))
		seen[hk] = n + 1
		if n > 0:
			sv["home"] = (sv["home"] as Vector3) + Vector3(4.5 * float(n), 0, 0)
	return out


## Pylonen an Flügelspitzen, Triebwerken und Heck; Keile am Bugrad.
func _props(p: Dictionary, j: Dictionary, plan: Dictionary) -> void:
	var props := []
	var span2: float = float(plan["span"]) * 0.5 + 0.8
	var tip_z: float = float(plan["tip_z"]) + 1.0
	var cone_pts := [Vector3(span2, 0, tip_z), Vector3(-span2, 0, tip_z), Vector3(0, 0, float(plan["tail"]) + 1.2),
		Vector3(float(plan["eng_x"]), 0, float(plan["eng_front"]) - 1.6), Vector3(-float(plan["eng_x"]), 0, float(plan["eng_front"]) - 1.6)]
	for c: Vector3 in cone_pts:
		props.append([_prop("pylon", plane_point(p, c), plane_dir(p, Vector3(0, 0, -1))), 0.03, 0.92])
	props.append([_prop("keil", plane_point(p, Vector3(0, 0, float(plan["nose_gear"]))), plane_dir(p, Vector3(1, 0, 0))), 0.01, 0.95])
	j["props"] = props


func _prop(kind: String, at: Vector3, face: Vector3) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Models.gse_mesh(kind)
	add_child(mi)
	mi.position = at
	mi.basis = Basis.looking_at(face.normalized(), Vector3.UP)
	mi.visible = false
	return mi


## Abfertigung läuft: f = Anteil der Abfertigungszeit (0 … 1).
func turn_step(p: Dictionary, f: float, sim: float) -> void:
	var j: Dictionary = jobs.get(int(p["id"]), {})
	if not j.has("svc"):
		return
	for pr: Array in j["props"]:
		var n: Variant = pr[0]
		if is_instance_valid(n):
			(n as Node3D).visible = f >= float(pr[1]) and f < float(pr[2])
	for sv: Dictionary in j["svc"]:
		_service(p, sv, f, sim)


## Abfertigung vorbei (oder abgebrochen): alle Fahrzeuge fahren zurück.
func turn_end(p: Dictionary) -> void:
	var j: Dictionary = jobs.get(int(p["id"]), {})
	if not j.has("svc"):
		return
	for sv: Dictionary in j["svc"]:
		if String(sv["phase"]) in ["anfahrt", "dock"]:
			_undock(sv)
			_leave(p, sv)
	for pr: Array in j["props"]:
		if is_instance_valid(pr[0]):
			(pr[0] as Node).queue_free()
	j["props"] = []
	j["turn_over"] = true


## Sind alle Fahrzeuge vom Flugzeug weg (Pushback darf beginnen)?
func turn_clear(p: Dictionary) -> bool:
	var j: Dictionary = jobs.get(int(p["id"]), {})
	for sv: Dictionary in j.get("svc", []):
		if String(sv["phase"]) in ["anfahrt", "dock"]:
			return false
		if String(sv["phase"]) == "ab":
			var v: Dictionary = sv["v"]
			if (v["pos"] as Vector3).distance_to(p["pos"]) < float(service_plan(String(p["kind"]))["span"]) * 0.5 + 2.0 \
					and bool(v.get("near_nose", false)):
				return false
	return true


func service_count() -> int:
	var n := 0
	for id: int in jobs:
		for sv: Dictionary in (jobs[id] as Dictionary).get("svc", []):
			if String(sv["phase"]) in ["anfahrt", "dock", "ab"]:
				n += 1
	return n


func _service(p: Dictionary, sv: Dictionary, f: float, sim: float) -> void:
	var phase: String = sv["phase"]
	match phase:
		"warten", "bereit":
			if f >= float(sv["in"]) and f < float(sv["out"]) - 0.05:
				_arrive(p, sv)
			elif f >= float(sv["out"]) and sv.get("v") is Dictionary:
				_send_home(sv["v"], String(sv["kind"]))
				sv["v"] = null
				sv["phase"] = "weg"
		"anfahrt":
			var v: Dictionary = sv["v"]
			_move(v, sim)
			if not bool(v["moving"]):
				if v.has("then"):
					_go(v, v["then"], GSE_V * 0.5, bool(v.get("then_rev", false)))
					v.erase("then")
				else:
					sv["phase"] = "dock"
					sv["t"] = 0.0
			if f >= float(sv["out"]):
				_undock(sv)
				_leave(p, sv)
		"dock":
			sv["t"] = float(sv["t"]) + sim
			_docked(p, sv, f, sim)
			if f >= float(sv["out"]) and _undocked(sv, sim):
				_leave(p, sv)
		"ab":
			var v: Dictionary = sv["v"]
			_move(v, sim)
			if not bool(v["moving"]):
				if v.has("then"):
					_go(v, v["then"], GSE_V, false)
					v.erase("then")
				else:
					_send_home(v, String(sv["kind"]))
					sv["v"] = null
					for c: Variant in sv.get("extra", []):
						if is_instance_valid(c):
							(c as Node).queue_free()
					sv["phase"] = "weg"


## Fahrzeug erscheint am Rand des Stands und fährt über einen Zwischenpunkt an seinen Platz.
func _arrive(p: Dictionary, sv: Dictionary) -> void:
	var kind: String = sv["kind"]
	var home := plane_point(p, sv["home"])
	var spot := plane_point(p, sv["spot"])
	var face := plane_dir(p, sv["face"])
	var way := [home]
	if sv.has("way"):
		for w: Vector3 in sv["way"]:
			way.append(plane_point(p, w))
	else:
		way.append(plane_point(p, sv["via"]))
	var rev_in := bool(sv.get("reverse_in", false))
	if not rev_in:
		way.append(spot)
	var v: Dictionary
	var h0: Vector3 = (way[1] as Vector3) - home
	h0.y = 0.0
	h0 = h0.normalized() if h0.length() > 0.1 else face
	if sv.get("v") is Dictionary and is_instance_valid((sv["v"] as Dictionary).get("node")):
		# kommt aus der Garage und wartet schon am Rand des Stands
		v = sv["v"]
		way[0] = v["pos"]
		h0 = v["heading"]
		v.erase("door_key")
		if v.has("load_then"):
			v.erase("load_then")
			_set_bags(v, 24)
	else:
		v = _spawn_kind(sv, home, h0)
	v["flight"] = int(p["id"])
	v["vmax"] = GSE_V
	sv["v"] = v
	_go(v, _route(way, h0, face), GSE_V)
	if rev_in:
		# Tankwagen: hält vor der Tragfläche und setzt gerade zurück an den Tankanschluss
		var pre: Vector3 = way[way.size() - 1]
		v["then"] = PackedVector3Array([pre, pre.lerp(spot, 0.5), spot])
		v["then_rev"] = true
	sv["phase"] = "anfahrt"


func _spawn_kind(sv: Dictionary, at: Vector3, h0: Vector3) -> Dictionary:
	var kind: String = sv["kind"]
	match kind:
		"bandlader":
			return _vehicle_from(_belt_loader(), kind, at, h0)
		"catering":
			return _vehicle_from(_catering_truck(), kind, at, h0)
		"zug":
			return _train(at, h0, bool(sv["full"]))
	var v := _vehicle(kind, at, h0)
	v["kind"] = kind
	return v


## Weiche Fahrt durch Wegpunkte: Richtung an jedem Zwischenpunkt zeigt vom vorigen zum nächsten.
static func _route(way: Array, h0: Vector3, h_end: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := way.size()
	var hs := [h0]
	for i in range(1, n - 1):
		var d: Vector3 = (way[i + 1] as Vector3) - (way[i - 1] as Vector3)
		d.y = 0.0
		hs.append(d.normalized() if d.length() > 0.1 else h0)
	hs.append(h_end)
	for i in range(n - 1):
		var seg := curve(way[i], hs[i], way[i + 1], hs[i + 1])
		out.append_array(seg if i == 0 else seg.slice(1))
	return out


## Weg zurück: erst vom Flugzeug weg, dann zum Rand des Stands (Gepäckzüge fahren nach hinten weiter).
func _leave(p: Dictionary, sv: Dictionary) -> void:
	var v: Variant = sv.get("v")
	if not (v is Dictionary):
		sv["phase"] = "weg"
		return
	var vd: Dictionary = v
	var pos: Vector3 = vd["pos"]
	var h: Vector3 = vd["heading"]
	var kind: String = sv["kind"]
	vd["rev"] = false
	if sv.has("exit"):
		# vorwärts weiter (Gepäckzüge nach hinten, Tankwagen nach vorn)
		var way := [pos]
		for w: Vector3 in sv["exit"]:
			way.append(plane_point(p, w))
		var last: Vector3 = way[way.size() - 1]
		var prev: Vector3 = way[way.size() - 2]
		var he := last - prev
		he.y = 0.0
		_go(vd, _route(way, h, he.normalized()), GSE_V)
	else:
		# rückwärts vom Rumpf weg, dann wenden und zurück zum Ausgangspunkt
		var back := pos - h * 6.0
		vd["near_nose"] = kind == "gpu"
		_go(vd, PackedVector3Array([pos, pos.lerp(back, 0.5), back]), 1.6, true)
		var home := plane_point(p, sv["home"])
		var side := (home - back)
		side.y = 0.0
		vd["then"] = curve(back, (-h + side.normalized()).normalized(), home, side.normalized())
	sv["phase"] = "ab"


# ---------------------------------------------------------------- Bewegliche Teile der Bodenfahrzeuge

func _belt_loader() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Models.gse_mesh("bandlader")
	n.add_child(mi)
	var band := Node3D.new()
	band.name = "Band"
	band.position = Vector3(0, 1.0, 2.6)
	n.add_child(band)
	var bm := MeshInstance3D.new()
	bm.mesh = Models.gse_part("band")
	band.add_child(bm)
	var bags := MultiMeshInstance3D.new()
	bags.name = "Koffer"
	bags.set_script(BeltAnim)
	band.add_child(bags)
	bags.call("setup", PackedVector3Array([Vector3(0, 0.12, -0.5), Vector3(0, 0.12, -7.3)]), Models.bag_mesh(), 0.9, 1.5)
	bags.visible = false
	return n


func _catering_truck() -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Models.gse_mesh("catering_basis")
	n.add_child(mi)
	var sc := MeshInstance3D.new()
	sc.name = "Schere"
	sc.mesh = Models.gse_part("schere")
	sc.position = Vector3(0, 0.92, 0.0)
	sc.scale = Vector3(1, 0.43, 1)
	n.add_child(sc)
	var box := Node3D.new()
	box.name = "Kasten"
	box.position = Vector3(0, 1.35, 0)
	n.add_child(box)
	var bm := MeshInstance3D.new()
	bm.mesh = Models.gse_part("kasten")
	box.add_child(bm)
	var pf := MeshInstance3D.new()
	pf.name = "Buehne"
	pf.mesh = Models.gse_part("buehne")
	pf.position = Vector3(0, 0.0, 1.2)
	box.add_child(pf)
	return n


## Gepäckschlepper mit drei Wagen, die der Spur des Schleppers folgen.
func _train(at: Vector3, heading: Vector3, full: bool) -> Dictionary:
	var tug := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Models.gse_mesh("gepaeckschlepper")
	tug.add_child(mi)
	var v := _vehicle_from(tug, "zug", at, heading)
	var cars := []
	var cols := [Color(0.62, 0.18, 0.16), Color(0.18, 0.28, 0.5), Color(0.12, 0.12, 0.13), Color(0.5, 0.4, 0.27),
		Color(0.25, 0.45, 0.3), Color(0.75, 0.72, 0.68), Color(0.85, 0.6, 0.15)]
	for c in range(3):
		var car := Node3D.new()
		var cm := MeshInstance3D.new()
		cm.mesh = Models.gse_mesh("wagen")
		car.add_child(cm)
		var cargo := Node3D.new()
		cargo.name = "Ladung"
		car.add_child(cargo)
		for i in range(8):
			var b := MeshInstance3D.new()
			b.mesh = Models.bag_mesh_col(cols[(i * 3 + c) % cols.size()])
			b.position = Vector3(-0.42 + float(i % 2) * 0.84, 0.58 + float(i / 4) * 0.63, -0.85 + float((i / 2) % 2) * 1.7)
			b.rotation.y = float(i % 3) * 0.12 - 0.12
			b.visible = full
			cargo.add_child(b)
		add_child(car)
		cars.append(car)
	v["cars"] = cars
	v["car_pos"] = []
	var trail := PackedVector3Array()
	var h := heading.normalized()
	for k in range(30):
		trail.append(at - h * (14.0 - float(k) * 0.5))
	trail.append(at)
	v["trail"] = trail
	v["bags"] = 24 if full else 0
	_place_cars(v)
	return v


func _trail_add(v: Dictionary) -> void:
	var tr: PackedVector3Array = v["trail"]
	var pos: Vector3 = v["pos"]
	if tr.is_empty() or tr[tr.size() - 1].distance_to(pos) > 0.3:
		tr.append(pos)
		if tr.size() > 200:
			tr = tr.slice(tr.size() - 200)
		v["trail"] = tr


## Wagen stehen auf der Spur des Schleppers im Abstand von 3,3 m.
func _place_cars(v: Dictionary) -> void:
	var cars: Array = v["cars"]
	var cps := []
	var pos: Vector3 = v["pos"]
	var h: Vector3 = v["heading"]
	h.y = 0.0
	h = h.normalized() if h.length() > 0.01 else Vector3(0, 0, -1)
	var hitch := pos - h * 1.6   # Kupplung hinten am Schlepper (Front -Z = heading)
	# Jeder Wagen hängt mit der Deichsel an der Kupplung davor und wird nachgezogen (Schleppkurve):
	# das Heck bewegt sich nur in Richtung der Kupplung, so schneiden die Wagen Kurven wie echte
	# Anhänger und schieben sich nie ineinander. Deichsel 1,1 m, Kasten 2,6 m, Kupplung 0,2 m.
	if not v.has("car_rear") or (v["car_rear"] as Array).size() != cars.size():
		var init := []
		var tr: PackedVector3Array = v.get("trail", PackedVector3Array())
		for c in range(cars.size()):
			init.append(hitch - h * (3.7 + 3.9 * float(c)))
		v["car_rear"] = init
	var rears: Array = v["car_rear"]
	var ahead := h   # Richtung des Fahrzeugs davor (Knickwinkel der Deichsel höchstens 65°)
	for c in range(cars.size()):
		var rear: Vector3 = rears[c]
		var d := hitch - rear
		d.y = 0.0
		if d.length() < 0.01:
			d = ahead
		var dir := d.normalized()
		var bend := ahead.signed_angle_to(dir, Vector3.UP)
		if absf(bend) > deg_to_rad(65.0):
			dir = ahead.rotated(Vector3.UP, signf(bend) * deg_to_rad(65.0)).normalized()
		ahead = dir
		rear = hitch - dir * 3.7
		rears[c] = rear
		var center := hitch - dir * (1.1 + 1.3)
		var node: Node3D = cars[c]
		if is_instance_valid(node):
			node.position = Vector3(center.x, 0.0, center.z)
			node.basis = Basis.looking_at(dir, Vector3.UP)
		cps.append(center)
		hitch = rear - dir * 0.2
	v["car_pos"] = cps


## Punkt, der entlang der Spur dist Meter hinter start liegt.
static func _trail_back(tr: PackedVector3Array, start: Vector3, dist: float) -> Vector3:
	var left := dist
	var cur := start
	var i := tr.size() - 1
	while i >= 0:
		var q := tr[i]
		var d := cur.distance_to(q)
		if d >= left:
			return cur + (q - cur) / maxf(d, 0.0001) * left
		left -= d
		cur = q
		i -= 1
	return cur


## Im Dock: Band heben, Koffer laufen, Kasten hoch, Schlauch und Kabel anlegen.
func _docked(p: Dictionary, sv: Dictionary, f: float, sim: float) -> void:
	var v: Dictionary = sv["v"]
	var node: Node3D = v["node"]
	if not is_instance_valid(node):
		return
	match String(sv["kind"]):
		"bandlader":
			var band := node.get_node_or_null("Band") as Node3D
			var sill: float = sv["door_y"]
			var goal := asin(clampf((sill - 1.05) / 7.6, -0.3, 0.9))
			band.rotation.x = move_toward(band.rotation.x, goal, sim * 0.25)
			var bags := band.get_node_or_null("Koffer") as Node3D
			var up := absf(band.rotation.x - goal) < 0.01
			var unload := f > 0.1 and f < 0.36
			var loading := f > 0.47 and f < 0.79
			bags.visible = up and (unload or loading)
			bags.set("speed", -0.9 if unload else 0.9)
			if not sv.has("crew"):
				var w := Factory.make_staff(Color(0.95, 0.85, 0.1), Color(0.15, 0.18, 0.28), 2 + int(sv["hold"]), true)
				add_child(w)
				var hh: Vector3 = v["heading"]
				w.position = (v["pos"] as Vector3) - hh * 3.4 + hh.cross(Vector3.UP) * 1.4
				w.basis = Basis.looking_at(hh, Vector3.UP)
				sv["crew"] = w
				sv["extra"] = [w]
			var crew := sv["crew"] as Node3D
			if is_instance_valid(crew):
				Factory.set_pose(crew, (1 + int(float(sv["t"]) * 2.0) % 2) if bags.visible else 0)
		"catering":
			var box := node.get_node_or_null("Kasten") as Node3D
			var sc := node.get_node_or_null("Schere") as Node3D
			var pf := box.get_node_or_null("Buehne") as Node3D
			var goal: float = float(sv["door_y"]) - 0.05
			box.position.y = move_toward(box.position.y, goal, sim * 0.35)
			sc.scale.y = maxf(0.05, box.position.y - 0.92)
			if absf(box.position.y - goal) < 0.01:
				pf.position.z = move_toward(pf.position.z, -1.7, sim * 0.6)
		"tank":
			if not sv.has("hose"):
				var a := (v["pos"] as Vector3) + Vector3(0, 1.0, 0) - (v["heading"] as Vector3) * 4.6
				var b := plane_point(p, sv["coupling"])
				var hose := _hose(a, b, 0.07, Color(0.12, 0.12, 0.12))
				sv["hose"] = hose
				sv["extra"] = [hose]
				var w := Factory.make_staff(Color(0.95, 0.85, 0.1), Color(0.15, 0.18, 0.28), 3, true)
				add_child(w)
				w.position = Vector3(b.x, 0, b.z) + plane_dir(p, Vector3(1.2, 0, -0.6))
				w.basis = Basis.looking_at(plane_dir(p, Vector3(-1, 0, 0)), Vector3.UP)
				(sv["extra"] as Array).append(w)
		"gpu":
			if not sv.has("hose"):
				var a := (v["pos"] as Vector3) + Vector3(0, 1.4, 0)
				var b := plane_point(p, Vector3(0.6, 1.5, float(service_plan(String(p["kind"]))["nose_gear"]) - 1.8))
				var cable := _hose(a, b, 0.05, Color(0.1, 0.1, 0.1))
				sv["hose"] = cable
				sv["extra"] = [cable]
		"zug":
			var cars: Array = v["cars"]
			var total := cars.size() * 8
			var n := int(v["bags"])
			var unload := f > 0.12 and f < 0.36
			var loading := f > 0.49 and f < 0.79
			# Ankunftszug füllt sich beim Entladen, Abflugzug leert sich beim Beladen
			var target := n
			if not bool(sv["full"]) and unload:
				target = int(float(total) * clampf((f - 0.12) / 0.24, 0.0, 1.0))
			elif bool(sv["full"]) and loading:
				target = int(float(total) * (1.0 - clampf((f - 0.49) / 0.3, 0.0, 1.0)))
			if target != n:
				v["bags"] = target
				var i := 0
				for car: Node3D in cars:
					var ld := car.get_node_or_null("Ladung")
					for b: Node in ld.get_children():
						(b as Node3D).visible = i < target
						i += 1


## Band absenken, Kasten herunter, Schlauch ab. true, sobald das Fahrzeug losfahren kann.
func _undocked(sv: Dictionary, sim: float) -> bool:
	var v: Dictionary = sv["v"]
	var node: Node3D = v["node"]
	if not is_instance_valid(node):
		return true
	match String(sv["kind"]):
		"bandlader":
			var band := node.get_node_or_null("Band") as Node3D
			(band.get_node("Koffer") as Node3D).visible = false
			band.rotation.x = move_toward(band.rotation.x, 0.0, sim * 0.3)
			return absf(band.rotation.x) < 0.01
		"catering":
			var box := node.get_node_or_null("Kasten") as Node3D
			var sc := node.get_node_or_null("Schere") as Node3D
			var pf := box.get_node_or_null("Buehne") as Node3D
			pf.position.z = move_toward(pf.position.z, 1.2, sim * 0.8)
			if pf.position.z < 1.19:
				return false
			box.position.y = move_toward(box.position.y, 1.35, sim * 0.45)
			sc.scale.y = maxf(0.05, box.position.y - 0.92)
			return absf(box.position.y - 1.35) < 0.01
	_undock(sv)
	return true


func _undock(sv: Dictionary) -> void:
	for key: String in ["hose"]:
		if sv.has(key) and is_instance_valid(sv[key]):
			(sv[key] as Node).queue_free()
		sv.erase(key)


## Schlauch oder Kabel: leicht durchhängender Bogen aus kurzen Zylindern.
func _hose(a: Vector3, b: Vector3, r: float, col: Color) -> Node3D:
	var k := preload("res://scripts/mesh_kit.gd").new()
	var n := 10
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var q := a.lerp(b, t)
		q.y -= sin(t * PI) * minf(1.2, a.distance_to(b) * 0.12)
		k.cyl(prev - a, q - a, r, r, col, 6, false)
		prev = q
	var mi := k.instance("Schlauch")
	mi.position = a
	add_child(mi)
	return mi


# ---------------------------------------------------------------- Garagen, Tore und Fahrwege

func _rebuild_net() -> void:
	net_dirty = false
	net.build(game.lines, false, game.stands())
	fire_net.build(game.lines, true, game.stands())
	unconnected = []
	for id: String in ["vorfelddepot", "tanklager", "busgarage", "catering", "feuerwache"]:
		for rec: Dictionary in game.items_of(id):
			var spots: Array = _spots(rec)
			if spots.is_empty():
				continue
			var outside: Vector3 = spots[0][1]
			var nn := (fire_net if id == "feuerwache" else net).nearest(outside, 60.0)
			if nn < 0:
				unconnected.append(rec)


## Tore oder Stellplätze eines Gebäudes: je [innen, außen, Tor?, Index] in Weltkoordinaten.
func _spots(rec: Dictionary) -> Array:
	var def: Dictionary = Catalog.ITEMS.get(String(rec["id"]), {})
	var list: Array = def.get("doors", def.get("bays", []))
	var b := Basis(Vector3.UP, float(rec["rot"]) * PI * 0.5)
	var p: Vector3 = rec["pos"]
	var out := []
	for i in range(list.size()):
		var e: Array = list[i]
		var local: Vector3 = e[0]
		var depth := float(e[3]) if e.size() > 3 else 3.5
		out.append([p + b * (local + Vector3(0, 0, -depth)), p + b * (local + Vector3(0, 0, 7.0)), def.has("doors"), i])
	return out


## Gibt es eine versorgte Garage für diese Fahrzeugart?
## Hat der Stand eine Zufahrt von der Betriebsstraße?
func stand_connected(st: Dictionary) -> bool:
	if net_dirty:
		_rebuild_net()
	return net.stand_link.has((st["node"] as Node).get_instance_id())


func has_garage(kind: String) -> bool:
	for gid: String in Catalog.garages_for(kind):
		for rec: Dictionary in game.items_of(gid):
			if game.supplied(rec, "strom"):
				return true
	return false


## Nächste versorgte Garage: [Gebäude, innen, außen, Tor?, Index] oder leer.
func _garage(kind: String, near: Vector3) -> Array:
	var best: Array = []
	var bd := INF
	for gid: String in Catalog.garages_for(kind):
		for rec: Dictionary in game.items_of(gid):
			if not game.supplied(rec, "strom") or not is_instance_valid(rec.get("node")):
				continue
			for sp: Array in _spots(rec):
				var d := (sp[1] as Vector3).distance_to(near) + randf() * 6.0
				# steht schon ein Fahrzeug hinter diesem Tor, lieber ein anderes nehmen
				for o: Dictionary in vehicles:
					if (o["pos"] as Vector3).distance_to(sp[0]) < 6.0:
						d += 400.0
				if d < bd:
					bd = d
					best = [rec, sp[0], sp[1], sp[2], sp[3]]
	return best


func _door_key(rec: Dictionary, idx: int) -> String:
	return "%d:%d" % [(rec["node"] as Node).get_instance_id(), idx]


## Tor offen halten, solange das Fahrzeug in der Nähe ist. false = muss noch warten.
func _door_step(v: Dictionary) -> bool:
	if not v.has("door_key"):
		return true
	var key: String = v["door_key"]
	var dp: Vector3 = v["door_pt"]
	var d := (v["pos"] as Vector3).distance_to(dp)
	if d < 16.0 or v.has("await_door"):
		door_want[key] = maxf(float(door_want.get(key, 0.0)), clock + 1.2)
	if v.has("await_door"):
		if float(door_open.get(key, 0.0)) >= 0.97:
			v.erase("await_door")
			if v.has("route"):
				_go(v, v["route"], float(v.get("vmax", GSE_V)))
				v.erase("route")
		return false
	return true


## Vorab: Ein Flug ist im Anflug, die Fahrzeuge fahren aus ihren Garagen zum Stand und warten am Rand.
func prestage(p: Dictionary, park_pos: Vector3, fwd: Vector3) -> void:
	var j := _job(p)
	if j.has("svc"):
		return
	if net_dirty:
		_rebuild_net()
	var ghost := {"pos": park_pos, "heading": fwd, "kind": p["kind"], "id": p["id"]}
	var plan := service_plan(String(p["kind"]))
	j["svc"] = _make_svc(plan)
	for sv: Dictionary in j["svc"]:
		_dispatch(ghost, sv)


func _dispatch(pp: Dictionary, sv: Dictionary) -> void:
	var kind: String = sv["kind"]
	var home := plane_point(pp, sv["home"])
	var g := _garage(kind, home)
	if g.is_empty():
		return
	var road := net.route(g[2], home, 60.0)
	if road.size() < 2:
		return
	var way := [g[1]]
	for q: Vector3 in road:
		way.append(q)
	var h0: Vector3 = (g[2] as Vector3) - (g[1] as Vector3)
	h0.y = 0.0
	h0 = h0.normalized()
	var last: Vector3 = way[way.size() - 1]
	var prev: Vector3 = way[way.size() - 2]
	var hend := last - prev
	hend.y = 0.0
	var v := _spawn_kind(sv, g[1], h0)
	v["flight"] = int(pp["id"])
	v["vmax"] = GSE_V * 1.4
	sv["v"] = v
	sv["phase"] = "anreise"
	var pts := _route(way, h0, hend.normalized() if hend.length() > 0.1 else h0)
	# Abflugzug holt die Koffer erst an der Sortierung ab
	if kind == "zug" and bool(sv.get("full", false)):
		var sp := sort_spot(g[2])
		if not sp.is_empty():
			# Ladeplatz neben den Abladeplätzen, je Zug ein eigener
			var loading := 0
			for o: Dictionary in vehicles:
				if o.has("load_then"):
					loading += 1
			var lp: Vector3 = (sp[0] as Vector3) + (sp[1] as Vector3).cross(Vector3.UP) * (8.0 + 6.0 * float(loading % 3))
			if sp.size() > 3:
				# am Rolltor: neben der Toröffnung, das Tor geht beim Beladen auf
				lp = (sp[0] as Vector3) + (sp[1] as Vector3).cross(Vector3.UP) * float([-9, 23, -25][loading % 3])
				v["load_door"] = sp[3]
			sp = [lp, sp[1], sp[2]]
			var r1 := net.route(g[2], sp[0], 60.0)
			var r2 := net.route(sp[0], home, 60.0)
			if r1.size() >= 2 and r2.size() >= 2:
				var w1 := [g[1]]
				for q: Vector3 in r1:
					w1.append(q)
				var side := (sp[1] as Vector3).cross(Vector3.UP)
				pts = _route(w1, h0, side)
				var w2 := []
				for q: Vector3 in r2:
					w2.append(q)
				v["load_then"] = {"t": 0.0, "pts": _route(w2, side, hend.normalized() if hend.length() > 0.1 else side)}
				_set_bags(v, 0)
	_leave_garage(v, g, pts)


## Fahrzeug steht in der Garage: Tor auf, dann losfahren (ohne Tor sofort).
func _leave_garage(v: Dictionary, g: Array, pts: PackedVector3Array) -> void:
	if bool(g[3]):
		var key := _door_key(g[0], int(g[4]))
		door_rec[key] = [g[0], int(g[4])]
		v["door_key"] = key
		v["door_pt"] = g[2]
		v["await_door"] = true
		v["route"] = pts
		door_want[key] = maxf(float(door_want.get(key, 0.0)), clock + 2.0)
	else:
		_go(v, pts, float(v.get("vmax", GSE_V)))


## Sortierstelle für die Gepäckzüge: vor dem Gepäckumschlag, sonst draußen an der Hallenwand
## bei der Gepäckanlage. Rückgabe [Punkt, Blickrichtung zum Gebäude, Gepäckumschlag?] oder leer.
func sort_spot(near: Vector3) -> Array:
	var best: Array = []
	var bd := INF
	for rec: Dictionary in game.items_of("gepaeckumschlag"):
		if not game.supplied(rec, "strom"):
			continue
		var b := Basis(Vector3.UP, float(rec["rot"]) * PI * 0.5)
		var size: Vector2 = Catalog.ITEMS["gepaeckumschlag"]["size"]
		# Rolltore liegen auf der Vorfeldseite (-Z)
		var pt: Vector3 = (rec["pos"] as Vector3) + b * Vector3(0, 0, -(size.y * 0.5 + 5.0))
		var d := pt.distance_to(near)
		if d < bd:
			bd = d
			best = [pt, b * Vector3(0, 0, 1), true]
	# Rolltore in der Außenwand einer Halle mit Gepäcksortierung: der Zug hält davor, das Tor geht auf
	for g: Dictionary in game.items_of("rolltor"):
		var h: Dictionary = g.get("hall", {})
		if h.is_empty() or GameState.floor_of(g) != 0 or not (h in game.items):
			continue
		var has_sorter := false
		for it: Dictionary in game.inside_of(h):
			if it["id"] == "gepaeckanlage":
				has_sorter = true
				break
		if not has_sorter:
			continue
		var n := Basis(Vector3.UP, float(g["rot"]) * PI * 0.5) * Vector3(0, 0, 1)
		var pt := door_point(g) + n * 4.5
		var d := pt.distance_to(near)
		if d < bd:
			bd = d
			best = [pt, -n, false, g]
	if not best.is_empty():
		return best
	for h: Dictionary in game.items_of("halle"):
		for it: Dictionary in game.inside_of(h):
			if it["id"] != "gepaeckanlage" or GameState.floor_of(it) != 0:
				continue
			var r: Rect2 = h["rect"]
			var q := Vector2((it["pos"] as Vector3).x, (it["pos"] as Vector3).z)
			var c := Vector2(clampf(q.x, r.position.x, r.end.x), clampf(q.y, r.position.y, r.end.y))
			var dl := [q.x - r.position.x, r.end.x - q.x, q.y - r.position.y, r.end.y - q.y]
			var m := 0
			for i in range(4):
				if float(dl[i]) < float(dl[m]):
					m = i
			var n: Vector3 = [Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 0, 1)][m]
			match m:
				0:
					c.x = r.position.x
				1:
					c.x = r.end.x
				2:
					c.y = r.position.y
				3:
					c.y = r.end.y
			var pt := Vector3(c.x, 0, c.y) + n * 6.0
			var d := pt.distance_to(near)
			if d < bd:
				bd = d
				best = [pt, -n, false]
	return best


## Mitte eines Rolltors an der Außenwand (draußen bündig).
static func door_point(g: Dictionary) -> Vector3:
	var n := Basis(Vector3.UP, float(g["rot"]) * PI * 0.5) * Vector3(0, 0, 1)
	var p: Vector3 = g["pos"]
	return Vector3(p.x, 0, p.z) + n * 1.0


## Ankunftszug fährt zur Sortierung, lädt dort ab und fährt dann heim. false = keine Sortierung erreichbar.
func _to_sorting(v: Dictionary) -> bool:
	var sp := sort_spot(v["pos"])
	if sp.is_empty():
		return false
	# jeder Zug bekommt einen eigenen Platz vor der Sortierung (nebeneinander)
	var side := (sp[1] as Vector3).cross(Vector3.UP)
	var used := {}
	for o: Dictionary in sorting:
		used[int(o.get("sort_slot", -1))] = true
	var slot := 0
	while used.has(slot) and slot < 5:
		slot += 1
	var target: Vector3 = (sp[0] as Vector3) + side * (float(slot) * 6.0 - 12.0)
	var gate: Dictionary = sp[3] if sp.size() > 3 else {}
	var end_dir := side
	if not gate.is_empty():
		# vor dem Rolltor: die Wagen stehen vor der Öffnung, weitere Züge links und rechts daneben.
		# Der Schlepper hält in Fahrtrichtung 7 m hinter der Mitte, damit die Wagen vor dem Tor stehen.
		var base: Vector3 = (sp[0] as Vector3) + side * float([0, 16, -16, 32, -32][mini(slot, 4)])
		var pre := net.route(v["pos"], base, 60.0)
		# Fahrtrichtung auf der Straße vor dem Abbiegen (letztes Stück, das entlang der Wand läuft)
		for k in range(pre.size() - 2, -1, -1):
			var along := (pre[k + 1] - pre[k]).dot(side)
			if absf(along) > 2.0:
				end_dir = side if along > 0.0 else -side
				break
		target = base + end_dir * 7.0
	# Ist die Einfahrt hinter dem Rolltor frei, fährt der erste Zug durchs Tor in die Halle
	var inside := not gate.is_empty() and slot == 0 and game.gate_bay_free(gate)
	var n_out := Vector3.ZERO
	if inside:
		n_out = -(sp[1] as Vector3)
		end_dir = -n_out
		target = door_point(gate) - n_out * 7.0
	var road := net.route(v["pos"], (door_point(gate) + n_out * 12.0) if inside else target, 60.0)
	if road.size() < 2:
		return false
	var way := []
	for q: Vector3 in road:
		way.append(q)
	if inside:
		# senkrecht auf das Tor zu, dann hinein
		way.append(door_point(gate) + n_out * 3.0)
		way.append(target)
	elif not gate.is_empty() and way.size() >= 2:
		# Anlauf parallel zur Wand, damit die Wagen gerade vor dem Tor stehen
		way.insert(way.size() - 1, target - end_dir * 14.0)
	v["rev"] = false
	v["vmax"] = GSE_V * 1.3
	v.erase("then")
	_go(v, _route(way, v["heading"], end_dir), GSE_V * 1.3)
	v["sort"] = {"t": 0.0, "via_hall": bool(sp[2]), "inside": inside}
	v["sort_slot"] = slot
	if not gate.is_empty():
		var key := _door_key(gate, 0)
		door_rec[key] = [gate, 0]
		v["sort_door"] = gate
	sorting.append(v)
	return true


var chute_users: Array = []   # Abflugzüge, die gerade an einer Make-up-Rutsche laden


## Make-up-Rutschen aller Sortierungen mit Strom (Gepäckumschlag: 8).
func chutes_total() -> int:
	var n := 0
	for it: Dictionary in game.items_of("gepaeckanlage"):
		var h: Dictionary = it.get("hall", {})
		if h.is_empty() or game.supplied(h, "strom"):
			n += int(game.opt(it, "rutschen"))
	for it: Dictionary in game.items_of("gepaeckumschlag"):
		if game.supplied(it, "strom"):
			n += 8
	return n


## Darf dieser Zug laden? Sonst wartet er, bis eine Rutsche frei wird.
func _chute_free(v: Dictionary) -> bool:
	for o: Dictionary in chute_users.duplicate():
		if not is_instance_valid(o.get("node")) or not o.has("load_then"):
			chute_users.erase(o)
	if v in chute_users:
		return true
	if chute_users.size() < chutes_total():
		chute_users.append(v)
		return true
	return false


## Gepäckzüge an der Sortierung: anhalten, Koffer abladen (Ankunft) bzw. aufladen (Abflug).
func _step_sorting(sim: float) -> void:
	for v: Dictionary in sorting.duplicate():
		if not is_instance_valid(v.get("node")):
			sorting.erase(v)
			continue
		var gate: Dictionary = v.get("sort_door", {})
		if not gate.is_empty() and not is_instance_valid(gate.get("node")):
			v.erase("sort_door")
			gate = {}
		if not gate.is_empty():
			var key := _door_key(gate, 0)
			if (v["pos"] as Vector3).distance_to(door_point(gate)) < 34.0:
				door_want[key] = maxf(float(door_want.get(key, 0.0)), clock + 1.5)
		var st: Dictionary = v["sort"]
		if bool(v["moving"]):
			# in die Halle erst, wenn das Tor offen ist
			if bool(st.get("inside", false)) and not gate.is_empty() and not bool(st.get("out", false)) \
					and (v["pos"] as Vector3).distance_to(door_point(gate)) < 10.0 \
					and float(door_open.get(_door_key(gate, 0), 0.0)) < 0.9:
				v["v"] = 0.0
				continue
			_move(v, sim)
			continue
		if bool(st.get("out", false)):
			# wieder draußen: Tor schließt, Zug fährt heim
			sorting.erase(v)
			v.erase("sort")
			if not gate.is_empty():
				door_want[_door_key(gate, 0)] = clock + 3.0
				v.erase("sort_door")
			_send_home(v, "zug")
			continue
		st["t"] = float(st["t"]) + sim
		var n := int(v.get("bags", 0))
		var want := maxi(0, 24 - int(float(st["t"]) * 1.6))
		if not gate.is_empty() and float(door_open.get(_door_key(gate, 0), 0.0)) < 0.9:
			want = n    # erst abladen, wenn das Tor offen ist
			st["t"] = 0.0
		if want < n:
			_set_bags(v, want)
			if not gate.is_empty() and terminal != null:
				for i in range(n - want):
					terminal.gate_bag(gate["node"])
		if want == 0:
			v["sorted"] = true
			if terminal != null and v.has("flight"):
				# über die Sortierung und das Förderband dauert es noch einen Moment bis zum Band
				terminal.bags_arrived(int(v["flight"]), 25.0 if bool(st["via_hall"]) else 10.0)
			if bool(st.get("inside", false)) and not gate.is_empty():
				# rückwärts aus der Halle, im Bogen zur Seite, damit er vorwärts wegfahren kann
				var no := Basis(Vector3.UP, float(gate["rot"]) * PI * 0.5) * Vector3(0, 0, 1)
				var sd := no.cross(Vector3.UP)
				var dp := door_point(gate)
				st["out"] = true
				door_want[_door_key(gate, 0)] = clock + 30.0
				_go(v, PackedVector3Array([v["pos"], dp - no * 2.0, dp + no * 5.0, dp + no * 9.0 + sd * 3.0, dp + no * 11.0 + sd * 9.0]), 2.2, true)
				continue
			sorting.erase(v)
			v.erase("sort")
			if not gate.is_empty():
				door_want[_door_key(gate, 0)] = clock + 5.0
				v.erase("sort_door")
			_send_home(v, "zug")


## Koffer auf den Wagen eines Zugs zeigen (n von 24).
func _set_bags(v: Dictionary, n: int) -> void:
	v["bags"] = n
	var i := 0
	for car: Node3D in v.get("cars", []):
		var ld := car.get_node_or_null("Ladung")
		if ld == null:
			continue
		for b: Node in ld.get_children():
			(b as Node3D).visible = i < n
			i += 1


## Fertig am Stand: zurück in die Garage (Tor geht vorher auf), sonst verschwindet es am Rand.
func _send_home(v: Dictionary, kind: String) -> void:
	if not is_instance_valid(v.get("node")):
		_free(v)
		return
	if kind == "zug" and int(v.get("bags", 0)) > 0 and not v.has("sorted"):
		if _to_sorting(v):
			return
		v["sorted"] = true
		if terminal != null and v.has("flight"):
			terminal.bags_arrived(int(v["flight"]), 30.0)
	var g := _garage(kind, v["pos"])
	if g.is_empty():
		_free(v)
		return
	var road := net.route(v["pos"], g[2], 60.0)
	if road.size() < 2:
		_free(v)
		return
	var way := []
	for q: Vector3 in road:
		way.append(q)
	way.append(g[1])
	var hin: Vector3 = (g[1] as Vector3) - (g[2] as Vector3)
	hin.y = 0.0
	v["rev"] = false
	v["vmax"] = GSE_V * 1.4
	v.erase("then")
	_go(v, _route(way, v["heading"], hin.normalized()), GSE_V * 1.4)
	if bool(g[3]):
		var key := _door_key(g[0], int(g[4]))
		door_rec[key] = [g[0], int(g[4])]
		v["door_key"] = key
		v["door_pt"] = g[2]
	if not returning.has(v):
		returning.append(v)


func _step_returning(sim: float) -> void:
	for v: Dictionary in returning.duplicate():
		if not is_instance_valid(v.get("node")):
			returning.erase(v)
			vehicles.erase(v)
			continue
		var wait := false
		if v.has("door_key"):
			var key: String = v["door_key"]
			var d := (v["pos"] as Vector3).distance_to(v["door_pt"])
			if d < 22.0:
				door_want[key] = maxf(float(door_want.get(key, 0.0)), clock + 1.2)
			if d < 9.0 and float(door_open.get(key, 0.0)) < 0.9:
				wait = true
				v["v"] = 0.0
		if not wait:
			_move(v, sim)
		if not bool(v["moving"]):
			returning.erase(v)
			_free(v)


## Rolltore: Vorhang wickelt sich nach oben auf (Knoten "Rolltor<i>" mit Drehpunkt an der Oberkante).
func _animate_doors(sim: float) -> void:
	for key: String in door_rec.keys():
		var e: Array = door_rec[key]
		var rec: Dictionary = e[0]
		if not is_instance_valid(rec.get("node")):
			door_rec.erase(key)
			continue
		var target := 1.0 if clock < float(door_want.get(key, 0.0)) else 0.0
		var o := move_toward(float(door_open.get(key, 0.0)), target, sim * 0.6)
		door_open[key] = o
		var curtain := (rec["node"] as Node3D).get_node_or_null("Rolltor%d" % int(e[1])) as Node3D
		if curtain != null:
			curtain.scale.y = maxf(0.05, 1.0 - o)
		var lamp := (rec["node"] as Node3D).get_node_or_null("Warnlicht%d" % int(e[1])) as Node3D
		if lamp != null:
			lamp.visible = o > 0.0 and o < 1.0 and fmod(clock * 2.5, 1.0) < 0.5


# ---------------------------------------------------------------- Feuerwehr

func has_fire_station() -> bool:
	for rec: Dictionary in game.items_of("feuerwache"):
		if game.supplied(rec, "strom"):
			return true
	return false


## Kontrollfahrten in regelmäßigen Abständen.
func _fire_tick(sim: float) -> void:
	fire_t -= sim
	if fire_t <= 0.0:
		fire_t = randf_range(260.0, 520.0)
		if missions.size() < 2:
			_fire_mission("kontrolle", null, 0.0)
	for m: Dictionary in missions.duplicate():
		_step_mission(m, sim)


## Notfall gemeldet: zwei Löschfahrzeuge in Bereitschaft an die Piste.
func fire_alarm(p: Dictionary) -> bool:
	if not has_fire_station():
		return false
	var ok := false
	for k in range(2):
		ok = _fire_mission("bereitschaft", p, 0.32 + 0.3 * float(k)) or ok
	return ok


## Das Flugzeug ist sicher gelandet: die Bereitschaft fährt zurück.
func fire_clear(p: Dictionary) -> void:
	for m: Dictionary in missions:
		if m.get("flight") is Dictionary and int((m["flight"] as Dictionary)["id"]) == int(p["id"]) and String(m["phase"]) in ["raus", "warten"]:
			m["phase"] = "warten"
			m["t"] = minf(float(m.get("t", 0.0)), 12.0)
			m.erase("flight")


func _fire_mission(kind: String, p: Variant, along: float) -> bool:
	var station: Dictionary = {}
	for rec: Dictionary in game.items_of("feuerwache"):
		if game.supplied(rec, "strom") and is_instance_valid(rec.get("node")):
			station = rec
			break
	if station.is_empty() or flights_ref == null:
		return false
	if net_dirty:
		_rebuild_net()
	var busy := {}
	for m: Dictionary in missions:
		busy[int(m["idx"])] = true
	var spots := _spots(station)
	var pick := -1
	for i in range(spots.size()):
		if not busy.has(i):
			pick = i
			break
	if pick < 0:
		return false
	var sp: Array = spots[pick]
	var target := Vector3.INF
	if bool(flights_ref.dirty):
		flights_ref._rebuild()
	if kind == "kontrolle":
		var best := INF
		for hd: Dictionary in flights_ref.graph.holds:
			var hp: Vector3 = hd["pos"]
			var dirv: Vector3 = hd["dir"]
			var side := dirv.cross(Vector3.UP).normalized()
			var cand := hp - dirv * 6.0 + side * 17.0
			var d := cand.distance_to(sp[1])
			if d < best:
				best = d
				target = cand
	else:
		var rwy: Dictionary = flights_ref._runway()
		if rwy.is_empty():
			return false
		var s: PackedVector3Array = rwy["samples"]
		var a := s[0]
		var b := s[s.size() - 1]
		var q := a.lerp(b, along)
		var n := (b - a).cross(Vector3.UP).normalized()
		if (sp[1] as Vector3 - q).dot(n) < 0.0:
			n = -n
		target = q + n * 92.0
	if target == Vector3.INF:
		return false
	var road := fire_net.route(sp[1], target, 160.0)
	if road.size() < 2:
		return false
	var way := [sp[0]]
	for w: Vector3 in road:
		way.append(w)
	var h0: Vector3 = (sp[1] as Vector3) - (sp[0] as Vector3)
	h0.y = 0.0
	h0 = h0.normalized()
	var last: Vector3 = way[way.size() - 1]
	var prev: Vector3 = way[way.size() - 2]
	var hend := (last - prev)
	hend.y = 0.0
	var parked := (station["node"] as Node3D).get_node_or_null("LF%d" % pick) as Node3D
	if parked != null:
		parked.visible = false
	var node := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Landmarks.fire_truck_mesh()
	node.add_child(mi)
	var lights := Node3D.new()
	lights.name = "Blaulicht"
	node.add_child(lights)
	for e: Array in [[Vector3(-0.8, 3.4, -5.1), 0.0], [Vector3(0.8, 3.4, -5.1), 0.25], [Vector3(-1.2, 3.45, 5.45), 0.12], [Vector3(1.2, 3.45, 5.45), 0.37]]:
		var lm := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.3
		lm.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.5, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.5, 1.0)
		mat.emission_energy_multiplier = 4.0
		lm.material_override = mat
		lm.position = e[0]
		lm.set_meta("phase", e[1])
		lights.add_child(lm)
	var v := _vehicle_from(node, "feuer", sp[0], h0)
	v["len"] = 11.0
	v["vmax"] = FIRE_V
	v["blue"] = kind == "bereitschaft"
	lights.visible = false
	var m := {"kind": kind, "station": station, "idx": pick, "v": v, "phase": "raus", "t": 25.0 if kind == "kontrolle" else 90.0,
		"parked": parked, "home": sp}
	if p is Dictionary:
		m["flight"] = p
	missions.append(m)
	_leave_garage(v, [station, sp[0], sp[1], true, pick], _route(way, h0, hend.normalized() if hend.length() > 0.1 else h0))
	return true


func _step_mission(m: Dictionary, sim: float) -> void:
	var v: Dictionary = m["v"]
	if not is_instance_valid(v.get("node")):
		missions.erase(m)
		return
	var lights := (v["node"] as Node3D).get_node_or_null("Blaulicht") as Node3D
	if lights != null:
		var on := bool(v.get("blue", false)) and String(m["phase"]) != "rein"
		lights.visible = on
		if on:
			for c in lights.get_children():
				(c as Node3D).visible = fmod(clock * 2.2 + float((c as Node3D).get_meta("phase", 0.0)), 0.5) < 0.22
	match String(m["phase"]):
		"raus":
			if _door_step(v):
				_move(v, sim)
			if not v.has("await_door") and not bool(v["moving"]):
				m["phase"] = "warten"
		"warten":
			if not (m.get("flight") is Dictionary):
				m["t"] = float(m["t"]) - sim
			else:
				var fp: Dictionary = m["flight"]
				if not (fp.get("state", "") in ["anflug", "landung"]) or not flights_ref.planes.has(fp):
					m["t"] = float(m["t"]) - sim
			if float(m["t"]) <= 0.0:
				var sp: Array = m["home"]
				var road := fire_net.route(v["pos"], sp[1], 160.0)
				if road.size() < 2:
					road = PackedVector3Array([v["pos"], sp[1]])
				var way := []
				for w: Vector3 in road:
					way.append(w)
				way.append(sp[0])
				var hin: Vector3 = (sp[0] as Vector3) - (sp[1] as Vector3)
				hin.y = 0.0
				_go(v, _route(way, v["heading"], hin.normalized()), FIRE_V)
				var key := _door_key(m["station"], int(m["idx"]))
				door_rec[key] = [m["station"], int(m["idx"])]
				v["door_key"] = key
				v["door_pt"] = sp[1]
				v.erase("await_door")
				m["phase"] = "rein"
		"rein":
			var key: String = v["door_key"]
			var d := (v["pos"] as Vector3).distance_to(v["door_pt"])
			if d < 26.0:
				door_want[key] = maxf(float(door_want.get(key, 0.0)), clock + 1.5)
			if d < 12.0 and float(door_open.get(key, 0.0)) < 0.9:
				v["v"] = 0.0
			else:
				_move(v, sim)
			if not bool(v["moving"]):
				var parked: Variant = m.get("parked")
				if is_instance_valid(parked):
					(parked as Node3D).visible = true
				_free(v)
				missions.erase(m)
