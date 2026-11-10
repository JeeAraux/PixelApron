extends Node3D
## Terminalbetrieb: prüft, ob eine Halle alles Nötige hat, rechnet Kapazität, Wärme und Ambiente aus
## und lässt Passagiere mit Wegsuche (1-m-Raster, AStarGrid2D) durch die Halle laufen.
##
## Abflug:  Eingang → Check-in → Sicherheitskontrolle → (Shop/Café/WC) → Gate, steigen beim Losrollen ein.
## Ankunft: Gate → Gepäckband → (WC) → Eingang, dann verlassen sie das Terminal.

const Catalog = preload("res://scripts/catalog.gd")
const Factory = preload("res://scripts/factory.gd")
const GameState = preload("res://scripts/game_state.gd")

const WALK := 1.8              # Meter pro Simulationssekunde
const PAX_PER_FIGURE := 8      # eine Figur steht für so viele Passagiere
const ESSENTIAL := [["eingang", "Eingang"], ["checkin", "Check-in"], ["sicherheit", "Sicherheitskontrolle"],
	["gate", "Gate"], ["gepaeckband", "Gepäckband"]]

var game: GameState
var dirty := true
var grids: Dictionary = {}     # Instanz-ID der Halle -> AStarGrid2D
var halls: Array = []          # Auswertung je Halle
var people: Array = []
var gate_use: Dictionary = {}  # Instanz-ID des Gates -> Flug-ID
var demand_dep := 0.0          # abfliegende Passagiere pro Stunde
var demand_arr := 0.0
var hint := ""
var bridges: Dictionary = {}   # Instanz-ID des Gates -> Fluggastbrücke
const Models = preload("res://scripts/models.gd")
const Kit = preload("res://scripts/mesh_kit.gd")
const BRIDGE_REACH := 38.0
var bus_cb: Callable            # ground_ops.pax_at_door(Flug-ID): ein Abfliegender ist an der Bus-Tür


func setup(g: GameState) -> void:
	game = g
	game.items_changed.connect(_mark)
	game.network_changed.connect(_mark)
	game.supply_changed.connect(_mark)


func _mark() -> void:
	dirty = true


# ---------------------------------------------------------------- Auswertung

func _analyze() -> void:
	dirty = false
	halls = []
	grids = {}
	for h: Dictionary in game.items_of("halle"):
		var counts := {}
		for it: Dictionary in game.inside_of(h):
			counts[it["id"]] = int(counts.get(it["id"], 0)) + 1
		var missing := []
		for e: Array in ESSENTIAL:
			var have := int(counts.get(e[0], 0))
			if e[0] == "gate":
				have += int(counts.get("busgate", 0))
			if have == 0:
				missing.append(e[1])
		var powered := game.supplied(h, "strom")
		var area := (h["rect"] as Rect2).get_area()
		var heat_ok := game.supplied(h, "waerme")
		var heated := float(counts.get("heizkoerper", 0)) * float(Catalog.ITEMS["heizkoerper"]["heats"]) if heat_ok else 0.0
		var decor := 0
		for id: String in counts:
			var pts := int(Catalog.ITEMS[id].get("decor", 0))
			if id == "anzeige" and not powered:
				pts = 0
			decor += pts * int(counts[id])
		var hid := (h["node"] as Node).get_instance_id()
		grids[hid] = {"dep": _make_grid(h, "dep"), "arr": _make_grid(h, "arr")}
		var problems := []
		if missing.is_empty():
			problems = _security_problems(h, grids[hid])
		var info := {
			"hall": h, "counts": counts, "missing": missing, "powered": powered, "area": area, "problems": problems,
			"complete": powered and missing.is_empty() and problems.is_empty() and int(counts.get("gepaeckanlage", 0)) > 0,
			"warm": clampf(heated / maxf(area, 1.0), 0.0, 1.0), "decor": decor,
			"wc": int(counts.get("wc", 0)) if game.supplied(h, "wasser") else 0,
		}
		halls.append(info)
	_rebuild_bridges()
	# Personen in abgerissenen Hallen verschwinden, die anderen suchen ihren Weg neu
	for per: Dictionary in people.duplicate():
		if not grids.has(int(per["hall_id"])):
			_drop(per)
		else:
			per["path"] = []


func _complete() -> Array:
	if dirty:
		_analyze()
	var out := []
	for info: Dictionary in halls:
		if bool(info["complete"]):
			out.append(info)
	return out


## Leer = Terminal kann abfertigen, sonst der Grund.
func check() -> String:
	if dirty:
		_analyze()
	if halls.is_empty():
		return "Keine Terminalhalle"
	if not _complete().is_empty():
		return ""
	var best: Dictionary = {}
	for info: Dictionary in halls:
		if not bool(info["powered"]):
			continue
		if best.is_empty() or (info["missing"] as Array).size() < (best["missing"] as Array).size():
			best = info
	if best.is_empty():
		return "Terminalhalle ohne Strom"
	if not (best["missing"] as Array).is_empty():
		return "Im Terminal fehlt: " + ", ".join(best["missing"])
	if not (best["problems"] as Array).is_empty():
		return String(best["problems"][0])
	return "Check-in braucht eine Gepäcksortierung"


func _sum(key: String) -> int:
	var total := 0
	for info: Dictionary in _complete():
		total += int((info["counts"] as Dictionary).get(key, 0))
	return total


