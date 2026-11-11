extends Node
## Geräusche, ohne Tondateien im Code erzeugt (AudioStreamWAV, 22 kHz, 16 Bit):
## Gong vor Durchsagen (beim Boarding), Triebwerksrauschen (rollende und startende Flugzeuge in der
## Nähe), Stimmengewirr (Innenansicht), Regen, Donner nach Blitzen, Martinshorn am Rettungswagen,
## Warnpiepen an fahrenden Rolltoren. Lautstärke aus der Einstellung "lautstaerke", 0 = aus.

const RATE := 22050

var game: Variant = null
var flights: Variant = null
var ops: Variant = null
var terminal: Variant = null
var weather: Variant = null
var cam: Variant = null

var volume := 0.7
var streams: Dictionary = {}
var players: Dictionary = {}
var _todo := ["gong", "jet", "crowd", "rain", "thunder", "horn", "beep"]
var _flash_was := 0.0
var _thunder_t := -1.0
var enabled := true


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		enabled = false


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)


## Ein Geräusch je Bild erzeugen, damit der Start nicht hängt.
func _make_next() -> void:
	if _todo.is_empty():
		return
	var key: String = _todo.pop_front()
	streams[key] = _gen(key)
	var loop := key in ["jet", "crowd", "rain", "beep"]
	if loop:
		var p := AudioStreamPlayer.new()
		p.stream = streams[key]
		p.volume_db = -80.0
		p.name = "Ton_" + key
		add_child(p)
		p.play()
		players[key] = p


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _gen(key: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var s := PackedFloat32Array()
	match key:
		"gong":
			# Dreiklang wie am Flughafen: G – E – C, jeder Ton klingt aus
			var notes := [783.99, 659.25, 523.25]
			s.resize(int(RATE * 2.4))
			for n in range(3):
				var start := int(RATE * 0.55 * float(n))
				for i in range(int(RATE * 1.3)):
					var t := float(i) / RATE
					var env := exp(-t * 2.6)
					var v := (sin(TAU * float(notes[n]) * t) + 0.3 * sin(TAU * float(notes[n]) * 2.0 * t)) * env * 0.35
					if start + i < s.size():
						s[start + i] += v
		"jet":
			# Rauschen mit tiefem Grollen und leichtem Pfeifen
			s.resize(RATE * 2)
			var lp := 0.0
			var lp2 := 0.0
			for i in range(s.size()):
				var t := float(i) / RATE
				var w := rng.randf_range(-1.0, 1.0)
				lp += (w - lp) * 0.05
				lp2 += (w - lp2) * 0.25
				s[i] = lp * 1.6 + lp2 * 0.25 + sin(TAU * 1800.0 * t) * 0.02
			_fade_loop(s)
		"crowd":
			# Stimmengewirr: gefiltertes Rauschen, langsam schwankend, ein paar Silben
			s.resize(RATE * 3)
			var lp := 0.0
			for i in range(s.size()):
				var t := float(i) / RATE
				var w := rng.randf_range(-1.0, 1.0)
				lp += (w - lp) * 0.12
				var mod := 0.6 + 0.4 * sin(TAU * 3.1 * t) * sin(TAU * 0.7 * t)
				s[i] = lp * mod * 1.2 + sin(TAU * (180.0 + 40.0 * sin(TAU * 2.3 * t)) * t) * 0.03 * mod
			_fade_loop(s)
		"rain":
			s.resize(RATE * 2)
			var hp := 0.0
			var prev := 0.0
			for i in range(s.size()):
				var w := rng.randf_range(-1.0, 1.0)
				hp = 0.85 * (hp + w - prev)
				prev = w
				s[i] = hp * 0.25 + (0.4 if rng.randf() < 0.002 else 0.0)
			_fade_loop(s)
		"thunder":
			s.resize(RATE * 3)
			var lp := 0.0
			for i in range(s.size()):
				var t := float(i) / RATE
				var w := rng.randf_range(-1.0, 1.0)
				lp += (w - lp) * 0.02
				var env := (1.0 - exp(-t * 30.0)) * exp(-t * 1.1) * (0.7 + 0.3 * sin(TAU * 1.7 * t))
				s[i] = lp * env * 4.0
		"horn":
			# Martinshorn: 440 Hz und 585 Hz im Wechsel, je 0,75 s, leicht rechteckig
			s.resize(int(RATE * 1.5))
			for i in range(s.size()):
				var t := float(i) / RATE
				var f := 440.0 if t < 0.75 else 585.0
				var v := sin(TAU * f * t)
				s[i] = clampf(v * 1.8, -1.0, 1.0) * 0.3
		"beep":
			s.resize(int(RATE * 0.8))
			for i in range(s.size()):
				var t := float(i) / RATE
				s[i] = (sin(TAU * 1600.0 * t) * 0.25) if t < 0.3 else 0.0
	return _wav(s, key in ["jet", "crowd", "rain", "horn", "beep"])


## Schleifenränder glätten, damit es nicht knackt.
static func _fade_loop(s: PackedFloat32Array) -> void:
	var n := mini(800, s.size() / 4)
	for i in range(n):
		var f := float(i) / float(n)
		var j := s.size() - n + i
		s[j] = s[j] * (1.0 - f) + s[i] * f


func play(key: String, db: float = 0.0) -> void:
	if not enabled or volume <= 0.0 or not streams.has(key):
		return
	var p := AudioStreamPlayer.new()
	p.stream = streams[key]
	p.volume_db = db + linear_to_db(volume)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _set_loop(key: String, level: float) -> void:
	var p: AudioStreamPlayer = players.get(key)
	if p == null:
		return
	var target := -80.0 if level <= 0.001 or volume <= 0.0 else linear_to_db(level * volume)
	p.volume_db = lerpf(p.volume_db, target, 0.08)


func _process(delta: float) -> void:
	if not enabled:
		return
	_make_next()
	if game == null or cam == null:
		return
	var focus: Vector3 = cam.target
	var zoom: float = cam.zoom
	var near := clampf(1.0 - (zoom - 40.0) / 500.0, 0.15, 1.0)
	# Triebwerke: rollende, startende und landende Flugzeuge in der Nähe der Kamera
	var jet := 0.0
	if flights != null:
		for p: Dictionary in flights.planes:
			var st := String(p["state"])
			if not (st in ["rollt_ein", "rollt_aus", "start", "landung", "pushback", "wartet"]):
				continue
			var d := (p["pos"] as Vector3).distance_to(focus)
			var loud := 1.0 if st in ["start", "landung"] else 0.45
			jet += loud * clampf(1.0 - d / (300.0 + zoom * 2.0), 0.0, 1.0)
		# Gong, wenn das Boarding eines Flugs beginnt (nur einmal je Flug)
		for p: Dictionary in flights.planes:
			if String(p["state"]) == "abfertigung" and not p.has("gong"):
				var f := 1.0 - float(p.get("timer", 0.0)) / maxf(float(p.get("turn", 1.0)), 0.01)
				if f >= 0.3:
					p["gong"] = true
					if game.interior_view or zoom < 200.0:
						play("gong", -6.0)
	_set_loop("jet", clampf(jet, 0.0, 1.0) * 0.55 * near)
	var people := 0
	if terminal != null:
		people = (terminal.people as Array).size()
	_set_loop("crowd", (0.5 if game.interior_view else 0.12) * clampf(float(people) / 60.0, 0.0, 1.0) * near)
	var rain := 0.0
	if weather != null and String(weather.state) == "regen":
		rain = float(weather.strength) * 0.5
	_set_loop("rain", rain)
	# Donner kurz nach dem Blitz
	if weather != null:
		var fl := float(weather.flash)
		if fl > 0.9 and _flash_was <= 0.9:
			_thunder_t = 0.6
		_flash_was = fl
	if _thunder_t >= 0.0:
		_thunder_t -= delta
		if _thunder_t < 0.0:
			play("thunder", -2.0)
	# Rolltore in Bewegung: Warnpiepen, lauter, je näher an der Kamera
	var beep := 0.0
	if ops != null:
		for key: String in ops.door_open:
			var o := float(ops.door_open[key])
			if o > 0.03 and o < 0.97 and ops.door_rec.has(key):
				var rec: Dictionary = (ops.door_rec[key] as Array)[0]
				if is_instance_valid(rec.get("node")):
					var d := (rec["pos"] as Vector3).distance_to(focus)
					beep = maxf(beep, clampf(1.0 - d / (120.0 + zoom), 0.0, 1.0))
		_horns(focus, zoom)
	_set_loop("beep", beep * 0.4 * near)


## Martinshorn als 3D-Ton am Rettungswagen, solange das Blaulicht an ist.
func _horns(focus: Vector3, zoom: float) -> void:
	if not streams.has("horn"):
		return
	for j: Dictionary in ops.rtw_jobs:
		var v: Dictionary = j["v"]
		var node: Variant = v.get("node")
		if not is_instance_valid(node):
			continue
		var hp := (node as Node).get_node_or_null("Horn") as AudioStreamPlayer3D
		var on := bool(v.get("blau", false)) and String(j["phase"]) == "hin" and volume > 0.0
		if hp == null and on:
			hp = AudioStreamPlayer3D.new()
			hp.name = "Horn"
			hp.stream = streams["horn"]
			hp.unit_size = 60.0
			hp.max_distance = 1500.0
			(node as Node).add_child(hp)
		if hp != null:
			hp.volume_db = linear_to_db(volume * 0.6)
			if on and not hp.playing:
				hp.play()
			elif not on and hp.playing:
				hp.stop()
