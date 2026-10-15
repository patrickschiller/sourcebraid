# SourceBraid: iOS-Umsetzung und lokale Testnachweise

Stand: 15. Oktober 2026 · [English](IOS_IMPLEMENTATION_TESTING.md)

Der [Modulplan M00–M10](IOS_READER_INTELLIGENCE_DUO_PLAN.de.md) wurde in der
freigegebenen Reihenfolge umgesetzt. Am 15. Oktober 2026 bestätigte der
Maintainer, dass die App gut aussieht und funktioniert, und gab
**1.1.0/Build 11** ausdrücklich zur Veröffentlichung frei. Die
Xcode-Cloud-Distribution wird in den [Release-Hinweisen](IOS_RELEASE_1.1.0.de.md)
getrennt verfolgt; hier wird kein erfolgreicher Cloud-Build, Upload oder
App-Store-Release behauptet. Der geplante iOS-Tag lautet `ios-v1.1.0`.

Die folgenden Nachweise sind chronologisch. Ältere Einträge behalten ihre
tatsächlich geprüften IDs 1.0.1/Build 10 und damaligen Nichtveröffentlichungs-
vermerke. Vor der Versionsanhebung bestanden auf dem nativen Duo 47 Unit-/
Integrationstests, nach Selektorkorrekturen alle 7 UI-Fälle sowie gesondert
1/1 deutscher UI-Ablauf auf dem geöffneten Innendisplay. Frühere Kernprüfungen
bestanden mit 23 Node- und 64 Python-Tests. Die Release-Vorabprüfungen werden
für die Versionsanhebung erneut ausgeführt und getrennt festgehalten.

## Implementierung und noch offene Abnahme

| Modul | Lokal implementiert / nachgewiesen | Offene Abnahme |
| --- | --- | --- |
| M00 | Xcode 27.1 (27A9275), SDK 27.1; nativer Markdown-Probeversuch zeigt Quelltext statt GFM-Darstellung. Daher AST-Renderer; Quick Look für PDF. | Mindest-OS 17 und native Vorschau auf realer Hardware. |
| M01 | GET-only GitHub-Client, commit-/blobgebundene Inventare, Root-Grenzen, SHA-Prüfung, Truncation-Walk, keine Redirects mit Token. | Live-Test des privaten Archivs und Anfragelimits. |
| M02 | UTC-Chronologie, markierter Tages-/Dateinamen-Fallback, neueste sieben, Teilbestandsstatus, getrennte geschützte Caches und Eviction. | Große Archive, Laufzeit/Speicher/Netzwerk auf Geräten. |
| M03 | GFM-Reader, Code/Tabellen/Aufgaben, relative Raster-Assets, interne Links, rohe HTML-Darstellung als Text, Quelltext/Sharing/GitHub-Fallback, PDF-Quick-Look. | VoiceOver, gesamte Formatmatrix und Mindest-OS. |
| M04 | SwiftUI-Split-Navigation, direktes Öffnen, native Bereiche Neueste/Suche/Chat, Toolbar, lokalisierte Daten, Tastatur und Rotation. | Schmale iPad-Fenster und mehrere reale Szenen. |
| M05 | Lokales SQLite FTS5/BM25, gebundene SQL-Parameter, Versionsabgleich/Löschabgleich, begrenzte DE/EN-Quellenauszüge. | Suchqualität und Rebuild bei großen Archiven. |
| M06 | Verfügbarkeitsmatrix, lokales `SystemLanguageModel.default`, Sprachprüfung, OS-Guards, Token-Vorabprüfung ab 26.4. | Tatsächliche Geräte-/Sprach-/Modellzustände. |
| M07 | Streaming-Chat, bei Anfrage festgelegter Bereich/Snapshot, Quellen-ID-Prüfung und Öffnen der belegten Version, Abbruch/Reset, begrenzte Tools/Verlauf. | Inhaltliche DE/EN-KI-Evaluation und Prompt-Injection auf echtem Modell. |
| M08 | Such-/Letzte-/Öffnen-App-Intents, nur geladene Einträge, lokale Authentifizierung, DE/EN-Texte und Phrasen; Metadaten bauen. | Kurzbefehle, Gerätesperre, Kaltstart und Siri am Gerät. |
| M09 | Systemspalten und ab iOS 27.1 `onHingeChange`; Schließen setzt die kompakte Hauptansicht auf Auswahl/Chat. | Echter Duo-Faltwechsel und gesamte Übergangsmatrix. |
| M10 | Unit-/Integration-/UI-Suiten, synthetische Demo, zweisprachige Anleitung/Datenschutz/Lizenztexte; Veröffentlichungsfreigabe des Maintainers vom 15. Oktober. | Verbleibende Geräte-/KI-/Accessibility-Nachweise und Distributionsergebnisse. |

Funktionstest und Release-Freigabe des Maintainers markieren nicht alle
Geräteprüfungen als bestanden. Mindest-OS-Starts, vollständige Falt-/
Wiederöffnungszyklen, teilweise gefaltete Haltungen, Duo-Dunkelmodus, reale
Duo-Hardware, Accessibility und echte Apple-Intelligence-Qualität bleiben auf
die unten dokumentierten Nachweise begrenzt.

## Technische Entscheidungen und Grenzen

