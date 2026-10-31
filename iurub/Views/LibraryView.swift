import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @State private var query = ""
    @State private var newestFirst = true
    let onExplore: () -> Void
    let onAdd: () -> Void
    let onSettings: () -> Void
    let onPlay: (SavedVideo) -> Void
    let onRemove: (SavedVideo) -> Void

    private var filtered: [SavedVideo] {
        let results = library.videos.filter {
            query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.channel.localizedCaseInsensitiveContains(query)
        }
        return newestFirst ? results : results.reversed()
    }
    var body: some View {
        NavigationStack {
            Group {
                if library.videos.isEmpty && library.errorMessage == nil {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if let error = library.errorMessage {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label(error, systemImage: "exclamationmark.triangle")
                                    Button("Riprova", action: library.reload)
                                }.padding().background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                            }
                            HStack {
                                Label("\(library.videos.count) video · sul dispositivo", systemImage: "iphone")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Menu {
                                    Button("Più recenti prima") { newestFirst = true }
                                    Button("Meno recenti prima") { newestFirst = false }
                                } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 32, height: 32) }
                                .accessibilityLabel("Ordina video")
                            }
                            if filtered.isEmpty && !query.isEmpty {
                                ContentUnavailableView.search(text: query)
                            }
                            LazyVStack(spacing: 20) {
                                ForEach(filtered) { video in
                                    VideoCard(video: video, blocked: video.isShort && !settings.shortsEnabled,
                                              onPlay: { onPlay(video) }, onRemove: { onRemove(video) })
                                }
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 16)
                        .frame(maxWidth: 680)
                        .frame(maxWidth: .infinity)
                    }
                    .background(Theme.canvas)
                    .searchable(text: $query, prompt: "Cerca tra i tuoi video")
                }
            }
            .navigationTitle("Guarda più tardi")
            .toolbar {
                ToolbarItem(placement: .principal) { BrandMark() }
                ToolbarItem(placement: .primaryAction) { SettingsButton(action: onSettings) }
                ToolbarItem(placement: .appLeading) {
                    Button(action: onAdd) { Image(systemName: "plus").frame(width: 32, height: 32) }
                        .accessibilityLabel("Aggiungi un link")
                        .accessibilityIdentifier("addLinkButton")
                }
            }
        }
    }

    private var emptyState: some View {
        GeometryReader { geometry in
            ScrollView {
                emptyContent.frame(minHeight: geometry.size.height)
            }
        }
        .background(Theme.canvas)
    }

    private var emptyContent: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 32).fill(Theme.accent.opacity(0.09)).frame(width: 126, height: 126).rotationEffect(.degrees(-7))
                RoundedRectangle(cornerRadius: 26).fill(Theme.card).frame(width: 100, height: 112).rotationEffect(.degrees(7))
                    .shadow(color: Theme.accent.opacity(0.08), radius: 10, y: 6)
                Image(systemName: "bookmark").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)
            .padding(.bottom, 32)
            Text("Meno scroll.\nPiù scelta.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
            Text("Salva dalla Home i video che ti interessano.\nLi ritrovi qui, quando vuoi.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 28)
            Button(action: onExplore) {
                Label("Esplora YouTube", systemImage: "arrow.right")
                    .font(.headline).frame(maxWidth: 260).padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 16))
            .accessibilityIdentifier("exploreButton")
            Button("Aggiungi un link", action: onAdd).font(.subheadline.weight(.medium)).padding(.top, 18)
            Spacer()
            Label("La tua lista, salvata su questo dispositivo", systemImage: "internaldrive")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}

private struct VideoCard: View {
    let video: SavedVideo
    let blocked: Bool
    let onPlay: () -> Void
    let onRemove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onPlay) {
                ZStack {
                    Rectangle().fill(Color.secondary.opacity(0.1))
                    AsyncImage(url: video.thumbnailURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "play.rectangle").font(.system(size: 38, weight: .light)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Image(systemName: blocked ? "lock.fill" : "play.fill")
                        .font(.title3).foregroundStyle(.white)
                        .padding(17).background(.black.opacity(0.55), in: Circle())
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Riproduci \(video.title)")
            .accessibilityIdentifier("play-\(video.id)")
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.title).font(.headline).lineLimit(3)
                    if !video.channel.isEmpty { Text(video.channel).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                    HStack(spacing: 4) {
                        if video.isShort { Text(blocked ? "Short · disattivato" : "Short").foregroundStyle(Theme.accent) }
                        Text(video.savedAt, style: .date).foregroundStyle(.tertiary)
                    }.font(.caption)
                }
                Spacer(minLength: 0)
                Menu {
                    Button(role: .destructive, action: onRemove) { Label("Rimuovi dalla lista", systemImage: "trash") }
                        .accessibilityIdentifier("remove-\(video.id)")
                    ShareLink(item: video.url) { Label("Condividi link", systemImage: "square.and.arrow.up") }
                } label: { Image(systemName: "ellipsis").frame(width: 40, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("Opzioni per \(video.title)")
                .accessibilityIdentifier("options-\(video.id)")
            }
            .padding(16)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.04)))
    }
}
