extends Node3D
## Wetter: klar, bewölkt, Regen, Nebel und Schnee. Es wechselt alle paar Spielstunden langsam und wirkt
## auf Optik (Regen- und Schneeflocken um die Kamera, Bodennebel, nasse und verschneite Flächen über
## die globalen Shaderwerte "wet", "snow", "rwy_snow") und auf den Flugbetrieb:
## - Nebel: Landungen nur mit Anflugbefeuerung (CAT I) und leuchtender Pistenbefeuerung, sonst Warten.
## - Regen: etwas weniger Flüge, längere Bremswege.
## - Schnee: Schnee sammelt sich auf der Piste; ist zu viel liegen geblieben, wird sie gesperrt und
##   geräumt (mit Winterdienst rasch durch einen Räumkonvoi, sonst lange). Vor dem Start wird enteist.

const Models = preload("res://scripts/models.gd")
const GameState = preload("res://scripts/game_state.gd")

const NAMES := {"klar": "Klar", "wolken": "Bewölkt", "regen": "Regen", "nebel": "Nebel", "schnee": "Schneefall"}
## Wahrscheinlichkeit beim Wetterwechsel
const ODDS := [["klar", 0.36], ["wolken", 0.28], ["regen", 0.16], ["nebel", 0.1], ["schnee", 0.1]]

var game: GameState
var cam: Node3D                 # iso_camera.gd (Ziel und Zoom für die Partikel)
var state := "klar"
var strength := 0.0             # 0..1, blendet beim Wechsel weich ein
var next_change := 240.0        # Spielminuten bis zum nächsten Wechsel
var forced := ""                # Szenario: festes Wetter
var snow_cover := 0.0           # Schneedecke auf Wiese und Dächern 0..1
var wet := 0.0                  # Nässe 0..1
var runway_snow := 0.0          # Schnee auf Pisten und Wegen 0..1
var plowing := 0.0              # Restminuten der Pistenräumung
var plow_total := 0.0
var plow_path := PackedVector3Array()
var plow_nodes: Array = []
var _rain: CPUParticles3D
var _flakes: CPUParticles3D
var _mist: Array = []           # Nebelschwaden: drei waagrechte Schichten um die Kamera


func setup(g: GameState, camera: Node3D) -> void:
	game = g
	cam = camera
	_rain = _particles(Vector2(0.035, 1.2), Color(0.75, 0.82, 0.92, 0.45), 2600, 1.1)
	_rain.direction = Vector3(0.12, -1, 0.05)
	_rain.spread = 2.0
	_rain.initial_velocity_min = 60.0
	_rain.initial_velocity_max = 75.0
	_flakes = _particles(Vector2(0.16, 0.16), Color(0.97, 0.98, 1.0, 0.9), 2200, 7.0)
	_flakes.direction = Vector3(0.25, -1, 0.1)
	_flakes.spread = 18.0
	_flakes.initial_velocity_min = 7.0
	_flakes.initial_velocity_max = 11.0
	var sh := load("res://shaders/mist.gdshader")
	for i in range(3):
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(2.0, 2.0)
		mi.mesh = pm
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("seed", float(i) * 1.7)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_mist.append(mi)


