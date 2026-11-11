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
const Weather = preload("res://scripts/weather.gd")
const Operations = preload("res://scripts/operations.gd")
const Events = preload("res://scripts/events.gd")
const Overlay = preload("res://scripts/overlay.gd")
const Sound = preload("res://scripts/sound.gd")
const RESUME_FLAG := "user://nach_update_laden"
const Catalog = preload("res://scripts/catalog.gd")
const GROUND_SHADER = preload("res://shaders/ground.gdshader")

var container: SubViewportContainer
var viewport: SubViewport
var world: Node3D
var sun: DirectionalLight3D
var env: Environment
var ground_mat: ShaderMaterial
var ground: MeshInstance3D
var cam_rig: IsoCamera
var game: GameState
var builder: Builder
var traffic: Traffic
var roads: Roads
var flights: Flights
var terminal: Terminal
var ops: GroundOps
var airfield: Airfield
var weather: Weather
var betrieb: Operations
var events: Events
var overlay: Overlay
var person_t := 0.0
var sound: Sound
var lod_far := false
var show_fps := false
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
	for gp: StringName in [&"snow", &"wet", &"rwy_snow"]:
		RenderingServer.global_shader_parameter_add(gp, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
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
	ops.flights_ref = flights
	terminal.bus_cb = ops.pax_at_door
	airfield = Airfield.new()
	airfield.name = "Flugfeld"
	world.add_child(airfield)
	airfield.setup(game)
	game.network_changed.connect(_update_ground_cuts)
	game.items_changed.connect(_update_ground_cuts)
	cam_rig = IsoCamera.new()
	cam_rig.name = "Kamera"
	world.add_child(cam_rig)
	weather = Weather.new()
	weather.name = "Wetter"
	world.add_child(weather)
	weather.setup(game, cam_rig)
	betrieb = Operations.new()
	betrieb.name = "Betrieb"
	add_child(betrieb)
	betrieb.setup(game)
	betrieb.flights = flights
	betrieb.terminal = terminal
	betrieb.traffic = traffic
	betrieb.weather = weather
	flights.weather = weather
	flights.betrieb = betrieb
	events = Events.new()
	events.name = "Ereignisse"
	add_child(events)
	events.game = game
	events.terminal = terminal
	events.ops = ops
	events.flights = flights
	events.weather = weather
	flights.events = events
	if "--demo" in OS.get_cmdline_user_args() or "--selftest" in OS.get_cmdline_user_args():
		events.enabled = false
	overlay = Overlay.new()
	overlay.name = "Overlay"
	world.add_child(overlay)
	overlay.game = game
	overlay.terminal = terminal
	overlay.flights = flights
	sound = Sound.new()
	sound.name = "Geraeusche"
	add_child(sound)
	sound.game = game
	sound.flights = flights
	sound.ops = ops
	sound.terminal = terminal
	sound.weather = weather
	if "--demo" in OS.get_cmdline_user_args() or "--selftest" in OS.get_cmdline_user_args():
		sound.enabled = false
	terminal.betrieb = betrieb
	game.income_cb = betrieb.book_income
	game.move_guard = _move_guard
	game.before_save.connect(_collect_extra)
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
		if game.load_game():
			_after_load()
	builder.set_tool("")
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--dbg="):
			var probe: Node = load("res://tests/dbg/%s.gd" % a.substr(6)).new()
			add_child(probe)
			probe.call("run", self)
			return
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
	ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(8000, 8000)
	ground.mesh = pm
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = GROUND_SHADER
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(ground)


## Offene Tunnelrampen schneiden Löcher in den Rasen.
func _update_ground_cuts() -> void:
	var cuts := game.tunnel_cuts()
	var a := PackedVector4Array()
	var b := PackedVector2Array()
	for c: Array in cuts.slice(0, 48):
		a.append(Vector4(c[0], c[1], c[2], c[3]))
		b.append(Vector2(c[4], c[5]))
	while a.size() < 48:
		a.append(Vector4.ZERO)
		b.append(Vector2.ZERO)
	ground_mat.set_shader_parameter("cut_a", a)
	ground_mat.set_shader_parameter("cut_b", b)
	ground_mat.set_shader_parameter("cut_n", mini(cuts.size(), 48))


func _make_thumbs() -> void:
	var ids := []
	for cat: Array in Catalog.CATEGORIES:
		ids.append_array(cat[2])
	ids.append("kopieren")
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
	hud.wall_mode_requested.connect(func() -> void: game.cycle_wall_mode())
	hud.overlay_requested.connect(func() -> void: hud.show_overlay(Overlay.NAMES[overlay.cycle()]))
	hud.section_toggled.connect(game.set_section_view)
	game.view_mode_changed.connect(func() -> void: hud.show_view_modes(game.wall_mode, game.section_view))
	hud.menu_opened.connect(_on_menu)
	hud.quit_requested.connect(func() -> void: get_tree().quit())
	hud.setting_changed.connect(_on_setting)
	hud.restart_requested.connect(_restart_for_update)
	hud.downloads_requested.connect(updater.open_downloads)
	hud.map_requested.connect(_toggle_map)
	hud.floor_step.connect(_on_floor_step)
	hud.option_changed.connect(_on_option)
	game.floor_changed.connect(_on_floor)
	updater.status_changed.connect(_on_update_status)
	game.interior_changed.connect(hud.show_interior)
	game.day_ended.connect(_on_day_ended)
	builder.info.connect(hud.set_info)
	builder.tool_changed.connect(_on_tool_changed)
	builder.inspect_requested.connect(_inspect)
	builder.mode_changed.connect(hud.show_draw_modes)
	builder.hint.connect(hud.set_hint)
	hud.draw_mode_selected.connect(builder.set_mode)
	hud.snap_toggled.connect(builder.set_snapping)
	hud.side_selected.connect(builder.set_side)
	hud.room_option.connect(builder.set_room_option)
	builder.side_changed.connect(hud.show_side)
	builder.steps.connect(hud.set_steps)
	hud.ops_ref = betrieb
	hud.fees_ref = game
	hud.events_ref = events
	hud.fee_changed.connect(func(key: String, dir: int) -> void: game.set_fee(key, dir))
	hud.night_ban_toggled.connect(func() -> void: game.night_ban = not game.night_ban)
	hud.clearance_requested.connect(_on_clearance)
	hud.atc_toggled.connect(_on_atc)
	hud.contract_requested.connect(betrieb.sign)
	hud.scenario_requested.connect(_start_scenario)
	hud.tutorial_requested.connect(_on_tutorial)
	hud.spot_requested.connect(_on_spot)
	game.money_changed.connect(hud.set_money)
	game.toast.connect(hud.toast)
	game.view_changed.connect(_on_view_changed)
	hud.set_money(game.money)


func _on_clearance(id: int) -> void:
	var t: String = flights.clearance(id)
	if t != "":
		hud.toast(t)


func _on_atc(on: bool) -> void:
	game.atc_manual = on
	hud.toast("Lotsenmodus: Landung, Pushback und Start gibst du im Flugplan frei" if on else "Freigaben wieder automatisch")
	if not on:
		for p: Dictionary in flights.planes.duplicate():
			p["frei_push"] = true
			p["frei_start"] = true
			if p["state"] == "warteschleife":
				flights.clearance(int(p["id"]))


func _on_tutorial() -> void:
	betrieb.start_tutorial()
	hud.toast("Lernschritte gestartet")


func _on_spot(pos: Vector3) -> void:
	cam_rig.target = pos
	cam_rig.zoom_goal = 180.0


func _new_map() -> void:
	builder.set_tool("")
	flights.clear()
	game.clear_all()
	betrieb.start_scenario("")
	betrieb.start_tutorial()
	hud.toast("Leere Karte, 30 Mio. € Startkapital")


## Szenario: Startflughafen neu aufbauen, Budget und Wetter nach Vorgabe.
func _start_scenario(key: String) -> void:
	builder.set_tool("")
	flights.clear()
	game.clear_all()
	game.load_starter()
	game.minutes = 6.0 * 60.0
	betrieb.start_scenario(key)
	_apply_sandbox()
	traffic.dirty = true


func _load() -> void:
	flights.clear()
	if game.load_game():
		_after_load()


## Wert eines Kommandozeilen-Arguments (--name=wert) oder der Vorgabewert.
func _arg(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for a in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback


## Ältere Spielstände: Bereiche im Terminal aus Wänden und Kontrolle ableiten.
## Wetter, Betrieb (Statistik, Verträge, Szenario) und Flotte aus dem Spielstand übernehmen.
func _after_load() -> void:
	_apply_sandbox.call_deferred()
	for h: Dictionary in game.items_of("halle"):
		terminal.auto_zones(h)
	var ex: Dictionary = game.extra
	weather.load_data(ex.get("wetter", {}))
	betrieb.load_data(ex.get("betrieb", {}))
	flights.load_data(ex.get("flotte", {}))
	hud.set_atc(game.atc_manual)


func _collect_extra() -> void:
	game.extra = {"wetter": weather.save_data(), "betrieb": betrieb.save_data(), "flotte": flights.save_data()}


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
		"sandkasten":
			_apply_sandbox()
		"lautstaerke":
			sound.set_volume(float(v))
		"fps":
			show_fps = bool(v)
		"ereignisse":
			if not ("--demo" in OS.get_cmdline_user_args() or "--selftest" in OS.get_cmdline_user_args()):
				events.enabled = bool(v)


## Sandkasten nach Einstellung, in Szenarien immer aus.
func _apply_sandbox() -> void:
	game.sandbox = bool(settings.get_value("sandkasten")) and betrieb.scenario == ""
	hud.sandbox = game.sandbox
	hud.set_money(game.money)
	builder._refresh()


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
		sun.light_energy = 0.2 * smoothstep(-0.04, -0.3, elev)
		sun.light_color = Color(0.62, 0.68, 0.9)
	# Nacht: gedämpftes, kaum gefärbtes Mondlicht; die Lampen setzen die warmen Akzente
	env.ambient_light_color = Color(0.66, 0.70, 0.78).lerp(Color(0.3, 0.33, 0.42), night).lerp(Color(0.85, 0.68, 0.6), dusk * (1.0 - night) * 0.35)
	env.ambient_light_energy = lerpf(0.62, 0.4, night)
	env.background_color = Color(0.36, 0.42, 0.3).lerp(Color(0.07, 0.09, 0.14), night)
	weather.apply_light(sun, env)
	if game.interior_view and game.view_floor < 0:
		# Untergeschoss: dunkel, nur Lampen in Tunneln und Kanälen leuchten
		env.background_color = Color(0.05, 0.05, 0.06)
		sun.light_energy = minf(sun.light_energy, 0.3)
		env.ambient_light_energy = 0.5
		RenderingServer.global_shader_parameter_set(&"night", 0.85)
		game.night = 0.85


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
	hud.set_clock(game.clock_text() + ("  · %d fps" % Engine.get_frames_per_second() if show_fps else ""))
	if sound.cam == null:
		sound.cam = cam_rig
	# Detailstufe: weit herausgezoomt Menschen, laufende Koffer und Einrichtung unter den Dächern ausblenden
	var far := cam_rig.zoom > 260.0 and not game.interior_view
	if far != lod_far:
		lod_far = far
		terminal.crowd.visible = not far
		game.set_lod_far(far)
	person_t -= delta
	if person_t <= 0.0 and not terminal.selected_person.is_empty():
		person_t = 0.5
		if terminal.selected_person in terminal.people:
			var d: Array = terminal.describe_person(terminal.selected_person, flights)
			hud.set_info(String(d[0]), String(d[1]), 0)
		else:
			terminal.selected_person = {}
	ui_timer -= delta
	if ui_timer <= 0.0:
		ui_timer = 0.25
		var status := flights.check_operation()
		if status == "" and flights.reason != "":
			status = flights.reason
		hud.set_flights(flights.rows(), status, flights.done, flights.hint, flights.wind_text())
		hud.set_economy(game.satisfaction, game.satisfaction_factors, game.day_income, game.upkeep_per_day())
		_update_heat()


## Info-Werkzeug: Details zu Flugzeug, Gebäude oder Weg unter dem Mauszeiger.
var _selected: Dictionary = {}
var _selected_at := Vector3.ZERO


func _on_option(key: String, dir: int) -> void:
	if _selected.is_empty():
		return
	var why := game.cycle_option(_selected, key, dir)
	if why != "":
		hud.toast(why)
	_inspect(_selected_at)


## Ebene gewechselt: im Keller verschwindet die Oberfläche, damit man hineinsieht.
## Ebene wechseln; außerhalb der Innenansicht schaltet der erste Schritt sie ein.
func _on_floor_step(d: int) -> void:
	if not game.interior_view:
		game.set_interior_view(true)
		if d < 0:
			game.set_view_floor(-1)
		return
	if d > 0 and game.view_floor >= game.floor_range().y:
		# oberste Ebene: der Halle unter der Kamera (sonst der größten) ein Stockwerk aufsetzen
		var h := game.hall_at(cam_rig.target)
		if h.is_empty():
			for it: Dictionary in game.items_of("halle"):
				if h.is_empty() or (it["rect"] as Rect2).get_area() > (h["rect"] as Rect2).get_area():
					h = it
		if h.is_empty():
			game.toast.emit("Erst eine Terminalhalle bauen")
			return
		if game.hall_levels(h) >= 3:
			game.toast.emit("Höchstens drei Ebenen je Halle")
			return
		var why := game.cycle_option(h, "etagen", 1)
		if why != "":
			game.toast.emit(why)
			return
		game.toast.emit("Neue Ebene: " + game.floor_name(game.hall_levels(h) - 1) + " – Rolltreppe, Treppe oder Aufzug im Geschoss darunter verbinden")
	game.set_view_floor(game.view_floor + d)


func _on_floor(f: int) -> void:
	hud.show_floor(f)
	var under := game.interior_view and f < 0
	ground.visible = not under
	# Untergeschoss: nur Tunnel, Förderbänder und Keller; Flugfeld, Flugzeuge und Vorfeld ausblenden
	for nd: Node3D in [airfield, flights, ops, roads.visuals]:
		if nd != null:
			nd.visible = not under
	for nd: Node in get_tree().get_nodes_in_group("oberirdisch"):
		(nd as Node3D).visible = not under
	env.background_color = Color(0.08, 0.08, 0.09) if under else Color(0.36, 0.42, 0.3)
	_update_grid()


func _inspect(p: Vector3) -> void:
	_selected = {}
	_selected_at = p
	hud.set_options([])
	terminal.selected_person = {}
	if game.interior_view:
		var per: Dictionary = terminal.person_at(p)
		if not per.is_empty():
			terminal.selected_person = per
			var d: Array = terminal.describe_person(per, flights)
			hud.set_info(String(d[0]), String(d[1]), 0)
			return
	var plane := flights.pick(p)
	if not plane.is_empty():
		hud.set_info("Flug " + String(plane["code"]), flights.describe(plane), 0)
		return
	var rec := game.pick(p)
	if rec.is_empty():
		hud.set_info("Ansehen", "Hier ist nichts gebaut.", 0)
		return
	_selected = rec
	hud.set_options(game.options_of(rec))
	var body := game.details(rec)
	if rec.get("id", "") == "halle":
		body = terminal.hall_summary(rec) + "\n" + body
	if rec.get("id", "") in ["parkhaus", "parkplatz"]:
		var spaces := 75 * int(game.opt(rec, "etagen")) if rec["id"] == "parkhaus" else 22
		body = ("Zufahrt: verbunden" if traffic.has_access(rec) else "Keine Zufahrt: vor der Einfahrt muss eine Straße liegen") \
			+ "\nBelegt: %d von %d Plätzen" % [traffic.parked_count(rec), spaces] + "\n" + body
	if rec.get("id", "") in ["gate", "busgate"]:
		body = "Gate %d (Gepäckbänder lassen sich im Infofeld des Bands einem Gate zuordnen)\n" % terminal.gate_number(rec) + body
	if rec.get("id", "") == "gepaeckband":
		var fid := int(terminal.belt_load.get((rec["node"] as Node).get_instance_id(), -1))
		body = ("Band läuft für Flug %s\n" % flights.code_of(fid) if fid >= 0 else "Band steht\n") + body
	if rec.get("id", "") in ["stand", "stand_aussen", "stand_gross", "stand_f"]:
		body = "Flugplatzcode %s: passt für Flugzeuge bis %s\n" % [String(Catalog.ITEMS[rec["id"]].get("code", "C")),
			{"C": "A321/B737", "E": "A350/B787/B767", "F": "A380"}.get(String(Catalog.ITEMS[rec["id"]].get("code", "C")), "")] + body
	if rec.get("id", "") in ["stand", "stand_aussen", "stand_gross", "stand_f"]:
		body = ("Zufahrt: an die Betriebsstraße angeschlossen" if ops.stand_connected(rec)
			else "Keine Zufahrt: am Kopf des Stands (Nasenseite) eine Betriebsstraße bis auf 16 m heranführen") + "\n" + body
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
	var h := float(game.view_floor) * Catalog.FLOOR_H if game.interior_view else 0.0
	return Plane(Vector3.UP, h).intersects_ray(from, dir)


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
			# Ziehen beenden (Räume, Hallen, Bereiche, Wände, Flächenabriss)
			if mb.button_index == MOUSE_BUTTON_LEFT:
				var rp: Variant = ground_at(mb.position)
				if rp != null:
					builder.on_release(rp)
			return
		hud.release_search()
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
		if k.alt_pressed and k.keycode >= KEY_1 and k.keycode <= KEY_9:
			hud.open_category(int(k.keycode - KEY_1))
			return
		if k.ctrl_pressed and k.keycode == KEY_F:
			hud.focus_search()
			return
		match k.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				builder.finish()
			KEY_TAB:
				builder.cycle_mode()
			KEY_V:
				builder.cycle_side()
			KEY_G:
				builder.set_snapping(not builder.snapping)
				hud.show_snapping(builder.snapping)
				game.toast.emit("Einrasten " + ("an" if builder.snapping else "aus"))
			KEY_R:
				builder.rotate()
			KEY_L:
				game.set_utility_view(not game.utility_view)
			KEY_M:
				_toggle_map()
			KEY_PAGEUP:
				_on_floor_step(1)
			KEY_PAGEDOWN:
				_on_floor_step(-1)
			KEY_B:
				hud.toggle_build()
			KEY_I:
				game.set_interior_view(not game.interior_view)
			KEY_H:
				game.cycle_wall_mode()
			KEY_O:
				hud.show_overlay(Overlay.NAMES[overlay.cycle()])
			KEY_J:
				game.set_section_view(not game.section_view)
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
			KEY_F2:
				hud.toggle_ops()
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
		if a.begins_with("--wetter="):
			weather.force(a.substr(9))
			weather.snow_cover = 1.0 if a.substr(9) == "schnee" else 0.0
			weather.wet = 1.0 if a.substr(9) == "regen" else 0.0
			weather.runway_snow = 0.45 if a.substr(9) == "schnee" else 0.0
	for i in range(2400):
		flights.step(0.05)
	set_process(false)
	sun.directional_shadow_max_distance = cam_rig.shadow_range()
	if mode == "karte":
		_toggle_map()
		cam_rig.zoom = cam_rig.zoom_goal
		hud.set_build_open(false)
	elif mode == "landung":
		# einem landenden Flugzeug folgen (Klappen, Spoiler, Landescheinwerfer)
		var zl := float(_arg(args, "--zoom=", "70"))
		var want := _arg(args, "--phase=", "landung")
		for i in range(20000):
			flights.step(0.05)
			var hit: Dictionary = {}
			for p: Dictionary in flights.planes:
				if want == "landung" and p["state"] == "landung" and float(p["speed"]) < 50.0:
					hit = p
				elif want == "anflug" and p["state"] == "anflug" and not p.has("approach") and (p["pos"] as Vector3).distance_to(p["td"]) < 700.0:
					hit = p
				elif want == "start" and p["state"] == "start" and float(p["alt"]) > 15.0:
					hit = p
			if not hit.is_empty():
				cam_rig.target = Vector3((hit["pos"] as Vector3).x, 0, (hit["pos"] as Vector3).z)
				flights.set_process(false)
				break
		cam_rig.zoom_goal = zl
		cam_rig.zoom = zl
		hud.set_build_open(false)
	elif mode in ["rollhalt", "piste", "vorfeld", "anflug"]:
		var spots := {"rollhalt": [Vector3(-872, 0, -186), 70.0], "piste": [Vector3(-842, 0, -272), 70.0],
			"vorfeld": [Vector3(-10, 0, -75), 300.0], "anflug": [Vector3(-1150, 0, -272), 520.0]}
		for i in range(1200):
			flights.step(0.05)
		cam_rig.target = spots[mode][0]
		cam_rig.zoom_goal = spots[mode][1]
		cam_rig.zoom = spots[mode][1]
	elif mode == "moebel":
		# Schaufenster der Einrichtung in einer eigenen Halle
		var hall := game.build_hall(Rect2(560, 560, 64, 40), true, {})
		var ids := ["uhr", "lounge", "bistrotisch", "snackautomat", "getraenkeautomat", "geldautomat", "trinkbrunnen",
			"werbebildschirm", "ladestation", "kofferwagen", "massagesessel", "muelltrennung", "spielecke", "aquarium",
			"palme", "baumbeet", "gruenwand", "springbrunnen", "fluegel", "flugzeugmodell", "fahnen", "infoschalter", "kiosk", "rollsteig"]
		var x := 564.0
		var z := 566.0
		var row_h := 0.0
		for id: String in ids:
			var sz: Vector2 = Catalog.ITEMS[id]["size"]
			if x + sz.x > 620.0:
				x = 564.0
				z += row_h + 3.0
				row_h = 0.0
			game.build_item(id, Vector3(x + sz.x * 0.5, 0, z + sz.y * 0.5), 0, true)
			x += sz.x + 2.5
			row_h = maxf(row_h, sz.y)
		game.set_interior_view(true)
		var zl := 40.0
		var tgt := Vector3(586, 0, 578)
		for a in args:
			if a.begins_with("--zoom="):
				zl = float(a.substr(7))
			if a.begins_with("--at="):
				var xz := a.substr(5).split(",")
				tgt = Vector3(float(xz[0]), 0, float(xz[1]))
		cam_rig.target = tgt
		cam_rig.zoom_goal = zl
		cam_rig.zoom = zl
		hud.set_build_open(false)
	elif mode == "einrichtung":
		# alle Terminal-Bauteile mit Varianten in einer eigenen Halle
		game.build_hall(Rect2(560, 560, 70, 44), true, {})
		var plan := [["checkin", 566, 566, 0, {}], ["sicherheit", 578, 568, 0, {}], ["gepaeckband", 592, 566, 0, {}],
			["gepaeckband", 606, 566, 0, {"stil": "karussell"}], ["gepaeckanlage", 622, 567, 0, {}],
			["gate", 568, 582, 0, {}], ["busgate", 581, 582, 0, {"bereich": "non_schengen"}], ["wc", 593, 581, 0, {}],
			["cafe", 604, 582, 0, {}], ["cafe", 614, 582, 0, {"stil": "bar"}], ["shop", 625, 582, 0, {"stil": "dutyfree"}],
			["shop", 566, 596, 0, {"stil": "buecher"}], ["shop", 576, 596, 0, {"stil": "elektronik"}], ["cafe", 586, 596, 0, {"stil": "baeckerei"}],
			["sitzreihe", 596, 595, 0, {}], ["pflanze", 600, 597, 0, {}], ["anzeige", 605, 595, 0, {}], ["kunst", 612, 596, 0, {}],
			["heizkoerper", 618, 594, 0, {}], ["sb_ausgang", 624, 595, 0, {}], ["eingang", 590, 603, 0, {"tuer": "dreh"}], ["eingang", 600, 603, 0, {}]]
		for e: Array in plan:
			game.build_item(String(e[0]), Vector3(float(e[1]), 0, float(e[2])), int(e[3]), true, e[4])
		game.set_interior_view(true)
		var zl := 46.0
		var tgt := Vector3(595, 0, 581)
		for a in args:
			if a.begins_with("--zoom="):
				zl = float(a.substr(7))
			if a.begins_with("--at="):
				var xz := a.substr(5).split(",")
				tgt = Vector3(float(xz[0]), 0, float(xz[1]))
		cam_rig.target = tgt
		cam_rig.zoom_goal = zl
		cam_rig.zoom = zl
		hud.set_build_open(false)
	elif mode == "landseite":
		# Linienbus an der Haltestelle, Fußgänger zum Terminal
		traffic.set_process(false)
		var seen := false
		for i in range(3000):
			traffic.step(0.1)
			for m: Dictionary in traffic.movers:
				if m["purpose"] == "bus" and float(m["halt"]) > 9.0:
					seen = true
			if seen:
				break
		var zl := 48.0
		var tgt := Vector3(-40, 0, 26)
		for a in args:
			if a.begins_with("--zoom="):
				zl = float(a.substr(7))
		cam_rig.target = tgt
		cam_rig.zoom_goal = zl
		cam_rig.zoom = zl
		hud.set_build_open(false)
	elif mode == "untergrund":
		# Ansicht Untergeschoss: Gepäckförderband und ein Straßentunnel
		game.build_line("tunnel", [Vector3(-215, 0, 110), Vector3(-290, 0, 185), Vector3(-330, 0, 300), Vector3(-330, 0, 420)], true)
		game.build_line("strasse", [Vector3(-330, 0, 420), Vector3(-330, 0, 520)], true)
		if not ("--flach" in args):
			game.set_interior_view(true)
			game.set_view_floor(-1)
		traffic.set_process(false)
		for i in range(600):
			traffic.step(0.1)
		var at := Vector3(140, 0, -8)
		for a in args:
			if a.begins_with("--at="):
				var xz := a.substr(5).split(",")
				at = Vector3(float(xz[0]), 0, float(xz[1]))
		cam_rig.target = at
		cam_rig.zoom_goal = 90.0
		cam_rig.zoom = 90.0
		hud.set_build_open(false)
	elif mode == "blick":
		# freier Blick: Flugbetrieb vorspulen, Kamera nach --at, --zoom, --yaw, optional --innen
		for i in range(int(_arg(args, "--schritte=", "1500"))):
			flights.step(0.05)
		var xz := _arg(args, "--at=", "-15,-15").split(",")
		cam_rig.target = Vector3(float(xz[0]), 0, float(xz[1]))
		cam_rig.zoom_goal = float(_arg(args, "--zoom=", "300"))
		cam_rig.zoom = cam_rig.zoom_goal
		var yb := _arg(args, "--yaw=", "")
		if yb != "":
			cam_rig.yaw = float(yb)
			cam_rig.yaw_goal = cam_rig.yaw
		if "--innen" in args:
			game.set_interior_view(true)
	elif mode == "tor" or mode == "feuer":
		# Rolltor geht auf: Gerätehalle (Fahrzeug fährt zum Stand) oder Feuerwache (Löschfahrzeug rückt aus)
		var want := float(_arg(args, "--f=", "0.6"))
		var focus: Vector3 = Vector3(-160, 0, -20)
		ops.fire_t = 9999.0
		if mode == "feuer":
			ops._fire_mission("kontrolle", null, 0.0)
		for i in range(20000):
			flights.step(0.05)
			var hit := false
			for key: String in ops.door_open:
				var o := float(ops.door_open[key])
				if o >= want and o < want + 0.08 and ops.door_rec.has(key):
					var e: Array = ops.door_rec[key]
					if (mode == "feuer") != (String((e[0] as Dictionary)["id"]) == "feuerwache"):
						continue
					focus = (e[0] as Dictionary)["pos"]
					hit = true
			if hit and i > 40:
				break
		for i in range(int(_arg(args, "--nach=", "0"))):
			flights.step(0.05)
		cam_rig.target = focus + Vector3(0, 0, 6)
		cam_rig.zoom_goal = float(_arg(args, "--zoom=", "42"))
		cam_rig.zoom = cam_rig.zoom_goal
		var yw := _arg(args, "--yaw=", "")
		if yw != "":
			cam_rig.yaw = float(yw)
			cam_rig.yaw_goal = cam_rig.yaw
	elif mode == "dienste":
		# Abfertigung am Stand: Fahrzeuge bei einem bestimmten Anteil der Abfertigungszeit
		var want_f := 0.28
		for a in args:
			if a.begins_with("--f="):
				want_f = float(a.substr(4))
		var found: Dictionary = {}
		for i in range(16000):
			flights.step(0.05)
			for p: Dictionary in flights.planes:
				if p["state"] == "abfertigung" and not bool(p.get("bus", false)):
					var f := 1.0 - float(p["timer"]) / maxf(float(p["turn"]), 0.01)
					if f >= want_f:
						found = p
			if not found.is_empty():
				break
		var at: Vector3 = found.get("pos", Vector3(-40, 0, -55))
		var h: Vector3 = found.get("heading", Vector3(0, 0, 1))
		var zoom := 62.0
		for a in args:
			if a.begins_with("--zoom="):
				zoom = float(a.substr(7))
		cam_rig.target = at + h.cross(Vector3.UP) * 9.0
		cam_rig.zoom_goal = zoom
		cam_rig.zoom = zoom
		hud.set_build_open(false)
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
		# Kurven-Werkzeug: Straße setzt am Ende der Bestandsstraße tangential fort
		cam_rig.target = Vector3(-230, 0, 150)
		cam_rig.zoom_goal = 120.0
		cam_rig.zoom = 120.0
		builder.set_tool("strasse")
		builder.set_mode("kurve")
		builder.on_move(Vector3(-215, 0, 110))
		builder.on_click(Vector3(-215, 0, 110))
		builder.on_move(Vector3(-235, 0, 200))
	elif mode == "strassen":
		# Straßenraum: Allee vor dem Terminal mit Bushaltestelle, Radweg an der Querstraße
		var at := Vector3(-30, 0, 34)
		var zz := 70.0
		for a in args:
			if a.begins_with("--zoom="):
				zz = float(a.substr(7))
			if a.begins_with("--at="):
				var xz := a.substr(5).split(",")
				at = Vector3(float(xz[0]), 0, float(xz[1]))
			if a.begins_with("--yaw="):
				cam_rig.yaw = float(a.substr(6))
				cam_rig.yaw_goal = cam_rig.yaw
		cam_rig.target = at
		cam_rig.zoom_goal = zz
		cam_rig.zoom = zz
		hud.set_build_open(false)
		if "--szene" in args:
			# freie Kreuzung: Radweg-Straße, Allee, 4-spurige Straße mit Gehweg, Bus- und Taxibucht
			game.build_line("strasse", [Vector3(400, 0, 300), Vector3(520, 0, 300)], true, false, "rad")
			game.build_line("strasse", [Vector3(520, 0, 300), Vector3(640, 0, 300)], true, false, "rad")
			game.build_line("strasse", [Vector3(520, 0, 180), Vector3(520, 0, 300)], true, false, "allee")
			game.build_line("strasse4", [Vector3(520, 0, 300), Vector3(520, 0, 420)], true, false, "gehweg")
			for sp: Array in [["haltestelle", Vector3(462, 0, 288)], ["taxistand", Vector3(585, 0, 312)], ["haltestelle", Vector3(532, 0, 360)]]:
				var snap: Array = game.stop_snap(String(sp[0]), sp[1])
				if not snap.is_empty():
					game.build_item(String(sp[0]), snap[0], int(snap[1]), true)
		for i in range(400):
			traffic.step(0.1)
	elif mode == "ersetzen":
		# Ersetzen: Bestandsstraße unter dem Zeiger wird zur 4-spurigen
		cam_rig.target = Vector3(-200, 0, 120)
		cam_rig.zoom_goal = 120.0
		cam_rig.zoom = 120.0
		builder.set_tool("strasse4")
		builder.set_mode("ersetzen")
		var on_road := Vector3(-215, 0, 110)
		for l: Dictionary in game.lines:
			var sm: PackedVector3Array = l["samples"]
			if l["kind"] == "strasse" and (sm[0].distance_to(on_road) < 3.0 or sm[sm.size() - 1].distance_to(on_road) < 3.0):
				on_road = sm[mini(14, sm.size() - 1)] if sm[0].distance_to(on_road) < 3.0 else sm[maxi(sm.size() - 15, 0)]
		cam_rig.target = on_road
		builder.on_move(on_road)
	elif mode.begins_with("modelle"):
		# Schaufenster aller Detailmodelle auf einer freien Wiese
		var base := Vector3(600, 0, 600)
		var Factory = load("res://scripts/factory.gd")
		var showcase := Node3D.new()
		world.add_child(showcase)
		var i := 0
		var px := -130.0
		for kind: String in Catalog.PLANES:
			var al: Array = Catalog.AIRLINES[i % Catalog.AIRLINES.size()]
			var pl: Node3D = Factory.make_plane(kind, al[1], int(al[2]), mode == "modelle_fracht")
			var plen := float(Catalog.PLANES[kind]["nose"]) * 2.0
			pl.position = base + Vector3(px + plen * 0.5, 0, 0)
			px += plen + 8.0
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
			car.rotation.y = PI if int(cx) % 2 == 1 else 0.0
			showcase.add_child(car)
			cx += 3.0
		for k in range(12):
			var per: Node3D = Factory.make_person(Factory.SHIRTS[k % Factory.SHIRTS.size()])
			per.position = base + Vector3(-20 + k * 1.0, 0, 34)
			Factory.set_pose(per, k % 6)
			showcase.add_child(per)
		# neue Bauten ab 0.13
		var bx := -60.0
		for bid: String in ["frachtterminal", "winterdienst", "bahnhof", "mietwagen", "taxistand", "kissandfly"]:
			var bn: Node3D = Factory.make_item(bid)
			var bsz: Vector2 = Catalog.ITEMS[bid]["size"]
			bn.position = base + Vector3(bx + bsz.x * 0.5, 0, 130)
			showcase.add_child(bn)
			bx += bsz.x + 10.0
		for vk: Array in [["pflug", Vector3(-40, 0, 95)], ["enteiser", Vector3(-30, 0, 95)], ["lader", Vector3(-18, 0, 95)]]:
			var vm := MeshInstance3D.new()
			var Mo2 = load("res://scripts/models.gd")
			vm.mesh = Mo2.plow_mesh() if vk[0] == "pflug" else (Mo2.deicer_mesh() if vk[0] == "enteiser" else Mo2.loader_mesh(4.0))
			vm.position = base + (vk[1] as Vector3)
			showcase.add_child(vm)
		if mode == "modelle_bauten":
			for c in showcase.get_children():
				var bz := c as Node3D
				if bz != null and bz.has_method("get_meta") and bz.name == "bahnhof":
					var zg := bz.get_node_or_null("Zug") as Node3D
					if zg != null:
						zg.visible = true
		# Fahrzeugreihe: alle Bodenfahrzeuge, Busse und Feuerwehr nebeneinander
		var Lm = load("res://scripts/landmarks.gd")
		var Mo = load("res://scripts/models.gd")
		var row := [["linienbus", 9.0], ["bus", 10.0], ["schlepper", 9.0], ["gepaeckschlepper", 4.0], ["wagen", 4.0], ["bandlader", 5.0],
			["catering_basis", 6.0], ["tank", 6.0], ["gpu", 4.0], ["treppe", 6.0], ["feuer", 7.0], ["rtw", 6.0]]
		var fx := -30.0
		for e: Array in row:
			var mi := MeshInstance3D.new()
			var kind: String = e[0]
			match kind:
				"linienbus":
					mi.mesh = Mo.city_bus_mesh(Color(0.86, 0.72, 0.16))
				"treppe":
					mi.mesh = Mo.stairs_mesh(3.4)
				"feuer":
					mi.mesh = Lm.fire_truck_mesh()
				"rtw":
					mi.mesh = Lm.rtw_mesh()
				_:
					mi.mesh = Mo.gse_mesh(kind)
			mi.position = base + Vector3(fx, 0, 50)
			showcase.add_child(mi)
			fx += float(e[1])
		cam_rig.target = base + (Vector3(0, 0, 10) if mode == "modelle" else Vector3(-14, 0, 33))
		cam_rig.zoom_goal = 75.0 if mode == "modelle" else 14.0
		if mode == "modelle_fahrzeuge":
			cam_rig.target = base + Vector3(10, 0, 50)
			cam_rig.zoom_goal = 34.0
		if mode == "modelle_autos":
			cam_rig.target = base + Vector3(12, 0, 26)
			cam_rig.zoom_goal = 11.0
		if mode == "modelle_a320" or mode == "modelle_b737":
			cam_rig.target = base + Vector3(-22 if mode == "modelle_a320" else 22, 0, 0)
			cam_rig.zoom_goal = 26.0
		for a in args:
			if a.begins_with("--at="):
				var axz := a.substr(5).split(",")
				cam_rig.target = base + Vector3(float(axz[0]), 0, float(axz[1]))
			elif a.begins_with("--zoom="):
				cam_rig.zoom_goal = float(a.substr(7))
			elif a.begins_with("--yaw="):
				cam_rig.yaw = float(a.substr(6))
				cam_rig.yaw_goal = cam_rig.yaw
		cam_rig.zoom = cam_rig.zoom_goal
	elif mode == "tower" or mode == "hangar" or mode == "feuerwache":
		var at: Vector3 = Vector3.ZERO
		for it: Dictionary in game.items_of(mode):
			at = it["pos"]
		for a in args:
			if a.begins_with("--at="):
				var xz := a.substr(5).split(",")
				at = Vector3(float(xz[0]), 0, float(xz[1]))
		cam_rig.target = at
		cam_rig.zoom_goal = 70.0
		for a in args:
			if a.begins_with("--zoom="):
				cam_rig.zoom_goal = float(a.substr(7))
			elif a.begins_with("--yaw="):
				cam_rig.yaw = float(a.substr(6))
				cam_rig.yaw_goal = cam_rig.yaw
		cam_rig.zoom = cam_rig.zoom_goal
	elif mode == "parkhaus":
		game.traffic_demand = 6
		for i in range(900):
			traffic.step(0.1)
		cam_rig.yaw = 225.0
		cam_rig.yaw_goal = 225.0
		cam_rig.target = Vector3(-40, 0, 34)
		cam_rig.zoom_goal = 48.0
		for a in args:
			if a.begins_with("--zoom="):
				cam_rig.zoom_goal = float(a.substr(7))
			elif a.begins_with("--yaw="):
				cam_rig.yaw = float(a.substr(6))
				cam_rig.yaw_goal = cam_rig.yaw
			elif a.begins_with("--at="):
				var xz := a.substr(5).split(",")
				cam_rig.target = Vector3(float(xz[0]), 0, float(xz[1]))
		cam_rig.zoom = cam_rig.zoom_goal
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
		var tz := 66.0
		var tt := Vector3(-2, 0, -8)
		for a in args:
			if a.begins_with("--zoom="):
				tz = float(a.substr(7))
			if a.begins_with("--at="):
				var xz := a.substr(5).split(",")
				tt = Vector3(float(xz[0]), 0, float(xz[1]))
		cam_rig.target = tt
		cam_rig.zoom_goal = tz
		cam_rig.zoom = tz
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
	var ob := _arg(args, "--betrieb=", "")
	if ob != "":
		hud.ops_tab = ob
		hud.show_ops(true)
	if "--lotse" in args:
		game.atc_manual = true
		hud.set_atc(true)
	var tab := _arg(args, "--tab=", "")
	if tab != "":
		hud._show_tab(tab, false)
	var such := _arg(args, "--suche=", "")
	if such != "":
		hud.search_edit.text = such
		hud._apply_search(such)
	for i in range(60):
		await get_tree().process_frame
	var scroll := _arg(args, "--scroll=", "")
	if scroll != "":
		hud.strip_scroll.scroll_horizontal = int(scroll)
	for i in range(60):
		await get_tree().process_frame
	if shot != "":
		get_viewport().get_texture().get_image().save_png(shot)
		print("screenshot ", shot)
	get_tree().quit()


# ---------------------------------------------------------------- Engpass-Karte

var _heat_root: Node3D = null
var _heat_mat: StandardMaterial3D = null


## Solange die Statistik offen ist: rote Flecken dort, wo Flugzeuge am längsten gewartet haben.
func _update_heat() -> void:
	var show: bool = hud.ops_window != null and hud.ops_window.visible and hud.ops_tab == "statistik"
	if not show:
		if _heat_root != null:
			_heat_root.queue_free()
			_heat_root = null
		return
	if _heat_root == null:
		_heat_root = Node3D.new()
		_heat_root.name = "Engpaesse"
		world.add_child(_heat_root)
		_heat_mat = StandardMaterial3D.new()
		_heat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_heat_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_heat_mat.no_depth_test = true
		_heat_mat.albedo_color = Color(1.0, 0.2, 0.1, 0.38)
	for c in _heat_root.get_children():
		c.queue_free()
	var spots: Array = betrieb.hotspots(14)
	var mx := 1.0
	for e: Array in spots:
		mx = maxf(mx, float(e[1]))
	for e: Array in spots:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var r := 8.0 + 30.0 * sqrt(float(e[1]) / mx)
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = 0.2
		cm.radial_segments = 24
		mi.mesh = cm
		mi.material_override = _heat_mat
		mi.position = (e[0] as Vector3) + Vector3(0, 0.5, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_heat_root.add_child(mi)


## Verschieben: belegte Stände bleiben, wo sie sind.
func _move_guard(rec: Dictionary) -> String:
	if String(rec["id"]) in GameState.STAND_IDS:
		for p: Dictionary in flights.planes:
			if is_same(p["stand"], rec):
				return "Stand ist belegt: erst verschieben, wenn das Flugzeug weg ist"
	return ""

