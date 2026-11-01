import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import IurubCore
#else
@testable import iurub
#endif

struct PlaybackTimestampTests {
    @Test func testRecognizesExplicitYouTubeTimes() {
        let values: [(String, Double)] = [
            ("t=42", 42), ("start=12.5", 12.5), ("time_continue=123", 123),
            ("t=1h2m3s", 3723), ("t=2m", 120), ("t=1h30s", 3630),
            ("t=90s", 90), ("t=0", 0), ("t=3.5s", 3.5),
            ("t=7&start=90", 7), ("t=invalid&start=18", 18)
        ]
        for (query, expected) in values {
            let url = URL(string: "https://youtu.be/jNQXAC9IVRw?\(query)")!
            #expect(PlaybackRecord.startTime(in: url) == expected)
        }
    }
    @Test func testRejectsMalformedNegativeOverflowAndForeignTimes() {
        for value in ["-1", "nan", "NaN", "inf", "1e100", "3x", "m", "h", "s", "1s2m", "1m2m", "1hgarbage", "9999999999999999999999999999999999999999h", "2592001", "%20", "1%20m"] {
            #expect(PlaybackRecord.startTime(in: URL(string: "https://youtube.com/watch?v=jNQXAC9IVRw&t=\(value)")!) == nil)
        }
        #expect(PlaybackRecord.startTime(in: URL(string: "https://evil.com/watch?v=jNQXAC9IVRw&t=42")!) == nil)
        #expect(PlaybackRecord.startTime(in: URL(string: "https://youtu.be/jNQXAC9IVRw")!) == nil)
    }
}

