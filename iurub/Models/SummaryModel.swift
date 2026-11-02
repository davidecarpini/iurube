import Foundation

enum SummaryModel: String, CaseIterable, Identifiable, Sendable {
    case lite25 = "google/gemini-2.5-flash-lite"
    case lite31 = "google/gemini-3.1-flash-lite"
    case flash25 = "google/gemini-2.5-flash"
    case flash38 = "google/gemini-3.8-flash"

    var id: String { rawValue }
    var shortName: String {
        switch self {
        case .lite25: return "2.5 Flash-Lite"
        case .lite31: return "3.1 Flash-Lite"
        case .flash25: return "2.5 Flash"
        case .flash38: return "3.8 Flash"
        }
    }
    var name: String { "Gemini " + shortName }

    // USD per million tokens, Google AI Studio standard endpoints, 2 November 2026.
    var referenceRates: SummaryRates {
        switch self {
        case .lite25: return SummaryRates(input: 0.10, audio: 0.30, output: 0.40)
        case .lite31: return SummaryRates(input: 0.25, audio: 0.50, output: 1.50)
        case .flash25: return SummaryRates(input: 0.30, audio: 1.00, output: 2.50)
        case .flash38: return SummaryRates(input: 0.75, audio: 0.75, output: 3.75)
        }
    }
}

struct SummaryRates: Equatable, Sendable {
    let input: Double
    let audio: Double
    let output: Double

    // Two static video resolutions, one frame per second and 32 audio tokens/s.
    // Each follow-up resends the video, instructions and preceding conversation.
    func estimate(minutes: Int, questions: Int) -> ClosedRange<Double> {
        let requests = 1 + questions
        let seconds = Double(minutes * 60 * requests)
        var textTokens = 300
        var outputTokens = 1_000
        for previousQuestions in 0..<questions {
            textTokens += 300 + 1_000 + 100 + previousQuestions * 600
            outputTokens += 500
        }
        let otherCosts = seconds * 32 * audio + Double(textTokens) * input + Double(outputTokens) * output
        let low = (seconds * 66 * input + otherCosts) / 1_000_000
        let high = (seconds * 258 * input + otherCosts) / 1_000_000
        return low...high
    }

    static func current(for model: SummaryModel) async throws -> SummaryRates {
        let url = URL(string: "https://openrouter.ai/api/v1/models/\(model.rawValue)/endpoints")!
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 8))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decodeEndpoint(data, model: model)
    }

    static func decodeEndpoint(_ data: Data, model: SummaryModel) throws -> SummaryRates {
        struct Catalog: Decodable {
            struct Model: Decodable {
                struct Endpoint: Decodable {
                    let tag: String
                    struct Prices: Decodable {
                        let prompt: String?
                        let audio: String?
                        let completion: String?
                    }
                    let pricing: Prices
                }
                let id: String
                let endpoints: [Endpoint]
            }
            let data: Model
        }
        let catalog = try JSONDecoder().decode(Catalog.self, from: data).data
        guard catalog.id == model.rawValue,
              let prices = catalog.endpoints.first(where: { $0.tag == "google-ai-studio" })?.pricing else {
            throw URLError(.cannotParseResponse)
        }
        func perMillion(_ raw: String?) throws -> Double {
            guard let raw, let value = Double(raw), value.isFinite, value >= 0 else {
                throw URLError(.cannotParseResponse)
            }
            return value * 1_000_000
        }
        return try SummaryRates(input: perMillion(prices.prompt), audio: perMillion(prices.audio), output: perMillion(prices.completion))
    }
}
