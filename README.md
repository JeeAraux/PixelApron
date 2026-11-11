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

- **Update 0.29.1: Gepäckzüge fahren bis an die Sortierung**
  - Die Einfahrt hinter einem Rolltor ist jetzt 16 m tief, der ganze Gepäckzug fährt in die Halle und hält längs an der Sortierung (Kofferablage). Im Startflughafen sitzt das Rolltor direkt neben dem Ring, die Rollenbahn führt um die Ecke darauf.
  - In eigenen Flughäfen das Rolltor mit „Verschieben“ neben die Gepäcksortierung setzen; ist die Einfahrt dahinter frei (keine Einrichtung, keine niedrigen Bänder), fahren die Züge hinein.
  - Fluggäste gehen im Schnitt etwas zügiger, damit sie trotz freierer Wege rechtzeitig am Gate sitzen.
- **Update 0.29: Fahrwege, Laufwege, Wetter drinnen**
  - **Kein Regen und Schnee in den Hallen:** In der Innenansicht fällt im Gebäude nichts mehr, draußen schon. Der graue Schleier bleibt draußen.
  - **Fahrzeuge bleiben auf Belag:** Vor Garagen, Gerätehalle, Tanklager, Catering, Feuerwache und Rettungswache gibt es einen Vorplatz mit Zufahrt zum nächsten Weg. Die Fahrwege folgen Kurven enger (keine Abkürzung über die Wiese), Verbindungen gibt es nur, wo Wege sich wirklich berühren. Die Feuerwehr stellt sich bei Kontrollfahrten und Bereitschaft an den Rand des Rollwegs statt auf die Wiese.
  - **Warteplätze am Stand:** Die Fahrzeuge warten nebeneinander auf dem Vorfeld oder der Standfläche, nicht auf der Wiese, nicht auf fremden Ständen, nicht auf der Betriebsstraße und nicht ineinander. Aus der Gerätehalle fahren sie nacheinander aus.
  - **Vorfeldbusse:** Sie fahren über Betriebsstraße und Vorfeld zum Flugzeug und setzen mit einem Wendebogen nach vorn ab, nicht mehr quer durch Flugzeuge und Flügel.
  - **Menschen gehen freier:** Jeder nimmt seine eigene Bahn durch die Halle, schlendert und geht in weichen Kurven, in eigenem Tempo.
  - **Einmündungen von Betriebsstraßen** mit gerundeten Ecken, die Randlinie ist an der Mündung offen. Straßenecken ohne Zacken.
  - **Overlay „Kofferwege“ (Taste O):** Pfeile zeigen, wohin die Koffer laufen: orange vom Check-in über die Durchleuchtung zur Sortierung, blau von der Sortierung zu den Gepäckbändern, violett vom Rolltor der Gepäckzüge zur Sortierung. Ein rotes Kreuz zeigt Schalter oder Bänder ohne Anschluss.
- **Update 0.28: Verschieben**
  - Neues Werkzeug „Verschieben“ in der Bauleiste (neben Abriss): Gebäude, Hallen und Einrichtung anklicken, woandershin ziehen, mit Klick absetzen. R dreht, Rechtsklick legt zurück. Verschieben kostet nichts.
  - Terminalhallen nehmen Einrichtung, Wände, Kofferbänder und Fluggastbrücken mit, die Menschen darin wandern mit. Stände nehmen ihre Einrolllinien mit.
  - Es gelten dieselben Regeln wie beim Bauen. Wege, auf denen ein Gebäude schon vorher stand, stören beim Verschieben nicht. Belegte Stände bleiben stehen, bis das Flugzeug weg ist. Strom, Wasser und Wärme kommen über die Leitungen: Wer ein Gebäude aus ihrer Reichweite schiebt, muss neu anschließen.
