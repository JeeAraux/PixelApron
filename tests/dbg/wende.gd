extends Node
## Probe Wendeplatte am Westende der Startpiste: bauen, Weg mit Umkehr prüfen, Bild. --zoom= BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1]
	var g = main.game
	g.sandbox = true
	var ms: Array = g.marker_snap("wendeplatte", Vector3(-1260, 0, -300))
	print("snap ", ms)
	var why: String = g.can_place("wendeplatte", ms[0], ms[1])
	print("can_place '", why, "'")
	var rec: Dictionary = g.build_item("wendeplatte", ms[0], ms[1])
	print("gebaut ", not rec.is_empty())
	main.flights._rebuild()
	var gr = main.flights.graph
	print("pads ", gr.pads.size())
	# von der Pistenmitte nach Westen rollen, am Ende wenden und nach Osten schauen
	var a: int = gr._nearest_kind(Vector3(-900, 0, -272), "piste")
	var thr := Vector3(-1300, 0, -272)
	var b: int = gr.pad_exit(thr)
	var path: Array = gr.path(a, b, {}, Vector3(-1, 0, 0), false, Vector3(1, 0, 0))
	print("weg ", path.size(), " knoten; über die Platte: ", path.any(func(n: int) -> bool: return gr.pos[n].z < -272.0 - 30.0 or gr.pos[n].z > -272.0 + 30.0))
	main.hud.set_build_open(false)
	main.cam_rig.target = Vector3(-1250, 0, -272)
	main.cam_rig.zoom = 160.0
	main.cam_rig.zoom_goal = 160.0
	for _f in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
