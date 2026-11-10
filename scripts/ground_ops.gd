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

var game: GameState
var terminal: Variant = null
var jobs: Dictionary = {}     # Flug-ID -> Auftrag (Schlepper, Treppen, Busse)
var walkers: Array = []       # Passagiere unter freiem Himmel


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
		"pos": at, "heading": heading.normalized(), "moving": false}
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
	var sp := move_toward(float(v["v"]), want, 1.5 * sim)
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
	_put(v)


func _put(v: Dictionary) -> void:
	var node: Node3D = v["node"]
	if not is_instance_valid(node):
		return
	var pos: Vector3 = v["pos"]
	node.position = Vector3(pos.x, 0.0, pos.z)
	var h: Vector3 = v["heading"]
	if h.length_squared() > 0.001:
		node.basis = Basis.looking_at(h, Vector3.UP)


func _free(v: Variant) -> void:
	if v is Dictionary and is_instance_valid((v as Dictionary).get("node")):
		((v as Dictionary)["node"] as Node).queue_free()


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
