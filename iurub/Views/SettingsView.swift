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
                    Text("Quando salvi un video in Guarda più tardi, inizia la preparazione del riassunto. Tocca Riassunto per leggerlo e fare domande. Le richieste usano il credito OpenRouter.")
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Chiave API OpenRouter", text: $key)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .privacySensitive()
                        .accessibilityIdentifier("openRouterKeyField")
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                } header: { Text("Chiave API") } footer: {
                    Text("La chiave viene conservata nel Portachiavi di questo dispositivo. Non viene mostrata nelle chat né inclusa nei salvataggi.")
                }
                Section {
                    Text("Gemini analizza i video pubblici di YouTube tramite OpenRouter. I video privati o con limitazioni di accesso potrebbero non essere disponibili.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
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
        .onDisappear { key = "" }
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
