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
        toggle.tap()
        app.buttons["closeSettings"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Short di prova"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--fixture"]
        app.launch()
        app.buttons["settingsButton"].tap()
        XCTAssertEqual(app.switches["shortsToggle"].value as? String, "1")
        capture("settings-shorts-enabled")
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
