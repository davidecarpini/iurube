import XCTest
import AVKit

final class IurubUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-state", "--fixture"]
        app.launch()
    }

    private func openPlayableClip() throws {
        app.terminate()
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "MovingBar", withExtension: "mp4"))
        app.launchEnvironment["IURUB_TEST_CLIP"] = try Data(contentsOf: file).base64EncodedString()
        app.launch()
        let savedVideo = app.webViews.staticTexts["Video già salvato nell’account"]
        XCTAssertTrue(savedVideo.waitForExistence(timeout: 10))
        savedVideo.tap()
        let play = app.webViews.buttons["Riproduci la clip"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        play.tap()
    }

    func testSpeedButtonsControlActualVideoAndStopAtLimits() throws {
        try openPlayableClip()
        let plus = app.buttons["speedUp"], minus = app.buttons["speedDown"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()
        XCTAssertTrue(app.webViews.staticTexts["Velocità effettiva 1.25"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.staticTexts["playbackSpeed"].frame.width, 30, "Il valore completo deve restare leggibile nella riga")
        capture("player-controls")
        for _ in 0..<3 { plus.tap() }
        XCTAssertTrue(app.webViews.staticTexts["Velocità effettiva 2"].waitForExistence(timeout: 5))
        XCTAssertFalse(plus.isEnabled)
        for _ in 0..<6 { minus.tap() }
        XCTAssertTrue(app.webViews.staticTexts["Velocità effettiva 0.5"].waitForExistence(timeout: 5))
        XCTAssertFalse(minus.isEnabled)
    }

    func testRealPictureInPictureContinuesOnHomeScreen() throws {
        try openPlayableClip()
        let pip = app.buttons["pictureInPicture"]
        XCTAssertTrue(pip.waitForExistence(timeout: 5))
        pip.tap()
        if !AVPictureInPictureController.isPictureInPictureSupported() {
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            throw XCTSkip("Questo simulatore non supporta la finestra di sistema. Verificato il messaggio di indisponibilità.")
        }
        let entered = NSPredicate(format: "label == %@", "Riporta il video nell’app")
        expectation(for: entered, evaluatedWith: pip)
        waitForExpectations(timeout: 8)
        func seconds() throws -> Int {
            let clock = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Secondi '")).firstMatch
            return try XCTUnwrap(Int(clock.label.replacingOccurrences(of: "Secondi ", with: "")))
        }
        let start = try seconds()
        XCUIDevice.shared.press(.home)
        let otherApp = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        otherApp.activate()
        XCTAssertTrue(otherApp.wait(for: .runningForeground, timeout: 6))
        // Sample the actual media clock across a full interval outside the app.
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        let end = try seconds()
        XCTContext.runActivity(named: "Video da " + String(start) + " a " + String(end) + " s passando a un’altra app") { _ in }
        XCTAssertGreaterThanOrEqual(end - start, 5, "Il video deve avanzare fuori dall’app")
        XCTAssertTrue(pip.waitForExistence(timeout: 5))
        app.tabBars.buttons["In corso"].tap()
        let inline = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Picture in Picture"), object: pip)
        let restored = XCTWaiter.wait(for: [inline], timeout: 8)
        if restored != .completed { capture("pip-return-diagnostic") }
        XCTAssertEqual(restored, .completed, "Riaprendo In corso il video deve rientrare nel player")
    }

    func testPlayingVideoFloatsAcrossTabsAndKeepsItsPlayhead() throws {
        try openPlayableClip()
        let clock = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Secondi '")).firstMatch
        func seconds() throws -> Int { try XCTUnwrap(Int(clock.label.replacingOccurrences(of: "Secondi ", with: ""))) }
        let moving = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (try? seconds()) ?? 0 >= 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [moving], timeout: 8), .completed)
        let before = try seconds()
        app.tabBars.buttons["Salvati"].tap()
        let mini = app.buttons["miniPlayerExpand"]
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        app.tabBars.buttons["Esplora"].tap()
        XCTAssertTrue(mini.waitForExistence(timeout: 5))
        capture("mini-player-esplora")
        Thread.sleep(forTimeInterval: 4)
        mini.tap()
        XCTAssertTrue(clock.waitForExistence(timeout: 5))
        let after = try seconds()
        XCTContext.runActivity(named: "Cambio tab durante la riproduzione da " + String(before) + " a " + String(after) + " secondi") { _ in }
        XCTAssertGreaterThanOrEqual(after - before, 4)
        XCTAssertTrue(app.tabBars.buttons["In corso"].isSelected)
        app.tabBars.buttons["Salvati"].tap()
        app.buttons["miniPlayerClose"].tap()
        XCTAssertFalse(mini.exists)
    }

    func testInlineVideoContinuesOrResumesAtCheckpointOnReturn() throws {
        try openPlayableClip()
        let clock = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Secondi '")).firstMatch
        func seconds() throws -> Int {
            try XCTUnwrap(Int(clock.label.replacingOccurrences(of: "Secondi ", with: "")))
        }
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (try? seconds()) ?? 0 >= 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 8), .completed)
        let events = app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Media '")).firstMatch
        let initialEvents = events.label
        let start = try seconds()
        XCUIDevice.shared.press(.home)
        let other = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        other.activate()
        XCTAssertTrue(other.wait(for: .runningForeground, timeout: 5))
        Thread.sleep(forTimeInterval: 6)
        app.activate()
        let end = try seconds()
        XCTContext.runActivity(named: initialEvents + " → " + events.label) { _ in }
        XCTContext.runActivity(named: "Riproduzione in background da " + String(start) + " a " + String(end) + " secondi") { _ in }
        if end - start < 6 && !AVPictureInPictureController.isPictureInPictureSupported() {
            // WebKit may suspend inline video on simulators without a system PiP window.
            // Verify the checkpoint and actual subsequent playback in this case.
            let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (try? seconds()) ?? 0 >= start + 2
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [resumed], timeout: 5), .completed)
            let visibleEvent = try XCTUnwrap(events.label.split(separator: " ").last { $0.hasPrefix("visible@") })
            let restoredPosition = try XCTUnwrap(Double(visibleEvent.dropFirst("visible@".count)))
            XCTAssertGreaterThanOrEqual(restoredPosition, Double(start) - 0.5)
        } else {
            XCTAssertGreaterThanOrEqual(end - start, 6)
        }
    }

    func testModelChoicePersistsAndControlsAutomaticSummaryAndFollowUp() throws {
        app.buttons["settingsButton"].tap()
        enableAutomaticSummaries()
        app.buttons["summaryModelSettings"].tap()
        let lite = app.buttons["choose-google/gemini-2.5-flash-lite"]
        XCTAssertTrue(lite.waitForExistence(timeout: 5))
        lite.tap()
        XCTAssertTrue(lite.isSelected)
        capture("model-and-costs")
        app.terminate()
        app.launchArguments = ["--ui-testing", "--fixture"]
        app.launch()
        app.buttons["settingsButton"].tap()
        XCTAssertEqual(app.switches["automaticSummariesToggle"].value as? String, "1")
        app.buttons["summaryModelSettings"].tap()
        XCTAssertTrue(lite.waitForExistence(timeout: 5))
        XCTAssertTrue(lite.isSelected)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["closeSettings"].tap()
        app.tabBars.buttons["Esplora"].tap()
        let save = webBookmark("+ Guarda più tardi")
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(webBookmark("Rimuovi da Guarda più tardi").waitForExistence(timeout: 10))
        app.webViews.staticTexts["Musica per concentrarsi"].tap()
        app.buttons["summaryButton"].tap()
        let attribution = app.staticTexts.matching(identifier: "summaryReplyModel").firstMatch
        XCTAssertTrue(attribution.waitForExistence(timeout: 10))
        XCTAssertEqual(attribution.label, "Gemini 2.5 Flash-Lite")
        app.buttons["closeSummary"].tap()

        app.buttons["settingsButton"].tap()
        app.buttons["summaryModelSettings"].tap()
        app.buttons["choose-google/gemini-3.1-flash-lite"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["closeSettings"].tap()
        app.buttons["summaryButton"].tap()
        XCTAssertEqual(attribution.label, "Gemini 2.5 Flash-Lite")
        app.buttons["Spiegamelo semplice"].tap()
        let followUp = app.staticTexts.matching(identifier: "summaryReplyModel").element(boundBy: 1)
        XCTAssertTrue(followUp.waitForExistence(timeout: 10))
        XCTAssertEqual(followUp.label, "Gemini 3.1 Flash-Lite")
    }

    func testLateOriginalConfirmationChangesBookmarkWithoutAnAlert() throws {
        app.terminate()
        app.launchArguments.append("--late-playlist-toast")
        app.launch()
        app.tabBars.buttons["Esplora"].tap()
        let save = webBookmark("+ Guarda più tardi")
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        save.tap()
        XCTAssertTrue(app.webViews.staticTexts["Salvato in Guarda più tardi"].waitForExistence(timeout: 8))
        let remove = webBookmark("Rimuovi da Guarda più tardi")
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        remove.tap()
        XCTAssertTrue(app.webViews.buttons["Annulla"].waitForExistence(timeout: 8))
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testYouTubePlaylistOpensByDefaultAndAccountSavePersists() throws {
        XCTAssertTrue(app.webViews.staticTexts["Guarda più tardi · account di prova"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.webViews.staticTexts["Video già salvato nell’account"].exists)
        XCTAssertFalse(app.buttons["exploreButton"].exists)
        app.tabBars.buttons["Esplora"].tap()
        let save = webBookmark("+ Guarda più tardi")
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        XCTAssertTrue(app.webViews.staticTexts["Salvato in Guarda più tardi"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Musica per concentrarsi"].waitForExistence(timeout: 10))
        capture("account-watch-later")
        app.terminate()
        app.launchArguments = ["--ui-testing", "--fixture"]
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Musica per concentrarsi"].waitForExistence(timeout: 10))
        let remove = app.webViews.descendants(matching: .any).matching(identifier: "Rimuovi da Guarda più tardi").element(boundBy: 1)
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.webViews.buttons["Annulla"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(app.webViews.staticTexts["Musica per concentrarsi"].exists)
        XCTAssertTrue(app.webViews.staticTexts["Video già salvato nell’account"].exists)
        app.tabBars.buttons["In corso"].tap()
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Video già salvato nell’account"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.staticTexts["Musica per concentrarsi"].exists)
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.switches["shortsToggle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Account YouTube"].exists)
        XCTAssertFalse(app.staticTexts["Archivio locale"].exists)
        XCTAssertFalse(app.buttons["deviceLibraryButton"].exists)
        capture("settings-cleaned")
    }

    func testAccountBookmarkFillsAfterSaveAndRemovesOnSecondTap() throws {
        app.tabBars.buttons["Esplora"].tap()
        let emptyBookmark = webBookmark("+ Guarda più tardi")
        XCTAssertTrue(emptyBookmark.waitForExistence(timeout: 10))
        emptyBookmark.tap()
        let filledBookmark = webBookmark("Rimuovi da Guarda più tardi")
        XCTAssertTrue(filledBookmark.waitForExistence(timeout: 10), "Only a confirmed account save should fill the bookmark")
        XCTAssertFalse(emptyBookmark.exists)
        capture("account-bookmark-filled")
        filledBookmark.tap()
        XCTAssertTrue(emptyBookmark.waitForExistence(timeout: 10), "Tapping the filled bookmark must remove membership")
        XCTAssertTrue(app.webViews.buttons["Annulla"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Video già salvato nell’account"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.staticTexts["Musica per concentrarsi"].exists)
        app.terminate()
        app.launchArguments = ["--ui-testing", "--fixture"]
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Video già salvato nell’account"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.webViews.staticTexts["Musica per concentrarsi"].exists, "The simulated YouTube account must persist removal")
    }

    func testCurrentVideoBookmarkTogglesAndCommentsRemainAccessible() throws {
        app.tabBars.buttons["Esplora"].tap()
        let video = app.webViews.staticTexts["Musica per concentrarsi"]
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        video.tap()
        let bookmark = app.buttons["saveCurrentVideo"]
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        XCTAssertEqual(bookmark.value as? String, "da verificare")
        bookmark.tap()
        let saved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "salvato"), object: bookmark)
        XCTAssertEqual(XCTWaiter.wait(for: [saved], timeout: 10), .completed)
        XCTAssertEqual(bookmark.label, "Rimuovi da Guarda più tardi")
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Musica per concentrarsi"].waitForExistence(timeout: 10))
        app.tabBars.buttons["In corso"].tap()
        bookmark.tap()
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "non salvato"), object: bookmark)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 10), .completed)
        XCTAssertEqual(bookmark.label, "Guarda più tardi")
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Video già salvato nell’account"].waitForExistence(timeout: 10))
        let removedRow = app.webViews["youtube-watchLater"].staticTexts["Musica per concentrarsi"]
        XCTAssertTrue(app.webViews["youtube-watchLater"].waitForExistence(timeout: 5))
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: removedRow)
        XCTAssertEqual(XCTWaiter.wait(for: [refreshed], timeout: 6), .completed)
        app.tabBars.buttons["In corso"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Musica per concentrarsi"].firstMatch.isHittable)
        let recommendations = app.webViews.staticTexts["Video suggerito da nascondere"]
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: recommendations)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        let comment = app.webViews.staticTexts["Secondo commento completo."]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        revealInWebView(comment)
        XCTAssertTrue(comment.isHittable)
        XCTAssertFalse(recommendations.exists)
        capture("video-comments-without-recommendations")
    }

    private func enableAutomaticSummaries() {
        let toggle = app.switches["automaticSummariesToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
    }

    func testSavedVideoWaitsForExplicitSummaryByDefault() throws {
        app.buttons["settingsButton"].tap()
        let toggle = app.switches["automaticSummariesToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        capture("settings-automatic-summaries-off")
        app.buttons["closeSettings"].tap()
        app.tabBars.buttons["Esplora"].tap()
        let bookmark = webBookmark("+ Guarda più tardi")
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        bookmark.tap()
        XCTAssertTrue(webBookmark("Rimuovi da Guarda più tardi").waitForExistence(timeout: 10))
        app.tabBars.buttons["Salvati"].tap()
        let savedVideo = app.webViews.staticTexts["Musica per concentrarsi"]
        XCTAssertTrue(savedVideo.waitForExistence(timeout: 10))
        savedVideo.tap()
        let summary = app.buttons["summaryButton"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        XCTAssertEqual(summary.value as? String, "Da preparare", "Neither saving nor opening the video starts an automatic request")
        summary.tap()
        XCTAssertTrue(app.staticTexts["summaryReply"].waitForExistence(timeout: 10))
    }

    func testConfirmedSavePrefetchesSummaryBeforeOpeningChat() throws {
        app.buttons["settingsButton"].tap()
        enableAutomaticSummaries()
        app.buttons["closeSettings"].tap()
        let id = "jfKfPfyJRdk"
        func prefetchStatus() -> [String: Any]? {
            let status = app.staticTexts["summaryPrefetchStatus"]
            guard status.exists, let data = status.label.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        app.tabBars.buttons["Esplora"].tap()
        let bookmark = webBookmark("+ Guarda più tardi")
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
        XCTAssertFalse((prefetchStatus()?["ready"] as? [String] ?? []).contains(id))
        bookmark.tap()
        XCTAssertTrue(webBookmark("Rimuovi da Guarda più tardi").waitForExistence(timeout: 10))
        let prefetched = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (prefetchStatus()?["ready"] as? [String] ?? []).contains(id)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [prefetched], timeout: 10), .completed, "A confirmed save must prepare the summary before the modal is opened")
        XCTAssertEqual((prefetchStatus()?["counts"] as? [String: Int])?[id], 1)
        app.webViews.staticTexts["Musica per concentrarsi"].tap()
        XCTAssertTrue(app.buttons["summaryButton"].waitForExistence(timeout: 10))
        app.buttons["summaryButton"].tap()
        let replies = app.staticTexts.matching(identifier: "summaryReply")
        XCTAssertTrue(replies.firstMatch.waitForExistence(timeout: 3))
        let summary = replies.firstMatch.label
        XCTAssertFalse(app.buttons["cancelSummary"].exists, "The cached summary should not start another request")
        XCTAssertEqual(replies.count, 1)
        capture("summary-prefetched-on-save")
        app.buttons["closeSummary"].tap()
        XCTAssertEqual((prefetchStatus()?["counts"] as? [String: Int])?[id], 1)
        app.buttons["summaryButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", summary)).firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(replies.count, 1)
        XCTAssertFalse(app.buttons["cancelSummary"].exists)
        app.buttons["closeSummary"].tap()
        XCTAssertEqual((prefetchStatus()?["counts"] as? [String: Int])?[id], 1)
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

    func testVideoSummaryChatPersistsAcrossReopenAndRestart() throws {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-state", "--fixture", "--summary-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["summaryButton"].waitForExistence(timeout: 10))
        app.buttons["summaryButton"].tap()
        let replies = app.staticTexts.matching(identifier: "summaryReply")
        XCTAssertTrue(replies.firstMatch.waitForExistence(timeout: 10))
        let initialSummary = replies.firstMatch.label
        XCTAssertFalse(initialSummary.isEmpty)
        capture("summary-initial")
        let input = app.descendants(matching: .any).matching(identifier: "summaryInput").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Quali sono i punti principali?")
        app.buttons["sendSummaryQuestion"].tap()
        XCTAssertTrue(replies.element(boundBy: 1).waitForExistence(timeout: 10))
        let followUp = replies.element(boundBy: 1).label
        XCTAssertFalse(followUp.isEmpty)
        capture("summary-follow-up")
        app.buttons["closeSummary"].tap()
        app.buttons["summaryButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", followUp)).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(replies.count, 2, "Reopening a saved chat must not regenerate the summary")
        app.terminate()
        app.launchArguments = ["--ui-testing", "--fixture", "--summary-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["summaryButton"].waitForExistence(timeout: 10))
        app.buttons["summaryButton"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", followUp)).firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(replies.count, 2)
        capture("summary-restored")
    }

    func testVideoSummaryCanRetryAfterFailure() throws {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--reset-state", "--fixture", "--summary-fixture", "--summary-error-once"]
        app.launch()
        XCTAssertTrue(app.buttons["summaryButton"].waitForExistence(timeout: 10))
        app.buttons["summaryButton"].tap()
        XCTAssertTrue(app.buttons["summaryRetry"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["summaryReply"].exists)
        capture("summary-error")
        app.buttons["closeSummary"].tap()
        app.buttons["summaryButton"].tap()
        XCTAssertTrue(app.buttons["summaryRetry"].waitForExistence(timeout: 5), "Reopening a failed chat must not automatically issue another paid request")
        XCTAssertFalse(app.staticTexts["summaryReply"].exists)
        app.buttons["summaryRetry"].tap()
        XCTAssertTrue(app.staticTexts["summaryReply"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["summaryRetry"].exists)
        capture("summary-retry-success")
    }

    func testFiveTabsToolbarProfileAndPageRefresh() throws {
        XCTAssertTrue(app.webViews.staticTexts["Guarda più tardi · account di prova"].waitForExistence(timeout: 10))
        let labels = ["In corso", "Salvati", "Iscrizioni", "Cronologia", "Esplora"]
        let buttons = labels.map { app.tabBars.buttons[$0] }
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        for button in buttons { XCTAssertTrue(button.exists) }
        for index in 0..<4 { XCTAssertLessThan(buttons[index].frame.midX, buttons[index + 1].frame.midX) }
        XCTAssertTrue(app.tabBars.buttons["Salvati"].isSelected)
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
        for (tab, rootHeading) in [
            ("Salvati", "Guarda più tardi · account di prova"),
            ("Iscrizioni", "Iscrizioni · fixture di test"),
            ("Cronologia", "Cronologia · fixture di test"),
            ("Esplora", "Home · fixture di test")
        ] {
            app.tabBars.buttons[tab].tap()
            app.buttons["profileButton"].tap()
            XCTAssertTrue(app.webViews.staticTexts["Tu · fixture di test"].waitForExistence(timeout: 10))
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.webViews.staticTexts[rootHeading].waitForExistence(timeout: 10), "Tapping the selected tab must return to that section's root")
        }
        capture("five-tabs-navigation")
    }

    func testInProgressResumesAcrossTabsRestartAndDifferentVideos() throws {
        XCTAssertTrue(app.tabBars.buttons["Salvati"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Salvati"].isSelected)
        app.tabBars.buttons["In corso"].tap()
        XCTAssertTrue(app.staticTexts["Un video alla volta"].waitForExistence(timeout: 5))
        app.buttons["inProgressAction"].tap()
        let firstVideo = app.webViews.staticTexts["Video già salvato nell’account"]
        XCTAssertTrue(firstVideo.waitForExistence(timeout: 10))
        firstVideo.tap()
        let seek = app.webViews.buttons["Avanza a 42 secondi"]
        XCTAssertTrue(seek.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["In corso"].isSelected)
        seek.tap()
        XCTAssertTrue(app.webViews.staticTexts["Posizione: 42 s"].waitForExistence(timeout: 5))
        capture("in-progress-42-seconds")
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(firstVideo.waitForExistence(timeout: 10))
        app.tabBars.buttons["In corso"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Posizione: 42 s"].waitForExistence(timeout: 5))
        app.tabBars.buttons["In corso"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Posizione: 42 s"].waitForExistence(timeout: 5), "Retapping In corso must preserve the playhead")
        app.terminate()
        app.launchArguments = ["--ui-testing", "--fixture"]
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Posizione: 42 s"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["In corso"].isSelected)
        capture("in-progress-restored")
        app.tabBars.buttons["Esplora"].tap()
        let secondVideo = app.webViews.staticTexts["Musica per concentrarsi"]
        let explored = secondVideo.waitForExistence(timeout: 10)
        if !explored { capture("esplora-dopo-ripresa") }
        XCTAssertTrue(explored, "La tab Esplora deve aprire il feed anche dopo la ripresa di un video")
        secondVideo.tap()
        XCTAssertTrue(app.webViews.staticTexts["Posizione: 0 s"].waitForExistence(timeout: 10), "A different video must not inherit the previous playhead")
        XCTAssertTrue(app.tabBars.buttons["In corso"].isSelected)
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(firstVideo.waitForExistence(timeout: 10))
        firstVideo.tap()
        XCTAssertTrue(app.webViews.staticTexts["Posizione: 42 s"].waitForExistence(timeout: 10), "Each video restores its own bookmark")
        app.webViews.buttons["Termina video"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Posizione: 300 s"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--fixture"]
        app.launch()
        XCTAssertTrue(firstVideo.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Salvati"].isSelected, "A completed video must not automatically resume on launch")
    }

    private func webBookmark(_ label: String) -> XCUIElement {
        // WebKit may expose an HTML button with aria-pressed as a toggle/switch.
        // Match its exact accessible name without assuming the platform AX role.
        app.webViews.descendants(matching: .any).matching(identifier: label).firstMatch
    }

    private func revealInWebView(_ element: XCUIElement) {
        for _ in 0..<5 {
            if element.isHittable { return }
            app.webViews.firstMatch.swipeUp()
        }
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
    func testLiveFlashLite25ReturnsVideoSummaryAndCost() throws {
        try checkLiveSummary(modelID: "google/gemini-2.5-flash-lite", name: "Gemini 2.5 Flash-Lite")
    }

    func testLiveFlashLite31ReturnsVideoSummaryAndCost() throws {
        try checkLiveSummary(modelID: "google/gemini-3.1-flash-lite", name: "Gemini 3.1 Flash-Lite")
    }

    private func checkLiveSummary(modelID: String, name: String) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_MODEL_LIVE"] == "1", "Uses OpenRouter for a 19-second public video")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-state", "--summary-live"]
        app.launch()
        XCTAssertTrue(app.buttons["summaryButton"].waitForExistence(timeout: 30))
        app.buttons["settingsButton"].tap()
        app.buttons["summaryModelSettings"].tap()
        app.buttons["choose-" + modelID].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["closeSettings"].tap()
        app.buttons["summaryButton"].tap()
        let source = app.staticTexts["summaryReplyModel"]
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            source.exists || app.buttons["summaryRetry"].exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 180), .completed)
        capture("live-" + name, app: app)
        XCTAssertTrue(source.exists, "Provider did not return a successful summary")
        XCTAssertTrue(source.label.hasPrefix(name + " · "), "Show the model and actual charge")
    }

    private func openPlayingPublicVideo(checkLayout: Bool = false) throws -> (XCUIApplication, () -> Double?) {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_PLAYBACK_LIVE"] == "1", "Requires public YouTube playback")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = checkLayout ? ["--playback-live", "--watch-layout-probe"] : ["--playback-live"]
        app.launch()
        app.open(try XCTUnwrap(URL(string: "iurub://open?url=https%3A%2F%2Fm.youtube.com%2Fwatch%3Fv%3Daqz-KE-bpKQ%26t%3D30s")))
        func position() -> Double? {
            let status = app.staticTexts["livePlaybackStatus"]
            guard status.exists, let data = status.label.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let video = record["video"] as? [String: Any], video["id"] as? String == "aqz-KE-bpKQ",
                  let duration = record["duration"] as? Double, duration > 90 else { return nil }
            return record["position"] as? Double
        }
        let play = app.webViews.buttons.matching(NSPredicate(format: "label == 'Riproduci' OR label == 'Play'")).firstMatch
        if play.waitForExistence(timeout: 15), play.isHittable { play.tap() }
        for _ in 0..<3 {
            let moving = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (position() ?? 0) >= 34 }, object: nil)
            if XCTWaiter.wait(for: [moving], timeout: 8) == .completed { break }
            if play.exists && play.isHittable { play.tap() }
        }
        let start = try XCTUnwrap(position())
        XCTAssertGreaterThanOrEqual(start, 34, "Il sito deve confermare che il video è in riproduzione")
        return (app, position)
    }

    func testPublicVideoContinuesAcrossTabs() throws {
        let (app, position) = try openPlayingPublicVideo(checkLayout: true)
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(app.buttons["miniPlayerExpand"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Esplora"].tap()
        XCTAssertTrue(app.tabBars.buttons["Esplora"].isSelected)
        let start = try XCTUnwrap(position())
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (position() ?? 0) >= start + 6 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [advanced], timeout: 16), .completed)
        let end = try XCTUnwrap(position())
        XCTContext.runActivity(named: "YouTube in Esplora da " + String(start) + " a " + String(end) + " secondi") { _ in }
        capture("youtube-mini-player-esplora", app: app)
        app.buttons["miniPlayerExpand"].tap()
        XCTAssertTrue(app.tabBars.buttons["In corso"].isSelected)
        waitForLayout(in: app) { $0["titleVisible"] as? Bool == true }
        capture("playing-title-after-return", app: app)
    }

    func testBackgroundOnPublicYouTubeVideo() throws {
        let (app, position) = try openPlayingPublicVideo()
        let start = try XCTUnwrap(position())
        XCUIDevice.shared.press(.home)
        let other = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        other.activate()
        XCTAssertTrue(other.wait(for: .runningForeground, timeout: 6))
        Thread.sleep(forTimeInterval: 10)
        app.activate()
        let end = try XCTUnwrap(position())
        XCTContext.runActivity(named: "Video YouTube da " + String(start) + " a " + String(end) + " secondi") { _ in }
        if end - start < 9 && !AVPictureInPictureController.isPictureInPictureSupported() {
            XCTAssertGreaterThanOrEqual(end, start - 1, "Il sito deve conservare il punto di visione")
            throw XCTSkip("WebKit ha sospeso il video YouTube sul simulatore privo di Picture in Picture.")
        }
        XCTAssertGreaterThanOrEqual(end - start, 9, "Il video deve continuare con un’altra app in primo piano")
    }

    func testSpeedOnPublicYouTubeVideo() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_PLAYBACK_LIVE"] == "1", "Requires public YouTube playback")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--playback-live", "--start-video-at-8", "--pause-restored-video"]
        app.launch()
        let plus = app.buttons["speedUp"], rate = app.staticTexts["playbackSpeed"]
        XCTAssertTrue(plus.waitForExistence(timeout: 20))
        let play = app.webViews.buttons.matching(NSPredicate(format: "label == 'Riproduci' OR label == 'Play'")).firstMatch
        _ = play.waitForExistence(timeout: 15)
        let minus = app.buttons["speedDown"]
        var original: Double?
        for _ in 0..<3 {
            if let value = rate.value as? String, let number = Double(value) { original = number; break }
            if play.exists && play.isHittable { play.tap() }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (rate.value as? String).flatMap(Double.init) != nil
            }, object: nil)
            if XCTWaiter.wait(for: [ready], timeout: 8) == .completed {
                original = (rate.value as? String).flatMap(Double.init); break
            }
        }
        if original == nil { capture("youtube-player-not-ready", app: app) }
        let initial = try XCTUnwrap(original, "YouTube deve aver caricato i metadati del video")
        let increasing = plus.isEnabled
        (increasing ? plus : minus).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let current = (rate.value as? String).flatMap(Double.init) else { return false }
            return increasing ? current > initial : current < initial
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
        capture("youtube-player-speed", app: app)
        (increasing ? minus : plus).tap()
        expectation(for: NSPredicate(format: "value == %@", String(initial)), evaluatedWith: rate)
        waitForExpectations(timeout: 8)
    }

    private func layout(in app: XCUIApplication) -> [String: Any] {
        let status = app.staticTexts["watchLayoutStatus"]
        guard status.exists, let data = status.label.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func waitForLayout(in app: XCUIApplication, _ matches: @escaping ([String: Any]) -> Bool) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in matches(self.layout(in: app)) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, "Watch layout: \(layout(in: app))")
    }

    func testRealVideoCommentsRemainAccessible() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_LAYOUT_LIVE"] == "1", "Requires the public YouTube watch page")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--playback-live", "--start-video-at-8", "--pause-restored-video", "--watch-layout-probe"]
        app.launch()
        XCTAssertTrue(app.buttons["summaryButton"].waitForExistence(timeout: 30))
        waitForLayout(in: app) { ($0["threads"] as? Int ?? 0) >= 3 && $0["titleVisible"] as? Bool == true && ($0["lastVisible"] as? Int ?? -1) >= 0 }
        capture("real-watch-comments-open", app: app)
        let before = try XCTUnwrap(layout(in: app)["lastVisible"] as? Int)
        let page = app.webViews["youtube-player"]
        let bottom = page.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.95))
        let higher = page.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.55))
        bottom.press(forDuration: 0.08, thenDragTo: higher)
        waitForLayout(in: app) { ($0["lastVisible"] as? Int ?? -1) > before }
        capture("real-watch-more-comments", app: app)
        app.tabBars.buttons["Salvati"].tap()
        app.tabBars.buttons["In corso"].tap()
        waitForLayout(in: app) { $0["titleVisible"] as? Bool == true }
        capture("real-watch-return-title", app: app)
        app.tabBars.buttons["Esplora"].tap()
        let feed = app.webViews["youtube-home"]
        let bookmark = feed.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@", "+ Guarda più tardi", "Rimuovi da Guarda più tardi")).firstMatch
        let menu = feed.buttons.matching(NSPredicate(format: "label IN %@", ["Altre azioni", "More actions", "Menu Azione", "Action menu"])).firstMatch
        XCTAssertTrue(bookmark.waitForExistence(timeout: 25))
        XCTAssertTrue(menu.isHittable && bookmark.isHittable)
        XCTAssertLessThanOrEqual(menu.frame.maxX, bookmark.frame.minX)
        XCTAssertEqual(menu.frame.midY, bookmark.frame.midY, accuracy: 4)
        capture("real-explore-actions", app: app)
    }

    func testRealVideoResumeAfterRestart() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_PLAYBACK_LIVE"] == "1", "Requires public YouTube playback")
        continueAfterFailure = false
        let app = XCUIApplication()
        var previousUpdate = 0.0
        func currentRecord() -> [String: Any]? {
            let status = app.staticTexts["livePlaybackStatus"]
            guard status.exists, let data = status.label.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        func confirmedRecord() -> [String: Any]? {
            guard let record = currentRecord(),
                  let video = record["video"] as? [String: Any], video["id"] as? String == "jNQXAC9IVRw",
                  let position = record["position"] as? Double, abs(position - 8) < 1,
                  let duration = record["duration"] as? Double, (18...25).contains(duration),
                  let updated = record["updatedAt"] as? Double, updated > previousUpdate,
                  record["completed"] as? Bool == false else { return nil }
            return record
        }
        for phase in ["first", "restored"] {
            app.launchArguments = ["--playback-live", "--pause-restored-video"]
            if phase == "first" { app.launchArguments.append("--start-video-at-8") }
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["In corso"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.tabBars.buttons["In corso"].isSelected)
            if phase == "restored", let updated = currentRecord()?["updatedAt"] as? Double {
                previousUpdate = max(previousUpdate, updated)
            }
            let play = app.webViews.buttons.matching(NSPredicate(format: "label == 'Riproduci' OR label == 'Play'")).firstMatch
            XCTAssertTrue(play.waitForExistence(timeout: 30))
            var confirmed = false
            // YouTube can expose the thumbnail's Play before its player has
            // finished loading. Retry that visible control, never synthesize progress.
            for _ in 0..<3 {
                if play.exists && play.isHittable { play.tap() }
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in confirmedRecord() != nil }, object: nil)
                if XCTWaiter.wait(for: [ready], timeout: 10) == .completed { confirmed = true; break }
            }
            if !confirmed { capture("youtube-playback-loading-timeout", app: app) }
            XCTAssertTrue(confirmed, "The real media element must confirm its duration and restored position")
            let record = try XCTUnwrap(confirmedRecord())
            previousUpdate = try XCTUnwrap(record["updatedAt"] as? Double)
            let evidence = XCTAttachment(data: try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            evidence.name = "youtube-playback-\(phase)-actual-media"
            evidence.lifetime = .keepAlways
            add(evidence)
            capture("youtube-in-progress-\(phase)", app: app)
            if phase == "restored" {
                app.buttons["profileButton"].tap()
                XCTAssertTrue(app.webViews.staticTexts["Cronologia"].firstMatch.waitForExistence(timeout: 30))
                XCTAssertTrue(app.buttons["backButton"].isEnabled)
                app.buttons["backButton"].tap()
                XCTAssertTrue(app.buttons["summaryButton"].waitForExistence(timeout: 30))
                let root = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"), object: app.buttons["backButton"])
                XCTAssertEqual(XCTWaiter.wait(for: [root], timeout: 10), .completed,
                               "Back must traverse the existing history instead of appending another video page")
                let resumed = try XCTUnwrap(currentRecord()?["position"] as? Double)
                XCTAssertEqual(resumed, 8, accuracy: 1)
                capture("youtube-player-after-back", app: app)
            }
            app.terminate()
        }
    }

    // Opt-in: uses the configured OpenRouter account for one short public video.
    func testRealVideoSummaryAndGroundedFollowUp() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_SUMMARY_LIVE"] == "1", "Requires a configured OpenRouter key")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--summary-live"]
        app.launch()
        XCTAssertTrue(app.buttons["summaryButton"].waitForExistence(timeout: 30))
        capture("gemini-video-button", app: app)
        app.buttons["summaryButton"].tap()
        let replies = app.staticTexts.matching(identifier: "summaryReply")
        XCTAssertTrue(replies.firstMatch.waitForExistence(timeout: 180))
        capture("gemini-live-summary", app: app)
        let input = app.descendants(matching: .any).matching(identifier: "summaryInput").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Quale caratteristica degli elefanti viene descritta?")
        app.buttons["sendSummaryQuestion"].tap()
        let stop = app.buttons["cancelSummary"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: stop)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 180), .completed)
        XCTAssertFalse(app.buttons["summaryRetry"].exists, "The live provider request must complete successfully")
        let answer = try XCTUnwrap(replies.allElementsBoundByIndex.last?.label).lowercased()
        XCTAssertTrue(answer.contains("elefant") || answer.contains("proboscid"), "The follow-up must discuss the actual elephants in the video")
        capture("gemini-live-follow-up", app: app)
        app.buttons["closeSummary"].tap()
    }

    func testExistingYouTubeWatchLater() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_LIVE"] == "1", "Requires a YouTube session")
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Salvati"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(app.buttons["refreshPage"].waitForExistence(timeout: 10))
        let playlistRow = app.webViews.buttons["Rimuovi da Guarda più tardi"].firstMatch
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 30))
        XCTAssertTrue(playlistRow.isHittable)
        XCTAssertLessThan(playlistRow.frame.minY, app.webViews.firstMatch.frame.minY + 220,
                          "The first video must be near the top, without a large playlist hero")
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
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 30))
        XCTAssertGreaterThanOrEqual(app.webViews.firstMatch.frame.maxY, app.frame.maxY - 1)
        XCTAssertFalse(app.webViews.buttons["Home"].exists)
        XCTAssertFalse(app.webViews.buttons["Tu"].exists)
        app.buttons["profileButton"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Cronologia"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["backButton"].isEnabled)
        capture("youtube-tu", app: app)
        app.buttons["backButton"].tap()
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 30))
        for label in ["Iscrizioni", "Cronologia", "Esplora"] {
            app.tabBars.buttons[label].tap()
            XCTAssertTrue(app.buttons["refreshPage"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.webViews.links.firstMatch.waitForExistence(timeout: 30))
            capture("youtube-\(label.lowercased())", app: app)
            print("NAVIGATION \(label): \(app.webViews.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label))")
        }
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(playlistRow.waitForExistence(timeout: 30))
        capture("youtube-salvati-navigation", app: app)
        XCTAssertFalse(app.webViews.buttons["Riproduci tutto"].exists, "The large playlist hero is hidden")
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["summaryCredentialsButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Account YouTube"].exists)
        XCTAssertFalse(app.staticTexts["Archivio locale"].exists)
        capture("youtube-settings", app: app)
        app.buttons["closeSettings"].tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

