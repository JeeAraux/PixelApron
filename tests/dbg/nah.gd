extends Node
## Sucht Begegnungen rollender Flugzeuge unter 21 m und zeigt Reservierungen und Vorfahrt.
func run(main: Node) -> void:
	await get_tree().process_frame
	main.set_process(false)
	var fl = main.flights
	var log := {}
	var shown := 0
	for i in range(20000):
		fl.step(0.1)
		var ps: Array = fl.planes
		for a in range(ps.size()):
			var pa: Dictionary = ps[a]
			var key: String = pa["code"]
			if log.get(key, "") != pa["state"]:
				log[key] = pa["state"]
				print(i, " ", key, " -> ", pa["state"], " ", str(Vector2(pa["pos"].x, pa["pos"].z).round()))
			for c in range(a + 1, ps.size()):
				var pc: Dictionary = ps[c]
				var ground := ["rollt_ein", "rollt_aus", "wartet", "pushback"]
				if pa["state"] in ground and pc["state"] in ground and float(pa["ghost"]) <= 0.0 and float(pc["ghost"]) <= 0.0:
					var gap := (pa["pos"] as Vector3).distance_to(pc["pos"])
					if gap < 21.0 and shown < 3:
						shown += 1
						print("NAH ", i, " gap=", snappedf(gap, 0.1))
						for q: Dictionary in [pa, pc]:
							var nodes: Array = q.get("path", [])
							var k: int = q.get("pk", 0)
							var ahead := []
							for j in range(k, mini(k + 8, nodes.size())):
								ahead.append([nodes[j], fl.reserved.get(nodes[j], -1)])
							print("  ", q["code"], " id=", q["id"], " ", q["state"], " pos=", str(Vector2(q["pos"].x, q["pos"].z).round()), " v=", snappedf(q["speed"], 0.1),
								" head=", str(Vector2(q["heading"].x, q["heading"].z).snapped(Vector2(0.01, 0.01))), " wait=", snappedf(q["wait"], 0.1),
								" occ=", q.get("occ", -1), " blocked_by=", q.get("blocked_by", -1), " ahead=", ahead)
	get_tree().quit()
