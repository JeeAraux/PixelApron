extends Node
## Prüft den neuen Startflughafen: Versorgung, Terminal, Bereiche, Personal, Garagen, Fahrwege.
func run(main: Node) -> void:
	await get_tree().process_frame
	var game = main.game
	print("Betrieb: '", main.flights.check_operation(), "'")
	print("Terminal: '", main.terminal.check(), "'")
	for info in main.terminal.halls:
		print("Halle complete=", info["complete"], " missing=", info["missing"], " problems=", info["problems"], " warm=", info["warm"])
	print("Personal ", main.terminal.staff_available(), " / ", main.terminal.staff_needed())
	for it in game.items:
		var sup: Dictionary = it.get("supply", {})
		for u in sup:
			if sup[u] != "ok" and not it.has("hall"):
				print("Versorgung ", it["id"], " ", u, " ", sup[u])
	main.ops._rebuild_net()
	print("Netz Knoten ", main.ops.net.pos.size(), " Feuer ", main.ops.fire_net.pos.size(), " ohne Anschluss ", main.ops.unconnected.size())
	for k in ["gpu", "tank", "catering", "bus"]:
		var g = main.ops._garage(k, Vector3(0, 0, -40))
		if g.is_empty():
			print(k, ": keine Garage")
		else:
			var r = main.ops.net.route(g[2], Vector3(-17, 0, -38))
			print(k, ": ", g[0]["id"], " Weg ", r.size(), " Punkte")
	for f in main.flights.factors if "factors" in main.flights else []:
		print(f)
	# 120 s simulieren
	for i in range(2400):
		main.flights.step(0.05)
		main.ops.step(0.05)
		main.terminal.step(0.05)
	print("Flugzeuge ", main.flights.planes.size(), " Fahrzeuge ", main.ops.vehicles.size(), " heim ", main.ops.returning.size(), " Leute ", main.terminal.people.size())
	for p in main.flights.planes:
		print("  ", p["code"], " ", p["state"])
	print("Tore offen: ", main.ops.door_open)
	print("Gründe: ", game.satisfaction_factors)
	get_tree().quit()
