extends Node
## Probe 0.30 Paket A: Gepäckzüge nicht unter der Tragfläche, Schlepper in Bereitschaft, Warten vor dem Umschlag.
func run(main: Node) -> void:
	await get_tree().process_frame
	var ops = main.ops
	var fl = main.flights
	var M = load("res://scripts/models.gd")
	seed(20261110)
	var under := 0
	var under_ex := ""
	var pool_max := 0
	var reused := 0
	var queued := 0
	var lane_bags := 0
	var seenq := {}
	var last_pool := 0
	for i in range(int(OS.get_environment("STEPS")) if OS.get_environment("STEPS") != "" else 16000):
		fl.step(0.1)
		pool_max = maxi(pool_max, ops.tug_pool.size())
		if ops.tug_pool.size() < last_pool:
			reused += 1
		last_pool = ops.tug_pool.size()
		for v: Dictionary in ops.sorting:
			var st: Dictionary = v.get("sort", {})
			if bool(st.get("queue", false)) and not seenq.has(v.get("node")):
				seenq[v.get("node")] = true
				queued += 1
		if i % 5 != 0:
			continue
		for pl: Dictionary in fl.planes:
			if String(pl.get("state", "")) != "abfertigung" and String(pl.get("state", "")) != "stand":
				pass
			var s: Dictionary = M.SPECS.get(String(pl["kind"]), M.SPECS["a320"])
			var h: Vector3 = pl["heading"]
			var right := h.cross(Vector3.UP).normalized()
			for v: Dictionary in ops.vehicles:
				if v.get("kind") != "zug":
					continue
				var pts: Array = [v["pos"]]
				pts.append_array(v.get("car_pos", []))
				for q: Vector3 in pts:
					var d: Vector3 = q - (pl["pos"] as Vector3)
					var lx := absf(d.dot(right))
					var lz := -d.dot(h)   # +z Richtung Heck
					if lx < float(s["r"]) + 1.0 or lx > float(s["tip_x"]):
						continue
					var w: Array = M._wing_at(s, lx)
					if lz > float(w[0]) - 0.5 and lz < float(w[0]) + float(w[2]) + 0.5 and float(w[1]) < 4.5:
						under += 1
						if under_ex == "":
							under_ex = "%s x %.1f z %.1f wing_y %.1f" % [pl["kind"], lx, lz, float(w[1])]
	print("unter Fluegel ", under, " ", under_ex, " | Schlepper-Bereitschaft max ", pool_max, " genutzt/abgezogen ", reused, " | wartend ", queued)
	get_tree().quit()
