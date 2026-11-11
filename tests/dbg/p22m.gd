extends Node
## Probe 0.22: A380 und B767 nebeneinander, Bild.
func run(main: Node) -> void:
	await get_tree().process_frame
	var F = load("res://scripts/factory.gd")
	var base := Vector3(700, 0, 700)
	var a: Node3D = F.make_plane("a380", Color(0.75, 0.15, 0.2), 1)
	a.position = base
	a.rotation.y = deg_to_rad(-90)
	main.world.add_child(a)
	var b: Node3D = F.make_plane("b767", Color(0.1, 0.35, 0.7), 2)
	b.position = base + Vector3(0, 0, 70)
	b.rotation.y = deg_to_rad(-90)
	main.world.add_child(b)
	var cam = main.cam_rig
	cam.target = base + Vector3(0, 0, 35)
	cam.zoom = 95.0
	cam.zoom_goal = 95.0
	main.hud.set_build_open(false)
	for i in range(40):
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
