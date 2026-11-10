extends Node
## Einstieg: baut Welt, Kamera, Spielstand, Bauwerkzeug, Verkehr, Flugbetrieb und Oberfläche
## zusammen und verteilt Maus- und Tastatureingaben.

const IsoCamera = preload("res://scripts/iso_camera.gd")
const GameState = preload("res://scripts/game_state.gd")
const Builder = preload("res://scripts/builder.gd")
const Traffic = preload("res://scripts/traffic.gd")
const Roads = preload("res://scripts/roads.gd")
const Flights = preload("res://scripts/flights.gd")
const Hud = preload("res://scripts/hud.gd")
const Thumbs = preload("res://scripts/thumbs.gd")
const Terminal = preload("res://scripts/terminal.gd")
const Settings = preload("res://scripts/settings.gd")
const Updater = preload("res://scripts/updater.gd")
const GroundOps = preload("res://scripts/ground_ops.gd")
const Airfield = preload("res://scripts/airfield.gd")
const RESUME_FLAG := "user://nach_update_laden"
const Catalog = preload("res://scripts/catalog.gd")
const GROUND_SHADER = preload("res://shaders/ground.gdshader")

var container: SubViewportContainer
var viewport: SubViewport
var world: Node3D
var sun: DirectionalLight3D
var env: Environment
var ground_mat: ShaderMaterial
var cam_rig: IsoCamera
var game: GameState
var builder: Builder
var traffic: Traffic
var roads: Roads
var flights: Flights
var terminal: Terminal
var ops: GroundOps
var airfield: Airfield
var hud: Hud
var settings: Settings
var updater: Updater
var ui_timer := 0.0
var day_night := true
var speed_before_menu := 1


func _ready() -> void:
	randomize()
	# globale Shader-Werte: night = 0 am Tag, 1 in der Nacht (Lampen, Fenster, Lichthöfe)
	RenderingServer.global_shader_parameter_add(&"night", RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	_make_view()
	_make_world()
	game = GameState.new()
	game.name = "Spielstand"
	add_child(game)
	game.setup(world)
	builder = Builder.new()
	builder.name = "Bauen"
	add_child(builder)
	builder.setup(game, world)
	roads = Roads.new()
	roads.name = "Strassennetz"
	world.add_child(roads)
	roads.setup(game)
	builder.roads = roads
	traffic = Traffic.new()
	traffic.name = "Verkehr"
	world.add_child(traffic)
	traffic.setup(game, roads)
	terminal = Terminal.new()
	terminal.name = "Terminalbetrieb"
	world.add_child(terminal)
	terminal.setup(game)
	flights = Flights.new()
	flights.name = "Flugbetrieb"
	world.add_child(flights)
	flights.setup(game)
	flights.terminal = terminal
	flights.traffic = traffic
	ops = GroundOps.new()
	ops.name = "Vorfelddienste"
	world.add_child(ops)
	ops.setup(game)
	ops.terminal = terminal
	flights.ops = ops
	terminal.bus_cb = ops.pax_at_door
	airfield = Airfield.new()
	airfield.name = "Flugfeld"
	world.add_child(airfield)
	airfield.setup(game)
	cam_rig = IsoCamera.new()
	cam_rig.name = "Kamera"
	world.add_child(cam_rig)
	hud = Hud.new()
	add_child(hud)
	settings = Settings.new()
	if not ("--selftest" in OS.get_cmdline_user_args() or "--demo" in OS.get_cmdline_user_args()):
		settings.load_file()
	updater = Updater.new()
	updater.name = "Updater"
	add_child(updater)
	_connect()
	_apply_all_settings()
	hud.set_version(updater.version())
	game.load_starter()
	if FileAccess.file_exists(RESUME_FLAG):
		DirAccess.remove_absolute(RESUME_FLAG)
		flights.clear()
		game.load_game()
	builder.set_tool("")
	var args := OS.get_cmdline_user_args()
	if "--fldebug" in args:
		var dbg: Node = load("res://tests/dbg/fl_debug.gd").new()
		add_child(dbg)
		dbg.call("run", self)
		return
	if "--selftest" in args:
		var t: Node = load("res://tests/selftest.gd").new()
		add_child(t)
		t.call("run", self)
		return
	if DisplayServer.get_name() != "headless":
		_make_thumbs()
	if not ("--demo" in args):
		updater.check_on_start()
	if "--demo" in args:
		_demo(args)


## Die 3D-Welt wird in voller Auflösung ohne Kantenglättung gerendert (1 Bildpixel = 1 Bildschirmpixel).
func _make_view() -> void:
	container = SubViewportContainer.new()
	container.name = "Bild"
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.stretch_shrink = 1
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	viewport = SubViewport.new()
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_debanding = true
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.handle_input_locally = false
	container.add_child(viewport)
	world = Node3D.new()
	world.name = "Welt"
	viewport.add_child(world)


func _make_world() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.42, 0.3)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.66, 0.70, 0.78)
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.4
	env.ssao_power = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.03
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_blur = 1.2
	sun.shadow_normal_bias = 1.2
	sun.basis = Basis.looking_at(Vector3(0.55, -0.75, -0.35).normalized(), Vector3.UP)
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8000, 8000)
	ground.mesh = pm
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = GROUND_SHADER
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ground)


