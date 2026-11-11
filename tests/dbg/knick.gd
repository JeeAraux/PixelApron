extends Node
## Bild: Straßenkette mit Knicken, spitze Einmündung, Kreuzung im Winkel.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	g.sandbox = true
	var a := Vector3(420, 0, 300)
	var pts := [a, Vector3(480, 0, 300), Vector3(530, 0, 330), Vector3(570, 0, 330), Vector3(600, 0, 290)]
	for i in range(pts.size() - 1):
		g.build_line("strasse", [pts[i], pts[i + 1]], false, false, "gehweg")
	g.build_line("strasse", [Vector3(500, 0, 400), Vector3(520, 0, 260)], false, false, "rad")
	g.build_line("strasse", [Vector3(450, 0, 380), Vector3(480, 0, 301)], false, false, "allee")
	var cam = main.cam_rig
	cam.target = Vector3(510, 0, 320)
	cam.zoom_goal = 95.0
	cam.zoom = 95.0
	main.hud.set_build_open(false)
	for i in range(90):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().size() - 1])
	get_tree().quit()