@MainActor
struct PlaybackStoreTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("iurub-playback-tests-\(UUID())/playback.json")
    }
    private func video(_ id: String = "jNQXAC9IVRw", title: String = "Video di prova") -> SavedVideo {
        SavedVideo(link: VideoLink(id: id, isShort: false), title: title, channel: "Canale", savedAt: Date(timeIntervalSince1970: 100))
    }
    @Test func testSelectedVideoAndPositionSurviveRestartAndRemainIsolated() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlaybackStore(fileURL: url)
        #expect(store.current == nil)
        #expect(store.select(video: video()).position == 0)
        store.update(videoID: video().id, position: 42, duration: 300, ended: false)
        #expect(store.select(video: video()).position == 42)
        let other = video("aqz-KE-bpKQ")
        #expect(store.select(video: other).position == 0)
        store.update(videoID: other.id, position: 91, duration: 600, ended: false)
        // A late event is allowed to update an existing bookmark without stealing selection.
        store.update(videoID: video().id, position: 43, duration: 300, ended: false)
        #expect(store.current?.video.id == other.id)
        #expect(store.current?.position == 91)
        let reopened = PlaybackStore(fileURL: url)
        #expect(reopened.current == store.current)
        #expect(reopened.select(video: video()).position == 43)
        #expect(reopened.select(video: other).position == 91)
        #expect(reopened.errorMessage == nil)
    }
    @Test func testCompletionRequiresEndedAndRestartsOnlyOnNewSelection() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlaybackStore(fileURL: url)
        store.select(video: video())
        store.update(videoID: video().id, position: 99.9, duration: 100, ended: false)
        #expect(store.current?.completed == false)
        #expect(store.select(video: video()).position == 99.9)
        store.update(videoID: video().id, position: 100, duration: 100, ended: true)
        #expect(store.current?.completed == true)
        let reopened = PlaybackStore(fileURL: url)
        #expect(reopened.current?.completed == true)
        #expect(reopened.select(video: video()).position == 0)
        #expect(reopened.current?.completed == false)
        reopened.update(videoID: video().id, position: 100, duration: 100, ended: true)
        #expect(reopened.select(video: video(), startAt: 42).position == 42)
        #expect(reopened.current?.completed == false)
    }
    @Test func testReplayClearsCompletionAndRestoresItsNewPosition() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlaybackStore(fileURL: url)
        store.select(video: video())
        store.update(videoID: video().id, position: 100, duration: 100, ended: true)
        store.update(videoID: video().id, position: 100, duration: 100, ended: false)
        #expect(store.current?.completed == true, "A final pause must not undo completion")
        store.update(videoID: video().id, position: 99.8, duration: 100, ended: false)
        #expect(store.current?.completed == true)
        store.update(videoID: video().id, position: 42, duration: 100, ended: false)
        let reopened = PlaybackStore(fileURL: url)
        #expect(reopened.current?.completed == false)
        #expect(reopened.current?.position == 42)
        #expect(reopened.select(video: video()).position == 42)
    }

    @Test func testInvalidAndUnknownProgressEventsCannotReplaceCurrentState() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlaybackStore(fileURL: url)
        store.select(video: video())
        store.update(videoID: video().id, position: 42, duration: 100, ended: false)
        let original = store.current
        store.update(videoID: "aqz-KE-bpKQ", position: 20, duration: 100, ended: true)
        for invalid in [-1, Double.nan, Double.infinity, PlaybackRecord.maximumTime + 1] {
            store.update(videoID: video().id, position: invalid, duration: 100, ended: true)
            store.update(videoID: video().id, position: 50, duration: invalid, ended: true)
        }
        #expect(store.current == original)
        store.update(videoID: video().id, position: 150, duration: 100, ended: false)
        #expect(store.current?.position == 100)
        #expect(store.current?.completed == false)
        #expect(PlaybackStore(fileURL: url).current == store.current)
    }
    @Test func testUnknownDurationAndExplicitStartAreHandledWithoutLosingBookmark() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlaybackStore(fileURL: url)
        #expect(store.select(video: video(), startAt: 42).position == 42)
        store.update(videoID: video().id, position: 60, duration: 0, ended: false)
        #expect(store.current?.duration == nil)
        #expect(store.select(video: video(), startAt: .nan).position == 60)
        #expect(store.select(video: video(), startAt: -1).position == 60)
        store.update(videoID: video().id, position: 60, duration: 90, ended: false)
        #expect(store.select(video: video(), startAt: 100).position == 90)
        #expect(store.select(video: video(), startAt: 0).position == 0)
        store.select(video: video("bad"))
        #expect(store.current?.video.id == video().id)
        #expect(store.errorMessage != nil)
    }
    @Test func testMetadataOnlyUpdatesTitleAndChannel() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlaybackStore(fileURL: url)
        store.select(video: video())
        store.update(videoID: video().id, position: 42, duration: 100, ended: false)
        let original = try #require(store.current)
        let metadata = SavedVideo(link: VideoLink(id: video().id, isShort: true), title: "Titolo aggiornato", channel: "Nuovo canale", savedAt: Date())
        store.updateMetadata(metadata)
        let updated = try #require(store.current)
        #expect(updated.video.title == "Titolo aggiornato")
        #expect(updated.video.channel == "Nuovo canale")
        #expect(updated.video.isShort == original.video.isShort)
        #expect(updated.video.savedAt == original.video.savedAt)
        #expect(updated.position == original.position)
        #expect(updated.duration == original.duration)
        #expect(updated.completed == original.completed)
        #expect(updated.updatedAt == original.updatedAt)
        store.updateMetadata(SavedVideo(link: VideoLink(id: video().id, isShort: false)))
        #expect(store.current == updated, "Placeholder metadata must not replace the known title")
        store.updateMetadata(video("aqz-KE-bpKQ", title: "Unrelated"))
        #expect(store.current == updated)
    }
    @Test func testClearCurrentDoesNotErasePerVideoBookmarks() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlaybackStore(fileURL: url)
        store.select(video: video())
        store.update(videoID: video().id, position: 42, duration: 100, ended: false)
        store.clearCurrent()
        let reopened = PlaybackStore(fileURL: url)
        #expect(reopened.current == nil)
        #expect(reopened.select(video: video()).position == 42)
    }
    @Test func testCorruptOrSemanticallyInvalidFileIsPreserved() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        for original in [Data("{corrupt".utf8), Data(#"{"version":1,"currentID":"jNQXAC9IVRw","records":[]}"#.utf8)] {
            try original.write(to: url)
            let store = PlaybackStore(fileURL: url)
            #expect(store.current == nil)
            #expect(store.errorMessage != nil)
            store.select(video: video())
            store.update(videoID: video().id, position: 42, duration: 100, ended: false)
            #expect(store.current?.position == 42)
            #expect(store.errorMessage != nil)
            #expect(try Data(contentsOf: url) == original)
        }
    }
    @Test func testWriteFailureKeepsPlaybackUsableAndReportsPersistenceError() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: url)
        let store = PlaybackStore(fileURL: url.appendingPathComponent("progress.json"))
        store.select(video: video())
        store.update(videoID: video().id, position: 42, duration: 100, ended: false)
        #expect(store.current?.position == 42)
        #expect(store.errorMessage != nil)
    }
    @Test func testKeepsAtMostOneHundredBookmarksIncludingCurrentVideo() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = PlaybackStore(fileURL: url)
        for index in 0..<101 {
            let selected = video(String(format: "%011d", index))
            store.select(video: selected)
            store.update(videoID: selected.id, position: 42, duration: 100, ended: false)
        }
        let data = try Data(contentsOf: url)
        let snapshot = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let records = try #require(snapshot["records"] as? [[String: Any]])
        #expect(records.count == 100)
        let reopened = PlaybackStore(fileURL: url)
        #expect(reopened.current?.video.id == "00000000100")
        #expect(reopened.current?.position == 42)
        #expect(reopened.select(video: video("00000000000")).position == 0)
        #expect(reopened.select(video: video("00000000100")).position == 42)
    }
}
