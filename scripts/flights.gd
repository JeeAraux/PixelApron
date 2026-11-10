extends Node3D
## Flugbetrieb: Flüge nach Plan anlegen, Anflug mit Abfangen, Aufsetzen, Ausrollen, Abrollen zum Stand,
## Abfertigung mit Bodenfahrzeugen, Pushback mit Schlepper, Rollen zum Rollhalteort, Aufreihen, Start.
##
## Rollen: Das Bugrad folgt einer geglätteten Linie (Ecken als Bögen), das Hauptfahrwerk zieht nach.
## Tempo nach Fläche (Piste, Rollweg, Vorfeld, Einrolllinie) und Kurvenradius, mit Anfahren und Bremsen.
## Rollwege werden wie im Stellwerk abschnittsweise reserviert. In den Pistenschutzbereich
## (näher als 90 m an der Pistenmitte) darf nur, wer die Piste hat: davor wird am Rollhalteort gewartet.
## Bei Tempo 1× vergeht pro Sekunde eine halbe Spielminute; Bewegungen in Metern pro Sekunde.

const Catalog = preload("res://scripts/catalog.gd")
const Factory = preload("res://scripts/factory.gd")
const Airside = preload("res://scripts/airside.gd")
const GameState = preload("res://scripts/game_state.gd")
const Models = preload("res://scripts/models.gd")

const CLOCK := 0.5             # Spielminuten pro Simulationssekunde
const INTERVAL := 7.0          # Spielminuten zwischen neuen Flügen bei mittlerer Zufriedenheit
const APPROACH_DIST := 2200.0
const GLIDE := 0.0524          # 3 Grad
const LOOKAHEAD := 80.0        # so weit voraus reserviert ein rollendes Flugzeug
const CLEAR := 30.0            # so weit hält das Bugrad vor einem belegten Abschnitt
const GSE_SPEED := 9.0
# Rollen (m/s, m/s²)
const V_RWY := 24.0
const V_TAXI := 14.0           # ~27 kn auf geraden Rollwegen
const V_APRON := 8.0
const V_LEAD := 3.0            # auf der Einrolllinie in die Position
const LAT := 1.0               # Querbeschleunigung in Kurven
const ACC := 0.7
const DEC := 1.4
const DEC_LAND := 2.4          # Bremsen nach dem Aufsetzen
const V_EXIT := 16.0           # Abrollgeschwindigkeit
const TURN_R := 35.0           # Radius beim Ausrunden von Ecken
const PUSH_V := 1.3
const TAKEOFF_ACC := 2.2

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
var traffic: Variant = null    # traffic.gd (Zufahrt Parkhaus)
var ops: Variant = null        # ground_ops.gd (Schlepper, Treppen, Busse)
var gate_short := 0.0          # Spielminuten, in denen noch "zu wenige Gates" gemeldet wird
var rwy_rev := false           # Betriebsrichtung: false = vom Anfang der Piste zum Ende
var _route_sets: Dictionary = {}   # je rollendem Flugzeug: verbleibende Route (für Gegenverkehr)


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
	_runway_direction()
	next_flight -= sim * CLOCK
	if next_flight <= 0.0:
		next_flight = INTERVAL * lerpf(1.6, 0.55, game.satisfaction / 100.0)
		_try_spawn()
	_build_route_sets()
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
	if ops != null:
		ops.step(sim)
	_satisfaction(sim)


func _rebuild() -> void:
	dirty = false
	graph.build(game.lines, game.stands(), game.items_of("rollhalt"))
	reserved.clear()
	for p: Dictionary in planes.duplicate():
		var st: Dictionary = p["stand"]
		if not st.is_empty() and not is_instance_valid(st["node"]):
			_remove(p, "%s: Stand wurde abgerissen" % p["code"])
			continue
		p["path"] = []   # wird beim nächsten Schritt neu gesucht
		p.erase("route")
		if p["state"] in ["abfertigung", "pushback"]:
			_reserve(_stand_id(p), int(p["id"]))


func _stand_id(p: Dictionary) -> int:
	var st: Dictionary = p["stand"]
	if st.is_empty() or not is_instance_valid(st["node"]):
		return -1
	return graph.stand_node.get((st["node"] as Node).get_instance_id(), -1)


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
	var need := INF
	for kind: String in Catalog.PLANES:
		need = minf(need, float(Catalog.PLANES[kind]["min_rwy"]))
	if length < need:
		return "Piste zu kurz (mindestens %d m)" % int(need)
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
	if game.night > 0.5 and not runway_lit():
		reason = "Nachts keine Landungen: die Piste hat keine Befeuerung (Befeuerungsstation mit Strom bauen)"
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
	# Flugzeugtyp: muss auf die Piste (Mindestlänge) und auf den Stand (Code) passen
	var length := float(s.size() - 1)
	var stand_code := String(Catalog.ITEMS[stand["id"]].get("code", "C"))
	var kinds := []
	for k: String in Catalog.PLANES:
		var pl: Dictionary = Catalog.PLANES[k]
		if length < float(pl["min_rwy"]):
			continue
		if String(pl["code"]) == "E" and stand_code != "E":
			continue
		kinds.append(k)
		if stand_code == "E" and String(pl["code"]) == "E":
			kinds.append(k)   # Großraum-Stände bevorzugt für Großraumflugzeuge
			kinds.append(k)
	if kinds.is_empty():
		reason = "Piste zu kurz für die Flugzeuge"
		return
	var kind: String = kinds[randi() % kinds.size()]
	var wide := String(Catalog.PLANES[kind]["code"]) == "E"
	var probe := graph.path(graph.nearest(s[s.size() / 2], "piste"), stand_id, {}, Vector3.ZERO, wide)
	if probe.is_empty():
		reason = "Kein Rollweg zwischen Piste und Stand" + (" (Großraumflugzeuge brauchen breite Rollwege)" if wide else "")
		return
	var airline: Array = Catalog.AIRLINES[randi() % Catalog.AIRLINES.size()]
	var dest := _destination(kind)
	counter += 1
	var ends := _rwy_ends(rwy)
	var dir: Vector3 = ends[1]
	var td: Vector3 = (ends[0] as Vector3) + dir * 300.0
	var node := Factory.make_plane(kind, airline[1])
	add_child(node)
	var spec: Dictionary = Models.SPECS.get(kind, Models.SPECS["a320"])
	var p := {
		"id": counter, "code": "%s %d" % [airline[0], 200 + (counter * 37) % 700], "kind": kind,
		"city": dest[0], "schengen": dest[1], "node": node,
		"state": "anflug", "pos": td, "alt": 400.0,
		"heading": dir, "speed": float(Catalog.PLANES[kind]["vapp"]), "stand": stand, "path": [],
		"timer": 0.0, "turn": 1.0, "wait": 0.0, "ghost": 0.0, "rerouted": false, "rwy": rwy, "dir": dir, "td": td,
		"gse": [], "delay": 0.0, "pitch": deg_to_rad(2.5), "roll": 0.0, "gear": 0.0, "wide": wide,
		"ng": -float(spec["nose_gear_z"]), "mg": float(spec["main_gear_z"]),
	}
	_plan_approach(p)
	runway_owner = counter
	planes.append(p)
	reason = ""
	if ops != null:
		var sfwd := (stand["node"] as Node3D).global_transform.basis.z
		sfwd.y = 0.0
		ops.prestage(p, _park_pos(p), sfwd.normalized())
		# selten: Notfall an Bord, die Feuerwehr fährt in Bereitschaft an die Piste
		if randf() < 0.05 and ops.fire_alarm(p):
			p["notfall"] = true
			game.toast.emit("%s meldet ein technisches Problem: Feuerwehr in Bereitschaft" % p["code"])


## Ziel passend zur Reichweite des Flugzeugs: [Name, Schengen?]
func _destination(kind: String) -> Array:
	var rng := String(Catalog.PLANES[kind]["range"])
	var ok := []
	for d: Array in Catalog.DESTINATIONS:
		var dr := String(d[2])
		if dr == rng or (rng == "mittel" and dr == "kurz") or (rng == "kurz" and dr == "mittel" and randf() < 0.3):
			ok.append(d)
	if ok.is_empty():
		ok = Catalog.DESTINATIONS
	var d: Array = ok[randi() % ok.size()]
	return [d[0], d[1]]


## Anfang und Richtung der Piste in der aktuellen Betriebsrichtung: [Schwelle, Richtung]
func _rwy_ends(rwy: Dictionary) -> Array:
	var s: PackedVector3Array = rwy["samples"]
	var a := s[0]
	var b := s[s.size() - 1]
	if rwy_rev:
		return [b, (a - b).normalized()]
	return [a, (b - a).normalized()]


