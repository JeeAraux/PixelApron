extends Node
## Probe kleineres Obergeschoss: Starthalle bekommt 3 Ebenen, 1. OG schmaler, 2. OG noch kleiner. [--innen --ebene=N] --zoom= --yaw= BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1]
	var g = main.game
	g.sandbox = true
	var h: Dictionary = g.items_of("halle")[0]
	var r: Rect2 = h["rect"]
	print("halle ", r, " ebenen ", g.hall_levels(h))
	for _i in range(4):
		if g.hall_levels(h) >= 3:
			break
		var w: String = g.cycle_option(h, "etagen", 1)
		if w != "":
			print("etagen: ", w)
			break
	var r1 := Rect2(r.position.x + 8, r.position.y + 6, r.size.x - 16, r.size.y - 14)
	r1 = g.storey_rect(Vector3(r1.position.x, 0, r1.position.y), Vector3(r1.end.x, 0, r1.end.y))
	print("og1 '", g.set_storey(h, 1, r1), "' ", g.floor_rect(h, 1))
	var r2 := Rect2(r1.position.x + r1.size.x * 0.35, r1.position.y + 6, r1.size.x * 0.4, r1.size.y - 12)
	r2 = g.storey_rect(Vector3(r2.position.x, 0, r2.position.y), Vector3(r2.end.x, 0, r2.end.y))
	print("og2 '", g.set_storey(h, 2, r2), "' ", g.floor_rect(h, 2))
	print("zu groß '", g.storey_problem(h, 2, r1.grow(4)), "'")
	var c := r.get_center()
	print("bau draußen '", g.can_place("gate", Vector3(r.position.x + 3, 0, c.y), 0), "' (Ebene ", g.view_floor, ")")
	var zoom := 150.0
	var yaw := 35.0
	var ebene := 0
	for a: String in args:
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--ebene="):
			ebene = int(a.substr(8))
	if "--innen" in args:
		g.set_interior_view(true)
		g.set_view_floor(ebene)
		print("bau außerhalb OG '", g.can_place("gate", Vector3(r.position.x + 3, 0, c.y), 0), "'")
		print("bau innerhalb OG '", g.can_place("gate", Vector3(c.x, 0, c.y), 0), "'")
	main.hud.set_build_open(false)
	main.cam_rig.target = Vector3(c.x, 0, c.y)
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	main.cam_rig.yaw = yaw
	main.cam_rig.yaw_goal = yaw
	for _f in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
