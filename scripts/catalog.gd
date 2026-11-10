extends RefCounted
## Alle baubaren Teile und Spielregeln als Daten. Ein neues Teil braucht hier einen Eintrag
## und in factory.gd eine Bauform, sonst keinen weiteren Code.

## Wege werden als Kurve gezogen. width und min_r in Metern, cost_m in Euro pro Meter.
## y legt fest, was oben liegt, wenn sich Wege überlappen. utility = Leitung unter der Erde.
const LINES := {
	"strasse": {"name": "Straße", "width": 7.5, "cost_m": 350, "min_r": 10.0, "min_len": 5.0,
		"color": Color(0.23, 0.225, 0.21), "mark": 1, "y": 0.06, "straight": false, "utility": "",
		"desc": "Zweispurige Straße, Autos fahren rechts. Mindestradius 10 m."},
	"gehweg": {"name": "Gehweg", "width": 3.0, "cost_m": 90, "min_r": 2.0, "min_len": 2.0,
		"color": Color(0.55, 0.53, 0.48), "mark": 4, "y": 0.07, "straight": false, "utility": "",
		"desc": "Gepflasterter Fußweg."},
	"rollweg": {"name": "Rollweg", "width": 18.0, "cost_m": 1100, "min_r": 30.0, "min_len": 10.0,
		"color": Color(0.2, 0.2, 0.19), "mark": 2, "y": 0.04, "straight": false, "utility": "",
		"desc": "Verbindet Piste und Vorfeld. Mindestradius 30 m."},
	"vorfeld": {"name": "Vorfeld", "width": 60.0, "cost_m": 2600, "min_r": 25.0, "min_len": 10.0,
		"color": Color(0.47, 0.46, 0.42), "mark": 5, "y": 0.03, "straight": false, "utility": "",
		"desc": "Betonfläche für Stände und Abfertigung, 60 m breit."},
	"piste": {"name": "Piste", "width": 45.0, "cost_m": 3800, "min_r": 0.0, "min_len": 400.0,
		"color": Color(0.18, 0.18, 0.17), "mark": 3, "y": 0.09, "straight": true, "utility": "",
		"desc": "Gerade, 45 m breit. ATR 72 ab 1.200 m, Airbus A320 ab 1.800 m Länge."},
	"stromkabel": {"name": "Stromkabel", "width": 1.4, "cost_m": 60, "min_r": 1.0, "min_len": 2.0,
		"color": Color(1.0, 0.83, 0.27), "mark": 0, "y": 0.16, "straight": false, "utility": "strom",
		"desc": "Verbindet Trafostation und Gebäude. Beide Enden müssen ein Gebäude oder ein anderes Kabel berühren."},
	"wasserrohr": {"name": "Wasserrohr", "width": 1.4, "cost_m": 80, "min_r": 1.0, "min_len": 2.0,
		"color": Color(0.33, 0.70, 1.0), "mark": 0, "y": 0.17, "straight": false, "utility": "wasser",
		"desc": "Verbindet Wasseranschluss und Gebäude."},
	"heizrohr": {"name": "Heizrohr", "width": 1.4, "cost_m": 140, "min_r": 1.0, "min_len": 2.0,
		"color": Color(1.0, 0.45, 0.30), "mark": 0, "y": 0.18, "straight": false, "utility": "waerme",
		"desc": "Fernwärme von der Heizzentrale zur Terminalhalle. Die Heizkörper in der Halle brauchen sie."},
	# Wände innerhalb einer Terminalhalle: gerade, zwei Klicks
	"innenwand": {"name": "Innenwand", "width": 0.3, "cost_m": 450, "min_r": 0.0, "min_len": 1.0,
		"color": Color(0.88, 0.86, 0.80), "mark": 0, "y": 0.1, "straight": true, "utility": "", "wall": true,
		"desc": "Feste Wand im Terminal. Passagiere laufen außen herum. Nur innerhalb einer Halle."},
	"glaswand": {"name": "Glaswand", "width": 0.3, "cost_m": 900, "min_r": 0.0, "min_len": 1.0,
		"color": Color(0.55, 0.75, 0.85), "mark": 0, "y": 0.1, "straight": true, "utility": "", "wall": true,
		"desc": "Trennt zum Beispiel den öffentlichen Bereich vom Bereich hinter der Kontrolle."},
}

