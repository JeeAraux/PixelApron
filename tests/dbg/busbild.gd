extends Node
## Probe Vorfeldbus: Simulation, bis ein Bus nahe an einem Flugzeug fährt oder steht; Bild. --zoom= --nach= BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var zoom := 70.0
	var after := 0
	for a: String in args:
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		elif a.begins_with("--nach="):
			after = int(a.substr(7))
	var fl = main.flights
	var ops = main.ops
	var found: Dictionary = {}
	var at := Vector3.ZERO
	for i in range(30000):
		fl.step(0.1)
		if i % 20 == 0:
			for v: Dictionary in ops.vehicles:
				if v["kind"] == "bus" and bool(v["moving"]):
					for p: Dictionary in fl.planes:
						if p["state"] == "abfertigung" and (p["pos"] as Vector3).distance_to(v["pos"]) < 45.0:
							found = v
							at = p["pos"]
			if not found.is_empty():
				print("Bus bei ", (found["pos"] as Vector3).round(), " Schritt ", i)
				break
	for i in range(after):
		fl.step(0.1)
	main.hud.set_build_open(false)
	main.cam_rig.target = at
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	for _f in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
