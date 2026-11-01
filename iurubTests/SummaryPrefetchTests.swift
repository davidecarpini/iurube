import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import IurubCore
#else
@testable import iurub
#endif

private actor PrefetchTestService: VideoSummarizing {
    struct Call: Sendable { let id: UUID; let videoID: String; let question: String }
    private(set) var calls: [Call] = []
    private(set) var maximumActive = 0
    private var active = 0
    private var continuations: [UUID: CheckedContinuation<String, Error>] = [:]

    // Intentionally ignores cancellation so tests can deliver late provider replies.
    func reply(video: SavedVideo, history: [SummaryMessage], question: String, key: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let call = Call(id: UUID(), videoID: video.id, question: question)
            calls.append(call)
            active += 1
            maximumActive = max(maximumActive, active)
            continuations[call.id] = continuation
        }
    }
    func succeed(_ index: Int, text: String = "Riassunto di prova") {
        guard calls.indices.contains(index), let continuation = continuations.removeValue(forKey: calls[index].id) else { return }
        active -= 1
        continuation.resume(returning: text)
    }
    func fail(_ index: Int) {
        guard calls.indices.contains(index), let continuation = continuations.removeValue(forKey: calls[index].id) else { return }
        active -= 1
        continuation.resume(throwing: SummaryFailure.server)
    }
    func cancelAll() {
        let remaining = continuations.values
        continuations.removeAll()
        active = 0
        for continuation in remaining { continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor
struct SummaryPrefetchTests {
    private func video(_ id: String = "jfKfPfyJRdk") -> SavedVideo {
        SavedVideo(link: VideoLink(id: id, isShort: false), title: "Video di prova")
    }
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("iurub-prefetch-tests-\(UUID())/conversations.json")
    }
    private func waitFor(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(await condition(), "Timed out waiting for deterministic provider state")
    }

    @Test func testDeduplicatesActiveRequestsAndReusesPersistedSummary() async throws {
        let service = PrefetchTestService(), url = temporaryURL()
        defer { Task { await service.cancelAll() }; try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { "test-key" })
        let item = video()
        store.prefetch(video: item)
        store.prefetch(video: item)
        store.request(video: item)
        try await waitFor { await service.calls.count == 1 }
        #expect(store.busy == [item.id])
        #expect(store.queued.isEmpty)
        await service.succeed(0, text: "Già pronto")
        try await waitFor { store.busy.isEmpty }
        store.prefetch(video: item)
        store.request(video: item)
        #expect(await service.calls.count == 1)
        #expect(store.conversations[item.id]?.map(\.text) == ["Già pronto"])
        let reopened = SummaryStore(fileURL: url, service: service, keyProvider: { "test-key" })
        reopened.prefetch(video: item)
        reopened.request(video: item)
        #expect(reopened.busy.isEmpty)
        #expect(reopened.conversations == store.conversations)
        #expect(await service.calls.count == 1)
    }

    @Test func testRapidSavesAreDeduplicatedAndAutomaticallySerialized() async throws {
        let service = PrefetchTestService(), url = temporaryURL()
        defer { Task { await service.cancelAll() }; try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { "test-key" })
        let a = video(), b = video("M7lc1UVf-VE"), c = video("aqz-KE-bpKQ")
        [a, b, a, c, b].forEach { store.prefetch(video: $0) }
        try await waitFor { await service.calls.count == 1 }
        #expect(store.queued == [b.id, c.id])
        await service.succeed(0)
        try await waitFor { await service.calls.count == 2 }
        #expect(store.queued == [c.id])
        await service.succeed(1)
        try await waitFor { await service.calls.count == 3 }
        await service.succeed(2)
        try await waitFor { store.busy.isEmpty }
        #expect(await service.calls.map(\.videoID) == [a.id, b.id, c.id])
        #expect(await service.maximumActive == 1)
        #expect(store.queued.isEmpty)
        #expect(store.conversations.count == 3)
    }

    @Test func testManualRequestTakesPriorityOverQueuedWorkWithoutDuplication() async throws {
        let service = PrefetchTestService(), url = temporaryURL()
        defer { Task { await service.cancelAll() }; try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { "test-key" })
        let a = video(), b = video("M7lc1UVf-VE"), c = video("aqz-KE-bpKQ")
        [a, b, c].forEach { store.prefetch(video: $0) }
        try await waitFor { await service.calls.count == 1 }
        store.request(video: c)
        try await waitFor { await service.calls.count == 2 }
        #expect(store.queued == [b.id])
        #expect(await service.calls.map(\.videoID) == [a.id, c.id])
        await service.succeed(1)
        try await waitFor { !store.busy.contains(c.id) }
        store.prefetch(video: c)
        store.request(video: c)
        await service.succeed(0)
        try await waitFor { await service.calls.count == 3 }
        await service.succeed(2)
        try await waitFor { store.busy.isEmpty }
        #expect(await service.calls.map(\.videoID) == [a.id, c.id, b.id])
        #expect(await service.maximumActive == 2, "Only the explicit manual request may run beside an automatic request")
    }

    @Test func testFailureDoesNotAutomaticallyRetryAndManualRetryCanSucceed() async throws {
        let service = PrefetchTestService(), url = temporaryURL()
        defer { Task { await service.cancelAll() }; try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { "test-key" })
        let a = video(), b = video("M7lc1UVf-VE")
        store.prefetch(video: a); store.prefetch(video: b)
        try await waitFor { await service.calls.count == 1 }
        await service.fail(0)
        try await waitFor { await service.calls.count == 2 }
        #expect(store.errors[a.id] != nil)
        for _ in 0..<4 { store.prefetch(video: a) }
        #expect(await service.calls.count == 2)
        #expect(!store.queued.contains(a.id))
        store.request(video: a)
        try await waitFor { await service.calls.count == 3 }
        await service.succeed(1); await service.succeed(2, text: "Retry riuscito")
        try await waitFor { store.busy.isEmpty }
        #expect(store.errors[a.id] == nil)
        #expect(store.conversations[a.id]?.map(\.text) == ["Retry riuscito"])
    }

    @Test func testMissingKeyStopsEachAttemptWithoutNetworkOrAutomaticRetry() async throws {
        let service = PrefetchTestService(), url = temporaryURL()
        defer { Task { await service.cancelAll() }; try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var key: String?, keyReads = 0
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { keyReads += 1; return key })
        let a = video(), b = video("M7lc1UVf-VE")
        store.prefetch(video: a); store.prefetch(video: b); store.prefetch(video: a)
        try await waitFor { store.busy.isEmpty && store.errors.count == 2 }
        #expect(await service.calls.isEmpty)
        #expect(keyReads == 2)
        store.prefetch(video: a); store.prefetch(video: b)
        #expect(keyReads == 2)
        #expect(store.queued.isEmpty)
        key = "test-key"
        store.request(video: a)
        try await waitFor { await service.calls.count == 1 }
        await service.succeed(0)
        try await waitFor { store.busy.isEmpty }
        #expect(store.conversations[a.id]?.count == 1)
        #expect(store.errors[a.id] == nil)
    }

    @Test func testCancellationRetainsAutomaticSlotUntilProviderActuallyReturns() async throws {
        let service = PrefetchTestService(), url = temporaryURL()
        defer { Task { await service.cancelAll() }; try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { "test-key" })
        let a = video(), b = video("M7lc1UVf-VE")
        store.prefetch(video: a); store.prefetch(video: b)
        try await waitFor { await service.calls.count == 1 }
        store.cancel(videoID: a.id)
        store.prefetch(video: a)
        #expect(await service.calls.count == 1)
        #expect(store.queued == [b.id])
        await service.succeed(0, text: "Risposta annullata")
        try await waitFor { await service.calls.count == 2 }
        #expect(store.conversations[a.id] == nil)
        #expect(store.errors[a.id] != nil)
        await service.succeed(1)
        try await waitFor { store.busy.isEmpty }
        store.prefetch(video: a)
        #expect(await service.calls.count == 2)
        #expect(await service.maximumActive == 1)
        store.request(video: a)
        try await waitFor { await service.calls.count == 3 }
        await service.succeed(2, text: "Ripreso manualmente")
        try await waitFor { store.busy.isEmpty }
        #expect(store.conversations[a.id]?.map(\.text) == ["Ripreso manualmente"])
    }

    @Test func testCancellingQueuedVideoRemovesOnlyThatAutomaticRequest() async throws {
        let service = PrefetchTestService(), url = temporaryURL()
        defer { Task { await service.cancelAll() }; try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { "test-key" })
        let a = video(), b = video("M7lc1UVf-VE")
        store.prefetch(video: a); store.prefetch(video: b)
        try await waitFor { await service.calls.count == 1 }
        store.cancel(videoID: b.id)
        #expect(store.queued.isEmpty)
        #expect(store.errors[b.id] != nil)
        await service.succeed(0)
        try await waitFor { store.busy.isEmpty }
        store.prefetch(video: b)
        #expect(await service.calls.count == 1)
        store.request(video: b)
        try await waitFor { await service.calls.count == 2 }
        await service.succeed(1)
        try await waitFor { store.busy.isEmpty }
        #expect(store.conversations[b.id]?.count == 1)
    }

    @Test func testClearedRequestCannotOverwriteNewChatOrReleaseAnotherTaskSlot() async throws {
        let service = PrefetchTestService(), url = temporaryURL()
        defer { Task { await service.cancelAll() }; try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { "test-key" })
        let a = video(), b = video("M7lc1UVf-VE")
        store.prefetch(video: a); store.prefetch(video: b)
        try await waitFor { await service.calls.count == 1 }
        store.clear(videoID: a.id)
        store.request(video: a)
        try await waitFor { await service.calls.count == 2 }
        await service.succeed(1, text: "Chat nuova")
        try await waitFor { store.conversations[a.id]?.first?.text == "Chat nuova" }
        #expect(store.queued == [b.id], "The cancelled automatic request still occupies its own slot")
        await service.succeed(0, text: "Risposta vecchia")
        try await waitFor { await service.calls.count == 3 }
        #expect(store.conversations[a.id]?.map(\.text) == ["Chat nuova"])
        await service.succeed(2)
        try await waitFor { store.busy.isEmpty }
        #expect(store.errors[a.id] == nil)
        #expect(store.conversations[a.id]?.map(\.text) == ["Chat nuova"])
    }

    @Test func testPrefetchPreservesExistingFollowUpConversation() async throws {
        let service = PrefetchTestService(), url = temporaryURL()
        defer { Task { await service.cancelAll() }; try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let item = video()
        let history = [SummaryMessage(role: "assistant", text: "Riassunto"),
                       SummaryMessage(role: "user", text: "Approfondisci"),
                       SummaryMessage(role: "assistant", text: "Approfondimento")]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = try JSONEncoder().encode([item.id: history])
        try original.write(to: url)
        let store = SummaryStore(fileURL: url, service: service, keyProvider: { "test-key" })
        store.prefetch(video: item)
        #expect(store.busy.isEmpty)
        #expect(store.queued.isEmpty)
        #expect(store.conversations[item.id] == history)
        #expect(await service.calls.isEmpty)
        #expect(try Data(contentsOf: url) == original)
    }
}
