extends Node
## Sucht beim Start im Hintergrund nach einer neuen Version auf GitHub (Releases von JeeAraux/PixelApron).
## Gibt es eine, lädt es die Spieldaten (PixelApron.pck, wenige MB) nach user://update.
## Beim nächsten Start lädt boot.gd sie. Braucht die neue Version eine neue Godot-Version,
## muss das Spiel einmal komplett neu heruntergeladen werden.

signal status_changed(text: String, ready: bool)

const Boot = preload("res://scripts/boot.gd")
const RELEASES := "https://github.com/JeeAraux/PixelApron/releases"
const UPDATE_DIR := "user://update"

var installed: Array = ["0.0.0", ""]
var latest := ""
var status := ""
var ready_to_restart := false
var full_download_needed := false
var http: HTTPRequest


## Für Tests lässt sich die Adresse über PIXELAPRON_RELEASES umstellen.
func releases() -> String:
	var env := OS.get_environment("PIXELAPRON_RELEASES")
	return env if env != "" else RELEASES


func version() -> String:
	return String(installed[0])


func _ready() -> void:
	installed = Boot.read_version("res://version.txt")
	http = HTTPRequest.new()
	http.timeout = 30.0
	add_child(http)


## Nur im exportierten Spiel automatisch prüfen (nicht im Editor, nicht im Test).
func check_on_start() -> void:
	if OS.has_feature("editor") and OS.get_environment("PIXELAPRON_RELEASES") == "":
		_status("Version %s (Editor)" % version())
		return
	check()


func check() -> void:
	if http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_status("Suche nach Updates …")
	http.request_completed.connect(_on_version, CONNECT_ONE_SHOT)
	if http.request(releases() + "/latest/download/version.txt") != OK:
		_status("Update-Prüfung nicht möglich")


func _on_version(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_status("Version %s · Keine Verbindung zum Update-Server" % version())
		return
	var lines := body.get_string_from_utf8().strip_edges().split("\n")
	latest = lines[0].strip_edges()
	var engine := lines[1].strip_edges() if lines.size() > 1 else ""
	if not Boot.is_newer(latest, version()):
		_status("Version %s · aktuell" % version())
		return
	var pending := Boot.read_version(UPDATE_DIR + "/version.txt")
	if pending[0] == latest and FileAccess.file_exists(UPDATE_DIR + "/PixelApron.pck"):
		ready_to_restart = true
		_status("Update %s ist geladen · Neustart zum Aktivieren" % latest)
		return
	if engine != String(installed[1]):
		full_download_needed = true
		_status("Version %s verfügbar · bitte einmal komplett neu herunterladen" % latest)
		return
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	http.download_file = UPDATE_DIR + "/PixelApron.pck.part"
	http.request_completed.connect(_on_pck.bind(lines), CONNECT_ONE_SHOT)
	_status("Lade Update %s …" % latest)
	if http.request(releases() + "/download/v%s/PixelApron.pck" % latest) != OK:
		_status("Update-Download fehlgeschlagen")


func _on_pck(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, lines: PackedStringArray) -> void:
	http.download_file = ""
	var part := UPDATE_DIR + "/PixelApron.pck.part"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		DirAccess.remove_absolute(part)
		_status("Update-Download fehlgeschlagen (%d)" % code)
		return
	var dir := DirAccess.open(UPDATE_DIR)
	if dir.file_exists("PixelApron.pck"):
		dir.remove("PixelApron.pck")
	dir.rename("PixelApron.pck.part", "PixelApron.pck")
	var f := FileAccess.open(UPDATE_DIR + "/version.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	ready_to_restart = true
	_status("Update %s ist geladen · Neustart zum Aktivieren" % latest)


func restart() -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()


func open_downloads() -> void:
	OS.shell_open(RELEASES + "/latest")


func _status(text: String) -> void:
	print("Update: ", text)
	status = text
	status_changed.emit(text, ready_to_restart)
