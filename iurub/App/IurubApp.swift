import SwiftUI

@main
struct IurubApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var settings: AppSettings
    @StateObject private var summaries: SummaryStore
    @StateObject private var playback: PlaybackStore

    init() {
        SummaryCredentials.discardLegacyProvisioning()
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let defaults = testing ? UserDefaults(suiteName: "it.davidecarpini.iurub.uitests")! : .standard
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-state") {
            defaults.removePersistentDomain(forName: "it.davidecarpini.iurub.uitests")
            try? SummaryCredentials.remove() // Isolated test Keychain service.
        }
        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("iurub-ui-tests/videos.json")
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-state") {
            try? FileManager.default.removeItem(at: testURL)
        }
        _library = StateObject(wrappedValue: LibraryStore(fileURL: testing ? testURL : nil))
        let preferences = AppSettings(defaults: defaults)
        _settings = StateObject(wrappedValue: preferences)
        let playbackTestURL = FileManager.default.temporaryDirectory.appendingPathComponent("iurub-ui-tests/playback.json")
        let livePlayback = ProcessInfo.processInfo.arguments.contains("--summary-live") || ProcessInfo.processInfo.arguments.contains("--playback-live")
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-state") {
            try? FileManager.default.removeItem(at: playbackTestURL)
        }
        let livePlaybackURL = FileManager.default.temporaryDirectory.appendingPathComponent("iurub-live-tests/playback.json")
        if livePlayback && ProcessInfo.processInfo.arguments.contains("--start-video-at-8") {
            try? FileManager.default.removeItem(at: livePlaybackURL)
        }
        _playback = StateObject(wrappedValue: PlaybackStore(fileURL: testing ? playbackTestURL : (livePlayback ? livePlaybackURL : nil)))
        let conversationURL = FileManager.default.temporaryDirectory.appendingPathComponent("iurub-ui-tests/conversations.json")
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-state") {
            try? FileManager.default.removeItem(at: conversationURL)
        }
        if testing && ProcessInfo.processInfo.arguments.contains("--fixture") {
            _summaries = StateObject(wrappedValue: SummaryStore(fileURL: conversationURL,
                service: FixtureSummaryService(failOnce: ProcessInfo.processInfo.arguments.contains("--summary-error-once")),
                modelProvider: { preferences.summaryModel }, keyProvider: { "fixture-only-not-a-key" }))
        } else {
            _summaries = StateObject(wrappedValue: SummaryStore(fileURL: testing ? conversationURL : nil,
                modelProvider: { preferences.summaryModel }))
        }
        #else
        _library = StateObject(wrappedValue: LibraryStore())
        let preferences = AppSettings()
        _settings = StateObject(wrappedValue: preferences)
        _summaries = StateObject(wrappedValue: SummaryStore(modelProvider: { preferences.summaryModel }))
        _playback = StateObject(wrappedValue: PlaybackStore())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(library)
                .environmentObject(settings)
                .environmentObject(summaries)
                .environmentObject(playback)
                .tint(Theme.accent)
                #if os(macOS)
                .frame(minWidth: 430, minHeight: 780)
                #endif
        }
    }
}
