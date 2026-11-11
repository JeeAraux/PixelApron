extends Node
## Probe 0.20: Räume, Waren, Sicherheitstechnik, Wand- und Schnittansicht.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var tb = main.terminal
	tb.dirty = true
	tb._analyze()
	var h: Dictionary = g.items_of("halle")[0]
	for st: Dictionary in g.rooms_of(h):
		print("raum ", st["kind"], " ok ", st["ok"], " ", st["missing"], " ", st["rec"]["rect"])
	print("tueren ", g.items_of("tuer").size(), " problems ", tb.halls[0]["problems"], " missing ", tb.halls[0]["missing"])
	print("sec cap ", tb.security_cap(), " retail ", tb.retail_per_pax(), " factor ", tb.retail_factor())
	print(tb.hall_summary(h))
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1] if args.size() > 1 and args[args.size() - 1].ends_with(".png") else ""
	if shot != "":
		var cam = main.cam_rig
		var at := Vector3(88, 0, -14)
		var zz := 22.0
		for a: String in args:
			if a.begins_with("--at="):
				var xy := a.substr(5).split(",")
				at = Vector3(float(xy[0]), 0, float(xy[1]))
			if a.begins_with("--zoom="):
				zz = float(a.substr(7))
			if a.begins_with("--yaw="):
				cam.yaw = float(a.substr(6))
				cam.yaw_goal = cam.yaw
		g.set_interior_view(true)
		if args.has("--voll"):
			g.cycle_wall_mode()
		if args.has("--ct"):
			for it: Dictionary in g.items_of("sicherheit"):
				g.cycle_option(it, "technik", 2)
		cam.target = at
		cam.zoom = zz
		cam.zoom_goal = zz
		main.hud.set_build_open(false)
		for i in range(400):
			main.flights.step(0.1)
		for i in range(40):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
