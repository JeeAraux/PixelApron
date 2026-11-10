extends Node
## Betrieb: Statistik (Pünktlichkeit, Passagiere, Einnahmen nach Bereich, Engpässe), Airline-Verträge,
## Szenarien mit Zielen und die Lernschritte für Einsteiger. Alles wird im Spielstand unter "betrieb" gesichert.

const Catalog = preload("res://scripts/catalog.gd")
const GameState = preload("res://scripts/game_state.gd")

const PUNCTUAL := 15.0          # Minuten: bis dahin gilt ein Abflug als pünktlich
## Verträge: je Airline Anforderungen [Art, Wert] und Antrittsprämie. Unter Vertrag fliegt die Airline dreimal so oft.
const OFFERS := {
	"IF": {"req": [["gates", 4], ["puenktlich", 75]], "bonus": 1500000, "text": "Mehr Kurzstrecke ab Wiesenfeld"},
	"DJ": {"req": [["stand_e", 1], ["lounge", 1]], "bonus": 3000000, "text": "Langstrecke mit Großraumflugzeugen"},
	"BW": {"req": [["zufriedenheit", 80], ["bahn", 1]], "bonus": 1800000, "text": "Umsteigen von der Bahn ins Flugzeug"},
	"WZ": {"req": [["fracht", 1], ["winter", 1]], "bonus": 2200000, "text": "Fracht auch im Winter"},
	"NX": {"req": [["gates", 8], ["lounge", 1], ["puenktlich", 85]], "bonus": 5000000, "text": "Drehkreuz mit Umsteigern"},
}
const REQ_TEXT := {"gates": "%d Gates", "stand_e": "%d Großraum-Stand", "lounge": "Airline-Lounge", "puenktlich": "Pünktlichkeit ab %d %%",
	"zufriedenheit": "Zufriedenheit ab %d %%", "bahn": "S-Bahnhof", "fracht": "Frachtterminal", "winter": "Winterdienst"}
## Szenarien: Titel, Beschreibung, Startgeld, Wetter, Ziele [Art, Wert, Text]
const SCENARIOS := {
	"drehkreuz": {"name": "Vom Regionalflughafen zum Drehkreuz", "money": 30000000, "wetter": "",
		"desc": "Baue den kleinen Flughafen aus, bis drei Airlines unter Vertrag sind und 20.000 Fluggäste abgeflogen sind – bei hoher Zufriedenheit und pünktlichen Abflügen.",
		"goals": [["vertraege", 3, "3 Airline-Verträge"], ["pax", 20000, "20.000 abgeflogene Passagiere"], ["zufriedenheit", 85, "Zufriedenheit 85 %"], ["puenktlich", 85, "85 % pünktlich"]]},
	"winter": {"name": "Winterchaos", "money": 18000000, "wetter": "schnee",
		"desc": "Dauerschneefall! Halte den Betrieb am Laufen: 40 Abflüge mit im Schnitt weniger als 20 Minuten Verspätung. Ohne Winterdienst wird es schwer.",
		"goals": [["abfluege", 40, "40 Abflüge"], ["verspaetung", 20, "Ø Verspätung unter 20 Min"], ["winter", 1, "Winterdienst gebaut"]]},
	"fracht": {"name": "Frachtdrehkreuz", "money": 25000000, "wetter": "",
		"desc": "Mache Wiesenfeld zum Frachtflughafen: 1.500 Tonnen Fracht umschlagen und einen Frachtvertrag mit Weizenair abschließen.",
		"goals": [["tonnen", 1500, "1.500 t Fracht"], ["vertrag_WZ", 1, "Vertrag mit Weizenair"]]},
}
## Lernschritte auf einer leeren Karte: [Text, Prüfung]
const TUTORIAL := [
	["Baue eine Piste (Wege → Piste), mindestens 1.800 m lang.", "piste"],
	["Verbinde die Piste mit einem Rollweg mit einem Vorfeld.", "vorfeld"],
	["Setze einen Stand auf das Vorfeld (Flugbetrieb → Stand mit Brücke oder Außenposition).", "stand"],
	["Baue einen Tower und eine Trafostation und verbinde sie mit einem Stromkabel.", "tower"],
	["Ziehe eine Terminalhalle auf und richte Eingang, Check-in, Gepäcksortierung, Kontrolle und ein Gate ein.", "terminal"],
	["Schließe die Halle an Strom und Wasser an, baue Toiletten und eine Fluggastbrücke oder ein Bus-Gate.", "flug"],
	["Führe eine Straße zum Eingang und baue ein Parkhaus mit Zufahrt. Dann kommen die ersten Flüge!", "parkhaus"],
]

