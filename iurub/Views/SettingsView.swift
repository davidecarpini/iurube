import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
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
                    Text("L’impostazione si applica subito alla Home, alle ricerche e ai canali. I video brevi pubblicati come video normali rimangono visibili.")
                }
                Section {
                    Label("Salvati su questo dispositivo", systemImage: "internaldrive")
                    Text("La lista di iurub è personale e locale. Non è sincronizzata con la playlist “Guarda più tardi” del tuo account YouTube.")
                        .foregroundStyle(.secondary)
                    Text("Puoi salvare video senza accedere a Google. Per riprodurli serve una connessione Internet.")
                        .foregroundStyle(.secondary)
                } header: { Text("Guarda più tardi") }
                Section {
                    Text("Puoi provare ad accedere dal sito YouTube nella Home. Google potrebbe non consentire il login all’interno dell’app: la lista di iurub continuerà comunque a funzionare.")
                        .foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://m.youtube.com/playlist?list=WL")!) {
                        Label("Apri la tua playlist YouTube nel browser", systemImage: "safari")
                    }
                } header: { Text("Account YouTube") }
                Section {
                    HStack { BrandMark(); Spacer(); Text("1.0").foregroundStyle(.secondary) }
                    Text("Scegli cosa guardare, poi prenditi il tuo tempo.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("iurub conserva solo i link e i titoli che salvi. Il sito e il player YouTube restano gestiti da Google. I video non vengono scaricati.")
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
        #if os(macOS)
        .frame(minWidth: 430, minHeight: 650)
        #endif
    }
}
