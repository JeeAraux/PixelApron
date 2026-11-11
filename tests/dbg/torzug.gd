extends Node
## Probe 0.18: Gepäckzug fährt vors Rolltor, Tor öffnet, Koffer laufen hinein und später aufs Gepäckband.
## Letztes Argument: Bildpfad (optional). --band: Bild beim Gepäckband statt am Tor.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var tb = main.terminal
	var ops = main.ops
	var fl = main.flights
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1] if args.size() > 1 and args[args.size() - 1].ends_with(".png") else ""
	var want_band := args.has("--band")
	seed(20261110)
	var at_door := false
	var door_open := 0.0
	var claim := false
	var stop_i := -1
	for i in range(14000):
		fl.step(0.1)
		for v: Dictionary in ops.sorting:
			if v.has("sort_door") and not bool(v["moving"]) and int(v.get("sort_slot", -1)) == 0:
				at_door = true
		for k: String in ops.door_open:
			door_open = maxf(door_open, float(ops.door_open[k]))
		var nclaim := 0
		for b: Dictionary in tb.moving_bags:
			if b.has("claim") and float(b["s"]) > 4.0:
				nclaim += 1
		claim = claim or nclaim > 3
		if shot != "" and stop_i < 0:
			var running := false
			for fid: int in tb.claim_sent:
				running = running or (tb.clock > float(tb.bags_ready.get(fid, INF)) + 4.0 and tb.belt_load.values().has(fid))
			if (not want_band and at_door and door_open > 0.95 and ops.sorting.size() > 0) or (want_band and running):
				stop_i = i
				break
		if shot == "" and at_door and claim:
			print("both at ", i)
			break
	print("at_door ", at_door, " door_open ", door_open, " claim ", claim, " claim_sent ", tb.claim_sent.size(), " moving ", tb.moving_bags.size())
	if shot != "":
		var cam = main.cam_rig
		var at := Vector3(100, 0, -28)
		var zz := 26.0
		if want_band:
			at = Vector3(55, 0, -4)
			zz = 30.0
			g.set_interior_view(true)
		for a: String in args:
			if a.begins_with("--yaw="):
				cam.yaw = float(a.substr(6))
				cam.yaw_goal = cam.yaw
			if a.begins_with("--innen"):
				g.set_interior_view(true)
		cam.target = at
		cam.zoom_goal = zz
		cam.zoom = zz
		main.hud.set_build_open(false)
		for i in range(40):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
