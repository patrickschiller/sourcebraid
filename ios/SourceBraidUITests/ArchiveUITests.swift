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
        XCTAssertTrue(app.navigationBars["Neueste"].exists)
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
        app.buttons["Latest"].firstMatch.tap()
        XCTAssertTrue(last.waitForExistence(timeout: 5))
        app.buttons["Chat"].firstMatch.tap()
        XCTAssertEqual(input.value as? String, draft, "Switching tabs must retain all draft lines")
        capture("Synthetic chat full height")
    }
}
