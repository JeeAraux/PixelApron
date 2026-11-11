extends Node
## Probe 0.17: Kofferwege im Startterminal, Gepäcklift in den Keller, Bild.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var tb = main.terminal
	g.sandbox = true
	tb.dirty = true
	tb._analyze()
	var h: Dictionary = g.items_of("halle")[0]
	print("linked starter ", g.checkins_linked(h).size(), " routes ", g.bag_routes().size())
	for did: int in g.bag_routes():
		print("  route len ", (g.bag_routes()[did] as PackedVector3Array).size())
	print(tb.hall_summary(h))
	# Keller: Halle mit Keller, Sortierung unten, Lift, Bänder oben und unten
	var kh: Dictionary = g.build_hall(Rect2(600, 600, 60, 40), false, {"keller": true})
	g.set_interior_view(true)
	g.set_view_floor(-1)
	print("sorter keller ", not g.build_item("gepaeckanlage", Vector3(640, 0, 615), 0).is_empty())
	print("lift ", not g.build_item("gepaecklift", Vector3(620, 0, 615), 0).is_empty(), " why ", g.can_place("gepaecklift", Vector3(620, 0, 615), 0))
	g.build_line("kofferband", [Vector3(620, 0, 616.45), Vector3(620, 0, 622), Vector3(635.5, 0, 622), Vector3(635.5, 0, 615)])
	g.set_view_floor(0)
	for x: float in [606.0, 612.0]:
		g.build_item("checkin", Vector3(x, 0, 626.5), 0)
	g.build_line("kofferband", [Vector3(615.45, 0, 625.34), Vector3(620, 0, 625.34), Vector3(620, 0, 616.45)])
	g._routes_dirty = true
	print("linked keller ", g.checkins_linked(kh).size())
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1] if args.size() > 1 else ""
	if shot != "":
		g.set_view_floor(0)
		g.set_interior_view(true)
		var cam = main.cam_rig
		var at := Vector3(-60, 0, 0)
		var zz := 40.0
		if args.has("--keller"):
			at = Vector3(620, 0, 620)
			zz = 30.0
		if args.has("--wand"):
			at = Vector3(80, 0, -14)
			zz = 22.0
		cam.target = at
		cam.zoom_goal = zz
		cam.zoom = zz
		main.hud.set_build_open(false)
		for it: Dictionary in g.items_of("checkin"):
			for k in range(3):
				tb._bag_drop(it)
				tb.moving_bags[tb.moving_bags.size() - 1]["s"] = -1.6 - float(k) * 3.0 - randf() * 2.0
		for i in range(240):
			tb._bag_step(0.1)
		for i in range(60):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
