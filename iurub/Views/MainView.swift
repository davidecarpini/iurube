import SwiftUI

struct MainView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var playback: PlaybackStore
    @EnvironmentObject private var summaries: SummaryStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var player = BrowserSession(saveDestination: .youtube, role: .player)
    @StateObject private var watchLater = BrowserSession(startPage: .watchLater, saveDestination: .youtube)
    @StateObject private var subscriptions = BrowserSession(startPage: .subscriptions, saveDestination: .youtube)
    @StateObject private var history = BrowserSession(startPage: .history, saveDestination: .youtube)
    @StateObject private var home = BrowserSession(saveDestination: .youtube)
    @State private var selectedTab = 1
    @State private var showingSettings = false
    @State private var didStart = false
    @State private var wasInBackground = false
    @State private var openingVideoToken = UUID()
    @State private var savedNeedsRefresh = false
    // Session-only hints come from the account UI, never the legacy local library.
    // Missing IDs in a partially loaded playlist do not mean "not saved".
    @State private var youtubeMembership: [String: Bool] = [:]
    @State private var accountContextNeedsRefresh = false

    private var sessions: [BrowserSession] { [player, watchLater, subscriptions, history, home] }

    var body: some View {
        TabView(selection: Binding(get: { selectedTab }, set: selectTab)) {
            inProgressTab
                .tabItem { Label("In corso", systemImage: "play.circle.fill") }.tag(0)
            browserTab(watchLater)
                .tabItem { Label("Salvati", systemImage: "bookmark.fill") }.tag(1)
            browserTab(subscriptions)
                .tabItem { Label("Iscrizioni", systemImage: "play.rectangle.on.rectangle") }.tag(2)
            browserTab(history)
                .tabItem { Label("Cronologia", systemImage: "clock.arrow.circlepath") }.tag(3)
            browserTab(home)
                .tabItem { Label("Esplora", systemImage: "safari") }.tag(4)
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
               let data = try? JSONSerialization.data(withJSONObject: [
                "ready": summaries.conversations.filter { !$0.value.isEmpty }.keys.sorted(),
                "busy": summaries.busy.sorted(),
                "counts": summaries.conversations.mapValues(\.count)
               ]) {
                Text(String(decoding: data, as: UTF8.self))
                    .font(.system(size: 1)).frame(width: 1, height: 1).opacity(0.01)
                    .accessibilityIdentifier("summaryPrefetchStatus").allowsHitTesting(false)
            }
            if ProcessInfo.processInfo.arguments.contains("--playback-live"),
               let record = playback.current, let data = try? JSONEncoder().encode(record) {
                // Expose actual media checkpoints to the opt-in simulator test.
                // It cannot read another app's protected container directly.
                Text(String(decoding: data, as: UTF8.self))
                    .font(.system(size: 1)).frame(width: 1, height: 1).opacity(0.01)
                    .accessibilityIdentifier("livePlaybackStatus").allowsHitTesting(false)
            }
        }
        #endif
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .onAppear(perform: start)
        .onReceive(settings.$shortsEnabled) { enabled in
            configureSessions(shortsEnabled: enabled)
        }
        .onReceive(settings.$automaticSummariesEnabled) { enabled in
            if !enabled { summaries.discardQueuedPrefetches() }
        }
        .onChange(of: youtubeMembership) { _, _ in
            configureSessions(shortsEnabled: settings.shortsEnabled)
        }
        .onChange(of: settings.shortsEnabled) { _, _ in
            if selectedTab == 0 { ensurePlayer() }
        }
        .onChange(of: selectedTab) { old, tab in
            if accountContextNeedsRefresh {
                accountContextNeedsRefresh = false
                resetMembershipHints()
                watchLater.openStartPage()
                savedNeedsRefresh = false
            }
            if old == 0 { player.captureProgress() }
            for (index, session) in sessions.enumerated() where index != tab { session.pauseWhenHidden() }
            if tab == 0 { ensurePlayer() }
            else if tab == 1 && savedNeedsRefresh {
                savedNeedsRefresh = false
                watchLater.openStartPage()
            }
            else if old == 0 { sessions[tab].startIfNeeded() }
            else if tab == 1 || tab == 3 { sessions[tab].openStartPage() }
            else { sessions[tab].startIfNeeded() }
        }
        .onChange(of: showingSettings) { _, showing in if showing { pauseAll() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                wasInBackground = true
                pauseAll()
            } else if phase == .active, wasInBackground {
                wasInBackground = false
                if selectedTab == 0 { player.returnFromPictureInPicture() }
            } else if phase == .inactive {
                player.captureProgress()
            }
        }
        .onOpenURL { url in
            guard url.scheme == "iurub", url.host == "open",
                  let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
                  let sourceURL = URL(string: raw), let link = VideoLink.parse(raw) else { return }
            openInProgress(SavedVideo(link: link), startAt: PlaybackRecord.startTime(in: sourceURL))
        }
    }

    @ViewBuilder private var inProgressTab: some View {
        if let current = playback.current {
            if current.video.isShort && !settings.shortsEnabled {
                inProgressPlaceholder(title: "Gli Shorts sono disattivati", symbol: "play.slash",
                                      detail: "Il punto di riproduzione è al sicuro. Abilita gli Shorts nelle impostazioni per continuare.",
                                      button: "Apri impostazioni", action: { showingSettings = true })
            } else {
                browserTab(player)
            }
        } else {
            inProgressPlaceholder(title: "Un video alla volta", symbol: "play.circle",
                                  detail: "Apri un video da Salvati o Esplora. Lo ritrovi qui, dal punto in cui ti sei fermato.",
                                  button: "Apri Salvati", action: { selectedTab = 1 })
        }
    }

    private func inProgressPlaceholder(title: String, symbol: String, detail: String, button: String,
                                       action: @escaping () -> Void) -> some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: { Text(detail) } actions: {
                Button(button, action: action).buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("inProgressAction")
            }
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .principal) { BrandMark() }
                ToolbarItem(placement: .primaryAction) { SettingsButton { showingSettings = true } }
            }
            .inlineTitle()
        }
    }

    private func browserTab(_ session: BrowserSession) -> some View {
        NavigationStack {
            BrowserPane(session: session, extendsToBottom: true)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if session === player, let error = playback.errorMessage {
                        Text(error).font(.caption).padding(10).frame(maxWidth: .infinity)
                            .background(.regularMaterial)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .principal) { BrandMark() }
                    ToolbarItemGroup(placement: .appLeading) {
                        Button(action: session.back) { Image(systemName: "chevron.left").frame(width: 28, height: 32) }
                            .disabled(!session.canGoBack).accessibilityLabel("Indietro")
                            .accessibilityIdentifier("backButton")
                        Button(action: session.reload) { Image(systemName: "arrow.clockwise").frame(width: 28, height: 32) }
                            .accessibilityLabel("Ricarica pagina")
                            .accessibilityIdentifier("refreshPage")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        SettingsButton { showingSettings = true }
                        Button(action: session.openAccount) { Image(systemName: "person.crop.circle").frame(width: 28, height: 32) }
                            .accessibilityLabel("Tu")
                            .accessibilityIdentifier("profileButton")
                    }
                }
                .inlineTitle()
                #if os(iOS)
                .toolbarBackground(.hidden, for: .tabBar)
                #endif
        }
    }

    private func start() {
        for session in sessions {
            session.onOpenVideo = { video, position in openInProgress(video, startAt: position) }
            session.onYouTubeMembership = { video, saved in
                guard !accountContextNeedsRefresh, youtubeMembership[video.id] != saved else { return }
                youtubeMembership[video.id] = saved
                if session !== watchLater { savedNeedsRefresh = true }
            }
            session.onYouTubeSaved = { video in
                guard settings.automaticSummariesEnabled else { return }
                summaries.prefetch(video: video)
            }
            session.onAccountContextChanged = {
                accountContextNeedsRefresh = true
                resetMembershipHints()
            }
        }
        configureSessions(shortsEnabled: settings.shortsEnabled)
        player.onPlayback = { id, position, duration, ended in
            playback.update(videoID: id, position: position, duration: duration, ended: ended)
        }
        player.onMetadata = { video in playback.updateMetadata(video) }
        player.onRestoreVideo = { video in playback.select(video: video) }
        guard !didStart else { return }
        didStart = true
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--playback-live"), arguments.contains("--start-video-at-8") {
            openInProgress(SavedVideo(link: VideoLink(id: "jNQXAC9IVRw", isShort: false), title: "Me at the zoo"), startAt: 8)
            return
        }
        if arguments.contains("--summary-live") || arguments.contains("--summary-fixture") {
            watchLater.startIfNeeded()
            return
        }
        #endif
        if let current = playback.current, !current.completed {
            // Read the saved list too, so the player's bookmark can reflect the
            // signed-in account without starting summaries for existing videos.
            watchLater.startIfNeeded()
            selectedTab = 0
        } else {
            watchLater.startIfNeeded()
        }
    }

    private func configureSessions(shortsEnabled: Bool) {
        let saved = youtubeMembership.filter(\.value).keys.sorted()
        let removed = youtubeMembership.filter { !$0.value }.keys.sorted()
        for session in sessions {
            session.configure(shortsEnabled: shortsEnabled, savedIDs: saved, removedIDs: removed)
        }
    }

    private func resetMembershipHints() {
        youtubeMembership = [:]
        sessions.forEach { $0.resetYouTubeMembership() }
    }

    private func openInProgress(_ video: SavedVideo, startAt: Double?) {
        guard settings.shortsEnabled || !video.isShort else { return }
        if accountContextNeedsRefresh {
            accountContextNeedsRefresh = false
            resetMembershipHints()
            watchLater.openStartPage()
        }
        if playback.current?.video.id == video.id, playback.current?.completed == false,
           startAt == nil, playerIsShowing(video.id) {
            playback.updateMetadata(video)
            selectedTab = 0
            return
        }
        let token = UUID()
        openingVideoToken = token
        player.pause()
        player.captureProgress {
            guard openingVideoToken == token else { return }
            let record = playback.select(video: video, startAt: startAt)
            player.loadVideo(record.video, position: record.position)
            selectedTab = 0
        }
    }

    private func playerIsShowing(_ videoID: String) -> Bool {
        player.currentVideo?.id == videoID && (player.isLoading || player.webView.url.flatMap { VideoLink.parse($0.absoluteString) }?.id == videoID)
    }

    private func ensurePlayer() {
        guard let record = playback.current, settings.shortsEnabled || !record.video.isShort else { return }
        if !playerIsShowing(record.video.id) { player.loadVideo(record.video, position: record.position) }
    }

    private func selectTab(_ tab: Int) {
        guard sessions.indices.contains(tab) else { return }
        if accountContextNeedsRefresh {
            accountContextNeedsRefresh = false
            resetMembershipHints()
            watchLater.openStartPage()
            savedNeedsRefresh = false
        }
        if tab != 0 { openingVideoToken = UUID() }
        if selectedTab == tab {
            if tab == 0 {
                // A second tap must never reset the current video's playhead.
                ensurePlayer()
            } else {
                pauseAll()
                if tab == 1 { savedNeedsRefresh = false }
                sessions[tab].openStartPage()
            }
        } else {
            selectedTab = tab
        }
    }

    private func pauseAll() {
        sessions.forEach { $0.pauseWhenHidden() }
    }
}

