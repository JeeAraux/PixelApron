extends Node
## Probe 0.23: Geräusche erzeugen (Dauer und Größe), Detailstufe.
func run(main: Node) -> void:
	await get_tree().process_frame
	var S = load("res://scripts/sound.gd")
	var s = S.new()
	var t0 := Time.get_ticks_msec()
	for k: String in ["gong", "jet", "crowd", "rain", "thunder", "horn", "beep"]:
		var w: AudioStreamWAV = s._gen(k)
		print(k, " ", w.data.size(), " bytes, loop ", w.loop_mode)
	print("dauer ms ", Time.get_ticks_msec() - t0)
	main.cam_rig.zoom = 400.0
	main.cam_rig.zoom_goal = 400.0
	for i in range(5):
		await get_tree().process_frame
	print("lod ", main.lod_far, " crowd ", main.terminal.crowd.visible)
	s.free()
	get_tree().quit()
