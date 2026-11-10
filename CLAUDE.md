# PixelApron

Flughafen-Aufbauspiel in Godot 4.7 (GDScript), isometrischer Pixel-Look. Sprache im Spiel und im Code: Deutsch.

## Arbeiten am Projekt
- Selbsttest: `godot --headless --path . -- --selftest` muss mit `SELFTEST BESTANDEN` enden.
- Vorschaubilder: `--demo --mode=bauen|leitungen|abfertigung|terminal|halle|kreuzung|verkehr|ampel|parkhaus|tower|hangar|feuerwache|modelle|modelle_nah|modelle_a320|modelle_b737|menu|einstellungen --shot=PFAD` (mit Fenster/xvfb).
- Detailmodelle (Flugzeuge, Menschen, Autos, Bodenfahrzeuge) entstehen in `scripts/models.gd` mit dem Baukasten `scripts/mesh_kit.gd` als ein Mesh mit Vertexfarben. Dreiecke im Uhrzeigersinn von außen = Vorderseite.
- Wegebau-Regeln (Kreuzungen, Kollisionen) stehen in `game_state.gd` (`check_line`, `CROSS_OK`), Einrasten in `builder.gd` (`_snap_line`).
- Straßennetz in `roads.gd` (Knoten, Spurgeometrie, Kreuzungsflächen, Schilder, Ampelphasen, `cycle_control`), Verkehr in `traffic.gd` (Legs: lane/conn/change/drive, Vorfahrt, Ziele Parkhaus und Terminal-Haltebucht). `traffic.step(dt)` lässt sich im Test direkt aufrufen.
- Sicherheitsbereich: `terminal.gd` `_security_problems` (Flutfüllung auf zwei Rastern: "dep" mit gesperrtem Einbahn-Ausgang, "arr" mit gesperrter Kontrolle).
- Neue Bauteile stehen als Daten in `scripts/catalog.gd`, ihre Form in `scripts/factory.gd`. `Factory.bake()` fasst einfarbige Teile zu einem Mesh zusammen; Knoten mit Meta `no_bake` (z. B. animierte Koffer) und benannte Gruppen bleiben einzeln.
- Flugzeuge: bewegliche Teile (Fahrwerk, FanL/FanR, Beacon, Strobe) animiert `flights.gd` `_animate`. Fluggastbrücken in `terminal.gd` (`_rebuild_bridges`, `_move_bridges`).

## Version und Updates
- `version.txt`: erste Zeile Spielversion, zweite Zeile Godot-Version.
- Jeder Push auf `main` baut per GitHub Actions die Windows-Version. Ist die Version in `version.txt` neu, entsteht automatisch ein Release `vX.Y.Z` mit `PixelApron-Windows.zip`, `PixelApron.pck` und `version.txt`.
- Das Spiel (`scripts/updater.gd`) prüft beim Start `releases/latest/download/version.txt`, lädt `PixelApron.pck` nach `user://update` und `scripts/boot.gd` lädt es beim nächsten Start.
- Für ein Update also: Änderung machen, Selbsttest, `version.txt` erhöhen, auf `main` pushen.
- `scripts/boot.gd` möglichst nicht ändern (es läuft immer aus der installierten Version). Projekteinstellungen und Godot-Version ändern sich nur mit einem kompletten Download.
