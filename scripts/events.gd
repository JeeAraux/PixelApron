extends Node
## Ereignisse im Betrieb: medizinische Notfälle (im Terminal und an Bord), Bandausfall, Stromausfall,
## Streik, Gewitter und Vogelschlag. Alle 4–10 Minuten (Spielsekunden) eines, zufällig gewichtet.
## Eigene Zufallsfolge, damit der übrige Ablauf (und der Selbsttest) davon unberührt bleibt.
## flights.gd ruft step(sim) auf. trigger(art) löst ein Ereignis sofort aus (Selbsttest, Szenarien).

const Catalog = preload("res://scripts/catalog.gd")
const Kit = preload("res://scripts/mesh_kit.gd")

var game: Variant = null
var terminal: Variant = null
var ops: Variant = null
var flights: Variant = null
var weather: Variant = null

var enabled := true
var rng := RandomNumberGenerator.new()
var next_t := 300.0
var active: Array = []        # laufende Ereignisse
var history: Array = []       # [Spielminute, Text] der letzten Ereignisse
var clock := 0.0

const KINDS := [["notfall_terminal", 3], ["notfall_bord", 2], ["bandausfall", 2], ["stromausfall", 1],
	["streik", 1], ["gewitter", 1], ["vogelschlag", 1]]


func _ready() -> void:
	rng.randomize()


func step(sim: float) -> void:
	clock += sim
	for e: Dictionary in active.duplicate():
		_step_event(e, sim)
	if weather != null and float(weather.flash) > 0.0:
		weather.flash = maxf(0.0, float(weather.flash) - sim * 5.0)
	if not enabled:
		return
	next_t -= sim
	if next_t > 0.0:
		return
	next_t = rng.randf_range(240.0, 600.0)
	var total := 0
	for k: Array in KINDS:
		total += int(k[1])
	var pick := rng.randi() % total
	for k: Array in KINDS:
		pick -= int(k[1])
		if pick < 0:
			trigger(String(k[0]))
			break


func _say(text: String) -> void:
	history.append([float(game.minutes), text])
	while history.size() > 12:
		history.pop_front()
	game.toast.emit(text)


func busy(kind: String) -> bool:
	for e: Dictionary in active:
		if String(e["kind"]) == kind:
			return true
	return false


## Ereignis auslösen. false, wenn es gerade nicht passt (kein Fluggast, kein Band …).
func trigger(kind: String) -> bool:
	match kind:
		"notfall_terminal":
			return _medical_terminal()
		"notfall_bord":
			return _medical_flight()
		"bandausfall":
			return _belt_failure()
		"stromausfall":
			return _power_failure()
		"streik":
			if busy("streik"):
				return false
			terminal.staff_factor = 0.6
			terminal.dirty = true
			active.append({"kind": "streik", "t": 0.0, "dur": 600.0})
			_say("Warnstreik: 40 % des Personals legen die Arbeit nieder (10 Minuten), die Abfertigung dauert länger")
			return true
		"gewitter":
			if busy("gewitter"):
				return false
			flights.storm = true
			ops.storm = true
			var prev := ""
			if weather != null:
				prev = String(weather.forced)
				if String(weather.state) != "schnee":
					weather.force("regen")
			active.append({"kind": "gewitter", "t": 0.0, "dur": 150.0, "next_flash": 2.0, "prev": prev})
			_say("Gewitter über dem Flughafen: Blitzwarnung, die Arbeit auf dem Vorfeld ruht")
			return true
		"vogelschlag":
			return _bird_strike()
	return false


func _step_event(e: Dictionary, sim: float) -> void:
	e["t"] = float(e["t"]) + sim
	match String(e["kind"]):
		"notfall_terminal":
			var per: Dictionary = e["per"]
			var info: Dictionary = e["info"]
			if bool(info.get("done", false)) or (not bool(e["rtw"]) and float(e["t"]) > 150.0):
				terminal.carry_away(per)
				active.erase(e)
				if bool(e["rtw"]) and info.has("arrived"):
					var secs := float(info["arrived"]) - float(info["sent"])
					_say("Patient versorgt und mit dem Rettungswagen abtransportiert (nach %d s vor Ort%s)" % [roundi(secs),
						", Anfahrt von außerhalb" if bool(info.get("outside", false)) else ""])
					if secs > 90.0:
						game.satisfaction = maxf(0.0, game.satisfaction - 2.0)
				else:
					_say("Der Fluggast ist wieder auf den Beinen")
		"notfall_bord":
			var p: Dictionary = e["plane"]
			if not (p in flights.planes):
				active.erase(e)
				return
			if not bool(e["sent"]) and String(p["state"]) in ["rollt_ein", "abfertigung"]:
				var st: Dictionary = p.get("stand", {})
				if not st.is_empty():
					var b := Basis(Vector3.UP, float(st["rot"]) * PI * 0.5)
					var target: Vector3 = (st["pos"] as Vector3) + b * Vector3(14.0, 0, 6.0)
					e["sent"] = ops.send_rtw(target, b * Vector3(0, 0, -1), 45.0, e["info"])
					if not bool(e["sent"]):
						active.erase(e)
			if bool((e["info"] as Dictionary).get("done", false)):
				active.erase(e)
				_say("Notfall an Bord von %s: Patient an den Rettungsdienst übergeben" % p["code"])
		"bandausfall":
			var l: Dictionary = e["line"]
			if float(e["t"]) >= float(e["dur"]) or not (l in game.lines):
				if l in game.lines:
					l.erase("broken")
					var nd: Variant = l["node"]
					if is_instance_valid(nd):
						var w := (nd as Node).get_node_or_null("Stoerung")
						if w != null:
							w.queue_free()
				game._routes_dirty = true
				terminal.dirty = true
				terminal.recall_technicians()
				active.erase(e)
				_say("Kofferband repariert, die Koffer laufen wieder")
		"stromausfall":
			var rec: Dictionary = e["rec"]
			if float(e["t"]) >= float(e["dur"]) or not (rec in game.items):
				rec.erase("failed")
				game.evaluate_supply()
				active.erase(e)
				_say("Strom wieder da: %s läuft wieder" % Catalog.label(String(rec["id"])))
		"streik":
			if float(e["t"]) >= float(e["dur"]):
				terminal.staff_factor = 1.0
				terminal.dirty = true
				active.erase(e)
				_say("Streik beendet, das Personal ist zurück")
		"gewitter":
			e["next_flash"] = float(e["next_flash"]) - sim
			if float(e["next_flash"]) <= 0.0 and weather != null:
				weather.flash = 1.0
				e["next_flash"] = rng.randf_range(3.0, 9.0)
			if float(e["t"]) >= float(e["dur"]):
				flights.storm = false
				ops.storm = false
				if weather != null:
					weather.force(String(e.get("prev", "")))
				active.erase(e)
				_say("Gewitter vorbei, die Abfertigung läuft weiter")
		"vogelschlag":
			if float(e["t"]) >= float(e["dur"]):
				active.erase(e)
				_say("Piste nach der Inspektion wieder frei")


