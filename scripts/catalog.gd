extends RefCounted
## Alle baubaren Teile und Spielregeln als Daten. Ein neues Teil braucht hier einen Eintrag
## und in factory.gd eine Bauform, sonst keinen weiteren Code.

## Wege werden als Kurve gezogen. width und min_r in Metern, cost_m in Euro pro Meter.
## y legt fest, was oben liegt, wenn sich Wege überlappen. utility = Leitung unter der Erde.
const LINES := {
	"strasse": {"name": "Straße", "width": 7.5, "cost_m": 350, "min_r": 10.0, "min_len": 5.0, "lanes": [1, 1],
		"color": Color(0.23, 0.225, 0.21), "mark": 1, "y": 0.06, "straight": false, "utility": "",
		"desc": "Eine Spur je Richtung. Kreuzt sie eine andere Straße, entsteht eine Kreuzung."},
	"strasse4": {"name": "Straße 4-spurig", "width": 14.0, "cost_m": 720, "min_r": 14.0, "min_len": 5.0, "lanes": [2, 2],
		"color": Color(0.23, 0.225, 0.21), "mark": 6, "y": 0.061, "straight": false, "utility": "",
		"desc": "Zwei Spuren je Richtung. Linke Spur zum Linksabbiegen. Kreuzungen bekommen automatisch Ampeln."},
	"einbahn": {"name": "Einbahnstraße", "width": 7.5, "cost_m": 380, "min_r": 10.0, "min_len": 5.0, "lanes": [2, 0],
		"color": Color(0.23, 0.225, 0.21), "mark": 7, "y": 0.062, "straight": false, "utility": "",
		"desc": "Zwei Spuren in Zeichenrichtung. Mit dem Werkzeug Spuren drehst du die Richtung um."},
	"gehweg": {"name": "Gehweg", "width": 3.0, "cost_m": 90, "min_r": 2.0, "min_len": 2.0,
		"color": Color(0.55, 0.53, 0.48), "mark": 4, "y": 0.07, "straight": false, "utility": "",
		"desc": "Gepflasterter Fußweg."},
	"rollweg": {"name": "Rollweg", "width": 18.0, "cost_m": 1100, "min_r": 30.0, "min_len": 10.0, "code": "C",
		"color": Color(0.2, 0.2, 0.19), "mark": 2, "y": 0.04, "straight": false, "utility": "",
		"desc": "Verbindet Piste und Vorfeld. ICAO Code C: 18 m breit, für Flugzeuge bis 36 m Spannweite (ATR, Embraer, A320, 737). Mindestradius 30 m."},
	"rollweg_breit": {"name": "Rollweg breit", "width": 25.0, "cost_m": 1600, "min_r": 45.0, "min_len": 10.0, "code": "E",
		"color": Color(0.2, 0.2, 0.19), "mark": 2, "y": 0.041, "straight": false, "utility": "",
		"desc": "ICAO Code E: 25 m breit, auch für Großraumflugzeuge (A330). Mindestradius 45 m."},
	"vorfeld": {"name": "Vorfeld", "width": 60.0, "cost_m": 2600, "min_r": 25.0, "min_len": 10.0,
		"color": Color(0.47, 0.46, 0.42), "mark": 5, "y": 0.03, "straight": false, "utility": "",
		"desc": "Betonfläche für Stände und Abfertigung, 60 m breit."},
	"rolllinie": {"name": "Rollführungslinie", "short": "Rolllinie", "width": 0.45, "cost_m": 25, "min_r": 18.0, "min_len": 4.0,
		"color": Color(0.93, 0.74, 0.16), "mark": 0, "y": 0.1, "straight": false, "utility": "", "marking": true,
		"desc": "Gelbe Mittellinie zum Selberzeichnen auf Vorfeld und Rollwegen. Gibt es auf einer Fläche gezeichnete Linien, rollen die Flugzeuge dort nur noch auf ihnen. Linien verbinden sich, wo sie sich berühren oder kreuzen; Stände schließen an die nächste Linie hinter ihnen an."},
	"betriebsstrasse": {"name": "Betriebsstraße", "width": 7.0, "cost_m": 300, "min_r": 8.0, "min_len": 5.0,
		"color": Color(0.26, 0.255, 0.24), "mark": 10, "y": 0.035, "straight": false, "utility": "",
		"desc": "Fahrweg für Bodenfahrzeuge auf der Luftseite: verbindet Gerätehalle, Tanklager, Busgarage, Catering und Feuerwache mit dem Vorfeld. Ohne Anschluss erscheinen die Fahrzeuge erst am Stand und die Abfertigung dauert länger."},
	"piste": {"name": "Piste", "width": 45.0, "cost_m": 3800, "min_r": 0.0, "min_len": 400.0,
		"color": Color(0.18, 0.18, 0.17), "mark": 3, "y": 0.09, "straight": true, "utility": "",
		"desc": "Gerade, 45 m breit. ATR 72 ab 1.200 m, Airbus A320 ab 1.800 m Länge."},
	"tunnel": {"name": "Straßentunnel", "width": 8.5, "cost_m": 2400, "min_r": 25.0, "min_len": 170.0, "lanes": [1, 1],
		"color": Color(0.24, 0.235, 0.22), "mark": 1, "y": 0.06, "straight": false, "utility": "", "underground": true,
		"desc": "Straße unter der Erde, eine Spur je Richtung. Rampen von je 70 m an beiden Enden, dazwischen darf darüber gebaut werden: unter Pisten, Rollwegen und Gebäuden hindurch. Die Enden schließen an Straßen an."},
	"foerderband": {"name": "Gepäckförderband", "width": 2.4, "cost_m": 900, "min_r": 4.0, "min_len": 10.0,
		"color": Color(0.18, 0.18, 0.19), "mark": 9, "y": 0.06, "straight": false, "utility": "", "underground": true,
		"desc": "Gepäcktunnel unter dem Vorfeld: verbindet die Gepäcksortierung einer Terminalhalle mit einem Gepäckumschlag. Die Koffer laufen sichtbar in der Ansicht Untergeschoss. Abfertigung 10 % schneller."},
	"zaun": {"name": "Sicherheitszaun", "width": 0.6, "cost_m": 45, "min_r": 1.0, "min_len": 2.0,
		"color": Color(0.3, 0.35, 0.32), "mark": 0, "y": 0.05, "straight": false, "utility": "", "fence": true,
		"desc": "2,5 m hoher Stabgitterzaun mit Stacheldraht. Trennt das Vorfeld von der Landseite."},
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
		"rect_tool": true, "min": Vector2(16, 12), "max": Vector2(400, 200),
		"desc": "Hülle des Terminals: zwei Ecken klicken. Innen baust du Eingang, Check-in, Kontrolle, Gates und mehr. Braucht Strom, für Heizkörper Wärme, für WCs Wasser."},
	"stand": {"name": "Stand mit Brücke", "short": "Kontaktstand", "size": Vector2(40, 46), "h": 0.2, "cost": 60000, "grid": 1.0, "on": "vorfeld",
		"desc": "Abstellposition am Terminal: Die Fluggastbrücke des nächsten Gates dockt an (Reichweite 36 m). Nase zeigt zum Terminal. Muss auf dem Vorfeld liegen."},
	"stand_gross": {"name": "Großraum-Stand", "size": Vector2(66, 74), "h": 0.2, "cost": 95000, "grid": 1.0, "on": "vorfeld", "code": "E",
		"desc": "Position für Großraumflugzeuge (A330, Code E), passt auch für alle kleineren. Mit Brücke, wenn eine in Reichweite ist, sonst Bus und Treppe. Braucht breite Rollwege."},
	"stand_aussen": {"name": "Außenposition", "size": Vector2(40, 46), "h": 0.2, "cost": 45000, "grid": 1.0, "on": "vorfeld",
		"desc": "Abstellposition ohne Brücke: Treppenwagen docken an, Vorfeldbusse bringen die Passagiere vom Bus-Gate. Braucht ein Bus-Gate und am besten eine Vorfeld-Haltestelle."},
	"fluggastbruecke": {"name": "Fluggastbrücke", "short": "Brücke", "size": Vector2(4, 4), "h": 6.5, "cost": 260000, "grid": 1.0,
		"bridge": true,
		"desc": "Direkt vor die Außenwand eines Terminals setzen, gegenüber einem Gate. Der Teleskoptunnel fährt bis 38 m weit an Tür L1 des Flugzeugs."},
	"befeuerungsstation": {"name": "Befeuerungsstation", "short": "Befeuerung", "size": Vector2(12, 7), "h": 4.2, "cost": 180000, "grid": 1.0,
		"needs": {"strom": 25},
		"desc": "Schaltanlage mit Konstantstromreglern: Mit Strom leuchten Rand-, Schwellen-, Mittellinien- und Aufsetzzonenfeuer der Pisten im Umkreis von 450 m und die Rollwegbefeuerung. Ohne Befeuerung landet und startet nachts niemand."},
	"anflugbefeuerung": {"name": "Anflugbefeuerung", "size": Vector2(8, 8), "h": 2.5, "cost": 240000, "grid": 1.0, "marker": "pistenende",
		"desc": "900 m lange Lichterkette mit Querbalken und Lauffeuer vor einer Pistenschwelle (CAT I). Rastet am Pistenende ein, leuchtet mit der Befeuerungsstation. Anflüge bei Nacht und schlechtem Wetter werden pünktlicher."},
	"papi": {"name": "PAPI", "short": "Gleitwinkelfeuer", "size": Vector2(6, 6), "h": 1.3, "cost": 60000, "grid": 1.0, "marker": "papi",
		"desc": "Gleitwinkelbefeuerung: vier Lampenkästen links neben dem Aufsetzpunkt zeigen den Piloten rot und weiß. Rastet neben der Piste ein."},
	"rollhalt": {"name": "Rollhalteort", "size": Vector2(4, 4), "h": 1.2, "cost": 15000, "grid": 1.0, "marker": "rollweg",
		"desc": "Haltepunkt auf einem Rollweg vor der Piste: Markierung, Haltebalken, Pistenwarnlichter und Schilder. Abflüge warten hier auf die Startfreigabe, Ankünfte kreuzen erst mit Freigabe. 60 bis 250 m vor der Pistenmitte auf einen Rollweg setzen; ohne eigenen Haltepunkt gilt ein gedachter bei 90 m."},
	"flutlicht": {"name": "Flutlichtmast", "size": Vector2(2, 2), "h": 25.0, "cost": 30000, "grid": 1.0,
		"desc": "25 m hoher Mast mit vier Scheinwerfern. Leuchtet nachts das Vorfeld aus."},
	"bushalt": {"name": "Vorfeld-Haltestelle", "short": "Bushaltestelle", "size": Vector2(28, 7), "h": 3.4, "cost": 35000, "grid": 1.0, "on": "vorfeld",
		"desc": "Haltebucht mit Dach für die Vorfeldbusse, nah am Bus-Gate. Hier steigen die Passagiere der Außenpositionen ein und aus."},
	"vorfelddepot": {"name": "Gerätehalle", "size": Vector2(26, 16), "h": 7.0, "cost": 380000, "grid": 2.0,
		"needs": {"strom": 30}, "garage": ["gpu", "bandlader", "zug", "schlepper", "treppe"],
		"doors": [[Vector3(-9, 0, 8), 4.6, 4.4, 4.5], [Vector3(-3, 0, 8), 4.6, 4.4, 4.5], [Vector3(3, 0, 8), 4.6, 4.4, 4.5], [Vector3(9, 0, 8), 4.6, 4.4, 4.5]], "desc": "Tankwagen, Gepäckschlepper und Catering. Ohne Depot mit Strom dauert jede Abfertigung anderthalbmal so lang."},
	"tanklager": {"name": "Tanklager", "size": Vector2(44, 32), "h": 14.0, "cost": 2200000, "grid": 2.0,
		"needs": {"strom": 30}, "garage": ["tank"], "doors": [[Vector3(-7, 0, 16), 5.0, 4.6, 6.0], [Vector3(7, 0, 16), 5.0, 4.6, 6.0]],
		"desc": "Drei Kerosintanks in einer Auffangwanne, Pumpenhaus, Füllstation und Wagenhalle mit zwei Rolltoren. Die Tankwagen fahren hier los und kommen zum Nachfüllen zurück. Ohne Tanklager wird nicht betankt und es gibt keine Einnahmen aus dem Kerosinverkauf."},
	"busgarage": {"name": "Busgarage", "size": Vector2(36, 22), "h": 7.5, "cost": 650000, "grid": 2.0,
		"needs": {"strom": 25}, "garage": ["bus"], "doors": [[Vector3(-11, 0, 11), 5.0, 4.6, 8.0], [Vector3(0, 0, 11), 5.0, 4.6, 8.0], [Vector3(11, 0, 11), 5.0, 4.6, 8.0]],
		"desc": "Halle für die Vorfeldbusse mit drei Rolltoren und Waschplatz. Die Busse zu den Außenpositionen starten hier; ohne Busgarage dauert das Einsteigen dort länger."},
	"catering": {"name": "Cateringbetrieb", "size": Vector2(30, 20), "h": 8.0, "cost": 900000, "grid": 2.0,
		"needs": {"strom": 60, "wasser": 4}, "garage": ["catering"], "doors": [[Vector3(-7, 0, 10), 4.0, 4.2, 5.0], [Vector3(2, 0, 10), 4.0, 4.2, 5.0]],
		"desc": "Großküche mit Laderampe. Die Hubwagen holen hier das Bordessen und fahren zu Tür R2. Bringt 2 € je abfliegendem Fluggast; ohne Catering gibt es nichts an Bord."},
	"personalgebaeude": {"name": "Personalgebäude", "size": Vector2(28, 16), "h": 11.5, "cost": 1100000, "grid": 2.0,
		"needs": {"strom": 40, "wasser": 3}, "staff": 160,
		"desc": "Umkleiden, Kantine und Büros für 160 Mitarbeiter. Zum Schichtwechsel laufen sie zum Terminal und zurück. Fehlt Personal, dauert jede Abfertigung länger."},
	"tower": {"name": "Tower", "size": Vector2(12, 12), "h": 39.0, "cost": 900000, "grid": 2.0,
		"needs": {"strom": 60}, "desc": "Ohne Tower mit Strom finden keine Flüge statt."},
	"hangar": {"name": "Hangar", "size": Vector2(44, 36), "h": 14.0, "cost": 650000, "grid": 2.0,
		"needs": {"strom": 120}, "desc": "Wartungshalle für Flugzeuge."},
	"feuerwache": {"name": "Feuerwache", "size": Vector2(30, 20), "h": 13.0, "cost": 700000, "grid": 2.0,
		"doors": [[Vector3(-11.5, 0, 4), 5.4, 5.4, 5.6], [Vector3(-4.5, 0, 4), 5.4, 5.4, 5.6], [Vector3(2.5, 0, 4), 5.4, 5.4, 5.6]],
		"needs": {"strom": 50, "wasser": 6}, "desc": "Flughafenfeuerwehr."},
	"parkhaus": {"name": "Parkhaus", "size": Vector2(32, 44), "h": 14.5, "cost": 1500000, "grid": 2.0,
		"needs": {"strom": 80}, "access": {"ein": Vector2(-6, -24), "aus": Vector2(6, -24)}, "spaces": 300,
		"desc": "Vier Ebenen, 300 Plätze. Ein- und Ausfahrt mit Schranke an der Vorderseite (Pfeil beim Setzen): dort muss eine Straße vorbeiführen. Bringt Parkgebühren."},
	"gepaeckumschlag": {"name": "Gepäckumschlag", "size": Vector2(30, 18), "h": 7.5, "cost": 520000, "grid": 2.0,
		"needs": {"strom": 35},
		"desc": "Halle am Vorfeld, in der die Koffer auf Gepäckwagen verladen werden. Mit einem Gepäckförderband zur Terminalhalle verbinden: Dann starten die Gepäckzüge hier und jede Abfertigung geht 10 % schneller."},
	"haltestelle": {"name": "Bushaltestelle", "size": Vector2(16, 4), "h": 3.2, "cost": 30000, "grid": 1.0,
		"access": {"halt": Vector2(0, -4.5)},
		"desc": "Haltestelle für Linienbusse an einer Straße (Pfeil zeigt zur Straße). Busse bringen Fluggäste aus der Stadt und nehmen andere mit. Hebt die Zufriedenheit."},
	"trafo": {"name": "Trafostation", "size": Vector2(10, 7), "h": 3.7, "cost": 180000, "grid": 1.0,
		"supply": {"strom": 630}, "desc": "Liefert 630 kW Strom über Kabel."},
	"wasseranschluss": {"name": "Wasseranschluss", "size": Vector2(4, 4), "h": 1.6, "cost": 25000, "grid": 1.0,
		"supply": {"wasser": 40}, "desc": "Anschluss an das öffentliche Netz, 40 m³/h."},
	"heizzentrale": {"name": "Heizzentrale", "size": Vector2(22, 15), "h": 23.0, "cost": 450000, "grid": 1.0,
		"needs": {"strom": 40, "wasser": 4}, "supply": {"waerme": 900},
		"desc": "Erzeugt 900 kW Wärme. Mit Heizrohren zur Terminalhalle verbinden."},
	"parkplatz": {"name": "Parkplatz", "size": Vector2(32, 25), "h": 0.5, "cost": 260000, "grid": 2.0,
		"access": {"ein": Vector2(-6.7, -13), "aus": Vector2(6.7, -13)}, "spaces": 22,
		"desc": "Ebenerdiger Parkplatz mit 22 Stellplätzen und Schranken. Die Zufahrt (Pfeil) muss an einer Straße liegen. Bringt Parkgebühren."},
	"busch": {"name": "Busch", "size": Vector2(2, 2), "h": 1.6, "cost": 200, "grid": 0.5, "desc": "Blühender Strauch."},
	"hecke": {"name": "Hecke", "size": Vector2(6, 1.2), "h": 1.7, "cost": 600, "grid": 0.5, "desc": "Geschnittene Hecke, 6 m."},
	"blumenbeet": {"name": "Blumenbeet", "size": Vector2(4, 2), "h": 0.7, "cost": 800, "grid": 0.5, "desc": "Bunte Blumen im Steinrand."},
	"teich": {"name": "Teich", "size": Vector2(13, 9), "h": 1.5, "cost": 9000, "grid": 1.0,
		"desc": "Teich mit Schilf, Seerosen und zwei Enten, die ihre Runden drehen."},
	"felsen": {"name": "Felsen", "size": Vector2(3, 3), "h": 1.2, "cost": 900, "grid": 0.5, "desc": "Findlinge mit Gräsern."},
	"picknick": {"name": "Picknicktisch", "size": Vector2(2.2, 2.2), "h": 0.8, "cost": 500, "grid": 0.5, "desc": "Holztisch mit Bänken für die Pause."},
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
	"busgate": {"name": "Bus-Gate", "size": Vector2(10, 8), "h": 3.2, "cost": 80000, "grid": 1.0, "inside": true,
		"wall": true, "walk": true, "needs": {"strom": 4},
		"desc": "Wartebereich mit Tür und Treppe zum Vorfeld. Von hier fahren die Busse zu den Außenpositionen. An die Außenwand zum Vorfeld stellen."},
	"rolltreppe": {"name": "Rolltreppe", "size": Vector2(2, 10), "h": 5.0, "cost": 120000, "grid": 1.0, "inside": true,
		"walk": true, "connector": true, "needs": {"strom": 8}, "decor": 1,
		"desc": "Verbindet diese Ebene mit der Ebene darüber. Passagiere fahren in Pfeilrichtung (+Z) nach oben, auf der zweiten Spur hinunter."},
	"aufzug": {"name": "Aufzug", "size": Vector2(3, 3), "h": 5.0, "cost": 90000, "grid": 1.0, "inside": true,
		"walk": true, "connector": true, "needs": {"strom": 6},
		"desc": "Gläserner Aufzug zur Ebene darüber, für alle mit schwerem Gepäck."},
	"treppe": {"name": "Treppe", "size": Vector2(3, 9), "h": 5.0, "cost": 30000, "grid": 1.0, "inside": true,
		"walk": true, "connector": true,
		"desc": "Feste Treppe zur Ebene darüber."},
	"passkontrolle": {"name": "Passkontrolle", "short": "Pässe", "size": Vector2(6, 6), "h": 2.6, "cost": 110000, "grid": 1.0,
		"inside": true, "walk": true, "needs": {"strom": 4}, "cap": 220,
		"desc": "Grenzkontrolle der Bundespolizei mit drei Kabinen. Trennt den Schengen- vom Non-Schengen-Bereich: Wer dorthin will (oder von dort kommt), muss hindurch."},
	"zoll": {"name": "Zoll", "size": Vector2(6, 5), "h": 2.6, "cost": 70000, "grid": 1.0, "inside": true, "walk": true,
		"needs": {"strom": 2},
		"desc": "Grüner und roter Kanal. Ankommende aus Non-Schengen-Ländern gehen nach dem Gepäckband hindurch."},
	"tuer": {"name": "Tür", "size": Vector2(2.4, 0.6), "h": 2.4, "cost": 4000, "grid": 0.5, "inside": true, "walk": true, "door": true,
		"desc": "Auf eine Innenwand setzen: Die Wand bekommt eine Öffnung. Automatiktür und Flügeltür gehen auf, wenn jemand kommt. Durch die Personaltür (mit Kartenleser) kommen nur Mitarbeiter."},
	"bereich_oeffentlich": {"name": "Öffentlicher Bereich", "short": "Öffentlich", "size": Vector2(4, 4), "h": 0.1, "cost": 0, "cost_m2": 3,
		"grid": 1.0, "inside": true, "rect_tool": true, "zone": "oeffentlich",
		"desc": "Bodenfläche für alle: Eingang, Check-in, Gepäckband und Ankunft. Rechteck mit zwei Klicks aufziehen."},
	"bereich_sicherheit": {"name": "Sicherheitsbereich", "short": "Sicherheit", "size": Vector2(4, 4), "h": 0.1, "cost": 0, "cost_m2": 6,
		"grid": 1.0, "inside": true, "rect_tool": true, "zone": "sicherheit",
		"desc": "Bereich hinter der Kontrolle. Alle Gates müssen darin liegen, und vom Eingang darf man nur durch die Sicherheitskontrolle hineinkommen. Läden und Cafés verdienen hier die Hälfte mehr."},
	"bereich_personal": {"name": "Personalbereich", "short": "Personal", "size": Vector2(4, 4), "h": 0.1, "cost": 0, "cost_m2": 5,
		"grid": 1.0, "inside": true, "rect_tool": true, "zone": "personal",
		"desc": "Nur für Mitarbeiter: Gepäcksortierung, Personalräume, Technik. Fluggäste kommen hier nicht hinein, Mitarbeiter nur durch Personaltüren."},
	"personalraum": {"name": "Personalraum", "size": Vector2(6, 4), "h": 2.6, "cost": 25000, "grid": 0.5, "inside": true,
		"needs": {"strom": 2, "wasser": 0.5},
		"desc": "Spinde, Tisch, Kaffeemaschine und Sofa für die Pause. In den Personalbereich stellen. Von hier gehen die Mitarbeiter an ihre Schalter."},
	"sb_ausgang": {"name": "Ausgang Sicherheitsbereich", "short": "SB-Ausgang", "size": Vector2(4, 1), "h": 2.9, "cost": 30000,
		"grid": 1.0, "inside": true, "walk": true, "oneway": true, "needs": {"strom": 1},
		"desc": "Einbahn-Tür in einer Lücke der Trennwand: Ankommende verlassen den Sicherheitsbereich, hinein kommt niemand. Vorderseite (Pfeil) zeigt nach draußen."},
	"gepaeckband": {"name": "Gepäckband", "size": Vector2(10, 5), "h": 2.2, "cost": 120000, "grid": 1.0,
		"inside": true, "needs": {"strom": 10}, "cap": 300,
		"desc": "Hier holen ankommende Passagiere ihre Koffer, 300 Passagiere pro Stunde."},
	"wc": {"name": "Toiletten", "size": Vector2(6, 5), "h": 2.7, "cost": 70000, "grid": 1.0, "inside": true,
		"needs": {"strom": 2, "wasser": 3}, "cap": 250,
		"desc": "Damen, Herren, barrierefrei. 250 Passagiere pro Stunde. Braucht Wasser in der Halle."},
	"heizkoerper": {"name": "Heizkörper", "size": Vector2(2, 0.5), "h": 0.9, "cost": 1500, "grid": 0.5,
		"inside": true, "needs": {"waerme": 30}, "heats": 400,
		"desc": "Heizt 400 m² Halle. Braucht Wärme von der Heizzentrale über ein Heizrohr."},
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
	# ---- Möbel und Ausstattung (furniture.gd), viele davon bewegt
	"uhr": {"name": "Bahnhofsuhr", "size": Vector2(1, 1), "h": 3.7, "cost": 4000, "grid": 0.5, "inside": true, "decor": 1,
		"desc": "Doppelseitige Uhr an einer Säule. Die Zeiger laufen mit der Spielzeit, der rote Sekundenzeiger tickt."},
	"snackautomat": {"name": "Snackautomat", "size": Vector2(1.2, 1), "h": 2.0, "cost": 6000, "grid": 0.5, "inside": true,
		"needs": {"strom": 1}, "retail": 1, "decor": 1, "desc": "Beleuchteter Automat mit Snacks. Bringt 1 € je Abflug."},
	"getraenkeautomat": {"name": "Getränkeautomat", "size": Vector2(1.2, 1), "h": 2.0, "cost": 6000, "grid": 0.5, "inside": true,
		"needs": {"strom": 1}, "retail": 1, "decor": 1, "desc": "Kühle Getränke. Bringt 1 € je Abflug."},
	"infoschalter": {"name": "Info-Schalter", "size": Vector2(4, 3), "h": 3.6, "cost": 35000, "grid": 0.5, "inside": true,
		"needs": {"strom": 1}, "decor": 3, "desc": "Runder Tresen mit zwei Mitarbeitern. Passagiere fühlen sich gut aufgehoben."},
	"lounge": {"name": "Lounge-Ecke", "size": Vector2(4, 4), "h": 1.8, "cost": 12000, "grid": 0.5, "inside": true, "decor": 3,
		"desc": "Zwei Sofas, Couchtisch mit Zeitschriften, Stehlampe und Teppich."},
	"bistrotisch": {"name": "Bistrotische", "size": Vector2(3, 3), "h": 1.0, "cost": 3500, "grid": 0.5, "inside": true, "decor": 1,
		"desc": "Zwei kleine Tische mit Holzstühlen, passend zum Café."},
	"trinkbrunnen": {"name": "Trinkbrunnen", "size": Vector2(1, 1), "h": 1.1, "cost": 3000, "grid": 0.5, "inside": true,
		"needs": {"wasser": 0.2}, "decor": 1, "desc": "Wasser zum Nachfüllen der Flasche, mit sprudelnder Fontäne."},
	"rollsteig": {"name": "Rollsteig", "size": Vector2(2, 14), "h": 1.1, "cost": 95000, "grid": 1.0, "inside": true,
		"walk": true, "needs": {"strom": 6}, "decor": 2, "desc": "Laufband für lange Wege zu den Gates. Die Paletten laufen sichtbar."},
	"werbebildschirm": {"name": "Werbebildschirm", "size": Vector2(1.5, 0.5), "h": 2.6, "cost": 9000, "grid": 0.5, "inside": true,
		"needs": {"strom": 1}, "retail": 1, "decor": 1, "desc": "Digitale Stele mit wechselnden Motiven. Bringt Werbeeinnahmen."},
	"spielecke": {"name": "Kinderspielecke", "size": Vector2(5, 5), "h": 1.3, "cost": 18000, "grid": 0.5, "inside": true, "decor": 3,
		"desc": "Rutsche, Schaukelpferd, Softbausteine und ein Spielteppich mit Straßen."},
	"ladestation": {"name": "Ladestation", "size": Vector2(1, 1), "h": 1.2, "cost": 4500, "grid": 0.5, "inside": true,
		"needs": {"strom": 1}, "decor": 2, "desc": "Handys laden: Säule mit sechs Anschlüssen und Ladeanzeigen."},
	"geldautomat": {"name": "Geldautomat", "size": Vector2(1.2, 1), "h": 2.2, "cost": 15000, "grid": 0.5, "inside": true,
		"needs": {"strom": 1}, "retail": 1, "decor": 1, "desc": "Bargeld für die Reise. Bringt Gebühren."},
	"kofferwagen": {"name": "Kofferwagen", "size": Vector2(3, 1.2), "h": 1.6, "cost": 2500, "grid": 0.5, "inside": true, "decor": 1,
		"desc": "Gepäckwagen zum Ausleihen, ineinander geschoben."},
	"kiosk": {"name": "Zeitungskiosk", "size": Vector2(3, 2.2), "h": 2.9, "cost": 30000, "grid": 0.5, "inside": true,
		"needs": {"strom": 2}, "retail": 2, "decor": 2, "desc": "Zeitschriften, Bücher und Getränke. Bringt 2 € je Abflug."},
	"aquarium": {"name": "Aquarium", "size": Vector2(4, 1.2), "h": 2.2, "cost": 40000, "grid": 0.5, "inside": true,
		"needs": {"strom": 2}, "decor": 4, "desc": "Großes Becken mit Fischschwärmen, Pflanzen und Luftblasen. Beruhigt vor dem Flug."},
	"palme": {"name": "Zimmerpalme", "size": Vector2(1.5, 1.5), "h": 3.0, "cost": 900, "grid": 0.5, "inside": true, "decor": 1,
		"desc": "Palme im Topf, die Wedel wiegen sich in der Lüftung."},
	"baumbeet": {"name": "Baum im Beet", "size": Vector2(4, 4), "h": 4.5, "cost": 8000, "grid": 0.5, "inside": true, "decor": 3,
		"desc": "Echter Baum im Hochbeet mit Blumen und Sitzrand aus Holz."},
	"flugzeugmodell": {"name": "Flugzeugmodell", "size": Vector2(4, 4), "h": 5.0, "cost": 20000, "grid": 0.5, "inside": true, "decor": 3,
		"desc": "Großes Modell eines A320, hängt an Seilen und dreht sich langsam."},
	"fahnen": {"name": "Fahnen", "size": Vector2(4, 0.6), "h": 4.5, "cost": 3000, "grid": 0.5, "inside": true, "decor": 2,
		"desc": "Vier Fahnen in Airline-Farben."},
	"fluegel": {"name": "Konzertflügel", "size": Vector2(2, 3), "h": 1.8, "cost": 25000, "grid": 0.5, "inside": true, "decor": 3,
		"desc": "Flügel mit Pianistin. Musik im Terminal."},
	"massagesessel": {"name": "Massagesessel", "size": Vector2(2.4, 1.2), "h": 1.4, "cost": 9000, "grid": 0.5, "inside": true,
		"needs": {"strom": 1}, "retail": 1, "decor": 1, "desc": "Zwei Sessel, die den Rücken massieren. Gegen Münzeinwurf."},
	"muelltrennung": {"name": "Mülltrennung", "size": Vector2(1.6, 0.6), "h": 1.0, "cost": 1200, "grid": 0.5, "inside": true, "decor": 1,
		"desc": "Papier, Verpackung, Glas, Rest."},
	"gruenwand": {"name": "Grüne Wand", "size": Vector2(4, 0.5), "h": 3.3, "cost": 14000, "grid": 0.5, "inside": true,
		"needs": {"wasser": 0.3}, "decor": 3, "desc": "Senkrechter Garten mit Farnen und Blüten."},
	"springbrunnen": {"name": "Springbrunnen", "size": Vector2(4, 4), "h": 2.0, "cost": 30000, "grid": 0.5, "inside": true,
		"needs": {"wasser": 1}, "decor": 4, "desc": "Rundes Becken mit drei Fontänen, die steigen und fallen."},
	"kunst": {"name": "Kunstwerk", "size": Vector2(3, 3), "h": 3.5, "cost": 25000, "grid": 0.5, "inside": true,
		"decor": 3, "desc": "Skulptur als Blickfang."},
}

