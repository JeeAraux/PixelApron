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
var betrieb: Variant = null    # operations.gd (Statistik)
var lost_recent := 0.0         # Spielminuten, in denen noch über verlorene Koffer geklagt wird
var lost_unhandled := false    # verlorene Koffer ohne Gepäckermittlung
var non_schengen_seen := false
var bridges: Dictionary = {}   # Instanz-ID des Gates -> Fluggastbrücke
const Models = preload("res://scripts/models.gd")
const Kit = preload("res://scripts/mesh_kit.gd")
const Interior = preload("res://scripts/interior.gd")
const BRIDGE_REACH := 38.0
var bus_cb: Callable            # ground_ops.pax_at_door(Flug-ID): ein Abfliegender ist an der Bus-Tür
var doors: Array = []           # [Tür-Datensatz, Öffnung 0..1]
var staff_t := 0.0               # Takt für Mitarbeiter, die zu ihren Plätzen gehen
## Mitarbeiter je Einrichtung (Schichtstärke) für die Personalrechnung
const STAFF_NEED := {"checkin": 4, "sicherheit": 8, "gate": 2, "busgate": 2, "passkontrolle": 6, "zoll": 3,
	"gepaeckanlage": 6, "gepaeckband": 1, "cafe": 4, "shop": 2, "infoschalter": 2, "kiosk": 1, "wc": 1,
	"airline_lounge": 4, "gepaeckermittlung": 2, "gepaeckroentgen": 3}
const STAFF_PER_STAND := 6
## Arbeitsplätze, zu denen Mitarbeiter aus dem Personalraum gehen
const WORKPLACES := ["checkin", "sicherheit", "gate", "busgate", "passkontrolle", "zoll", "gepaeckanlage", "infoschalter",
	"cafe", "shop", "gepaeckband", "kiosk"]


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
	game.refresh_belts()
	for h: Dictionary in game.items_of("halle"):
		var counts := {}
		for it: Dictionary in game.inside_of(h):
			if Catalog.is_zone(String(it["id"])):
				continue
			counts[it["id"]] = int(counts.get(it["id"], 0)) + 1
		counts["checkin_band"] = game.checkins_linked(h).size()
		counts["claim_band"] = game.claims_linked(h).size()
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
			if not Catalog.ITEMS.has(id):
				continue
			var pts := int(Catalog.ITEMS[id].get("decor", 0))
			if id == "anzeige" and not powered:
				pts = 0
			decor += pts * int(counts[id])
		var hid := (h["node"] as Node).get_instance_id()
		grids[hid] = _make_grids(h)
		var problems := []
		if missing.is_empty():
			problems = _security_problems(h, grids[hid])
			if not game.legacy_belts and int(counts.get("checkin", 0)) > 0 and int(counts["checkin_band"]) == 0:
				problems.append("Check-in nicht über ein Kofferband mit der Gepäcksortierung verbunden")
			if not game.legacy_claims and int(counts.get("gepaeckband", 0)) > 0 and int(counts["claim_band"]) == 0:
				problems.append("Gepäckband nicht über ein Kofferband mit der Gepäcksortierung verbunden (Einlauf an der Schmalseite)")
		var info := {
			"hall": h, "counts": counts, "missing": missing, "powered": powered, "area": area, "problems": problems,
			"complete": powered and missing.is_empty() and problems.is_empty() and int(counts.get("gepaeckanlage", 0)) > 0,
			"warm": clampf(heated / maxf(area, 1.0), 0.0, 1.0), "decor": decor,
			"wc": int(counts.get("wc", 0)) if game.supplied(h, "wasser") else 0,
		}
		halls.append(info)
	_rebuild_bridges()
	var old_open := {}
	for d: Array in doors:
		old_open[(d[0] as Dictionary).get("node")] = d[1]
	doors = []
	for it: Dictionary in game.items:
		if Catalog.is_door(String(it["id"])):
			doors.append([it, float(old_open.get(it.get("node"), 0.0))])
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
	# Schalter am Kofferband schaffen ein Viertel mehr
	# nur Schalter mit Kofferband zur Sortierung arbeiten (alte Spielstände: alle, mit Band ein Viertel mehr)
	var cap := float(Catalog.ITEMS["checkin"]["cap"])
	var desks := float(_sum("checkin_band")) * cap * 1.25
	if game.legacy_belts:
		desks += float(_sum("checkin") - _sum("checkin_band")) * cap
	return minf(desks,
		float(_sum("sicherheit") * int(Catalog.ITEMS["sicherheit"]["cap"])))


func capacity_arr() -> float:
	# nur Gepäckbänder mit Kofferband von der Sortierung (alte Spielstände: alle)
	var n := _sum("gepaeckband") if game.legacy_claims else _sum("claim_band")
	return float(n * int(Catalog.ITEMS["gepaeckband"]["cap"]))


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
	# Läden hinter der Kontrolle verdienen die Hälfte mehr (dort warten die Reisenden)
	var airside := 0
	var all := 0
	for info: Dictionary in _complete():
		var h: Dictionary = info["hall"]
		for it: Dictionary in game.inside_of(h):
			if it["id"] == "cafe" or it["id"] == "shop":
				all += 1
				if game.zone_at(h, (it["rect"] as Rect2).get_center(), GameState.floor_of(it)) == "sicherheit":
					airside += 1
	if all > 0:
		total = roundi(float(total) * (1.0 + 0.5 * float(airside) / float(all)))
	return total


## Anteil der Fluggäste, deren Koffer nicht ankommt: Durchleuchtung und Förderband zum Umschlag
## senken die Fehlleitungen, eine Gepäckband-Zuordnung zum Gate auch.
func lost_rate(hall: Dictionary) -> float:
	var r := 0.05
	if not _any(hall, "gepaeckroentgen").is_empty():
		r -= 0.02
	if not game.baggage_link(hall).is_empty():
		r -= 0.015
	if game.checkins_linked(hall).size() > 0:
		r -= 0.01
	for it: Dictionary in game.inside_of(hall):
		if it["id"] == "gepaeckband" and int(game.opt(it, "gate")) > 0:
			r -= 0.005
			break
	return maxf(r, 0.005)


func has_fastlane() -> bool:
	for it: Dictionary in game.items_of("sicherheit"):
		if bool(game.opt(it, "fastlane")):
			return true
	return false


## Zusatzerlöse eines abfliegenden Flugs: Lounge-Gäste (Vielflieger) und Mietwagenrückgaben.
func extra_income(p: Dictionary) -> int:
	var pax := int(Catalog.PLANES[p["kind"]]["pax"])
	var total := 0
	var business := roundi(float(pax) * 0.08)
	if has_fastlane():
		total += business * 6
	if _sum("airline_lounge") > 0:
		var guests := business
		total += guests * 25
		if betrieb != null:
			betrieb.stats["lounge"] = int(betrieb.stats["lounge"]) + guests
	for it: Dictionary in game.items_of("mietwagen"):
		if game.supplied(it, "strom"):
			total += roundi(float(pax) * 0.8)
			break
	return total