## Gelandet und gestartet wird gegen den Wind. Gewechselt wird nur, wenn gerade niemand die Piste nutzt.
func _runway_direction() -> void:
	var rwy := _runway()
	if rwy.is_empty():
		return
	var s: PackedVector3Array = rwy["samples"]
	var d := (s[s.size() - 1] - s[0]).normalized()
	var head := d.dot(game.wind_from())   # > 0: Gegenwind bei Landung Richtung Ende
	var want_rev := rwy_rev
	if head < -0.2:
		want_rev = true
	elif head > 0.2:
		want_rev = false
	if want_rev == rwy_rev or runway_owner != -1:
		return
	for p: Dictionary in planes:
		if p["state"] in ["anflug", "landung", "start", "wartet"]:
			return
	rwy_rev = want_rev
	game.toast.emit("Wind gedreht: Betrieb jetzt auf Piste %02d" % _active_number())


## Wind und Betriebsrichtung für die Anzeige.
func wind_text() -> String:
	var n := _active_number()
	var w := "Wind %03d° %d kn" % [roundi(game.wind_dir), roundi(game.wind_kt)]
	return w + (" · Piste %02d in Betrieb" % n if n > 0 else "")


func _active_number() -> int:
	var rwy := _runway()
	if rwy.is_empty():
		return 0
	var nums := Factory.runway_numbers(rwy["samples"])
	return nums[1] if rwy_rev else nums[0]


## Anflug: aus einer Warteschleife seitlich heran, in einer Kurve mit Querneigung auf den Endanflug,
## dann 3°-Gleitpfad. Die Kurve wird vorab abgetastet.
func _plan_approach(p: Dictionary) -> void:
	var dir: Vector3 = p["dir"]
	var td: Vector3 = p["td"]
	var entry := td - dir * 2600.0
	var side := dir.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
	var start := entry - dir * 1800.0 + side * randf_range(2200.0, 3200.0)
	var h0 := (entry - dir * 900.0 - start).normalized()
	var c1 := start + h0 * 1400.0
	var c2 := entry - dir * 1500.0
	var pts := PackedVector3Array()
	for i in range(121):
		var t := float(i) / 120.0
		var u := 1.0 - t
		pts.append(start * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + entry * (t * t * t))
	var cum := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	p["approach"] = {"pts": pts, "s": cum, "total": cum[cum.size() - 1], "alt0": 420.0, "alt1": 2600.0 * GLIDE}
	p["as"] = 0.0
	p["pos"] = start
	p["heading"] = h0
	p["alt"] = 420.0
	p["speed"] = float(Catalog.PLANES[p["kind"]]["vapp"]) * 1.3
	_place(p)


# ---------------------------------------------------------------- Reservierungen

## Ist Knoten n für Flugzeug id frei? Reservierungen der Flugzeuge in `ignore` (Folgeverkehr hinter uns) zählen nicht.
func _free_for(n: int, id: int, ignore: Dictionary = {}) -> bool:
	if n < 0:
		return true
	if reserved.has(n) and int(reserved[n]) != id and not ignore.has(int(reserved[n])):
		return false
	for m: int in graph.near[n]:
		if reserved.has(m) and int(reserved[m]) != id and not ignore.has(int(reserved[m])):
			return false
	return true


## Wer blockiert Knoten n für Flugzeug id (Besitzer der Reservierung, sonst -1)?
func _blocker(n: int, id: int, ignore: Dictionary = {}) -> int:
	if reserved.has(n) and int(reserved[n]) != id and not ignore.has(int(reserved[n])):
		return int(reserved[n])
	for m: int in graph.near[n]:
		if reserved.has(m) and int(reserved[m]) != id and not ignore.has(int(reserved[m])):
			return int(reserved[m])
	return -1


## Liegt q in Fahrtrichtung von p vor ihm (auf derselben Linie, höchstens 25 m seitlich)?
func _in_front(p: Dictionary, q: Dictionary, min_ahead: float = 0.0) -> bool:
	var h: Vector3 = p["heading"]
	h.y = 0.0
	if h.length_squared() < 0.01:
		return false
	h = h.normalized()
	var d: Vector3 = (q["pos"] as Vector3) - (p["pos"] as Vector3)
	d.y = 0.0
	return d.dot(h) > min_ahead and absf(d.dot(h.cross(Vector3.UP))) < 25.0


## Steht oder rollt ein anderes Flugzeug am Boden so nah, dass sich die Rümpfe überdecken?
func _overlapping(p: Dictionary) -> bool:
	for q: Dictionary in planes:
		if is_same(q, p) or not (q["state"] in ["rollt_ein", "rollt_aus", "wartet", "pushback"]):
			continue
		if (q["pos"] as Vector3).distance_to(p["pos"]) < 42.0:
			return true
	return false


## Flugzeuge, die hinter p in dieselbe Richtung rollen. Der Vordere hat Vorrang: was ein Folgendes
## vor ihm schon reserviert hat, darf er trotzdem befahren (sonst warten beide aufeinander).
func _followers(p: Dictionary) -> Dictionary:
	var out := {}
	var h: Vector3 = p["heading"]
	h.y = 0.0
	if h.length_squared() < 0.01:
		return out
	h = h.normalized()
	for q: Dictionary in planes:
		if is_same(q, p) or not (q["state"] in ["rollt_ein", "rollt_aus", "wartet"]):
			continue
		var qh: Vector3 = q["heading"]
		qh.y = 0.0
		if qh.length_squared() < 0.01 or qh.normalized().dot(h) < 0.8:
			continue
		if _in_front(q, p, 15.0):
			out[int(q["id"])] = true
	return out


## Flugnummer zu einer ID (oder "?").
func code_of(id: int) -> String:
	var q := _plane_by_id(id)
	return String(q.get("code", "?"))


