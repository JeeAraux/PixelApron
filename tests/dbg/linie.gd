extends Node
## Probe Einrolllinien als Rolllinien im Startflughafen: Weg zum Stand, Abriss, Bild. --at=x,z --zoom= BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var g = main.game
	g.sandbox = true
	var n := 0
	for l: Dictionary in g.lines:
		if l["kind"] == "rolllinie":
			n += 1
	print("rolllinien ", n)
	for st: Dictionary in g.stands():
		print(st["id"], " ", st["pos"], " linien ", g.stand_lines(st).size())
	main.flights._rebuild()
	var gr = main.flights.graph
	var st0: Dictionary = g.stands()[1]
	var sid: int = gr.stand_node.get((st0["node"] as Node).get_instance_id(), -1)
	var rw: int = gr._nearest_kind(Vector3(0, 0, -272), "piste")
	var path: Array = gr.path(rw, sid)
	var kinds := {}
	for i: int in path:
		kinds[gr.kind[i]] = int(kinds.get(gr.kind[i], 0)) + 1
	print("weg zum Stand ", path.size(), " Knoten ", kinds)
	if "--abriss" in args:
		var before: int = g.lines.size()
		g.remove(g.stands()[0])
		print("Abriss nimmt Linien mit: ", before - g.lines.size())
	main.hud.set_build_open(false)
	var at := Vector3(-40, 0, -75)
	var zoom := 90.0
	for a: String in args:
		if a.begins_with("--at="):
			var xz := a.substr(5).split(",")
			at = Vector3(float(xz[0]), 0, float(xz[1]))
		elif a.begins_with("--zoom="):
			zoom = float(a.substr(7))
	main.cam_rig.target = at
	main.cam_rig.zoom = zoom
	main.cam_rig.zoom_goal = zoom
	for _f in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
