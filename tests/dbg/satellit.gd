extends Node
## Probe 0.31: Satellit (Halle ohne Eingang) über Personentunnel und Rolltreppen an die Haupthalle.
## Abfliegende checken in der Haupthalle ein und gehen durch den Tunnel zum Bus-Gate im Satelliten.
## --bild=tunnel|satellit|draussen, --zoom=, letztes Argument BILD.png
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var tb = main.terminal
	var fl = main.flights
	g.sandbox = true
	seed(5)
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1] if args.size() > 1 and args[args.size() - 1].ends_with(".png") else ""
	var mode := "tunnel"
	var zoom := 60.0
	for a: String in args:
		if a.begins_with("--bild="):
			mode = a.substr(7)
		if a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	var sat: Dictionary = g.build_hall(Rect2(60, 78, 44, 22), true)
	print("satellit ", not sat.is_empty())
	var tr: Dictionary = g.build_item("trafo", Vector3(112, 0, 92), 0, true)
	print("trafo ", not tr.is_empty(), " ", g.can_place("trafo", Vector3(112, 0, 92), 0))
	g.build_line("stromkabel", [Vector3(109, 0, 92), Vector3(103, 0, 92)], true)
	g.build_line("wasserrohr", [Vector3(40, 0, 18), Vector3(64, 0, 79)], true)
	g.set_interior_view(true)
	g.view_floor = 0
	g.build_zone("bereich_sicherheit", Rect2(60, 78, 44, 22), true, 0)
	var bg: Dictionary = g.build_item("busgate", Vector3(90, 0, 96), 2, true)
	print("busgate ", not bg.is_empty(), " ", g.can_place("busgate", Vector3(90, 0, 96), 2))
	for x: float in [70.0, 76.0]:
		g.build_item("sitzreihe", Vector3(x, 0, 88), 0, true)
	g.build_item("wc", Vector3(99, 0, 82), 0, true)
	var tun: Dictionary = g.build_line("personentunnel", [Vector3(52, 0, 2), Vector3(56, 0, 40), Vector3(66, 0, 84)], false)
	print("tunnel ", not tun.is_empty(), " ", g.ped_tunnel_why(g.line_samples("personentunnel", [Vector3(52, 0, 2), Vector3(56, 0, 40), Vector3(66, 0, 84)])))
	g.view_floor = -1
	var main_hall: Dictionary = g.items_of("halle")[0]
	var esc1: Dictionary = g.build_item("rolltreppe", Vector3(48, 0, 6), 0, true, {}, -1)
	var esc2: Dictionary = g.build_item("rolltreppe", Vector3(70, 0, 92), 2, true, {}, -1)
	print("rolltreppen ", not esc1.is_empty(), " ", not esc2.is_empty(), " | ", g.can_place("rolltreppe", Vector3(48, 0, 6), 0))
	g.view_floor = 0
	g.set_interior_view(false)
	tb.dirty = true
	tb._analyze()
	for info: Dictionary in tb.halls:
		print("halle ", info["hall"]["rect"], " komplett ", info["complete"], " fehlt ", info["missing"], " probleme ", info["problems"], " strom ", info["powered"])
	print("links ", tb.links.size(), " check '", tb.check(), "'")
	# alle Gates der Haupthalle als belegt markieren, damit der Satellit drankommt
	for it: Dictionary in g.inside_of(main_hall):
		if it["id"] in ["gate", "busgate"]:
			tb.gate_use[(it["node"] as Node).get_instance_id()] = 999999
	var in_tunnel := 0
	var at_sat := 0
	var arr_back := 0
	var shot_done := false
	for i in range(14000):
		fl.step(0.1)
		var nt := 0
		var ns := 0
		for per: Dictionary in tb.people:
			if per.has("follow"):
				continue
			var pp: Vector3 = per["pos"]
			if per.has("tun"):
				nt += 1
			if (sat["rect"] as Rect2).has_point(Vector2(pp.x, pp.z)) and pp.y > -1.0 and bool(per["dep"]):
				ns += 1
		in_tunnel = maxi(in_tunnel, nt)
		at_sat = maxi(at_sat, ns)
		if shot != "" and not shot_done and ((mode == "tunnel" and nt >= 6) or (mode == "satellit" and ns >= 5)):
			shot_done = true
			var cam = main.cam_rig
			g.set_interior_view(true)
			if mode == "tunnel":
				g.set_view_floor(-1)
				cam.target = Vector3(56, -5, 40)
			else:
				g.set_view_floor(0)
				cam.target = Vector3(82, 0, 89)
			cam.zoom = zoom
			cam.zoom_goal = zoom
			main.hud.set_build_open(false)
			for k in range(40):
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(shot)
			print("nachher leute ", tb.people.size())
			for per2: Dictionary in tb.people:
				if per2.has("tun"):
					var nd: Node3D = per2["node"]
					print("tun ", per2["pos"], " vis ", nd.visible, " sichtbar ", nd.is_visible_in_tree(), " eltern ", nd.get_parent().name, " ", nd.get_parent().visible)
			print("bild bei ", i, " im tunnel ", nt, " im satelliten ", ns)
			get_tree().quit()
			return
	print("max im tunnel ", in_tunnel, " max abfliegend im satelliten ", at_sat)
	get_tree().quit()


func Catalog_has(id: String) -> bool:
	return load("res://scripts/catalog.gd").LINES.has(id)
