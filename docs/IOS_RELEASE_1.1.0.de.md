# SourceBraid für iOS 1.1.0

15. Oktober 2026 · [English](IOS_RELEASE_1.1.0.md)

Der Maintainer hat diesen Release-Kandidaten nach eigenem Funktionstest zur
Veröffentlichung freigegeben. App und Share Extension verwenden
**1.1.0/Build 11**. Der geplante GitHub-Tag **`ios-v1.1.0`** gilt nur für iOS.
Chrome, Codex-Plugin und gehosteter MCP bleiben auf 1.0.1.

## Änderungen

- **Neueste** startet mit sieben aktuellen Beiträgen, lokalisierten Daten und
  der überarbeiteten SourceBraid-Farbgestaltung. Native Bereiche für Suche und
  Chat sowie Toolbar-Aktionen passen sich an iPhone, iPad und das breite
  Duo-Display an.
- Der lokale Markdown-Reader stellt Überschriften, Tabellen, Aufgaben, Code,
  lokale Bilder und Archivlinks dar. PDF-Anhänge öffnen in nativem Quick Look.
  Markdown-Quelltext, Teilen und GitHub-Fallback bleiben erreichbar.
- Heruntergeladene Beiträge und Volltextsuche funktionieren offline.
  Cache-Starts stellen den lokalen Katalog wieder her, ohne sämtliche Artikel
  erneut zu laden. Ein leerer Cache versucht höchstens sieben Artikeltexte;
  begrenzte Hintergrundpakete und manuelles Aktualisieren lesen Änderungen.
  Metadaten und Suchabdeckung können anfangs unvollständig sein. iOS bestimmt
  die Hintergrund-Ausführungszeit.
- Optionaler Apple-Intelligence-Chat beantwortet Fragen zum gewählten Beitrag
  oder zu indizierten Archivauszügen mit Quellenlinks, Streaming und Abbruch.
  Der Senden-Button liegt im Eingabefeld; über der Tab-Bar bleibt mehr Abstand.
- Schreibgeschützte App-Kurzbefehle suchen, zeigen aktuelle Beiträge und öffnen
  geladene Einträge. Die Einstellungen beschreiben URL-Inhalte aus jeder App.

## Kompatibilität und Datenschutz

Reader und Suche sind für iOS/iPadOS ab 17 ausgelegt. Chat benötigt zusätzlich
iOS/iPadOS ab 26, unterstützte Hardware, aktivierte Apple Intelligence und ein
verfügbares Systemmodell in einer unterstützten Sprache. Die Duo-Faltanpassung
benötigt iOS 27.1. Bei nicht verfügbarer KI bleiben Reader und Suche nutzbar.

Archivabrufe verwenden authentifizierte GET-Anfragen an GitHub; Zugangsdaten
bleiben im gemeinsamen Schlüsselbund. Downloads und der neu aufbaubare
Suchindex liegen in einem geschützten lokalen Cache ohne Backup. Chat nutzt
Apples Modell auf dem Gerät mit begrenzten Auszügen und Verlauf im
Arbeitsspeicher; es wird kein externer KI-Dienst oder Private Cloud Compute
aufgerufen. Externe Bilder werden erst nach bewusster Auswahl geladen.
Reader, Suche, Chat und Kurzbefehle ändern keine GitHub-Dateien; die Share
Extension behält ihre bisherigen Schreibzugriffe zum Speichern. Den gesamten
Datenfluss beschreiben die [Datenschutzhinweise](../PRIVACY.md).

## Prüfung und Distributionsstatus

Nach der Versionsanhebung bestanden auf dem geöffneten nativen Duo **47 Unit-/
Integrationstests und alle 7 UI-Fälle** mit Runtime 27.1. Vorgeschriebener
unsignierter Simulator-Build und unsignierter Geräte-Release-Build bestanden;
beide gebauten Bundles bestehen den iOS-Validator mit **1.1.0/Build 11**.
Die Release-Binärdatei enthält keine Debug-Demo-/Beispielmarker. Kernprüfungen
bestanden mit **23 Node-**, **64 Python-** und **33 ChatGPT-MCP-Tests**. Auch
MCP-Deployment-Probelauf und reproduzierbare Submission-Bundle-Prüfung bestanden
ohne Deployment. Dieses separate Bundle bleibt auf Version 1.0.1.

Lokale Nachweise liegen außerhalb von Git: `/private/tmp/sourcebraid-release110-duo.xcresult`
mit Log, `/private/tmp/sourcebraid-release110-build-simulator.log`,
`/private/tmp/sourcebraid-release110-build-device.log` sowie die zugehörigen
Kern-/MCP-Logs. Grenzen der synthetischen Bilder und der KI-Nachweise bleiben
im [Testprotokoll](IOS_IMPLEMENTATION_TESTING.de.md) festgehalten.

Der Xcode-Cloud-Workflow wurde mit **Xcode 27.1 RC (27A9275)** und automatischem
Start bei `ios`-Änderungen auf `main` geprüft. Die nächste Buildnummer wurde auf
**11** gesetzt. Cloud-Archivierung, Upload und App-Store-Verarbeitung werden
getrennt von dieser lokalen Vorprüfung verfolgt; dieses Dokument behauptet
deren Erfolg nicht. Der iOS-Tag erhält die unabhängige Versionsregel für
Submission-Bundles unter `v*`.

Mindest-OS-Starts, vollständige Duo-Falt-/Wiederöffnungszyklen und teilweise
gefaltete Haltungen, Duo-Dunkelmodus, reale Duo-Hardware, echte Modellqualität
und die übrige Accessibility-/Gerätematrix behalten ihren dokumentierten
offenen Status. Der Funktionstest des Maintainers belegt nicht jede
Matrixbedingung. Siehe [Testprotokoll](IOS_IMPLEMENTATION_TESTING.de.md) und
[Gerätecheckliste](IOS_DEVICE_ACCEPTANCE.de.md).
