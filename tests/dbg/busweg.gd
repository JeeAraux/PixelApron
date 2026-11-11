extends Node
## Probe: fahren Busse und Bodenfahrzeuge durch stehende Flugzeuge? Zählt Fahrzeugpositionen im Umriss
## fremder Flugzeuge (Rumpf ± Spannweite) und eigener (Rumpf ± 3 m, ohne die Arbeitsplätze). --schritte=
func run(main: Node) -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var steps := 12000
	for a: String in args:
		if a.begins_with("--schritte="):
			steps = int(a.substr(11))
	var fl = main.flights
	var ops = main.ops
	var Cat = load("res://scripts/catalog.gd")
	var Mod = load("res://scripts/models.gd")
	seed(20261110)
	var hits := {}
	var samples := 0
	for i in range(steps):
		fl.step(0.1)
		if i % 10 != 0:
			continue
		for p: Dictionary in fl.planes:
			if not (p["state"] in ["abfertigung", "rollt_ein", "pushback", "wartet", "rollt_aus"]):
				continue
			var pl: Dictionary = Cat.PLANES.get(p["kind"], Cat.PLANES["a320"])
			var half := float(pl["span"]) * 0.5
			var nose := float(pl["nose"])
			var length := float((Mod.SPECS.get(p["kind"], Mod.SPECS["a320"]) as Dictionary)["len"])
			for v: Dictionary in ops.vehicles:
				if not (v["kind"] in ["bus", "zug", "tank", "catering", "bandlader", "gpu", "treppe"]):
					continue
				var vp: Vector3 = v["pos"]
				var h: Vector3 = p["heading"]
				h.y = 0.0
				var b := Basis.looking_at(h.normalized(), Vector3.UP)
				var loc := b.inverse() * (vp - (p["pos"] as Vector3))
				# Rumpf: |x| < 2,5 von der Nase bis zum Heck (das kann kein Fahrzeug)
				if absf(loc.x) < 2.6 and loc.z > -nose and loc.z < length - nose:
					var key := "%s im Rumpf (%s, %s)" % [v["kind"], p["state"], p["kind"]]
					hits[key] = int(hits.get(key, 0)) + 1
				samples += 1
	print("Proben ", samples)
	for k: String in hits:
		print("  ", k, ": ", hits[k])
	get_tree().quit()
