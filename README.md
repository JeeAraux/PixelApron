# PixelApron

Flughafen-Aufbauspiel im isometrischen Pixel-Look, gebaut mit Godot 4.

## Spielen unter Windows

1. Unter **[Releases](https://github.com/JeeAraux/PixelApron/releases/latest)** `PixelApron-Windows.zip` herunterladen und entpacken.
2. `PixelApron.exe` starten. Bei der Windows-Warnung auf *Weitere Informationen* und dann *Trotzdem ausführen* klicken.
3. **Updates kommen automatisch:**
   - Beim Start sucht das Spiel nach einer neuen Version und lädt sie im Hintergrund (meist unter 1 MB).
   - Ist sie fertig geladen, erscheint ein Hinweis. Im Menü (Esc) kannst du dann *Update aktivieren: Neustart* wählen, sonst ist es beim nächsten Start aktiv.
   - Dein Spielstand bleibt erhalten.
   - Nur wenn sich die Godot-Version ändert, musst du die ZIP einmal neu herunterladen. Das Spiel sagt dir dann Bescheid.

Spielstände und Einstellungen liegen unter `%APPDATA%\Godot\app_userdata\PixelApron`.

## Neue Version veröffentlichen

`version.txt` erhöhen (z. B. `0.4.1`) und auf `main` pushen. GitHub Actions testet, baut die Windows-Version und erstellt das Release. Die installierten Spiele holen es sich selbst.

---

Erster spielbarer Prototyp für das Flughafen-Aufbauspiel in Godot 4. Du baust selbst, und der Flughafen läuft:

- **Wege mit Kurven:**
  - Straße, Gehweg, Rollweg und Vorfeld ziehst du durch beliebig viele Punkte. Die Ecken werden automatisch ausgerundet.
  - Die Piste baust du gerade mit zwei Klicks.
  - Jeder Wegtyp hat einen Mindestradius, ein Rollweg zum Beispiel 30 m.
- **Flugbetrieb:**
  - Flüge kommen nach Plan, landen und rollen über dein Rollnetz zu einem freien Stand. Dort werden sie abgefertigt, dann rollen sie zur Piste und starten.
  - Die Piste nutzt immer nur ein Flugzeug, die anderen warten davor.
  - Ab 1.200 m Pistenlänge kommen ATR 72, ab 1.800 m auch Airbus A320.
  - Landungen und Abflüge bringen Geld. Rechts siehst du den Flugplan.
  - Rollende Flugzeuge reservieren den Rollweg vor sich (70 m). Ist er belegt, warten sie oder suchen einen anderen Weg.
- **Bodenabfertigung (neu in v3):**
  - Am Stand fahren Tankwagen, Gepäckwagen und Catering ans Flugzeug und danach wieder weg.
  - Mit einem Vorfelddepot mit Strom geht die Abfertigung schneller. Ohne Depot dauert sie 50 % länger.
- **Zufriedenheit und Geld (neu in v3):**
  - Oben siehst du die Zufriedenheit. Fährst du mit der Maus darüber, zeigt sie, was sie hebt oder senkt: wartende Flugzeuge, Depot, Parkhaus, Versorgung und Bäume, Kübel und Bänke am Terminal.
  - Hohe Zufriedenheit bringt mehr Flüge und höhere Ticketpreise.
  - Jedes Bauwerk kostet Unterhalt. Um Mitternacht kommt die Tagesbilanz.
- **Info (neu in v3):** Ohne Werkzeug klickst du auf ein Flugzeug, Gebäude oder einen Weg und siehst Details, Versorgung und Unterhalt.
- **Strom und Wasser:**
  - Du verlegst Kabel und Rohre selbst, von der Trafostation und vom Wasseranschluss zu den Gebäuden.
  - Ein Trafo liefert 630 kW. Hängen zu viele Gebäude daran, ist das Netz überlastet.
  - Ohne Strom im Tower oder ohne Strom und Wasser im Terminal kommen keine neuen Flüge.
  - Gebäude ohne Versorgung zeigen eine rote Warnung. Die Leitungsansicht (L) dunkelt die Welt ab und lässt die Leitungen leuchten.
- **Terminal selbst bauen (neu in v4):** siehe Abschnitt „Terminal bauen“ unten.
- **Gebäude und Deko:** Stand, Tower, Vorfelddepot, Hangar, Feuerwache, Parkhaus, Trafostation, Wasseranschluss und Heizzentrale. Dazu Baum, Blumenkübel, Laterne und Bank.
- **Bauen:**
  - Gebäude liegen auf einem Raster und lassen sich drehen. Sie dürfen sich nicht überlappen und nicht auf Wegen stehen.
  - Stände müssen auf dem Vorfeld liegen.
  - Beim Abriss bekommst du die Hälfte der Kosten zurück, mit Rückgängig alles.
- **Zeit:** Mit Pause, 1×, 2× und 3× stellst du das Tempo ein.
- **Verkehr:**
  - Autos fahren rechts, halten Abstand und biegen an verbundenen Straßen ab.
  - Je mehr Landungen und Starts in der letzten Stunde, desto mehr Autos kommen an offenen Straßenenden herein.
- **Menü (Esc, neu in v4):** Weiterspielen, Speichern, Laden, Neue Karte, Einstellungen und Beenden. Solange das Menü offen ist, steht das Spiel still.
- **Einstellungen:** Vollbild, Schatten, Kamera-Tempo, Mausrad umkehren, Scrollen am Bildrand, Bauraster immer zeigen, automatisch um Mitternacht speichern, Tastenhilfe. Sie bleiben gespeichert.
- **Speichern und Laden:** über das Menü, oder F5 speichert und F9 lädt. Spielstände aus v3 enthalten noch das alte Fertig-Terminal und laden ohne Terminal.

## Terminal bauen

1. **Halle aufziehen:** Reiter *Terminal* → *Terminalhalle*. Klicke eine Ecke, dann die gegenüberliegende Ecke. Die Halle kostet 1.400 € pro m². Die Innenansicht schaltet sich dabei ein, das Dach verschwindet. Mit **I** oder dem Knopf *Innenansicht* schaltest du sie selbst um.
2. **Anschließen:** Die Halle braucht Strom (Stromkabel vom Trafo). Für Toiletten und Café braucht sie Wasser (Wasserrohr), für Heizkörper Wärme (**Heizrohr** von der Heizzentrale). Was in der Halle steht, hängt an ihrem Anschluss.
3. **Einrichten:** Pflicht sind
   - ein **Eingang** an der Außenwand,
   - ein **Check-in** und eine **Gepäcksortierung**,
   - eine **Sicherheitskontrolle**, durch die die Passagiere von vorn nach hinten gehen,
   - ein **Gate** an der Außenwand zum Vorfeld, am besten eins je Stand,
   - ein **Gepäckband**.

   Fehlt etwas, kommen keine Flüge. Der Flugplan zeigt, was fehlt.
4. **Wände:** Innenwand und Glaswand ziehst du mit zwei Klicks innerhalb der Halle. Passagiere laufen außen herum.
5. **Ausstattung:** Toiletten, Heizkörper (je 250 m²), Café und Shop bringen Geld je Passagier. Sitzreihen, Pflanzen, Anzeigetafeln und Kunst heben die Zufriedenheit.

Passagiere sind als kleine Figuren zu sehen. Eine Figur steht für acht Passagiere.
- **Abflug:** Sie kommen durch den Eingang, gehen zum Check-in und durch die Kontrolle. Manche machen einen Abstecher zu Shop, Café oder WC. Dann warten sie am Gate und steigen ein, wenn das Flugzeug losrollt.
- **Ankunft:** Sie steigen am Gate aus, holen ihre Koffer am Gepäckband und gehen hinaus.

**Kapazität pro Stunde:**

| Teil | Passagiere pro Stunde |
|---|---|
| Check-in | 80 |
| Kontrolle | 150 |
| Gepäckband | 300 |
| Toiletten | 250 |

Kommen mehr Passagiere, entstehen Warteschlangen: Die Abfertigung dauert länger und die Zufriedenheit sinkt. Klickst du ohne Werkzeug auf die Halle, siehst du Auslastung, Wärme und was fehlt.

## Starten

1. Lade **Godot 4.7** (Standard-Version, nicht .NET) von https://godotengine.org/download herunter und entpacke es. Eine Installation ist nicht nötig.
2. Starte Godot und wähle **Importieren**. Wähle dort die Datei `project.godot` aus diesem Ordner.
3. Drücke **F5** oder den Play-Knopf oben rechts.

Beim ersten Öffnen legt Godot den Ordner `.godot/` an. Den musst du nicht sichern.

## Steuerung

| Taste | Wirkung |
|---|---|
| Linksklick | Punkt setzen, Gebäude setzen, abreißen. Ohne Werkzeug: Details ansehen |
| Rechtsklick oder Enter | Weg fertigstellen, ohne Weg: Werkzeug abwählen |
| Esc | Laufenden Weg abbrechen, sonst Menü öffnen. Im Menü: zurück oder schließen |
| I | Innenansicht an/aus (Dächer weg) |
| R | Gebäude um 90 Grad drehen |
| L | Leitungsansicht an/aus |
| Leertaste, 1, 2, 3 | Pause, Tempo 1×, 2×, 3× |
| Entf | Abriss-Werkzeug |
| Strg+Z | Rückgängig |
| WASD, Pfeiltasten oder mittlere Maustaste ziehen | Karte verschieben |
| Mausrad | Zoom |
| Q / E | Ansicht um 90 Grad drehen |
| F5 / F9 | Speichern / Laden |

## Aufbau

| Datei | Aufgabe |
|---|---|
| `scripts/main.gd` | Setzt alles zusammen, verteilt Eingaben |
| `scripts/catalog.gd` | **Alle Teile und Regeln als Daten:** Preise, Größen, Radius, Strom- und Wasserbedarf, Flugzeugtypen |
| `scripts/factory.gd` | Formen der Gebäude, Flugzeuge, Autos und Wege |
| `scripts/builder.gd` | Bauwerkzeug mit Vorschau, Raster, Einrasten, Prüfungen |
| `scripts/game_state.gd` | Geld, Zeit, gebaute Teile, Strom- und Wassernetz, Rückgängig, Speichern, Startflughafen |
| `scripts/airside.gd` | Rollnetz als Graph und Wegsuche (A*) |
| `scripts/flights.gd` | Flugplan, Landung, Rollen, Abfertigung, Start, Pistenbelegung |
| `scripts/terminal.gd` | Terminalbetrieb: Pflichtteile, Kapazität, Wärme, Gates, Passagiere mit Wegsuche |
| `scripts/settings.gd` | Einstellungen, gespeichert in `user://einstellungen.cfg` |
| `scripts/traffic.gd` | Autos auf Straßen |
| `scripts/spline.gd` | Kurven, Radius, Wege-Mesh |
| `scripts/iso_camera.gd` | Iso-Kamera, rastet auf Bildpixel ein |
| `scripts/hud.gd` | Oberfläche: Kopfzeile, Flugplan, Baumenü, Spielmenü und Einstellungen |
| `scripts/thumbs.gd` | Vorschaubilder für das Baumenü |
| `shaders/` | Wiese und Markierungen |
| `tests/selftest.gd` | Automatischer Test: Bauen, Flüge, Strom, Wasser, Speichern |

## Ein neues Teil hinzufügen

Beispiel: ein WC-Häuschen.

1. Trage es in `catalog.gd` unter `ITEMS` ein, zum Beispiel:
   ```
   "wc": {"name": "WC-Haus", "size": Vector2(6, 4), "cost": 40000, "grid": 1.0},
   ```
   Mit `"needs": {"strom": 5, "wasser": 2}` braucht es Strom und Wasser. Hänge danach `"wc"` in `CATEGORIES` an eine Kategorie.
2. Ergänze in `factory.gd` in `make_item` einen Fall `"wc":` mit ein paar Blöcken.

Die Karte mit Vorschaubild erscheint dann von selbst im Baumenü.

## Selbsttest

```
godot --headless --path . -- --selftest
```

Der Test baut Wege, Gebäude und eine Terminalhalle mit Einrichtung und Wänden. Er lässt Flüge landen, abfertigen und starten und prüft, ob Passagiere zum Gate und zum Gepäckband laufen. Außerdem nimmt er der Halle Wärme und Kontrolle weg. Er prüft den Abstand rollender Flugzeuge, die Bodenfahrzeuge, das Depot, den Unterhalt um Mitternacht und ob mehr Flüge mehr Autos bringen. Außerdem nimmt er dem Terminal den Strom, überlastet den Trafo und prüft Abriss, Rückgängig sowie Speichern und Laden. Am Ende steht `SELFTEST BESTANDEN`.

## Als Windows-Programm exportieren

Gehe auf **Projekt › Exportieren › Hinzufügen › Windows Desktop**. Beim ersten Mal lädt Godot die Exportvorlagen herunter. Danach erzeugt **Projekt exportieren** eine .exe.

## Nächste Schritte

1. Mehrere Etagen im Terminal, Rolltreppen und Fluggastbrücken vom Gate zum Flugzeug.
2. Passagiere kommen sichtbar mit Auto, Bus und Bahn zum Eingang.
3. Personal und Löhne: Check-in, Kontrolle und Reinigung brauchen Mitarbeiter.
4. Mehrere Pisten und Rollhaltepunkte mit Freigabe durch den Tower.
5. Eigene Modelle aus Blender statt der Grundkörper in `factory.gd`.
