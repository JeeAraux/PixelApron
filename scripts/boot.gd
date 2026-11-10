extends Node
## Startszene. Liegt ein heruntergeladenes Update bereit, das neuer ist als die installierte Version,
## wird es geladen und überdeckt die Spieldateien. Danach startet das eigentliche Spiel.
## Diese Datei soll möglichst nie geändert werden und lädt nichts aus dem übrigen Spiel vor.

const UPDATE_DIR := "user://update"


func _ready() -> void:
	var pck := UPDATE_DIR + "/PixelApron.pck"
	if FileAccess.file_exists(pck) and not OS.has_feature("editor"):
		var installed := read_version("res://version.txt")
		var update := read_version(UPDATE_DIR + "/version.txt")
		if is_newer(update[0], installed[0]) and update[1] == installed[1]:
			if ProjectSettings.load_resource_pack(pck, true):
				print("Update geladen: ", update[0])
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")


## [Spielversion, Godot-Version] aus einer version.txt
static func read_version(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return ["0.0.0", ""]
	var lines := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	var game := lines[0].strip_edges() if lines.size() > 0 else "0.0.0"
	var engine := lines[1].strip_edges() if lines.size() > 1 else ""
	return [game, engine]


## Vergleicht Versionen wie 0.4.10 und 0.4.9 Zahl für Zahl.
static func is_newer(a: String, b: String) -> bool:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in range(maxi(pa.size(), pb.size())):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false