func _make_thumbs() -> void:
	var ids := []
	for cat: Array in Catalog.CATEGORIES:
		ids.append_array(cat[2])
	var t := Thumbs.new()
	add_child(t)
	var textures: Dictionary = await t.render(ids)
	hud.set_thumbs(textures)
	t.queue_free()


func _connect() -> void:
	hud.tool_selected.connect(builder.set_tool)
	hud.speed_selected.connect(_set_speed)
	hud.utility_toggled.connect(game.set_utility_view)
	hud.save_requested.connect(game.save_game)
	hud.load_requested.connect(_load)
	hud.new_requested.connect(_new_map)
	hud.undo_requested.connect(game.undo_last)
	hud.interior_toggled.connect(game.set_interior_view)
	hud.menu_opened.connect(_on_menu)
	hud.quit_requested.connect(func() -> void: get_tree().quit())
	hud.setting_changed.connect(_on_setting)
	hud.restart_requested.connect(_restart_for_update)
	hud.downloads_requested.connect(updater.open_downloads)
	hud.map_requested.connect(_toggle_map)
	updater.status_changed.connect(_on_update_status)
	game.interior_changed.connect(hud.show_interior)
	game.day_ended.connect(_on_day_ended)
	builder.info.connect(hud.set_info)
	builder.tool_changed.connect(_on_tool_changed)
	builder.inspect_requested.connect(_inspect)
	game.money_changed.connect(hud.set_money)
	game.toast.connect(hud.toast)
	game.view_changed.connect(_on_view_changed)
	hud.set_money(game.money)


func _new_map() -> void:
	builder.set_tool("")
	flights.clear()
	game.clear_all()
	hud.toast("Leere Karte, 30 Mio. € Startkapital")


func _load() -> void:
	flights.clear()
	game.load_game()


func _set_speed(i: int) -> void:
	game.set_speed(i)
	hud.show_speed(i)


# ---------------------------------------------------------------- Menü und Einstellungen

## Spiel speichern, merken, dass es nach dem Neustart geladen wird, und neu starten.
func _restart_for_update() -> void:
	game.save_game(true)
	var f := FileAccess.open(RESUME_FLAG, FileAccess.WRITE)
	if f != null:
		f.store_string("1")
		f.close()
	updater.restart()


func _on_update_status(text: String, ready: bool) -> void:
	hud.set_update_status(text, ready, updater.full_download_needed)
	if ready:
		hud.toast("Update %s geladen · im Menü (Esc) neu starten" % updater.latest)
	elif updater.full_download_needed:
		hud.toast("Neue Version %s verfügbar · im Menü (Esc) herunterladen" % updater.latest)


func _on_day_ended() -> void:
	if bool(settings.get_value("autospeichern")):
		game.save_game(true)


func _on_menu(open: bool) -> void:
	if open:
		speed_before_menu = game.speed
		_set_speed(0)
		hud.show_settings(settings.values)
		cam_rig.enabled = false
		cam_rig.dragging = false
	else:
		_set_speed(speed_before_menu)
		cam_rig.enabled = true


func _on_setting(key: String, value: Variant) -> void:
	settings.set_value(key, value)
	_apply_setting(key, value)


func _apply_all_settings() -> void:
	for key: String in settings.values:
		_apply_setting(key, settings.values[key])


