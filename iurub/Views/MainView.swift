import SwiftUI

struct MainView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var watchLater = BrowserSession(startPage: .watchLater, saveDestination: .youtube)
    @StateObject private var home = BrowserSession(saveDestination: .youtube)
    @State private var selectedTab = 0
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: $selectedTab) {
            browserTab(watchLater, title: "Guarda più tardi", icon: "bookmark.fill")
                .tabItem { Label("Guarda più tardi", systemImage: "bookmark.fill") }
                .tag(0)
            browserTab(home, title: "Home", icon: "house")
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(1)
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .onAppear { watchLater.startIfNeeded() }
        .onReceive(settings.$shortsEnabled) { enabled in
            for session in [watchLater, home] { session.configure(shortsEnabled: enabled, savedIDs: []) }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == 0 {
                home.pause()
                watchLater.openStartPage()
            } else {
                watchLater.pause()
                home.startIfNeeded()
            }
        }
        .onChange(of: showingSettings) { _, showing in if showing { pauseBoth() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { pauseBoth() } }
        .onOpenURL { url in
            guard url.scheme == "iurub", url.host == "open",
                  let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
                  let link = VideoLink.parse(raw) else { return }
            selectedTab = 1
            home.load(link.url)
        }
    }

    private func browserTab(_ session: BrowserSession, title: String, icon: String) -> some View {
        NavigationStack {
            BrowserPane(session: session)
                .toolbar {
                    ToolbarItem(placement: .principal) { BrandMark() }
                    ToolbarItem(placement: .appLeading) {
                        Button(action: session.back) { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                            .disabled(!session.canGoBack).accessibilityLabel("Indietro")
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button(action: session.openStartPage) { Image(systemName: icon).frame(width: 32, height: 32) }
                            .accessibilityLabel(title == "Home" ? "Torna alla home YouTube" : "Aggiorna Guarda più tardi")
                            .accessibilityIdentifier(title == "Home" ? "youtubeHome" : "refreshWatchLater")
                        SettingsButton { showingSettings = true }
                    }
                }
                .inlineTitle()
        }
    }

    private func pauseBoth() { watchLater.pause(); home.pause() }
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
