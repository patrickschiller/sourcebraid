import XCTest

final class ArchiveUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["SOURCEBRAID_DEMO"] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light
    }
    override func tearDown() { app.terminate(); XCUIDevice.shared.orientation = .portrait; XCUIDevice.shared.appearance = .light }

    private func launch() {
        app.launch()
        XCTAssertTrue(app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-7.md"].waitForExistence(timeout: 15))
    }
    @discardableResult
    private func selectAndRead() -> Bool {
        app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-7.md"].tap()
        XCTAssertTrue(app.webViews["archive.reader.web"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["Markdown-Reader"].waitForExistence(timeout: 10))
        return !app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-7.md"].isHittable
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testOfflineMermaidRenderingAndSecurity() {
        app.launchEnvironment["SOURCEBRAID_MERMAID_PROBE"] = "1"
        app.launch()
        let status = app.staticTexts["archive.mermaid.probe.result"]
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            status.exists && (status.label.hasPrefix("good=") || status.label.hasPrefix("Mermaid probe failed:"))
        }, object: nil)
        let result = XCTWaiter.wait(for: [complete], timeout: 25)
        capture("Synthetic Mermaid probe stage")
        XCTAssertEqual(result, .completed, status.label)
        XCTAssertEqual(status.label,
            "good=3;failed=true;limited=true;unsafe=0;count=6;pageScript=false;isolated=true")
        XCTAssertTrue(app.webViews["archive.mermaid.probe.web"].exists)
        XCTAssertTrue(app.webViews.staticTexts["Synthetic Mermaid checks"].exists)
        capture("Synthetic offline Mermaid rendering")
    }

    private func tapUniqueVisible(_ query: XCUIElementQuery) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            query.allElementsBoundByIndex.filter { $0.isHittable }.count == 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed,
            "Expected one reachable system control")
        let matches = query.allElementsBoundByIndex.filter { $0.isHittable }
        guard matches.count == 1 else { return }
        matches[0].tap()
    }

    private func returnToSelection() {
        // Duo moves Back into a vertical system toolbar. Its observed native
        // identifier remains stable without assuming a NavigationBar container.
        tapUniqueVisible(app.descendants(matching: .any).matching(identifier: "BackButton"))
        let row = app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-7.md"]
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in row.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
    }

    private func closeSearchIfPresented() {
        let close = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["Schließen", "Close"]))
        if close.allElementsBoundByIndex.contains(where: { $0.isHittable }) { tapUniqueVisible(close) }
    }

    private func reveal(_ link: XCUIElement, in web: XCUIElement) {
        // Short, slow drags keep adjacent links from being skipped by inertia.
        for _ in 0..<16 where !link.isHittable {
            web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).press(forDuration: 0.1,
                thenDragTo: web.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    func testLatestSevenReaderRawAndBack() {
        launch()
        for number in 1...7 { XCTAssertTrue(app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-\(number).md"].exists) }
        capture("Synthetic library")
        let usesCompactNavigation = selectAndRead(); capture("Synthetic formatted reader")
        app.buttons["Reader options"].tap(); app.buttons["Raw Markdown"].tap()
        XCTAssertTrue(app.scrollViews["archive.reader.raw"].waitForExistence(timeout: 5))
        capture("Synthetic raw Markdown")
        if usesCompactNavigation {
            returnToSelection()
        }
    }

    func testDifferentClipsOpenAfterReturningToList() {
        launch()
        // Start below the newest item: this regression concerns successive
        // selections, not which article happened to be loaded first.
        verifySuccessiveReaderSelections([5, 6, 7, 5])
    }

    func testDifferentSearchResultsOpenAfterReturningToList() {
        launch()
        app.buttons["Search"].firstMatch.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        verifySuccessiveReaderSelections([7, 6, 5])
    }

    private func verifySuccessiveReaderSelections(_ numbers: [Int]) {
        for number in numbers {
            let row = app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-\(number).md"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            if !row.isHittable { app.swipeDown() }
            row.tap()
            let web = app.webViews["archive.reader.web"]
            let opened = web.waitForExistence(timeout: 10)
            if !opened { capture("Synthetic reader stalled after selection \(number)") }
            let loading = app.descendants(matching: .any).matching(identifier: "archive.reader.loading").firstMatch
            let phase = opened ? "loaded" : (loading.exists ? (loading.value as? String ?? "Unknown loading phase") : "No loading marker")
            XCTAssertTrue(opened, "Reader remained loading for selection \(number): \(phase)")
            XCTAssertTrue(web.staticTexts["Markdown-Reader"].waitForExistence(timeout: 5))
            XCTAssertTrue(web.staticTexts["Synthetic document body \(number)."].waitForExistence(timeout: 5),
                "Rendered body must belong to selection \(number)")
            XCTAssertTrue(app.staticTexts["Synthetic article \(number)"].exists)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Original source").firstMatch.exists)
            app.buttons["Reader options"].tap(); app.buttons["Raw Markdown"].tap()
            let raw = app.scrollViews["archive.reader.raw"]
            XCTAssertTrue(raw.waitForExistence(timeout: 5))
            let ownSource = raw.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "https://example.invalid/synthetic-\(number)")).firstMatch
            XCTAssertTrue(ownSource.exists, "Raw source must belong to selection \(number)")
            capture("Synthetic successive reader selection \(number)")
            app.buttons["Reader options"].tap(); app.buttons["Raw Markdown"].tap()
            XCTAssertTrue(web.waitForExistence(timeout: 5))
            if !row.isHittable { returnToSelection() }
        }
    }

    func testSearchAndSettings() {
        launch()
        app.buttons["Search"].firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("zzzfixtureabsent")
        let result = app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-7.md"]
        XCTAssertTrue(result.waitForNonExistence(timeout: 5), "An absent term must filter cached rows")
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "zzzfixtureabsent".count))
        search.typeText("scrolling")
        capture("Synthetic native search results")
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(app.webViews["archive.reader.web"].waitForExistence(timeout: 10))
        if !result.isHittable { returnToSelection() }
        XCTAssertEqual(search.value as? String, "scrolling", "Reader navigation must retain the query")
        // Compact system search replaces toolbar actions with Close; wide
        // navigation can keep both the search field and ordinary actions visible.
        closeSearchIfPresented()
        XCTAssertTrue(app.buttons["archive.options"].waitForExistence(timeout: 5))
        app.buttons["archive.options"].tap(); app.buttons["Settings"].tap()
        XCTAssertTrue(app.textFields["Owner or organization"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["archive.options"].waitForExistence(timeout: 5))
    }

    func testGermanLibraryReaderAndSettings() {
        verifyGermanReaderSettingsSearchAndChat()
    }

    private func verifyGermanReaderSettingsSearchAndChat(_ appearance: String = "light") {
        let prefix = appearance == "dark" ? "Synthetic German dark" : "Synthetic German"
        app.launchArguments = ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launchEnvironment["SOURCEBRAID_CHAT_EXAMPLE"] = "1"
        launch()
        XCTAssertTrue(app.navigationBars["Zuletzt"].exists)
        XCTAssertTrue(app.staticTexts["Synthetischer Beitrag 7"].exists)
        capture("\(prefix) latest seven")
        let usesCompactNavigation = selectAndRead()
        XCTAssertTrue(app.webViews.staticTexts["Markdown-Reader"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Reader-Optionen"].exists)
        capture("\(prefix) reader")
        if usesCompactNavigation { returnToSelection() }
        app.buttons["archive.options"].tap(); app.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.textFields["Eigentümer oder Organisation"].waitForExistence(timeout: 5))
        capture("\(prefix) settings")
        app.buttons["Fertig"].tap()
        app.buttons["Suche"].firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Offline-Suche")
        let result = app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-7.md"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-6.md"].waitForNonExistence(timeout: 5))
        capture("\(prefix) search example")
        closeSearchIfPresented()
        app.buttons["Chat"].firstMatch.tap()
        let input = app.descendants(matching: .any)["archive.chat.input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Was zeigt dieser Beitrag?")
        capture("\(prefix) chat keyboard")
        app.buttons["Frage senden"].tap()
        let answer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Beispielantwort mit Testdaten")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Synthetischer Beitrag 7"].exists, "The example answer must show its source")
        capture("\(prefix) chat example")
    }

    func testRotationPreservesSelection() {
        launch(); selectAndRead()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.webViews["archive.reader.web"].waitForExistence(timeout: 5)); capture("Synthetic landscape reader")
        XCUIDevice.shared.orientation = .portrait
        if !app.webViews["archive.reader.web"].exists { app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-7.md"].tap() }
        XCTAssertTrue(app.webViews["archive.reader.web"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Synthetic article 7"].exists)
    }

    func testDarkModeAndLargeType() {
        XCUIDevice.shared.appearance = .dark
        app.launchEnvironment["SOURCEBRAID_CHAT_LAYOUT"] = "1"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        launch(); selectAndRead(); capture("Synthetic dark reader large type")
        XCTAssertTrue(app.buttons["Reader options"].isHittable)
        app.buttons["archive.reader.ask"].tap()
        let input = app.descendants(matching: .any)["archive.chat.input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap()
        input.typeText("Synthetic large type draft\nA second question\nA third line")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Send question"].isHittable)
        XCTAssertTrue(app.buttons["archive.chat.dismissKeyboard"].isHittable)
        capture("Synthetic dark chat keyboard large type")
        app.buttons["archive.chat.dismissKeyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.terminate()
        app.launchEnvironment.removeValue(forKey: "SOURCEBRAID_CHAT_LAYOUT")
        verifyGermanReaderSettingsSearchAndChat("dark")
    }

    func testInternalLinkAndNativePDFPreview() {
        launch(); selectAndRead()
        let web = app.webViews["archive.reader.web"]
        let pdf = web.links["Synthetic PDF"]
        reveal(pdf, in: web)
        XCTAssertTrue(pdf.isHittable); pdf.tap()
        XCTAssertTrue(app.navigationBars["synthetic.pdf"].waitForExistence(timeout: 10))
        let page = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "SourceBraid synthetic PDF - no private content")).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 20), "Quick Look must render the PDF page, not only its title")
        capture("Synthetic native PDF preview")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["synthetic.pdf"].waitForNonExistence(timeout: 5))
        let internalLink = web.links["Other archived clip"]
        // Start from the heading after the modal transition, rather than guessing
        // where the restored scroll position puts a link just above the viewport.
        let heading = web.staticTexts["Markdown-Reader"]
        for _ in 0..<8 where !heading.isHittable { web.swipeDown() }
        XCTAssertTrue(heading.isHittable)
        reveal(internalLink, in: web)
        capture("Synthetic reader after PDF dismissal")
        XCTAssertTrue(internalLink.isHittable); internalLink.tap()
        XCTAssertTrue(app.staticTexts["Synthetic article 1"].waitForExistence(timeout: 5))
    }

    func testChatTabAndKeyboardPreserveLatestSeven() {
        app.launchEnvironment["SOURCEBRAID_CHAT_LAYOUT"] = "1"
        launch()
        XCTAssertFalse(app.descendants(matching: .any)["archive.chat.input"].exists, "The initial list has the full content area")
        let last = app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-1.md"]
        XCTAssertTrue(last.isHittable, "Seven short demo rows fit before scrolling")
        capture("Synthetic latest seven full list")
        selectAndRead()
        app.buttons["archive.reader.ask"].tap()
        let input = app.descendants(matching: .any)["archive.chat.input"].firstMatch
        let draft = "Synthetic draft\nA second question\nA third line"
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText(draft)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Send question"].isHittable)
        XCTAssertTrue(app.buttons["archive.chat.dismissKeyboard"].isHittable)
        capture("Synthetic chat with keyboard")
        app.buttons["archive.chat.dismissKeyboard"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, draft, "Dismissing the keyboard must retain all draft lines")
        app.buttons["Recent"].firstMatch.tap()
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        app.buttons["Chat"].firstMatch.tap()
        XCTAssertEqual(input.value as? String, draft, "Switching tabs must retain all draft lines")
        capture("Synthetic chat full height")
    }
}