func _plane_by_id(id: int) -> Dictionary:
	for q: Dictionary in planes:
		if int(q["id"]) == id:
			return q
	return {}


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
			var vapp := float(Catalog.PLANES[p["kind"]]["vapp"])
			if p.has("approach"):
				# Kurve auf den Endanflug: Bahn folgen, Querneigung aus der Kurvenkrümmung
				var ap: Dictionary = p["approach"]
				var cum: PackedFloat32Array = ap["s"]
				var pts: PackedVector3Array = ap["pts"]
				var v: float = p["speed"]
				v = move_toward(v, vapp * 1.08, 0.6 * sim)
				p["speed"] = v
				var s_now := minf(float(p["as"]) + v * sim, float(ap["total"]))
				p["as"] = s_now
				var i := 0
				while i < cum.size() - 2 and cum[i + 1] <= s_now:
					i += 1
				var f := clampf((s_now - cum[i]) / maxf(cum[i + 1] - cum[i], 0.01), 0.0, 1.0)
				p["pos"] = pts[i].lerp(pts[i + 1], f)
				var old_h: Vector3 = p["heading"]
				var nh := (pts[i + 1] - pts[i]).normalized()
				var turn := old_h.cross(nh).y / maxf(v * sim, 0.01)
				p["heading"] = nh
				var want_roll := clampf(atan(v * v * turn / 9.81), -0.5, 0.5)
				p["roll"] = lerpf(float(p.get("roll", 0.0)), want_roll, clampf(sim * 1.5, 0.0, 1.0))
				var k := s_now / maxf(float(ap["total"]), 1.0)
				p["alt"] = lerpf(float(ap["alt0"]), float(ap["alt1"]), k)
				p["pitch"] = deg_to_rad(1.5)
				if s_now >= float(ap["total"]) - 0.01:
					p.erase("approach")
					p["heading"] = p["dir"]
				_animate(p, sim)
				_place(p)
				return
			p["roll"] = lerpf(float(p.get("roll", 0.0)), 0.0, clampf(sim * 1.5, 0.0, 1.0))
			p["speed"] = move_toward(float(p["speed"]), vapp, 0.5 * sim)
			var pos: Vector3 = p["pos"]
			var to_td := td - pos
			var move := float(p["speed"]) * sim
			if to_td.length() <= move:
				p["pos"] = td
				p["alt"] = 0.0
				p["state"] = "landung"
				p["speed"] = float(p["speed"]) * 0.97
				movements.append(game.minutes)
				pax_log.append([game.minutes, int(Catalog.PLANES[p["kind"]]["pax"]), false])
			else:
				p["pos"] = pos + to_td.normalized() * move
				var alt := maxf(0.0, (to_td.length() - move) * GLIDE)
				# Abfangen: kurz vor dem Aufsetzen flacher und Nase hoch
				if alt < 14.0:
					alt = 14.0 * pow(alt / 14.0, 1.6)
				p["alt"] = alt
				p["pitch"] = deg_to_rad(lerpf(5.5, 2.5, clampf(alt / 14.0, 0.0, 1.0)))
		"landung":
			var v: float = p["speed"]
			v = maxf(V_EXIT, v - DEC_LAND * sim)
			p["speed"] = v
			p["pos"] = (p["pos"] as Vector3) + dir * v * sim
			p["pitch"] = move_toward(float(p["pitch"]), 0.0, deg_to_rad(2.0) * sim)
			if v <= V_EXIT + 0.01 and float(p["pitch"]) < 0.01:
				if ops != null and bool(p.get("notfall", false)):
					ops.fire_clear(p)
				p["state"] = "rollt_ein"
				p["path"] = []
				p.erase("route")
		"rollt_ein":
			if not p.has("route"):
				if not _plan_arrival(p):
					_remove(p, "%s findet keinen Weg zum Stand" % p["code"])
					return
			var res := _drive(p, sim)
			if runway_owner == id and _vacated(p):
				runway_owner = -1
			if res == "ziel":
				if runway_owner == id:
					runway_owner = -1
				_park(p)
		"abfertigung":
			p["timer"] = float(p["timer"]) - sim * CLOCK
			_update_gse(p, sim)
			var f := 1.0 - float(p["timer"]) / maxf(float(p["turn"]), 0.01)
			if ops != null:
				ops.turn_step(p, f, sim)
				if f >= 0.3:
					ops.want_board(p)
				if f >= 0.82:
					ops.call_tug(p, float(p["ng"]))
			var ready: bool = ops == null or (ops.remote_done(p) and ops.turn_clear(p))
			if float(p["timer"]) <= 0.0 and not ready:
				p["delay"] = float(p["delay"]) + sim * CLOCK
			if float(p["timer"]) <= 0.0 and ready:
				_clear_gse(p)
				if terminal != null:
					terminal.flight_left(p)
				if ops != null:
					ops.turn_end(p)
					ops.call_tug(p, float(p["ng"]))
					ops.remote_leave(p)
				p["state"] = "pushback"
				p["push_phase"] = "bereit"
				p["ptimer"] = 0.0
		"pushback":
			_pushback(p, sim)
		"rollt_aus", "wartet":
			if not p.has("route"):
				if not _plan_departure(p):
					_remove(p, "%s findet keinen Weg zur Piste" % p["code"])
					return
			var res := _drive(p, sim)
			p["state"] = "wartet" if res == "piste" else "rollt_aus"
			if res == "piste":
				p["delay"] = float(p["delay"]) + sim * CLOCK
			if res == "ziel":
				p["state"] = "start"
				p["speed"] = 0.0
				p["lineup"] = 3.0
				p["stand"] = {}
		"start":
			var h: Vector3 = p["heading"]
			if float(p["alt"]) < 150.0:
				p["heading"] = h.lerp(dir, clampf(sim * 1.5, 0.0, 1.0)).normalized()
			if float(p.get("lineup", 0.0)) > 0.0:
				p["lineup"] = float(p["lineup"]) - sim
			else:
				var v: float = float(p["speed"]) + TAKEOFF_ACC * sim
				p["speed"] = v
				p["pos"] = (p["pos"] as Vector3) + (p["heading"] as Vector3) * v * sim
				var vr := float(Catalog.PLANES[p["kind"]]["vr"])
				if v > vr:
					p["pitch"] = move_toward(float(p["pitch"]), deg_to_rad(9.0), deg_to_rad(3.0) * sim)
				if v > vr + 4.0:
					p["alt"] = float(p["alt"]) + v * 0.11 * sim
				p["speed"] = minf(v, vr * 1.6)
				# ab 150 m eine Standardkurve in Richtung Ziel, mit Querneigung
				if float(p["alt"]) > 150.0:
					if not p.has("out_heading"):
						var ang := randf_range(0.6, 1.9) * (1.0 if randf() < 0.5 else -1.0)
						p["out_heading"] = dir.rotated(Vector3.UP, ang)
					var cur: Vector3 = p["heading"]
					var goal: Vector3 = p["out_heading"]
					var rate := deg_to_rad(3.0) * sim
					var ang2 := cur.signed_angle_to(goal, Vector3.UP)
					var step := clampf(ang2, -rate, rate)
					p["heading"] = cur.rotated(Vector3.UP, step)
					var want_roll := clampf(atan(v * (step / maxf(sim, 0.001)) / 9.81), -0.45, 0.45)
					p["roll"] = lerpf(float(p.get("roll", 0.0)), want_roll, clampf(sim * 1.2, 0.0, 1.0))
			if float(p["alt"]) > 40.0 and runway_owner == id:
				_release_all(id)
				runway_owner = -1
				movements.append(game.minutes)
				pax_log.append([game.minutes, int(Catalog.PLANES[p["kind"]]["pax"]), true])
			if float(p["alt"]) > 650.0 or (p["pos"] as Vector3).length() > 4200.0:
				var plane: Dictionary = Catalog.PLANES[p["kind"]]
				done += 1
				var fare := int(float(int(plane["pax"]) * Catalog.TICKET_FEE) * lerpf(0.7, 1.2, game.satisfaction / 100.0))
				var shops := int(plane["pax"]) * (int(terminal.retail_per_pax()) if terminal != null else 0)
				game.earn(fare + shops, "Abflug %s nach %s" % [p["code"], p["city"]] + (" (mit Café und Shop)" if shops > 0 else ""))
				if float(p["delay"]) < 3.0:
					game.satisfaction = minf(100.0, game.satisfaction + 0.6)
				_remove(p, "")
				return
	_animate(p, sim)
	_place(p)


## Hat das gelandete Flugzeug den Pistenschutzbereich verlassen?
func _vacated(p: Dictionary) -> bool:
	return graph.runway_distance(p["pos"]) > graph.hold_limit(graph.nearest(p["pos"])) + 20.0


## Ist ein landendes Flugzeug so nah, dass kein Start mehr dazwischen passt?
## (Start mit Aufreihen dauert gut eine Minute; im Endanflug fliegt man rund 70 m/s.)
func _arrival_close() -> bool:
	for q: Dictionary in planes:
		if q["state"] == "landung":
			return true
		if q["state"] == "anflug":
			var remaining := (q["pos"] as Vector3).distance_to(q["td"])
			if q.has("approach"):
				var ap: Dictionary = q["approach"]
				remaining = float(ap["total"]) - float(q.get("as", 0.0)) + 2600.0
			if remaining < 5500.0:
				return true
	return false


## Leuchtet die Befeuerung der Betriebspiste (Befeuerungsstation mit Strom in der Nähe)?
func runway_lit() -> bool:
	if game.legacy_lights:
		return true
	var rwy := _runway()
	if rwy.is_empty():
		return false
	var sm: PackedVector3Array = rwy["samples"]
	for st: Dictionary in game.items_of("befeuerungsstation"):
		if game.supplied(st, "strom") and GameState.seg_dist(st["pos"], sm[0], sm[sm.size() - 1]) <= 450.0:
			return true
	return false


func _may_take_runway(id: int) -> bool:
	return runway_owner == id or (runway_owner == -1 and not _arrival_close())


## Bugrad-Position und Hauptfahrwerk aus Mitte und Richtung.
func _nose(p: Dictionary) -> Vector3:
	return (p["pos"] as Vector3) + (p["heading"] as Vector3) * float(p["ng"])


func _set_gear(p: Dictionary) -> void:
	p["mg_pos"] = (p["pos"] as Vector3) - (p["heading"] as Vector3) * float(p["mg"])


# ---------------------------------------------------------------- Wege planen

## Weg von der Landebahn (oder von dort, wo das Flugzeug gerade ist) zum Stand.
func _plan_arrival(p: Dictionary) -> bool:
	var h: Vector3 = p["heading"]
	var nose := _nose(p)
	var start := -1
	if graph.kind.size() > 0 and graph.runway_distance(p["pos"]) < 30.0:
		var v: float = p["speed"]
		start = _node_ahead(nose, h, maxf(25.0, v * v / (2.0 * DEC) * 0.7))
	if start < 0:
		start = graph.nearest(nose)
	var goal := _stand_id(p)
	if start < 0 or goal < 0:
		return false
	var nodes := graph.path(start, goal, {}, h, bool(p.get("wide", false)))
	if nodes.is_empty():
		return false
	var st: Dictionary = p["stand"]
	var fwd := (st["node"] as Node3D).global_transform.basis.z.normalized()
	var park := _park_pos(p)
	_set_route(p, nodes, park + fwd * float(p["ng"]), true)
	return true


## Weg vom Ende des Pushbacks zur Startposition auf der Piste.
func _plan_departure(p: Dictionary) -> bool:
	var h: Vector3 = p["heading"]
	var start := graph.nearest_taxi(p["pos"], 40.0)
	if start < 0:
		start = graph.nearest(p["pos"])
	var goal := _rwy_goal(p)
	if start < 0 or goal < 0:
		return false
	var nodes := graph.path(start, goal, {}, h, bool(p.get("wide", false)))
	if nodes.is_empty():
		return false
	_set_route(p, nodes, null, false)
	return true


func _rwy_goal(p: Dictionary) -> int:
	var ends := _rwy_ends(p["rwy"])
	p["dir"] = ends[1]
	return graph.nearest((ends[0] as Vector3) + (ends[1] as Vector3) * 70.0, "piste")


## Nächster Pistenknoten mindestens min_d vor dem Bugrad.
func _node_ahead(nose: Vector3, h: Vector3, min_d: float) -> int:
	var best := -1
	var bd := INF
	for i in range(graph.pos.size()):
		if graph.kind[i] != "piste":
			continue
		var to := graph.pos[i] - nose
		var along := to.dot(h)
		if along < min_d:
			continue
		var d := to.length()
		if d < bd:
			bd = d
			best = i
	return best