// Preserve the original on-device library without presenting it as the Google playlist.
struct DeviceLibraryScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showingAdd = false
    @State private var playingVideo: SavedVideo?
    @State private var toast: ToastMessage?
    @State private var blocked = false

    var body: some View {
        LibraryView(onExplore: { dismiss() }, onAdd: { showingAdd = true }, onSettings: { dismiss() },
                    onPlay: { video in
                        if video.isShort && !settings.shortsEnabled { blocked = true } else { playingVideo = video }
                    }, onRemove: { video in
                        if let removed = library.remove(video.id) { toast = ToastMessage(text: "Video rimosso dal dispositivo", removedVideo: removed) }
                    }, isDeviceArchive: true)
            .sheet(isPresented: $showingAdd) { AddVideoView(onSave: save) }
            .sheet(item: $playingVideo) { PlayerView(video: $0, onSave: save) }
            .alert("Gli Shorts sono disattivati", isPresented: $blocked) { Button("OK", role: .cancel) {} }
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastView(message: toast, onUndo: {
                        if let video = toast.removedVideo { _ = library.restore(video) }
                        self.toast = nil
                    }).padding(20)
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(7))
                        if !Task.isCancelled { self.toast = nil }
                    }
                }
            }
    }
    private func save(_ video: SavedVideo) {
        if library.save(video) { toast = ToastMessage(text: "Salvato sul dispositivo", removedVideo: nil) }
    }
}

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let removedVideo: SavedVideo?
}

struct ToastView: View {
    let message: ToastMessage
    let onUndo: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: message.removedVideo == nil ? "checkmark.circle.fill" : "trash")
                .foregroundStyle(Theme.accent)
            Text(message.text).font(.subheadline.weight(.medium))
            if message.removedVideo != nil {
                Spacer(minLength: 4)
                Button("Annulla", action: onUndo).font(.subheadline.bold()).accessibilityIdentifier("undoRemove")
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }
}

extension View {
    @ViewBuilder func inlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
