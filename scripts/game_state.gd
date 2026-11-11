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
signal before_save                 # Systeme legen ihren Zustand in extra ab
signal hall_moved(h: Dictionary, delta: Vector3)   # Halle samt Einrichtung verschoben

const Catalog = preload("res://scripts/catalog.gd")
const Spline = preload("res://scripts/spline.gd")
const MAP_HALF := 3000.0   # Spielfeld 6 × 6 km, Mitte im Ursprung


static func on_map(p: Vector3, margin: float = 0.0) -> bool:
	return absf(p.x) <= MAP_HALF - margin and absf(p.z) <= MAP_HALF - margin
const Factory = preload("res://scripts/factory.gd")
const Kit = preload("res://scripts/mesh_kit.gd")
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
	"gepaeckband": [["stil", "Bauart", ["oval", "karussell"]], ["gate", "Für Gate", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]]],
	"eingang": [["tuer", "Tür", ["schiebe", "dreh"]]],
	"sicherheit": [["fastlane", "Fast-Lane", [false, true]], ["technik", "Technik", ["klassisch", "ct", "express"]]],
	"gepaeckanlage": [["rutschen", "Make-up-Rutschen", [4, 6, 8, 2]]],
	"tuer": [["art", "Art", ["automatik", "fluegel", "personal"]]],
	"fluggastbruecke": [["steg", "Steg (m)", [0, 12, 20, 30]], ["oberdeck", "Oberdeck (A380)", [false, true]]],
	"baum": [["stil", "Baumart", ["laub", "nadel", "birke", "pappel", "obst"]]],
	"stand": [["markierung", "Markierung", ["eigene", "voll", "aus"]]],
	"busgarage": [["tore", "Tore (Größe)", [4, 5, 6, 8, 3, 2]]],
	"feuerwache": [["tore", "Tore (Größe)", [4, 5, 6, 3, 2]]],
	"gepaeckumschlag": [["tore", "Tore (Größe)", [4, 5, 6, 8, 3]]],
	"stand_aussen": [["markierung", "Markierung", ["eigene", "voll", "aus"]]],
	"stand_gross": [["markierung", "Markierung", ["eigene", "voll", "aus"]]],
	"stand_f": [["markierung", "Markierung", ["eigene", "voll", "aus"]]],
}
const OPTION_TEXT := {"glas": "Glas", "beton": "Beton", "holz": "Holz", "eckig": "eckig", "abgerundet": "abgerundet", "rund": "rund",
	"flach": "Flachdach", "gewoelbt": "Tonnendach", "shed": "Sheddach", "schengen": "Schengen", "non_schengen": "Non-Schengen",
	"grau": "Grau", "rot": "Rot", "blau": "Blau", "weiss": "Weiß", "klassisch": "klassisch", "modern": "modern",
	"cafe": "Café", "baeckerei": "Bäckerei", "bar": "Bar", "restaurant": "Restaurant", "kiosk": "Kiosk", "dutyfree": "Duty Free",
	"buecher": "Bücher", "elektronik": "Elektronik", "apotheke": "Apotheke", "mode": "Mode", "oval": "Oval", "karussell": "Karussell", "schiebe": "Schiebetür", "dreh": "Drehtür",
	"automatik": "Automatik (Glas)", "fluegel": "Flügeltür", "personal": "Personaltür",
	"voll": "aufgemalt (fest)", "eigene": "Rolllinien (änderbar)", "aus": "keine",
	"laub": "Laubbaum", "nadel": "Nadelbaum", "birke": "Birke", "pappel": "Pappel", "obst": "Obstbaum"}
var junction_controls: Dictionary = {}   # Kreuzung (gerundete Lage) -> rechts, vorfahrt, ampel
var satisfaction := 75.0
var satisfaction_factors: Array = []
var extra: Dictionary = {}       # Zustand weiterer Systeme (Wetter, Betrieb, Flotte) für den Spielstand
var atc_manual := false          # Lotsenmodus: Freigaben gibt der Spieler
var road_side := "gehweg"        # Querschnitt neuer Straßen (Catalog.SIDES)
var sandbox := false             # Sandkasten: Bauen kostet nichts, Geld ist unbegrenzt
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
	network_changed.connect(func() -> void: _routes_dirty = true)
	items_changed.connect(func() -> void: _routes_dirty = true)


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
	if sandbox and amount > 0:
		money_changed.emit(money)   # Sandkasten: Ausgaben werden nicht abgebucht
		return
	money -= amount
	money_changed.emit(money)


## Reicht das Geld? Im Sandkasten immer.
func can_afford(cost: int) -> bool:
	return sandbox or cost <= money


var income_cb: Callable          # Betrieb: Einnahmen nach Bereich zählen (Bereich, Betrag)


## Einnahme ohne Meldung (z. B. viele kleine Parkgebühren)
func earn_quiet(amount: int, cat: String = "Sonstiges") -> void:
	_spend(-amount)
	day_income += amount
	if income_cb.is_valid():
		income_cb.call(cat, amount)


func earn(amount: int, why: String, cat: String = "Sonstiges") -> void:
	_spend(-amount)
	day_income += amount
	if income_cb.is_valid():
		income_cb.call(cat, amount)
	toast.emit("+" + fmt_money(amount) + "  " + why)


## Spielzeit weiterlaufen lassen; um Mitternacht werden die laufenden Kosten abgebucht.
var night := 0.0       # 0 Tag, 1 Nacht (main.gd setzt es nach der Spieluhr)
var legacy_lights := false   # Spielstand von vor 0.10: Pistenbefeuerung ohne Befeuerungsstation
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
		total += float(line_cost(String(l["kind"]), l["samples"], String(l.get("side", "")))) * Catalog.UPKEEP_LINES
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

func line_cost(kind: String, samples: PackedVector3Array, side: String = "") -> int:
	var cpm: int = Catalog.LINES[kind]["cost_m"]
	if side != "" and Catalog.has_sides(kind):
		cpm += int(Catalog.SIDES[side]["cost_m"])
	return roundi(Spline.length(samples) * float(cpm) / 100.0) * 100


## Baut einen Weg durch die Klickpunkte. Prüft Kollisionen, räumt Bäume und Deko weg und legt
## bei Straßen Kreuzungen an (beide Straßen werden am Kreuzungspunkt geteilt).
## plain: ohne Prüfung und ohne Kreuzungen (Laden von Spielständen).
func build_line(kind: String, points: Array, free: bool = false, plain: bool = false, side: String = "") -> Dictionary:
	var def: Dictionary = Catalog.LINES[kind]
	var samples := line_samples(kind, points)
	if samples.size() < 2:
		return {}
	if Catalog.has_sides(kind) and not Catalog.SIDES.has(side):
		side = road_side
	var cost := 0 if free else line_cost(kind, samples, side)
	if not can_afford(cost):
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
	if Catalog.has_sides(kind):
		rec["side"] = side
	if Catalog.is_wall(kind):
		ensure_basement(hall_at(samples[0]), view_floor)
		rec["floor"] = view_floor
		(rec["node"] as Node3D).position.y = float(view_floor) * Catalog.FLOOR_H
		_apply_interior(rec["node"], true)
		if not wall_cuts(rec).is_empty() and not (rec.get("hall", {}) as Dictionary).is_empty():
			refresh_walls(rec["hall"], view_floor)
		_apply_visibility(rec)
	elif Catalog.is_floor_line(kind):
		# Kofferband: auf der gezeigten Ebene, wenn es in einer Halle liegt; Höhenverlauf und Wandöffnungen
		var fl := view_floor if interior_view and not hall_at(samples[0]).is_empty() else 0
		rec["floor"] = fl
		_reshape_belt(rec)
		_belt_walls()
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
	var keep_side := String(rec.get("side", ""))
	var kind: String = rec["kind"]
	var flip := bool(rec.get("flip", false))
	var order := [["strasse", false], ["strasse4", false], ["einbahn", false], ["einbahn", true]]
	var idx := 0
	for i in range(order.size()):
		if order[i][0] == kind and bool(order[i][1]) == flip:
			idx = i
	var nxt: Array = order[(idx + 1) % order.size()]
	return upgrade_line(rec, String(nxt[0]), bool(nxt[1]), keep_side)


## Welche Wegarten sich ineinander umbauen lassen (Ersetzen-Werkzeug wie in Städtebauspielen)
const UPGRADE_FAMILY := {"strasse": "strasse", "strasse4": "strasse", "einbahn": "strasse",
	"rollweg": "rollweg", "rollweg_breit": "rollweg"}


## Kosten des Umbaus (positiv: zahlen, negativ: Erstattung der halben Differenz).
func upgrade_cost(rec: Dictionary, new_kind: String, side: String = "") -> int:
	var samples: PackedVector3Array = rec["samples"]
	var old_side := String(rec.get("side", ""))
	if side == "":
		side = old_side
	var diff := line_cost(new_kind, samples, side) - line_cost(String(rec["kind"]), samples, old_side)
	return diff if diff > 0 else -int(float(-diff) * 0.5)


## Prüft, ob ein Weg zu new_kind umgebaut werden kann ("" = ja, sonst der Grund).
func can_upgrade(rec: Dictionary, new_kind: String, flip: bool = false, side: String = "") -> String:
	var kind: String = rec.get("kind", "")
	if not UPGRADE_FAMILY.has(kind) or UPGRADE_FAMILY.get(new_kind, "") != UPGRADE_FAMILY[kind]:
		return "Lässt sich nicht in " + Catalog.label(new_kind) + " umbauen"
	if side == "" or not Catalog.has_sides(new_kind):
		side = String(rec.get("side", ""))
	if kind == new_kind and flip == bool(rec.get("flip", false)) and side == String(rec.get("side", "")):
		return "Ist schon " + Catalog.label(kind)
	var extra := upgrade_cost(rec, new_kind, side)
	if not can_afford(extra):
		return "Nicht genug Geld: " + fmt_money(extra) + " nötig"
	# breiterer Weg darf nicht in Gebäude ragen (Deko wird weggeräumt)
	var w: float = Catalog.LINES[new_kind]["width"]
	if w <= float(Catalog.LINES[kind]["width"]) + 0.01:
		return ""
	var samples: PackedVector3Array = rec["samples"]
	for it: Dictionary in items:
		var id: String = it["id"]
		if Catalog.is_inside(id) or Catalog.is_marker(id) or id in DECOR:
			continue
		var on := String(Catalog.ITEMS[id].get("on", ""))
		if on == kind or on == new_kind:
			continue
		var r: Rect2 = (it["rect"] as Rect2).grow(w * 0.5 - 0.25)
		for i in range(0, samples.size(), 2):
			if r.has_point(Vector2(samples[i].x, samples[i].z)):
				return "Zu breit: stößt an " + Catalog.label(id)
	return ""


## Baut einen Weg an Ort und Stelle um (andere Spuren, Breite oder Richtung), Verlauf und Anschlüsse bleiben.
func upgrade_line(rec: Dictionary, new_kind: String, flip: bool = false, side: String = "") -> String:
	var why := can_upgrade(rec, new_kind, flip, side)
	if why != "":
		return why
	if side == "" or not Catalog.has_sides(new_kind):
		side = String(rec.get("side", ""))
	var samples: PackedVector3Array = rec["samples"]
	var extra := upgrade_cost(rec, new_kind, side)
	var w: float = Catalog.LINES[new_kind]["width"]
	var removed := false
	for it: Dictionary in items.duplicate():
		if not (String(it["id"]) in DECOR):
			continue
		var r: Rect2 = (it["rect"] as Rect2).grow(w * 0.5 - 0.25)
		for i in range(0, samples.size(), 2):
			if r.has_point(Vector2(samples[i].x, samples[i].z)):
				_remove_one(it, 0.0)
				removed = true
				break
	if removed:
		items_changed.emit()
	var node: Variant = rec["node"]
	if is_instance_valid(node):
		(node as Node).queue_free()
	var mesh := Factory.make_line(new_kind, samples, float(rec.get("y", 0.06)))
	line_root.add_child(mesh)
	rec["node"] = mesh
	rec["kind"] = new_kind
	rec["flip"] = flip
	if Catalog.has_sides(new_kind):
		rec["side"] = side
	rec["bounds"] = Spline.bounds(samples, w * 0.5)
	rec["cost"] = maxi(0, int(rec["cost"]) + extra)
	_spend(extra)
	_apply_visibility(rec)
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
		if Catalog.utility_of(k) != "" or Catalog.is_floor_line(k):
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
	if Catalog.utility_of(kind) != "" or Catalog.is_floor_line(kind) or samples.size() < 2:
		return out
	if Catalog.is_marking(kind):
		# Rollführungslinie: nur auf Vorfeld oder Rollweg, darf alles kreuzen
		for i in range(0, samples.size(), 2):
			if not _on_pavement(samples[i]):
				out["why"] = "Rolllinien nur auf Vorfeld und Rollwegen zeichnen"
				return out
		return out
	var w: float = Catalog.LINES[kind]["width"]
	var bounds := Spline.bounds(samples, w * 0.5)
	var step := 2 if w > 20.0 else 1
	# Gebäude und Deko
	for it: Dictionary in items:
		var id: String = it["id"]
		if Catalog.is_inside(id) or Catalog.is_marker(id):
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
					if Catalog.is_marking(String(l["kind"])):
						continue
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
	for key: String in ["flip", "side"]:
		if l.has(key):
			ra[key] = l[key]
			rb[key] = l[key]
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
	if Catalog.is_floor_line(kind):
		node.visible = floor_shown(floor_of(l))
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


var lod_far := false        # weit herausgezoomt: Einrichtung unter den Dächern ausblenden (Leistung)


func set_lod_far(on: bool) -> void:
	lod_far = on
	for it: Dictionary in items:
		if Catalog.is_inside(String(it["id"])):
			_apply_floor(it)


var wall_mode := "halb"     # Innenansicht: Wände "voll", "halb" oder "aus" (Taste H)
var section_view := false    # Innenansicht: alle Ebenen bis zur gezeigten übereinander (Taste J)
signal view_mode_changed


func cycle_wall_mode() -> String:
	var order := ["halb", "voll", "aus"]
	wall_mode = order[(order.find(wall_mode) + 1) % order.size()]
	_refresh_view()
	return wall_mode


func set_section_view(on: bool) -> void:
	section_view = on
	_refresh_view()


func _refresh_view() -> void:
	for it: Dictionary in items:
		_apply_floor(it)
	for l: Dictionary in lines:
		_apply_visibility(l)
		if Catalog.is_wall(String(l["kind"])):
			_apply_interior(l["node"], true)
	view_mode_changed.emit()


