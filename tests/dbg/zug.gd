extends Node
## Abstände der Gepäckwagen: kleinster Abstand der Wagenmitten je Zug und zwischen Zügen.
func run(main: Node) -> void:
	await get_tree().process_frame
	main.set_process(false)
	seed(20261110)
	var fl = main.flights
	var own := INF
	var other := INF
	for i in range(9000):
		fl.step(0.1)
		if i % 20 != 0:
			continue
		var trains := []
		for v: Dictionary in main.ops.vehicles:
			if (v.get("car_pos", []) as Array).size() >= 2:
				trains.append(v)
		for v: Dictionary in trains:
			var cps: Array = v["car_pos"]
			var pts := [v["pos"]] + cps
			for ci in range(1, pts.size()):
				var g := (pts[ci] as Vector3).distance_to(pts[ci - 1])
				if g < own:
					own = g
					var pts2: PackedVector3Array = v["pts"]
					var ii: int = v["i"]
					var segd := Vector3.ZERO
					if ii < pts2.size() - 1:
						segd = (pts2[ii + 1] - pts2[ii]).normalized()
					print(i, " eigener Abstand ", snappedf(g, 0.01), " idx=", ci, " pos=", (v["pos"] as Vector3).round(), " hd=", (v["heading"] as Vector3).snapped(Vector3.ONE * 0.01), " seg=", segd.snapped(Vector3.ONE * 0.01), " v=", snappedf(v["v"], 0.1), " await=", v.has("await_door"), " sort=", v.has("sort"))
		for a in range(trains.size()):
			for b in range(a + 1, trains.size()):
				for p in [trains[a]["pos"]] + trains[a]["car_pos"]:
					for q in [trains[b]["pos"]] + trains[b]["car_pos"]:
						var g2 := (p as Vector3).distance_to(q)
						if g2 < other:
							other = g2
							print(i, " fremd ", snappedf(g2, 0.01), " A=", (trains[a]["pos"] as Vector3).round(), " mov=", trains[a]["moving"], " await=", trains[a].has("await_door"), " ret=", main.ops.returning.has(trains[a]), " B=", (trains[b]["pos"] as Vector3).round(), " mov=", trains[b]["moving"], " await=", trains[b].has("await_door"), " ret=", main.ops.returning.has(trains[b]))
	print("ZUG eigener ", own, " fremder ", other)
	get_tree().quit()
