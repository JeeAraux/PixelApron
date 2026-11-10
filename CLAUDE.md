# PixelApron

Flughafen-Aufbauspiel in Godot 4.7 (GDScript), isometrischer Pixel-Look. Sprache im Spiel und im Code: Deutsch.

## Arbeiten am Projekt
- Selbsttest: `godot --headless --path . -- --selftest` muss mit `SELFTEST BESTANDEN` enden.
- Vorschaubilder: `--demo --mode=bauen|leitungen|abfertigung|terminal|halle|kreuzung|verkehr|ampel|parkhaus|tower|hangar|feuerwache|modelle|modelle_nah|modelle_a320|modelle_b737|menu|einstellungen|rollhalt|piste|vorfeld|anflug|karte|pushback|bus|rollen|haltestelle|dienste|landseite|untergrund|moebel --shot=PFAD` (mit Fenster/xvfb, am besten `--rendering-driver opengl3`). Zusätze: `--zeit=STUNDE`, `--zoom=`, `--at=x,z`, `--f=0.6` (Abfertigungsanteil bei `dienste`), `--flach` (Tunnel von oben).
- Fehlersuche: `--fldebug` (tests/dbg/fl_debug.gd: Zustandswechsel, Begegnungen unter 25 m, wartende Flugzeuge), `--dbg=NAME` lädt `tests/dbg/NAME.gd` und ruft `run(main)`.
- Detailmodelle (Flugzeuge, Menschen, Autos, Bodenfahrzeuge) entstehen in `scripts/models.gd` mit dem Baukasten `scripts/mesh_kit.gd` als ein Mesh mit Vertexfarben. Dreiecke im Uhrzeigersinn von außen = Vorderseite.
- Wegebau-Regeln (Kreuzungen, Kollisionen) stehen in `game_state.gd` (`check_line`, `CROSS_OK`), Einrasten in `builder.gd` (`_snap_line`).
- Straßennetz in `roads.gd` (Knoten, Spurgeometrie, Kreuzungsflächen, Schilder, Ampelphasen, `cycle_control`), Verkehr in `traffic.gd` (Legs: lane/conn/change/drive, Vorfahrt, Ziele Parkhaus und Terminal-Haltebucht). `traffic.step(dt)` lässt sich im Test direkt aufrufen.
- Sicherheitsbereich: `terminal.gd` `_security_problems` (Flutfüllung auf zwei Rastern: "dep" mit gesperrtem Einbahn-Ausgang, "arr" mit gesperrter Kontrolle).
- Neue Bauteile stehen als Daten in `scripts/catalog.gd`, ihre Form in `scripts/factory.gd`. `Factory.bake()` fasst einfarbige Teile zu einem Mesh zusammen; Knoten mit Meta `no_bake` (z. B. animierte Koffer) und benannte Gruppen bleiben einzeln.
- Flugzeuge: bewegliche Teile (Fahrwerk, FanL/FanR, Beacon, Strobe) animiert `flights.gd` `_animate`. Fluggastbrücken sind eigene Bauteile ("fluggastbruecke"), Bewegung in `terminal.gd` (`_rebuild_bridges`, `_move_bridges`).
- Rollverkehr (`flights.gd` `_drive`): Knotenreservierung (LOOKAHEAD/CLEAR, `near` 30 m), Blocksicherung bis zur nächsten Kreuzung (`_block_ahead`), Gegenverkehr über `_route_sets`/`_yield_point` (wer weiter weg ist, wartet), Pushback-Freigabe in `_plan_pushback`, Geisterfahrt nur als letzte Notlösung. Pistenfreigabe `_may_take_runway`/`_arrival_close`. Graph in `airside.gd`.
- Bodenabfertigung (`ground_ops.gd`): Schlepper, Treppen, Vorfeldbusse, Fußgänger draußen und die Dienste am Stand (`service_plan` je Typ aus `Models.SPECS`, `turn_start/turn_step/turn_end/turn_clear`). Fahrzeuge weichen einander und rollenden Flugzeugen aus (`_blocked`). Bewegliche Teile: Band, Kasten/Schere/Bühne, Schlauch, Gepäckwagen.
- Flugfeld-Optik (`airfield.gd`): Befeuerung, Schilder, Rollhalte, Standmarkierungen, Lichthöfe; Pixelschrift `pixel_font.gd`.
- Stockwerke: `Catalog.FLOOR_H`, Hallen-Optionen etagen/keller, Verbinder (Rolltreppe, Aufzug, Treppe), `game_state` `view_floor`/`set_view_floor`, Ebene -1 = Untergeschoss (Tunnel, Förderband, Keller). Bauformen über `game_state.OPTIONS` (`cycle_option`), Factory bekommt sie als Meta "opts".
- Unter der Erde: Linientypen mit `"underground": true` ("tunnel" mit Höhenprofil `Catalog.tunnel_profile`, "foerderband" auf -4,2 m). `Catalog.covered()` sagt, welche Stützpunkte Bauen darüber erlauben. Offene Rampen schneiden Löcher in den Rasen (`game.tunnel_cuts`, ground.gdshader `cut_a/cut_b`).
- Wegebau: Zeichenarten in `builder.gd` (`draw_mode` gerade/kurve/frei, `curve_points`, `_arc`, `_hermite`, `_snap_dir`, `_snap_arc`), Stützpunkte über `GameState.line_samples`.
- Möbel und Landschaft: `furniture.gd` und `landscape.gd` (fein aus `mesh_kit.gd`), Bewegung über `deco_anim.gd` (Knotennamen Zeiger_*, Dreh*, Wipp*, Hub*, Blink*) und `belt_anim.gd` (MultiMesh entlang eines Pfads: Koffer, Fische, Enten, Rollsteig).
- Landseite in `traffic.gd`: Linienbusse (`_bus_tick`, Haltestelle "haltestelle"), Fußgänger `peds`, Parkplatz "parkplatz" wie Parkhaus.
- Shader: `kit.gdshader` (Vertexfarbe; Alpha 0.6 Fenster, 0.3 Lampe, 0.8 Laub wiegt sich), `lamp`, `halo`, `ground` (Wiese, Kartenrand, Tunnellöcher), `line` (Wege, Markierungen, mark 9 Förderband), `screen` (Werbebildschirme). Kompatibilitäts-Renderer rechnet in sRGB (`CURRENT_RENDERER`).

## Version und Updates
- `version.txt`: erste Zeile Spielversion, zweite Zeile Godot-Version.
- Jeder Push auf `main` baut per GitHub Actions die Windows-Version. Ist die Version in `version.txt` neu, entsteht automatisch ein Release `vX.Y.Z` mit `PixelApron-Windows.zip`, `PixelApron.pck` und `version.txt`.
- Das Spiel (`scripts/updater.gd`) prüft beim Start `releases/latest/download/version.txt`, lädt `PixelApron.pck` nach `user://update` und `scripts/boot.gd` lädt es beim nächsten Start.
- Für ein Update also: Änderung machen, Selbsttest, `version.txt` erhöhen, auf `main` pushen.
- `scripts/boot.gd` möglichst nicht ändern (es läuft immer aus der installierten Version). Projekteinstellungen und Godot-Version ändern sich nur mit einem kompletten Download.
