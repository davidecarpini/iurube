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

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortsEnabled = defaults.bool(forKey: "shortsEnabled")
        summaryModel = defaults.string(forKey: "summaryModel").flatMap(SummaryModel.init(rawValue:)) ?? .flash25
    }
}
