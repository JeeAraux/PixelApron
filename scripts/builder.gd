extends Node
## Bauwerkzeug: Wege mit Kurven ziehen, Gebäude und Deko setzen, abreißen.
## Bekommt Bodenpunkte von main.gd und zeigt eine Vorschau in der 3D-Welt.

signal info(title: String, body: String, state: int)  # state: 0 neutral, 1 gut, 2 Problem
signal tool_changed(id: String)
signal inspect_requested(p: Vector3)
signal mode_changed(mode: String, shown: bool, upgrade: bool)
signal side_changed(side: String)
signal steps(text: String)   # kurzer Arbeitsschritt für die Wegebau-Leiste ("1 Startpunkt klicken")
signal hint(text: String)   # kurzer Text am Mauszeiger (Länge, Winkel, Radius)

const Catalog = preload("res://scripts/catalog.gd")
const Spline = preload("res://scripts/spline.gd")
const Factory = preload("res://scripts/factory.gd")
const GameState = preload("res://scripts/game_state.gd")
const Streetscape = preload("res://scripts/streetscape.gd")

const SNAP_DIST := 7.0
## An welche Wege ein neuer Weg einrastet
const SNAP_GROUPS := {"strasse": ["strasse", "strasse4", "einbahn"], "strasse4": ["strasse", "strasse4", "einbahn"],
	"einbahn": ["strasse", "strasse4", "einbahn"], "gehweg": ["gehweg", "strasse", "strasse4", "einbahn"],
	"rollweg": ["rollweg", "rollweg_breit", "vorfeld", "piste"], "rollweg_breit": ["rollweg", "rollweg_breit", "vorfeld", "piste"],
	"vorfeld": ["vorfeld", "rollweg", "rollweg_breit"], "piste": ["piste"], "betriebsstrasse": ["betriebsstrasse"],
	"rolllinie": ["rolllinie", "rollweg", "rollweg_breit"]}
const ANGLE_STEP := 15.0
## Zeichenarten für Straßen, Rollwege und Vorfeld (wie in Städtebauspielen)
const MODES := ["gerade", "kurve", "frei", "ersetzen"]
const MODE_NAMES := {"gerade": "Gerade", "kurve": "Kurve", "frei": "Freihand", "ersetzen": "Ersetzen"}
const MAGNET := 4.0   # Grad: so nah rastet ein Winkel auf die nächste 15-Grad-Stufe ein

var game: GameState
var roads: Node3D   # roads.gd, für das Kreuzungs-Werkzeug
var root3d: Node3D
var tool := ""
var points: Array = []
var hover := Vector3.ZERO
var raw_hover := Vector3.ZERO
var has_hover := false
var rot := 0
var reason := ""
var target: Dictionary = {}
var preview: MeshInstance3D
var ghost: Node3D
var marker_root: Node3D
var mat_ok: StandardMaterial3D
var mat_bad: StandardMaterial3D
var mat_mark: StandardMaterial3D
var mat_overlay: StandardMaterial3D
var mat_snap: StandardMaterial3D
var snap_kind := ""          # "ende" (Wegende), "weg" (auf einem Weg) oder leer
var snap_tan := Vector3.ZERO  # Richtung des Weges, an dem der Zeiger einrastet (bei "ende": in den Weg hinein)
var draw_mode := "gerade"
var start_tan := Vector3.ZERO # Richtung, in der der neue Weg am Startpunkt weiterläuft (angeschlossener Weg)
var ref_dir := Vector3.ZERO   # Richtung der Straße unter dem Startpunkt (für rechte Winkel)
var mat_tint_ok: StandardMaterial3D
var mat_tint_bad: StandardMaterial3D
var mat_guide: StandardMaterial3D
var mat_upgrade: StandardMaterial3D
var snapping := true          # Winkel und Länge einrasten (Shift kehrt es um)
var room_zone := ""           # Raum-Werkzeug: Bereich, der mit angelegt wird ("" = keiner)
var room_door := "automatik"  # Raum-Werkzeug: Türart
var room_kind := ""           # Raum-Werkzeug: Raumart (lager, kueche, sanitaet, pause, technik)
var area_from := Vector3.INF  # Flächenabriss: Startecke beim Ziehen


func setup(g: GameState, r: Node3D) -> void:
	game = g
	root3d = r
	mat_ok = _tmat(Color(0.38, 0.86, 0.95, 0.55))
	mat_bad = _tmat(Color(1.0, 0.32, 0.25, 0.55))
	mat_mark = _tmat(Color(0.92, 0.98, 1.0, 0.95))
	mat_overlay = _tmat(Color(1.0, 0.25, 0.2, 0.45))
	mat_snap = _tmat(Color(1.0, 0.85, 0.2, 0.95))
	mat_tint_ok = _tmat(Color(0.45, 0.9, 1.0, 0.22))
	mat_tint_bad = _tmat(Color(1.0, 0.3, 0.22, 0.5))
	mat_guide = _tmat(Color(1.0, 1.0, 1.0, 0.55))
	mat_upgrade = _tmat(Color(0.35, 0.85, 1.0, 0.5))
	preview = MeshInstance3D.new()
	preview.name = "Vorschau"
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root3d.add_child(preview)
	marker_root = Node3D.new()
	marker_root.name = "Punkte"
	root3d.add_child(marker_root)
	game.money_changed.connect(func(_v: int) -> void: _refresh())


func _tmat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func is_line_tool() -> bool:
	return Catalog.LINES.has(tool)


func is_item_tool() -> bool:
	return Catalog.ITEMS.has(tool) and not is_rect_tool()


## Terminalhalle: Rechteck mit zwei Klicks.
func is_rect_tool() -> bool:
	return Catalog.ITEMS.has(tool) and bool(Catalog.ITEMS[tool].get("rect_tool", false))


## Zeichenarten gibt es für alle geschwungenen Wege außer Leitungen und Wänden.
func uses_modes() -> bool:
	if not is_line_tool():
		return false
	var def: Dictionary = Catalog.LINES[tool]
	return not bool(def["straight"]) and Catalog.utility_of(tool) == "" and not Catalog.is_wall(tool)


## Lässt sich der gewählte Weg auf bestehende Wege derselben Familie umbauen (Ersetzen)?
func can_replace() -> bool:
	return GameState.UPGRADE_FAMILY.has(tool)


func replacing() -> bool:
	return draw_mode == "ersetzen" and uses_modes() and can_replace()


func set_mode(m: String) -> void:
	if not (m in MODES) or (m == "ersetzen" and not can_replace()):
		return
	draw_mode = m
	if m == "ersetzen":
		points.clear()
		start_tan = Vector3.ZERO
		ref_dir = Vector3.ZERO
	elif points.size() > 1:
		points = [points[0]]
	_clear_highlight()
	_emit_mode()
	_refresh()


func _emit_mode() -> void:
	mode_changed.emit(draw_mode, uses_modes(), can_replace())


func cycle_mode() -> void:
	if not uses_modes():
		return
	var avail := MODES.duplicate()
	if not can_replace():
		avail.erase("ersetzen")
	set_mode(avail[(maxi(avail.find(draw_mode), 0) + 1) % avail.size()])


## Winkel- und Längenraster ein- oder ausschalten.
func set_snapping(on: bool) -> void:
	snapping = on
	if has_hover:
		hover = _snap(raw_hover)
	_refresh()


func is_drawing() -> bool:
	return ((is_line_tool() or is_rect_tool() or tool == "kopieren" or tool == "raum") and not points.is_empty()) \
		or area_from != Vector3.INF


func set_tool(id: String) -> void:
	var self_turning := func(t: String) -> bool: return Catalog.ITEMS.has(t) and (Catalog.is_door(t) or Catalog.is_marker(t) or bool(Catalog.ITEMS[t].get("bridge", false)))
	if self_turning.call(tool) and not self_turning.call(id):
		rot = 0   # Türen und Brücken drehen sich selbst nach der Wand
	points.clear()
	_clear_highlight()
	if ghost != null:
		ghost.queue_free()
		ghost = null
	tool = id
	start_tan = Vector3.ZERO
	ref_dir = Vector3.ZERO
	if draw_mode == "ersetzen" and not can_replace():
		draw_mode = "gerade"
	_emit_mode()
	hint.emit("")
	if Catalog.utility_of(id) != "" and not game.utility_view:
		game.set_utility_view(true)
	if Catalog.is_terminal_tool(id) and not game.interior_view:
		game.set_interior_view(true)
	if is_item_tool():
		ghost = Factory.make_item(id)
		_paint(ghost, mat_ok)
		root3d.add_child(ghost)
	if has_hover:
		hover = _snap(raw_hover)
	tool_changed.emit(tool)
	_refresh()