final class EntryUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testGuestCanCancelBrowseAndConnectWithoutLosingTheAccountAtRelaunch() throws {
        app.launchArguments = ["--ui-testing", "--reset-state", "--fixture", "--guest-fixture"]
        app.launch()
        let signIn = app.buttons["welcomeSignIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        capture("ingresso-ospite")
        signIn.tap()
        XCTAssertTrue(app.buttons["closeSignIn"].waitForExistence(timeout: 5))
        app.buttons["closeSignIn"].tap()
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        app.buttons["welcomeExplore"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Musica per concentrarsi"].waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["--ui-testing", "--fixture", "--guest-fixture"]
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Musica per concentrarsi"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Salvati"].tap()
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()
        let confirm = app.webViews.buttons["Conferma account di prova"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 6))
        confirm.tap()
        XCTAssertTrue(app.buttons["closeSignIn"].waitForNonExistence(timeout: 12), "Dismiss only after YouTube confirms the account")
        let signedRow = app.webViews["youtube-watchLater"].staticTexts["Video già salvato nell’account"]
        XCTAssertTrue(signedRow.waitForExistence(timeout: 8))
        XCTAssertTrue(signedRow.isHittable)
        XCTAssertFalse(signIn.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Video già salvato nell’account"].waitForExistence(timeout: 8))
        XCTAssertFalse(signIn.exists)
    }

