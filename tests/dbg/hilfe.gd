extends Node
## Probe: Tastenübersicht (F1) und Kostenanzeige am Mauszeiger. Letztes Argument BILD.png
func run(main: Node) -> void:
	await get_tree().process_frame
	main.hud.toggle_help()
	for k in range(20):
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
