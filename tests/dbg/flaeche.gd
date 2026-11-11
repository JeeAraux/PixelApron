extends Node
## Probe Vorfeldfläche: Fläche aufziehen, Stand darauf, Rollführungslinie vom Rollweg A, Weg prüfen. BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1]
	var g = main.game
	g.sandbox = true
	var r := Rect2(420, -92, 120, 50)
	print("apron '", g.can_place_apron(r), "'")
	var a: Dictionary = g.build_apron(r)
	print("gebaut ", not a.is_empty(), " ", a.get("rect"))
	print("apron2 '", g.can_place_apron(Rect2(540, -92, 40, 30)), "'")
	g.build_apron(Rect2(540, -92, 40, 30))
	var sp := Vector3(480, 0, -64)
	print("stand '", g.can_place("stand_aussen", sp, 0), "'")
	var st: Dictionary = g.build_item("stand_aussen", sp, 0)
	print("stand gebaut ", not st.is_empty())
	var l: Dictionary = g.build_line("rolllinie", [Vector3(440, 0, -104), Vector3(462, 0, -98), Vector3(478, 0, -90), Vector3(480, 0, -86)])
	print("linie ", not l.is_empty())
	main.flights._rebuild()
	var gr = main.flights.graph
	var sid: int = gr.stand_node.get((st["node"] as Node).get_instance_id(), -1)
	var rw: int = gr._nearest_kind(Vector3(0, 0, -272), "piste")
	var path: Array = gr.path(rw, sid) if sid >= 0 else []
	print("stand ", sid, " weg von der Piste: ", path.size(), " Knoten")
	main.hud.set_build_open(false)
	main.cam_rig.target = Vector3(490, 0, -75)
	main.cam_rig.zoom = 110.0
	main.cam_rig.zoom_goal = 110.0
	for _f in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
