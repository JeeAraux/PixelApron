extends Node
func run(main: Node) -> void:
	await get_tree().process_frame
	main.set_process(false)
	var fl = main.flights
	var log := {}
	for i in range(9000):
		fl.step(0.1)
		var ps: Array = fl.planes
		for a in range(ps.size()):
			var pa: Dictionary = ps[a]
			var key: String = pa["code"]
			var line := "%s %s %s" % [pa["state"], str(pa.get("push_phase", "")), str(Vector2(pa["pos"].x, pa["pos"].z).round())]
			if log.get(key, "") != pa["state"] + str(pa.get("push_phase", "")):
				log[key] = pa["state"] + str(pa.get("push_phase", ""))
				var st: Dictionary = pa["stand"]
				print(i, " ", key, " -> ", line, " stand=", st.get("pos", "-"))
			for c in range(a + 1, ps.size()):
				var pc: Dictionary = ps[c]
				var ground := ["rollt_ein", "rollt_aus", "wartet", "pushback"]
				if pa["state"] in ground and pc["state"] in ground:
					var gap := (pa["pos"] as Vector3).distance_to(pc["pos"])
					if gap < 25.0:
						print(i, " NAH ", pa["code"], " ", pa["state"], " ", str(Vector2(pa["pos"].x, pa["pos"].z).round()), " v=", snappedf(pa["speed"], 0.1), " / ", pc["code"], " ", pc["state"], " ", str(Vector2(pc["pos"].x, pc["pos"].z).round()), " v=", snappedf(pc["speed"], 0.1), " gap=", snappedf(gap, 0.1))
	get_tree().quit()