func capacity_dep() -> float:
	return minf(float(_sum("checkin") * int(Catalog.ITEMS["checkin"]["cap"])),
		float(_sum("sicherheit") * int(Catalog.ITEMS["sicherheit"]["cap"])))


func capacity_arr() -> float:
	return float(_sum("gepaeckband") * int(Catalog.ITEMS["gepaeckband"]["cap"]))


func set_demand(arr_per_h: float, dep_per_h: float) -> void:
	demand_arr = arr_per_h
	demand_dep = dep_per_h


## Faktor für die Abfertigungszeit: über 1, wenn mehr Passagiere kommen, als das Terminal schafft.
func slowdown() -> float:
	var ld := demand_dep / maxf(capacity_dep(), 1.0)
	var la := demand_arr / maxf(capacity_arr(), 1.0)
	return clampf(maxf(ld, la), 1.0, 2.0)


## Einnahmen aus Café und Shop je abfliegendem Passagier.
func retail_per_pax() -> int:
	var total := 0
	for id: String in ["cafe", "shop"]:
		var n := _sum(id)
		if n > 0:
			total += int(Catalog.ITEMS[id]["retail"]) + mini(n - 1, 2)
	return total


## Einflüsse auf die Zufriedenheit: [Text, Punkte]
func factors() -> Array:
	var out := []
	hint = ""
	var done := _complete()
	if done.is_empty():
		return out
	var wc_cap := 0
	var area := 0.0
	var warm := 0.0
	var decor := 0
	for info: Dictionary in done:
		wc_cap += int(info["wc"]) * int(Catalog.ITEMS["wc"]["cap"])
		area += float(info["area"])
		warm += float(info["warm"]) * float(info["area"])
		decor += int(info["decor"])
	warm /= maxf(area, 1.0)
	if wc_cap == 0:
		out.append(["Keine Toiletten mit Wasser im Terminal", -15])
		hint = "Toiletten bauen und die Halle an Wasser anschließen"
	elif demand_dep + demand_arr > float(wc_cap):
		out.append(["Toiletten überlastet", -6])
	if warm < 0.95:
		out.append(["Terminal zu kalt: %d %% beheizt" % roundi(warm * 100.0), -roundi(15.0 * (1.0 - warm))])
		if hint == "":
			hint = "Heizkörper bauen und die Halle mit einem Heizrohr an die Heizzentrale anschließen"
	var ld := demand_dep / maxf(capacity_dep(), 1.0)
	if ld > 1.05:
		var which := "Check-in" if _sum("checkin") * int(Catalog.ITEMS["checkin"]["cap"]) <= _sum("sicherheit") * int(Catalog.ITEMS["sicherheit"]["cap"]) else "Kontrolle"
		out.append(["Warteschlangen am %s" % which, -mini(20, roundi(10.0 * (ld - 1.0)) + 3)])
		hint = "%s überlastet: mehr davon bauen" % which
	var la := demand_arr / maxf(capacity_arr(), 1.0)
	if la > 1.05:
		out.append(["Gedränge am Gepäckband", -mini(15, roundi(10.0 * (la - 1.0)) + 2)])
		if hint == "":
			hint = "Gepäckband überlastet: ein weiteres bauen"
	var bonus := mini(10, roundi(float(decor) / maxf(area / 100.0, 1.0) * 4.0))
	if bonus > 0:
		out.append(["Ausstattung im Terminal (Pflanzen, Sitze, Café, Kunst)", bonus])
	return out


func gate_name(gate: Dictionary) -> String:
	var i := 1
	var id: String = gate.get("id", "gate")
	for g: Dictionary in game.items_of(id):
		if is_same(g, gate):
			return ("Bus-Gate %d" if id == "busgate" else "Gate %d") % i
		i += 1
	return "Gate"


## Zusammenfassung für das Info-Werkzeug.
func hall_summary(h: Dictionary) -> String:
	if dirty:
		_analyze()
	for info: Dictionary in halls:
		if not is_same(info["hall"], h):
			continue
		var c: Dictionary = info["counts"]
		var lines := []
		if bool(info["complete"]):
			lines.append("Betriebsbereit")
		elif not bool(info["powered"]):
			lines.append("Ohne Strom")
		elif not (info["missing"] as Array).is_empty():
			lines.append("Es fehlt: " + ", ".join(info["missing"]))
		elif not (info["problems"] as Array).is_empty():
			lines.append(String(info["problems"][0]))
		else:
			lines.append("Es fehlt: Gepäcksortierung")
		if (info["problems"] as Array).is_empty() and (info["missing"] as Array).is_empty():
			lines.append("Sicherheitsbereich: geschlossen, nur über die Kontrolle erreichbar")
		lines.append("Check-in %d · Kontrolle %d · Gates %d · Bänder %d · WC %d" % [int(c.get("checkin", 0)),
			int(c.get("sicherheit", 0)), int(c.get("gate", 0)), int(c.get("gepaeckband", 0)), int(c.get("wc", 0))])
		lines.append("Abflug %d/h von %d/h möglich, Ankunft %d/h von %d/h" % [roundi(demand_dep), roundi(capacity_dep()),
			roundi(demand_arr), roundi(capacity_arr())])
		lines.append("Beheizt: %d %%" % roundi(float(info["warm"]) * 100.0))
		return "\n".join(lines)
	return ""


# ---------------------------------------------------------------- Gates

