# SourceBraid: Markenfarben der App

12. Oktober 2026 · [English](IOS_BRAND_APPEARANCE.md)

Diese lokale Anpassung gibt der iOS-/iPadOS-App eine zurückhaltende Identität,
inspiriert von [sourcebraid.com](https://sourcebraid.com/). Warme Papierflächen,
dunkelgrüne Schrift und ein einzelner Petrol-Akzent übertragen den Charakter
der Webseite auf native Apple-Steuerelemente. **Neueste** mit sieben Einträgen,
Navigation, Reader und Hintergrundaktualisierung folgen weiterhin dem
[Reader-Konzept](IOS_READER_REFRESH_UX.de.md).

## Palette und Verwendung

| Semantische Rolle | Hell | Dunkel | Verwendung |
| --- | --- | --- | --- |
| Hintergrund | `#F4F1E9` | `#122C2A` | Hauptfläche des Inhalts |
| Fläche | `#FBFAF6` | `#1C403C` | Listenzeilen, Einstellungsbereiche, Reader-/Chatkarten und Chat-Eingabe |
| Schrift | `#143431` | `#F4F1E9` | Titel und Fließtext |
| Sekundärtext | `#49615E` | `#AEC2BC` | Datum, Metadaten und Erklärungen |
| Akzent | `#166B68` | `#8FD1BF` | Links, gewählte Bereiche und Hauptaktionen |
| Gedämpfte Fläche | `#E6EFE8` | `#214B43` | Ausgewählte Zeilen, Nutzernachrichten und Codeblöcke |
| Trennlinie | `#CCCFC8` | `#35534D` | Dekorative Trennung von Inhalten |
| Beschriftung gefüllter Aktionen | `#FFFFFF` | `#143431` | Text/Symbole auf einer gefüllten Akzentfläche |

Die fünf Hauptfarben des hellen Modus stammen aus dem
[öffentlichen Stylesheet](https://sourcebraid.com/assets/index-C6HlaNR4.css)
der Webseite. Gedämpfte Flächen, Trennlinien und die dunkle Palette sind
Anpassungen für die App. Benannte Farb-Assets bieten helle, dunkle und
kontrastverstärkte Varianten; SwiftUI und der Markdown-Reader verwenden dieselben
semantischen Farben. Reader-Links, Zitate, Code und Tabellen werden einheitlich
gestaltet; der Dokumentinhalt bleibt erhalten.

Die Chat-Eingabe verwendet `BrandSurface`. Ihr Rahmen nutzt ohne Fokus den
Sekundärtext-Farbton und mit Fokus den Akzent. Die Beschriftungsfarbe gefüllter
Aktionen (`onAccent`) gilt auch für den Einstellungsbutton vor der
Archivkonfiguration.

Senden/Stoppen sitzt rechts in derselben abgerundeten Eingabefläche. Ein eigener
reservierter Textbereich verhindert Überlagerung. Tastatur-Ausblenden bleibt bei
Fokus eine separate Aktion neben dem Feld. Reguläres Padding innerhalb des
Safe-Area-Inset schafft mehr Abstand des Composers zur unteren Systemleiste.

Native Schriften, Dynamic Type, SF Symbols, Tab-Leisten, Toolbars, Suchfelder,
Safe Areas und Tastaturverhalten bleiben erhalten. Der Akzent setzt Schwerpunkte,
Papierflächen halten den Lesebereich ruhig. Es werden keine Schrift-, Logo- oder
Quellcodedateien der Webseite und keine dekorativen Kartenmuster übernommen.
Zusätzliche grelle Akzentfarben, verspielte Illustrationen oder gedrehte Karten
sind nicht vorgesehen.

## Kontrast und Barrierefreiheit

Die berechneten Textkontraste der Standardpalette sind:

| Textkombination | Hell | Dunkel |
| --- | --- | --- |
| Schrift auf Hintergrund | 11,89:1 | 13,11:1 |
| Sekundärtext auf Hintergrund (hell) / Fläche (dunkel) | 5,90:1 | 6,08:1 |
| Akzent auf Fläche | 6,03:1 | 6,52:1 |
| Beschriftung gefüllter Aktionen auf Akzent | 6,29:1 | 7,69:1 |

Diese Werte überschreiten 4,5:1 für normalen Text. Dekorative dünne Trennlinien
tragen keine Information allein. Aktionsbeschriftungen, SF Symbols,
Auswahlmarkierungen und Absender bleiben unabhängig von Farbe erkennbar.
Kontrastverstärkte Varianten und Systemmaterialien benötigen eine eigene
Sichtprüfung; die Palettenberechnung prüft nicht jede zusammengesetzte Ansicht.

## Prüfgrenze

Neueste, Suche, Chat, Einstellungen und gerendertes Markdown im hellen/dunklen
Modus, mit erhöhtem Kontrast und vergrößerter Schrift prüfen. Dabei Datum und
Platzhalter, gewählte Tabs, Links, Eingabe-/Sendesteuerung, Quellen, Codeblöcke
und Tabellen auf Lesbarkeit prüfen. Den Eingaberahmen mit und ohne Fokus,
reservierten Platz für Text/Aktion, die separate Tastatur-Ausblendaktion und
Abstand zur unteren Systemleiste prüfen. Auch den Einstellungsbutton der noch
nicht konfigurierten Archivansicht prüfen.
Tastaturfälle sowie kompakte/breite
Übergänge mit synthetischen Inhalten wiederholen. Build-, UI-Test- und
Screenshot-Ergebnisse gehören ins
[Testprotokoll](IOS_IMPLEMENTATION_TESTING.de.md); dieses Konzept behauptet
keine bestandenen Prüfungen.

Diese Änderung ergänzt keine Cache-Anfragen, Hintergrundarbeit, KI-Funktion,
GitHub-Rechte, Netzwerkendpunkte oder Zugangsdatenbehandlung. Die Arbeit bleibt
bis zur Veröffentlichungsfreigabe des Maintainers lokal; kein Commit oder Push
ist freigegeben.