func _park_pos(p: Dictionary) -> Vector3:
	var st: Dictionary = p["stand"]
	var fwd := (st["node"] as Node3D).global_transform.basis.z.normalized()
	var nose := float(Catalog.PLANES[p["kind"]]["nose"])
	var depth: float = (Catalog.ITEMS[st["id"]]["size"] as Vector2).y
	return (st["pos"] as Vector3) + fwd * (depth * 0.5 - 6.0 - nose)


## Rolllinie aus Knoten bauen: Douglas-Peucker, Ecken als Bögen ausrunden, dicht abtasten,
## je Meter ein Tempolimit aus Fläche und Krümmung, rückwärts die Bremskurve.
func _set_route(p: Dictionary, nodes: Array, end_pt: Variant, stand_end: bool) -> void:
	var start := _nose(p)
	var h: Vector3 = p["heading"]
	_set_gear(p)
	var first := 0
	while first < nodes.size() - 1:
		var dq := graph.pos[nodes[first]] - start
		if dq.length() < 32.0 and dq.dot(h) < 4.0:
			first += 1
		else:
			break
	var pts: Array = [start]
	var vk: Array = [_kind_v(graph.kind[nodes[mini(first, nodes.size() - 1)]])]
	for k in range(first, nodes.size()):
		var q: Vector3 = graph.pos[nodes[k]]
		if k == nodes.size() - 1 and end_pt != null:
			q = end_pt
		if q.distance_to(pts[pts.size() - 1]) > 0.8:
			pts.append(q)
			vk.append(_kind_v(graph.kind[nodes[k]]))
	if pts.size() < 2:
		pts.append(start + h * 2.0)
		vk.append(V_APRON)
	var keep := _simplify(pts, 0.7)
	var P: Array = []
	var seg_v: Array = []   # Tempo des Abschnitts, der an P[i] endet
	for i in range(keep.size()):
		P.append(pts[keep[i]])
		var v := INF
		if i == 0:
			v = vk[0]
		else:
			for j in range(int(keep[i - 1]) + 1, int(keep[i]) + 1):
				v = minf(v, float(vk[j]))
		seg_v.append(v)
	# Ecken ausrunden
	var n := P.size()
	var cut := []
	var ang := []
	for i in range(n):
		cut.append(0.0)
		ang.append(0.0)
	for i in range(1, n - 1):
		var u: Vector3 = ((P[i - 1] as Vector3) - (P[i] as Vector3)).normalized()
		var w: Vector3 = ((P[i + 1] as Vector3) - (P[i] as Vector3)).normalized()
		var theta := PI - acos(clampf(u.dot(w), -1.0, 1.0))
		ang[i] = theta
		if theta > 0.02:
			# flache Abzweige (Schnellabrollwege) mit großem Radius, enge mit TURN_R
			cut[i] = maxf(TURN_R * tan(minf(theta, 2.6) * 0.5), 25.0)
	for _pass in range(2):
		for i in range(n - 1):
			var seg_len: float = (P[i] as Vector3).distance_to(P[i + 1])
			var sum: float = float(cut[i]) + float(cut[i + 1])
			if sum > seg_len * 0.98 and sum > 0.0:
				var f := seg_len * 0.98 / sum
				cut[i] = float(cut[i]) * f
				cut[i + 1] = float(cut[i + 1]) * f
	var out := PackedVector3Array([P[0]])
	var vl := PackedFloat32Array([float(seg_v[mini(1, n - 1)])])
	for i in range(1, n):
		var a: Vector3 = P[i - 1]
		var b: Vector3 = P[i]
		var dv := (b - a).normalized()
		var s1 := b - dv * float(cut[i])
		_dense(out, vl, s1, float(seg_v[i]))
		if i < n - 1 and float(cut[i]) > 0.05:
			var w: Vector3 = ((P[i + 1] as Vector3) - b).normalized()
			var e := b + w * float(cut[i])
			var theta: float = ang[i]
			var radius := float(cut[i]) / maxf(tan(theta * 0.5), 0.01)
			var vr := clampf(sqrt(LAT * radius * 0.8), 2.5, minf(float(seg_v[i]), float(seg_v[i + 1])))
			var steps := maxi(3, ceili(radius * theta / 1.5))
			for k in range(1, steps + 1):
				var t := float(k) / float(steps)
				var q := s1 * ((1.0 - t) * (1.0 - t)) + b * (2.0 * (1.0 - t) * t) + e * (t * t)
				out.append(q)
				vl.append(vr)
	# Bogenlänge und Bremskurve
	var cum := PackedFloat32Array()
	cum.resize(out.size())
	cum[0] = 0.0
	for i in range(1, out.size()):
		cum[i] = cum[i - 1] + out[i - 1].distance_to(out[i])
	var total := cum[cum.size() - 1]
	var cap := PackedFloat32Array()
	cap.resize(out.size())
	cap[out.size() - 1] = 0.0
	for i in range(out.size() - 2, -1, -1):
		var ds := cum[i + 1] - cum[i]
		cap[i] = minf(vl[i], sqrt(cap[i + 1] * cap[i + 1] + 2.0 * DEC * ds))
		if stand_end:
			var rest := total - cum[i]
			cap[i] = minf(cap[i], 0.25 + sqrt(2.0 * 0.3 * rest))
			if rest < 30.0:
				cap[i] = minf(cap[i], V_LEAD)
	# Bogenlänge, an der die Linie jedem Knoten am nächsten kommt
	var node_s := PackedFloat32Array()
	node_s.resize(nodes.size())
	var idx := 0
	for k in range(nodes.size()):
		if k < first:
			node_s[k] = 0.0
			continue
		var q: Vector3 = graph.pos[nodes[k]]
		var best := idx
		var bd := INF
		for i in range(idx, mini(out.size(), idx + 160)):
			var d := out[i].distance_squared_to(q)
			if d < bd:
				bd = d
				best = i
		idx = best
		node_s[k] = cum[best]
	p["path"] = nodes
	p["route"] = {"pts": out, "s": cum, "cap": cap, "node_s": node_s, "total": total, "stand": stand_end}
	p["rs"] = 0.0
	p["ri"] = 0
	p["pk"] = 0
	for k in range(first):
		_reserve(nodes[k], int(p["id"]))


func _kind_v(k: String) -> float:
	match k:
		"piste":
			return V_RWY
		"rollweg", "rollweg_breit":
			return V_TAXI
		"vorfeld", "rolllinie":
			return V_APRON
	return V_LEAD


func _dense(out: PackedVector3Array, vl: PackedFloat32Array, to: Vector3, v: float) -> void:
	var from := out[out.size() - 1]
	var d := from.distance_to(to)
	var steps := maxi(1, ceili(d / 2.0))
	for k in range(1, steps + 1):
		out.append(from.lerp(to, float(k) / float(steps)))
		vl.append(v)


## Douglas-Peucker: Indizes der Punkte, die übrig bleiben.
func _simplify(pts: Array, tol: float) -> Array:
	var keep := {0: true, pts.size() - 1: true}
	var stack := [[0, pts.size() - 1]]
	while not stack.is_empty():
		var seg: Array = stack.pop_back()
		var a: int = seg[0]
		var b: int = seg[1]
		var pa: Vector3 = pts[a]
		var pb: Vector3 = pts[b]
		var best := -1
		var bd := tol
		for i in range(a + 1, b):
			var d := Airside._seg_dist(pts[i], pa, pb)
			if d > bd:
				bd = d
				best = i
		if best >= 0:
			keep[best] = true
			stack.append([a, best])
			stack.append([best, b])
	var out := keep.keys()
	out.sort()
	return out


# ---------------------------------------------------------------- Rollen