## Personal: gebraucht (Schalter, Kontrolle, Gates, Stände …) und vorhanden (Personalgebäude mit Strom).
func staff_needed() -> int:
	var n := 0
	for info: Dictionary in halls:
		var counts: Dictionary = info["counts"]
		for id: String in STAFF_NEED:
			n += int(counts.get(id, 0)) * int(STAFF_NEED[id])
	n += game.stands().size() * STAFF_PER_STAND
	return n


func staff_available() -> int:
	var n := 0
	for b: Dictionary in game.items_of("personalgebaeude"):
		if game.supplied(b, "strom"):
			n += int(Catalog.ITEMS["personalgebaeude"]["staff"])
	return n


## Faktor für die Abfertigungszeit bei Personalmangel (1 = genug Personal, bis 1,5).
func staff_slowdown() -> float:
	if dirty:
		_analyze()
	var need := staff_needed()
	if need <= 0:
		return 1.0
	var short := clampf(1.0 - float(staff_available()) / float(need), 0.0, 1.0)
	return 1.0 + 0.5 * short


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
	# Bedürfnisse hinter der Kontrolle: etwas zu essen und zu trinken, Lounge, Gepäck
	var food := false
	var zoned := false
	for info: Dictionary in done:
		var h: Dictionary = info["hall"]
		if game.zones_of(h).is_empty():
			food = food or int((info["counts"] as Dictionary).get("cafe", 0)) + int((info["counts"] as Dictionary).get("kiosk", 0)) + int((info["counts"] as Dictionary).get("snackautomat", 0)) > 0
			continue
		zoned = true
		for it: Dictionary in game.inside_of(h):
			if it["id"] in ["cafe", "kiosk", "snackautomat", "getraenkeautomat", "airline_lounge"] and game.zone_at(h, (it["rect"] as Rect2).get_center(), GameState.floor_of(it)) == "sicherheit":
				food = true
	if not food:
		out.append(["Hunger: nichts zu essen im Wartebereich" if zoned else "Hunger: kein Café, Kiosk oder Automat", -4])
		if hint == "":
			hint = "Café, Kiosk oder Snackautomat in den Sicherheitsbereich stellen"
	if lost_recent > 0.0 and lost_unhandled:
		out.append(["Verlorene Koffer und keine Gepäckermittlung", -4])
		if hint == "":
			hint = "Gepäckermittlung (Lost & Found) nahe den Gepäckbändern bauen"
	if non_schengen_seen and _sum("gepaeckroentgen") == 0:
		out.append(["Gepäck für Non-Schengen-Flüge wird nicht durchleuchtet", -3])
		if hint == "":
			hint = "Gepäckdurchleuchtung in den Personalbereich neben die Gepäcksortierung stellen"
	if _sum("airline_lounge") > 0:
		out.append(["Airline-Lounge für Vielflieger", 2])
	if has_fastlane():
		out.append(["Fast-Lane an der Kontrolle für Vielflieger", 1])
	var need := staff_needed()
	var have := staff_available()
	if have < need:
		out.append(["Zu wenig Personal: %d von %d Mitarbeitern" % [have, need], -mini(12, 4 + roundi(8.0 * (1.0 - float(have) / maxf(float(need), 1.0))))])
		if hint == "":
			hint = "Personalgebäude bauen und mit Strom versorgen: Abfertigung dauert sonst länger" if have == 0 else "Mehr Personal: ein weiteres Personalgebäude bauen"
	for info: Dictionary in done:
		var h: Dictionary = info["hall"]
		if int((info["counts"] as Dictionary).get("personalraum", 0)) == 0:
			out.append(["Kein Personalraum im Terminal", -3])
			if hint == "":
				hint = "Personalraum in den Personalbereich stellen"
		if not game.zones_of(h).is_empty():
			for it: Dictionary in game.inside_of(h):
				if it["id"] == "gepaeckanlage" and GameState.floor_of(it) >= 0 and game.zone_at(h, (it["rect"] as Rect2).get_center(), GameState.floor_of(it)) != "personal":
					out.append(["Gepäcksortierung offen zugänglich (nicht im Personalbereich)", -2])
					break
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
		if int(c.get("gepaeckband", 0)) > 0 and not game.legacy_claims:
			lines.append("Gepäckbänder am Kofferband von der Sortierung: %d von %d%s" % [int(c.get("claim_band", 0)), int(c.get("gepaeckband", 0)),
				"" if int(c.get("claim_band", 0)) >= int(c.get("gepaeckband", 0)) else " (Einlauf an der Schmalseite anschließen)"])
		if int(c.get("checkin", 0)) > 0:
			lines.append("Check-in am Kofferband zur Sortierung: %d von %d%s" % [int(c.get("checkin_band", 0)), int(c.get("checkin", 0)),
				"" if int(c.get("checkin_band", 0)) >= int(c.get("checkin", 0)) else (" (übrige Schalter ans Kofferband anschließen)" if not game.legacy_belts else " (Kofferband anschließen: +25 % Durchsatz)")])
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
			var ns := String(game.opt(it, "bereich")) == "non_schengen"
			if ns != (not bool(p.get("schengen", true))):
				score += 300.0
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
	var gy: float = (gate["pos"] as Vector3).y
	return [wall - n * 1.2 + along * 2.5 + Vector3(0, gy, 0), wall + n * 1.5 + along * 2.5, n]


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
	if not bool(p.get("schengen", true)):
		non_schengen_seen = true
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
		var desk := _desk(hall)
		if not desk.is_empty():
			plan.append(["go", _front(desk, 2.4, 1.6)])
			plan.append(["wait", randf_range(2.5, 4.5)])
			plan.append(["drop_bag", desk])
		var sec := _any(hall, "sicherheit")
		if not sec.is_empty():
			var lane := (-1.6 if randf() < 0.5 else 1.6) - 0.6
			var ss := _size(sec)
			plan.append(["go", _pt(sec, Vector3(lane, 0, ss.y * 0.5 + 0.7))])
			plan.append(["go", _pt(sec, Vector3(lane, 0, -ss.y * 0.5 - 0.7))])
			plan.append(["wait", randf_range(0.5, 1.5)])
		_maybe(plan, hall, "shop", 0.25)
		if not bool(p.get("schengen", true)):
			_through(plan, hall, "passkontrolle", true, 1.5)
		# Bedürfnisse: Hunger (Café, Kiosk, Automat), Toilette; Vielflieger in die Lounge
		if i % 10 == 0 and not _any(hall, "airline_lounge").is_empty():
			_maybe(plan, hall, "airline_lounge", 1.0)
			plan.append(["wait", randf_range(4.0, 8.0)])
		elif not _maybe(plan, hall, "cafe", 0.25):
			if not _maybe(plan, hall, "kiosk", 0.15):
				_maybe(plan, hall, "snackautomat", 0.1)
		_maybe(plan, hall, "wc", 0.18)
		var row: float = [-1.0, 0.6, 2.4][randi() % 3]
		var flip := 1.0 if row > 0.0 else -1.0
		var seat_x := -3.25 + float(randi() % 8) * 0.93
		plan.append(["go", _pt(gate, Vector3(seat_x, 0, row + 0.55 * -flip))])
		plan.append(["go", _pt(gate, Vector3(seat_x, 0, row - 0.05 * flip))])
		var face := Basis(Vector3.UP, float(gate["rot"]) * PI * 0.5) * Vector3(0, 0, -flip)
		plan.append(["sit", face])
		plan.append(["stay"])
		_spawn(p, hall, true, _pt(door, Vector3(randf_range(-2.0, 2.0), 0, 0.3)), plan)


