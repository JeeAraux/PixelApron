extends Node
## Probe 0.22: Betriebsfenster, Reiter Gebühren und Lärm (Bild).
func run(main: Node) -> void:
	await get_tree().process_frame
	for i in range(1500):
		main.flights.step(0.1)
	main.hud.ops_tab = "gebuehren"
	main.hud.show_ops(true)
	main.hud.set_build_open(false)
	for i in range(30):
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	get_viewport().get_texture().get_image().save_png(args[args.size() - 1])
	get_tree().quit()
