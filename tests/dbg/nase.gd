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
	main.hud.set_build_open(false)
	main.hud.visible = false
	for i in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
