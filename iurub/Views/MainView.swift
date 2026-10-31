import SwiftUI
#if os(iOS)
import UIKit
#endif

struct MainView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var browser = BrowserSession()
    @State private var selectedTab = 0
    @State private var showingSettings = false
    @State private var showingAdd = false
    @State private var playingVideo: SavedVideo?
    @State private var blockedVideo = false
    @State private var toast: ToastMessage?

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView(
                onExplore: { selectedTab = 1 },
                onAdd: { showingAdd = true },
                onSettings: { showingSettings = true },
                onPlay: play,
                onRemove: remove
            )
            .tabItem { Label("Guarda più tardi", systemImage: "bookmark.fill") }
            .tag(0)
            .accessibilityIdentifier("libraryTab")

            NavigationStack {
                BrowserPane(session: browser, onSave: save)
                    .toolbar {
                        ToolbarItem(placement: .principal) { BrandMark() }
                        ToolbarItem(placement: .appLeading) {
                            Button(action: browser.back) { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                                .disabled(!browser.canGoBack)
                                .accessibilityLabel("Indietro")
                        }
                        ToolbarItemGroup(placement: .primaryAction) {
                            Button(action: browser.home) { Image(systemName: "house").frame(width: 32, height: 32) }
                                .accessibilityLabel("Torna alla home YouTube")
                            SettingsButton { showingSettings = true }
                        }
                    }
                    .inlineTitle()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(1)
            .accessibilityIdentifier("homeTab")
        }
        .overlay(alignment: .bottom) {
            if let toast {
                ToastView(message: toast, onUndo: {
                    if let video = toast.removedVideo { _ = library.restore(video) }
                    self.toast = nil
                })
                .padding(.horizontal, 20)
                .padding(.bottom, 70)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(for: .seconds(toast.removedVideo == nil ? 3 : 7))
                    guard !Task.isCancelled else { return }
                    withAnimation { self.toast = nil }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toast?.id)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingAdd) { AddVideoView(onSave: save) }
        .sheet(item: $playingVideo) { video in PlayerView(video: video, onSave: save) }
        .alert("Gli Shorts sono disattivati", isPresented: $blockedVideo) {
            Button("Impostazioni") { showingSettings = true }
            Button("Annulla", role: .cancel) {}
        } message: { Text("Puoi abilitarli nelle impostazioni. Il video rimane nella tua lista.") }
        .onReceive(settings.$shortsEnabled) { enabled in
            browser.configure(shortsEnabled: enabled, savedIDs: library.videos.map(\.id))
        }
        .onReceive(library.$videos) { videos in
            browser.configure(shortsEnabled: settings.shortsEnabled, savedIDs: videos.map(\.id))
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == 1 { browser.startIfNeeded() } else { browser.pause() }
        }
        .onChange(of: showingSettings) { _, showing in if showing { browser.pause() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { browser.pause() } }
        .onOpenURL { url in
            guard url.scheme == "iurub", url.host == "open",
                  let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
                  let link = VideoLink.parse(raw) else { return }
            play(SavedVideo(link: link))
        }
    }

    private func play(_ video: SavedVideo) {
        if video.isShort && !settings.shortsEnabled { blockedVideo = true; return }
        browser.pause()
        playingVideo = video
    }
    private func save(_ video: SavedVideo) {
        if video.isShort && !settings.shortsEnabled { blockedVideo = true; return }
        if library.contains(video.id) {
            toast = ToastMessage(text: "È già in Guarda più tardi", removedVideo: nil)
        } else if library.save(video) {
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            toast = ToastMessage(text: "Salvato in Guarda più tardi", removedVideo: nil)
        } else {
            toast = ToastMessage(text: library.errorMessage ?? "Salvataggio non riuscito", removedVideo: nil)
        }
    }
    private func remove(_ video: SavedVideo) {
        if let removed = library.remove(video.id) {
            toast = ToastMessage(text: "Video rimosso", removedVideo: removed)
        }
    }
}

struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    let removedVideo: SavedVideo?
}

private struct ToastView: View {
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