## Gate für einen Flug wählen. Auf Außenpositionen (oder wenn keine Brücke hinreicht) geht es
## mit dem Bus: dann bevorzugt ein Bus-Gate. Setzt p["bus"].
func assign_gate(p: Dictionary) -> Dictionary:
	var stand: Dictionary = p["stand"]
	var sp: Vector3 = stand.get("pos", Vector3.ZERO)
	var remote := String(stand.get("id", "stand")) == "stand_aussen"
	var best: Dictionary = {}
	var bd := INF
	for info: Dictionary in _complete():
		for it: Dictionary in game.inside_of(info["hall"]):
			if not (it["id"] in ["gate", "busgate"]):
				continue
			var gid := (it["node"] as Node).get_instance_id()
			if gate_use.has(gid):
				continue
			var score := (it["pos"] as Vector3).distance_to(sp)
			if remote:
				score += 0.0 if it["id"] == "busgate" else 400.0
			elif it["id"] == "gate" and bridge_reaches(it, p):
				score -= 1000.0
			elif it["id"] == "busgate":
				score += 150.0
			if score < bd:
				bd = score
				best = it
	p["bus"] = remote or best.is_empty() or not (best["id"] == "gate" and bridge_reaches(best, p))
	if not best.is_empty():
		gate_use[(best["node"] as Node).get_instance_id()] = int(p["id"])
	return best


## Erreicht die Brücke dieses Gates Tür L1 des Flugzeugs (in seiner Parkposition)?
func bridge_reaches(gate: Dictionary, p: Dictionary) -> bool:
	if dirty:
		_analyze()
	var b := _bridge_for_gate(gate)
	if b.is_empty() or not p.has("heading"):
		return false
	var s: Dictionary = Models.SPECS.get(p["kind"], Models.SPECS["a320"])
	var h: Vector3 = p["heading"]
	var door: Vector3 = (p["pos"] as Vector3) + Basis.looking_at(Vector3(h.x, 0, h.z).normalized(), Vector3.UP) * Vector3(-(float(s["r"]) + 2.0), 0.0, float(s["doors"][0]))
	var a: Vector3 = b["anchor"]
	# Tür muss vor der Brücke liegen (nicht hinter dem Terminal) und in Reichweite
	return Vector2(door.x - a.x, door.z - a.z).length() < BRIDGE_REACH and (door - a).dot(b["out"]) > 4.0


## Tür eines Gates zum Vorfeld: [Punkt innen, Punkt außen, Außennormale].
func gate_door(gate: Dictionary) -> Array:
	var h: Dictionary = gate["hall"]
	var hr: Rect2 = h["rect"]
	var gr: Rect2 = gate["rect"]
	var c := gr.get_center()
	var cand := [[gr.position.y - hr.position.y, Vector3(0, 0, -1), Vector3(c.x, 0, hr.position.y)],
		[hr.end.y - gr.end.y, Vector3(0, 0, 1), Vector3(c.x, 0, hr.end.y)],
		[gr.position.x - hr.position.x, Vector3(-1, 0, 0), Vector3(hr.position.x, 0, c.y)],
		[hr.end.x - gr.end.x, Vector3(1, 0, 0), Vector3(hr.end.x, 0, c.y)]]
	cand.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var n: Vector3 = cand[0][1]
	var wall: Vector3 = cand[0][2]
	var along := n.cross(Vector3.UP)
	return [wall - n * 1.2 + along * 2.5, wall + n * 1.5 + along * 2.5, n]


## Vorfeld-Haltestelle für ein Gate: [Halteposition, Fahrtrichtung]. Ohne Haltestelle hält der Bus
## direkt vor der Tür.
func bus_stop(gate: Dictionary) -> Array:
	var door := gate_door(gate)
	var best: Dictionary = {}
	var bd := 260.0
	for it: Dictionary in game.items_of("bushalt"):
		var d := (it["pos"] as Vector3).distance_to(door[1])
		if d < bd:
			bd = d
			best = it
	if not best.is_empty():
		var b := Basis(Vector3.UP, float(best["rot"]) * PI * 0.5)
		return [(best["pos"] as Vector3) + b * Vector3(0, 0, -0.6), b * Vector3(1, 0, 0)]
	var n: Vector3 = door[2]
	return [(door[1] as Vector3) + n * 6.0, n.cross(Vector3.UP)]


func _release_gate(fid: int) -> void:
	for gid: int in gate_use.keys():
		if int(gate_use[gid]) == fid:
			gate_use.erase(gid)


# ---------------------------------------------------------------- Passagiere

func _pt(it: Dictionary, local: Vector3) -> Vector3:
	var b := Basis(Vector3.UP, float(it["rot"]) * PI * 0.5)
	return (it["pos"] as Vector3) + b * local


func _size(it: Dictionary) -> Vector2:
	return Catalog.ITEMS[it["id"]]["size"]


func _any(hall: Dictionary, id: String) -> Dictionary:
	var list := []
	for it: Dictionary in game.inside_of(hall):
		if it["id"] == id:
			list.append(it)
	if list.is_empty():
		return {}
	return list[randi() % list.size()]


func _front(it: Dictionary, spread: float, depth: float) -> Vector3:
	var s := _size(it)
	return _pt(it, Vector3(randf_range(-spread, spread), 0, s.y * 0.5 + 0.6 + randf() * depth))