# ---------------------------------------------------------------- Eingaben (von main.gd)

func on_move(p: Variant) -> void:
	if p == null:
		if has_hover:
			has_hover = false
			_refresh()
		return
	raw_hover = p
	if tool == "":
		hover = raw_hover
		has_hover = true
		return
	var s := _snap(raw_hover)
	if tool == "kopieren":
		s = raw_hover.snapped(Vector3(2, 0, 2))
	if replacing():
		s = raw_hover
	if has_hover and s.is_equal_approx(hover) and not (tool in ["abriss", "spuren", "kreuzung"]):
		return
	hover = s
	has_hover = true
	_refresh()


func on_click(p: Vector3) -> void:
	raw_hover = p
	hover = _snap(p)
	has_hover = true
	if tool == "kopieren":
		hover = p.snapped(Vector3(2, 0, 2))
		_click_copy()
		_refresh()
		return
	if is_rect_tool():
		if points.is_empty():
			points.append(hover)
			_refresh()
			return
		if Catalog.is_zone(tool):
			var zr := GameState.zone_rect(points[0], hover)
			var zwhy := game.can_place_zone(tool, zr)
			if zwhy == "":
				game.build_zone(tool, zr)
				points.clear()
			else:
				game.toast.emit(zwhy)
			_refresh()
			return
		if tool == "geschoss":
			var gr := GameState.storey_rect(points[0], hover)
			var gwhy := game.set_storey(game.hall_at(Vector3(gr.get_center().x, 0, gr.get_center().y)), game.view_floor, gr)
			if gwhy == "":
				points.clear()
			else:
				game.toast.emit(gwhy)
			_refresh()
			return
		if tool == "vorfeldflaeche":
			var ar := GameState.apron_rect(points[0], hover)
			var awhy := game.can_place_apron(ar)
			if awhy == "":
				game.build_apron(ar)
				points.clear()
			else:
				game.toast.emit(awhy)
			_refresh()
			return
		var r := GameState.hall_rect(points[0], hover)
		var why := game.can_place_hall(r)
		if why == "":
			game.build_hall(r)
			points.clear()
		else:
			game.toast.emit(why)
		_refresh()
	elif replacing():
		hover = p
		_click_replace()
	elif is_line_tool():
		if not points.is_empty():
			var last: Vector3 = points[points.size() - 1]
			if last.distance_to(hover) < 1.0:
				return
		if uses_modes() and draw_mode != "frei":
			_click_mode()
			return
		if points.is_empty():
			_begin(hover)
		else:
			points.append(hover)
		var def: Dictionary = Catalog.LINES[tool]
		if points.size() >= 2 and (bool(def["straight"]) or snap_kind != ""):
			# Gerade Wege sind nach zwei Klicks fertig, alle anderen, sobald sie an einen Weg anschließen
			finish()
			return
		_refresh()
	elif is_item_tool():
		_refresh()
		if reason == "":
			game.build_item(tool, hover, rot)
		else:
			game.toast.emit(reason)
		_refresh()
	elif tool == "":
		inspect_requested.emit(p)
	elif tool == "spuren":
		var rec := game.pick(p)
		if rec.get("type", "") == "line" and Catalog.is_road(String(rec["kind"])):
			var why := game.cycle_road(rec)
			game.toast.emit(why if why != "" else "Jetzt: " + _road_name(rec))
		else:
			game.toast.emit("Klicke auf eine Straße")
		_refresh()
	elif tool == "kreuzung":
		var ctrl: String = roads.cycle_control(p)
		game.toast.emit("Kreuzung: " + String(roads.CONTROL_NAMES.get(ctrl, "")) if ctrl != "" else "Klicke auf eine Kreuzung (mindestens drei Straßen)")
		_refresh()
	elif tool == "raum":
		if points.is_empty():
			points.append(hover)
			_refresh()
			return
		var rr := room_rect(points[0], hover)
		var why := game.build_room(rr, room_zone, room_door, room_kind)
		game.toast.emit(why if why != "" else "Raum %d × %d m gebaut" % [int(rr.size.x), int(rr.size.y)])
		points.clear()
		_refresh()
	elif tool == "abriss":
		_refresh()
		if not target.is_empty():
			var t := target
			_clear_highlight()
			game.toast.emit(game.describe(t) + " abgerissen")
			game.remove(t, 0.5)
			_refresh()
		elif area_from == Vector3.INF:
			area_from = hover   # auf freiem Boden: Fläche aufziehen
		else:
			_finish_area()


## Maustaste losgelassen: Rechtecke und Wände, die man aufgezogen hat, werden gebaut (wie in
## Aufbauspielen mit Grundriss). Ohne Ziehen bleibt es beim Klicken von Ecke zu Ecke.
func on_release(p: Vector3) -> void:
	if area_from != Vector3.INF and tool == "abriss":
		if Vector2(p.x - area_from.x, p.z - area_from.z).length() > 2.0:
			hover = p
			_finish_area()
		return
	if points.size() != 1:
		return
	var drag := (is_rect_tool() or tool == "raum" or (is_line_tool() and Catalog.is_wall(tool)) or (tool == "kopieren" and clip.is_empty()))
	if drag and Vector2(p.x - (points[0] as Vector3).x, p.z - (points[0] as Vector3).z).length() > 1.5:
		on_click(p)


func _finish_area() -> void:
	var r := _area_rect()
	area_from = Vector3.INF
	var n := game.demolish_area(r)
	game.toast.emit("%d Teile abgerissen" % n if n > 0 else "Hier war nichts zum Abreißen")
	_refresh()


func _area_rect() -> Rect2:
	var a := area_from
	var b := hover
	return Rect2(minf(a.x, b.x), minf(a.z, b.z), absf(a.x - b.x), absf(a.z - b.z))


static func room_rect(a: Vector3, b: Vector3) -> Rect2:
	var x0 := snappedf(minf(a.x, b.x), 1.0)
	var z0 := snappedf(minf(a.z, b.z), 1.0)
	return Rect2(x0, z0, maxf(snappedf(maxf(a.x, b.x), 1.0) - x0, 1.0), maxf(snappedf(maxf(a.z, b.z), 1.0) - z0, 1.0))


func on_right() -> void:
	if area_from != Vector3.INF:
		area_from = Vector3.INF
		_refresh()
		return
	if tool == "kopieren" and not clip.is_empty() and points.is_empty():
		clip = {}
		game.toast.emit("Blaupause verworfen")
		_refresh()
		return
	if is_drawing():
		if points.size() >= 2 and not (uses_modes() and draw_mode != "frei"):
			finish()
		else:
			cancel()
	else:
		set_tool("")


func on_escape() -> void:
	if is_drawing():
		cancel()
	else:
		set_tool("")


func rotate() -> void:
	rot = (rot + 1) % 4
	if has_hover:
		hover = _snap(raw_hover)
	_refresh()


func cancel() -> void:
	area_from = Vector3.INF
	points.clear()
	start_tan = Vector3.ZERO
	ref_dir = Vector3.ZERO
	_refresh()


## Erster Punkt eines Weges: Am Ende eines Weges läuft der neue tangential weiter,
## mitten auf einem Weg merkt er sich dessen Richtung für rechte Winkel.
func _begin(p: Vector3) -> void:
	points = [p]
	start_tan = Vector3.ZERO
	ref_dir = Vector3.ZERO
	if snap_kind == "ende" and snap_tan != Vector3.ZERO:
		start_tan = -snap_tan
	elif snap_kind == "weg" and snap_tan != Vector3.ZERO:
		ref_dir = snap_tan


## Klick in den Zeichenarten Gerade und Kurve.
func _click_mode() -> void:
	if points.is_empty():
		_begin(hover)
		_refresh()
		return
	if draw_mode == "kurve" and points.size() == 1 and start_tan == Vector3.ZERO:
		# zweiter Klick legt die Richtung (Kontrollpunkt) fest
		points.append(hover)
		_refresh()
		return
	_commit(curve_points(hover))