- **Update 0.27.2: Einrolllinien an der Rollweg-Mittellinie**
  - Die Einrolllinien der Positionen schließen jetzt tangential an die Mittellinie des Rollwegs dahinter an, nicht mehr an eine Hilfslinie am Rollwegrand. Die alte Rollgasse des Startflughafens ist weg, Spielstände werden beim Laden umgestellt.
  - Einrolllinien machen einen Rollweg oder ein Vorfeld nicht mehr zur „nur auf Linien“-Fläche. Die Flugzeuge rollen auf ihnen bis in die Position.
  - Vorfelder haben keine fest aufgemalte Mittellinie mehr, alle gelben Linien zeichnet man selbst (oder sie kommen als änderbare Rolllinien).
- **Update 0.27.1: Rollführungslinien an den Positionen**
  - Die Einrolllinien an den Ständen sind keine aufgemalte Deko mehr, sondern echte Rollführungslinien: Sie lassen sich abreißen, ersetzen und neu zeichnen. Neue Stände bekommen sie automatisch, wenn hinter ihnen schon eine Rolllinie liegt. Wird ein Stand abgerissen, verschwinden seine Linien mit.
  - Alte Spielstände behalten ihre aufgemalten Linien. Stellt man im Infofeld des Stands die Markierung auf „Rolllinien (änderbar)“, werden sie zu echten Linien. Liegt hinter dem Stand nur Vorfeld, bekommt das Vorfeld dabei eine Mittellinie.
- **Update 0.27: Große Hallen, Vorfeld als Fläche, Obergeschosse nach Maß**
  - **Busgarage, Feuerwache und Gepäckumschlag nach Größe:** Im Infofeld lässt sich die Zahl der Tore einstellen (Gepäckumschlag bis 8, Busgarage bis 8, Feuerwache bis 6). Die Halle wächst mit, jede Spur hat ihr eigenes Rolltor und ihre Einrichtung: Löschfahrzeuge, Arbeitsgruben und Waschplatz, Abladebänder mit Sammelband und Leitstand. In der Innenansicht ist das Dach ab, man sieht hinein.
  - **Gepäckzüge fahren in die Halle:** Die Züge fahren durch das Tor in eine freie Spur des Gepäckumschlags, laden dort ab und setzen rückwärts hinaus. Die Koffer laufen über das Sammelband zur Sortierung und weiter zum Gepäckband, wo sie von der Rampe auf das Band rutschen.
  - **Vorfeld als Fläche:** Neues Werkzeug „Vorfeldfläche“: Beton wird als Rechteck aufgezogen, mehrere Flächen ergeben jede Form. Stände, Haltestellen und Masten stehen darauf, Bodenfahrzeuge fahren frei, Flugzeuge nur auf den Rollführungslinien.
  - **Bushaltebuchten an der Betriebsstraße:** Die Vorfeldbus-Haltestelle rastet am Rand der Betriebsstraße als Bucht ein.
  - **Obergeschosse mit eigenen Maßen:** Mit dem Werkzeug „Geschossfläche“ (Terminal → Halle) zieht man im gezeigten Obergeschoss einen neuen Umriss auf. Höhere Geschosse dürfen kleiner sein und springen zurück, darunter entsteht eine Dachterrasse mit Glasgeländer. Kleinere Flächen werden anteilig erstattet.
  - **Geführte Vorfelder:** Eine Fläche gilt erst dann als „nur auf Linien“, wenn dort wirklich Rollführungslinien liegen, eine kurze Linie sperrt keinen Rollweg mehr.
