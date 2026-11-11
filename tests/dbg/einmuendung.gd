extends Node
## Probe Einmündung einer Betriebsstraße: --at= --zoom= BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var g = main.game
	g.sandbox = true
	g.toast.connect(func(t: String) -> void: print("Meldung: ", t))
	var l: Dictionary = g.build_line("betriebsstrasse", [Vector3(600, 0, 150), Vector3(800, 0, 150)])
	g.build_line("betriebsstrasse", [Vector3(700, 0, 150), Vector3(700, 0, 190), Vector3(712, 0, 220)])
	print("gebaut ", not l.is_empty())
	var l2: Dictionary = g.build_line("betriebsstrasse", [Vector3(640, 0, 110), Vector3(655, 0, 150)])
	print("schräg ", not l2.is_empty())
	main.hud.set_build_open(false)
	main.cam_rig.target = Vector3(700, 0, 152)
	main.cam_rig.zoom = 22.0
	main.cam_rig.zoom_goal = 22.0
	for _f in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