## Kategorien des Baumenüs: [Schlüssel, Titel, Teile]
const CATEGORIES := [
	["wege", "Wege", ["strasse", "strasse4", "einbahn", "tunnel", "spuren", "kreuzung", "gehweg", "rollweg", "rollweg_breit", "vorfeld", "rolllinie", "piste"]],
	["flug", "Flugbetrieb", ["stand", "stand_aussen", "stand_gross", "fluggastbruecke", "bushalt", "flutlicht", "rollhalt", "befeuerungsstation", "anflugbefeuerung", "papi", "tower", "betriebsstrasse", "vorfelddepot", "tanklager", "busgarage", "catering", "gepaeckumschlag", "foerderband", "hangar", "feuerwache", "personalgebaeude"]],
	["terminal", "Terminal", ["halle", "innenwand", "glaswand", "tuer", "bereich_oeffentlich", "bereich_sicherheit", "bereich_personal", "eingang", "checkin", "gepaeckanlage", "sicherheit", "sb_ausgang", "passkontrolle", "zoll", "gate", "busgate", "gepaeckband", "rolltreppe", "aufzug", "treppe", "personalraum"]],
	["ausstattung", "Ausstattung", ["wc", "heizkoerper", "cafe", "shop", "sitzreihe", "pflanze", "anzeige", "kunst", "infoschalter", "kiosk", "rollsteig"]],
	["moebel", "Möbel", ["uhr", "lounge", "bistrotisch", "snackautomat", "getraenkeautomat", "geldautomat", "trinkbrunnen", "werbebildschirm",
		"ladestation", "kofferwagen", "massagesessel", "muelltrennung", "spielecke", "aquarium", "palme", "baumbeet", "gruenwand",
		"springbrunnen", "fluegel", "flugzeugmodell", "fahnen"]],
	["versorgung", "Versorgung", ["stromkabel", "wasserrohr", "heizrohr", "trafo", "wasseranschluss", "heizzentrale"]],
	["umfeld", "Umfeld", ["parkhaus", "parkplatz", "haltestelle", "zaun", "baum", "busch", "hecke", "blumenbeet", "teich", "felsen", "kuebel", "laterne", "bank", "picknick"]],
]

