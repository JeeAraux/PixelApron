extends Node3D
## Flugbetrieb: Flüge nach Plan anlegen, Anflug, Landung, Rollen zum Stand, Abfertigung
## mit Bodenfahrzeugen, Rollen zur Piste, Start.
## Rollwege werden wie im Stellwerk abschnittsweise reserviert; die Piste nutzt immer nur ein Flugzeug.
## Bei Tempo 1× vergeht pro Sekunde eine halbe Spielminute; Bewegungen in Metern pro Sekunde.

const Catalog = preload("res://scripts/catalog.gd")
const Factory = preload("res://scripts/factory.gd")
const Airside = preload("res://scripts/airside.gd")
const GameState = preload("res://scripts/game_state.gd")

const TAXI_SPEED := 20.0
const CLOCK := 0.5             # Spielminuten pro Simulationssekunde
const INTERVAL := 7.0          # Spielminuten zwischen neuen Flügen bei mittlerer Zufriedenheit
const APPROACH_DIST := 2200.0
const GLIDE := 0.0524          # 3 Grad
const LOOKAHEAD := 70.0        # so weit voraus reserviert ein rollendes Flugzeug
const GSE_SPEED := 9.0

var game: GameState
var graph := Airside.new()
var dirty := true
var planes: Array = []
var reserved: Dictionary = {}  # Knoten -> Flugzeug-ID
var runway_owner := -1
var next_flight := 2.0
var counter := 0
var done := 0
var reason := ""               # warum gerade keine Flüge kommen
var hint := ""                 # Hinweis, der den Betrieb bremst
var movements: Array = []      # Spielminuten der letzten Landungen und Starts
var pax_log: Array = []        # [Spielminute, Passagiere, Abflug?] der letzten zwei Stunden
var terminal: Variant = null   # terminal.gd (Gates, Passagiere, Kapazität)
var gate_short := 0.0          # Spielminuten, in denen noch "zu wenige Gates" gemeldet wird


func setup(g: GameState) -> void:
	game = g
	game.network_changed.connect(_mark_dirty)
	game.items_changed.connect(_mark_dirty)


func _mark_dirty() -> void:
	dirty = true


func _process(delta: float) -> void:
	step(delta * game.sim_factor())


## Ein Simulationsschritt; sim = vergangene Simulationssekunden (auch für Tests nutzbar).
func step(sim: float) -> void:
	if sim <= 0.0:
		return
	if dirty:
		_rebuild()
	game.advance(sim * CLOCK)
	next_flight -= sim * CLOCK
	if next_flight <= 0.0:
		next_flight = INTERVAL * lerpf(1.6, 0.55, game.satisfaction / 100.0)
		_try_spawn()
	for p: Dictionary in planes.duplicate():
		_update(p, sim)
	while not movements.is_empty() and float(movements[0]) < game.minutes - 60.0:
		movements.pop_front()
	game.traffic_demand = movements.size()
	# Passagiere pro Stunde, gemittelt über zwei Stunden
	while not pax_log.is_empty() and float(pax_log[0][0]) < game.minutes - 120.0:
		pax_log.pop_front()
	var arr := 0.0
	var dep := 0.0
	for e: Array in pax_log:
		if bool(e[2]):
			dep += float(e[1])
		else:
			arr += float(e[1])
	gate_short = maxf(0.0, gate_short - sim * CLOCK)
	if terminal != null:
		terminal.set_demand(arr * 0.5, dep * 0.5)
		terminal.step(sim)
	_satisfaction(sim)


func _rebuild() -> void:
	dirty = false
	graph.build(game.lines, game.stands())
	reserved.clear()
	for p: Dictionary in planes.duplicate():
		var st: Dictionary = p["stand"]
		if not st.is_empty() and not is_instance_valid(st["node"]):
			_remove(p, "%s: Stand wurde abgerissen" % p["code"])
			continue
		p["path"] = []   # wird beim nächsten Schritt neu gesucht
		if p["state"] == "abfertigung":
			_reserve(graph.stand_node.get((st["node"] as Node).get_instance_id(), -1), int(p["id"]))


