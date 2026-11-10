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

- **Update 0.14: Neue Bauleiste und Wegebau wie in Städtebauspielen**
  - **Bauleiste:** Dock mit Kategorie-Bildern, zuletzt benutzten Bauteilen, Blaupause, Zurück und Abriss. Darüber die Ablage mit Abschnitten als Sprungmarken, Suche über alle Bauteile (Strg+F) und einem Streifen, der waagrecht blättert (Mausrad, Pfeile) und nie über den Bildschirmrand ragt. Die Kopfzeile verdichtet sich bei kleinen Fenstern.
  - **Wegebau-Leiste:** Gerade, Kurve, Freihand und Ersetzen, Einrasten an/aus (G) und immer der nächste Schritt im Klartext.
  - **Ersetzen:** Bestehende Straße oder Rollweg anklicken und an Ort und Stelle umbauen (2-spurig, 4-spurig, Einbahn, Rollweg schmal/breit), Einbahnstraßen drehen. Kreuzungen und Anschlüsse bleiben.
- **Update 0.13: Wetter, Fracht, Verträge, Lotsenmodus und vieles mehr**
  - **Wetter:** Regen, Nebel und Schnee mit Winterdienst (Räumkonvoi auf der Piste, Enteisung vor dem Start); nachts Scheinwerferkegel von Autos, Bodenfahrzeugen und Flugzeugen, Lichtfelder unter den Flutlichtmasten.
  - **Flugbetrieb:** Bei mehreren Pisten wird nach dem Wind auf eine zum Landen und eine zum Starten verteilt. Frachtterminal mit Frachtflügen (777F und Frachtversionen), Wartungschecks im Hangar, Flugplan mit geplanten Zeiten und Verspätungen, Lotsenmodus mit Freigaben per Knopf.
  - **Neue Flugzeuge:** Airbus A350-900, Boeing 787-9, Bombardier CRJ900 und Boeing 777F, jede Airline mit eigener Lackierung.
  - **Terminal:** Airline-Lounge und Fast-Lane, Gepäckermittlung und Gepäckdurchleuchtung, Hunger als Bedürfnis.
  - **Landseite:** S-Bahnhof mit einfahrenden Zügen, Taxistand, Kiss & Fly und Mietwagenzentrum.
  - **Betrieb (F2):** Statistik mit Pünktlichkeit, Einnahmen nach Bereich und Engpässen, Airline-Verträge mit Prämien, Szenarien (Drehkreuz, Winterchaos, Frachtdrehkreuz) und Lernschritte für Einsteiger.
  - **Blaupause:** Bereiche samt Terminalmodulen kopieren und einfügen.
- **Update 0.12: Fahrzeuge und Flugzeuge von Grund auf neu**
  - **Flugzeuge nach Vorbild:** Rumpf mit echtem Nasen- und Heckprofil, Cockpitscheiben, Türen und Fensterreihe, Flügel mit Profil und Sharklets, gepfeiltes Leitwerk, Triebwerke mit Einlauflippe und Fan, Fahrwerk mit Felgen und Federbein, Airline-Schriftzug.
  - **Autos nach Vorbild** (Kompaktwagen, Limousine, Kombi, SUV, Transporter, Taxi): glatte Karosserie mit Motorhaube, geneigten Scheiben, Säulen, Türfugen, Scheinwerfern, Rückleuchten, Spiegeln und Felgen.
  - **Busse und Bodenfahrzeuge neu:** Linienbus und Vorfeldbus mit Panoramascheiben, Lkw-Fahrerhäuser, Tankwagen mit Laufsteg, Pushback-Schlepper, Gepäckschlepper, Bandlader, Treppenwagen und Flugfeldlöschfahrzeug mit Panoramakabine.
