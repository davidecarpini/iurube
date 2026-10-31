import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var shortsEnabled: Bool {
        didSet { defaults.set(shortsEnabled, forKey: "shortsEnabled") }
    }
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortsEnabled = defaults.bool(forKey: "shortsEnabled")
    }
}