# ---------------------------------------------------------------- Flugplan

func _runway() -> Dictionary:
	var best: Dictionary = {}
	var best_len := 0.0
	for l: Dictionary in game.lines:
		if l["kind"] == "piste":
			var s: PackedVector3Array = l["samples"]
			var length := float(s.size() - 1)
			if length > best_len:
				best_len = length
				best = l
	return best


## Prüft, ob der Flughafen gerade Flüge abfertigen kann. Leerer Text = ja.
func check_operation() -> String:
	var rwy := _runway()
	if rwy.is_empty():
		return "Keine Piste"
	var length := float((rwy["samples"] as PackedVector3Array).size() - 1)
	if length < float(Catalog.PLANES["atr"]["min_rwy"]):
		return "Piste zu kurz (mindestens 1.200 m)"
	var towers := game.items_of("tower")
	if towers.is_empty():
		return "Kein Tower"
	var tower_ok := false
	for t: Dictionary in towers:
		tower_ok = tower_ok or game.supplied(t, "strom")
	if not tower_ok:
		return "Tower ohne Strom"
	if terminal != null:
		var t: String = terminal.check()
		if t != "":
			return t
	if game.stands().is_empty():
		return "Kein Stand auf dem Vorfeld"
	return ""


func depot_ok() -> bool:
	for d: Dictionary in game.items_of("vorfelddepot"):
		if game.supplied(d, "strom"):
			return true
	return false


func _free_stand() -> Dictionary:
	var taken := {}
	for p: Dictionary in planes:
		if not (p["stand"] as Dictionary).is_empty():
			taken[(p["stand"]["node"] as Node).get_instance_id()] = true
	var free := []
	for st: Dictionary in game.stands():
		if not taken.has((st["node"] as Node).get_instance_id()):
			free.append(st)
	if free.is_empty():
		return {}
	return free[randi() % free.size()]


func _try_spawn() -> void:
	reason = check_operation()
	if reason != "":
		return
	if runway_owner != -1:
		return
	for p: Dictionary in planes:
		if p["state"] == "wartet":
			return   # startende Flugzeuge haben Vorrang
	var stand := _free_stand()
	if stand.is_empty():
		reason = "Alle Stände belegt"
		return
	var rwy := _runway()
	var s: PackedVector3Array = rwy["samples"]
	var stand_id: int = graph.stand_node.get((stand["node"] as Node).get_instance_id(), -1)
	var probe := graph.path(graph.nearest(s[s.size() / 2], "piste"), stand_id)
	if probe.is_empty():
		reason = "Kein Rollweg zwischen Piste und Stand"
		return
	var length := float(s.size() - 1)
	var kind := "atr"
	if length >= float(Catalog.PLANES["a320"]["min_rwy"]) and randf() < 0.6:
		kind = "a320"
	var airline: Array = Catalog.AIRLINES[randi() % Catalog.AIRLINES.size()]
	counter += 1
	var dir := (s[s.size() - 1] - s[0]).normalized()
	var td := s[0] + dir * 300.0
	var node := Factory.make_plane(kind, airline[1])
	add_child(node)
	var p := {
		"id": counter, "code": "%s %d" % [airline[0], 200 + (counter * 37) % 700], "kind": kind,
		"city": Catalog.DESTINATIONS[randi() % Catalog.DESTINATIONS.size()], "node": node,
		"state": "anflug", "pos": td - dir * APPROACH_DIST, "alt": APPROACH_DIST * GLIDE,
		"heading": dir, "speed": float(Catalog.PLANES[kind]["vapp"]), "stand": stand, "path": [], "pi": 0,
		"timer": 0.0, "turn": 1.0, "wait": 0.0, "ghost": 0.0, "rerouted": false, "rwy": rwy, "dir": dir, "td": td,
		"gse": [], "delay": 0.0,
	}
	runway_owner = counter
	planes.append(p)
	reason = ""
	_place(p)


