extends CanvasLayer
## Oberfläche: Kopfzeile (Zeit, Tempo, Zufriedenheit, Geld, Ansichten, Menü), Infofeld links,
## Flugplan rechts, das Baumenü unten und das Spielmenü mit Einstellungen (Esc).

signal tool_selected(id: String)
signal speed_selected(index: int)
signal utility_toggled(on: bool)
signal save_requested
signal load_requested
signal new_requested
signal undo_requested
signal interior_toggled(on: bool)
signal menu_opened(open: bool)
signal quit_requested
signal setting_changed(key: String, value: Variant)
signal restart_requested
signal downloads_requested
signal map_requested
signal floor_step(dir: int)
signal option_changed(key: String, dir: int)
signal draw_mode_selected(mode: String)
signal snap_toggled(on: bool)
signal clearance_requested(id: int)
signal atc_toggled(on: bool)
signal contract_requested(code: String)
signal scenario_requested(key: String)
signal tutorial_requested
signal spot_requested(pos: Vector3)

const Catalog = preload("res://scripts/catalog.gd")
const GameState = preload("res://scripts/game_state.gd")
const Settings = preload("res://scripts/settings.gd")
const Ops = preload("res://scripts/operations.gd")

const C_PANEL := Color(0.083, 0.075, 0.055, 0.88)
const C_GOLD := Color(0.73, 0.65, 0.42)
const C_TEXT := Color(0.96, 0.91, 0.74)
const C_DIM := Color(0.76, 0.72, 0.58)
const C_FAINT := Color(0.60, 0.56, 0.45)
const C_OK := Color(0.66, 0.85, 0.56)
const C_BAD := Color(1.0, 0.55, 0.45)
const C_PRICE := Color(0.94, 0.78, 0.36)
const CARD_W := 94.0
const RECENT_MAX := 5

var root: Control
var money_label: Label
var day_label: Label
var sat_label: Label
var sat_holder: Control
var clock_label: Label
var info_title: Label
var info_body: Label
var toast_label: Label
var toast_tween: Tween
var flight_status: Label
var flight_rows: VBoxContainer
var flight_done: Label
var utility_button: Button
var interior_button: Button
var help_label: Label
var menu_layer: Control
var menu_page: Control
var settings_page: Control
var new_button: Button
var setting_controls: Dictionary = {}
var subtitle_label: Label
var update_label: Label
var restart_button: Button
var download_button: Button
var tool_buttons: Dictionary = {}
var thumb_rects: Dictionary = {}
var tab_buttons: Dictionary = {}
var tab_pages: Dictionary = {}
var tool_category: Dictionary = {}
var speed_buttons: Array = []
var tool_group := ButtonGroup.new()
var tab_group := ButtonGroup.new()
var speed_group := ButtonGroup.new()
var info_details: Control          # Text und Hilfe im Infofeld (einklappbar)
var info_toggle: Button
var flights_details: Control
var flights_toggle: Button
var build_pages: Control           # Ablage der Bauleiste (einklappbar, das Dock bleibt)
var dock: PanelContainer
var tray: PanelContainer
var tray_title: Label
var chip_box: HFlowContainer
var chip_buttons: Array = []       # [Knopf, Abschnitt]
var search_edit: LineEdit
var search_text := ""
var strip_scroll: ScrollContainer
var strip_row: HBoxContainer
var arrow_l: Button
var arrow_r: Button
var scroll_tween: Tween
var sections: Array = []           # {cat, name, box, ids}
var card_meta: Dictionary = {}     # id -> Suchtext (Name, Abschnitt)
var card_desc: Dictionary = {}     # id -> Beschreibung (wenn der Name nichts findet)
var cat_icons: Dictionary = {}
var thumb_tex: Dictionary = {}
var recent: Array = []
var recent_box: HBoxContainer
var recent_sep: Control
var layout_queued := false
var line_bar: PanelContainer
var line_title: Label
var step_label: Label
var step_text := ""
var snap_button: Button
var modes_shown := false
var current_tool := ""
var top_row: HBoxContainer
var title_box: Control
var view_buttons: Array = []      # [Knopf, langer Text, kurzer Text]
var build_open := true
var current_tab := ""
var map_button: Button
var floor_box: Control
var floor_label: Label
var options_box: VBoxContainer
var mode_box: HBoxContainer
var mode_buttons: Dictionary = {}
var hint_panel: PanelContainer
var hint_label: Label
var ops_ref: Variant = null         # operations.gd (Statistik, Verträge, Szenario)
var ops_window: PanelContainer
var ops_body: VBoxContainer
var ops_tab := "statistik"
var ops_sig := ""
var ops_timer := 0.0
var ops_button: Button
var atc_button: Button
var row_nodes: Dictionary = {}      # Flug-ID -> [Zeile, Code, Strecke, Zeit, Status, Knopf]
var tutorial_panel: PanelContainer
var tutorial_label: Label


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	tool_group.allow_unpress = true
	_build_top()
	_build_info()
	_build_flights()
	_build_menu()
	_build_toast()
	_build_game_menu()
	_build_hint()
	_build_ops()
	_build_tutorial()


## Kleines Schild am Mauszeiger mit Länge, Winkel und Radius beim Wegebau.
func _build_hint() -> void:
	hint_panel = PanelContainer.new()
	hint_panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.055, 0.04, 0.88), Color(0.62, 0.55, 0.36), 1, 5))
	hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_label = _label("", 14, C_TEXT)
	hint_panel.add_child(hint_label)
	hint_panel.visible = false
	root.add_child(hint_panel)


func set_hint(text: String) -> void:
	hint_label.text = text
	hint_panel.visible = text != ""
	hint_panel.reset_size()


func _process(_dt: float) -> void:
	if hint_panel != null and hint_panel.visible:
		var mp := get_viewport().get_mouse_position()
		hint_panel.position = mp + Vector2(22, 18)
	if ops_window != null and ops_window.visible:
		ops_timer -= _dt
		if ops_timer <= 0.0:
			ops_timer = 1.0
			_ops_refresh()
	if tutorial_panel != null and ops_ref != null:
		var tt: String = ops_ref.tutorial_text()
		tutorial_panel.visible = tt != ""
		if tt != "" and tutorial_label.text != tt:
			tutorial_label.text = tt


# ---------------------------------------------------------------- Stil

func _box(bg: Color, border: Color, bw: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_content_margin_all(pad)
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 16
	var panel := _box(C_PANEL, C_GOLD, 3, 12)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 4
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("normal", "Button", _box(Color(0.15, 0.14, 0.10), Color(0.36, 0.32, 0.22), 2, 6))
	th.set_stylebox("hover", "Button", _box(Color(0.21, 0.19, 0.13), Color(0.62, 0.55, 0.36), 2, 6))
	th.set_stylebox("pressed", "Button", _box(Color(0.29, 0.25, 0.12), Color(0.94, 0.76, 0.31), 3, 6))
	th.set_stylebox("hover_pressed", "Button", _box(Color(0.32, 0.28, 0.13), Color(1.0, 0.82, 0.4), 3, 6))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.91, 0.87, 0.78))
	th.set_color("font_hover_color", "Button", C_TEXT)
	th.set_color("font_pressed_color", "Button", Color(1.0, 0.88, 0.54))
	th.set_color("font_hover_pressed_color", "Button", Color(1.0, 0.88, 0.54))
	th.set_font_size("font_size", "Button", 14)
	th.set_color("font_color", "Label", C_TEXT)
	th.set_stylebox("panel", "TooltipPanel", _box(Color(0.06, 0.055, 0.04, 0.97), C_GOLD, 2, 8))
	th.set_color("font_color", "TooltipLabel", C_TEXT)
	th.set_font_size("font_size", "TooltipLabel", 14)
	return th


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, toggle: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 40)
	return b


# ---------------------------------------------------------------- Kopfzeile

