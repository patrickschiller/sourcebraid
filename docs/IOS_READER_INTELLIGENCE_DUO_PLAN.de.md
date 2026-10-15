# SourceBraid: iOS-Reader, Apple Intelligence und iPhone Duo

**SourceBraid — Weave the web into Markdown.**

Stand: **12. Oktober 2026** · Status: **Konzept freigegeben; lokale Umsetzung, Geräteabnahme offen**
· [English version](IOS_READER_INTELLIGENCE_DUO_PLAN.md)

Dieses Konzept plant die Erweiterung der Konfigurations-App zu einem
Archiv-Reader mit optionalem KI-Chat. Es implementiert keine Funktionen und
ändert keine Zusagen für die aktuelle Plugin-Veröffentlichung. Die Module
M00–M10 werden einzeln, in dieser Reihenfolge, umgesetzt und abgenommen.

## Freigegebene lokale Umsetzung

Der Maintainer hat die Modulreihenfolge freigegeben und intensive lokale Xcode-
und Gerätetests verlangt. Keine Commits oder Veröffentlichung vor abschließender
Freigabe. Der aktuelle [Umsetzungs-/Teststand](IOS_IMPLEMENTATION_TESTING.de.md)
und die [Gerätecheckliste](IOS_DEVICE_ACCEPTANCE.de.md) ergänzen dieses Konzept;
die nachfolgend beschriebenen Abnahmekriterien bleiben verbindlich.

## 1. Ziel und verbindliche Produktentscheidungen

1. Auf iPhone und iPad lassen sich die Markdown-Dateien des konfigurierten
   GitHub-Archivs korrekt lesen, einschließlich archivierter Bilder und
   nachvollziehbarer Herkunft. Eine geeignete Apple-Systemdarstellung hat
   Vorrang; ihre tatsächliche Markdown-Unterstützung wird zuerst geprüft.
2. Auf unterstützten Geräten beantwortet ein optionaler Chat Fragen zu einem
   Beitrag oder zum Archiv und verlinkt die verwendeten Belege. Der erste
   Ausbau verwendet ausdrücklich Apples **lokales** Systemmodell.
3. Auf dem geöffneten iPhone Duo stehen links die letzten fünf Beiträge und
   der Chat, rechts der ausgewählte Beitrag. Die zugeklappte Hauptansicht
   zeigt die Auswahl und den Chat. Auswahl und Leseposition bleiben erhalten.
4. GitHub-Markdown und Git-Historie bleiben maßgeblich. Katalog, Suchindex,
   Vorschaudateien und Antworten sind daraus abgeleitet; KI-Ergebnisse werden
   nicht automatisch zu Archivinhalt oder Quellenmetadaten.
5. Lesen und Suchen funktionieren ohne Apple Intelligence. Das bestehende
   Deployment-Ziel iOS/iPadOS 17 bleibt zunächst erhalten. Neuere Funktionen
   erhalten getrennte SDK- und Laufzeitprüfungen.

Geplanter Umfang: Lesen, Archivnavigation, lokale Suche, belegter Chat und
gezielte Systemaktionen. Bearbeiten, Löschen per KI, automatische Änderungen
an Markdown/Index-Shards, Cloud-KI, ein eigener MCP-Server in der App und
Android gehören nicht zu diesem Ausbau. Die Share Extension bleibt der
bestehende Weg zum Speichern neuer Inhalte.

## 2. Ausgangslage im Repository

| Baustein | Vorhanden | Konsequenz |
| --- | --- | --- |
| [ContentView](../ios/SourceBraid/App/ContentView.swift), [SettingsViewModel](../ios/SourceBraid/App/SettingsViewModel.swift) | Einstellungsformular und lokale Erfassungsliste | Einstellungen in einen eigenen Bereich verschieben; Reader-Zustand separat aufbauen. |
| [GitHubClient](../ios/SourceBraid/Shared/GitHubClient.swift) | Verbindungstest, Schreiben und privates Lesen einzelner Dateien | Leseschnittstelle mit vollständigem Dateikatalog und konsistenten Git-Snapshots ergänzen. |
| [RecentCaptureStore](../ios/SourceBraid/Shared/RecentCaptureStore.swift) | Maximal 20 lokale Share-Extension-Erfassungen ohne Repository-Namensraum | Kein Beleg für die letzten fünf Beiträge des gesamten Archivs. |
| [ClipBuilder](../ios/SourceBraid/Shared/ClipBuilder.swift) | Markdown, Frontmatter, relative Assets, URL-Hash-Shards; Indexmodell nur `Encodable` | Eigenes tolerantes Lesemodell; bestehendes Schreibformat erhalten. |
| [Xcode-Projekt](../ios/SourceBraid.xcodeproj/project.pbxproj) | iOS 17, iPhone und iPad, bestehendes XCTest-Target | Reader auf beiden Gerätefamilien; KI nur im App-Target, nicht in der Share Extension. |
| [Lokales Plugin](../codex-plugin/sourcebraid/scripts/sourcebraid.py), [ChatGPT-Dienst](../chatgpt-mcp/src/archive.mjs) | Suche/Abruf und abgeleitete Indizes mit jeweils eigenen Grenzen | Fachliche Such-/Abrufverträge übernehmen, keinen Server oder Python-Prozess auf iOS benötigen. |

Die bestehenden Plugin-Listen sind keine Vorlage für eine exakte Chronologie:
Der lokale Parser bevorzugt zum Teil Tagesdaten vor `captured_at`; der
gehostete Dienst listet nach Pfad und begrenzt seinen Fallback-Scan. Der neue
Reader definiert seine Sortierung und Vollständigkeit ausdrücklich.

## 3. Verifizierte Plattformbasis und offene Nachweise

### Markdown