- **Update 0.11: Rolllinien selbst zeichnen, runde Modelle**
  - **Rollführungslinien:** Die gelben Linien auf Vorfeld und Rollwegen zeichnest du selbst (Wege → Rollführungslinie). Wo Linien liegen, rollen die Flugzeuge nur noch auf ihnen; Stände schließen an die nächste Linie an.
  - **Außenpositionen:** Passagiere gehen die Treppe hinunter, steigen durch die geöffneten Türen in den Bus und fahren darin mit; am Terminal steigen sie wieder aus (beim Abflug umgekehrt).
  - **Gepäckwagen** hängen sauber mit Deichsel hintereinander statt ineinander.
  - **Runder statt kantig:** Fahrzeuge mit abgerundeten Kanten, Karosserien von Autos und Bussen weich geformt, Flügel und Leitwerke mit runder Vorderkante.
- **Update 0.10: Anschlüsse, Befeuerung, Gepäcksortierung und flüssigere Bewegung**
  - **Brücken und Eingänge sitzen richtig:** Fluggastbrücken rasten bündig an der Fassade auf Höhe des Gates ein, ein gläserner Treppenturm mit Aufzug führt hinunter zum Gate. Eingänge und Brücken öffnen die Außenwand mit Laibung und Sturz.
  - **Stände mit Zufahrt:** Die Betriebsstraße läuft am Kopf der Stände entlang, die Infoanzeige zeigt, ob ein Stand angeschlossen ist. Straßen dürfen nicht mehr über Stände gehen, Fahrzeuge weichen stehenden Fahrzeugen aus statt durch sie hindurchzufahren.
  - **Rollhalteorte und Befeuerung selbst bauen:** Rollhalteort (Markierung, Haltebalken, Warnlichter, Schilder) rastet auf dem Rollweg ein, Anflugbefeuerung und PAPI am Pistenende. Die Pistenfeuer leuchten mit einer Befeuerungsstation am Stromnetz. Ohne Befeuerung wird nachts nicht geflogen.
  - **Flugzeuge:** Höchstens 90° je Abbiegung, kein Wenden auf der Stelle, kein Rückwärtsrollen außer beim Pushback. Landeklappen fahren aus, Spoiler stellen sich beim Aufsetzen auf, Landescheinwerfer leuchten.
  - **Gepäck:** Gepäckzüge bringen die Koffer zur Sortierung im Gepäckumschlag und holen dort die Koffer für den Abflug ab. Gepäckbänder lassen sich einem Gate zuordnen. Ankommende warten am Band, bis ihre Koffer da sind.
  - **Menschen und Fahrzeuge:** Menschen mit Gelenken, acht Gangphasen und geglätteten Wegen statt Zickzack. Bustüren schwenken auf, Fahrzeuge nicken beim Bremsen und neigen sich in Kurven, schönere Fahrerhäuser und Gepäckwagen mit Dach.
  - **Straßenbau:** Kreuzungen mit gerundeten Bordsteinen und Randlinien, spitze Einmündungen überlappen nicht mehr. Neue Straßen richten sich parallel oder rechtwinklig nach der nächsten Straße aus.
- **Großes Update 0.9: Alles selbst bauen, Fahrzeuge aus der Garage**
  - **Terminal wirklich selbst bauen:** Türen (Automatik, Flügeltür, Personaltür mit Kartenleser) setzt du in Innenwände, sie gehen auf, wenn jemand kommt. Bereiche ziehst du als Bodenfläche auf: öffentlich, Sicherheitsbereich, Personal. Gates müssen im Sicherheitsbereich liegen, Läden dort verdienen mehr, in den Personalbereich kommen nur Mitarbeiter. Personalraum für die Pausen.
  - **Personal:** Personalgebäude mit Platz für 160 Mitarbeiter, Schichtwechsel mit Leuten auf dem Weg zum Terminal. Mitarbeiter gehen durch Personaltüren an ihre Schalter, eine Reinigungskraft schiebt ihren Wagen durch die Halle. Zu wenig Personal verlängert die Abfertigung.
  - **Garagen und Betriebsstraße:** Gerätehalle mit vier Rolltoren, Tanklager mit Tanks, Füllstation und Wagenhalle, Busgarage mit Waschanlage, Cateringbetrieb mit Laderampe. Die Fahrzeuge fahren schon beim Anflug los: Rolltor auf, über die Betriebsstraße zum Stand, danach zurück in die Garage. Kerosin und Bordessen bringen Geld.
  - **Feuerwehr:** Rolltore öffnen sich, bevor ein Löschfahrzeug ausrückt: Kontrollfahrten zum Rollhalt und Bereitschaft an der Piste, wenn ein Flugzeug ein Problem meldet.
  - **Rollverkehr:** Wer vorne rollt, hat Vorrang. Dadurch blockieren sich ein Abflug und eine Ankunft, die hintereinander auf demselben Rollweg fahren, nicht mehr gegenseitig.
  - **Maßstab:** Das Startterminal ist jetzt 250 × 40 m groß mit vier Brücken, sechs Gates, drei Kontrollspuren und Vordach; Hallen bis 400 × 200 m. Feinere Fassade, Wände mit Sockelleisten und Glaswände mit Sicherheitsmarkierung.