- **Update 0.26: Wetter, Keller, Pushback und Rollwege**
  - **Nebel und Nacht:** Kein weißes Flimmern mehr über Laternen und Lichtkegeln im Nebel. Stattdessen ziehen Nebelschwaden knapp über dem Boden, Tower und Dächer ragen heraus. Die Nacht ist dunkler und ruhiger, Fenster leuchten gleichmäßig warm, Oberlichter im Dach nur schwach.
  - **Landescheinwerfer:** Lichtkegel in der Luft bei Nacht, Nebel und Regen, weich ein- und ausgeblendet. Dazu kommen rote und grüne Positionslichter und der Doppelblitz der Strobes.
  - **Durchstarten:** Ein kleiner Teil der Anflüge startet durch, bei Nebel, Schnee, Starkregen, Gewitter und Seitenwind deutlich mehr. Die Maschine steigt geradeaus, fährt Fahrwerk und Klappen ein und kommt über eine Platzrunde zurück.
  - **Keller:** Wer im Untergeschoss baut, bekommt den Keller unter der Halle automatisch angelegt.
  - **Treppen und Rolltreppen zwischen den Ebenen:** In der Decke darüber gibt es eine Öffnung mit Glasbrüstung, und die Verbindung ist auch von der oberen Ebene aus zu sehen.
  - **Neue Rolltreppe nach Vorbild:** 1000-mm-Stufen mit gelben Kanten, die flach aus der Kammplatte laufen, Glasbalustrade, umlaufender Handlauf und Edelstahlverkleidung. Die Treppe hat Natursteinstufen und Wangen.
  - **Menschen je Ebene:** Im Keller sind nur die Leute im Keller zu sehen, oben nur die oben.
  - **Räume nebeneinander:** Gemeinsame Wände werden nicht mehr doppelt gebaut, und Türen schneiden alle Wandstücke, auf denen sie sitzen.
  - **Fahrzeuge in der rechten Spur:** Auf Betriebsstraßen fahren die Fahrzeuge rechts statt in der Mitte. Radfahrer treten in die Pedale, statt zu laufen.
  - **Pushback wie echt:** Der Schlepper schiebt rückwärts auf die Rollgasse hinter dem Stand, das Heck schwenkt in den Bogen, und die Nase zeigt am Ende in die Rollrichtung. Ziele, von denen kein Weg zur Piste führt, werden nicht mehr gewählt.
  - **Rollwegkreuzungen:** An Kreuzungen gibt es eine gemeinsame Fläche mit Ausrundungen und gelben Randlinien entlang der Bögen. Die Mittellinien führen als Bögen in jeden Ast, ohne Überlappungen.
  - **Realistischere Rollwege:** Die Flugzeuge bevorzugen den Parallelrollweg und lange gerade Strecken. Über Vorfelder rollen sie nur, wenn es nötig ist, und auf der Piste nur zum Kreuzen oder Zurückrollen.
  - **Wendeplatte:** Neues Bauteil am Pistenende. Flugzeuge können dort umkehren (Backtrack) und in voller Länge starten.
  - **Standmarkierung wählbar:** Mit Einrolllinie, mit selbst gezeichneten Rollführungslinien oder ganz ohne. Vorfelder ohne eigene Linien zeigen die gelbe Mittellinie, auf der die Flugzeuge rollen.
  - **Abfertigung:** Frachttore von A320 und A321 an der richtigen Stelle. Gepäckzüge fahren nicht mehr durch Triebwerke (A380, A350). Vorfeldbusse meiden Standflächen und halten vor wartenden Flugzeugen an.
- **Update 0.25: Fenster nach Vorbild**
  - **Kabinenfenster in Originalgröße:** Jeder Typ hat Fenstermaß und Fensterabstand nach Herstellerangabe, zum Beispiel A320 mit 22,9 × 31,2 cm im 21-Zoll-Raster, 737 mit 25,4 × 35,6 cm und 787 mit den großen 27,2 × 46,7 cm. Die Fenster sind abgerundet, folgen der Rumpfwölbung, haben einen hellgrauen Rand und im Glas spiegelt sich der Himmel.
  - **Cockpitscheiben nach Seitenansichten der Vorbilder:** Die Airbus-Anordnung hat sechs Scheiben mit dunklen Holmen und einem hinteren Fenster mit abfallender Oberkante. Die Boeing 737, 767 und 777 haben weiße Holme und schräge Seitenfenster. Die 787 hat nur vier Scheiben mit keilförmigem Seitenfenster. Die Maske des A350 läuft hinten spitz aus, und das Cockpit des A380 sitzt tiefer, zwischen den Decks.
  - **Türen an der richtigen Stelle:** A320 und A321 haben Türen, Notausstiege und Frachttüren nach den Airbus-Unterlagen (Tür 1 rund 5 m hinter der Nase). Bei den anderen Typen ist die vordere Tür passend nach hinten gerückt.
