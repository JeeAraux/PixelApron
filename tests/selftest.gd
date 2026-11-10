extends Node
## Automatischer Rundgang durch die Bauwerkzeuge. Start:
## godot --path . -- --selftest   (auch ohne Fenster mit --headless)

var failures := 0


func check(cond: bool, what: String) -> void:
	print(("OK    " if cond else "FEHLER ") + what)
	if not cond:
		failures += 1


const Catalog = preload("res://scripts/catalog.gd")


func run(main: Node) -> void:
	await get_tree().process_frame
	main.set_process(false)
	var game = main.game
	var b = main.builder
	var lines0: int = game.lines.size()
	var items0: int = game.items.size()
	check(lines0 >= 5 and items0 >= 20, "Startflughafen geladen (%d Wege, %d Objekte)" % [lines0, items0])
	check(main.traffic.movers.size() > 5, "Verkehr fährt (%d Fahrzeuge)" % main.traffic.movers.size())

	# Versorgung und Flugbetrieb
	var term: Dictionary = game.items_of("halle")[0]
	var hangar0: Dictionary = game.items_of("hangar")[0]
	var tb = main.terminal
	check(game.supplied(term, "strom") and game.supplied(term, "wasser") and game.supplied(term, "waerme"), "Terminalhalle hat Strom, Wasser und Wärme")
	check(game.inside_of(term).size() > 20 and game.walls_of(term).size() == 3, "Terminal eingerichtet (%d Teile, %d Wände)" % [game.inside_of(term).size(), game.walls_of(term).size()])
	check(tb.check() == "", "Terminal betriebsbereit " + tb.check())
	check(String(hangar0["supply"].get("strom", "")) == "fehlt", "Hangar ohne Kabel hat keinen Strom")
	check(main.flights.check_operation() == "", "Flugbetrieb startklar")
	var fl = main.flights
	var m0: int = game.money
	var seen_states := {}
	var min_gap := INF
	var saw_gse := false
	var ground := ["rollt_ein", "rollt_aus", "wartet"]
	var max_people := 0
	var at_gate := false
	var at_band := false
	var crossed := ""
	var hold_min := INF
	var push_seen := false
	var tug_seen := false
	var bus_seen := false
	var stairs_seen := false
	var bus_boarded := false
	var outdoor_pax := 0
	var stand_rects := []
	for st: Dictionary in game.stands():
		stand_rects.append([st, (st["rect"] as Rect2).grow(-3.0)])
	for i in range(9000):
		fl.step(0.1)
		outdoor_pax = maxi(outdoor_pax, main.ops.walkers.size())
		for j: Dictionary in main.ops.jobs.values():
			tug_seen = tug_seen or j.has("tug")
			stairs_seen = stairs_seen or j.has("stairs")
			bus_seen = bus_seen or j.has("bus") or j.has("dep_bus")
			bus_boarded = bus_boarded or bool(j.get("boarded", false))
		for p: Dictionary in fl.planes:
			if p["state"] == "pushback" and p.get("push_phase", "") == "schieben":
				push_seen = true
			if p["state"] == "wartet":
				hold_min = minf(hold_min, fl.graph.runway_distance(p["pos"]))
			if p["state"] in ground and float(p["ghost"]) <= 0.0:
				var pp: Vector3 = p["pos"]
				for e: Array in stand_rects:
					var own: bool = is_same(e[0], p["stand"])
					if not own and (e[1] as Rect2).has_point(Vector2(pp.x, pp.z)):
						crossed = "%s (%s) bei %s" % [p["code"], p["state"], str(pp)]
		max_people = maxi(max_people, tb.people.size())
		for per: Dictionary in tb.people:
			var plan: Array = per["plan"]
			var si: int = per["si"]
			if si < plan.size() and plan[si][0] == "stay":
				at_gate = true
			if not bool(per["dep"]) and si < plan.size() and plan[si][0] == "wait" and si > 2:
				at_band = true
		for p: Dictionary in fl.planes:
			seen_states[p["state"]] = true
			if not (p["gse"] as Array).is_empty():
				saw_gse = true
		for a in range(fl.planes.size()):
			var pa: Dictionary = fl.planes[a]
			if not (pa["state"] in ground) or float(pa["ghost"]) > 0.0:
				continue
			for c in range(a + 1, fl.planes.size()):
				var pc: Dictionary = fl.planes[c]
				if pc["state"] in ground and float(pc["ghost"]) <= 0.0:
					var gap := (pa["pos"] as Vector3).distance_to(pc["pos"])
					if gap < min_gap and gap < 20.0:
						print("      zu nah: %s %s %s / %s %s %s" % [pa["code"], pa["state"], str(pa["pos"]), pc["code"], pc["state"], str(pc["pos"])])
					min_gap = minf(min_gap, gap)
	print("      Zustände: ", seen_states.keys(), "  abgeflogen: ", fl.done, "  kleinster Abstand am Boden: ", min_gap)
	var m1: int = game.money
	check(min_gap > 20.0, "Rollende Flugzeuge halten Abstand (Reservierung)")
	check(crossed == "", "Kein Flugzeug rollt über fremde Stände " + crossed)
	check(push_seen and tug_seen, "Pushback mit Schlepper")
	check(hold_min < INF and hold_min > 85.0, "Abflüge warten am Rollhalteort (%.0f m vor der Pistenmitte)" % hold_min)
	check(stairs_seen and bus_seen, "Außenpositionen: Treppenwagen und Vorfeldbusse fahren")
	check(outdoor_pax > 5 and bus_boarded, "Passagiere steigen per Bus und Treppe ein und aus (bis zu %d draußen)" % outdoor_pax)
	check(saw_gse, "Bodenfahrzeuge fahren zum Flugzeug")
	check(max_people > 10, "Passagiere laufen durchs Terminal (bis zu %d Figuren)" % max_people)
	check(at_gate, "Abfliegende Passagiere warten am Gate")
	check(at_band, "Ankommende Passagiere holen Gepäck")
	check(tb.capacity_dep() >= 300.0 and tb.capacity_arr() >= 300.0, "Kapazität: Abflug %d/h, Ankunft %d/h" % [tb.capacity_dep(), tb.capacity_arr()])
	check(tb.hall_summary(term).contains("Betriebsbereit"), "Info zur Halle")
	check(game.satisfaction >= 0.0 and game.satisfaction <= 100.0 and not game.satisfaction_factors.is_empty(), "Zufriedenheit berechnet (%d %%)" % roundi(game.satisfaction))
	var demand_before: int = game.traffic_demand
	var base_target: int = main.traffic.compute_target()
	game.traffic_demand = demand_before + 4
	check(main.traffic.compute_target() > base_target, "Mehr Flüge bringen mehr Autos (%d → %d)" % [base_target, main.traffic.compute_target()])
	game.traffic_demand = demand_before
	# Abfertigung mit und ohne Vorfelddepot
	check(not fl.depot_ok(), "Ohne Depot langsamere Abfertigung")
	var dep: Dictionary = game.build_item("vorfelddepot", Vector3(-150, 0, 10), 0)
	var dep_ok := not dep.is_empty()
	var dep_cable: Dictionary = game.build_line("stromkabel", [Vector3(-23, 0, 52), Vector3(-150, 0, 18)])
	check(dep_ok and fl.depot_ok(), "Vorfelddepot gebaut und versorgt")
	var test_plane := {"id": 999, "kind": "a320", "stand": game.stands()[0], "code": "TEST 1", "city": "Test", "gse": [], "pos": Vector3.ZERO}
	var slow_t: float = tb.slowdown()
	fl._park(test_plane)
	var expect: float = float(Catalog.PLANES["a320"]["turn"]) * slow_t * (1.0 if not (test_plane["gate"] as Dictionary).is_empty() else 1.25)
	check(is_equal_approx(float(test_plane["turn"]), expect), "Mit Depot normale Abfertigungszeit (%.0f Min)" % float(test_plane["turn"]))
	fl._clear_gse(test_plane)
	fl._release_all(999)
	main.ops.release(test_plane)
	tb.flight_left(test_plane)
	for per: Dictionary in tb.people.duplicate():
		if int(per["flight"]) == 999:
			tb._drop(per)
	game.remove(dep, 1.0)
	game.remove(dep_cable, 1.0)
	# Unterhalt um Mitternacht
	var before_mid: int = game.money
	var upkeep: int = game.upkeep_per_day()
	game.day_income = 0
	var to_midnight: float = 1440.0 - fmod(game.minutes, 1440.0) + 1.0
	game.advance(to_midnight)
	check(upkeep > 0 and game.money == before_mid - upkeep, "Unterhalt um Mitternacht abgezogen (%s)" % game.fmt_money(upkeep))
	# Info-Werkzeug
	check(game.describe(game.pick(Vector3(20, 0, 5))) == "Terminalhalle" and game.details(term).contains("Unterhalt"), "Info zeigt Gebäudedetails")
	check(game.describe(game.pick(Vector3(-15, 0, 0.5))) == "Check-in", "Info zeigt Einrichtung")
	check(seen_states.has("abfertigung"), "Flugzeug ist am Stand angekommen")
	check(fl.done >= 2, "Flugzeuge sind wieder gestartet (%d)" % fl.done)
	check(m1 > m0, "Einnahmen aus Flügen (%d €)" % (m1 - m0))
	var cable: Dictionary = {}
	for l: Dictionary in game.lines:
		if l["kind"] == "stromkabel":
			cable = l
			break
	var pts: Array = cable["points"]
	game.remove(cable, 1.0)
	check(not game.supplied(term, "strom"), "Ohne Kabel hat das Terminal keinen Strom")
	check(main.flights.check_operation() != "", "Ohne Strom keine neuen Flüge: " + main.flights.check_operation())
	game.build_line("stromkabel", pts, true)
	check(game.supplied(term, "strom"), "Kabel neu verlegt, Strom wieder da")
	var big: Dictionary = game.build_hall(Rect2(600, 600, 200, 100), true)
	var extra: Dictionary = game.build_line("stromkabel", [Vector3(56, 0, 52), Vector3(600, 0, 640)], true)
	check(String(term["supply"].get("strom", "")) == "ueberlast", "Große Halle angeschlossen: Trafo überlastet")
	game.remove(extra, 1.0)
	game.remove(big, 1.0)
	check(game.supplied(term, "strom"), "Kabel entfernt, Trafo wieder im Rahmen")
	# Wärme
	var heat_pipe: Dictionary = {}
	for l: Dictionary in game.lines:
		if l["kind"] == "heizrohr":
			heat_pipe = l
	var heat_pts: Array = heat_pipe["points"]
	game.remove(heat_pipe, 1.0)
	var cold := false
	for f: Array in tb.factors():
		cold = cold or String(f[0]).contains("kalt")
	check(not game.supplied(term, "waerme") and cold, "Ohne Heizrohr wird das Terminal kalt")
	game.build_line("heizrohr", heat_pts, true)
	check(game.supplied(term, "waerme"), "Heizrohr neu verlegt")
	# Fehlende Kontrolle blockiert den Flugbetrieb
	var secs: Array = game.items_of("sicherheit")
	var sec_pos := []
	for sc: Dictionary in secs:
		sec_pos.append(sc["pos"])
		game.remove(sc, 1.0)
	check(tb.check().contains("Sicherheitskontrolle"), "Ohne Kontrolle keine Flüge: " + tb.check())
	for sp: Vector3 in sec_pos:
		game.build_item("sicherheit", sp, 0, true)
	check(tb.check() == "", "Kontrolle wieder da")
	# Sicherheitsbereich: Einbahn-Ausgang und geschlossene Trennwand
	var sbx: Dictionary = game.items_of("sb_ausgang")[0]
	var sbx_pos: Vector3 = sbx["pos"]
	game.remove(sbx, 1.0)
	check(tb.check().contains("Sicherheitsbereich offen"), "Offene Lücke statt Ausgang erkannt")
	var plug: Dictionary = game.build_line("glaswand", [Vector3(12, 0, -8), Vector3(16, 0, -8)], true)
	check(tb.check().contains("Ausgang Sicherheitsbereich"), "Ohne Ausgang kommen Ankommende nicht raus: " + tb.check())
	game.remove(plug, 1.0)
	game.build_item("sb_ausgang", sbx_pos, 0, true)
	check(tb.check() == "", "Ausgang Sicherheitsbereich wieder da")
	var gw: Dictionary = game.walls_of(term)[0]
	var gw_pts: Array = gw["points"]
	game.remove(gw, 1.0)
	check(tb.check().contains("Sicherheitsbereich offen"), "Lücke in der Trennwand erkannt: " + tb.check())
	game.build_line("glaswand", gw_pts, true)
	check(tb.check() == "", "Sicherheitsbereich wieder geschlossen")

	# Straßennetz und Verkehr
	var rd = main.roads
	var tr = main.traffic
	rd.ensure()
	var jn: int = rd.nearest_junction(Vector3(115, 0, 35))
	check(jn >= 0 and rd.degree(jn) == 3, "Einmündung im Startnetz erkannt (%s)" % rd.control_of(jn))
	var c1: String = rd.cycle_control(Vector3(115, 0, 35))
	var c2: String = rd.cycle_control(Vector3(115, 0, 35))
	check(c1 != c2 and "ampel" in [c1, c2], "Kreuzung umschalten: %s → %s" % [c1, c2])
	jn = rd.nearest_junction(Vector3(115, 0, 35))
	if rd.control_of(jn) != "ampel":
		rd.cycle_control(Vector3(115, 0, 35))
	jn = rd.nearest_junction(Vector3(115, 0, 35))
	check((rd.nodes[jn]["lamps"] as Array).size() == 3, "Ampel mit drei Signalen")
	var side_road: Dictionary = {}
	for l: Dictionary in game.lines:
		if l["kind"] == "strasse" and (l["samples"] as PackedVector3Array)[0].z > 100.0:
			side_road = l
	check(game.cycle_road(side_road) == "" and side_road["kind"] == "strasse4", "Spuren ändern: 4-spurig")
	rd.ensure()
	check(rd.lanes(side_road, 1) == 2 and rd.lanes(side_road, -1) == 2, "Zwei Spuren je Richtung")
	game.cycle_road(side_road)
	rd.ensure()
	check(side_road["kind"] == "einbahn" and rd.lanes(side_road, -1) == 0, "Einbahnstraße")
	game.cycle_road(side_road)
	game.cycle_road(side_road)
	check(side_road["kind"] == "strasse", "Zurück auf 2-spurig")
	game.traffic_demand = 6
	tr.set_process(false)
	var m_before: int = game.money
	var max_wait := 0.0
	var parked_seen := 0
	var red_min := INF
	for i in range(2500):
		tr.step(0.1)
		parked_seen = maxi(parked_seen, tr.parked.size())
		for mv: Dictionary in tr.movers:
			max_wait = maxf(max_wait, float(mv["wait"]))
			var legs: Array = mv["legs"]
			if float(mv["v"]) < 0.05 and legs.size() > 1 and legs[0]["type"] == "lane" and legs[1]["type"] == "conn":
				var ni: int = legs[1]["node"]
				if rd.control_of(ni) == "ampel" and rd.signal_at(ni, int(legs[1]["from_e"])) == "rot":
					var rest := float(legs[0]["len"]) - float(mv["s"]) - float(mv["len"]) * 0.5
					if rest < 10.0:
						red_min = minf(red_min, rest)
	check(tr.movers.size() > 10, "Verkehr läuft auf Spuren (%d Autos)" % tr.movers.size())
	check(parked_seen > 0 and game.money > m_before, "Autos parken im Parkhaus und zahlen (%d geparkt)" % parked_seen)
	check(max_wait < 90.0, "Niemand steckt fest (längste Wartezeit %.0f s)" % max_wait)
	check(red_min < INF and red_min > 0.85, "Autos halten bei Rot vor der Haltelinie (Front %.1f m vor dem Kreuzungsrand)" % red_min)
	tr.set_process(true)
	b.set_tool("stand")
	b.on_move(Vector3(400, 0, 400))
	check(b.reason != "", "Stand neben dem Vorfeld abgelehnt: " + b.reason)
	game.build_line("vorfeld", [Vector3(300, 0, 300), Vector3(430, 0, 300)], true)
	b.on_move(Vector3(365, 0, 300))
	check(b.reason == "", "Stand auf dem Vorfeld erlaubt " + b.reason + " " + str(b.hover))
	b.set_tool("")
	fl.clear()
	lines0 = game.lines.size()

	# Straße mit Kurve
	var money0: int = game.money
	b.set_tool("strasse")
	b.on_click(Vector3(500, 0, 300))
	b.on_click(Vector3(560, 0, 330))
	b.on_click(Vector3(620, 0, 300))
	b.finish()
	check(game.lines.size() == lines0 + 1, "Kurvige Straße gebaut")
	var road_s: PackedVector3Array = game.lines[game.lines.size() - 1]["samples"]
	var road_mid: Vector3 = road_s[road_s.size() / 2]
	check(game.money < money0, "Baukosten abgezogen (%d €)" % (money0 - game.money))

	# Rollweg mit zu enger Kurve wird abgelehnt
	b.set_tool("rollweg")
	b.on_click(Vector3(500, 0, 420))
	b.on_click(Vector3(512, 0, 432))
	b.on_click(Vector3(500, 0, 444))
	b.finish()
	check(game.lines.size() == lines0 + 1, "Zu enge Rollweg-Kurve abgelehnt")
	b.cancel()

	# Piste: zwei Klicks, baut sich selbst fertig
	b.set_tool("piste")
	b.on_click(Vector3(-600, 0, 500))
	b.on_click(Vector3(300, 0, 520))
	check(game.lines.size() == lines0 + 2, "Piste mit zwei Klicks gebaut")

	# Einrasten an Wegenden
	b.set_tool("strasse")
	b.on_move(Vector3(623, 0, 303))
	check(b.hover.distance_to(road_s[road_s.size() - 1]) < 0.5 and b.snap_kind == "ende", "Neue Straße rastet am Straßenende ein")
	b.on_click(Vector3(623, 0, 303))
	b.on_click(Vector3(700, 0, 300))
	b.finish()
	check(game.lines.size() == lines0 + 3, "Anschluss-Straße gebaut")

	# Terminalhalle aufziehen und einrichten
	items0 = game.items.size()
	b.set_tool("halle")
	check(game.interior_view, "Terminal-Werkzeug schaltet die Innenansicht ein")
	b.on_click(Vector3(800, 0, 800))
	b.on_click(Vector3(840, 0, 824))
	check(game.items.size() == items0 + 1, "Terminalhalle 40 × 24 m gebaut")
	var hall: Dictionary = game.items[game.items.size() - 1]
	check(int((hall["rect"] as Rect2).get_area()) == 960 and int(hall["cost"]) == 1344000, "Preis nach Fläche (%s)" % game.fmt_money(int(hall["cost"])))
	b.on_click(Vector3(830, 0, 810))
	b.on_click(Vector3(860, 0, 830))
	check(game.items.size() == items0 + 1, "Überlappende Halle abgelehnt")
	b.cancel()
	b.set_tool("checkin")
	b.on_move(Vector3(900, 0, 900))
	check(b.reason.contains("innerhalb"), "Check-in außerhalb abgelehnt: " + b.reason)
	b.on_move(Vector3(820, 0, 812))
	check(b.reason == "", "Check-in in der Halle erlaubt " + b.reason)
	b.on_click(Vector3(820, 0, 812))
	check(game.items.size() == items0 + 2 and is_same(game.items[game.items.size() - 1]["hall"], hall), "Check-in gehört zur Halle")
	b.set_tool("gate")
	b.on_move(Vector3(820, 0, 818))
	check(b.reason.contains("Außenwand"), "Gate mitten in der Halle abgelehnt: " + b.reason)
	b.on_move(Vector3(820, 0, 819.6))
	check(b.reason == "", "Gate an der Außenwand erlaubt " + b.reason)
	var l_before: int = game.lines.size()
	b.set_tool("innenwand")
	b.on_click(Vector3(820, 0, 801))
	b.on_click(Vector3(820, 0, 813))
	check(game.lines.size() == l_before, "Wand durch den Check-in abgelehnt")
	b.on_click(Vector3(806, 0, 801))
	b.on_click(Vector3(806, 0, 823))
	check(game.lines.size() == l_before + 1 and is_same(game.lines[game.lines.size() - 1]["hall"], hall), "Innenwand gebaut")
	b.on_click(Vector3(880, 0, 801))
	b.on_click(Vector3(880, 0, 823))
	check(game.lines.size() == l_before + 1, "Wand außerhalb einer Halle abgelehnt")
	b.set_tool("pflanze")
	b.on_move(Vector3(806, 0, 812))
	check(b.reason != "", "Pflanze auf der Wand abgelehnt: " + b.reason)

	# Andere Gebäude: Kollision, drehen
	b.set_tool("hangar")
	b.on_move(Vector3(560, 0, 330))
	check(b.reason != "", "Hangar auf der Straße abgelehnt: " + b.reason)
	b.on_move(Vector3(820, 0, 812))
	check(b.reason != "", "Hangar in der Halle abgelehnt: " + b.reason)
	b.rotate()
	b.on_move(Vector3(900, 0, 900))
	b.on_click(Vector3(900, 0, 900))
	check(game.items.size() == items0 + 3 and int(game.items[game.items.size() - 1]["rot"]) == 1, "Gedrehter Hangar gesetzt")
	b.set_tool("kuebel")
	b.on_click(Vector3(860.3, 0, 830.2))
	check(game.items.size() == items0 + 4, "Blumenkübel gesetzt")

	# Abriss und Rückgängig: die Halle nimmt Einrichtung und Wände mit
	b.set_tool("abriss")
	b.on_move(Vector3(830, 0, 803))
	var before: int = game.money
	var lines_b: int = game.lines.size()
	var refund: int = int(hall["cost"]) / 2 + 30000 + int(game.lines[game.lines.size() - 1]["cost"]) / 2
	b.on_click(Vector3(830, 0, 803))
	check(game.items.size() == items0 + 2 and game.lines.size() == lines_b - 1, "Halle mit Einrichtung und Wand abgerissen")
	check(game.money - before == refund, "Hälfte zurückerstattet (%s)" % game.fmt_money(game.money - before))
	b.on_move(road_mid)
	b.on_click(road_mid)
	check(game.lines.size() == lines0 + 2, "Straße abgerissen")
	game.undo_last()
	check(game.items.size() == items0 + 1, "Rückgängig entfernt den Kübel")
	game.set_interior_view(false)

	# Wegebau: Kollisionen, Kreuzungen, Einrasten
	const Spline = preload("res://scripts/spline.gd")
	var chk: Dictionary = game.check_line("strasse", Spline.path([Vector3(150, 0, -40), Vector3(230, 0, -40)], false))
	check(String(chk["why"]).contains("Tower"), "Straße durch den Tower abgelehnt: " + String(chk["why"]))
	chk = game.check_line("rollweg", Spline.path([Vector3(640, 0, 240), Vector3(640, 0, 360)], false))
	check(String(chk["why"]).contains("Straße"), "Rollweg über eine Straße abgelehnt: " + String(chk["why"]))
	chk = game.check_line("strasse", Spline.path([Vector3(-50, 0, 30), Vector3(50, 0, 30)], false))
	check(String(chk["why"]).contains("Liegt auf"), "Straße auf einer Straße abgelehnt: " + String(chk["why"]))
	var n0: int = game.lines.size()
	b.set_tool("strasse")
	b.on_click(Vector3(680, 0, 240))
	b.on_click(Vector3(680, 0, 380))
	b.finish()
	check(game.lines.size() == n0 + 3, "Kreuzung angelegt: beide Straßen geteilt (%d → %d Wege)" % [n0, game.lines.size()])
	game.undo_last()
	check(game.lines.size() == n0 + 1, "Rückgängig nimmt die neue Straße samt Stücken zurück")
	n0 = game.lines.size()
	b.set_tool("strasse")
	b.on_click(Vector3(640, 0, 200))
	b.on_move(Vector3(640, 0, 302))
	check(b.snap_kind == "weg", "Rastet mitten auf einer Straße ein")
	b.on_click(Vector3(640, 0, 302))
	check(b.points.is_empty() and game.lines.size() == n0 + 2, "Anschluss an die Straße: fertig und Einmündung angelegt")
	var tree: Dictionary = game.build_item("baum", Vector3(800, 0, 150), 0)
	var trees_before: int = game.items_of("baum").size()
	game.build_line("strasse", [Vector3(780, 0, 150), Vector3(830, 0, 150)])
	check(game.items_of("baum").size() == trees_before - 1, "Baum im Weg wird weggeräumt")
	b.set_tool("")

	# Speichern und Laden
	game.save_game()
	var nl: int = game.lines.size()
	var ni: int = game.items.size()
	var nm: int = game.money
	game.clear_all()
	check(game.lines.size() == 0, "Karte geleert")
	await get_tree().process_frame
	game.load_game()
	check(game.lines.size() == nl and game.items.size() == ni and game.money == nm, "Spielstand wieder geladen")
	var term2: Dictionary = game.items_of("halle")[0]
	check(game.walls_of(term2).size() == 3 and game.inside_of(term2).size() > 20 and tb.check() == "", "Terminal mit Wänden und Einrichtung geladen")
	await get_tree().process_frame
	check(main.traffic.movers.size() > 5, "Verkehr nach dem Laden wieder unterwegs")

	# Fahrzeuge bewegen sich (das am weitesten gefahrene zählt, manche warten hinter anderen)
	main.set_process(true)
	var cars := []
	var starts := []
	for m: Dictionary in main.traffic.movers:
		cars.append(m["node"])
		starts.append((m["node"] as Node3D).position)
	for i in range(30):
		await get_tree().process_frame
	var moved := 0.0
	for k in range(cars.size()):
		if is_instance_valid(cars[k]):
			moved = maxf(moved, (cars[k] as Node3D).position.distance_to(starts[k]))
	check(moved > 0.5, "Fahrzeuge haben sich bewegt (%.1f m)" % moved)

	print("SELFTEST " + ("BESTANDEN" if failures == 0 else "%d FEHLER" % failures))
	get_tree().quit(0 if failures == 0 else 1)
