import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeviceLibrary = false
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
                    Label("La tua playlist YouTube", systemImage: "person.crop.circle")
                    Text("Salvati mostra Guarda più tardi del tuo account YouTube. Iscrizioni, Cronologia, Esplora e Tu condividono lo stesso accesso.")
                        .foregroundStyle(.secondary)
                    Text("I pulsanti Guarda più tardi usano il menu di salvataggio di YouTube. Le modifiche compaiono anche negli altri dispositivi collegati allo stesso account.")
                        .foregroundStyle(.secondary)
                } header: { Text("Account YouTube") }
                Section {
                    Button { showingDeviceLibrary = true } label: {
                        Label("Salvati sul dispositivo", systemImage: "internaldrive")
                    }.accessibilityIdentifier("deviceLibraryButton")
                } header: { Text("Archivio locale") } footer: {
                    Text("I link salvati nella versione precedente rimangono qui. Sono separati dalla playlist del tuo account e non vengono trasferiti automaticamente.")
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
        .sheet(isPresented: $showingDeviceLibrary) { DeviceLibraryScreen() }
        #if os(macOS)
        .frame(minWidth: 430, minHeight: 650)
        #endif
    }
}
