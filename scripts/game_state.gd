extends Node
## Spielstand: Geld, Spielzeit, gebaute Wege und Objekte, Versorgungsnetze,
## Rückgängig, Speichern und Laden.

signal money_changed(value: int)
signal toast(text: String)
signal network_changed      # Wege geändert (Verkehr, Rollnetz)
signal items_changed        # Gebäude geändert
signal supply_changed       # Strom/Wasser neu berechnet
signal view_changed(on: bool)  # Leitungsansicht an/aus
signal interior_changed(on: bool)  # Innenansicht (Dächer aus) an/aus
signal day_ended                   # Mitternacht (Tagesbilanz)
signal floor_changed(f: int)       # angezeigte Ebene im Terminal (-1 Keller, 0 Erdgeschoss, 1, 2)

const Catalog = preload("res://scripts/catalog.gd")
const Spline = preload("res://scripts/spline.gd")
const MAP_HALF := 3000.0   # Spielfeld 6 × 6 km, Mitte im Ursprung


static func on_map(p: Vector3, margin: float = 0.0) -> bool:
	return absf(p.x) <= MAP_HALF - margin and absf(p.z) <= MAP_HALF - margin
const Factory = preload("res://scripts/factory.gd")
const SAVE_PATH := "user://spielstand.json"
const START_MONEY := 30000000
const SPEEDS := [0.0, 1.0, 3.0, 8.0]
const DAYS := ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

var money: int = START_MONEY
var minutes := 6.0 * 60.0    # Spielzeit seit Montag 00:00
var speed := 1               # Index in SPEEDS
var lines: Array = []        # je Weg: {type, kind, points, samples, bounds, node, cost}
var items: Array = []        # je Objekt: {type, id, pos, rot, rect, node, cost, supply}
var history: Array = []
var utility_view := false
var interior_view := false
var view_floor := 0          # Ebene, die in der Innenansicht gezeigt und bebaut wird

## Einstellbare Bauformen je Gebäude: [Schlüssel, Anzeigename, Werte]
const OPTIONS := {
	"halle": [["etagen", "Ebenen", [1, 2, 3]], ["keller", "Keller", [false, true]], ["fassade", "Fassade", ["glas", "beton", "holz"]],
		["form", "Ecken", ["eckig", "abgerundet", "rund"]], ["dach", "Dach", ["flach", "gewoelbt", "shed"]], ["vordach", "Vordach (+Z)", [false, true]]],
	"parkhaus": [["etagen", "Etagen", [2, 3, 4, 5, 6]], ["farbe", "Fassade", ["grau", "rot", "blau", "holz"]]],
	"gate": [["bereich", "Bereich", ["schengen", "non_schengen"]]],
	"busgate": [["bereich", "Bereich", ["schengen", "non_schengen"]]],
	"tower": [["stil", "Bauform", ["klassisch", "modern"]]],
	"hangar": [["farbe", "Farbe", ["grau", "blau", "weiss"]]],
	"cafe": [["stil", "Laden", ["cafe", "baeckerei", "bar", "restaurant"]]],
	"shop": [["stil", "Laden", ["kiosk", "dutyfree", "buecher", "elektronik", "apotheke", "mode"]]],
	"gepaeckband": [["stil", "Bauart", ["oval", "karussell"]]],
	"eingang": [["tuer", "Tür", ["schiebe", "dreh"]]],
	"tuer": [["art", "Art", ["automatik", "fluegel", "personal"]]],
	"baum": [["stil", "Baumart", ["laub", "nadel", "birke", "pappel", "obst"]]],
}
const OPTION_TEXT := {"glas": "Glas", "beton": "Beton", "holz": "Holz", "eckig": "eckig", "abgerundet": "abgerundet", "rund": "rund",
	"flach": "Flachdach", "gewoelbt": "Tonnendach", "shed": "Sheddach", "schengen": "Schengen", "non_schengen": "Non-Schengen",
	"grau": "Grau", "rot": "Rot", "blau": "Blau", "weiss": "Weiß", "klassisch": "klassisch", "modern": "modern",
	"cafe": "Café", "baeckerei": "Bäckerei", "bar": "Bar", "restaurant": "Restaurant", "kiosk": "Kiosk", "dutyfree": "Duty Free",
	"buecher": "Bücher", "elektronik": "Elektronik", "apotheke": "Apotheke", "mode": "Mode", "oval": "Oval", "karussell": "Karussell", "schiebe": "Schiebetür", "dreh": "Drehtür",
	"automatik": "Automatik (Glas)", "fluegel": "Flügeltür", "personal": "Personaltür",
	"laub": "Laubbaum", "nadel": "Nadelbaum", "birke": "Birke", "pappel": "Pappel", "obst": "Obstbaum"}
var junction_controls: Dictionary = {}   # Kreuzung (gerundete Lage) -> rechts, vorfahrt, ampel
var satisfaction := 75.0
var satisfaction_factors: Array = []
var traffic_demand := 0      # Landungen und Starts in der letzten Spielstunde
var day_income := 0
var last_day := 0
var line_root: Node3D
var item_root: Node3D


func setup(root: Node3D) -> void:
	line_root = Node3D.new()
	line_root.name = "Wege"
	root.add_child(line_root)
	item_root = Node3D.new()
	item_root.name = "Objekte"
	root.add_child(item_root)


static func fmt_money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if v < 0 else "") + out + " €"


static func fmt_short(v: int) -> String:
	if absi(v) >= 1000000:
		var num := str(snappedf(float(v) / 1000000.0, 0.1)).replace(".", ",").trim_suffix(",0")
		return num + " Mio. €"
	return fmt_money(v)


func _spend(amount: int) -> void:
	money -= amount
	money_changed.emit(money)


## Einnahme ohne Meldung (z. B. viele kleine Parkgebühren)
func earn_quiet(amount: int) -> void:
	_spend(-amount)
	day_income += amount


func earn(amount: int, why: String) -> void:
	_spend(-amount)
	day_income += amount
	toast.emit("+" + fmt_money(amount) + "  " + why)


## Spielzeit weiterlaufen lassen; um Mitternacht werden die laufenden Kosten abgebucht.
var night := 0.0       # 0 Tag, 1 Nacht (main.gd setzt es nach der Spieluhr)
var wind_dir := 250.0   # Wind kommt aus dieser Richtung (Grad, 0 = Norden = -z)
var wind_kt := 9.0
var _wind_goal := 250.0


## Einheitsvektor in die Richtung, aus der der Wind weht.
func wind_from() -> Vector3:
	var a := deg_to_rad(wind_dir)
	return Vector3(sin(a), 0.0, -cos(a))


func advance(game_minutes: float) -> void:
	minutes += game_minutes
	Engine.set_meta("spielminuten", minutes)
	# Wind dreht langsam; ab und zu ein neues Wetter
	if randf() < game_minutes / 240.0:
		_wind_goal = fposmod(_wind_goal + randf_range(-140.0, 140.0), 360.0)
	var diff := fposmod(_wind_goal - wind_dir + 180.0, 360.0) - 180.0
	wind_dir = fposmod(wind_dir + clampf(diff, -game_minutes * 0.8, game_minutes * 0.8), 360.0)
	wind_kt = clampf(wind_kt + randf_range(-0.3, 0.3) * game_minutes, 3.0, 22.0)
	var day := int(minutes / 1440.0)
	if day != last_day:
		var day_name: String = DAYS[last_day % 7]
		last_day = day
		var cost := upkeep_per_day()
		_spend(cost)
		var result := day_income - cost
		toast.emit("Tagesbilanz %s: Einnahmen %s, Unterhalt %s, Ergebnis %s" % [day_name, fmt_money(day_income), fmt_money(cost), fmt_money(result)])
		day_income = 0
		day_ended.emit()


func upkeep_per_day() -> int:
	var total := 0.0
	for it: Dictionary in items:
		total += float(item_value(it)) * Catalog.UPKEEP_ITEMS
	for l: Dictionary in lines:
		total += float(line_cost(String(l["kind"]), l["samples"])) * Catalog.UPKEEP_LINES
	return roundi(total / 10.0) * 10


## Neupreis eines Objekts (Hallen nach Fläche).
func item_value(it: Dictionary) -> int:
	if it["id"] == "halle":
		return hall_cost(it["rect"])
	return int(Catalog.ITEMS[it["id"]]["cost"])


## Bäume, Kübel und Bänke in der Nähe eines Terminals (für das Ambiente).
func decor_near_terminals(radius: float) -> int:
	var count := 0
	var terms := items_of("halle")
	for it: Dictionary in items:
		if not (it["id"] in ["baum", "kuebel", "bank", "busch", "hecke", "blumenbeet", "teich", "picknick", "felsen"]):
			continue
		var p: Vector3 = it["pos"]
		for t: Dictionary in terms:
			if (t["rect"] as Rect2).grow(radius).has_point(Vector2(p.x, p.z)):
				count += 1
				break
	return count


# ---------------------------------------------------------------- Zeit

func sim_factor() -> float:
	return float(SPEEDS[speed])


func set_speed(i: int) -> void:
	speed = clampi(i, 0, SPEEDS.size() - 1)


func clock_text() -> String:
	var m := int(minutes)
	var day: String = DAYS[(m / 1440) % 7]
	return "%s %02d:%02d" % [day, (m / 60) % 24, m % 60]


# ---------------------------------------------------------------- Wege

func line_cost(kind: String, samples: PackedVector3Array) -> int:
	var cpm: int = Catalog.LINES[kind]["cost_m"]
	return roundi(Spline.length(samples) * float(cpm) / 100.0) * 100