## Höhe einer Terminal-Ebene in Metern (Keller = Ebene -1)
const FLOOR_H := 5.0

## Versorgungsnetze mit Anzeigename und Einheit
const UTILITIES := {"strom": ["Strom", "kW"], "wasser": ["Wasser", "m³/h"], "waerme": ["Wärme", "kW"]}
## Strombedarf der Halle selbst (Licht, Lüftung) je Quadratmeter
const HALL_POWER_M2 := 0.03

## Flugzeugtypen: Pistenlänge, Sitzplätze, Abfertigungszeit in Spielminuten, Landeentgelt.
## code: ICAO-Code nach Spannweite (C bis 36 m, E bis 65 m) – bestimmt Stand und Rollweg.
## range: Kurz-, Mittel- oder Langstrecke (für die Ziele).
const PLANES := {
	"atr72": {"name": "ATR 72-600", "min_rwy": 1200.0, "pax": 70, "turn": 25.0, "fee": 900, "vapp": 57.0, "vr": 55.0, "nose": 13.6,
		"code": "C", "span": 27.0, "range": "kurz"},
	"e190": {"name": "Embraer 190", "min_rwy": 1500.0, "pax": 100, "turn": 30.0, "fee": 1500, "vapp": 64.0, "vr": 66.0, "nose": 18.1,
		"code": "C", "span": 28.7, "range": "kurz"},
	"a320": {"name": "Airbus A320", "min_rwy": 1700.0, "pax": 180, "turn": 40.0, "fee": 2400, "vapp": 70.0, "vr": 72.0, "nose": 18.8,
		"code": "C", "span": 35.8, "range": "mittel"},
	"b737": {"name": "Boeing 737-800", "min_rwy": 1700.0, "pax": 189, "turn": 42.0, "fee": 2500, "vapp": 72.0, "vr": 74.0, "nose": 19.75,
		"code": "C", "span": 35.8, "range": "mittel"},
	"a321": {"name": "Airbus A321neo", "min_rwy": 2000.0, "pax": 220, "turn": 45.0, "fee": 2900, "vapp": 72.0, "vr": 75.0, "nose": 22.25,
		"code": "C", "span": 35.8, "range": "mittel"},
	"a330": {"name": "Airbus A330-300", "min_rwy": 2500.0, "pax": 290, "turn": 60.0, "fee": 5200, "vapp": 72.0, "vr": 78.0, "nose": 31.85,
		"code": "E", "span": 60.3, "range": "lang"},
}
## Ausgedachte Airlines mit Hausfarbe
const AIRLINES := [["IF", Color(0.62, 0.22, 0.18)], ["DJ", Color(0.18, 0.30, 0.52)], ["BW", Color(0.16, 0.42, 0.40)],
	["WZ", Color(0.85, 0.55, 0.12)], ["NX", Color(0.35, 0.22, 0.48)]]
