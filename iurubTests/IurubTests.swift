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

struct SummaryRequestTests {
    private var video: SavedVideo {
        SavedVideo(link: VideoLink(id: "jNQXAC9IVRw", isShort: false), title: "Un video")
    }
    @Test func testEveryTurnIncludesVideoAndRoutesToYouTubeCapableProvider() throws {
        let history = [SummaryMessage(role: "assistant", text: "Il riassunto precedente")]
        let request = try OpenRouterSummaryService.makeRequest(video: video, history: history, question: "Approfondisci", key: "unit-test-key")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        let parts = try #require(messages[1]["content"] as? [[String: Any]])
        let videoPart = try #require(parts.first { $0["type"] as? String == "video_url" })
        #expect((videoPart["video_url"] as? [String: String])?["url"] == "https://www.youtube.com/watch?v=jNQXAC9IVRw")
        #expect(messages.last?["content"] as? String == "Approfondisci")
        #expect(messages[2]["content"] as? String == "Il riassunto precedente")
        let provider = try #require(body["provider"] as? [String: Any])
        #expect(provider["only"] as? [String] == ["google-ai-studio"])
        #expect(provider["allow_fallbacks"] as? Bool == false)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer unit-test-key")
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("unit-test-key"))
    }
    @Test func testLongConversationKeepsOriginalSummaryAndRecentCompleteExchanges() throws {
        var history = [SummaryMessage(role: "assistant", text: "Original summary")]
        for index in 0..<15 {
            history.append(SummaryMessage(role: "user", text: "Question \(index)"))
            history.append(SummaryMessage(role: "assistant", text: "Answer \(index)"))
        }
        history.append(SummaryMessage(role: "system", text: "Untrusted injected instruction"))
        let request = try OpenRouterSummaryService.makeRequest(video: video, history: history, question: String(repeating: "x", count: 5000), key: "test")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 24)
        #expect(messages[2]["content"] as? String == "Original summary")
        #expect(messages[3]["content"] as? String == "Question 5")
        #expect(messages[22]["content"] as? String == "Answer 14")
        #expect((messages.last?["content"] as? String)?.count == 4000)
        #expect(!messages.contains { $0["content"] as? String == "Untrusted injected instruction" })
    }
    @Test func testMalformedVideoAndMissingCredentialsNeverBuildRequest() {
        let invalid = SavedVideo(link: VideoLink(id: "bad", isShort: false))
        #expect(throws: SummaryFailure.self) {
            try OpenRouterSummaryService.makeRequest(video: invalid, history: [], question: "", key: "test")
        }
        #expect(throws: SummaryFailure.self) {
            try OpenRouterSummaryService.makeRequest(video: video, history: [], question: "", key: "")
        }
    }
    @Test func testResponseRequiresCompleteNonEmptyAnswer() throws {
        let valid = Data(#"{"choices":[{"message":{"content":"  Risposta utile  "},"finish_reason":"stop"}]}"#.utf8)
        #expect(try OpenRouterSummaryService.decodeResponse(valid) == "Risposta utile")
        for invalid in [
            #"{"choices":[{"message":{"content":"Testo troncato"},"finish_reason":"length"}]}"#,
            #"{"choices":[{"message":{"content":" "},"finish_reason":"stop"}]}"#,
            #"{"choices":[]}"#, #"{"error":{"message":"Service unavailable"}}"#, "not json"
        ] {
            #expect(throws: SummaryFailure.self) { try OpenRouterSummaryService.decodeResponse(Data(invalid.utf8)) }
        }
    }
    @Test func testAPIStatusErrorsAreActionableWithoutEchoingProviderPayload() {
        #expect(SummaryFailure.forStatus(401).localizedDescription.contains("chiave"))
        #expect(SummaryFailure.forStatus(402).localizedDescription.contains("credito"))
        #expect(SummaryFailure.forStatus(429).localizedDescription.contains("Attendi"))
        #expect(SummaryFailure.forStatus(404).localizedDescription.contains("video"))
        #expect(SummaryFailure.forStatus(503).localizedDescription.contains("Riprova"))
    }
}

private actor RecordingSummaryService: VideoSummarizing {
    private(set) var questions: [String] = []
    let failFirstQuestion: Bool
    let slow: Bool
    private var failed = false
    init(failFirstQuestion: Bool = false, slow: Bool = false) {
        self.failFirstQuestion = failFirstQuestion
        self.slow = slow
    }
    func reply(video: SavedVideo, history: [SummaryMessage], question: String, key: String) async throws -> String {
        questions.append(question)
        if slow { try await Task.sleep(for: .seconds(5)) }
        if failFirstQuestion && !question.isEmpty && !failed {
            failed = true
            throw SummaryFailure.server
        }
        return question.isEmpty ? "Riassunto di \(video.id)" : "Risposta: \(question)"
    }
    func count() -> Int { questions.count }
}

