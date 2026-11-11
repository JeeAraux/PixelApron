extends Node
## Probe alter Spielstand (Version 10): aufgemalte Einrolllinien werden beim Laden zu Rolllinien.
func run(main: Node) -> void:
	await get_tree().process_frame
	var g = main.game
	for st: Dictionary in g.stands():
		for l: Dictionary in g.stand_lines(st):
			g.remove(l, 0.0)
		(st["opts"] as Dictionary).erase("markierung")
	g.save_game(true)
	var txt := FileAccess.get_file_as_string(g.SAVE_PATH)
	var data: Dictionary = JSON.parse_string(txt)
	data["version"] = 10
	var f := FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	print("geladen ", g.load_game())
	for st: Dictionary in g.stands():
		print(st["id"], " markierung ", (st["opts"] as Dictionary).get("markierung", "-"), " linien ", g.stand_lines(st).size())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.SAVE_PATH))
	get_tree().quit()
