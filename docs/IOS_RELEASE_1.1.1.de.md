# SourceBraid für iOS 1.1.1

17. Oktober 2026 · [English](IOS_RELEASE_1.1.1.md)

## Release-Status

Der Maintainer hat das Pushen der aktuellen Änderungen, die Veröffentlichung
des iOS-spezifischen GitHub-Releases **`ios-v1.1.1`**, die Begleitung seines
Xcode-Cloud-Builds und die Einreichung der passenden App-Version zur
Apple-Prüfung freigegeben. Dieses Protokoll beschreibt den geprüften
Kandidaten. Die Freigabe allein belegt weder erfolgreiche Cloud-Archivierung
und Upload noch Prüfeinreichung oder App-Store-Veröffentlichung.

Der Kandidat für App und Share Extension ist **1.1.1/Build 13**. Build 12
scheiterte vor der Kompilierung, weil seine konfigurierte Xcode-27.1-RC-/macOS-
Umgebung nicht mehr verfügbar war. Build 13 ist für einen neuen Durchlauf mit
der unterstützten Xcode-27.1-Umgebung vorbereitet; ein erfolgreicher
Cloud-Durchlauf bleibt zu bestätigen.
**1.1.0/Build 11** ist die
vorherige, bereits veröffentlichte App-Store-Version. Ihr erfolgreicher
Cloud-Build belegt diesen Kandidaten nicht. Chrome-Erweiterung, Codex-Plugin
und gehosteter ChatGPT-MCP behalten ihre unabhängigen Release-Versionen.

## Änderungen

- Mehrere Beiträge lassen sich auf dem kompakten iPhone-Layout nacheinander
  öffnen. In 1.1.0 konnte der erste gewählte Beitrag erscheinen, während die
  nächste Auswahl nach Zurück dauerhaft lud. Der Reader behält jetzt seine
  Navigationsidentität, startet anhand von Dateipfad/-version, setzt
  beitragsspezifische Zustände zurück und verwirft veraltete Ergebnisse.
  Unterbrochene Abrufe bieten erneutes Versuchen; ungültiges UTF-8 zeigt einen
  Dateifehler mit GitHub-Fallback.
- Ein unterbrochener erster Archivabruf wird fortgesetzt, statt nur seinen
  ersten fertigen Beitrag anzuzeigen. Der Start ergänzt fehlende Plätze bis
  insgesamt sieben geladene/indexierte Beiträge. Die Abdeckung zeigt
  geladenen und vollständigen Bestand; **Übrige Beiträge laden** startet die
  ausdrückliche inkrementelle Aktualisierung. Fertiger Fortschritt bleibt
  nach Stopp sichtbar. Die Wiederherstellung kann keinen Cache erneut öffnen,
  der in einem anderen Fenster gerade entfernt wird.
- Die Apple-Intelligence-Diagnose unterscheidet ausgeschaltete Intelligence,
  ein noch nicht bereites Systemmodell, nicht unterstützte Sprache und
  ungeeignete Hardware mit konkreten Hilfeschritten. Geprüft wird beim Öffnen
  von Chat, bei der Rückkehr in den Vordergrund, vor der Generierung und auf
  Wunsch. Entwurf und Verlauf bleiben erhalten. Apples Einrichtungshilfe
  beschreibt die nächsten Schritte; SourceBraid kann weder den Systemmodell-
  Download erzwingen noch dessen Fortschritt anzeigen.
- Mermaid-Diagramme werden mit gebündeltem, fest versioniertem **Mermaid Tiny
  12.2.0** vollständig auf dem Gerät dargestellt. Gängige Fluss-, Sequenz-,
  Zustands-, Klassen-, ER- und Gantt-Syntax wird unterstützt. Fehlerhafte,
  nicht unterstützte oder zu große Diagramme behalten ihren Originalquelltext,
  ebenso Zeitüberschreitungen und die WebKit-Wiederherstellung. Auch nach
  erfolgreicher Vorschau bleibt der Quelltext erreichbar. Tiny enthält keine
  Mindmaps, Architekturdiagramme oder KaTeX; ELK-Layouts verwenden Dagre.
