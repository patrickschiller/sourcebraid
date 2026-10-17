# SourceBraid 1.0.1 – Veröffentlichungsplan

[English](PUBLISHING_CHECKLIST.md). Prüfung: 28. September 2026, öffentlicher
Commit `bb7c77ab18b3908d324a4a8e43056d574e60fbde`.
Diese Arbeitsliste ergänzt [RELEASING.md](../RELEASING.md).
Häkchen dokumentieren tatsächlich ausgeführte Prüfungen; offene Punkte sind
keine Bestätigung, dass Konten oder Store-Einträge noch nicht existieren.

Empfohlene Reihenfolge: lokal installieren und testen, Chrome einreichen,
während dessen Prüfung den ChatGPT-Dienst bereitstellen und abnehmen.
Jeden Kanal nach seiner Freigabe veröffentlichen; die gemeinsame Ankündigung
erst starten, wenn alle darin genannten Installationslinks funktionieren.
iOS benötigt für diesen Plan keine neue Veröffentlichung.

## Geprüfter Stand

- [x] `git pull --ff-only origin main`: bereits aktuell, kein neuer Commit.
- [x] Letzten Commit mit seinem Vorgänger verglichen: 60 Dateien geändert.
  Chrome steigt von 0.7.1 auf 1.0.1, ergänzt DE/EN-Metadaten, ausdrückliche
  Datenzustimmung und tokenfreien Plugin-Konfigurationsexport. `downloads`
  entfällt; Hostrechte sind ausdrücklich HTTP, HTTPS und lokale Dateien.
  Archivpfade und lokaler Index werden stärker abgegrenzt. Neu sind der
  lesende Cloudflare-MCP-Dienst, Marketplace-Eintrag und Release-/Review-Kits.
- [x] 23 Capture-, 63 Python- und 33 Remote-MCP-Tests bestanden.
- [x] Worker-Build als Dry Run bestanden; vorhandene npm-Abhängigkeiten benutzt.
- [x] Release-Bundle reproduzierbar gebaut, Inhalte geprüft, 24 Prüfsummen gültig.
  `RELEASE_MANIFEST.json` nennt obigen Commit und unveränderte Release-Eingaben.