- Markdown/Git-Historie bleiben maßgeblich. Kein Archivformat, Index-Shard,
  Capture-Workflow, Browser-Scope oder Plugin-Werkzeug wurde migriert.
- `swift-markdown` und `swift-cmark` sind auf **0.9.0** festgelegt, inklusive
  `Package.resolved`. Apache-Lizenz mit Swift-Ausnahme, NOTICE und cmark-COPYING
  stehen vollständig im App-Bundle und unter Einstellungen → Lizenzen.
- Quick Looks `canPreview` ist ein Fähigkeitsindikator, kein Nachweis für
  formatiertes Markdown. Der synthetische Simulator-Probeversuch zeigte rohe
  Überschriften, Fettschrift-Syntax und Tabellen-Pipes. PDFs verwenden dagegen
  die native Vorschau. Native Markdown-Abnahme auf OS 17 bleibt offen.
- Markdown wird als AST in erlaubtes HTML/CSS übersetzt. Rohes HTML wird
  escaped; CSP und WebKit blockieren Dokument-JavaScript/Netzwerk. Nur die App
  führt eine feste, JSON-escaped DOM-Operation für Quellenanker aus.
- Frontmatter liest den von SourceBraid verwendeten Skalar-/Listen-Teil von
  YAML. Unbekannte oder komplexe Metadaten bleiben im unveränderten Quelltext;
  es werden keine Titel, Autoren oder Aufnahmezeiten erfunden.
- Cache-Start/Vordergrund lädt lokale Metadaten ohne Artikel-/Bestandsanfragen.
  Ein leerer Cache versucht höchstens sieben Dateien, zunächst priorisiert nach
  Dateinamen und als Teilbestand markiert. Weitere inkrementelle Hintergrundpakete
  ermitteln die vollständige Aufnahmezeit-Reihenfolge; manuelle Aktualisierung
  kann ausstehende Arbeit abschließen. Shards beschleunigen diesen Erstabruf noch
  nicht. Siehe [Navigations-/Refresh-Konzept](IOS_READER_REFRESH_UX.de.md).
- Hintergrundabruf mit `BGAppRefreshTaskRequest`, frühestens nach einer Stunde;
  iOS bestimmt die Ausführung. Grenzen: 20 Artikelversuche, 10 MiB Dateibudget,
  32 Bestandsanfragen und Abbruch nach 25 Sekunden. Unveränderter vollständiger
  Commit/Index benötigt eine Commit-Anfrage; gleiche SHAs/Suchzeilen werden
  wiederverwendet. Ablauf/Wechsel/Löschung bricht alte Schreiber ab. Keine
  Hintergrund-KI oder externen Bilder.
- Budgets: 5 MiB/Markdown, 20 MiB/Asset, 250 MiB zurückbehaltener Cache pro
  Archiv, darin SQLite bis etwa 100 MiB und Katalog bis 32 MiB. Cache-Schreib-
  und SQLite-Journaldateien können vorübergehend zusätzlichen Platz benötigen.
  Große Dateien erhalten GitHub-Fallback, ohne das separate 25-MB-Capturelimit
  zu verändern. Diese Budgets sind noch am echten Archiv zu messen.
- Suche ist wortbasierte Volltextsuche über indizierte Downloads; sie behauptet
  keine vollständige oder semantische Archivabdeckung. Gelöschte/geänderte
  Dateiversionen werden aus Suchergebnissen ausgefiltert.
- KI: höchstens vier Quellen, zusammen 4.500 Zeichen; Auszüge je Quelle bis
  1.600 Zeichen/24 Zeilen, Fragen bis 1.200 Zeichen, kurzer Gesprächskontext
  und maximal zehn sichtbare Frage-/Antwortpaare im Arbeitsspeicher. Werkzeuge
  lesen nur diese Auszüge bzw. bis zu fünf Titel, mit sechs Aufrufen und
  6.000 Ausgabezeichen pro Frage. Sie können weder schreiben noch Netzwerke
  anfordern. Kontextfehler führen zu keiner überprüften Antwort.
- Quellen-IDs verweisen auf tatsächlich gelieferte Auszüge. Das prüft nicht,
  ob jede Behauptung inhaltlich belegt ist; die Geräte-Evaluation ist erforderlich.
- Foundation Models ab OS 26, Token-Vorabprüfung ab 26.4, Duo-Hinge ab 27.1.
  Reader/Suche bleiben ab 17 vorgesehen. Kein Private Cloud Compute oder
  externer KI-Dienst. App Intents sind gezielte Aktionen; keine Zusage eines
  frei verfügbaren Siri-Archivchats.
- Dateimetadaten im eigenen Cache dienen lokal der Eviction. Der App-
  Datenschutzmanifest ergänzt dafür `FileTimestamp`/`C617.1`. Der Validator
  verlangt diesen exakten Zweck für die App und erhält die engere Declaration
  der Share Extension; ein negativer Test weist abweichende Zwecke zurück.

