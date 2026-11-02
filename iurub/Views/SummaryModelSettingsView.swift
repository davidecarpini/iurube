import SwiftUI

struct SummaryModelSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var minutes = 30
    @State private var questions = 0
    @State private var liveRates: [SummaryModel: SummaryRates] = [:]

    private func rates(for model: SummaryModel) -> SummaryRates {
        liveRates[model] ?? model.referenceRates
    }

    var body: some View {
        Form {
            Section {
                ForEach(SummaryModel.allCases) { model in
                    Button {
                        settings.summaryModel = model
                    } label: {
                        HStack {
                            Text(model.name).foregroundStyle(.primary)
                            Spacer()
                            if model == settings.summaryModel {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(model == settings.summaryModel ? .isSelected : [])
                    .accessibilityIdentifier("choose-" + model.rawValue)
                }
            } header: { Text("Modello per riassunti e domande") } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("La scelta vale dalla prossima richiesta, anche per i riassunti automatici. Rileggere una chat salvata è gratuito.")
                    if settings.summaryModel == .lite25 || settings.summaryModel == .flash25 {
                        Text("Google può limitare l’accesso ai modelli 2.5. In quel caso puoi scegliere 3.1 Flash-Lite.")
                    }
                }
            }
            Section {
                Picker("Durata del video", selection: $minutes) {
                    ForEach([10, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
                .pickerStyle(.segmented).accessibilityLabel("Durata del video")
                Stepper("Domande per video: \(questions)", value: $questions, in: 0...5)
                    .accessibilityIdentifier("estimateQuestions")
                comparison
            } header: { Text("Quanto spenderei? · USD") } footer: {
                Text("La stima comprende un riassunto per video. Ogni domanda invia di nuovo il video e la conversazione.")
            }
            Section("Come leggere la stima") {
                Text("L’intervallo confronta due risoluzioni. Per secondo ipotizziamo 66–258 token di immagini e 32 di audio. Il costo effettivo dipende dai token elaborati, dal ragionamento e dagli eventuali sconti.")
                Text("Il calcolo include 300 token di istruzioni per richiesta, 1.000 per il riassunto, 100 per domanda e 500 per risposta. Il totale per 30 video assume la stessa durata e lo stesso numero di domande.")
                Link("Come Google calcola i token video", destination: URL(string: "https://ai.google.dev/gemini-api/docs/video-understanding#technical-details")!)
            }.font(.footnote)
            Section {
                ForEach(SummaryModel.allCases) { model in
                    let rate = rates(for: model)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.name).font(.subheadline.weight(.semibold))
                        Text("Video e testo \(rate.input.formatted(.number.precision(.fractionLength(2)))) · Audio \(rate.audio.formatted(.number.precision(.fractionLength(2)))) · Risposta \(rate.output.formatted(.number.precision(.fractionLength(2))))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Link("Listino Google AI Studio", destination: URL(string: "https://ai.google.dev/gemini-api/docs/pricing")!)
            } header: { Text("USD per milione di token") } footer: {
                Text(liveRates.isEmpty ? "Tariffe di riferimento del 2 novembre 2026. Per 3.8 Flash includono la promozione fino al 31 dicembre 2026." : "Tariffe standard lette da OpenRouter per Google AI Studio all’apertura di questa schermata.")
            }
        }
        .navigationTitle("Modello e costi")
        .inlineTitle()
        .task { await refreshRates() }
    }

    @ViewBuilder private var comparison: some View {
        if typeSize.isAccessibilitySize {
            ForEach(SummaryModel.allCases) { model in
                let cost = rates(for: model).estimate(minutes: minutes, questions: questions)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.name).bold()
                    Text("1 video: \(rangeText(cost)) USD")
                    Text("30 video: \(rangeText(cost, count: 30)) USD")
                }
            }
        } else {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    Text("Gemini")
                    Text("1 video").gridColumnAlignment(.trailing)
                    Text("30 video").gridColumnAlignment(.trailing)
                }.foregroundStyle(.secondary)
                ForEach(SummaryModel.allCases) { model in
                    let cost = rates(for: model).estimate(minutes: minutes, questions: questions)
                    GridRow {
                        Text(model.shortName).fontWeight(model == settings.summaryModel ? .bold : .regular)
                        Text(rangeText(cost)).monospacedDigit()
                        Text(rangeText(cost, count: 30)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
        }
    }

    private func rangeText(_ range: ClosedRange<Double>, count: Int = 1) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(count == 1 ? 3 : 2))
        let low = (range.lowerBound * Double(count)).formatted(format)
        let high = (range.upperBound * Double(count)).formatted(format)
        return low + "–" + high
    }

    private func refreshRates() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--fixture") { return }
        #endif
        do {
            liveRates = try await withThrowingTaskGroup(of: (SummaryModel, SummaryRates).self) { group in
                for model in SummaryModel.allCases {
                    group.addTask { (model, try await SummaryRates.current(for: model)) }
                }
                var result: [SummaryModel: SummaryRates] = [:]
                for try await (model, rates) in group { result[model] = rates }
                return result
            }
        } catch {
            // The entire table keeps its dated reference rates when offline.
        }
    }
}
