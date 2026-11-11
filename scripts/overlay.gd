extends Node3D
## Karten-Overlays: Gedränge und Wartezeit in den Hallen (aus terminal.heat), Fluglärm um die Pisten
## (flights.noise_at). Farbverlauf durchsichtig → gelb → rot, einmal je Sekunde neu.

const MODES := ["aus", "gedraenge", "warten", "laerm", "koffer"]
const NAMES := {"aus": "Overlay aus", "gedraenge": "Gedränge", "warten": "Wartezeit", "laerm": "Fluglärm", "koffer": "Kofferwege"}
const Kit = preload("res://scripts/mesh_kit.gd")

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
	if bag_mesh != null:
		bag_mesh.visible = false
	if mode == "aus" or game == null:
		return
	if mode == "koffer":
		_bags()
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


var bag_mesh: MeshInstance3D


## Kofferwege: Pfeile in Laufrichtung über den Bändern. Orange vom Check-in zur Sortierung, blau von der
## Sortierung zum Gepäckband, violett vom Rolltor (Gepäckzüge) zur Sortierung. Rotes Kreuz: nicht angeschlossen.
func _bags() -> void:
	var routes: Dictionary = game.bag_routes()
	var k := Kit.new()
	var cols := {"checkin": Color(1.0, 0.55, 0.1), "gepaeckband": Color(0.2, 0.55, 1.0), "rolltor": Color(0.7, 0.35, 1.0)}
	var fh := 5.0
	var t := Time.get_ticks_msec() * 0.001
	for it: Dictionary in game.items:
		var id := String(it["id"])
		if not cols.has(id):
			continue
		var node: Variant = it["node"]
		if not is_instance_valid(node):
			continue
		var f := int(it.get("floor", 0))
		if game.interior_view and f != game.view_floor:
			continue
		var key := (node as Node).get_instance_id()
		var col: Color = cols[id]
		if not routes.has(key) or (routes[key] as PackedVector3Array).size() < 2:
			var c: Vector3 = (it["pos"] as Vector3) + Vector3(0, float(f) * fh + 2.6, 0)
			for sg: float in [-1.0, 1.0]:
				k.box(Vector3(-1.2, -0.12, -0.12), Vector3(1.2, 0.12, 0.12), Color(0.95, 0.1, 0.1),
					Transform3D(Basis(Vector3.UP, PI * 0.25 * sg), c))
			continue
		var r: PackedVector3Array = routes[key]
		var run := 0.0
		var next := fmod(t * 1.5, 3.0)
		for i in range(r.size() - 1):
			var a := r[i]
			var b := r[i + 1]
			var seg := a.distance_to(b)
			if seg < 0.01:
				continue
			var d := (b - a) / seg
			while next <= run + seg:
				var p := a + d * (next - run) + Vector3(0, 0.55, 0)
				var flat := Vector3(d.x, 0, d.z)
				if flat.length() > 0.05:
					flat = flat.normalized()
					var side := flat.cross(Vector3.UP) * 0.7
					k.tri(p + flat * 0.9, p - flat * 0.5 + side, p - flat * 0.5 - side, col, p + Vector3(0, -5, 0))
				next += 3.0
			run += seg
	if bag_mesh == null:
		bag_mesh = MeshInstance3D.new()
		bag_mesh.name = "Kofferwege"
		bag_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bag_mesh)
	bag_mesh.mesh = k.commit() if k.count > 0 else null
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	bag_mesh.material_override = m
	bag_mesh.visible = true

