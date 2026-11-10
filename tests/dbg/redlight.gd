extends Node
func run(main: Node) -> void:
	await get_tree().process_frame
	var game = main.game
	var rd = main.roads
	var tr = main.traffic
	var jn: int = rd.nearest_junction(Vector3(115, 0, 35))
	if rd.control_of(jn) != "ampel":
		rd.cycle_control(Vector3(115, 0, 35))
	game.traffic_demand = 6
	tr.set_process(false)
	var hist := {}
	for i in range(2500):
		tr.step(0.1)
		for mv: Dictionary in tr.movers:
			var legs: Array = mv["legs"]
			var key: int = (mv["node"] as Node).get_instance_id()
			var sig := ""
			if legs.size() > 1 and legs[0]["type"] == "lane" and legs[1]["type"] == "conn":
				var ni: int = legs[1]["node"]
				if rd.control_of(ni) == "ampel":
					sig = rd.signal_at(ni, int(legs[1]["from_e"]))
				var rest := float(legs[0]["len"]) - float(mv["s"]) - float(mv["len"]) * 0.5
				var h: Array = hist.get(key, [])
				h.append("%d %s v=%.1f rest=%.1f commit=%s gap=%.1f purp=%s" % [i, sig, mv["v"], rest, str(mv.get("commit", -1)), tr._gap_ahead(mv), mv["purpose"]])
				if h.size() > 40:
					h.pop_front()
				hist[key] = h
				if float(mv["v"]) < 0.05 and sig == "rot" and tr._gap_ahead(mv) > 8.0 and rest < 0.85:
					print("PROBLEM bei ", i)
					for line in h.slice(maxi(0, h.size() - 30)):
						print("  ", line)
					get_tree().quit()
					return
			else:
				hist.erase(key)
	print("kein Problem")
	get_tree().quit()