## Gates werden je Halle von links nach rechts durchnummeriert (Gate 1, 2, …); Bänder lassen sich
## einem Gate zuordnen (Bauform "gate", 0 = alle).
func gate_number(gate: Dictionary) -> int:
	var list := []
	for h: Dictionary in game.items_of("halle"):
		for it: Dictionary in game.inside_of(h):
			if it["id"] in ["gate", "busgate"]:
				list.append(it)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector3 = a["pos"]
		var pb: Vector3 = b["pos"]
		return pa.x < pb.x - 0.5 or (absf(pa.x - pb.x) <= 0.5 and pa.z < pb.z))
	for i in range(list.size()):
		if is_same(list[i], gate):
			return i + 1
	return 0


## Band für die Ankommenden eines Gates: zugeordnetes Band, sonst das nächste freie für alle Gates.
func belt_for(hall: Dictionary, gate: Dictionary) -> Dictionary:
	var nr := gate_number(gate)
	var best: Dictionary = {}
	var bd := INF
	var any_best: Dictionary = {}
	var ad := INF
	var linked := game.claims_linked(hall)
	for it: Dictionary in game.inside_of(hall):
		if it["id"] != "gepaeckband":
			continue
		if not game.legacy_claims and not linked.is_empty() and not linked.has((it["node"] as Node).get_instance_id()):
			continue
		var d := (it["pos"] as Vector3).distance_to(gate["pos"])
		var g := int(game.opt(it, "gate"))
		if g == nr and nr > 0 and d < bd:
			bd = d
			best = it
		elif g == 0 and d < ad:
			ad = d
			any_best = it
	if not best.is_empty():
		return best
	if not any_best.is_empty():
		return any_best
	return _any(hall, "gepaeckband")


var bags_ready: Dictionary = {}   # Flug-ID -> Spielzeit, ab der seine Koffer auf dem Band liegen
var belt_load: Dictionary = {}    # Band (Instanz-ID) -> Flug-ID, dessen Koffer gerade laufen


## Die Gepäckzüge haben die Koffer eines Flugs in der Sortierung abgeladen: sie laufen aufs Band.
func bags_arrived(p_id: int, delay: float = 0.0) -> void:
	bags_ready[p_id] = clock + delay
	_claim_flow(p_id)


var claim_sent: Dictionary = {}   # Flug-ID -> true, sobald seine Koffer zum Band unterwegs sind
const CLAIM_SPEED := 2.5


## Koffer eines Flugs laufen sichtbar von der Sortierung über die Kofferbänder auf sein Gepäckband.
## Das Band füllt sich, sobald die ersten ankommen (höchstens 40 s später als ohne Weg).
func _claim_flow(p_id: int) -> void:
	if claim_sent.has(p_id) or not bags_ready.has(p_id):
		return
	var band_id := -1
	for bid: int in belt_load:
		if int(belt_load[bid]) == p_id:
			band_id = bid
	if band_id < 0:
		return
	var route: PackedVector3Array = game.bag_routes().get(band_id, PackedVector3Array())
	if route.size() < 2:
		return
	claim_sent[p_id] = true
	var cum := PackedFloat32Array([0.0])
	for i in range(1, route.size()):
		cum.append(cum[i - 1] + route[i].distance_to(route[i - 1]))
	var wait := maxf(0.0, float(bags_ready[p_id]) - clock)
	bags_ready[p_id] = clock + maxf(wait, minf(cum[cum.size() - 1] / CLAIM_SPEED, 40.0))
	_bag_arrived(route[0])
	for i in range(10):
		var mi := MeshInstance3D.new()
		mi.mesh = Models.bag_mesh_col(Interior.BAG_COLS[(p_id + i * 3) % Interior.BAG_COLS.size()])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		mi.position = route[0]
		moving_bags.append({"node": mi, "route": route, "cum": cum, "s": -float(i) * 2.2, "v": CLAIM_SPEED, "claim": true})


## Ein Koffer vom Gepäckzug läuft durchs Rolltor zur Sortierung (wenn ein Kofferband anschließt).
func gate_bag(gate_node: Node) -> void:
	if not is_instance_valid(gate_node) or moving_bags.size() > 220:
		return
	var route: PackedVector3Array = game.bag_routes().get(gate_node.get_instance_id(), PackedVector3Array())
	if route.size() < 2:
		return
	var cum := PackedFloat32Array([0.0])
	for i in range(1, route.size()):
		cum.append(cum[i - 1] + route[i].distance_to(route[i - 1]))
	var mi := MeshInstance3D.new()
	mi.mesh = Models.bag_mesh_col(Interior.BAG_COLS[moving_bags.size() % Interior.BAG_COLS.size()])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	mi.position = route[0]
	moving_bags.append({"node": mi, "route": route, "cum": cum, "s": 0.0, "v": CLAIM_SPEED})


## Ankommende betreten das Terminal am Gate (oder durch die Tür des Bus-Gates) und gehen zum Band.
func _arrivals(p: Dictionary, gate: Dictionary, n: int, start: Vector3, spacing: float) -> void:
	var hall: Dictionary = gate["hall"]
	var band := belt_for(hall, gate)
	if not band.is_empty():
		belt_load[(band["node"] as Node).get_instance_id()] = int(p["id"])
		_claim_flow(int(p["id"]))
	var rate := lost_rate(hall)
	var desk := _any(hall, "gepaeckermittlung")
	for i in range(n):
		var plan := [["wait", float(i) * spacing], ["show"], ["hide_bag"]]
		if not bool(p.get("schengen", true)):
			_through(plan, hall, "passkontrolle", false, 1.2)
		var lost := randf() < rate
		if betrieb != null:
			betrieb.stats["koffer"] = int(betrieb.stats["koffer"]) + PAX_PER_FIGURE
			if lost:
				betrieb.stats["koffer_weg"] = int(betrieb.stats["koffer_weg"]) + 1
		if lost:
			lost_recent = 240.0
			lost_unhandled = desk.is_empty()
		if not band.is_empty():
			var bs := _size(band)
			plan.append(["go", _pt(band, Vector3(randf_range(-bs.x * 0.4, bs.x * 0.4), 0, bs.y * 0.5 + 0.5 + randf() * 0.8))])
			plan.append(["bags", int(p["id"])])
			plan.append(["wait", randf_range(2.0, 9.0) + (6.0 if lost else 0.0)])
			if not lost:
				plan.append(["take_bag"])
		if lost and not desk.is_empty():
			# Koffer kam nicht an: zur Gepäckermittlung
			plan.append(["go", _front(desk, 1.4, 1.0)])
			plan.append(["wait", randf_range(4.0, 7.0)])
		if not bool(p.get("schengen", true)):
			_through(plan, hall, "zoll", false, 0.6)
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