## Ziele: [Name, Schengen?, Reichweite]
const DESTINATIONS := [["Hamburg", true, "kurz"], ["Berlin", true, "kurz"], ["Sylt", true, "kurz"], ["Kopenhagen", true, "kurz"],
	["Palma", true, "mittel"], ["Wien", true, "mittel"], ["Zürich", true, "mittel"], ["Rom", true, "mittel"], ["Paris", true, "mittel"],
	["Amsterdam", true, "mittel"], ["Lissabon", true, "mittel"], ["London", false, "mittel"], ["Antalya", false, "mittel"],
	["Istanbul", false, "mittel"], ["Dublin", false, "mittel"], ["New York", false, "lang"], ["Dubai", false, "lang"],
	["Toronto", false, "lang"], ["Singapur", false, "lang"]]
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
	if TOOLS.has(id):
		return String(TOOLS[id]["name"])
	return id


## Werkzeuge ohne eigenes Bauteil
const TOOLS := {
	"spuren": {"name": "Spuren ändern", "desc": "Klicke auf eine Straße: 2-spurig, 4-spurig, Einbahnstraße und umgekehrte Einbahnstraße im Wechsel."},
	"kreuzung": {"name": "Kreuzung regeln", "desc": "Klicke auf eine Kreuzung: rechts vor links, Vorfahrtsstraße oder Ampel im Wechsel."},
}
const ROADS := ["strasse", "strasse4", "einbahn", "tunnel"]
## Tunnel: Tiefe der Fahrbahn, Länge einer Rampe, ab welcher Tiefe die Decke geschlossen ist
const TUNNEL_DEPTH := 7.0
const TUNNEL_RAMP := 70.0
const TUNNEL_COVER := -5.4