var game: GameState
var flights: Variant = null
var terminal: Variant = null
var traffic: Variant = null
var weather: Variant = null

# Statistik
var stats := {"abfluege": 0, "puenktlich": 0, "verspaetung": 0.0, "pax": 0, "tonnen": 0, "koffer": 0, "koffer_weg": 0,
	"lounge": 0, "checks": 0}
var recent: Array = []          # Verspätung der letzten 40 Abflüge in Minuten
var income: Dictionary = {}     # Bereich -> Euro seit Spielbeginn
var hourly: Array = []          # [Stunde, Passagiere, Bewegungen, Einnahmen] der letzten 24 Stunden
var _hour := -1
var waits: Dictionary = {}      # Rasterzelle (40 m) -> Warteminuten der Flugzeuge
# Verträge, Szenario, Lernschritte
var contracts: Dictionary = {}  # Kürzel -> {"aktiv": bool, "seit": Minute, "verletzt": Minuten}
var scenario := ""
var scenario_done := false
var tutorial := -1
var _tick := 0.0


func setup(g: GameState) -> void:
	game = g


# ---------------------------------------------------------------- Statistik

func book_income(area: String, amount: int) -> void:
	income[area] = int(income.get(area, 0)) + amount
	_ensure_hour()
	if not hourly.is_empty():
		hourly[hourly.size() - 1][3] = int(hourly[hourly.size() - 1][3]) + amount


func departure(p: Dictionary, delay: float, pax: int, tonnes: int) -> void:
	stats["abfluege"] = int(stats["abfluege"]) + 1
	if delay <= PUNCTUAL:
		stats["puenktlich"] = int(stats["puenktlich"]) + 1
	stats["verspaetung"] = float(stats["verspaetung"]) + delay
	stats["pax"] = int(stats["pax"]) + pax
	stats["tonnen"] = int(stats["tonnen"]) + tonnes
	recent.append(delay)
	while recent.size() > 40:
		recent.pop_front()
	_ensure_hour()
	hourly[hourly.size() - 1][1] = int(hourly[hourly.size() - 1][1]) + pax


func movement() -> void:
	_ensure_hour()
	hourly[hourly.size() - 1][2] = int(hourly[hourly.size() - 1][2]) + 1


func _ensure_hour() -> void:
	var h := int(game.minutes / 60.0)
	if h != _hour:
		_hour = h
		hourly.append([h, 0, 0, 0])
		while hourly.size() > 24:
			hourly.pop_front()


## Anteil pünktlicher Abflüge der letzten 40 (0..100), -1 ohne Daten.
func punctuality() -> float:
	if recent.is_empty():
		return -1.0
	var ok := 0
	for d: float in recent:
		if d <= PUNCTUAL:
			ok += 1
	return 100.0 * float(ok) / float(recent.size())


func avg_delay() -> float:
	if recent.is_empty():
		return 0.0
	var s := 0.0
	for d: float in recent:
		s += d
	return s / float(recent.size())


## Ein Flugzeug wartet an p (für die Engpass-Karte).
func waited(p: Vector3, minutes: float) -> void:
	var key := Vector2i(floori(p.x / 40.0), floori(p.z / 40.0))
	waits[key] = float(waits.get(key, 0.0)) + minutes


## Die Stellen, an denen Flugzeuge am längsten gewartet haben: [Mitte, Minuten]
func hotspots(n: int = 5) -> Array:
	var out := []
	for key: Vector2i in waits:
		out.append([Vector3((float(key.x) + 0.5) * 40.0, 0, (float(key.y) + 0.5) * 40.0), float(waits[key])])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	return out.slice(0, n)


# ---------------------------------------------------------------- Verträge

func _count(id: String) -> int:
	return game.items_of(id).size()


func _powered(id: String) -> bool:
	for it: Dictionary in game.items_of(id):
		if not Catalog.ITEMS[id].has("needs") or game.supplied(it, "strom"):
			return true
	return false