## Baut das gezeigte Stück und setzt am Ende tangential fort (wie in Städtebauspielen).
func _commit(pts: Array) -> void:
	if pts.size() < 2:
		return
	var st := _line_state(pts)
	if not bool(st["ok"]):
		game.toast.emit(String(st["why"]))
		_refresh()
		return
	var attached := snap_kind != ""
	var last: Vector3 = pts[pts.size() - 1]
	var prev: Vector3 = pts[pts.size() - 2]
	game.build_line(tool, pts, false, false, game.road_side if Catalog.has_sides(tool) else "")
	points.clear()
	start_tan = Vector3.ZERO
	ref_dir = Vector3.ZERO
	if not attached and tool != "tunnel":
		points = [last]
		var t := last - prev
		t.y = 0.0
		if t.length() > 0.01:
			start_tan = t.normalized()
	_refresh()


## Punkte des Weges für den Mauszeiger e in der aktuellen Zeichenart.
func curve_points(e: Vector3) -> Array:
	if points.is_empty():
		return [e]
	var s: Vector3 = points[0]
	if not uses_modes() or draw_mode == "frei":
		var out := points.duplicate()
		out.append(e)
		return out
	if draw_mode == "gerade":
		return [s, e]
	if points.size() >= 2:
		return _quad(s, points[1], e)
	if start_tan != Vector3.ZERO:
		if snap_kind == "ende" and snap_tan != Vector3.ZERO:
			return _hermite(s, start_tan, e, snap_tan)
		return _arc(s, start_tan, e)
	return [s, e]


## Kreisbogen ab s in Richtung t bis e.
static func _arc(s: Vector3, t: Vector3, e: Vector3) -> Array:
	var d := Vector3(e.x - s.x, 0.0, e.z - s.z)
	var l := d.length()
	if l < 0.5:
		return [s, e]
	var tn := Vector3(t.x, 0.0, t.z).normalized()
	var side := Vector3(-tn.z, 0.0, tn.x)
	var h := d.dot(side)
	if absf(h) < 0.01 * l and d.dot(tn) > 0.0:
		return [s, e]
	var r := l * l / (2.0 * h)
	var c := s + side * r
	var rad := absf(r)
	var a0 := atan2(s.z - c.z, s.x - c.x)
	var a1 := atan2(e.z - c.z, e.x - c.x)
	var tang := Vector3(-sin(a0), 0.0, cos(a0))
	var sweep := fposmod(a1 - a0, TAU) if tang.dot(tn) > 0.0 else -fposmod(a0 - a1, TAU)
	var n := maxi(4, ceili(absf(sweep) * rad / 2.0))
	var out := []
	for i in range(n + 1):
		var a := a0 + sweep * float(i) / float(n)
		out.append(Vector3(c.x + cos(a) * rad, 0.0, c.z + sin(a) * rad))
	out[n] = Vector3(e.x, 0.0, e.z)
	return out


## Kubische Kurve mit vorgegebener Richtung an beiden Enden (te zeigt in den Zielweg hinein).
static func _hermite(s: Vector3, ts: Vector3, e: Vector3, te: Vector3) -> Array:
	var l := Vector2(e.x - s.x, e.z - s.z).length()
	var h := l * 0.42
	var p1 := s + ts.normalized() * h
	var p2 := e - te.normalized() * h
	var n := maxi(6, ceili(l / 2.0))
	var out := []
	for i in range(n + 1):
		var t := float(i) / float(n)
		var u := 1.0 - t
		out.append(s * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + e * (t * t * t))
	return out


## Quadratische Kurve: Start, Kontrollpunkt, Ende.
static func _quad(s: Vector3, c: Vector3, e: Vector3) -> Array:
	var n := maxi(6, ceili((s.distance_to(c) + c.distance_to(e)) / 2.0))
	var out := []
	for i in range(n + 1):
		var t := float(i) / float(n)
		out.append(s.lerp(c, t).lerp(c.lerp(e, t), t))
	return out


func finish() -> void:
	if uses_modes() and draw_mode != "frei":
		if not points.is_empty() and has_hover and points[points.size() - 1].distance_to(hover) > 1.0:
			_commit(curve_points(hover))
		return
	if not is_line_tool() or points.size() < 2:
		return
	var st := _line_state(points)
	if bool(st["ok"]):
		game.build_line(tool, points, false, false, game.road_side if Catalog.has_sides(tool) else "")
		points.clear()
	else:
		game.toast.emit(String(st["why"]))
		var def: Dictionary = Catalog.LINES[tool]
		if bool(def["straight"]):
			points.clear()
	_refresh()


# ---------------------------------------------------------------- Raster und Einrasten

func _snap(p: Vector3) -> Vector3:
	if tool == "raum":
		return Vector3(snappedf(p.x, 1.0), 0.0, snappedf(p.z, 1.0))
	if is_rect_tool():
		var g: float = Catalog.ITEMS[tool]["grid"]
		return Vector3(snappedf(p.x, g), 0.0, snappedf(p.z, g))
	if is_line_tool():
		return _snap_line(p)
	if is_item_tool() and Catalog.is_door(tool):
		var dp := _snap_door(p)
		if dp != Vector3.INF:
			return dp
	if is_item_tool() and tool == "rolltor":
		var ws: Array = game.wall_snap(tool, p)
		if not ws.is_empty():
			rot = int(ws[1])
			return ws[0]
	if is_item_tool() and Catalog.is_marker(tool):
		var ms: Array = game.marker_snap(tool, p)
		if not ms.is_empty():
			rot = int(ms[1])
			return ms[0]
	if is_item_tool() and tool == "bushalt":
		# Vorfeld-Haltestelle: als Bucht an eine Betriebsstraße einrasten (sonst frei auf dem Vorfeld)
		var bs2: Array = game.apron_bay_snap(tool, p)
		if not bs2.is_empty() and not game._on_kind(p, "vorfeld"):
			rot = int(bs2[1])
			snap_kind = "bucht"
			return bs2[0]
	if is_item_tool() and (Catalog.ITEMS[tool].get("access", {}) as Dictionary).has("halt"):
		var ss: Array = game.stop_snap(tool, p)
		if not ss.is_empty():
			rot = int(ss[1])
			snap_kind = "bucht"
			return ss[0]
		snap_kind = ""
	if is_item_tool() and bool(Catalog.ITEMS[tool].get("bridge", false)):
		var bs: Array = game.bridge_snap(p)
		if not bs.is_empty():
			rot = int(bs[1])
			return bs[0]
	if is_item_tool():
		var g: float = Catalog.ITEMS[tool]["grid"]
		var s: Vector2 = Catalog.ITEMS[tool]["size"]
		if rot % 2 == 1:
			s = Vector2(s.y, s.x)
		var ox := fmod(s.x * 0.5, g)
		var oz := fmod(s.y * 0.5, g)
		return Vector3(snappedf(p.x - ox, g) + ox, 0.0, snappedf(p.z - oz, g) + oz)
	return Vector3(p.x, 0.0, p.z)


## Tür: auf die nächste Innenwand der gezeigten Ebene (bis 3 m), quer dazu gedreht, im 0,5-m-Raster.
func _snap_door(p: Vector3) -> Vector3:
	var hall := game.hall_at(p)
	if hall.is_empty():
		return Vector3.INF
	var best := Vector3.INF
	var bd := 3.0
	for l: Dictionary in game.walls_of(hall):
		if GameState.floor_of(l) != game.view_floor:
			continue
		var smp: PackedVector3Array = l["samples"]
		var a := Vector3(smp[0].x, 0, smp[0].z)
		var b := Vector3(smp[smp.size() - 1].x, 0, smp[smp.size() - 1].z)
		var d := b - a
		var length := d.length()
		if length < 3.0:
			continue
		var dn := d / length
		if absf(dn.x) < 0.98 and absf(dn.z) < 0.98:
			continue
		var t := clampf(snappedf((p - a).dot(dn), 0.5), 1.3, length - 1.3)
		var q := a + dn * t
		var dist := Vector2(q.x - p.x, q.z - p.z).length()
		if dist < bd:
			bd = dist
			best = q
			rot = 0 if absf(dn.x) > 0.5 else 1
	return best