static func is_road(kind: String) -> bool:
	return kind in ROADS


static func is_inside(id: String) -> bool:
	return ITEMS.has(id) and bool(ITEMS[id].get("inside", false))


## Bodenbereich im Terminal (öffentlich, Sicherheitsbereich, Personal)?
static func is_zone(id: String) -> bool:
	return ITEMS.has(id) and ITEMS[id].has("zone")


## Markierung oder Befeuerung, die an Piste oder Rollweg einrastet (Lage statt Drehung bestimmt das Aussehen).
## Bodenmarkierung als Weg (Rollführungslinie): liegt auf anderen Belägen, kreuzt alles.
static func is_marking(kind: String) -> bool:
	return LINES.has(kind) and bool(LINES[kind].get("marking", false))


static func is_marker(id: String) -> bool:
	return ITEMS.has(id) and ITEMS[id].has("marker")


static func is_door(id: String) -> bool:
	return ITEMS.has(id) and bool(ITEMS[id].get("door", false))


## Garage für diese Fahrzeugart (Kind wie in ground_ops): Gebäude-IDs
static func garages_for(vehicle: String) -> Array:
	var out := []
	for id: String in ITEMS:
		if vehicle in (ITEMS[id].get("garage", []) as Array):
			out.append(id)
	return out


