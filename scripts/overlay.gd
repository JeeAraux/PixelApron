extends Node3D
## Karten-Overlays: Gedränge und Wartezeit in den Hallen (aus terminal.heat), Fluglärm um die Pisten
## (flights.noise_at). Farbverlauf durchsichtig → gelb → rot, einmal je Sekunde neu.

const MODES := ["aus", "gedraenge", "warten", "laerm"]
const NAMES := {"aus": "Overlay aus", "gedraenge": "Gedränge", "warten": "Wartezeit", "laerm": "Fluglärm"}

var game: Variant = null
var terminal: Variant = null
var flights: Variant = null
var mode := "aus"
var refresh_t := 0.0
var quads: Dictionary = {}   # Schlüssel -> MeshInstance3D


func cycle() -> String:
	mode = MODES[(MODES.find(mode) + 1) % MODES.size()]
	refresh_t = 0.0
	_refresh()
	return mode


func set_mode(m: String) -> void:
	mode = m if m in MODES else "aus"
	_refresh()


func _process(delta: float) -> void:
	if mode == "aus":
		return
	refresh_t -= delta
	if refresh_t <= 0.0:
		refresh_t = 1.0
		_refresh()


static func ramp(v: float) -> Color:
	v = clampf(v, 0.0, 1.0)
	if v < 0.02:
		return Color(0, 0, 0, 0)
	var c := Color(0.3, 0.85, 0.35).lerp(Color(1.0, 0.85, 0.15), clampf(v * 2.0, 0.0, 1.0))
	if v > 0.5:
		c = Color(1.0, 0.85, 0.15).lerp(Color(0.95, 0.15, 0.1), (v - 0.5) * 2.0)
	c.a = 0.25 + 0.45 * v
	return c


func _quad(key: String, rect: Rect2, y: float, img: Image) -> void:
	var mi: MeshInstance3D = quads.get(key)
	if mi == null:
		mi = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		m.no_depth_test = false
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		quads[key] = mi
	(mi.mesh as PlaneMesh).size = rect.size
	mi.position = Vector3(rect.get_center().x, y, rect.get_center().y)
	(mi.material_override as StandardMaterial3D).albedo_texture = ImageTexture.create_from_image(img)
	mi.visible = true


func _refresh() -> void:
	for k: String in quads:
		(quads[k] as Node3D).visible = false
	if mode == "aus" or game == null:
		return
	if mode == "laerm":
		_noise()
		return
	if terminal == null:
		return
	var key := "crowd" if mode == "gedraenge" else "wait"
	for hid: int in terminal.heat:
		var hm: Dictionary = terminal.heat[hid]
		var w := int(hm["w"])
		var h := int(hm["h"])
		var a: PackedFloat32Array = hm[key]
		var mx := 0.0
		for v: float in a:
			mx = maxf(mx, v)
		var scale := maxf(mx, 20.0 if key == "crowd" else 12.0)
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for z in range(h):
			for x in range(w):
				img.set_pixel(x, z, ramp(a[z * w + x] / scale))
		var y := float(maxi(game.view_floor, 0)) * 5.0 + 0.2
		_quad("h%d" % hid, hm["rect"], y, img)


func _noise() -> void:
	if flights == null:
		return
	var rws: Array = game.runway_list()
	if rws.is_empty():
		return
	var r := Rect2()
	var first := true
	for rw: Array in rws:
		for q: Vector3 in rw:
			var pr := Rect2(q.x, q.z, 0, 0).grow(2600.0)
			r = pr if first else r.merge(pr)
			first = false
	var w := 160
	var h := maxi(16, roundi(160.0 * r.size.y / r.size.x))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for z in range(h):
		for x in range(w):
			var p := Vector3(r.position.x + (float(x) + 0.5) / float(w) * r.size.x, 0, r.position.y + (float(z) + 0.5) / float(h) * r.size.y)
			img.set_pixel(x, z, ramp((float(flights.noise_at(p)) - 45.0) / 28.0))
	_quad("laerm", r, 0.6, img)