# ---------------------------------------------------------------- Reservierungen

func _free_for(n: int, id: int) -> bool:
	if n < 0:
		return true
	if reserved.has(n) and int(reserved[n]) != id:
		return false
	for m: int in graph.near[n]:
		if reserved.has(m) and int(reserved[m]) != id:
			return false
	return true


func _reserve(n: int, id: int) -> void:
	if n >= 0:
		reserved[n] = id


func _release_all(id: int) -> void:
	for n in reserved.keys():
		if int(reserved[n]) == id:
			reserved.erase(n)


func _blocked_for(id: int) -> Dictionary:
	var out := {}
	for n in reserved.keys():
		if int(reserved[n]) != id:
			out[n] = true
			for m: int in graph.near[n]:
				out[m] = true
	return out


# ---------------------------------------------------------------- Ablauf je Flugzeug

func _update(p: Dictionary, sim: float) -> void:
	var dir: Vector3 = p["dir"]
	var id: int = p["id"]
	match String(p["state"]):
		"anflug":
			var td: Vector3 = p["td"]
			var pos: Vector3 = p["pos"]
			var to_td := td - pos
			var move := float(p["speed"]) * sim
			if to_td.length() <= move:
				p["pos"] = td
				p["alt"] = 0.0
				p["state"] = "landung"
				movements.append(game.minutes)
				pax_log.append([game.minutes, int(Catalog.PLANES[p["kind"]]["pax"]), false])
			else:
				p["pos"] = pos + to_td.normalized() * move
				p["alt"] = maxf(0.0, (to_td.length() - move) * GLIDE)
		"landung":
			var v: float = p["speed"]
			v = maxf(TAXI_SPEED, v - 3.2 * sim)
			p["speed"] = v
			p["pos"] = (p["pos"] as Vector3) + dir * v * sim
			if v <= TAXI_SPEED + 0.01:
				p["state"] = "rollt_ein"
				p["path"] = []
		"rollt_ein":
			if (p["path"] as Array).is_empty():
				var start := _node_ahead(p) if runway_owner == id else graph.nearest(p["pos"])
				var goal: int = graph.stand_node.get((p["stand"]["node"] as Node).get_instance_id(), -1)
				p["path"] = graph.path(start, goal)
				p["pi"] = 0
				if (p["path"] as Array).is_empty():
					_remove(p, "%s findet keinen Weg zum Stand" % p["code"])
					return
			if runway_owner == id and graph.kind[_current_node(p)] != "piste":
				runway_owner = -1
			if _follow(p, sim):
				if runway_owner == id:
					runway_owner = -1
				_park(p)
		"abfertigung":
			p["timer"] = float(p["timer"]) - sim * CLOCK
			_update_gse(p, sim)
			if float(p["timer"]) <= 0.0:
				_clear_gse(p)
				if terminal != null:
					terminal.flight_left(p)
				p["state"] = "rollt_aus"
				p["path"] = []
		"rollt_aus", "wartet":
			if (p["path"] as Array).is_empty():
				var rwy: Dictionary = p["rwy"]
				var s: PackedVector3Array = rwy["samples"]
				var goal := graph.nearest(s[0] + dir * 15.0, "piste")
				var start := -1
				if not bool(p.get("left", false)):
					start = graph.stand_node.get((p["stand"]["node"] as Node).get_instance_id(), -1)
				if start == -1:
					start = graph.nearest(p["pos"])
				p["path"] = graph.path(start, goal)
				p["pi"] = 0
				if (p["path"] as Array).is_empty():
					_remove(p, "%s findet keinen Weg zur Piste" % p["code"])
					return
			var path: Array = p["path"]
			var nxt: int = path[mini(int(p["pi"]) + 1, path.size() - 1)]
			if graph.kind[nxt] == "piste" and runway_owner != id:
				if runway_owner == -1 and not _arrival_close():
					runway_owner = id
					p["state"] = "rollt_aus"
				else:
					p["state"] = "wartet"
					p["delay"] = float(p["delay"]) + sim * CLOCK
					return
			var arrived := _follow(p, sim)
			if int(p["pi"]) > 0:
				p["left"] = true
			if arrived:
				_release_all(id)
				p["state"] = "start"
				p["speed"] = 0.0
				p["heading"] = dir
				p["stand"] = {}
		"start":
			var v: float = float(p["speed"]) + 3.0 * sim
			p["speed"] = v
			p["heading"] = dir
			p["pos"] = (p["pos"] as Vector3) + dir * v * sim
			if v > float(Catalog.PLANES[p["kind"]]["vr"]):
				p["alt"] = float(p["alt"]) + 9.0 * sim
			if float(p["alt"]) > 40.0 and runway_owner == id:
				runway_owner = -1
				movements.append(game.minutes)
				pax_log.append([game.minutes, int(Catalog.PLANES[p["kind"]]["pax"]), true])
			if float(p["alt"]) > 300.0:
				var plane: Dictionary = Catalog.PLANES[p["kind"]]
				done += 1
				var fare := int(float(int(plane["pax"]) * Catalog.TICKET_FEE) * lerpf(0.7, 1.2, game.satisfaction / 100.0))
				var shops := int(plane["pax"]) * (int(terminal.retail_per_pax()) if terminal != null else 0)
				game.earn(fare + shops, "Abflug %s nach %s" % [p["code"], p["city"]] + (" (mit Café und Shop)" if shops > 0 else ""))
				if float(p["delay"]) < 3.0:
					game.satisfaction = minf(100.0, game.satisfaction + 0.6)
				_remove(p, "")
				return
	_place(p)