    private func simulateInterruptedReturn(_ flag: String) {
        app.launchArguments = ["--ui-testing", "--reset-state", "--fixture", "--guest-fixture", flag]
        app.launch()
        let login = app.buttons["welcomeSignIn"]
        XCTAssertTrue(login.waitForExistence(timeout: 10))
        login.tap()
        let confirm = app.webViews.buttons["Conferma account di prova"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        confirm.tap()
    }

    private func assertArrivedInSaved() {
        XCTAssertTrue(app.buttons["closeSignIn"].waitForNonExistence(timeout: 14))
        let row = app.webViews["youtube-watchLater"].staticTexts["Video già salvato nell’account"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.isHittable)
        XCTAssertTrue(app.tabBars.buttons["Salvati"].isSelected)
    }

    func testInterruptedReturnAfterConfirmationOpensSavedAutomatically() {
        simulateInterruptedReturn("--interrupt-login-return")
        assertArrivedInSaved()
    }

    func testAcceptedLoginWithoutReturnNavigationStillOpensSaved() {
        simulateInterruptedReturn("--stalled-login-return")
        assertArrivedInSaved()
    }

    func testRetryChecksExistingSessionWithoutAskingForCredentialsAgain() {
        simulateInterruptedReturn("--retry-login-return")
        let retry = app.buttons["retrySignIn"]
        XCTAssertTrue(retry.waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["Usa YouTube nel browser"].exists)
        capture("riprova-nel-client")
        retry.tap()
        assertArrivedInSaved()
    }

    func testInterruptedGuestLoginRetriesInsideTheClientAndDoesNotUnlockSaved() {
        simulateInterruptedReturn("--interrupt-before-login")
        let retry = app.buttons["retrySignIn"]
        XCTAssertTrue(retry.waitForExistence(timeout: 6))
        retry.tap()
        let confirm = app.webViews.buttons["Conferma account di prova"]
        XCTAssertTrue(retry.waitForNonExistence(timeout: 8))
        XCTAssertTrue(confirm.waitForExistence(timeout: 8))
        XCTAssertTrue(confirm.isHittable)
        XCTAssertTrue(app.buttons["closeSignIn"].exists)
        confirm.tap()
        assertArrivedInSaved()
    }

    func testInterruptedReturnRecoversTheExistingRealYouTubeSession() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_ENTRY_LIVE"] == "1")
        app.launchArguments = ["--ui-testing", "--reset-state", "--live-login-return"]
        app.launch()
        let interrupt = app.webViews.buttons["Conferma account di prova"]
        XCTAssertTrue(interrupt.waitForExistence(timeout: 12))
        interrupt.tap() // Only the redirect error is simulated; Watch Later is fetched from YouTube.
        XCTAssertTrue(app.buttons["closeSignIn"].waitForNonExistence(timeout: 20))
        let row = app.webViews.descendants(matching: .any).matching(identifier: "Rimuovi da Guarda più tardi").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 25))
        XCTAssertTrue(app.tabBars.buttons["Salvati"].isSelected)
        XCTAssertFalse(app.buttons["welcomeSignIn"].exists)
    }

    func testFreshYouTubeSessionReachesOfficialGoogleFormAndCanCancel() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_ENTRY_LIVE"] == "1")
        app.launchArguments = ["--ui-testing", "--reset-state", "--guest-live"]
        app.launch()
        let signIn = app.buttons["welcomeSignIn"]
        let reject = app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES[c] %@", "(Reject all|Rifiuta tutto|Rifiuta tutte le opzioni)")).firstMatch
        if !signIn.waitForExistence(timeout: 8), reject.waitForExistence(timeout: 12) { reject.tap() }
        XCTAssertTrue(signIn.waitForExistence(timeout: 22), "An unauthenticated YouTube session must show the invitation")
        capture("benvenuto-youtube-reale")
        signIn.tap()
        let google = app.staticTexts["accounts.google.com"]
        XCTAssertTrue(google.waitForExistence(timeout: 30))
        let email = app.webViews.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 20), "The first-party sign-in identifier field must appear")
        capture("accesso-google-reale")
        app.buttons["closeSignIn"].tap()
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        app.buttons["welcomeExplore"].tap()
        XCTAssertTrue(app.tabBars.buttons["Esplora"].isSelected)
    }

    func testExistingLiveYouTubeSessionOpensSavedWithoutAnInvitation() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["IURUB_ENTRY_LIVE"] == "1")
        app.launchArguments = ["--ui-testing", "--reset-state"]
        app.launch()
        let row = app.webViews.descendants(matching: .any).matching(identifier: "Rimuovi da Guarda più tardi").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["welcomeSignIn"].exists)
    }
}