func _build_top() -> void:
	var bar := PanelContainer.new()
	bar.anchor_right = 1.0
	var sb := _box(C_PANEL, C_GOLD, 0, 10)
	sb.border_width_bottom = 3
	bar.add_theme_stylebox_override("panel", sb)
	root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	bar.add_child(row)
	top_row = row
	var title := VBoxContainer.new()
	title_box = title
	title.add_theme_constant_override("separation", 0)
	title.add_child(_label("PixelApron", 22, C_TEXT))
	subtitle_label = _label("Flughafen Wiesenfeld", 13, C_DIM)
	title.add_child(subtitle_label)
	row.add_child(title)
	var tsep := VSeparator.new()
	title.set_meta("sep", tsep)
	row.add_child(tsep)
	clock_label = _label("Mo 06:00", 22, C_TEXT)
	clock_label.custom_minimum_size = Vector2(96, 0)
	clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(clock_label)
	var names := ["II", "1×", "2×", "3×"]
	var tips := ["Pause (Leertaste)", "Normal (1)", "Schnell (2)", "Sehr schnell (3)"]
	for i in range(4):
		var b := _button(names[i], true)
		b.custom_minimum_size = Vector2(44, 40)
		b.button_group = speed_group
		b.button_pressed = i == 1
		b.tooltip_text = tips[i]
		b.pressed.connect(func() -> void: speed_selected.emit(i))
		row.add_child(b)
		speed_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var sat_box := VBoxContainer.new()
	sat_box.add_theme_constant_override("separation", 0)
	sat_box.mouse_filter = Control.MOUSE_FILTER_STOP
	sat_label = _label("", 20, C_OK)
	sat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sat_box.add_child(sat_label)
	sat_box.add_child(_label("Zufriedenheit", 12, C_DIM))
	sat_holder = sat_box
	row.add_child(sat_box)
	row.add_child(VSeparator.new())
	var money_box := VBoxContainer.new()
	money_box.add_theme_constant_override("separation", 0)
	money_label = _label("", 22, C_TEXT)
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_box.add_child(money_label)
	day_label = _label("", 12, C_DIM)
	day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_box.add_child(day_label)
	row.add_child(money_box)
	row.add_child(VSeparator.new())
	ops_button = _button("Betrieb", true)
	ops_button.tooltip_text = "Statistik, Airline-Verträge, Szenarien und Lernschritte (F2)"
	ops_button.toggled.connect(func(on: bool) -> void: show_ops(on))
	row.add_child(ops_button)
	map_button = _button("Karte", true)
	map_button.tooltip_text = "Ganze Karte zeigen und zurück (M)"
	map_button.toggled.connect(func(_on: bool) -> void: map_requested.emit())
	row.add_child(map_button)
	view_buttons = [[ops_button, "Betrieb", "Betr."], [map_button, "Karte", "Karte"]]
	utility_button = _button("Leitungen", true)
	utility_button.tooltip_text = "Strom-, Wasser- und Heizleitungen zeigen (L)"
	utility_button.toggled.connect(func(on: bool) -> void: utility_toggled.emit(on))
	row.add_child(utility_button)
	view_buttons.append([utility_button, "Leitungen", "Netz"])
	interior_button = _button("Innenansicht", true)
	interior_button.tooltip_text = "Dächer ausblenden und ins Terminal schauen (I)"
	interior_button.toggled.connect(func(on: bool) -> void: interior_toggled.emit(on))
	row.add_child(interior_button)
	view_buttons.append([interior_button, "Innenansicht", "Innen"])
	# Ebenenwahl (nur in der Innenansicht): Keller, Erdgeschoss, Obergeschosse
	var fb := HBoxContainer.new()
	fb.add_theme_constant_override("separation", 4)
	var down := _button("▼", false)
	down.custom_minimum_size = Vector2(34, 40)
	down.tooltip_text = "Ebene tiefer (Bild ab)"
	down.pressed.connect(func() -> void: floor_step.emit(-1))
	fb.add_child(down)
	floor_label = _label("EG", 16, C_TEXT)
	floor_label.custom_minimum_size = Vector2(44, 0)
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fb.add_child(floor_label)
	var up := _button("▲", false)
	up.custom_minimum_size = Vector2(34, 40)
	up.tooltip_text = "Ebene höher (Bild auf)"
	up.pressed.connect(func() -> void: floor_step.emit(1))
	fb.add_child(up)
	floor_box = fb
	fb.visible = false
	row.add_child(fb)
	var menu_b := _button("Menü", false)
	menu_b.custom_minimum_size = Vector2(76, 40)
	menu_b.tooltip_text = "Speichern, Laden, Einstellungen (Esc)"
	menu_b.pressed.connect(open_menu)
	row.add_child(menu_b)


# ---------------------------------------------------------------- Infofeld

func _build_info() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 80)
	panel.custom_minimum_size = Vector2(360, 0)
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	info_title = _label("Ansehen", 20, C_TEXT)
	info_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info_title)
	info_toggle = _fold_button()
	info_toggle.pressed.connect(func() -> void: _fold(info_details, info_toggle, not info_details.visible))
	head.add_child(info_toggle)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	col.add_child(details)
	info_details = details
	col = details
	info_body = _label("", 15, C_DIM)
	info_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_body.custom_minimum_size = Vector2(336, 0)
	col.add_child(info_body)
	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 4)
	col.add_child(options_box)
	col.add_child(HSeparator.new())
	help_label = _label("Linksklick bauen · Rechtsklick fertig oder abwählen · R drehen · Esc Menü\nWASD oder mittlere Maustaste verschieben · Mausrad zoomen · Q/E drehen\nLeertaste Pause · L Leitungen · I Innenansicht · Strg+Z rückgängig\nWegebau: Tab Zeichenart · G Einrasten · Strg+F Suche · Alt+1…7 Kategorie", 12, C_FAINT)
	help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_label.custom_minimum_size = Vector2(336, 0)
	col.add_child(help_label)
	_fold(info_details, info_toggle, false)


## Kleiner Knopf zum Ein- und Ausklappen eines Felds.
func _fold_button() -> Button:
	var b := _button("–", false)
	b.custom_minimum_size = Vector2(30, 26)
	b.tooltip_text = "Ein- oder ausklappen"
	return b


func _fold(details: Control, b: Button, open: bool) -> void:
	details.visible = open
	b.text = "–" if open else "+"


# ---------------------------------------------------------------- Flugplan

