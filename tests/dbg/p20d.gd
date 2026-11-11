extends Node
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var tb = main.terminal
	var ops = main.ops
	for i in range(50):
		main.flights.step(0.1)
	var sh: Dictionary = g.items_of("halle")[0]
	tb.stock[(sh["node"] as Node).get_instance_id()] = 0.3
	print("room ", g.room_ok(sh, "lager"), " net ", ops.net.pos.size(), " stock ", tb.stock_of(sh))
	var gate: Dictionary = g.items_of("rolltor")[0]
	var dp: Vector3 = ops.door_point(gate)
	var start: Vector3 = ops.net.pos[0]
	for q: Vector3 in ops.net.pos:
		if q.distance_to(dp) > start.distance_to(dp):
			start = q
	print("start ", start, " route ", ops.net.route(start, dp + Vector3(0,0,-4.5), 80.0).size())
	ops.delivery_t = 0.0
	ops._delivery_tick(0.1)
	print("deliveries ", ops.deliveries.size())
	get_tree().quit()