func _particles(size: Vector2, col: Color, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if size.y > size.x * 2.0 else BaseMaterial3D.BILLBOARD_ENABLED
	q.material = m
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.gravity = Vector3.ZERO
	p.local_coords = false
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


## Wetter für ein Szenario festlegen ("" = wieder zufällig).
func force(s: String) -> void:
	forced = s
	if s != "":
		state = s
		strength = 1.0


func is_snow() -> bool:
	return state == "schnee" and strength > 0.3


func is_fog() -> bool:
	return state == "nebel" and strength > 0.5


func has_winter_service() -> bool:
	for it: Dictionary in game.items_of("winterdienst"):
		if game.supplied(it, "strom"):
			return true
	return false


## Wie stark das Wetter den Flugplan ausdünnt (Faktor auf den Abstand neuer Flüge).
func spawn_factor() -> float:
	match state:
		"regen":
			return lerpf(1.0, 1.12, strength)
		"nebel":
			return lerpf(1.0, 1.35, strength)
		"schnee":
			return lerpf(1.0, 1.25, strength)
	return 1.0


## Zusätzliche Bodenzeit für die Enteisung vor dem Start (Spielminuten), 0 ohne Schnee.
func deice_minutes() -> float:
	if not is_snow() and snow_cover < 0.3:
		return 0.0
	return 4.0 if has_winter_service() else 12.0


func runway_closed() -> bool:
	return plowing > 0.0


## Muss die Piste geräumt werden (und darf die Räumung beginnen, sobald sie frei ist)?
func needs_plowing() -> bool:
	return plowing <= 0.0 and runway_snow > 0.55


## Räumung beginnen: mit Winterdienst fährt ein Konvoi aus drei Räumfahrzeugen die Piste ab.
func start_plowing(samples: PackedVector3Array) -> void:
	var service := has_winter_service()
	plow_total = 6.0 if service else 28.0
	plowing = plow_total
	plow_path = samples
	_clear_plows()
	if service and samples.size() > 1:
		for i in range(3):
			var mi := MeshInstance3D.new()
			mi.mesh = Models.plow_mesh()
			add_child(mi)
			plow_nodes.append(mi)
	game.toast.emit("Piste gesperrt: Schnee wird geräumt" + (" (Winterdienst unterwegs)" if service else " – ohne Winterdienst dauert es lange"))


func _clear_plows() -> void:
	for n: Node in plow_nodes:
		n.queue_free()
	plow_nodes.clear()


func step(game_minutes: float) -> void:
	if forced == "":
		next_change -= game_minutes
		if next_change <= 0.0:
			next_change = randf_range(150.0, 420.0)
			var r := randf()
			var acc := 0.0
			var pick := "klar"
			for o: Array in ODDS:
				acc += float(o[1])
				if r <= acc:
					pick = o[0]
					break
			if pick != state:
				state = pick
				strength = 0.0
				if state != "klar" and state != "wolken":
					game.toast.emit("Wetter: %s zieht auf" % String(NAMES[state]))
	strength = minf(1.0, strength + game_minutes / 25.0)
	var raining := state == "regen"
	var snowing := state == "schnee"
	wet = move_toward(wet, 1.0 if raining else (0.4 if snowing else 0.0), game_minutes / (20.0 if raining else 90.0))
	snow_cover = move_toward(snow_cover, 1.0 if snowing else 0.0, game_minutes / (60.0 if snowing else 240.0))
	if snowing:
		runway_snow = minf(1.0, runway_snow + game_minutes / 70.0 * strength)
	else:
		runway_snow = maxf(0.0, runway_snow - game_minutes / 150.0)
	if plowing > 0.0:
		plowing = maxf(0.0, plowing - game_minutes)
		var f := 1.0 - plowing / maxf(plow_total, 0.01)
		runway_snow = minf(runway_snow, lerpf(runway_snow, 0.05, f))
		if plowing <= 0.0:
			runway_snow = 0.05
			_clear_plows()
			game.toast.emit("Piste geräumt, Betrieb läuft wieder")
	RenderingServer.global_shader_parameter_set(&"snow", snow_cover)
	RenderingServer.global_shader_parameter_set(&"wet", wet)
	RenderingServer.global_shader_parameter_set(&"rwy_snow", runway_snow)


func _process(_delta: float) -> void:
	if cam == null:
		return
	var z: float = cam.get("zoom")
	var t: Vector3 = cam.get("target")
	var show := z < 900.0
	var w := clampf(z * 1.1, 60.0, 900.0)
	for p: CPUParticles3D in [_rain, _flakes]:
		p.global_position = t + Vector3(0, 60.0 if p == _rain else 30.0, 0)
		p.emission_box_extents = Vector3(w, 25.0, w)
	_rain.emitting = show and state == "regen" and strength > 0.2
	_flakes.emitting = show and state == "schnee" and strength > 0.2
	# Nebelschwaden in 1,5 / 4 / 8 m Höhe, nachts dunkler
	var fogamt := strength if state == "nebel" else 0.0
	var night: float = game.night if game != null else 0.0
	var wd := deg_to_rad(float(game.wind_dir)) if game != null else 0.0
	for i in range(_mist.size()):
		var mi: MeshInstance3D = _mist[i]
		mi.visible = fogamt > 0.02 and show and not (game.interior_view and game.view_floor < 0)
		if mi.visible:
			mi.global_position = Vector3(t.x, [1.5, 4.0, 8.0][i], t.z)
			mi.scale = Vector3(w * 1.6, 1.0, w * 1.6)
			var mat := mi.material_override as ShaderMaterial
			mat.set_shader_parameter("amount", fogamt * [0.55, 0.42, 0.3][i])
			mat.set_shader_parameter("col", Color(0.86, 0.88, 0.9).lerp(Color(0.2, 0.22, 0.27), night))
			mat.set_shader_parameter("drift", Vector2(sin(wd), -cos(wd)) * -1.0)
	_move_plows()


## Räumkonvoi: drei Fahrzeuge versetzt über die Pistenlänge, hin und zurück.
func _move_plows() -> void:
	if plow_nodes.is_empty() or plow_path.size() < 2:
		return
	var a := plow_path[0]
	var b := plow_path[plow_path.size() - 1]
	var dir := (b - a).normalized()
	var right := dir.cross(Vector3.UP)
	var f := 1.0 - plowing / maxf(plow_total, 0.01)
	var leg := fmod(f * 2.0, 1.0)
	var back := f >= 0.5
	for i in range(plow_nodes.size()):
		var mi: MeshInstance3D = plow_nodes[i]
		var s := clampf(leg - float(i) * 0.03, 0.0, 1.0)
		var pos := a.lerp(b, (1.0 - s) if back else s) + right * (float(i) - 1.0) * 6.5 * (-1.0 if back else 1.0)
		mi.position = pos + Vector3(0, 0.1, 0)
		var fwd := -dir if back else dir
		mi.basis = Basis.looking_at(fwd, Vector3.UP)


## Licht nach Wetter dämpfen (nach dem Tageslicht aufrufen).
var flash := 0.0   # Blitz bei Gewitter (Ereignisse), klingt schnell ab


func apply_light(sun: DirectionalLight3D, env: Environment) -> void:
	if flash > 0.0:
		sun.light_energy += flash * 2.5
		env.ambient_light_energy += flash * 2.0
	var dim := 0.0
	match state:
		"wolken":
			dim = 0.35
		"regen":
			dim = 0.55
		"nebel":
			dim = 0.5
		"schnee":
			dim = 0.45
	dim *= strength
	sun.light_energy *= 1.0 - dim
	env.ambient_light_energy *= 1.0 + dim * 0.25
	var fog := state == "nebel" or state == "schnee" or state == "regen"
	env.fog_enabled = fog and strength > 0.02
	if env.fog_enabled:
		# Bodennebel: dicht am Boden, Dächer, Tower und Masten ragen heraus; nicht mehr alles gleich grau
		env.fog_light_color = Color(0.74, 0.77, 0.8).lerp(Color(0.16, 0.18, 0.23), game.night)
		env.fog_light_energy = 1.0
		env.fog_density = 0.0
		env.fog_sky_affect = 0.0
		env.fog_height = 9.0 if state == "nebel" else 40.0
		env.fog_height_density = (0.012 if state == "nebel" else (0.008 if state == "schnee" else 0.004)) * strength


func status_text() -> String:
	var t := String(NAMES.get(state, state))
	if plowing > 0.0:
		t += " · Piste wird geräumt (%d Min)" % ceili(plowing)
	elif runway_snow > 0.3:
		t += " · Schnee auf der Piste"
	return t


func save_data() -> Dictionary:
	return {"state": state, "next": next_change, "snow": snow_cover, "wet": wet, "rwy": runway_snow, "forced": forced}


func load_data(d: Dictionary) -> void:
	state = String(d.get("state", "klar"))
	strength = 1.0
	next_change = float(d.get("next", 240.0))
	snow_cover = float(d.get("snow", 0.0))
	wet = float(d.get("wet", 0.0))
	runway_snow = float(d.get("rwy", 0.0))
	forced = String(d.get("forced", ""))
	plowing = 0.0
	_clear_plows()