func _build_flights() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -456.0
	panel.offset_right = -16.0
	panel.offset_top = 80.0
	panel.custom_minimum_size = Vector2(440, 0)
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_child(_label("FLUGPLAN", 18, C_TEXT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	flight_done = _label("", 13, C_DIM)
	head.add_child(flight_done)
	atc_button = _button("Lotse", true)
	atc_button.custom_minimum_size = Vector2(58, 26)
	atc_button.tooltip_text = "Lotsenmodus: Landung, Pushback und Start gibst du selbst frei"
	atc_button.toggled.connect(func(on: bool) -> void: atc_toggled.emit(on))
	head.add_child(atc_button)
	flights_toggle = _fold_button()
	flights_toggle.pressed.connect(func() -> void: _fold(flights_details, flights_toggle, not flights_details.visible))
	head.add_child(flights_toggle)
	col.add_child(head)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	col.add_child(details)
	flights_details = details
	flight_status = _label("", 14, C_OK)
	flight_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(flight_status)
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", _box(Color(0.03, 0.03, 0.02, 0.9), Color(0.23, 0.2, 0.14), 2, 8))
	details.add_child(board)
	flight_rows = VBoxContainer.new()
	flight_rows.add_theme_constant_override("separation", 3)
	board.add_child(flight_rows)


func set_flights(rows: Array, status: String, done: int, hint: String = "", wind: String = "") -> void:
	flight_done.text = "Abgefertigt: %d" % done
	if wind != "":
		hint = wind + ("\n" + hint if hint != "" else "")
	if status == "":
		flight_status.text = "Flugbetrieb läuft" + ("\n" + hint if hint != "" else "")
		flight_status.add_theme_color_override("font_color", C_OK if hint == "" else Color(0.94, 0.76, 0.31))
	else:
		flight_status.text = "Keine neuen Flüge: " + status
		flight_status.add_theme_color_override("font_color", C_BAD)
	# Zeilen je Flug behalten und nur aktualisieren, damit die Freigabe-Knöpfe klickbar bleiben
	var seen := {}
	var shown := 0
	for r: Array in rows:
		var fid := int(r[5]) if r.size() > 5 else shown
		shown += 1
		if shown > 8:
			break
		seen[fid] = true
		var e: Array = row_nodes.get(fid, [])
		if e.is_empty() or not is_instance_valid(e[0]):
			e = _flight_row(fid)
			row_nodes[fid] = e
		(e[1] as Label).text = String(r[0])
		(e[2] as Label).text = String(r[2])
		(e[3] as Label).text = String(r[7]) if r.size() > 7 else ""
		(e[3] as Label).add_theme_color_override("font_color", C_BAD if String(e[3].text).contains("+") else C_DIM)
		(e[4] as Label).text = String(r[3])
		(e[4] as Label).add_theme_color_override("font_color", r[4])
		var btxt := String(r[6]) if r.size() > 6 else ""
		(e[5] as Button).visible = btxt != ""
		(e[5] as Button).text = btxt
		(e[0] as Control).tooltip_text = String(r[1])
		flight_rows.move_child(e[0], shown - 1)
	for fid: int in row_nodes.keys():
		if not seen.has(fid):
			var e: Array = row_nodes[fid]
			if is_instance_valid(e[0]):
				(e[0] as Node).queue_free()
			row_nodes.erase(fid)
	var more := rows.size() - 8
	var tail := flight_rows.get_node_or_null("Mehr") as Label
	var empty_l := flight_rows.get_node_or_null("Leer") as Label
	if rows.is_empty():
		if empty_l == null:
			empty_l = _label("Gerade kein Flugzeug unterwegs", 14, C_FAINT)
			empty_l.name = "Leer"
			flight_rows.add_child(empty_l)
	elif empty_l != null:
		empty_l.queue_free()
	if more > 0:
		if tail == null:
			tail = _label("", 13, C_FAINT)
			tail.name = "Mehr"
			flight_rows.add_child(tail)
		tail.text = "… und %d weitere" % more
		flight_rows.move_child(tail, flight_rows.get_child_count() - 1)
	elif tail != null:
		tail.queue_free()


func _flight_row(fid: int) -> Array:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	var code := _label("", 15, Color(0.94, 0.76, 0.31))
	code.custom_minimum_size = Vector2(58, 0)
	line.add_child(code)
	var route := _label("", 14, C_TEXT)
	route.custom_minimum_size = Vector2(104, 0)
	route.clip_text = true
	line.add_child(route)
	var tm := _label("", 12, C_DIM)
	tm.custom_minimum_size = Vector2(70, 0)
	line.add_child(tm)
	var st := _label("", 13, C_TEXT)
	st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	st.clip_text = true
	line.add_child(st)
	var b := _button("", false)
	b.custom_minimum_size = Vector2(0, 24)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", C_OK)
	b.visible = false
	b.pressed.connect(func() -> void: clearance_requested.emit(fid))
	line.add_child(b)
	flight_rows.add_child(line)
	return [line, code, route, tm, st, b]


func set_atc(on: bool) -> void:
	if atc_button != null:
		atc_button.set_pressed_no_signal(on)


# ---------------------------------------------------------------- Baumenü

func _price(id: String) -> String:
	if Catalog.LINES.has(id):
		return "%d €/m" % int(Catalog.LINES[id]["cost_m"])
	if Catalog.ITEMS.has(id):
		if Catalog.ITEMS[id].has("cost_m2"):
			return "%s €/m²" % GameState.fmt_money(int(Catalog.ITEMS[id]["cost_m2"])).trim_suffix(" €")
		return GameState.fmt_short(int(Catalog.ITEMS[id]["cost"]))
	if Catalog.TOOLS.has(id):
		return "Werkzeug"
	return "50 % zurück"


func _tooltip(id: String) -> String:
	var desc := ""
	if Catalog.LINES.has(id):
		desc = String(Catalog.LINES[id].get("desc", ""))
	elif Catalog.ITEMS.has(id):
		desc = String(Catalog.ITEMS[id].get("desc", ""))
	elif Catalog.TOOLS.has(id):
		desc = String(Catalog.TOOLS[id]["desc"])
	else:
		desc = "Gebäude oder Wege abreißen. Du bekommst die Hälfte der Kosten zurück. (Entf)"
	return Catalog.label(id) + " · " + _price(id) + "\n" + desc


func _card(id: String) -> Button:
	var b := _button("", true)
	b.custom_minimum_size = Vector2(CARD_W, 112)
	b.button_group = tool_group
	b.tooltip_text = _tooltip(id)
	b.toggled.connect(_on_tool_toggled.bind(id))
	b.add_theme_stylebox_override("normal", _box(Color(0.13, 0.12, 0.085, 0.92), Color(0.27, 0.24, 0.17), 1, 4))
	b.add_theme_stylebox_override("hover", _box(Color(0.2, 0.18, 0.12), Color(0.7, 0.62, 0.4), 2, 4))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 3
	col.offset_right = -3
	col.offset_top = 4
	col.offset_bottom = -3
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(68, 68)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	thumb_rects[id] = pic
	var title := Catalog.label(id)
	if Catalog.ITEMS.has(id) and Catalog.ITEMS[id].has("short"):
		title = String(Catalog.ITEMS[id]["short"])
	elif Catalog.LINES.has(id) and Catalog.LINES[id].has("short"):
		title = String(Catalog.LINES[id]["short"])
	var name := _label(title, 13 if title.length() <= 11 else 11, C_TEXT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name)
	var price := _label(_price(id), 11, C_PRICE)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(price)
	tool_buttons[id] = b
	return b


## Bauleiste unten, neu aufgebaut:
## - Dock: Kategorien als Bildknöpfe, zuletzt benutzte Bauteile, Blaupause, Rückgängig, Abriss.
## - Ablage darüber: Abschnitte der Kategorie (Sprungmarken), Suche über alle Bauteile und ein
##   waagrecht scrollender Streifen, der nie breiter als der Bildschirm wird (Mausrad, Pfeile).
## - Wegebau-Leiste: Zeichenart, Einrasten und der nächste Schritt, solange ein Weg gewählt ist.
func _build_menu() -> void:
	# Ablage
	tray = PanelContainer.new()
	var tsb := _box(Color(0.075, 0.068, 0.05, 0.93), Color(0.52, 0.46, 0.3), 2, 10)
	tsb.set_corner_radius_all(10)
	tsb.shadow_color = Color(0, 0, 0, 0.4)
	tsb.shadow_size = 6
	tray.add_theme_stylebox_override("panel", tsb)
	root.add_child(tray)
	var tcol := VBoxContainer.new()
	tcol.add_theme_constant_override("separation", 8)
	tray.add_child(tcol)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	tcol.add_child(head)
	tray_title = _label("", 18, C_TEXT)
	tray_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(tray_title)
	chip_box = HFlowContainer.new()
	chip_box.add_theme_constant_override("h_separation", 4)
	chip_box.add_theme_constant_override("v_separation", 4)
	chip_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(chip_box)
	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Suchen …  (Strg+F)"
	search_edit.custom_minimum_size = Vector2(190, 30)
	search_edit.clear_button_enabled = true
	search_edit.add_theme_stylebox_override("normal", _box(Color(0.05, 0.045, 0.035), Color(0.36, 0.32, 0.22), 1, 6))
	search_edit.add_theme_stylebox_override("focus", _box(Color(0.05, 0.045, 0.035), C_GOLD, 2, 6))
	search_edit.add_theme_color_override("font_color", C_TEXT)
	search_edit.add_theme_color_override("font_placeholder_color", C_FAINT)
	search_edit.add_theme_font_size_override("font_size", 14)
	search_edit.text_changed.connect(_apply_search)
	search_edit.text_submitted.connect(_search_pick)
	search_edit.gui_input.connect(_search_input)
	head.add_child(search_edit)
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 4)
	tcol.add_child(strip)
	arrow_l = _arrow("◀", -1)
	strip.add_child(arrow_l)
	strip_scroll = ScrollContainer.new()
	strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip_scroll.custom_minimum_size = Vector2(400, 134)
	strip_scroll.gui_input.connect(_strip_input)
	strip_scroll.get_h_scroll_bar().value_changed.connect(func(_v: float) -> void: _update_chips())
	strip.add_child(strip_scroll)
	strip_row = HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 26)
	strip_scroll.add_child(strip_row)
	arrow_r = _arrow("▶", 1)
	strip.add_child(arrow_r)
	build_pages = tray
	for cat: Array in Catalog.CATEGORIES:
		var key: String = cat[0]
		var page := HBoxContainer.new()
		page.add_theme_constant_override("separation", 26)
		page.visible = false
		strip_row.add_child(page)
		tab_pages[key] = page
		var groups: Array = Catalog.GROUPS.get(key, [[String(cat[1]), cat[2]]])
		var placed := {}
		for g: Array in groups:
			for id: String in g[1]:
				placed[id] = true
		var rest := []
		for id: String in cat[2]:
			if not placed.has(id):
				rest.append(id)
		for gi in range(groups.size()):
			var ids: Array = (groups[gi][1] as Array).filter(func(x: String) -> bool: return x in cat[2])
			if gi == groups.size() - 1:
				ids.append_array(rest)
			if ids.is_empty():
				continue
			var sec := VBoxContainer.new()
			sec.add_theme_constant_override("separation", 3)
			page.add_child(sec)
			var gl := _label(String(groups[gi][0]).to_upper(), 11, C_FAINT)
			sec.add_child(gl)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 5)
			sec.add_child(row)
			for id: String in ids:
				row.add_child(_card(id))
				tool_category[id] = key
				var short := String(Catalog.ITEMS[id].get("short", "")) if Catalog.ITEMS.has(id) else ""
				card_meta[id] = (Catalog.label(id) + " " + short + " " + id + " " + String(groups[gi][0])).to_lower()
				card_desc[id] = (String(cat[1]) + " " + _tooltip(id)).to_lower()
			sections.append({"cat": key, "name": String(groups[gi][0]), "box": sec, "ids": ids})
	# Dock
	dock = PanelContainer.new()
	var dsb := _box(Color(0.06, 0.055, 0.04, 0.95), C_GOLD, 2, 6)
	dsb.set_corner_radius_all(14)
	dsb.shadow_color = Color(0, 0, 0, 0.45)
	dsb.shadow_size = 5
	dock.add_theme_stylebox_override("panel", dsb)
	root.add_child(dock)
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 4)
	dock.add_child(drow)
	var n := 0
	for cat: Array in Catalog.CATEGORIES:
		n += 1
		var key: String = cat[0]
		var t := _dock_button(String(cat[1]), true)
		t.button_group = tab_group
		t.tooltip_text = "%s (Alt+%d) · %d Bauteile" % [String(cat[1]), n, (cat[2] as Array).size()]
		t.pressed.connect(_show_tab.bind(key))
		drow.add_child(t)
		tab_buttons[key] = t
		cat_icons[key] = t.get_meta("icon")
	drow.add_child(_dock_sep())
	recent_box = HBoxContainer.new()
	recent_box.add_theme_constant_override("separation", 3)
	recent_box.tooltip_text = "Zuletzt benutzt"
	drow.add_child(recent_box)
	recent_sep = _dock_sep()
	drow.add_child(recent_sep)
	var copy := _dock_button("Blaupause", true)
	copy.button_group = tool_group
	copy.tooltip_text = _tooltip("kopieren")
	copy.toggled.connect(_on_tool_toggled.bind("kopieren"))
	drow.add_child(copy)
	tool_buttons["kopieren"] = copy
	cat_icons["_kopieren"] = copy.get_meta("icon")
	var undo := _dock_button("Zurück", false, "↶", C_TEXT)
	undo.tooltip_text = "Letzten Bau zurücknehmen, volle Erstattung (Strg+Z)"
	undo.pressed.connect(func() -> void: undo_requested.emit())
	drow.add_child(undo)
	var demolish := _dock_button("Abriss", true, "✕", C_BAD)
	demolish.button_group = tool_group
	demolish.tooltip_text = _tooltip("abriss")
	demolish.add_theme_stylebox_override("pressed", _box(Color(0.3, 0.1, 0.08), C_BAD, 2, 4))
	demolish.add_theme_stylebox_override("hover_pressed", _box(Color(0.34, 0.12, 0.09), C_BAD, 2, 4))
	demolish.toggled.connect(_on_tool_toggled.bind("abriss"))
	drow.add_child(demolish)
	tool_buttons["abriss"] = demolish
	var fold := _button("▾", true)
	fold.custom_minimum_size = Vector2(26, 58)
	fold.add_theme_stylebox_override("pressed", fold.get_theme_stylebox("normal"))
	fold.add_theme_stylebox_override("hover_pressed", fold.get_theme_stylebox("hover"))
	fold.tooltip_text = "Ablage ein- und ausklappen (B). Ein Klick auf die offene Kategorie klappt auch zu."
	fold.button_pressed = true
	fold.toggled.connect(func(on: bool) -> void: set_build_open(on))
	drow.add_child(fold)
	tab_buttons["_fold"] = fold
	_build_line_bar()
	get_viewport().size_changed.connect(_queue_layout)
	var first: String = Catalog.CATEGORIES[0][0]
	(tab_buttons[first] as Button).set_pressed_no_signal(true)
	_show_tab(first, false)


