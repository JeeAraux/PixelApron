extends Node
## Probe Flugzeugnase: ein Flugzeug groß, Kamera auf die Front. --kind= --yaw= --zoom= --dreh= (Grad) BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var F = load("res://scripts/factory.gd")
	var args := OS.get_cmdline_user_args()
	var kind := "a320"
	var zoom := 16.0
	var yaw := 45.0
	var dreh := -60.0
	var at := 0.0
	var eye := ""
	for a: String in args:
		if a.begins_with("--kind="):
			kind = a.substr(7)
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--dreh="):
			dreh = float(a.substr(7))
		elif a.begins_with("--auf="):
			at = float(a.substr(6))
		elif a.begins_with("--eye="):
			eye = a.substr(6)
	var base := Vector3(800, 0, 800)
	var pl: Node3D = F.make_plane(kind, Color(0.1, 0.3, 0.65), 1)
	pl.position = base
	pl.rotation.y = deg_to_rad(dreh)
	main.world.add_child(pl)
	var Cat = load("res://scripts/catalog.gd")
	var cam = main.cam_rig
	var M = load("res://scripts/models.gd")
	var sp: Dictionary = M.SPECS.get(kind, M.SPECS["a320"])
	cam.target = base + pl.basis * Vector3(0, float(sp["cy"]), -float(sp["len"]) * 0.5 + 3.0 + at)
	cam.yaw = yaw
	cam.yaw_goal = yaw
	cam.zoom = zoom
	cam.zoom_goal = zoom
	if eye != "":
		# Augenhöhe: --eye=azimut,erhebung,abstand (Grad, Grad, m), Blick auf die Nase (+--auf)
		var e := eye.split(",")
		var az := deg_to_rad(float(e[0]))
		var el := deg_to_rad(float(e[1]))
		var dist := float(e[2])
		var look := pl.global_transform * Vector3(0, float(sp["cy"]) + float(sp["r"]) * 0.35, -float(sp["len"]) * 0.5 + float(sp["nose_len"]) * 0.8 + at)
		var dir := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
		var c3 := Camera3D.new()
		c3.fov = 30.0
		c3.far = 4000.0
		main.world.add_child(c3)
		c3.global_position = look + (pl.global_transform.basis * dir) * dist
		c3.look_at(look)
		c3.make_current()
	main.hud.set_build_open(false)
	main.hud.visible = false
	for i in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