## Gebäude und Deko. size = Grundfläche (x, z), h = Höhe, grid = Rasterweite beim Setzen.
## needs/supply: Strom in kW, Wasser in m³/h. on = muss auf diesem Wegtyp liegen.
const ITEMS := {
	# Terminalhalle: Rechteck mit zwei Klicks aufziehen, Preis je Quadratmeter
	"halle": {"name": "Terminalhalle", "size": Vector2(24, 16), "h": 9.6, "cost": 0, "cost_m2": 1400, "grid": 2.0,
		"rect_tool": true, "min": Vector2(16, 12), "max": Vector2(240, 120),
		"desc": "Hülle des Terminals: zwei Ecken klicken. Innen baust du Eingang, Check-in, Kontrolle, Gates und mehr. Braucht Strom, für Heizkörper Wärme, für WCs Wasser."},
	"stand": {"name": "Stand", "size": Vector2(40, 46), "h": 0.2, "cost": 60000, "grid": 1.0, "on": "vorfeld",
		"desc": "Abstellposition für ein Flugzeug. Muss auf dem Vorfeld liegen."},
	"vorfelddepot": {"name": "Vorfelddepot", "size": Vector2(26, 16), "h": 7.0, "cost": 380000, "grid": 2.0,
		"needs": {"strom": 30}, "desc": "Tankwagen, Gepäckschlepper und Catering. Ohne Depot mit Strom dauert jede Abfertigung anderthalbmal so lang."},
	"tower": {"name": "Tower", "size": Vector2(12, 12), "h": 39.0, "cost": 900000, "grid": 2.0,
		"needs": {"strom": 60}, "desc": "Ohne Tower mit Strom finden keine Flüge statt."},
	"hangar": {"name": "Hangar", "size": Vector2(44, 36), "h": 14.0, "cost": 650000, "grid": 2.0,
		"needs": {"strom": 120}, "desc": "Wartungshalle für Flugzeuge."},
	"feuerwache": {"name": "Feuerwache", "size": Vector2(30, 20), "h": 13.0, "cost": 700000, "grid": 2.0,
		"needs": {"strom": 50, "wasser": 6}, "desc": "Flughafenfeuerwehr."},
	"parkhaus": {"name": "Parkhaus", "size": Vector2(32, 44), "h": 14.5, "cost": 1500000, "grid": 2.0,
		"needs": {"strom": 80}, "desc": "Vier Ebenen für Autos der Passagiere."},
	"trafo": {"name": "Trafostation", "size": Vector2(10, 7), "h": 3.7, "cost": 180000, "grid": 1.0,
		"supply": {"strom": 630}, "desc": "Liefert 630 kW Strom über Kabel."},
	"wasseranschluss": {"name": "Wasseranschluss", "size": Vector2(4, 4), "h": 1.6, "cost": 25000, "grid": 1.0,
		"supply": {"wasser": 40}, "desc": "Anschluss an das öffentliche Netz, 40 m³/h."},
	"heizzentrale": {"name": "Heizzentrale", "size": Vector2(22, 15), "h": 23.0, "cost": 450000, "grid": 1.0,
		"needs": {"strom": 40, "wasser": 4}, "supply": {"waerme": 900},
		"desc": "Erzeugt 900 kW Wärme. Mit Heizrohren zur Terminalhalle verbinden."},
	"baum": {"name": "Baum", "size": Vector2(4, 4), "h": 7.0, "cost": 300, "grid": 0.5, "desc": "Laubbaum."},
	"kuebel": {"name": "Blumenkübel", "size": Vector2(1.4, 1.4), "h": 1.8, "cost": 150, "grid": 0.5, "desc": "Bepflanzter Kübel."},
	"laterne": {"name": "Laterne", "size": Vector2(0.8, 0.8), "h": 7.0, "cost": 1200, "grid": 0.5, "desc": "Straßenlaterne."},
	"bank": {"name": "Bank", "size": Vector2(2.2, 0.8), "h": 1.0, "cost": 400, "grid": 0.5, "desc": "Sitzbank."},

	# ---- Einrichtung der Terminalhalle (inside). Vorderseite = lokale +Z-Richtung, R dreht.
	# walk: Passagiere laufen hindurch. wall: muss an der Außenwand stehen. cap: Passagiere pro Stunde.
	"eingang": {"name": "Eingang", "size": Vector2(6, 2), "h": 3.4, "cost": 40000, "grid": 1.0, "inside": true,
		"wall": true, "walk": true, "needs": {"strom": 2},
		"desc": "Automatische Schiebetür in der Außenwand. Hier kommen die Passagiere herein und gehen hinaus."},
	"checkin": {"name": "Check-in", "size": Vector2(6, 3), "h": 2.9, "cost": 60000, "grid": 1.0, "inside": true,
		"needs": {"strom": 6}, "cap": 80,
		"desc": "Zwei Schalter, 80 Passagiere pro Stunde. Braucht eine Gepäcksortierung in der Halle."},
	"gepaeckanlage": {"name": "Gepäcksortierung", "short": "Gepäckanlage", "size": Vector2(8, 6), "h": 3.0, "cost": 420000, "grid": 1.0,
		"inside": true, "needs": {"strom": 40},
		"desc": "Bringt die Koffer vom Check-in zu den Flugzeugen. Ohne sie kein Check-in."},
	"sicherheit": {"name": "Sicherheitskontrolle", "short": "Kontrolle", "size": Vector2(6, 8), "h": 2.5, "cost": 150000, "grid": 1.0,
		"inside": true, "walk": true, "needs": {"strom": 12}, "cap": 150,
		"desc": "Zwei Spuren mit Röntgen und Torsonde, 150 Passagiere pro Stunde. Passagiere gehen von vorn nach hinten hindurch."},
	"gate": {"name": "Gate", "size": Vector2(10, 8), "h": 3.2, "cost": 90000, "grid": 1.0, "inside": true,
		"wall": true, "walk": true, "needs": {"strom": 4},
		"desc": "Wartebereich mit Ausgang zum Flugzeug. An die Außenwand zum Vorfeld stellen. Ein Gate je Flugzeug am Stand."},
	"gepaeckband": {"name": "Gepäckband", "size": Vector2(10, 5), "h": 2.2, "cost": 120000, "grid": 1.0,
		"inside": true, "needs": {"strom": 10}, "cap": 300,
		"desc": "Hier holen ankommende Passagiere ihre Koffer, 300 Passagiere pro Stunde."},
	"wc": {"name": "Toiletten", "size": Vector2(6, 5), "h": 2.7, "cost": 70000, "grid": 1.0, "inside": true,
		"needs": {"strom": 2, "wasser": 3}, "cap": 250,
		"desc": "Damen, Herren, barrierefrei. 250 Passagiere pro Stunde. Braucht Wasser in der Halle."},
	"heizkoerper": {"name": "Heizkörper", "size": Vector2(2, 0.5), "h": 0.9, "cost": 1500, "grid": 0.5,
		"inside": true, "needs": {"waerme": 30}, "heats": 250,
		"desc": "Heizt 250 m² Halle. Braucht Wärme von der Heizzentrale über ein Heizrohr."},
	"cafe": {"name": "Café", "size": Vector2(8, 6), "h": 2.8, "cost": 80000, "grid": 1.0, "inside": true,
		"needs": {"strom": 15, "wasser": 1}, "retail": 3, "decor": 4,
		"desc": "Bringt 3 € je abfliegendem Passagier und hebt die Stimmung."},
	"shop": {"name": "Shop", "size": Vector2(8, 6), "h": 2.8, "cost": 60000, "grid": 1.0, "inside": true,
		"needs": {"strom": 8}, "retail": 4, "decor": 3,
		"desc": "Zeitschriften und Reisebedarf. Bringt 4 € je abfliegendem Passagier."},
	"sitzreihe": {"name": "Sitzreihe", "size": Vector2(5, 1), "h": 1.0, "cost": 2500, "grid": 0.5, "inside": true,
		"decor": 1, "desc": "Fünf Sitze. Wartende Passagiere freuen sich."},
	"pflanze": {"name": "Pflanze", "size": Vector2(1, 1), "h": 2.0, "cost": 400, "grid": 0.5, "inside": true,
		"decor": 1, "desc": "Große Topfpflanze."},
	"anzeige": {"name": "Anzeigetafel", "size": Vector2(3, 1), "h": 3.4, "cost": 18000, "grid": 0.5, "inside": true,
		"needs": {"strom": 1}, "decor": 2, "desc": "Abflüge und Ankünfte. Passagiere finden sich besser zurecht."},
	"kunst": {"name": "Kunstwerk", "size": Vector2(3, 3), "h": 3.5, "cost": 25000, "grid": 0.5, "inside": true,
		"decor": 3, "desc": "Skulptur als Blickfang."},
}

