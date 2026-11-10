extends Node
## Begegnungen am Boden mit Kurs und Tempo; Zufallszahl über --seed=N.
func run(main: Node) -> void:
	await get_tree().process_frame
	main.set_process(false)
	var sd := 1
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			sd = int(a.substr(7))
	seed(sd)
	var fl = main.flights
	var min_gap := INF
	var last := -100
	var gh := {}
	for i in range(12000):
		fl.step(0.1)
		var ps: Array = fl.planes
		for q: Dictionary in ps:
			var stk: String = q["state"]
			if String(gh.get("s%d" % int(q["id"]), "")) != stk:
				gh["s%d" % int(q["id"])] = stk
				var hh: Vector3 = q["heading"]
				print(i, " ", q["code"], " -> ", stk, " pos=", str(Vector2(q["pos"].x, q["pos"].z).round()), " hd=", str(Vector2(hh.x, hh.z).snapped(Vector2(0.01, 0.01))), " stand=", (q["stand"] as Dictionary).get("pos", "-"), " wind=", snappedf(main.game.wind_dir, 1))
			var g := float(q["ghost"]) > 0.0
			if g != bool(gh.get(q["id"], false)):
				gh[q["id"]] = g
				var o: Dictionary = fl._plane_by_id(int(q.get("blocked_by", -1)))
				var h: Vector3 = q["heading"]
				print(i, (" GEIST AN " if g else " GEIST AUS "), q["code"], " ", q["state"], " pos=", str(Vector2(q["pos"].x, q["pos"].z).round()), " hd=", str(Vector2(h.x, h.z).snapped(Vector2(0.01, 0.01))),
					" blockiert von ", "-" if o.is_empty() else "%s %s %s v=%.1f" % [o["code"], o["state"], str(Vector2(o["pos"].x, o["pos"].z).round()), float(o["speed"])])
		for a in range(ps.size()):
			var pa: Dictionary = ps[a]
			for c in range(a + 1, ps.size()):
				var pc: Dictionary = ps[c]
				var ground := ["rollt_ein", "rollt_aus", "wartet"]
				if pa["state"] in ground and pc["state"] in ground and float(pa["ghost"]) <= 0.0 and float(pc["ghost"]) <= 0.0:
					var gap := (pa["pos"] as Vector3).distance_to(pc["pos"])
					min_gap = minf(min_gap, gap)
					if gap < 40.0 and i - last > 20:
						last = i
						print(i, " gap=", snappedf(gap, 0.1))
						for q: Dictionary in [pa, pc]:
							var h: Vector3 = q["heading"]
							print("   ", q["code"], " ", q["state"], " pos=", str(Vector2(q["pos"].x, q["pos"].z).round()), " hd=", str(Vector2(h.x, h.z).snapped(Vector2(0.01, 0.01))), " v=", snappedf(q["speed"], 0.1), " w=", snappedf(q["wait"], 1), " by=", q.get("blocked_by", -1), " id=", q["id"], " stand=", (q["stand"] as Dictionary).get("pos", "-"), " rer=", q.get("rerouted", false))
	print("SEED ", sd, " kleinster Abstand ", min_gap, " abgeflogen ", fl.done)
	get_tree().quit()
