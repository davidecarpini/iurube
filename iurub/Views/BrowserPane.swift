import SwiftUI
#if os(iOS)
import SafariServices
#endif

struct BrowserPane: View {
    @ObservedObject var session: BrowserSession
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var summaries: SummaryStore
    var extendsToBottom = false
    var onSave: ((SavedVideo) -> Void)? = nil
    @State private var feedback: String?
    @State private var safariURL: IdentifiedURL?
    @State private var summaryVideo: SavedVideo?
    @Environment(\.openURL) private var openURL

    var body: some View {
        YouTubeWebView(session: session)
            .ignoresSafeArea(.container, edges: extendsToBottom ? .bottom : [])
            .overlay(alignment: .top) {
                if session.isLoading { ProgressView().padding(10).background(.regularMaterial, in: Capsule()).padding(.top, 8) }
            }
            .overlay {
                if let error = session.loadError {
                    ContentUnavailableView {
                        Label("Impossibile caricare YouTube", systemImage: "wifi.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Riprova", action: session.reload).buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.canvas)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let video = session.currentVideo {
                    let saved = session.saveDestination == .youtube ? session.youtubeSavedIDs.contains(video.id) : library.contains(video.id)
                    HStack(spacing: 2) {
                        Button(action: session.saveCurrent) {
                            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                                .font(.headline).frame(width: 44, height: 44)
                        }
                        .disabled(session.saveDestination == .device && saved)
                        .accessibilityLabel(session.saveDestination == .youtube ? (saved ? "Rimuovi da Guarda più tardi" : "Guarda più tardi") : (saved ? "Salvato sul dispositivo" : "Salva sul dispositivo"))
                        .accessibilityValue(saved ? "salvato" : (session.saveDestination == .youtube && !session.youtubeRemovedIDs.contains(video.id) ? "da verificare" : "non salvato"))
                        .accessibilityIdentifier("saveCurrentVideo")
                        if session.role == .player {
                            Button(action: session.togglePictureInPicture) {
                                Image(systemName: session.isDetached ? "pip.exit" : "pip.enter")
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(session.isDetached ? "Riporta il video nell’app" : "Picture in Picture")
                            .accessibilityHint("Guarda il video mentre usi altre app")
                            .accessibilityIdentifier("pictureInPicture")
                            speedControls
                        }
                        Button {
                            session.pause()
                            summaryVideo = video
                        } label: {
                            HStack(spacing: 8) {
                                if summaries.busy.contains(video.id) || summaries.queued.contains(video.id) {
                                    ProgressView().controlSize(.small)
                                } else { Image(systemName: "sparkles") }
                                ViewThatFits(in: .horizontal) {
                                    Text("Riassunto").fixedSize()
                                    Color.clear.frame(width: 0, height: 1)
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).frame(minHeight: 44)
                            .background(Theme.accent.opacity(0.1), in: Capsule())
                        }
                        .accessibilityLabel("Riassunto")
                        .accessibilityIdentifier("summaryButton")
                        .accessibilityValue(summaries.busy.contains(video.id) ? "In preparazione" : (summaries.queued.contains(video.id) ? "In attesa" : ((summaries.conversations[video.id] ?? []).isEmpty ? "Da preparare" : "Pronto")))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(.regularMaterial)
                }
            }
            .overlay(alignment: .bottom) {
                if let feedback {
                    Text(feedback).font(.subheadline.weight(.medium)).padding(14)
                        .background(.regularMaterial, in: Capsule()).padding(.bottom, 64)
                        .task(id: feedback) {
                            try? await Task.sleep(for: .seconds(3))
                            if !Task.isCancelled { self.feedback = nil }
                        }
                        .accessibilityIdentifier("webSaveFeedback")
                }
            }
            .onAppear {
                session.onSave = { video in
                    onSave?(video)
                    feedback = library.contains(video.id) ? "Salvato sul dispositivo" : (library.errorMessage ?? "Salvataggio non riuscito")
                    if session.saveDestination == .device {
                        session.configure(shortsEnabled: settings.shortsEnabled, savedIDs: library.videos.map(\.id))
                    }
                }
            }
            .onDisappear { session.pauseWhenHidden(); session.onSave = nil }
            .onReceive(session.$saveFeedback) { if let message = $0 { feedback = message } }
            .alert("iurub", isPresented: Binding(get: { session.notice != nil }, set: { if !$0 { session.notice = nil } })) {
                Button("OK") { session.notice = nil }
            } message: { Text(session.notice ?? "") }
            .alert("Aprire questo link?", isPresented: Binding(get: { session.externalURL != nil }, set: { if !$0 { session.externalURL = nil } })) {
                Button("Apri nel browser") {
                    if let url = session.externalURL {
                        session.pause()
                        #if os(iOS)
                        safariURL = IdentifiedURL(url: url)
                        #else
                        openURL(url)
                        #endif
                    }
                    session.externalURL = nil
                }
                Button("Annulla", role: .cancel) { session.externalURL = nil }
            } message: { Text(session.externalURL?.host ?? "Link esterno a YouTube") }
            .sheet(item: $summaryVideo) { video in VideoSummaryView(video: video) }
            #if os(iOS)
            .sheet(item: $safariURL) { item in SafariView(url: item.url).ignoresSafeArea() }
            #endif
    }
    private var speedControls: some View {
        HStack(spacing: 0) {
            Button { session.stepSpeed(-1) } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
            }
            .disabled((session.mediaRate ?? 0.5) <= 0.5)
            .accessibilityLabel("Riduci velocità").accessibilityIdentifier("speedDown")
            Text(session.mediaRate.map { $0.formatted(.number.precision(.fractionLength(0...2))) + "×" } ?? "–")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityLabel("Velocità di riproduzione")
                .accessibilityValue(session.mediaRate.map { String($0) } ?? "")
                .accessibilityIdentifier("playbackSpeed")
            Button { session.stepSpeed(1) } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            .disabled((session.mediaRate ?? 2) >= 2)
            .accessibilityLabel("Aumenta velocità").accessibilityIdentifier("speedUp")
        }
        .background(.quaternary, in: Capsule())
    }
}

struct PlayerView: View {
    let video: SavedVideo
    let onSave: (SavedVideo) -> Void
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var session = BrowserSession()

    var body: some View {
        NavigationStack {
            BrowserPane(session: session, onSave: onSave)
                .navigationTitle("Il tuo video")
                .inlineTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Chiudi") { session.pause(); dismiss() }.accessibilityIdentifier("closePlayer")
                    }
                    ToolbarItem(placement: .appLeading) {
                        Button(action: session.back) { Image(systemName: "chevron.left") }
                            .disabled(!session.canGoBack).accessibilityLabel("Indietro")
                    }
                }
        }
        .onAppear {
            session.configure(shortsEnabled: settings.shortsEnabled, savedIDs: library.videos.map(\.id))
            if !session.hasLoaded { session.load(video.url) }
        }
        .onReceive(library.$videos) { videos in session.configure(shortsEnabled: settings.shortsEnabled, savedIDs: videos.map(\.id)) }
        .onReceive(settings.$shortsEnabled) { enabled in session.configure(shortsEnabled: enabled, savedIDs: library.videos.map(\.id)) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.pause() } }
        .onDisappear { session.pause() }
    }
}

private struct IdentifiedURL: Identifiable { let id = UUID(); let url: URL }
#if os(iOS)
private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif

extension ToolbarItemPlacement {
    static var appLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
}
