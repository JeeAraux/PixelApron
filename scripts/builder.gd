extends Node
## Bauwerkzeug: Wege mit Kurven ziehen, Gebäude und Deko setzen, abreißen.
## Bekommt Bodenpunkte von main.gd und zeigt eine Vorschau in der 3D-Welt.

signal info(title: String, body: String, state: int)  # state: 0 neutral, 1 gut, 2 Problem
signal tool_changed(id: String)
signal inspect_requested(p: Vector3)

const Catalog = preload("res://scripts/catalog.gd")
const Spline = preload("res://scripts/spline.gd")
const Factory = preload("res://scripts/factory.gd")
const GameState = preload("res://scripts/game_state.gd")

const SNAP_DIST := 7.0

var game: GameState
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


func setup(g: GameState, r: Node3D) -> void:
	game = g
	root3d = r
	mat_ok = _tmat(Color(0.38, 0.86, 0.95, 0.55))
	mat_bad = _tmat(Color(1.0, 0.32, 0.25, 0.55))
	mat_mark = _tmat(Color(0.92, 0.98, 1.0, 0.95))
	mat_overlay = _tmat(Color(1.0, 0.25, 0.2, 0.45))
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


func is_drawing() -> bool:
	return (is_line_tool() or is_rect_tool()) and not points.is_empty()


func set_tool(id: String) -> void:
	points.clear()
	_clear_highlight()
	if ghost != null:
		ghost.queue_free()
		ghost = null
	tool = id
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
	if has_hover and s.is_equal_approx(hover) and tool != "abriss":
		return
	hover = s
	has_hover = true
	_refresh()


func on_click(p: Vector3) -> void:
	raw_hover = p
	hover = _snap(p)
	has_hover = true
	if is_rect_tool():
		if points.is_empty():
			points.append(hover)
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
	elif is_line_tool():
		if not points.is_empty():
			var last: Vector3 = points[points.size() - 1]
			if last.distance_to(hover) < 1.0:
				return
		points.append(hover)
		var def: Dictionary = Catalog.LINES[tool]
		if bool(def["straight"]) and points.size() >= 2:
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
	elif tool == "abriss":
		_refresh()
		if not target.is_empty():
			var t := target
			_clear_highlight()
			game.toast.emit(game.describe(t) + " abgerissen")
			game.remove(t, 0.5)
			_refresh()


func on_right() -> void:
	if is_drawing():
		if points.size() >= 2:
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
	points.clear()
	_refresh()


func finish() -> void:
	if not is_line_tool() or points.size() < 2:
		return
	var st := _line_state(points)
	if bool(st["ok"]):
		game.build_line(tool, points)
		points.clear()
	else:
		game.toast.emit(String(st["why"]))
		var def: Dictionary = Catalog.LINES[tool]
		if bool(def["straight"]):
			points.clear()
	_refresh()


# ---------------------------------------------------------------- Raster und Einrasten

func _snap(p: Vector3) -> Vector3:
	if is_rect_tool():
		var g: float = Catalog.ITEMS[tool]["grid"]
		return Vector3(snappedf(p.x, g), 0.0, snappedf(p.z, g))
	if is_line_tool():
		var best := SNAP_DIST
		var found := false
		var q := Vector3.ZERO
		for e: Vector3 in game.endpoints(Catalog.utility_of(tool) != ""):
			var d := Vector2(e.x - p.x, e.z - p.z).length()
			if d < best:
				best = d
				q = e
				found = true
		if found:
			return Vector3(q.x, 0.0, q.z)
		return Vector3(roundf(p.x), 0.0, roundf(p.z))
	if is_item_tool():
		var g: float = Catalog.ITEMS[tool]["grid"]
		var s: Vector2 = Catalog.ITEMS[tool]["size"]
		if rot % 2 == 1:
			s = Vector2(s.y, s.x)
		var ox := fmod(s.x * 0.5, g)
		var oz := fmod(s.y * 0.5, g)
		return Vector3(snappedf(p.x - ox, g) + ox, 0.0, snappedf(p.z - oz, g) + oz)
	return Vector3(p.x, 0.0, p.z)


# ---------------------------------------------------------------- Vorschau

func _line_state(pts: Array) -> Dictionary:
	var def: Dictionary = Catalog.LINES[tool]
	var straight: bool = def["straight"]
	var samples := Spline.path(pts, straight)
	var length := Spline.length(samples)
	var minr := INF if straight else Spline.min_radius(samples)
	var need: float = def["min_r"]
	var min_len: float = def["min_len"]
	var cost := game.line_cost(tool, samples)
	var why := ""
	if Catalog.is_wall(tool) and pts.size() >= 2:
		why = game.can_place_wall(pts[0], pts[pts.size() - 1])
	if why != "":
		pass
	elif length < min_len:
		why = "Zu kurz: mindestens %d m" % int(min_len)
	elif minr < need:
		why = "Kurve zu eng: Radius %d m, nötig sind %d m" % [int(minr), int(need)]
	elif cost > game.money:
		why = "Nicht genug Geld"
	return {"ok": why == "", "why": why, "samples": samples, "length": length, "minr": minr, "cost": cost}