## Ein Rollschritt entlang der Linie. Rückgabe: "fahrt", "ziel", "belegt" oder "piste" (wartet am Rollhalteort).
func _drive(p: Dictionary, sim: float) -> String:
	var id: int = p["id"]
	var r: Dictionary = p["route"]
	var pts: PackedVector3Array = r["pts"]
	var cum: PackedFloat32Array = r["s"]
	var cap: PackedFloat32Array = r["cap"]
	var node_s: PackedFloat32Array = r["node_s"]
	var total: float = r["total"]
	var nodes: Array = p["path"]
	var rs: float = p["rs"]
	var ghost := float(p["ghost"]) > 0.0
	if ghost:
		var g := float(p["ghost"]) - sim
		# Notlösung erst beenden, wenn wir am anderen ganz vorbei sind
		if g <= 0.0 and _overlapping(p):
			g = 0.5
		p["ghost"] = g
	var foll := {} if ghost else _followers(p)
	# Freigabe voraus: Knoten reservieren, bis einer belegt ist oder die Piste nicht frei
	var limit := total
	var why := ""
	var k: int = p["pk"]
	while k < nodes.size() and node_s[k] < rs - 0.5:
		k += 1
	p["pk"] = k
	# Gegenverkehr: Wer weiter von der gemeinsamen Strecke entfernt ist, wartet davor
	var yield_s := INF if ghost else _yield_point(p, nodes, node_s, k, rs)
	if yield_s < INF:
		limit = minf(limit, maxf(yield_s, rs))
		why = "belegt"
	var kk := k
	while kk < nodes.size():
		var n: int = nodes[kk]
		if node_s[kk] - rs > LOOKAHEAD:
			break
		if node_s[kk] > limit + 6.0:
			break   # nicht weiter reservieren, als wir fahren dürfen
		if graph.zone[n] == 1 and runway_owner != id:
			if _may_take_runway(id):
				runway_owner = id
			else:
				limit = minf(limit, _hold_s(p, kk))
				why = "piste"
				break
		if not ghost and not _free_for(n, id, foll):
			limit = minf(limit, node_s[kk] - CLEAR)
			why = "belegt"
			p["blocked_by"] = _blocker(n, id, foll)
			break
		# Blocksicherung: einen Rollwegabschnitt bis zur nächsten Kreuzung nur befahren,
		# wenn er ganz frei ist (sonst stehen sich zwei Flugzeuge Nase an Nase gegenüber)
		if not ghost and int(reserved.get(n, -1)) != id:
			var blk := _block_ahead(nodes, node_s, kk, id, foll)
			if int(blk[0]) >= 0:
				limit = minf(limit, node_s[kk] - CLEAR - 14.0)
				why = "belegt"
				p["blocked_by"] = int(blk[0])
				break
			for nb: int in blk[1]:
				_reserve(nb, id)
		if ghost and not _free_for(n, id):
			kk += 1
			continue
		_reserve(n, id)
		kk += 1
	# Was hinter dem Haltepunkt schon reserviert war, wieder freigeben (der andere soll vorbeikommen).
	# Nur wenn wir dort noch sicher anhalten können; sonst bleibt alles belegt, wo wir stehen.
	if why == "belegt" and limit > rs + 5.0:
		for j in range(k, mini(nodes.size(), k + 40)):
			var nj: int = nodes[j]
			if node_s[j] > limit + 6.0 and int(reserved.get(nj, -1)) == id:
				reserved.erase(nj)
	# Letzte Sicherung: steht oder kommt direkt voraus ein Flugzeug entgegen, rechtzeitig anhalten
	if not ghost:
		var gd := _guard_ahead(p)
		if float(gd[0]) >= 0.0:
			var stop_s := rs + maxf(float(gd[0]) - 52.0, 0.0)
			if stop_s < limit:
				limit = stop_s
				why = "belegt"
				p["blocked_by"] = int(gd[1])
	# Tempo: Bremskurve der Linie und Halt vor dem Hindernis
	var ri: int = p["ri"]
	var want := cap[ri]
	if limit < total:
		want = minf(want, sqrt(2.0 * DEC * maxf(0.0, limit - rs - 0.5)))
	var v: float = p["speed"]
	if want > v:
		v = minf(want, v + ACC * sim)
	else:
		v = maxf(want, v - DEC * 2.5 * sim)
	rs = minf(rs + v * sim, maxf(limit, rs))
	rs = minf(rs, total)
	p["speed"] = v
	p["rs"] = rs
	while ri < cum.size() - 2 and cum[ri + 1] <= rs:
		ri += 1
	p["ri"] = ri
	var seg := maxf(cum[ri + 1] - cum[ri], 0.0001) if ri + 1 < cum.size() else 1.0
	var t := clampf((rs - cum[ri]) / seg, 0.0, 1.0)
	var nose := pts[ri].lerp(pts[mini(ri + 1, pts.size() - 1)], t)
	# Hauptfahrwerk wird nachgezogen (Bugradsteuerung)
	var wb := float(p["ng"]) + float(p["mg"])
	var mg_pos: Vector3 = p.get("mg_pos", (p["pos"] as Vector3) - (p["heading"] as Vector3) * float(p["mg"]))
	var dv := nose - mg_pos
	dv.y = 0.0
	if dv.length() > 0.01:
		mg_pos = nose - dv.normalized() * wb
	var hd := nose - mg_pos
	hd.y = 0.0
	if hd.length() > 0.01:
		p["heading"] = hd.normalized()
	p["mg_pos"] = mg_pos
	p["pos"] = mg_pos + (p["heading"] as Vector3) * float(p["mg"])
	# Wo das Flugzeug steht, ist immer belegt (auch abseits der eigenen Route, z. B. nach dem Pushback)
	var here: int = p.get("occ", -1)
	if not p.has("occ_at") or (p["occ_at"] as Vector3).distance_to(p["pos"]) > 3.0:
		here = graph.nearest(p["pos"])
		p["occ_at"] = p["pos"]
	if here >= 0 and int(p.get("occ", -1)) != here:
		var old_occ: int = p.get("occ", -1)
		if old_occ >= 0 and int(reserved.get(old_occ, -1)) == id and not nodes.has(old_occ):
			reserved.erase(old_occ)
		# wo der Rumpf steht, wird immer belegt (andere sehen ihn dann über ihren Nahbereich)
		if int(reserved.get(here, -1)) in [-1, id]:
			_reserve(here, id)
			p["occ"] = here
	# Knoten hinter dem Heck freigeben
	for j in range(k):
		var n: int = nodes[j]
		if node_s[j] < rs - 32.0 and reserved.has(n) and int(reserved[n]) == id:
			reserved.erase(n)
	# Warten, Umweg, Notlösung
	if v < 0.05 and why == "belegt":
		p["wait"] = float(p["wait"]) + sim
		p["delay"] = float(p["delay"]) + sim * CLOCK
		if float(p["wait"]) > 12.0 and not bool(p["rerouted"]):
			p["rerouted"] = true
			_reroute(p)
		elif float(p["wait"]) > 40.0 and _deadlocked(p):
			# Notlösung gegen gegenseitiges Blockieren: nur einer von beiden fährt durch
			var q := _plane_by_id(int(p.get("blocked_by", -1)))
			var go := q.is_empty() or float(q.get("ghost", 0.0)) <= 0.0 and (int(q.get("blocked_by", -1)) != int(p["id"]) or int(p["id"]) > int(q["id"]))
			# Steht der andere vor uns, wir aber nicht vor ihm, fährt er zuerst (nicht durch ihn hindurch)
			if not q.is_empty() and float(q.get("ghost", 0.0)) <= 0.0 and _in_front(p, q) != _in_front(q, p):
				go = not _in_front(p, q)
			if go:
				p["ghost"] = 15.0
				p["wait"] = 0.0
		return "belegt"
	if v > 0.5:
		p["wait"] = 0.0
		p["rerouted"] = false
	if why == "piste" and v < 0.3:
		return "piste"
	if rs >= total - 0.05:
		p["speed"] = 0.0
		return "ziel"
	return "fahrt"


## Flugzeug direkt voraus (Mitte bis 95 m, seitlich bis 12 m), das entgegenkommt oder steht:
## [Abstand der Mitten, id] oder [-1, -1]. Gleichgerichteten Verkehr regeln die Reservierungen.
func _guard_ahead(p: Dictionary) -> Array:
	var pos: Vector3 = p["pos"]
	var h: Vector3 = p["heading"]
	h.y = 0.0
	if h.length_squared() < 0.01:
		return [-1.0, -1]
	h = h.normalized()
	var side := h.cross(Vector3.UP)
	var best := -1.0
	var who := -1
	for q: Dictionary in planes:
		if is_same(q, p) or not (q["state"] in ["rollt_ein", "rollt_aus", "wartet", "pushback"]) or float(q["ghost"]) > 0.0:
			continue
		var d: Vector3 = (q["pos"] as Vector3) - pos
		d.y = 0.0
		var ahead := d.dot(h)
		if ahead < 8.0 or ahead > 95.0 or absf(d.dot(side)) > 12.0:
			continue
		var qh: Vector3 = q["heading"]
		if qh.dot(h) > -0.3 and float(q["speed"]) > 1.0:
			continue
		if best < 0.0 or ahead < best:
			best = ahead
			who = int(q["id"])
	return [best, who]


## Verbleibende Routen aller rollenden Flugzeuge als Knotenmengen (einmal pro Schritt).
func _build_route_sets() -> void:
	_route_sets = {}
	for p: Dictionary in planes:
		if not (p["state"] in ["rollt_ein", "rollt_aus", "wartet"]) or not p.has("route"):
			continue
		var nodes: Array = p["path"]
		var node_s: PackedFloat32Array = p["route"]["node_s"]
		var k: int = p.get("pk", 0)
		var setn := {}
		for j in range(k, mini(nodes.size(), k + 90)):
			var a := graph.pos[nodes[maxi(j - 1, 0)]]
			var b := graph.pos[nodes[mini(j + 1, nodes.size() - 1)]]
			var d := b - a
			d.y = 0.0
			setn[nodes[j]] = [node_s[j], d.normalized() if d.length() > 0.01 else Vector3.ZERO]
		_route_sets[int(p["id"])] = {"set": setn, "rs": float(p["rs"]), "nodes": nodes, "node_s": node_s, "k": k,
			"pos": p["pos"]}


