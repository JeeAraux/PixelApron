extends Node
## Probe: Bauen im Obergeschoss.
func run(main: Node) -> void:
	await get_tree().process_frame
	main.set_process(false)
	var g = main.game
	var b = main.builder
	g.sandbox = true
	var h: Dictionary = g.build_hall(Rect2(600, 600, 60, 40))
	print("Halle: ", not h.is_empty())
	print("etagen -> ", g.cycle_option(h, "etagen", 1), " = ", g.hall_levels(h))
	g.set_interior_view(true)
	g.set_view_floor(1)
	print("view_floor ", g.view_floor, " range ", g.floor_range())
	b.set_tool("checkin")
	b.on_move(Vector3(620, 0, 620))
	print("reason: '", b.reason, "' hover ", b.hover)
	var n0: int = g.items.size()
	b.on_click(Vector3(620, 0, 620))
	print("gebaut: ", g.items.size() - n0)
	if g.items.size() > n0:
		var it: Dictionary = g.items[g.items.size() - 1]
		print("floor ", g.floor_of(it), " y ", (it["node"] as Node3D).global_position.y, " visible ", (it["node"] as Node3D).visible)
	b.set_tool("innenwand")
	b.on_click(Vector3(605, 0, 630))
	b.on_click(Vector3(640, 0, 630))
	b.finish()
	print("walls on floor1: ", g.walls_of(h).filter(func(l: Dictionary) -> bool: return g.floor_of(l) == 1).size())
	for l: Dictionary in g.walls_of(h):
		var nd: Node3D = l["node"]
		print(" wall vis ", nd.visible, " y ", nd.global_position.y, " floor ", g.floor_of(l))
		for c in nd.get_children():
			print("   ", c.name, " ", (c as Node3D).visible, " ", (c as Node3D).position)
	b.set_tool("rolltreppe")
	b.on_move(Vector3(650, 0, 620))
	print("rolltreppe reason: '", b.reason, "'")
	b.set_tool("bereich_sicherheit")
	b.on_click(Vector3(602, 0, 602))
	b.on_click(Vector3(630, 0, 615))
	print("zones: ", g.zones_of(h).size())
	b.set_tool("gate")
	b.on_move(Vector3(615, 0, 608))
	print("gate reason '", b.reason, "'")
	get_tree().quit()
