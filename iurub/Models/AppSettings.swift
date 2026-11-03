import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var shortsEnabled: Bool {
        didSet { defaults.set(shortsEnabled, forKey: "shortsEnabled") }
    }
    @Published var summaryModel: SummaryModel {
        didSet { defaults.set(summaryModel.rawValue, forKey: "summaryModel") }
    }
    @Published var automaticSummariesEnabled: Bool {
        didSet { defaults.set(automaticSummariesEnabled, forKey: "automaticSummariesEnabled") }
    }

    @Published var browsesAsGuest: Bool {
        didSet { defaults.set(browsesAsGuest, forKey: "browsesAsGuest") }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        browsesAsGuest = defaults.bool(forKey: "browsesAsGuest")
        shortsEnabled = defaults.bool(forKey: "shortsEnabled")
        automaticSummariesEnabled = defaults.bool(forKey: "automaticSummariesEnabled")
        summaryModel = defaults.string(forKey: "summaryModel").flatMap(SummaryModel.init(rawValue:)) ?? .flash25
    }
}
