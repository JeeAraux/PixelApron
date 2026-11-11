extends Node
## Probe: Rolltreppe/Treppe Keller → EG und EG → OG; Aufnahme der Ebene --ebene=N (Standard 0).
## --yaw= --zoom= BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1]
	var ebene := 0
	var yaw := 45.0
	var zoom := 40.0
	for a: String in args:
		if a.begins_with("--ebene="):
			ebene = int(a.substr(8))
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	var g = main.game
	var b = main.builder
	g.sandbox = true
	var h: Dictionary = g.build_hall(Rect2(600, 600, 50, 30))
	g.cycle_option(h, "etagen", 1)
	g.set_interior_view(true)
	g.set_view_floor(-1)
	for e: Array in [["rolltreppe", Vector3(612, 0, 612)], ["treppe", Vector3(625, 0, 612)]]:
		b.set_tool(e[0])
		b.on_move(e[1])
		var n0: int = g.items.size()
		b.on_click(e[1])
		print("UG ", e[0], " gebaut ", g.items.size() - n0, " '", b.reason, "'")
	g.set_view_floor(0)
	for e: Array in [["rolltreppe", Vector3(612, 0, 622)], ["aufzug", Vector3(630, 0, 622)]]:
		b.set_tool(e[0])
		b.on_move(e[1])
		var n0: int = g.items.size()
		b.on_click(e[1])
		print("EG ", e[0], " gebaut ", g.items.size() - n0, " '", b.reason, "'")
	b.set_tool("")
	g.set_view_floor(ebene)
	main.hud.set_build_open(false)
	main.cam_rig.target = Vector3(620, float(ebene) * 5.0, 617)
	main.cam_rig.yaw = yaw
	main.cam_rig.yaw_goal = yaw
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	for _f in range(40):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
