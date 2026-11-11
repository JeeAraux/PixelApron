extends Node
## Probe Radfahrer: vier Tretphasen nebeneinander, Seitenansicht. BILD
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var F = load("res://scripts/factory.gd")
	var S = load("res://scripts/streetscape.gd")
	var base := Vector3(800, 0, 800)
	for i in range(4):
		var node := Node3D.new()
		var bm := MeshInstance3D.new()
		bm.mesh = S.bike_mesh(Color(0.7, 0.12, 0.1))
		node.add_child(bm)
		var rider: Node3D = F.make_person(Color(0.2, 0.4, 0.7))
		rider.position = Vector3(0, 0.06, 0.12)
		node.add_child(rider)
		F.set_pose(rider, 20 + i * 2)
		node.position = base + Vector3(0, 0, float(i) * 2.4)
		main.world.add_child(node)
	var c3 := Camera3D.new()
	c3.fov = 30.0
	main.world.add_child(c3)
	c3.global_position = base + Vector3(13.0, 1.4, 3.6)
	c3.look_at(base + Vector3(0, 0.8, 3.6))
	c3.make_current()
	main.hud.visible = false
	for _f in range(20):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