## Halle oder Wand für die Innenansicht: Dach und hohe Fassade weg, niedrige Fassade auf der gezeigten Ebene.
## Wandansicht "voll" zeigt Innenwände in ganzer Höhe, "aus" blendet sie ganz aus.
func _apply_interior(n: Node3D, wall: bool = false) -> void:
	for part: String in ["Dach", "Hoch"]:
		var c := n.get_node_or_null(part) as Node3D
		if c != null:
			c.visible = not interior_view or (wall and part == "Hoch" and wall_mode == "voll")
	var low := n.get_node_or_null("Tief") as Node3D
	var own := n.get_node_or_null("TiefE%d" % view_floor) as Node3D if view_floor >= 1 else null
	if low != null:
		low.visible = interior_view and view_floor >= 0 and not (wall and wall_mode == "aus") and own == null
		if not wall:
			low.position.y = float(maxi(view_floor, 0)) * Catalog.FLOOR_H
	if not wall:
		for f in range(1, 8):
			var te := n.get_node_or_null("TiefE%d" % f) as Node3D
			if te != null:
				te.visible = interior_view and te == own
			var tr := n.get_node_or_null("Terrasse%d" % (f - 1)) as Node3D
			if tr != null:
				tr.visible = not interior_view or view_floor >= f
	for f in range(-1, 4):
		var slab := n.get_node_or_null("Ebene%d" % f) as Node3D
		if slab != null:
			slab.visible = (not interior_view and f >= 0) or (interior_view and f <= view_floor and (f >= 0 or view_floor <= 0) \
				and (not section_view or f == _lowest_floor(n)))


# ---------------------------------------------------------------- Ebenen und Bauformen

static func floor_of(rec: Dictionary) -> int:
	return int(rec.get("floor", 0))


## Schnittansicht: Ebene f ist zu sehen (die gezeigte und alle darunter bis zum Erdgeschoss bzw. Keller).
func floor_shown(f: int) -> bool:
	if not interior_view:
		return f >= 0
	if section_view:
		return f <= view_floor and (f >= 0 or view_floor < 0)
	return f == view_floor


static func _lowest_floor(n: Node3D) -> int:
	return -1 if n.get_node_or_null("Ebene-1") != null else 0


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


## Kosten, um einer Halle einen Keller zu geben (0, wenn sie schon einen hat).
func basement_cost(h: Dictionary) -> int:
	if h.is_empty() or hall_basement(h):
		return 0
	return int((h["rect"] as Rect2).get_area() * float(Catalog.ITEMS["halle"]["cost_m2"]) * 0.6)


## Wird im Untergeschoss gebaut und die Halle hat noch keinen Keller, wird er mit angelegt.
func ensure_basement(h: Dictionary, f: int) -> String:
	if f >= 0 or h.is_empty() or hall_basement(h):
		return ""
	var c := basement_cost(h)
	var why := cycle_option(h, "keller", 1)
	if why == "":
		toast.emit("Keller unter der Halle angelegt (%s)" % fmt_money(c))
	return why


## Umriss einer Ebene in Weltkoordinaten (Obergeschosse können kleiner sein als das Erdgeschoss).
func floor_rect(h: Dictionary, f: int) -> Rect2:
	var r: Rect2 = h["rect"]
	if f <= 0:
		return r
	var loc: Array = Factory.floor_rects(r.size.x, r.size.y, h.get("opts", {}), hall_levels(h))
	if f >= loc.size():
		return r
	var l: Rect2 = loc[f]
	return Rect2(r.get_center() + l.position, l.size)


## Rechteck einer Geschossfläche aus zwei Eckpunkten (2-m-Raster).
static func storey_rect(a: Vector3, b: Vector3) -> Rect2:
	return apron_rect(a, b)


## Prüft einen neuen Umriss für Ebene f der Halle h. Leer = ok.
func storey_problem(h: Dictionary, f: int, r: Rect2) -> String:
	if h.is_empty():
		return "Nur über einer Terminalhalle"
	if f < 1 or f >= hall_levels(h):
		return "Geschossfläche nur für Obergeschosse: in der Innenansicht ein Obergeschoss wählen"
	if r.size.x < 10.0 or r.size.y < 10.0:
		return "Mindestens 10 × 10 m"
	var below := floor_rect(h, f - 1)
	if not below.grow(0.05).encloses(r):
		return "Ein Obergeschoss darf nicht über das Geschoss darunter hinausragen"
	for it: Dictionary in inside_of(h):
		var itf := floor_of(it)
		var top := itf + (1 if _two_floors(String(it["id"])) else 0)
		if top >= f and not r.grow(0.05).encloses(it["rect"]):
			return "Außerhalb liegt noch Einrichtung (%s im %s)" % [Catalog.label(String(it["id"])), floor_name(maxi(itf, f))]
	for l: Dictionary in walls_of(h):
		if floor_of(l) >= f:
			for v: Vector3 in l["samples"]:
				if not r.grow(0.3).has_point(Vector2(v.x, v.z)):
					return "Außerhalb steht noch eine Wand im %s" % floor_name(floor_of(l))
	return ""


func _storey_area(h: Dictionary) -> float:
	var a := 0.0
	for f in range(1, hall_levels(h)):
		a += floor_rect(h, f).get_area()
	return a


## Setzt den Umriss von Ebene f (und kürzt die Ebenen darüber auf diesen Umriss).
func set_storey(h: Dictionary, f: int, r: Rect2) -> String:
	var why := storey_problem(h, f, r)
	if why != "":
		return why
	var hr: Rect2 = h["rect"]
	var c := hr.get_center()
	var o: Dictionary = h.get("opts", {}).duplicate(true)
	var eb: Dictionary = o.get("ebenen", {})
	var full := r.grow(0.05).encloses(floor_rect(h, f - 1))
	eb[str(f)] = [r.position.x - c.x, r.position.y - c.y, r.end.x - c.x, r.end.y - c.y]
	for g in range(f + 1, hall_levels(h)):
		if eb.has(str(g)):
			var a: Array = eb[str(g)]
			var cur := Rect2(float(a[0]) + c.x, float(a[1]) + c.y, float(a[2]) - float(a[0]), float(a[3]) - float(a[1])).intersection(r)
			if cur.size.x < 10.0 or cur.size.y < 10.0:
				eb.erase(str(g))
			else:
				eb[str(g)] = [cur.position.x - c.x, cur.position.y - c.y, cur.end.x - c.x, cur.end.y - c.y]
	if full:
		eb.erase(str(f))
	# Kosten nach Geschossfläche: kleiner wird erstattet (halber Preis), größer kostet wie neu
	var before := _storey_area(h)
	var old_o: Dictionary = h.get("opts", {})
	o["ebenen"] = eb
	h["opts"] = o
	var delta := int((_storey_area(h) - before) * float(Catalog.ITEMS["halle"]["cost_m2"]) * 0.8)
	if delta > 0 and not can_afford(delta):
		h["opts"] = old_o
		return "Nicht genug Geld: " + fmt_money(delta) + " nötig"
	_spend(delta if delta > 0 else delta / 2)
	_rebuild_node(h)
	items_changed.emit()
	toast.emit("%s: %d × %d m" % [floor_name(f), roundi(r.size.x), roundi(r.size.y)])
	return ""


## Fehlertext für eine Ebene der Halle (Keller wird bei Bedarf angelegt, wenn das Geld reicht).
## Mit r: liegt das Rechteck auch innerhalb des Umrisses dieser Ebene?
func floor_problem(h: Dictionary, f: int, extra: int = 0, r: Rect2 = Rect2()) -> String:
	if f >= hall_levels(h):
		return "Diese Halle hat kein %s (Ebenen im Infofeld der Halle einstellen)" % floor_name(f)
	if f >= 1 and r.size != Vector2.ZERO and not floor_rect(h, f).grow(0.05).encloses(r):
		return "Außerhalb der Geschossfläche des %s" % floor_name(f)
	if f < 0 and not hall_basement(h) and not can_afford(basement_cost(h) + extra):
		return "Für den Keller fehlt Geld: %s nötig" % fmt_money(basement_cost(h) + extra)
	return ""


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
		# Verbinder (Rolltreppe, Treppe, Aufzug, Gepäcklift) reichen in die Ebene darüber
		var both := _two_floors(String(it["id"])) and f + 1 == view_floor
		node.visible = (floor_shown(f) or both) if interior_view else (f >= 0 and not lod_far)
	else:
		node.visible = not (interior_view and view_floor < 0)
		# Hallen mit abnehmbarem Dach (Garagen, Feuerwache, Gepäckumschlag): in der Innenansicht offen
		var roof := node.get_node_or_null("Dach") as Node3D
		if roof != null:
			roof.visible = not interior_view


func floor_name(f: int) -> String:
	return "Untergeschoss" if f < 0 else ("Erdgeschoss" if f == 0 else "%d. Obergeschoss" % f)


## Einstellungen eines Gebäudes für das Infofeld: [Schlüssel, Name, Wert als Text]
func options_of(rec: Dictionary) -> Array:
	var out := []
	for e: Array in OPTIONS.get(String(rec.get("id", "")), []):
		var v: Variant = opt(rec, e[0])
		var txt: String = str(v) if typeof(v) == TYPE_INT else String(OPTION_TEXT.get(v, str(v)))
		if e[0] == "gate":
			txt = "alle Gates" if int(v) == 0 else "Gate %d" % int(v)
		if e[0] == "tore":
			var sz := Catalog.size_of(String(rec["id"]), rec.get("opts", {}))
			txt = ("alte Größe" if int(v) == 0 else "%d Tore" % int(v)) + " · %d × %d m" % [roundi(sz.x), roundi(sz.y)]
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
	if typeof(cur) == TYPE_FLOAT and typeof(values[0]) == TYPE_INT:
		cur = int(cur)
	var i := values.find(cur)
	var v: Variant = values[(i + dir + values.size()) % values.size()]
	var cost := 0
	var move_to: Array = []
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
			# neue Ebenen erben den Umriss der obersten Ebene
			cost = int(floor_rect(rec, hall_levels(rec) - 1).get_area() * float(Catalog.ITEMS["halle"]["cost_m2"]) * 0.8) * (n - hall_levels(rec))
		if key == "keller":
			if not bool(v):
				for it: Dictionary in inside_of(rec):
					if floor_of(it) < 0:
						return "Erst die Einrichtung im Keller abreißen"
			cost = int(area * float(Catalog.ITEMS["halle"]["cost_m2"]) * 0.6) * (1 if bool(v) else -1)
	if rec["id"] == "parkhaus" and key == "etagen":
		cost = 70000 * (int(v) - int(cur))
	if Catalog.SIZED.has(String(rec["id"])) and key == "tore":
		# neue Größe: gleiche Mitte, alles andere muss Platz lassen
		var no: Dictionary = (rec.get("opts", {}) as Dictionary).duplicate()
		no["tore"] = v
		var nr := footprint(String(rec["id"]), rec["pos"], int(rec["rot"]), no)
		for it: Dictionary in items:
			if it != rec and not Catalog.is_inside(String(it["id"])) and not Catalog.is_marker(String(it["id"])) \
					and nr.grow(-0.05).intersects(it["rect"]):
				return "Kein Platz für diese Größe: " + Catalog.label(String(it["id"]))
		var why_l := _rect_on_lines(nr, "")
		if why_l != "":
			return "Kein Platz für diese Größe: " + why_l
		var old_a := (rec["rect"] as Rect2).get_area()
		cost = int((nr.get_area() - old_a) * float(Catalog.ITEMS[rec["id"]]["cost"]) / maxf(Catalog.size_of(String(rec["id"]), {}).x * Catalog.size_of(String(rec["id"]), {}).y, 1.0))
		move_to = [rec["pos"], nr]
	if rec["id"] == "gepaeckanlage" and key == "rutschen":
		cost = 30000 * (int(v) - int(cur))
	if rec["id"] == "sicherheit" and key == "technik":
		var price := {"klassisch": 0, "ct": 120000, "express": 260000}
		cost = int(price.get(String(v), 0)) - int(price.get(String(cur), 0))
	if rec["id"] == "fluggastbruecke" and key == "oberdeck":
		cost = 60000 if bool(v) else -60000
	if rec["id"] == "fluggastbruecke" and key == "steg":
		# Rotunde nach außen verschieben; der Steg darf über Straßen und Betriebsstraßen gehen
		var anchor := bridge_anchor(rec)
		var np := anchor + bridge_normal(rec) * float(int(v))
		var nr := footprint("fluggastbruecke", np, int(rec["rot"]))
		for it: Dictionary in items:
			if it != rec and not Catalog.is_inside(String(it["id"])) and not String(it["id"]).begins_with("stand") \
					and nr.grow(-0.05).intersects(it["rect"]):
				return "Die Rotunde stößt dort an: " + Catalog.label(String(it["id"]))
		var on_line := _rect_on_lines(nr, "vorfeld")
		if on_line != "":
			return "Die Rotunde stünde auf einem Weg – anderen Steg wählen"
		cost = 9000 * (int(v) - int(cur))
		move_to = [np, nr]
	if not can_afford(cost):
		return "Nicht genug Geld: " + fmt_money(cost) + " nötig"
	if not move_to.is_empty():
		rec["pos"] = move_to[0]
		rec["rect"] = move_to[1]
		(rec["node"] as Node3D).position = move_to[0]
	if not rec.has("opts"):
		rec["opts"] = {}
	var was: Variant = rec["opts"].get(key, cur)
	rec["opts"][key] = v
	if key == "markierung" and String(was) == "voll" and String(v) != "voll" and stand_lines(rec).is_empty():
		# die aufgemalten Einrolllinien werden zu echten Rolllinien, die man ändern kann
		if make_leadins(rec) > 0:
			network_changed.emit()
			toast.emit("Einrolllinien als Rolllinien angelegt (lassen sich ändern und abreißen)")
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
		rec["cuts"] = facade_cuts(rec)
		rec["holes"] = slab_holes(rec)
		node = Factory.make_hall(r.size.x, r.size.y, rec.get("opts", {}), rec["cuts"], rec["holes"])
	else:
		node = Factory.make_item(String(rec["id"]), rec.get("opts", {}))
	node.transform = old.transform
	item_root.add_child(node)
	old.queue_free()
	rec["node"] = node
	_apply_floor(rec)


# ---------------------------------------------------------------- Gebäude und Deko

func footprint(id: String, pos: Vector3, rot: int, opts: Dictionary = {}) -> Rect2:
	var s: Vector2 = Catalog.size_of(id, opts)
	if rot % 2 == 1:
		s = Vector2(s.y, s.x)
	return Rect2(pos.x - s.x * 0.5, pos.z - s.y * 0.5, s.x, s.y)


## Liegt p auf Vorfeld oder Rollweg (für Rollführungslinien)?
func _on_pavement(p: Vector3) -> bool:
	for k: String in ["vorfeld", "rollweg", "rollweg_breit"]:
		if _on_kind(p, k):
			return true
	return false


func _on_kind(p: Vector3, kind: String) -> bool:
	if kind == "vorfeld":
		for a: Dictionary in items_of("vorfeldflaeche"):
			if (a["rect"] as Rect2).has_point(Vector2(p.x, p.z)):
				return true
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
# ---------------------------------------------------------------- Vorfeld als Fläche

const APRON_OK := ["flutlicht", "rollhalt", "papi", "bushalt", "fluggastbruecke", "stand", "stand_aussen", "stand_gross", "stand_f"]


static func apron_rect(a: Vector3, b: Vector3) -> Rect2:
	var x0 := snappedf(minf(a.x, b.x), 2.0)
	var z0 := snappedf(minf(a.z, b.z), 2.0)
	var x1 := snappedf(maxf(a.x, b.x), 2.0)
	var z1 := snappedf(maxf(a.z, b.z), 2.0)
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func apron_cost(r: Rect2) -> int:
	return roundi(r.get_area() * float(Catalog.ITEMS["vorfeldflaeche"]["cost_m2"]) / 100.0) * 100