func _apply_setting(key: String, v: Variant) -> void:
	match key:
		"vollbild":
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if bool(v) else DisplayServer.WINDOW_MODE_WINDOWED)
		"schatten":
			var q := int(v)
			sun.shadow_enabled = q > 0
			RenderingServer.directional_shadow_atlas_set_size([2048, 2048, 4096, 8192][clampi(q, 0, 3)], true)
		"kantenglaettung":
			viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(int(v), 0, 3)]
		"tag_nacht":
			day_night = bool(v)
		"umgebungslicht":
			env.ssao_enabled = bool(v)
		"kamera_tempo":
			cam_rig.pan_speed = float(v)
		"zoom_umkehren":
			cam_rig.invert_zoom = bool(v)
		"kantenscrollen":
			cam_rig.edge_scroll = bool(v)
		"raster_immer":
			_update_grid()
		"hilfe":
			hud.set_help_visible(bool(v))


func _update_grid() -> void:
	var id := builder.tool
	var on := bool(settings.get_value("raster_immer")) or (id != "" and id != "abriss")
	ground_mat.set_shader_parameter("grid", 1.0 if on else 0.0)


func _on_tool_changed(id: String) -> void:
	hud.show_tool(id)
	_update_grid()


## Sonnenstand, Licht- und Himmelsfarbe nach der Spieluhr. Nachts Mondlicht, Lampen und Fenster leuchten.
func _daylight() -> void:
	if game.utility_view:
		return
	var h := fmod(game.minutes, 1440.0) / 60.0
	if not day_night:
		h = 13.0
	var a := PI * (h - 5.5) / 15.0       # 5:30 Aufgang, 20:30 Untergang
	var elev := sin(a)
	var night := 1.0 - smoothstep(-0.14, 0.1, elev)
	RenderingServer.global_shader_parameter_set(&"night", night)
	game.night = night
	var dusk := 1.0 - smoothstep(0.0, 0.45, elev)
	if elev > -0.04:
		var sp := Vector3(cos(a) * 0.9, maxf(elev, 0.05) * 1.3, 0.45).normalized()
		sun.basis = Basis.looking_at(-sp, Vector3.UP)
		sun.light_energy = 1.25 * smoothstep(-0.04, 0.2, elev)
		sun.light_color = Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.62, 0.38), dusk * 0.85)
	else:
		sun.basis = Basis.looking_at(Vector3(-0.4, -0.8, -0.45).normalized(), Vector3.UP)
		sun.light_energy = 0.22 * smoothstep(-0.04, -0.3, elev)
		sun.light_color = Color(0.6, 0.7, 1.0)
	env.ambient_light_color = Color(0.66, 0.70, 0.78).lerp(Color(0.34, 0.40, 0.62), night).lerp(Color(0.85, 0.68, 0.6), dusk * (1.0 - night) * 0.35)
	env.ambient_light_energy = lerpf(0.62, 0.52, night)
	env.background_color = Color(0.36, 0.42, 0.3).lerp(Color(0.07, 0.09, 0.14), night)


## Leitungsansicht: Welt abdunkeln, Leitungen leuchten (unbeleuchtetes Material).
func _on_view_changed(on: bool) -> void:
	hud.show_utility(on)
	sun.light_energy = 0.35 if on else 1.15
	env.ambient_light_energy = 0.22 if on else 0.55
	RenderingServer.global_shader_parameter_set(&"night", 0.0)


func _process(delta: float) -> void:
	sun.directional_shadow_max_distance = cam_rig.shadow_range()
	_daylight()
	if not hud.is_menu_open():
		builder.on_move(ground_at(get_viewport().get_mouse_position()))
	hud.set_clock(game.clock_text())
	ui_timer -= delta
	if ui_timer <= 0.0:
		ui_timer = 0.25
		var status := flights.check_operation()
		if status == "" and flights.reason != "":
			status = flights.reason
		hud.set_flights(flights.rows(), status, flights.done, flights.hint, flights.wind_text())
		hud.set_economy(game.satisfaction, game.satisfaction_factors, game.day_income, game.upkeep_per_day())