## Erster Knoten der Route ab k, der die Route des anderen in Gegenrichtung berührt: [Index, Abstand] oder [-1, INF].
func _opposing_entry(nodes: Array, node_s: PackedFloat32Array, k: int, rs: float, other: Dictionary) -> Array:
	for kk in range(k, mini(nodes.size(), k + 90)):
		if node_s[kk] - rs > 450.0:
			break
		var n: int = nodes[kk]
		var hit := -1
		if other.has(n):
			hit = n
		else:
			for m: int in graph.near[n]:
				if other.has(m):
					hit = m
					break
		if hit < 0:
			continue
		var a := graph.pos[nodes[maxi(kk - 1, 0)]]
		var b := graph.pos[nodes[mini(kk + 1, nodes.size() - 1)]]
		var dme := b - a
		dme.y = 0.0
		if dme.length() < 0.01:
			continue
		var e: Array = other[hit]
		if dme.normalized().dot(e[1]) < -0.3:
			return [kk, maxf(node_s[kk] - rs, 0.0)]
	return [-1, INF]


## Haltepunkt (Bogenlänge), wenn wir einem entgegenkommenden Flugzeug den Vortritt lassen müssen, sonst INF.
func _yield_point(p: Dictionary, nodes: Array, node_s: PackedFloat32Array, k: int, rs: float) -> float:
	var id: int = p["id"]
	if not _route_sets.has(id):
		return INF
	var mine: Dictionary = _route_sets[id]["set"]
	var best := INF
	for qid: int in _route_sets:
		if qid == id:
			continue
		var q: Dictionary = _route_sets[qid]
		if (q["pos"] as Vector3).distance_to(p["pos"]) > 900.0:
			continue
		var me := _opposing_entry(nodes, node_s, k, rs, q["set"])
		if int(me[0]) < 0:
			continue
		var them := _opposing_entry(q["nodes"], q["node_s"], int(q["k"]), float(q["rs"]), mine)
		var a: float = me[1]
		var b: float = them[1]
		if a > b + 0.5 or (absf(a - b) <= 0.5 and id > qid):
			best = minf(best, node_s[int(me[0])] - CLEAR - 14.0)
			p["blocked_by"] = qid
	return best


## Abschnitt ab Index kk bis einschließlich der nächsten Kreuzung: [Blockierer oder -1, Knoten].
## Im Pistenschutzbereich endet die Prüfung (dort gilt die Pistenfreigabe).
func _block_ahead(nodes: Array, node_s: PackedFloat32Array, kk: int, id: int, ignore: Dictionary = {}) -> Array:
	var out := []
	var j := kk
	var start_s := node_s[kk]
	var seen_line := false
	while j < nodes.size():
		var n: int = nodes[j]
		if graph.zone[n] == 1 and runway_owner != id:
			break
		if graph.in_stand[n] == 1:
			break
		var deg: int = (graph.adj[n] as Array).size()
		if not _free_for(n, id, ignore):
			return [_blocker(n, id, ignore), out]
		out.append(n)
		if deg == 2:
			seen_line = true
		elif seen_line:
			break   # Kreuzung am Ende des Abschnitts gehört dazu
		if node_s[j] - start_s > 600.0:
			break
		j += 1
	return [-1, out]


## Verklemmt: Der Blockierer kommt selbst nicht weiter und wartet (auf uns oder lange).
## Wer hinter einem Pushback oder einem rollenden Flugzeug steht, wartet einfach.
func _deadlocked(p: Dictionary) -> bool:
	var q := _plane_by_id(int(p.get("blocked_by", -1)))
	if q.is_empty():
		return true
	if q["state"] in ["pushback", "abfertigung", "start", "landung", "anflug"]:
		return false
	if float(q["speed"]) > 0.2:
		return false
	return int(q.get("blocked_by", -1)) == int(p["id"]) or float(q["wait"]) > 30.0


## Bogenlänge, an der das Bugrad vor dem Rollhalteort hält (Cockpit hinter der Markierung).
func _hold_s(p: Dictionary, kk: int) -> float:
	var nodes: Array = p["path"]
	var node_s: PackedFloat32Array = p["route"]["node_s"]
	var s1 := node_s[kk]
	if kk == 0:
		return s1 - 8.0
	var s0 := node_s[kk - 1]
	var d0 := graph.runway_distance(graph.pos[nodes[kk - 1]])
	var d1 := graph.runway_distance(graph.pos[nodes[kk]])
	var f := clampf((d0 - graph.hold_limit(nodes[kk])) / maxf(d0 - d1, 0.01), 0.0, 1.0)
	var line := lerpf(s0, s1, f)
	var nose_ahead := float(Catalog.PLANES[p["kind"]]["nose"]) - float(p["ng"])
	return line - nose_ahead - 2.0


func _reroute(p: Dictionary) -> void:
	var nodes: Array = p["path"]
	if nodes.is_empty():
		return
	var goal: int = nodes[nodes.size() - 1]
	var start := graph.nearest(_nose(p))
	var alt := graph.path(start, goal, _blocked_for(int(p["id"])), p["heading"], bool(p.get("wide", false)))
	if alt.is_empty():
		return
	var r: Dictionary = p["route"]
	# nur nehmen, wenn der Umweg nicht viel länger ist und nicht über die Piste führt
	var alt_len := 0.0
	var via_rwy := false
	for i in range(1, alt.size()):
		alt_len += graph.pos[alt[i - 1]].distance_to(graph.pos[alt[i]])
		via_rwy = via_rwy or graph.zone[alt[i]] == 1
	var remaining := float(r["total"]) - float(p["rs"])
	if alt_len > remaining * 1.4 + 120.0 or (via_rwy and runway_owner != int(p["id"])):
		return
	var end_pt: Variant = null
	if bool(r["stand"]):
		var pts: PackedVector3Array = r["pts"]
		end_pt = pts[pts.size() - 1]
	_release_all(int(p["id"]))
	_set_route(p, alt, end_pt, bool(r["stand"]))


# ---------------------------------------------------------------- Pushback

func _pushback(p: Dictionary, sim: float) -> void:
	var id: int = p["id"]
	match String(p["push_phase"]):
		"bereit":
			p["ptimer"] = float(p["ptimer"]) + sim
			var tug_ok: bool = ops == null or ops.tug_ready(p)
			if not tug_ok or float(p["ptimer"]) < 6.0:
				return
			if not p.has("push"):
				if not _plan_pushback(p):
					p["wait"] = float(p["wait"]) + sim
					p["delay"] = float(p["delay"]) + sim * CLOCK
					return
			p["wait"] = 0.0
			p["push_phase"] = "schieben"
			p["ps"] = 0.0
			p["speed"] = 0.0
		"schieben":
			var push: Dictionary = p["push"]
			var pts: PackedVector3Array = push["pts"]
			var cum: PackedFloat32Array = push["s"]
			var total: float = push["total"]
			var ps: float = p["ps"]
			var want := minf(PUSH_V, sqrt(2.0 * 0.25 * maxf(total - ps, 0.0)) + 0.1)
			var v := move_toward(float(p["speed"]), want, 0.3 * sim)
			p["speed"] = v
			ps = minf(ps + v * sim, total)
			p["ps"] = ps
			var i := 0
			while i < cum.size() - 2 and cum[i + 1] <= ps:
				i += 1
			var seg := maxf(cum[i + 1] - cum[i], 0.0001)
			var t := clampf((ps - cum[i]) / seg, 0.0, 1.0)
			p["pos"] = pts[i].lerp(pts[i + 1], t)
			var tng := pts[i + 1] - pts[i]
			tng.y = 0.0
			if tng.length() > 0.001:
				p["heading"] = -tng.normalized()
			if ops != null:
				ops.tug_follow(p, _nose(p), p["heading"], sim)
			if ps >= total - 0.05:
				p["push_phase"] = "abkoppeln"
				p["ptimer"] = 0.0
				p["speed"] = 0.0
		"abkoppeln":
			p["ptimer"] = float(p["ptimer"]) + sim
			if float(p["ptimer"]) > 3.0 and not bool(p.get("tug_off", false)):
				p["tug_off"] = true
				if ops != null:
					ops.tug_leave(p)
			if float(p["ptimer"]) > 9.0:
				_release_all(id)
				p.erase("push")
				p["stand"] = {}   # Position ist frei für den nächsten Flug
				p["state"] = "rollt_aus"
				p["path"] = []
				p.erase("route")
				_set_gear(p)
				_plan_departure(p)
				_reserve(graph.nearest_taxi(p["pos"], 40.0), id)


