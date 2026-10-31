import SwiftUI

@main
struct IurubApp: App {
    @StateObject private var library: LibraryStore
    @StateObject private var settings: AppSettings

    init() {
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let defaults = testing ? UserDefaults(suiteName: "it.davidecarpini.iurub.uitests")! : .standard
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-state") {
            defaults.removePersistentDomain(forName: "it.davidecarpini.iurub.uitests")
        }
        let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("iurub-ui-tests/videos.json")
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-state") {
            try? FileManager.default.removeItem(at: testURL)
        }
        _library = StateObject(wrappedValue: LibraryStore(fileURL: testing ? testURL : nil))
        _settings = StateObject(wrappedValue: AppSettings(defaults: defaults))
        #else
        _library = StateObject(wrappedValue: LibraryStore())
        _settings = StateObject(wrappedValue: AppSettings())
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(library)
                .environmentObject(settings)
                .tint(Theme.accent)
                #if os(macOS)
                .frame(minWidth: 430, minHeight: 780)
                #endif
        }
    }
}
