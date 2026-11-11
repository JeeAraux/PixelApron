extends Node
## Probe 0.19: Gepäckzug fährt durchs Rolltor hinein, lädt ab, fährt rückwärts hinaus; Abflugzüge an den Rutschen.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var ops = main.ops
	var fl = main.flights
	var tb = main.terminal
	seed(20261110)
	var inside_seen := false
	var out_seen := false
	var home_after := false
	var max_users := 0
	var load_bags := 0
	var hall: Dictionary = g.items_of("halle")[0]
	var args := OS.get_cmdline_user_args()
	var shot := args[args.size() - 1] if args.size() > 1 and args[args.size() - 1].ends_with(".png") else ""
	for i in range(16000):
		fl.step(0.1)
		if shot != "":
			var ready := false
			for v: Dictionary in ops.sorting:
				var st0: Dictionary = v.get("sort", {})
				if bool(st0.get("inside", false)) and not bool(v["moving"]) and not bool(st0.get("out", false)) and float(st0.get("t", 0.0)) > 4.0:
					ready = true
			if ready:
				g.set_interior_view(true)
				var cam = main.cam_rig
				cam.target = Vector3(100, 0, -22)
				cam.zoom = 24.0
				cam.zoom_goal = 24.0
				for a: String in args:
					if a.begins_with("--yaw="):
						cam.yaw = float(a.substr(6))
						cam.yaw_goal = cam.yaw
				main.hud.set_build_open(false)
				for k in range(40):
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png(shot)
				get_tree().quit()
				return
		for v: Dictionary in ops.sorting:
			var st: Dictionary = v.get("sort", {})
			if bool(st.get("inside", false)) and (hall["rect"] as Rect2).has_point(Vector2((v["pos"] as Vector3).x, (v["pos"] as Vector3).z)):
				if not inside_seen:
					print("drin bei ", i, " pos ", v["pos"])
				inside_seen = true
			if bool(st.get("out", false)):
				out_seen = true
		max_users = maxi(max_users, ops.chute_users.size())
		for b: Dictionary in tb.moving_bags:
			if b.has("claim") and not b.has("v"):
				pass
		if out_seen and inside_seen and i % 100 == 0:
			home_after = true
	print("inside ", inside_seen, " out ", out_seen, " chute max ", max_users, " pool ", tb.transfer_pool, " sorting ", ops.sorting.size())
	get_tree().quit()
