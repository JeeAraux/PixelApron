extends Node
func run(main: Node) -> void:
	await get_tree().process_frame
	main.set_process(false)
	var ops = main.ops
	ops.fire_t = 9999.0
	print("Einsatz ", ops._fire_mission("kontrolle", null, 0.0))
	var m: Dictionary = ops.missions[0]
	var v: Dictionary = m["v"]
	var key: String = ops._door_key(m["station"], int(m["idx"]))
	for i in range(400):
		main.flights.step(0.05)
		if i % 10 == 0:
			print(i, " tor=", snappedf(float(ops.door_open.get(key, 0.0)), 0.01), " phase=", m["phase"], " pos=", (v["pos"] as Vector3).round(), " moving=", v["moving"], " await=", v.has("await_door"), " v=", snappedf(float(v["v"]), 0.1))
	get_tree().quit()