final class IntelligenceDiagnosticsUITests: XCTestCase {
    func testModelPreparationGuidanceKeepsReaderAvailable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment = ["SOURCEBRAID_DEMO": "1", "SOURCEBRAID_INTELLIGENCE_STATE": "modelNotReady"]
        defer { app.terminate() }
        for language in ["en", "de"] {
            let german = language == "de"
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", german ? "de_DE" : "en_US"]
            app.launch()
            let clip = app.buttons["archive.clip.clips/2026/10/2026-10-12-demo-7.md"]
            XCTAssertTrue(clip.waitForExistence(timeout: 20))
            app.buttons["Chat"].firstMatch.tap()
            XCTAssertTrue(app.staticTexts[german ? "Lokales Modell ist nicht bereit" : "Local model is not ready"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.descendants(matching: .any)["archive.chat.input"].exists)
            let recheck = app.buttons["archive.chat.checkAvailability"]
            XCTAssertTrue(recheck.isHittable, "The main readiness action must be reachable without scrolling")
            let help = app.descendants(matching: .any)["archive.chat.appleHelp"].firstMatch
            XCTAssertTrue(help.isHittable, "Apple's setup guide must be reachable without scrolling")
            recheck.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", german ? "Downloadfortschritt" : "download progress")).firstMatch.exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "\(language)-intelligence-diagnostics"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.buttons[german ? "Zuletzt" : "Recent"].firstMatch.tap()
            clip.tap()
            XCTAssertTrue(app.webViews["archive.reader.web"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }
}

/// Explicitly invoked native capture workflow. All articles are original
/// fictional examples; no user archive or generated AI answer is photographed.
final class AppStoreScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SOURCEBRAID_APP_STORE_CAPTURE"] == "1",
            "Opt in with TEST_RUNNER_SOURCEBRAID_APP_STORE_CAPTURE=1 for store screenshots")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment = ["SOURCEBRAID_DEMO": "1", "SOURCEBRAID_STORE_DEMO": "1"]
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light
    }