- **Update 0.24: Schönere Flugzeuge**
  - **Cockpit wie beim Vorbild:** Große Frontscheiben mit Mittelholm, je zwei Seitenscheiben mit schrägem hinteren Fenster, schwarze Gummirahmen, Scheibenwischer und Himmelsspiegelung. Airbus und Boeing unterscheiden sich in Form und Höhe, der A350 trägt seine dunkle „Maske“.
  - **Nasenformen nach Hersteller:** Die Boeing 737 hat die spitze Nase, die A320-Familie die stumpfe, dazwischen 787, 767, A350 und die Regionaljets. Dazu kommen die Fuge am Radom, Anstellwinkel-Sensoren und statische Druckplatten.
  - **Bugfahrwerk:** Federbein mit verchromtem Kolben, Drehmomentstütze, Achse, Rollscheinwerfer, dunkler Schacht und schmale, schräg hängende Klappen.
- **Update 0.23: Leistung und Geräusche**
  - **Detailstufe:** Weit herausgezoomt blendet das Spiel Menschen, laufende Koffer und die Einrichtung unter den Hallendächern aus. Große Flughäfen laufen so flüssiger. Wer möchte, lässt sich die Bilder pro Sekunde in der Kopfzeile anzeigen (Einstellung).
  - **Geräusche** (im Spiel erzeugt, ohne Tondateien): Gong, wenn das Boarding beginnt, Triebwerksrauschen rollender, startender und landender Flugzeuge in der Nähe, Stimmengewirr in der Innenansicht, Regen, Donner nach Blitzen, Martinshorn am Rettungswagen und Warnpiepen fahrender Rolltore. Lautstärke in den Einstellungen.
- **Update 0.22: Größere Flugzeuge, Gebühren, Fluglärm**
  - **Flugplatzcodes A–F:** Stände, Rollwege und Pisten passen zur Spannweite. Neu sind die **Boeing 767** (Code D) und der **Airbus A380** (Code F, vierstrahlig, Doppelstock), dazu ein **A380-Stand** (84 × 80 m). Ab Code D brauchen Flugzeuge breite Rollwege, der A380 eine Piste ab 2950 m.
  - **Fluggastbrücke mit Oberdeck-Steg** (Bauform): ein zweiter Tunnel und eine zweite Kabine darüber.
  - **Gebühren** im Betriebsfenster (Reiter „Gebühren und Lärm“): Landeentgelt (mehr Geld je Landung, Airlines kommen seltener), Parkgebühr und Ladenmiete (mehr Einnahmen, aber über 120 % ärgern sich die Reisenden).
  - **Fluglärm:** Drei Wohngebiete rund um den Flughafen, eines davon in der Anflugschneise. Über 55 dB beschweren sich die Anwohner, nachts dreifach, und die Zufriedenheit sinkt. Wohngebiete lassen sich auch selbst bauen (Umfeld). **Nachtflugverbot** 23–6 Uhr zum Umschalten. Das Betriebsfenster zeigt außerdem das Ereignisprotokoll.
- **Update 0.21: Leben im Betrieb**
  - **Personen ansehen:** In der Innenansicht eine Figur anklicken. Das Infofeld zeigt Flug, was sie gerade tut, als Nächstes vorhat, Hunger, Toilette, Laune und Wartezeit, dazu ihren Weg als gelbe Linie.
  - **Overlays (O):** Gedränge und Wartezeit als Wärmekarte über den Hallen, Fluglärm um die Pisten mit An- und Abflugschneisen.
  - **Medizinische Notfälle:** Ein Fluggast bricht im Terminal zusammen. Ersthelfer kommen aus dem Sanitätsraum, und ein Rettungswagen fährt mit Blaulicht an die Hallenwand und holt den Patienten ab. Bei einem Notfall an Bord wartet der RTW am Stand. Neue **Rettungswache** (Flugbetrieb → Werft und Dienste). Ohne Wache kommt der RTW von außerhalb und braucht viel länger.
  - **Störungen und Ereignisse** (Einstellung „Ereignisse“): Bandausfall mit Techniker (mit Technikraum schneller), Stromausfall an einem Trafo, Warnstreik (weniger Personal), Gewitter mit Blitzen (Vorfeld und Abfertigung ruhen), Vogelschlag (Pisteninspektion durch die Feuerwehr).