## Nächster Pistenknoten vor dem gelandeten Flugzeug (in Landerichtung).
func _node_ahead(p: Dictionary) -> int:
	var pos: Vector3 = p["pos"]
	var dir: Vector3 = p["dir"]
	var best := -1
	var bd := INF
	for i in range(graph.pos.size()):
		if graph.kind[i] != "piste":
			continue
		var to := graph.pos[i] - pos
		if to.dot(dir) < -1.0:
			continue
		var d := to.length()
		if d < bd:
			bd = d
			best = i
	return best if best != -1 else graph.nearest(pos, "piste")


func _arrival_close() -> bool:
	for q: Dictionary in planes:
		if q["state"] == "anflug" or q["state"] == "landung":
			return true
	return false


func _current_node(p: Dictionary) -> int:
	var path: Array = p["path"]
	return path[clampi(int(p["pi"]), 0, path.size() - 1)]


## Bewegt das Flugzeug entlang seines Pfades. Vor jedem Stück reserviert es die Knoten voraus;
## sind sie belegt, wartet es, sucht nach einer Weile einen Umweg. true = Ziel erreicht.
func _follow(p: Dictionary, sim: float) -> bool:
	var id: int = p["id"]
	var path: Array = p["path"]
	var pi: int = p["pi"]
	var pos: Vector3 = p["pos"]
	var need := []
	var dist := 0.0
	var last := pos
	var k := pi + 1
	while k < path.size() and dist < LOOKAHEAD:
		var n: int = path[k]
		need.append(n)
		dist += last.distance_to(graph.pos[n])
		last = graph.pos[n]
		k += 1
	var ghost := float(p["ghost"]) > 0.0
	if ghost:
		p["ghost"] = float(p["ghost"]) - sim
	var free := true
	for n: int in need:
		if graph.kind[n] == "piste" and runway_owner == id:
			continue
		if not _free_for(n, id):
			free = false
			break
	if not free and not ghost:
		p["wait"] = float(p["wait"]) + sim
		p["delay"] = float(p["delay"]) + sim * CLOCK
		if float(p["wait"]) > 12.0 and not bool(p["rerouted"]):
			p["rerouted"] = true
			var alt := graph.path(path[pi], path[path.size() - 1], _blocked_for(id))
			if not alt.is_empty():
				p["path"] = alt
				p["pi"] = 0
		elif float(p["wait"]) > 40.0:
			p["ghost"] = 15.0   # Notlösung gegen gegenseitiges Blockieren
			p["wait"] = 0.0
		return false
	p["wait"] = 0.0
	p["rerouted"] = false
	for n: int in need:
		_reserve(n, id)
	var budget := TAXI_SPEED * sim
	while budget > 0.0:
		var i: int = p["pi"]
		if i >= path.size() - 1:
			break
		var target: Vector3 = graph.pos[path[i + 1]]
		var to := target - pos
		var d := to.length()
		if d <= budget:
			pos = target
			budget -= d
			p["pi"] = i + 1
		else:
			pos += to / d * budget
			budget = 0.0
		if d > 0.01:
			p["heading"] = (p["heading"] as Vector3).lerp(to.normalized(), 0.35).normalized()
	p["pos"] = pos
	for j in range(int(p["pi"])):
		var n: int = path[j]
		if reserved.has(n) and int(reserved[n]) == id:
			reserved.erase(n)
	return int(p["pi"]) >= path.size() - 1