func can_place_apron(r: Rect2) -> String:
	if r.size.x < 10.0 or r.size.y < 10.0:
		return "Mindestens 10 × 10 m"
	if not on_map(Vector3(r.position.x, 0, r.position.y)) or not on_map(Vector3(r.end.x, 0, r.end.y)):
		return "Außerhalb der Karte"
	var inner := r.grow(-0.05)
	for it: Dictionary in items:
		var id := String(it["id"])
		if Catalog.is_inside(id) or id == "vorfeldflaeche" or id in APRON_OK or Catalog.is_marker(id) or id in DECOR:
			continue
		if inner.intersects(it["rect"]):
			return "Hier steht schon etwas: " + Catalog.label(id)
	if not can_afford(apron_cost(r)):
		return "Nicht genug Geld: " + fmt_money(apron_cost(r)) + " nötig"
	return ""


func build_apron(r: Rect2, free: bool = false) -> Dictionary:
	var c := r.get_center()
	var rec := build_item("vorfeldflaeche", Vector3(c.x, 0, c.y), 0, true, {"w": r.size.x, "d": r.size.y})
	if rec.is_empty():
		return rec
	if not free:
		var cost := apron_cost(r)
		_spend(cost)
		rec["cost"] = cost
	network_changed.emit()
	return rec


static func hall_rect(a: Vector3, b: Vector3) -> Rect2:
	var g: float = Catalog.ITEMS["halle"]["grid"]
	var x0 := snappedf(minf(a.x, b.x), g)
	var z0 := snappedf(minf(a.z, b.z), g)
	var x1 := snappedf(maxf(a.x, b.x), g)
	var z1 := snappedf(maxf(a.z, b.z), g)
	return Rect2(x0, z0, x1 - x0, z1 - z0)


func _rect_on_lines(r: Rect2, on: String) -> String:
	var hit := _lines_hit(r, on, true)
	return "" if hit.is_empty() else "Liegt auf einem Weg: " + Catalog.label(String((hit[0] as Dictionary)["kind"]))


## Wege, auf denen das Rechteck liegt (beim Verschieben zählen Wege nicht, auf denen es schon vorher lag).
func _lines_hit(r: Rect2, on: String, first: bool = false) -> Array:
	var out := []
	for l: Dictionary in lines:
		var kind: String = l["kind"]
		if kind == "gehweg" or kind == on or Catalog.utility_of(kind) != "" or Catalog.is_floor_line(kind) or Catalog.is_marking(kind):
			continue
		var b: Rect2 = l["bounds"]
		if not b.intersects(r):
			continue
		var w: float = Catalog.LINES[kind]["width"]
		var grown := r.grow(w * 0.5 - 0.3)
		var old := _skip_rect.grow(w * 0.5 - 0.3) if _skip_rect.size != Vector2.ZERO else Rect2()
		var s: PackedVector3Array = l["samples"]
		for i in range(0, s.size(), 2):
			if Catalog.covered(kind, s[i]):
				continue
			var q := Vector2(s[i].x, s[i].z)
			if grown.has_point(q) and not old.has_point(q):
				out.append(l)
				break
		if first and not out.is_empty():
			return out
	return out


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


const BRIDGE_OFF := 4.8   # Mitte der Rotunde vor der Fassade (Treppenturm liegt dazwischen)


## Außennormale einer Brücke (zeigt von der Fassade weg).
static func bridge_normal(rec: Dictionary) -> Vector3:
	return Basis(Vector3.UP, float(rec["rot"]) * PI * 0.5) * Vector3(0, 0, 1)


## Wo die Brücke ohne Steg stünde (am Treppenturm vor der Fassade). Mit Steg steht die Rotunde
## weiter draußen, z. B. jenseits einer Straße.
func bridge_anchor(rec: Dictionary) -> Vector3:
	var steg := float(int(opt(rec, "steg")))
	return (rec["pos"] as Vector3) - bridge_normal(rec) * steg

## Fluggastbrücke einrasten: bündig vor die nächste Außenwand, auf Höhe eines Gates innen,
## sonst im 1-m-Raster. Rückgabe [Lage, Drehung] oder leer.
func bridge_snap(p: Vector3) -> Array:
	var hs := hall_side(p)
	if hs.is_empty():
		return []
	var hall: Dictionary = hs[0]
	var n: Vector3 = hs[1]
	var c: Vector3 = hs[2]
	var r: Rect2 = hall["rect"]
	var along := Vector3(-n.z, 0, n.x)
	var t := snappedf(c.dot(along), 1.0)
	var best := 9.0
	for g: Dictionary in inside_of(hall):
		if not (g["id"] in ["gate", "busgate"]) or floor_of(g) != 0:
			continue
		var gp: Vector3 = g["pos"]
		if Vector2(gp.x - c.x, gp.z - c.z).dot(Vector2(n.x, n.z)) < -16.0:
			continue
		var d := absf(gp.dot(along) - c.dot(along))
		if d < best:
			best = d
			t = gp.dot(along)
	# auf der Wand bleiben (Ecken frei lassen)
	var lo: float
	var hi: float
	if absf(n.x) > 0.5:
		lo = r.position.y + 3.0
		hi = r.end.y - 3.0
	else:
		lo = r.position.x + 3.0
		hi = r.end.x - 3.0
	var sgn := along.x + along.z
	t = clampf(t * sgn, lo, hi) * sgn
	var wall_pt := c - along * c.dot(along) + along * t
	return [Vector3(wall_pt.x, 0, wall_pt.z) + n * BRIDGE_OFF, rot_for_normal(n)]


## Pisten als [Anfang, Ende] (Mittellinie).
func runway_list() -> Array:
	var out := []
	for l: Dictionary in lines:
		if l["kind"] == "piste":
			var sm: PackedVector3Array = l["samples"]
			out.append([Vector3(sm[0].x, 0, sm[0].z), Vector3(sm[sm.size() - 1].x, 0, sm[sm.size() - 1].z)])
	return out


static func seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()


func runway_dist(p: Vector3) -> float:
	var best := INF
	for r: Array in runway_list():
		best = minf(best, seg_dist(p, r[0], r[1]))
	return best


## Rolltor: bündig an die nächste Außenwand einer Halle (bis 4 m), Vorderseite (+Z) nach draußen,
## entlang der Wand im 1-m-Raster. Gibt [Mitte, Drehung] oder [] zurück.
func wall_snap(id: String, p: Vector3) -> Array:
	var size: Vector2 = Catalog.ITEMS[id]["size"]
	var best: Array = []
	var bd := 4.0
	for h: Dictionary in items_of("halle"):
		var r: Rect2 = h["rect"]
		if not r.grow(4.0).has_point(Vector2(p.x, p.z)):
			continue
		var hx := size.x * 0.5
		var hz := size.y * 0.5
		# [Abstand, Mitte, Drehung]
		var cand := [
			[absf(p.z - r.end.y), Vector3(clampf(snappedf(p.x, 1.0), r.position.x + hx, r.end.x - hx), 0, r.end.y - hz), 0],
			[absf(p.x - r.end.x), Vector3(r.end.x - hz, 0, clampf(snappedf(p.z, 1.0), r.position.y + hx, r.end.y - hx)), 1],
			[absf(p.z - r.position.y), Vector3(clampf(snappedf(p.x, 1.0), r.position.x + hx, r.end.x - hx), 0, r.position.y + hz), 2],
			[absf(p.x - r.position.x), Vector3(r.position.x + hz, 0, clampf(snappedf(p.z, 1.0), r.position.y + hx, r.end.y - hx)), 3]]
		for c: Array in cand:
			if float(c[0]) < bd:
				bd = float(c[0])
				best = [c[1], c[2]]
	return best


## Haltestelle, Taxistand, Kiss & Fly: an den Straßenrand einrasten, Vorderseite zur Straße, so dass
## die Haltebucht vor dem Bauteil liegt. Nur an geraden, achsparallelen Stellen (Bauteile drehen in
## 90-Grad-Schritten). Gibt [Mitte, Drehung] oder [] zurück.
func stop_snap(id: String, p: Vector3) -> Array:
	var best_d := 26.0
	var hit: Array = []
	for l: Dictionary in lines:
		var kind: String = l["kind"]
		if not Catalog.has_sides(kind):
			continue
		if not (l["bounds"] as Rect2).grow(26.0).has_point(Vector2(p.x, p.z)):
			continue
		var smp: PackedVector3Array = l["samples"]
		for i in range(1, smp.size() - 1):
			var d := Vector2(smp[i].x - p.x, smp[i].z - p.z).length()
			if d < best_d:
				best_d = d
				hit = [l, i]
	if hit.is_empty():
		return []
	var rec: Dictionary = hit[0]
	var smp: PackedVector3Array = rec["samples"]
	var i: int = hit[1]
	var t := smp[mini(i + 2, smp.size() - 1)] - smp[maxi(i - 2, 0)]
	t.y = 0.0
	if t.length() < 0.01:
		return []
	t = t.normalized()
	var nrm := t.cross(Vector3.UP)
	var q := smp[i] + t * (p - smp[i]).dot(t)
	if (p - q).dot(nrm) < 0.0:
		nrm = -nrm
	var best_r := -1
	var best_dot := 0.94
	for r in range(4):
		var front := Basis(Vector3.UP, float(r) * PI * 0.5) * Vector3(0, 0, -1)
		var dt := front.dot(-nrm)
		if dt > best_dot:
			best_dot = dt
			best_r = r
	if best_r < 0:
		return []
	var depth: float = (Catalog.ITEMS[id]["size"] as Vector2).y
	var hw: float = float(Catalog.LINES[rec["kind"]]["width"]) * 0.5
	var c := q + nrm * (hw + 3.0 + depth * 0.5)
	# entlang der Straße auf ganze Meter, quer exakt an der Bucht
	var axis := Vector3(1, 0, 0) if absf(t.x) > absf(t.z) else Vector3(0, 0, 1)
	var along := snappedf(c.dot(axis), 1.0)
	c = Vector3(along if axis.x > 0.5 else c.x, 0.0, along if axis.z > 0.5 else c.z)
	return [c, best_r]


## Vorfeld-Haltestelle als Bucht am Rand einer Betriebsstraße: [Lage, Drehung] oder leer.
## Die Haltekante (lokal -Z) liegt an der Straße, der Bus hält in der Bucht neben der Fahrspur.
func apron_bay_snap(id: String, p: Vector3) -> Array:
	var best_d := 24.0
	var hit: Array = []
	for l: Dictionary in lines:
		if l["kind"] != "betriebsstrasse":
			continue
		if not (l["bounds"] as Rect2).grow(24.0).has_point(Vector2(p.x, p.z)):
			continue
		var smp: PackedVector3Array = l["samples"]
		for i in range(1, smp.size() - 1):
			var d := Vector2(smp[i].x - p.x, smp[i].z - p.z).length()
			if d < best_d:
				best_d = d
				hit = [l, i]
	if hit.is_empty():
		return []
	var rec: Dictionary = hit[0]
	var smp: PackedVector3Array = rec["samples"]
	var i: int = hit[1]
	var t := smp[mini(i + 2, smp.size() - 1)] - smp[maxi(i - 2, 0)]
	t.y = 0.0
	if t.length() < 0.01:
		return []
	t = t.normalized()
	var nrm := t.cross(Vector3.UP)
	var q := smp[i] + t * (p - smp[i]).dot(t)
	if (p - q).dot(nrm) < 0.0:
		nrm = -nrm
	var best_r := -1
	var best_dot := 0.94
	for r in range(4):
		var front := Basis(Vector3.UP, float(r) * PI * 0.5) * Vector3(0, 0, -1)
		var dt := front.dot(-nrm)
		if dt > best_dot:
			best_dot = dt
			best_r = r
	if best_r < 0:
		return []
	var depth: float = (Catalog.ITEMS[id]["size"] as Vector2).y
	var hw: float = float(Catalog.LINES["betriebsstrasse"]["width"]) * 0.5
	var c := q + nrm * (hw + depth * 0.5 - 0.3)
	return [Vector3(c.x, 0.0, c.z), best_r]


## Befeuerung und Markierungen einrasten. Rückgabe [Lage, Drehung] oder leer.
## pistenende: 12 m vor einer Schwelle in Pistenrichtung. papi: links neben dem Aufsetzpunkt.
## rollweg: auf die Mittellinie des nächsten Rollwegs.
const PAD_AT := 32.0   # Wendekreis: Mitte so weit hinter der Schwelle


## Seitlicher Abstand der Außenkante der Wendespur von der Pistenmitte (Durchmesser des Wendekreises).
static func pad_width() -> float:
	return float(Catalog.LINES["piste"]["width"]) * 0.5 + 24.0


func marker_snap(id: String, p: Vector3) -> Array:
	var mode := String(Catalog.ITEMS[id].get("marker", ""))
	var hw := float(Catalog.LINES["piste"]["width"]) * 0.5
	if mode == "pistenende" or mode == "papi":
		var best: Array = []
		var bd := 700.0 if mode == "pistenende" else 400.0
		for r: Array in runway_list():
			for e in range(2):
				var thr: Vector3 = r[e]
				var other: Vector3 = r[1 - e]
				var inward := (other - thr).normalized()
				var q: Vector3
				if mode == "pistenende":
					q = thr - inward * 12.0
				else:
					var length := thr.distance_to(other)
					var aim := 400.0 if length >= 2400.0 else 300.0 if length >= 1500.0 else 250.0
					var left := Vector3.UP.cross(inward).normalized()
					q = thr + inward * aim + left * (hw + 28.0)
				var d := Vector2(q.x - p.x, q.z - p.z).length()
				if d < bd:
					bd = d
					best = [q, rot_for_normal(-inward if mode == "pistenende" else inward)]
		return best
	if mode == "wende":
		# Wendeplatte: Mitte des Wendekreises neben dem Pistenende, Seite nach dem Mauszeiger
		var best3: Array = []
		var bd3 := 500.0
		for r: Array in runway_list():
			for e in range(2):
				var thr: Vector3 = r[e]
				var inward := ((r[1 - e] as Vector3) - thr).normalized()
				var lat := inward.cross(Vector3.UP).normalized()
				var side := 1.0 if (p - thr).dot(lat) >= 0.0 else -1.0
				var q := thr + inward * PAD_AT + lat * side * pad_width() * 0.5
				var d := Vector2(q.x - p.x, q.z - p.z).length()
				if d < bd3:
					bd3 = d
					best3 = [q, rot_for_normal(-inward)]
		return best3
	if mode == "rollweg":
		var best2: Array = []
		var bd2 := 14.0
		for l: Dictionary in lines:
			if not (l["kind"] in ["rollweg", "rollweg_breit"]):
				continue
			var sm: PackedVector3Array = l["samples"]
			for i in range(sm.size()):
				var d := Vector2(sm[i].x - p.x, sm[i].z - p.z).length()
				if d < bd2:
					bd2 = d
					var t := sm[mini(i + 1, sm.size() - 1)] - sm[maxi(i - 1, 0)]
					t.y = 0.0
					best2 = [Vector3(sm[i].x, 0, sm[i].z), rot_for_normal(t.normalized())]
		return best2
	return []


