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

const Catalog = preload("res://scripts/catalog.gd")
const GameState = preload("res://scripts/game_state.gd")
const Settings = preload("res://scripts/settings.gd")

const C_PANEL := Color(0.083, 0.075, 0.055, 0.88)
const C_GOLD := Color(0.73, 0.65, 0.42)
const C_TEXT := Color(0.96, 0.91, 0.74)
const C_DIM := Color(0.76, 0.72, 0.58)
const C_FAINT := Color(0.60, 0.56, 0.45)
const C_OK := Color(0.66, 0.85, 0.56)
const C_BAD := Color(1.0, 0.55, 0.45)
const C_PRICE := Color(0.94, 0.78, 0.36)

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
var build_pages: Control           # Karten des Baumenüs (einklappbar, Reiter bleiben)
var build_open := true
var current_tab := ""
var map_button: Button


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
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", 0)
	title.add_child(_label("PixelApron", 22, C_TEXT))
	subtitle_label = _label("Flughafen Wiesenfeld", 13, C_DIM)
	title.add_child(subtitle_label)
	row.add_child(title)
	row.add_child(VSeparator.new())
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
	map_button = _button("Karte", true)
	map_button.tooltip_text = "Ganze Karte zeigen und zurück (M)"
	map_button.toggled.connect(func(_on: bool) -> void: map_requested.emit())
	row.add_child(map_button)
	utility_button = _button("Leitungen", true)
	utility_button.tooltip_text = "Strom-, Wasser- und Heizleitungen zeigen (L)"
	utility_button.toggled.connect(func(on: bool) -> void: utility_toggled.emit(on))
	row.add_child(utility_button)
	interior_button = _button("Innenansicht", true)
	interior_button.tooltip_text = "Dächer ausblenden und ins Terminal schauen (I)"
	interior_button.toggled.connect(func(on: bool) -> void: interior_toggled.emit(on))
	row.add_child(interior_button)
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
	col.add_child(HSeparator.new())
	help_label = _label("Linksklick bauen · Rechtsklick fertig oder abwählen · R drehen · Esc Menü\nWASD oder mittlere Maustaste verschieben · Mausrad zoomen · Q/E drehen\nLeertaste Pause · L Leitungen · I Innenansicht · Strg+Z rückgängig", 12, C_FAINT)
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
	panel.offset_left = -416.0
	panel.offset_right = -16.0
	panel.offset_top = 80.0
	panel.custom_minimum_size = Vector2(400, 0)
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
	for c in flight_rows.get_children():
		c.queue_free()
	if rows.is_empty():
		flight_rows.add_child(_label("Gerade kein Flugzeug unterwegs", 14, C_FAINT))
		return
	var shown := 0
	for r: Array in rows:
		shown += 1
		if shown > 8:
			flight_rows.add_child(_label("… und %d weitere" % (rows.size() - 8), 13, C_FAINT))
			break
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var code := _label(String(r[0]), 15, Color(0.94, 0.76, 0.31))
		code.custom_minimum_size = Vector2(62, 0)
		line.add_child(code)
		var route := _label(String(r[2]), 14, C_TEXT)
		route.custom_minimum_size = Vector2(130, 0)
		line.add_child(route)
		var st := _label(String(r[3]), 14, r[4])
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(st)
		line.tooltip_text = String(r[1])
		flight_rows.add_child(line)


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


func _card(id: String, accent: Color = C_GOLD) -> Button:
	var b := _button("", true)
	b.custom_minimum_size = Vector2(108, 116)
	b.button_group = tool_group
	b.tooltip_text = _tooltip(id)
	b.toggled.connect(_on_tool_toggled.bind(id))
	if accent != C_GOLD:
		b.add_theme_stylebox_override("pressed", _box(Color(0.3, 0.1, 0.08), accent, 3, 6))
		b.add_theme_stylebox_override("hover_pressed", _box(Color(0.34, 0.12, 0.09), accent, 3, 6))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 4
	col.offset_right = -4
	col.offset_top = 4
	col.offset_bottom = -4
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(72, 72)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pic)
	thumb_rects[id] = pic
	var title := Catalog.label(id)
	if Catalog.ITEMS.has(id) and Catalog.ITEMS[id].has("short"):
		title = String(Catalog.ITEMS[id]["short"])
	var name := _label(title, 13 if title.length() <= 12 else 11, C_TEXT)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.clip_text = true
	col.add_child(name)
	var price := _label(_price(id), 12, C_PRICE if accent == C_GOLD else accent)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(price)
	tool_buttons[id] = b
	return b