## Kategorien des Baumenüs: [Schlüssel, Titel, Teile]
const CATEGORIES := [
	["wege", "Wege", ["strasse", "gehweg", "rollweg", "vorfeld", "piste"]],
	["flug", "Flugbetrieb", ["stand", "tower", "vorfelddepot", "hangar", "feuerwache"]],
	["terminal", "Terminal", ["halle", "innenwand", "glaswand", "eingang", "checkin", "gepaeckanlage", "sicherheit", "gate", "gepaeckband"]],
	["ausstattung", "Ausstattung", ["wc", "heizkoerper", "cafe", "shop", "sitzreihe", "pflanze", "anzeige", "kunst"]],
	["versorgung", "Versorgung", ["stromkabel", "wasserrohr", "heizrohr", "trafo", "wasseranschluss", "heizzentrale"]],
	["umfeld", "Umfeld", ["parkhaus", "baum", "kuebel", "laterne", "bank"]],
]

## Versorgungsnetze mit Anzeigename und Einheit
const UTILITIES := {"strom": ["Strom", "kW"], "wasser": ["Wasser", "m³/h"], "waerme": ["Wärme", "kW"]}
## Strombedarf der Halle selbst (Licht, Lüftung) je Quadratmeter
const HALL_POWER_M2 := 0.03