## Info-Werkzeug: Details zu Flugzeug, Gebäude oder Weg unter dem Mauszeiger.
func _inspect(p: Vector3) -> void:
	var plane := flights.pick(p)
	if not plane.is_empty():
		hud.set_info("Flug " + String(plane["code"]), flights.describe(plane), 0)
		return
	var rec := game.pick(p)
	if rec.is_empty():
		hud.set_info("Ansehen", "Hier ist nichts gebaut.", 0)
		return
	var body := game.details(rec)
	if rec.get("id", "") == "halle":
		body = terminal.hall_summary(rec) + "\n" + body
	if rec.get("id", "") == "parkhaus":
		var spaces := int(Catalog.ITEMS["parkhaus"]["spaces"])
		body = ("Zufahrt: verbunden" if traffic.has_access(rec) else "Keine Zufahrt: vor der Einfahrt muss eine Straße liegen") \
			+ "\nBelegt: %d von %d Plätzen" % [traffic.parked_count(rec), spaces] + "\n" + body
	if rec.get("type", "") == "line" and Catalog.is_road(String(rec["kind"])):
		var ni: int = roads.nearest_junction(p, 12.0)
		if ni >= 0:
			body = "Kreuzung: %s (ändern mit Werkzeug Kreuzung regeln)\n" % String(Roads.CONTROL_NAMES.get(roads.control_of(ni), "")) + body
	hud.set_info(game.describe(rec), body, 0)


## Schnittpunkt des Mausstrahls mit dem Boden (oder null).
func ground_at(screen_pos: Vector2) -> Variant:
	var sp := screen_pos / float(container.stretch_shrink)
	var from := cam_rig.cam.project_ray_origin(sp)
	var dir := cam_rig.cam.project_ray_normal(sp)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, dir)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		_escape()
		get_viewport().set_input_as_handled()
		return
	if hud.is_menu_open():
		return
	if cam_rig.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var p: Variant = ground_at(mb.position)
			if p != null:
				builder.on_click(p)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			builder.on_right()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				builder.finish()
			KEY_R:
				builder.rotate()
			KEY_L:
				game.set_utility_view(not game.utility_view)
			KEY_M:
				_toggle_map()
			KEY_B:
				hud.toggle_build()
			KEY_I:
				game.set_interior_view(not game.interior_view)
			KEY_SPACE:
				_set_speed(1 if game.speed == 0 else 0)
			KEY_1:
				_set_speed(1)
			KEY_2:
				_set_speed(2)
			KEY_3:
				_set_speed(3)
			KEY_F5:
				game.save_game()
			KEY_F9:
				_load()
			KEY_DELETE:
				builder.set_tool("abriss")
			KEY_Z:
				if k.ctrl_pressed:
					game.undo_last()


var _map_back: Array = []   # [Ziel, Zoom] vor der Kartenübersicht


## Ganze Karte zeigen und wieder zurück zum vorherigen Ausschnitt.
func _toggle_map() -> void:
	if _map_back.is_empty():
		_map_back = [cam_rig.target, cam_rig.zoom_goal]
		var size := viewport.get_visible_rect().size
		cam_rig.frame(Rect2(-GameState.MAP_HALF, -GameState.MAP_HALF, GameState.MAP_HALF * 2.0, GameState.MAP_HALF * 2.0),
			size.x / maxf(size.y, 1.0))
		hud.show_map(true)
	else:
		cam_rig.target = _map_back[0]
		cam_rig.zoom_goal = _map_back[1]
		_map_back = []
		hud.show_map(false)


## Esc: Menü schließen oder zurück, laufenden Weg abbrechen, sonst Menü öffnen.
func _escape() -> void:
	if hud.is_menu_open():
		hud.menu_back()
	elif builder.is_drawing():
		builder.cancel()
	else:
		hud.open_menu()


