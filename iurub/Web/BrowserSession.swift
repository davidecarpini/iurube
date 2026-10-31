import Combine
import Foundation
import SwiftUI
import WebKit

@MainActor
final class BrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var currentVideo: SavedVideo?
    @Published private(set) var loadError: String?
    @Published var notice: String?
    @Published var externalURL: URL?
    private(set) var webView: WKWebView!
    var onSave: ((SavedVideo) -> Void)?
    private var shortsEnabled = false
    private var savedIDs: [String] = []
    private var observers: [NSKeyValueObservation] = []
    private let messageProxy = MessageProxy()
    private var lastURL: URL = URL(string: "https://m.youtube.com/")!
    private(set) var hasLoaded = false

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        #endif
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        messageProxy.owner = self
        config.userContentController.add(messageProxy, name: "iurub")
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        #endif
        #if DEBUG
        webView.isInspectable = true
        #endif
        observers = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in self?.isLoading = view.isLoading }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in self?.urlDidChange(view.url) }
            }
        ]
        installScripts()
    }

    func configure(shortsEnabled: Bool, savedIDs: [String]) {
        guard self.shortsEnabled != shortsEnabled || self.savedIDs != savedIDs else { return }
        self.shortsEnabled = shortsEnabled
        self.savedIDs = savedIDs
        installScripts()
        webView.evaluateJavaScript("window.iurub?.configure(\(configurationJSON));", completionHandler: nil)
        if !shortsEnabled, let url = webView.url, Self.isShortURL(url) {
            pause()
            home()
        }
    }

    private var configurationJSON: String {
        let data = try! JSONSerialization.data(withJSONObject: ["shortsEnabled": shortsEnabled, "savedIDs": savedIDs])
        return String(decoding: data, as: UTF8.self)
    }

    private func installScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        guard let sourceURL = Bundle.main.url(forResource: "YouTubeBridge", withExtension: "js"),
              let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            loadError = "I filtri di iurub non sono disponibili. Reinstalla l’app."
            return
        }
        let script = """
        (() => {
          const host = new URL(document.baseURI).hostname;
          if (!(host === 'youtube.com' || host.endsWith('.youtube.com'))) return;
          window.__iurubConfig = \(configurationJSON);
          \(source)
        })();
        """
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    func startIfNeeded() {
        guard !hasLoaded else { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--fixture") {
            loadFixture()
            return
        }
        #endif
        home()
    }

    func home() { load(URL(string: "https://m.youtube.com/")!) }

    func load(_ url: URL) {
        guard url.scheme == "https", let host = url.host, VideoLink.isYouTubeHost(host) else { return }
        if !shortsEnabled && Self.isShortURL(url) {
            notice = "Gli Shorts sono disattivati. Puoi abilitarli nelle impostazioni."
            return
        }
        hasLoaded = true
        currentVideo = VideoLink.parse(url.absoluteString).map { SavedVideo(link: $0) }
        loadError = nil
        lastURL = url
        webView.load(URLRequest(url: url))
    }

    func back() { if webView.canGoBack { webView.goBack() } }
    func reload() {
        loadError = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--fixture") { loadFixture(); return }
        #endif
        if webView.url == nil { load(lastURL) } else { webView.reload() }
    }
    func pause() {
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.evaluateJavaScript("window.iurub?.pause();", completionHandler: nil)
    }

    func saveCurrent() {
        let requestedURL = webView.url
        webView.evaluateJavaScript("window.iurub?.currentVideo();") { [weak self] value, _ in
            guard let self, self.webView.url == requestedURL else { return }
            if let body = value as? [String: Any], let video = self.decodeVideo(body) {
                self.onSave?(video)
            } else if let video = self.currentVideo {
                self.onSave?(video)
            }
        }
    }

    private func urlDidChange(_ url: URL?) {
        guard let url else { currentVideo = nil; return }
        if !shortsEnabled && Self.isShortURL(url) { home(); return }
        if let link = VideoLink.parse(url.absoluteString) {
            if currentVideo?.id != link.id { currentVideo = SavedVideo(link: link) }
        } else { currentVideo = nil }
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              VideoLink.isYouTubeHost(message.frameInfo.securityOrigin.host),
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "save":
            guard let raw = body["video"] as? [String: Any], let video = decodeVideo(raw) else { return }
            guard shortsEnabled || !video.isShort else {
                notice = "Abilita gli Shorts nelle impostazioni per salvare questo video."
                return
            }
            onSave?(video)
        case "current":
            if let raw = body["video"] as? [String: Any], let video = decodeVideo(raw),
               VideoLink.parse(webView.url?.absoluteString ?? "")?.id == video.id {
                currentVideo = video
            } else if VideoLink.parse(webView.url?.absoluteString ?? "") == nil {
                currentVideo = nil
            }
        case "blockedShort": notice = "Gli Shorts sono disattivati. Puoi abilitarli nelle impostazioni."
        default: break
        }
    }

    private func decodeVideo(_ body: [String: Any]) -> SavedVideo? {
        guard let rawURL = body["url"] as? String, let link = VideoLink.parse(rawURL),
              let id = body["id"] as? String, id == link.id else { return nil }
        return SavedVideo(link: link, title: body["title"] as? String ?? "", channel: body["channel"] as? String ?? "")
    }

    static func isShortURL(_ url: URL) -> Bool {
        guard let host = url.host, VideoLink.isYouTubeHost(host) else { return false }
        return url.path == "/shorts" || url.path.hasPrefix("/shorts/")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        // Third-party frames are used by the original YouTube player and ads.
        guard navigationAction.targetFrame?.isMainFrame != false else { decisionHandler(.allow); return }
        if !shortsEnabled && Self.isShortURL(url) {
            notice = "Gli Shorts sono disattivati. Puoi abilitarli nelle impostazioni."
            decisionHandler(.cancel); return
        }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        let host = url.host?.lowercased() ?? ""
        if url.scheme == "https" && (VideoLink.isYouTubeHost(host) || host == "accounts.google.com" || host == "consent.google.com") {
            decisionHandler(.allow); return
        }
        // Do not launch custom schemes or other apps automatically.
        if ["https", "http"].contains(url.scheme ?? "") { externalURL = url }
        else if navigationAction.navigationType == .linkActivated { notice = "Questo collegamento non può essere aperto in iurub." }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadError = nil
        urlDidChange(webView.url)
        webView.evaluateJavaScript("window.iurub?.configure(\(configurationJSON));", completionHandler: nil)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handle(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handle(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadError = "La pagina è stata interrotta. Tocca Riprova per riaprirla."
    }
    private func handle(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        isLoading = false
        loadError = "YouTube non è raggiungibile. Controlla la connessione e riprova."
    }

    #if DEBUG
    private func loadFixture() {
        guard let url = Bundle.main.url(forResource: "YouTubeFixture", withExtension: "html"),
              let html = try? String(contentsOf: url, encoding: .utf8) else { return }
        hasLoaded = true
        webView.loadHTMLString(html, baseURL: URL(string: "https://m.youtube.com/"))
    }
    #endif
}

private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: BrowserSession?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { owner?.receive(message) }
    }
}

#if os(iOS)
struct YouTubeWebView: UIViewRepresentable {
    let session: BrowserSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#else
struct YouTubeWebView: NSViewRepresentable {
    let session: BrowserSession
    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