## Ein Flugzeug steht am Stand: Ankommende steigen am Gate aus, Abfliegende kommen zum Eingang herein.
func flight_parked(p: Dictionary, gate: Dictionary) -> void:
	if gate.is_empty():
		return
	var br := _bridge_for_gate(gate)
	if not br.is_empty() and not bool(p.get("bus", false)):
		br["plane"] = p
	var hall: Dictionary = gate["hall"]
	var n := ceili(float(Catalog.PLANES[p["kind"]]["pax"]) / float(PAX_PER_FIGURE))
	if not bool(p.get("bus", false)):
		_arrivals(p, gate, n, _pt(gate, Vector3(3.5, 0, -3.2)), 0.45)
	for i in range(n):
		var door := _any(hall, "eingang")
		if door.is_empty():
			break
		var plan := [["wait", 3.0 + float(i) * 0.6], ["show"]]
		var desk := _any(hall, "checkin")
		if not desk.is_empty():
			plan.append(["go", _front(desk, 2.4, 1.6)])
			plan.append(["wait", randf_range(2.5, 4.5)])
		var sec := _any(hall, "sicherheit")
		if not sec.is_empty():
			var lane := (-1.6 if randf() < 0.5 else 1.6) - 0.6
			var ss := _size(sec)
			plan.append(["go", _pt(sec, Vector3(lane, 0, ss.y * 0.5 + 0.7))])
			plan.append(["go", _pt(sec, Vector3(lane, 0, -ss.y * 0.5 - 0.7))])
			plan.append(["wait", randf_range(0.5, 1.5)])
		_maybe(plan, hall, "shop", 0.25)
		_maybe(plan, hall, "cafe", 0.2)
		_maybe(plan, hall, "wc", 0.15)
		var row: float = [-1.0, 0.6, 2.4][randi() % 3]
		var flip := 1.0 if row > 0.0 else -1.0
		var seat_x := -3.25 + float(randi() % 8) * 0.93
		plan.append(["go", _pt(gate, Vector3(seat_x, 0, row + 0.55 * -flip))])
		plan.append(["go", _pt(gate, Vector3(seat_x, 0, row - 0.05 * flip))])
		var face := Basis(Vector3.UP, float(gate["rot"]) * PI * 0.5) * Vector3(0, 0, -flip)
		plan.append(["sit", face])
		plan.append(["stay"])
		_spawn(p, hall, true, _pt(door, Vector3(randf_range(-2.0, 2.0), 0, 0.3)), plan)


## Ankommende betreten das Terminal am Gate (oder durch die Tür des Bus-Gates) und gehen zum Band.
func _arrivals(p: Dictionary, gate: Dictionary, n: int, start: Vector3, spacing: float) -> void:
	var hall: Dictionary = gate["hall"]
	var band := _any(hall, "gepaeckband")
	for i in range(n):
		var plan := [["wait", float(i) * spacing], ["show"]]
		if not band.is_empty():
			var bs := _size(band)
			plan.append(["go", _pt(band, Vector3(randf_range(-bs.x * 0.4, bs.x * 0.4), 0, bs.y * 0.5 + 0.5 + randf() * 0.8))])
			plan.append(["wait", randf_range(4.0, 8.0)])
		_maybe(plan, hall, "wc", 0.2)
		var door := _any(hall, "eingang")
		if not door.is_empty():
			plan.append(["go", _pt(door, Vector3(randf_range(-2.0, 2.0), 0, 0))])
		plan.append(["end"])
		_spawn(p, hall, false, start + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5)), plan)


## Ein Bus hat Ankommende an der Haltestelle abgesetzt; n Figuren kommen durch das Bus-Gate herein.
func bus_arrivals(p: Dictionary, n: int) -> void:
	var gate: Dictionary = p.get("gate", {})
	if gate.is_empty() or not is_instance_valid(gate.get("node")):
		return
	_arrivals(p, gate, n, gate_door(gate)[0], 0.0)


## Der Abflugbus steht bereit: alle Abfliegenden dieses Flugs gehen zur Tür des Bus-Gates.
## Rückgabe: Anzahl der Figuren, die kommen.
func board_bus(p: Dictionary) -> int:
	var gate: Dictionary = p.get("gate", {})
	if gate.is_empty():
		return 0
	var inside: Vector3 = gate_door(gate)[0]
	var count := 0
	for per: Dictionary in people:
		if int(per["flight"]) != int(p["id"]) or not bool(per["dep"]):
			continue
		per["plan"] = [["show"], ["go", inside + Vector3(randf_range(-1.5, 1.5), 0, 0)], ["bus"]]
		per["si"] = 0
		per["path"] = []
		per["timer"] = 0.0
		var luggage := (per["node"] as Node3D).get_node_or_null("Koffer") as Node3D
		if luggage != null:
			luggage.position = Vector3(0.36, 0, 0.32)
		count += 1
	return count


func bus_pax_pending(p: Dictionary) -> bool:
	for per: Dictionary in people:
		if int(per["flight"]) == int(p["id"]) and bool(per["dep"]):
			return true
	return false


func _maybe(plan: Array, hall: Dictionary, id: String, chance: float) -> void:
	if randf() >= chance:
		return
	var it := _any(hall, id)
	if it.is_empty():
		return
	var s := _size(it)
	plan.append(["go", _front(it, s.x * 0.35, 0.8)])
	plan.append(["wait", randf_range(2.0, 5.0)])


