import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showingCredentials = false
    @State private var hasAPIKey = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $settings.shortsEnabled) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Abilita Shorts")
                                Text(settings.shortsEnabled ? "Gli Shorts sono visibili su YouTube" : "Gli Shorts sono nascosti e bloccati")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "play.rectangle.on.rectangle").foregroundStyle(Theme.accent) }
                    }
                    .accessibilityIdentifier("shortsToggle")
                } header: { Text("La tua esperienza") } footer: {
                    Text("L’impostazione si applica subito a tutte le sezioni, alle ricerche e ai canali. I video brevi pubblicati come video normali rimangono visibili.")
                }
                Section {
                    Toggle(isOn: $settings.automaticSummariesEnabled) {
                        Label("Riassunto automatico nei Salvati", systemImage: "sparkles")
                    }
                    .accessibilityIdentifier("automaticSummariesToggle")
                    NavigationLink {
                        SummaryModelSettingsView()
                    } label: {
                        LabeledContent("Modello e costi", value: settings.summaryModel.shortName)
                    }
                    .accessibilityIdentifier("summaryModelSettings")
                    Button { showingCredentials = true } label: {
                        Label {
                            HStack {
                                Text("OpenRouter")
                                Spacer()
                                Text(hasAPIKey ? "Configurato" : "Aggiungi chiave")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "sparkles").foregroundStyle(Theme.accent) }
                    }.accessibilityIdentifier("summaryCredentialsButton")
                } header: { Text("Riassunti con Gemini") } footer: {
                    Text(settings.automaticSummariesEnabled
                         ? "Quando aggiungi un video ai Salvati, iurub prepara il riassunto usando il tuo credito OpenRouter."
                         : "Il riassunto viene generato solo quando tocchi Riassunto nel video.")
                }
                Section {
                    HStack { BrandMark(); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0").foregroundStyle(.secondary) }
                    Text("Scegli cosa guardare, poi prenditi il tuo tempo.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Il sito, l’account, la playlist e il player YouTube sono gestiti da Google. I video non vengono scaricati.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("iurub") }
            }
            .navigationTitle("Impostazioni")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }.accessibilityIdentifier("closeSettings")
                }
            }
        }
        .onAppear { updateCredentialStatus() }
        .sheet(isPresented: $showingCredentials, onDismiss: updateCredentialStatus) { OpenRouterCredentialsView() }
        #if os(macOS)
        .frame(minWidth: 430, minHeight: 650)
        #endif
    }

    private func updateCredentialStatus() { hasAPIKey = (try? SummaryCredentials.read()) != nil }
}

struct OpenRouterCredentialsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var error: String?
    @State private var hasKey = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(hasKey ? "Incolla una nuova chiave" : "Incolla la tua chiave", text: $key)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .privacySensitive()
                        .accessibilityIdentifier("openRouterKeyField")
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    if hasKey {
                        Button("Rimuovi da questo iPhone", role: .destructive) {
                            do { try SummaryCredentials.remove(); key = ""; hasKey = false; error = nil }
                            catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("removeOpenRouterKey")
                    }
                } header: { Text(hasKey ? "Chiave personale configurata" : "Chiave personale") } footer: {
                    Text("Serve solo per i riassunti e le domande sui video. Rimane nel Portachiavi di questo dispositivo.")
                }
                Section {
                    guideStep("1. Accedi a OpenRouter", detail: "Apri la pagina delle chiavi. Accedi o crea un account: può essere diverso da quello di YouTube.")
                    Link("Apri la pagina delle chiavi", destination: URL(string: "https://openrouter.ai/settings/keys")!)
                        .accessibilityIdentifier("openRouterKeysLink")
                    guideStep("2. Crea una chiave", detail: "Scegli «Create Key», chiamala «iurub» e imposta un limite di spesa. Copia la chiave appena viene mostrata.")
                    guideStep("3. Torna in iurub", detail: "Incolla la chiave nel campo qui sopra e tocca «Salva». Ora puoi aprire un video e scegliere «Riassunto».")
                } header: { Text("Come ottenere la chiave") }
                Section {
                    Text("Riassunti e domande usano il tuo credito OpenRouter. Se il saldo è a zero, puoi aggiungere credito al tuo account. Il limite della chiave non è una ricarica.")
                    Link("Controlla saldo e crediti", destination: URL(string: "https://openrouter.ai/settings/credits")!)
                } header: { Text("Quanto spenderò?") }
            }
            .navigationTitle("OpenRouter").inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("saveOpenRouterKey")
                }
            }
        }
        .onAppear { hasKey = (try? SummaryCredentials.read()) != nil }
        .onDisappear { key = "" }
    }

    private func guideStep(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 3)
    }

    private func save() {
        do {
            try SummaryCredentials.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
            key = ""
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