## Öffnungen in der Außenwand einer Halle (Erdgeschoss): Eingänge und Brückenköpfe.
## Je Öffnung [Mitte lokal (Vector2), Breite, Höhe].
func facade_cuts(hall: Dictionary) -> Array:
	var out := []
	var hr: Rect2 = hall["rect"]
	var cen := hr.get_center()
	for it: Dictionary in inside_of(hall):
		if not (it["id"] in ["eingang", "rolltor"]) or floor_of(it) != 0:
			continue
		var r: Rect2 = it["rect"]
		var d := [r.position.x - hr.position.x, hr.end.x - r.end.x, r.position.y - hr.position.y, hr.end.y - r.end.y]
		var m := 0
		for i in range(4):
			if float(d[i]) < float(d[m]):
				m = i
		var rc := r.get_center() - cen
		var oh := 3.35 if it["id"] == "eingang" else 4.05
		var shrink := 0.2 if it["id"] == "eingang" else 1.2
		match m:
			0:
				out.append([Vector2(-hr.size.x * 0.5, rc.y), r.size.y - shrink, oh])
			1:
				out.append([Vector2(hr.size.x * 0.5, rc.y), r.size.y - shrink, oh])
			2:
				out.append([Vector2(rc.x, -hr.size.y * 0.5), r.size.x - shrink, oh])
			3:
				out.append([Vector2(rc.x, hr.size.y * 0.5), r.size.x - shrink, oh])
	for b: Dictionary in items_of("fluggastbruecke"):
		var hs := hall_side(bridge_anchor(b))
		if hs.is_empty() or not is_same(hs[0], hall):
			continue
		var c: Vector3 = hs[2]
		out.append([Vector2(c.x - cen.x, c.z - cen.y), 3.4, 6.4])
	return out


var _facade_queue: Array = []

## Fassade einer Halle neu bauen, wenn sich Eingänge oder Brücken geändert haben (gesammelt am Bildende).
## Deckenöffnungen über Rolltreppen, Treppen und Aufzügen: [[Ebene, Rechteck lokal zur Hallenmitte, Drehung]].
func slab_holes(hall: Dictionary) -> Array:
	var out := []
	var c: Vector2 = (hall["rect"] as Rect2).get_center()
	for it: Dictionary in inside_of(hall):
		if not bool(Catalog.ITEMS.get(String(it["id"]), {}).get("connector", false)):
			continue
		var r: Rect2 = it["rect"]
		out.append([floor_of(it) + 1, Rect2(r.position - c, r.size).grow(0.05), int(it.get("rot", 0))])
	out.sort_custom(func(a: Array, b: Array) -> bool: return str(a) < str(b))
	return out


func queue_facade(hall: Dictionary) -> void:
	if _facade_queue.is_empty():
		call_deferred("flush_facades")
	for h: Dictionary in _facade_queue:
		if is_same(h, hall):
			return
	_facade_queue.append(hall)


func flush_facades() -> void:
	var todo := _facade_queue.duplicate()
	_facade_queue = []
	var changed := false
	for hall: Dictionary in todo:
		if not (hall in items):
			continue
		var cuts := facade_cuts(hall)
		if str(cuts) == str(hall.get("cuts", [])) and str(slab_holes(hall)) == str(hall.get("holes", [])):
			continue
		_rebuild_node(hall)
		changed = true
	if changed:
		items_changed.emit()


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
		var bs := bridge_snap(pos)
		if bs.is_empty():
			return "Direkt vor die Außenwand einer Terminalhalle setzen"
		pos = bs[0]
		rot = bs[1]
		for other: Dictionary in items_of("fluggastbruecke"):
			if (other["pos"] as Vector3).distance_to(pos) < 7.0:
				return "Hier steht schon eine Fluggastbrücke"
	if id == "rolltor":
		var ws := wall_snap(id, pos)
		if ws.is_empty():
			return "An die Außenwand einer Terminalhalle setzen"
		pos = ws[0]
		rot = ws[1]
	if Catalog.is_marker(id):
		var ms := marker_snap(id, pos)
		if ms.is_empty():
			match String(Catalog.ITEMS[id]["marker"]):
				"rollweg":
					return "Auf einen Rollweg setzen"
				"papi":
					return "Neben eine Piste setzen (links vom Aufsetzpunkt)"
				_:
					return "An ein Pistenende setzen"
		var mp: Vector3 = ms[0]
		if id == "rollhalt":
			var rd := runway_dist(mp)
			if rd < 60.0 or rd > 250.0:
				return "Rollhalteorte 60 bis 250 m vor der Pistenmitte setzen (hier %d m)" % int(rd)
		for other: Dictionary in items_of(id):
			if (other["pos"] as Vector3).distance_to(mp) < (20.0 if id == "rollhalt" else 100.0):
				return "Hier ist schon eine " + Catalog.label(id)
		if not on_map(mp):
			return "Außerhalb der Karte"
		if not _moving and not can_afford(int(Catalog.ITEMS[id]["cost"])):
			return "Nicht genug Geld"
		return ""
	if id == "befeuerungsstation" and runway_dist(pos) > 450.0:
		return "Höchstens 450 m von einer Piste entfernt bauen"
	var def: Dictionary = Catalog.ITEMS[id]
	var on: String = def.get("on", "")
	var r := footprint(id, pos, rot, _place_opts)
	var inner := r.grow(-0.05)
	if not on_map(Vector3(r.position.x, 0, r.position.y)) or not on_map(Vector3(r.end.x, 0, r.end.y)):
		return "Außerhalb der Karte"
	if Catalog.is_inside(id):
		var hall := hall_for_rect(r)
		if hall.is_empty():
			return "Nur innerhalb einer Terminalhalle"
		var f := view_floor
		var why_floor := floor_problem(hall, f, 0 if _moving else int(def["cost"]), r)
		if why_floor != "":
			return why_floor
		if _two_floors(id) and f + 1 >= hall_levels(hall):
			return "Darüber gibt es keine Ebene: der Halle erst eine weitere Ebene geben"
		if _two_floors(id) and floor_problem(hall, f + 1, 0, r) != "":
			return "Oben endet die Verbindung außerhalb der Geschossfläche"
		if id == "eingang" and f != 0:
			return "Eingänge nur im Erdgeschoss"
		if id == "rolltor" and f != 0:
			return "Rolltore nur im Erdgeschoss"
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
			var covers := itf == f or (_two_floors(String(it["id"])) and itf + 1 == f) \
				or (_two_floors(id) and itf == f + 1)
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
			# auf Vorfeldflächen stehen Stände, Haltestellen, Masten und Markierungen
			if it["id"] == "vorfeldflaeche" and (on == "vorfeld" or id in APRON_OK):
				continue
			if inner.intersects(it["rect"]):
				return "Hier steht schon etwas"
		var bay := false
		if id == "bushalt" and not apron_bay_snap(id, pos).is_empty() and not _on_kind(pos, on):
			bay = true   # Haltebucht am Rand einer Betriebsstraße
		elif on != "" and not _on_kind(pos, on):
			return "Muss auf dem " + Catalog.label(on) + " liegen" + (" oder als Bucht an einer Betriebsstraße" if id == "bushalt" else "")
		# Brücken stehen mit der Rotunde auf dem Vorfeld
		var on_line := _rect_on_lines(r, "betriebsstrasse" if bay else ("vorfeld" if bool(def.get("bridge", false)) else on))
		if on_line != "":
			return on_line
	var cost: int = def["cost"]
	if not _moving and not can_afford(cost):
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


## Reicht durch zwei Ebenen (Rolltreppe, Treppe, Aufzug, Gepäcklift)?
static func _two_floors(id: String) -> bool:
	var d: Dictionary = Catalog.ITEMS.get(id, {})
	return bool(d.get("connector", false)) or bool(d.get("bag_lift", false))


## Prüft eine Wand: beide Enden in derselben Halle, nicht durch Einrichtung. Leer = ok.
func can_place_wall(a: Vector3, b: Vector3) -> String:
	var hall := hall_at(a)
	if hall.is_empty() or not is_same(hall, hall_at(b)):
		return "Wände nur innerhalb einer Terminalhalle"
	var why_floor := floor_problem(hall, view_floor, 0, Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(0.01))
	if why_floor != "":
		return why_floor
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
	if not _moving and not can_afford(hall_cost(r)):
		return "Nicht genug Geld"
	return ""


# ---------------------------------------------------------------- Verschieben

var _moving := false
var _place_opts: Dictionary = {}
var _skip_rect := Rect2()      # Verschieben: alte Lage (Wegstücke, die schon darunter lagen, zählen nicht)
var move_guard: Callable        # main: Grund, warum etwas gerade nicht verschoben werden kann (belegter Stand)


## Lässt sich das überhaupt verschieben? Leer = ja.
func movable_why(rec: Dictionary) -> String:
	if rec.get("type", "") != "item":
		return "Nur Gebäude und Einrichtung lassen sich verschieben"
	var id := String(rec["id"])
	if Catalog.is_zone(id) or id == "vorfeldflaeche":
		return "Flächen abreißen und neu aufziehen"
	if move_guard.is_valid():
		var g: String = move_guard.call(rec)
		if g != "":
			return g
	return ""


## Alles, was mit einer Halle mitwandert: Einrichtung, Wände, Kofferbänder, Fluggastbrücken.
func hall_movers(h: Dictionary) -> Dictionary:
	var its: Array = inside_of(h)
	for b: Dictionary in items_of("fluggastbruecke"):
		var hs := hall_side(bridge_anchor(b))
		if not hs.is_empty() and is_same(hs[0], h):
			its.append(b)
	var ls: Array = walls_of(h)
	var hr: Rect2 = h["rect"]
	for l: Dictionary in lines:
		if not Catalog.is_floor_line(String(l["kind"])) or l in ls:
			continue
		var all_in := true
		for v: Vector3 in (l["samples"] as PackedVector3Array):
			if not hr.grow(0.5).has_point(Vector2(v.x, v.z)):
				all_in = false
				break
		if all_in:
			ls.append(l)
	return {"items": its, "lines": ls}


## Grund, warum rec nicht nach pos/rot (Halle: um pos - alte Mitte) verschoben werden kann, oder leer.
func move_problem(rec: Dictionary, pos: Vector3, rot: int) -> String:
	var why := movable_why(rec)
	if why != "":
		return why
	var id := String(rec["id"])
	if id == "halle":
		return _hall_move_problem(rec, Vector3(pos.x, 0, pos.z) - Vector3(rec["pos"].x, 0, rec["pos"].z))
	var idx := items.find(rec)
	items.remove_at(idx)
	var vf := view_floor
	if Catalog.is_inside(id):
		view_floor = floor_of(rec)
	_moving = true
	_place_opts = rec.get("opts", {})
	_skip_rect = rec["rect"]
	why = can_place(id, pos, rot)
	_skip_rect = Rect2()
	_moving = false
	_place_opts = {}
	view_floor = vf
	items.insert(idx, rec)
	return why


func _hall_move_problem(h: Dictionary, d: Vector3) -> String:
	if d.length() < 0.01:
		return ""
	var mv := hall_movers(h)
	var hr: Rect2 = h["rect"]
	var nr := Rect2(hr.position + Vector2(d.x, d.z), hr.size)
	if not on_map(Vector3(nr.position.x, 0, nr.position.y)) or not on_map(Vector3(nr.end.x, 0, nr.end.y)):
		return "Außerhalb der Karte"
	var gone_i: Array = [h] + (mv["items"] as Array)
	var gone_l: Array = mv["lines"]
	for it: Dictionary in gone_i:
		items.erase(it)
	for l: Dictionary in gone_l:
		lines.erase(l)
	_moving = true
	_skip_rect = hr
	var why := can_place_hall(nr)
	_skip_rect = Rect2()
	_moving = false
	for it: Dictionary in gone_i:
		items.append(it)
	for l: Dictionary in gone_l:
		lines.append(l)
	_grid_dirty = true
	return why


func _shift_item(it: Dictionary, d: Vector3) -> void:
	it["pos"] = (it["pos"] as Vector3) + d
	var r: Rect2 = it["rect"]
	it["rect"] = Rect2(r.position + Vector2(d.x, d.z), r.size)
	var n: Variant = it["node"]
	if is_instance_valid(n):
		(n as Node3D).position += d


func _shift_line(l: Dictionary, d: Vector3) -> void:
	var pts := []
	for q: Vector3 in l["points"]:
		pts.append(q + d)
	l["points"] = pts
	var sm: PackedVector3Array = l["samples"]
	for i in range(sm.size()):
		sm[i] += d
	l["samples"] = sm
	var b: Rect2 = l["bounds"]
	l["bounds"] = Rect2(b.position + Vector2(d.x, d.z), b.size)
	var n: Variant = l["node"]
	if is_instance_valid(n):
		(n as Node3D).position += d
	_grid_dirty = true


## Verschiebt ein Gebäude (Halle: mit Einrichtung, Wänden, Bändern und Brücken). Kostenlos. "" = ok.
func move_item(rec: Dictionary, pos: Vector3, rot: int) -> String:
	var why := move_problem(rec, pos, rot)
	if why != "":
		return why
	var id := String(rec["id"])
	if id == "halle":
		var d := Vector3(pos.x, 0, pos.z) - Vector3(rec["pos"].x, 0, rec["pos"].z)
		if d.length() < 0.01:
			return ""
		var mv := hall_movers(rec)
		_shift_item(rec, d)
		for it: Dictionary in mv["items"]:
			_shift_item(it, d)
		for l: Dictionary in mv["lines"]:
			_shift_line(l, d)
		hall_moved.emit(rec, d)
		evaluate_supply()
		items_changed.emit()
		network_changed.emit()
		return ""
	if bool(Catalog.ITEMS[id].get("bridge", false)):
		var bs := bridge_snap(pos)
		if not bs.is_empty():
			pos = bs[0]
			rot = bs[1]
	if Catalog.is_marker(id):
		var ms := marker_snap(id, pos)
		if not ms.is_empty():
			pos = ms[0]
			rot = ms[1]
	if id == "rolltor":
		var ws := wall_snap(id, pos)
		if not ws.is_empty():
			pos = ws[0]
			rot = ws[1]
	var old_facade: Dictionary = {}
	if id in ["eingang", "rolltor"] or _two_floors(id):
		old_facade = rec.get("hall", {})
	elif bool(Catalog.ITEMS[id].get("bridge", false)):
		var hs0 := hall_side(bridge_anchor(rec))
		if not hs0.is_empty():
			old_facade = hs0[0]
	var old_hall: Dictionary = rec.get("hall", {})
	var is_stand := id in STAND_IDS
	var had_leads := false
	if is_stand:
		for sl: Dictionary in stand_lines(rec):
			_remove_one(sl, 0.0)
			had_leads = true
	var node: Node3D = rec["node"]
	node.position = Vector3(pos.x, node.position.y, pos.z)
	node.rotation.y = float(rot) * PI * 0.5
	rec["pos"] = node.position
	rec["rot"] = rot
	rec["rect"] = footprint(id, pos, rot, rec.get("opts", {}))
	if Catalog.is_inside(id):
		rec["hall"] = hall_for_rect(rec["rect"])
		if Catalog.is_door(id):
			if not old_hall.is_empty():
				refresh_walls(old_hall, floor_of(rec))
			if not (rec["hall"] as Dictionary).is_empty() and not is_same(rec["hall"], old_hall):
				refresh_walls(rec["hall"], floor_of(rec))
	if not old_facade.is_empty() and old_facade in items:
		queue_facade(old_facade)
	if id in ["eingang", "rolltor"] or _two_floors(id):
		if not (rec.get("hall", {}) as Dictionary).is_empty():
			queue_facade(rec["hall"])
	elif bool(Catalog.ITEMS[id].get("bridge", false)):
		var hs1 := hall_side(bridge_anchor(rec))
		if not hs1.is_empty():
			queue_facade(hs1[0])
	if is_stand and (had_leads or String(opt(rec, "markierung")) == "eigene"):
		make_leadins(rec, true)
	_apply_floor(rec)
	evaluate_supply()
	items_changed.emit()
	if is_stand or Catalog.ITEMS[id].has("garage") or Catalog.is_marker(id) or id in ["bushalt", "haltestelle", "taxistand", "kissfly", "parkhaus", "parkplatz", "mietwagen"]:
		network_changed.emit()
	return ""