## Wege rasten an Wegenden ein, dann irgendwo auf passenden Wegen, sonst an 15-Grad-Schritten
## zum letzten Punkt (Shift hält den Winkel frei) und auf ganze Meter.
func _snap_line(p: Vector3) -> Vector3:
	snap_kind = ""
	if tool == "kofferband":
		return _snap_belt(p)
	var util := Catalog.utility_of(tool)
	var group: Array = SNAP_GROUPS.get(tool, [tool])
	var candidates := []
	for l: Dictionary in game.lines:
		var k: String = l["kind"]
		var ok := false
		if util != "":
			ok = Catalog.utility_of(k) != ""
		elif Catalog.is_wall(tool):
			ok = Catalog.is_wall(k)
		else:
			ok = k in group
		if ok:
			candidates.append(l)
	snap_tan = Vector3.ZERO
	var best := SNAP_DIST
	var q := Vector3.ZERO
	var ends := 0
	for l: Dictionary in candidates:
		var smp: PackedVector3Array = l["samples"]
		var n := smp.size()
		for ei in range(2):
			var e: Vector3 = smp[0] if ei == 0 else smp[n - 1]
			var d := Vector2(e.x - p.x, e.z - p.z).length()
			if d < best - 0.01:
				best = d
				q = e
				snap_kind = "ende"
				var inner: Vector3 = smp[mini(4, n - 1)] if ei == 0 else smp[maxi(n - 5, 0)]
				var t := Vector3(inner.x - e.x, 0.0, inner.z - e.z)
				snap_tan = t.normalized() if t.length() > 0.01 else Vector3.ZERO
				ends = 1
			elif absf(d - best) <= 0.01 and snap_kind == "ende":
				ends += 1
	if snap_kind != "":
		if ends > 1:
			snap_tan = Vector3.ZERO   # mehrere Wege enden hier: keine eindeutige Richtung
		return Vector3(q.x, 0.0, q.z)
	best = INF
	for l: Dictionary in candidates:
		var reach := maxf(4.5, float(Catalog.LINES[l["kind"]]["width"]) * 0.5) if util == "" else 3.0
		var b: Rect2 = (l["bounds"] as Rect2).grow(reach)
		if not b.has_point(Vector2(p.x, p.z)):
			continue
		var smp: PackedVector3Array = l["samples"]
		for i in range(smp.size()):
			var v := smp[i]
			var d := Vector2(v.x - p.x, v.z - p.z).length()
			if d < reach and d < best:
				best = d
				q = v
				snap_kind = "weg"
				var t := smp[mini(i + 2, smp.size() - 1)] - smp[maxi(i - 2, 0)]
				t.y = 0.0
				snap_tan = t.normalized() if t.length() > 0.01 else Vector3.ZERO
	if snap_kind != "":
		return Vector3(q.x, 0.0, q.z)
	if not points.is_empty() and snapping != Input.is_key_pressed(KEY_SHIFT):
		var last: Vector3 = points[points.size() - 1]
		if uses_modes():
			if draw_mode == "kurve" and points.size() == 1 and start_tan != Vector3.ZERO:
				return _snap_arc(last, start_tan, p)
			var ref := Vector3.RIGHT
			if points.size() == 1 and start_tan != Vector3.ZERO:
				ref = start_tan
			elif points.size() == 1 and ref_dir != Vector3.ZERO:
				ref = ref_dir
			elif points.size() == 1:
				# frei begonnen: an der Richtung des nächsten Weges ausrichten (parallel, rechtwinklig)
				var nd := _nearby_dir(last, 90.0)
				if nd != Vector3.ZERO:
					ref = nd
			elif points.size() >= 2:
				var pr: Vector3 = points[points.size() - 2]
				ref = Vector3(last.x - pr.x, 0.0, last.z - pr.z).normalized()
			return _snap_dir(last, ref, p)
		return _snap_dir(last, Vector3.RIGHT, p)
	if snapping == Input.is_key_pressed(KEY_SHIFT):
		return Vector3(p.x, 0.0, p.z)
	return Vector3(snappedf(p.x, 0.5), 0.0, snappedf(p.z, 0.5))


## Kofferband: rastet an den Seiten der Check-in-Schalter, an den Kanten der Gepäcksortierung und an
## anderen Kofferbändern ein; sonst gerade Stücke in 15-Grad-Schritten.
func _snap_belt(p: Vector3) -> Vector3:
	snap_tan = Vector3.ZERO
	var best := 2.2
	var q := Vector3.INF
	var spots: Array = game.belt_spots(game.view_floor if game.interior_view else 0)
	for l: Dictionary in game.lines:
		if l["kind"] != "kofferband" or GameState.floor_of(l) != (game.view_floor if game.interior_view else 0):
			continue
		# die Klickpunkte, nicht die ausgerundeten Enden
		var lp: Array = l["points"]
		spots.append(lp[0])
		spots.append(lp[lp.size() - 1])
	for sp: Vector3 in spots:
		var d := Vector2(sp.x - p.x, sp.z - p.z).length()
		if d < best:
			best = d
			q = Vector3(sp.x, 0, sp.z)
	if q != Vector3.INF:
		snap_kind = "ende"
		return q
	if not points.is_empty() and snapping != Input.is_key_pressed(KEY_SHIFT):
		var last: Vector3 = points[points.size() - 1]
		var ref := Vector3.RIGHT
		if points.size() >= 2:
			var pr: Vector3 = points[points.size() - 2]
			ref = Vector3(last.x - pr.x, 0.0, last.z - pr.z).normalized()
		return _snap_dir(last, ref, p)
	return Vector3(snappedf(p.x, 0.5), 0.0, snappedf(p.z, 0.5))


## Richtung des nächsten Weges derselben Art in der Nähe (oder Null).
func _nearby_dir(p: Vector3, max_d: float) -> Vector3:
	var group: Array = SNAP_GROUPS.get(tool, [tool])
	var best := max_d
	var dir := Vector3.ZERO
	for l: Dictionary in game.lines:
		if not (l["kind"] in group):
			continue
		var sm: PackedVector3Array = l["samples"]
		for i in range(0, sm.size(), 2):
			var d := Vector2(sm[i].x - p.x, sm[i].z - p.z).length()
			if d < best:
				best = d
				var t := sm[mini(i + 2, sm.size() - 1)] - sm[maxi(i - 2, 0)]
				t.y = 0.0
				if t.length() > 0.01:
					dir = t.normalized()
	return dir


## Richtung ab base: rastet weich auf 15-Grad-Stufen zur Bezugsrichtung ein, Länge auf halbe Meter.
static func _snap_dir(base: Vector3, ref: Vector3, p: Vector3) -> Vector3:
	var d := Vector3(p.x - base.x, 0.0, p.z - base.z)
	var l := d.length()
	if l < 1.0:
		return Vector3(p.x, 0.0, p.z)
	var r := Vector3(ref.x, 0.0, ref.z).normalized()
	var ang := r.signed_angle_to(d, Vector3.UP)
	var stepr := deg_to_rad(ANGLE_STEP)
	var snapped_ang := roundf(ang / stepr) * stepr
	if absf(ang - snapped_ang) < deg_to_rad(MAGNET):
		ang = snapped_ang
	l = snappedf(l, 0.5)
	return base + r.rotated(Vector3.UP, ang) * l


## Kurvenende bei bekannter Startrichtung: Der Abbiegewinkel des Bogens rastet auf 15-Grad-Stufen ein.
static func _snap_arc(base: Vector3, t: Vector3, p: Vector3) -> Vector3:
	var d := Vector3(p.x - base.x, 0.0, p.z - base.z)
	var l := d.length()
	if l < 1.0:
		return Vector3(p.x, 0.0, p.z)
	var r := Vector3(t.x, 0.0, t.z).normalized()
	var half := r.signed_angle_to(d, Vector3.UP)
	var turn := half * 2.0
	var stepr := deg_to_rad(ANGLE_STEP)
	var snapped_turn := roundf(turn / stepr) * stepr
	if absf(turn - snapped_turn) < deg_to_rad(MAGNET + 1.0):
		half = snapped_turn * 0.5
	l = snappedf(l, 0.5)
	return base + r.rotated(Vector3.UP, half) * l


# ---------------------------------------------------------------- Vorschau

func _line_state(pts: Array) -> Dictionary:
	var def: Dictionary = Catalog.LINES[tool]
	var straight: bool = def["straight"]
	var samples := GameState.line_samples(tool, pts)
	var length := Spline.length(samples)
	var minr := INF if straight else Spline.min_radius(samples)
	var need: float = def["min_r"]
	var min_len: float = def["min_len"]
	var cost := game.line_cost(tool, samples, game.road_side if Catalog.has_sides(tool) else "")
	var why := ""
	var check := {"why": "", "decor": [], "junctions": []}
	if Catalog.is_wall(tool) and pts.size() >= 2:
		why = game.can_place_wall(pts[0], pts[pts.size() - 1])
	elif samples.size() >= 2:
		check = game.check_line(tool, samples)
		why = String(check["why"])
	if why != "":
		pass
	elif length < min_len:
		why = "Zu kurz: mindestens %d m" % int(min_len)
	elif minr < need:
		why = "Kurve zu eng: Radius %d m, nötig sind %d m" % [int(minr), int(need)]
	elif not game.can_afford(cost):
		why = "Nicht genug Geld"
	return {"ok": why == "", "why": why, "samples": samples, "length": length, "minr": minr, "cost": cost,
		"decor": (check["decor"] as Array).size(), "junctions": check["junctions"]}


