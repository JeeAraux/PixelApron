extends Node
## Bild: Startterminal mit zweiter Ebene, Ansicht 1. OG.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var b = main.builder
	g.sandbox = true
	var h: Dictionary = g.items_of("halle")[0]
	print("etagen: ", g.cycle_option(h, "etagen", 1), " ", g.hall_levels(h))
	var r: Rect2 = h["rect"]
	print("rect ", r)
	g.set_interior_view(true)
	g.set_view_floor(int(OS.get_cmdline_user_args().has("--eg")) * -1 + 1)
	if g.view_floor == 1:
		b.set_tool("cafe")
		var c := r.get_center()
		b.on_move(Vector3(c.x, 0, c.y))
		print("cafe reason ", b.reason)
		b.on_click(Vector3(c.x, 0, c.y))
		b.set_tool("sitzreihe")
		b.on_move(Vector3(c.x + 20, 0, c.y))
		print("sitz reason ", b.reason)
		b.on_click(Vector3(c.x + 20, 0, c.y))
		b.set_tool("innenwand")
		b.on_click(Vector3(r.position.x + 10, 0, c.y + 5))
		b.on_click(Vector3(r.position.x + 40, 0, c.y + 5))
		b.finish()
		b.set_tool("checkin")
		b.on_move(Vector3(c.x - 15, 0, c.y - 4))
	var cam = main.cam_rig
	cam.target = Vector3(r.get_center().x, 5.0 * g.view_floor, r.get_center().y)
	cam.zoom_goal = 90.0
	cam.zoom = 90.0
	for i in range(90):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().size() - 1])
	get_tree().quit()