func _refresh() -> void:
	preview.mesh = null
	preview.position = Vector3.ZERO
	for c in marker_root.get_children():
		c.queue_free()
	if ghost != null:
		ghost.visible = false
	if tool == "":
		info.emit("Ansehen", "Klicke auf ein Gebäude, einen Weg oder ein Flugzeug für Details. Unten wählst du ein Bauwerkzeug.", 0)
	elif is_rect_tool():
		_refresh_rect()
	elif is_line_tool():
		_refresh_line()
	elif is_item_tool():
		_refresh_item()
	elif tool == "abriss":
		_refresh_demolish()


func _refresh_line() -> void:
	var def: Dictionary = Catalog.LINES[tool]
	var title := String(def["name"]) + " bauen"
	var per_m := GameState.fmt_money(int(def["cost_m"])) + " pro Meter"
	for p: Vector3 in points:
		_marker(p, 1.4)
	var pts := points.duplicate()
	if has_hover:
		_marker(hover, 0.9)
		var add_hover := pts.is_empty()
		if not add_hover:
			var last: Vector3 = pts[pts.size() - 1]
			add_hover = last.distance_to(hover) > 0.5
		if add_hover:
			pts.append(hover)
	if pts.size() < 2:
		var how := "Klicke Start- und Endpunkt." if bool(def["straight"]) else "Klicke den Startpunkt, dann weitere Punkte für Kurven."
		if Catalog.is_wall(tool):
			how = "Klicke Anfang und Ende der Wand, innerhalb einer Halle. Endpunkte rasten ein."
		info.emit(title, how + "\n" + per_m, 0)
		return
	var st := _line_state(pts)
	var w: float = def["width"]
	var y: float = def["y"]
	if Catalog.is_wall(tool):
		w = 0.8
		y = 1.3
	preview.mesh = Spline.ribbon(st["samples"], w, y + 0.25)
	preview.material_override = mat_ok if bool(st["ok"]) else mat_bad
	var body := "Länge %d m · %s" % [int(st["length"]), GameState.fmt_money(int(st["cost"]))]
	var minr: float = st["minr"]
	if minr < 100000.0:
		body += "\nEngster Radius %d m (nötig %d m)" % [int(minr), int(def["min_r"])]
	if not bool(st["ok"]):
		body += "\n" + String(st["why"])
	elif not bool(def["straight"]):
		body += "\nRechtsklick oder Enter: fertig"
	info.emit(title, body, 1 if bool(st["ok"]) else 2)


func _refresh_rect() -> void:
	var def: Dictionary = Catalog.ITEMS[tool]
	var title := String(def["name"]) + " bauen"
	var per := "%s pro m²" % GameState.fmt_money(int(def["cost_m2"]))
	if has_hover:
		_marker(hover, 1.2)
	for p: Vector3 in points:
		_marker(p, 1.6)
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


func _refresh_item() -> void:
	var def: Dictionary = Catalog.ITEMS[tool]
	var s: Vector2 = def["size"]
	var title := String(def["name"]) + " setzen"
	var head := "%s · %s × %s m" % [GameState.fmt_money(int(def["cost"])), _num(s.x), _num(s.y)]
	if not has_hover or ghost == null:
		info.emit(title, head, 0)
		return
	ghost.visible = true
	ghost.position = hover
	ghost.rotation.y = float(rot) * PI * 0.5
	reason = game.can_place(tool, hover, rot)
	_paint(ghost, mat_ok if reason == "" else mat_bad)
	var body := head + _supply_text(def) + "\nR dreht um 90 Grad"
	if reason != "":
		body += "\n" + reason
	info.emit(title, body, 1 if reason == "" else 2)


func _refresh_demolish() -> void:
	_clear_highlight()
	if not has_hover:
		info.emit("Abriss", "Klicke auf ein Gebäude oder einen Weg.", 0)
		return
	target = game.pick(hover)
	if target.is_empty():
		info.emit("Abriss", "Klicke auf ein Gebäude oder einen Weg.\nDu bekommst die Hälfte der Baukosten zurück.", 0)
		return
	_highlight(target)
	var cost: int = target["cost"]
	info.emit("Abriss", "%s abreißen\nErstattung %s" % [game.describe(target), GameState.fmt_money(cost / 2)], 2)


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


func _marker(p: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size, size, size)
	mi.mesh = bm
	mi.material_override = mat_mark
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = p + Vector3(0, size * 0.5 + 0.3, 0)
	marker_root.add_child(mi)


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


func _highlight(rec: Dictionary) -> void:
	var node: Variant = rec["node"]
	if is_instance_valid(node):
		_overlay(node as Node, mat_overlay)


func _clear_highlight() -> void:
	if not target.is_empty():
		var node: Variant = target["node"]
		if is_instance_valid(node):
			_overlay(node as Node, null)
	target = {}
