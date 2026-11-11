extends Node
## Probe Abfertigung: --kind= --f=0.5 --zoom= --yaw= BILD (Flugzeug dieses Musters am Stand)
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1]
	var kind := "a320"
	var want := 0.5
	var zoom := 70.0
	var yaw := 45.0
	for a: String in args:
		if a.begins_with("--kind="):
			kind = a.substr(7)
		elif a.begins_with("--f="):
			want = float(a.substr(4))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
	var fl = main.flights
	fl.force_kind = kind
	main.game.sandbox = true
	var found: Dictionary = {}
	for i in range(40000):
		fl.step(0.05)
		for p: Dictionary in fl.planes:
			if String(p["kind"]) == kind and p["state"] == "abfertigung":
				var f := 1.0 - float(p["timer"]) / maxf(float(p["turn"]), 0.01)
				if f >= want:
					found = p
		if not found.is_empty():
			break
	if found.is_empty():
		print("keins gefunden")
		get_tree().quit()
		return
	print("gefunden ", found["code"], " am Stand ", found["pos"])
	main.hud.set_build_open(false)
	var h: Vector3 = found["heading"]
	main.cam_rig.target = (found["pos"] as Vector3) + h.cross(Vector3.UP) * 6.0
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	main.cam_rig.yaw = yaw
	main.cam_rig.yaw_goal = yaw
	for _f in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