func _build_menu() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_top = -12.0
	panel.offset_bottom = -12.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var pages := Control.new()
	pages.custom_minimum_size = Vector2(0, 116)
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pages)
	build_pages = pages
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	var widest := 0.0
	for cat: Array in Catalog.CATEGORIES:
		var key: String = cat[0]
		var page := HBoxContainer.new()
		page.add_theme_constant_override("separation", 6)
		page.visible = false
		pages.add_child(page)
		for id: String in cat[2]:
			page.add_child(_card(id))
			tool_category[id] = key
		widest = maxf(widest, float((cat[2] as Array).size()) * 114.0)
		tab_pages[key] = page
		var t := _button(String(cat[1]), true)
		t.custom_minimum_size = Vector2(112, 36)
		t.button_group = tab_group
		t.pressed.connect(_show_tab.bind(key))
		tabs.add_child(t)
		tab_buttons[key] = t
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.custom_minimum_size = Vector2(24, 0)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_child(sp)
	var fold := _button("Baumenü", true)
	fold.custom_minimum_size = Vector2(96, 36)
	fold.tooltip_text = "Bauteile ein- und ausblenden (B). Ein Klick auf den offenen Reiter klappt auch zu."
	fold.button_pressed = true
	fold.toggled.connect(func(on: bool) -> void: set_build_open(on))
	tabs.add_child(fold)
	tab_buttons["_fold"] = fold
	var undo := _button("Rückgängig", false)
	undo.custom_minimum_size = Vector2(104, 36)
	undo.tooltip_text = "Letzten Bau zurücknehmen, volle Erstattung (Strg+Z)"
	undo.pressed.connect(func() -> void: undo_requested.emit())
	tabs.add_child(undo)
	var demolish := _button("Abriss", true)
	demolish.custom_minimum_size = Vector2(110, 36)
	demolish.button_group = tool_group
	demolish.tooltip_text = _tooltip("abriss")
	demolish.add_theme_color_override("font_color", C_BAD)
	demolish.add_theme_stylebox_override("pressed", _box(Color(0.3, 0.1, 0.08), C_BAD, 3, 6))
	demolish.add_theme_stylebox_override("hover_pressed", _box(Color(0.34, 0.12, 0.09), C_BAD, 3, 6))
	demolish.toggled.connect(_on_tool_toggled.bind("abriss"))
	tabs.add_child(demolish)
	tool_buttons["abriss"] = demolish
	pages.custom_minimum_size.x = widest
	var first: String = Catalog.CATEGORIES[0][0]
	(tab_buttons[first] as Button).set_pressed_no_signal(true)
	_show_tab(first, false)


func _show_tab(key: String, toggle: bool = true) -> void:
	# erneuter Klick auf den offenen Reiter klappt das Baumenü zu
	if toggle and key == current_tab and build_open:
		set_build_open(false)
		return
	current_tab = key
	for k: String in tab_pages:
		(tab_pages[k] as Control).visible = k == key
		(tab_buttons[k] as Button).set_pressed_no_signal(k == key)
	set_build_open(true)


## Karten des Baumenüs zeigen oder verbergen; die Reiterzeile bleibt immer sichtbar.
func set_build_open(on: bool) -> void:
	build_open = on
	if build_pages != null:
		build_pages.visible = on
	if tab_buttons.has("_fold"):
		(tab_buttons["_fold"] as Button).set_pressed_no_signal(on)


func toggle_build() -> void:
	set_build_open(not build_open)


func show_map(on: bool) -> void:
	map_button.set_pressed_no_signal(on)


func set_thumbs(textures: Dictionary) -> void:
	for id: String in textures:
		if thumb_rects.has(id):
			(thumb_rects[id] as TextureRect).texture = textures[id]


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
	for key: String in tool_buttons:
		(tool_buttons[key] as Button).set_pressed_no_signal(key == id)
	if tool_category.has(id):
		_show_tab(String(tool_category[id]), false)


func show_speed(i: int) -> void:
	for k in range(speed_buttons.size()):
		(speed_buttons[k] as Button).set_pressed_no_signal(k == i)


func show_utility(on: bool) -> void:
	utility_button.set_pressed_no_signal(on)


func show_interior(on: bool) -> void:
	interior_button.set_pressed_no_signal(on)


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