func build_hall(r: Rect2, free: bool = false, opts: Dictionary = {}) -> Dictionary:
	var cost := 0 if free else hall_cost(r)
	if not can_afford(cost):
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
	if not can_afford(cost):
		toast.emit("Nicht genug Geld")
		return {}
	if bool(Catalog.ITEMS[id].get("bridge", false)):
		var bs := bridge_snap(pos)
		if not bs.is_empty():
			pos = bs[0]
			rot = bs[1]
	if Catalog.is_marker(id):
		var ms := marker_snap(id, pos)
		if not ms.is_empty():
			pos = ms[0]
			rot = ms[1]
	if id == "rolltor":
		var ws := wall_snap(id, pos)
		if not ws.is_empty():
			pos = ws[0]
			rot = ws[1]
	var f := 0
	if Catalog.is_inside(id):
		f = view_floor if floor == -99 else floor
		if ensure_basement(hall_for_rect(footprint(id, pos, rot)), f) != "":
			return {}
	if Catalog.SIZED.has(id) and not opts.has("tore"):
		opts = opts.duplicate()
		opts["tore"] = int((Catalog.SIZED[id]["tore"] as Array)[0])
	var node := Factory.make_item(id, opts)
	node.position = Vector3(pos.x, float(f) * Catalog.FLOOR_H, pos.z)
	node.rotation.y = float(rot) * PI * 0.5
	item_root.add_child(node)
	var rec := {"type": "item", "id": id, "pos": node.position, "rot": rot,
		"rect": footprint(id, pos, rot, opts), "node": node, "cost": cost, "supply": {}, "opts": opts.duplicate()}
	if Catalog.is_inside(id):
		rec["hall"] = hall_for_rect(rec["rect"])
		rec["floor"] = f
		_apply_floor(rec)
	if (id == "eingang" or id == "rolltor" or _two_floors(id)) and rec.has("hall"):
		queue_facade(rec["hall"])
	elif bool(Catalog.ITEMS[id].get("bridge", false)):
		var hsb := hall_side(bridge_anchor(rec))
		if not hsb.is_empty():
			queue_facade(hsb[0])
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
	var half := maxf(r.size.x, r.size.y) * 0.5
	# Wände auf der Türlinie sammeln (auch mehrere hintereinander): die Tür muss ganz auf Wand sitzen
	var spans := []
	for l: Dictionary in walls_of(hall):
		if floor_of(l) != f:
			continue
		var s: PackedVector3Array = l["samples"]
		var a := Vector2(s[0].x, s[0].z)
		var b := Vector2(s[s.size() - 1].x, s[s.size() - 1].z)
		var d := b - a
		if d.length() < 0.5 or absf(d.normalized().dot(along)) < 0.98:
			continue
		var ta := (a - c).dot(along)
		var tb := (b - c).dot(along)
		if ((a + along * -ta) - c).length() > 0.35:
			continue
		spans.append(Vector2(minf(ta, tb), maxf(ta, tb)))
	spans.sort_custom(func(x: Vector2, y: Vector2) -> bool: return x.x < y.x)
	var reach := -half
	for sp: Vector2 in spans:
		if sp.x > reach + 0.05:
			continue
		reach = maxf(reach, sp.y)
	if reach >= half - 0.05:
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
		if (a + dn * t).distance_to(c) > 0.4 or t + half < 0.05 or t - half > d.length() - 0.05 or absf(dn.dot(along)) < 0.98:
			continue
		# auch Türen, die nur zum Teil auf diesem Wandstück sitzen (Wand endet an der Tür)
		out.append([maxf(t - half, 0.0), minf(t + half, d.length())])
	# Kofferbänder, die durch die Wand laufen: Öffnung nur in Bandhöhe (Fluggäste kommen nicht durch)
	for bl: Dictionary in lines:
		if bl["kind"] != "kofferband" or floor_of(bl) != floor_of(l):
			continue
		var bs: PackedVector3Array = bl["samples"]
		for i in range(bs.size() - 1):
			var p := Vector2(bs[i].x, bs[i].z)
			var q := Vector2(bs[i + 1].x, bs[i + 1].z)
			var r := q - p
			var den := r.x * d.y - r.y * d.x
			if absf(den) < 0.0001:
				continue
			var w := a - p
			var u := (w.x * d.y - w.y * d.x) / den        # entlang des Bands
			var tw := (w.x * r.y - w.y * r.x) / den       # entlang der Wand (0..1)
			if u < 0.0 or u > 1.0 or tw < 0.0 or tw > 1.0:
				continue
			var h := lerpf(bs[i].y, bs[i + 1].y, u)
			var tt := tw * d.length()
			out.append([tt - 0.75, tt + 0.75, maxf(h - 0.4, 0.05), h + 0.6])
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
		var zn := String(Catalog.ITEMS[z["id"]]["zone"])
		if zn != "" and floor_of(z) == f and (z["rect"] as Rect2).has_point(p):
			return zn
	return ""


## Räume einer Art in einer Halle: [{rec, ok, missing}]
func rooms_of(hall: Dictionary, kind: String = "") -> Array:
	var out := []
	for z: Dictionary in zones_of(hall):
		var rk := Catalog.room_of(String(z["id"]))
		if rk == "" or (kind != "" and rk != kind):
			continue
		out.append(room_status(z))
	return out


## Ist ein Raum fertig eingerichtet? Ausstattung muss ganz im Raum stehen (gleiche Ebene).
func room_status(z: Dictionary) -> Dictionary:
	var rk := Catalog.room_of(String(z["id"]))
	var spec: Dictionary = Catalog.ROOM_TYPES[rk]
	var r: Rect2 = z["rect"]
	var missing := []
	if r.get_area() < float(spec["area"]):
		missing.append("mindestens %d m²" % int(spec["area"]))
	var hall: Dictionary = z.get("hall", {})
	for need: Array in spec["needs"]:
		var have := 0
		if not hall.is_empty():
			for it: Dictionary in inside_of(hall):
				if it["id"] == need[0] and floor_of(it) == floor_of(z) and r.grow(0.05).encloses(it["rect"]):
					have += 1
		if have < int(need[1]):
			missing.append("%d× %s" % [int(need[1]) - have, Catalog.label(String(need[0]))])
	return {"rec": z, "kind": rk, "ok": missing.is_empty(), "missing": missing}


## Gibt es in der Halle einen fertigen Raum dieser Art?
func room_ok(hall: Dictionary, kind: String) -> bool:
	for st: Dictionary in rooms_of(hall, kind):
		if bool(st["ok"]):
			return true
	return false


## Irgendwo ein fertiger Raum dieser Art?
func any_room_ok(kind: String) -> bool:
	for h: Dictionary in items_of("halle"):
		if room_ok(h, kind):
			return true
	return false


## Flächenabriss: alles im Rechteck (auf der gezeigten Ebene). Hallen nur, wenn sie ganz drin liegen.
func area_victims(r: Rect2) -> Array:
	var out := []
	for it: Dictionary in items:
		var id: String = it["id"]
		var ir: Rect2 = it["rect"]
		if id == "halle":
			if r.encloses(ir):
				out.append(it)
		elif Catalog.is_inside(id):
			if interior_view and floor_of(it) == view_floor and (r.has_point(ir.get_center()) if not Catalog.is_zone(id) else r.encloses(ir)):
				if not out.has(it.get("hall", {})):
					out.append(it)
		elif not (interior_view and view_floor < 0) and r.has_point(ir.get_center()):
			out.append(it)
	for l: Dictionary in lines:
		var kind: String = l["kind"]
		if Catalog.utility_of(kind) != "" and not utility_view:
			continue
		if Catalog.is_floor_line(kind) and interior_view and floor_of(l) != view_floor:
			continue
		if Catalog.is_wall(kind) and not interior_view:
			continue
		var sm: PackedVector3Array = l["samples"]
		var inside := 0
		for v: Vector3 in sm:
			if r.has_point(Vector2(v.x, v.z)):
				inside += 1
		if inside * 2 >= sm.size():
			out.append(l)
	return out


func demolish_area(r: Rect2) -> int:
	var n := 0
	for rec: Dictionary in area_victims(r):
		if rec in items or rec in lines:
			remove(rec, 0.5)
			n += 1
	return n


## Raum-Werkzeug (wie in Aufbauspielen mit Grundriss): Rechteck auf der gezeigten Ebene einer Halle.
## Wände entstehen auf allen Seiten, die nicht an der Außenwand oder einer bestehenden Wand liegen,
## eine Tür auf der längsten neuen Seite (Mitte, sonst versetzt), optional ein Bereich darüber.
## Gibt "" oder den Grund zurück.
func room_problem(r: Rect2) -> String:
	if r.size.x < 3.0 or r.size.y < 3.0:
		return "Raum mindestens 3 × 3 m"
	var hall := hall_for_rect(r)
	if hall.is_empty():
		return "Räume nur innerhalb einer Terminalhalle"
	return floor_problem(hall, view_floor, 0, r)


func room_edges(r: Rect2) -> Array:
	var hall := hall_for_rect(r)
	var hr: Rect2 = hall.get("rect", Rect2())
	var out := []
	var corners := [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)]
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var horizontal := absf(a.y - b.y) < 0.01
		# an der Außenwand: keine Innenwand nötig
		if horizontal and (absf(a.y - hr.position.y) < 0.6 or absf(a.y - hr.end.y) < 0.6):
			continue
		if not horizontal and (absf(a.x - hr.position.x) < 0.6 or absf(a.x - hr.end.x) < 0.6):
			continue
		# vorhandene Wände auf dieser Linie abziehen: nur die Lücken bekommen eine neue Wand
		var u0 := minf(a.x, b.x) if horizontal else minf(a.y, b.y)
		var u1 := maxf(a.x, b.x) if horizontal else maxf(a.y, b.y)
		var line_v := a.y if horizontal else a.x
		var gaps: Array = [Vector2(u0, u1)]
		for l: Dictionary in walls_of(hall):
			if floor_of(l) != view_floor:
				continue
			var sm: PackedVector3Array = l["samples"]
			var la := Vector2(sm[0].x, sm[0].z)
			var lb := Vector2(sm[sm.size() - 1].x, sm[sm.size() - 1].z)
			var on_line := (absf(la.y - line_v) < 0.3 and absf(lb.y - line_v) < 0.3) if horizontal \
				else (absf(la.x - line_v) < 0.3 and absf(lb.x - line_v) < 0.3)
			if not on_line:
				continue
			var w0 := minf(la.x, lb.x) if horizontal else minf(la.y, lb.y)
			var w1 := maxf(la.x, lb.x) if horizontal else maxf(la.y, lb.y)
			var next: Array = []
			for g: Vector2 in gaps:
				if w1 <= g.x + 0.05 or w0 >= g.y - 0.05:
					next.append(g)
					continue
				if w0 > g.x + 0.3:
					next.append(Vector2(g.x, w0))
				if w1 < g.y - 0.3:
					next.append(Vector2(w1, g.y))
			gaps = next
		var lo := hr.grow(-0.05)
		for g: Vector2 in gaps:
			if g.y - g.x < 0.5:
				continue
			var ga := Vector2(g.x, line_v) if horizontal else Vector2(line_v, g.x)
			var gb := Vector2(g.y, line_v) if horizontal else Vector2(line_v, g.y)
			# Enden an der Außenwand knapp nach innen ziehen (sonst liegt der Punkt nicht in der Halle)
			ga = Vector2(clampf(ga.x, lo.position.x, lo.end.x), clampf(ga.y, lo.position.y, lo.end.y))
			gb = Vector2(clampf(gb.x, lo.position.x, lo.end.x), clampf(gb.y, lo.position.y, lo.end.y))
			out.append([Vector3(ga.x, 0, ga.y), Vector3(gb.x, 0, gb.y)])
	return out


func room_cost(r: Rect2, zone_id: String) -> int:
	var total := 0
	for e: Array in room_edges(r):
		total += line_cost("innenwand", PackedVector3Array([e[0], e[1]]))
	total += int(Catalog.ITEMS["tuer"]["cost"])
	if zone_id != "":
		total += zone_cost(zone_id, r)
	return total


func build_room(r: Rect2, zone_id: String, door_art: String, room_kind: String = "", free: bool = false) -> String:
	var why := room_problem(r)
	if why != "":
		return why
	if not free and not can_afford(room_cost(r, zone_id) + basement_cost(hall_for_rect(r)) * int(view_floor < 0)):
		return "Nicht genug Geld"
	why = ensure_basement(hall_for_rect(r), view_floor)
	if why != "":
		return why
	var edges := room_edges(r)
	var built := []
	for e: Array in edges:
		var wy := can_place_wall(e[0], e[1])
		if wy != "":
			continue
		var rec := build_line("innenwand", [e[0], e[1]], free)
		if not rec.is_empty():
			built.append(rec)
	if zone_id != "":
		build_zone(zone_id, r, free)
	if room_kind != "" and Catalog.ITEMS.has("raum_" + room_kind):
		build_zone("raum_" + room_kind, r, free)
	# Tür: längste neue Wand, Mitte; geht das nicht, ein Stück daneben
	built.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return Spline.length(x["samples"]) > Spline.length(y["samples"]))
	for w: Dictionary in built:
		var sm: PackedVector3Array = w["samples"]
		var a := sm[0]
		var b := sm[sm.size() - 1]
		var length := a.distance_to(b)
		if length < 3.0:
			continue
		var rot := 0 if absf(b.z - a.z) < 0.01 else 1
		for f: float in [0.5, 0.3, 0.7, 0.15, 0.85]:
			var p := a.lerp(b, f)
			p = Vector3(snappedf(p.x, 0.5), 0, snappedf(p.z, 0.5))
			if can_place("tuer", p, rot) == "":
				build_item("tuer", p, rot, free, {"art": door_art})
				return ""
	return "" if not built.is_empty() else "Hier stehen schon alle Wände"


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
	var why_floor := floor_problem(hall, fl, 0, r)
	if why_floor != "":
		return why_floor
	if r.size.x < 1.0 or r.size.y < 1.0:
		return "Zu klein"
	if not can_afford(zone_cost(id, r)):
		return "Nicht genug Geld"
	return ""