## Durch eine Kontrolle gehen: forward = von vorn (+Z) nach hinten, sonst umgekehrt; kurz anhalten.
func _through(plan: Array, hall: Dictionary, id: String, forward: bool, stop: float) -> void:
	var it := _any(hall, id)
	if it.is_empty():
		return
	var s := _size(it)
	var x := randf_range(-s.x * 0.35, s.x * 0.35)
	var a := _pt(it, Vector3(x, 0, s.y * 0.5 + 0.6))
	var b := _pt(it, Vector3(x, 0, -s.y * 0.5 - 0.6))
	plan.append(["go", a if forward else b])
	plan.append(["wait", randf_range(stop * 0.6, stop * 1.4)])
	plan.append(["go", b if forward else a])


func _maybe(plan: Array, hall: Dictionary, id: String, chance: float) -> bool:
	if randf() >= chance:
		return false
	var it := _any(hall, id)
	if it.is_empty():
		return false
	var s := _size(it)
	plan.append(["go", _front(it, s.x * 0.35, 0.8)])
	plan.append(["wait", randf_range(2.0, 5.0)])
	return true


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


var clock := 0.0


func step(sim: float) -> void:
	clock += sim
	lost_recent = maxf(0.0, lost_recent - sim * 0.5)
	if dirty:
		_analyze()
	_bag_step(sim)
	_move_bridges(sim)
	_belts(sim)
	_animate_inside(sim)
	_animate_doors(sim)
	_staff_tick(sim)
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
		"drop_bag":
			# Koffer abgeben: er läuft über die Bänder zur Sortierung
			var mine := node.get_node_or_null("Koffer") as Node3D
			if mine != null:
				mine.visible = false
			_bag_drop(st[1])
			per["si"] = si + 1
		"hide_bag", "take_bag":
			var bag := node.get_node_or_null("Koffer") as Node3D
			if bag != null:
				bag.visible = st[0] == "take_bag"
			per["si"] = si + 1
		"bags":
			# am Band warten, bis die Koffer des Flugs da sind (spätestens nach drei Minuten)
			per["timer"] = float(per["timer"]) + sim
			Factory.set_pose(node, 0)
			var ready_at := float(bags_ready.get(int(st[1]), INF))
			if clock >= ready_at or float(per["timer"]) > 180.0:
				per["timer"] = 0.0
				per["si"] = si + 1
		"go":
			var path: Array = per["path"]
			var here: Vector3 = per["pos"]
			var goal: Vector3 = st[1]
			var fa := _floor_at(here)
			var fb := _floor_at(goal)
			if fa != fb and path.is_empty():
				# andere Ebene: erst zum Verbinder, dann fahren, dann weiter
				var dir := 1 if fb > fa else -1
				var con := _connector(int(per["hall_id"]), fa, dir, here)
				if con.is_empty():
					per["pos"] = goal
					node.position = goal
					per["si"] = si + 1
					return
				plan.insert(si, ["ride", con[1], con[2], String(con[0]["id"])])
				plan.insert(si, ["go", con[1]])
				return
			if path.is_empty():
				path = _path(int(per["hall_id"]), per["pos"], st[1], bool(per["dep"]), String(per.get("mode", "")))
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
			per["pos"] = pos
			per["pi"] = pi
			node.position = pos
			Factory.walk(node, float(per["walk"]), look, sim)
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
		"ride":
			# Rolltreppe, Treppe oder Aufzug: vom unteren zum oberen Ende (oder umgekehrt)
			var a: Vector3 = st[1]
			var b: Vector3 = st[2]
			var speed := 0.55 if st[3] == "rolltreppe" else (0.45 if st[3] == "treppe" else 1.2)
			per["timer"] = float(per["timer"]) + sim
			var dur := maxf(a.distance_to(b) / speed, 1.0)
			var t := clampf(float(per["timer"]) / dur, 0.0, 1.0)
			var pos := a.lerp(b, t)
			if st[3] == "aufzug":
				pos = Vector3(a.x, lerpf(a.y, b.y, smoothstep(0.0, 1.0, t)), a.z)
			per["pos"] = pos
			node.position = pos
			var flat := Vector3(b.x - a.x, 0, b.z - a.z)
			if flat.length() > 0.1:
				node.basis = Basis.looking_at(flat.normalized(), Vector3.UP)
			Factory.set_pose(node, 0 if st[3] != "treppe" else 1 + int(float(per["timer"]) / 0.3) % 4)
			if t >= 1.0:
				per["timer"] = 0.0
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
	var oneway := _cell_set(_cells_of(h, "sb_ausgang"))
	# 0. Bereiche: Gates im Sicherheitsbereich, Eingang und Check-in öffentlich
	for it: Dictionary in game.inside_of(h):
		var iid := String(it["id"])
		var zc: String = game.zone_at(h, (it["rect"] as Rect2).get_center(), GameState.floor_of(it))
		if (iid == "gate" or iid == "busgate") and zc != "sicherheit":
			out.append("Gates müssen im Sicherheitsbereich liegen: Bereich »Sicherheitsbereich« über die Gates ziehen")
			return out
		if (iid == "eingang" or iid == "checkin") and (zc == "sicherheit" or zc == "personal"):
			out.append("Eingang und Check-in gehören in den öffentlichen Bereich")
			return out
	# 1. Ohne durch die Kontrolle (und ohne verkehrt durch den Ausgang) zu den Gates?
	var free := _flood(g, "arr", entries, oneway)
	for key: String in free:
		var parts := key.split(",")
		if game.zone_at(h, Vector2(float(parts[0]) + 0.5, float(parts[1]) + 0.5), int(parts[2])) == "sicherheit":
			out.append("Sicherheitsbereich offen: Vom Eingang kommt man ohne Kontrolle hinein. Mit Wänden, Glaswänden oder Personaltüren abtrennen.")
			return out
	for c: Array in gates:
		if free.has(_ckey(c)):
			out.append("Sicherheitsbereich offen: Gates sind ohne Kontrolle erreichbar. Mit Wänden oder Glaswänden abtrennen.")
			return out
	# 2. Kommen Abfliegende durch die Kontrolle zu den Gates?
	var dep_reach := _flood(g, "dep", entries, {})
	var any_gate := false
	for c: Array in gates:
		any_gate = any_gate or dep_reach.has(_ckey(c))
	if not any_gate:
		out.append("Kein Weg vom Eingang durch die Kontrolle zu den Gates")
		return out
	# 3. Kommen Ankommende hinaus?
	var arr_reach := _flood(g, "arr", gates, {})
	var any_exit := false
	for c: Array in entries:
		any_exit = any_exit or arr_reach.has(_ckey(c))
	if not any_exit:
		out.append("Ankommende kommen nicht aus dem Sicherheitsbereich: Ausgang Sicherheitsbereich bauen")
		return out
	# 4. Non-Schengen-Bereich nur durch die Passkontrolle
	var ns_gates := []
	var s_gates := []
	for it: Dictionary in game.inside_of(h):
		if not (it["id"] in ["gate", "busgate"]):
			continue
		if String(game.opt(it, "bereich")) == "non_schengen":
			ns_gates.append_array(_cells_of_item(it))
		else:
			s_gates.append_array(_cells_of_item(it))
	if not ns_gates.is_empty():
		var pk := _cells_of(h, "passkontrolle")
		if pk.is_empty():
			out.append("Non-Schengen-Gates brauchen eine Passkontrolle")
			return out
		var from_s := _flood(g, "dep", s_gates + entries, _cell_set(pk))
		for c: Array in ns_gates:
			if from_s.has(_ckey(c)):
				out.append("Non-Schengen-Bereich offen: mit Wänden abtrennen, Zugang nur durch die Passkontrolle")
				return out
	return out