static func is_wall(kind: String) -> bool:
	return LINES.has(kind) and bool(LINES[kind].get("wall", false))


## Gehört dieses Werkzeug zum Terminalbau (dann Innenansicht einschalten)?
static func is_terminal_tool(id: String) -> bool:
	return id == "halle" or is_inside(id) or is_wall(id)


static func is_underground(kind: String) -> bool:
	return LINES.has(kind) and bool(LINES[kind].get("underground", false))


## Liegt dieser Stützpunkt eines Weges unter der Erde (dann darf man darüber bauen)?
static func covered(kind: String, v: Vector3) -> bool:
	if kind == "foerderband":
		return true
	return kind == "tunnel" and v.y < TUNNEL_COVER


## Höhenverlauf eines Tunnels: sanfte Rampen an beiden Enden.
static func tunnel_profile(samples: PackedVector3Array) -> PackedVector3Array:
	var n := samples.size()
	if n < 2:
		return samples
	var total := 0.0
	var dist := PackedFloat32Array([0.0])
	for i in range(1, n):
		total += Vector2(samples[i].x - samples[i - 1].x, samples[i].z - samples[i - 1].z).length()
		dist.append(total)
	var out := PackedVector3Array()
	for i in range(n):
		var d := dist[i]
		var y := -TUNNEL_DEPTH * smoothstep(0.0, TUNNEL_RAMP, d) * smoothstep(0.0, TUNNEL_RAMP, total - d)
		out.append(Vector3(samples[i].x, y, samples[i].z))
	return out


static func utility_of(kind: String) -> String:
	if LINES.has(kind):
		return String(LINES[kind].get("utility", ""))
	return ""