- **Feinschliff 0.8.1:** Alle älteren Bauten im feinen Stil neu gebaut. Hangar mit Bogendach, Faltschiebetor und einer ATR 72 in der Wartung, Tower mit durchsichtiger Kanzel, Lotsen an den Pulten und drehendem Radar, Feuerwache mit offenen Toren, Löschfahrzeugen, Sirene, Solardach und wehender Fahne, Parkhaus mit Rampen, geparkten Autos auf jeder Ebene, begrünter Fassade, gläsernem Treppenhaus und Solardach. Check-in, Sicherheitskontrolle, Gates, Gepäckband, Café und Shops mit vielen Details (Drehtür oder Schiebetür, Gepäckkarussell, Café, Bäckerei, Bar oder Restaurant), Abflugtafeln und Gate-Anzeigen. Trafostation, Heizzentrale mit Rauch, Wasseranschluss und Vorfelddepot neu. Rollverkehr noch sicherer beim Pushback.
- **Großes Update 0.8:**
  - **Wegebau wie im Städtebauspiel:** Drei Zeichenarten (Tab wechselt): *Gerade* setzt am Ende automatisch fort, *Kurve* läuft am Ende einer Straße tangential als Kreisbogen weiter, *Freihand* wie bisher. Winkel rasten weich auf 15-Grad-Stufen zur angeschlossenen Straße ein (Shift: frei). Die Vorschau zeigt den echten Belag, ein Schild am Mauszeiger zeigt Länge, Radius und Winkel.
  - **Unter der Erde:** Straßentunnel mit Rampen, Portalen und beleuchteter Röhre (darüber darf gebaut werden, auch Pisten). Gepäckförderband im Tunnel vom Terminal zum neuen *Gepäckumschlag*, die Koffer laufen sichtbar. Ansicht *Untergeschoss* mit ▼ oder Bild ab.
  - **Stockwerke und Bauformen:** Terminalhallen mit bis zu drei Ebenen, Keller, Rolltreppen, Aufzügen und Treppen, verschiedenen Fassaden, Dächern und runden Formen. Parkhäuser mit 2 bis 6 Etagen.
  - **Grenzkontrolle:** Passkontrolle trennt Schengen- und Non-Schengen-Flüge, Zoll für Ankünfte.
  - **Abfertigung nach Vorbild:** Je Flugzeugtyp eigene Positionen: Bodenstrom an der Nase, Förderbandwagen an beiden Frachttoren (das Band hebt sich, Koffer laufen hinauf oder hinunter), Gepäckzüge mit drei Wagen, die sich füllen und leeren, Catering mit Scherenhub an Tür R2, Tankwagen mit Schlauch vor der rechten Tragfläche, Pylonen und Unterlegkeile. Die Fahrzeuge fahren über eigene Wege an und weichen einander und rollenden Flugzeugen aus.
  - **Flugzeuge weichen einander aus:** Rollwegabschnitte werden blockweise freigegeben, bei Gegenverkehr wartet der, der weiter weg ist; Pushback erst, wenn niemand entgegenkommt. Neue Typen (ATR 72, Embraer 190, A321, A330) mit feineren Nasen, Starts und Landungen mit Anflugkurven, Betrieb nach Windrichtung.
  - **Landseite:** Linienbusse mit Haltestelle, Fahrgäste gehen zu Fuß zum Terminal und warten unter dem Dach, Autofahrer laufen vom Parkhaus oder der Vorfahrt zum Eingang. Ebenerdiger Parkplatz, Sicherheitszaun.
  - **24 neue Möbel, viele bewegt:** Bahnhofsuhr mit laufenden Zeigern, Aquarium mit Fischschwärmen, Springbrunnen, Rollsteig, Werbestelen mit wechselnden Motiven, Kinderspielecke mit Schaukelpferd, hängendes Flugzeugmodell, Lounge, Kiosk, Info-Schalter, Automaten, Ladesäule, Flügel und mehr.
  - **Landschaft:** Büsche, Hecken, Blumenbeete, Teich mit Enten, Felsen, Picknicktische, feinere Laternen, Bänke und Kübel. Hellere Wiese mit Blumen, Wolkenschatten, Tag und Nacht mit weichen Lichtern.

