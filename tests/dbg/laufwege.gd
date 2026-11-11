extends Node
## Probe Laufwege im Terminal: Spuren der Menschen als Punkte. --schritte= --at= --zoom= BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var steps := 2500
	var at := Vector3(-40, 0, -5)
	var zoom := 70.0
	for a: String in args:
		if a.begins_with("--schritte="):
			steps = int(a.substr(11))
		elif a.begins_with("--at="):
			var xz := a.substr(5).split(",")
			at = Vector3(float(xz[0]), 0, float(xz[1]))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	var tb = main.terminal
	var pts := PackedVector3Array()
	for i in range(steps):
		main.flights.step(0.1)
		if i % 25 == 0:
			await get_tree().process_frame
		if i > steps - 900 and i % 3 == 0:
			for per: Dictionary in tb.people:
				var p: Vector3 = per["pos"]
				if p.y < 1.0:
					pts.append(p)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.18, 0.05, 0.18)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.6)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = mat
	mm.mesh = bm
	mm.instance_count = pts.size()
	for i in range(pts.size()):
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i] + Vector3(0, 0.15, 0)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	main.world.add_child(mi)
	print("Spurpunkte ", pts.size())
	main.game.set_interior_view(true)
	main.hud.set_build_open(false)
	main.cam_rig.target = at
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	for _f in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
