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
	check(game.inside_of(term).size() > 20 and game.walls_of(term).size() == 5, "Terminal eingerichtet (%d Teile, %d Wände)" % [game.inside_of(term).size(), game.walls_of(term).size()])
	check(tb.check() == "", "Terminal betriebsbereit " + tb.check())
	check(String(hangar0["supply"].get("strom", "")) == "ok", "Hangar im Startflughafen hat Strom")
	check(main.flights.check_operation() == "", "Flugbetrieb startklar")
	# 0.9: Bereiche, Türen, Personal, Garagen und Betriebsstraße im Startflughafen
	check(game.zones_of(term).size() == 3, "Bereiche angelegt (öffentlich, Sicherheit, Personal)")
	check(game.zone_at(term, Vector2(-67, -20), 0) == "sicherheit" and game.zone_at(term, Vector2(-34, 2.5), 0) == "oeffentlich"
		and game.zone_at(term, Vector2(96, -20), 0) == "personal", "Gates im Sicherheitsbereich, Check-in öffentlich, Gepäck im Personalbereich")
	var doors: Array = game.items_of("tuer")
	check(doors.size() == 2, "Zwei Personaltüren gesetzt")
	var cut_walls := 0
	for l: Dictionary in game.walls_of(term):
		cut_walls += game.wall_cuts(l).size()
	check(cut_walls == 2, "Die Türen öffnen ihre Wände (%d Öffnungen)" % cut_walls)
	var tgrids: Dictionary = tb.grids[(term["node"] as Node).get_instance_id()]
	var dcell := Vector2i(88, -8)
	check((tgrids[0]["dep"] as AStarGrid2D).is_point_solid(dcell) and not (tgrids[0]["staff"] as AStarGrid2D).is_point_solid(dcell),
		"Personaltür: Fluggäste kommen nicht durch, Mitarbeiter schon")
	check((tgrids[0]["dep"] as AStarGrid2D).is_point_solid(Vector2i(100, -15)), "Personalbereich ist für Fluggäste gesperrt")
	check(tb.staff_available() >= tb.staff_needed() and is_equal_approx(tb.staff_slowdown(), 1.0),
		"Genug Personal (%d von %d)" % [tb.staff_available(), tb.staff_needed()])
	main.ops._rebuild_net()
	check(main.ops.unconnected.is_empty() and main.ops.net.pos.size() > 50, "Garagen über die Betriebsstraße ans Vorfeld angeschlossen")
	for vk: String in ["gpu", "tank", "catering", "bus"]:
		var gg: Array = main.ops._garage(vk, Vector3(-40, 0, -40))
		check(not gg.is_empty() and main.ops.net.route(gg[2], Vector3(-17, 0, -38)).size() > 3, "Fahrweg von der Garage zum Stand: " + vk)
	check(main.ops.has_garage("tank") and main.ops.has_garage("catering") and main.ops.has_fire_station(), "Tanklager, Catering und Feuerwache versorgt")
	# 0.10: Fassadenöffnungen, Brücken an der Wand, Zufahrten, Befeuerung, Rollhalteorte, Kurvenregel
	check((term.get("cuts", []) as Array).size() == 8, "Eingänge und Brückenköpfe öffnen die Fassade (%d Öffnungen)" % (term.get("cuts", []) as Array).size())
	var flush_ok := true
	for br: Dictionary in game.items_of("fluggastbruecke"):
		var hs: Array = game.hall_side(br["pos"])
		flush_ok = flush_ok and not hs.is_empty() and absf(float(hs[3]) - float(game.BRIDGE_OFF)) < 0.05
	check(flush_ok, "Fluggastbrücken stehen bündig an der Fassade")
	var connected := 0
	for st: Dictionary in game.stands():
		if main.ops.stand_connected(st):
			connected += 1
	check(connected == game.stands().size(), "Alle Stände haben eine Zufahrt von der Betriebsstraße (%d)" % connected)
	check(main.flights.runway_lit() and game.items_of("rollhalt").size() == 6 and game.items_of("anflugbefeuerung").size() == 2,
		"Befeuerungsstation versorgt die Piste, Rollhalteorte und Anflugbefeuerung gebaut")
	if bool(main.flights.dirty):
		main.flights._rebuild()
	var custom_holds := 0
	for h: Dictionary in main.flights.graph.holds:
		if bool(h.get("custom", false)):
			custom_holds += 1
	check(custom_holds == 6, "Rollhalteorte gelten im Rollnetz (%d)" % custom_holds)
	var gr = main.flights.graph
	var tpath: Array = gr.path(gr.nearest(Vector3(0, 0, -104)), gr.nearest(Vector3(-600, 0, -104)), {}, Vector3(1, 0, 0))
	var sharp := 0
	for ti in range(1, tpath.size() - 1):
		var d0: Vector3 = gr.pos[tpath[ti]] - gr.pos[tpath[ti - 1]]
		var d1: Vector3 = gr.pos[tpath[ti + 1]] - gr.pos[tpath[ti]]
		if d0.length() > 0.1 and d1.length() > 0.1 and d0.normalized().dot(d1.normalized()) < -0.01:
			sharp += 1
	check(tpath.size() > 3 and sharp == 0, "Flugzeuge wenden ohne Kurven über 90° (%d Knoten)" % tpath.size())
	var belts: Array = []
	var gates_t: Array = []
	for it: Dictionary in game.inside_of(term):
		if it["id"] == "gepaeckband":
			belts.append(it)
		if it["id"] in ["gate", "busgate"]:
			gates_t.append(it)
	game.cycle_option(belts[0], "gate", 1)
	var belt0: Dictionary = game.inside_of(term).filter(func(it: Dictionary) -> bool: return it["id"] == "gepaeckband")[0]
	var g1: Dictionary = {}
	for g: Dictionary in gates_t:
		if tb.gate_number(g) == 1:
			g1 = g
	check(not g1.is_empty() and is_same(tb.belt_for(term, g1), belt0) and int(game.opt(belt0, "gate")) == 1, "Gepäckband dem Gate 1 zugeordnet")
	game.cycle_option(belt0, "gate", -1)
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
	var door_seen := false
	var home_seen := false
	var staff_seen := false
	var leaf_open := false
	var bus_door := false
	var sort_seen := false
	var belt_run := false
	var flaps_seen := false
	var walk_frames := false
	for i in range(12000):
		fl.step(0.1)
		outdoor_pax = maxi(outdoor_pax, main.ops.walkers.size())
		for dk: String in main.ops.door_open:
			door_seen = door_seen or float(main.ops.door_open[dk]) > 0.9
		home_seen = home_seen or not main.ops.returning.is_empty()
		sort_seen = sort_seen or not main.ops.sorting.is_empty()
		belt_run = belt_run or (not tb.belt_load.is_empty() and not tb.bags_ready.is_empty())
		for vv: Dictionary in main.ops.vehicles:
			bus_door = bus_door or (vv["kind"] == "bus" and float(vv.get("door", 0.0)) > 0.9)
		for pl: Dictionary in fl.planes:
			flaps_seen = flaps_seen or float(pl.get("flaps", 0.0)) > 0.5
		if i % 50 == 0:
			for per: Dictionary in tb.people:
				walk_frames = walk_frames or int((per["node"] as Node3D).get_meta("pose", 0)) >= 10
		for per: Dictionary in tb.people:
			staff_seen = staff_seen or bool(per.get("staff", false))
		for d: Array in tb.doors:
			leaf_open = leaf_open or float(d[1]) > 0.9
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
			if main.ops.service_count() > 3:
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
	check(door_seen, "Rolltore gehen auf, wenn ein Fahrzeug aus der Garage fährt")
	check(bus_door, "Vorfeldbusse öffnen ihre Türen")
	check(sort_seen and belt_run, "Gepäckzüge fahren zur Sortierung, die Koffer laufen aufs Band")
	check(flaps_seen, "Landeklappen fahren aus")
	check(walk_frames, "Passagiere gehen mit acht Gangphasen")
	check(home_seen, "Fahrzeuge fahren nach der Abfertigung zurück in die Garage")
	check(staff_seen and leaf_open, "Mitarbeiter gehen durchs Terminal, Personaltüren öffnen sich")
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
	var old_dep: Dictionary = game.items_of("vorfelddepot")[0]
	var dep_pos: Vector3 = old_dep["pos"]
	var dep_rot: int = old_dep["rot"]
	game.remove(old_dep, 1.0)
	check(not fl.depot_ok(), "Ohne Gerätehalle langsamere Abfertigung")
	var dep: Dictionary = game.build_item("vorfelddepot", dep_pos, dep_rot)
	var dep_ok := not dep.is_empty()
	check(dep_ok and fl.depot_ok(), "Gerätehalle gebaut und über das Kabel versorgt")
	var test_plane := {"id": 999, "kind": "a320", "stand": game.stands()[0], "code": "TEST 1", "city": "Test", "gse": [], "pos": Vector3.ZERO}
	var slow_t: float = tb.slowdown()
	fl._park(test_plane)
	var expect: float = float(Catalog.PLANES["a320"]["turn"]) * slow_t * tb.staff_slowdown() * (1.0 if not (test_plane["gate"] as Dictionary).is_empty() else 1.25)
	if bool(test_plane.get("bus", false)) and not main.ops.has_garage("bus"):
		expect *= 1.15
	if not (test_plane["gate"] as Dictionary).is_empty() and not game.baggage_link(test_plane["gate"]["hall"]).is_empty():
		expect *= 0.9   # Gepäckförderband zum Umschlag
	check(is_equal_approx(float(test_plane["turn"]), expect), "Mit Depot normale Abfertigungszeit (%.0f Min)" % float(test_plane["turn"]))
	fl._clear_gse(test_plane)
	fl._release_all(999)
	main.ops.release(test_plane)
	tb.flight_left(test_plane)
	for per: Dictionary in tb.people.duplicate():
		if int(per["flight"]) == 999:
			tb._drop(per)
	# Unterhalt um Mitternacht
	var before_mid: int = game.money
	var upkeep: int = game.upkeep_per_day()
	game.day_income = 0
	var to_midnight: float = 1440.0 - fmod(game.minutes, 1440.0) + 1.0
	game.advance(to_midnight)
	check(upkeep > 0 and game.money == before_mid - upkeep, "Unterhalt um Mitternacht abgezogen (%s)" % game.fmt_money(upkeep))
	# Info-Werkzeug
	check(game.describe(game.pick(Vector3(20, 0, 5))) == "Terminalhalle" and game.details(term).contains("Unterhalt"), "Info zeigt Gebäudedetails")
	check(game.describe(game.pick(Vector3(-34, 0, 2.5))) == "Check-in", "Info zeigt Einrichtung")
	check(seen_states.has("abfertigung"), "Flugzeug ist am Stand angekommen")
	check(fl.done >= 2, "Flugzeuge sind wieder gestartet (%d)" % fl.done)
	check(m1 > m0, "Einnahmen aus Flügen (%d €)" % (m1 - m0))
	var cable: Dictionary = {}
	for l: Dictionary in game.lines:
		if l["kind"] == "stromkabel" and (l["points"][1] as Vector3).distance_to(Vector3(58, 0, 15)) < 1.0:
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
	var plug: Dictionary = game.build_line("glaswand", [Vector3(28, 0, -8), Vector3(32, 0, -8)], true)
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
	# Bereiche: ohne Sicherheitsbereich kein Betrieb, alte Spielstände bekommen sie automatisch
	var sz: Dictionary = {}
	for z: Dictionary in game.zones_of(term):
		if z["id"] == "bereich_sicherheit":
			sz = z
	var sz_rect: Rect2 = sz["rect"]
	game.remove(sz, 1.0)
	check(tb.check().contains("Sicherheitsbereich"), "Gates ohne Sicherheitsbereich erkannt: " + tb.check())
	game.build_zone("bereich_sicherheit", sz_rect, true, 0)
	check(tb.check() == "", "Sicherheitsbereich wieder angelegt")
	for z: Dictionary in game.zones_of(term):
		game.remove(z, 1.0)
	check(tb.check() != "", "Ohne Bereiche kein Betrieb: " + tb.check())
	tb.auto_zones(term)
	check(game.zones_of(term).size() >= 2 and tb.check() == "", "Bereiche aus Wänden und Kontrolle abgeleitet (%d Flächen) " % game.zones_of(term).size() + tb.check())
	# Personal
	var staff_b: Dictionary = game.items_of("personalgebaeude")[0]
	var sb_pos: Vector3 = staff_b["pos"]
	game.remove(staff_b, 1.0)
	check(tb.staff_slowdown() > 1.2, "Ohne Personalgebäude dauert die Abfertigung länger (×%.2f)" % tb.staff_slowdown())
	game.build_item("personalgebaeude", sb_pos, 0, true)
	check(is_equal_approx(tb.staff_slowdown(), 1.0), "Personalgebäude wieder da")
	# Feuerwehr rückt aus: Tor geht auf, Fahrzeug fährt hinaus
	main.ops.fire_t = 9999.0
	check(main.ops._fire_mission("kontrolle", null, 0.0), "Kontrollfahrt der Feuerwehr gestartet")
	var fm: Dictionary = main.ops.missions[main.ops.missions.size() - 1]
	var fv: Dictionary = fm["v"]
	var fstart: Vector3 = fv["pos"]
	var opened := false
	for i in range(900):
		main.ops.step(0.1)
		var fk: String = main.ops._door_key(fm["station"], int(fm["idx"]))
		opened = opened or float(main.ops.door_open.get(fk, 0.0)) > 0.95
	check(opened and (fv["pos"] as Vector3).distance_to(fstart) > 30.0, "Rolltor auf, Löschfahrzeug ausgerückt (%.0f m)" % (fv["pos"] as Vector3).distance_to(fstart))

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
				# nur Autos, die wegen der Ampel stehen (nicht im Rückstau hinter einem Vordermann)
				# (wer bei Gelb schon zu nah war und durchfährt, zählt nicht)
				if rd.control_of(ni) == "ampel" and rd.signal_at(ni, int(legs[1]["from_e"])) == "rot" and tr._gap_ahead(mv) > 8.0 \
						and int(mv.get("commit", -1)) != ni:
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
	# Rollhalteort rastet auf dem Rollweg ein, nicht zu nah an der Piste
	b.set_tool("rollhalt")
	b.on_move(Vector3(-1277, 0, -176))
	check(b.reason != "", "Rollhalteort zu nah an einer anderen abgelehnt: " + b.reason)
	b.on_move(Vector3(-285, 0, -238))
	check(b.reason != "", "Rollhalteort dicht an der Piste abgelehnt: " + b.reason)
	var nh: int = game.items_of("rollhalt").size()
	b.on_move(Vector3(-342, 0, -126))
	b.on_click(Vector3(-342, 0, -126))
	check(game.items_of("rollhalt").size() == nh + 1, "Rollhalteort auf den Rollweg gesetzt " + b.reason)
	game.undo_last()
	# Fluggastbrücke rastet bündig an der Wand ein und öffnet die Fassade
	b.set_tool("fluggastbruecke")
	b.on_move(Vector3(-100, 0, -27))
	var nb: int = game.items_of("fluggastbruecke").size()
	b.on_click(Vector3(-100, 0, -27))
	var newb: Array = game.items_of("fluggastbruecke")
	var term_b: Dictionary = game.items_of("halle")[0]
	game.flush_facades()
	check(newb.size() == nb + 1 and absf((newb[newb.size() - 1]["pos"] as Vector3).z - (-24.0 - float(game.BRIDGE_OFF))) < 0.05
		and (term_b["cuts"] as Array).size() == 9, "Neue Brücke bündig an der Wand, Fassade geöffnet " + b.reason)
	game.undo_last()
	game.flush_facades()
	b.set_tool("")
	fl.clear()
	lines0 = game.lines.size()

	# Straße mit Kurve
	var money0: int = game.money
	b.set_tool("strasse")
	b.set_mode("frei")
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
	# Tür auf die neue Wand: rastet ein, Wand bekommt eine Öffnung
	var inner_wall: Dictionary = game.lines[game.lines.size() - 1]
	b.set_tool("tuer")
	b.on_move(Vector3(815, 0, 812))
	check(b.reason.contains("Innenwand"), "Tür ohne Wand abgelehnt: " + b.reason)
	b.on_move(Vector3(806.6, 0, 816.2))
	check(b.reason == "" and absf(b.hover.x - 806.0) < 0.01 and b.rot == 1, "Tür rastet quer auf die Wand ein " + b.reason)
	var n_items: int = game.items.size()
	b.on_click(Vector3(806.6, 0, 816.2))
	check(game.items.size() == n_items + 1 and game.wall_cuts(inner_wall).size() == 1, "Tür gesetzt, Wand geöffnet")
	game.remove(game.items[game.items.size() - 1], 1.0)
	check(game.wall_cuts(inner_wall).is_empty(), "Tür abgerissen, Wand wieder zu")
	# Bereich aufziehen
	b.set_tool("bereich_sicherheit")
	b.on_click(Vector3(808, 0, 814))
	b.on_click(Vector3(838, 0, 823))
	check(game.zones_of(hall).size() == 1 and game.zone_at(hall, Vector2(830, 820), 0) == "sicherheit", "Sicherheitsbereich aufgezogen")
	game.remove(game.zones_of(hall)[0], 1.0)
	b.set_tool("")
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
	check(String((game.items[game.items.size() - 1]["supply"] as Dictionary).get("strom", "")) == "fehlt", "Hangar ohne Kabel hat keinen Strom")
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
	var tw: Vector3 = (game.items_of("tower")[0]["node"] as Node3D).position
	var chk: Dictionary = game.check_line("strasse", Spline.path([tw + Vector3(-3, 0, -40), tw + Vector3(3, 0, 40)], false))
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

	# Zeichenart Gerade: setzt am Ende fort; Kurve schließt tangential an
	b.set_tool("strasse")
	b.set_mode("gerade")
	n0 = game.lines.size()
	b.on_click(Vector3(1200, 0, 600))
	b.on_click(Vector3(1260, 0, 600))
	check(game.lines.size() == n0 + 1 and b.points.size() == 1 and b.start_tan.distance_to(Vector3.RIGHT) < 0.01,
		"Gerade: Stück gebaut, Zeichnen geht am Ende weiter")
	b.on_move(Vector3(1300, 0, 601.5))
	check(absf(b.hover.z - 600.0) < 0.01, "Gerade: Winkel rastet weich auf die Verlängerung ein (%.2f)" % b.hover.z)
	b.cancel()
	b.set_mode("kurve")
	b.on_move(Vector3(1260.5, 0, 600.4))
	check(b.snap_kind == "ende" and b.snap_tan.distance_to(Vector3.LEFT) < 0.05, "Kurve: Wegende mit Richtung erkannt")
	b.on_click(Vector3(1260.5, 0, 600.4))
	check(b.start_tan.distance_to(Vector3.RIGHT) < 0.05, "Kurve: startet in Richtung der Straße")
	b.on_move(Vector3(1310, 0, 650))
	b.on_click(b.hover)
	var arc_rec: Dictionary = game.lines[game.lines.size() - 1]
	var arc_s: PackedVector3Array = arc_rec["samples"]
	var arc_dir := (arc_s[3] - arc_s[0]).normalized()
	check(game.lines.size() == n0 + 2 and arc_dir.dot(Vector3.RIGHT) > 0.98 and Spline.min_radius(arc_s) > 40.0,
		"Kurve: Bogen tangential angeschlossen (Radius %d m)" % int(Spline.min_radius(arc_s)))
	b.cancel()
	b.set_mode("frei")
	b.set_tool("")
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
	check(game.walls_of(term2).size() == 5 and game.inside_of(term2).size() > 20 and tb.check() == "", "Terminal mit Wänden und Einrichtung geladen " + tb.check())
	check(game.zones_of(term2).size() >= 2 and game.items_of("tuer").size() == 2, "Bereiche und Türen geladen")
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