static func _ckey(c: Array) -> String:
	return "%d,%d,%d" % [int((c[0] as Vector2i).x), int((c[0] as Vector2i).y), int(c[1])]


func _cell_set(cells: Array) -> Dictionary:
	var out := {}
	for c: Array in cells:
		out[_ckey(c)] = true
	return out


## Zellen [Vector2i, Ebene] aller Teile einer Art in der Halle.
func _cells_of(h: Dictionary, id: String) -> Array:
	var out := []
	for it: Dictionary in game.inside_of(h):
		if it["id"] == id:
			out.append_array(_cells_of_item(it))
	return out


func _cells_of_item(it: Dictionary) -> Array:
	var out := []
	var f := GameState.floor_of(it)
	var ir: Rect2 = (it["rect"] as Rect2).grow(-0.25)
	for x in range(floori(ir.position.x), ceili(ir.end.x)):
		for z in range(floori(ir.position.y), ceili(ir.end.y)):
			out.append([Vector2i(x, z), f])
	return out


## Flutfüllung über alle Ebenen; Rolltreppen, Aufzüge und Treppen verbinden ihre Ebene mit der darüber.
func _flood(g: Dictionary, mode: String, starts: Array, blocked: Dictionary) -> Dictionary:
	var seen := {}
	var queue := []
	var links: Dictionary = g.get("links", {})
	for c: Array in starts:
		var gf: Dictionary = g.get(int(c[1]), {})
		if gf.is_empty():
			continue
		var grid: AStarGrid2D = gf[mode]
		var cell: Vector2i = c[0]
		var key := _ckey(c)
		if grid.is_in_boundsv(cell) and not grid.is_point_solid(cell) and not blocked.has(key) and not seen.has(key):
			seen[key] = true
			queue.append(c)
	var qi := 0
	while qi < queue.size():
		var c: Array = queue[qi]
		qi += 1
		var cell: Vector2i = c[0]
		var f: int = c[1]
		var grid: AStarGrid2D = g[f][mode]
		var nexts := []
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			nexts.append([cell + d, f])
		for lf: int in links.get(_ckey(c), []):
			nexts.append([cell, lf])
		for nx: Array in nexts:
			var key := _ckey(nx)
			if seen.has(key) or blocked.has(key):
				continue
			var nf: int = nx[1]
			if not g.has(nf):
				continue
			var ng: AStarGrid2D = g[nf][mode]
			var ncell: Vector2i = nx[0]
			if not ng.is_in_boundsv(ncell) or ng.is_point_solid(ncell):
				continue
			seen[key] = true
			queue.append(nx)
	return seen


## Raster und Ebenenverbindungen einer Halle: {Ebene: {"dep", "arr"}, "links": {Zelle: [Ebenen]}}
func _make_grids(h: Dictionary) -> Dictionary:
	var out := {}
	var lo := -1 if game.hall_basement(h) else 0
	for f in range(lo, game.hall_levels(h)):
		out[f] = {"dep": _make_grid(h, "dep", f), "arr": _make_grid(h, "arr", f), "staff": _make_grid(h, "staff", f)}
	var links := {}
	for it: Dictionary in game.inside_of(h):
		if not bool(Catalog.ITEMS[it["id"]].get("connector", false)):
			continue
		var f := GameState.floor_of(it)
		for c: Array in _cells_of_item(it):
			var up := [c[0], f + 1]
			if not links.has(_ckey(c)):
				links[_ckey(c)] = []
			(links[_ckey(c)] as Array).append(f + 1)
			if not links.has(_ckey(up)):
				links[_ckey(up)] = []
			(links[_ckey(up)] as Array).append(f)
	out["links"] = links
	return out


## mode "dep": Ausgang Sicherheitsbereich ist zu (Einbahn), "arr": Kontrolle ist zu.
func _make_grid(h: Dictionary, mode: String = "dep", f: int = 0) -> AStarGrid2D:
	var r: Rect2 = h["rect"]
	var g := AStarGrid2D.new()
	g.region = Rect2i(floori(r.position.x), floori(r.position.y), ceili(r.size.x), ceili(r.size.y))
	g.cell_size = Vector2(1, 1)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	for it: Dictionary in game.inside_of(h):
		var itf := GameState.floor_of(it)
		var def: Dictionary = Catalog.ITEMS[it["id"]]
		if Catalog.is_zone(String(it["id"])):
			continue
		# Verbinder ragen in die Ebene darüber (dort ist ihr oberes Ende begehbar)
		if itf != f and not (bool(def.get("connector", false)) and itf + 1 == f):
			continue
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
		if GameState.floor_of(l) != f:
			continue
		for v: Vector3 in game.wall_probe(l):
			var c := Vector2i(floori(v.x), floori(v.z))
			if g.is_in_boundsv(c):
				g.set_point_solid(c, true)
	# Türen öffnen die Wand (Personaltüren nur für Mitarbeiter)
	for it: Dictionary in game.inside_of(h):
		if not Catalog.is_door(String(it["id"])) or GameState.floor_of(it) != f:
			continue
		if mode != "staff" and String(game.opt(it, "art")) == "personal":
			continue
		for c: Array in _cells_of_item(it):
			var cell: Vector2i = c[0]
			if g.is_in_boundsv(cell):
				g.set_point_solid(cell, false)
	# Personalbereich ist für Fluggäste gesperrt
	if mode != "staff":
		for z: Dictionary in game.zones_of(h):
			if GameState.floor_of(z) != f or String(Catalog.ITEMS[z["id"]]["zone"]) != "personal":
				continue
			var zr: Rect2 = z["rect"]
			for x in range(floori(zr.position.x), ceili(zr.end.x)):
				for zz in range(floori(zr.position.y), ceili(zr.end.y)):
					var c := Vector2i(x, zz)
					if g.is_in_boundsv(c) and game.zone_at(h, Vector2(float(x) + 0.5, float(zz) + 0.5), f) == "personal":
						g.set_point_solid(c, true)
	return g


func _cell(g: AStarGrid2D, p: Vector3) -> Vector2i:
	var r := g.region
	return Vector2i(clampi(floori(p.x), r.position.x, r.end.x - 1), clampi(floori(p.z), r.position.y, r.end.y - 1))


