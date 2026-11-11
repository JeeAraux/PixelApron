extends Node
## Probe 0.21: Ereignisse auslösen und ein Stück laufen lassen; Bild mit --kind=… und Pfad.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var ev = main.events
	var fl = main.flights
	var ops = main.ops
	var tb = main.terminal
	seed(20261110)
	var args := OS.get_cmdline_user_args()
	var kind := "notfall_terminal"
	for a: String in args:
		if a.begins_with("--kind="):
			kind = a.substr(7)
	g.toast.connect(func(t: String) -> void: print("TOAST ", t))
	# erst Betrieb anlaufen lassen, bis Fluggäste im Terminal sind
	for i in range(2600):
		fl.step(0.1)
	print("people ", tb.people.size(), " planes ", fl.planes.size())
	var ok: bool = ev.trigger(kind)
	print("trigger ", kind, " ", ok)
	var shot := args[args.size() - 1] if args.size() > 1 and args[args.size() - 1].ends_with(".png") else ""
	var shot_at := -1
	for i in range(3000):
		fl.step(0.1)
		if shot != "" and kind == "notfall_terminal" and not ops.rtw_jobs.is_empty() and String(ops.rtw_jobs[0]["phase"]) == "vor_ort":
			shot_at = i
			break
		if ev.active.is_empty() and i > 50:
			print("fertig nach ", i)
			break
	print("rtw jobs ", ops.rtw_jobs.size(), " active ", ev.active.size())
	if shot != "":
		var cam = main.cam_rig
		var at := Vector3(0, 0, -30)
		if not ops.rtw_jobs.is_empty():
			at = (ops.rtw_jobs[0]["v"]["pos"] as Vector3)
		cam.target = at
		cam.zoom = 30.0
		cam.zoom_goal = 30.0
		for a: String in args:
			if a.begins_with("--yaw="):
				cam.yaw = float(a.substr(6))
				cam.yaw_goal = cam.yaw
			if a == "--innen":
				g.set_interior_view(true)
			if a.begins_with("--overlay="):
				main.overlay.set_mode(a.substr(10))
				cam.zoom = 900.0
				cam.zoom_goal = 900.0
				cam.target = Vector3(0, 0, -150)
		main.hud.set_build_open(false)
		for i in range(40):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