## Höhe der gezeigten Ebene für Vorschauen von Einrichtung, Wänden und Bereichen.
func _lift() -> float:
	if not game.interior_view:
		return 0.0
	if tool == "raum" or Catalog.is_floor_line(tool) or (Catalog.ITEMS.has(tool) and Catalog.is_inside(tool)):
		return float(game.view_floor) * Catalog.FLOOR_H
	return 0.0


func _refresh() -> void:
	preview.mesh = null
	preview.position = Vector3.ZERO
	marker_root.position = Vector3(0, _lift(), 0)
	for c in marker_root.get_children():
		c.queue_free()
	if ghost != null:
		ghost.visible = false
	if not is_line_tool():
		steps.emit("")
	if tool == "":
		info.emit("Ansehen", "Klicke auf ein Gebäude, einen Weg oder ein Flugzeug für Details. Unten wählst du ein Bauwerkzeug.", 0)
	elif is_rect_tool():
		_refresh_rect()
	elif replacing():
		_refresh_replace()
	elif is_line_tool():
		_refresh_line()
	elif is_item_tool():
		_refresh_item()
	elif tool == "abriss":
		_refresh_demolish()
	elif tool == "raum":
		_refresh_room()
	elif tool == "kopieren":
		_refresh_copy()
	elif tool == "spuren":
		_clear_highlight()
		var rec := game.pick(hover) if has_hover else {}
		if rec.get("type", "") == "line" and Catalog.is_road(String(rec["kind"])):
			target = rec
			_highlight(rec)
			info.emit("Spuren ändern", _road_name(rec) + "\nKlick: nächster Typ (2-spurig → 4-spurig → Einbahn → Einbahn umgekehrt)", 1)
		else:
			info.emit("Spuren ändern", "Klicke auf eine Straße, um Spuren und Richtung zu ändern.", 0)
	elif tool == "kreuzung":
		var ni: int = roads.nearest_junction(hover) if has_hover else -1
		if ni >= 0:
			_marker(roads.nodes[ni]["pos"], 3.0, mat_snap)
			info.emit("Kreuzung regeln", "Jetzt: %s\nKlick: rechts vor links → Vorfahrtsstraße → Ampel" % String(roads.CONTROL_NAMES.get(roads.control_of(ni), "")), 1)
		else:
			info.emit("Kreuzung regeln", "Fahre über eine Kreuzung mit mindestens drei Straßen.", 0)


func _refresh_line() -> void:
	var def: Dictionary = Catalog.LINES[tool]
	var title := String(def["name"]) + " bauen"
	var per_m := GameState.fmt_money(int(def["cost_m"])) + " pro Meter"
	if Catalog.has_sides(tool):
		var sd: Dictionary = Catalog.SIDES[game.road_side]
		per_m = "%s · %s pro Meter (V wechselt den Querschnitt)" % [String(sd["name"]), GameState.fmt_money(int(def["cost_m"]) + int(sd["cost_m"]))]
	var modes := uses_modes() and draw_mode != "frei"
	for i in range(points.size()):
		_marker(points[i], 1.6 if i == 0 else 1.1, mat_mark)
	if has_hover:
		_marker(hover, 2.6 if snap_kind != "" else 1.0, mat_snap if snap_kind != "" else mat_mark)
	var pts: Array = []
	if not points.is_empty() and has_hover and points[points.size() - 1].distance_to(hover) > 0.5:
		pts = curve_points(hover)
	steps.emit(_step_text(def, not pts.is_empty()))
	if points.size() == 1 and start_tan != Vector3.ZERO:
		_guide(points[0], points[0] + start_tan * 40.0)
	if modes and draw_mode == "kurve" and points.size() >= 2:
		_guide(points[0], points[1])
		if has_hover:
			_guide(points[1], hover)
	if pts.size() < 2:
		var how := "Klicke Start- und Endpunkt."
		if modes and draw_mode == "gerade":
			how = "Gerade: Startpunkt klicken, dann das Ende. Es geht automatisch am Ende weiter, Rechtsklick hört auf. Am Ende eines Weges läuft der neue in dessen Richtung weiter."
		elif modes and draw_mode == "kurve":
			how = "Kurve: Startpunkt, dann Richtung, dann Ende klicken. Am Ende eines Weges geht die Kurve tangential weiter, dann reichen Start und Ende."
			if points.size() == 1 and start_tan == Vector3.ZERO:
				how = "Kurve: Jetzt die Richtung klicken (Kontrollpunkt), danach das Ende."
		elif not bool(def["straight"]):
			how = "Freihand: Klicke den Startpunkt, dann weitere Punkte für Kurven. Klickst du auf einen Weg, schließt der neue Weg dort an und ist fertig."
		if Catalog.is_wall(tool):
			how = "Klicke Anfang und Ende der Wand, innerhalb einer Halle. Endpunkte rasten ein."
		if uses_modes():
			how += "\nTab wechselt: Gerade · Kurve · Freihand"
		info.emit(title, how + "\n" + per_m, 0)
		hint.emit("")
		return
	var st := _line_state(pts)
	var w: float = def["width"]
	var y: float = def["y"]
	if Catalog.is_wall(tool):
		w = 0.8
		y = 1.3
	var samples: PackedVector3Array = st["samples"]
	var flat := PackedVector3Array()
	for v: Vector3 in samples:
		flat.append(Vector3(v.x, 0.0, v.z))
	var ok := bool(st["ok"])
	if Catalog.utility_of(tool) != "" or Catalog.is_wall(tool):
		preview.mesh = Spline.ribbon(flat, w, y + 0.25)
		preview.position.y = _lift()
		preview.material_override = mat_ok if ok else mat_bad
	else:
		# Vorschau im echten Aussehen des Weges, getönt
		if tool == "kofferband":
			flat = game.belt_profile(flat, game.view_floor if game.interior_view else 0)
		var look := Factory.make_line(tool, flat, y + 0.12)
		if Catalog.has_sides(tool) and game.road_side != "ohne":
			look.add_child(Streetscape.build(flat, w, game.road_side, y + 0.12, [], 0.12))
		_tint(look, mat_tint_ok if ok else mat_tint_bad)
		marker_root.add_child(look)
	var length: float = st["length"]
	var body := "Länge %d m · %s" % [int(length), GameState.fmt_money(int(st["cost"]))]
	var minr: float = st["minr"]
	var tip := "%s m" % _num(snappedf(length, 0.5))
	if minr < 100000.0:
		body += "\nEngster Radius %d m (nötig %d m)" % [int(minr), int(def["min_r"])]
		if minr < 3000.0:
			tip += " · R %d m" % int(minr)
	var a := pts[pts.size() - 2] as Vector3
	var b := pts[pts.size() - 1] as Vector3
	var ref := start_tan if start_tan != Vector3.ZERO else ref_dir
	if ref != Vector3.ZERO and points.size() == 1:
		var endd := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if endd.length() > 0.1:
			tip += " · %d°" % absi(roundi(rad_to_deg(ref.signed_angle_to(endd, Vector3.UP))))
	var crossings := 0
	var p_first: Vector3 = pts[0]
	var p_last: Vector3 = pts[pts.size() - 1]
	for jn: Array in st["junctions"]:
		var jp: Vector3 = jn[1]
		if jp.distance_to(p_first) < 6.0 or jp.distance_to(p_last) < 6.0:
			continue   # Anschluss am Anfang oder Ende, keine neue Kreuzung
		crossings += 1
		_marker(jp, 2.4, mat_snap)
	if ok:
		if crossings > 0:
			body += "\n%d Kreuzung(en) werden angelegt" % crossings
		if int(st["decor"]) > 0:
			body += "\n%d Bäume oder Deko werden weggeräumt" % int(st["decor"])
	if snap_kind != "" and not points.is_empty():
		body += "\nSchließt hier an: Klick baut den Weg"
	if tool == "tunnel":
		body += "\nDer Teil zwischen den Rampen liegt unter der Erde (Ansicht Untergeschoss: Bild ab)"
	if not ok:
		body += "\n" + String(st["why"])
		tip += "\n" + String(st["why"])
	elif modes:
		body += "\nKlick: bauen · Rechtsklick: aufhören · Shift: frei ohne Einrasten · Tab: Zeichenart"
	elif not bool(def["straight"]):
		body += "\nRechtsklick oder Enter: fertig · Shift: freier Winkel"
	info.emit(title, body, 1 if ok else 2)
	hint.emit(tip)


