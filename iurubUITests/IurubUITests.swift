import XCTest

final class IurubUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-state", "--fixture"]
        app.launch()
    }

    func testTabsSavingFromHomePersistenceRemovalAndUndo() throws {
        XCTAssertTrue(app.buttons["exploreButton"].waitForExistence(timeout: 5))
        app.buttons["exploreButton"].tap()
        let save = app.webViews.buttons["+ Guarda più tardi"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(app.webViews.buttons["✓ Salvato in Guarda più tardi"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Guarda più tardi"].tap()
        XCTAssertTrue(app.buttons["play-jfKfPfyJRdk"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["play-jfKfPfyJRdk"].waitForExistence(timeout: 5))
        app.buttons["options-jfKfPfyJRdk"].tap()
        app.buttons["Rimuovi dalla lista"].tap()
        XCTAssertTrue(app.buttons["exploreButton"].waitForExistence(timeout: 5))
        app.buttons["undoRemove"].tap()
        XCTAssertTrue(app.buttons["play-jfKfPfyJRdk"].waitForExistence(timeout: 5))
        capture("saved-library")
    }

    func testShortsTogglePersistsAndRestoresShelf() throws {
        app.tabBars.buttons["Home"].tap()
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
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Home · fixture di test"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.staticTexts["Short di prova"].exists)
    }

    func testLinkValidationAndSavingWithoutGoogleLogin() throws {
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
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// Optional checks against the live site; excluded unless explicitly enabled.
final class IurubLiveUITests: XCTestCase {
    func testLiveYouTube() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_LIVE"] == "1", "Enable IURUB_LIVE for network-dependent YouTube checks")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-state"]
        app.launch()
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20))
        let reject = app.webViews.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Reject all", "Rifiuta tutto")).firstMatch
        if !app.webViews.buttons["Search YouTube"].firstMatch.waitForExistence(timeout: 5), reject.waitForExistence(timeout: 15) { reject.tap() }
        capture(app, "youtube-live-home")
        app.webViews.buttons["Search YouTube"].firstMatch.tap()
        let field = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.searchField.rawValue, XCUIElement.ElementType.textField.rawValue)).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Big Buck Bunny Blender\n")
        let save = app.webViews.buttons["+ Guarda più tardi"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 25))
        capture(app, "youtube-live-search")
        save.tap()
        XCTAssertTrue(app.webViews.buttons["✓ Salvato in Guarda più tardi"].firstMatch.waitForExistence(timeout: 5))
        app.tabBars.buttons["Guarda più tardi"].tap()
        let video = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "play-")).firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        let videoID = video.identifier
        capture(app, "youtube-live-library")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons[videoID].waitForExistence(timeout: 5))
        app.buttons[videoID].tap()
        XCTAssertTrue(app.buttons["closePlayer"].waitForExistence(timeout: 10))
        let play = app.webViews.buttons.matching(NSPredicate(format: "label == %@ OR label == %@ OR label == %@", "Play", "Play video", "Riproduci")).firstMatch
        if play.waitForExistence(timeout: 20) { play.tap() }
        let playback = app.webViews.otherElements["YouTube Video Player"].descendants(matching: .any)
            .matching(NSPredicate(format: "value MATCHES %@", ".*(second|minute).*" )).firstMatch
        XCTAssertTrue(playback.waitForExistence(timeout: 25))
        let initialTime = playback.value as? String ?? ""
        let progress = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initialTime), object: playback)
        let progressResult = XCTWaiter.wait(for: [progress], timeout: 60)
        print("LIVE PLAYBACK: \(initialTime) -> \(playback.value as? String ?? "unknown")")
        capture(app, "youtube-live-player")
        XCTAssertEqual(progressResult, .completed, "The live video's playback position must advance")
        app.buttons["closePlayer"].tap()
        XCTAssertTrue(app.buttons[videoID].waitForExistence(timeout: 5))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