static func _floor_at(p: Vector3) -> int:
	return roundi(p.y / Catalog.FLOOR_H)


## Weg auf einer Ebene (a und b auf derselben Ebene).
func _path(hall_id: int, a: Vector3, b: Vector3, dep: bool = true, mode: String = "") -> Array:
	var f := _floor_at(a)
	if not grids.has(hall_id) or not (grids[hall_id] as Dictionary).has(f):
		return [b]
	var g: AStarGrid2D = grids[hall_id][f][mode if mode != "" else ("dep" if dep else "arr")]
	var ca := _cell(g, a)
	var cb := _cell(g, b)
	var sa := g.is_point_solid(ca)
	var sb := g.is_point_solid(cb)
	g.set_point_solid(ca, false)
	g.set_point_solid(cb, false)
	var ids := g.get_id_path(ca, cb, true)
	var y := float(f) * Catalog.FLOOR_H
	# Treppenstufen des Rasters glätten: nur Eckpunkte behalten, zwischen denen die Sicht frei ist,
	# und jedem Menschen einen kleinen Versatz geben, damit nicht alle auf derselben Linie laufen
	var raw := [Vector2(a.x, a.z)]
	for i in range(1, ids.size() - 1):
		raw.append(Vector2(float(ids[i].x) + 0.5, float(ids[i].y) + 0.5))
	raw.append(Vector2(b.x, b.z))
	var keep := [raw[0]]
	var anchor := 0
	var i2 := 1
	while i2 < raw.size():
		var far := i2
		var j := i2 + 1
		while j < raw.size() and j - anchor < 40 and _clear_line(g, raw[anchor], raw[j]):
			far = j
			j += 1
		keep.append(raw[far])
		anchor = far
		i2 = far + 1
	g.set_point_solid(ca, sa)
	g.set_point_solid(cb, sb)
	var jitter := Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
	var out := []
	for k in range(1, keep.size()):
		var q: Vector2 = keep[k]
		if k < keep.size() - 1 and not g.is_point_solid(_cell(g, Vector3(q.x + jitter.x, 0, q.y + jitter.y))):
			q += jitter
		out.append(Vector3(q.x, y, q.y))
	if out.is_empty():
		out.append(Vector3(b.x, y, b.z))
	return out


## Freie Sicht im Raster zwischen zwei Punkten (alle Zellen entlang der Linie begehbar, Abstand 0,3 m zum Rand)?
func _clear_line(g: AStarGrid2D, p: Vector2, q: Vector2) -> bool:
	var d := q - p
	var n := maxi(1, ceili(d.length() / 0.35))
	var side := Vector2(-d.y, d.x).normalized() * 0.28 if d.length() > 0.01 else Vector2.ZERO
	for k in range(n + 1):
		var c := p + d * (float(k) / float(n))
		for o: Vector2 in [Vector2.ZERO, side, -side]:
			var cell := _cell(g, Vector3(c.x + o.x, 0, c.y + o.y))
			if not g.is_in_boundsv(cell) or g.is_point_solid(cell):
				return false
	return true


## Verbinder für eine Fahrt von Ebene f eine Ebene in Richtung dir (+1/-1), nah an p: [Teil, Start, Ziel] oder leer.
func _connector(hall_id: int, f: int, dir: int, p: Vector3) -> Array:
	var best: Array = []
	var bd := INF
	for it: Dictionary in game.items:
		if not bool(Catalog.ITEMS.get(it["id"], {}).get("connector", false)):
			continue
		if not is_instance_valid(it.get("hall", {}).get("node")) or (it["hall"]["node"] as Node).get_instance_id() != hall_id:
			continue
		var cf := GameState.floor_of(it)
		if (dir > 0 and cf != f) or (dir < 0 and cf != f - 1):
			continue
		var lo := _pt(it, Vector3(0, 0, -4.6 if it["id"] != "aufzug" else 0.0))
		var hi := _pt(it, Vector3(0, Catalog.FLOOR_H, 4.6 if it["id"] != "aufzug" else 0.0))
		var from: Vector3 = lo if dir > 0 else hi
		var to: Vector3 = hi if dir > 0 else lo
		var d := Vector2(from.x - p.x, from.z - p.z).length()
		if d < bd:
			bd = d
			best = [it, from, to]
	return best


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
			var d := (g["pos"] as Vector3).distance_to(game.bridge_anchor(it))
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
	root.add_to_group("oberirdisch")
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
		var cd := (b["cab_dir"] as Vector3).lerp(Vector3(face.x, 0.0, face.z).normalized(), clampf(sim * 0.8, 0.0, 1.0))
		cd.y = 0.0
		if cd.length() > 0.01:
			b["cab_dir"] = cd.normalized()
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
	# Ein Band läuft, solange die Koffer seines Flugs da sind und noch Ankommende davor warten
	var waiting := {}
	for per: Dictionary in people:
		if not bool(per["dep"]):
			waiting[int(per["flight"])] = true
	belt_phase += sim * 0.9
	var straight := 7.2
	var r := 1.17
	var perim := 2.0 * straight + TAU * r
	for h: Dictionary in game.items_of("halle"):
		for it: Dictionary in game.inside_of(h):
			if it["id"] != "gepaeckband":
				continue
			var cases := (it["node"] as Node3D).get_node_or_null("Koffer") as Node3D
			if cases == null:
				continue
			var bid := (it["node"] as Node).get_instance_id()
			var fid := int(belt_load.get(bid, -1))
			var running := fid >= 0 and waiting.has(fid) and clock >= float(bags_ready.get(fid, INF))
			if not running and fid >= 0 and not waiting.has(fid):
				belt_load.erase(bid)
			cases.visible = running
			if not running:
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


# ---------------------------------------------------------------- Bewegte Einrichtung

var inside_t := 0.0


## Rolltreppenstufen laufen, Aufzugskabinen fahren auf und ab.
func _animate_inside(sim: float) -> void:
	inside_t += sim
	for it: Dictionary in game.items:
		var id: String = it["id"]
		if id != "rolltreppe" and id != "aufzug":
			continue
		var node: Node3D = it["node"]
		if not is_instance_valid(node) or not node.visible:
			continue
		if id == "rolltreppe":
			var steps := node.get_node_or_null("Stufen") as Node3D
			if steps != null:
				var k := fmod(inside_t * 0.5, 8.0 / 24.0) / (8.0 / 24.0)
				steps.position = Vector3(0, Catalog.FLOOR_H / 24.0 * k, 8.0 / 24.0 * k)
		else:
			var cab := node.get_node_or_null("Kabine") as Node3D
			if cab != null:
				var ph := fmod(inside_t * 0.12 + float(it["pos"].x) * 0.01, 2.0)
				var u := clampf(ph * 1.6 - 0.3, 0.0, 1.0) if ph < 1.0 else clampf((2.0 - ph) * 1.6 - 0.3, 0.0, 1.0)
				cab.position.y = smoothstep(0.0, 1.0, u) * Catalog.FLOOR_H