- **Details (neu in 0.7):**
  - **Flugzeuge:** Die Fans drehen sich, das Fahrwerk fährt nach dem Start ein und vor der Landung aus. Beacon und Blitzlichter blinken. Dazu kommen genauere Cockpitscheiben, Frachttüren, Querruder, Spoiler, Höhen- und Seitenruder sowie ein Airline-Schriftzug.
  - **Fluggastbrücken:** Jedes Gate hat eine Brücke an der Außenwand. Sie fährt zum Flugzeug aus, dockt an der vorderen Tür an und fährt nach dem Boarding wieder ein (Reichweite etwa 36 m).
  - **Menschen:** Schultern, Jacken, Röcke, fünf Frisuren, Mützen, Rucksäcke und Rollkoffer, auch Kinder. Sie bewegen sich mit einem Gangzyklus in vier Phasen und setzen sich am Gate auf die Sitze. Auf dem Vorfeld stehen Einweiser und Lader in Warnwesten.
  - **Terminal:** Check-in mit Monitoren und Wartegassen im Zickzack, Kontrolle mit Körperscanner, Rollenbahn und Wannen, Boarding-Schleusen am Gate. Die Koffer laufen auf dem Gepäckband um.
  - **Gebäude:** Tower mit Galerie, Geländer, Radarkuppel und Antennen. Hangar mit Tonnendach, Falttor und Werkstatt. Feuerwache mit Toren, Schlauchturm und zwei Flugfeldlöschfahrzeugen. Trafostation mit Transformatoren und Zaun. Heizzentrale mit Schornsteinleiter und Lüftern. Schriftzug TERMINAL auf der Halle.
  - **Leistung:** Jedes Gebäude wird zu einem einzigen Mesh zusammengefasst. So bleiben viele Details flüssig.
- **Straßennetz (neu in 0.6):**
  - **Straßentypen:** 2-spurig, 4-spurig (zwei Spuren je Richtung) und Einbahnstraße. Mit dem Werkzeug *Spuren ändern* klickst du eine Straße durch alle Typen, auch die Richtung der Einbahnstraße.
  - **Kreuzungen:** Sie bekommen eine eigene Fläche, Haltelinien und Schilder.
  - **Regelung:** Mit *Kreuzung regeln* schaltest du zwischen rechts vor links, Vorfahrtsstraße (Vorfahrt-achten-Linien für die Nebenstraße) und Ampel mit Phasen um. Kreuzungen 4-spuriger Straßen bekommen automatisch eine Ampel.
  - **Autos:** Sie fahren auf ihrer Spur und durch Kreuzungen auf sauberen Kurvenbögen. Sie wechseln die Spur vor dem Abbiegen und halten Abstand. Sie bremsen an der Haltelinie, warten auf Grün oder auf Vorfahrt, und Linksabbieger lassen den Gegenverkehr durch. Blinker und Bremslichter leuchten.
  - **Ziele:** Autos fahren ins Parkhaus, durch die Einfahrt mit Schranke, parken und kommen später über die Ausfahrt wieder heraus (Parkgebühr). Andere halten in einer Haltebucht vor dem Terminal oder fahren einfach durch.
  - **Parkhaus:** Ein- und Ausfahrt liegen an der Vorderseite, davor muss eine Straße liegen. Die Infoanzeige zeigt die Zufahrt und die belegten Plätze.