## Baut einen Weg durch die Klickpunkte. Prüft Kollisionen, räumt Bäume und Deko weg und legt
## bei Straßen Kreuzungen an (beide Straßen werden am Kreuzungspunkt geteilt).
## plain: ohne Prüfung und ohne Kreuzungen (Laden von Spielständen).
func build_line(kind: String, points: Array, free: bool = false, plain: bool = false) -> Dictionary:
	var def: Dictionary = Catalog.LINES[kind]
	var samples := line_samples(kind, points)
	if samples.size() < 2:
		return {}
	var cost := 0 if free else line_cost(kind, samples)
	if cost > money:
		toast.emit("Nicht genug Geld: " + fmt_money(cost) + " nötig")
		return {}
	var check := {"why": "", "decor": [], "junctions": []}
	if not plain:
		check = check_line(kind, samples)
		if String(check["why"]) != "" and not free:
			toast.emit(String(check["why"]))
			return {}
	for d: Dictionary in check["decor"]:
		_remove_one(d, 0.0)
	if not (check["decor"] as Array).is_empty():
		items_changed.emit()
	var rec := _make_line(kind, points, samples, cost)
	if Catalog.is_wall(kind):
		rec["floor"] = view_floor
		(rec["node"] as Node3D).position.y = float(view_floor) * Catalog.FLOOR_H
		if not wall_cuts(rec).is_empty() and not (rec.get("hall", {}) as Dictionary).is_empty():
			refresh_walls(rec["hall"], view_floor)
		_apply_visibility(rec)
	_spend(cost)
	var group := [rec]
	if Catalog.is_road(kind) and not (check["junctions"] as Array).is_empty():
		group = _make_junctions(rec, check["junctions"])
	history.append(group if group.size() > 1 else rec)
	if Catalog.utility_of(kind) != "":
		evaluate_supply()
	else:
		network_changed.emit()
	return group[0]


## Stützpunkte eines Weges aus den Klickpunkten (Tunnel bekommen ihren Höhenverlauf).
static func line_samples(kind: String, points: Array) -> PackedVector3Array:
	var s := Spline.path(points, bool(Catalog.LINES[kind]["straight"]))
	if kind == "tunnel":
		s = Catalog.tunnel_profile(s)
	elif kind == "foerderband":
		for i in range(s.size()):
			s[i] = Vector3(s[i].x, -4.2, s[i].z)
	return s


## Spuren-Werkzeug: Straßentyp wechseln (2-spurig, 4-spurig, Einbahn, Einbahn umgekehrt).
func cycle_road(rec: Dictionary) -> String:
	var kind: String = rec["kind"]
	var flip := bool(rec.get("flip", false))
	var order := [["strasse", false], ["strasse4", false], ["einbahn", false], ["einbahn", true]]
	var idx := 0
	for i in range(order.size()):
		if order[i][0] == kind and bool(order[i][1]) == flip:
			idx = i
	var nxt: Array = order[(idx + 1) % order.size()]
	var new_kind: String = nxt[0]
	var samples: PackedVector3Array = rec["samples"]
	var old_cost := line_cost(kind, samples)
	var new_cost := line_cost(new_kind, samples)
	var extra := maxi(0, new_cost - old_cost)
	if extra > money:
		return "Nicht genug Geld"
	# breitere Straße darf nicht in Gebäude ragen
	var w: float = Catalog.LINES[new_kind]["width"]
	for it: Dictionary in items:
		if Catalog.is_inside(String(it["id"])) or String(it["id"]) in DECOR:
			continue
		var r: Rect2 = (it["rect"] as Rect2).grow(w * 0.5 - 0.25)
		for i in range(0, samples.size(), 2):
			if r.has_point(Vector2(samples[i].x, samples[i].z)):
				return "Zu breit: stößt an " + Catalog.label(String(it["id"]))
	var node: Variant = rec["node"]
	if is_instance_valid(node):
		(node as Node).queue_free()
	var mesh := Factory.make_line(new_kind, samples, float(rec.get("y", 0.06)))
	line_root.add_child(mesh)
	rec["node"] = mesh
	rec["kind"] = new_kind
	rec["flip"] = bool(nxt[1])
	rec["bounds"] = Spline.bounds(samples, w * 0.5)
	rec["cost"] = int(rec["cost"]) + extra
	_spend(extra)
	_grid_dirty = true
	network_changed.emit()
	return ""


## Legt den Datensatz und das Modell eines Weges an (ohne Geld, ohne Verlauf).
func _make_line(kind: String, points: Array, samples: PackedVector3Array, cost: int, raw: bool = false) -> Dictionary:
	var def: Dictionary = Catalog.LINES[kind]
	var base_y: float = def["y"]
	var node := Factory.make_line(kind, samples, base_y + 0.0004 * float(lines.size() % 20))
	line_root.add_child(node)
	var w: float = def["width"]
	var rec := {"type": "line", "kind": kind, "points": points.duplicate(), "samples": samples,
		"bounds": Spline.bounds(samples, w * 0.5), "node": node, "cost": cost, "raw": raw,
		"y": base_y + 0.0004 * float(lines.size() % 20)}
	if Catalog.is_wall(kind):
		rec["hall"] = hall_at(Spline.sample_at(samples, Spline.length(samples) * 0.5))
	lines.append(rec)
	_grid_dirty = true
	_apply_visibility(rec)
	return rec


# ---------------------------------------------------------------- Kollisionen und Kreuzungen

## Welche Wege einander kreuzen dürfen
const CROSS_OK := {
	"strasse": ["strasse", "strasse4", "einbahn", "gehweg", "tunnel"],
	"strasse4": ["strasse", "strasse4", "einbahn", "gehweg", "tunnel"],
	"einbahn": ["strasse", "strasse4", "einbahn", "gehweg", "tunnel"],
	"tunnel": ["strasse", "strasse4", "einbahn", "tunnel"],
	"gehweg": ["strasse", "strasse4", "einbahn", "gehweg"],
	"rollweg": ["rollweg", "rollweg_breit", "vorfeld", "piste", "betriebsstrasse"],
	"rollweg_breit": ["rollweg", "rollweg_breit", "vorfeld", "piste", "betriebsstrasse"],
	"vorfeld": ["rollweg", "rollweg_breit", "vorfeld", "piste", "betriebsstrasse"],
	"betriebsstrasse": ["rollweg", "rollweg_breit", "vorfeld", "betriebsstrasse"],
	"piste": ["rollweg", "rollweg_breit", "vorfeld", "piste"],
}
## Kleine Deko, die ein neuer Weg einfach wegräumt
const DECOR := ["baum", "kuebel", "laterne", "bank", "busch", "felsen", "picknick", "blumenbeet"]
const GRID_CELL := 16.0

var _grid: Dictionary = {}
var _grid_dirty := true


func _ensure_grid() -> void:
	if not _grid_dirty:
		return
	_grid_dirty = false
	_grid = {}
	for li in range(lines.size()):
		var l: Dictionary = lines[li]
		var k: String = l["kind"]
		if Catalog.utility_of(k) != "" or Catalog.is_wall(k):
			continue
		var s: PackedVector3Array = l["samples"]
		for j in range(s.size()):
			var key := Vector2i(floori(s[j].x / GRID_CELL), floori(s[j].z / GRID_CELL))
			if not _grid.has(key):
				_grid[key] = []
			(_grid[key] as Array).append(Vector2i(li, j))


## Prüft einen geplanten Weg.
## Ergebnis: why (leer = erlaubt), decor (wird weggeräumt), junctions ([Straße, Kreuzungspunkt, Index im neuen Weg]).
func check_line(kind: String, samples: PackedVector3Array) -> Dictionary:
	var out := {"why": "", "decor": [], "junctions": []}
	for v: Vector3 in samples:
		if not on_map(v):
			out["why"] = "Außerhalb der Karte"
			return out
	if Catalog.utility_of(kind) != "" or Catalog.is_wall(kind) or samples.size() < 2:
		return out
	var w: float = Catalog.LINES[kind]["width"]
	var bounds := Spline.bounds(samples, w * 0.5)
	var step := 2 if w > 20.0 else 1
	# Gebäude und Deko
	for it: Dictionary in items:
		var id: String = it["id"]
		if Catalog.is_inside(id):
			continue
		if String(Catalog.ITEMS[id].get("on", "")) == kind:
			continue
		var r: Rect2 = (it["rect"] as Rect2).grow(w * 0.5 - 0.25)
		if not r.intersects(bounds):
			continue
		for i in range(0, samples.size(), step):
			if Catalog.covered(kind, samples[i]):
				continue
			if r.has_point(Vector2(samples[i].x, samples[i].z)):
				if id in DECOR:
					(out["decor"] as Array).append(it)
				else:
					out["why"] = "Geht durch: " + Catalog.label(id)
					return out
				break
	# Andere Wege
	_ensure_grid()
	var hits := {}   # Weg -> {Index im neuen Weg: [Abstand, Index im alten Weg]}
	var reach := ceili((w * 0.5 + 30.0) / GRID_CELL)
	for i in range(0, samples.size(), step):
		var v := samples[i]
		if Catalog.covered(kind, v):
			continue
		var c := Vector2i(floori(v.x / GRID_CELL), floori(v.z / GRID_CELL))
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				for e: Vector2i in _grid.get(c + Vector2i(dx, dz), []):
					var l: Dictionary = lines[e.x]
					var j: int = e.y
					var w2: float = Catalog.LINES[l["kind"]]["width"]
					var p: Vector3 = (l["samples"] as PackedVector3Array)[j]
					if Catalog.covered(String(l["kind"]), p):
						continue
					var d := Vector2(p.x - v.x, p.z - v.z).length()
					if d >= (w + w2) * 0.5 - 0.6:
						continue
					if not hits.has(e.x):
						hits[e.x] = {}
					var h: Dictionary = hits[e.x]
					if not h.has(i) or d < float(h[i][0]):
						h[i] = [d, j]
	for li: int in hits:
		var l: Dictionary = lines[li]
		var hl: Dictionary = hits[li]
		var k2: String = l["kind"]
		if not (k2 in CROSS_OK.get(kind, [])):
			out["why"] = "Überschneidet " + Catalog.label(k2)
			return out
		if not (Catalog.is_road(kind) and Catalog.is_road(k2)):
			continue
		# zusammenhängende Abschnitte: kurz = Kreuzung, lang = liegt auf der Straße
		var idx: Array = hl.keys()
		idx.sort()
		var runs := []
		var cur := [idx[0]]
		for n in range(1, idx.size()):
			if int(idx[n]) - int(cur[cur.size() - 1]) <= step + 1:
				cur.append(idx[n])
			else:
				runs.append(cur)
				cur = [idx[n]]
		runs.append(cur)
		var w2: float = Catalog.LINES[k2]["width"]
		var ls0: PackedVector3Array = l["samples"]
		for run: Array in runs:
			if float(int(run[run.size() - 1]) - int(run[0])) > (w + w2) * 1.6 + 3.0:
				out["why"] = "Liegt auf einer Straße oder kreuzt zu flach"
				return out
			# Tunnelrampen: nur an ihren Enden anschließen
			if kind == "tunnel" or k2 == "tunnel":
				var near_end := true
				if kind == "tunnel":
					near_end = mini(int(run[0]), samples.size() - 1 - int(run[run.size() - 1])) < int(w + w2) + 2
				if k2 == "tunnel":
					var j0: int = hl[run[0]][1]
					near_end = near_end and mini(j0, ls0.size() - 1 - j0) < int(w + w2) + 2
				if not near_end:
					out["why"] = "Kreuzt eine Tunnelrampe: Tunnel schließen nur an ihren Enden an"
					return out
			var best_i: int = run[0]
			for i: int in run:
				if float(hl[i][0]) < float(hl[best_i][0]):
					best_i = i
			var ls: PackedVector3Array = l["samples"]
			(out["junctions"] as Array).append([l, ls[int(hl[best_i][1])], best_i])
	return out


