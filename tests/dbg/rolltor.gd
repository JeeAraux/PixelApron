extends Node
## Probe 0.18: Ausrundungen der Kofferbänder, Einläufe der Gepäckbänder, Rolltor mit Gepäckzug, Bild.
## Zusätze: --tor (Blick von draußen aufs Rolltor), --band (Gepäckbänder), --ecke (Bogen), --yaw=
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var tb = main.terminal
	var ops = main.ops
	g.sandbox = true
	tb.dirty = true
	tb._analyze()
	var h: Dictionary = g.items_of("halle")[0]
	print("checkins ", g.checkins_linked(h).size(), " claims ", g.claims_linked(h).size(), " routes ", g.bag_routes().size())
	for l: Dictionary in g.lines:
		if l["kind"] == "kofferband":
			var sm: PackedVector3Array = l["samples"]
			print("  band ", l["points"], " n=", sm.size(), " a=", sm[0], " e=", sm[sm.size() - 1])
	print(tb.hall_summary(h))
	print("problems ", tb.halls[0]["problems"])
	var gate: Dictionary = g.items_of("rolltor")[0] if not g.items_of("rolltor").is_empty() else {}
	print("rolltor ", gate.get("pos"), " rot ", gate.get("rot"), " route ", (g.bag_routes().get((gate["node"] as Node).get_instance_id(), PackedVector3Array()) as PackedVector3Array).size())
	print("cuts ", g.facade_cuts(h))
	print("sort_spot ", ops.sort_spot(Vector3(50, 0, -63)))
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1] if args.size() > 1 else ""
	if shot != "":
		var cam = main.cam_rig
		var at := Vector3(70, 0, -10)
		var zz := 34.0
		var inside := true
		if args.has("--tor"):
			at = Vector3(102, 0, -27)
			zz = 22.0
			inside = false
		if args.has("--band"):
			at = Vector3(50, 0, -3)
			zz = 22.0
		if args.has("--innen"):
			inside = true
		if args.has("--ecke"):
			at = Vector3(74, 0, -12)
			zz = 16.0
		for a: String in args:
			if a.begins_with("--yaw="):
				cam.yaw = float(a.substr(6))
				cam.yaw_goal = cam.yaw
		g.set_view_floor(0)
		g.set_interior_view(inside)
		cam.target = at
		cam.zoom_goal = zz
		cam.zoom = zz
		main.hud.set_build_open(false)
		if args.has("--tor"):
			# Gepäckzug vor dem Tor, Tor offen
			var key: String = ops._door_key(gate, 0)
			ops.door_rec[key] = [gate, 0]
			ops.door_want[key] = 1e9
			ops.door_open[key] = 1.0
			ops._animate_doors(0.1)
		for it: Dictionary in g.items_of("checkin"):
			for k in range(2):
				tb._bag_drop(it)
				tb.moving_bags[tb.moving_bags.size() - 1]["s"] = -1.6 - float(k) * 3.0 - randf() * 2.0
		for c: Dictionary in g.items_of("gepaeckband"):
			var bid: int = (c["node"] as Node).get_instance_id()
			tb.belt_load[bid] = 900 + bid % 50
			tb.bags_ready[900 + bid % 50] = tb.clock
			tb._claim_flow(900 + bid % 50)
		for i in range(30):
			tb.gate_bag(gate["node"])
			tb.moving_bags[tb.moving_bags.size() - 1]["s"] = -float(i) * 1.5
		for i in range(200):
			tb._bag_step(0.1)
		for i in range(60):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
