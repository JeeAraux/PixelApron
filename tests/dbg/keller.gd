extends Node
## Probe: Bauen im Keller (Ebene -1), Verbinder vom Keller ins Erdgeschoss. Mit BILD: Aufnahme.
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1] if args[args.size() - 1].ends_with(".png") else ""
	var g = main.game
	var b = main.builder
	g.sandbox = true
	var h: Dictionary = g.build_hall(Rect2(600, 600, 60, 40))
	if "--start" in args:
		h = g.items_of("halle")[0]
		print("Starthalle ", h["rect"])
	print("Halle: ", not h.is_empty())
	print("vorher wände ", g.walls_of(h).size())
	print("keller -> '", g.cycle_option(h, "keller", 1), "' = ", g.hall_basement(h))
	g.set_interior_view(true)
	g.set_view_floor(-1)
	print("view_floor ", g.view_floor)
	var Cat = load("res://scripts/catalog.gd")
	var i := 0
	for tool: String in ["regal", "checkin", "gepaeckanlage", "rolltreppe", "treppe", "aufzug"]:
		i += 1
		if not Cat.ITEMS.has(tool):
			print(tool, " fehlt")
			continue
		b.set_tool(tool)
		var p := Vector3(603 + i * 8, 0, 612)
		b.on_move(p)
		var n0: int = g.items.size()
		b.on_click(p)
		print(tool, ": reason '", b.reason, "' gebaut ", g.items.size() - n0)
		if g.items.size() > n0:
			var it: Dictionary = g.items[g.items.size() - 1]
			print("   floor ", g.floor_of(it), " y ", (it["node"] as Node3D).global_position.y, " vis ", (it["node"] as Node3D).visible)
	b.set_tool("innenwand")
	b.on_click(Vector3(605, 0, 630))
	b.on_click(Vector3(640, 0, 630))
	b.finish()
	print("wände: ", g.walls_of(h).size())
	var hr: Rect2 = h["rect"]
	var ra := Vector3(hr.position.x + 4, 0, hr.end.y - 14)
	var rb := ra + Vector3(10, 0, 10)
	b.set_tool("raum")
	b.on_move(ra)
	b.on_click(ra)
	b.on_move(rb)
	print("raum reason vor '", b.reason, "'")
	b.on_release(rb)
	print("raum reason '", b.reason, "' wände ", g.walls_of(h).size())
	print("problem ", g.room_problem(Rect2(Vector2(ra.x, ra.z), Vector2(10, 10))))
	if shot != "":
		main.cam_rig.target = Vector3(630, 0, 620)
		main.cam_rig.zoom = 70.0
		main.cam_rig.zoom_goal = 70.0
		for _f in range(40):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
