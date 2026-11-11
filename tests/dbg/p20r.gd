extends Node
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var h: Dictionary = g.items_of("halle")[0]
	print("vorher ", g.room_ok(h, "lager"))
	main.betrieb.start_scenario("winter")
	main.betrieb.start_scenario("")
	h = g.items_of("halle")[0]
	for st: Dictionary in g.rooms_of(h):
		print("nachher ", st["ok"], " ", st["missing"], " floor ", g.floor_of(st["rec"]), " vf ", g.view_floor)
	for it: Dictionary in g.items_of("regal"):
		print("regal ", it["rect"], " floor ", g.floor_of(it), " hall ", not (it.get("hall", {}) as Dictionary).is_empty())
	get_tree().quit()