Apples Dokumentation stützt die [Kontext-Vorabprüfung](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window),
die [Kurzbefehls-Lokalisierung](https://developer.apple.com/videos/play/tech-talks/10168/)
und den [Dateimetadaten-Zweck](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).
Die konkrete API-Nutzung wurde zusätzlich gegen das installierte SDK gebaut.

## Testnachweise vor der iPhone-Layout-Ergänzung

Die Testinhalte und Screenshots sind ausschließlich synthetisch. Kein Test
benötigt PAT, Benutzerarchiv oder Netzwerkzugriff auf GitHub. Chat-Integration
prüft einen injizierten Antwortadapter und belegt keine echte KI-Qualität.

| Prüfung | Ergebnis / Umfang |
| --- | --- |
| `node --test tests/capture-utils.test.js` | 23 bestanden. |
| `python3 -m unittest discover -s tests -p "test_*.py"` | 64 bestanden. „Push“-Ausgaben stammen aus bestehenden Mock-Tests; kein tatsächlicher Push. |
| `python3 scripts/validate_ios_release.py` | Bestanden; bisherige Release-IDs unverändert. Kein Distribution-Archive/Upload. |
| iPad Pro 13 M5, Runtime iOS 27.0, SDK 27.1 | 32 Unit-/Integrationstests und 6 UI-Tests bestanden in seriellen Läufen. |
| iPhone 17, Runtime iOS 27.0, SDK 27.1 | 32 Unit-/Integrationstests und 6 UI-Tests bestanden in seriellen Läufen. |
| Generischer iOS-Simulator-Build, ohne Signierung | Bestanden mit Xcode 27.1; App und Share Extension gebaut. Auch der Validator für das gebaute App-Bundle besteht. |
| Generischer iOS-Geräte-Build, Release, ohne Signierung | Bestanden, arm64, MinimumOSVersion 17.0; App-Bundle-Validator bestanden. Kein Archive, keine Installation oder Distribution. |
| Release-Binärdatei | Foundation Models als `LC_LOAD_WEAK_DYLIB`; Debug-Demo-/Probe-Schalter fehlen. Das ersetzt keinen Starttest auf OS 17. |

Die Swift-Tests decken Capture-Kompatibilität, UTC-/Legacy-Metadaten,
Pfadgrenzen, aktives HTML, immutable Reads und SHA, Teilbäume, Auth-Fehler,
Cache-Trennung/Eviction/Korruption, FTS-Updates/Löschung/Rebuild, Quellen-IDs,
Verfügbarkeit, Frage-/Toolbudgets und Abbruch/Archivwechsel ab. Zusätzlich
prüfen Regressionen Dateilimits auch bei Cache-Treffern, GitHub-Anfragelimits
und Abbruch sowie den aktuellen Archivbereich bei einer älteren Reader-Zitation.
UI prüft letzte fünf, direktes Öffnen/Zurück, Quelltext, Suche/Einstellungen,
deutsche Bedienung, Rotation, Dunkelmodus/große Schrift, internen Clip-Link
und native synthetische PDF.

Der erste iPad-Start mit parallelem Simulator-Klon scheiterte am CoreSimulator-
Startdienst. Nach vollständigem Boot und `-parallel-testing-enabled NO` war
die Suite grün. UI-Fehler während der Entwicklung (Lesen im scrollenden Listenteil,
antippbare Row-Fläche, Menü-Selektor und Scrollposition des Link-Tests) wurden
korrigiert und im folgenden Lauf geprüft. Die linke Spalte ist oben ausgerichtet.
Der PDF-Test wartet auf den dargestellten Seitentext, nicht nur auf den Titel;
PDFKit bestätigt zusätzlich eine lesbare Seite. Nach Schließen der Vorschau
wartet der Test auf die Rückkehr und verwendet kurze Scrollschritte, damit
benachbarte Links nicht übersprungen werden. Frühere weiße PDF-Screenshots
und fehlgeschlagene Läufe sind keine erfolgreichen Darstellungsnachweise.

Lokale Diagnoseartefakte liegen außerhalb des Repositorys, insbesondere
`/private/tmp/sourcebraid-final-units-{iphone,ipad}.xcresult`,
`/private/tmp/sourcebraid-final-layout-{iphone,ipad}.xcresult` und zugehörige Logs; synthetische
Screenshots sind im xcresult enthalten. Sie werden nicht in einen Release kopiert.
Die finalen Build-Logs heißen `sourcebraid-final-build-simulator.log` und
`sourcebraid-final-build-device-release.log` im selben temporären Ordner. Die
Metadata-Warnung für ein Target ohne App Intents betrifft die Share Extension;
die App erzeugt `Metadata.appintents`.
Die damalige Simulator-Runtime war 27.0, trotz SDK 27.1; kein Duo-Simulator-
oder echter Hardwaretest wurde als bestanden gezählt.

## Früherer Abgleich mit Apples Duo-Vorbereitung

Die bisherige Implementierung folgte den adaptiven Layoutregeln. Der konkrete
Workflow aus [Apples „Prepare“-Anleitung](https://developer.apple.com/iphone-duo/prepare/)
wurde erst beim nachträglichen Abgleich am 12. Oktober vollständig auf den
Quelltext angewendet: Xcode 27.1 exportierte `app-resizability` mit
`xcrun agent skills export`; alle fünf Aufgabenreferenzen wurden geprüft.
Der Skill-Export bleibt lokal außerhalb des Repositorys.

| Schritt / Prüfbereich | Nachweis / Status |
| --- | --- |
| Voraussetzungen | `UILaunchScreen` vorhanden, alle vier iPad-Orientierungen erlaubt, kein `UIRequiresFullScreen`. Info.plist, Debug-/Release-Projekteinstellungen und gebaute Plists stimmen überein; keine weiteren `.xcconfig`-Dateien. |
| Hauptbildschirm, Orientierung, Idiom | Keine davon abhängigen Produktlayouts. Systemspalten und `horizontalSizeClass` bestimmen die Navigation; die Größenklasse bezeichnet verfügbaren Platz. |
| Szenen und Safe Areas | SwiftUI `App`/`WindowGroup` und lokale `scenePhase`; keine manuellen Insets oder Symmetrieannahmen. Der eingebettete SwiftUI-Host der Share Extension füllt seinen Container; `NavigationStack`/`Form` berücksichtigen dessen Safe Areas. |
| Vollständige Datei-Abdeckung | 30 Swift-Dateien, beide Info.plists und Projektkonfigurationen geprüft. Vier Geräte-Idiom-Annahmen ausschließlich in `ArchiveUITests.swift` korrigiert: sichtbare, bedienbare **Lesen**-Schaltfläche vor Readeröffnung erkennen und diese Entscheidung für Zurücknavigation behalten. Orientierungswechsel bleiben Testeingaben. |
| Erneute UI-Prüfung | Nach dem Testfix jeweils 6 UI-Tests auf iPhone 17 und iPad Pro 13 M5 bestanden, ohne Fehler. SDK 27.1, Runtime 27.0, seriell. Lokale Result-Bundles: `/private/tmp/sourcebraid-duo-audit-{iphone,ipad}.xcresult`, zugehörige `.log`-Dateien. |
| Apples Schritt 3: Größenwechsel, Audit vom 12. Oktober | Damals war nur Runtime iOS 27.0/24A434 installiert, ohne verfügbaren Duo-Simulator. Runtime 27.1 wurde am 15. Oktober nachinstalliert; siehe den späteren Duo-Testnachweis. Extreme Fenstergrößen mit resizablem Simulator/Mirroring und reale Geräteabnahme bleiben offen. |

Besonders offen sind vertikale Systemleisten mit asymmetrischen Safe Areas,
extreme Fensterhöhen und Chat mit Tastatur sowie Falten während einer Sitzung.
Ein Quelltextaudit und iPhone-/iPad-Rotation ersetzen diese Laufzeitprüfungen
nicht. Die [Gerätecheckliste](IOS_DEVICE_ACCEPTANCE.de.md) enthält sie als
ausdrückliche Abnahmepunkte.

## Ergänzung: iPhone-Layout und Hintergrundaktualisierung

Das spätere [UI-/Refresh-Konzept](IOS_READER_REFRESH_UX.de.md) ersetzt das
frühere Lesen-Control und den vollständigen Artikelabruf beim Start. Native
Bereiche geben den fünf Startzeilen den ganzen Inhaltsbereich; Antippen öffnet
direkt den Reader. Eine dauerhafte Root-Tab-Leiste gibt jedem Bereich stabile
Split-Navigation; Modelle/Auswahl/Suche/Entwurf bleiben beim Spaltenwechsel
gemeinsam. Daten folgen der Sprache und behalten reine UTC-Tagesdaten.
Der Chat nutzt Safe Areas und eine Tastatur-Ausblendaktion ohne schwebende
Keyboard-Toolbar über Senden.

Fünfzehn neue synthetische Tests prüfen Refresh/Cache, Transport-Anfragebudgets,
Ablauf-Abbruch, Löschung aus anderer Szene, geschützte Kataloge und
Persistierungs-Rollback. Die UI-Suite ergänzt Eingabe/Tastatur und Entwurfserhalt
beim Bereichswechsel. Chat-Layouttests injizieren nur Verfügbarkeit, verlangen
die synthetische Debug-Demo und senden keine Modellfrage. Sprachgetrennte
Demo-Cache-Identitäten verhindern englische Testtitel im deutschen Lauf.

Der aktualisierte Quelltextaudit umfasst 32 Swift-Dateien, beide Plists und
Projektkonfigurationen. Kein produktiver Screen-/Orientierungs-/Geräteklassen-
Layoutentscheid, manuelle Safe-Area-Offsets oder ausgelassene Zielstellen.
Launchscreen, vier iPad-Orientierungen und fehlender Vollbild-Opt-out bleiben
geprüft. Echte Hintergrundplanung/Ablauf, gesperrter Cache und Duo-Resizing
bleiben Geräteabnahme, getrennt von injizierten/automatisierten Nachweisen.

Die endgültigen UI-Korrekturen wurden mit Bildern und Accessibility-Bäumen
geprüft: Root-Tab-Leiste mit eigenem Navigationskontext je Bereich, kein
übergeordneter Identifier überschreibt mehr das Eingabefeld, kompakte aktive
Suche vor Einstellungen schließen. Auf breitem iPad bleiben normale
Toolbar-Aktionen ohne diesen Schließen-Knopf sichtbar. Tests prüfen Controls
statt Geräteklassen anzunehmen. Suchabdeckung zählt auch noch nicht geladene
Markdown-Dateien (Regression: 5 indiziert von 31 im Bestand).

### Abschließende Prüfung der Ergänzung

Alle folgenden Läufe verwendeten Xcode 27.1/SDK 27.1, serielle Simulator-Tests
und Runtime iOS 27.0. Getestet wurde der **iPhone-17-Pro-Max-Simulator**, nicht
das reale Gerät des Maintainers. Es wurden nur synthetische Testinhalte geladen.

| Prüfung | Ergebnis / Umfang |
| --- | --- |
| iPhone 17 Pro Max: gesamte Suite | 47 Unit-/Integrationstests und alle 7 UI-Tests bestanden. |
| iPhone 17 Pro Max: abschließende Wiederholung | Nach Anpassung der Bestandsabdeckung und Tests erneut alle 47 Unit-/Integrationstests sowie 2 gezielte UI-Tests bestanden: tatsächliche Suchfilterung/Einstellungen und Reader → Chat → Tastatur/Entwurfserhalt. Die übrigen 5 UI-Fälle stammen aus dem vorherigen vollständigen Lauf. |
| iPad Pro 13 M5: gesamte abschließende Suite | 47 Unit-/Integrationstests und alle 7 UI-Tests mit den endgültigen Quellen bestanden. |
| Capture-/Python-Kernsuiten | 23 Node-Tests und 64 Python-Tests bestanden. „Push“-Ausgaben aus Mocks führten keinen Git-Push aus. |
| Vorgeschriebener generischer iOS-Simulator-Build | Ohne Signierung bestanden, einschließlich App und Share Extension; Release-Validator für das gebaute Bundle bestanden. |
| Generischer iOS-Geräte-Build, Release | Ohne Signierung bestanden; Bundle-Validator bestanden. Version 1.0.1/Build 10 bleiben unverändert. |
| Gebautes Bundle / Release-Binärdatei | Mindest-OS 17.0, Refresh-ID/`fetch`, Launchscreen und vier iPad-Orientierungen geprüft; kein Vollbild-Opt-out. Hintergrund-Capability nur in der App. Foundation Models bleibt schwach verknüpft; synthetische Debug-Schalter fehlen im Release. |

Lokale Result-Bundles: `/private/tmp/sourcebraid-redesign-check-pro-max.xcresult`,
`/private/tmp/sourcebraid-redesign-verified-pro-max.xcresult` und
`/private/tmp/sourcebraid-redesign-verified-ipad.xcresult`, jeweils mit `.log`.
Abschließende Build-Logs: `/private/tmp/sourcebraid-redesign-build-simulator.log`
und `/private/tmp/sourcebraid-redesign-build-device.log`. Synthetische Bilder
wurden auf Startliste mit fünf Zeilen, native Suche, deutsche Daten,
Chat-/Tastaturbedienung und breite Auswahl-/Reader-Spalten visuell geprüft.
Die temporären Artefakte bleiben außerhalb von Git; frühere fehlgeschlagene
Entwicklungsläufe sind keine erfolgreichen Nachweise. Beide Builds wurden
weder signiert noch installiert, archiviert oder hochgeladen.

### Neueste sieben und UI-Beispiele

Die anschließende Textanpassung benennt den Startbereich **Neueste** (Englisch
**Latest**) und zeigt höchstens sieben Beiträge. Der Erstabruf bei leerem Cache
versucht ebenfalls höchstens sieben Dateien; ein Cache-Neustart stellt weiterhin
keine GitHub-Anfrage. Vorschläge für Kurzbefehle entsprechen der Siebenerliste.
Das separate KI-Werkzeug für letzte Titel behält sein Fünf-Titel-Budget. Die
bestehenden Start-/Hintergrundtests prüfen jetzt sieben geladene/indizierte
Dateien von 31, dann getrennte Pakete mit 20 und vier; Cache-Wiederherstellung
prüft sieben sichtbare Beiträge von acht gespeicherten.

Der deutsche UI-Lauf prüft zusätzlich eine selektive Offline-Suche und eine
Chatfrage mit sichtbarer Quelle. `SOURCEBRAID_CHAT_EXAMPLE=1` benötigt die
synthetische Debug-Demo `SOURCEBRAID_DEMO=1` und injiziert eine feste, ausdrücklich
als Beispiel mit Testdaten bezeichnete Antwort. Er nutzt den echten Retrieval-/
Quellen-/UI-Pfad, ohne Sprachmodellaufruf oder privates Archiv. Bestehende
Tastaturtests injizieren weiterhin nur Verfügbarkeit. Die Beispielbilder belegen
Layout und Bedienung, keine echte Apple-Intelligence-Qualität.

Prüfung dieser Anpassung: Auf iPhone 17 Pro Max bestanden alle **47 Unit-/
Integrationstests und 7 UI-Tests**. Auf iPad Pro 13 M5 bestanden alle **47
Unit-/Integrationstests und 3 betroffene UI-Fälle**: Siebenerliste mit Reader/
Zurück, deutsche Such-/Chat-/Einstellungsbeispiele sowie Tastatur/Entwurfserhalt.
Runtime 27.0, SDK 27.1, serielle Ausführung. Bundles:
`/private/tmp/sourcebraid-recent-seven-pro-max.xcresult` und
`/private/tmp/sourcebraid-recent-seven-ipad.xcresult`, mit zugehörigen Logs.
Die exportierten synthetischen iPhone-Bilder wurden visuell geprüft; sieben
kurze Testzeilen passen bei Standardschrift. Längere Titel, größere Schrift
oder kleinere Fenster können regulär scrollen.

Vorgeschriebener generischer Simulator-Build und Geräte-Release-Build ohne
Signierung bestanden; beide gebauten Bundles bestehen den Validator. Die
Release-Binärdatei enthält weder den neuen Beispielschalter/-adapter noch
bisherige Debug-Testinhalte. Version/Build unverändert. Build-Logs:
`/private/tmp/sourcebraid-recent-seven-build-simulator.log` und
`/private/tmp/sourcebraid-recent-seven-build-device.log`. Keine Signierung,
Installation, Archivierung, Commits, Pushes oder Uploads ausgeführt.

### App-Farben nach dem Vorbild der Website

Das [Farbkonzept](IOS_BRAND_APPEARANCE.de.md) ergänzt warme Papierflächen,
dunkelgrüne Schrift und einen Petrol-Akzent mit passenden Varianten für Dunkelmodus
und erhöhten Kontrast. Neueste, Suche, Chat, Einstellungen und Markdown-Reader
nutzen dieselbe Palette. Native Navigation, Schrift, Suche und Tastatur bleiben
erhalten. Die Chat-Eingabe erhält einen Rahmen in sekundärer Schriftfarbe,
bei Fokus im Akzent sowie eine zur Darstellung passende Beschriftung gefüllter
Aktionen; diese gilt auch für den Einstellungsbutton vor Archivkonfiguration.
Archiv-, Refresh- und KI-Verhalten ändern sich dadurch nicht.

Lokal geprüft mit Xcode 27.1/SDK 27.1 und Runtime iOS 27.0:

| Prüfung | Ergebnis / Umfang |
| --- | --- |
| iPhone-17-Pro-Max-Simulator: gesamte Suite | Alle 47 Unit-/Integrationstests und 7 UI-Tests bestanden. |
| iPhone: letzte Kontrastkorrekturen | Beide betroffenen UI-Tests erneut bestanden: deutsche Reader-/Einstellungs-/Such-/Chat-Beispiele im Hellmodus sowie Dunkelmodus mit vergrößerter Reader-Schrift. |
| iPad-Pro-13-M5-Simulator | Alle 47 Unit-/Integrationstests und 3 betroffene UI-Fälle bestanden: helle deutsche Beispiele, Dunkelmodus/große Schrift und Chat-Tastatur/Entwurfserhalt. |
| Vorgeschriebener generischer Simulator-Build | Ohne Signierung bestanden; Bundle-Validator bestanden. |
| Generischer Geräte-Release-Build | Ohne Signierung bestanden; Bundle-Validator bestanden. Version 1.0.1/Build 10 unverändert. |
| Release-Testinhalte | Demo-, Chat-Layout-/Beispielschalter sowie synthetische Testinhalte und Beispieladapter fehlen in der Release-Binärdatei. |

Result-Bundles: `/private/tmp/sourcebraid-brand-pro-max.xcresult`,
`/private/tmp/sourcebraid-brand-final-pro-max.xcresult` und
`/private/tmp/sourcebraid-brand-ipad.xcresult`, jeweils mit zugehörigem Log.
Abschließende Build-Logs: `/private/tmp/sourcebraid-brand-final-build-simulator.log`
und `/private/tmp/sourcebraid-brand-final-build-device.log`.

Exportierte synthetische Bilder wurden auf helle/dunkle Startzeilen, native
Suche, Reader-Inhalte, Einstellungsflächen und fokussierte Chat-Steuerelemente
mit Tastatur visuell geprüft. Ebenso geprüft: breite iPad-Reader-/Chat-Anordnung
und dunkler Reader mit größerer Schrift. Berechnete Text-/Aktionskontraste
bestehen; tatsächliche Systemdarstellung mit erhöhtem Kontrast, VoiceOver und
reale iPhone-/Duo-Tests bleiben Geräteabnahme. Die Chat-Beispielantworten sind
ausdrücklich Testdaten und kein Nachweis echter Modellqualität.

Bilder sowie Build-/Testartefakte bleiben außerhalb des Repositorys. Keine
Installation auf realen Geräten, Signierung, Archivierung, Commits, Pushes oder
Uploads ausgeführt.

### Schreibweise Neueste und integrierte Chat-Aktion

Der deutsche Bereich und Kurzbefehltitel heißen jetzt **Neueste**. Senden/
Stoppen sitzt innerhalb der gemeinsamen abgerundeten Eingabefläche, mit einem
eigenen Textbereich für bis zu fünf Zeilen. Tastatur-Ausblenden bleibt eine
separate Aktion neben dem fokussierten Feld. Reguläres unteres Padding steigt
von 10 auf 24 Punkte im vorhandenen Safe-Area-Inset; keine manuelle
Safe-Area-Verschiebung.

Auf iPhone-17-Pro-Max- und iPad-Pro-13-M5-Simulator bestanden jeweils alle
**47 Unit-/Integrationstests und 3 betroffenen UI-Tests**. Bestehende UI-Fälle
prüfen den deutschen Bereich, synthetische Frage/Antwort/Quelle, dreizeiligen
Entwurfserhalt nach Tastaturausblenden und Tabwechsel sowie bedienbares Senden/
Ausblenden bei geöffneter Tastatur im Dunkelmodus mit XXXL-Schrift. Exportierte
iPhone-/iPad-Bilder wurden auf eigenen Platz für Text/Aktion, zusätzlichen
Abstand und normale/vergrößerte Schrift visuell geprüft. Synthetische Beispiele
belegen weder echte Modellqualität noch reale Geräteabnahme.

Vorgeschriebener generischer Simulator-Build und generischer Geräte-Release-Build
ohne Signierung bestanden; beide gebauten Bundles bestehen den Validator.
Xcode 27.1/SDK 27.1, Runtime 27.0, serielle Tests, Version 1.0.1/Build 10
unverändert. Result-Bundles: `/private/tmp/sourcebraid-composer-pro-max.xcresult`
und `/private/tmp/sourcebraid-composer-ipad.xcresult`, jeweils mit Log. Build-Logs:
`/private/tmp/sourcebraid-composer-build-simulator.log` und
`/private/tmp/sourcebraid-composer-build-device.log`. Keine Commits, Pushes,
Signierung, Installation auf realen Geräten oder Uploads ausgeführt.

### Nativer iPhone-Duo-Simulator: 15. Oktober

Die arm64-Runtime iOS 27.1, Build `24A94232`, wurde mit Xcode 27.1 (`27A9275`)
installiert. Getestet wurde das native Ziel **iPhone Duo** mit der UDID
`8820032A-139A-41E1-A7B4-7F0AD0B47624`, seriell und ohne Signierung. Diese
Ergebnisse sind von allen bisherigen iPhone-/iPad-Läufen mit Runtime 27.0 getrennt.

Im ersten Lauf bestanden alle **47 Unit-/Integrationstests**. Vier von sieben
UI-Fällen scheiterten an Zurück-Abfragen, die eine NavigationBar als Container
voraussetzten. Der exportierte Accessibility-Baum zeigte den System-
`BackButton` in einer eigenen vertikalen Symbolleiste. Die Tests verlangen nun
genau ein erreichbares Element mit diesem beobachteten Identifier; auch
Schließen-Abfragen der Suche setzen den alten Container nicht mehr voraus.
Produktcode, Berechtigungen, Zugangsdaten und Archivregeln wurden bei diesem
Nachtrag nicht verändert. Der erste fehlgeschlagene UI-Lauf zählt nicht als Erfolg.

Mit den korrigierten Selektoren bestanden **alle sieben UI-Fälle**. Belegt sind
sieben erreichbare kurze Testzeilen, formatierter/roher Reader und Zurück,
deutsche/englische Suche und Einstellungen, deutsche synthetische Chat-Antwort
mit Quelle, mehrzeiliger Entwurfserhalt nach Tastaturausblenden und Tabwechsel,
erreichbares Senden/Ausblenden bei XXXL, interne Links und gerenderte native
PDF-Vorschau. Die Bilder wurden geprüft: Der aktive LCD-Bereich maß
**466 × 678 Punkte** (`1398 × 2034` Pixel), mit nativen vertikalen Systemleisten.
Die feste Beispielantwort bleibt als Testdaten bezeichnet; das echte KI-Modell
wurde damit nicht geprüft.

Wichtige Grenzen dieses nativen Laufs:

- Der Dunkelmodus-/Großschriftfall bestand seine Bedienungsprüfungen, die Bilder
  blieben jedoch trotz `XCUIDevice.appearance = .dark` hell. Auch ein separater
  dokumentierter Aufruf `simctl ui … appearance dark` war erfolgreich und die
  Abfrage meldete vor und nach einem synthetischen App-Start `dark`, während
  die App im Bild hell blieb. Der vorherige Zustand `light` wurde wiederhergestellt
  und geprüft. Tatsächlicher Duo-Dunkelmodus bleibt **offen**; eine Ursache in
  App oder Runtime ist nicht nachgewiesen.
- Der Rotationsfall bestand die Reader-Präsenzprüfungen, sein als Querformat
  benanntes Bild blieb aber hochkant mit `1398 × 2034` Pixeln. Tatsächliche
  Drehung und Zustandserhalt durch einen geänderten Duo-Bereich sind damit
  **nicht belegt**.
- Im ersten Lauf mit geschlossenem Display war die Aufnahme der inaktiven
  zweiten Anzeige schwarz. Der nachfolgende offene Lauf ergänzt echte
  zweispaltige Nachweise. Teilweise gefaltete Haltung und Zustandserhalt über
  Scharnierübergänge bleiben offen. Die Pose-Steuerung in Device Hub erfordert
  manuelle Bedienung; Rotation/Geometrie ersetzen keinen Scharnierübergang.
- Reales Duo, echte Apple Intelligence, Share-Extension-Bedienung, Mindest-OS
  und die übrige [Gerätematrix](IOS_DEVICE_ACCEPTANCE.de.md) bleiben offen.

Nachweise außerhalb von Git: `/private/tmp/sourcebraid-duo-20261015.xcresult`
(47 Unit-/Integrationserfolge; erste UI-Fehler),
`/private/tmp/sourcebraid-duo-final-20261015.xcresult` (7 UI-Erfolge), zugehörige
Logs/Bildverzeichnisse und `/private/tmp/sourcebraid-duo-appearance-20261015.txt`
für die unabhängige Darstellungsbeobachtung. Bildnamen mit „dark“ oder
„landscape“ beschreiben angeforderte Bedingungen, keine nachgewiesene
Darstellung/Haltung.

Die beiden betroffenen deutschen/englischen Reader-/Such-/Einstellungsabläufe
bestanden außerdem jeweils auf iPhone 17 Pro Max und iPad Pro 13 M5 (Runtime
27.0). Damit funktionieren die portablen Control-Abfragen weiterhin mit den
bisherigen Systemleisten. Result-Bundles:
`/private/tmp/sourcebraid-duo-controls-pro-max-20261015.xcresult` und
`/private/tmp/sourcebraid-duo-controls-ipad-20261015.xcresult`, mit zugehörigen Logs.

Auch vorgeschriebener generischer iOS-Simulator-Build und Prüfung des gebauten
Bundles bestanden ohne Signierung. Build-Log:
`/private/tmp/sourcebraid-duo-build-simulator-20261015.log`. Version 1.0.1/Build
10 unverändert. Keine Commits, Pushes, Distributionsarchive oder Uploads ausgeführt.

### Aufgeklappte Duo-Testbilder: 15. Oktober

Nachdem der Maintainer Duo in Device Hub manuell aufgeklappt hatte, bestätigte
`devicectl device info displays` die innere Anzeige `LCD-1` (Display 3) als aktiv
mit eingeschalteter Beleuchtung und die äußere Anzeige als inaktiv. Innen wurde
`landscapeRight` (`rot90`) gemeldet; die nativen Bilder messen **2853 × 2007
Pixel**. Damit ist das beobachtete offene Layout belegt, kein geprüfter
Rotationswechsel oder vollständiger Faltzyklus.

Der deutsche Reader-/Einstellungs-/Such-/Chat-Ablauf bestand **1/1 UI-Test** auf
dieser Anzeige. Native Bilder wurden visuell geprüft: alle sieben neuesten
Testzeilen neben dem Reader, Suchtreffer neben dem Reader mit Tastatur sowie
Chat neben dem ausgewählten Beitrag mit und ohne Tastatur. Die Inhalte sind
synthetisch; die feste Chat-Antwort ist ausdrücklich als Testdaten bezeichnet
und belegt keine echte Antwortgenerierung durch Apple Intelligence.

`XCUIApplication.screenshot()` lieferte bei aktivem Innendisplay schwarze Bilder.
Die verwendbaren Aufnahmen adressieren deshalb mit `simctl io … screenshot
--display=3` ausdrücklich Anzeige 3. Die vorübergehende Synchronisierung im
UI-Test wurde anschließend entfernt und der exakte vorherige Quelltext
wiederhergestellt. Dieser Bildnachtrag verändert keinen Produktcode.

Nachweise außerhalb von Git: `/private/tmp/sourcebraid-duo-open-native-20261015.xcresult`,
das zugehörige Log sowie `/private/tmp/sourcebraid-duo-open-native-20261015/` mit
sechs nativen Bildern, Displayzustand als JSON pro Aufnahme und Capture-Manifest.
Ausgelieferte Kopien heißen `duo-open-20261015-{reader,suche,chat,chat-tastatur}.png`
im lokalen Visualisierungsordner `sourcebraid-ui`. Vollständige Falt-/Wiederöffnungs-
übergänge, teilweise gefaltete Haltungen, Duo-Dunkelmodus, reale Hardware und
echte Modellqualität bleiben offen. Keine Commits, Pushes oder Uploads ausgeführt.

### Release-Vorprüfung 1.1.0: 15. Oktober

Nach Maintainer-Freigabe wurden App und Share Extension auf 1.1.0/Build 11
angehoben. Beide unsignierten Builds und Bundle-Validatoren bestanden. Auf dem
geöffneten nativen Duo (Runtime 27.1) bestanden alle 47 iOS-Unit-/Integrations-
und 7 UI-Tests; die dokumentierten Bild-/Darstellungs-/Rotationsgrenzen bleiben
unverändert. Kernprüfungen bestanden mit 23 Node-, 64 Python- und 33 MCP-Tests,
ebenso MCP-Build-Probelauf und reproduzierbare Submission-Bundle-Prüfung.
Nachweise: `/private/tmp/sourcebraid-release110-duo.xcresult` mit Log,
`/private/tmp/sourcebraid-release110-build-{simulator,device}.log` und zugehörige
Kern-/MCP-Logs. Geplant ist der iOS-Tag `ios-v1.1.0`; Chrome/Plugin/MCP bleiben
1.0.1. Der bestehende Versionsregel-Test erlaubt jetzt diesen unabhängigen
iOS-Release. Xcode Cloud 27.1 RC wurde geprüft; nächste Cloud-Buildnummer ist 11.
Diese lokalen Ergebnisse behaupten weder erfolgreichen Cloud-Upload noch eine
App-Store-Veröffentlichung.

## Nächster Abnahmeschritt

[Gerätecheckliste](IOS_DEVICE_ACCEPTANCE.de.md) lokal in Xcode und auf dem
iPhone abarbeiten; anschließend echte Duo-Übergänge prüfen. Offene Mindest-
OS-, KI-, Siri-/Kurzbefehls-, Accessibility- und Lastnachweise festhalten.
Für den Gerätestart Signing prüfen und in Xcode **Run** verwenden; der
unsignierte Build lässt sich nicht direkt auf dem iPhone installieren.
Die Veröffentlichung von 1.1.0 ist freigegeben; Cloud-Build- und
Distributionsergebnisse werden getrennt von diesen offenen Prüfungen erfasst.