func build_zone(id: String, r: Rect2, free: bool = false, f: int = -99) -> Dictionary:
	var fl := view_floor if f == -99 else f
	if ensure_basement(hall_for_rect(r), fl) != "":
		return {}
	var cost := 0 if free else zone_cost(id, r)
	if not can_afford(cost):
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


const STAND_IDS := ["stand", "stand_aussen", "stand_gross", "stand_f"]


## Einrolllinien eines Stands als Rollführungslinien: von der Linie (oder dem Rollweg) hinter dem Stand
## in beiden Richtungen als Bogen hinein bis zu den Haltebalken. Rückgabe {"lines": [Punktlisten],
## "base": Vorfeld-Linie ohne eigene Rolllinie (deren Mitte bekommt dann auch eine) oder {}}.
func stand_leadins(st: Dictionary) -> Dictionary:
	var out := {"lines": [], "base": {}, "rank": 9}
	var node: Node3D = st["node"]
	if not is_instance_valid(node):
		return out
	var bas := Basis(Vector3.UP, float(int(st["rot"])) * PI * 0.5)
	var fwd := bas.z
	var lat := bas.x
	var sp: Vector3 = st["pos"]
	var hd: float = (Catalog.ITEMS[st["id"]]["size"] as Vector2).y * 0.5
	var lp := sp - fwd * (hd + 1.0)
	var inner := (st["rect"] as Rect2).grow(-1.0)
	var best := {}
	var best_rank := 9
	var best_d := INF
	for l: Dictionary in lines:
		var k := String(l["kind"])
		var rank: int = {"rolllinie": 0, "rollweg": 1, "rollweg_breit": 1, "vorfeld": 2}.get(k, 9)
		if rank > best_rank or rank == 9:
			continue
		var sm: PackedVector3Array = l["samples"]
		for j in range(sm.size() - 1):
			var la := (sm[j] - sp).dot(lat)
			var lb := (sm[j + 1] - sp).dot(lat)
			if la * lb > 0.0 or absf(la - lb) < 0.001:
				continue
			var q := sm[j].lerp(sm[j + 1], la / (la - lb))
			q.y = 0.0
			var d := q.distance_to(lp)
			if d > 42.0 or (q - lp).dot(fwd) > 4.0 or inner.has_point(Vector2(q.x, q.z)):
				continue
			if rank < best_rank or d < best_d:
				best_rank = rank
				best_d = d
				var t := sm[j + 1] - sm[j]
				t.y = 0.0
				best = {"p": q, "t": t.normalized(), "line": l}
	if best.is_empty():
		return out
	out["rank"] = best_rank
	if best_rank == 2:
		out["base"] = best["line"]
	var bp: Vector3 = best["p"]
	var tng: Vector3 = best["t"]
	var end := sp + fwd * (hd - 11.0)
	var dout := (end - bp).normalized()
	var span := bp.distance_to(end)
	for sgn: float in [-1.0, 1.0]:
		var din := tng * sgn
		var theta := PI - acos(clampf((-din).dot(dout), -1.0, 1.0))
		var cut := minf(35.0 * tan(theta * 0.5), span * 0.66)
		var s1 := bp - din * cut
		var e := bp + dout * cut
		var pts := []
		for i in range(13):
			var tt := float(i) / 12.0
			pts.append(s1 * ((1.0 - tt) * (1.0 - tt)) + bp * (2.0 * (1.0 - tt) * tt) + e * (tt * tt))
		pts.append(end)
		(out["lines"] as Array).append(pts)
	return out


## Legt die Einrolllinien eines Stands als echte Rolllinien an (änder- und abreißbar). Liegt hinter dem
## Stand nur ein Vorfeld ohne Linie, bekommt es zuerst eine Mittellinie. Rückgabe: Zahl der Linien.
func make_leadins(st: Dictionary, only_on_lines: bool = false) -> int:
	var li: Dictionary = stand_leadins(st)
	var n := 0
	# automatisch nur an Rolllinien oder Rollwege anschließen (nicht an ein Vorfeld ohne Linien)
	if only_on_lines and int(li["rank"]) > 1:
		return 0
	var base: Dictionary = li["base"]
	if not base.is_empty():
		var c := build_line("rolllinie", base["points"], true)
		if not c.is_empty():
			n += 1
			li = stand_leadins(st)
	for pts: Array in li["lines"]:
		var smp := line_samples("rolllinie", pts)
		if String(check_line("rolllinie", smp)["why"]) != "":
			continue
		if not build_line("rolllinie", pts, true).is_empty():
			n += 1
	return n


## Rolllinien, die in diesem Stand enden (mit dem Stand abreißen).
func stand_lines(st: Dictionary) -> Array:
	var out := []
	var r := (st["rect"] as Rect2).grow(-2.0)
	for l: Dictionary in lines:
		if l["kind"] != "rolllinie":
			continue
		var sm: PackedVector3Array = l["samples"]
		var a := sm[0]
		var b := sm[sm.size() - 1]
		if r.has_point(Vector2(a.x, a.z)) or r.has_point(Vector2(b.x, b.z)):
			out.append(l)
	return out


func stands() -> Array:
	var out := []
	for it: Dictionary in items:
		if it["id"] == "stand" or it["id"] == "stand_aussen" or it["id"] == "stand_gross" or it["id"] == "stand_f":
			out.append(it)
	return out


func items_of(id: String) -> Array:
	var out := []
	for it: Dictionary in items:
		if it["id"] == id:
			out.append(it)
	return out


# ---------------------------------------------------------------- Versorgung (Strom, Wasser)

const BELT_LOW := 0.62    # Bandhöhe an Schaltern, Sortierung und Lift
const BELT_HIGH := 2.9    # unter der Decke: Fluggäste gehen darunter durch
const BELT_RAMP := 5.0
var legacy_belts := false # Spielstand von vor 0.17: Schalter arbeiten auch ohne Kofferband
var fees := {"lande": 1.0, "park": 1.0, "miete": 1.0}   # Gebühren als Faktor (0,5 … 2,0)
var night_ban := false                                  # Nachtflugverbot 23–6 Uhr
const FEE_STEPS := [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]


func set_fee(key: String, dir: int) -> float:
	var i := FEE_STEPS.find(float(fees.get(key, 1.0)))
	if i < 0:
		i = 2
	fees[key] = FEE_STEPS[clampi(i + dir, 0, FEE_STEPS.size() - 1)]
	return float(fees[key])


func is_night_hour() -> bool:
	var hr := fmod(minutes, 1440.0) / 60.0
	return hr >= 23.0 or hr < 6.0
var legacy_claims := false # Spielstand von vor 0.18: Gepäckbänder arbeiten auch ohne Kofferband
const CLAIM_INLET := Vector3(-5.5, 0, 0)   # Einlauf des Gepäckbands (lokal)
const GATE_INLET := Vector3(2.1, 0, -1.5)  # Rollenbahn hinter dem Rolltor (lokal, innen, neben der Fahrspur)
const XRAY_INLET := 4.5                    # Ein-/Auslauf der Gepäckdurchleuchtung (lokal ±X)
const BELT_CAP := 6                        # so viele Check-in-Schalter verkraftet ein Kofferband
const GATE_BAY := Vector2(4.0, 10.0)       # Einfahrt hinter einem Rolltor (Breite, Tiefe) für Gepäckzüge


## Anschlussstellen für Kofferbänder auf Ebene f: Seiten der Check-ins, Kanten der Sortierung,
## Ein-/Auslauf der Gepäcklifte (lokal +Z), Kanten eines Gepäckumschlags.
func belt_spots(f: int) -> Array:
	var out := []
	for it: Dictionary in items:
		var id: String = it["id"]
		var itf := floor_of(it)
		var xf := (it["node"] as Node3D).transform
		if id == "checkin" and itf == f:
			for sx: float in [-3.45, 3.45]:
				var p := xf * Vector3(sx, 0, -1.16)
				out.append(Vector3(p.x, 0, p.z))
		elif (id == "gepaeckanlage" and itf == f) or (id == "gepaeckumschlag" and f == 0):
			var r: Rect2 = it["rect"]
			var c := r.get_center()
			for e: Vector2 in [Vector2(r.position.x - 0.5, c.y), Vector2(r.end.x + 0.5, c.y), Vector2(c.x, r.position.y - 0.5), Vector2(c.x, r.end.y + 0.5)]:
				out.append(Vector3(e.x, 0, e.y))
		elif id == "gepaecklift" and (itf == f or itf + 1 == f):
			var p2 := xf * Vector3(0, 0, 1.45)
			out.append(Vector3(p2.x, 0, p2.z))
		elif id == "gepaeckband" and itf == f:
			var p3 := xf * CLAIM_INLET
			out.append(Vector3(p3.x, 0, p3.z))
		elif id == "rolltor" and itf == f:
			var p4 := xf * GATE_INLET
			out.append(Vector3(p4.x, 0, p4.z))
		elif id == "gepaeckroentgen" and itf == f:
			for sx: float in [-XRAY_INLET, XRAY_INLET]:
				var p5 := xf * Vector3(sx, 0, 0)
				out.append(Vector3(p5.x, 0, p5.z))
	return out


func _belt_end_low(p: Vector3, f: int) -> bool:
	for sp: Vector3 in belt_spots(f):
		if Vector2(sp.x - p.x, sp.z - p.z).length() < 1.6:
			return true
	return false


## Höhenverlauf eines Kofferbands: niedrig an Anschlüssen, dazwischen unter der Decke.
func belt_profile(samples: PackedVector3Array, f: int) -> PackedVector3Array:
	var n := samples.size()
	var cum := PackedFloat32Array([0.0])
	for i in range(1, n):
		cum.append(cum[i - 1] + Vector2(samples[i].x - samples[i - 1].x, samples[i].z - samples[i - 1].z).length())
	var length := cum[n - 1]
	var low0 := _belt_end_low(samples[0], f)
	var low1 := _belt_end_low(samples[n - 1], f)
	var out := PackedVector3Array()
	# kurze Stücke mit nur einem niedrigen Ende steigen steiler, damit sie oben am nächsten Band ankommen
	var ramp := BELT_RAMP if low0 == low1 else clampf(length - 2.0, 1.5, BELT_RAMP)
	for i in range(n):
		var h := BELT_HIGH
		if low0 and low1 and length < 12.0:
			h = BELT_LOW
		else:
			if low0:
				h = minf(h, BELT_LOW + (BELT_HIGH - BELT_LOW) * clampf((cum[i] - 1.0) / ramp, 0.0, 1.0))
			if low1:
				h = minf(h, BELT_LOW + (BELT_HIGH - BELT_LOW) * clampf((length - cum[i] - 1.0) / ramp, 0.0, 1.0))
		out.append(Vector3(samples[i].x, h, samples[i].z))
	return out


const BELT_ROUND := 2.2   # Radius der Ausrundung, wo zwei Bänder mit einem Knick aneinanderstoßen


static func _rev_path(s: PackedVector3Array) -> PackedVector3Array:
	var o := PackedVector3Array()
	for i in range(s.size() - 1, -1, -1):
		o.append(s[i])
	return o


static func _flat_len(s: PackedVector3Array) -> float:
	var l := 0.0
	for i in range(s.size() - 1):
		l += Vector2(s[i + 1].x - s[i].x, s[i + 1].z - s[i].z).length()
	return l


## Rest eines Pfads ab Abstand d vom Anfang (erster Punkt = Schnittpunkt).
static func _path_from(s: PackedVector3Array, d: float) -> PackedVector3Array:
	var run := 0.0
	for i in range(s.size() - 1):
		var l := Vector2(s[i + 1].x - s[i].x, s[i + 1].z - s[i].z).length()
		if run + l >= d:
			var out := PackedVector3Array([s[i].lerp(s[i + 1], (d - run) / maxf(l, 0.0001))])
			for j in range(i + 1, s.size()):
				if j == i + 1 and Vector2(s[j].x - out[0].x, s[j].z - out[0].z).length() < 0.25:
					continue
				out.append(s[j])
			if out.size() < 2:
				out.append(s[s.size() - 1])
			return out
		run += l
	return PackedVector3Array([s[s.size() - 1], s[s.size() - 1]])


## Grundriss eines Kofferbands: aus den Klickpunkten, und wo genau ein anderes Band mit einem Knick
## anschließt, laufen beide in einem gemeinsamen Bogen zusammen (je die Hälfte einer Bézierkurve).
func _belt_base(rec: Dictionary) -> PackedVector3Array:
	var s := line_samples("kofferband", rec["points"])
	if s.size() < 2:
		return s
	var f := floor_of(rec)
	var my_len := _flat_len(s)
	for end: int in [0, 1]:
		var cur := s if end == 0 else _rev_path(s)
		var e := cur[0]
		var hits := 0
		var oth := PackedVector3Array()
		for l: Dictionary in lines:
			if l == rec or l["kind"] != "kofferband" or floor_of(l) != f:
				continue
			var os := line_samples("kofferband", l["points"])
			if os.size() < 2:
				continue
			for oe: int in [0, 1]:
				var q := os[0] if oe == 0 else os[os.size() - 1]
				if Vector2(q.x - e.x, q.z - e.z).length() < 0.35:
					hits += 1
					oth = os if oe == 0 else _rev_path(os)
		if hits != 1 or _belt_end_low(e, f):
			continue
		var c := (e + oth[0]) * 0.5
		var r := minf(BELT_ROUND, 0.4 * minf(my_len, _flat_len(oth)))
		if r < 0.3:
			continue
		var rest := _path_from(cur, r)
		var p0 := rest[0]
		var p2 := _path_from(oth, r)[0]
		var va := Vector3(p0.x - c.x, 0, p0.z - c.z).normalized()
		var vb := Vector3(p2.x - c.x, 0, p2.z - c.z).normalized()
		var ang := rad_to_deg(acos(clampf(va.dot(vb), -1.0, 1.0)))
		if ang < 25.0 or ang > 172.0:
			continue
		var arc := PackedVector3Array()
		for k: int in [5, 4, 3, 2, 1]:
			var t := float(k) * 0.1
			arc.append(p0 * (1.0 - t) * (1.0 - t) + c * 2.0 * t * (1.0 - t) + p2 * t * t)
		arc.append_array(rest)
		s = arc if end == 0 else _rev_path(arc)
	return s


## Band neu formen (Grundriss mit Ausrundungen, Höhen) und sein Modell neu bauen. Gibt true zurück,
## wenn sich etwas geändert hat.
func _reshape_belt(rec: Dictionary) -> bool:
	var old: PackedVector3Array = rec["samples"]
	var nw := belt_profile(_belt_base(rec), floor_of(rec))
	var changed := old.size() != nw.size()
	if not changed:
		for i in range(old.size()):
			if old[i].distance_to(nw[i]) > 0.01:
				changed = true
				break
	var node: Variant = rec["node"]
	if changed or not is_instance_valid(node) or not bool(rec.get("shaped", false)):
		rec["samples"] = nw
		rec["shaped"] = true
		if is_instance_valid(node):
			(node as Node).queue_free()
		var nn := Factory.make_line("kofferband", nw, 0.0)
		nn.position.y = float(floor_of(rec)) * Catalog.FLOOR_H
		line_root.add_child(nn)
		rec["node"] = nn
		_apply_visibility(rec)
		_merges_dirty = true
		return true
	return false


