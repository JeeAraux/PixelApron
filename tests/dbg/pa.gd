extends Node
## Probe 0.16: Raum ziehen, Kofferband, Flächenabriss, Bild.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var b = main.builder
	g.sandbox = true
	var h: Dictionary = g.build_hall(Rect2(600, 600, 64, 40))
	main.terminal.dirty = true
	g.set_interior_view(true)
	b.set_tool("raum")
	b.room_zone = "bereich_personal"
	b.room_door = "personal"
	b.on_move(Vector3(640, 0, 600))
	b.on_click(Vector3(640, 0, 600))
	b.on_move(Vector3(664, 0, 618))
	b.on_release(Vector3(664, 0, 618))
	print("walls ", g.walls_of(h).size(), " doors ", g.items_of("tuer").size(), " zones ", g.zones_of(h).size())
	# Sortierung im Raum, Check-ins davor, Kofferband
	print("sorter ", not g.build_item("gepaeckanlage", Vector3(652, 0, 608), 0).is_empty())
	for x: float in [612.0, 618.0, 624.0]:
		g.build_item("checkin", Vector3(x, 0, 626.5), 0)
	b.set_tool("kofferband")
	b.set_mode("gerade")
	var p0 := Vector3(627.45, 0, 625.34)
	b.on_move(p0)
	print("belt snap ", b.hover, " kind ", b.snap_kind)
	b.on_click(p0)
	b.on_move(Vector3(634, 0, 625.34))
	b.on_click(Vector3(634, 0, 625.34))
	b.on_move(Vector3(634, 0, 608))
	b.on_click(Vector3(634, 0, 608))
	b.on_move(Vector3(647.4, 0, 608))
	print("belt end snap ", b.hover, " ", b.snap_kind)
	b.on_click(Vector3(647.4, 0, 608))
	b.on_right()
	print("belts ", g.lines.filter(func(l: Dictionary) -> bool: return l["kind"] == "kofferband").size())
	print("linked ", g.checkins_linked(h).size())
	# zweite Kette: Check-ins untereinander verbinden (Lücke 6 m zwischen Schaltern)
	b.set_tool("")
	main.terminal._analyze()
	print(main.terminal.hall_summary(h))
	var cam = main.cam_rig
	var zz := 48.0
	var tt := Vector3(632, 0, 615)
	if OS.get_cmdline_user_args().has("--nah"):
		zz = 16.0
		tt = Vector3(619, 0, 627)
	cam.target = tt
	cam.zoom_goal = zz
	cam.zoom = zz
	main.hud.set_build_open(false)
	if OS.get_cmdline_user_args().has("--raum"):
		main.hud.show_tool("raum")
		b.set_tool("raum")
		main.hud.show_tool("raum")
		b.on_move(Vector3(606, 0, 600))
		b.on_click(Vector3(606, 0, 600))
		b.on_move(Vector3(628, 0, 614))
		cam.target = Vector3(625, 0, 612)
		cam.zoom_goal = 40.0
		cam.zoom = 40.0
	for i in range(90):
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	print("area ", g.area_victims(Rect2(605, 620, 25, 10)).size())
	get_tree().quit()