func _park(p: Dictionary) -> void:
	var id: int = p["id"]
	_release_all(id)
	var st: Dictionary = p["stand"]
	var node: Node3D = st["node"]
	_reserve(graph.stand_node.get(node.get_instance_id(), -1), id)
	var fwd := node.global_transform.basis.z.normalized()
	var nose := 18.6 if p["kind"] == "a320" else 13.6
	p["pos"] = (st["pos"] as Vector3) + fwd * (14.0 - nose)
	p["heading"] = fwd
	p["state"] = "abfertigung"
	var plane: Dictionary = Catalog.PLANES[p["kind"]]
	var slow := 1.0 if depot_ok() else 1.5
	var gate: Dictionary = {}
	if terminal != null:
		gate = terminal.assign_gate(p)
		slow *= float(terminal.slowdown())
		if gate.is_empty():
			slow *= 1.25
			gate_short = 60.0
	p["gate"] = gate
	p["turn"] = float(plane["turn"]) * slow
	p["timer"] = p["turn"]
	_spawn_gse(p)
	if terminal != null:
		terminal.flight_parked(p, gate)
	game.earn(int(plane["fee"]) + int(plane["pax"]) * Catalog.TICKET_FEE, "Landung %s aus %s" % [p["code"], p["city"]])


# ---------------------------------------------------------------- Bodenfahrzeuge

## Tankwagen, Gepäck und Catering fahren vom Depot (oder vom Vorfeldrand) an ihre Plätze am Flugzeug.
func _spawn_gse(p: Dictionary) -> void:
	var st: Dictionary = p["stand"]
	var node: Node3D = st["node"]
	var b := node.global_transform.basis
	var fwd := b.z.normalized()
	var side := b.x.normalized()
	var c: Vector3 = p["pos"]
	var home := (st["pos"] as Vector3) + side * 26.0 - fwd * 18.0
	var depots := game.items_of("vorfelddepot")
	if depot_ok() and not depots.is_empty():
		home = depots[0]["pos"]
	var big: bool = p["kind"] == "a320"
	var span := 7.5 if big else 6.0
	var spots := [
		["tank", c + side * span + fwd * 1.5, fwd],
		["gepaeck", c - side * 3.5 - fwd * (10.0 if big else 7.0), side],
		["catering", c + side * 3.6 + fwd * (11.0 if big else 6.0), side],
	]
	var list := []
	for i in range(spots.size()):
		var spot: Array = spots[i]
		var v := Factory.make_gse(String(spot[0]))
		add_child(v)
		var start: Vector3 = home + side * float(i) * 4.0
		v.position = start
		list.append({"node": v, "home": start, "spot": spot[1], "face": spot[2], "delay": 0.04 * float(i)})
	p["gse"] = list