## Knopf im Dock: Bild oben, Name darunter.
func _dock_button(text: String, toggle: bool, glyph: String = "", gcol: Color = C_TEXT) -> Button:
	var b := _button("", toggle)
	b.custom_minimum_size = Vector2(70, 58)
	b.add_theme_stylebox_override("normal", _box(Color(0.1, 0.09, 0.065, 0.0), Color(0, 0, 0, 0), 0, 4))
	b.add_theme_stylebox_override("hover", _box(Color(0.2, 0.18, 0.12), Color(0.5, 0.45, 0.3), 1, 4))
	var pb := _box(Color(0.27, 0.23, 0.11), Color(0.94, 0.76, 0.31), 0, 4)
	pb.border_width_bottom = 3
	pb.set_corner_radius_all(8)
	b.add_theme_stylebox_override("pressed", pb)
	b.add_theme_stylebox_override("hover_pressed", pb)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 3
	col.offset_bottom = -3
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	if glyph != "":
		var g := _label(glyph, 24, gcol)
		g.custom_minimum_size = Vector2(36, 36)
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		g.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		col.add_child(g)
	else:
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(36, 36)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(pic)
		b.set_meta("icon", pic)
	var l := _label(text, 11, C_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return b


func _dock_sep() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.45, 0.4, 0.27, 0.6)
	c.custom_minimum_size = Vector2(1, 44)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _arrow(text: String, dir: int) -> Button:
	var b := _button(text, false)
	b.custom_minimum_size = Vector2(28, 134)
	b.add_theme_stylebox_override("normal", _box(Color(0.1, 0.09, 0.065), Color(0.3, 0.27, 0.19), 1, 2))
	b.pressed.connect(func() -> void: _scroll_by(float(dir) * strip_scroll.size.x * 0.8))
	return b


func _scroll_by(dx: float) -> void:
	var bar := strip_scroll.get_h_scroll_bar()
	var goal := clampf(float(strip_scroll.scroll_horizontal) + dx, 0.0, maxf(0.0, bar.max_value - bar.page))
	_scroll_to(goal)