Apple dokumentiert Quick Look für verschiedene Dateitypen einschließlich
Text, garantiert aber keinen vollständigen Markdown-/GFM-Reader.
`QLPreviewController.canPreview` bestätigt nur eine mögliche Vorschau.
Deshalb ist Quick Look erst nach bestandenem Darstellungstest als Hauptreader
geeignet. [Quick Look](https://developer.apple.com/documentation/quicklook/),
[canPreview](https://developer.apple.com/documentation/quicklook/qlpreviewcontroller/canpreview(_:))

SwiftUI `Text` unterstützt keine vollständige Markdown-Blockdarstellung, etwa
Tabellen und Codeblöcke. `AttributedString` bietet Parsing, aber keinen
fertigen Dokumentviewer. Auch das `MarkdownViewer`-Beispiel zu
`ReadableDocument` verweist auf einen eigenen `MarkdownView`.
[Text](https://developer.apple.com/documentation/swiftui/text/init(_:tableName:bundle:comment:)),
[Parsing](https://developer.apple.com/documentation/foundation/attributedstring/markdownparsingoptions/interpretedsyntax-swift.enum),
[ReadableDocument](https://developer.apple.com/documentation/swiftui/readabledocument)

**Entscheidung:** M00 prüft den nativen Weg. Besteht er die Pflichtfälle nicht,
implementiert M03 einen lokalen Markdown-Renderer hinter derselben
Schnittstelle. Vorgesehener Ersatz ist ein AST-basierter Parser mit sicher
erzeugtem HTML und gebündeltem CSS in `WKWebView`. Das offizielle Projekt
[Swift Markdown](https://github.com/swiftlang/swift-markdown) ist ein
Parserkandidat; Version, Paketumfang und
[Lizenz](https://github.com/swiftlang/swift-markdown/blob/main/LICENSE.txt)
werden vor Aufnahme geprüft und dokumentiert. Es ist keine mit iOS gelieferte
Viewer-Komponente. Kein entfernter Renderingdienst ist vorgesehen.

### Apple Intelligence

Foundation Models ist ab iOS/iPadOS 26 die Basis für den optionalen Chat.
Geplant ist `SystemLanguageModel.default`, mit Prüfung von `availability`
und unterstützter Sprache. Die aktuellen Framework-Dokumente umfassen auch
weitere Modellwege; dieses Konzept wählt bewusst ausschließlich den lokalen
Weg. [Foundation Models](https://developer.apple.com/documentation/foundationmodels),
[SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)

Ein Betriebssystem-Check allein genügt nicht: Geräteeignung, Aktivierung,
Modellbereitschaft und Sprache müssen berücksichtigt werden. Die App baut
eine eigene SwiftUI-Chatoberfläche; ein allgemein einbettbares, vollständiges
Apple-Intelligence-Chat-Control wird nicht als vorhandene API vorausgesetzt.
App Intents bilden einen separaten Systemzugang und ersetzen diesen Chat
nicht. Insbesondere verspricht das Reader-Schema derzeit nur Shortcuts,
nicht automatisch Siri-/Apple-Intelligence-Entdeckung.
[Verfügbarkeit](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.property),
[Reader-Schema](https://developer.apple.com/documentation/appintents/app-schema-domain-reader)

### iPhone Duo

Apple beschreibt das Gerät und den vollständigen Bildschirmzugang mit
Xcode/iOS SDK 27.1. Standardnavigation, Size Classes und asymmetrische Safe
Areas bilden die Grundlage. [Geräteübersicht](https://developer.apple.com/iphone-duo/),
[Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/)

Für besondere Faltzustände stehen unter anderem Reserved Regions und
Arrangement-APIs zur Verfügung. Ein Arrangement stellt keine Navigation
bereit. Die primäre Wahl für SourceBraid bleibt `NavigationSplitView`;
zusätzliche APIs werden nur bei nachgewiesenem Bedarf eingesetzt.
[Adaptive Layouts](https://developer.apple.com/videos/play/tech-talks/111463/)

Bei der Konzeptprüfung war lokal Xcode 27.0 installiert; die aktive
Entwicklerauswahl verwies auf Command Line Tools. Ein explizites
`DEVELOPER_DIR` konnte Xcode erreichen. Die Duo-spezifischen SDK-27.1-Tests
sind noch nicht durchgeführt. M00 klärt geeignete Toolchain, Simulatoren,
Geräte und die für eine spätere Veröffentlichung akzeptierte Xcode-Version.
SDK-Version und Mindestbetriebssystem werden getrennt behandelt.

## 4. Bedienung und Zustände

### Breite Ansicht: iPad und geöffnetes Duo

```text
┌───────────────────────────────────┬──────────────────────────────────────┐
│ SourceBraid        Einstellungen  │ Beitragstitel                        │
│ Letzte 5 · Synchronisierungsstand │ Quelle · Erfasst · Verarbeitungsart  │
│ 1  Beitrag                        │                                      │
│ 2  Beitrag                        │ Formatierter Markdown-Inhalt         │
│ 3  Beitrag                        │ mit Bildern, Tabellen und Links      │
│ 4  Beitrag                        │                                      │
│ 5  Beitrag                        │                                      │
│ Alle Beiträge / Suche             │                                      │
├───────────────────────────────────┤                                      │
│ Archiv fragen                     │                                      │
│ Bereich: Dieser Beitrag / Archiv  │                                      │
│ Verlauf und anklickbare Belege    │                                      │
│ Nachricht …              Senden   │                                      │
└───────────────────────────────────┴──────────────────────────────────────┘
```

Linke Liste und Chatverlauf scrollen unabhängig; der Eingabebereich bleibt
mit geöffneter Tastatur erreichbar. Fünf Beiträge bedeutet fünf auswählbare
Einträge, nicht fünf erzwungen sichtbare Zeilen bei jeder Schriftgröße.
Spaltenbreiten folgen verfügbarer Fensterfläche, Mindestlesebreite und
Accessibility; kein hartes 50:50-Verhältnis. Ohne Auswahl zeigt die rechte
Seite eine Aufforderung, einen Beitrag zu wählen.

### Kompakte Ansicht und Übergänge

- Die zugeklappte Duo-Hauptansicht zeigt die letzten fünf Beiträge und den
  Chat. Antippen einer Zeile wählt den Beitrag und den möglichen Chatkontext,
  öffnet aber nicht automatisch die Detailspalte.
- Beim Zuklappen kehrt die Navigation ausdrücklich zur Hauptansicht zurück,
  auch wenn zuvor der Reader aktiv war. Aufklappen stellt den ausgewählten
  Beitrag rechts einschließlich Leseposition wieder her.
- Explizites „Lesen“ bzw. ein Quellenbeleg darf eine separate Detailansicht
  öffnen; „Zurück“ führt wieder zu Auswahl und Chat. Damit bleiben Inhalte
  auch auf normalen iPhones und in schmalen iPad-Fenstern lesbar. Die
  Anforderung „nur Auswahl und Chat“ gilt für die zugeklappte Hauptansicht.
- Textentwurf, Chatverlauf, Auswahl, Quellenbelege und laufende Antwort gehen
  bei einem Layoutwechsel nicht verloren. Layoutänderung startet keine zweite
  Anfrage. Eine suspendierte App darf eine Antwort sauber abbrechen und
  „Fortsetzen/Erneut versuchen“ anbieten; keine Hintergrundgarantie.
- Layoutentscheidungen verwenden Size Classes, lokale Fenstergeometrie und
  ggf. reservierte Regionen. Kein Gerätemodellvergleich, `UIScreen.main`,
  Orientierungsheuristik oder Scharnierwinkel als Spalten-Breakpoint.
  Ein dokumentierter Schließen-Callback darf die Navigationspolitik steuern;
  der kompakte Fallback muss auch ohne diesen Callback funktionieren.
- KI nicht verfügbar: verständlicher Status an Stelle der aktiven
  Chatbedienung, weiter benutzbare Liste, Suche und Reader. Keine leere,
  scheinbar funktionsfähige Chatbox.

Technisch liegen dauerhafter Sitzungszustand und laufende Aufgaben außerhalb
der wechselnden View-Hierarchie. Auswahl und Leseposition dürfen lokal
wiederhergestellt werden; Chatverlauf und Entwurf bleiben zunächst nur im
Speicher. Repositorywechsel beendet den bisherigen Chatkontext. Mehrere
Fenster erhalten getrennte UI-/Chatsitzungen; ein gemeinsam verwendeter
Cache braucht serialisierte Schreibzugriffe.

## 5. Daten-, Such- und Sicherheitsverträge

### Archivzugriff und letzte fünf Beiträge

`ArchiveIdentity` umfasst GitHub-Host, Owner, Repository, Branch und
normalisierten Root-Pfad. `ClipID` ergänzt den repositoryrelativen Pfad;
ein bestimmter Inhalt wird zusätzlich durch Commit- und Blob-SHA bezeichnet.
Die erste Umsetzung unterstützt weiterhin den vorhandenen Host GitHub.com.

Ein Synchronisierungslauf löst den Branch einmal zu einem Commit auf und liest
Dateien/Assets dieses Snapshots. Der Katalog enumeriert alle Markdown-Dateien
unter dem konfigurierten Root. JSONL-Shards beschleunigen den Start; Pfade und
Metadaten werden mit den maßgeblichen Markdown-Dateien abgeglichen, auch wenn
ein Shard fehlt, veraltet ist oder eine Zeile beschädigt ist. Gelöschte Dateien
verschwinden nach vollständiger Bestandsprüfung; bei abgebrochenem Scan gibt
es keine spekulativen Löschungen aus dem Cache.

Die Contents-API ist keine unbegrenzt paginierbare Verzeichnisliste. Für große
Bestände ist die Trees-API vorgesehen; abgeschnittene rekursive Ergebnisse
werden durch Teilbaumabfragen vervollständigt. Abbruch, Größenlimit oder
API-Limit wird als unvollständiger Stand angezeigt.
[GitHub Contents](https://docs.github.com/en/rest/repos/contents),
[GitHub Trees](https://docs.github.com/en/rest/git/trees)

Sortiervertrag:

1. Neueste zuerst: Gültiges `captured_at` mit Zeitzone wird als UTC-Zeitpunkt
   absteigend verglichen.
2. Ohne gültigen Zeitstempel gilt `capture_date`, danach ein im bekannten
   Legacy-Format als Erfassungsdatum definiertes Tagesdatum, zuletzt ein
   gültiges Datum aus dem Archivpfad. Tageswerte erhalten ausschließlich für
   die Sortierung 00:00 UTC, unabhängig von der Gerätezeitzone. Herkunft und
   Tagesgenauigkeit bleiben sichtbar; dies ist keine behauptete Uhrzeit.
3. Erst wenn alle Datumsquellen fehlen, gilt ein Beitrag als undatiert und
   folgt den datierten. Gleiche Sortierwerte werden anhand des normalisierten
   Pfads lexikografisch aufsteigend aufgelöst, ohne sprachabhängige Sortierung.
4. Publikationsdatum, Commitdatum und lokale Gerätehistorie ersetzen niemals
   stillschweigend den Erfassungszeitpunkt. Nicht vorhandene Titel erscheinen
   als Dateiname mit entsprechender Kennzeichnung.
5. „Letzte 5“ meint die ersten fünf vorhandenen Markdown-Beiträge dieses
   Archivs, unabhängig vom Erfassungsgerät. Bei weniger Beiträgen alle zeigen.
   Während des Erstabgleichs „Bis zu 5 zuletzt geladene Beiträge“ mit Fortschritt
   anzeigen; erst nach vollständigem Metadatenabgleich globale Aktualität
   beanspruchen. Offline gilt „Stand vom …“.

PDF-Platzhalter sind sichtbare Beiträge mit Konvertierungsstatus; ein später
geänderter Blob aktualisiert den Reader und Suchindex. Angehängte PDFs können
ergänzend in Quick Look geöffnet werden. Für KI zählt nur vorhandener
extrahierter Text; eine ausstehende Konvertierung wird nicht als gelesener
PDF-Inhalt behandelt.

### Lokale Speicherung und Suche

`ArchiveCache` speichert verifizierte Metadaten und nach Bedarf Markdown und
Assets. `ArchiveSearchIndex` ist ein neu aufbaubarer SQLite-FTS-Index für Titel,
Tags, Quelle und Text; kein Zugriff auf die Desktop-Datenbank ist erforderlich.
Schema-Version, Archividentität, Blob-SHA und Abdeckungsstatus sind getrennt
von den Archivformaten. Kein neues Frontmatter-Feld oder neues Shardformat.

Katalogvollständigkeit, heruntergeladene Inhalte und Suchabdeckung sind
unterschiedliche Zustände. Ein vollständiger Pfadkatalog bedeutet noch keine
vollständige Volltextsuche. „Archiv durchsuchen“ zeigt die Zahl der indizierten
gegenüber bekannten Beiträge; „keine Treffer im geladenen Teil“ behauptet
nicht, dass das ganze Archiv keine Antwort enthält.

Startbudgets als zu überprüfende Produktvorgabe: 5 MiB je Markdown-Datei,
20 MiB je Asset, 250 MiB gesamter persistenter Cache einschließlich Suchindex.
Größere Dateien erhalten eine explizite Limitanzeige und einen GitHub-Link;
kein stilles Abschneiden. Downloads sind abbrechbar und gedrosselt.
ETags/Blob-SHAs vermeiden unnötige Übertragungen; Rate-Limit-/Retry-Header
steuern Wiederholungen. M00 misst diese Vorgaben an synthetischen Archiven.
[GitHub API-Verhalten](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api)

Cache liegt im geschützten App-Container, ist von Backups ausgeschlossen und
hat eine Größen-/Verdrängungsstrategie. „Lokale Daten entfernen“ löscht Cache,
Suchindex und Vorschauen, niemals GitHub-Dateien. Abmelden entfernt außerdem
Zugangsdaten und flüchtige Chats; ein Archivwechsel sperrt sofort alte
Ergebnisse und verwirft den alten Cache. Der ungetrennte bisherige
`RecentCaptureStore` wird beim Wechsel geleert bzw. künftig sauber pro
Archiv geführt. Bestehende Keychain-/App-Group-Grenzen bleiben erhalten.

### Rendering, Ressourcen und Herkunft

- YAML-Frontmatter getrennt vom Text darstellen. Parser akzeptiert bekannte
  Altformate und unbekannte optionale Felder; keine Objektkonstruktion aus
  YAML, keine Änderung der Originalbytes. Fehler erscheinen nachvollziehbar.
- Pflichtumfang: Überschriften, Absätze, Hervorhebungen, Listen, Tasklisten,
  Zitate, Codeblöcke, GFM-Tabellen, Links, archivierte Rasterbilder. Rohansicht
  und Kopieren bleiben verfügbar. Mathematik/Mermaid werden zunächst lesbar
  als Quelltext angezeigt; kein beliebiger Skript-Renderer.
- Relative Links und Assets werden relativ zur Markdown-Datei aufgelöst.
  Normalisierte Pfade müssen im erlaubten Archivbereich bleiben; Symlinks,
  Submodule, absolute Dateipfade und Traversal werden nicht verfolgt.
  Verlinkte Archivbeiträge öffnen den Reader, Quellenlinks extern nach Tippen.
  Dieser Vertrag gilt für jeden Renderer: externe Links nur über `https`/`http`,
  lokale/aktive oder beliebige App-Schemata wie `file`, `data` und `javascript`
  ablehnen. Protokollrelative URLs werden nicht als Archivpfade behandelt.
  Externe Ressourcen erhalten niemals GitHub-Authentifizierung.
- Externe Bilder laden standardmäßig nicht; ein bewusstes Nachladen erklärt
  den Drittanbieterzugriff. Keine entfernten Fonts, automatischen
  Quellenbesuche, Tracker oder automatisch geladenen SVG-/HTML-Aktivinhalte.
- Beim WebKit-Ersatz: AST-Whitelist, HTML-Escaping, JavaScript aus,
  nichtpersistenter WebKit-Datenspeicher, restriktive CSP sowie kontrollierter
  Ressourcen-Handler und Navigationsprüfung. Kein PAT in HTML, URLs, Logs
  oder JavaScript-Brücken. WebKit-Konfiguration allein ersetzt den Resolver
  und die Netzwerksperren nicht.
  [JavaScript](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript),
  [Datenspeicher](https://developer.apple.com/documentation/webkit/wkwebsitedatastore),
  [Ressourcen-Handler](https://developer.apple.com/documentation/webkit/wkurlschemehandler)

### KI-Vertrag

Die Oberfläche heißt beispielsweise „Archiv fragen“ mit Hinweis auf Apple
Intelligence. Sie bietet „Diesen Beitrag zusammenfassen“, freie Fragen,
Suche nach einem Thema und Vergleich ausgewählter Treffer. Ein sichtbarer
Bereichsschalter unterscheidet **Diesen Beitrag** und **Archiv**; der
Standardbereich ist der ausgewählte Beitrag. Ohne Auswahl wird kein
unsichtbarer Kontext angenommen.

Der Ablauf ist: Frage → lokale Suche/gezielter Abruf → begrenzte Textauszüge →
Systemmodell → Antwort mit überprüften Quellenverweisen. Dokumente werden
an Überschriften/Absatzgrenzen zerlegt. Abrufrangfolge und Ausschnittgrößen
werden mit festen Beispielen getestet. Der gesamte Archivinhalt wird nicht
in eine Sitzung eingefügt. Kontextbudget berücksichtigt Instruktionen,
Werkzeugschemas, Verlauf, Auszüge und Antwortreserve; lange Gespräche erhalten
eine neue begrenzte Sitzung mit erneutem Quellenabruf.

Apple nennt derzeit 4096 Tokens für eine lokale Sitzung. Die konkrete
Modellkapazität wird über die verfügbare API geprüft; `tokenCount(for:)`
setzt iOS/iPadOS 26.4 voraus. Auf 26.0–26.3 gelten konservative Grenzen plus
Fehlerbehandlung. Abschnittsweise Zusammenfassungen müssen ihre Abdeckung
anzeigen und Belege bis zur Originalquelle erhalten.
[Kontextfenster](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window),
[Tokenzählung](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/tokencount(for:))

`ArchiveAIService` erhält ausschließlich schmale, lesende Werkzeuge:

| Geplanter Vertrag | Ergebnis |
| --- | --- |
| `listRecent(limit <= 5)` | Verifizierte Einträge und Stand/Vollständigkeit |
| `searchArchive(query, scope, limit)` | Begrenzte Treffer, Ausschnitte und Suchabdeckung |
| `fetchClip(clipID, section, budget)` | Text im erlaubten Archiv, Snapshot und Beleg-IDs |

Das Modell erhält keine Zugangsdaten, beliebigen URLs, SQL-Ausführung,
Dateisystempfade oder Schreibwerkzeuge. `Tool`-Aufrufe werden unabhängig von
Modellausgaben validiert, begrenzt und abbrechbar ausgeführt.
[Foundation Models Tool](https://developer.apple.com/documentation/foundationmodels/tool)

Belege referenzieren `ClipID`, Blob-SHA und Abschnitt/Textbereich aus dem
tatsächlich gelieferten Kontext. Nur diese IDs werden zu anklickbaren
Quellenchips; erfundene IDs werden zurückgewiesen. Eine formale Belegprüfung
beweist noch nicht die inhaltliche Wahrheit: Ein Evaluationssatz prüft
zusätzlich, ob die Antwort durch den genannten Auszug gestützt wird.
Bei fehlenden Belegen, Teilindex, Ablehnung oder Kontextüberlauf erklärt die
App die Grenze und bietet Quelltext/Suche an.

Archivtext ist nicht vertrauenswürdig und darf Anweisungen an die KI
enthalten. Er wird als Quellenmaterial abgegrenzt; Werkzeuggrenzen erzwingen
den Lesezugriff auch dann, wenn Prompt-Abgrenzung versagt. Guardrails bleiben
aktiv. Keine automatische Websuche oder Weitergabe an ChatGPT, einen
SourceBraid-Server, Private Cloud Compute oder andere Modellanbieter.

| Laufzeitzustand | Verhalten |
| --- | --- |
| OS zu alt oder Gerät nicht geeignet | Reader/Suche voll nutzbar, KI begründet nicht verfügbar |
| Apple Intelligence ausgeschaltet | Aktivierungshinweis; kein automatischer Cloud-Ersatz |
| Modell noch nicht bereit | Erklärter Wartezustand und erneute Prüfung |
| Sprache/Region aktuell nicht unterstützt | Verständlicher Hinweis; keine erzwungene Systemsprachänderung |
| Modell bereit | Eingabe, Streaming, Stopp und Quellenlinks verfügbar |
| Laufzeitfehler, Ablehnung, zu großer Kontext | Entwurf erhalten, Fehler erklären, gezielt erneut versuchen |

Verfügbarkeit bei Aktivierung der App und vor einer Anfrage neu prüfen;
unbekannte künftige Zustände sicher behandeln. Aktuelle APIs wie Tokenzählung
haben eigene Versionsgrenzen; M00 dokumentiert die tatsächlich gewählte
SDK-/OS-Kombination, statt Beispiele verschiedener Versionen zu vermischen.
Offline-KI funktioniert nur bei bereitem lokalem Modell und lokal vorhandenen
Quellen. GitHub-Synchronisierung benötigt weiterhin Netzwerk.

## 6. Modulplan: jeweils ein eigenständig prüfbarer Arbeitsschritt

Jedes Modul startet erst nach Abnahme seiner Voraussetzung. Dateinamen neuer
Bausteine sind Zielstruktur, keine Behauptung bereits vorhandener Dateien.
Jeder Umsetzungs-PR führt Problem, Verhalten, Datenschutz-/Berechtigungseffekt
und tatsächlich ausgeführte Checks auf; Commits tragen DCO-Sign-off.

### M00 — Plattform- und Renderer-Nachweis

**Voraussetzung:** dieses Konzept. **Ergebnis:** dokumentierte Entscheidungen
mit synthetischen Testdateien, bevor Produktcode erweitert wird.

- Quick Look gegen alle M03-Pflichtfälle auf Mindest- und aktuellem OS testen;
  `canPreview`, Formatierung, private Assets und Quellenlinks getrennt prüfen.
- Native Option wählen, wenn alle Pflichtfälle bestehen; sonst lokalen
  Parser/WebKit-Weg samt Version, Lizenz und Integrationsaufwand festlegen.
- Foundation-Models-Minimalversuch auf geeignetem Gerät: Deutsch/Englisch,
  Verfügbarkeit, kurzer belegter Abruf, Streaming/Abbruch, Kontextgrenze.
- Xcode 27.1/Duo-Testumgebung und die konkret verfügbaren APIs prüfen;
  Speicher-/Downloadbudgets mit kleinen und großen synthetischen Archiven
  kalibrieren. Fehlende Hardware wird als offener Nachweis festgehalten.

**Abnahme:** Entscheidungsprotokoll mit Ergebnissen und begründetem Renderer;
kein unbewiesenes Versprechen eines nativen Voll-Viewers oder Systemchats.
Reader-Module können ohne KI-Testgerät fortgesetzt werden; M06/M07/M10 erhalten
dann ein ausdrücklich offenes Freigabekriterium.

### M01 — Domänenmodelle und lesender GitHub-Zugriff

**Voraussetzung:** M00. **Bausteine:** `ArchiveIdentity`, `ClipID`,
`ArchiveReadClient`, `ArchiveSnapshot`; vorhandene Konfiguration/Keychain.

- Abhängigkeiten injizierbar machen, lesende Schnittstelle von Capture-Writes
  trennen, Git-Commit fixieren, Trees und Blobs unter Root sicher lesen.
- URL-/Pfadvalidierung, Authentifizierung nur zum erlaubten GitHub-Endpunkt,
  Redirect-Prüfung, Größenlimits, Abbruch, Backoff und 401/403/404 unterscheiden.
- Keine höheren Tokenrechte. Capture nutzt weiter seine bisherigen
  Schreibrechte; Reader und KI können nur GET-Operationen anfordern.

**Abnahme:** Mock-Netzwerktests für Snapshot-Konsistenz, Branch/Root-Wechsel,
abgeschnittene Trees, große Verzeichnisse, Traversal, Redirects und Limits;
bestehender Share-Speicherablauf unverändert funktionsfähig.

### M02 — Archivkatalog, letzte fünf und Offline-Cache

**Voraussetzung:** M01. **Bausteine:** `ClipMetadataReader`, `ArchiveCatalog`,
`ArchiveCache`, tolerante Index-/Frontmatter-Lesemodelle.

- Shards als Starthilfe, maßgebliche Markdown-Metadaten und fehlende Einträge
  abgleichen; Sortier-/Vollständigkeitsvertrag aus Abschnitt 5 implementieren.
- Blob-basierte Aktualisierung, Offlinezustand, Fortschritt, Löschabgleich,
  Cachebegrenzung und Isolation bei Konfigurationswechsel umsetzen.
- Lokale Capture-Hinweise nur als vorläufig kennzeichnen, bis GitHub bestätigt.

**Abnahme:** Archiv mit Chrome-, iOS- und synthetischen Legacy-Einträgen liefert
dieselben fünf unabhängig vom Gerät; Tests für gleiche Tage, Zeitzonen,
fehlende Daten, ungültige Shards, leeres Archiv, Offline und PDF-Konvertierung.

### M03 — Markdown-Reader und kontrollierte Assets

**Voraussetzung:** M02 und Rendererentscheidung aus M00.
**Bausteine:** `MarkdownDocument`, `MarkdownRenderer`, `ArchiveAssetResolver`,
`ClipReaderView`, optional `SystemPreviewAdapter`.

- Frontmatter/Herkunft, Pflichtsyntax, Linknavigation, relative Bilder,
  Konvertierungsstatus, Rohtext und Leseposition umsetzen.
- Native Vorschau bzw. abgesicherten lokalen Renderer integrieren; alle
  Ressourcen durch denselben Archiv- und Snapshot-Vertrag auflösen.

**Abnahme:** Synthetische Darstellungsfixtures visuell auf iPhone/iPad prüfen;
zusätzlich dunkles Design, Dynamic Type, VoiceOver, lange Tabellen/Code,
kaputte Assets und fehlerhaftes Markdown. Netzwerktest bestätigt keine
ungewollten Drittanbieterabrufe oder Tokenweitergabe. Rohtext allein erfüllt
die Reader-Abnahme nicht.

### M04 — Archivoberfläche und adaptive Grundnavigation

**Voraussetzung:** M03. **Bausteine:** `ArchiveViewModel`, `LibrarySidebar`,
`ArchiveSplitView`, separater `SettingsView`, zentraler Sitzungszustand.

- Bisherige Einstellungen erreichbar erhalten; Startansicht mit letzten fünf,
  „Alle Beiträge“, Refresh und Reader erstellen. „Lokale Daten entfernen“
  und „Abmelden“ mit der in Abschnitt 5 definierten Wirkung ergänzen.
  Chatbereich zunächst als
  interner Platzhalter für M07, nicht als ausgelieferte leere Funktion.
- Breite Ansicht zweispaltig; kompakte Ansicht mit bewusster Detailnavigation.
  Zustände für Einrichtung, Laden, leer, Fehler und offline lokalisieren.

**Abnahme:** Auswahl, Rücknavigation, Wiederherstellung und Rotation auf iPhone
und iPad funktionieren; Fensterverkleinerung bewahrt Auswahl/Leseposition.
Dieser Stand ist als Reader ohne KI separat veröffentlichbar.

### M05 — Lokale Volltextsuche und Quellenabruf

**Voraussetzung:** M04. **Bausteine:** `ArchiveSearchIndex`, `ArchiveRetriever`,
`SourceExcerpt`; SQLite über eine geprüfte lokale Integration.

- Volltextindex aus geladenen Markdown-Dateien aufbauen, versionieren und
  nach Blobänderung aktualisieren; Löschungen und Neuaufbau unterstützen.
- Suche unabhängig von KI anbieten; Abschnitte, Ergebnislimits und
  Suchabdeckung liefern. Aktuellen Beitrag vollständig oder in Abschnitten
  abrufen; lange Quellen mit klarer Abschnittsauswahl behandeln.

**Abnahme:** Feste deutsche/englische Suchfälle finden erwartete Quellen;
Cacheverlust ist reparierbar. Teilindex, Cacheverdrängung, entfernte Beiträge
und Konfigurationswechsel liefern keine irreführende Vollständigkeit.

### M06 — Apple-Intelligence-Verfügbarkeit und Sitzungsadapter

**Voraussetzung:** M05. **Bausteine:** `IntelligenceAvailability`,
`ArchiveAIService`-Protokoll, Foundation-Models-Adapter und Test-Doubles.

- API-/Laufzeitgrenzen isolieren, Statusmatrix implementieren und das lokale
  Modell explizit wählen. Reader darf ohne das Framework-Modell funktionieren.
- Lebensdauer, Abbruch, Streaming, Fehler und Kontextbudget zentral verwalten;
  keine Generierung durch View-Neuaufbau oder gleichzeitig konkurrierende
  Anfragen in derselben Modellsitzung.

**Abnahme:** Alle Statuszustände simuliert; echte Verfügbarkeits-/Sprachprüfung
auf unterstützter Hardware protokolliert. Auf iOS 17 und ungeeigneten Geräten
startet die App mit nutzbarem Reader; kein unbeabsichtigter Cloud-Aufruf.

### M07 — Archivchat mit überprüfbaren Quellen

**Voraussetzung:** M06. **Bausteine:** `ArchiveChatViewModel`, `ArchiveChatView`,
lesende Modellwerkzeuge, `CitationValidator`.

- Nachrichteneingabe, Verlauf, Bereichswahl, Streaming, Stopp und Fehlerfälle
  in der linken/kompakten Hauptansicht einbauen.
- Retrieval aus M05 an Werkzeuge anbinden; Beleg-IDs erzeugen und prüfen;
  Quellenchips öffnen den Reader am passenden Abschnitt/Snapshot.
- Begrenzten Kontext, Sitzungserneuerung und Prompt-Injection-Abwehr testen.
  Auswahlwechsel verändert bereits laufende Fragen nicht rückwirkend.

**Abnahme:** Synthetischer DE/EN-Evaluationssatz umfasst Zusammenfassung,
Faktfrage, Vergleich, fehlende Antwort, langen Artikel, Teilindex und
eingeschleuste Anweisungen. Keine ungültigen Quellenlinks, Schreiboperationen
oder archivübergreifenden Antworten; festgestellte Qualitätsgrenzen sind vor
Freigabe dokumentiert. Jede Layoutänderung erhält den Chat ohne Doppelanfrage.

### M08 — App Intents und gezielte Systemintegration

**Voraussetzung:** M07. **Bausteine:** `ArchiveClipEntity`, Abfragen und
Aktionen zum Suchen/Öffnen/Anzeigen letzter Beiträge; App Shortcuts.

- Dokumentierte Schemas auf semantische Eignung und tatsächliche
  Siri-/Shortcuts-Unterstützung prüfen. Kandidaten sind `.system.open` und
  `.system.searchInApp`. Reader-/Files-Schemas sind aktuell Shortcuts-only
  und keine Garantie für frei formulierte Siri-Archivfragen.
- Intents nutzen denselben lesenden Dienst, begrenzte Ergebnisse und klare
  Fehler bei gesperrtem Gerät, fehlender Anmeldung oder Offline-Lücke.
- Private Inhalte erst nach Entsperren/erforderlicher Authentifizierung
  bereitstellen. Kein automatischer Volltext-Export an Spotlight; eine
  spätere Spotlight-Indexierung wäre ein eigener Datenschutzentscheid.

Die Intent-Authentifizierung wird ausdrücklich gesetzt; der dokumentierte
Standard `alwaysAllowed` genügt nicht für private Archivinhalte. Ein
optionales Frage-Intent darf nur den gleichen lokalen, belegten Chatdienst
aufrufen, wenn Sprache, Gerät und Ausführungskontext es unterstützen.
[System-Schemas](https://developer.apple.com/documentation/appintents/app-schema-domain-system-and-in-app-search),
[Files-Schema](https://developer.apple.com/documentation/appintents/app-schema-domain-files),
[Intent-Authentifizierung](https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy)

**Abnahme:** Such-/Öffnungsaktionen in Shortcuts und unterstützten
Systemoberflächen getestet, Widerruf/Archivwechsel berücksichtigt. Nur
nachgewiesene Siri-Funktionen dokumentieren. Dieser Systemzugang kann separat
ausgeliefert werden; der funktionierende In-App-Chat bleibt unabhängig.
[App-Intents-Integration](https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence)

### M09 — iPhone-Duo-Anpassung und Übergangstests

**Voraussetzung:** M08; M04/M07 liefern Navigation und Chat, M00 die Toolchain.
**Bausteine:** bestehende adaptive Views, gezielte SDK-27.1-Erweiterungen.

- Geöffnet links letzte fünf + Chat und rechts Reader; geschlossen primäre
  Auswahl-/Chatansicht nach Abschnitt 4 ausdrücklich sicherstellen.
- Standardcontainer zuerst prüfen. Bei Bedarf reservierte Bereiche für
  eigene Controls berücksichtigen; keine parallelen Layoutsysteme ohne Bedarf.
- App-Zustand über Falten, Rotation, Tastatur und Szene erhalten; seitliche
  Systemleisten und asymmetrische Abstände prüfen. Layout nicht an ein
  bestimmtes Gerätemodell oder feste Pixelbreiten koppeln.
- Keine zweite Außenbildschirm-Szene verlangen: Die gewünschte Oberfläche
  passt sich innerhalb der aktiven App-Szene an. Kameraspezifische
  Mehrdisplay-APIs werden dafür nicht benötigt.

**Abnahme:** Device-Hub-Matrix für offen, geschlossen, teilweise gefaltet,
beide Ausrichtungen, Split View auf beiden Seiten, Tastatur und sehr große
Schrift. Zuklappen während Streaming/Abruf/Reader zeigt Auswahl + Chat und
bewahrt Zustand. Endgültige Duo-Freigabe benötigt zusätzlich einen Test auf
echtem Gerät; Simulatorerfolg allein ist kein Hardware-Nachweis.

### M10 — Gesamtabnahme, Dokumentation und gestufter Release

**Voraussetzung:** M09. **Bausteine:** Tests/CI, englische und deutsche
Produktdokumentation, iOS-Review-Informationen und synthetische Screenshots.

- Reader, Capture, Suche, KI, Intents und Duo gemeinsam testen. Accessibility,
  Energie-/Speicherverhalten und Offline-/Authfehler auf Geräten abnehmen.
- `ios/README.md`, Root-READMEs und App-Review-Material entsprechend dem
  ausgelieferten Stand aktualisieren. Datenschutztexte/Privacy Manifests auf
  neue lokale Verarbeitung und explizite Systemaktionen prüfen; bestehende
  Rechts-/Sicherheitsgarantien nicht abschwächen.
- Zuerst Reader (M01–M04), danach Suche/KI (M05–M07), dann nachgewiesene
  System-/Duo-Funktionen veröffentlichen. Feature-Gates erlauben diese Stufen
  ohne Änderung des Archivformats. Ein KI-Problem muss den Reader nicht sperren.
- Jede Stufe erhält Checks, Versions-/Buildnummer und Freigabeprotokoll.
  Öffentliche Dateien werden explizit erlaubt; keine privaten Archive,
  Website, Tokens, Caches, Screenshots privater Inhalte oder private Historie.

**Abnahme:** Alle für die jeweilige Stufe nötigen Nachweise grün; offene
Hardware-/API-Nachweise führen zum Zurückhalten dieser Funktion. Keine
Veröffentlichungsaussage, bevor die Stufe tatsächlich ausgeliefert ist.

## 7. Prüfplan und Fertigdefinition

| Ebene | Pflichtnachweise bei Umsetzung |
| --- | --- |
| Swift-Unit-Tests | Pfade, tolerant gelesene Metadaten, Chronologie, Cacheisolation, Snapshot, Limits, Suchabdeckung, Belege, Verfügbarkeit, Abbruch |
| Netzwerk-/Sicherheitstests | Mock-GitHub, Rate-Limits, Truncation, Redirects, keine Zugangsdaten im Renderer/Modell, keine automatischen Fremdabrufe |
| Reader-Visualtests | Pflichtsyntax und schadhafte Fixtures; iPhone/iPad, hell/dunkel, Dynamic Type, VoiceOver, Offline |
| UI-/Integrationstests | Einrichtung, Auswahl, Einstellungen, Refresh, Quellenlinks, Chatbereich, Layoutwechsel, Mehrfensterisolation, Kontowechsel |
| KI-Evaluation | DE/EN, korrekte Belege und inhaltliche Stützung, fehlende Treffer, lange Quellen, Injection, Ablehnung, Geräteverfügbarkeit |
| Duo-Gerätetest | Offen/geschlossen/teilweise gefaltet, Safe Areas, Tastatur, Multitasking, Streaming und Wiederherstellung |
| Regression/Release | Share Extension, PDF-Konvertierungsstatus, Paketgrenzen, DCO, englische/deutsche Dokumentation und Release-Preflight |

Für Änderungen an gemeinsamem Capture, Skripten oder Plugin sind aus dem
Repository-Root beide Kernsuiten vorgeschrieben:

```sh
node --test tests/capture-utils.test.js
python3 -m unittest discover -s tests -p "test_*.py"
```

Für iOS-Implementierungsänderungen aus `ios/` ohne Signierung bauen:

```sh
xcodebuild \
  -project SourceBraid.xcodeproj \
  -scheme SourceBraid \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

XCTest zusätzlich mit einem tatsächlich installierten Simulator ausführen;
das generische Build-Ziel ist kein Testgerät. Die konkrete Destination und
OS-Version im PR festhalten. Der Release-Preflight lautet aus dem Root:
`python3 scripts/validate_ios_release.py`. Falls nötig, pro Kommando
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` setzen; für Duo
die in M00 verifizierte 27.1-Toolchain verwenden.

Aktueller Nachweisstand dieses Dokuments: Repository-/API-Recherche und
Toolchain-Version geprüft. **Keine Reader-, KI- oder Duo-Implementierung,
kein Simulatorbuild und keine Hardwareabnahme durchgeführt.** Für die reine
Dokumentationsänderung werden Links, Sprachparität, Diff und öffentliche
Inhaltsgrenzen geprüft. Spätere Checks dürfen nur mit tatsächlichem Ergebnis
als bestanden markiert werden.

## 8. Arbeitsliste und Entscheidungspunkte

- [ ] M00 Machbarkeit und konkrete Plattform-/Rendererentscheidung
- [ ] M01 Lesender GitHub-Zugriff und Domänenverträge
- [ ] M02 Katalog, letzte fünf und Offline-Cache
- [ ] M03 Formatierter Markdown-Reader und Assets
- [ ] M04 Adaptive Archivoberfläche
- [ ] M05 Lokale Suche und Quellenabruf
- [ ] M06 KI-Verfügbarkeit und Sitzungsadapter
- [ ] M07 Archivchat und überprüfte Belege
- [ ] M08 Nachgewiesene App-Intents-/Systemaktionen
- [ ] M09 Duo-Anpassung und Gerätetests
- [ ] M10 Gesamtabnahme und Release-Unterlagen

Noch zu messen bzw. zu entscheiden: nativer Renderer oder Parser/WebKit
(M00), endgültige Cache-/Dateibudgets (M00/M02), nachweisbare KI-Qualität und
Kontextstrategie je unterstützter OS-Version (M06/M07), konkrete
System-Schemas (M08), zusätzliche Duo-APIs und Gerätefreigabe (M09).
Alle übrigen Produktentscheidungen stehen in diesem Plan, sodass die
Umsetzung mit M00 beginnen kann, ohne die Architektur neu zu entwerfen.
