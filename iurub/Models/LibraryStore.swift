import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var videos: [SavedVideo] = []
    @Published private(set) var errorMessage: String?
    private let fileURL: URL
    private var canWrite = true

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL
        reload()
    }

    static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iurub", isDirectory: true)
            .appendingPathComponent("saved-videos.json")
    }

    func contains(_ id: String) -> Bool { videos.contains { $0.id == id } }

    func reload() {
        do {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                videos = []
            } else {
                let decoded = try JSONDecoder().decode([SavedVideo].self, from: Data(contentsOf: fileURL))
                // A malformed file must not be silently replaced by an empty library.
                guard decoded.allSatisfy({ VideoLink.validID($0.id) }),
                      Set(decoded.map(\.id)).count == decoded.count else { throw LibraryError.invalidData }
                videos = decoded.sorted { $0.savedAt > $1.savedAt }
            }
            canWrite = true
            errorMessage = nil
        } catch {
            canWrite = false
            errorMessage = "Non riesco a leggere i video salvati. I dati originali sono conservati. Riprova."
        }
    }

    @discardableResult
    func save(_ video: SavedVideo) -> Bool {
        guard VideoLink.validID(video.id) else { return false }
        if contains(video.id) { return false }
        return commit([video] + videos)
    }

    @discardableResult
    func remove(_ id: String) -> SavedVideo? {
        guard let video = videos.first(where: { $0.id == id }) else { return nil }
        return commit(videos.filter { $0.id != id }) ? video : nil
    }

    @discardableResult
    func restore(_ video: SavedVideo) -> Bool {
        guard VideoLink.validID(video.id), !contains(video.id) else { return false }
        return commit((videos + [video]).sorted { $0.savedAt > $1.savedAt })
    }

    private func commit(_ next: [SavedVideo]) -> Bool {
        guard canWrite else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(next).write(to: fileURL, options: .atomic)
            videos = next
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Salvataggio non riuscito. Controlla lo spazio disponibile e riprova."
            return false
        }
    }

    private enum LibraryError: Error { case invalidData }
}
