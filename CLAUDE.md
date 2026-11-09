# PixelApron

Flughafen-Aufbauspiel in Godot 4.7 (GDScript), isometrischer Pixel-Look. Sprache im Spiel und im Code: Deutsch.

## Arbeiten am Projekt
- Selbsttest: `godot --headless --path . -- --selftest` muss mit `SELFTEST BESTANDEN` enden.
- Vorschaubilder: `--demo --mode=bauen|leitungen|abfertigung|terminal|halle|menu|einstellungen --shot=PFAD` (mit Fenster/xvfb).
- Neue Bauteile stehen als Daten in `scripts/catalog.gd`, ihre Form in `scripts/factory.gd`.

## Version und Updates
- `version.txt`: erste Zeile Spielversion, zweite Zeile Godot-Version.
- Jeder Push auf `main` baut per GitHub Actions die Windows-Version. Ist die Version in `version.txt` neu, entsteht automatisch ein Release `vX.Y.Z` mit `PixelApron-Windows.zip`, `PixelApron.pck` und `version.txt`.
- Das Spiel (`scripts/updater.gd`) prüft beim Start `releases/latest/download/version.txt`, lädt `PixelApron.pck` nach `user://update` und `scripts/boot.gd` lädt es beim nächsten Start.
- Für ein Update also: Änderung machen, Selbsttest, `version.txt` erhöhen, auf `main` pushen.
- `scripts/boot.gd` möglichst nicht ändern (es läuft immer aus der installierten Version). Projekteinstellungen und Godot-Version ändern sich nur mit einem kompletten Download.
