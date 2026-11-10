extends Node
func run(main: Node) -> void:
	await get_tree().process_frame
	var game = main.game
	for it in game.items_of("haltestelle"):
		print("Haltestelle pos ", it["pos"], " rect ", it["rect"], " rot ", it.get("rot"))
	for it in game.items_of("parkhaus"):
		print("Parkhaus pos ", it["pos"], " rect ", it["rect"])
	for l in game.lines:
		if l["kind"] == "strasse":
			var s: PackedVector3Array = l["samples"]
			for v in s:
				if absf(v.x + 48.0) < 0.6:
					print("Strasse bei x=-48: ", v)
	print("access ", main.traffic.access.size(), " bus ", main.traffic.has_bus_line(), " entrances ", main.traffic.entrances)
	for it in game.items_of("gepaeckumschlag"):
		print("Umschlag ", it["pos"], " supply ", it["supply"])
	for h in game.items_of("halle"):
		print("Halle ", h["rect"], " Gepaeck verbunden: ", not game.baggage_link(h).is_empty())
	get_tree().quit()
