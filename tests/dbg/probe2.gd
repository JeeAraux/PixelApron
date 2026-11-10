extends Node
func run(main: Node) -> void:
	await get_tree().process_frame
	var game = main.game
	var counts := {}
	for it in game.items:
		counts[it["id"]] = int(counts.get(it["id"], 0)) + 1
	print(counts)
	var lc := {}
	for l in game.lines:
		lc[l["kind"]] = int(lc.get(l["kind"], 0)) + 1
	print(lc)
	get_tree().quit()