## Pushback-Kurve: rückwärts aus der Position, das Heck schwenkt entgegen der späteren Rollrichtung.
## Reserviert Zufahrt und den Rollweg dahinter; false, wenn dort gerade jemand ist.
func _plan_pushback(p: Dictionary) -> bool:
	var id: int = p["id"]
	var sid := _stand_id(p)
	if sid < 0 or not graph.lead_of.has(sid):
		return false
	var lid: int = graph.lead_of[sid]
	var goal := _rwy_goal(p)
	var path0 := graph.path(lid, goal, {}, Vector3.ZERO, bool(p.get("wide", false)))
	if path0.size() < 3:
		return false
	var b_node: int = path0[1]
	var dvec := graph.pos[path0[2]] - graph.pos[path0[1]]
	dvec.y = 0.0
	var d := dvec.normalized()
	var t_node := graph.nearest_taxi(graph.pos[b_node] - d * 26.0, 30.0)
	if t_node < 0:
		t_node = b_node
	var need := graph.path(lid, t_node)
	need.append_array(graph.path(t_node, b_node))
	need.append(sid)
	# auch dort, wo nach dem Pushback das Heck steht, muss frei sein
	var tail_node := graph.nearest_taxi(graph.pos[t_node] - d * 20.0, 30.0)
	if tail_node >= 0:
		need.append(tail_node)
	for n: int in need:
		if not _free_for(n, id):
			return false
	# Pushback erst, wenn der erste Rollwegabschnitt in Abflugrichtung frei ist (kein Gegenverkehr)
	var dep := graph.path(t_node, goal, {}, d, bool(p.get("wide", false)))
	var dep_s := PackedFloat32Array()
	var run := 0.0
	for i in range(dep.size()):
		if i > 0:
			run += graph.pos[dep[i]].distance_to(graph.pos[dep[i - 1]])
		dep_s.append(run)
	var blk := _block_ahead(dep, dep_s, 0, id) if not dep.is_empty() else [-1, []]
	if int(blk[0]) >= 0:
		return false
	# kein Pushback, solange uns auf dem ersten Stück jemand entgegenrollt
	var dep_set := {}
	for i in range(mini(dep.size(), 90)):
		var a := graph.pos[dep[maxi(i - 1, 0)]]
		var b := graph.pos[dep[mini(i + 1, dep.size() - 1)]]
		var dd := b - a
		dd.y = 0.0
		dep_set[dep[i]] = [dep_s[i], dd.normalized() if dd.length() > 0.01 else Vector3.ZERO]
	for qid: int in _route_sets:
		if qid == id:
			continue
		var q: Dictionary = _route_sets[qid]
		var them := _opposing_entry(q["nodes"], q["node_s"], int(q["k"]), float(q["rs"]), dep_set)
		if int(them[0]) >= 0 and float(them[1]) < 500.0:
			return false
	for n: int in need:
		_reserve(n, id)
	for n: int in blk[1]:
		_reserve(n, id)
	var p0: Vector3 = p["pos"]
	var fwd: Vector3 = p["heading"]
	var tp := graph.pos[t_node]
	var depth := maxf((p0 - tp).dot(fwd), 10.0)
	var c1 := p0 - fwd * depth * 0.55
	var c2 := tp + d * minf(24.0, depth * 0.6)
	var pts := PackedVector3Array()
	var steps := 60
	for k in range(steps + 1):
		var t := float(k) / float(steps)
		var u := 1.0 - t
		pts.append(p0 * (u * u * u) + c1 * (3.0 * u * u * t) + c2 * (3.0 * u * t * t) + tp * (t * t * t))
	var cum := PackedFloat32Array()
	cum.resize(pts.size())
	cum[0] = 0.0
	for k in range(1, pts.size()):
		cum[k] = cum[k - 1] + pts[k - 1].distance_to(pts[k])
	p["push"] = {"pts": pts, "s": cum, "total": cum[cum.size() - 1]}
	return true


func _park(p: Dictionary) -> void:
	var id: int = p["id"]
	_release_all(id)
	var st: Dictionary = p["stand"]
	var node: Node3D = st["node"]
	_reserve(graph.stand_node.get(node.get_instance_id(), -1), id)
	var fwd := node.global_transform.basis.z.normalized()
	p["pos"] = _park_pos(p)
	p["heading"] = fwd
	p["hs"] = fwd
	p["speed"] = 0.0
	p["pitch"] = 0.0
	p.erase("route")
	p["state"] = "abfertigung"
	var plane: Dictionary = Catalog.PLANES[p["kind"]]
	var slow := 1.0 if depot_ok() else 1.5
	var gate: Dictionary = {}
	if terminal != null:
		gate = terminal.assign_gate(p)
		slow *= float(terminal.slowdown())
		slow *= float(terminal.staff_slowdown())
		if gate.is_empty():
			slow *= 1.25
			gate_short = 60.0
	if ops != null and bool(p.get("bus", false)) and not ops.has_garage("bus"):
		slow *= 1.15
	p["gate"] = gate
	# Gepäckförderband vom Terminal zum Gepäckumschlag: Koffer sind schneller am Flugzeug
	var hall: Dictionary = gate.get("hall", {}) if not gate.is_empty() else {}
	if not hall.is_empty() and not game.baggage_link(hall).is_empty():
		slow *= 0.9
	p["turn"] = float(plane["turn"]) * slow
	p["timer"] = p["turn"]
	_spawn_gse(p)
	if ops != null:
		ops.turn_start(p)
	if terminal != null:
		terminal.flight_parked(p, gate)
	if ops != null and bool(p.get("bus", false)) and not gate.is_empty():
		var door: Array = terminal.gate_door(gate)
		ops.remote_arrive(p, terminal.bus_stop(gate), door[1], true)
	game.earn(int(plane["fee"]) + int(plane["pax"]) * Catalog.TICKET_FEE, "Landung %s aus %s" % [p["code"], p["city"]])
	# Kerosin und Bordessen verkauft der Flughafen selbst, wenn er Tanklager und Catering hat
	if ops != null:
		if ops.has_garage("tank"):
			game.earn_quiet(int(plane["pax"]) * 4)
		if ops.has_garage("catering"):
			game.earn_quiet(int(plane["pax"]) * 2)


# ---------------------------------------------------------------- Bodenfahrzeuge

## Tankwagen, Gepäck und Catering fahren vom Depot (oder vom Vorfeldrand) an ihre Plätze am Flugzeug.
func _spawn_gse(p: Dictionary) -> void:
	var st: Dictionary = p["stand"]
	var node: Node3D = st["node"]
	var b := node.global_transform.basis
	var fwd := b.z.normalized()
	var c: Vector3 = p["pos"]
	# Einweiser vor der Nase (geht nach dem Andocken); die Fahrzeuge steuert ground_ops.gd
	var list := []
	var crew := [[c + fwd * (float(Catalog.PLANES[p["kind"]]["nose"]) + 3.0), -fwd, 0.06]]
	for i in range(crew.size()):
		var w := Factory.make_staff(Color(0.95, 0.85, 0.1), Color(0.15, 0.18, 0.28), i, true)
		add_child(w)
		w.position = crew[i][0]
		w.basis = Basis.looking_at(crew[i][1], Vector3.UP)
		list.append({"node": w, "static": true, "until": crew[i][2]})
	p["gse"] = list


func _update_gse(p: Dictionary, _sim: float) -> void:
	var total: float = p["turn"]
	var f := 1.0 - float(p["timer"]) / maxf(total, 0.01)
	for g: Dictionary in p["gse"]:
		if bool(g.get("static", false)):
			var nd: Variant = g["node"]
			if is_instance_valid(nd):
				(nd as Node3D).visible = f < float(g.get("until", 2.0))
			continue
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
			v.basis = v.basis.orthonormalized().slerp(Basis.looking_at(look.normalized(), Vector3.UP), 0.2)


func _clear_gse(p: Dictionary) -> void:
	for g: Dictionary in p["gse"]:
		var v: Variant = g["node"]
		if is_instance_valid(v):
			(v as Node).queue_free()
	p["gse"] = []


