extends Node
## Probe Hallen mit Torzahl (Busgarage, Feuerwache, Gepäckumschlag im Startflughafen): --innen --zoom= --yaw= BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1]
	var zoom := 120.0
	var yaw := 45.0
	for a: String in args:
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
	var g = main.game
	for id: String in ["busgarage", "feuerwache", "gepaeckumschlag"]:
		for it: Dictionary in g.items_of(id):
			print(id, " ", it["rect"], " opts ", it.get("opts", {}))
	if "--ohne_tor" in args:
		for r: Dictionary in g.items_of("rolltor").duplicate():
			g.remove(r)
	if "--innen" in args:
		g.set_interior_view(true)
	var seen := 0
	for i in range(int(_arg(args, "--schritte=", "3000"))):
		main.flights.step(0.05)
		for v: Dictionary in main.ops.sorting:
			var g2: Variant = v.get("sort_door")
			if g2 is Dictionary and (g2 as Dictionary).has("umschlag") and bool((v.get("sort", {}) as Dictionary).get("inside", false)):
				if seen < 3 and i % 200 == 0:
					print("Zug in Spur ", (g2 as Dictionary)["bay"], " pos ", v["pos"], " moving ", v["moving"])
					seen += 1
	main.hud.set_build_open(false)
	main.cam_rig.target = Vector3(315, 0, -40)
	for a2: String in args:
		if a2.begins_with("--at="):
			var xz := a2.substr(5).split(",")
			main.cam_rig.target = Vector3(float(xz[0]), 0, float(xz[1]))
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	main.cam_rig.yaw = yaw
	main.cam_rig.yaw_goal = yaw
	for _f in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()


func _arg(args: PackedStringArray, key: String, def: String) -> String:
	for a: String in args:
		if a.begins_with(key):
			return a.substr(key.length())
	return def