- **Update 0.20: Räume, Warenlogistik, Ansichten, Kontrolltechnik**
  - **Raumarten wie in Prison Architect:** Lager, Küche, Sanitätsraum, Pausenraum und Technikraum. Mit dem Raum-Werkzeug wählbar (Leiste: Raum) oder als Fläche aufziehen. Ein Raum zählt erst mit seiner Ausstattung (Regale, Küchenzeile, Behandlungsliege, Spinde und Bistrotische, Schaltschränke) und Mindestfläche. Das Infofeld der Halle zeigt, was fehlt.
  - **Wirkung:** Eine Küche bringt den Cafés mehr. Der Pausenraum lässt das Personal 10 % mehr schaffen. Sanitätsraum und Technikraum helfen bei Notfällen und Störungen (ab 0.21).
  - **Warenlogistik:** Läden und Cafés verkaufen ihre Regale leer. Mitarbeiter bringen mit Rollwagen Ware aus dem Lager. Ein Lieferwagen füllt das Lager über ein Rolltor auf. Ohne Lager werden die Regale nie ganz voll.
  - **Wandansicht (H):** Innenwände halb, in voller Höhe oder ausgeblendet. **Schnittansicht (J):** alle Ebenen bis zur gezeigten übereinander. Beides gibt es als Knöpfe neben der Ebenenwahl.
  - **Sicherheitskontrolle:** Bauform Technik: klassisch (150/h), CT-Scanner (220/h) oder Express mit Wannenrückführung (280/h).
- **Update 0.19: Gepäckabfertigung**
  - **Gepäckzüge fahren in die Halle:** Ist hinter dem Rolltor eine 4 × 10 m große Einfahrt frei (gelbe Fahrspur), fährt der erste Zug durchs offene Tor hinein, lädt ab und setzt rückwärts im Bogen wieder hinaus. Weitere Züge warten vor dem Tor.
  - **Abflugzüge am Tor:** Sie laden neben der Toröffnung, das Tor fährt hoch, und die Koffer laufen sichtbar aus der Sortierung hinaus.
  - **Make-up-Rutschen:** Die Gepäcksortierung hat 2, 4, 6 oder 8 Rutschen (Bauform). Jeder Abflugzug braucht eine freie Rutsche, sonst wartet er.
  - **Gepäckdurchleuchtung im Kofferweg:** Kofferbänder schließen an den Schmalseiten an, die Koffer fahren durch den Tunnel. Für Non-Schengen-Flüge zählt sie nur, wenn die Koffer der Schalter wirklich hindurchlaufen.
  - **Transfergepäck:** 10–25 % der Koffer jedes ankommenden Flugs bleiben in der Sortierung. Abflugzüge nehmen sie mit und laden damit schneller.
  - **Bandlast:** Ein Kofferband verkraftet die Koffer von 6 Schaltern. Hängen mehr dahinter, stauen sich die Koffer und die Schalter arbeiten langsamer (Hinweis im Infofeld). Wo ein Band seitlich auf ein anderes trifft, steht ein Einschleuser.
  - **Startflughafen:** Sortierung, Durchleuchtung und Rolltor sind neu angeordnet.
- **Update 0.18: Runde Kofferbänder, Gepäckband-Anschluss, Rolltore**
  - **Rundungen:** Wo zwei Kofferbänder mit einem Knick aneinanderstoßen, laufen sie in einem gemeinsamen Bogen ineinander. Die Bänder sind jetzt aus einem Stück (Wanne, Gurt, Seitenbleche) und an Knicken auf Gehrung geschnitten; kurze Stücke steigen steiler, damit sie oben am nächsten Band ankommen.
  - **Gepäckband mit Einlauf:** An der linken Schmalseite steht ein Steilförderer mit Rutsche. Dort muss ein Kofferband aus der Sortierung ankommen, sonst arbeitet das Band nicht (Ankommende gehen nur an angeschlossene Bänder). Die Koffer eines Flugs laufen sichtbar von der Sortierung über die Bänder auf ihr Gepäckband. Ältere Spielstände behalten die alte Regel.
  - **Rolltor:** neues Bauteil für die Außenwand (rastet bündig ein). Gepäckzüge fahren bei einer Halle mit Sortierung vor das nächste Rolltor, das Tor fährt hoch, die Wagen stehen vor der Öffnung und die Koffer laufen über die Rollenbahn hinein, mit einem Kofferband bis zur Sortierung.
