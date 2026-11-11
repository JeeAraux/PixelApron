extends Node
## Probe Wetter und Licht: [--innen] [--overlay=koffer] --wetter= --zeit=STUNDE --at=x,z --zoom= --yaw= BILD (startet sofort, ohne Demo-Vorlauf)
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1]
	var w := "klar"
	var hour := 12.0
	var at := Vector3(-40, 0, -40)
	var zoom := 230.0
	var yaw := 45.0
	for a: String in args:
		if a.begins_with("--wetter="):
			w = a.substr(9)
		elif a.begins_with("--zeit="):
			hour = float(a.substr(7))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--at="):
			var xz := a.substr(5).split(",")
			at = Vector3(float(xz[0]), 0, float(xz[1]))
	var g = main.game
	g.minutes = floorf(g.minutes / 1440.0) * 1440.0 + hour * 60.0
	main.weather.force(w)
	if "--innen" in args:
		g.set_interior_view(true)
	for a2: String in args:
		if a2.begins_with("--overlay="):
			main.overlay.set_mode(a2.substr(10))
	main.weather.strength = 1.0
	main.hud.set_build_open(false)
	main.cam_rig.target = at
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	main.cam_rig.yaw = yaw
	main.cam_rig.yaw_goal = yaw
	for i in range(400):
		main.flights.step(0.05)
	for _f in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
