extends Node3D
## Rollender Verkehr: Autos fahren auf Straßen (rechts) und halten Abstand.
## An verbundenen Enden biegen sie auf die nächste Straße ab. An offenen Enden (Kartenrand)
## kommen neue Autos herein oder fahren hinaus. Wie viele unterwegs sind, hängt vom Flugbetrieb ab:
## Jede Landung und jeder Start der letzten Spielstunde bringt zusätzliche Autos.

const Spline = preload("res://scripts/spline.gd")
const Factory = preload("res://scripts/factory.gd")
const GameState = preload("res://scripts/game_state.gd")

const LINK_DIST := 2.5
const CARS_PER_MOVEMENT := 5
const GAP := 9.0

var game: GameState
var movers: Array = []
var target := 0
var adjust_timer := 0.0


func setup(g: GameState) -> void:
	game = g
	game.network_changed.connect(rebuild)


func _roads() -> Array:
	var out := []
	for l: Dictionary in game.lines:
		if l["kind"] == "strasse":
			out.append(l)
	return out


func compute_target() -> int:
	var total := 0.0
	for l: Dictionary in _roads():
		total += float((l["samples"] as PackedVector3Array).size() - 1)
	if total <= 0.0:
		return 0
	return mini(160, int(total / 70.0) + game.traffic_demand * CARS_PER_MOVEMENT)


func rebuild() -> void:
	for m: Dictionary in movers:
		var node: Variant = m["node"]
		if is_instance_valid(node):
			(node as Node).queue_free()
	movers.clear()
	target = compute_target()
	var roads := _roads()
	if roads.is_empty():
		return
	for i in range(target):
		var l: Dictionary = roads[randi() % roads.size()]
		var length := float((l["samples"] as PackedVector3Array).size() - 1)
		_spawn(l, randf() * length, 1 if randf() < 0.5 else -1)


func _spawn(line: Dictionary, d: float, dir: int) -> void:
	var node := Factory.make_car(Factory.car_color())
	add_child(node)
	var speed := randf_range(10.0, 14.0)
	var m := {"node": node, "line": line, "d": d, "dir": dir, "speed": speed, "vmax": speed, "lane": 1.9}
	movers.append(m)
	_place(m)


## Offene Straßenenden (ohne Anschluss), dort kommen Autos herein.
func _open_ends() -> Array:
	var out := []
	for l: Dictionary in _roads():
		var s: PackedVector3Array = l["samples"]
		for far: bool in [false, true]:
			var e: Vector3 = s[s.size() - 1] if far else s[0]
			if _links(l, e).is_empty():
				out.append([l, float(s.size() - 1) if far else 0.0, -1 if far else 1])
	return out


func _links(line: Dictionary, end_point: Vector3) -> Array:
	var options := []
	for other: Dictionary in game.lines:
		if is_same(other, line) or other["kind"] != "strasse":
			continue
		var os: PackedVector3Array = other["samples"]
		if os[0].distance_to(end_point) < LINK_DIST:
			options.append([other, 0.0, 1])
		elif os[os.size() - 1].distance_to(end_point) < LINK_DIST:
			options.append([other, float(os.size() - 1), -1])
	return options


func _process(delta: float) -> void:
	var f: float = game.sim_factor()
	if f <= 0.0:
		return
	delta *= minf(f, 3.0)
	adjust_timer -= delta
	if adjust_timer <= 0.0:
		adjust_timer = 1.0
		target = compute_target()
		if movers.size() < target:
			var ends := _open_ends()
			for i in range(mini(3, target - movers.size())):
				if ends.is_empty():
					break
				var e: Array = ends[randi() % ends.size()]
				_spawn(e[0], e[1], e[2])
	_follow_gaps()
	for m: Dictionary in movers.duplicate():
		var s: PackedVector3Array = (m["line"] as Dictionary)["samples"]
		var length := float(s.size() - 1)
		var d: float = float(m["d"]) + float(m["dir"]) * float(m["speed"]) * delta
		m["d"] = d
		if d > length or d < 0.0:
			if not _at_end(m, d > length):
				continue
		_place(m)


## Autos bremsen hinter einem langsameren Auto auf derselben Spur.
func _follow_gaps() -> void:
	for m: Dictionary in movers:
		var v: float = m["vmax"]
		for o: Dictionary in movers:
			if is_same(o, m) or not is_same(o["line"], m["line"]) or int(o["dir"]) != int(m["dir"]):
				continue
			var ahead := (float(o["d"]) - float(m["d"])) * float(m["dir"])
			if ahead > 0.0 and ahead < GAP * 2.0:
				v = minf(v, float(o["speed"]) * clampf((ahead - GAP * 0.6) / GAP, 0.0, 1.0))
		m["speed"] = v


## Am Straßenende: abbiegen, hinausfahren (zu viele Autos) oder wenden. false = Auto entfernt.
func _at_end(m: Dictionary, far_end: bool) -> bool:
	var line: Dictionary = m["line"]
	var s: PackedVector3Array = line["samples"]
	var end_point: Vector3 = s[s.size() - 1] if far_end else s[0]
	var options := _links(line, end_point)
	if options.is_empty():
		if movers.size() > target:
			(m["node"] as Node).queue_free()
			movers.erase(m)
			return false
		m["dir"] = -int(m["dir"])
		m["d"] = float(s.size() - 1) if far_end else 0.0
		return true
	var pick: Array = options[randi() % options.size()]
	m["line"] = pick[0]
	m["d"] = pick[1]
	m["dir"] = pick[2]
	return true


func _place(m: Dictionary) -> void:
	var s: PackedVector3Array = (m["line"] as Dictionary)["samples"]
	var d: float = m["d"]
	var t := Spline.dir_at(s, d) * float(m["dir"])
	var pos := Spline.sample_at(s, d) + t.cross(Vector3.UP) * float(m["lane"])
	var node: Node3D = m["node"]
	node.position = Vector3(pos.x, 0.0, pos.z)
	node.basis = Basis.looking_at(t, Vector3.UP)