## Teilt Straßen an den Kreuzungspunkten. Gibt die Stücke des neuen Weges zurück.
func _make_junctions(rec: Dictionary, junctions: Array) -> Array:
	var cuts := []
	for jn: Array in junctions:
		var old: Dictionary = jn[0]
		var still := false
		for l: Dictionary in lines:
			still = still or is_same(l, old)
		if still:
			_split_at(old, jn[1])
		cuts.append(int(jn[2]))
	var pieces := [rec]
	cuts.sort()
	cuts.reverse()
	for c: int in cuts:
		var last: Dictionary = pieces[0]
		var parts := _split_at(last, (rec["samples"] as PackedVector3Array)[c])
		if parts.size() == 2:
			pieces[0] = parts[1]
			pieces.push_front(parts[0])
	return pieces


## Teilt einen Weg an dem Stützpunkt, der p am nächsten liegt. Liegt p nah am Ende, bleibt er ganz.
func _split_at(l: Dictionary, p: Vector3) -> Array:
	var s: PackedVector3Array = l["samples"]
	var best := 0
	var bd := INF
	for i in range(s.size()):
		var d := s[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	if best < 4 or best > s.size() - 5:
		return [l]
	var a := s.slice(0, best + 1)
	var b := s.slice(best)
	var cost: int = l["cost"]
	var ca := roundi(float(cost) * float(best) / float(s.size() - 1))
	var in_history := history.has(l)
	_remove_one(l, 0.0)
	var ra := _make_line(String(l["kind"]), Array(a), a, ca, true)
	var rb := _make_line(String(l["kind"]), Array(b), b, cost - ca, true)
	if in_history:
		history.append([ra, rb])
	return [ra, rb]


func endpoints(utility_only: bool = false) -> Array:
	var out := []
	for l: Dictionary in lines:
		if utility_only != (Catalog.utility_of(String(l["kind"])) != ""):
			continue
		var s: PackedVector3Array = l["samples"]
		out.append(s[0])
		out.append(s[s.size() - 1])
	return out


func set_utility_view(on: bool) -> void:
	utility_view = on
	for l: Dictionary in lines:
		_apply_visibility(l)
	view_changed.emit(on)


func _apply_visibility(l: Dictionary) -> void:
	var kind := String(l["kind"])
	var node := l["node"] as Node3D
	if not is_instance_valid(node):
		return
	if Catalog.is_wall(kind):
		node.visible = (floor_of(l) == view_floor) if interior_view else floor_of(l) >= 0
		return
	var basement := interior_view and view_floor < 0
	if Catalog.utility_of(kind) != "":
		node.visible = utility_view and not basement
		return
	node.visible = Catalog.is_underground(kind) or not basement


## Innenansicht: Dächer der Hallen weg, Wände niedrig, damit man hineinsieht.
func set_interior_view(on: bool) -> void:
	interior_view = on
	if not on and view_floor < 0:
		view_floor = 0
	for it: Dictionary in items:
		_apply_floor(it)
	for l: Dictionary in lines:
		_apply_visibility(l)
		if Catalog.is_wall(String(l["kind"])):
			_apply_interior(l["node"], true)
	interior_changed.emit(on)
	floor_changed.emit(view_floor)


## Halle oder Wand für die Innenansicht: Dach und hohe Fassade weg, niedrige Fassade auf der gezeigten Ebene.
func _apply_interior(n: Node3D, wall: bool = false) -> void:
	for part: String in ["Dach", "Hoch"]:
		var c := n.get_node_or_null(part) as Node3D
		if c != null:
			c.visible = not interior_view
	var low := n.get_node_or_null("Tief") as Node3D
	if low != null:
		low.visible = interior_view and view_floor >= 0
		if not wall:
			low.position.y = float(maxi(view_floor, 0)) * Catalog.FLOOR_H
	for f in range(-1, 4):
		var slab := n.get_node_or_null("Ebene%d" % f) as Node3D
		if slab != null:
			slab.visible = (not interior_view and f >= 0) or (interior_view and f <= view_floor and (f >= 0 or view_floor < 0))


# ---------------------------------------------------------------- Ebenen und Bauformen

static func floor_of(rec: Dictionary) -> int:
	return int(rec.get("floor", 0))


func opt(rec: Dictionary, key: String) -> Variant:
	var o: Dictionary = rec.get("opts", {})
	if o.has(key):
		return o[key]
	for e: Array in OPTIONS.get(String(rec.get("id", "")), []):
		if e[0] == key:
			return (e[2] as Array)[0] if not (rec.get("id", "") == "parkhaus" and key == "etagen") else 4
	return null


func hall_levels(h: Dictionary) -> int:
	return int(opt(h, "etagen"))


func hall_basement(h: Dictionary) -> bool:
	return bool(opt(h, "keller"))


## Ebenen, die es irgendwo gibt: [niedrigste, höchste]
func floor_range() -> Vector2i:
	var hi := 0
	for h: Dictionary in items_of("halle"):
		hi = maxi(hi, hall_levels(h) - 1)
	return Vector2i(-1, hi)   # Untergeschoss gibt es immer: Tunnel, Förderbänder, Keller


func set_view_floor(f: int) -> void:
	var r := floor_range()
	view_floor = clampi(f, r.x, r.y)
	for it: Dictionary in items:
		_apply_floor(it)
	for l: Dictionary in lines:
		_apply_visibility(l)
	floor_changed.emit(view_floor)


func _apply_floor(it: Dictionary) -> void:
	var node: Node3D = it["node"]
	if not is_instance_valid(node):
		return
	if it["id"] == "halle":
		_apply_interior(node)
	elif Catalog.is_zone(String(it["id"])):
		node.visible = interior_view and floor_of(it) == view_floor
	elif Catalog.is_inside(String(it["id"])):
		var f := floor_of(it)
		node.visible = (f == view_floor) if interior_view else f >= 0
	else:
		node.visible = not (interior_view and view_floor < 0)


func floor_name(f: int) -> String:
	return "Untergeschoss" if f < 0 else ("Erdgeschoss" if f == 0 else "%d. Obergeschoss" % f)


## Einstellungen eines Gebäudes für das Infofeld: [Schlüssel, Name, Wert als Text]
func options_of(rec: Dictionary) -> Array:
	var out := []
	for e: Array in OPTIONS.get(String(rec.get("id", "")), []):
		var v: Variant = opt(rec, e[0])
		var txt: String = str(v) if typeof(v) == TYPE_INT else String(OPTION_TEXT.get(v, str(v)))
		if typeof(v) == TYPE_BOOL:
			txt = "ja" if bool(v) else "nein"
		out.append([e[0], e[1], txt])
	return out


## Bauform wechseln (dir = +1/-1). Rückgabe: Fehlertext oder leer.
func cycle_option(rec: Dictionary, key: String, dir: int) -> String:
	var values: Array = []
	for e: Array in OPTIONS.get(String(rec.get("id", "")), []):
		if e[0] == key:
			values = e[2]
	if values.is_empty():
		return ""
	var cur: Variant = opt(rec, key)
	var i := values.find(cur)
	var v: Variant = values[(i + dir + values.size()) % values.size()]
	var cost := 0
	if rec["id"] == "halle":
		var area := (rec["rect"] as Rect2).get_area()
		if key == "etagen":
			var n := int(v)
			for it: Dictionary in inside_of(rec):
				if floor_of(it) >= n:
					return "Erst die Einrichtung der oberen Ebene abreißen"
			for l: Dictionary in walls_of(rec):
				if floor_of(l) >= n:
					return "Erst die Wände der oberen Ebene abreißen"
			cost = int(area * float(Catalog.ITEMS["halle"]["cost_m2"]) * 0.8) * (n - hall_levels(rec))
		if key == "keller":
			if not bool(v):
				for it: Dictionary in inside_of(rec):
					if floor_of(it) < 0:
						return "Erst die Einrichtung im Keller abreißen"
			cost = int(area * float(Catalog.ITEMS["halle"]["cost_m2"]) * 0.6) * (1 if bool(v) else -1)
	if rec["id"] == "parkhaus" and key == "etagen":
		cost = 70000 * (int(v) - int(cur))
	if cost > money:
		return "Nicht genug Geld: " + fmt_money(cost) + " nötig"
	if not rec.has("opts"):
		rec["opts"] = {}
	rec["opts"][key] = v
	if cost > 0:
		_spend(cost)
		rec["cost"] = int(rec["cost"]) + cost
	elif cost < 0:
		earn_quiet(-cost / 2)
		rec["cost"] = maxi(0, int(rec["cost"]) + cost)
	_rebuild_node(rec)
	evaluate_supply()
	items_changed.emit()
	return ""


func _rebuild_node(rec: Dictionary) -> void:
	var old: Node3D = rec["node"]
	var node: Node3D
	if rec["id"] == "halle":
		var r: Rect2 = rec["rect"]
		node = Factory.make_hall(r.size.x, r.size.y, rec.get("opts", {}))
	else:
		node = Factory.make_item(String(rec["id"]), rec.get("opts", {}))
	node.transform = old.transform
	item_root.add_child(node)
	old.queue_free()
	rec["node"] = node
	_apply_floor(rec)


# ---------------------------------------------------------------- Gebäude und Deko

func footprint(id: String, pos: Vector3, rot: int) -> Rect2:
	var s: Vector2 = Catalog.ITEMS[id]["size"]
	if rot % 2 == 1:
		s = Vector2(s.y, s.x)
	return Rect2(pos.x - s.x * 0.5, pos.z - s.y * 0.5, s.x, s.y)


func _on_kind(p: Vector3, kind: String) -> bool:
	var w: float = Catalog.LINES[kind]["width"]
	for l: Dictionary in lines:
		if l["kind"] != kind:
			continue
		var b: Rect2 = l["bounds"]
		if not b.has_point(Vector2(p.x, p.z)):
			continue
		for v: Vector3 in (l["samples"] as PackedVector3Array):
			if Vector2(v.x - p.x, v.z - p.z).length() < w * 0.5:
				return true
	return false


## Terminalhalle an diesem Bodenpunkt (oder leer).
func hall_at(p: Vector3) -> Dictionary:
	for it: Dictionary in items:
		if it["id"] == "halle" and (it["rect"] as Rect2).has_point(Vector2(p.x, p.z)):
			return it
	return {}


## Halle, die das Rechteck ganz enthält (oder leer).
func hall_for_rect(r: Rect2) -> Dictionary:
	for it: Dictionary in items:
		if it["id"] == "halle" and (it["rect"] as Rect2).grow(0.05).encloses(r):
			return it
	return {}


## Alles, was in dieser Halle eingebaut ist.
func inside_of(hall: Dictionary) -> Array:
	var out := []
	for it: Dictionary in items:
		if is_same(it.get("hall", null), hall):
			out.append(it)
	return out


func walls_of(hall: Dictionary) -> Array:
	var out := []
	for l: Dictionary in lines:
		if is_same(l.get("hall", null), hall):
			out.append(l)
	return out


func hall_cost(r: Rect2) -> int:
	return roundi(r.get_area() * float(Catalog.ITEMS["halle"]["cost_m2"]) / 1000.0) * 1000


## Rechteck aus zwei Eckpunkten, auf das Raster der Halle gerundet.
static func hall_rect(a: Vector3, b: Vector3) -> Rect2:
	var g: float = Catalog.ITEMS["halle"]["grid"]
	var x0 := snappedf(minf(a.x, b.x), g)
	var z0 := snappedf(minf(a.z, b.z), g)
	var x1 := snappedf(maxf(a.x, b.x), g)
	var z1 := snappedf(maxf(a.z, b.z), g)
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func _rect_on_lines(r: Rect2, on: String) -> String:
	for l: Dictionary in lines:
		var kind: String = l["kind"]
		if kind == "gehweg" or kind == on or Catalog.utility_of(kind) != "" or Catalog.is_wall(kind):
			continue
		var b: Rect2 = l["bounds"]
		if not b.intersects(r):
			continue
		var w: float = Catalog.LINES[kind]["width"]
		var grown := r.grow(w * 0.5 - 0.3)
		var s: PackedVector3Array = l["samples"]
		for i in range(0, s.size(), 2):
			if Catalog.covered(kind, s[i]):
				continue
			if grown.has_point(Vector2(s[i].x, s[i].z)):
				return "Liegt auf einem Weg: " + Catalog.label(kind)
	return ""


## Berührt das Rechteck die Außenwand der Halle?
static func touches_wall(r: Rect2, hall_r: Rect2) -> bool:
	return r.position.x - hall_r.position.x < 0.6 or hall_r.end.x - r.end.x < 0.6 \
		or r.position.y - hall_r.position.y < 0.6 or hall_r.end.y - r.end.y < 0.6


## Nächste Außenwand einer Halle von außen gesehen: [Halle, Außennormale, Wandpunkt, Abstand] oder leer.
func hall_side(p: Vector3) -> Array:
	var best: Array = []
	var bd := 8.0
	for h: Dictionary in items:
		if h["id"] != "halle":
			continue
		var r: Rect2 = h["rect"]
		var q := Vector2(p.x, p.z)
		if r.has_point(q):
			continue
		var c := Vector2(clampf(q.x, r.position.x, r.end.x), clampf(q.y, r.position.y, r.end.y))
		var d := q.distance_to(c)
		if d < bd:
			bd = d
			var n := Vector3.ZERO
			if is_equal_approx(c.y, r.position.y) and q.y < r.position.y:
				n = Vector3(0, 0, -1)
			elif is_equal_approx(c.y, r.end.y) and q.y > r.end.y:
				n = Vector3(0, 0, 1)
			elif q.x < r.position.x:
				n = Vector3(-1, 0, 0)
			else:
				n = Vector3(1, 0, 0)
			best = [h, n, Vector3(c.x, 0, c.y), d]
	return best


## Drehung (0–3), bei der die lokale +Z-Achse in Richtung n zeigt.
static func rot_for_normal(n: Vector3) -> int:
	if n.x > 0.5:
		return 1
	if n.z < -0.5:
		return 2
	if n.x < -0.5:
		return 3
	return 0


## Leerer Text = darf gebaut werden, sonst der Grund.
func can_place(id: String, pos: Vector3, rot: int) -> String:
	if bool(Catalog.ITEMS[id].get("bridge", false)):
		var hs := hall_side(pos)
		if hs.is_empty() or float(hs[3]) > 4.5:
			return "Direkt vor die Außenwand einer Terminalhalle setzen"
		rot = rot_for_normal(hs[1])
	var def: Dictionary = Catalog.ITEMS[id]
	var on: String = def.get("on", "")
	var r := footprint(id, pos, rot)
	var inner := r.grow(-0.05)
	if not on_map(Vector3(r.position.x, 0, r.position.y)) or not on_map(Vector3(r.end.x, 0, r.end.y)):
		return "Außerhalb der Karte"
	if Catalog.is_inside(id):
		var hall := hall_for_rect(r)
		if hall.is_empty():
			return "Nur innerhalb einer Terminalhalle"
		var f := view_floor
		if f >= hall_levels(hall) or (f < 0 and not hall_basement(hall)):
			return "Diese Halle hat keine %s (Ebenen im Infofeld der Halle einstellen)" % floor_name(f)
		if bool(def.get("connector", false)) and f + 1 >= hall_levels(hall):
			return "Darüber gibt es keine Ebene: der Halle erst eine weitere Ebene geben"
		if id == "eingang" and f != 0:
			return "Eingänge nur im Erdgeschoss"
		if bool(def.get("wall", false)) and f >= 0 and not touches_wall(r, hall["rect"]):
			return "Muss an der Außenwand der Halle stehen"
		if Catalog.is_door(id):
			var why_door := _door_wall_why(hall, f, r, rot)
			if why_door != "":
				return why_door
		for it: Dictionary in inside_of(hall):
			if Catalog.is_zone(String(it["id"])):
				continue
			var itf := floor_of(it)
			var covers := itf == f or (bool(Catalog.ITEMS[it["id"]].get("connector", false)) and itf + 1 == f) \
				or (bool(def.get("connector", false)) and itf == f + 1)
			if covers and inner.intersects(it["rect"]):
				return "Hier steht schon etwas"
		var probe := r.grow(-0.1)
		for l: Dictionary in walls_of(hall):
			if floor_of(l) != f or Catalog.is_door(id):
				continue
			for v: Vector3 in wall_probe(l):
				if probe.has_point(Vector2(v.x, v.z)):
					return "Steht auf einer Wand"
	else:
		for it: Dictionary in items:
			if Catalog.is_inside(String(it["id"])):
				continue
			if inner.intersects(it["rect"]):
				return "Hier steht schon etwas"
		if on != "" and not _on_kind(pos, on):
			return "Muss auf dem " + Catalog.label(on) + " liegen"
		var on_line := _rect_on_lines(r, on)
		if on_line != "":
			return on_line
	var cost: int = def["cost"]
	if cost > money:
		return "Nicht genug Geld"
	return ""


## Punkte entlang einer Wand alle 0,25 m (für Kollisionen und die Wegsuche der Passagiere).
func wall_probe(l: Dictionary) -> PackedVector3Array:
	var s: PackedVector3Array = l["samples"]
	var a: Vector3 = s[0]
	var b: Vector3 = s[s.size() - 1]
	var out := PackedVector3Array()
	var n := maxi(1, ceili(a.distance_to(b) / 0.25))
	for i in range(n + 1):
		out.append(a.lerp(b, float(i) / float(n)))
	return out


## Prüft eine Wand: beide Enden in derselben Halle, nicht durch Einrichtung. Leer = ok.
func can_place_wall(a: Vector3, b: Vector3) -> String:
	var hall := hall_at(a)
	if hall.is_empty() or not is_same(hall, hall_at(b)):
		return "Wände nur innerhalb einer Terminalhalle"
	var tmp := {"samples": PackedVector3Array([a, b])}
	for v: Vector3 in wall_probe(tmp):
		for it: Dictionary in inside_of(hall):
			if floor_of(it) != view_floor or Catalog.is_zone(String(it["id"])) or Catalog.is_door(String(it["id"])):
				continue
			if (it["rect"] as Rect2).grow(-0.1).has_point(Vector2(v.x, v.z)):
				return "Wand geht durch: " + Catalog.label(String(it["id"]))
	return ""


func can_place_hall(r: Rect2) -> String:
	var def: Dictionary = Catalog.ITEMS["halle"]
	var mn: Vector2 = def["min"]
	var mx: Vector2 = def["max"]
	var lo := minf(r.size.x, r.size.y)
	var hi := maxf(r.size.x, r.size.y)
	if lo < minf(mn.x, mn.y) or hi < maxf(mn.x, mn.y):
		return "Zu klein: mindestens %d × %d m" % [int(mn.x), int(mn.y)]
	if hi > maxf(mx.x, mx.y) or lo > minf(mx.x, mx.y):
		return "Zu groß: höchstens %d × %d m" % [int(mx.x), int(mx.y)]
	var inner := r.grow(-0.05)
	for it: Dictionary in items:
		if Catalog.is_inside(String(it["id"])):
			continue
		if inner.intersects(it["rect"]):
			return "Hier steht schon etwas"
	var on_line := _rect_on_lines(r, "")
	if on_line != "":
		return on_line
	if hall_cost(r) > money:
		return "Nicht genug Geld"
	return ""


func build_hall(r: Rect2, free: bool = false, opts: Dictionary = {}) -> Dictionary:
	var cost := 0 if free else hall_cost(r)
	if cost > money:
		toast.emit("Nicht genug Geld")
		return {}
	var node := Factory.make_hall(r.size.x, r.size.y, opts)
	var c := r.get_center()
	node.position = Vector3(c.x, 0.0, c.y)
	item_root.add_child(node)
	var rec := {"type": "item", "id": "halle", "pos": node.position, "rot": 0, "rect": r,
		"node": node, "cost": cost, "supply": {}, "opts": opts.duplicate()}
	items.append(rec)
	history.append(rec)
	_apply_interior(node)
	_spend(cost)
	evaluate_supply()
	items_changed.emit()
	return rec


func build_item(id: String, pos: Vector3, rot: int, free: bool = false, opts: Dictionary = {}, floor: int = -99) -> Dictionary:
	var cost: int = 0 if free else int(Catalog.ITEMS[id]["cost"])
	if cost > money:
		toast.emit("Nicht genug Geld")
		return {}
	if bool(Catalog.ITEMS[id].get("bridge", false)):
		var hs := hall_side(pos)
		if not hs.is_empty():
			rot = rot_for_normal(hs[1])
	var f := 0
	if Catalog.is_inside(id):
		f = view_floor if floor == -99 else floor
	var node := Factory.make_item(id, opts)
	node.position = Vector3(pos.x, float(f) * Catalog.FLOOR_H, pos.z)
	node.rotation.y = float(rot) * PI * 0.5
	item_root.add_child(node)
	var rec := {"type": "item", "id": id, "pos": node.position, "rot": rot,
		"rect": footprint(id, pos, rot), "node": node, "cost": cost, "supply": {}, "opts": opts.duplicate()}
	if Catalog.is_inside(id):
		rec["hall"] = hall_for_rect(rec["rect"])
		rec["floor"] = f
		_apply_floor(rec)
	items.append(rec)
	history.append(rec)
	if Catalog.is_door(id) and not (rec["hall"] as Dictionary).is_empty():
		refresh_walls(rec["hall"], f)
	_spend(cost)
	evaluate_supply()
	items_changed.emit()
	return rec


# ---------------------------------------------------------------- Türen und Bereiche

## Tür muss quer auf einer Innenwand derselben Ebene sitzen (Wand parallel zur Türbreite).
func _door_wall_why(hall: Dictionary, f: int, r: Rect2, rot: int) -> String:
	var c := r.get_center()
	var along := Vector2(1, 0) if rot % 2 == 0 else Vector2(0, 1)
	for l: Dictionary in walls_of(hall):
		if floor_of(l) != f:
			continue
		var s: PackedVector3Array = l["samples"]
		var a := Vector2(s[0].x, s[0].z)
		var b := Vector2(s[s.size() - 1].x, s[s.size() - 1].z)
		var d := b - a
		if d.length() < 0.5:
			continue
		var dn := d.normalized()
		if absf(dn.dot(along)) < 0.98:
			continue
		var t := (c - a).dot(dn)
		var half := maxf(r.size.x, r.size.y) * 0.5
		if t < half - 0.05 or t > d.length() - half + 0.05:
			continue
		if (a + dn * t).distance_to(c) < 0.35:
			return ""
	return "Tür auf eine Innenwand setzen (quer zur Wand, nicht an deren Ende)"


## Türen, die auf dieser Wand sitzen: Abschnitte [von, bis] in Metern ab dem Wandanfang.
func wall_cuts(l: Dictionary) -> Array:
	var out := []
	var hall: Dictionary = l.get("hall", {})
	if hall.is_empty():
		return out
	var s: PackedVector3Array = l["samples"]
	var a := Vector2(s[0].x, s[0].z)
	var b := Vector2(s[s.size() - 1].x, s[s.size() - 1].z)
	var d := b - a
	if d.length() < 0.5:
		return out
	var dn := d.normalized()
	for it: Dictionary in inside_of(hall):
		if not Catalog.is_door(String(it["id"])) or floor_of(it) != floor_of(l):
			continue
		var r: Rect2 = it["rect"]
		var c := r.get_center()
		var t := (c - a).dot(dn)
		var half := maxf(r.size.x, r.size.y) * 0.5
		var along := Vector2(1, 0) if r.size.x >= r.size.y else Vector2(0, 1)
		if (a + dn * t).distance_to(c) > 0.4 or t < half - 0.1 or t > d.length() - half + 0.1 or absf(dn.dot(along)) < 0.98:
			continue
		out.append([t - half, t + half])
	return out


## Wände einer Ebene neu bauen (nach dem Setzen oder Abreißen einer Tür).
func refresh_walls(hall: Dictionary, f: int) -> void:
	for l: Dictionary in walls_of(hall):
		if floor_of(l) != f:
			continue
		var old: Variant = l["node"]
		var s: PackedVector3Array = l["samples"]
		var node := Factory.make_wall(String(l["kind"]), s[0], s[s.size() - 1], wall_cuts(l))
		node.position.y = float(f) * Catalog.FLOOR_H
		line_root.add_child(node)
		l["node"] = node
		if is_instance_valid(old):
			(old as Node).queue_free()
		_apply_visibility(l)
		_apply_interior(node, true)


func zones_of(hall: Dictionary) -> Array:
	var out := []
	for it: Dictionary in inside_of(hall):
		if Catalog.is_zone(String(it["id"])):
			out.append(it)
	return out


## Bereich an einem Bodenpunkt einer Halle und Ebene: "oeffentlich", "sicherheit", "personal" oder "".
## Später gebaute Bereiche liegen über früheren.
func zone_at(hall: Dictionary, p: Vector2, f: int) -> String:
	var zs := zones_of(hall)
	for i in range(zs.size() - 1, -1, -1):
		var z: Dictionary = zs[i]
		if floor_of(z) == f and (z["rect"] as Rect2).has_point(p):
			return String(Catalog.ITEMS[z["id"]]["zone"])
	return ""


static func zone_rect(a: Vector3, b: Vector3) -> Rect2:
	var x0 := floorf(minf(a.x, b.x))
	var z0 := floorf(minf(a.z, b.z))
	var x1 := ceilf(maxf(a.x, b.x))
	var z1 := ceilf(maxf(a.z, b.z))
	return Rect2(x0, z0, maxf(x1 - x0, 1.0), maxf(z1 - z0, 1.0))


func zone_cost(id: String, r: Rect2) -> int:
	return roundi(r.get_area() * float(Catalog.ITEMS[id].get("cost_m2", 0)) / 10.0) * 10


func can_place_zone(id: String, r: Rect2, f: int = -99) -> String:
	var fl := view_floor if f == -99 else f
	var hall := hall_for_rect(r)
	if hall.is_empty():
		return "Bereiche nur innerhalb einer Terminalhalle"
	if fl >= hall_levels(hall) or (fl < 0 and not hall_basement(hall)):
		return "Diese Halle hat keine " + floor_name(fl)
	if r.size.x < 1.0 or r.size.y < 1.0:
		return "Zu klein"
	if zone_cost(id, r) > money:
		return "Nicht genug Geld"
	return ""


func build_zone(id: String, r: Rect2, free: bool = false, f: int = -99) -> Dictionary:
	var fl := view_floor if f == -99 else f
	var cost := 0 if free else zone_cost(id, r)
	if cost > money:
		toast.emit("Nicht genug Geld")
		return {}
	var node := Factory.make_zone(id, r.size.x, r.size.y)
	var c := r.get_center()
	node.position = Vector3(c.x, float(fl) * Catalog.FLOOR_H, c.y)
	item_root.add_child(node)
	var rec := {"type": "item", "id": id, "pos": node.position, "rot": 0, "rect": r, "node": node, "cost": cost,
		"supply": {}, "opts": {}, "hall": hall_for_rect(r), "floor": fl}
	items.append(rec)
	history.append(rec)
	_apply_floor(rec)
	_spend(cost)
	items_changed.emit()
	return rec


func stands() -> Array:
	var out := []
	for it: Dictionary in items:
		if it["id"] == "stand" or it["id"] == "stand_aussen" or it["id"] == "stand_gross":
			out.append(it)
	return out


func items_of(id: String) -> Array:
	var out := []
	for it: Dictionary in items:
		if it["id"] == id:
			out.append(it)
	return out


# ---------------------------------------------------------------- Versorgung (Strom, Wasser)

func _touches_item(l: Dictionary, it: Dictionary) -> bool:
	var r: Rect2 = (it["rect"] as Rect2).grow(2.5)
	var b: Rect2 = l["bounds"]
	if not b.intersects(r):
		return false
	var s: PackedVector3Array = l["samples"]
	for i in range(0, s.size(), 2):
		if r.has_point(Vector2(s[i].x, s[i].z)):
			return true
	return r.has_point(Vector2(s[s.size() - 1].x, s[s.size() - 1].z))


func _touches_line(a: Dictionary, b: Dictionary) -> bool:
	var sa: PackedVector3Array = a["samples"]
	var sb: PackedVector3Array = b["samples"]
	for e: Vector3 in [sa[0], sa[sa.size() - 1]]:
		for v: Vector3 in sb:
			if e.distance_to(v) < 3.0:
				return true
	for e: Vector3 in [sb[0], sb[sb.size() - 1]]:
		for v: Vector3 in sa:
			if e.distance_to(v) < 3.0:
				return true
	return false


## Bedarf eines Objekts. Eine Halle braucht Strom für sich selbst plus alles, was in ihr steht.
func needs_of(it: Dictionary) -> Dictionary:
	if it["id"] != "halle":
		return Catalog.ITEMS[it["id"]].get("needs", {})
	var out := {"strom": roundf((it["rect"] as Rect2).get_area() * Catalog.HALL_POWER_M2)}
	for inner: Dictionary in inside_of(it):
		var n: Dictionary = Catalog.ITEMS[inner["id"]].get("needs", {})
		for util: String in n:
			out[util] = float(out.get(util, 0.0)) + float(n[util])
	return out


## Berechnet für jedes Gebäude, ob es Strom, Wasser und Wärme bekommt.
## Zustand je Netz: "ok", "fehlt" (nicht angeschlossen) oder "ueberlast".
## Was in einer Halle steht, hängt am Netz der Halle.
func evaluate_supply() -> void:
	for it: Dictionary in items:
		it["supply"] = {}
	for util: String in Catalog.UTILITIES:
		var nodes := []   # Leitungen und beteiligte Gebäude
		for l: Dictionary in lines:
			if Catalog.utility_of(String(l["kind"])) == util:
				nodes.append(l)
		for it: Dictionary in items:
			if Catalog.is_inside(String(it["id"])):
				continue
			var def: Dictionary = Catalog.ITEMS[it["id"]]
			if needs_of(it).has(util) or (def.get("supply", {}) as Dictionary).has(util):
				nodes.append(it)
		var n := nodes.size()
		var adj := []
		for i in range(n):
			adj.append([])
		for i in range(n):
			for j in range(i + 1, n):
				var a: Dictionary = nodes[i]
				var b: Dictionary = nodes[j]
				var linked := false
				if a["type"] == "line" and b["type"] == "line":
					linked = _touches_line(a, b)
				elif a["type"] == "line" and b["type"] == "item":
					linked = _touches_item(a, b)
				elif a["type"] == "item" and b["type"] == "line":
					linked = _touches_item(b, a)
				if linked:
					(adj[i] as Array).append(j)
					(adj[j] as Array).append(i)
		var comp := []
		comp.resize(n)
		comp.fill(-1)
		var cap := []
		var dem := []
		for i in range(n):
			if comp[i] != -1:
				continue
			var cid := cap.size()
			cap.append(0.0)
			dem.append(0.0)
			var stack := [i]
			comp[i] = cid
			while not stack.is_empty():
				var k: int = stack.pop_back()
				var node: Dictionary = nodes[k]
				if node["type"] == "item":
					var def: Dictionary = Catalog.ITEMS[node["id"]]
					cap[cid] = float(cap[cid]) + float((def.get("supply", {}) as Dictionary).get(util, 0.0))
					dem[cid] = float(dem[cid]) + float(needs_of(node).get(util, 0.0))
				for nb: int in adj[k]:
					if comp[nb] == -1:
						comp[nb] = cid
						stack.append(nb)
		for i in range(n):
			var node: Dictionary = nodes[i]
			if node["type"] != "item":
				continue
			if not needs_of(node).has(util):
				continue
			var c: int = comp[i]
			var state := "ok"
			if float(cap[c]) <= 0.0:
				state = "fehlt"
			elif float(dem[c]) > float(cap[c]):
				state = "ueberlast"
			(node["supply"] as Dictionary)[util] = state
	for it: Dictionary in items:
		var hall: Dictionary = it.get("hall", {})
		if hall.is_empty():
			continue
		for util: String in (Catalog.ITEMS[it["id"]].get("needs", {}) as Dictionary):
			(it["supply"] as Dictionary)[util] = (hall["supply"] as Dictionary).get(util, "fehlt")
	_update_status_labels()
	supply_changed.emit()


## Ist die Halle über Gepäckförderbänder mit einem Gepäckumschlag verbunden? Gibt den Umschlag zurück.
func baggage_link(hall: Dictionary) -> Dictionary:
	var belts := []
	for l: Dictionary in lines:
		if l["kind"] == "foerderband":
			belts.append(l)
	if belts.is_empty():
		return {}
	var seen := {}
	var stack := []
	for i in range(belts.size()):
		if _touches_item(belts[i], hall):
			stack.append(i)
			seen[i] = true
	while not stack.is_empty():
		var i: int = stack.pop_back()
		for u: Dictionary in items_of("gepaeckumschlag"):
			if _touches_item(belts[i], u):
				return u
		for j in range(belts.size()):
			if not seen.has(j) and _touches_line(belts[i], belts[j]):
				seen[j] = true
				stack.append(j)
	return {}


## Offene Tunnelrampen als Löcher im Rasen: je [Mitte x, Mitte z, Richtung x, Richtung z, halbe Länge, halbe Breite]
func tunnel_cuts() -> Array:
	var out := []
	for l: Dictionary in lines:
		if l["kind"] != "tunnel":
			continue
		var s: PackedVector3Array = l["samples"]
		var w: float = float(Catalog.LINES["tunnel"]["width"]) * 0.5 + 0.9
		for from_end: bool in [false, true]:
			var idx := []
			for i in range(s.size()):
				var k := s.size() - 1 - i if from_end else i
				if s[k].y < -0.05 or i < 2:
					idx.append(k)
				if s[k].y < Catalog.TUNNEL_COVER - 0.4:
					break
			var a := 0
			while a < idx.size() - 1:
				var b := mini(a + 10, idx.size() - 1)
				var p0: Vector3 = s[idx[a]]
				var p1: Vector3 = s[idx[b]]
				var d := Vector2(p1.x - p0.x, p1.z - p0.z)
				if d.length() > 0.5:
					var c := (Vector2(p0.x, p0.z) + Vector2(p1.x, p1.z)) * 0.5
					var dn := d.normalized()
					out.append([c.x, c.y, dn.x, dn.y, d.length() * 0.5 + 0.6, w])
				a = b
	return out


func supplied(it: Dictionary, util: String) -> bool:
	return String((it["supply"] as Dictionary).get(util, "ok")) == "ok"


func _update_status_labels() -> void:
	for it: Dictionary in items:
		if Catalog.is_inside(String(it["id"])):
			continue
		var node: Node3D = it["node"]
		var old := node.get_node_or_null("Status")
		var text := ""
		for util: String in Catalog.UTILITIES:
			var st: String = (it["supply"] as Dictionary).get(util, "ok")
			var name: String = Catalog.UTILITIES[util][0]
			if st == "fehlt":
				text += ("\n" if text != "" else "") + ("Keine " if util == "waerme" else "Kein ") + name
			elif st == "ueberlast":
				text += ("\n" if text != "" else "") + name + " überlastet"
		if text == "":
			if old != null:
				old.queue_free()
			continue
		var lbl: Label3D = old if old != null else Label3D.new()
		if old == null:
			lbl.name = "Status"
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.no_depth_test = true
			lbl.fixed_size = true
			lbl.pixel_size = 0.0028
			lbl.font_size = 26
			lbl.outline_size = 8
			lbl.modulate = Color(1.0, 0.45, 0.35)
			lbl.outline_modulate = Color(0.1, 0.03, 0.02)
			lbl.visibility_range_end = 950.0   # weit herausgezoomt ausblenden
			node.add_child(lbl)
		lbl.text = text
		lbl.position = Vector3(0, float(Catalog.ITEMS[it["id"]]["h"]) + 3.0, 0)


# ---------------------------------------------------------------- Auswählen, Abreißen, Rückgängig

func pick(p: Vector3) -> Dictionary:
	var q := Vector2(p.x, p.z)
	for it: Dictionary in items:
		if Catalog.is_inside(String(it["id"])) and not Catalog.is_zone(String(it["id"])) and (it["rect"] as Rect2).grow(0.2).has_point(q):
			if not interior_view or floor_of(it) == view_floor:
				return it
	for l: Dictionary in lines:
		if Catalog.is_wall(String(l["kind"])) and (not interior_view or floor_of(l) == view_floor):
			for v: Vector3 in wall_probe(l):
				if Vector2(v.x - p.x, v.z - p.z).length() < 0.7:
					return l
	if interior_view:
		for i in range(items.size() - 1, -1, -1):
			var it: Dictionary = items[i]
			if Catalog.is_zone(String(it["id"])) and floor_of(it) == view_floor and (it["rect"] as Rect2).has_point(q):
				return it
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		var r: Rect2 = it["rect"]
		if Catalog.is_zone(String(it["id"])):
			continue
		if r.has_point(q):
			return it
	var best: Dictionary = {}
	var best_score := INF
	for l: Dictionary in lines:
		var kind: String = l["kind"]
		if Catalog.utility_of(kind) != "" and not utility_view:
			continue
		var b: Rect2 = l["bounds"]
		if not b.has_point(q):
			continue
		var w: float = maxf(float(Catalog.LINES[kind]["width"]), 3.0)
		var s: PackedVector3Array = l["samples"]
		for v: Vector3 in s:
			var d := Vector2(v.x - p.x, v.z - p.z).length()
			if d < w * 0.5 and d + w < best_score:
				best_score = d + w
				best = l
	return best


## Mehrzeilige Details für das Info-Werkzeug.
func details(rec: Dictionary) -> String:
	var out := []
	if rec.get("type", "") == "line":
		var kind: String = rec["kind"]
		out.append(String(Catalog.LINES[kind].get("desc", "")))
		var cost := line_cost(kind, rec["samples"])
		out.append("Unterhalt %s pro Tag" % fmt_money(roundi(float(cost) * Catalog.UPKEEP_LINES)))
		return "\n".join(out)
	var def: Dictionary = Catalog.ITEMS[rec["id"]]
	if rec["id"] == "halle" or Catalog.is_zone(String(rec["id"])):
		var r: Rect2 = rec["rect"]
		out.append("%d × %d m, %s m²" % [int(r.size.x), int(r.size.y), fmt_money(int(r.get_area())).trim_suffix(" €")])
		if Catalog.is_zone(String(rec["id"])):
			out.append(String(def.get("desc", "")))
	else:
		out.append(String(def.get("desc", "")))
	var needs := needs_of(rec)
	var in_hall := rec.has("hall")
	for util: String in Catalog.UTILITIES:
		if needs.has(util):
			var st: String = (rec["supply"] as Dictionary).get(util, "ok")
			var word: String = {"ok": "versorgt", "fehlt": "nicht angeschlossen", "ueberlast": "Netz überlastet"}[st]
			if in_hall and st == "fehlt":
				word = "Halle nicht angeschlossen"
			out.append("%s: %d %s, %s" % [Catalog.UTILITIES[util][0], int(needs[util]), Catalog.UTILITIES[util][1], word])
	var sup: Dictionary = def.get("supply", {})
	for util: String in sup:
		out.append("Liefert %d %s %s" % [int(sup[util]), Catalog.UTILITIES[util][1], Catalog.UTILITIES[util][0]])
	out.append("Unterhalt %s pro Tag" % fmt_money(roundi(float(item_value(rec)) * Catalog.UPKEEP_ITEMS)))
	return "\n".join(out)


func describe(rec: Dictionary) -> String:
	if rec.get("type", "") == "line":
		var s: PackedVector3Array = rec["samples"]
		return "%s (%d m)" % [Catalog.label(String(rec["kind"])), int(Spline.length(s))]
	return Catalog.label(String(rec.get("id", "")))


func remove(rec: Dictionary, refund: float = 0.5) -> void:
	var any_line: bool = rec["type"] == "line"
	if rec.get("id", "") == "halle":
		var walls := walls_of(rec)
		any_line = any_line or not walls.is_empty()
		for inner: Dictionary in inside_of(rec) + walls:
			_remove_one(inner, refund)
	_remove_one(rec, refund)
	if Catalog.is_door(String(rec.get("id", ""))) and not (rec.get("hall", {}) as Dictionary).is_empty():
		refresh_walls(rec["hall"], floor_of(rec))
	evaluate_supply()
	if any_line:
		network_changed.emit()
	if rec["type"] == "item":
		items_changed.emit()


func _remove_one(rec: Dictionary, refund: float) -> void:
	var node: Variant = rec["node"]
	if is_instance_valid(node):
		(node as Node).queue_free()
	lines.erase(rec)
	items.erase(rec)
	history.erase(rec)
	for h: Variant in history.duplicate():
		if h is Array:
			(h as Array).erase(rec)
			if (h as Array).is_empty():
				history.erase(h)
	if rec["type"] == "line":
		_grid_dirty = true
	var cost: int = rec["cost"]
	_spend(-int(float(cost) * refund))


func undo_last() -> void:
	if history.is_empty():
		toast.emit("Nichts zum Rückgängigmachen")
		return
	var entry: Variant = history[history.size() - 1]
	if entry is Array:
		var group: Array = (entry as Array).duplicate()
		history.pop_back()
		for rec: Dictionary in group:
			if rec in lines or rec in items:
				_remove_one(rec, 1.0)
		evaluate_supply()
		network_changed.emit()
		items_changed.emit()
		toast.emit("Rückgängig: " + describe(group[0]))
		return
	var rec: Dictionary = entry
	remove(rec, 1.0)
	toast.emit("Rückgängig: " + describe(rec))


func clear_all() -> void:
	for rec: Dictionary in lines + items:
		var node: Variant = rec["node"]
		if is_instance_valid(node):
			(node as Node).queue_free()
	lines.clear()
	items.clear()
	history.clear()
	junction_controls = {}
	_grid_dirty = true
	money = START_MONEY
	satisfaction = 75.0
	day_income = 0
	money_changed.emit(money)
	network_changed.emit()
	items_changed.emit()
	supply_changed.emit()


# ---------------------------------------------------------------- Speichern und Laden

func save_game(quiet: bool = false) -> void:
	var data := {"version": 6, "controls": junction_controls, "money": money, "minutes": minutes, "satisfaction": satisfaction, "lines": [], "items": [],
		"wind": [wind_dir, wind_kt]}
	var ls: Array = data["lines"]
	for l: Dictionary in lines:
		var pts := []
		for p: Vector3 in l["points"]:
			pts.append([snappedf(p.x, 0.01), snappedf(p.z, 0.01)])
		if bool(l.get("raw", false)):
			pts = []
			for p: Vector3 in (l["samples"] as PackedVector3Array):
				pts.append([snappedf(p.x, 0.01), snappedf(p.z, 0.01)])
		ls.append({"kind": l["kind"], "points": pts, "cost": l["cost"], "raw": bool(l.get("raw", false)), "flip": bool(l.get("flip", false)),
			"floor": floor_of(l)})
	var its: Array = data["items"]
	for it: Dictionary in items:
		var p: Vector3 = it["pos"]
		var e := {"id": it["id"], "x": snappedf(p.x, 0.01), "z": snappedf(p.z, 0.01), "rot": it["rot"], "cost": it["cost"],
			"opts": it.get("opts", {}), "floor": floor_of(it)}
		if it["id"] == "halle" or Catalog.is_zone(String(it["id"])):
			var r: Rect2 = it["rect"]
			e["w"] = r.size.x
			e["d"] = r.size.y
		its.append(e)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		toast.emit("Speichern fehlgeschlagen")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if not quiet:
		toast.emit("Gespeichert")


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		toast.emit("Noch kein Spielstand gespeichert")
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		toast.emit("Spielstand ist beschädigt")
		return false
	var data: Dictionary = parsed
	clear_all()
	# Hallen zuerst, damit Wände und Einrichtung ihre Halle finden
	for it: Dictionary in data.get("items", []):
		if String(it["id"]) == "halle":
			var w := float(it["w"])
			var d := float(it["d"])
			var rec := build_hall(Rect2(float(it["x"]) - w * 0.5, float(it["z"]) - d * 0.5, w, d), true, it.get("opts", {}))
			if not rec.is_empty():
				rec["cost"] = int(it.get("cost", 0))
	for l: Dictionary in data.get("lines", []):
		if not Catalog.LINES.has(String(l["kind"])):
			continue
		var pts := []
		for p: Array in l["points"]:
			pts.append(Vector3(float(p[0]), 0.0, float(p[1])))
		var rec: Dictionary = {}
		view_floor = int(l.get("floor", 0))
		if bool(l.get("raw", false)):
			rec = _make_line(String(l["kind"]), pts, PackedVector3Array(pts), int(l.get("cost", 0)), true)
		else:
			rec = build_line(String(l["kind"]), pts, true, true)
		if not rec.is_empty():
			rec["cost"] = int(l.get("cost", 0))
			rec["flip"] = bool(l.get("flip", false))
	for it: Dictionary in data.get("items", []):
		if not Catalog.ITEMS.has(String(it["id"])) or String(it["id"]) == "halle":
			continue
		if Catalog.is_zone(String(it["id"])):
			var zw := float(it.get("w", 4.0))
			var zd := float(it.get("d", 4.0))
			var zr := build_zone(String(it["id"]), Rect2(float(it["x"]) - zw * 0.5, float(it["z"]) - zd * 0.5, zw, zd), true, int(it.get("floor", 0)))
			if not zr.is_empty():
				zr["cost"] = int(it.get("cost", 0))
			continue
		var rec := build_item(String(it["id"]), Vector3(float(it["x"]), 0.0, float(it["z"])), int(it["rot"]), true,
			it.get("opts", {}), int(it.get("floor", 0)))
		if not rec.is_empty():
			rec["cost"] = int(it.get("cost", 0))
	view_floor = 0
	history.clear()
	junction_controls = data.get("controls", {})
	network_changed.emit()
	money = int(data.get("money", START_MONEY))
	minutes = float(data.get("minutes", 360.0))
	var wnd: Array = data.get("wind", [250.0, 9.0])
	wind_dir = float(wnd[0])
	_wind_goal = wind_dir
	wind_kt = float(wnd[1])
	last_day = int(minutes / 1440.0)
	satisfaction = float(data.get("satisfaction", 75.0))
	money_changed.emit(money)
	toast.emit("Spielstand geladen")
	return true


# ---------------------------------------------------------------- Startflughafen

func load_starter() -> void:
	var V := func(x: float, z: float) -> Vector3: return Vector3(x, 0.0, z)
	# Vorfeld bis zum Terminal, dahinter der Parallelrollweg A (Abstand Pistenmitte 168 m nach ICAO,
	# Rollhalteorte 90 m vor der Pistenmitte), an den Enden Zurollwege, dazwischen zwei Schnellabrollwege.
	build_line("vorfeld", [V.call(-155, -56), V.call(215, -56)], true)
	build_line("vorfeld", [V.call(-155, -92), V.call(215, -92)], true)
	build_line("vorfeld", [V.call(118, -24), V.call(215, -24)], true)
	build_line("rollweg_breit", [V.call(-1280, -272), V.call(-1278, -200), V.call(-1266, -140), V.call(-1230, -110),
		V.call(-1180, -104), V.call(1180, -104), V.call(1230, -110), V.call(1266, -140), V.call(1278, -200),
		V.call(1280, -272)], true)
	build_line("piste", [V.call(-1300, -272), V.call(1300, -272)], true)
	# Schnellabrollwege für beide Landerichtungen
	for x: float in [140.0, 470.0]:
		build_line("rollweg", [V.call(x, -272), V.call(x + 70, -260), V.call(x + 125, -238), V.call(x + 160, -205),
			V.call(x + 178, -165), V.call(x + 184, -130), V.call(x + 185, -104)], true)
	for x: float in [-160.0, -520.0]:
		build_line("rollweg", [V.call(x, -272), V.call(x - 70, -260), V.call(x - 125, -238), V.call(x - 160, -205),
			V.call(x - 178, -165), V.call(x - 184, -130), V.call(x - 185, -104)], true)
	# Betriebsstraße vor den Ständen (unter den Brücken durch), um den Großraum-Stand herum zu den Garagen
	build_line("betriebsstrasse", [V.call(-176, -32), V.call(110, -32), V.call(121, -25), V.call(128, -12), V.call(140, -7),
		V.call(204, -7), V.call(216, -12), V.call(223, -26), V.call(234, -32), V.call(372, -32)], true)
	build_line("strasse", [V.call(430, 60), V.call(260, 60), V.call(170, 40), V.call(60, 30),
		V.call(-60, 30), V.call(-150, 45), V.call(-215, 110)], true)
	build_line("strasse", [V.call(115, 210), V.call(115, 35)], true)
	build_line("gehweg", [V.call(-36, 20), V.call(36, 20)], true)
	_starter_terminal(V)
	# Kontaktstände mit Brücke vor den Gates, Außenpositionen mit Bus und Treppe an den Enden
	for x: float in [-85.0, -40.0, 5.0, 50.0]:
		build_item("stand", V.call(x, -55), 0, true)
	for x: float in [-130.0, 95.0]:
		build_item("stand_aussen", V.call(x, -55), 0, true)
	for x: float in [-67.0, -22.0, 11.0, 56.0]:
		build_item("fluggastbruecke", V.call(x, -26.5), 0, true)
	build_item("stand_gross", V.call(165, -50), 0, true)
	build_item("bushalt", V.call(123.5, -45), 1, true)
	for x: float in [-107.5, -62.5, -17.5, 27.5, 72.5, 129.5]:
		build_item("flutlicht", V.call(x, -48), 0, true)
	build_item("tower", V.call(262, 22), 0, true)
	build_item("hangar", V.call(-200, -48), 0, true)
	build_item("parkhaus", V.call(-40, 62), 0, true)
	build_item("trafo", V.call(60, 50), 0, true)
	build_item("trafo", V.call(205, 14), 0, true)
	build_item("trafo", V.call(-70, 55), 0, true)
	build_item("wasseranschluss", V.call(40, 22), 0, true)
	build_item("wasseranschluss", V.call(219, -5), 0, true)
	build_item("heizzentrale", V.call(92, 60), 0, true)
	build_item("haltestelle", V.call(-48, 22), 2, true)
	# Luftseite: Gerätehalle im Westen, Catering, Tanklager, Busgarage und Feuerwache im Osten
	build_item("vorfelddepot", V.call(-160, -10), 2, true)
	build_item("catering", V.call(240, -12), 2, true)
	build_item("tanklager", V.call(250, -55), 0, true)
	build_item("busgarage", V.call(298, -52), 0, true)
	build_item("feuerwache", V.call(345, -52), 0, true)
	build_item("gepaeckumschlag", V.call(295, -10), 0, true)
	build_item("personalgebaeude", V.call(150, 14), 0, true)
	# Sicherheitszaun zwischen Landseite und Luftseite, Grünanlagen am Terminal
	build_line("zaun", [V.call(-142, 4), V.call(-232, 4)], true)
	build_line("zaun", [V.call(108, 4), V.call(322, 4)], true)
	for x: float in [-44.0, 44.0]:
		build_item("blumenbeet", V.call(x, 23.5), 0, true)
	for p: Vector2 in [Vector2(-70, 22), Vector2(70, 22), Vector2(-84, 23), Vector2(84, 23), Vector2(20, 88), Vector2(44, 90)]:
		build_item("busch", V.call(p.x, p.y), 0, true)
	build_item("teich", V.call(30, 100), 0, true)
	build_item("picknick", V.call(46, 102), 0, true)
	build_item("felsen", V.call(16, 104), 0, true)
	build_line("foerderband", [V.call(96, -19), V.call(150, -14), V.call(281, -8)], true)
	# Strom: Trafo 1 fürs Terminal und die Heizzentrale, Trafo 2 für die Luftseite und den Tower,
	# Trafo 3 für Parkhaus und Gerätehalle
	build_line("stromkabel", [V.call(58, 46), V.call(58, 15)], true)
	build_line("stromkabel", [V.call(65, 52), V.call(81, 56)], true)
	build_line("stromkabel", [V.call(204, 18), V.call(164, 18)], true)
	build_line("stromkabel", [V.call(209, 11), V.call(229, -4)], true)
	build_line("stromkabel", [V.call(240, -21), V.call(240, -40)], true)
	build_line("stromkabel", [V.call(271, -55), V.call(281, -55)], true)
	build_line("stromkabel", [V.call(315, -50), V.call(331, -50)], true)
	build_line("stromkabel", [V.call(209, 17), V.call(257, 20)], true)
	build_line("stromkabel", [V.call(267, 16), V.call(283, -3)], true)
	build_line("stromkabel", [V.call(-66, 55), V.call(-57, 55)], true)
	build_line("stromkabel", [V.call(-74, 51), V.call(-120, 34), V.call(-160, 12), V.call(-160, -1)], true)
	# Wasser: Anschluss 1 fürs Terminal und die Heizzentrale, Anschluss 2 für Catering, Feuerwache, Personal
	build_line("wasserrohr", [V.call(40, 20), V.call(40, 15)], true)
	build_line("wasserrohr", [V.call(42, 23), V.call(82, 57)], true)
	build_line("wasserrohr", [V.call(220, -4), V.call(226, -4)], true)
	build_line("wasserrohr", [V.call(254, -20), V.call(258, -26), V.call(338, -26), V.call(338, -43)], true)
	build_line("wasserrohr", [V.call(219, -3), V.call(200, 6), V.call(163, 10)], true)
	build_line("heizrohr", [V.call(84, 52), V.call(84, 30), V.call(84, 15)], true)
	for x: float in [-24.0, -12.0, 12.0, 24.0]:
		build_item("kuebel", V.call(x, 23.2), 0, true)
	for x: float in [-6.0, 6.0]:
		build_item("bank", V.call(x, 23.2), 0, true)
	for x in range(-30, 140, 30):
		build_item("laterne", V.call(float(x), 25.0), 0, true)
	for x in range(130, 420, 24):
		build_item("baum", V.call(float(x), 76 + float(x % 7)), 0, true)
	for p: Vector2 in [Vector2(-110, 90), Vector2(-90, 110), Vector2(20, 80), Vector2(-260, 20), Vector2(-240, 60),
			Vector2(150, 110), Vector2(-120, 140)]:
		build_item("baum", V.call(p.x, p.y), 0, true)
	history.clear()
	money = START_MONEY
	minutes = 6.0 * 60.0
	money_changed.emit(money)


## Terminal des Startflughafens: Halle 250 × 40 m, Landseite oben (+z), Vorfeld unten (-z).
## Öffentlicher Bereich vorn mit Eingängen, Check-in und Gepäckbändern; Glaswand mit drei
## Kontrollspuren und dem Ausgang; dahinter der Sicherheitsbereich mit Gates, Läden und Cafés;
## im Osten der Personalbereich mit Gepäcksortierung und Personalraum hinter Personaltüren.
func _starter_terminal(V: Callable) -> void:
	build_hall(Rect2(-142, -24, 250, 40), true, {"vordach": true})
	var put := func(id: String, x: float, z: float, r: int = 0, o: Dictionary = {}) -> void:
		build_item(id, V.call(x, z), r, true, o)
	# Bereiche
	build_zone("bereich_oeffentlich", Rect2(-142, -8, 250, 24), true, 0)
	build_zone("bereich_sicherheit", Rect2(-142, -24, 222, 16), true, 0)
	build_zone("bereich_personal", Rect2(80, -24, 28, 16), true, 0)
	# Wände: Glaswand mit Lücken für Kontrolle und Ausgang, Personalbereich mit Innenwänden
	build_line("glaswand", [V.call(-142, -8), V.call(-18, -8)], true)
	build_line("glaswand", [V.call(0, -8), V.call(28, -8)], true)
	build_line("glaswand", [V.call(32, -8), V.call(80, -8)], true)
	build_line("innenwand", [V.call(80, -8), V.call(108, -8)], true)
	build_line("innenwand", [V.call(80, -24), V.call(80, -8)], true)
	put.call("tuer", 88, -8, 0, {"art": "personal"})
	put.call("tuer", 80, -14, 1, {"art": "personal"})
	put.call("sb_ausgang", 30, -8)
	for x: float in [-15.0, -9.0, -3.0]:
		put.call("sicherheit", x, -8)
	# Landseite: Eingänge, Check-in, Gepäckbänder, Info, Café, Kiosk, WC
	for x: float in [-110.0, -48.0, 0.0, 48.0]:
		put.call("eingang", x, 15)
	for x: float in [-100.0, -94.0, -88.0, -40.0, -34.0, -28.0]:
		put.call("checkin", x, 2.5)
	put.call("gepaeckband", 45, -1.5)
	put.call("gepaeckband", 60, -1.5, 0, {"stil": "karussell"})
	put.call("infoschalter", 15, 6)
	put.call("cafe", -125, 8, 0, {"stil": "baeckerei"})
	put.call("kiosk", 95, 10)
	put.call("wc", 75, 12)
	put.call("wc", -134, -1.5, 1)
	for x: float in [-70.0, 24.0]:
		put.call("anzeige", x, 14.5)
	put.call("anzeige", -64, -5.5)
	for p: Vector2 in [Vector2(-66, 7), Vector2(-60, 7), Vector2(26, 7), Vector2(32, 7)]:
		put.call("sitzreihe", p.x, p.y)
	for x: float in [-118.0, -78.0, -56.0, -20.0, 30.0, 66.0]:
		put.call("pflanze", x, 14.5)
	put.call("uhr", 8, 10)
	put.call("snackautomat", -140.5, 10, 1)
	put.call("getraenkeautomat", -140.5, 8, 1)
	put.call("geldautomat", -20, 12.5)
	put.call("werbebildschirm", -6, 4, 0)
	put.call("ladestation", 36, 10)
	put.call("kofferwagen", -78, 10)
	put.call("trinkbrunnen", 70, 5)
	# Sicherheitsbereich: Gates an der Vorfeldseite, dazwischen Läden, Cafés, WCs
	for x: float in [-67.0, -22.0, 11.0, 56.0]:
		put.call("gate", x, -20)
	put.call("busgate", -120, -20)
	put.call("busgate", 70, -20)
	put.call("shop", -95, -20, 0, {"stil": "dutyfree"})
	put.call("shop", -35, -20, 0, {"stil": "buecher"})
	put.call("cafe", -45, -20, 0, {"stil": "bar"})
	put.call("cafe", 25, -20, 0, {"stil": "cafe"})
	put.call("wc", -82, -21.5)
	put.call("wc", 40, -21.5)
	put.call("kunst", -6, -20)
	put.call("anzeige", -10, -14.5)
	put.call("anzeige", 40, -15)
	put.call("lounge", -130, -12)
	put.call("spielecke", -105, -11.5)
	put.call("aquarium", 0, -14.8)
	for x: float in [-140.0, -86.0, -52.0, 18.0, 46.0, 64.0]:
		put.call("pflanze", x, -9.2)
	# Personalbereich: Gepäcksortierung und Personalraum
	put.call("gepaeckanlage", 96, -20)
	put.call("personalraum", 101, -11)
	# Heizkörper an den Außenwänden
	for x: float in [-136.0, -125.0, -95.0, -82.0, -70.0, -60.0, -35.0, -20.0, -10.0, 10.0, 20.0, 34.0, 60.0, 72.0, 86.0, 100.0]:
		put.call("heizkoerper", x, 15.75)
	for x: float in [-136.0, -103.0, -88.0, -58.0, -30.0, 2.0, 32.0, 47.0, 85.0]:
		put.call("heizkoerper", x, -23.75)
	for z: float in [-18.0, 6.0]:
		put.call("heizkoerper", 107.75, z, 1)
