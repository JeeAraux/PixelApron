extends Node
## Probe Gerätehalle: Simulation laufen lassen, Fahrzeuge in der Nähe der Halle ausgeben und Bild. --schritte= --at= --zoom= BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var steps := 6000
	var at := Vector3(-160, 0, -25)
	var zoom := 60.0
	for a: String in args:
		if a.begins_with("--schritte="):
			steps = int(a.substr(11))
		elif a.begins_with("--at="):
			var xz := a.substr(5).split(",")
			at = Vector3(float(xz[0]), 0, float(xz[1]))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	var ops = main.ops
	var worst := 0
	for i in range(steps):
		main.flights.step(0.1)
		if i % 500 == 0:
			var near := 0
			for v: Dictionary in ops.vehicles:
				if (v["pos"] as Vector3).distance_to(at) < 30.0:
					near += 1
			worst = maxi(worst, near)
			print(i, " nahe der Halle: ", near, " zurück: ", ops.returning.size())
	for v: Dictionary in ops.vehicles:
		if (v["pos"] as Vector3).distance_to(at) < 30.0:
			var ph := ""
			for j: Dictionary in ops.jobs.values():
				for sv: Dictionary in j.get("svc", []):
					if sv.get("v") is Dictionary and is_same(sv["v"], v):
						ph = String(sv["phase"]) + " home " + str(sv["home"])
			print("  ", v["kind"], " ", (v["pos"] as Vector3).round(), " fährt ", v["moving"], " zurück ", v in ops.returning, " v ", snappedf(float(v.get("v", 0.0)), 0.1), " ", ph, " flug ", v.get("flight", -1))
	main.hud.set_build_open(false)
	main.cam_rig.target = at
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	print("vor Bildern: '", main.flights.check_operation(), "'")
	for _f in range(30):
		await get_tree().process_frame
	print("Betrieb: '", main.flights.check_operation(), "' Terminal: '", main.terminal.check(), "'")
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
