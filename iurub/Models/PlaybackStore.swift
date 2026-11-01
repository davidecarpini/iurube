import Combine
import Foundation

struct PlaybackRecord: Codable, Equatable, Sendable {
    var video: SavedVideo
    var position: Double
    var duration: Double?
    var completed: Bool
    var updatedAt: Date

    // Far beyond a normal video, while excluding overflow and malformed events.
    static let maximumTime: Double = 30 * 24 * 60 * 60

    static func startTime(in url: URL) -> Double? {
        guard VideoLink.parse(url.absoluteString) != nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        for name in ["t", "start", "time_continue"] {
            if let raw = components.queryItems?.first(where: { $0.name == name })?.value,
               let seconds = parseTime(raw) { return seconds }
        }
        return nil
    }

    private static func parseTime(_ value: String) -> Double? {
        let value = value.lowercased()
        if value.range(of: #"^[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
           let seconds = Double(value), validTime(seconds) { return seconds }
        guard !value.isEmpty,
              let pattern = try? NSRegularExpression(pattern: #"^(?:([0-9]+)h)?(?:([0-9]+)m)?(?:([0-9]+(?:\.[0-9]+)?)s)?$"#),
              let match = pattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.range.length > 0 else { return nil }
        let multipliers: [Double] = [3600, 60, 1]
        var total: Double = 0
        for index in 1...3 {
            if let range = Range(match.range(at: index), in: value) {
                guard let number = Double(value[range]) else { return nil }
                total += number * multipliers[index - 1]
            }
        }
        return validTime(total) ? total : nil
    }

    static func validTime(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= maximumTime
    }
}

@MainActor
final class PlaybackStore: ObservableObject {
    @Published private(set) var current: PlaybackRecord?
    @Published private(set) var errorMessage: String?
    private var records: [String: PlaybackRecord] = [:]
    private var currentID: String?
    private var canWrite = true
    private let fileURL: URL

    private struct Snapshot: Codable {
        let version: Int
        let currentID: String?
        let records: [PlaybackRecord]
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iurub/playback.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: self.fileURL))
            guard snapshot.version == 1, snapshot.records.count <= 100,
                  Set(snapshot.records.map { $0.video.id }).count == snapshot.records.count,
                  snapshot.records.allSatisfy(Self.isValid),
                  snapshot.currentID == nil || snapshot.records.contains(where: { $0.video.id == snapshot.currentID }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            records = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.video.id, $0) })
            currentID = snapshot.currentID
            current = currentID.flatMap { records[$0] }
        } catch {
            canWrite = false
            errorMessage = "Non riesco a leggere il punto di riproduzione. I dati originali sono conservati; i nuovi progressi resteranno disponibili in questa sessione."
        }
    }

    @discardableResult
    func select(video: SavedVideo, startAt: Double? = nil) -> PlaybackRecord {
        var selected = records[video.id] ?? PlaybackRecord(video: video, position: 0, duration: nil, completed: false, updatedAt: Date())
        guard VideoLink.validID(video.id) else {
            errorMessage = "Impossibile riprendere questo video: il link YouTube non è valido."
            return selected
        }
        selected.video = mergedMetadata(existing: selected.video, incoming: video)
        if selected.completed {
            selected.position = 0
            selected.completed = false
        }
        if let startAt, PlaybackRecord.validTime(startAt) {
            selected.position = selected.duration.map { min(startAt, $0) } ?? startAt
        }
        selected.updatedAt = Date()
        records[video.id] = selected
        currentID = video.id
        current = selected
        prune()
        persist()
        return selected
    }

    func update(videoID: String, position: Double, duration: Double, ended: Bool) {
        guard var record = records[videoID], PlaybackRecord.validTime(position), PlaybackRecord.validTime(duration) else { return }
        if duration > 0 { record.duration = duration }
        record.position = record.duration.map { min(position, $0) } ?? position
        // Only an ended event establishes completion. Playback resumed away
        // from the final frame clears it, while a trailing pause at the end does not.
        if ended {
            record.completed = true
            if let duration = record.duration { record.position = duration }
        } else if let duration = record.duration, record.position < duration - 0.5 {
            record.completed = false
        }
        record.updatedAt = Date()
        records[videoID] = record
        // A late event from a previous player may update its bookmark, never selection.
        if currentID == videoID { current = record }
        persist()
    }

    func updateMetadata(_ video: SavedVideo) {
        guard var record = records[video.id] else { return }
        let merged = mergedMetadata(existing: record.video, incoming: video)
        guard merged != record.video else { return }
        record.video = merged
        records[video.id] = record
        if currentID == video.id { current = record }
        persist()
    }

    func clearCurrent() {
        currentID = nil
        current = nil
        persist()
    }

    private func mergedMetadata(existing: SavedVideo, incoming: SavedVideo) -> SavedVideo {
        var result = existing
        let title = incoming.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let channel = incoming.channel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty && title != "Video YouTube" { result.title = String(title.prefix(300)) }
        if !channel.isEmpty { result.channel = String(channel.prefix(120)) }
        return result
    }

    private static func isValid(_ record: PlaybackRecord) -> Bool {
        guard VideoLink.validID(record.video.id), PlaybackRecord.validTime(record.position),
              record.updatedAt.timeIntervalSince1970.isFinite else { return false }
        if let duration = record.duration {
            return PlaybackRecord.validTime(duration) && duration > 0 && record.position <= duration
        }
        return true
    }

    private func prune() {
        guard records.count > 100 else { return }
        let retained = records.values.filter { $0.video.id != currentID }
            .sorted { $0.updatedAt > $1.updatedAt }.prefix(currentID == nil ? 100 : 99)
        var next = Dictionary(uniqueKeysWithValues: retained.map { ($0.video.id, $0) })
        if let currentID, let selected = records[currentID] { next[currentID] = selected }
        records = next
    }

    private func persist() {
        guard canWrite else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let snapshot = Snapshot(version: 1, currentID: currentID,
                                    records: records.values.sorted { $0.updatedAt > $1.updatedAt })
            let data = try JSONEncoder().encode(snapshot)
            #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: fileURL, options: .atomic)
            #endif
            errorMessage = nil
        } catch {
            errorMessage = "Non riesco a salvare il punto di riproduzione. Puoi continuare a guardare, ma il progresso potrebbe non restare dopo la chiusura dell’app."
        }
    }
}