# ---------------------------------------------------------------- Türen und Personal

## Türflügel gehen auf, wenn jemand näher als zwei Meter kommt (Personaltüren nur für Mitarbeiter).
func _animate_doors(sim: float) -> void:
	for d: Array in doors:
		var it: Dictionary = d[0]
		var node: Variant = it.get("node")
		if not is_instance_valid(node):
			continue
		var n := node as Node3D
		var kind := String(n.get_meta("door_kind", "automatik"))
		var c: Vector3 = it["pos"]
		var want := 0.0
		var reach := 2.2 if kind == "automatik" else 1.7
		for per: Dictionary in people:
			if kind == "personal" and not bool(per.get("staff", false)):
				continue
			var q: Vector3 = per["pos"]
			if absf(q.y - c.y) < 2.0 and Vector2(q.x - c.x, q.z - c.z).length() < reach:
				want = 1.0
				break
		var o := move_toward(float(d[1]), want, sim * (2.4 if want > 0.5 else 1.2))
		d[1] = o
		if not n.visible:
			continue
		var e := smoothstep(0.0, 1.0, o)
		for nm: String in ["TuerL", "TuerR"]:
			var leaf := n.get_node_or_null(nm) as Node3D
			if leaf == null:
				continue
			if kind == "automatik":
				var bx := float(leaf.get_meta("base_x", 0.0))
				leaf.position.x = bx + signf(bx) * e * 1.02
			else:
				leaf.rotation.y = float(leaf.get_meta("swing", 1.0)) * e * 1.45


## Mitarbeiter gehen vom Personalraum zu den Schaltern und zurück, eine Reinigungskraft schiebt
## ihren Wagen durch die öffentlichen Bereiche.
func _staff_tick(sim: float) -> void:
	staff_t -= sim
	if staff_t > 0.0:
		return
	staff_t = randf_range(6.0, 14.0)
	var count := 0
	var cleaners := 0
	for per: Dictionary in people:
		if bool(per.get("staff", false)):
			count += 1
			if bool(per.get("cleaner", false)):
				cleaners += 1
	for info: Dictionary in halls:
		var h: Dictionary = info["hall"]
		if not is_instance_valid(h.get("node")):
			continue
		var hid := (h["node"] as Node).get_instance_id()
		if not grids.has(hid):
			continue
		var area: float = info["area"]
		if cleaners < 1 and area > 400.0 and randf() < 0.5:
			_spawn_cleaner(h, hid)
			cleaners += 1
		if count >= 4 + int(area / 600.0):
			continue
		var rooms := []
		var work := []
		for it: Dictionary in game.inside_of(h):
			if it["id"] == "personalraum":
				rooms.append(it)
			elif String(it["id"]) in WORKPLACES:
				work.append(it)
		if rooms.is_empty() or work.is_empty():
			continue
		var room: Dictionary = rooms[randi() % rooms.size()]
		var job: Dictionary = work[randi() % work.size()]
		var start := _front(room, 1.5, 0.3)
		var goal := _front(job, _size(job).x * 0.3, 0.6)
		var vest := String(job["id"]) in ["gepaeckanlage", "gepaeckband"]
		var shirt: Color = Color(0.2, 0.3, 0.52) if not vest else Color(0.25, 0.27, 0.3)
		if String(job["id"]) == "sicherheit" or String(job["id"]) == "passkontrolle":
			shirt = Color(0.12, 0.2, 0.35)
		elif String(job["id"]) == "cafe":
			shirt = Color(0.15, 0.15, 0.16)
		var node: Node3D = Factory.make_staff(shirt, Color(0.12, 0.13, 0.18), randi() % 4, vest)
		node.position = start
		node.visible = false
		add_child(node)
		var plan := [["show"], ["go", goal], ["wait", randf_range(4.0, 12.0)], ["go", start], ["end"]]
		people.append({"node": node, "flight": -1, "dep": true, "hall_id": hid, "plan": plan, "si": 0, "path": [], "pi": 0,
			"timer": 0.0, "pos": start, "staff": true, "mode": "staff"})
		count += 1


func _spawn_cleaner(h: Dictionary, hid: int) -> void:
	var g: Dictionary = grids[hid]
	if not g.has(0):
		return
	var grid: AStarGrid2D = g[0]["dep"]
	var r := grid.region
	var pts := []
	var tries := 0
	while pts.size() < 5 and tries < 80:
		tries += 1
		var c := Vector2i(randi_range(r.position.x + 1, r.end.x - 2), randi_range(r.position.y + 1, r.end.y - 2))
		if grid.is_point_solid(c):
			continue
		var zc := game.zone_at(h, Vector2(float(c.x) + 0.5, float(c.y) + 0.5), 0)
		if zc == "personal":
			continue
		pts.append(Vector3(float(c.x) + 0.5, 0.0, float(c.y) + 0.5))
	if pts.size() < 2:
		return
	var node: Node3D = Factory.make_staff(Color(0.3, 0.55, 0.75), Color(0.2, 0.25, 0.32), randi() % 4)
	var cart := MeshInstance3D.new()
	cart.name = "Wagen"
	cart.mesh = preload("res://scripts/interior.gd").cleaning_cart_mesh()
	cart.position = Vector3(0, 0, -0.85)
	cart.rotation.y = PI
	node.add_child(cart)
	node.position = pts[0]
	node.visible = false
	add_child(node)
	var plan := [["show"]]
	for i in range(1, pts.size()):
		plan.append(["go", pts[i]])
		plan.append(["wait", randf_range(5.0, 10.0)])
	plan.append(["end"])
	people.append({"node": node, "flight": -1, "dep": true, "hall_id": hid, "plan": plan, "si": 0, "path": [], "pi": 0,
		"timer": 0.0, "pos": pts[0], "staff": true, "cleaner": true})


