extends Node
## Schnellprobe 0.10: Startflughafen, Fassadenöffnungen, Befeuerung, Rollhalte, Gepäcksortierung, Bustüren.
func run(main: Node) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	main.set_process(false)
	var game = main.game
	var fl = main.flights
	var term: Dictionary = game.items_of("halle")[0]
	print("Betrieb: '", fl.check_operation(), "'  Terminal: '", main.terminal.check(), "'")
	print("Öffnungen in der Fassade: ", (term.get("cuts", []) as Array).size(), " ", term.get("cuts", []))
	print("Brücken: ", game.items_of("fluggastbruecke").map(func(b: Dictionary) -> String: return str(b["pos"])))
	for st: Dictionary in game.items_of("befeuerungsstation"):
		print("Station: ", st["pos"], " ", st["supply"])
	print("Piste beleuchtet: ", fl.runway_lit(), "  Rollhalte: ", game.items_of("rollhalt").size(), "  Holds im Graph: ", fl.graph.holds.size())
	main.ops._rebuild_net()
	var conn := 0
	for st: Dictionary in game.stands():
		if main.ops.stand_connected(st):
			conn += 1
	print("Stände mit Zufahrt: ", conn, " von ", game.stands().size(), "  Sortierstelle: ", main.ops.sort_spot(Vector3(0, 0, -40)))
	var door_seen := false
	var sort_seen := false
	var bags_seen := false
	var belt_seen := false
	for i in range(int(OS.get_cmdline_user_args().has("--lang")) * 6000 + 300):
		fl.step(0.1)
		for v: Dictionary in main.ops.vehicles:
			if v["kind"] == "bus" and float(v.get("door", 0.0)) > 0.9:
				door_seen = true
		sort_seen = sort_seen or not main.ops.sorting.is_empty()
		bags_seen = bags_seen or not main.terminal.bags_ready.is_empty()
		belt_seen = belt_seen or not main.terminal.belt_load.is_empty()
		if i % 1500 == 0:
			var st := []
			for p: Dictionary in fl.planes:
				st.append("%s %s" % [p["code"], p["state"]])
			print(i, " ", st, " sorting=", main.ops.sorting.size(), " bags=", main.terminal.bags_ready.keys())
	print("Bustür offen: ", door_seen, "  Sortierung: ", sort_seen, "  Koffer bereit: ", bags_seen, "  Band belegt: ", belt_seen, "  abgeflogen: ", fl.done)
	get_tree().quit()
