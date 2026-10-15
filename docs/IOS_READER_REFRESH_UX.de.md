# SourceBraid: Reader-Navigation und Hintergrundaktualisierung

12. Oktober 2026 · [English](IOS_READER_REFRESH_UX.md)

Diese lokale Ergänzung ersetzt das gedrängte iPhone-Layout und den vollständigen
Artikelabruf bei jedem Start. Sie erweitert den freigegebenen
[Reader-Plan](IOS_READER_INTELLIGENCE_DUO_PLAN.de.md). Geräteabnahme und
Veröffentlichungsfreigabe bleiben offen; kein Commit, Push oder Upload ist
freigegeben.

## Navigation und Darstellung

Das [Konzept für die Markenfarben der App](IOS_BRAND_APPEARANCE.de.md) beschreibt
die zurückhaltende Papier-/Grün-Palette nach dem Vorbild der SourceBraid-Webseite.

Die App startet mit **Neueste** und zeigt die neuesten sieben Beiträge.
Die native gruppierte Liste nutzt den verfügbaren Inhaltsbereich. Antippen
öffnet den Beitrag direkt; die systemeigene
Zurücknavigation führt zur Liste. Datumswerte erscheinen entsprechend der
aktuellen Sprache statt als ISO-Zeitstempel. Reine Tagesdaten behalten ihren
UTC-Kalendertag.

Ab OS 18 trennt die systemeigene Tab-Leiste **Neueste**, **Suche** und **Chat**.
OS 17 verwendet entsprechende Aktionen in der unteren Toolbar. Oben stehen
Aktualisieren/Stopp und ein Mehr-Menü für Einstellungen, lokale Datenlöschung
und Abmelden. Reader-Aktionen bleiben in dessen Toolbar; dort kann man auch zum
Chat über den ausgewählten Beitrag wechseln. Der Chat hat einen eigenen
scrollbaren Bereich und ein mehrzeiliges Eingabefeld oberhalb von Safe Area und
Tastatur. Er belegt keinen Platz mehr in der Startliste. Ein nicht verfügbares
Modell zeigt seinen Status im Chat; der Reader bleibt nutzbar.

Senden/Stoppen sitzt rechts innerhalb der gemeinsamen abgerundeten Eingabefläche.
Der Text hat einen eigenen reservierten Bereich und überlagert die Aktion nicht.
Bei Fokus bleibt Tastatur-Ausblenden eine separate Aktion neben dem Eingabefeld.
Reguläres Padding innerhalb des Safe-Area-Inset schafft mehr Abstand zur unteren
Systemleiste, ohne manuelle Safe-Area-Offsets.

Die Tab-Leiste an der Wurzel gibt jedem Bereich eine dauerhafte
`NavigationSplitView` für breite und kompakte Fenster.
Breit erscheint die gewählte Liste/Suche/Chat links und der Reader rechts.
Beim Schließen des Duo wählt der vorhandene Hinge-Adapter die Hauptansicht mit
Auswahl/Chat. Auswahl, Suchtext/-ergebnisse, Chatentwurf/-verlauf und Modelle
liegen im dauerhaften Root. Das Layout nutzt verfügbaren Platz und Safe Areas,
keine Displaymaße, Geräteklassen oder festen Listen-/Chathöhen. Echte
Duo-Faltwechsel, sehr flache Fenster und vertikale Systemleisten bleiben Teil
der [Geräteabnahme](IOS_DEVICE_ACCEPTANCE.de.md).