## Nur für Vorschaubilder: Flugbetrieb vorspulen, optional Werkzeug zeigen, Screenshot speichern.
func _demo(args: PackedStringArray) -> void:
	var shot := ""
	var mode := "bauen"
	for a in args:
		if a.begins_with("--shot="):
			shot = a.substr(7)
		if a.begins_with("--mode="):
			mode = a.substr(7)
		if a.begins_with("--zeit="):
			game.minutes = float(a.substr(7)) * 60.0
	for i in range(2400):
		flights.step(0.05)
	set_process(false)
	sun.directional_shadow_max_distance = cam_rig.shadow_range()
	if mode == "karte":
		_toggle_map()
		cam_rig.zoom = cam_rig.zoom_goal
		hud.set_build_open(false)
	elif mode in ["rollhalt", "piste", "vorfeld", "anflug"]:
		var spots := {"rollhalt": [Vector3(-872, 0, -186), 70.0], "piste": [Vector3(-842, 0, -272), 70.0],
			"vorfeld": [Vector3(-10, 0, -75), 300.0], "anflug": [Vector3(-1150, 0, -272), 520.0]}
		for i in range(1200):
			flights.step(0.05)
		cam_rig.target = spots[mode][0]
		cam_rig.zoom_goal = spots[mode][1]
		cam_rig.zoom = spots[mode][1]
	elif mode in ["pushback", "bus", "rollen", "haltestelle"]:
		var found: Dictionary = {}
		for i in range(12000):
			flights.step(0.05)
			for p: Dictionary in flights.planes:
				if mode == "pushback" and p["state"] == "pushback" and float(p.get("ps", 0.0)) > 25.0:
					found = p
				if mode == "rollen" and p["state"] == "rollt_ein" and float(p["speed"]) < 6.0 and (p["pos"] as Vector3).z > -230.0:
					found = p
			if mode == "bus":
				for j: Dictionary in ops.jobs.values():
					if j.has("bus") and bool(j.get("unloading", false)) and ops.walkers.size() > 8:
						found = j["flight"]
			if mode == "haltestelle":
				for j: Dictionary in ops.jobs.values():
					if j.has("dep_bus") and bool(j.get("dep_called", false)) and int(j.get("dep_out", 0)) > 5:
						found = {"pos": Vector3(-5, 0, -25)}
			if not found.is_empty():
				break
		var at: Vector3 = found.get("pos", Vector3(-60, 0, -55))
		cam_rig.target = at + Vector3(0, 0, -6 if mode == "pushback" else 4)
		cam_rig.zoom_goal = 85.0
		cam_rig.zoom = 85.0
	elif mode == "bauen":
		cam_rig.target = Vector3(-20, 0, -40)
		cam_rig.zoom_goal = 230.0
		cam_rig.zoom = 230.0
		builder.set_tool("rollweg")
		builder.on_click(Vector3(-150, 0, -95))
		builder.on_click(Vector3(-190, 0, -120))
		builder.on_move(Vector3(-200, 0, -170))
	elif mode.begins_with("modelle"):
		# Schaufenster aller Detailmodelle auf einer freien Wiese
		var base := Vector3(600, 0, 600)
		var Factory = load("res://scripts/factory.gd")
		var showcase := Node3D.new()
		world.add_child(showcase)
		var i := 0
		for kind: String in Catalog.PLANES:
			var pl: Node3D = Factory.make_plane(kind, Catalog.AIRLINES[i % Catalog.AIRLINES.size()][1])
			pl.position = base + Vector3(-110 + 50 * i + (12 if kind == "a330" else 0), 0, 0)
			pl.rotation.y = deg_to_rad(-90)
			showcase.add_child(pl)
			i += 1
		var gx := -20.0
		for g: String in ["tank", "catering", "gepaeck"]:
			var v: Node3D = Factory.make_gse(g)
			v.position = base + Vector3(gx, 0, 26)
			showcase.add_child(v)
			gx += 7.0
		var cx := 4.0
		for kind: String in ["kompakt", "limousine", "kombi", "suv", "transporter", "taxi"]:
			var car: Node3D = Factory.make_car(Factory.CAR_COLORS[int(cx) % Factory.CAR_COLORS.size()], kind)
			car.position = base + Vector3(cx, 0, 26)
			showcase.add_child(car)
			cx += 3.0
		for k in range(12):
			var per: Node3D = Factory.make_person(Factory.SHIRTS[k % Factory.SHIRTS.size()])
			per.position = base + Vector3(-20 + k * 1.0, 0, 34)
			Factory.set_pose(per, k % 6)
			showcase.add_child(per)
		cam_rig.target = base + (Vector3(0, 0, 10) if mode == "modelle" else Vector3(-14, 0, 33))
		cam_rig.zoom_goal = 75.0 if mode == "modelle" else 14.0
		if mode == "modelle_a320" or mode == "modelle_b737":
			cam_rig.target = base + Vector3(-22 if mode == "modelle_a320" else 22, 0, 0)
			cam_rig.zoom_goal = 26.0
		cam_rig.zoom = cam_rig.zoom_goal
	elif mode == "tower" or mode == "hangar" or mode == "feuerwache":
		var at := {"tower": Vector3(190, 0, -40), "hangar": Vector3(-200, 0, -48), "feuerwache": Vector3(330, 0, -55)}
		cam_rig.target = at[mode]
		cam_rig.zoom_goal = 70.0
		cam_rig.zoom = 70.0
	elif mode == "parkhaus":
		game.traffic_demand = 6
		for i in range(900):
			traffic.step(0.1)
		cam_rig.yaw = 225.0
		cam_rig.yaw_goal = 225.0
		cam_rig.target = Vector3(-40, 0, 34)
		cam_rig.zoom_goal = 48.0
		cam_rig.zoom = 48.0
	elif mode == "verkehr" or mode == "ampel":
		if mode == "ampel":
			roads.cycle_control(Vector3(115, 0, 35))
			roads.cycle_control(Vector3(115, 0, 35))
		game.traffic_demand = 6
		for i in range(700):
			traffic.step(0.1)
		cam_rig.target = Vector3(-30, 0, 20) if mode == "verkehr" else Vector3(112, 0, 40)
		cam_rig.zoom_goal = 70.0 if mode == "verkehr" else 45.0
		cam_rig.zoom = cam_rig.zoom_goal
	elif mode == "kreuzung":
		cam_rig.target = Vector3(-110, 0, 60)
		cam_rig.zoom_goal = 120.0
		cam_rig.zoom = 120.0
		builder.set_tool("strasse")
		builder.on_click(Vector3(-130, 0, 130))
		builder.on_move(Vector3(-100, 0, -10))
	elif mode == "halle":
		cam_rig.target = Vector3(-120, 0, 40)
		cam_rig.zoom_goal = 150.0
		cam_rig.zoom = 150.0
		builder.set_tool("halle")
		builder.on_click(Vector3(-170, 0, 10))
		builder.on_move(Vector3(-110, 0, 46))
		hud._show_tab("ausstattung")
	elif mode == "status":
		cam_rig.target = Vector3(-170, 0, -60)
		cam_rig.zoom_goal = 160.0
		cam_rig.zoom = 160.0
		hud.show_tool("terminal")
	elif mode == "leitungen":
		cam_rig.target = Vector3(60, 0, 10)
		cam_rig.zoom_goal = 200.0
		cam_rig.zoom = 200.0
		builder.set_tool("stromkabel")
		builder.on_click(Vector3(64, 0, 54))
		builder.on_move(Vector3(-150, 0, -40))
	elif mode == "terminal" or mode == "menu" or mode == "einstellungen":
		cam_rig.target = Vector3(-2, 0, -8)
		cam_rig.zoom_goal = 66.0
		cam_rig.zoom = 66.0
		game.set_interior_view(true)
		for i in range(900):
			flights.step(0.05)
		if mode != "terminal":
			hud.open_menu()
			if mode == "einstellungen":
				hud.menu_page.visible = false
				hud.settings_page.visible = true
		else:
			_inspect(Vector3(20, 0, 5))
			hud._show_tab("terminal")
	elif mode == "abfertigung" or mode == "bruecke":
		var parked: Dictionary = {}
		for i in range(4000):
			flights.step(0.05)
			for p: Dictionary in flights.planes:
				if p["state"] == "abfertigung" and float(p["timer"]) < float(p["turn"]) * 0.6:
					if mode != "bruecke" or not bool(p.get("bus", true)):
						parked = p
			if not parked.is_empty():
				break
		var at: Vector3 = parked.get("pos", Vector3(-60, 0, -55))
		cam_rig.target = at + Vector3(0, 0, 8)
		cam_rig.zoom_goal = 95.0
		cam_rig.zoom = 95.0
		if not parked.is_empty():
			_inspect(at)
	hud.set_clock(game.clock_text())
	hud.set_flights(flights.rows(), flights.check_operation(), flights.done, flights.hint)
	hud.set_economy(game.satisfaction, game.satisfaction_factors, game.day_income, game.upkeep_per_day())
	_daylight()
	for i in range(120):
		await get_tree().process_frame
	if shot != "":
		get_viewport().get_texture().get_image().save_png(shot)
		print("screenshot ", shot)
	get_tree().quit()