## Nächster Arbeitsschritt beim Wegebau, kurz für die Wegebau-Leiste.
func _step_text(def: Dictionary, previewing: bool) -> String:
	var attach := "  · schließt an" if snap_kind != "" and previewing else ""
	if Catalog.is_wall(tool):
		return "1 Anfang klicken" if points.is_empty() else "2 Ende klicken"
	if not uses_modes():
		if points.is_empty():
			return "1 Startpunkt klicken"
		return ("2 Endpunkt klicken" if bool(def["straight"]) else "Weitere Punkte · Rechtsklick oder Enter: fertig") + attach
	match draw_mode:
		"gerade":
			if points.is_empty():
				return "1 Startpunkt klicken (rastet an Wegen ein)"
			return "2 Endpunkt klicken · baut und zieht weiter · Rechtsklick: Kette beenden" + attach
		"kurve":
			if points.is_empty():
				return "1 Startpunkt klicken"
			if points.size() == 1 and start_tan == Vector3.ZERO:
				return "2 Richtung klicken"
			return ("3" if start_tan == Vector3.ZERO else "2") + " Endpunkt klicken · Rechtsklick: Kette beenden" + attach
	if points.is_empty():
		return "1 Startpunkt klicken"
	return "Weitere Punkte klicken · Rechtsklick oder Enter: fertig" + attach


## Gestrichelte Hilfslinie (Richtung des angeschlossenen Weges, Kontrollpunkte).
func _guide(a: Vector3, b: Vector3) -> void:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var l := d.length()
	if l < 0.5:
		return
	var dir := d / l
	var k := 0.0
	while k < l:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var seg := minf(1.6, l - k)
		bm.size = Vector3(0.35, 0.05, seg)
		mi.mesh = bm
		mi.material_override = mat_guide
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.basis = Basis.looking_at(dir, Vector3.UP)
		mi.position = a + dir * (k + seg * 0.5) + Vector3(0, 0.45, 0)
		marker_root.add_child(mi)
		k += 3.2


