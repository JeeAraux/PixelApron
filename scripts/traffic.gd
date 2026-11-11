extends Node3D
## Straßenverkehr auf Spuren. Jedes Auto fährt eine Folge von Abschnitten ("Legs"):
## Spur → Kurvenbogen durch die Kreuzung → nächste Spur, dazu Spurwechsel und Zufahrten.
## Position und Richtung ergeben sich aus einem Punkt vor und einem hinter der Wagenmitte,
## so fahren die Autos saubere Bögen statt abzuknicken.
##
## Ziele: Parkhaus (rein über die Einfahrt mit Schranke, später wieder raus), Vorfahrt am Terminal
## (kurz halten, Fahrgäste aussteigen lassen) oder einfach durch zu einem anderen Kartenrand.
## Regeln an Kreuzungen: Ampel, Vorfahrtsstraße (Vorfahrt achten) und rechts vor links.

const Spline = preload("res://scripts/spline.gd")
const Factory = preload("res://scripts/factory.gd")
const GameState = preload("res://scripts/game_state.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Roads = preload("res://scripts/roads.gd")
const Models = preload("res://scripts/models.gd")
const Streetscape = preload("res://scripts/streetscape.gd")

const CARS_PER_MOVEMENT := 5
const MIN_GAP := 2.2
const STOP_BEFORE := 1.7   # Abstand Spurende → Fahrzeugfront beim Halt (Haltelinie bei 0.6 m)
const LOOK := 45.0
const ACCEL := 2.6
const BRAKE := 7.0
const PARK_FEE := 6
const BUS_EVERY := 40.0     # Sekunden zwischen zwei Linienbussen
const PED_MAX := 90
const WALK := 1.35

var game: GameState
var roads: Roads
var movers: Array = []
var occupancy: Dictionary = {}     # Leg-Schlüssel -> Autos
var target := 0
var adjust_timer := 0.0
var clock := 0.0
var access: Dictionary = {}        # Instanz-ID Parkhaus/Halle -> Zufahrt
var parked: Array = []             # [Parkhaus-Datensatz, Restzeit]
var barriers: Dictionary = {}      # Schranken-Knoten -> offen bis (clock)
var dirty := true
var bus_timer := 6.0
var peds: Array = []               # Fußgänger auf der Landseite (Bus, Parkhaus, Vorfahrt → Terminal)
var entrances: Array = []          # Punkte vor den Terminal-Eingängen (außen)
var stop_timer := 0.0
var bikes: Array = []              # Radfahrer auf Radwegen: {node, rider, path, s, len, speed}
var life_timer := 1.0
const BIKE_MAX := 14
const STROLL_MAX := 18


func setup(g: GameState, r: Roads) -> void:
	game = g
	roads = r
	game.network_changed.connect(rebuild)
	game.items_changed.connect(func() -> void: dirty = true)


func compute_target() -> int:
	var total := 0.0
	for l: Dictionary in roads.roads():
		total += float((l["samples"] as PackedVector3Array).size() - 1)
	if total <= 0.0:
		return 0
	var per := float(CARS_PER_MOVEMENT) * (0.75 if station_ok() else 1.0)
	return mini(160, int(total / 70.0) + int(float(game.traffic_demand) * per))


# ---------------------------------------------------------------- Aufbau

func rebuild() -> void:
	for m: Dictionary in movers:
		var node: Variant = m["node"]
		if is_instance_valid(node):
			(node as Node).queue_free()
	movers.clear()
	occupancy.clear()
	roads.dirty = true
	roads.ensure()
	_find_access()
	target = compute_target()
	var rl := roads.roads()
	if rl.is_empty():
		return
	for i in range(target):
		var l: Dictionary = rl[randi() % rl.size()]
		var d := 1 if randf() < 0.5 else -1
		if roads.lanes(l, d) == 0:
			d = -d
		var k := randi() % roads.lanes(l, d)
		var path := roads.lane_path(l, d, k)
		var length := Spline.length(path)
		if length < 6.0:
			continue
		var pos := randf_range(2.0, length - 2.0)
		if _lane_free(l, d, k, pos, 9.0):
			_spawn_on_lane(l, d, k, pos, "durch")


## Zufahrten zu Parkhäusern und Terminal-Vorfahrt neu suchen.
func _find_access() -> void:
	dirty = false
	access = {}
	for it: Dictionary in game.items_of("parkhaus") + game.items_of("parkplatz") + game.items_of("mietwagen"):
		var def: Dictionary = Catalog.ITEMS[it["id"]]
		var acc: Dictionary = def["access"]
		var xf := (it["node"] as Node3D).transform
		var ein: Vector3 = xf * Vector3((acc["ein"] as Vector2).x, 0, (acc["ein"] as Vector2).y)
		var aus: Vector3 = xf * Vector3((acc["aus"] as Vector2).x, 0, (acc["aus"] as Vector2).y)
		var inside_ein: Vector3 = xf * Vector3((acc["ein"] as Vector2).x, 0, (acc["ein"] as Vector2).y + 10.0)
		var inside_aus: Vector3 = xf * Vector3((acc["aus"] as Vector2).x, 0, (acc["aus"] as Vector2).y + 10.0)
		var a := _nearest_lane(ein, 30.0)
		var b := _nearest_lane(aus, 30.0)
		if a.is_empty() or b.is_empty():
			continue
		access[(it["node"] as Node).get_instance_id()] = {"rec": it, "ein": a, "aus": b, "gate_in": ein, "gate_out": aus,
			"inside_in": inside_ein, "inside_out": inside_aus}
	entrances = []
	for h: Dictionary in game.items_of("halle"):
		var r: Rect2 = h["rect"]
		for it: Dictionary in game.inside_of(h):
			if it["id"] != "eingang":
				continue
			var ep: Vector3 = it["pos"]
			var dl := ep.x - r.position.x
			var dr := r.end.x - ep.x
			var dt := ep.z - r.position.y
			var db := r.end.y - ep.z
			var m := minf(minf(dl, dr), minf(dt, db))
			var nrm := Vector3(-1, 0, 0) if m == dl else (Vector3(1, 0, 0) if m == dr else (Vector3(0, 0, -1) if m == dt else Vector3(0, 0, 1)))
			entrances.append([Vector3(ep.x, 0, ep.z) + nrm * 4.0, nrm])
		for it: Dictionary in game.inside_of(h):
			if it["id"] != "eingang":
				continue
			var lp := _nearest_lane(it["pos"], 40.0)
			if not lp.is_empty():
				access[(h["node"] as Node).get_instance_id()] = {"rec": h, "halt": lp}
				break
	# Bushaltestellen: Haltepunkt 4,5 m vor der Vorderseite
	for it: Dictionary in game.items_of("haltestelle"):
		var xf := (it["node"] as Node3D).transform
		var lp := _nearest_lane(xf * Vector3(0, 0, -4.5), 14.0)
		if lp.is_empty():
			continue
		access[(it["node"] as Node).get_instance_id()] = {"rec": it, "halt": lp, "bus": true,
			"wait": xf * Vector3(-0.6, 0, 1.0), "xf": xf}
	# Taxistand und Kiss & Fly: Haltepunkt vor der Vorderseite an der Straße
	for id: String in ["taxistand", "kissandfly"]:
		for it: Dictionary in game.items_of(id):
			var xf := (it["node"] as Node3D).transform
			var lp := _nearest_lane(xf * Vector3(0, 0, -4.5), 14.0)
			if lp.is_empty():
				continue
			access[(it["node"] as Node).get_instance_id()] = {"rec": it, "halt": lp, id: true}


## Nächste rechte Spur in der Nähe eines Punkts: {line, d, k, pos (Abstand auf der Spur), point}
func _nearest_lane(p: Vector3, max_d: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_d
	for l: Dictionary in roads.roads():
		var b: Rect2 = (l["bounds"] as Rect2).grow(max_d)
		if not b.has_point(Vector2(p.x, p.z)):
			continue
		for d: int in [1, -1]:
			var n := roads.lanes(l, d)
			if n == 0:
				continue
			var path := roads.lane_path(l, d, n - 1)
			var run := 0.0
			for i in range(path.size()):
				if i > 0:
					run += path[i].distance_to(path[i - 1])
				var dd := Vector2(path[i].x - p.x, path[i].z - p.z).length()
				if dd < bd and run > 3.0 and run < Spline.length(path) - 3.0:
					bd = dd
					best = {"line": l, "d": d, "k": n - 1, "pos": run, "point": path[i]}
	return best


# ---------------------------------------------------------------- Legs

func _make_leg(type: String, path: PackedVector3Array, key: String, extra: Dictionary = {}) -> Dictionary:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		cum.append(cum[i - 1] + path[i].distance_to(path[i - 1]))
	var leg := {"type": type, "path": path, "cum": cum, "len": cum[cum.size() - 1], "key": key, "off": 0.0}
	leg.merge(extra, true)
	return leg


func _lane_leg(l: Dictionary, d: int, k: int, from: float = 0.0) -> Dictionary:
	var full := roads.lane_path(l, d, k)
	var path := full
	if from > 0.5:
		path = _slice(full, from, INF)
	var ni := roads.node_ahead(l, d)
	var leg := _make_leg("lane", path, "L%d|%d|%d" % [Roads.iid(l), d, k],
		{"line": l, "d": d, "k": k, "arr_node": ni, "arr_end": roads.arrival_end(l, d)})
	leg["off"] = from if from > 0.5 else 0.0
	return leg


func _conn_leg(l: Dictionary, d: int, k: int, nl: Dictionary, nd: int, nk: int) -> Dictionary:
	var path := roads.conn_path(l, d, k, nl, nd, nk)
	var ni := roads.node_ahead(l, d)
	return _make_leg("conn", path, "C%d|%d|%d>%d|%d|%d" % [Roads.iid(l), d, k, Roads.iid(nl), nd, nk],
		{"node": ni, "from_e": roads.arrival_end(l, d), "turn": roads.turn_of(l, d, nl, nd), "line": nl, "d": nd, "k": nk})


## Teil eines Pfads zwischen zwei Abständen
func _slice(path: PackedVector3Array, d0: float, d1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var run := 0.0
	out.append(_point_on(path, d0))
	for i in range(1, path.size()):
		run += path[i].distance_to(path[i - 1])
		if run > d0 + 0.05 and run < d1 - 0.05:
			out.append(path[i])
	if d1 < INF:
		out.append(_point_on(path, d1))
	if out.size() < 2:
		out.append(path[path.size() - 1])
	return out


func _point_on(path: PackedVector3Array, d: float) -> Vector3:
	var run := 0.0
	for i in range(1, path.size()):
		var seg := path[i].distance_to(path[i - 1])
		if run + seg >= d:
			return path[i - 1].lerp(path[i], (d - run) / maxf(seg, 0.0001))
		run += seg
	return path[path.size() - 1]


static func _leg_point(leg: Dictionary, s: float) -> Vector3:
	var path: PackedVector3Array = leg["path"]
	var cum: PackedFloat32Array = leg["cum"]
	if s <= 0.0:
		return path[0]
	if s >= float(leg["len"]):
		return path[path.size() - 1]
	var lo := 0
	var hi := cum.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if cum[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := cum[hi] - cum[lo]
	return path[lo].lerp(path[hi], (s - cum[lo]) / maxf(seg, 0.0001))


static func _bezier(p0: Vector3, d0: Vector3, p3: Vector3, d3: Vector3) -> PackedVector3Array:
	var dist := p0.distance_to(p3)
	var h := dist * 0.42
	var p1 := p0 + d0 * h
	var p2 := p3 - d3 * h
	var out := PackedVector3Array()
	var steps := maxi(4, ceili(dist / 0.5))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var u := 1.0 - t
		out.append(p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t)
	return out


# ---------------------------------------------------------------- Autos erzeugen

func _spawn_on_lane(l: Dictionary, d: int, k: int, pos: float, purpose: String, kind: String = "") -> Dictionary:
	var leg := _lane_leg(l, d, k, pos)
	return _spawn_with_legs([leg], purpose, kind)


func _spawn_with_legs(legs: Array, purpose: String, kind: String = "") -> Dictionary:
	var node := Factory.make_car(Factory.car_color(), kind)
	add_child(node)
	kind = node.get_meta("kind")
	var length: float = Models.CAR_DIMS[kind][0]
	var vmax := randf_range(11.5, 14.5) if kind != "linienbus" else 10.0
	var m := {"node": node, "legs": legs, "prev": [], "s": 0.0, "v": vmax * 0.6, "vmax": vmax, "len": length,
		"purpose": purpose, "route": [], "wait": 0.0, "halt": 0.0, "blink": 0, "brake": false, "goal": {}}
	movers.append(m)
	_occupy(m, legs[0])
	_assign_goal(m)
	_plan(m)
	_place(m, 0.0)
	return m


func _assign_goal(m: Dictionary) -> void:
	var purpose: String = m["purpose"]
	m["goal"] = {}
	if purpose == "parkhaus" or purpose == "terminal":
		var options := []
		for key: int in access:
			var a: Dictionary = access[key]
			if purpose == "parkhaus" and a.has("ein"):
				options.append({"lane": a["ein"], "action": "parken", "acc": a})
			elif purpose == "terminal" and a.has("halt") and not a.has("bus"):
				if a.has("taxistand") and String((m["node"] as Node).get_meta("kind", "")) != "taxi":
					continue
				options.append({"lane": a["halt"], "action": "halten", "acc": a})
		# Taxis fahren bevorzugt zum Taxistand
		if String((m["node"] as Node).get_meta("kind", "")) == "taxi":
			var taxi_opts := options.filter(func(o: Dictionary) -> bool: return (o["acc"] as Dictionary).has("taxistand"))
			if not taxi_opts.is_empty():
				options = taxi_opts
		if not options.is_empty():
			m["goal"] = options[randi() % options.size()]
	elif purpose == "bus":
		var stops := []
		for key: int in access:
			var a: Dictionary = access[key]
			if a.has("bus"):
				# Haltebucht so legen, dass der Bus mittig vor dem Wartehäuschen hält
				var lane: Dictionary = (a["halt"] as Dictionary).duplicate()
				lane["pos"] = maxf(4.0, float(lane["pos"]) - 16.0)
				stops.append({"lane": lane, "action": "bus", "acc": a})
		if not stops.is_empty():
			m["goal"] = stops[randi() % stops.size()]
	elif purpose == "raus":
		m["goal"] = {"action": "raus"}


## Offene Straßenenden (Kartenrand): [Straße, Richtung hinein]
func _open_ends() -> Array:
	var out := []
	for ni in range(roads.nodes.size()):
		if roads.degree(ni) != 1:
			continue
		var e: Dictionary = roads.nodes[ni]["ends"][0]
		var l: Dictionary = e["line"]
		var d := 1 if bool(e["at_start"]) else -1
		if roads.lanes(l, d) > 0:
			out.append([l, d])
	return out


func _lane_free(l: Dictionary, d: int, k: int, pos: float, gap: float) -> bool:
	var key := "L%d|%d|%d" % [Roads.iid(l), d, k]
	for o: Dictionary in occupancy.get(key, []):
		var leg: Dictionary = o["legs"][0]
		if absf(float(leg["off"]) + float(o["s"]) - pos) < gap:
			return false
	return true


# ---------------------------------------------------------------- Wegplanung

## Dijkstra über gerichtete Straßen. goal_fn(l, d) -> true am Ziel. Gibt die Folge [l, d] ab dem nächsten Abschnitt zurück.
func _route(l: Dictionary, d: int, goal_fn: Callable) -> Array:
	var start_key := "%d|%d" % [Roads.iid(l), d]
	var dist := {start_key: 0.0}
	var prev := {}
	var state := {start_key: [l, d]}
	var open := [start_key]
	var done := {}
	while not open.is_empty():
		var bi := 0
		for i in range(open.size()):
			if float(dist[open[i]]) < float(dist[open[bi]]):
				bi = i
		var cur: String = open[bi]
		open.remove_at(bi)
		if done.has(cur):
			continue
		done[cur] = true
		var cl: Dictionary = state[cur][0]
		var cd: int = state[cur][1]
		if cur != start_key and goal_fn.call(cl, cd):
			var out := []
			var key := cur
			while key != start_key:
				out.push_front(state[key])
				key = prev[key]
			return out
		for ex: Array in roads.exits(cl, cd):
			var nk := "%d|%d" % [Roads.iid(ex[0]), int(ex[1])]
			var nd2 := float(dist[cur]) + float((ex[0]["samples"] as PackedVector3Array).size())
			if not dist.has(nk) or nd2 < float(dist[nk]):
				dist[nk] = nd2
				prev[nk] = cur
				state[nk] = ex
				if not open.has(nk):
					open.append(nk)
	return []


## Plant die nächste Kreuzung: Ziel prüfen, Ausfahrt wählen, Spurwechsel und Kurvenbogen anhängen.
func _plan(m: Dictionary) -> void:
	var legs: Array = m["legs"]
	var cur: Dictionary = legs[legs.size() - 1]
	if cur["type"] != "lane":
		return
	var l: Dictionary = cur["line"]
	var d: int = cur["d"]
	var k: int = cur["k"]
	var goal: Dictionary = m["goal"]
	# Ziel auf dieser Spur?
	if goal.has("lane"):
		var gl: Dictionary = goal["lane"]
		if is_same(gl["line"], l) and int(gl["d"]) == d and float(gl["pos"]) > float(cur["off"]) + float(m["s"]) + 4.0:
			if k != int(gl["k"]):
				_lane_change(m, int(gl["k"]), float(gl["pos"]) - 14.0)
			m["stop_at"] = float(gl["pos"])
			return
	m.erase("stop_at")
	var ni := roads.node_ahead(l, d)
	if roads.degree(ni) <= 1:
		m["exit_at_end"] = true
		return
	var options := roads.exits(l, d)
	if options.is_empty():
		m["exit_at_end"] = true
		return
	var route: Array = m["route"]
	if route.is_empty() or not _route_valid(route, l, d):
		route = _route_for(m, l, d)
		m["route"] = route
	var nxt: Array = options[randi() % options.size()]
	if not route.is_empty():
		nxt = route.pop_front()
	var nl: Dictionary = nxt[0]
	var nd: int = nxt[1]
	var turn := roads.turn_of(l, d, nl, nd)
	var n_out := roads.lanes(nl, nd)
	var n_in := roads.lanes(l, d)
	var want_k := k
	if n_in > 1:
		want_k = 0 if turn < 0 else (n_in - 1 if turn > 0 else k)
	var nk := 0 if turn < 0 else (n_out - 1 if turn > 0 else clampi(want_k, 0, n_out - 1))
	if want_k != k:
		var lane_len := Spline.length(roads.lane_path(l, d, k))
		var at := float(cur["off"]) + float(m["s"]) + 6.0
		if lane_len - at > 26.0:
			_lane_change(m, want_k, at)
			k = want_k
		else:
			nk = clampi(k, 0, n_out - 1)
	legs.append(_conn_leg(l, d, k, nl, nd, nk))
	legs.append(_lane_leg(nl, nd, nk))


func _route_valid(route: Array, l: Dictionary, d: int) -> bool:
	var first: Array = route[0]
	for ex: Array in roads.exits(l, d):
		if is_same(ex[0], first[0]) and int(ex[1]) == int(first[1]):
			return true
	return false


func _route_for(m: Dictionary, l: Dictionary, d: int) -> Array:
	var goal: Dictionary = m["goal"]
	if goal.has("lane"):
		var gl: Dictionary = goal["lane"]
		return _route(l, d, func(cl: Dictionary, cd: int) -> bool: return is_same(cl, gl["line"]) and cd == int(gl["d"]))
	var ends := _open_ends()
	if ends.is_empty():
		return []
	if goal.get("action", "") == "raus" or m["purpose"] == "durch":
		return _route(l, d, func(cl: Dictionary, cd: int) -> bool: return roads.degree(roads.node_ahead(cl, cd)) == 1)
	return []


## Spurwechsel: die aktuelle Spur endet bei at, ein Bogen führt auf Spur nk, dort geht es weiter.
func _lane_change(m: Dictionary, nk: int, at: float) -> void:
	var legs: Array = m["legs"]
	var cur: Dictionary = legs[legs.size() - 1]
	var l: Dictionary = cur["line"]
	var d: int = cur["d"]
	var k: int = cur["k"]
	var here := float(cur["off"]) + float(m["s"]) if legs.size() == 1 else float(cur["off"])
	at = maxf(at, here + 2.0)
	var a_path := roads.lane_path(l, d, k)
	var b_path := roads.lane_path(l, d, nk)
	var b_len := Spline.length(b_path)
	if at + 14.0 > b_len - 4.0:
		return
	# aktuelle Spur bis "at" kürzen
	var trimmed := _slice(a_path, float(cur["off"]), at)
	var new_cur := _make_leg("lane", trimmed, cur["key"], {"line": l, "d": d, "k": k, "arr_node": -1, "arr_end": -1})
	new_cur["off"] = cur["off"]
	legs[legs.size() - 1] = new_cur
	if legs.size() == 1:
		_reoccupy(m, cur, new_cur)
	var p0 := _point_on(a_path, at)
	var d0 := (_point_on(a_path, at + 1.0) - p0).normalized()
	var p3 := _point_on(b_path, at + 14.0)
	var d3 := (_point_on(b_path, at + 15.0) - p3).normalized()
	legs.append(_make_leg("change", _bezier(p0, d0, p3, d3), "W%d" % randi(), {"line": l, "d": d, "k": nk}))
	legs.append(_lane_leg(l, d, nk, at + 14.0))


# ---------------------------------------------------------------- Belegung

func _occupy(m: Dictionary, leg: Dictionary) -> void:
	var key: String = leg["key"]
	if not occupancy.has(key):
		occupancy[key] = []
	(occupancy[key] as Array).append(m)


func _release(m: Dictionary, leg: Dictionary) -> void:
	var key: String = leg["key"]
	if occupancy.has(key):
		(occupancy[key] as Array).erase(m)


func _reoccupy(m: Dictionary, old: Dictionary, new_leg: Dictionary) -> void:
	_release(m, old)
	_occupy(m, new_leg)


func _remove(m: Dictionary) -> void:
	_release(m, m["legs"][0])
	var node: Variant = m["node"]
	if is_instance_valid(node):
		(node as Node).queue_free()
	movers.erase(m)


# ---------------------------------------------------------------- Fahren

func _process(delta: float) -> void:
	var f: float = game.sim_factor()
	if f <= 0.0:
		return
	step(delta * minf(f, 3.0))


func step(dt: float) -> void:
	clock += dt
	roads.step(dt)
	if dirty:
		_find_access()
	adjust_timer -= dt
	if adjust_timer <= 0.0:
		adjust_timer = 1.0
		_spawn_tick()
	_parking_tick(dt)
	_bus_tick(dt)
	for m: Dictionary in movers.duplicate():
		_drive(m, dt)
	_animate_barriers(dt)
	_staff_shift(dt)
	_trains(dt)
	_step_peds(dt)
	_street_life(dt)


func _spawn_tick() -> void:
	target = compute_target()
	if movers.size() >= target:
		return
	var ends := _open_ends()
	for i in range(mini(3, target - movers.size())):
		if ends.is_empty():
			break
		var e: Array = ends[randi() % ends.size()]
		var l: Dictionary = e[0]
		var d: int = e[1]
		var k := randi() % roads.lanes(l, d)
		if not _lane_free(l, d, k, 0.0, 10.0):
			continue
		var r := randf()
		var purpose := "durch"
		if r < 0.45:
			purpose = "parkhaus"
		elif r < 0.75:
			purpose = "terminal"
		var kind := ""
		if purpose == "terminal" and _has("taxistand") and randf() < 0.35:
			kind = "taxi"
		var m := _spawn_on_lane(l, d, k, 0.0, purpose, kind)
		if (m["goal"] as Dictionary).is_empty() and purpose != "durch":
			m["purpose"] = "durch"


func _parking_tick(dt: float) -> void:
	for p: Array in parked.duplicate():
		p[1] = float(p[1]) - dt
		if float(p[1]) > 0.0:
			continue
		var a: Dictionary = access.get(int(p[0]), {})
		if a.is_empty():
			parked.erase(p)
			continue
		var lane: Dictionary = a["aus"]
		if not _lane_free(lane["line"], int(lane["d"]), int(lane["k"]), float(lane["pos"]) + 6.0, 14.0):
			continue
		parked.erase(p)
		_update_lot(int(p[0]))
		var path := roads.lane_path(lane["line"], int(lane["d"]), int(lane["k"]))
		var join := _point_on(path, float(lane["pos"]) + 6.0)
		var jdir := (_point_on(path, float(lane["pos"]) + 7.0) - join).normalized()
		var gate: Vector3 = a["gate_out"]
		var inside: Vector3 = a["inside_out"]
		var out_dir := (gate - inside).normalized()
		var drive := PackedVector3Array([inside, gate])
		drive.append_array(_bezier(gate, out_dir, join, jdir).slice(1))
		var legs := [_make_leg("drive", drive, "D%d" % randi(), {"gate": a["rec"], "gate_name": "SchrankeAus"}),
			_lane_leg(lane["line"], int(lane["d"]), int(lane["k"]), float(lane["pos"]) + 6.0)]
		var m := _spawn_with_legs(legs, "raus")
		m["v"] = 2.0
		game.earn_quiet(roundi(float(PARK_FEE) * float(game.fees["park"])), "Parken")


func _drive(m: Dictionary, dt: float) -> void:
	var legs: Array = m["legs"]
	var leg: Dictionary = legs[0]
	var s: float = m["s"]
	var v: float = m["v"]
	var vmax: float = m["vmax"]
	if leg["type"] == "conn":
		vmax = 6.5 if int(leg["turn"]) != 0 else 10.5
	elif leg["type"] == "drive" or leg["type"] == "change":
		vmax = minf(vmax, 7.0 if leg["type"] == "drive" else vmax)
	# Halt in der Haltebucht vor dem Terminal
	if float(m["halt"]) > 0.0:
		m["halt"] = float(m["halt"]) - dt
		m["v"] = 0.0
		m["brake"] = true
		m["blink"] = 1
		if m["purpose"] == "bus":
			# Türen auf, kurz vor der Abfahrt wieder zu
			var want := 1.0 if float(m["halt"]) > 1.4 else 0.0
			m["door"] = move_toward(float(m.get("door", 0.0)), want, dt * 1.2)
			Factory.set_bus_doors(m["node"], float(m["door"]))
		_place(m, dt)
		if float(m["halt"]) <= 0.0:
			if float(m.get("door", 0.0)) > 0.0:
				m["door"] = 0.0
				Factory.set_bus_doors(m["node"], 0.0)
			_rejoin(m)
		return
	var gap := _gap_ahead(m)
	var stop := _stop_distance(m)
	var free := minf(gap, stop)
	var want := vmax
	# vor Kurven langsamer werden
	if leg["type"] == "lane" and legs.size() > 1 and legs[1]["type"] == "conn" and int(legs[1]["turn"]) != 0:
		want = minf(want, 6.5 + (float(leg["len"]) - s) * 0.35)
	want = minf(want, sqrt(maxf(0.0, 2.0 * 4.5 * maxf(free - MIN_GAP, 0.0))))
	var nv := v + clampf(want - v, -BRAKE * dt, ACCEL * dt)
	if free < MIN_GAP:
		nv = 0.0
	m["brake"] = nv < v - 0.05 or nv < 0.3
	if nv < 0.2 and stop < MIN_GAP + 1.5:
		m["wait"] = float(m["wait"]) + dt
	elif nv > 1.0:
		m["wait"] = 0.0
	m["v"] = nv
	s += nv * dt
	# Leg-Wechsel
	while s >= float(leg["len"]):
		s -= float(leg["len"])
		if leg["type"] == "drive" and leg.has("gate"):
			_open_barrier(leg["gate"], String(leg["gate_name"]))
		if legs.size() == 1:
			_end_of_path(m, leg)
			return
		_release(m, leg)
		var prev: Array = m["prev"]
		prev.push_front(leg)
		if prev.size() > 2:
			prev.pop_back()
		legs.pop_front()
		leg = legs[0]
		if leg["type"] == "lane":
			m.erase("commit")
		_occupy(m, leg)
		if leg["type"] == "drive" and leg.has("gate"):
			_open_barrier(leg["gate"], String(leg["gate_name"]))
		if leg["type"] == "lane" and legs.size() == 1:
			m["s"] = s
			_plan(m)
	m["s"] = s
	# Ziel auf der Spur erreicht?
	if m.has("stop_at") and leg["type"] == "lane" and legs.size() == 1:
		var here := float(leg["off"]) + s
		if here >= float(m["stop_at"]) - 0.5:
			_reach_goal(m)
	# Blinker: nächste Abbiegung
	m["blink"] = 0
	for i in range(mini(2, legs.size())):
		var lg: Dictionary = legs[i]
		if lg["type"] == "conn" and (i == 0 or float(leg["len"]) - s < 35.0):
			m["blink"] = int(lg["turn"])
		elif lg["type"] == "change":
			m["blink"] = 1 if int(lg["k"]) > int(leg.get("k", 0)) else -1
	_place(m, dt)


## Abstand zum Vordermann (über die nächsten Legs).
func _gap_ahead(m: Dictionary) -> float:
	var legs: Array = m["legs"]
	var acc := 0.0
	var mine := float(legs[0]["off"]) + float(m["s"])
	var half := float(m["len"]) * 0.5
	for i in range(mini(3, legs.size())):
		var leg: Dictionary = legs[i]
		var best := INF
		for o: Dictionary in occupancy.get(leg["key"], []):
			if is_same(o, m):
				continue
			var ol: Dictionary = o["legs"][0]
			var pos := float(ol["off"]) + float(o["s"])
			var rel := pos - (mine if i == 0 else float(leg["off"]))
			if rel > 0.0 and rel < best:
				best = rel - float(o["len"]) * 0.5 - half
		if best < INF:
			return acc + best
		acc += float(leg["len"]) - (float(m["s"]) if i == 0 else 0.0)
		if acc > LOOK:
			break
	return INF


## Abstand bis zur Haltelinie, wenn Ampel oder Vorfahrt das Weiterfahren verbieten (sonst INF).
func _stop_distance(m: Dictionary) -> float:
	var legs: Array = m["legs"]
	var leg: Dictionary = legs[0]
	if m.has("stop_at") and leg["type"] == "lane":
		return float(m["stop_at"]) - (float(leg["off"]) + float(m["s"])) + MIN_GAP + 0.5
	if leg["type"] != "lane" or legs.size() < 2 or legs[1]["type"] != "conn":
		return INF
	var conn: Dictionary = legs[1]
	var ni: int = conn["node"]
	var ei: int = conn["from_e"]
	var rest := float(leg["len"]) - float(m["s"]) - float(m["len"]) * 0.5
	if rest > 40.0:
		return INF
	var ctrl := roads.control_of(ni)
	var must := false
	match ctrl:
		"ampel":
			var sig := roads.signal_at(ni, ei)
			var v: float = m["v"]
			if int(m.get("commit", -1)) == ni:
				must = false   # bei Gelb schon zu nah zum Anhalten: fährt durch
			elif sig == "rot":
				must = rest - STOP_BEFORE > v * v / (2.0 * 6.5) - 0.3
				if not must:
					m["commit"] = ni
			elif sig == "gelb":
				must = rest - STOP_BEFORE > v * v / (2.0 * 4.5) + 0.5
				if not must:
					m["commit"] = ni
		"vorfahrt":
			if not roads.is_major(ni, ei):
				must = _junction_busy(ni, ei) or _approaching(ni, roads.nodes[ni]["major"], 30.0)
		"rechts":
			var r := roads.right_of(ni, ei)
			must = _junction_busy(ni, ei) or (r >= 0 and _approaching(ni, [r], 22.0))
	# Linksabbieger lassen den Gegenverkehr durch (auch bei Grün)
	if not must and int(conn["turn"]) < 0:
		var opp := _opposite(ni, ei)
		if opp >= 0 and _approaching(ni, [opp], 26.0):
			must = true
		if _junction_busy_from(ni, opp):
			must = true
	if must and float(m["wait"]) > 7.0 and ctrl != "ampel":
		must = false   # niemand wartet ewig (verhindert Verklemmung)
	if not must:
		return INF
	# Haltelinie liegt 0.6 m vor dem Spurende (0.45 m breit); die Front hält gut einen Meter davor.
	# Wer die Linie schon überfahren hat, räumt die Kreuzung.
	if rest < 0.5:
		return INF
	return rest - STOP_BEFORE + MIN_GAP


func _junction_busy(ni: int, ei: int) -> bool:
	for o: Dictionary in movers:
		var ol: Dictionary = o["legs"][0]
		if ol["type"] == "conn" and int(ol["node"]) == ni and int(ol["from_e"]) != ei:
			return true
	return false


func _opposite(ni: int, ei: int) -> int:
	var ends: Array = roads.nodes[ni]["ends"]
	var mine: Vector3 = ends[ei]["out"]
	var best := -1
	var bd := -0.6
	for i in range(ends.size()):
		if i == ei:
			continue
		var dt := mine.dot(ends[i]["out"])
		if dt < bd:
			bd = dt
			best = i
	return best


func _junction_busy_from(ni: int, ei: int) -> bool:
	if ei < 0:
		return false
	for o: Dictionary in movers:
		var ol: Dictionary = o["legs"][0]
		if ol["type"] == "conn" and int(ol["node"]) == ni and int(ol["from_e"]) == ei and int(ol["turn"]) >= 0:
			return true
	return false


func _approaching(ni: int, ends: Array, within: float) -> bool:
	for o: Dictionary in movers:
		var ol: Dictionary = o["legs"][0]
		if ol["type"] != "lane" or int(ol.get("arr_node", -1)) != ni:
			continue
		if not (int(ol["arr_end"]) in ends):
			continue
		if float(ol["len"]) - float(o["s"]) < within and float(o["v"]) > 0.5:
			return true
	return false


## Aus der Haltebucht zurück auf die Spur und dann zum Kartenrand.
func _rejoin(m: Dictionary) -> void:
	var leg: Dictionary = m["legs"][0]
	var rj: Array = leg["rejoin"]
	var l: Dictionary = rj[0]
	var d: int = rj[1]
	var k: int = rj[2]
	var lane := roads.lane_path(l, d, k)
	var pos := minf(float(rj[3]), Spline.length(lane) - 3.0)
	var from := _leg_point(leg, float(leg["len"]))
	var fdir := (from - _leg_point(leg, float(leg["len"]) - 1.0)).normalized()
	var join := _point_on(lane, pos)
	var jdir := (_point_on(lane, pos + 1.0) - join).normalized()
	_release(m, leg)
	var back := _make_leg("drive", _bezier(from, fdir, join, jdir), "D%d" % randi())
	m["legs"] = [back, _lane_leg(l, d, k, pos)]
	m["s"] = 0.0
	m["purpose"] = "raus"
	_assign_goal(m)
	m["route"] = []
	m.erase("stop_at")
	m.erase("exit_at_end")
	_occupy(m, back)


func _trim_plan(m: Dictionary) -> void:
	var legs: Array = m["legs"]
	while legs.size() > 1:
		legs.pop_back()
	m.erase("stop_at")
	m.erase("exit_at_end")


func _reach_goal(m: Dictionary) -> void:
	var goal: Dictionary = m["goal"]
	m.erase("stop_at")
	match String(goal.get("action", "")):
		"halten":
			# rechts raus in die Haltebucht, damit die Spur frei bleibt
			var leg: Dictionary = m["legs"][0]
			var here := _leg_point(leg, float(m["s"]))
			var dir := (_leg_point(leg, float(m["s"]) + 1.0) - here).normalized()
			var right := dir.cross(Vector3.UP)
			var a := here + dir * 7.0 + right * 3.0
			var b := here + dir * 13.0 + right * 3.0
			var path := _bezier(here, dir, a, dir)
			path.append(b)
			_release(m, leg)
			var bay := _make_leg("drive", path, "D%d" % randi(), {"halt_end": true,
				"rejoin": [leg["line"], int(leg["d"]), int(leg["k"]), float(leg["off"]) + float(m["s"]) + 26.0]})
			m["legs"] = [bay]
			m["s"] = 0.0
			_occupy(m, bay)
		"bus":
			# Linienbus: in die Haltebucht vor der Haltestelle
			var leg: Dictionary = m["legs"][0]
			var here := _leg_point(leg, float(m["s"]))
			var dir := (_leg_point(leg, float(m["s"]) + 1.0) - here).normalized()
			var right := dir.cross(Vector3.UP)
			var a := here + dir * 10.0 + right * 3.2
			var b := here + dir * 22.0 + right * 3.2
			var path := _bezier(here, dir, a, dir)
			path.append(b)
			_release(m, leg)
			var bay := _make_leg("drive", path, "D%d" % randi(), {"halt_end": true, "bus_stop": goal["acc"],
				"rejoin": [leg["line"], int(leg["d"]), int(leg["k"]), float(leg["off"]) + float(m["s"]) + 36.0]})
			m["legs"] = [bay]
			m["s"] = 0.0
			_occupy(m, bay)
		"parken":
			var a: Dictionary = goal["acc"]
			var leg: Dictionary = m["legs"][0]
			var here := _leg_point(leg, float(m["s"]))
			var dir := (_leg_point(leg, float(m["s"]) + 1.0) - here).normalized()
			var gate: Vector3 = a["gate_in"]
			var inside: Vector3 = a["inside_in"]
			var in_dir := (inside - gate).normalized()
			var path := _bezier(here, dir, gate, in_dir)
			path.append(inside)
			_release(m, leg)
			var drive := _make_leg("drive", path, "D%d" % randi(), {"gate": a["rec"], "gate_name": "SchrankeEin", "park": a})
			m["legs"] = [drive]
			m["s"] = 0.0
			_occupy(m, drive)
			_open_barrier(a["rec"], "SchrankeEin")
		_:
			pass


func _end_of_path(m: Dictionary, leg: Dictionary) -> void:
	if leg.has("halt_end"):
		m["halt"] = randf_range(3.5, 6.5)
		m["s"] = float(leg["len"])
		m["v"] = 0.0
		if leg.has("bus_stop"):
			m["halt"] = 15.0
			_bus_arrived(m, leg["bus_stop"])
		else:
			# Fahrgäste steigen auf der Beifahrerseite aus und gehen zum Eingang
			var node: Node3D = m["node"]
			var right := node.basis.x
			for i in range(1 + randi() % 2):
				_ped_to_entrance(node.position + right * 1.6 + node.basis.z * float(i), "rein")
		return
	if leg.has("park"):
		var a: Dictionary = leg["park"]
		parked.append([(a["rec"]["node"] as Node).get_instance_id(), randf_range(40.0, 160.0)])
		_update_lot((a["rec"]["node"] as Node).get_instance_id())
		var xf := (a["rec"]["node"] as Node3D).transform
		for i in range(1 + randi() % 2):
			_ped_to_entrance(xf * Vector3(10.0 + float(i), 0, -23.0), "rein")
		_remove(m)
		return
	if bool(m.get("exit_at_end", false)) or leg["type"] != "lane":
		_remove(m)
		return
	# Sackgasse ohne Plan: neu planen
	_remove(m)


# ---------------------------------------------------------------- Darstellung

func _place(m: Dictionary, _dt: float) -> void:
	var half := float(m["len"]) * 0.32
	var front := _along(m, half)
	var back := _along(m, -half)
	var node: Node3D = m["node"]
	var dir := front - back
	var y := (front.y + back.y) * 0.5
	node.position = Vector3((front.x + back.x) * 0.5, y, (front.z + back.z) * 0.5)
	if dir.length_squared() > 0.0004:
		node.basis = Basis.looking_at(dir.normalized(), Vector3.UP)   # neigt sich auf Tunnelrampen
	# Karosserie nickt beim Bremsen und Anfahren, neigt sich in Kurven
	var body := node.get_node_or_null("Body") as Node3D
	if body != null and _dt > 0.0:
		var acc := (float(m["v"]) - float(m.get("pv", m["v"]))) / _dt
		m["pv"] = m["v"]
		m["acc"] = lerpf(float(m.get("acc", 0.0)), acc, clampf(_dt * 5.0, 0.0, 1.0))
		var hd := Vector3(dir.x, 0, dir.z).normalized() if dir.length_squared() > 0.0004 else Vector3.ZERO
		var turn := 0.0
		if m.has("ph") and hd != Vector3.ZERO:
			turn = (m["ph"] as Vector3).cross(hd).y / _dt
		if hd != Vector3.ZERO:
			m["ph"] = hd
		m["roll"] = lerpf(float(m.get("roll", 0.0)), clampf(turn * float(m["v"]) * 0.012, -0.045, 0.045), clampf(_dt * 4.0, 0.0, 1.0))
		body.rotation = Vector3(clampf(float(m["acc"]) * 0.006, -0.035, 0.035), 0, float(m["roll"]))
	# Untergeschoss-Ansicht: nur Autos im Tunnel zeigen
	node.visible = y < -1.0 or not (game.interior_view and game.view_floor < 0)
	var brake := node.get_node_or_null("Bremslicht") as Node3D
	if brake != null:
		brake.visible = bool(m["brake"])
	var on := fmod(clock, 0.8) < 0.4
	var bl := node.get_node_or_null("BlinkerL") as Node3D
	var br := node.get_node_or_null("BlinkerR") as Node3D
	if bl != null:
		bl.visible = on and int(m["blink"]) < 0
	if br != null:
		br.visible = on and int(m["blink"]) > 0


## Punkt im Abstand off vor (oder hinter) der Wagenmitte entlang der geplanten Strecke.
func _along(m: Dictionary, off: float) -> Vector3:
	var legs: Array = m["legs"]
	var s := float(m["s"]) + off
	if s >= 0.0:
		for leg: Dictionary in legs:
			if s <= float(leg["len"]):
				return _leg_point(leg, s)
			s -= float(leg["len"])
		var last: Dictionary = legs[legs.size() - 1]
		return _leg_point(last, float(last["len"]))
	for leg: Dictionary in m["prev"]:
		s += float(leg["len"])
		if s >= 0.0:
			return _leg_point(leg, s)
	return _leg_point(legs[0], 0.0) + (_leg_point(legs[0], 0.0) - _leg_point(legs[0], 1.0)) * (-s)


# ---------------------------------------------------------------- Schranken

func _open_barrier(rec: Dictionary, name: String) -> void:
	var node: Variant = rec.get("node")
	if not is_instance_valid(node):
		return
	var arm := (node as Node3D).get_node_or_null(name) as Node3D
	if arm != null:
		barriers[arm] = clock + 2.5


func _animate_barriers(dt: float) -> void:
	for key: Variant in barriers.keys():
		if not is_instance_valid(key):
			barriers.erase(key)
			continue
		var arm := key as Node3D
		var open := clock < float(barriers[key])
		var goal := deg_to_rad(80.0) if open else 0.0
		arm.rotation.z = move_toward(arm.rotation.z, goal, dt * 3.0)
		if not open and is_zero_approx(arm.rotation.z):
			barriers.erase(key)


## Parkplatz: so viele Autos zeigen, wie dort geparkt sind.
func _update_lot(iid: int) -> void:
	var a: Dictionary = access.get(iid, {})
	if a.is_empty() or a["rec"]["id"] != "parkplatz":
		return
	var node: Node3D = a["rec"]["node"]
	var n := parked_count(a["rec"])
	for i in range(22):
		var car := node.get_node_or_null("Platz%d" % i) as Node3D
		if car != null:
			car.visible = i < n


func parked_count(rec: Dictionary) -> int:
	var n := 0
	var id := (rec["node"] as Node).get_instance_id()
	for p: Array in parked:
		if int(p[0]) == id:
			n += 1
	return n


func has_access(rec: Dictionary) -> bool:
	if dirty:
		_find_access()
	return access.has((rec["node"] as Node).get_instance_id())


# ---------------------------------------------------------------- Linienbusse und Fußgänger

func has_bus_line() -> bool:
	for key: int in access:
		if (access[key] as Dictionary).has("bus"):
			return true
	return false


## Alle 40 Sekunden kommt ein Linienbus von einem Kartenrand, hält an einer Haltestelle und fährt weiter.
func _bus_tick(dt: float) -> void:
	bus_timer -= dt
	stop_timer -= dt
	if stop_timer <= 0.0:
		stop_timer = 7.0
		_stop_waiters()
	if bus_timer > 0.0:
		return
	bus_timer = BUS_EVERY * randf_range(0.8, 1.2)
	if not has_bus_line():
		return
	var buses := 0
	for m: Dictionary in movers:
		if m["purpose"] == "bus":
			buses += 1
	if buses >= 3:
		return
	var ends := _open_ends()
	if ends.is_empty():
		return
	for _t in range(4):
		var e: Array = ends[randi() % ends.size()]
		var l: Dictionary = e[0]
		var d: int = e[1]
		var k := roads.lanes(l, d) - 1
		if _lane_free(l, d, k, 0.0, 18.0):
			var m := _spawn_on_lane(l, d, k, 0.0, "bus", "linienbus")
			if (m["goal"] as Dictionary).is_empty():
				m["purpose"] = "durch"
			return


## Bus hält: Fahrgäste steigen hinten aus und gehen zum Terminal, Wartende steigen vorn ein.
func _bus_arrived(m: Dictionary, a: Dictionary) -> void:
	var node: Node3D = m["node"]
	var right := node.basis.x
	var fwd := -node.basis.z
	var n := 3 + randi() % 8
	for i in range(n):
		var door := node.position + right * 1.7 - fwd * ([-0.4, 3.9][i % 2] as float) + fwd * randf_range(-0.4, 0.4)
		_ped_to_entrance(door, "rein", float(i) * 0.6)
	var stop_id := (a["rec"]["node"] as Node).get_instance_id()
	var front := node.position + right * 1.7 + fwd * 5.0
	var k := 0
	for pd: Dictionary in peds:
		if String(pd["state"]) == "wartet" and int(pd.get("stop", -1)) == stop_id:
			pd["state"] = "geht"
			pd["action"] = "einsteigen"
			pd["pts"] = PackedVector3Array([pd["pos"], front])
			pd["i"] = 0
			pd["delay"] = float(k) * 0.8 + 1.0
			k += 1
	m["halt"] = maxf(15.0, float(k) * 0.8 + 6.0)


## Abfliegende Fahrgäste gehen vom Terminal zur Haltestelle und warten unter dem Dach.
func _stop_waiters() -> void:
	if entrances.is_empty():
		return
	for key: int in access:
		var a: Dictionary = access[key]
		if not a.has("bus"):
			continue
		var waiting := 0
		for pd: Dictionary in peds:
			if int(pd.get("stop", -1)) == key:
				waiting += 1
		if waiting >= 7 or randf() < 0.4:
			continue
		var xf: Transform3D = a["xf"]
		var spot := xf * Vector3(randf_range(-2.4, 2.4), 0, randf_range(0.4, 1.2))
		var e: Array = entrances[randi() % entrances.size()]
		var start: Vector3 = (e[0] as Vector3) + (e[1] as Vector3) * 1.0
		var pd := _ped(PackedVector3Array([start, start.lerp(spot, 0.5), spot]), "warten")
		if not pd.is_empty():
			pd["stop"] = key
			pd["face"] = xf.basis * Vector3(0, 0, -1)


func _ped_to_entrance(from: Vector3, action: String, delay: float = 0.0) -> void:
	if entrances.is_empty():
		return
	var best: Array = entrances[0]
	for e: Array in entrances:
		if (e[0] as Vector3).distance_to(from) < (best[0] as Vector3).distance_to(from):
			best = e
	var goal: Vector3 = best[0]
	var door: Vector3 = goal - (best[1] as Vector3) * 3.5
	var pd := _ped(PackedVector3Array([from, from.lerp(goal, 0.5), goal, door]), action)
	if not pd.is_empty():
		pd["delay"] = delay


func _ped(pts: PackedVector3Array, action: String, staff: bool = false) -> Dictionary:
	if peds.size() >= PED_MAX:
		return {}
	var node: Node3D
	if staff:
		var vest := randf() < 0.45
		node = Factory.make_staff(Color(0.2, 0.3, 0.52) if not vest else Color(0.28, 0.3, 0.33), Color(0.12, 0.13, 0.18), randi() % 4, vest)
	else:
		node = Factory.make_person(Factory.SHIRTS[randi() % Factory.SHIRTS.size()])
	add_child(node)
	node.position = pts[0]
	# jeder geht etwas versetzt (weicht den anderen aus) und in eigenem Tempo
	var off := randf_range(-0.8, 0.8)
	var shifted := PackedVector3Array()
	for i in range(pts.size()):
		var d := pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]
		d.y = 0.0
		var side := d.normalized().cross(Vector3.UP) if d.length() > 0.01 else Vector3.ZERO
		shifted.append(pts[i] + side * (off if i > 0 and i < pts.size() - 1 else off * 0.3))
	var pd := {"node": node, "pts": shifted, "i": 0, "pos": shifted[0], "walk": 0.0, "action": action,
		"state": "geht", "speed": WALK * randf_range(0.85, 1.15), "delay": 0.0}
	peds.append(pd)
	return pd


func _step_peds(dt: float) -> void:
	var hide := game.interior_view and game.view_floor < 0
	for pd: Dictionary in peds.duplicate():
		var node: Node3D = pd["node"]
		if not is_instance_valid(node):
			peds.erase(pd)
			continue
		node.visible = not hide and float(pd["delay"]) <= 0.0
		if float(pd["delay"]) > 0.0:
			pd["delay"] = float(pd["delay"]) - dt
			continue
		if String(pd["state"]) == "wartet":
			Factory.set_pose(node, 0)
			continue
		var pts: PackedVector3Array = pd["pts"]
		var i: int = pd["i"]
		var pos: Vector3 = pd["pos"]
		var budget := float(pd["speed"]) * dt
		# Abstand halten: langsamer, wenn jemand direkt voraus geht
		if i < pts.size() - 1:
			var dirv := (pts[i + 1] - pos)
			dirv.y = 0.0
			if dirv.length() > 0.01:
				dirv = dirv.normalized()
				for o: Dictionary in peds:
					if is_same(o, pd) or String(o["state"]) == "wartet":
						continue
					var d := (o["pos"] as Vector3) - pos
					if d.length() < 0.9 and d.dot(dirv) > 0.3:
						budget *= 0.35
						break
		var look := Vector3.ZERO
		while budget > 0.0 and i < pts.size() - 1:
			var target := pts[i + 1]
			var dd := pos.distance_to(target)
			look = target - pos
			if dd <= budget:
				budget -= dd
				pos = target
				i += 1
			else:
				pos += look / dd * budget
				budget = 0.0
		pd["walk"] = float(pd["walk"]) + float(pd["speed"]) * dt
		pd["pos"] = pos
		pd["i"] = i
		node.position = pos
		look.y = 0.0
		Factory.walk(node, float(pd["walk"]), look, dt)
		if i >= pts.size() - 1:
			if String(pd["action"]) == "warten":
				pd["state"] = "wartet"
				var face: Vector3 = pd.get("face", Vector3.ZERO)
				if face.length() > 0.1:
					node.basis = Basis.looking_at(face.normalized(), Vector3.UP)
			else:
				node.queue_free()
				peds.erase(pd)


# ---------------------------------------------------------------- Schichtwechsel

var _shift_t := 0.0


## Zum Schichtwechsel (5:30, 13:30, 21:30) laufen Mitarbeiter vom Personalgebäude zum Terminal
## und die abgelösten zurück.
func _staff_shift(dt: float) -> void:
	_shift_t -= dt
	if _shift_t > 0.0:
		return
	_shift_t = randf_range(1.5, 4.0)
	var m := fmod(game.minutes, 1440.0)
	var on := false
	for t: float in [330.0, 810.0, 1290.0]:
		if m >= t - 20.0 and m < t + 20.0:
			on = true
	if not on or entrances.is_empty():
		return
	var blds: Array = game.items_of("personalgebaeude")
	if blds.is_empty():
		return
	var bld: Dictionary = blds[randi() % blds.size()]
	var b := Basis(Vector3.UP, float(bld["rot"]) * PI * 0.5)
	var door: Vector3 = (bld["pos"] as Vector3) + b * Vector3(randf_range(-1.0, 1.0), 0, 6.4)
	var front: Vector3 = (bld["pos"] as Vector3) + b * Vector3(randf_range(-2.0, 2.0), 0, 10.0)
	var e: Array = entrances[0]
	for en: Array in entrances:
		if (en[0] as Vector3).distance_to(front) < (e[0] as Vector3).distance_to(front):
			e = en
	var goal: Vector3 = (e[0] as Vector3) + Vector3(randf_range(-1.5, 1.5), 0, 0)
	var inside: Vector3 = goal - (e[1] as Vector3) * 3.5
	if randf() < 0.5:
		_ped(PackedVector3Array([door, front, front.lerp(goal, 0.5), goal, inside]), "rein", true)
	else:
		_ped(PackedVector3Array([inside, goal, goal.lerp(front, 0.5), front, door]), "weg", true)


# ---------------------------------------------------------------- S-Bahn, Taxis, Kiss & Fly, Mietwagen

var train_t: Dictionary = {}       # Bahnhof (Instanz-ID) -> Zeit im Zugumlauf


func _has(id: String) -> bool:
	for key: int in access:
		if (access[key] as Dictionary).has(id):
			return true
	return false


## S-Bahnhof mit Strom, höchstens 300 m vom nächsten Terminal entfernt?
func station_ok() -> bool:
	for it: Dictionary in game.items_of("bahnhof"):
		if not game.supplied(it, "strom"):
			continue
		var p: Vector3 = it["pos"]
		for h: Dictionary in game.items_of("halle"):
			if (h["rect"] as Rect2).grow(300.0).has_point(Vector2(p.x, p.z)):
				return true
	return false


## Einflüsse der Landseite auf die Zufriedenheit: [Text, Punkte]
func landside_factors() -> Array:
	if dirty:
		_find_access()
	var out := []
	if station_ok():
		out.append(["S-Bahn-Anschluss", 4])
	elif not game.items_of("bahnhof").is_empty():
		out.append(["S-Bahnhof ohne Strom oder zu weit vom Terminal", -1])
	if _has("taxistand"):
		out.append(["Taxistand am Terminal", 2])
	if _has("kissandfly"):
		out.append(["Kiss & Fly: Bringen und Abholen ohne Gedränge", 2])
	for it: Dictionary in game.items_of("mietwagen"):
		if game.supplied(it, "strom") and access.has((it["node"] as Node).get_instance_id()):
			out.append(["Mietwagenzentrum", 2])
			break
	# Straßenraum: Bäume und Radwege machen die Anreise angenehmer
	var meters := {"allee": 0.0, "rad": 0.0}
	for l: Dictionary in roads.roads():
		var sd := String(l.get("side", ""))
		if meters.has(sd):
			meters[sd] = float(meters[sd]) + Spline.length(l["samples"] as PackedVector3Array)
	if float(meters["allee"]) >= 150.0:
		out.append(["Alleen an der Zufahrt", 1])
	if float(meters["rad"]) >= 150.0:
		out.append(["Radwege zum Flughafen", 1])
	return out


## Züge: alle zwei Minuten fährt eine S-Bahn ein, hält 25 Sekunden (Fahrgäste gehen zum Terminal) und fährt weiter.
func _trains(dt: float) -> void:
	for it: Dictionary in game.items_of("bahnhof"):
		var node: Node3D = it["node"]
		var z := node.get_node_or_null("Zug") as Node3D
		if z == null:
			continue
		var key := node.get_instance_id()
		var t := float(train_t.get(key, randf_range(0.0, 60.0))) + dt
		if not game.supplied(it, "strom"):
			z.visible = false
			train_t[key] = t
			continue
		const ARRIVE := 14.0
		const STOP := 25.0
		const LEAVE := 14.0
		const CYCLE := 120.0
		if t > CYCLE:
			t -= CYCLE
		train_t[key] = t
		var x := 0.0
		if t < ARRIVE:
			var f := t / ARRIVE
			x = -48.0 * pow(1.0 - f, 2.0)
		elif t < ARRIVE + STOP:
			x = 0.0
			if not bool(z.get_meta("unloaded", false)):
				z.set_meta("unloaded", true)
				if station_ok():
					var xf := node.transform
					for i in range(3 + randi() % 4):
						_ped_to_entrance(xf * Vector3(randf_range(-3.0, 3.0), 0, 9.5), "rein", float(i) * 0.8)
		elif t < ARRIVE + STOP + LEAVE:
			var f := (t - ARRIVE - STOP) / LEAVE
			x = 48.0 * f * f
		else:
			z.visible = false
			z.set_meta("unloaded", false)
			continue
		z.visible = true
		z.position.x = x

# ---------------------------------------------------------------- Leben auf Gehwegen und Radwegen

## Spaziergänger auf Gehwegen und Radfahrer auf Radwegen (je nach Querschnitt der Straßen).
func _street_life(dt: float) -> void:
	life_timer -= dt
	if life_timer <= 0.0:
		life_timer = 2.5
		_spawn_street_life()
	var hide := game.interior_view and game.view_floor < 0
	for b: Dictionary in bikes.duplicate():
		var node: Node3D = b["node"]
		if not is_instance_valid(node):
			bikes.erase(b)
			continue
		b["s"] = float(b["s"]) + float(b["speed"]) * dt
		if float(b["s"]) >= float(b["len"]):
			node.queue_free()
			bikes.erase(b)
			continue
		var path: PackedVector3Array = b["path"]
		var p := _path_at(path, float(b["s"]))
		var ahead := _path_at(path, float(b["s"]) + 1.0)
		node.position = p
		node.visible = not hide
		Factory.face(node, ahead - p, dt)
		# Tretkurbel: eine Umdrehung auf gut 4 m (Übersetzung eines Stadtrads)
		var frame := int(fposmod(float(b["s"]), 4.2) / 4.2 * float(Models.WALK_FRAMES)) % Models.WALK_FRAMES
		Factory.set_pose(b["rider"], 20 + frame)


func _path_at(path: PackedVector3Array, s: float) -> Vector3:
	var run := 0.0
	for i in range(1, path.size()):
		var seg := path[i].distance_to(path[i - 1])
		if run + seg >= s:
			return path[i - 1].lerp(path[i], (s - run) / maxf(seg, 0.001))
		run += seg
	return path[path.size() - 1]


func _spawn_street_life() -> void:
	var walk_roads := []
	var bike_roads := []
	for l: Dictionary in roads.roads():
		var side := String(l.get("side", "ohne"))
		if side == "ohne" or not Catalog.has_sides(String(l["kind"])):
			continue
		if Spline.length(l["samples"] as PackedVector3Array) < 40.0:
			continue
		walk_roads.append(l)
		if side == "rad":
			bike_roads.append(l)
	var quiet := 0.5 if game.night > 0.6 else 1.0
	var strollers := 0
	for pd: Dictionary in peds:
		if bool(pd.get("stroll", false)):
			strollers += 1
	if not walk_roads.is_empty() and strollers < int(float(mini(STROLL_MAX, walk_roads.size() * 3)) * quiet):
		var l: Dictionary = walk_roads[randi() % walk_roads.size()]
		var w: float = Catalog.LINES[l["kind"]]["width"]
		var v := Streetscape.width_of(String(l["side"]))
		var sg := 1 if randf() < 0.5 else -1
		var path := roads.side_path(l, sg, w * 0.5 + v - 1.25)
		if path.size() >= 2:
			if randf() < 0.5:
				path.reverse()
			var pd := _ped(path, "")
			if not pd.is_empty():
				pd["stroll"] = true
				pd["speed"] = WALK * randf_range(0.7, 1.0)
	if not bike_roads.is_empty() and bikes.size() < int(float(mini(BIKE_MAX, bike_roads.size() * 4)) * quiet):
		var l: Dictionary = bike_roads[randi() % bike_roads.size()]
		var w: float = Catalog.LINES[l["kind"]]["width"]
		var sg := 1 if randf() < 0.5 else -1
		var path := roads.side_path(l, sg, w * 0.5 + 1.8)
		if path.size() < 2:
			return
		if sg < 0:
			path.reverse()   # Rechtsverkehr auch auf dem Radweg
		var node := Node3D.new()
		var cols := [Color(0.15, 0.3, 0.6), Color(0.7, 0.12, 0.1), Color(0.1, 0.1, 0.1), Color(0.85, 0.85, 0.82), Color(0.15, 0.45, 0.25)]
		var bm := MeshInstance3D.new()
		bm.mesh = Streetscape.bike_mesh(cols[randi() % cols.size()])
		node.add_child(bm)
		var rider := Factory.make_person(Factory.SHIRTS[randi() % Factory.SHIRTS.size()])
		rider.position = Vector3(0, 0.06, 0.12)
		node.add_child(rider)
		add_child(node)
		node.position = path[0]
		bikes.append({"node": node, "rider": rider, "path": path, "s": 0.0, "len": Spline.length(path),
			"speed": randf_range(4.0, 6.0)})
