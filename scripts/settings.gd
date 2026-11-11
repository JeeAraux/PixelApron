extends RefCounted
## Einstellungen des Spielers, gespeichert in user://einstellungen.cfg.

const PATH := "user://einstellungen.cfg"

## Schlüssel, Standardwert, Anzeigename, Art (bool, choice, slider), Optionen
const DEFS := [
	["sandkasten", true, "Sandkasten: unbegrenztes Geld (nicht in Szenarien)", "bool", []],
	["ereignisse", true, "Ereignisse: Notfälle, Störungen, Streik, Gewitter, Vogelschlag", "bool", []],
	["vollbild", false, "Vollbild", "bool", []],
	["schatten", 3, "Schatten", "choice", ["Aus", "Normal", "Hoch", "Sehr hoch"]],
	["kantenglaettung", 2, "Kantenglättung", "choice", ["Aus", "2×", "4×", "8×"]],
	["tag_nacht", true, "Tag und Nacht", "bool", []],
	["umgebungslicht", true, "Umgebungsverdeckung (weiche Schatten in Ecken)", "bool", []],
	["kamera_tempo", 1.0, "Kamera-Tempo", "slider", [0.4, 2.5]],
	["zoom_umkehren", false, "Mausrad-Zoom umkehren", "bool", []],
	["kantenscrollen", false, "Am Bildrand scrollen", "bool", []],
	["raster_immer", false, "Bauraster immer zeigen", "bool", []],
	["autospeichern", true, "Um Mitternacht automatisch speichern", "bool", []],
	["hilfe", true, "Tastenhilfe im Infofeld", "bool", []],
]

var values: Dictionary = {}


func _init() -> void:
	for d: Array in DEFS:
		values[d[0]] = d[1]


func get_value(key: String) -> Variant:
	return values.get(key)


func set_value(key: String, v: Variant) -> void:
	values[key] = v
	save()


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for d: Array in DEFS:
		values[d[0]] = cf.get_value("spiel", String(d[0]), d[1])


func save() -> void:
	var cf := ConfigFile.new()
	for key: String in values:
		cf.set_value("spiel", key, values[key])
	cf.save(PATH)
