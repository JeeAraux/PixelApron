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

var game: GameState
var terminal: Variant = null
var jobs: Dictionary = {}     # Flug-ID -> Auftrag (Schlepper, Treppen, Busse)
var walkers: Array = []       # Passagiere unter freiem Himmel
var vehicles: Array = []      # alle Bodenfahrzeuge, damit sie einander ausweichen
var flights_ref: Variant = null   # flights.gd: rollende Flugzeuge, vor denen Fahrzeuge warten
var linked_baggage := false   # Gepäckförderband zum Umschlag vorhanden: Abfertigung schneller


func setup(g: GameState) -> void:
	game = g


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
	mi.mesh = Models.stairs_mesh(h) if kind == "treppe" else Models.gse_mesh(kind)
	node.add_child(mi)
	add_child(node)
	var v := {"node": node, "pts": PackedVector3Array(), "i": 0, "v": 0.0, "vmax": BUS_V, "rev": false,
		"pos": at, "heading": heading.normalized(), "moving": false, "len": _length_of(kind), "wait": 0.0}
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
	if not bool(v["moving"]):
		return
	var pts: PackedVector3Array = v["pts"]
	var i: int = v["i"]
	var left := 0.0
	for j in range(i, pts.size() - 1):
		left += pts[j].distance_to(pts[j + 1])
	var vmax: float = v["vmax"]
	var want := minf(vmax, sqrt(2.0 * 1.2 * maxf(left - 0.2, 0.0)) + 0.3)
	# Abstand halten: vor anderen Fahrzeugen und rollenden Flugzeugen warten (nach 6 s geht es trotzdem weiter)
	if _blocked(v):
		v["wait"] = float(v.get("wait", 0.0)) + sim
		if float(v["wait"]) < 6.0:
			want = 0.0
	else:
		v["wait"] = 0.0
	var sp := move_toward(float(v["v"]), want, (3.0 if want < float(v["v"]) else 1.5) * sim)
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
			v["heading"] = -seg.normalized() if bool(v["rev"]) else seg.normalized()
	v["pos"] = pos
	v["i"] = i
	if i >= pts.size() - 1:
		v["moving"] = false
		v["v"] = 0.0
	if v.has("trail"):
		_trail_add(v)
	_put(v)


## Steht vor dem Fahrzeug (in Fahrtrichtung) ein anderes Fahrzeug oder rollt ein Flugzeug heran?
func _blocked(v: Dictionary) -> bool:
	var pos: Vector3 = v["pos"]
	var h: Vector3 = v["heading"]
	var dirm := -h if bool(v["rev"]) else h
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
		node.basis = Basis.looking_at(h, Vector3.UP)
	if v.has("cars"):
		_place_cars(v)


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
		node.basis = Basis.looking_at(to.normalized(), Vector3.UP)
		Factory.set_pose(node, 1 + int(float(wd["walk"]) / 0.3) % 4)
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
		_free(sv.get("v"))
		_undock(sv)
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
	if look.length_squared() > 0.0001:
		node.basis = Basis.looking_at(look.normalized(), Vector3.UP)
	Factory.set_pose(node, 1 + int(float(wk["walk"]) / 0.3) % 4)
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
	var entry := _bus_door(bd, door)
	_walker(flight, PackedVector3Array([door, door.lerp(entry, 0.5) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), entry]), "in_dep_bus")
	j["dep_out"] = int(j["dep_out"]) + 1


## Eine der drei Bustüren auf der Seite, die ref zugewandt ist.
func _bus_door(bus: Dictionary, ref: Vector3) -> Vector3:
	var h: Vector3 = bus["heading"]
	var side := h.cross(Vector3.UP).normalized()
	var z: float = [-4.6, 0.0, 4.6][randi() % 3]
	var c: Vector3 = (bus["pos"] as Vector3) - h * z
	var a := c + side * 1.9
	var b := c - side * 1.9
	return a if a.distance_to(ref) < b.distance_to(ref) else b


func step(sim: float) -> void:
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
			"to_terminal":
				if terminal != null and not j.is_empty():
					terminal.bus_arrivals(j["flight"], 1)
			"in_dep_bus":
				if not j.is_empty():
					j["dep_in"] = int(j["dep_in"]) + 1
			"on_board":
				if not j.is_empty():
					j["on_board"] = int(j.get("on_board", 0)) + 1
		_drop_walker(wk)