    override func tearDown() {
        app?.terminate()
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.appearance = .light
    }

    func testEnglishProductScreenshots() { captureProduct(language: "en", locale: "en_US") }
    func testGermanProductScreenshots() { captureProduct(language: "de", locale: "de_DE") }
    func testEnglishIntelligenceDiagnostics() { captureDiagnostics(language: "en", locale: "en_US") }
    func testGermanIntelligenceDiagnostics() { captureDiagnostics(language: "de", locale: "de_DE") }

    private func captureDiagnostics(language: String, locale: String) {
        app.launchEnvironment["SOURCEBRAID_INTELLIGENCE_STATE"] = "modelNotReady"
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        XCTAssertTrue(app.buttons["archive.clip.clips/2026/10/2026-10-17-demo-7.md"].waitForExistence(timeout: 20))
        app.buttons["Chat"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["archive.chat.diagnostics"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["archive.chat.checkAvailability"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["archive.chat.input"].exists)
        capture("\(language)-05-intelligence-diagnostics-preview")
    }

    private func captureProduct(language: String, locale: String) {
        let german = language == "de"
        let clip = "archive.clip.clips/2026/10/2026-10-17-demo-7.md"
        let heading = german ? "Die Idee bleibt. Die Quelle auch." : "Keep the idea. Keep the source."
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
        let latest = app.buttons[clip]
        XCTAssertTrue(latest.waitForExistence(timeout: 20))
        let refresh = app.buttons["archive.refresh"]
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            refresh.label == (german ? "Aktualisieren" : "Refresh")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 15), .completed)
        capture("\(language)-02-latest")

        latest.tap()
        let reader = app.webViews["archive.reader.web"]
        XCTAssertTrue(reader.staticTexts[heading].waitForExistence(timeout: 10))
        capture("\(language)-01-reader")

        let compact = !latest.isHittable
        app.buttons[german ? "Reader-Optionen" : "Reader options"].tap()
        app.buttons[german ? "Markdown-Quelltext" : "Raw Markdown"].tap()
        XCTAssertTrue(app.scrollViews["archive.reader.raw"].waitForExistence(timeout: 5))
        capture("\(language)-04-markdown")

        if compact {
            let back = app.descendants(matching: .any).matching(identifier: "BackButton")
            let visible = back.allElementsBoundByIndex.filter { $0.isHittable }
            XCTAssertEqual(visible.count, 1)
            visible.first?.tap()
            XCTAssertTrue(latest.waitForExistence(timeout: 5))
        }
        app.buttons[german ? "Suche" : "Search"].firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("offline\n")
        XCTAssertTrue(latest.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["archive.clip.clips/2026/10/2026-10-17-demo-1.md"].waitForNonExistence(timeout: 5))
        capture("\(language)-03-offline-search")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
