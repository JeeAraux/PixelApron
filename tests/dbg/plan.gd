extends Node
## Probe 0.13: Flugplan-Verspätungen, Wetter, Fracht, Betrieb.
func run(main: Node) -> void:
	await get_tree().process_frame
	main.set_process(false)
	main.weather.force("klar")
	var fl = main.flights
	var arr_late := []
	var seen := {}
	for i in range(int(OS.get_cmdline_user_args().has("--lang")) * 10000 + 8000):
		fl.step(0.1)
		for p: Dictionary in fl.planes:
			if p["state"] == "abfertigung" and not seen.has(p["id"]):
				seen[p["id"]] = true
				arr_late.append(roundi(main.game.minutes - float(p.get("sta", 0.0))))
	print("Ankunft gegenüber Plan (Min): ", arr_late)
	print("Abflüge: ", main.betrieb.stats, " recent=", main.betrieb.recent)
	print("Pünktlich: ", main.betrieb.punctuality(), "  Einnahmen: ", main.betrieb.income)
	print("Engpässe: ", main.betrieb.hotspots(3))
	get_tree().quit()
