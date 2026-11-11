extends Node
## Probe alter Spielstand (Version 10): aufgemalte Einrolllinien werden beim Laden zu Rolllinien.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	for st: Dictionary in g.stands():
		for l: Dictionary in g.stand_lines(st):
			g.remove(l, 0.0)
		(st["opts"] as Dictionary).erase("markierung")
	g.build_line("rolllinie", [Vector3(-150, 0, -93), Vector3(210, 0, -93)], true)
	g.save_game(true)
	var txt := FileAccess.get_file_as_string(g.SAVE_PATH)
	var data: Dictionary = JSON.parse_string(txt)
	data["version"] = 10
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	print("geladen ", g.load_game())
	var alt := 0
	for l: Dictionary in g.lines:
		if l["kind"] == "rolllinie" and absf((l["points"][0] as Vector3).z + 93.0) < 0.1 and (l["points"] as Array).size() == 2:
			alt += 1
	print("alte Rollgasse noch da: ", alt)
	for st: Dictionary in g.stands():
		print(st["id"], " markierung ", (st["opts"] as Dictionary).get("markierung", "-"), " linien ", g.stand_lines(st).size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.SAVE_PATH))
	get_tree().quit()