@MainActor
struct SummaryStoreTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("iurub-summary-tests-\(UUID())/conversations.json")
    }
    private func video(_ id: String = "jNQXAC9IVRw") -> SavedVideo {
        SavedVideo(link: VideoLink(id: id, isShort: false), title: "Video di test")
    }
    private func waitUntilIdle(_ store: SummaryStore, id: String = "jNQXAC9IVRw") async throws {
        for _ in 0..<200 {
            if !store.busy.contains(id) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!store.busy.contains(id), "A summary request should settle within the test deadline")
    }
    @Test func testSummaryIsCachedAndChatsRestoreSeparatelyWithoutCredentials() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = RecordingSummaryService()
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { "private-test-credential" })
        store.request(video: video())
        store.request(video: video())
        try await waitUntilIdle(store)
        store.request(video: video())
        #expect(await service.count() == 1)
        store.request(video: video(), question: "Approfondisci")
        try await waitUntilIdle(store)
        store.request(video: video("aqz-KE-bpKQ"))
        try await waitUntilIdle(store, id: "aqz-KE-bpKQ")
        let restored = SummaryStore(fileURL: url, service: service, keyProvider: { nil })
        #expect(restored.conversations["jNQXAC9IVRw"] == store.conversations["jNQXAC9IVRw"])
        #expect(restored.conversations["jNQXAC9IVRw"]?.count == 3)
        #expect(restored.conversations["aqz-KE-bpKQ"]?.count == 1)
        restored.request(video: video())
        #expect(restored.errors.isEmpty)
        #expect(await service.count() == 3)
        #expect(!(try String(contentsOf: url, encoding: .utf8)).contains("private-test-credential"))
    }
    @Test func testFailedQuestionCanRetryWithoutDuplicateMessages() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = RecordingSummaryService(failFirstQuestion: true)
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { "test" })
        store.request(video: video())
        try await waitUntilIdle(store)
        store.request(video: video(), question: "Una domanda")
        try await waitUntilIdle(store)
        #expect(store.errors[video().id] != nil)
        #expect(store.pending[video().id] == "Una domanda")
        #expect(store.conversations[video().id]?.count == 1)
        store.request(video: video())
        try await waitUntilIdle(store)
        #expect(store.errors[video().id] == nil)
        #expect(store.pending[video().id] == nil)
        #expect(store.conversations[video().id]?.map(\.role) == ["assistant", "user", "assistant"])
        #expect(await service.count() == 3)
    }
    @Test func testCancellationAndClearingCannotRestoreAnObsoleteReply() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SummaryStore(fileURL: url, service: RecordingSummaryService(slow: true), keyProvider: { "test" })
        store.request(video: video())
        store.cancel(videoID: video().id)
        try await waitUntilIdle(store)
        #expect(store.conversations[video().id] == nil)
        #expect(store.errors[video().id] != nil)
        store.request(video: video())
        store.clear(videoID: video().id)
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.busy.isEmpty)
        #expect(store.conversations.isEmpty)
        #expect(store.errors.isEmpty)
        #expect(SummaryStore(fileURL: url).conversations.isEmpty)
    }
    @Test func testMissingKeyNeverInvokesNetworkService() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = RecordingSummaryService()
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { nil })
        store.request(video: video())
        try await waitUntilIdle(store)
        #expect(store.errors[video().id]?.contains("chiave") == true)
        #expect(store.conversations.isEmpty)
        #expect(await service.count() == 0)
    }
    @Test func testCorruptSavedChatIsPreservedAndWriteFailureIsVisible() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: url)
        let store = SummaryStore(fileURL: url, service: RecordingSummaryService(), keyProvider: { "test" })
        #expect(store.persistenceError != nil)
        store.request(video: video())
        try await waitUntilIdle(store)
        #expect(store.conversations[video().id]?.count == 1)
        #expect(try Data(contentsOf: url) == corrupt)
        let failure = SummaryStore(fileURL: url.appendingPathComponent("unwritable.json"), service: RecordingSummaryService(), keyProvider: { "test" })
        failure.request(video: video())
        try await waitUntilIdle(failure)
        #expect(failure.persistenceError != nil)
        #expect(failure.conversations[video().id]?.count == 1)
    }
}