- **Sicherheitsbereich (neu in 0.6):**
  - Hinter die Kontrolle darf niemand ohne Kontrolle. Das Spiel prüft, ob die Gates vom Eingang nur durch die Sicherheitskontrolle erreichbar sind.
  - Ankommende verlassen den Bereich über einen *Ausgang Sicherheitsbereich*, eine Einbahn-Tür in der Trennwand.
  - Fehlt etwas oder ist eine Lücke offen, sagt der Flugplan, was zu tun ist.
- **Wege mit Kurven:**
  - Straße, Gehweg, Rollweg und Vorfeld ziehst du durch beliebig viele Punkte. Die Ecken werden automatisch ausgerundet.
  - Die Piste baust du gerade mit zwei Klicks.
  - Jeder Wegtyp hat einen Mindestradius, ein Rollweg zum Beispiel 30 m.
  - **Einrasten (neu in 0.5):** Wege rasten an Wegenden und irgendwo auf passenden Wegen ein. Klickst du beim Bauen auf einen Weg, schließt der neue Weg dort an und ist sofort fertig. Ohne Ziel rastet die Richtung in 15-Grad-Schritten ein, mit Shift ist sie frei.
  - **Kreuzungen:** Kreuzt eine Straße eine andere, werden beide dort geteilt und verbunden. Autos biegen dort ab.
  - **Nichts mehr übereinander:** Wege können nicht durch Gebäude gehen, und Straßen nicht über Rollwege, Vorfeld oder Piste. Eine Straße kann nicht auf einer anderen liegen. Bäume, Kübel, Laternen und Bänke im Weg räumt das Spiel automatisch weg.
- **Flugbetrieb:**
  - Flüge kommen nach Plan, landen und rollen über dein Rollnetz zu einem freien Stand. Dort werden sie abgefertigt, dann rollen sie zur Piste und starten.
  - Die Piste nutzt immer nur ein Flugzeug, die anderen warten davor.
  - Ab 1.700 m Pistenlänge kommen Airbus A320 und Boeing 737-800. Beide sind detailliert nachgebaut, mit Fenstern, Türen, Triebwerken, Fahrwerk, Winglets und Lichtern.
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
- **Details (neu in 0.5):** Menschen mit Laufbewegung, Haaren und Gepäck. Autos fahren als Kleinwagen, Limousine, Kombi, SUV, Transporter und Taxi. Dazu Tankwagen, Catering-Hubwagen und Gepäckschlepper mit Wagen.
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
| Tab | Zeichenart beim Wegebau wechseln (Gerade, Kurve, Freihand, Ersetzen) |
| G | Einrasten von Winkel und Länge an/aus (Shift kehrt es kurz um) |
| B | Ablage der Bauleiste ein-/ausklappen |
| Alt+1 … Alt+7 | Kategorie der Bauleiste öffnen |
| Strg+F | Bauteil suchen, Enter wählt den ersten Treffer |

## Aufbau

| Datei | Aufgabe |
|---|---|
| `scripts/main.gd` | Setzt alles zusammen, verteilt Eingaben |
| `scripts/catalog.gd` | **Alle Teile und Regeln als Daten:** Preise, Größen, Radius, Strom- und Wasserbedarf, Flugzeugtypen |
| `scripts/factory.gd` | Formen der Gebäude, Flugzeuge, Autos und Wege |
| `scripts/interior.gd`, `buildings.gd`, `landmarks.gd` | Feine Modelle: Einrichtung der Hallen, Versorgungsbauten, Hangar, Tower, Feuerwache, Parkhaus |
| `scripts/furniture.gd`, `landscape.gd` | Möbel und Landschaft, bewegt über `deco_anim.gd` und `belt_anim.gd` |
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
