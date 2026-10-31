import AppKit
import WebKit

@main
struct WebKitChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let runner = Runner()
        Task { await runner.run() }
        app.run()
    }
}

@MainActor
final class Runner {
    let session = BrowserSession()
    var window: NSWindow!
    var passed = 0
    var received: [SavedVideo] = []

    func check(_ condition: Bool, _ message: String) throws {
        guard condition else { throw NSError(domain: "iurub", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        passed += 1
        print("PASS: \(message)")
    }
    func js(_ source: String) async throws -> Any { try await session.webView.evaluateJavaScript(source) ?? NSNull() }
    func settle() async { try? await Task.sleep(for: .milliseconds(400)) }
    func waitFor(_ source: String, timeout: Int = 50) async throws -> Any {
        for _ in 0..<timeout {
            if let value = try? await js(source), (value as? Bool) == true { return value }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "iurub", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timeout: \(source)"])
    }
    func run() async {
        do {
            window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 420, height: 860), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "iurub · verifica WebKit"
            window.contentView = session.webView
            window.orderBack(nil)
            session.onSave = { [weak self] video in self?.received.append(video) }
            let html = try String(contentsOf: Bundle.main.url(forResource: "YouTubeFixture", withExtension: "html")!, encoding: .utf8)
            session.webView.loadHTMLString(html, baseURL: URL(string: "https://m.youtube.com/"))
            _ = try await waitFor("!!document.querySelector('.iurub-save')")
            try check(try await js("getComputedStyle(document.getElementById('short-shelf')).display") as? String == "none", "Real WebKit hides Shorts by default")
            _ = try await js("document.querySelector('.iurub-save').click()")
            await settle()
            try check(received.first?.id == "jfKfPfyJRdk", "WKScriptMessage origin validation accepts legitimate save")
            try check(received.first?.title == "Musica per concentrarsi", "Metadata reaches native Swift intact")
            session.configure(shortsEnabled: false, savedIDs: ["jfKfPfyJRdk"])
            await settle()
            try check(try await js("document.querySelector('.iurub-save').dataset.saved") as? String == "true", "Native persisted state updates WebKit save button")
            session.configure(shortsEnabled: true, savedIDs: [])
            await settle()
            try check(try await js("getComputedStyle(document.getElementById('short-shelf')).display") as? String != "none", "Toggle restores Shorts without reloading")
            session.configure(shortsEnabled: false, savedIDs: [])
            _ = try await js("addDynamic()")
            await settle()
            try check(try await js("!!document.querySelector('#dynamic .iurub-save')") as? Bool == true, "MutationObserver catches a newly inserted video")
            _ = try await js("document.querySelector('#dynamic .iurub-save').click()")
            await settle()
            try check(received.last?.id == "M7lc1UVf-VE", "Dynamic video saves through the native bridge")
            let previousURL = session.webView.url
            _ = try await js("history.pushState({}, '', '/shorts/aqz-KE-bpKQ')")
            await settle()
            try check(session.webView.url == previousURL, "Disabled Shorts cannot navigate using SPA history")
            try check(session.notice != nil, "Native UI receives a blocked-Short notice")
            session.notice = nil
            session.load(URL(string:"https://m.youtube.com/shorts/aqz-KE-bpKQ")!)
            try check(session.webView.url == previousURL && session.notice != nil, "Native URL navigation also blocks Shorts")
            let fixtureSnapshot = WKSnapshotConfiguration()
            fixtureSnapshot.rect = NSRect(x:0, y:0, width:420, height:860)
            if let image = try? await session.webView.takeSnapshot(configuration:fixtureSnapshot),
               let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff),
               let png = bitmap.representation(using:.png,properties:[:]) {
                try png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("webkit-fixture.png"))
            }
            let beforeSpoof = received.count
            session.webView.navigationDelegate = nil
            session.webView.loadHTMLString("<body>Untrusted origin</body>", baseURL: URL(string:"https://example.com/"))
            _ = try await waitFor("document.body?.textContent === 'Untrusted origin'")
            _ = try await js("window.webkit.messageHandlers.iurub.postMessage({type:'save',video:{id:'aqz-KE-bpKQ',url:'https://m.youtube.com/watch?v=aqz-KE-bpKQ',title:'Spoof'}}); true")
            await settle()
            try check(received.count == beforeSpoof, "Native bridge rejects save messages from another origin")
            // Load the actual mobile site using the production WKWebView configuration.
            session.webView.navigationDelegate = session
            session.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
            session.home()
            _ = try await waitFor("document.readyState === 'complete' && location.hostname.endsWith('youtube.com')", timeout: 200)
            await settle()
            let summary = try await js("JSON.stringify({url:location.href,title:document.title,buttons:document.querySelectorAll('.iurub-save').length,filter:document.documentElement.classList.contains('iurub-no-shorts'),text:document.body.innerText.slice(0,700)})")
            print("LIVE YOUTUBE: \(summary)")
            try check(try await js("getComputedStyle(document.querySelector('.pivot-shorts').closest('ytm-pivot-bar-item-renderer')).display") as? String == "none", "Shorts bottom tab is hidden on live YouTube")
            session.load(URL(string: "https://m.youtube.com/results?search_query=big+buck+bunny")!)
            _ = try await waitFor("location.pathname === '/results' && document.readyState === 'complete'", timeout:200)
            await settle()
            try check((try await js("document.querySelectorAll('.iurub-save').length") as? Int ?? 0) > 0, "Save buttons appear in live YouTube search results")
            let liveVideo = try await js("JSON.stringify(document.querySelector('.iurub-save').__iurubVideo)")
            print("LIVE VIDEO METADATA: \(liveVideo)")
            let previousSaves = received.count
            _ = try await js("document.querySelector('.iurub-save').click(); true")
            await settle()
            try check(received.count == previousSaves + 1, "A live search card sends a save to native Swift")
            let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("iurub-live-check-\(UUID())/videos.json")
            defer { try? FileManager.default.removeItem(at: storeURL.deletingLastPathComponent()) }
            let store = LibraryStore(fileURL: storeURL)
            try check(store.save(received.last!), "Live YouTube video is saved atomically")
            try check(LibraryStore(fileURL: storeURL).videos.first?.id == received.last?.id, "Live saved video survives a library reload")
            try check(try await js("typeof window.iurub === 'object'") as? Bool == true, "Bridge loads on live YouTube in WebKit")
            let config = WKSnapshotConfiguration()
            config.rect = NSRect(x:0, y:0, width:420, height:860)
            if let image = try? await session.webView.takeSnapshot(configuration: config),
               let tiff = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using:.png, properties:[:]) {
                try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            }
            print("PASS: \(passed) native WebKit checks")
            exit(0)
        } catch {
            print("FAIL after \(passed) checks: \(error)")
            exit(1)
        }
    }
}