func _step_job(j: Dictionary, sim: float) -> void:
	var p: Dictionary = j["flight"]
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
		_free(v)
		(j["leaving"] as Array).erase(v)
	var tg: Variant = j.get("tug_gone")
	if tg is Dictionary:
		var td: Dictionary = tg
		_move(td, sim)
		if not bool(td["moving"]):
			if td.has("then"):
				_go(td, td["then"], TUG_V)
				td.erase("then")
			else:
				_free(td)
				j.erase("tug_gone")
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
				var entry := _bus_door(bus, foot)
				_walker(int(p["id"]), PackedVector3Array([v["door"], v["top"], v["bottom"], foot, foot.lerp(entry, 0.5), entry]), "in_bus")
				walkers[walkers.size() - 1]["delay"] = float(i / stairs.size()) * 1.1 + 0.4
		if bool(j.get("unloading", false)) and int(j["in_bus"]) >= n and not bool(j.get("bus_back", false)):
			j["bus_back"] = true
			var stop: Array = j["stop"]
			_go(bus, curve(bus["pos"], bus["heading"], stop[0], stop[1]), BUS_V)
		if bool(j.get("bus_back", false)) and not bool(bus["moving"]) and not bool(j.get("bus_empty", false)):
			j["bus_empty"] = true
			var door2: Vector3 = j["door"]
			for i in range(n):
				var exitp := _bus_door(bus, door2)
				_walker(int(p["id"]), PackedVector3Array([exitp, exitp.lerp(door2, 0.5) + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)), door2]), "to_terminal")
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
			for i in range(cnt):
				var v: Dictionary = stairs[i % stairs.size()]
				var foot: Vector3 = v["foot"]
				var exitp := _bus_door(db, foot)
				_walker(int(p["id"]), PackedVector3Array([exitp, exitp.lerp(foot, 0.5), foot, v["bottom"], v["top"], v["door"]]), "on_board")
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
		svc.append({"kind": "zug", "in": t_in + 0.02, "out": t_out, "home": hf, "full": full, "hold": 1,
			"way": [Vector3(out_lane, 0, zf - 16.0), Vector3(out_lane, 0, za - 13.0)], "spot": Vector3(lane, 0, za + 1.0),
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
	for sv: Dictionary in svc:
		sv["phase"] = "warten"
	j["svc"] = svc
	# Pylonen an Flügelspitzen, Triebwerken und Heck; Keile am Bugrad
	var props := []
	var span2: float = float(plan["span"]) * 0.5 + 0.8
	var tip_z: float = float(plan["tip_z"]) + 1.0
	var cone_pts := [Vector3(span2, 0, tip_z), Vector3(-span2, 0, tip_z), Vector3(0, 0, float(plan["tail"]) + 1.2),
		Vector3(float(plan["eng_x"]), 0, float(plan["eng_front"]) - 1.6), Vector3(-float(plan["eng_x"]), 0, float(plan["eng_front"]) - 1.6)]
	for c: Vector3 in cone_pts:
		props.append([_prop("pylon", plane_point(p, c), plane_dir(p, Vector3(0, 0, -1))), 0.03, 0.92])
	props.append([_prop("keil", plane_point(p, Vector3(0, 0, float(plan["nose_gear"]))), plane_dir(p, Vector3(1, 0, 0))), 0.01, 0.95])
	j["props"] = props
	j["crew"] = []


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
		"warten":
			if f >= float(sv["in"]) and f < float(sv["out"]) - 0.05:
				_arrive(p, sv)
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
					_free(v)
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
	match kind:
		"bandlader":
			v = _vehicle_from(_belt_loader(), kind, home, h0)
		"catering":
			v = _vehicle_from(_catering_truck(), kind, home, h0)
		"zug":
			v = _train(home, h0, bool(sv["full"]))
		_:
			v = _vehicle(kind, home, h0)
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
	v["trail"] = PackedVector3Array()
	var h := heading.normalized()
	for k in range(30):
		(v["trail"] as PackedVector3Array).append(at - h * (14.0 - float(k) * 0.5))
	(v["trail"] as PackedVector3Array).append(at)
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
	var tr: PackedVector3Array = v["trail"]
	var cars: Array = v["cars"]
	var cps := []
	var pos: Vector3 = v["pos"]
	var h: Vector3 = v["heading"]
	var anchor := pos + h * 1.5   # Kupplung hinten am Schlepper (Front -Z = heading)
	anchor = pos - h * 1.6
	for c in range(cars.size()):
		var want := 3.3 * float(c) + 1.3
		var front := _trail_back(tr, anchor, want)
		var rear := _trail_back(tr, anchor, want + 2.6)
		var node: Node3D = cars[c]
		if not is_instance_valid(node):
			continue
		var mid := (front + rear) * 0.5
		node.position = Vector3(mid.x, 0.0, mid.z)
		var d := front - rear
		d.y = 0.0
		if d.length() > 0.05:
			node.basis = Basis.looking_at(d.normalized(), Vector3.UP)
		cps.append(mid)
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
