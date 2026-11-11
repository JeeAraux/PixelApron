extends Node
## Probe 0.19: Startterminal nach dem Umbau (Durchleuchtung im Kofferweg, Einfahrt hinter dem Rolltor).
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var tb = main.terminal
	tb.dirty = true
	tb._analyze()
	var h: Dictionary = g.items_of("halle")[0]
	var ds := []
	for did: int in g.checkins_linked(h):
		ds.append([g.desk_screened(did), g.desk_factor(did)])
	print("checkins ", g.checkins_linked(h).size(), " claims ", g.claims_linked(h).size(), " desks ", ds)
	print("staff ", tb.staff_available(), "/", tb.staff_needed(), " chutes ", main.ops.chutes_total())
	var rt: Dictionary = g.items_of("rolltor")[0]
	print("bay ", g.gate_bay(rt), " free ", g.gate_bay_free(rt), " route ", g.bag_routes().has((rt["node"] as Node).get_instance_id()))
	print("problems ", tb.halls[0]["problems"], " missing ", tb.halls[0]["missing"])
	print(tb.hall_summary(h))
	for l: Dictionary in g.lines:
		if l["kind"] == "kofferband":
			var sm: PackedVector3Array = l["samples"]
			print("  ", l["points"], " desks ", l.get("desks"), " ", sm[0].y, "..", sm[sm.size() - 1].y, " weiche ", (l["node"] as Node).get_children().filter(func(c: Node) -> bool: return String(c.name).begins_with("Weiche")).size())
	get_tree().quit()
