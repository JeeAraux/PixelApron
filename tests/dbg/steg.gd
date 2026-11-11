extends Node
## Bild: Fluggastbrücke mit Steg über die Betriebsstraße.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	g.sandbox = true
	var br: Array = g.items_of("fluggastbruecke")
	var b0: Dictionary = br[0]
	print("steg: '", g.cycle_option(b0, "steg", 1), "' ", g.opt(b0, "steg"), " pos ", b0["pos"])
	var b1: Dictionary = br[1]
	print("steg2: '", g.cycle_option(b1, "steg", 1), "' '", g.cycle_option(b1, "steg", 1), "' ", g.opt(b1, "steg"), " pos ", b1["pos"])
	main.terminal._rebuild_bridges()
	print("gate ", not (main.terminal.bridges.values()[0]["gate"] as Dictionary).is_empty())
	var cam = main.cam_rig
	cam.target = Vector3(-30, 0, -38)
	cam.zoom_goal = 34.0
	cam.zoom = 34.0
	main.hud.set_build_open(false)
	for i in range(1200):
		main.flights.step(0.05)
	for i in range(90):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_cmdline_user_args()[OS.get_cmdline_user_args().size() - 1])
	get_tree().quit()
