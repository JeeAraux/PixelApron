extends Node
## Probe: Zurückschleppen bei einer Blockade (Mechanik): Flugzeug mitten auf dem Rollweg zurückschleppen,
## danach muss es normal weiterrollen und ankommen.
func run(main: Node) -> void:
	await get_tree().process_frame
	main.set_process(false)
	seed(7)
	print("los")
	var fl = main.flights
	var p: Dictionary = {}
	for i in range(20000):
		fl.step(0.1)
		if p.is_empty():
			for q: Dictionary in fl.planes:
				if q["state"] in ["rollt_ein", "rollt_aus"] and q.has("route") and float(q["rs"]) > 260.0:
					var rs0 := float(q["rs"])
					var ok: bool = fl._start_tow(q, {})
					if not ok:
						continue
					p = q
					print(i, " Start ", q["code"], " rs ", snappedf(rs0, 0.1), " ok ", ok, " nach ", q.get("tow", {}))
					break
			continue
		if i % 50 == 0:
			print(i, " ", p["state"], " rs ", snappedf(float(p["rs"]), 0.1), " tow ", p.has("tow"), " pos ", Vector2(p["pos"].x, p["pos"].z).round())
		if p["state"] in ["abfertigung", "start"] or not (p in fl.planes):
			print("ANGEKOMMEN bei ", i)
			break
	print("ende ", fl.planes.size(), " ", fl.reason)
	get_tree().quit()
