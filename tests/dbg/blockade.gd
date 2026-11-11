extends Node
## Zählt aufgelöste Blockaden (Zurückschleppen) und Notlösungen (Durchfahren); --seed=N, --schritte=N
func run(main: Node) -> void:
	await get_tree().process_frame
	main.set_process(false)
	var sd := 1
	var steps := 20000
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			sd = int(a.substr(7))
		if a.begins_with("--schritte="):
			steps = int(a.substr(11))
	seed(sd)
	var fl = main.flights
	var towing := {}
	var min_gap := INF
	for i in range(steps):
		fl.step(0.1)
		for q: Dictionary in fl.planes:
			if q.has("tow") and not towing.has(q["id"]):
				towing[q["id"]] = true
				print(i, " SCHLEPPEN ", q["code"], " ", q["state"], " pos ", Vector2(q["pos"].x, q["pos"].z).round(), " für ", q["tow"]["other"])
			elif not q.has("tow"):
				towing.erase(q["id"])
		if i % 10 == 0:
			for a2 in range(fl.planes.size()):
				for b2 in range(a2 + 1, fl.planes.size()):
					var pa: Dictionary = fl.planes[a2]
					var pb: Dictionary = fl.planes[b2]
					if pa["state"] in ["rollt_ein", "rollt_aus", "wartet"] and pb["state"] in ["rollt_ein", "rollt_aus", "wartet"]:
						min_gap = minf(min_gap, (pa["pos"] as Vector3).distance_to(pb["pos"]))
	print("ERGEBNIS seed ", sd, " schleppen ", fl.tows, " durchfahren ", fl.ghosts, " min_abstand ", snappedf(min_gap, 0.1))
	get_tree().quit()