- **Update 0.17: Kofferwege und europäische Straßen**
  - **Kofferbänder** laufen zwischen den Anschlüssen unter der Decke (Fluggäste gehen darunter durch) und brechen sich durch Wände eine Öffnung. Der neue **Gepäcklift** bringt Koffer in den Keller oder ins Obergeschoss, die Sortierung darf im Keller stehen.
  - **Check-in nur mit Band:** Fluggäste gehen nur an Schalter, die über Kofferbänder mit der Sortierung verbunden sind. Koffer laufen nur, wenn wirklich jemand eincheckt, und folgen ihrem Weg bis zur Sortierung; erst dann läuft deren Ring. Ältere Spielstände behalten die alte Regel.
  - **Straßen im europäischen Stil:** Ampeln am Mast an der Haltelinie mit Kontrastblende und Fußgängersignal, Richtungspfeile auf den Spuren, Schilder am Zebrastreifen, Leitlinien 3 m/6 m, an Hochbordstraßen eine gepflasterte Rinne statt weißer Randlinie.
- **Update 0.16: Bauen wie in Aufbauspielen mit Grundriss, Kofferbänder, Stockwerke**
  - **Sandkasten:** Geld ist unbegrenzt (Einstellung, Standard an; Szenarien bleiben mit Budget).
  - **Ziehen statt Klicken:** Hallen, Bereiche, Wände und das neue Werkzeug **Raum** zieht man mit gedrückter Maustaste auf. Ein Raum bekommt automatisch Wände, Tür und auf Wunsch einen Bereich (öffentlich, Sicherheit, Personal). Abriss auf freiem Boden zieht eine Fläche auf.
  - **Stockwerke:** Vorschau steht jetzt auf der gezeigten Ebene; ▲ über der obersten Ebene setzt der Halle ein Geschoss auf.
  - **Check-in neu:** Schalter mit Lichtportal, Fluginfo-Bildschirmen, Gepäckwaage mit Einzug und Sammelband. **Kofferband** vom Check-in zur Gepäcksortierung: rastet an Schaltern und Sortierung ein, Koffer laufen sichtbar, angeschlossene Schalter schaffen 25 % mehr.
  - **Fluggastbrücken mit Steg** (12, 20 oder 30 m) über Betriebs- und Terminalstraßen.
  - **Straßen:** Knicke zwischen Straßenstücken werden rund ausgebildet, Gehwege überlappen nicht mehr.
- **Update 0.15: Schönere Straßen**
  - **Querschnitte:** Jede Straße wahlweise als reine Fahrbahn, mit Gehweg, mit Gehweg und rotem Radweg oder als Allee mit Grünstreifen und Bäumen. Hochbord, Pflaster, Straßenleuchten mit Lichtkreisen in der Nacht. Wahl in der Wegebau-Leiste oder mit V, Ersetzen baut bestehende Straßen um.
  - **Kreuzungen:** Gehwegecken um die Bordsteinbögen und Zebrastreifen an allen Zufahrten mit Gehweg.
  - **Haltebuchten:** Bushaltestelle, Taxistand und Kiss & Fly rasten am Straßenrand ein; davor entsteht eine Bucht mit Zickzacklinie und Aufschrift, in die Busse und Taxis einfahren.
  - **Leben:** Spaziergänger auf den Gehwegen, Radfahrer auf den Radwegen. Alleen und Radwege heben die Zufriedenheit etwas.
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
   - ein **Gepäckband**, dessen Einlauf über ein Kofferband mit der Sortierung verbunden ist,
   - am besten ein **Rolltor** in der Außenwand nahe der Sortierung für die Gepäckzüge.

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
| V | Querschnitt neuer Straßen wechseln (Fahrbahn, Gehweg, Radweg, Allee) |
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
