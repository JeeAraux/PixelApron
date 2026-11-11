extends Node
## Probe Pushback: läuft bis zum ersten Pushback und nimmt fünf Bilder auf (BILD_0..4.png), --zoom=
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1].trim_suffix(".png")
	var zoom := 110.0
	for a: String in args:
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	var fl = main.flights
	main.hud.set_build_open(false)
	var found: Dictionary = {}
	for i in range(30000):
		fl.step(0.05)
		for p: Dictionary in fl.planes:
			if p["state"] == "pushback" and p.has("push"):
				found = p
		if not found.is_empty():
			break
	if found.is_empty():
		print("kein Pushback")
		get_tree().quit()
		return
	var pts: PackedVector3Array = found["push"]["pts"]
	var mk := Node3D.new()
	main.world.add_child(mk)
	for q: Vector3 in pts:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.6, 0.6, 0.6)
		b.mesh = bm
		b.position = q + Vector3(0, 0.3, 0)
		mk.add_child(b)
	print("push total ", found["push"]["total"], " start ", pts[0], " end ", pts[pts.size() - 1])
	var c: Vector3 = (pts[0] + pts[pts.size() - 1]) * 0.5
	main.cam_rig.target = c
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	var shots := 0
	var last := -1.0
	for i in range(20000):
		fl.step(0.05)
		var total := float(found["push"]["total"]) if found.has("push") else 1.0
		var ps := float(found.get("ps", 0.0))
		var frac := ps / maxf(total, 1.0)
		var want := float(shots) / 4.0
		if (frac >= want - 0.001 and frac > last + 0.01) or (shots == 4 and found["state"] != "pushback") or (shots == 0):
			last = frac
			for _f in range(4):
				await get_tree().process_frame
			print("bild ", shots, " state ", found["state"], " phase ", found.get("push_phase", ""), " ps ", ps, " pos ", found["pos"], " heading ", found["heading"])
			get_viewport().get_texture().get_image().save_png("%s_%d.png" % [shot, shots])
			shots += 1
			if shots > 4:
				break
		if found["state"] != "pushback" and shots < 4:
			shots = 4
	get_tree().quit()
