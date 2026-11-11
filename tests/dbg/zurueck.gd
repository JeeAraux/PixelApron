extends Node
## Probe: Zurück für Verschieben (Gebäude, Weg) und Flächenabriss.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	var tw: Dictionary = g.items_of("tower")[0]
	var p0: Vector3 = tw["pos"]
	print("verschieben: '", g.move_item(tw, p0 + Vector3(20, 0, 0), 0), "' pos ", tw["pos"])
	g.undo_last()
	print("zurück: pos ", tw["pos"], " gleich ", (tw["pos"] as Vector3).is_equal_approx(p0))
	# Weg verschieben: Gehweg vor dem Terminal
	var gw: Dictionary = {}
	for l: Dictionary in g.lines:
		if l["kind"] == "gehweg":
			gw = l
	var a0: Vector3 = gw["points"][0]
	print("weg: '", g.move_line(gw, Vector3(0, 0, 3)), "'")
	var moved := false
	for l: Dictionary in g.lines:
		if l["kind"] == "gehweg" and (l["points"][0] as Vector3).is_equal_approx(a0 + Vector3(0, 0, 3)):
			moved = true
	print("weg verschoben ", moved)
	g.undo_last()
	var back := false
	for l: Dictionary in g.lines:
		if l["kind"] == "gehweg" and (l["points"][0] as Vector3).is_equal_approx(a0):
			back = true
	print("weg zurück ", back)
	# Flächenabriss über Tower, Trafo und Heizzentrale: zurück baut alles wieder auf
	var n_items: int = g.items.size()
	var n_lines: int = g.lines.size()
	var m0: int = g.money
	var n: int = g.demolish_area(Rect2(200, 0, 80, 40))
	print("abgerissen ", n, " items ", g.items.size(), "/", n_items, " lines ", g.lines.size(), "/", n_lines, " geld ", g.money - m0)
	g.undo_last()
	print("nach zurück items ", g.items.size(), "/", n_items, " lines ", g.lines.size(), "/", n_lines, " geld ", g.money - m0)
	get_tree().quit()