Die Gestaltung folgt Apples [Toolbar-Vorgaben](https://developer.apple.com/design/human-interface-guidelines/toolbars)
und [Tab-Leisten-Vorgaben](https://developer.apple.com/design/human-interface-guidelines/tab-bars):
Systemdarstellung, erkennbare Bereiche, SF Symbols, wenige häufige Aktionen und
weitere Aktionen im Mehr-Menü. Xcodes Skills `swiftui-specialist` und
`app-resizability` wurden für den Quelltextreview verwendet; die exportierten
Skills bleiben außerhalb des Repositorys.

## Start- und Aktualisierungsregeln

| Auslöser | Arbeit |
| --- | --- |
| Start mit Cache / Vordergrund | Geschützten lokalen Metadatenkatalog und Suchabdeckung wiederherstellen. Keine automatische GitHub-Bestands- oder Artikelanfrage. |
| Leerer lokaler Cache | Gepinnten Bestand mit Anfragebudget lesen und höchstens sieben Markdown-Dateien versuchen. Unvollständige Abdeckung anzeigen. |
| Geplanter Hintergrundabruf | Neuesten Commit prüfen, Bestandsänderungen abgleichen und ein begrenztes Paket fehlender/geänderter Dateien oder Suchzeilen verarbeiten. |
| Pull to refresh / Toolbar-Aktualisierung | Ausdrücklichen inkrementellen Abgleich starten; ausstehende Artikel innerhalb vorhandener Datei-/Cache-Grenzen vervollständigen. Stopp bleibt verfügbar. |
| Nicht geladenen Beitrag öffnen | Diesen Beitrag gezielt laden und Metadaten/Suchzeile seiner aktuellen Version ergänzen. |

Bei völlig leerem Cache sind die Metadaten in den Beiträgen noch unbekannt.
Die ersten sieben Kandidaten werden deshalb anhand verfügbarer Dateinamensdaten
und deterministischer Fallbacks priorisiert. Die Oberfläche kennzeichnet den
Teilbestand. Weitere Pakete ermitteln die tatsächliche Aufnahmezeit-Reihenfolge;
ohne die erforderlichen Metadaten kann die App keine endgültigen neuesten sieben
garantieren. Bereits vollständig gespeicherte Metadaten liefern diese sofort.

Der Katalog speichert den gepinnten Commit und jede Datei-SHA. Bei vollständigem,
unverändertem Bestand/Index genügt während einer Aktualisierung die
Commit-Anfrage. Unveränderte Dateien und passende Suchzeilen werden wiederverwendet.
Neue/geänderte Dateien werden gelesen, gelöschte Pfade aus Katalog und Suchindex
entfernt. Eine ältere Quellenreferenz bleibt gepinnt und überschreibt keine
aktuellen Metadaten. GitHub-Markdown und Historie bleiben maßgeblich; der lokale
Suchindex ist verwerfbar. Die Such-/Chatabdeckung zählt alle Markdown-Dateien
im Bestand einschließlich noch nicht geladener Dateien; sieben Startdateien
dürfen keine vollständige Archivabdeckung suggerieren.

## Hintergrundjob und Grenzen

Die App registriert `de.patrickschiller.sourcebraid.archive.refresh` beim
`BGTaskScheduler` und deklariert `fetch` in `UIBackgroundModes`. Eine konfigurierte
App meldet beim Wechsel in den Hintergrund und nach einem Job einen
`BGAppRefreshTaskRequest` an. Frühester Beginn ist eine Stunde später.
**iOS entscheidet, ob und wann er läuft; dies ist kein stündlicher Timer.**
Deaktivierte Hintergrundaktualisierung, erzwungenes Beenden, Energie-/Netzbedingungen
und Systemgrenzen können den Abruf verzögern. Manuelles Aktualisieren und Lesen
aus dem Cache bleiben möglich.

Ein Hintergrundpaket versucht maximal 20 Artikel mit 10 MiB Dateibudget und
32 Bestandsanfragen; zusätzlich gilt die vorhandene 5-MiB-Markdown-Grenze.
Deklarierte/reservierte Bytes zählen auch bei fehlgeschlagenen Abrufen;
unbekannte Größen reservieren das verfügbare Dateibudget. Ein interner
25-Sekunden-Timeout und der Ablauf-Handler von iOS brechen Arbeit ab. Ein späterer
Job setzt ausstehende Arbeit fort. Im Hintergrund werden weder KI-Antworten
erzeugt noch externe Bilder geladen.
Benötigt ein großer Bestand mehr Traversierungsanfragen als das Paket erlaubt,
bleibt der bisherige Katalog erhalten; manuelles Aktualisieren kann den Walk
abschließen. Ein abgeschnittener Bestand wird nicht als vollständig gespeichert.

Ein gemeinsamer Koordinator serialisiert Refresh-/Cache-Schreibvorgänge über
App-Szenen und gezielte Reader-Abrufe hinweg. Datenlöschung und
Konfigurationswechsel brechen alte Schreiber ab und warten vor dem Löschen.
Abmelden storniert geplante Jobs; Speichern der Konfiguration ermöglicht die
Planung wieder. Fehler bei atomarer Katalogpersistierung rollen den Speicherstand
zurück. Ein unlesbarer/geschützter Katalog wird niemals als leeres Archiv
behandelt und überschrieben. Start/Vordergrund liest den Katalog erneut, um
abgeschlossene Hintergrundpakete zu übernehmen.

Zusätzlich finden nur authentifizierte GET-Anfragen zum vorhandenen Endpunkt
`api.github.com` zu Hintergrundzeitpunkten statt. Keine zusätzlichen
GitHub-Rechte, Archivformate, KI-Endpunkte, Zugangsspeicher oder Capture-Änderungen.
Keychain und vorhandener Cache-Dateischutz gelten weiterhin. Siehe
[PRIVACY.md](../PRIVACY.md).

Apples [Background-Tasks-Dokumentation](https://developer.apple.com/documentation/backgroundtasks)
beschreibt Systemplanung und Ablaufbehandlung; die APIs werden außerdem gegen
das installierte SDK kompiliert.

## Prüfung und Abnahme

Synthetische Regressionstests prüfen Cache-Starts ohne Netzwerkanfragen, den
Sieben-Dateien-Start, unveränderte Commits, SHA-Änderungen/Löschungen, Paket- und
Fehlerbudgets, gezielte Indexierung, Abbruch, Datenlöschung aus anderer Szene,
Konfigurationswechsel, geschützte Kataloge und Persistierungs-Rollback. UI-Tests
prüfen native Bereiche, Sichtbarkeit der neuesten sieben, lokalisierte Daten,
Reader-Navigation, Suche, Tastatur/Entwurfserhalt, Rotation sowie PDF und
Markdown-Quelltext. Ergebnisse stehen im
[Testprotokoll](IOS_IMPLEMENTATION_TESTING.de.md).

Auf dem echten iPhone Cache-Neustarts und tatsächliche GitHub-Anfragen messen;
deaktivierte Hintergrundaktualisierung, Stromsparmodus, Sperren/Entsperren,
Netzwerkverlust, Token-Widerruf, Job-Ablauf und Abmelden während eines Abrufs
prüfen. Tatsächliche Ausführungen protokollieren; der früheste Beginn ist keine
Garantie. Auf Duo kompakte/breite Übergänge und Tastaturfälle wiederholen.
Diese Gerätefälle, OS-17-Start und echte Modellqualität bleiben offen.