## Erfüllt der Flughafen eine Anforderung? [erfüllt, Text mit Ist-Wert]
func requirement(r: Array) -> Array:
	var kind: String = r[0]
	var v: float = float(r[1])
	var fmt: String = REQ_TEXT.get(kind, kind)
	var label := fmt % int(v) if fmt.contains("%d") else fmt
	match kind:
		"gates":
			var n := _count("gate") + _count("busgate")
			return [float(n) >= v, "%s (%d)" % [label, n]]
		"stand_e":
			var n := _count("stand_gross")
			return [float(n) >= v, "%s (%d)" % [label, n]]
		"lounge":
			return [_count("airline_lounge") > 0, label]
		"puenktlich":
			var p := punctuality()
			return [p >= v, "%s (%s)" % [label, "–" if p < 0.0 else "%d %%" % roundi(p)]]
		"zufriedenheit":
			return [game.satisfaction >= v, "%s (%d %%)" % [label, roundi(game.satisfaction)]]
		"bahn":
			return [_powered("bahnhof"), label]
		"fracht":
			return [_powered("frachtterminal"), label]
		"winter":
			return [_powered("winterdienst"), label]
	return [false, label]


func offer_ok(code: String) -> bool:
	for r: Array in OFFERS[code]["req"]:
		if not bool(requirement(r)[0]):
			return false
	return true


func is_contract(code: String) -> bool:
	return bool((contracts.get(code, {}) as Dictionary).get("aktiv", false))


func active_contracts() -> int:
	var n := 0
	for code: String in contracts:
		if is_contract(code):
			n += 1
	return n


## Vertrag unterschreiben: Prämie gibt es sofort, die Airline fliegt dreimal so oft.
func sign(code: String) -> bool:
	if is_contract(code) or not offer_ok(code):
		return false
	contracts[code] = {"aktiv": true, "seit": game.minutes, "verletzt": 0.0}
	var bonus := int(OFFERS[code]["bonus"])
	game.earn(bonus, "Vertrag mit %s unterschrieben" % airline_name(code))
	book_income("Verträge", bonus)
	return true


func airline_name(code: String) -> String:
	for a: Array in Catalog.AIRLINES:
		if String(a[0]) == code:
			return String(a[3])
	return code


## Gewicht beim Auswürfeln der Airline eines neuen Flugs.
func airline_weight(code: String) -> float:
	return 3.0 if is_contract(code) else 1.0


func _check_contracts(minutes: float) -> void:
	for code: String in contracts:
		var c: Dictionary = contracts[code]
		if not bool(c.get("aktiv", false)):
			continue
		if offer_ok(code):
			c["verletzt"] = 0.0
			continue
		var before := float(c.get("verletzt", 0.0))
		c["verletzt"] = before + minutes
		if before < 1.0 and float(c["verletzt"]) >= 1.0:
			game.toast.emit("%s: Vertragsbedingungen nicht erfüllt – in einem Tag wird gekündigt" % airline_name(code))
		if float(c["verletzt"]) > 1440.0:
			c["aktiv"] = false
			game.satisfaction = maxf(0.0, game.satisfaction - 8.0)
			game.toast.emit("%s hat den Vertrag gekündigt" % airline_name(code))


# ---------------------------------------------------------------- Szenario und Lernschritte

func start_scenario(key: String) -> void:
	scenario = key
	scenario_done = false
	stats = {"abfluege": 0, "puenktlich": 0, "verspaetung": 0.0, "pax": 0, "tonnen": 0, "koffer": 0, "koffer_weg": 0, "lounge": 0, "checks": 0}
	recent.clear()
	income.clear()
	contracts.clear()
	tutorial = -1
	if key == "":
		if weather != null:
			weather.force("")
		return
	var sc: Dictionary = SCENARIOS[key]
	game.money = int(sc["money"])
	game.money_changed.emit(game.money)
	if weather != null:
		weather.force(String(sc["wetter"]))
	game.toast.emit("Szenario: " + String(sc["name"]))