- Der Hauptbereich heißt jetzt **Recent** / **Zuletzt**. Die überholte Liste
  **Zuletzt gespeichert** entfällt aus den Einstellungen. Der Capture-Speicher
  der Share Extension bleibt unverändert.
- Erweiterte englische/deutsche App-Store-Texte und **22 native Produktbilder**:
  pro Sprache vier iPhone-, vier iPhone-Duo- und drei iPad-Bilder. Die neuen
  Bilder und Texte sind im Store-Entwurf 1.1.1 gespeichert und nach erneutem
  Laden geprüft. Alle Beispielbeiträge sind fiktiv; weder private Archive noch
  erzeugte KI-Antworten erscheinen darin.

## Kompatibilität und Datenschutz

Reader und Suche unterstützen weiterhin iOS/iPadOS ab 17. Chat benötigt
zusätzlich iOS/iPadOS ab 26, geeignete Hardware, aktivierte Apple Intelligence
und ein bereites Systemmodell in einer unterstützten Sprache. Die
Duo-Faltanpassung benötigt iOS 27.1. Reader und Suche bleiben ohne lokale KI
verfügbar.

Es gibt keine neuen GitHub-Berechtigungen, Zugangsdaten-Speicher,
Archivformatänderungen oder externen Diagrammdienste. Mermaid führt nur das
gebündelte Programm der App in einer isolierten WebKit-Umgebung aus.
Archivskripte, Diagrammlinks und eingebettete/externe Diagrammmedien bleiben
deaktiviert. Externe Artikelbilder benötigen weiterhin eine bewusste Freigabe
für den jeweiligen Beitrag. Tokens bleiben im Schlüsselbund; Reader und Suche
verwenden den vorhandenen geschützten, verwerfbaren Cache. Die Share Extension
behält ihre bisherigen Capture-Schreibzugriffe. Siehe [Datenschutz](../PRIVACY.md).

## Prüfung und Distributionsprotokoll

Der funktionale Kandidat besteht **58 Unit-/Integrationstests und 14 UI-Fälle**
auf Simulatoren mit iOS 27.1. Vorgeschriebener unsignierter iOS-Simulator-Build,
Quell-/Bundle-Validierung, Integritätsprüfung der gebündelten Ressourcen und
`git diff --check` bestehen. Die UI-Nachweise umfassen aufeinanderfolgende
Beitragsauswahl, unterschiedliche gerenderte/rohe Inhalte, Navigation über
Zuletzt/Suche, Erhalt des Chatentwurfs, Reader-Links/PDFs, englische/deutsche
Einstellungen und Store-Aufnahmen. Die echte WebKit-Mermaid-Prüfung besteht
auf iPhone 17 Pro und iPad Pro 13 Zoll; Produktaufnahmen auch im nativen
iPhone-Duo-Simulator. Der kontrollierte 1.1.0-Vergleich reproduziert den
Fehler nach dem ersten Öffnen und grenzt die äußere Reader-Identität als
Ursache ein. Umfang und lokale Nachweispfade stehen im
[Testprotokoll](IOS_IMPLEMENTATION_TESTING.de.md).

Diese Prüfungen belegen die funktionale Änderung vor der Distribution.
Das genaue versionierte Release-Bundle, Signierung, neue Xcode-Cloud-
Archivierung, Upload, App-Store-Verarbeitung und Prüfeinreichung werden jeweils
an ihren tatsächlichen Ergebnissen geprüft. Bei Vorbereitung dieses Protokolls
wird kein erfolgreicher neuer Cloud-Build oder eine Apple-Freigabe behauptet.
Der erfolgreiche historische **Build 11** bleibt getrennt.

Die Abnahme der korrigierten Navigation auf dem physischen iPhone, tatsächliche
Apple-Intelligence-Vorbereitung/Antwortqualität, Mindest-OS-Starts, physische
Duo-Faltwechsel und die übrige Accessibility-Matrix bleiben in der
[Gerätecheckliste](IOS_DEVICE_ACCEPTANCE.de.md) dokumentiert. Simulatoren und
Veröffentlichungsfreigabe ersetzen diese offenen Prüfungen nicht.