func _tint(n: Node, m: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = m
	for c in n.get_children():
		_tint(c, m)


func _refresh_rect() -> void:
	var def: Dictionary = Catalog.ITEMS[tool]
	if Catalog.is_zone(tool):
		_refresh_zone(def)
		return
	var title := String(def["name"]) + " bauen"
	var per := "%s pro m²" % GameState.fmt_money(int(def["cost_m2"]))
	if has_hover:
		_marker(hover, 1.2)
	for p: Vector3 in points:
		_marker(p, 1.6)
	if tool == "geschoss":
		var fy := float(maxi(game.view_floor, 0)) * Catalog.FLOOR_H
		if points.is_empty() or not has_hover:
			info.emit(String(def["name"]), String(def["desc"]) + "\nIn der Innenansicht ein Obergeschoss wählen (Bild auf/ab), dann erste Ecke drücken und ziehen.", 0)
			return
		var gr := GameState.storey_rect(points[0], hover)
		var hh: Dictionary = game.hall_at(Vector3(gr.get_center().x, 0, gr.get_center().y))
		var gwhy: String = game.storey_problem(hh, game.view_floor, gr)
		var gbm := BoxMesh.new()
		gbm.size = Vector3(maxf(gr.size.x, 0.5), 0.4, maxf(gr.size.y, 0.5))
		preview.mesh = gbm
		preview.position = Vector3(gr.get_center().x, fy + 0.3, gr.get_center().y)
		preview.material_override = mat_ok if gwhy == "" else mat_bad
		info.emit(String(def["name"]), "%s: %d × %d m\n%s" % [game.floor_name(game.view_floor), int(gr.size.x), int(gr.size.y),
			gwhy if gwhy != "" else "Loslassen oder gegenüberliegende Ecke klicken"], 1 if gwhy == "" else 2)
		return
	if tool == "vorfeldflaeche":
		if points.is_empty() or not has_hover:
			info.emit(title, String(def["desc"]) + "\nErste Ecke drücken und ziehen.\n" + per, 0)
			return
		var ar := GameState.apron_rect(points[0], hover)
		var awhy := game.can_place_apron(ar)
		var abm := BoxMesh.new()
		abm.size = Vector3(maxf(ar.size.x, 0.5), 0.3, maxf(ar.size.y, 0.5))
		preview.mesh = abm
		preview.position = Vector3(ar.get_center().x, 0.15, ar.get_center().y)
		preview.material_override = mat_ok if awhy == "" else mat_bad
		info.emit(title, "%d × %d m · %s\n%s" % [int(ar.size.x), int(ar.size.y), GameState.fmt_money(game.apron_cost(ar)),
			awhy if awhy != "" else "Loslassen oder gegenüberliegende Ecke klicken"], 1 if awhy == "" else 2)
		return
	if points.is_empty() or not has_hover:
		info.emit(title, "Klicke die erste Ecke der Halle.\n" + per, 0)
		return
	var r := GameState.hall_rect(points[0], hover)
	var why := game.can_place_hall(r)
	var bm := BoxMesh.new()
	bm.size = Vector3(maxf(r.size.x, 0.5), 9.6, maxf(r.size.y, 0.5))
	preview.mesh = bm
	preview.position = Vector3(r.get_center().x, 4.8, r.get_center().y)
	preview.material_override = mat_ok if why == "" else mat_bad
	var body := "%d × %d m = %s m² · %s" % [int(r.size.x), int(r.size.y),
		GameState.fmt_money(int(r.get_area())).trim_suffix(" €"), GameState.fmt_money(game.hall_cost(r))]
	body += "\nBraucht Strom (Licht und Lüftung %d kW) plus die Einrichtung" % roundi(r.get_area() * Catalog.HALL_POWER_M2)
	body += "\n" + (why if why != "" else "Klicke die gegenüberliegende Ecke")
	info.emit(title, body, 1 if why == "" else 2)


func _refresh_zone(def: Dictionary) -> void:
	var title := String(def["name"]) + " anlegen"
	if has_hover:
		_marker(hover, 1.0)
	for p: Vector3 in points:
		_marker(p, 1.4)
	var per := "%s pro m²" % GameState.fmt_money(int(def.get("cost_m2", 0)))
	if points.is_empty() or not has_hover:
		info.emit(title, String(def.get("desc", "")) + "\nKlicke die erste Ecke (" + game.floor_name(game.view_floor) + ").\n" + per, 0)
		return
	var r := GameState.zone_rect(points[0], hover)
	var why := game.can_place_zone(tool, r)
	var bm := BoxMesh.new()
	bm.size = Vector3(r.size.x, 0.25, r.size.y)
	preview.mesh = bm
	preview.position = Vector3(r.get_center().x, float(game.view_floor) * Catalog.FLOOR_H + 0.2, r.get_center().y)
	preview.material_override = mat_ok if why == "" else mat_bad
	var body := "%d × %d m · %s" % [int(r.size.x), int(r.size.y), GameState.fmt_money(game.zone_cost(tool, r))]
	body += "\n" + (why if why != "" else "Klicke die gegenüberliegende Ecke. Spätere Bereiche liegen über früheren.")
	info.emit(title, body, 1 if why == "" else 2)


func _refresh_item() -> void:
	var def: Dictionary = Catalog.ITEMS[tool]
	var s: Vector2 = def["size"]
	var title := String(def["name"]) + " setzen"
	var head := "%s · %s × %s m" % [GameState.fmt_money(int(def["cost"])), _num(s.x), _num(s.y)]
	if not has_hover or ghost == null:
		info.emit(title, head, 0)
		return
	ghost.visible = true
	ghost.position = hover + Vector3(0, _lift(), 0)
	ghost.rotation.y = float(rot) * PI * 0.5
	reason = game.can_place(tool, hover, rot)
	_paint(ghost, mat_ok if reason == "" else mat_bad)
	var body := head + _supply_text(def) + "\nR dreht um 90 Grad"
	if snap_kind == "bucht":
		body += "\nRastet am Straßenrand ein, davor entsteht eine Haltebucht"
	if reason != "":
		body += "\n" + reason
	info.emit(title, body, 1 if reason == "" else 2)


## Vorschau des Raums: Boden, neue Wände, Tür, Kosten.
func _refresh_room() -> void:
	var title := "Raum anlegen"
	if has_hover:
		_marker(hover, 1.0)
	for p: Vector3 in points:
		_marker(p, 1.4)
	var zone_txt := "ohne Bereich" if room_zone == "" else Catalog.label(room_zone)
	if points.is_empty() or not has_hover:
		info.emit(title, "Ziehe ein Rechteck in einer Halle auf (oder klicke zwei Ecken). Wände entstehen ringsum, außer an der Außenwand und an vorhandenen Wänden, dazu eine Tür.\nAuf der %s · %s" % [game.floor_name(game.view_floor), zone_txt], 0)
		steps.emit("Erste Ecke drücken und ziehen")
		hint.emit("")
		return
	var r := room_rect(points[0], hover)
	var why := game.room_problem(r)
	var bm := BoxMesh.new()
	bm.size = Vector3(maxf(r.size.x, 0.2), 0.2, maxf(r.size.y, 0.2))
	preview.mesh = bm
	preview.position = Vector3(r.get_center().x, _lift() + 0.15, r.get_center().y)
	preview.material_override = mat_ok if why == "" else mat_bad
	var edges := game.room_edges(r) if why == "" else []
	for e: Array in edges:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var mi := MeshInstance3D.new()
		var wb := BoxMesh.new()
		var d := b - a
		wb.size = Vector3(0.35, 2.4, d.length())
		mi.mesh = wb
		mi.material_override = mat_ok
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.basis = Basis.looking_at(d.normalized(), Vector3.UP)
		mi.position = (a + b) * 0.5 + Vector3(0, 1.2, 0)
		marker_root.add_child(mi)
	var cost := game.room_cost(r, room_zone) if why == "" else 0
	var tip := "%d × %d m" % [int(r.size.x), int(r.size.y)]
	if why == "":
		tip += " · %d Wände · %s" % [edges.size(), GameState.fmt_money(cost)]
		info.emit(title, "%s, %s, Tür: %s\nLoslassen oder Klick baut den Raum" % [tip, zone_txt, String(GameState.OPTION_TEXT.get(room_door, room_door))], 1)
		steps.emit("Loslassen baut den Raum · Rechtsklick bricht ab")
	else:
		tip += " · " + why
		info.emit(title, why, 2)
		steps.emit(why)
	hint.emit(tip)


func _refresh_demolish() -> void:
	_clear_highlight()
	if area_from != Vector3.INF and has_hover:
		var r := _area_rect()
		var bm := BoxMesh.new()
		bm.size = Vector3(maxf(r.size.x, 0.2), 0.3, maxf(r.size.y, 0.2))
		preview.mesh = bm
		preview.position = Vector3(r.get_center().x, float(game.view_floor if game.interior_view else 0) * Catalog.FLOOR_H + 0.2, r.get_center().y)
		preview.material_override = mat_bad
		var vic := game.area_victims(r)
		info.emit("Fläche abreißen", "%d Teile im Rechteck · Loslassen reißt ab, Rechtsklick bricht ab" % vic.size(), 2)
		hint.emit("%d Teile" % vic.size())
		return
	if not has_hover:
		info.emit("Abriss", "Klicke auf ein Gebäude oder einen Weg, oder ziehe auf freiem Boden eine Fläche auf.", 0)
		return
	target = game.pick(hover)
	if target.is_empty():
		info.emit("Abriss", "Klicke auf ein Gebäude oder einen Weg, oder drücke hier und ziehe eine Fläche auf.\nDu bekommst die Hälfte der Baukosten zurück.", 0)
		return
	_highlight(target)
	var cost: int = target["cost"]
	info.emit("Abriss", "%s abreißen\nErstattung %s" % [game.describe(target), GameState.fmt_money(cost / 2)], 2)


## Ersetzen: Weg unter dem Zeiger, der sich in den gewählten Typ umbauen lässt (oder leer).
func _replace_target() -> Dictionary:
	if not has_hover:
		return {}
	var rec := game.pick(hover)
	if rec.get("type", "") != "line" or not GameState.UPGRADE_FAMILY.has(String(rec["kind"])):
		return {}
	return rec


func _replace_flip(rec: Dictionary) -> bool:
	if tool != "einbahn" or String(rec["kind"]) != "einbahn":
		return false
	if String(rec.get("side", "")) != game.road_side:
		return bool(rec.get("flip", false))   # nur Querschnitt ändern
	return not bool(rec.get("flip", false))


func _replace_side() -> String:
	return game.road_side if Catalog.has_sides(tool) else ""


## Raum-Werkzeug: Bereich und Türart wählen.
func set_room_option(key: String, value: String) -> void:
	if key == "bereich":
		room_zone = value
	elif key == "tuer":
		room_door = value
	elif key == "raumart":
		room_kind = value
	_refresh()


## Querschnitt neuer Straßen wählen (Fahrbahn, Gehweg, Radweg, Allee).
func set_side(side: String) -> void:
	if not Catalog.SIDES.has(side):
		return
	game.road_side = side
	side_changed.emit(side)
	_refresh()


func cycle_side() -> void:
	if Catalog.has_sides(tool):
		var order: Array = Catalog.SIDE_ORDER
		set_side(order[(order.find(game.road_side) + 1) % order.size()])


func _refresh_replace() -> void:
	_clear_highlight()
	var title := "Ersetzen: " + Catalog.label(tool)
	var rec := _replace_target()
	if rec.is_empty():
		info.emit(title, "Fahre über einen bestehenden Weg und klicke: Er wird an Ort und Stelle zu %s umgebaut. Kreuzungen und Anschlüsse bleiben.\nEine Einbahnstraße mit dem Einbahn-Werkzeug dreht die Richtung um." % Catalog.label(tool), 0)
		steps.emit("Auf einen Weg klicken, um ihn umzubauen")
		hint.emit("")
		return
	var flip := _replace_flip(rec)
	var why := game.can_upgrade(rec, tool, flip, _replace_side())
	target = rec
	_highlight(rec, mat_upgrade if why == "" else mat_overlay)
	var cost := game.upgrade_cost(rec, tool, _replace_side())
	var what := "%s → %s" % [_road_name(rec), Catalog.label(tool) + (" (umgedreht)" if flip else "") + _side_suffix(_replace_side())]
	var price := ("Kosten " + GameState.fmt_money(cost)) if cost > 0 else ("Erstattung " + GameState.fmt_money(-cost) if cost < 0 else "kostenlos")
	if why == "":
		info.emit(title, what + "\n" + price + "\nKlick: umbauen", 1)
		hint.emit(what + " · " + price)
		steps.emit("Klick baut um · Rechtsklick: anderes Werkzeug")
	else:
		info.emit(title, what + "\n" + why, 2)
		hint.emit(why)
		steps.emit(why)


func _click_replace() -> void:
	var rec := _replace_target()
	if rec.is_empty():
		game.toast.emit("Klicke auf eine Straße oder einen Rollweg")
		return
	_clear_highlight()
	var flip := _replace_flip(rec)
	var before := _road_name(rec)
	var why := game.upgrade_line(rec, tool, flip, _replace_side())
	game.toast.emit(why if why != "" else "%s → %s" % [before, _road_name(rec)])
	_refresh()


func _road_name(rec: Dictionary) -> String:
	var kind: String = rec["kind"]
	var name := Catalog.label(kind)
	if kind == "einbahn" and bool(rec.get("flip", false)):
		name += " (umgedreht)"
	return name + _side_suffix(String(rec.get("side", "")))


static func _side_suffix(side: String) -> String:
	if not Catalog.SIDES.has(side) or side == "gehweg":
		return ""
	return ", " + String(Catalog.SIDES[side]["short"])


func _supply_text(def: Dictionary) -> String:
	var parts := []
	var needs: Dictionary = def.get("needs", {})
	if needs.has("strom"):
		parts.append("%d kW Strom" % int(needs["strom"]))
	if needs.has("wasser"):
		parts.append("%d m³/h Wasser" % int(needs["wasser"]))
	if needs.has("waerme"):
		parts.append("%d kW Wärme" % int(needs["waerme"]))
	var out := ""
	if not parts.is_empty():
		out += "\nBraucht " + " und ".join(parts)
	var sup: Dictionary = def.get("supply", {})
	if sup.has("strom"):
		out += "\nLiefert %d kW Strom" % int(sup["strom"])
	if sup.has("wasser"):
		out += "\nLiefert %d m³/h Wasser" % int(sup["wasser"])
	if sup.has("waerme"):
		out += "\nLiefert %d kW Wärme" % int(sup["waerme"])
	if bool(def.get("inside", false)) and not parts.is_empty():
		out += " (über die Halle)"
	if def.has("cap"):
		out += "\nSchafft %d Passagiere pro Stunde" % int(def["cap"])
	return out


func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else str(snappedf(v, 0.1)).replace(".", ",")


func _marker(p: Vector3, size: float, m: Material = null) -> void:
	# flache Scheibe mit Rand statt Würfel
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = size * 0.5
	cm.bottom_radius = size * 0.5
	cm.height = 0.12
	cm.radial_segments = 24
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m if m != null else mat_mark
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = p + Vector3(0, 0.42, 0)
	marker_root.add_child(mi)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = size * 0.62
	tm.outer_radius = size * 0.78
	tm.rings = 24
	tm.ring_segments = 6
	ring.mesh = tm
	ring.scale = Vector3(1.0, 0.25, 1.0)
	ring.material_override = mi.material_override
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = p + Vector3(0, 0.45, 0)
	marker_root.add_child(ring)


func _paint(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_paint(c, m)


func _overlay(n: Node, m: Material) -> void:
	if n is MeshInstance3D:
		(n as MeshInstance3D).material_overlay = m
	for c in n.get_children():
		_overlay(c, m)


func _highlight(rec: Dictionary, mat: Material = null) -> void:
	var node: Variant = rec["node"]
	if is_instance_valid(node):
		_overlay(node as Node, mat if mat != null else mat_overlay)


func _clear_highlight() -> void:
	if not target.is_empty():
		var node: Variant = target["node"]
		if is_instance_valid(node):
			_overlay(node as Node, null)
	target = {}


# ---------------------------------------------------------------- Blaupause (Kopieren und Einfügen)

var clip: Dictionary = {}     # kopierter Bereich: halls, lines, items, size, origin


## Erster Klick: Ecke, zweiter Klick: Bereich kopieren; danach setzt jeder Klick eine Kopie ein.
func _click_copy() -> void:
	if not clip.is_empty() and points.is_empty():
		_paste(hover)
		return
	if points.is_empty():
		points.append(hover)
		return
	var r := GameState.hall_rect(points[0], hover)
	points.clear()
	clip = _capture(r)
	var n := (clip["halls"] as Array).size() + (clip["lines"] as Array).size() + (clip["items"] as Array).size()
	if n == 0:
		clip = {}
		game.toast.emit("Im Bereich liegt nichts zum Kopieren")
	else:
		game.toast.emit("Blaupause mit %d Teilen – zum Einfügen klicken, Rechtsklick verwirft sie" % n)


func _capture(r: Rect2) -> Dictionary:
	var c := r.get_center()
	var origin := Vector3(c.x, 0, c.y)
	var halls := []
	var hall_ids := {}
	for h: Dictionary in game.items_of("halle"):
		var hr: Rect2 = h["rect"]
		if r.encloses(hr):
			hall_ids[h["node"]] = true
			var inside := []
			for it: Dictionary in game.inside_of(h):
				var e := {"id": it["id"], "pos": (it["pos"] as Vector3) - origin, "rot": it["rot"], "opts": it.get("opts", {}).duplicate(),
					"floor": GameState.floor_of(it)}
				if Catalog.is_zone(String(it["id"])):
					e["size"] = (it["rect"] as Rect2).size
				inside.append(e)
			var walls := []
			for l: Dictionary in game.walls_of(h):
				var pts := []
				for q: Vector3 in l["points"]:
					pts.append(q - origin)
				walls.append({"kind": l["kind"], "points": pts, "floor": GameState.floor_of(l)})
			halls.append({"rect": Rect2(hr.position - Vector2(origin.x, origin.z), hr.size), "opts": h.get("opts", {}).duplicate(), "inside": inside, "walls": walls})
	var lines := []
	for l: Dictionary in game.lines:
		if Catalog.is_wall(String(l["kind"])):
			continue
		var all_in := true
		for q: Vector3 in (l["samples"] as PackedVector3Array):
			if not r.has_point(Vector2(q.x, q.z)):
				all_in = false
				break
		if all_in:
			var pts := []
			for q: Vector3 in l["points"]:
				pts.append(q - origin)
			lines.append({"kind": l["kind"], "points": pts, "side": String(l.get("side", ""))})
	var items := []
	for it: Dictionary in game.items:
		var id := String(it["id"])
		if id == "halle" or Catalog.is_inside(id):
			continue
		var p: Vector3 = it["pos"]
		if r.has_point(Vector2(p.x, p.z)):
			items.append({"id": id, "pos": p - origin, "rot": it["rot"], "opts": it.get("opts", {}).duplicate()})
	return {"halls": halls, "lines": lines, "items": items, "size": r.size, "origin": origin}


func _paste(at: Vector3) -> void:
	var ok := 0
	var total := 0
	var money0 := game.money
	var old_floor := game.view_floor
	for h: Dictionary in clip["halls"]:
		total += 1
		var hr: Rect2 = h["rect"]
		var nr := Rect2(hr.position + Vector2(at.x, at.z), hr.size)
		if game.can_place_hall(nr) != "":
			continue
		var rec := game.build_hall(nr, false, h["opts"])
		if rec.is_empty():
			continue
		ok += 1
		for w: Dictionary in h["walls"]:
			total += 1
			game.view_floor = int(w["floor"])
			var pts := []
			for q: Vector3 in w["points"]:
				pts.append(q + at)
			if not game.build_line(String(w["kind"]), pts).is_empty():
				ok += 1
		for e: Dictionary in h["inside"]:
			total += 1
			var pos: Vector3 = (e["pos"] as Vector3) + at
			if Catalog.is_zone(String(e["id"])):
				var sz: Vector2 = e["size"]
				var zr := Rect2(pos.x - sz.x * 0.5, pos.z - sz.y * 0.5, sz.x, sz.y)
				if not game.build_zone(String(e["id"]), zr, false, int(e["floor"])).is_empty():
					ok += 1
				continue
			game.view_floor = int(e["floor"])
			if game.can_place(String(e["id"]), pos, int(e["rot"])) == "":
				if not game.build_item(String(e["id"]), pos, int(e["rot"]), false, e["opts"], int(e["floor"])).is_empty():
					ok += 1
	game.view_floor = old_floor
	for l: Dictionary in clip["lines"]:
		total += 1
		var pts := []
		for q: Vector3 in l["points"]:
			pts.append(q + at)
		if not game.build_line(String(l["kind"]), pts, false, false, String(l.get("side", ""))).is_empty():
			ok += 1
	for e: Dictionary in clip["items"]:
		total += 1
		var pos: Vector3 = (e["pos"] as Vector3) + at
		if game.can_place(String(e["id"]), pos, int(e["rot"])) != "":
			continue
		if not game.build_item(String(e["id"]), pos, int(e["rot"]), false, e["opts"]).is_empty():
			ok += 1
	game.toast.emit("Blaupause eingefügt: %d von %d Teilen für %s" % [ok, total, GameState.fmt_money(money0 - game.money)])


func _refresh_copy() -> void:
	if not has_hover:
		return
	var corners := []
	if clip.is_empty():
		if points.is_empty():
			info.emit("Blaupause", "Klicke zwei Ecken eines Bereichs: Gebäude, Wege und ganze Terminalhallen darin werden kopiert. Danach setzt jeder Klick eine Kopie (zum normalen Preis). Rechtsklick verwirft die Blaupause.", 0)
			_marker(hover, 2.0, mat_mark)
			return
		var r := GameState.hall_rect(points[0], hover)
		corners = [Vector3(r.position.x, 0, r.position.y), Vector3(r.end.x, 0, r.position.y), Vector3(r.end.x, 0, r.end.y), Vector3(r.position.x, 0, r.end.y)]
		info.emit("Blaupause", "Bereich %d × %d m: zweite Ecke klicken" % [roundi(r.size.x), roundi(r.size.y)], 1)
	else:
		var sz: Vector2 = clip["size"]
		var h := Vector3(sz.x * 0.5, 0, sz.y * 0.5)
		corners = [hover - h, hover + Vector3(h.x, 0, -h.z), hover + h, hover + Vector3(-h.x, 0, h.z)]
		var n := (clip["halls"] as Array).size() + (clip["lines"] as Array).size() + (clip["items"] as Array).size()
		info.emit("Blaupause einfügen", "%d Teile, %d × %d m. Klick setzt eine Kopie, Rechtsklick verwirft die Blaupause." % [n, roundi(sz.x), roundi(sz.y)], 1)
	for i in range(4):
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var steps := maxi(1, int(a.distance_to(b) / 6.0))
		for j in range(steps + 1):
			_marker(a.lerp(b, float(j) / float(steps)), 1.4, mat_snap)