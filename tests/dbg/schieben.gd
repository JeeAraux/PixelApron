extends Node
## Probe Verschieben über das Werkzeug: Tower, Außenstand (mit Einrolllinien), neue Halle mit Einrichtung und Wand. [--innen] --at= --zoom= BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var g = main.game
	var b = main.builder
	g.sandbox = true
	var toasts := []
	g.toast.connect(func(t: String) -> void: toasts.append(t))
	var carry := func(at: Vector3, to: Vector3) -> void:
		b.on_move(at)
		b.on_click(at)
		b.on_move(to)
		b.on_click(to)
	b.set_tool("verschieben")
	var tw: Dictionary = g.items_of("tower")[0]
	var p0: Vector3 = tw["pos"]
	carry.call(p0, p0 + Vector3(-55, 0, 10))
	print("Tower ", p0, " -> ", tw["pos"], " ", toasts)
	toasts.clear()
	var st: Dictionary = g.items_of("stand_aussen")[0]
	var sp: Vector3 = st["pos"]
	carry.call(sp, sp + Vector3(-15, 0, 0))
	print("Stand ", sp, " -> ", st["pos"], " Linien ", g.stand_lines(st).size(), " ", toasts)
	toasts.clear()
	b.set_tool("")
	var h: Dictionary = g.build_hall(Rect2(520, 140, 60, 40))
	g.set_interior_view(true)
	g.view_floor = 0
	var shop: Dictionary = g.build_item("shop", Vector3(540, 0, 160), 0)
	var wall: Dictionary = g.build_line("innenwand", [Vector3(560, 0, 142), Vector3(560, 0, 170)])
	print("Halle gebaut ", not h.is_empty(), " Shop ", not shop.is_empty(), " Wand ", not wall.is_empty())
	b.set_tool("verschieben")
	var hp: Vector3 = h["pos"]
	carry.call(hp + Vector3(12, 0, 12), hp + Vector3(52, 0, 42))
	print("Halle ", hp, " -> ", h["pos"], " Shop ", shop.get("pos"), " Wand ", (wall.get("points", [Vector3.ZERO]) as Array)[0], " ", toasts)
	b.set_tool("")
	g.set_interior_view("--innen" in args)
	main.hud.set_build_open(false)
	var at := (h["pos"] as Vector3)
	var zoom := 140.0
	for a: String in args:
		if a.begins_with("--at="):
			var xz := a.substr(5).split(",")
			at = Vector3(float(xz[0]), 0, float(xz[1]))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	if "--halten" in args:
		# Halle aufnehmen und über freier Wiese halten (Vorschau)
		b.set_tool("verschieben")
		b.on_move(h["pos"])
		b.on_click(h["pos"])
		b.on_move((h["pos"] as Vector3) + Vector3(-30, 0, 20))
		at = (h["pos"] as Vector3) + Vector3(-15, 0, 10)
	main.cam_rig.target = at
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	for _f in range(40):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