func _update_gse(p: Dictionary, _sim: float) -> void:
	var total: float = p["turn"]
	var f := 1.0 - float(p["timer"]) / maxf(total, 0.01)
	for g: Dictionary in p["gse"]:
		var v: Node3D = g["node"]
		var home: Vector3 = g["home"]
		var spot: Vector3 = g["spot"]
		var t0: float = 0.02 + float(g["delay"])
		var leg := minf(0.18, home.distance_to(spot) / GSE_SPEED / (total / CLOCK))
		var pos := spot
		var look: Vector3 = g["face"]
		if f < t0:
			pos = home
			look = (spot - home).normalized()
		elif f < t0 + leg:
			pos = home.lerp(spot, (f - t0) / maxf(leg, 0.001))
			look = (spot - home).normalized()
		elif f > 0.97 - leg:
			pos = spot.lerp(home, clampf((f - (0.97 - leg)) / maxf(leg, 0.001), 0.0, 1.0))
			look = (home - spot).normalized()
		v.position = Vector3(pos.x, 0.0, pos.z)
		if look.length_squared() > 0.001:
			v.basis = Basis.looking_at(look, Vector3.UP)


func _clear_gse(p: Dictionary) -> void:
	for g: Dictionary in p["gse"]:
		var v: Variant = g["node"]
		if is_instance_valid(v):
			(v as Node).queue_free()
	p["gse"] = []


