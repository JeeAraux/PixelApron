extends Node
## Probe: Räume nebeneinander, Türen auf gemeinsamen Wänden. --zoom= --yaw= --voll BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1]
	var yaw := 45.0
	var zoom := 34.0
	for a: String in args:
		if a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	var g = main.game
	g.sandbox = true
	var h: Dictionary = g.build_hall(Rect2(600, 600, 50, 30))
	g.set_interior_view(true)
	g.set_view_floor(0)
	if "--voll" in args:
		g.cycle_wall_mode()
	for r: Rect2 in [Rect2(604, 604, 8, 8), Rect2(612, 604, 8, 8), Rect2(604, 612, 16, 6), Rect2(620, 604, 6, 14)]:
		print("raum ", r, ": '", g.build_room(r, "", "fluegel", "", false), "'")
	for it: Dictionary in g.inside_of(h):
		if String(it["id"]) == "tuer":
			print("tür ", it["pos"], " rot ", it["rot"])
	for l: Dictionary in g.walls_of(h):
		print("wand ", (l["samples"] as PackedVector3Array)[0], " -> ", (l["samples"] as PackedVector3Array)[(l["samples"] as PackedVector3Array).size() - 1], " cuts ", g.wall_cuts(l))
	main.hud.set_build_open(false)
	main.cam_rig.target = Vector3(614, 0, 611)
	main.cam_rig.yaw = yaw
	main.cam_rig.yaw_goal = yaw
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	for _f in range(40):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