## Bewegliche Teile: Fans drehen, Fahrwerk ein- und ausfahren, Beacon und Blitzlichter blinken.
func _animate(p: Dictionary, sim: float) -> void:
	var node: Node3D = p["node"]
	var state: String = p["state"]
	var target := 0.0
	match state:
		"anflug", "start":
			target = 34.0
		"landung":
			target = 30.0 if float(p["speed"]) > 30.0 else 16.0   # Schubumkehr, dann Leerlauf
		"rollt_ein", "rollt_aus", "wartet":
			target = 16.0
		"abfertigung":
			target = 0.0 if float(p["timer"]) < float(p["turn"]) - 2.0 else 10.0
		"pushback":
			target = 12.0 if p.get("push_phase", "") != "bereit" else 0.0   # Triebwerke werden beim Zurückschieben gestartet
	var rate := lerpf(float(p.get("fan_rate", 0.0)), target, clampf(sim * 0.6, 0.0, 1.0))
	p["fan_rate"] = rate
	p["spin"] = fmod(float(p.get("spin", 0.0)) + rate * sim, TAU)
	p["t"] = float(p.get("t", 0.0)) + sim
	for fan: String in ["FanL", "FanR"]:
		var f := node.get_node_or_null(fan) as Node3D
		if f != null:
			f.rotation.z = float(p["spin"])
	var gear := node.get_node_or_null("Fahrwerk") as Node3D
	if gear != null:
		# Fahrwerk fährt in etwa 6 s aus oder ein (in den Rumpf hinein)
		var want := 1.0
		if state == "anflug":
			want = 1.0 if (p["pos"] as Vector3).distance_to(p["td"]) < 2600.0 and not p.has("approach") else 0.0
		elif state == "start" and float(p["alt"]) > 12.0:
			want = 0.0
		var g := move_toward(float(p.get("gear", 1.0)), want, sim / 6.0)
		p["gear"] = g
		var s: Dictionary = Models.SPECS.get(p["kind"], Models.SPECS["a320"])
		var belly := float(s["cy"]) - float(s["r"]) + 0.3
		gear.visible = g > 0.03
		gear.scale = Vector3(1.0, maxf(g, 0.03), 1.0)
		gear.position = Vector3(0, belly * (1.0 - g), 0)
	# Landeklappen: im Endanflug und bei der Landung ganz, zum Start halb, sonst eingefahren
	var flap_want := 0.0
	match state:
		"anflug":
			flap_want = 1.0 if (p["pos"] as Vector3).distance_to(p["td"]) < 2600.0 and not p.has("approach") else (0.5 if p.has("approach") else 0.0)
		"landung":
			flap_want = 1.0
		"rollt_aus", "wartet":
			flap_want = 0.45
		"start":
			flap_want = 0.45 if float(p["alt"]) < 150.0 else 0.0
	var fl := move_toward(float(p.get("flaps", 0.0)), flap_want, sim / 9.0)
	var spo_want := 1.0 if state == "landung" and float(p["speed"]) > 18.0 else 0.0
	var sp := move_toward(float(p.get("spoilers", 0.0)), spo_want, sim / 1.2)
	if not is_equal_approx(fl, float(p.get("flaps", 0.0))) or not is_equal_approx(sp, float(p.get("spoilers", 0.0))) or not p.has("flaps"):
		p["flaps"] = fl
		p["spoilers"] = sp
		var e := smoothstep(0.0, 1.0, fl)
		for nm: String in ["KlappeLi", "KlappeLa", "KlappeRi", "KlappeRa"]:
			var f := node.get_node_or_null(nm) as Node3D
			if f != null:
				var ax: Vector3 = f.get_meta("axis")
				f.basis = Basis(ax, e * 0.62)
				f.position = (f.get_meta("hinge") as Vector3) + Vector3(0, -0.12 * e, float(f.get_meta("chord")) * 0.16 * e)
		for nm: String in ["SpoilerL", "SpoilerR"]:
			var spn := node.get_node_or_null(nm) as Node3D
			if spn != null:
				spn.basis = Basis(spn.get_meta("axis") as Vector3, -smoothstep(0.0, 1.0, sp) * 0.85)
	var land := node.get_node_or_null("Landelicht") as Node3D
	if land != null:
		land.visible = state in ["anflug", "landung", "start"] or (game.night > 0.4 and state in ["rollt_ein", "rollt_aus", "wartet"])
	var beacon := node.get_node_or_null("Beacon") as Node3D
	if beacon != null:
		var on := rate > 2.0 or state == "pushback"
		beacon.visible = on and fmod(float(p["t"]), 1.1) < 0.18
	var strobe := node.get_node_or_null("Strobe") as Node3D
	if strobe != null:
		strobe.visible = state in ["anflug", "landung", "start"] and fmod(float(p["t"]), 1.4) < 0.08


func _place(p: Dictionary) -> void:
	var node: Node3D = p["node"]
	var pos: Vector3 = p["pos"]
	var pitch := float(p.get("pitch", 0.0))
	var lift := 0.0
	if float(p["alt"]) < 2.0 and pitch > 0.0:
		lift = maxf(0.0, 13.0 * sin(pitch) - 1.3)   # Heck nicht durch den Boden drehen
	node.position = Vector3(pos.x, float(p["alt"]) + lift, pos.z)
	var h: Vector3 = p["heading"]
	h.y = 0.0
	if h.length_squared() > 0.0001:
		var hs: Vector3 = p.get("hs", h)
		hs = hs.lerp(h.normalized(), 0.5)
		if hs.length_squared() < 0.0001:
			hs = h
		p["hs"] = hs.normalized()
		node.basis = Basis.looking_at(p["hs"], Vector3.UP) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, float(p.get("roll", 0.0)))


func _remove(p: Dictionary, msg: String) -> void:
	var id: int = p["id"]
	if runway_owner == id:
		runway_owner = -1
	_release_all(id)
	_clear_gse(p)
	if terminal != null:
		terminal.flight_left(p)
	if ops != null:
		ops.release(p)
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
	if ops != null:
		ops.clear()
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
		factors.append(["Keine Gerätehalle mit Strom: Abfertigung dauert länger", -6])
		hint = "Ohne Gerätehalle dauert jede Abfertigung länger"
	if ops != null:
		if not ops.has_garage("tank"):
			target -= 3.0
			factors.append(["Kein Tanklager: Flugzeuge werden nicht betankt", -3])
			if hint == "":
				hint = "Tanklager bauen: Tankwagen betanken die Flugzeuge, der Kerosinverkauf bringt Geld"
		if not ops.has_garage("catering"):
			target -= 2.0
			factors.append(["Kein Cateringbetrieb: nichts zu essen an Bord", -2])
		if not ops.has_fire_station():
			target -= 5.0
			factors.append(["Keine Feuerwache mit Strom", -5])
		if not ops.unconnected.is_empty():
			target -= 2.0
			factors.append(["%d Garage(n) ohne Betriebsstraße zum Vorfeld" % ops.unconnected.size(), -2])
			if hint == "":
				hint = "%s mit einer Betriebsstraße ans Vorfeld anschließen" % Catalog.label(String((ops.unconnected[0] as Dictionary)["id"]))
		if not runway_lit():
			target -= 4.0
			factors.append(["Piste ohne Befeuerung: nachts keine Flüge", -4])
			if hint == "":
				hint = "Befeuerungsstation nahe der Piste bauen und ans Stromnetz anschließen"
		elif not game.legacy_lights and (game.items_of("anflugbefeuerung").is_empty() or game.items_of("papi").is_empty()):
			target -= 1.0
			factors.append(["Ohne Anflugbefeuerung und PAPI landen Flugzeuge bei Nacht unpünktlicher", -1])
		var loose := 0
		for st: Dictionary in game.stands():
			if not ops.stand_connected(st):
				loose += 1
		if loose > 0:
			target -= 1.5
			factors.append(["%d Stand/Stände ohne Zufahrt von der Betriebsstraße: Fahrzeuge kreuzen das Vorfeld" % loose, -1.5])
			if hint == "":
				hint = "Eine Betriebsstraße am Kopf der Stände entlangführen"
	var parking := false
	var any_parking := false
	for ph: Dictionary in game.items_of("parkhaus"):
		any_parking = true
		parking = parking or (game.supplied(ph, "strom") and (traffic == null or traffic.has_access(ph)))
	if not parking:
		target -= 12.0
		factors.append(["Parkhaus ohne Strom oder ohne Zufahrt" if any_parking else "Kein Parkhaus", -12])
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
	if traffic != null and traffic.has_bus_line():
		target += 3.0
		factors.append(["Linienbus hält am Flughafen", 3])
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
	if p["state"] in ["rollt_ein", "rollt_aus", "start", "landung"]:
		lines.append("%d km/h" % roundi(float(p["speed"]) * 3.6))
	if p["state"] == "abfertigung":
		lines.append("Tankwagen, Gepäck und Catering sind am Flugzeug")
		var gate: Dictionary = p.get("gate", {})
		if terminal != null and not gate.is_empty():
			if bool(p.get("bus", false)):
				lines.append("Außenposition: Busse und Treppen, " + String(terminal.gate_name(gate)))
			else:
				lines.append("Fluggastbrücke am " + String(terminal.gate_name(gate)))
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
			if float(p["timer"]) <= 0.0:
				return ["Boarding per Bus", Color(0.94, 0.76, 0.31)]
			return ["Abfertigung %d Min" % ceili(float(p["timer"])), Color(0.66, 0.85, 0.56)]
		"pushback":
			if p.get("push_phase", "") == "bereit":
				return ["Wartet auf Pushback" if float(p["wait"]) > 1.0 else "Türen zu, Schlepper dockt an", Color(0.94, 0.76, 0.31)]
			return ["Pushback", Color(0.94, 0.76, 0.31)]
		"rollt_aus":
			if float(p["wait"]) > 1.0:
				return ["Wartet auf Rollweg", Color(1.0, 0.55, 0.45)]
			return ["Rollt zur Piste", Color(0.94, 0.76, 0.31)]
		"wartet":
			return ["Wartet am Rollhalt", Color(1.0, 0.55, 0.45)]
		"start":
			return ["Start", Color(0.56, 0.75, 0.94)]
	return ["", Color.WHITE]


func rows() -> Array:
	var out := []
	for p: Dictionary in planes:
		var st := _status(p)
		out.append([String(p["code"]), String(Catalog.PLANES[p["kind"]]["name"]), _route(p), st[0], st[1]])
	return out