func _spawn(p: Dictionary, hall: Dictionary, dep: bool, start: Vector3, plan: Array) -> void:
	var node := Factory.make_person(Factory.SHIRTS[randi() % Factory.SHIRTS.size()])
	if randf() < 0.1:
		node.scale = Vector3.ONE * randf_range(0.58, 0.7)   # Kinder
	elif randf() < 0.65:
		# Rollkoffer mit ausgezogenem Griff, an der rechten Hand
		var bag := Node3D.new()
		bag.name = "Koffer"
		bag.position = Vector3(0.36, 0, 0.32)
		node.add_child(bag)
		var c: Color = Factory.SHIRTS[randi() % Factory.SHIRTS.size()].darkened(0.35)
		Factory.blk(bag, Vector3(-0.12, 0.06, -0.2), Vector3(0.12, 0.62, 0.2), c)
		Factory.blk(bag, Vector3(-0.02, 0.62, -0.12), Vector3(0.02, 0.95, -0.08), Color(0.2, 0.2, 0.22))
		Factory.blk(bag, Vector3(-0.08, 0.93, -0.13), Vector3(0.08, 0.97, -0.07), Color(0.2, 0.2, 0.22))
		for wz: float in [-0.15, 0.15]:
			Factory.blk(bag, Vector3(-0.1, 0.0, wz - 0.03), Vector3(0.1, 0.06, wz + 0.03), Color(0.08, 0.08, 0.08))
	node.visible = false
	node.position = start
	add_child(node)
	people.append({"node": node, "flight": int(p["id"]), "dep": dep, "hall_id": (hall["node"] as Node).get_instance_id(),
		"plan": plan, "si": 0, "path": [], "pi": 0, "timer": 0.0, "pos": start})


## Das Flugzeug rollt los: wer am Gate wartet (oder noch unterwegs ist), ist eingestiegen.
func flight_left(p: Dictionary) -> void:
	var fid: int = p["id"]
	for gid: int in bridges:
		var b: Dictionary = bridges[gid]
		if not (b["plane"] as Dictionary).is_empty() and int(b["plane"]["id"]) == fid:
			b["plane"] = {}
	_release_gate(fid)
	for per: Dictionary in people.duplicate():
		if int(per["flight"]) == fid and bool(per["dep"]):
			_drop(per)


func _drop(per: Dictionary) -> void:
	var node: Variant = per["node"]
	if is_instance_valid(node):
		(node as Node).queue_free()
	people.erase(per)


func clear_people() -> void:
	for per: Dictionary in people.duplicate():
		_drop(per)
	gate_use.clear()


func step(sim: float) -> void:
	if dirty:
		_analyze()
	_move_bridges(sim)
	_belts(sim)
	for per: Dictionary in people.duplicate():
		_update_person(per, sim)


func _update_person(per: Dictionary, sim: float) -> void:
	var plan: Array = per["plan"]
	var si: int = per["si"]
	if si >= plan.size():
		_drop(per)
		return
	var st: Array = plan[si]
	var node: Node3D = per["node"]
	match String(st[0]):
		"wait":
			per["timer"] = float(per["timer"]) + sim
			if float(per["timer"]) >= float(st[1]):
				per["timer"] = 0.0
				per["si"] = si + 1
		"show":
			node.visible = true
			per["si"] = si + 1
		"go":
			var path: Array = per["path"]
			if path.is_empty():
				path = _path(int(per["hall_id"]), per["pos"], st[1], bool(per["dep"]))
				per["path"] = path
				per["pi"] = 0
			var pos: Vector3 = per["pos"]
			var budget := WALK * sim
			var pi: int = per["pi"]
			var look := Vector3.ZERO
			while budget > 0.0 and pi < path.size():
				var target: Vector3 = path[pi]
				var d := pos.distance_to(target)
				if d <= budget:
					budget -= d
					look = target - pos
					pos = target
					pi += 1
				else:
					look = target - pos
					pos += look / d * budget
					budget = 0.0
			per["walk"] = float(per.get("walk", 0.0)) + WALK * sim - budget
			Factory.set_pose(node, 1 + int(float(per["walk"]) / 0.3) % 4)
			per["pos"] = pos
			per["pi"] = pi
			node.position = pos
			if look.length_squared() > 0.0001:
				node.basis = Basis.looking_at(Vector3(look.x, 0, look.z).normalized(), Vector3.UP)
			if pi >= path.size():
				per["path"] = []
				per["si"] = si + 1
				Factory.set_pose(node, 0)
		"sit":
			Factory.set_pose(node, 5)
			node.basis = Basis.looking_at(st[1], Vector3.UP)
			var luggage := node.get_node_or_null("Koffer") as Node3D
			if luggage != null:
				luggage.position = Vector3(0.45, 0, -0.3)
			per["si"] = si + 1
		"stay":
			pass
		"bus":
			if bus_cb.is_valid():
				bus_cb.call(int(per["flight"]))
			_drop(per)
		"end":
			_drop(per)


# ---------------------------------------------------------------- Wegsuche

