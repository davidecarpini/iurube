import SwiftUI

struct AddVideoView: View {
    let onSave: (SavedVideo) -> Void
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var linkText = ""
    @State private var title = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://www.youtube.com/watch?v=…", text: $linkText)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .accessibilityIdentifier("videoLinkField")
                    TextField("Titolo (facoltativo)", text: $title)
                        .accessibilityIdentifier("videoTitleField")
                } header: { Text("Link del video") } footer: {
                    Text("Incolla un link YouTube. Il video verrà aggiunto alla lista su questo dispositivo.")
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) } }
            }
            .navigationTitle("Aggiungi un video")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        guard let link = VideoLink.parse(linkText) else {
                            error = "Inserisci un link valido a un video YouTube."
                            return
                        }
                        guard settings.shortsEnabled || !link.isShort else {
                            error = "Questo è uno Short. Abilita prima gli Shorts nelle impostazioni."
                            return
                        }
                        onSave(SavedVideo(link: link, title: title))
                        if library.contains(link.id) { dismiss() } else { error = library.errorMessage }
                    }
                    .disabled(linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("confirmAddVideo")
                }
            }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        .frame(minWidth: 430, minHeight: 350)
        #endif
    }
}