## Alte Spielstände: Bereiche aus Wänden und Kontrolle ableiten. Alles, was vom Eingang ohne
## Kontrolle erreichbar ist, wird öffentlich, der Rest Sicherheitsbereich; um die Gepäcksortierung
## kommt ein Personalbereich.
func auto_zones(h: Dictionary) -> void:
	if not game.zones_of(h).is_empty():
		return
	var g := _make_grids(h)
	var entries := _cells_of(h, "eingang")
	if entries.is_empty():
		return
	# eigenes Raster: nur Wände, Kontrolle und Ausgang sperren
	var blocked := _cell_set(_cells_of(h, "sicherheit") + _cells_of(h, "sb_ausgang") + _cells_of(h, "passkontrolle"))
	var open_g := {}
	for fk: Variant in g:
		if typeof(fk) != TYPE_INT:
			continue
		var f: int = fk
		var base: AStarGrid2D = g[f]["staff"]
		var og := AStarGrid2D.new()
		og.region = base.region
		og.cell_size = Vector2(1, 1)
		og.update()
		for l: Dictionary in game.walls_of(h):
			if GameState.floor_of(l) != f:
				continue
			for v: Vector3 in game.wall_probe(l):
				var c := Vector2i(floori(v.x), floori(v.z))
				if og.is_in_boundsv(c):
					og.set_point_solid(c, true)
		for it: Dictionary in game.inside_of(h):
			if Catalog.is_door(String(it["id"])) and GameState.floor_of(it) == f and String(game.opt(it, "art")) != "personal":
				for c: Array in _cells_of_item(it):
					if og.is_in_boundsv(c[0]):
						og.set_point_solid(c[0], false)
		open_g[f] = {"dep": og}
	open_g["links"] = g.get("links", {})
	var public := _flood(open_g, "dep", entries, blocked)
	var r: Rect2 = h["rect"]
	for fk: Variant in open_g:
		if typeof(fk) != TYPE_INT:
			continue
		var f: int = fk
		# Zeilen in Läufe zerlegen, gleiche Läufe untereinander zu Rechtecken zusammenfassen
		var rects := []
		var open_runs := {}
		for z in range(floori(r.position.y), ceili(r.end.y)):
			var runs := []
			var x := floori(r.position.x)
			while x < ceili(r.end.x):
				var secure := not public.has(_ckey([Vector2i(x, z), f]))
				if secure:
					var x0 := x
					while x < ceili(r.end.x) and not public.has(_ckey([Vector2i(x, z), f])):
						x += 1
					runs.append(Vector2i(x0, x))
				else:
					x += 1
			var next_open := {}
			for run: Vector2i in runs:
				if open_runs.has(run):
					var rr: Rect2 = open_runs[run]
					rr.size.y += 1.0
					next_open[run] = rr
				else:
					next_open[run] = Rect2(float(run.x), float(z), float(run.y - run.x), 1.0)
			for run: Vector2i in open_runs:
				if not next_open.has(run):
					rects.append(open_runs[run])
			open_runs = next_open
		for run: Vector2i in open_runs:
			rects.append(open_runs[run])
		game.build_zone("bereich_oeffentlich", r, true, f)
		for rr: Rect2 in rects:
			game.build_zone("bereich_sicherheit", rr, true, f)
	for it: Dictionary in game.inside_of(h):
		if it["id"] == "gepaeckanlage":
			var gr: Rect2 = (it["rect"] as Rect2).grow(1.0).intersection(r)
			game.build_zone("bereich_personal", Rect2(floorf(gr.position.x), floorf(gr.position.y), ceilf(gr.size.x), ceilf(gr.size.y)), true, GameState.floor_of(it))
	dirty = true


# ---------------------------------------------------------------- Koffer vom Check-in zur Sortierung

var moving_bags: Array = []        # {node, route, cum, s}
var scale_timer: Dictionary = {}   # Schalter-Knoten -> Restzeit, solange ein Koffer auf der Waage liegt
var sorter_busy: Dictionary = {}   # Sortierung (Instanz-ID) -> Zeit, bis zu der ihr Ring läuft
const BAG_SPEED := 1.3


## Schalter, an dem Abfliegende einchecken: nur solche mit Kofferband zur Sortierung.
func _desk(hall: Dictionary) -> Dictionary:
	var linked := game.checkins_linked(hall)
	var list := []
	for it: Dictionary in game.inside_of(hall):
		if it["id"] == "checkin" and (game.legacy_belts or linked.has((it["node"] as Node).get_instance_id())):
			list.append(it)
	if list.is_empty():
		return {}
	return list[randi() % list.size()]


func _bag_drop(desk: Dictionary) -> void:
	var dn: Variant = desk.get("node")
	if not is_instance_valid(dn):
		return
	var dnode := dn as Node3D
	var scale := dnode.get_node_or_null("Koffer_Waage") as Node3D
	if scale != null:
		scale.visible = true
		scale_timer[dnode] = 1.6
	var route: PackedVector3Array = game.bag_routes().get(dnode.get_instance_id(), PackedVector3Array())
	if route.size() < 2:
		return
	var cum := PackedFloat32Array([0.0])
	for i in range(1, route.size()):
		cum.append(cum[i - 1] + route[i].distance_to(route[i - 1]))
	var mi := MeshInstance3D.new()
	mi.mesh = Models.bag_mesh_col(Interior.BAG_COLS[randi() % Interior.BAG_COLS.size()])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.position = route[0]
	moving_bags.append({"node": mi, "route": route, "cum": cum, "s": -1.6})


func _bag_step(sim: float) -> void:
	for dnode: Variant in scale_timer.keys():
		scale_timer[dnode] = float(scale_timer[dnode]) - sim
		if float(scale_timer[dnode]) <= 0.0:
			if is_instance_valid(dnode):
				var sc := (dnode as Node3D).get_node_or_null("Koffer_Waage") as Node3D
				if sc != null:
					sc.visible = false
			scale_timer.erase(dnode)
	for b: Dictionary in moving_bags.duplicate():
		var node: MeshInstance3D = b["node"]
		b["s"] = float(b["s"]) + sim * float(b.get("v", BAG_SPEED))
		var cum: PackedFloat32Array = b["cum"]
		var route: PackedVector3Array = b["route"]
		var s := float(b["s"])
		if s >= cum[cum.size() - 1]:
			if not b.has("claim"):
				_bag_arrived(route[route.size() - 1])
			node.queue_free()
			moving_bags.erase(b)
			continue
		if s < 0.0:
			node.visible = false   # liegt noch auf der Waage
			continue
		var i := 0
		while i < cum.size() - 2 and cum[i + 1] < s:
			i += 1
		var seg := maxf(cum[i + 1] - cum[i], 0.001)
		var p := route[i].lerp(route[i + 1], clampf((s - cum[i]) / seg, 0.0, 1.0))
		node.position = p + Vector3(0, 0.17, 0)
		var d := route[i + 1] - route[i]
		d.y = 0.0
		if d.length() > 0.01:
			node.basis = Basis.looking_at(d.normalized(), Vector3.UP).rotated(Vector3.UP, PI * 0.5)
		# sichtbar, wenn die Ebene gezeigt wird (in der Halle) oder draußen
		var f := floori((p.y + 1.0) / Catalog.FLOOR_H)
		var inside := not game.hall_at(p).is_empty()
		node.visible = (not inside) or (game.interior_view and f == game.view_floor)
	for sid: int in sorter_busy.keys():
		if clock > float(sorter_busy[sid]):
			sorter_busy.erase(sid)
			_sorter_ring(sid, false)


## Koffer an der Sortierung angekommen: ihr Ring läuft eine Weile mit Koffern.
func _bag_arrived(p: Vector3) -> void:
	for it: Dictionary in game.items_of("gepaeckanlage"):
		if (it["rect"] as Rect2).grow(2.0).has_point(Vector2(p.x, p.z)):
			var sid := (it["node"] as Node).get_instance_id()
			if not sorter_busy.has(sid):
				_sorter_ring(sid, true)
			sorter_busy[sid] = clock + 40.0
			return


func _sorter_ring(sid: int, on: bool) -> void:
	var nd := instance_from_id(sid) as Node3D
	if nd == null:
		return
	var ring := nd.find_child("Ringkoffer", true, false) as Node3D
	if ring != null:
		ring.visible = on