## Flugzeugtypen: Pistenlänge, Sitzplätze, Abfertigungszeit in Spielminuten, Landeentgelt.
const PLANES := {
	"a320": {"name": "Airbus A320", "min_rwy": 1700.0, "pax": 180, "turn": 40.0, "fee": 2400, "vapp": 70.0, "vr": 72.0, "nose": 18.8},
	"b737": {"name": "Boeing 737-800", "min_rwy": 1700.0, "pax": 189, "turn": 42.0, "fee": 2500, "vapp": 72.0, "vr": 74.0, "nose": 19.75},
}
## Ausgedachte Airlines mit Hausfarbe
const AIRLINES := [["IF", Color(0.62, 0.22, 0.18)], ["DJ", Color(0.18, 0.30, 0.52)], ["BW", Color(0.16, 0.42, 0.40)],
	["WZ", Color(0.85, 0.55, 0.12)], ["NX", Color(0.35, 0.22, 0.48)]]
const DESTINATIONS := ["Hamburg", "Berlin", "Palma", "Wien", "Zürich", "London", "Antalya", "Rom", "Paris", "Amsterdam"]
const TICKET_FEE := 14
## Laufende Kosten pro Spieltag als Anteil der Baukosten.
const UPKEEP_ITEMS := 0.002
const UPKEEP_LINES := 0.001


static func label(id: String) -> String:
	if LINES.has(id):
		return String(LINES[id]["name"])
	if ITEMS.has(id):
		return String(ITEMS[id]["name"])
	if id == "abriss":
		return "Abriss"
	return id


static func is_inside(id: String) -> bool:
	return ITEMS.has(id) and bool(ITEMS[id].get("inside", false))


static func is_wall(kind: String) -> bool:
	return LINES.has(kind) and bool(LINES[kind].get("wall", false))


## Gehört dieses Werkzeug zum Terminalbau (dann Innenansicht einschalten)?
static func is_terminal_tool(id: String) -> bool:
	return id == "halle" or is_inside(id) or is_wall(id)


static func utility_of(kind: String) -> String:
	if LINES.has(kind):
		return String(LINES[kind].get("utility", ""))
	return ""