- [x] [GitHub Release checks](https://github.com/patrickschiller/sourcebraid/actions/runs/36350019080)
  für diesen Commit erfolgreich.
- [x] Chrome-Bilder vorhanden: zwei Screenshots 1280×800, Promo 440×280,
  Icon 128×128. Texte und Reviewer-Schritte liegen vor.
- [x] Lokale CLI und Plugin-Suche geprüft: SourceBraid wird derzeit nicht angeboten;
  der Repository-Marketplace muss für die lokale Installation hinzugefügt werden.
- [x] Homepage sowie öffentliche Privacy-/Terms-Links antworten mit HTTP 200.
- [ ] **HTTPS-Blocker beheben:** `https://mcp.sourcebraid.com/health` scheitert
  derzeit an einem Zertifikat, das nicht zum Hostnamen passt. Mit Python und
  curl bestätigt. Kein erfolgreicher Health-/OAuth-Test; TLS-Prüfung beibehalten.
- [ ] **Außendarstellung korrigieren:** `PRODUCT_HUNT.md`, `COMMUNITY_POSTS.md`,
  `DEMO_SCRIPT.md` und `GITHUB.md` behaupten teilweise noch, es gebe keinen
  zentralen Inhaltsdienst. Gehostete ChatGPT-Anfragen durchlaufen jedoch
  SourceBraid/Cloudflare. Lokale Volltextsuche und Löschfunktionen nicht als
  Funktionen der gehosteten ChatGPT-Verbindung bewerben.
- [ ] Finalen Release-Commit/Tag und GitHub-Release veröffentlichen.
  Die Abfragen lieferten aktuell weder Tags noch Releases.

Die vorhandene lokale `.gitignore`-Änderung blieb erhalten. Der Builder prüft
saubere **Release-Eingaben**, nicht den gesamten Arbeitsbaum. Vor einer finalen
Veröffentlichung einen sauberen öffentlichen Checkout nach `RELEASING.md` nutzen.
Kein iOS-Build, echter Chrome-Durchlauf oder Live-ChatGPT-Test wurde hier ausgeführt.
Automatische Paketprüfungen ersetzen keine Sichtprüfung der Screenshots.

## 1. Auf diesem Rechner starten – gemeinsam

- [ ] Lokales Codex-Plugin aus dem geprüften Checkout installieren:

  ```bash
  codex plugin marketplace add .
  codex plugin add sourcebraid@sourcebraid
  ```

  Beide Befehle sind in der installierten CLI verfügbar und werden im
  Repository-Hauptverzeichnis ausgeführt. Danach einen neuen Chat öffnen;
  bei Bedarf die Desktop-App neu starten. Ein Repo-Marketplace verteilt das
  Plugin lokal und ist getrennt vom öffentlichen Verzeichnis.
  [OpenAI-Paketdokumentation](https://developers.openai.com/plugins/build/plugins).

- [ ] Ein dediziertes privates Testarchiv auswählen, das geprüfte
  `sourcebraid-review-fixture-v1.0.1.zip` dort entpacken und ausschließlich seine
  sechs synthetischen Dateien committen/pushen. Damit ist „portable weave“ als
  Suchbegriff reproduzierbar. `OWNER` und `TEST_REPO` im folgenden Befehl ersetzen;
  Zugang über bestehendes
  `gh auth login` oder die dokumentierten Token-Umgebungsvariablen einrichten:

  ```bash
  python3 codex-plugin/sourcebraid/scripts/sourcebraid.py config \
    --repo-slug OWNER/TEST_REPO --branch main --root-folder web-clips
  python3 codex-plugin/sourcebraid/scripts/sourcebraid.py index build
  python3 codex-plugin/sourcebraid/scripts/sourcebraid.py search "portable weave"
  ```

- [ ] In einem neuen Chat Suche und Abruf einer synthetischen Quelle testen.
  Das vollständige lokale Plugin verwendet Python, lokalen Index und GitHub-Zugang.
  Anleitung: [ChatGPT und Codex](../docs/CHATGPT_PLUGIN.md).
- [ ] In Chrome `chrome://extensions` öffnen, Entwicklermodus aktivieren,
  „Entpackte Erweiterung laden“ und `chrome-extension/sourcebraid` auswählen.
- [ ] Im Testarchiv Einwilligung, HTML-Aufnahme mit Bild, Tags/Notizen,
  Markdown-Fallback und tokenfreien Konfigurationsexport prüfen.
- [ ] Öffentliche und lokale synthetische PDF testen, für lokale Dateien den
  Datei-URL-Zugriff aktivieren; GitHub-Actions-Konvertierung bis zum fertigen
  Markdown und zu den Bildern prüfen. Datum und Ergebnis protokollieren.

## 2. Google Chrome Web Store

- [ ] **Patrick:** Publisherkonto festlegen, Registrierung und einmalige Gebühr
  erledigen, Kontaktmail bestätigen und 2FA aktivieren.
  [Registrierung](https://developer.chrome.com/docs/webstore/register),
  [Kontoeinrichtung](https://developer.chrome.com/docs/webstore/set-up-account),
  [2FA](https://developer.chrome.com/docs/webstore/program-policies/two-step-verification).
- [ ] **Patrick:** Trader-/Non-Trader-Angabe anhand der tatsächlichen Situation
  ausfüllen; erforderliche Identitäts-/Kontaktnachweise abschließen.
  [Google-Anforderungen](https://developer.chrome.com/docs/webstore/program-policies/trader-verification-faq).
- [ ] **Gemeinsam:** Eigenes privates Chrome-Review-Archiv vorbereiten. Sein PAT
  benötigt `Contents: Read and write`; Workflow-Schreibrechte nur, wenn damit
  die PDF-Unterstützung installiert wird. Zugang ausschließlich im vorgesehenen
  Reviewer-Feld hinterlegen. [Test instructions](https://developer.chrome.com/docs/webstore/cws-dashboard-test-instructions).
- [ ] **Codex + Patrick:** Das geprüfte Chrome-ZIP im
  [Developer Dashboard](https://chrome.google.com/webstore/devconsole) hochladen.
  DE/EN-Texte aus [STORE_LISTING.md](../chrome-extension/STORE_LISTING.md),
  vorhandene Bilder und öffentliche Support-/Privacy-Links übernehmen.
  [Bildvorgaben](https://developer.chrome.com/docs/webstore/images).
- [ ] **Gemeinsam:** Single-purpose, Datenkategorien, Remote-Code-Antwort und
  Begründung jeder Berechtigung am realen Verhalten prüfen. HTTP-/HTTPS-Zugriff
  ist weiterhin breit; lokale Dateien sind für lokale PDFs vorgesehen.
  [Privacy-Felder](https://developer.chrome.com/docs/webstore/cws-dashboard-privacy).
- [ ] **Patrick:** Länder und öffentliche Sichtbarkeit festlegen, Einreichung
  abschließen. Bei verzögerter Veröffentlichung innerhalb von 30 Tagen nach
  Freigabe publizieren. [Veröffentlichung](https://developer.chrome.com/docs/webstore/publish).
- [ ] **Gemeinsam:** Nach Freigabe aus dem Store frisch installieren und
  Aufnahme/PDF nochmals abnehmen. Live-Store-URL dokumentieren.

Google nennt wenige Tage bis mehrere Wochen für die Prüfung; breite Hostrechte
können sie verlängern. Keinen festen Launchtermin vor Freigabe versprechen.
[Review-Verfahren](https://developer.chrome.com/docs/webstore/review-process).

## 3. ChatGPT und öffentliches OpenAI-Plugin-Verzeichnis

Der vorhandene Primärpfad ist **With MCP / Universal**: ein gehosteter Dienst
mit `search`, `fetch`, `sourcebraid_list` und `sourcebraid_status`, ausschließlich
lesend. Das optionale Skills-ZIP allein verbindet ChatGPT nicht mit dem Archiv.

- [ ] **Patrick:** OpenAI-Publisheridentität verifizieren und
  `Apps Management: Write` prüfen. [Einreichung](https://developers.openai.com/plugins/deploy/submission).
- [ ] **Patrick:** Cloudflare-Konto, Domainkontrolle und Kostenrahmen festlegen.
- [ ] **Codex + Patrick:** Nach [Deployment-Runbook](../docs/CHATGPT_MCP_DEPLOYMENT.md)
  Worker, KV und Custom Domain bereitstellen; das falsche TLS-Zertifikat beheben.
  Kein GitHub-PAT gehört in globale Worker-Variablen.
- [ ] **Gemeinsam:** Öffentliches HTTPS, `/health`, OAuth-Metadaten und erwartetes
  HTTP 401 ohne Anmeldung prüfen. Health allein genügt nicht.
- [ ] **Gemeinsam:** Separates privates OpenAI-Review-Archiv aus dem Fixture-ZIP
  befüllen. Eigenen PAT mit ausschließlich `Contents: Read-only` für dieses
  Repository erstellen. Nie den Chrome-Schreibtoken verwenden oder Tokens in
  Chats, Screenshots und öffentliche Dateien eintragen.
- [ ] **Gemeinsam:** ChatGPT-Entwicklermodus und MCP-Verbindung einrichten;
  Verfügbarkeit hängt vom Konto/Workspace ab.
  [Offizieller Testablauf](https://developers.openai.com/plugins/deploy/connect-chatgpt).
- [ ] **Gemeinsam:** Alle fünf positiven und drei negativen Fälle im
  [MCP-Einreichungskit](OPENAI_MCP_SUBMISSION.md) live bestehen: Status,
  Liste, Suche, Abruf, Zusammenfassung sowie verweigertes Löschen,
  fremde/unerlaubte Pfade und widerrufener Token. Zusätzlich Refresh,
  Wiederverbinden und Trennung zweier Nutzerarchive prüfen. Bösartige
  Anweisungen in einer synthetischen Quelle müssen als Quelldaten behandelt
  werden und dürfen weder Tokenweitergabe noch fremde Netzwerkaufrufe auslösen.
- [ ] **Codex:** Ergebnisse mit Datum und Worker-/Commitversion festhalten;
  bei Bedarf echte ChatGPT-Demo mit synthetischen Quellen aufnehmen.
- [ ] **Patrick + Codex:** Im OpenAI-Portal Domainnachweis, Tool-Scan,
  Listing und geschützten Reviewzugang vervollständigen; Länder, Erklärungen
  und Release Notes prüfen, zur Prüfung einreichen und nach Freigabe publizieren.
  [Einreichungsablauf](https://developers.openai.com/plugins/deploy/submission).
- [ ] **Gemeinsam:** Installation aus dem öffentlichen Verzeichnis abnehmen,
  Live-Link erfassen und zeitlich begrenzte Review-Zugänge anschließend widerrufen.

## 4. Pakete und gemeinsamer Abschluss

Die lokal geprüften Dateien liegen unter `dist/sourcebraid-release-v1.0.1/`:

| Datei | Verwendung |
| --- | --- |
| `sourcebraid-chrome-v1.0.1.zip` | Google-Upload |
| `sourcebraid-chatgpt-mcp-v1.0.1.zip` | Quellpaket für Worker-Deployment |
| `sourcebraid-review-fixture-v1.0.1.zip` | Drei synthetische Quellen plus Index-Shards |
| `sourcebraid-plugin-skills-v1.0.1.zip` | Optionales lokales Skills-Paket; kein gehosteter MCP |
| `RELEASE_MANIFEST.json`, `SHA256SUMS` | Commitbezug und Integrität |

- [ ] Finale Korrekturen in DE/EN abgleichen und mit DCO-Sign-off committen.
  Anschließend relevante Tests und Pakete vom finalen sauberen Commit erneut
  prüfen. Vorhandene lokale Änderungen nicht ungeprüft in den Release übernehmen.
- [ ] Geprüften Tag `v1.0.1` und GitHub-Release mit passenden Artefakten publizieren;
  erst danach die taggebundene Plugin-Installation bewerben.
- [ ] Nur tatsächlich freigegebene Store-/Plugin-Links und Aussagen in den
  Launchentwürfen verwenden; private Website-Quellen und reale Archive ausschließen.
- [ ] Reale Erstinstallation je veröffentlichtem Kanal bestehen und danach die
  [Launch-Checkliste](LAUNCH_CHECKLIST.md) für die öffentliche Ankündigung nutzen.

Nächster gemeinsamer Arbeitsschritt: lokales Plugin und Chrome einrichten und
einen synthetischen Capture-to-Search-Durchlauf abschließen. Kontoprüfungen bei
Google, OpenAI und Cloudflare können parallel vorbereitet werden.