func _place(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	var pos: Vector3 = p["pos"]
	node.position = Vector3(pos.x, float(p["alt"]), pos.z)
	var h: Vector3 = p["heading"]
	if h.length_squared() > 0.0001:
		node.basis = Basis.looking_at(h, Vector3.UP)


func _remove(p: Dictionary, msg: String) -> void:
	var id: int = p["id"]
	if runway_owner == id:
		runway_owner = -1
	_release_all(id)
	_clear_gse(p)
	if terminal != null:
		terminal.flight_left(p)
	(p["node"] as Node).queue_free()
	planes.erase(p)
	if msg != "":
		game.toast.emit(msg)


func clear() -> void:
	for p: Dictionary in planes.duplicate():
		_remove(p, "")
	reserved.clear()
	runway_owner = -1
	pax_log.clear()
	if terminal != null:
		terminal.clear_people()
	dirty = true


# ---------------------------------------------------------------- Zufriedenheit

## Zufriedenheit der Passagiere und Airlines. Sie bestimmt, wie oft neue Flüge kommen
## und wie viel die Tickets einbringen.
func _satisfaction(sim: float) -> void:
	var factors := []
	var target := 80.0
	var waiting := 0
	var stuck := 0
	for p: Dictionary in planes:
		if p["state"] == "wartet":
			waiting += 1
		elif float(p["wait"]) > 8.0:
			stuck += 1
	if waiting > 0:
		target -= 7.0 * waiting
		factors.append(["%d Flugzeug(e) warten auf die Piste" % waiting, -7 * waiting])
	if stuck > 0:
		target -= 4.0 * stuck
		factors.append(["%d Flugzeug(e) stehen auf dem Rollweg" % stuck, -4 * stuck])
	hint = ""
	if not depot_ok():
		target -= 6.0
		factors.append(["Kein Vorfelddepot mit Strom: Abfertigung dauert länger", -6])
		hint = "Ohne Vorfelddepot dauert jede Abfertigung länger"
	var parking := false
	for ph: Dictionary in game.items_of("parkhaus"):
		parking = parking or game.supplied(ph, "strom")
	if not parking:
		target -= 12.0
		factors.append(["Kein Parkhaus mit Strom", -12])
	if gate_short > 0.0:
		target -= 5.0
		factors.append(["Zu wenige Gates: Flugzeuge warten auf ein Gate", -5])
		if hint == "":
			hint = "Zu wenige Gates: mehr Gates bauen"
	if terminal != null:
		var t: String = terminal.check()
		if t != "":
			target -= 30.0
			factors.append(["Terminal: " + t, -30])
		else:
			for f: Array in terminal.factors():
				target += float(f[1])
				factors.append(f)
			if hint == "" and String(terminal.hint) != "":
				hint = terminal.hint
	var decor := game.decor_near_terminals(40.0)
	var bonus := mini(6, decor / 2)
	if bonus > 0:
		target += float(bonus)
		factors.append(["Vorplatz: %d Bäume, Kübel und Bänke am Terminal" % decor, bonus])
	target = clampf(target, 5.0, 100.0)
	game.satisfaction = lerpf(game.satisfaction, target, clampf(sim * 0.01, 0.0, 1.0))
	game.satisfaction_factors = factors


# ---------------------------------------------------------------- Anzeige

## Flugzeug in der Nähe eines Bodenpunkts (für das Info-Werkzeug).
func pick(p: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := 25.0
	for q: Dictionary in planes:
		var qp: Vector3 = q["pos"]
		var d := Vector2(qp.x - p.x, qp.z - p.z).length()
		if d < bd:
			bd = d
			best = q
	return best


func describe(p: Dictionary) -> String:
	var plane: Dictionary = Catalog.PLANES[p["kind"]]
	var lines := ["%s, %d Sitzplätze" % [String(plane["name"]), int(plane["pax"])]]
	lines.append(_route(p) + " · " + _status(p)[0])
	if p["state"] == "abfertigung":
		lines.append("Tankwagen, Gepäck und Catering sind am Flugzeug")
		var gate: Dictionary = p.get("gate", {})
		if terminal != null and not gate.is_empty():
			lines.append("Passagiere am " + String(terminal.gate_name(gate)))
		if not depot_ok():
			lines.append("Ohne Vorfelddepot dauert es 50 % länger")
	if float(p["delay"]) >= 1.0:
		lines.append("Verspätung %d Min" % int(p["delay"]))
	return "\n".join(lines)


func _route(p: Dictionary) -> String:
	return ("aus " if p["state"] in ["anflug", "landung", "rollt_ein"] else "nach ") + String(p["city"])


func _status(p: Dictionary) -> Array:
	match String(p["state"]):
		"anflug":
			return ["Anflug", Color(0.56, 0.75, 0.94)]
		"landung":
			return ["Landung", Color(0.56, 0.75, 0.94)]
		"rollt_ein":
			if float(p["wait"]) > 1.0:
				return ["Wartet auf Rollweg", Color(1.0, 0.55, 0.45)]
			return ["Rollt zum Stand", Color(0.94, 0.76, 0.31)]
		"abfertigung":
			return ["Abfertigung %d Min" % ceili(float(p["timer"])), Color(0.66, 0.85, 0.56)]
		"rollt_aus":
			if float(p["wait"]) > 1.0:
				return ["Wartet auf Rollweg", Color(1.0, 0.55, 0.45)]
			return ["Rollt zur Piste", Color(0.94, 0.76, 0.31)]
		"wartet":
			return ["Wartet auf Piste", Color(1.0, 0.55, 0.45)]
		"start":
			return ["Start", Color(0.56, 0.75, 0.94)]
	return ["", Color.WHITE]


func rows() -> Array:
	var out := []
	for p: Dictionary in planes:
		var st := _status(p)
		out.append([String(p["code"]), String(Catalog.PLANES[p["kind"]]["name"]), _route(p), st[0], st[1]])
	return out
