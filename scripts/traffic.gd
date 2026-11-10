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

const CARS_PER_MOVEMENT := 5
const MIN_GAP := 2.2
const STOP_BEFORE := 1.7   # Abstand Spurende → Fahrzeugfront beim Halt (Haltelinie bei 0.6 m)
const LOOK := 45.0
const ACCEL := 2.6
const BRAKE := 7.0
const PARK_FEE := 6

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
	return mini(160, int(total / 70.0) + game.traffic_demand * CARS_PER_MOVEMENT)


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
	for it: Dictionary in game.items_of("parkhaus"):
		var def: Dictionary = Catalog.ITEMS["parkhaus"]
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
	for h: Dictionary in game.items_of("halle"):
		for it: Dictionary in game.inside_of(h):
			if it["id"] != "eingang":
				continue
			var lp := _nearest_lane(it["pos"], 40.0)
			if not lp.is_empty():
				access[(h["node"] as Node).get_instance_id()] = {"rec": h, "halt": lp}
				break


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

func _spawn_on_lane(l: Dictionary, d: int, k: int, pos: float, purpose: String) -> Dictionary:
	var leg := _lane_leg(l, d, k, pos)
	return _spawn_with_legs([leg], purpose)


func _spawn_with_legs(legs: Array, purpose: String) -> Dictionary:
	var node := Factory.make_car(Factory.car_color())
	add_child(node)
	var kind: String = node.get_meta("kind")
	var length: float = Models.CAR_DIMS[kind][0]
	var vmax := randf_range(11.5, 14.5)
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
			elif purpose == "terminal" and a.has("halt"):
				options.append({"lane": a["halt"], "action": "halten", "acc": a})
		if not options.is_empty():
			m["goal"] = options[randi() % options.size()]
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
	for m: Dictionary in movers.duplicate():
		_drive(m, dt)
	_animate_barriers(dt)


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
		var m := _spawn_on_lane(l, d, k, 0.0, purpose)
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
		game.earn_quiet(PARK_FEE)


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
		_place(m, dt)
		if float(m["halt"]) <= 0.0:
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
			if sig == "rot":
				must = true
			elif sig == "gelb":
				var v: float = m["v"]
				must = rest - STOP_BEFORE > v * v / (2.0 * 4.5) + 0.5
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
		return
	if leg.has("park"):
		var a: Dictionary = leg["park"]
		parked.append([(a["rec"]["node"] as Node).get_instance_id(), randf_range(40.0, 160.0)])
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
	dir.y = 0.0
	node.position = Vector3((front.x + back.x) * 0.5, 0.0, (front.z + back.z) * 0.5)
	if dir.length_squared() > 0.0004:
		node.basis = Basis.looking_at(dir.normalized(), Vector3.UP)
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