func _scroll_to(x: float) -> void:
	if scroll_tween != null:
		scroll_tween.kill()
	scroll_tween = create_tween()
	scroll_tween.tween_property(strip_scroll, "scroll_horizontal", int(x), 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Mausrad über dem Streifen blättert waagrecht.
func _strip_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			_scroll_by(-CARD_W * 2.0)
			strip_scroll.accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN or mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			_scroll_by(CARD_W * 2.0)
			strip_scroll.accept_event()


## Sprungmarken der gezeigten Kategorie neu anlegen.
func _rebuild_chips() -> void:
	for c in chip_box.get_children():
		c.queue_free()
	chip_buttons.clear()
	if search_text != "":
		return
	var mine := sections.filter(func(s: Dictionary) -> bool: return s["cat"] == current_tab)
	if mine.size() < 2:
		return
	for s: Dictionary in mine:
		var c := _button("%s  %d" % [String(s["name"]), (s["ids"] as Array).size()], true)
		c.custom_minimum_size = Vector2(0, 28)
		c.add_theme_font_size_override("font_size", 13)
		var cn := _box(Color(0.12, 0.11, 0.08), Color(0.3, 0.27, 0.19), 1, 5)
		cn.set_corner_radius_all(13)
		cn.content_margin_left = 12
		cn.content_margin_right = 12
		c.add_theme_stylebox_override("normal", cn)
		var cp := _box(Color(0.3, 0.26, 0.12), C_GOLD, 1, 5)
		cp.set_corner_radius_all(13)
		cp.content_margin_left = 12
		cp.content_margin_right = 12
		c.add_theme_stylebox_override("pressed", cp)
		c.add_theme_stylebox_override("hover_pressed", cp)
		var box: Control = s["box"]
		c.pressed.connect(func() -> void: _scroll_to(_section_x(box)))
		chip_box.add_child(c)
		chip_buttons.append([c, box])
	_update_chips()


func _section_x(box: Control) -> float:
	var bar := strip_scroll.get_h_scroll_bar()
	var x := box.global_position.x - strip_row.global_position.x
	return clampf(x, 0.0, maxf(0.0, bar.max_value - bar.page))


## Die Sprungmarke des Abschnitts links im Streifen leuchtet.
func _update_chips() -> void:
	if chip_buttons.is_empty():
		return
	var at := float(strip_scroll.scroll_horizontal) + 30.0
	var bar := strip_scroll.get_h_scroll_bar()
	var active := 0
	var max_scroll := bar.max_value - bar.page
	for i in range(chip_buttons.size()):
		if _section_x(chip_buttons[i][1]) <= at:
			active = i
	if max_scroll < 4.0:
		active = -1   # alles sichtbar: keine Marke hervorheben
	elif float(strip_scroll.scroll_horizontal) >= max_scroll - 2.0:
		active = chip_buttons.size() - 1
	for i in range(chip_buttons.size()):
		(chip_buttons[i][0] as Button).set_pressed_no_signal(i == active)
	arrow_l.disabled = strip_scroll.scroll_horizontal <= 0
	arrow_r.disabled = float(strip_scroll.scroll_horizontal) >= bar.max_value - bar.page - 1.0


func _show_tab(key: String, toggle: bool = true) -> void:
	# erneuter Klick auf die offene Kategorie klappt die Ablage zu
	if toggle and key == current_tab and build_open and search_text == "":
		set_build_open(false)
		return
	if search_text != "":
		search_edit.text = ""
		search_text = ""
		_reset_search()
	if key != current_tab:
		strip_scroll.scroll_horizontal = 0
	current_tab = key
	for k: String in tab_pages:
		(tab_pages[k] as Control).visible = k == key
		(tab_buttons[k] as Button).set_pressed_no_signal(k == key)
	for cat: Array in Catalog.CATEGORIES:
		if cat[0] == key:
			tray_title.text = String(cat[1])
	_rebuild_chips()
	set_build_open(true)


## Suche über alle Kategorien: passende Bauteile bleiben im Streifen, der Rest verschwindet.
func _apply_search(t: String) -> void:
	search_text = t.strip_edges().to_lower()
	if search_text == "":
		_reset_search()
		_show_tab(current_tab, false)
		return
	var hits := 0
	var page_hits := {}
	var by_name := false
	for id: String in card_meta:
		by_name = by_name or (card_meta[id] as String).contains(search_text)
	var pool: Dictionary = card_meta if by_name else card_desc
	for s: Dictionary in sections:
		var any := false
		for id: String in s["ids"]:
			var m := (pool[id] as String).contains(search_text)
			(tool_buttons[id] as Control).visible = m
			if m:
				any = true
				hits += 1
		(s["box"] as Control).visible = any
		if any:
			page_hits[s["cat"]] = true
	for k: String in tab_pages:
		(tab_pages[k] as Control).visible = page_hits.has(k)
		(tab_buttons[k] as Button).set_pressed_no_signal(false)
	tray_title.text = "Suche · %d Treffer" % hits if hits > 0 else "Suche · nichts gefunden"
	strip_scroll.scroll_horizontal = 0
	_rebuild_chips()
	set_build_open(true)


func _reset_search() -> void:
	for s: Dictionary in sections:
		(s["box"] as Control).visible = true
		for id: String in s["ids"]:
			(tool_buttons[id] as Control).visible = true


## Enter in der Suche wählt den ersten Treffer.
func _search_pick(_t: String) -> void:
	for s: Dictionary in sections:
		if not (s["box"] as Control).visible or not (tab_pages[s["cat"]] as Control).visible:
			continue
		for id: String in s["ids"]:
			if (tool_buttons[id] as Control).visible:
				search_edit.release_focus()
				(tool_buttons[id] as Button).button_pressed = true
				return


func _search_input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
		search_edit.text = ""
		_apply_search("")
		search_edit.release_focus()
		search_edit.accept_event()


## Strg+F: in die Suche springen.
func focus_search() -> void:
	set_build_open(true)
	search_edit.grab_focus()
	search_edit.select_all()


func release_search() -> void:
	if search_edit != null and search_edit.has_focus():
		search_edit.release_focus()


## Alt+Ziffer: Kategorie öffnen.
func open_category(index: int) -> void:
	if index >= 0 and index < Catalog.CATEGORIES.size():
		_show_tab(String(Catalog.CATEGORIES[index][0]))


## Ablage zeigen oder verbergen; das Dock bleibt immer sichtbar.
func set_build_open(on: bool) -> void:
	build_open = on
	if tray != null:
		tray.visible = on
	if tab_buttons.has("_fold"):
		(tab_buttons["_fold"] as Button).set_pressed_no_signal(on)
		(tab_buttons["_fold"] as Button).text = "▾" if on else "▴"
	_queue_layout()


func toggle_build() -> void:
	set_build_open(not build_open)


func show_map(on: bool) -> void:
	map_button.set_pressed_no_signal(on)


func set_thumbs(textures: Dictionary) -> void:
	for id: String in textures:
		thumb_tex[id] = textures[id]
		if thumb_rects.has(id):
			(thumb_rects[id] as TextureRect).texture = textures[id]
	for key: String in Catalog.CATEGORY_ICON:
		var icon_id: String = Catalog.CATEGORY_ICON[key]
		if textures.has(icon_id) and cat_icons.has(key):
			(cat_icons[key] as TextureRect).texture = textures[icon_id]
	if textures.has("kopieren") and cat_icons.has("_kopieren"):
		(cat_icons["_kopieren"] as TextureRect).texture = textures["kopieren"]
	_refresh_recent()


## Zuletzt benutzte Bauteile als kleine Bildknöpfe im Dock.
func _note_recent(id: String) -> void:
	if not tool_category.has(id):
		return
	recent.erase(id)
	recent.push_front(id)
	if recent.size() > RECENT_MAX:
		recent.resize(RECENT_MAX)
	_refresh_recent()


func _refresh_recent() -> void:
	if recent_box == null:
		return
	for c in recent_box.get_children():
		c.queue_free()
	for id: String in recent:
		var b := _button("", false)
		b.custom_minimum_size = Vector2(44, 58)
		b.tooltip_text = "Zuletzt: " + _tooltip(id)
		b.add_theme_stylebox_override("normal", _box(Color(0.1, 0.09, 0.065, 0.0), Color(0, 0, 0, 0), 0, 2))
		var pic := TextureRect.new()
		pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pic.offset_left = 3
		pic.offset_right = -3
		pic.offset_top = 9
		pic.offset_bottom = -9
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.texture = thumb_tex.get(id)
		b.add_child(pic)
		b.pressed.connect(_pick_recent.bind(id))
		recent_box.add_child(b)
	recent_sep.visible = not recent.is_empty()
	_queue_layout()


func _pick_recent(id: String) -> void:
	(tool_buttons[id] as Button).button_pressed = true


# ---------------------------------------------------------------- Wegebau-Leiste

func _build_line_bar() -> void:
	line_bar = PanelContainer.new()
	var sb := _box(Color(0.06, 0.055, 0.04, 0.94), Color(0.38, 0.8, 0.92, 0.9), 2, 6)
	sb.set_corner_radius_all(10)
	line_bar.add_theme_stylebox_override("panel", sb)
	line_bar.visible = false
	root.add_child(line_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	line_bar.add_child(row)
	line_title = _label("", 15, C_TEXT)
	line_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line_title.custom_minimum_size = Vector2(0, 34)
	row.add_child(line_title)
	mode_box = HBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 3)
	row.add_child(mode_box)
	mode_box.add_child(_dock_sep())
	var mg := ButtonGroup.new()
	for m: Array in [["gerade", "━  Gerade", "Gerade Stücke, baut weiter am Ende"],
			["kurve", "◠  Kurve", "Bögen; am Wegende geht es tangential weiter"],
			["frei", "∿  Freihand", "Beliebig viele Punkte, Ecken werden gerundet"],
			["ersetzen", "⇄  Ersetzen", "Bestehenden Weg anklicken und in diesen Typ umbauen (Straße ↔ 4-spurig ↔ Einbahn, Rollweg ↔ breit)"]]:
		var b := _button(String(m[1]), true)
		b.button_group = mg
		b.custom_minimum_size = Vector2(0, 34)
		b.tooltip_text = String(m[2]) + " (Tab wechselt)"
		var key: String = m[0]
		b.pressed.connect(func() -> void: draw_mode_selected.emit(key))
		mode_box.add_child(b)
		mode_buttons[key] = b
	mode_box.add_child(_dock_sep())
	snap_button = _button("⊹  Einrasten", true)
	snap_button.custom_minimum_size = Vector2(0, 34)
	snap_button.button_pressed = true
	snap_button.tooltip_text = "Winkel in 15°-Stufen und Längen auf halbe Meter einrasten (G). Shift hält es kurz frei."
	snap_button.toggled.connect(func(on: bool) -> void: snap_toggled.emit(on))
	mode_box.add_child(snap_button)
	mode_box.add_child(_dock_sep())
	step_label = _label("", 14, Color(0.62, 0.9, 1.0))
	step_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(step_label)


func show_draw_modes(mode: String, shown: bool, upgrade: bool = false) -> void:
	modes_shown = shown
	mode_box.visible = shown
	(mode_buttons["ersetzen"] as Control).visible = upgrade
	for key: String in mode_buttons:
		(mode_buttons[key] as Button).set_pressed_no_signal(key == mode)
	_update_line_bar()


func show_snapping(on: bool) -> void:
	snap_button.set_pressed_no_signal(on)


## Nächster Schritt beim Wegebau ("" = keine Wegebau-Leiste).
func set_steps(text: String) -> void:
	step_text = text
	step_label.text = text
	_update_line_bar()


func _update_line_bar() -> void:
	var on := step_text != "" and Catalog.LINES.has(current_tool)
	line_bar.visible = on
	if on:
		line_title.text = Catalog.label(current_tool) + "  ·  " + _price(current_tool)
	_queue_layout()


func _queue_layout() -> void:
	if not layout_queued:
		layout_queued = true
		_layout_build.call_deferred()


## Kopfzeile bei schmalen Fenstern verdichten: erst kürzere Knopftexte, dann ohne Titel.
func _fit_top(w: float) -> void:
	if top_row == null:
		return
	title_box.visible = true
	(title_box.get_meta("sep") as Control).visible = true
	day_label.visible = true
	top_row.add_theme_constant_override("separation", 14)
	for vb: Array in view_buttons:
		(vb[0] as Button).text = String(vb[1])
	if top_row.get_combined_minimum_size().x + 24.0 <= w:
		return
	for vb: Array in view_buttons:
		(vb[0] as Button).text = String(vb[2])
	top_row.add_theme_constant_override("separation", 8)
	if top_row.get_combined_minimum_size().x + 24.0 <= w:
		return
	title_box.visible = false
	(title_box.get_meta("sep") as Control).visible = false
	if top_row.get_combined_minimum_size().x + 24.0 <= w:
		return
	day_label.visible = false


## Dock, Ablage und Wegebau-Leiste mittig unten anordnen, nie breiter als der Bildschirm.
func _layout_build(test_size: Vector2 = Vector2.ZERO) -> void:
	layout_queued = false
	if dock == null:
		return
	var vs := root.get_viewport_rect().size if test_size == Vector2.ZERO else test_size
	_fit_top(vs.x)
	var room := vs.x - 24.0
	# Dock: zuletzt benutzte ausblenden, wenn es zu eng wird
	recent_box.visible = true
	dock.reset_size()
	if dock.get_combined_minimum_size().x > room:
		recent_box.visible = false
		recent_sep.visible = false
	elif not recent.is_empty():
		recent_sep.visible = true
	dock.reset_size()
	dock.size = dock.get_combined_minimum_size()
	dock.position = Vector2(roundf((vs.x - dock.size.x) * 0.5), vs.y - dock.size.y - 10.0)
	var top := dock.position.y
	if tray.visible:
		var content := strip_row.get_combined_minimum_size().x
		var max_strip := maxf(200.0, room - 2.0 * 32.0 - 28.0)
		var w := minf(content, max_strip)
		var scrolls := content > max_strip + 0.5
		arrow_l.visible = scrolls
		arrow_r.visible = scrolls
		strip_scroll.custom_minimum_size = Vector2(maxf(w, minf(520.0, max_strip)), 134)
		tray.reset_size()
		tray.size = tray.get_combined_minimum_size()
		if tray.size.x > room:
			strip_scroll.custom_minimum_size.x -= tray.size.x - room
			tray.reset_size()
			tray.size = tray.get_combined_minimum_size()
		tray.position = Vector2(roundf((vs.x - tray.size.x) * 0.5), top - tray.size.y - 6.0)
		top = tray.position.y
		_update_chips.call_deferred()
	if line_bar.visible:
		line_bar.reset_size()
		line_bar.size = line_bar.get_combined_minimum_size()
		if line_bar.size.x > room:
			step_label.visible = false
			line_bar.reset_size()
			line_bar.size = line_bar.get_combined_minimum_size()
		else:
			step_label.visible = true
		line_bar.position = Vector2(roundf((vs.x - line_bar.size.x) * 0.5), top - line_bar.size.y - 6.0)


# ---------------------------------------------------------------- Meldungen

func _build_toast() -> void:
	toast_label = _label("", 18, C_TEXT)
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.offset_top = 84.0
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	toast_label.add_theme_constant_override("outline_size", 6)
	toast_label.modulate.a = 0.0
	root.add_child(toast_label)


func _on_tool_toggled(on: bool, id: String) -> void:
	if on:
		tool_selected.emit(id)
	elif tool_group.get_pressed_button() == null:
		tool_selected.emit("")


## Werkzeug von außen gesetzt (z. B. Esc): Knöpfe anpassen, ohne Signale auszulösen.
func show_tool(id: String) -> void:
	current_tool = id
	for key: String in tool_buttons:
		(tool_buttons[key] as Button).set_pressed_no_signal(key == id)
	if tool_category.has(id) and search_text == "":
		_show_tab(String(tool_category[id]), false)
		if build_open:
			strip_scroll.ensure_control_visible.call_deferred(tool_buttons[id])
	_note_recent(id)
	_update_line_bar()


func show_speed(i: int) -> void:
	for k in range(speed_buttons.size()):
		(speed_buttons[k] as Button).set_pressed_no_signal(k == i)


func show_utility(on: bool) -> void:
	utility_button.set_pressed_no_signal(on)


func show_interior(on: bool) -> void:
	interior_button.set_pressed_no_signal(on)
	floor_box.visible = on   # Ebenenwahl nur in der Innenansicht
	_queue_layout()


func show_floor(f: int) -> void:
	floor_label.text = "UG" if f < 0 else ("EG" if f == 0 else "%d.OG" % f)


## Bauformen des gewählten Gebäudes als Zeilen "Name  ◀ Wert ▶".
func set_options(opts: Array) -> void:
	for c in options_box.get_children():
		c.queue_free()
	for o: Array in opts:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var name_l := _label(String(o[1]), 14, C_DIM)
		name_l.custom_minimum_size = Vector2(110, 0)
		row.add_child(name_l)
		var left := _button("◀", false)
		left.custom_minimum_size = Vector2(30, 28)
		left.pressed.connect(func() -> void: option_changed.emit(String(o[0]), -1))
		row.add_child(left)
		var val := _label(String(o[2]), 14, C_TEXT)
		val.custom_minimum_size = Vector2(120, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(val)
		var right := _button("▶", false)
		right.custom_minimum_size = Vector2(30, 28)
		right.pressed.connect(func() -> void: option_changed.emit(String(o[0]), 1))
		row.add_child(right)
		options_box.add_child(row)


func set_help_visible(on: bool) -> void:
	help_label.visible = on


# ---------------------------------------------------------------- Spielmenü (Esc)

func _build_game_menu() -> void:
	menu_layer = Control.new()
	menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_layer.visible = false
	root.add_child(menu_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.015, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(center)
	# Hauptseite
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(340, 0)
	center.add_child(panel)
	menu_page = panel
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var head := _label("Menü", 26, C_TEXT)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var sub := _label("Das Spiel ist pausiert", 13, C_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	update_label = _label("", 13, C_FAINT)
	update_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	update_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	update_label.custom_minimum_size = Vector2(300, 0)
	col.add_child(update_label)
	restart_button = _button("Update aktivieren: Neustart", false)
	restart_button.custom_minimum_size = Vector2(300, 44)
	restart_button.add_theme_color_override("font_color", C_OK)
	restart_button.visible = false
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	col.add_child(restart_button)
	download_button = _button("Neue Version herunterladen", false)
	download_button.custom_minimum_size = Vector2(300, 44)
	download_button.visible = false
	download_button.pressed.connect(func() -> void: downloads_requested.emit())
	col.add_child(download_button)
	col.add_child(HSeparator.new())
	for entry: Array in [["Weiterspielen", "resume"], ["Speichern", "save"], ["Laden", "load"],
			["Neue Karte", "new"], ["Einstellungen", "settings"], ["Spiel beenden", "quit"]]:
		var b := _button(String(entry[0]), false)
		b.custom_minimum_size = Vector2(300, 44)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_menu_action.bind(String(entry[1]), b))
		col.add_child(b)
		if entry[1] == "new":
			new_button = b
	# Einstellungen
	var sp := PanelContainer.new()
	sp.custom_minimum_size = Vector2(460, 0)
	sp.visible = false
	center.add_child(sp)
	settings_page = sp
	var scol := VBoxContainer.new()
	scol.add_theme_constant_override("separation", 10)
	sp.add_child(scol)
	var sh := _label("Einstellungen", 26, C_TEXT)
	sh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scol.add_child(sh)
	scol.add_child(HSeparator.new())
	for d: Array in Settings.DEFS:
		var key: String = d[0]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var name := _label(String(d[2]), 16, C_TEXT)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name)
		match String(d[3]):
			"bool":
				var cb := CheckButton.new()
				cb.focus_mode = Control.FOCUS_NONE
				cb.toggled.connect(func(on: bool) -> void: setting_changed.emit(key, on))
				line.add_child(cb)
				setting_controls[key] = cb
			"choice":
				var group := ButtonGroup.new()
				var opts: Array = d[4]
				var boxes := []
				for i in range(opts.size()):
					var ob := _button(String(opts[i]), true)
					ob.custom_minimum_size = Vector2(72, 34)
					ob.button_group = group
					ob.pressed.connect(func() -> void: setting_changed.emit(key, i))
					line.add_child(ob)
					boxes.append(ob)
				setting_controls[key] = boxes
			"slider":
				var range_v: Array = d[4]
				var sl := HSlider.new()
				sl.min_value = float(range_v[0])
				sl.max_value = float(range_v[1])
				sl.step = 0.1
				sl.custom_minimum_size = Vector2(180, 24)
				sl.focus_mode = Control.FOCUS_NONE
				sl.value_changed.connect(func(v: float) -> void: setting_changed.emit(key, v))
				line.add_child(sl)
				setting_controls[key] = sl
		scol.add_child(line)
	scol.add_child(HSeparator.new())
	var back := _button("Zurück", false)
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(menu_back)
	scol.add_child(back)


## Werte in die Bedienelemente übernehmen, ohne Signale auszulösen.
func show_settings(values: Dictionary) -> void:
	for key: String in setting_controls:
		var c: Variant = setting_controls[key]
		var v: Variant = values.get(key)
		if c is CheckButton:
			(c as CheckButton).set_pressed_no_signal(bool(v))
		elif c is HSlider:
			(c as HSlider).set_value_no_signal(float(v))
		elif c is Array:
			for i in range((c as Array).size()):
				((c as Array)[i] as Button).set_pressed_no_signal(i == int(v))


func _menu_action(action: String, b: Button) -> void:
	match action:
		"resume":
			close_menu()
		"save":
			save_requested.emit()
			close_menu()
		"load":
			load_requested.emit()
			close_menu()
		"new":
			if b.text == "Neue Karte":
				b.text = "Wirklich? Alles wird gelöscht"
				b.add_theme_color_override("font_color", C_BAD)
				return
			new_requested.emit()
			close_menu()
		"settings":
			menu_page.visible = false
			settings_page.visible = true
		"quit":
			quit_requested.emit()


func set_update_status(text: String, ready: bool, full_download: bool) -> void:
	update_label.text = text
	restart_button.visible = ready
	download_button.visible = full_download


func set_version(v: String) -> void:
	subtitle_label.text = "Flughafen Wiesenfeld · v" + v


func is_menu_open() -> bool:
	return menu_layer.visible


func open_menu() -> void:
	if menu_layer.visible:
		return
	menu_layer.visible = true
	menu_page.visible = true
	settings_page.visible = false
	new_button.text = "Neue Karte"
	new_button.remove_theme_color_override("font_color")
	menu_opened.emit(true)


func close_menu() -> void:
	if not menu_layer.visible:
		return
	menu_layer.visible = false
	menu_opened.emit(false)


## Esc im Menü: aus den Einstellungen zurück, sonst Menü schließen.
func menu_back() -> void:
	if settings_page.visible:
		settings_page.visible = false
		menu_page.visible = true
	else:
		close_menu()


func set_clock(text: String) -> void:
	clock_label.text = text


func set_economy(sat: float, factors: Array, day_income: int, upkeep: int) -> void:
	sat_label.text = "%d %%" % roundi(sat)
	var c := C_OK if sat >= 65.0 else (Color(0.94, 0.76, 0.31) if sat >= 40.0 else C_BAD)
	sat_label.add_theme_color_override("font_color", c)
	var tip := "Zufriedenheit von Passagieren und Airlines.\nHoch = mehr Flüge und höhere Ticketpreise."
	for f: Array in factors:
		tip += "\n%s%d  %s" % ["+" if int(f[1]) > 0 else "", int(f[1]), String(f[0])]
	sat_holder.tooltip_text = tip
	day_label.text = "heute +%s · Unterhalt %s/Tag" % [GameState.fmt_money(day_income), GameState.fmt_money(upkeep)]


func set_money(v: int) -> void:
	money_label.text = GameState.fmt_money(v)
	money_label.add_theme_color_override("font_color", C_TEXT if v >= 0 else C_BAD)


func set_info(title: String, body: String, state: int) -> void:
	info_title.text = title
	if title != "Ansehen" and body != "" and info_details != null:
		_fold(info_details, info_toggle, true)
	info_body.text = body
	var c := C_DIM
	if state == 1:
		c = C_OK
	elif state == 2:
		c = C_BAD
	info_body.add_theme_color_override("font_color", c)


func toast(text: String) -> void:
	toast_label.text = text
	if toast_tween != null:
		toast_tween.kill()
	toast_label.modulate.a = 1.0
	toast_tween = create_tween()
	toast_tween.tween_interval(2.4)
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.6)


# ---------------------------------------------------------------- Betrieb (Statistik, Verträge, Ziele)

## Säulendiagramm ohne Achsen (Werte 0 … max), mit Beschriftung darunter.
class BarChart extends Control:
	var values: Array = []
	var labels: Array = []
	var color := Color(0.94, 0.76, 0.31)

	func _draw() -> void:
		var n := values.size()
		if n == 0:
			return
		var mx := 1.0
		for v: float in values:
			mx = maxf(mx, v)
		var w := size.x / float(n)
		var h := size.y - 16.0
		for i in range(n):
			var bh := h * float(values[i]) / mx
			draw_rect(Rect2(i * w + 1.0, h - bh, w - 2.0, bh), color)
			if i < labels.size() and String(labels[i]) != "":
				draw_string(ThemeDB.fallback_font, Vector2(i * w, size.y - 2.0), String(labels[i]), HORIZONTAL_ALIGNMENT_LEFT, w * 3.0, 11, Color(0.76, 0.72, 0.58))


func _build_ops() -> void:
	ops_window = PanelContainer.new()
	ops_window.anchor_left = 0.5
	ops_window.anchor_right = 0.5
	ops_window.offset_left = -330.0
	ops_window.offset_right = 330.0
	ops_window.offset_top = 80.0
	ops_window.custom_minimum_size = Vector2(660, 560)
	ops_window.visible = false
	root.add_child(ops_window)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	ops_window.add_child(col)
	var head := HBoxContainer.new()
	var title := _label("BETRIEB", 20, C_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := _button("×", false)
	close.custom_minimum_size = Vector2(34, 30)
	close.pressed.connect(func() -> void: show_ops(false))
	head.add_child(close)
	col.add_child(head)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var tg := ButtonGroup.new()
	for t: Array in [["statistik", "Statistik"], ["vertraege", "Airline-Verträge"], ["ziele", "Szenarien und Ziele"]]:
		var b := _button(String(t[1]), true)
		b.button_group = tg
		b.button_pressed = t[0] == ops_tab
		b.custom_minimum_size = Vector2(0, 34)
		var key: String = t[0]
		b.pressed.connect(func() -> void:
			ops_tab = key
			ops_sig = ""
			_ops_refresh())
		tabs.add_child(b)
	col.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(636, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	ops_body = VBoxContainer.new()
	ops_body.add_theme_constant_override("separation", 6)
	ops_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(ops_body)


func show_ops(on: bool) -> void:
	ops_window.visible = on
	ops_button.set_pressed_no_signal(on)
	if on:
		ops_sig = ""
		_ops_refresh()


func toggle_ops() -> void:
	show_ops(not ops_window.visible)


## Inhalt der Betriebsseite als Liste von Einträgen; neu gebaut nur, wenn sich etwas geändert hat.
func _ops_refresh() -> void:
	if ops_ref == null:
		return
	var rows: Array = []
	match ops_tab:
		"statistik":
			rows = _ops_stats()
		"vertraege":
			rows = _ops_contracts()
		"ziele":
			rows = _ops_goals()
	var sig := var_to_str(rows)
	if sig == ops_sig:
		return
	ops_sig = sig
	for c in ops_body.get_children():
		c.queue_free()
	for r: Array in rows:
		ops_body.add_child(_ops_row(r))


func _ops_row(r: Array) -> Control:
	match String(r[0]):
		"title":
			return _label(String(r[1]), 17, Color(0.94, 0.76, 0.31))
		"text":
			var l := _label(String(r[1]), 14, r[2] if r.size() > 2 else C_DIM)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(620, 0)
			return l
		"kv":
			var h := HBoxContainer.new()
			var k := _label(String(r[1]), 14, C_DIM)
			k.custom_minimum_size = Vector2(300, 0)
			h.add_child(k)
			h.add_child(_label(String(r[2]), 15, r[3] if r.size() > 3 else C_TEXT))
			return h
		"bar":
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 8)
			var k := _label(String(r[1]), 14, C_TEXT)
			k.custom_minimum_size = Vector2(300, 0)
			k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			h.add_child(k)
			var pb := ProgressBar.new()
			pb.custom_minimum_size = Vector2(200, 18)
			pb.max_value = 1.0
			pb.value = float(r[2])
			pb.show_percentage = false
			var fill := StyleBoxFlat.new()
			fill.bg_color = r[3]
			pb.add_theme_stylebox_override("fill", fill)
			var bg := StyleBoxFlat.new()
			bg.bg_color = Color(0.15, 0.14, 0.1)
			pb.add_theme_stylebox_override("background", bg)
			h.add_child(pb)
			h.add_child(_label(String(r[4]) if r.size() > 4 else "", 13, C_DIM))
			return h
		"button":
			var b := _button(String(r[1]), false)
			b.custom_minimum_size = Vector2(0, 34)
			b.disabled = not bool(r[4])
			var action: String = r[2]
			var arg: Variant = r[3]
			b.pressed.connect(func() -> void: _ops_action(action, arg, b))
			return b
		"chart":
			var ch := BarChart.new()
			ch.values = r[1]
			ch.labels = r[2]
			ch.custom_minimum_size = Vector2(620, 90)
			return ch
		"sep":
			return HSeparator.new()
	return Control.new()


func _ops_action(action: String, arg: Variant, b: Button) -> void:
	match action:
		"sign":
			contract_requested.emit(String(arg))
			ops_sig = ""
			_ops_refresh()
		"spot":
			spot_requested.emit(arg)
		"scenario":
			if not b.text.begins_with("Wirklich"):
				b.text = "Wirklich? Der aktuelle Flughafen wird ersetzt"
				b.add_theme_color_override("font_color", C_BAD)
				return
			scenario_requested.emit(String(arg))
			show_ops(false)
		"tutorial":
			tutorial_requested.emit()
			show_ops(false)


func _ops_stats() -> Array:
	var o = ops_ref
	var st: Dictionary = o.stats
	var rows := [["title", "Pünktlichkeit und Verkehr"]]
	var pu: float = o.punctuality()
	rows.append(["kv", "Abflüge gesamt", str(int(st["abfluege"]))])
	rows.append(["kv", "Pünktlich (bis 15 Min, letzte 40)", "–" if pu < 0.0 else "%d %%" % roundi(pu), C_OK if pu >= 85.0 else (C_BAD if pu >= 0.0 and pu < 70.0 else C_TEXT)])
	rows.append(["kv", "Durchschnittliche Verspätung", "%d Min" % roundi(float(o.avg_delay()))])
	rows.append(["kv", "Abgeflogene Passagiere", GameState.fmt_money(int(st["pax"])).replace(" €", "")])
	rows.append(["kv", "Umgeschlagene Fracht", "%d t" % int(st["tonnen"])])
	var bags := int(st["koffer"])
	rows.append(["kv", "Fehlgeleitete Koffer", "%d von %d (%.1f ‰)" % [int(st["koffer_weg"]), bags, 1000.0 * float(st["koffer_weg"]) / maxf(float(bags), 1.0)]])
	rows.append(["kv", "Lounge-Gäste", str(int(st["lounge"]))])
	rows.append(["kv", "Wartungschecks im Hangar", str(int(st["checks"]))])
	rows.append(["sep"])
	rows.append(["title", "Passagiere je Stunde (letzte 24 Stunden)"])
	var vals := []
	var labs := []
	for e: Array in o.hourly:
		vals.append(float(e[1]))
		labs.append("%02d" % (int(e[0]) % 24) if int(e[0]) % 3 == 0 else "")
	rows.append(["chart", vals, labs])
	rows.append(["sep"])
	rows.append(["title", "Einnahmen nach Bereich (seit Spielbeginn)"])
	var inc: Dictionary = o.income
	var total := 0
	for k: String in inc:
		total += maxi(0, int(inc[k]))
	var keys := inc.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(inc[a]) > int(inc[b]))
	for k: String in keys:
		if int(inc[k]) <= 0:
			continue
		rows.append(["bar", k, float(inc[k]) / maxf(float(total), 1.0), C_PRICE, GameState.fmt_money(int(inc[k]))])
	if keys.is_empty():
		rows.append(["text", "Noch keine Einnahmen.", C_FAINT])
	rows.append(["sep"])
	rows.append(["title", "Engpässe: hier warten Flugzeuge am längsten"])
	var spots: Array = o.hotspots(5)
	if spots.is_empty():
		rows.append(["text", "Bisher keine Wartezeiten am Boden.", C_FAINT])
	var mx := 1.0
	for e: Array in spots:
		mx = maxf(mx, float(e[1]))
	for e: Array in spots:
		var pos: Vector3 = e[0]
		rows.append(["bar", "Bei x %d, z %d" % [roundi(pos.x), roundi(pos.z)], float(e[1]) / mx, C_BAD, "%d Min" % roundi(float(e[1]))])
		rows.append(["button", "Auf der Karte zeigen", "spot", pos, true])
	return rows


func _ops_contracts() -> Array:
	var o = ops_ref
	var rows := [["text", "Airlines unter Vertrag fliegen dreimal so oft. Die Prämie gibt es beim Unterschreiben; werden die Bedingungen einen Tag lang nicht erfüllt, kündigt die Airline.", C_DIM]]
	for al: Array in Catalog.AIRLINES:
		var code := String(al[0])
		var off: Dictionary = Ops.OFFERS[code]
		rows.append(["sep"])
		var active: bool = o.is_contract(code)
		rows.append(["title", "%s (%s)%s" % [String(al[3]), code, " – unter Vertrag" if active else ""]])
		rows.append(["text", String(off["text"]) + " · Prämie " + GameState.fmt_money(int(off["bonus"])), C_TEXT])
		for r: Array in off["req"]:
			var rq: Array = o.requirement(r)
			rows.append(["text", ("✓ " if bool(rq[0]) else "✗ ") + String(rq[1]), C_OK if bool(rq[0]) else C_BAD])
		if not active:
			rows.append(["button", "Vertrag unterschreiben", "sign", code, o.offer_ok(code)])
		elif float((o.contracts[code] as Dictionary).get("verletzt", 0.0)) > 0.0:
			rows.append(["text", "Bedingungen nicht erfüllt: Kündigung droht!", C_BAD])
	return rows


func _ops_goals() -> Array:
	var o = ops_ref
	var rows := []
	if String(o.scenario) != "":
		var sc: Dictionary = Ops.SCENARIOS[o.scenario]
		rows.append(["title", String(sc["name"]) + (" – geschafft!" if bool(o.scenario_done) else "")])
		rows.append(["text", String(sc["desc"]), C_TEXT])
		for g: Array in sc["goals"]:
			var gs: Array = o.goal_state(g)
			rows.append(["bar", ("✓ " if bool(gs[0]) else "") + String(gs[2]), float(gs[1]), C_OK if bool(gs[0]) else Color(0.94, 0.76, 0.31), ""])
		rows.append(["sep"])
	rows.append(["title", "Szenario starten"])
	rows.append(["text", "Jedes Szenario beginnt mit dem Startflughafen und eigenem Budget. Der aktuelle Flughafen wird ersetzt (vorher speichern!).", C_DIM])
	for key: String in Ops.SCENARIOS:
		var sc: Dictionary = Ops.SCENARIOS[key]
		rows.append(["text", String(sc["name"]) + ": " + String(sc["desc"]), C_TEXT])
		rows.append(["button", "„%s“ starten" % String(sc["name"]), "scenario", key, true])
	rows.append(["sep"])
	rows.append(["title", "Lernschritte für Einsteiger"])
	rows.append(["text", "Schritt für Schritt vom leeren Feld zum ersten Flug. Am besten auf einer neuen, leeren Karte (Menü → Neue Karte).", C_DIM])
	rows.append(["button", "Lernschritte starten", "tutorial", 0, true])
	return rows


## Lernschritte: kleines Feld oben in der Mitte.
func _build_tutorial() -> void:
	tutorial_panel = PanelContainer.new()
	tutorial_panel.anchor_left = 0.5
	tutorial_panel.anchor_right = 0.5
	tutorial_panel.offset_left = -300.0
	tutorial_panel.offset_right = 300.0
	tutorial_panel.offset_top = 118.0
	tutorial_panel.visible = false
	root.add_child(tutorial_panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	tutorial_panel.add_child(h)
	tutorial_label = _label("", 15, C_TEXT)
	tutorial_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tutorial_label.custom_minimum_size = Vector2(480, 0)
	h.add_child(tutorial_label)
	var skip := _button("Beenden", false)
	skip.custom_minimum_size = Vector2(80, 32)
	skip.pressed.connect(func() -> void:
		if ops_ref != null:
			ops_ref.tutorial = -1)
	h.add_child(skip)
