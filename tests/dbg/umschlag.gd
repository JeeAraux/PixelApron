extends Node
## Probe 0.29.2: Gepäckzug fährt in eine Spur des Gepäckumschlags, lädt ab, wendet im Quergang und fährt
## vorwärts durchs Nachbartor hinaus. --phase=ab|wende|raus, --yaw=, --zoom=, letztes Argument BILD.png
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var ops = main.ops
	var fl = main.flights
	seed(20261110)
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1] if args.size() > 1 and args[args.size() - 1].ends_with(".png") else ""
	var phase := "ab"
	var zoom := 34.0
	var yaw := 999.0
	for a: String in args:
		if a.begins_with("--phase="):
			phase = a.substr(8)
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		if a.begins_with("--yaw="):
			yaw = float(a.substr(6))
	var rec: Dictionary = g.items_of("gepaeckumschlag")[0]
	var c: Vector3 = rec["pos"]
	var stats := {"rein": 0, "wende": 0, "raus": 0, "rueck": 0, "dep_lane": 0}
	var seen := {}
	var max_wait := 0.0
	for i in range(20000):
		fl.step(0.1)
		for v: Dictionary in ops.vehicles:
			if v.get("kind") != "zug":
				continue
			var id := (v["node"] as Node).get_instance_id() if is_instance_valid(v.get("node")) else 0
			var st: Dictionary = v.get("sort", {})
			var inside := bool(st.get("inside", false))
			var out := bool(st.get("out", false))
			var p: Vector3 = v["pos"]
			var in_hall := absf(p.x - c.x) < 17.0 and absf(p.z - c.z) < 17.5
			if inside and in_hall and not out and not seen.has("rein%d" % id):
				seen["rein%d" % id] = true
				stats["rein"] += 1
			if out and in_hall and bool(v["rev"]) and not seen.has("rueck%d" % id):
				seen["rueck%d" % id] = true
				stats["rueck"] += 1
			if out and in_hall and not bool(v["rev"]) and not seen.has("wende%d" % id):
				seen["wende%d" % id] = true
				stats["wende"] += 1
			if v.has("load_then") and (v["load_then"] as Dictionary).has("exit") and in_hall and not seen.has("dep%d" % id):
				seen["dep%d" % id] = true
				stats["dep_lane"] += 1
			if in_hall:
				max_wait = maxf(max_wait, float(v.get("wait", 0.0)))
			if shot != "":
				var ok := false
				match phase:
					"ab":
						ok = inside and not out and not bool(v["moving"]) and in_hall and float(st.get("t", 0.0)) > 3.0
					"wende":
						ok = out and bool(v["moving"]) and in_hall and (p - c).length() > 0.0 and int(v["i"]) >= int(v.get("shot_i", 15))
					"raus":
						ok = out and bool(v["moving"]) and not in_hall and int(v["i"]) >= 17
					"lade":
						ok = v.has("load_then") and (v["load_then"] as Dictionary).has("exit") and in_hall and not bool(v["moving"])
				if ok:
					print("bild bei ", i, " ", phase, " pos ", p)
					g.set_interior_view(true)
					var cam = main.cam_rig
					cam.target = Vector3(c.x, 0, c.z)
					cam.zoom = zoom
					cam.zoom_goal = zoom
					if yaw < 900.0:
						cam.yaw = yaw
						cam.yaw_goal = yaw
					main.hud.set_build_open(false)
					for k in range(40):
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png(shot)
					print(stats, " wait ", max_wait)
					get_tree().quit()
					return
	print(stats, " wait ", max_wait, " sorting ", ops.sorting.size())
	get_tree().quit()