## Prüft den Sicherheitsbereich mit einer Flutfüllung auf dem 1-m-Raster:
## Vom Eingang dürfen die Gates nur durch die Kontrolle erreichbar sein, Ankommende müssen
## über einen Ausgang Sicherheitsbereich wieder hinauskommen.
func _security_problems(h: Dictionary, g: Dictionary) -> Array:
	var out := []
	var entries := _cells_of(h, "eingang")
	var gates := _cells_of(h, "gate") + _cells_of(h, "busgate")
	if entries.is_empty() or gates.is_empty():
		return out
	var arr: AStarGrid2D = g["arr"]
	var dep: AStarGrid2D = g["dep"]
	var oneway := {}
	for c: Vector2i in _cells_of(h, "sb_ausgang"):
		oneway[c] = true
	# 1. Ohne durch die Kontrolle (und ohne verkehrt durch den Ausgang) zu den Gates?
	var free := _flood(arr, entries, oneway)
	for c: Vector2i in gates:
		if free.has(c):
			out.append("Sicherheitsbereich offen: Gates sind ohne Kontrolle erreichbar. Mit Wänden oder Glaswänden abtrennen.")
			return out
	# 2. Kommen Abfliegende durch die Kontrolle zu den Gates?
	var dep_reach := _flood(dep, entries, {})
	var any_gate := false
	for c: Vector2i in gates:
		any_gate = any_gate or dep_reach.has(c)
	if not any_gate:
		out.append("Kein Weg vom Eingang durch die Kontrolle zu den Gates")
		return out
	# 3. Kommen Ankommende hinaus?
	var arr_reach := _flood(arr, gates, {})
	var any_exit := false
	for c: Vector2i in entries:
		any_exit = any_exit or arr_reach.has(c)
	if not any_exit:
		out.append("Ankommende kommen nicht aus dem Sicherheitsbereich: Ausgang Sicherheitsbereich bauen")
	return out


func _cells_of(h: Dictionary, id: String) -> Array:
	var out := []
	for it: Dictionary in game.inside_of(h):
		if it["id"] != id:
			continue
		var ir: Rect2 = (it["rect"] as Rect2).grow(-0.25)
		for x in range(floori(ir.position.x), ceili(ir.end.x)):
			for z in range(floori(ir.position.y), ceili(ir.end.y)):
				out.append(Vector2i(x, z))
	return out


func _flood(g: AStarGrid2D, starts: Array, blocked: Dictionary) -> Dictionary:
	var seen := {}
	var queue := []
	for c: Vector2i in starts:
		if g.is_in_boundsv(c) and not g.is_point_solid(c) and not blocked.has(c):
			seen[c] = true
			queue.append(c)
	var qi := 0
	while qi < queue.size():
		var c: Vector2i = queue[qi]
		qi += 1
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n) or not g.is_in_boundsv(n) or g.is_point_solid(n) or blocked.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return seen


## mode "dep": Ausgang Sicherheitsbereich ist zu (Einbahn), "arr": Kontrolle ist zu.
func _make_grid(h: Dictionary, mode: String = "dep") -> AStarGrid2D:
	var r: Rect2 = h["rect"]
	var g := AStarGrid2D.new()
	g.region = Rect2i(floori(r.position.x), floori(r.position.y), ceili(r.size.x), ceili(r.size.y))
	g.cell_size = Vector2(1, 1)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	for it: Dictionary in game.inside_of(h):
		var def: Dictionary = Catalog.ITEMS[it["id"]]
		var walk := bool(def.get("walk", false))
		if mode == "dep" and bool(def.get("oneway", false)):
			walk = false
		if mode == "arr" and it["id"] == "sicherheit":
			walk = false
		if walk:
			continue
		var ir: Rect2 = (it["rect"] as Rect2).grow(-0.25)
		for x in range(floori(ir.position.x), ceili(ir.end.x)):
			for z in range(floori(ir.position.y), ceili(ir.end.y)):
				var c := Vector2i(x, z)
				if g.is_in_boundsv(c):
					g.set_point_solid(c, true)
	for l: Dictionary in game.walls_of(h):
		for v: Vector3 in game.wall_probe(l):
			var c := Vector2i(floori(v.x), floori(v.z))
			if g.is_in_boundsv(c):
				g.set_point_solid(c, true)
	return g


func _cell(g: AStarGrid2D, p: Vector3) -> Vector2i:
	var r := g.region
	return Vector2i(clampi(floori(p.x), r.position.x, r.end.x - 1), clampi(floori(p.z), r.position.y, r.end.y - 1))


func _path(hall_id: int, a: Vector3, b: Vector3, dep: bool = true) -> Array:
	if not grids.has(hall_id):
		return [b]
	var g: AStarGrid2D = grids[hall_id]["dep" if dep else "arr"]
	var ca := _cell(g, a)
	var cb := _cell(g, b)
	var sa := g.is_point_solid(ca)
	var sb := g.is_point_solid(cb)
	g.set_point_solid(ca, false)
	g.set_point_solid(cb, false)
	var ids := g.get_id_path(ca, cb, true)
	g.set_point_solid(ca, sa)
	g.set_point_solid(cb, sb)
	var out := []
	for i in range(1, ids.size() - 1):
		out.append(Vector3(float(ids[i].x) + 0.5, 0.0, float(ids[i].y) + 0.5))
	out.append(b)
	return out


# ---------------------------------------------------------------- Fluggastbrücken

## Je Gate eine Brücke an der Außenwand. Sie fährt aus und dockt an Tür L1 an, wenn das
## zugeteilte Flugzeug in Reichweite am Stand steht, und fährt danach wieder ein.
func _rebuild_bridges() -> void:
	var old := bridges
	bridges = {}
	for it: Dictionary in game.items_of("fluggastbruecke"):
		var bid := (it["node"] as Node).get_instance_id()
		var b: Dictionary
		if old.has(bid):
			b = old[bid]
			old.erase(bid)
		else:
			var basis := Basis(Vector3.UP, float(it["rot"]) * PI * 0.5)
			b = _make_bridge(it["pos"], basis * Vector3(0, 0, 1))
		b["item"] = it
		b["gate"] = _gate_near(it)
		bridges[bid] = b
	for bid: int in old:
		var node: Variant = old[bid]["node"]
		if is_instance_valid(node):
			(node as Node).queue_free()