func _medical_terminal() -> bool:
	var per: Dictionary = terminal.pick_patient(rng)
	if per.is_empty():
		return false
	terminal.collapse(per)
	var aid: bool = terminal.first_aid(per)
	var info := {}
	var sent := false
	for opt: Array in terminal.rescue_point(per):
		if ops.send_rtw(opt[0], opt[1], 30.0, info):
			sent = true
			break
	active.append({"kind": "notfall_terminal", "t": 0.0, "per": per, "info": info, "rtw": sent})
	_say("Medizinischer Notfall im Terminal: %s%s" % ["Ersthelfer aus dem Sanitätsraum sind unterwegs, " if aid else "",
		"Rettungswagen alarmiert" if sent else "kein Rettungswagen erreichbar (Betriebsstraße fehlt)"])
	return true


func _medical_flight() -> bool:
	var cand := []
	for p: Dictionary in flights.planes:
		if String(p["state"]) in ["anflug", "landung"] and not bool(p.get("cargo", false)) and not bool(p.get("medical", false)):
			cand.append(p)
	if cand.is_empty():
		return false
	var p: Dictionary = cand[rng.randi() % cand.size()]
	p["medical"] = true
	active.append({"kind": "notfall_bord", "t": 0.0, "plane": p, "sent": false, "info": {}})
	_say("Notfall an Bord von %s: ein Rettungswagen erwartet das Flugzeug am Stand" % p["code"])
	return true


func _belt_failure() -> bool:
	var cand := []
	for l: Dictionary in game.lines:
		if l["kind"] == "kofferband" and not bool(l.get("broken", false)):
			cand.append(l)
	if cand.is_empty():
		return false
	var l: Dictionary = cand[rng.randi() % cand.size()]
	l["broken"] = true
	game._routes_dirty = true
	terminal.dirty = true
	var sm: PackedVector3Array = l["samples"]
	var mid := sm[sm.size() / 2]
	var k := Kit.new()
	k.sphere(Vector3.ZERO, 0.28, Color(1.0, 0.15, 0.1, 0.3), 10, 6)
	var w := k.instance("Stoerung")
	w.position = mid + Vector3(0, 0.6, 0)
	(l["node"] as Node).add_child(w)
	var hall: Dictionary = game.hall_at(mid)
	var tech: bool = game.any_room_ok("technik")
	if not hall.is_empty():
		terminal.send_technician(hall, mid)
	active.append({"kind": "bandausfall", "t": 0.0, "dur": 45.0 if tech else 90.0, "line": l})
	_say("Störung: ein Kofferband steht still, ein Techniker ist unterwegs%s" % (" (Technikraum: schnelle Reparatur)" if tech else ""))
	return true


func _power_failure() -> bool:
	var cand: Array = game.items_of("trafo")
	if cand.is_empty() or busy("stromausfall"):
		return false
	var rec: Dictionary = cand[rng.randi() % cand.size()]
	rec["failed"] = true
	game.evaluate_supply()
	var tech: bool = game.any_room_ok("technik")
	active.append({"kind": "stromausfall", "t": 0.0, "dur": 40.0 if tech else 90.0, "rec": rec})
	_say("Stromausfall: ein Trafo ist ausgefallen%s" % (" – die Technik schaltet schnell um" if tech else ", alles daran steht"))
	return true


func _bird_strike() -> bool:
	var cand := []
	for p: Dictionary in flights.planes:
		if String(p["state"]) in ["start", "landung"]:
			cand.append(p)
	if cand.is_empty():
		return false
	var p: Dictionary = cand[rng.randi() % cand.size()]
	flights.inspect_t = 150.0
	ops._fire_mission("kontrolle", null, 0.0)
	active.append({"kind": "vogelschlag", "t": 0.0, "dur": 150.0})
	_say("Vogelschlag bei %s: die Piste wird inspiziert und ist kurz gesperrt" % p["code"])
	return true


## Text für das Betriebsfenster.
func summary() -> String:
	var lines := []
	for e: Dictionary in active:
		lines.append("läuft: " + String(e["kind"]).replace("_", " "))
	for h: Array in history:
		lines.append(String(h[1]))
	return "\n".join(lines)
