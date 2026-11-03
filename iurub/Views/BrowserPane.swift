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
    @State private var feedbackID = UUID()
    @State private var safariURL: IdentifiedURL?
    @State private var summaryVideo: SavedVideo?
    @Environment(\.openURL) private var openURL

    @ViewBuilder private var browserContent: some View {
        if session.role == .player {
            // The root hosts this web view so the same decoder stays attached across tab changes.
            Color.clear.anchorPreference(key: PlayerViewportKey.self, value: .bounds) { PlayerViewport(page: $0) }
        } else {
            YouTubeWebView(session: session)
        }
    }

    var body: some View {
        browserContent
            .ignoresSafeArea(.container, edges: extendsToBottom && session.role != .player ? .bottom : [])
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
                    HStack(spacing: 0) {
                        Button(action: session.saveCurrent) {
                            controlLabel(saved ? "Salvato" : "Salva", symbol: saved ? "bookmark.fill" : "bookmark",
                                         color: saved ? Theme.accent : .primary)
                        }
                        .disabled(session.saveDestination == .device && saved)
                        .accessibilityLabel(session.saveDestination == .youtube ? (saved ? "Rimuovi da Guarda più tardi" : "Guarda più tardi") : (saved ? "Salvato sul dispositivo" : "Salva sul dispositivo"))
                        .accessibilityValue(saved ? "salvato" : (session.saveDestination == .youtube && !session.youtubeRemovedIDs.contains(video.id) ? "da verificare" : "non salvato"))
                        .accessibilityIdentifier("saveCurrentVideo")
                        if session.role == .player {
                            Button(action: session.togglePictureInPicture) {
                                controlLabel("Finestra", symbol: session.isDetached ? "pip.exit" : "pip.enter")
                            }
                            .accessibilityLabel(session.isDetached ? "Riporta il video nell’app" : "Picture in Picture")
                            .accessibilityIdentifier("pictureInPicture")
                            speedControls
                        }
                        Button {
                            session.pause()
                            summaryVideo = video
                        } label: {
                            controlLabel("Riassunto", symbol: "sparkles", color: Theme.accent,
                                         busy: summaries.busy.contains(video.id) || summaries.queued.contains(video.id))
                        }
                        .accessibilityLabel("Riassunto")
                        .accessibilityIdentifier("summaryButton")
                        .accessibilityValue(summaries.busy.contains(video.id) ? "In preparazione" : (summaries.queued.contains(video.id) ? "In attesa" : ((summaries.conversations[video.id] ?? []).isEmpty ? "Da preparare" : "Pronto")))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8).frame(minHeight: 64)
                    .background(Theme.card)
                    .overlay(alignment: .top) { Divider() }
                    .anchorPreference(key: PlayerViewportKey.self, value: .bounds) {
                        session.role == .player ? PlayerViewport(controls: $0) : PlayerViewport()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let feedback {
                    Text(feedback).font(.subheadline.weight(.medium)).padding(14)
                        .background(.regularMaterial, in: Capsule()).padding(.bottom, 64)
                        .allowsHitTesting(false)
                        .task(id: feedbackID) {
                            try? await Task.sleep(for: .seconds(3))
                            if !Task.isCancelled { self.feedback = nil }
                        }
                        .accessibilityIdentifier("webSaveFeedback")
                }
            }
            .onAppear {
                session.onSave = { video in
                    onSave?(video)
                    feedbackID = UUID()
                    feedback = library.contains(video.id) ? "Salvato sul dispositivo" : (library.errorMessage ?? "Salvataggio non riuscito")
                    if session.saveDestination == .device {
                        session.configure(shortsEnabled: settings.shortsEnabled, savedIDs: library.videos.map(\.id))
                    }
                }
            }
            .onDisappear { session.onSave = nil }
            .onChange(of: session.windowHint) { _, value in
                guard let hint = value else { return }
                feedbackID = UUID()
                feedback = hint
                session.windowHint = nil
            }
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
    private func controlLabel(_ title: String, symbol: String, color: Color = .primary, busy: Bool = false) -> some View {
        VStack(spacing: 3) {
            Group {
                if busy { ProgressView().controlSize(.small) }
                else { Image(systemName: symbol).font(.system(size: 20, weight: .medium)) }
            }
            .frame(height: 24)
            Text(title).font(.caption2.weight(.medium)).lineLimit(1)
        }
        .foregroundStyle(color)
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
    }

    private var speedControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                speedButton(-1)
                Text(session.mediaRate.map { $0.formatted(.number.precision(.fractionLength(0...2))) + "×" } ?? "–")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Velocità di riproduzione")
                    .accessibilityValue(session.mediaRate.map { String($0) } ?? "")
                    .accessibilityIdentifier("playbackSpeed")
                speedButton(1)
            }
            Text("Velocità").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
    }

    private func speedButton(_ direction: Int) -> some View {
        let increase = direction > 0
        return Button { session.stepSpeed(direction) } label: {
            Image(systemName: increase ? "plus" : "minus").font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .disabled(session.mediaRate.map { increase ? $0 >= 2 : $0 <= 0.5 } ?? true)
        .accessibilityLabel(increase ? "Aumenta velocità" : "Riduci velocità")
        .accessibilityIdentifier(increase ? "speedUp" : "speedDown")
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