## Gate innen gegenüber der Brücke (höchstens 16 m entfernt).
func _gate_near(it: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var bd := 16.0
	for info: Dictionary in halls:
		for g: Dictionary in game.inside_of(info["hall"]):
			if g["id"] != "gate":
				continue
			var d := (g["pos"] as Vector3).distance_to(it["pos"])
			if d < bd:
				bd = d
				best = g
	return best


func _bridge_for_gate(gate: Dictionary) -> Dictionary:
	for bid: int in bridges:
		var b: Dictionary = bridges[bid]
		if not (b["gate"] as Dictionary).is_empty() and is_same(b["gate"], gate):
			return b
	return {}


## Bewegliche Teile einer Brücke: zwei Teleskoptunnel, Kabine mit Faltenbalg, Fahrwerk mit Hubsäule.
func _make_bridge(anchor: Vector3, out: Vector3) -> Dictionary:
	var root := Node3D.new()
	root.name = "Fluggastbruecke"
	add_child(root)
	var grey := Color(0.74, 0.75, 0.76)
	var dark := Color(0.26, 0.27, 0.29)
	var glass := Color(0.2, 0.3, 0.36, 0.6)
	# Tunnel als Einheitslänge entlang z (-0.5 … 0.5), wird gestreckt
	for e: Array in [["TunnelA", 1.45, 1.5], ["TunnelB", 1.3, 1.36]]:
		var tk := Kit.new()
		var hw: float = e[1]
		var hh: float = e[2]
		tk.box(Vector3(-hw, -hh, -0.5), Vector3(hw, hh, 0.5), grey)
		for side: float in [-1.0, 1.0]:
			tk.box(Vector3(side * hw - 0.02, -0.15, -0.5), Vector3(side * hw + 0.02, 0.7, 0.5), glass)
			tk.box(Vector3(side * hw - 0.03, -hh, -0.5), Vector3(side * hw + 0.03, -hh + 0.15, 0.5), dark)
		tk.box(Vector3(-hw - 0.05, hh, -0.5), Vector3(hw + 0.05, hh + 0.08, 0.5), dark)
		var mi := tk.instance(e[0])
		root.add_child(mi)
	var cab := Node3D.new()
	cab.name = "Kabine"
	root.add_child(cab)
	var ck := Kit.new()
	ck.box(Vector3(-1.8, -0.15, -1.4), Vector3(1.8, 2.75, 1.5), grey)
	ck.box(Vector3(-1.82, 1.2, -1.2), Vector3(1.82, 2.1, 1.2), glass)
	# Faltenbalg (Vordach) zur Flugzeugtür
	for i in range(4):
		var z := -1.4 - float(i) * 0.18
		ck.box(Vector3(-1.6 + float(i) * 0.05, -0.1, z - 0.18), Vector3(1.6 - float(i) * 0.05, 2.6 - float(i) * 0.03, z), Color(0.18, 0.18, 0.19))
	ck.box(Vector3(-1.9, 2.75, -1.6), Vector3(1.9, 2.9, 1.6), dark)
	ck.box(Vector3(-0.4, 2.9, 0.4), Vector3(0.4, 3.2, 1.0), Color(0.95, 0.55, 0.1, 0.3))
	cab.add_child(ck.instance("KabineModell"))
	var leg := Node3D.new()
	leg.name = "Fahrwerk"
	root.add_child(leg)
	var lk := Kit.new()
	lk.box(Vector3(-1.6, 0.3, -0.55), Vector3(1.6, 0.7, 0.55), dark)
	for wx: float in [-1.25, 1.25]:
		lk.cyl(Vector3(wx - 0.22, 0.45, 0), Vector3(wx + 0.22, 0.45, 0), 0.45, 0.45, Models.TYRE, 16, true, Models.METAL)
	leg.add_child(lk.instance("Raeder"))
	var post := MeshInstance3D.new()
	post.name = "Saeule"
	var pk := Kit.new()
	for sx: float in [-0.9, 0.9]:
		pk.box(Vector3(sx - 0.12, 0.0, -0.12), Vector3(sx + 0.12, 1.0, 0.12), Color(0.85, 0.7, 0.15))
	post.mesh = pk.commit()
	leg.add_child(post)
	var rest := anchor + out * 13.0 + out.cross(Vector3.UP) * 3.0
	var b := {"node": root, "anchor": anchor, "out": out, "end": rest, "rest": rest, "plane": {}, "height": 3.6,
		"cab_dir": out, "gate": {}, "wait": 0.0}
	_pose_bridge(b)
	return b


func _mi(k: Kit) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit()
	return mi


## Andocken: kurz warten (Triebwerke aus), weit ausfahren bis vor die Tür, dann langsam heranfahren.
## Beim Abflug zurück in die Parkstellung.
func _move_bridges(sim: float) -> void:
	for bid: int in bridges:
		var b: Dictionary = bridges[bid]
		var goal: Vector3 = b["rest"]
		var goal_h := 3.6
		var face: Vector3 = b["out"]
		var final := false
		var p: Dictionary = b["plane"]
		if not p.is_empty() and p.get("state", "") == "abfertigung" and is_instance_valid(p.get("node")):
			b["wait"] = float(b["wait"]) + sim
			var s: Dictionary = Models.SPECS.get(p["kind"], Models.SPECS["a320"])
			var pn := p["node"] as Node3D
			var xf := pn.global_transform
			var outward := (xf.basis * Vector3(-1, 0, 0)).normalized()
			outward.y = 0.0
			var door: Vector3 = xf * Vector3(-(float(s["r"]) + 0.15), 0.0, float(s["doors"][0]))
			var target := door + outward * 1.75
			if float(b["wait"]) > 4.0:
				var cur: Vector3 = b["end"]
				var approach := target + outward * 4.0
				goal = approach if Vector2(cur.x - target.x, cur.z - target.z).length() > 4.3 and not bool(b.get("near", false)) else target
				b["near"] = goal == target
				final = goal == target
				goal_h = float(s["cy"]) - 0.85
				face = -outward
		else:
			b["wait"] = 0.0
			b["near"] = false
		var cur2: Vector3 = b["end"]
		var spd := 0.4 if final else 1.4
		var step := spd * sim
		goal.y = 0.0
		cur2.y = 0.0
		var d := cur2.distance_to(goal)
		var moving := d > 0.02
		if d <= step:
			cur2 = goal
		else:
			cur2 += (goal - cur2) / d * step
		b["end"] = cur2
		b["moving"] = moving
		b["height"] = move_toward(float(b["height"]), goal_h, 0.25 * sim)
		b["cab_dir"] = (b["cab_dir"] as Vector3).slerp(face.normalized(), clampf(sim * 0.8, 0.0, 1.0)).normalized()
		_pose_bridge(b)


func _pose_bridge(b: Dictionary) -> void:
	var root: Node3D = b["node"]
	if not is_instance_valid(root):
		return
	var a: Vector3 = (b["anchor"] as Vector3) + Vector3(0, 4.6, 0) + (b["out"] as Vector3) * 1.4
	var e: Vector3 = b["end"]
	var h: float = b["height"]
	var tip := Vector3(e.x, h + 1.3, e.z)
	var dir := tip - a
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() < 0.5:
		return
	var length := dir.length()
	var bas := Basis.looking_at(dir.normalized(), Vector3.UP)
	# zwei Tunnelstücke überlappen sich wie ein Teleskop
	var la := length * 0.55 + 0.8
	var lb := length * 0.55
	var ta := root.get_node("TunnelA") as Node3D
	ta.global_transform = Transform3D(bas.scaled_local(Vector3(1, 1, la)), a + dir.normalized() * la * 0.5)
	var tb := root.get_node("TunnelB") as Node3D
	tb.global_transform = Transform3D(bas.scaled_local(Vector3(1, 1, lb)), tip - dir.normalized() * lb * 0.5)
	var cab := root.get_node("Kabine") as Node3D
	var cd: Vector3 = b["cab_dir"]
	cab.global_transform = Transform3D(Basis.looking_at(Vector3(cd.x, 0, cd.z).normalized(), Vector3.UP), Vector3(e.x, h, e.z))
	# Fahrwerk bei drei Vierteln der Länge, Hubsäule bis unter den Tunnel
	var leg := root.get_node("Fahrwerk") as Node3D
	var lp := a + dir * 0.72
	var ground := Vector3(lp.x, 0, lp.z)
	leg.global_transform = Transform3D(Basis.looking_at(flat.normalized().cross(Vector3.UP) if bool(b.get("moving", false)) else flat.normalized(), Vector3.UP), ground)
	var post := leg.get_node("Saeule") as Node3D
	post.scale = Vector3(1, maxf(lp.y - 1.4, 0.5), 1)
	post.position = Vector3(0, 0.7, 0)


# ---------------------------------------------------------------- Gepäckbänder

var belt_phase := 0.0


## Koffer laufen auf dem Band um (Umfang einer flachen Ellipse um die Insel).
func _belts(sim: float) -> void:
	var busy := false
	for per: Dictionary in people:
		busy = busy or not bool(per["dep"])
	if not busy:
		return
	belt_phase += sim * 0.9
	var straight := 7.2
	var r := 1.17
	var perim := 2.0 * straight + TAU * r
	for h: Dictionary in game.items_of("halle"):
		for it: Dictionary in game.inside_of(h):
			if it["id"] != "gepaeckband":
				continue
			var cases := (it["node"] as Node3D).get_node_or_null("Koffer")
			if cases == null:
				continue
			var n := cases.get_child_count()
			for i in range(n):
				var d := fmod(belt_phase + float(i) * perim / float(n), perim)
				var pos := Vector3.ZERO
				var yaw := 0.0
				if d < straight:
					pos = Vector3(-3.6 + d, 0, r)
				elif d < straight + PI * r:
					var a := (d - straight) / r
					pos = Vector3(3.6 + sin(a) * r, 0, cos(a) * r)
					yaw = a
				elif d < 2.0 * straight + PI * r:
					pos = Vector3(3.6 - (d - straight - PI * r), 0, -r)
					yaw = PI
				else:
					var a := (d - 2.0 * straight - PI * r) / r
					pos = Vector3(-3.6 - sin(a) * r, 0, -cos(a) * r)
					yaw = PI + a
				var c := cases.get_child(i) as Node3D
				c.position = pos + Vector3(0, 0.76, 0)
				c.rotation.y = yaw