var _merges_dirty := true


## Einschleuser: wo ein Band seitlich auf ein anderes trifft (Ende an der Mitte), steht ein Gehäuse
## mit Leitblech und Lampe. Hängt als Knoten "Weiche" am zuführenden Band.
func _belt_merges() -> void:
	_merges_dirty = false
	var belts := []
	for l: Dictionary in lines:
		if l["kind"] == "kofferband":
			belts.append(l)
	for l: Dictionary in belts:
		var nd: Variant = l["node"]
		if not is_instance_valid(nd):
			continue
		for c: Node in (nd as Node).get_children():
			if String(c.name).begins_with("Weiche"):
				c.queue_free()
	for l: Dictionary in belts:
		var nd: Variant = l["node"]
		if not is_instance_valid(nd):
			continue
		var sl: PackedVector3Array = l["samples"]
		var f := floor_of(l)
		var idx := 0
		for e: Vector3 in [sl[0], sl[sl.size() - 1]]:
			if _belt_end_low(e, f):
				continue
			var joint := false
			var hit := Vector3.INF
			var hdir := Vector3.ZERO
			for m: Dictionary in belts:
				if m == l or floor_of(m) != f:
					continue
				var sm: PackedVector3Array = m["samples"]
				if Vector2(sm[0].x - e.x, sm[0].z - e.z).length() < 0.6 or Vector2(sm[sm.size() - 1].x - e.x, sm[sm.size() - 1].z - e.z).length() < 0.6:
					joint = true
					break
				for i in range(1, sm.size() - 1):
					if Vector2(sm[i].x - e.x, sm[i].z - e.z).length() < 1.3:
						hit = sm[i]
						hdir = (sm[i + 1] - sm[i - 1])
						break
			if joint or hit == Vector3.INF:
				continue
			hdir.y = 0.0
			var k := Kit.new()
			var bas := Basis.looking_at(hdir.normalized() if hdir.length() > 0.01 else Vector3.FORWARD, Vector3.UP)
			var xf := Transform3D(bas, hit)
			k.box(Vector3(-0.85, 0.18, -0.9), Vector3(0.85, 0.32, 0.9), Color(0.55, 0.57, 0.6), xf)
			for sx: float in [-0.85, 0.85]:
				k.box(Vector3(sx - 0.04, -0.15, -0.9), Vector3(sx + 0.04, 0.18, 0.9), Color(0.42, 0.45, 0.48), xf)
			for i in range(5):
				var z := -0.8 + float(i) * 0.36
				k.box(Vector3(-0.86, 0.32, z), Vector3(0.86, 0.34, z + 0.18), Color(0.92, 0.74, 0.18), xf)
			k.box(Vector3(0.6, 0.34, -0.15), Vector3(0.74, 0.46, 0.0), Color(0.3, 0.9, 0.4, 0.3), xf)
			var mi := k.instance("Weiche%d" % idx)
			(nd as Node).add_child(mi)
			idx += 1


## Nach Änderungen an Bändern, Schaltern, Sortierung oder Liften: Höhen anpassen, Wände neu schneiden.
func refresh_belts() -> void:
	var any := false
	for l: Dictionary in lines:
		if l["kind"] == "kofferband":
			any = _reshape_belt(l) or any
	if any:
		_belt_walls()
	if _merges_dirty:
		_belt_merges()
	_routes_dirty = true


func _belt_walls() -> void:
	for h: Dictionary in items_of("halle"):
		var floors := {}
		for l: Dictionary in walls_of(h):
			floors[floor_of(l)] = true
		for f: int in floors:
			refresh_walls(h, f)
	_routes_dirty = true


# ---------------------------------------------------------------- Kofferwege

var _routes_dirty := true
var _routes: Dictionary = {}    # Schalter/Rolltor (Instanz-ID) -> Weg der Koffer (Weltpunkte) bis zur Sortierung,
								# Gepäckband (Instanz-ID) -> Weg von der Sortierung bis aufs Band


## Wege der Koffer: von der Waage jedes Check-ins über Sammelbänder, Kofferbänder und Gepäcklifte zur
## nächsten Gepäcksortierung (oder einem Gepäckumschlag). Ein Dijkstra von allen Zielen aus.
func bag_routes() -> Dictionary:
	if not _routes_dirty:
		return _routes
	_routes_dirty = false
	_routes = {}
	_desk_info = {}
	var fh := Catalog.FLOOR_H
	var segs := []    # [Punkte (Welt), Ebene]
	for l: Dictionary in lines:
		if l["kind"] != "kofferband" or bool(l.get("broken", false)):
			continue
		var pts := PackedVector3Array()
		var f := floor_of(l)
		for v: Vector3 in (l["samples"] as PackedVector3Array):
			pts.append(Vector3(v.x, float(f) * fh + v.y, v.z))
		segs.append([pts, f, l])
		l["desks"] = 0
	var desk_start := {}   # Schalter-ID -> Index des Waagenpunkts
	var nodes := PackedVector3Array()
	var seg_of := PackedInt32Array()
	var targets := []
	for it: Dictionary in items:
		var id: String = it["id"]
		var f := floor_of(it)
		var xf := (it["node"] as Node3D).transform
		if id == "checkin":
			var pts := PackedVector3Array()
			for sx: float in [3.45, 2.9, 0.0, -2.95, -3.45]:
				var p := xf * Vector3(sx, 0, -1.16)
				pts.append(Vector3(p.x, float(f) * fh + 0.45, p.z))
			desk_start[(it["node"] as Node).get_instance_id()] = [segs.size(), 2]
			segs.append([pts, f])
		elif id == "gepaeckband" or id == "rolltor":
			# Einlauf am Gepäckband: Ende des Kofferbands → Steilförderer → Rutsche auf die Insel.
			# Rolltor: vom Tor über die Rollenbahn nach innen.
			var y0 := float(f) * fh
			var raw: Array = [CLAIM_INLET + Vector3(0, BELT_LOW, 0), Vector3(-5.45, 1.45, 0), Vector3(-3.4, 0.9, 0)] if id == "gepaeckband" \
				else [Vector3(GATE_INLET.x, 0.9, 0.9), Vector3(GATE_INLET.x, 0.62, -0.9), GATE_INLET + Vector3(0, BELT_LOW, 0)]
			var pts2 := PackedVector3Array()
			for q: Vector3 in raw:
				var w := xf * Vector3(q.x, 0, q.z)
				pts2.append(Vector3(w.x, y0 + q.y, w.z))
			# Gepäckband: Weg beginnt innen (Index 2) und wird umgedreht; Rolltor: beginnt am Tor (Index 0)
			desk_start[(it["node"] as Node).get_instance_id()] = [segs.size(), 2 if id == "gepaeckband" else 0, id == "gepaeckband"]
			segs.append([pts2, f])
		elif id == "gepaecklift":
			var c := xf * Vector3(0, 0, 0)
			var e := xf * Vector3(0, 0, 1.45)
			segs.append([PackedVector3Array([Vector3(e.x, float(f) * fh + BELT_LOW, e.z), Vector3(c.x, float(f) * fh + BELT_LOW, c.z),
				Vector3(c.x, float(f + 1) * fh + BELT_LOW, c.z), Vector3(e.x, float(f + 1) * fh + BELT_LOW, e.z)]), f])
		elif id == "gepaeckroentgen":
			# Durchlauf: Koffer fahren durch den Tunnel (zählt als durchleuchtet)
			var pts3 := PackedVector3Array()
			for q: Vector3 in [Vector3(-XRAY_INLET, BELT_LOW, 0), Vector3(-4, 0.84, 0), Vector3(0, 0.84, 0), Vector3(4, 0.84, 0), Vector3(XRAY_INLET, BELT_LOW, 0)]:
				var w := xf * Vector3(q.x, 0, q.z)
				pts3.append(Vector3(w.x, float(f) * fh + q.y, w.z))
			segs.append([pts3, f, "xray"])
		elif id == "gepaeckanlage" or id == "gepaeckumschlag":
			targets.append([(it["rect"] as Rect2).grow(1.6), float(f) * fh])
	# Knoten
	var first := PackedInt32Array()
	for si in range(segs.size()):
		first.append(nodes.size())
		for v: Vector3 in (segs[si][0] as PackedVector3Array):
			nodes.append(v)
			seg_of.append(si)
	var n := nodes.size()
	if n == 0:
		return _routes
	var adj := []
	adj.resize(n)
	for i in range(n):
		adj[i] = []
	for si in range(segs.size()):
		var cnt := (segs[si][0] as PackedVector3Array).size()
		for k in range(cnt - 1):
			var a := first[si] + k
			var w := nodes[a].distance_to(nodes[a + 1])
			(adj[a] as Array).append([a + 1, w])
			(adj[a + 1] as Array).append([a, w])
	# Übergänge: Ende eines Stücks an einem Punkt eines anderen (gleiche Höhe ± 3 m)
	for si in range(segs.size()):
		var cnt := (segs[si][0] as PackedVector3Array).size()
		for ei: int in [first[si], first[si] + cnt - 1]:
			var e := nodes[ei]
			for j in range(n):
				if seg_of[j] == si:
					continue
				var v := nodes[j]
				if absf(v.y - e.y) < 3.0 and Vector2(v.x - e.x, v.z - e.z).length() < 1.6:
					(adj[ei] as Array).append([j, 0.5])
					(adj[j] as Array).append([ei, 0.5])
	# Dijkstra von allen Zielpunkten
	var dist := PackedFloat32Array()
	var nxt := PackedInt32Array()
	dist.resize(n)
	nxt.resize(n)
	var open := []
	for i in range(n):
		dist[i] = INF
		nxt[i] = -1
		for t: Array in targets:
			if (t[0] as Rect2).has_point(Vector2(nodes[i].x, nodes[i].z)) and absf(nodes[i].y - float(t[1])) < 3.6:
				dist[i] = 0.0
				open.append(i)
				break
	var done := {}
	while not open.is_empty():
		var bi := 0
		for k in range(1, open.size()):
			if dist[open[k]] < dist[open[bi]]:
				bi = k
		var u: int = open[bi]
		open.remove_at(bi)
		if done.has(u):
			continue
		done[u] = true
		for e: Array in adj[u]:
			var v: int = e[0]
			var nd := dist[u] + float(e[1])
			if nd < dist[v]:
				dist[v] = nd
				nxt[v] = u
				open.append(v)
	for did: int in desk_start:
		var ds: Array = desk_start[did]
		var start: int = first[int(ds[0])] + int(ds[1])
		if dist[start] == INF:
			continue
		var route := PackedVector3Array()
		var cur := start
		var guard := 0
		while cur >= 0 and guard < 4000:
			route.append(nodes[cur])
			cur = nxt[cur]
			guard += 1
		if ds.size() > 2 and bool(ds[2]):
			route = _rev_path(route)
		_routes[did] = route
		# Schalter: über welche Bänder (Last) und durch eine Durchleuchtung?
		if ds.size() == 2:
			var seen := {}
			var xr := false
			cur = start
			guard = 0
			while cur >= 0 and guard < 4000:
				var sg: Array = segs[seg_of[cur]]
				if sg.size() > 2:
					if sg[2] is Dictionary and not seen.has(seg_of[cur]):
						seen[seg_of[cur]] = true
						(sg[2] as Dictionary)["desks"] = int((sg[2] as Dictionary).get("desks", 0)) + 1
					elif sg[2] is String:
						xr = true
				cur = nxt[cur]
				guard += 1
			var bl := []
			for si: int in seen:
				bl.append(segs[si][2])
			_desk_info[did] = {"xray": xr, "belts": bl}
	return _routes


var _desk_info: Dictionary = {}   # Schalter-ID -> {xray: bool, belts: [Bänder auf dem Weg]}


## Koffer dieses Schalters laufen durch eine Gepäckdurchleuchtung.
func desk_screened(did: int) -> bool:
	bag_routes()
	return bool((_desk_info.get(did, {}) as Dictionary).get("xray", false))


## Leistung eines Schalters nach der Last seiner Bänder: über BELT_CAP Schalter auf einem Band
## stauen sich die Koffer, der Schalter schafft anteilig weniger.
func desk_factor(did: int) -> float:
	bag_routes()
	var f := 1.0
	for l: Dictionary in (_desk_info.get(did, {}) as Dictionary).get("belts", []):
		var n := int(l.get("desks", 0))
		if n > BELT_CAP:
			f = minf(f, float(BELT_CAP) / float(n))
	return f


## Kofferbänder mit mehr als BELT_CAP Schaltern dahinter.
func belts_overloaded() -> Array:
	bag_routes()
	var out := []
	for l: Dictionary in lines:
		if l["kind"] == "kofferband" and int(l.get("desks", 0)) > BELT_CAP:
			out.append(l)
	return out


## Fläche hinter einem Rolltor, in die ein Gepäckzug einfahren kann (Weltrechteck).
func gate_bay(g: Dictionary) -> Rect2:
	var xf := (g["node"] as Node3D).transform
	var a := xf * Vector3(-GATE_BAY.x * 0.5, 0, 1.0)
	var b := xf * Vector3(GATE_BAY.x * 0.5, 0, 1.0 - GATE_BAY.y)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z)))


## Ist die Einfahrt hinter dem Rolltor frei (keine Einrichtung, keine niedrigen Bänder, keine Wand)?
func gate_bay_free(g: Dictionary) -> bool:
	if floor_of(g) != 0 or not g.has("hall"):
		return false
	var r := gate_bay(g).grow(-0.05)
	for it: Dictionary in inside_of(g["hall"]):
		if it == g or Catalog.is_zone(String(it["id"])) or floor_of(it) != 0:
			continue
		if r.intersects(it["rect"]):
			return false
	for l: Dictionary in lines:
		if l["kind"] != "kofferband" or floor_of(l) != 0:
			continue
		for v: Vector3 in (l["samples"] as PackedVector3Array):
			if v.y < 2.3 and r.has_point(Vector2(v.x, v.z)):
				return false
	for w: Dictionary in walls_of(g["hall"]):
		if floor_of(w) != 0:
			continue
		for v: Vector3 in (w["samples"] as PackedVector3Array):
			if r.has_point(Vector2(v.x, v.z)):
				return false
	return true


## Check-in-Schalter einer Halle, die über Kofferbänder an eine Gepäcksortierung (oder einen
## Gepäckumschlag) angeschlossen sind: Instanz-ID des Schalters -> true.
func checkins_linked(hall: Dictionary) -> Dictionary:
	return _linked(hall, "checkin")


## Gepäckbänder einer Halle, deren Einlauf über Kofferbänder mit einer Sortierung verbunden ist.
func claims_linked(hall: Dictionary) -> Dictionary:
	return _linked(hall, "gepaeckband")


func _linked(hall: Dictionary, kind: String) -> Dictionary:
	var routes := bag_routes()
	var out := {}
	for it: Dictionary in inside_of(hall):
		if it["id"] == kind:
			var did := (it["node"] as Node).get_instance_id()
			if routes.has(did):
				out[did] = true
	return out