## Fortschritt eines Ziels: [erreicht, Anteil 0..1, Text]
func goal_state(g: Array) -> Array:
	var kind: String = g[0]
	var v: float = float(g[1])
	var cur := 0.0
	var ok := false
	match kind:
		"vertraege":
			cur = float(active_contracts())
			ok = cur >= v
		"pax":
			cur = float(stats["pax"])
			ok = cur >= v
		"zufriedenheit":
			cur = game.satisfaction
			ok = cur >= v
		"puenktlich":
			cur = maxf(punctuality(), 0.0)
			ok = cur >= v and recent.size() >= 10
		"abfluege":
			cur = float(stats["abfluege"])
			ok = cur >= v
		"verspaetung":
			var a := avg_delay()
			ok = int(stats["abfluege"]) >= 10 and a < v
			return [ok, 1.0 if ok else clampf(v / maxf(a, 0.1), 0.0, 1.0), "%s (jetzt %d Min)" % [String(g[2]), roundi(a)]]
		"winter":
			ok = _powered("winterdienst")
			cur = 1.0 if ok else 0.0
		"tonnen":
			cur = float(stats["tonnen"])
			ok = cur >= v
		_:
			if kind.begins_with("vertrag_"):
				ok = is_contract(kind.substr(8))
				cur = 1.0 if ok else 0.0
	return [ok, clampf(cur / maxf(v, 0.01), 0.0, 1.0), "%s (%s)" % [String(g[2]), _num(cur)]]


static func _num(v: float) -> String:
	if v >= 1000.0:
		return GameState.fmt_money(int(v)).replace(" €", "").replace("€", "")
	return str(roundi(v))


func tutorial_check(kind: String) -> bool:
	match kind:
		"piste":
			for l: Dictionary in game.lines:
				if l["kind"] == "piste" and (l["samples"] as PackedVector3Array).size() > 1800:
					return true
			return false
		"vorfeld":
			var has_v := false
			var has_r := false
			for l: Dictionary in game.lines:
				has_v = has_v or l["kind"] == "vorfeld"
				has_r = has_r or String(l["kind"]).begins_with("rollweg")
			return has_v and has_r
		"stand":
			return not game.stands().is_empty()
		"tower":
			return _powered("tower")
		"terminal":
			return terminal != null and String(terminal.check()) == "" and not game.items_of("halle").is_empty()
		"flug":
			if flights == null:
				return false
			var why: String = flights.check_operation()
			return why == "" or why.begins_with("Kein Parkhaus")
		"parkhaus":
			for ph: Dictionary in game.items_of("parkhaus") + game.items_of("parkplatz"):
				if traffic == null or traffic.has_access(ph):
					return true
			return false
	return true


func tutorial_text() -> String:
	if tutorial < 0 or tutorial >= TUTORIAL.size():
		return ""
	return "Schritt %d von %d: %s" % [tutorial + 1, TUTORIAL.size(), String(TUTORIAL[tutorial][0])]


func start_tutorial() -> void:
	tutorial = 0


func step(game_minutes: float) -> void:
	_tick += game_minutes
	if _tick < 1.0:
		return
	var m := _tick
	_tick = 0.0
	_check_contracts(m)
	if tutorial >= 0 and tutorial < TUTORIAL.size():
		while tutorial < TUTORIAL.size() and tutorial_check(String(TUTORIAL[tutorial][1])):
			tutorial += 1
			if tutorial < TUTORIAL.size():
				game.toast.emit("Geschafft! Nächster Schritt: " + String(TUTORIAL[tutorial][0]))
			else:
				game.toast.emit("Alle Lernschritte geschafft – viel Spaß mit deinem Flughafen!")
	if scenario != "" and not scenario_done:
		var all := true
		for g: Array in SCENARIOS[scenario]["goals"]:
			all = all and bool(goal_state(g)[0])
		if all:
			scenario_done = true
			game.toast.emit("Szenario geschafft: " + String(SCENARIOS[scenario]["name"]) + "!")


func save_data() -> Dictionary:
	var w := []
	for key: Vector2i in waits:
		w.append([key.x, key.y, waits[key]])
	return {"stats": stats, "recent": recent, "income": income, "contracts": contracts, "scenario": scenario,
		"done": scenario_done, "tutorial": tutorial, "waits": w}


func load_data(d: Dictionary) -> void:
	var st: Dictionary = d.get("stats", {})
	for key: String in stats:
		if st.has(key):
			stats[key] = st[key]
	recent = d.get("recent", [])
	income = d.get("income", {})
	contracts = d.get("contracts", {})
	scenario = String(d.get("scenario", ""))
	scenario_done = bool(d.get("done", false))
	tutorial = int(d.get("tutorial", -1))
	waits = {}
	for e: Array in d.get("waits", []):
		waits[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
