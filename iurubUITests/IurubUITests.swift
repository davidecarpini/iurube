import XCTest

final class IurubUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-state", "--fixture"]
        app.launch()
    }

    func testYouTubePlaylistIsFirstTabAndAccountSavePersists() throws {
        XCTAssertTrue(app.webViews.staticTexts["Guarda più tardi · account di prova"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["Video già salvato nell’account"].exists)
        XCTAssertFalse(app.buttons["exploreButton"].exists)
        app.tabBars.buttons["Esplora"].tap()
        let save = app.webViews.buttons["+ Guarda più tardi"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(app.staticTexts["Salvato in Guarda più tardi su YouTube"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Musica per concentrarsi"].waitForExistence(timeout: 10))
        capture("account-watch-later")
        app.terminate()
        app.launchArguments = ["--ui-testing", "--fixture"]
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Musica per concentrarsi"].waitForExistence(timeout: 10))
        let remove = app.webViews.buttons.matching(identifier: "Rimuovi da Guarda più tardi").element(boundBy: 1)
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.webViews.buttons["Annulla"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.staticTexts["Musica per concentrarsi"].exists)
        XCTAssertTrue(app.webViews.staticTexts["Video già salvato nell’account"].exists)
        app.webViews.buttons["Annulla"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Musica per concentrarsi"].waitForExistence(timeout: 5))
        app.buttons["settingsButton"].tap()
        app.buttons["deviceLibraryButton"].tap()
        XCTAssertTrue(app.buttons["addLinkButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["play-jfKfPfyJRdk"].exists, "Account saves must not silently write to the local archive")
    }

    func testShortsTogglePersistsAndRestoresShelf() throws {
        app.tabBars.buttons["Esplora"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Home · fixture di test"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.staticTexts["Short di prova"].exists)
        app.buttons["settingsButton"].tap()
        let toggle = app.switches["shortsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        // SwiftUI exposes the whole labeled row as a switch. Tap the control
        // at its trailing edge, rather than the non-interactive label center.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["closeSettings"].tap()
        capture("shorts-after-enabling")
        XCTAssertTrue(app.webViews.staticTexts["Short di prova"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--fixture"]
        app.launch()
        app.buttons["settingsButton"].tap()
        XCTAssertEqual(app.switches["shortsToggle"].value as? String, "1")
        capture("settings-shorts-enabled")
        app.switches["shortsToggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(app.switches["shortsToggle"].value as? String, "0")
        app.buttons["closeSettings"].tap()
        app.tabBars.buttons["Esplora"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Home · fixture di test"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.staticTexts["Short di prova"].exists)
    }

    func testLocalArchivePreservesLinksRemovalAndUndo() throws {
        app.buttons["settingsButton"].tap()
        app.buttons["deviceLibraryButton"].tap()
        XCTAssertTrue(app.buttons["addLinkButton"].waitForExistence(timeout: 5))
        app.buttons["addLinkButton"].tap()
        let field = app.textFields["videoLinkField"]
        field.tap(); field.typeText("https://evil.com/watch?v=jfKfPfyJRdk")
        app.buttons["confirmAddVideo"].tap()
        XCTAssertTrue(app.staticTexts["Inserisci un link valido a un video YouTube."].exists)
        // Relaunch a clean add sheet to avoid depending on localized selection menus.
        app.buttons["Annulla"].tap()
        app.buttons["addLinkButton"].tap()
        app.textFields["videoLinkField"].tap()
        app.textFields["videoLinkField"].typeText("https://youtu.be/jfKfPfyJRdk")
        app.textFields["videoTitleField"].tap()
        app.textFields["videoTitleField"].typeText("Il mio video")
        app.buttons["confirmAddVideo"].tap()
        XCTAssertTrue(app.buttons["play-jfKfPfyJRdk"].waitForExistence(timeout: 5))
        app.buttons["options-jfKfPfyJRdk"].tap()
        app.buttons["Rimuovi dalla lista"].tap()
        XCTAssertTrue(app.buttons["exploreButton"].waitForExistence(timeout: 5))
        app.buttons["undoRemove"].tap()
        XCTAssertTrue(app.buttons["play-jfKfPfyJRdk"].waitForExistence(timeout: 5))
    }

    func testFourTabsToolbarProfileAndPageRefresh() throws {
        XCTAssertTrue(app.webViews.staticTexts["Guarda più tardi · account di prova"].waitForExistence(timeout: 10))
        let labels = ["Salvati", "Iscrizioni", "Cronologia", "Esplora"]
        let buttons = labels.map { app.tabBars.buttons[$0] }
        XCTAssertEqual(app.tabBars.buttons.count, 4)
        for button in buttons { XCTAssertTrue(button.exists) }
        for index in 0..<3 { XCTAssertLessThan(buttons[index].frame.midX, buttons[index + 1].frame.midX) }
        XCTAssertFalse(app.buttons["refreshWatchLater"].exists)
        XCTAssertFalse(app.buttons["youtubeHome"].exists)
        XCTAssertLessThan(app.buttons["backButton"].frame.midX, app.buttons["refreshPage"].frame.midX)
        XCTAssertLessThan(app.buttons["settingsButton"].frame.midX, app.buttons["profileButton"].frame.midX)
        XCTAssertGreaterThanOrEqual(app.webViews.firstMatch.frame.maxY, app.frame.maxY - 1, "The web view must reach the bottom of the screen, behind the floating tab bar")
        XCTAssertFalse(app.webViews.buttons["Home"].exists)
        XCTAssertFalse(app.webViews.buttons["Tu"].exists)
        for label in ["Iscrizioni", "Cronologia"] {
            app.tabBars.buttons[label].tap()
            let heading = app.webViews.staticTexts["\(label) · fixture di test"]
            XCTAssertTrue(heading.waitForExistence(timeout: 10))
            app.buttons["refreshPage"].tap()
            XCTAssertTrue(heading.waitForExistence(timeout: 10))
        }
        app.buttons["profileButton"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Tu · fixture di test"].waitForExistence(timeout: 10))
        // loadHTMLString fixtures do not provide WKWebView's native navigation history.
        // The real profile -> Back path is covered by the live test below.
        app.buttons["refreshPage"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Tu · fixture di test"].waitForExistence(timeout: 10), "Refresh must reload the current page, not reset to a tab's root")
        app.tabBars.buttons["Esplora"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Home · fixture di test"].waitForExistence(timeout: 10))
        capture("four-tabs-navigation")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// Opt-in, read-only verification using the existing YouTube login.
final class IurubLiveUITests: XCTestCase {
    func testExistingYouTubeWatchLater() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_LIVE"] == "1", "Requires a YouTube session")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["refreshPage"].waitForExistence(timeout: 10))
        let heading = app.webViews.staticTexts.matching(NSPredicate(format: "label == %@ OR label == %@", "Guarda più tardi", "Watch later")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 30))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "youtube-account-watch-later"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.webViews.buttons["Rimuovi da Guarda più tardi"].firstMatch.waitForExistence(timeout: 10))
        app.webViews.buttons["Menu Azione"].firstMatch.tap()
        XCTAssertTrue(app.webViews.buttons["Salva in una playlist"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.buttons["Rimuovi da Guarda più tardi"].firstMatch.exists)
        // Open the official chooser only; never toggle membership in the real account.
        app.webViews.buttons["Salva in una playlist"].tap()
        let selectedPlaylist = app.webViews.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@", "Watch later", "Selezionato")).firstMatch
        XCTAssertTrue(selectedPlaylist.waitForExistence(timeout: 5))
        app.buttons["refreshPage"].tap()
        app.tabBars.buttons["Esplora"].tap()
        XCTAssertTrue(app.buttons["refreshPage"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(heading.waitForExistence(timeout: 30))
        XCTAssertGreaterThanOrEqual(app.webViews.firstMatch.frame.maxY, app.frame.maxY - 1)
        XCTAssertFalse(app.webViews.buttons["Home"].exists)
        XCTAssertFalse(app.webViews.buttons["Tu"].exists)
        app.buttons["profileButton"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Cronologia"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["backButton"].isEnabled)
        capture("youtube-tu", app: app)
        app.buttons["backButton"].tap()
        XCTAssertTrue(heading.waitForExistence(timeout: 30))
        for label in ["Iscrizioni", "Cronologia", "Esplora"] {
            app.tabBars.buttons[label].tap()
            XCTAssertTrue(app.buttons["refreshPage"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.webViews.links.firstMatch.waitForExistence(timeout: 30))
            capture("youtube-\(label.lowercased())", app: app)
            print("NAVIGATION \(label): \(app.webViews.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label))")
        }
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(heading.waitForExistence(timeout: 30))
        capture("youtube-salvati-navigation", app: app)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