func _belt_near(l: Dictionary, r: Rect2, grow: float) -> bool:
	var g := r.grow(grow)
	for v: Vector3 in (l["samples"] as PackedVector3Array):
		if g.has_point(Vector2(v.x, v.z)):
			return true
	return false


func _belts_touch(a: Dictionary, b: Dictionary) -> bool:
	var sa: PackedVector3Array = a["samples"]
	var sb: PackedVector3Array = b["samples"]
	for e: Vector3 in [sa[0], sa[sa.size() - 1]]:
		for v: Vector3 in sb:
			if Vector2(e.x - v.x, e.z - v.z).length() < 1.3:
				return true
	for e: Vector3 in [sb[0], sb[sb.size() - 1]]:
		for v: Vector3 in sa:
			if Vector2(e.x - v.x, e.z - v.z).length() < 1.3:
				return true
	return false


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
					if not bool(node.get("failed", false)):
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
	# Deckenöffnungen über Rolltreppen und Treppen aus dem Keller: dort fehlt der Rasen unter der Halle
	for it: Dictionary in items:
		if floor_of(it) < 0 and bool(Catalog.ITEMS.get(String(it["id"]), {}).get("connector", false)):
			var r: Rect2 = it["rect"]
			var c2 := r.get_center()
			out.append([c2.x, c2.y, 1.0, 0.0, r.size.x * 0.5 + 0.05, r.size.y * 0.5 + 0.05])
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
		if Catalog.SIDES.has(String(rec.get("side", ""))):
			out.append("Querschnitt: " + String(Catalog.SIDES[rec["side"]]["name"]))
		var cost := line_cost(kind, rec["samples"], String(rec.get("side", "")))
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
	var was_belt: bool = rec.get("kind", "") == "kofferband"
	if rec.get("id", "") == "halle":
		var walls := walls_of(rec)
		any_line = any_line or not walls.is_empty()
		for inner: Dictionary in inside_of(rec) + walls:
			_remove_one(inner, refund)
	var facade_hall: Dictionary = {}
	if rec.get("id", "") in ["eingang", "rolltor"] or _two_floors(String(rec.get("id", ""))):
		facade_hall = rec.get("hall", {})
	elif rec.get("id", "") == "fluggastbruecke":
		var hsr := hall_side(bridge_anchor(rec))
		if not hsr.is_empty():
			facade_hall = hsr[0]
	if String(rec.get("id", "")) in STAND_IDS:
		for sl: Dictionary in stand_lines(rec):
			_remove_one(sl, refund)
			any_line = true
	_remove_one(rec, refund)
	if Catalog.is_door(String(rec.get("id", ""))) and not (rec.get("hall", {}) as Dictionary).is_empty():
		refresh_walls(rec["hall"], floor_of(rec))
	if not facade_hall.is_empty() and facade_hall in items:
		queue_facade(facade_hall)
	evaluate_supply()
	if was_belt:
		_belt_walls()
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
	if not sandbox:
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
	before_save.emit()
	var data := {"version": 12, "controls": junction_controls, "money": money, "minutes": minutes, "satisfaction": satisfaction, "lines": [], "items": [],
		"wind": [wind_dir, wind_kt], "extra": extra, "lotse": atc_manual, "fees": fees, "nachtflug": night_ban}
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
			"floor": floor_of(l), "side": String(l.get("side", ""))})
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
	legacy_lights = int(data.get("version", 0)) < 7
	legacy_belts = int(data.get("version", 0)) < 9
	legacy_claims = int(data.get("version", 0)) < 10
	var fd: Dictionary = data.get("fees", {})
	fees = {"lande": float(fd.get("lande", 1.0)), "park": float(fd.get("park", 1.0)), "miete": float(fd.get("miete", 1.0))}
	night_ban = bool(data.get("nachtflug", false))
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
			if Catalog.is_floor_line(String(l["kind"])) and not Catalog.is_wall(String(l["kind"])):
				rec["floor"] = int(l.get("floor", 0))
				(rec["node"] as Node3D).position.y = float(rec["floor"]) * Catalog.FLOOR_H
				_apply_visibility(rec)
			if Catalog.has_sides(String(l["kind"])):
				# vor 0.15 gespeicherte Straßen bekommen Gehwege
				var sd := String(l.get("side", "gehweg"))
				rec["side"] = sd if Catalog.SIDES.has(sd) else "gehweg"
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
		var lo: Dictionary = (it.get("opts", {}) as Dictionary).duplicate()
		if Catalog.SIZED.has(String(it["id"])) and not lo.has("tore"):
			lo["tore"] = 0   # alter Spielstand: Gebäude in alter Größe
		if String(it["id"]) in STAND_IDS and not lo.has("markierung") and int(data.get("version", 0)) < 11:
			lo["markierung"] = "voll"   # alter Spielstand: Einrolllinien bleiben aufgemalt
		var rec := build_item(String(it["id"]), Vector3(float(it["x"]), 0.0, float(it["z"])), int(it["rot"]), true,
			lo, int(it.get("floor", 0)))
		if not rec.is_empty():
			rec["cost"] = int(it.get("cost", 0))
	view_floor = 0
	var ver := int(data.get("version", 0))
	if ver < 12:
		# Rollgasse des alten Startflughafens (lag am Rand von Rollweg A): weg, die Einrolllinien
		# schließen jetzt an die Mittellinie des Rollwegs an
		for l: Dictionary in lines.duplicate():
			if l["kind"] == "rolllinie" and (l["points"] as Array).size() == 2 \
					and (l["points"][0] as Vector3).is_equal_approx(Vector3(-150, 0, -93)) \
					and (l["points"][1] as Vector3).is_equal_approx(Vector3(210, 0, -93)):
				_remove_one(l, 0.0)
				if ver == 11:
					for st: Dictionary in stands():
						if String((st.get("opts", {}) as Dictionary).get("markierung", "eigene")) == "eigene":
							for sl: Dictionary in stand_lines(st):
								_remove_one(sl, 0.0)
							make_leadins(st, true)
	if ver < 11:
		# alter Spielstand: liegt hinter einem Stand schon eine Rolllinie, werden seine aufgemalten
		# Einrolllinien zu echten Rolllinien (sonst bleiben sie aufgemalt, umstellbar im Infofeld)
		for st: Dictionary in stands():
			if String((st.get("opts", {}) as Dictionary).get("markierung", "")) != "voll" or not stand_lines(st).is_empty():
				continue
			if int(stand_leadins(st)["rank"]) <= 1 and make_leadins(st, true) > 0:
				st["opts"]["markierung"] = "eigene"
				_rebuild_node(st)
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
	extra = data.get("extra", {})
	atc_manual = bool(data.get("lotse", false))
	money_changed.emit(money)
	toast.emit("Spielstand geladen")
	return true


# ---------------------------------------------------------------- Startflughafen

## Stellen, an denen ein Rollweg den Abstand d zur Pistenmitte unterschreitet (für Rollhalteorte).
func _auto_holds(d: float) -> Array:
	var out := []
	for l: Dictionary in lines:
		if not (l["kind"] in ["rollweg", "rollweg_breit"]):
			continue
		var sm: PackedVector3Array = l["samples"]
		var prev := runway_dist(sm[0])
		for i in range(1, sm.size()):
			var cur := runway_dist(sm[i])
			if (prev >= d) != (cur >= d):
				out.append(Vector3(sm[i].x, 0, sm[i].z))
			prev = cur
	return out


func load_starter() -> void:
	legacy_lights = false
	legacy_belts = false
	legacy_claims = false
	fees = {"lande": 1.0, "park": 1.0, "miete": 1.0}
	night_ban = false
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
	build_line("betriebsstrasse", [V.call(-176, -35), V.call(110, -35), V.call(121, -27), V.call(128, -12), V.call(140, -7),
		V.call(204, -7), V.call(216, -12), V.call(223, -27), V.call(234, -35), V.call(372, -35)], true)
	build_line("strasse", [V.call(430, 60), V.call(260, 60), V.call(170, 40), V.call(60, 30),
		V.call(-60, 30), V.call(-150, 45), V.call(-215, 110)], true, false, "allee")
	build_line("strasse", [V.call(115, 210), V.call(115, 35)], true, false, "rad")
	build_line("gehweg", [V.call(-36, 20), V.call(36, 20)], true)
	_starter_terminal(V)
	# Kontaktstände mit Brücke vor den Gates, Außenpositionen mit Bus und Treppe an den Enden
	# Kontaktstände hinter der Betriebsstraße (z = -35), Brücken bündig an der Fassade
	for x: float in [-85.0, -40.0, 5.0, 50.0]:
		build_item("stand", V.call(x, -63), 0, true)
	for x: float in [-130.0, 95.0]:
		build_item("stand_aussen", V.call(x, -63), 0, true)
	for x: float in [-67.0, -22.0, 11.0, 56.0]:
		build_item("fluggastbruecke", V.call(x, -28.8), 0, true)
	build_item("stand_gross", V.call(165, -50), 0, true)
	# Einrolllinien als echte Rolllinien (lassen sich ändern und abreißen)
	for st: Dictionary in stands():
		make_leadins(st)
	build_item("bushalt", V.call(123.5, -62), 1, true)
	for x: float in [-107.5, -62.5, -17.5, 27.5, 72.5]:
		build_item("flutlicht", V.call(x, -52), 0, true)
	build_item("tower", V.call(262, 22), 0, true)
	build_item("hangar", V.call(-200, -48), 0, true)
	build_item("parkhaus", V.call(-40, 62), 0, true)
	build_item("trafo", V.call(60, 50), 0, true)
	build_item("trafo", V.call(205, 14), 0, true)
	build_item("trafo", V.call(-70, 55), 0, true)
	build_item("wasseranschluss", V.call(40, 18), 0, true)
	build_item("wasseranschluss", V.call(219, -5), 0, true)
	build_item("heizzentrale", V.call(92, 60), 0, true)
	build_item("haltestelle", V.call(-48, 21.25), 2, true)
	# Luftseite: Gerätehalle im Westen, Catering, Tanklager, Busgarage und Feuerwache im Osten
	build_item("vorfelddepot", V.call(-160, -10), 2, true)
	build_item("catering", V.call(240, -12), 2, true)
	build_item("tanklager", V.call(250, -55), 0, true)
	build_item("busgarage", V.call(298, -59), 0, true, {"tore": 2})
	build_item("feuerwache", V.call(345, -55), 0, true, {"tore": 2})
	build_item("rettungswache", V.call(378, -50), 0, true)
	# Ortsteile in der Nachbarschaft (Fluglärm, Beschwerden): eins in der östlichen Anflugschneise
	build_item("wohngebiet", V.call(2050, -272), 0, true)
	build_item("wohngebiet", V.call(-300, 420), 0, true)
	build_item("wohngebiet", V.call(500, -760), 0, true)
	build_item("gepaeckumschlag", V.call(295, -10), 2, true, {"tore": 3})
	build_item("personalgebaeude", V.call(150, 14), 0, true)
	# Befeuerung: Station mit Strom, Anflugbefeuerung und PAPI an beiden Pistenenden, Rollhalteorte
	build_item("befeuerungsstation", V.call(-192, -12), 0, true)
	build_line("stromkabel", [V.call(-160, 3), V.call(-192, 3), V.call(-192, -9)], true)
	build_line("stromkabel", [V.call(-185, 3), V.call(-212, 3), V.call(-212, -29)], true)
	for e: Vector3 in [V.call(-1300, -272), V.call(1300, -272)]:
		build_item("anflugbefeuerung", e, 0, true)
		build_item("papi", e, 0, true)
	for hp: Vector3 in _auto_holds(90.0):
		build_item("rollhalt", hp, 0, true)
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
	build_line("stromkabel", [V.call(359, -50), V.call(370, -50)], true)
	build_line("stromkabel", [V.call(209, 17), V.call(257, 20)], true)
	build_line("stromkabel", [V.call(267, 16), V.call(283, -3)], true)
	build_line("stromkabel", [V.call(-66, 55), V.call(-57, 55)], true)
	build_line("stromkabel", [V.call(-74, 51), V.call(-120, 34), V.call(-160, 12), V.call(-160, -1)], true)
	# Wasser: Anschluss 1 fürs Terminal und die Heizzentrale, Anschluss 2 für Catering, Feuerwache, Personal
	build_line("wasserrohr", [V.call(40, 20), V.call(40, 15)], true)
	build_line("wasserrohr", [V.call(42, 19), V.call(82, 57)], true)
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
	put.call("tuer", 84, -8, 0, {"art": "personal"})
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
	put.call("gepaeckanlage", 90, -20)
	put.call("gepaeckroentgen", 90, -12.5, 1)
	put.call("personalraum", 100, -10.5)
	# Lager im Personalbereich: Regale, von hier bringen Mitarbeiter Ware in Läden und Cafés
	build_room(Rect2(80, -16, 6, 8), "", "personal", "lager", true)
	put.call("regal", 83, -14.9)
	put.call("regal", 83, -11.5)
	# Heizkörper an den Außenwänden
	for x: float in [-136.0, -125.0, -95.0, -82.0, -70.0, -60.0, -35.0, -20.0, -10.0, 10.0, 20.0, 34.0, 60.0, 72.0, 86.0, 100.0]:
		put.call("heizkoerper", x, 15.75)
	for x: float in [-136.0, -103.0, -88.0, -58.0, -30.0, 2.0, 32.0, 47.0, 85.0]:
		put.call("heizkoerper", x, -23.75)
	for z: float in [-18.0, 6.0]:
		put.call("heizkoerper", 107.75, z, 1)
	# Kofferbänder: Check-ins (Sammelband hinten) → unter der Decke → durch die Innenwand → Sortierung
	build_line("kofferband", [V.call(-84.55, 1.34), V.call(-43.45, 1.34)], true)
	build_line("kofferband", [V.call(-24.55, 1.34), V.call(-17, 1.34)], true)
	build_line("kofferband", [V.call(-17, 1.34), V.call(-17, 5)], true)
	build_line("kofferband", [V.call(-17, 5), V.call(90, 5)], true)
	# durch die Wand in die Gepäckdurchleuchtung, von dort direkt in die Sortierung
	build_line("kofferband", [V.call(90, 5), V.call(90, -8)], true)
	# Sortierung → durch Innen- und Glaswand → Einläufe der beiden Gepäckbänder (Abzweig zum zweiten)
	build_line("kofferband", [V.call(85.5, -20), V.call(74, -20)], true)
	build_line("kofferband", [V.call(74, -20), V.call(74, -7)], true)
	build_line("kofferband", [V.call(74, -7), V.call(39.5, -7)], true)
	build_line("kofferband", [V.call(39.5, -7), V.call(39.5, -1.5)], true)
	build_line("kofferband", [V.call(54.5, -1.5), V.call(54.5, -7)], true)
	# Rolltor hinter der Sortierung: hier halten die Gepäckzüge, die Koffer laufen über die Rollenbahn hinein
	put.call("rolltor", 105, -23, 2)
	build_line("kofferband", [V.call(102.9, -21.5), V.call(94.5, -21.5)], true)
