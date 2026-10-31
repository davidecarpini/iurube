import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import IurubCore
#else
@testable import iurub
#endif

struct VideoLinkTests {
    @Test func testNormalizesShareLinksAndRemovesTracking() {
        let forms = [
            "https://youtu.be/jfKfPfyJRdk?si=tracking",
            "https://www.youtube.com/watch?v=jfKfPfyJRdk&t=123",
            "https://m.youtube.com/watch?list=PLtest&v=jfKfPfyJRdk",
            "https://www.youtube.com/embed/jfKfPfyJRdk",
            "https://www.youtube.com/live/jfKfPfyJRdk",
            "  https://youtube.com/watch?v=jfKfPfyJRdk\n"
        ]
        for value in forms {
            #expect(VideoLink.parse(value)?.url.absoluteString == "https://m.youtube.com/watch?v=jfKfPfyJRdk")
        }
    }
    @Test func testRejectsSpoofedOriginsAndMalformedIDs() {
        let rejected = [
            "https://youtube.com.evil.com/watch?v=jfKfPfyJRdk",
            "https://notyoutube.com/watch?v=jfKfPfyJRdk",
            "https://youtube.com@evil.com/watch?v=jfKfPfyJRdk",
            "https://evil@youtube.com/watch?v=jfKfPfyJRdk",
            "javascript:alert(1)", "file:///watch?v=jfKfPfyJRdk",
            "https://youtube.com:8080/watch?v=jfKfPfyJRdk",
            "https://youtube.com/watch?v=too-short", "https://youtu.be/../../jfKfPfyJRdk",
            "https://youtube.com/playlist?list=WL", "https://youtube.com/watch?v=jfKfPfyJRdk%22"
        ]
        for value in rejected { #expect(VideoLink.parse(value) == nil) }
    }
    @Test func testShortIdentityAndCanonicalURL() {
        let short = VideoLink.parse("https://youtube.com/shorts/aqz-KE-bpKQ?si=test")
        #expect(short?.id == "aqz-KE-bpKQ")
        #expect(short?.isShort == true)
        #expect(short?.url.absoluteString == "https://m.youtube.com/shorts/aqz-KE-bpKQ")
    }
    @Test func testSanitizesMetadataSizeAndEmptyTitles() {
        let link = VideoLink(id: "jfKfPfyJRdk", isShort: false)
        #expect(SavedVideo(link: link, title: "  \n ").title == "Video YouTube")
        #expect(SavedVideo(link: link, title: String(repeating: "a", count: 1000)).title.count == 300)
    }
}

@MainActor
struct LibraryTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("iurub-tests-\(UUID())/videos.json")
    }
    private func video(_ id: String = "jfKfPfyJRdk", at date: Date = Date()) -> SavedVideo {
        SavedVideo(link: VideoLink(id: id, isShort: false), title: "Un video", channel: "Un canale", savedAt: date)
    }
    @Test func testSavePersistsAcrossInstancesAndDeduplicatesURLForms() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LibraryStore(fileURL: url)
        #expect(store.save(video()))
        #expect(!(store.save(SavedVideo(link: VideoLink.parse("https://youtu.be/jfKfPfyJRdk")!))))
        let reopened = LibraryStore(fileURL: url)
        #expect(reopened.videos.count == 1)
        #expect(reopened.videos.first?.title == "Un video")
        #expect(reopened.errorMessage == nil)
    }
    @Test func testRemoveUndoAndOrderSurviveRestart() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let old = video("jfKfPfyJRdk", at: Date(timeIntervalSince1970: 100))
        let new = video("aqz-KE-bpKQ", at: Date(timeIntervalSince1970: 200))
        let store = LibraryStore(fileURL: url)
        #expect(store.save(old)); #expect(store.save(new))
        #expect(store.videos.map(\.id) == [new.id, old.id])
        let removed = try #require(store.remove(old.id))
        #expect(!(LibraryStore(fileURL: url).contains(old.id)))
        #expect(store.restore(removed))
        #expect(LibraryStore(fileURL: url).videos == [new, old])
        #expect(!(store.restore(removed)))
    }
    @Test func testCorruptLibraryIsPreservedInsteadOfOverwritten() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("{corrupt".utf8)
        try original.write(to: url)
        let store = LibraryStore(fileURL: url)
        #expect(store.errorMessage != nil)
        #expect(!(store.save(video())))
        #expect(try Data(contentsOf: url) == original)
    }
    @Test func testWriteFailureDoesNotClaimVideoIsSaved() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("iurub-file-\(UUID())")
        defer { try? FileManager.default.removeItem(at: parent) }
        try Data("not a directory".utf8).write(to: parent)
        let store = LibraryStore(fileURL: parent.appendingPathComponent("videos.json"))
        #expect(!(store.save(video())))
        #expect(store.videos.isEmpty)
        #expect(store.errorMessage != nil)
    }
    @Test func testInvalidOrDuplicatePersistedIDsCannotBeLoaded() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode([video(), video()]).write(to: url)
        #expect(LibraryStore(fileURL: url).errorMessage != nil)
        try JSONEncoder().encode([video("bad")]).write(to: url)
        #expect(LibraryStore(fileURL: url).errorMessage != nil)
    }
    @Test func testShortsPreferenceDefaultsOffAndPersists() async {
        let suite = "iurub.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        #expect(!(settings.shortsEnabled))
        settings.shortsEnabled = true
        #expect(AppSettings(defaults: defaults).shortsEnabled)
        settings.shortsEnabled = false
        #expect(!(AppSettings(defaults: defaults).shortsEnabled))
    }
}
