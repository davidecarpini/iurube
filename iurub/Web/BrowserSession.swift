import Combine
import Foundation
import SwiftUI
import WebKit
#if os(iOS)
import AVFAudio
#endif

@MainActor
final class BrowserSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    enum SaveDestination: String { case device, youtube }
    enum Role { case browse, player }
    enum StartPage: String, CaseIterable {
        case home, watchLater, subscriptions, history, you
        var url: URL {
            let path: String
            switch self {
            case .home: path = "/"
            case .watchLater: path = "/playlist?list=WL"
            case .subscriptions: path = "/feed/subscriptions"
            case .history: path = "/feed/history"
            case .you: path = "/feed/library"
            }
            return URL(string: "https://m.youtube.com" + path)!
        }
    }
    let role: Role
    let saveDestination: SaveDestination
    let startPage: StartPage
    @Published private(set) var isLoading = false
    @Published private(set) var mediaRate: Double?
    @Published private(set) var isDetached = false
    @Published private(set) var canGoBack = false
    @Published private(set) var currentVideo: SavedVideo?
    @Published private(set) var loadError: String?
    @Published var notice: String?
    @Published var externalURL: URL?
    let saveFeedback = PassthroughSubject<String, Never>()
    var onPlaylistEdit: (() -> Void)?
    @Published private(set) var youtubeSavedIDs: Set<String> = []
    @Published private(set) var youtubeRemovedIDs: Set<String> = []
    private(set) var webView: WKWebView!
    var onSave: ((SavedVideo) -> Void)?
    var onYouTubeMembership: ((SavedVideo, Bool) -> Void)?
    var onYouTubeSaved: ((SavedVideo) -> Void)?
    var onAccountContextChanged: (() -> Void)?
    var onOpenVideo: ((SavedVideo, Double?) -> Void)? {
        didSet {
            installScripts()
            webView.evaluateJavaScript("window.iurub?.configure(\(configurationJSON));", completionHandler: nil)
        }
    }
    var onPlayback: ((String, Double, Double, Bool) -> Void)?
    var onMetadata: ((SavedVideo) -> Void)?
    var onRestoreVideo: ((SavedVideo) -> PlaybackRecord)?
    private var resumeTarget: [String: Any]?
    private var lastPlayback: [String: Any]?
    private var lastBrowseURL: URL?
    private var activePlaybackID: String?
    private var playbackSession = UUID().uuidString
    private var navigationGeneration = UUID()
    private var pendingHistoryAdoption: [String: Any]?
    #if DEBUG
    private var pausedLiveProbe = false
    #endif

    private var shortsEnabled = false
    private var savedIDs: [String] = []
    private var removedIDs: [String] = []
    private var observers: [NSKeyValueObservation] = []
    private let messageProxy = MessageProxy()
    private var lastURL: URL = URL(string: "https://m.youtube.com/")!
    private(set) var hasLoaded = false

    init(startPage: StartPage = .home, saveDestination: SaveDestination = .device, role: Role = .browse) {
        self.role = role
        self.startPage = startPage
        self.saveDestination = saveDestination
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--fixture") { config.websiteDataStore = .nonPersistent() }
        #endif
        #if os(iOS)
        if role == .player {
            // Configure the category without taking audio focus until WebKit plays media.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        }
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

    func configure(shortsEnabled: Bool, savedIDs: [String], removedIDs: [String] = []) {
        guard self.shortsEnabled != shortsEnabled || self.savedIDs != savedIDs || self.removedIDs != removedIDs else { return }
        self.shortsEnabled = shortsEnabled
        self.savedIDs = savedIDs
        self.removedIDs = removedIDs
        if saveDestination == .youtube {
            youtubeSavedIDs = Set(savedIDs)
            youtubeRemovedIDs = Set(removedIDs)
        }
        installScripts()
        webView.evaluateJavaScript("window.iurub?.configure(\(configurationJSON));", completionHandler: nil)
        if !shortsEnabled, let url = webView.url, Self.isShortURL(url) {
            pause()
            if role == .browse { home() } else { webView.stopLoading() }
        }
    }

    func resetYouTubeMembership() {
        guard saveDestination == .youtube else { return }
        savedIDs = []
        removedIDs = []
        youtubeSavedIDs = []
        youtubeRemovedIDs = []
        installScripts()
        webView.evaluateJavaScript("window.iurub?.configure({resetMembership:true,savedIDs:[],removedIDs:[]});", completionHandler: nil)
    }

    private var configurationJSON: String {
        var config: [String: Any] = ["shortsEnabled": shortsEnabled, "savedIDs": savedIDs,
            "removedIDs": removedIDs,
            "saveDestination": saveDestination.rawValue, "startPage": startPage.rawValue,
            "routeVideoOpens": role == .browse && onOpenVideo != nil, "trackPlayback": role == .player,
            "playbackSession": playbackSession]
        if let resumeTarget { config["resume"] = resumeTarget }
        let data = try! JSONSerialization.data(withJSONObject: config)
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
        openStartPage()
    }

    func openStartPage() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--summary-live"), startPage == .watchLater {
            load(URL(string: "https://m.youtube.com/watch?v=jNQXAC9IVRw")!)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--fixture") {
            loadFixture()
            return
        }
        #endif
        load(startPage.url)
    }

    func home() { load(URL(string: "https://m.youtube.com/")!) }

    func openAccount() {
        onAccountContextChanged?()
        pause()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--fixture") {
            webView.evaluateJavaScript("window.fixtureNavigate?.('you');", completionHandler: nil)
            return
        }
        #endif
        load(StartPage.you.url)
    }

    func load(_ url: URL) {
        guard url.scheme == "https", let host = url.host, VideoLink.isYouTubeHost(host) else { return }
        if !shortsEnabled && Self.isShortURL(url) {
            notice = "Gli Shorts sono disattivati. Puoi abilitarli nelle impostazioni."
            return
        }
        if let link = VideoLink.parse(url.absoluteString), role == .browse, let onOpenVideo {
            onOpenVideo(SavedVideo(link: link), PlaybackRecord.startTime(in: url))
            return
        }
        navigationGeneration = UUID()
        pendingHistoryAdoption = nil
        hasLoaded = true
        if let link = VideoLink.parse(url.absoluteString) {
            if currentVideo?.id != link.id { currentVideo = SavedVideo(link: link) }
        } else { currentVideo = nil }
        loadError = nil
        lastURL = url
        isLoading = true
        webView.load(URLRequest(url: url))
    }

    func loadVideo(_ video: SavedVideo, position: Double) {
        guard VideoLink.validID(video.id), shortsEnabled || !video.isShort else { return }
        let seconds = position.isFinite ? min(PlaybackRecord.maximumTime, max(0, position)) : 0
        pendingHistoryAdoption = nil
        resumeTarget = ["id": video.id, "position": seconds]
        activePlaybackID = video.id
        #if DEBUG
        pausedLiveProbe = false
        #endif
        playbackSession = UUID().uuidString
        navigationGeneration = UUID()
        lastPlayback = nil
        mediaRate = nil
        isDetached = false
        currentVideo = video
        installScripts()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--fixture") {
            loadPlaybackFixture(video)
            return
        }
        #endif
        var components = URLComponents(url: video.url, resolvingAgainstBaseURL: false)!
        if seconds > 0 {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "t", value: "\(Int(seconds))s"))
            components.queryItems = items
        }
        if let url = components.url { load(url) }
    }

    func captureProgress(completion: (() -> Void)? = nil) {
        guard role == .player, hasLoaded else { completion?(); return }
        let generation = navigationGeneration
        webView.evaluateJavaScript("window.iurub?.playbackSnapshot();") { [weak self] value, _ in
            if let self, self.navigationGeneration == generation, let body = value as? [String: Any] {
                self.acceptPlayback(body)
            }
            completion?()
        }
    }

    private func acceptPlayback(_ body: [String: Any]) {
        guard role == .player, let id = body["id"] as? String, VideoLink.validID(id),
              id == activePlaybackID, body["session"] as? String == playbackSession,
              VideoLink.parse(webView.url?.absoluteString ?? "")?.id == id,
              let position = body["position"] as? Double, let duration = body["duration"] as? Double,
              PlaybackRecord.validTime(position), PlaybackRecord.validTime(duration), duration > 0 else { return }
        lastPlayback = body
        onPlayback?(id, position, duration, body["ended"] as? Bool ?? false)
        #if DEBUG
        // The opt-in live probe pauses only after the real site's media confirms
        // a restored position, so the short test video cannot end before relaunch.
        if !pausedLiveProbe, ProcessInfo.processInfo.arguments.contains("--playback-live"),
           ProcessInfo.processInfo.arguments.contains("--pause-restored-video") {
            pausedLiveProbe = true
            webView.pauseAllMediaPlayback(completionHandler: nil)
            webView.evaluateJavaScript("window.iurub?.pause();", completionHandler: nil)
        }
        #endif
    }

    // A WebKit history traversal must remain a traversal. Loading the destination
    // again would append it and make successive Back taps alternate between videos.
    private func prepareHistoryNavigation(to url: URL) {
        navigationGeneration = UUID()
        playbackSession = UUID().uuidString
        lastPlayback = nil
        pendingHistoryAdoption = nil
        if let link = VideoLink.parse(url.absoluteString) {
            let metadata = currentVideo?.id == link.id ? currentVideo! : SavedVideo(link: link)
            // Ignore stale t= parameters stored in history; resume the latest bookmark.
            let record = onRestoreVideo?(metadata) ?? PlaybackRecord(video: metadata, position: 0, duration: nil, completed: false, updatedAt: Date())
            activePlaybackID = link.id
            currentVideo = record.video
            resumeTarget = ["id": link.id, "position": record.position]
            pendingHistoryAdoption = ["id": link.id, "position": record.position, "session": playbackSession]
        } else {
            activePlaybackID = nil
            currentVideo = nil
            resumeTarget = nil
        }
        installScripts()
    }

    private func adoptHistoryDocumentIfReady() {
        guard let adoption = pendingHistoryAdoption,
              let id = adoption["id"] as? String,
              VideoLink.parse(webView.url?.absoluteString ?? "")?.id == id,
              let data = try? JSONSerialization.data(withJSONObject: adoption) else { return }
        let generation = navigationGeneration
        let json = String(decoding: data, as: UTF8.self)
        // A restored bfcache document still has its old immutable configuration.
        // The bridge adopts this generation only when its own URL matches the target.
        webView.evaluateJavaScript("window.iurub?.adoptPlayback(\(json));") { [weak self] value, _ in
            guard let self, self.navigationGeneration == generation else { return }
            if value as? Bool == true { self.pendingHistoryAdoption = nil }
        }
    }

    func back() {
        guard webView.canGoBack else { return }
        let generation = navigationGeneration
        captureProgress { [weak self] in
            guard let self, self.navigationGeneration == generation, self.webView.canGoBack else { return }
            self.webView.goBack()
        }
    }
    func reload() {
        loadError = nil
        if role == .player, let video = currentVideo {
            let generation = navigationGeneration
            captureProgress { [weak self] in
                guard let self, self.navigationGeneration == generation, self.currentVideo?.id == video.id else { return }
                let lastPosition = self.lastPlayback?["id"] as? String == video.id ? self.lastPlayback?["position"] as? Double : nil
                let position = lastPosition ?? (self.resumeTarget?["position"] as? Double) ?? 0
                self.loadVideo(video, position: position)
            }
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--fixture") {
            let page = StartPage.allCases.first { $0.url == webView.url } ?? startPage
            loadFixture(page: page)
            return
        }
        #endif
        if webView.url == nil { load(lastURL) } else { webView.reload() }
    }
    func pause() {
        captureProgress()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.evaluateJavaScript("window.iurub?.pause();", completionHandler: nil)
    }

    func prepareBackgroundPlayback() {
        guard role == .player, let id = currentVideo?.id, VideoLink.validID(id) else { return }
        webView.evaluateJavaScript("window.iurub?.enterBackground('\(id)');", completionHandler: nil)
    }

    /// An in-app tab switch must not pause the system PiP window.
    /// Check the live element in WebKit, since the app can become inactive during its transition.
    func pauseWhenHidden() {
        guard role == .player, currentVideo != nil else { pause(); return }
        let generation = navigationGeneration
        webView.evaluateJavaScript("window.iurub?.pauseWhenHidden();") { [weak self] handled, _ in
            guard let self, self.navigationGeneration == generation, handled as? Bool != true else { return }
            self.pause()
        }
    }

    func stepSpeed(_ direction: Int) {
        guard [-1, 1].contains(direction), let id = currentVideo?.id, VideoLink.validID(id) else { return }
        webView.evaluateJavaScript("window.iurub?.stepSpeed('\(id)', \(direction));") { [weak self] value, _ in
            guard let self, self.currentVideo?.id == id, value as? Bool != true else { return }
            self.notice = "Il player non può cambiare velocità in questo momento."
        }
    }

    func returnFromPictureInPicture() {
        guard isDetached, let id = currentVideo?.id else { return }
        webView.closeAllMediaPresentations { [weak self] in
            guard let self, self.currentVideo?.id == id else { return }
            self.isDetached = false
        }
    }

    func togglePictureInPicture() {
        guard let id = currentVideo?.id, VideoLink.validID(id) else { return }
        if isDetached {
            returnFromPictureInPicture()
            return
        }
        webView.evaluateJavaScript("window.iurub?.togglePiP('\(id)');") { [weak self] result, _ in
            guard let self, self.currentVideo?.id == id else { return }
            switch result as? String {
            case "requested": break
            case "playFirst": self.notice = "Avvia il video, poi tocca di nuovo Picture in Picture."
            case "notReady", nil: self.notice = "Il video si sta caricando. Avvialo e riprova."
            default: self.notice = "Picture in Picture non è disponibile per questo video o dispositivo."
            }
        }
    }

    func saveCurrent() {
        if saveDestination == .youtube {
            webView.evaluateJavaScript("window.iurub?.toggleCurrentToYouTube();", completionHandler: nil)
            return
        }
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
        if !shortsEnabled && Self.isShortURL(url) {
            if role == .browse { home() }
            return
        }
        if let link = VideoLink.parse(url.absoluteString) {
            if role == .browse, let onOpenVideo {
                currentVideo = nil
                onOpenVideo(SavedVideo(link: link), PlaybackRecord.startTime(in: url))
                // Fallback for site navigation that bypassed both link capture and
                // WKNavigationDelegate. Return the browsing tab to its prior page.
                if webView.canGoBack { webView.goBack() }
                else { webView.load(URLRequest(url: lastBrowseURL ?? startPage.url)) }
                return
            }
            if role == .player, activePlaybackID != link.id {
                let video = currentVideo?.id == link.id ? currentVideo! : SavedVideo(link: link)
                currentVideo = video
                onOpenVideo?(video, PlaybackRecord.startTime(in: url))
            } else if currentVideo?.id != link.id { currentVideo = SavedVideo(link: link) }
            adoptHistoryDocumentIfReady()
        } else {
            currentVideo = nil
            if role == .browse, let host = url.host, VideoLink.isYouTubeHost(host) { lastBrowseURL = url }
        }
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              VideoLink.isYouTubeHost(message.frameInfo.securityOrigin.host),
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "openVideo":
            guard role == .browse, let raw = body["video"] as? [String: Any], let video = decodeVideo(raw),
                  shortsEnabled || !video.isShort else { return }
            let seconds = body["startSeconds"] as? Double
            onOpenVideo?(video, seconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
        case "mediaControls", "pipFailed":
            guard role == .player, let id = body["id"] as? String, id == currentVideo?.id,
                  body["session"] as? String == playbackSession,
                  VideoLink.parse(webView.url?.absoluteString ?? "")?.id == id else { return }
            if type == "pipFailed" {
                notice = "Il player non ha aperto la finestra Picture in Picture. Riprova durante la riproduzione."
            } else {
                mediaRate = (body["rate"] as? Double).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                isDetached = body["detached"] as? Bool ?? false
            }
        case "playback": acceptPlayback(body)
        case "save":
            guard saveDestination == .device else { return }
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
                if role == .player { onMetadata?(video) }
            } else if VideoLink.parse(webView.url?.absoluteString ?? "") == nil {
                currentVideo = nil
            }
        case "blockedShort": notice = "Gli Shorts sono disattivati. Puoi abilitarli nelle impostazioni."
        case "youtubeMembership":
            guard saveDestination == .youtube,
                  let raw = body["video"] as? [String: Any], let video = decodeVideo(raw),
                  let saved = body["saved"] as? Bool else { return }
            onYouTubeMembership?(video, saved)
        case "youtubeAccountContextChanged":
            guard saveDestination == .youtube else { return }
            onAccountContextChanged?()
        case "youtubeSaveResult":
            guard saveDestination == .youtube else { return }
            let video = (body["video"] as? [String: Any]).flatMap(decodeVideo)
            if let video, let saved = body["saved"] as? Bool {
                onYouTubeMembership?(video, saved)
                if body["status"] as? String == "saved", saved {
                    // Only a newly confirmed account save starts a paid request.
                    // Reading an existing playlist or an unconfirmed click does not.
                    onYouTubeSaved?(video)
                }
            }
            switch body["status"] as? String {
            case "saved", "removed":
                onPlaylistEdit?()
                saveFeedback.send(body["status"] as? String == "saved" ? "Salvato" : "Rimosso")
            case "alreadySaved": saveFeedback.send("Salvato")
            case "alreadyRemoved": saveFeedback.send("Rimosso")
            case "submitted":
                onPlaylistEdit?()
                notice = "YouTube non ha confermato la modifica. Apri Salvati per controllare."
            case "choose": notice = "Seleziona Guarda più tardi nel menu YouTube."
            default: notice = "Apri il menu del video su YouTube e scegli Guarda più tardi. Se richiesto, accedi al tuo account."
            }
        case "youtubeRemoveResult":
            guard saveDestination == .youtube else { return }
            if body["status"] as? String == "manual" {
                notice = "Apri il menu ⋯ del video e scegli Rimuovi da Guarda più tardi."
            }
        #if DEBUG
        case "fixtureAccountSave", "fixtureAccountRemove":
            guard ProcessInfo.processInfo.arguments.contains("--fixture"), ProcessInfo.processInfo.arguments.contains("--ui-testing"),
                  let id = body["id"] as? String, VideoLink.validID(id) else { return }
            let defaults = UserDefaults(suiteName: "it.davidecarpini.iurub.uitests")!
            var ids = defaults.stringArray(forKey: "fixtureAccountIDs") ?? ["M7lc1UVf-VE"]
            if type == "fixtureAccountRemove" { ids.removeAll { $0 == id } }
            else if !ids.contains(id) { ids.append(id) }
            defaults.set(ids, forKey: "fixtureAccountIDs")
        #endif
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
        if role == .player, navigationAction.navigationType == .backForward,
           url.scheme == "https", VideoLink.isYouTubeHost(host) || host == "accounts.google.com" || host == "consent.google.com" {
            let generation = navigationGeneration
            // Read the outgoing playhead while its document is still active. After
            // adoption, late snapshots carry the old session and are rejected.
            captureProgress { [weak self] in
                guard let self, self.navigationGeneration == generation else {
                    decisionHandler(.cancel)
                    return
                }
                self.prepareHistoryNavigation(to: url)
                decisionHandler(.allow)
            }
            return
        }
        if let link = VideoLink.parse(url.absoluteString), let onOpenVideo,
           role == .browse || link.id != currentVideo?.id ||
            (navigationAction.navigationType == .linkActivated && PlaybackRecord.startTime(in: url) != nil) {
            decisionHandler(.cancel)
            onOpenVideo(SavedVideo(link: link), PlaybackRecord.startTime(in: url))
            return
        }
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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--watch-layout-probe"), role == .player {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.captureWatchLayout()
            }
        }
        #endif
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
    /// Structural diagnostics for the opt-in live layout test. No cookies, tokens,
    /// account identifiers, comment text or page HTML are exported.
    private func captureWatchLayout() {
        guard let url = webView.url, VideoLink.parse(url.absoluteString) != nil else { return }
        let script = """
        (() => {
          const shape = n => ({tag:n.tagName, cls:typeof n.className==='string'?n.className:'',
            shown:!!(n.getBoundingClientRect().width && n.getBoundingClientRect().height),
            rect:n.getBoundingClientRect().toJSON()});
          const ancestors = n => { const chain=[]; for(let i=0;n&&i<7;i++,n=n.parentElement) chain.push(shape(n)); return chain; };
          return JSON.stringify({
            path:location.pathname,
            regions:Array.from(document.querySelectorAll('*')).filter(n=>/watch|comment|related|recommend|secondary/i.test(n.tagName+' '+n.className)).slice(0,160).map(n=>({...shape(n),children:Array.from(n.children).map(shape)})),
            videoCards:Array.from(document.querySelectorAll('a[href*="/watch?v="]')).slice(0,10).map(ancestors)
          });
        })()
        """
        webView.evaluateJavaScript(script) { value, _ in
            guard let json = value as? String else { return }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("iurub-watch-layout.json")
            try? json.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func loadPlaybackFixture(_ video: SavedVideo) {
        guard let file = Bundle.main.url(forResource: "PlaybackFixture", withExtension: "html"),
              var html = try? String(contentsOf: file, encoding: .utf8) else { return }
        let titleData = try! JSONEncoder().encode(video.title)
        let title = String(decoding: titleData, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c")
        let ids = UserDefaults(suiteName: "it.davidecarpini.iurub.uitests")!.stringArray(forKey: "fixtureAccountIDs") ?? ["M7lc1UVf-VE"]
        let accountData = try! JSONSerialization.data(withJSONObject: ids)
        html = html.replacingOccurrences(of: "/*IURUB_PLAYBACK_FIXTURE*/", with: "window.fixtureVideoTitle = \(title); window.fixtureAccountIDs = \(String(decoding: accountData, as: UTF8.self));")
        if let clip = ProcessInfo.processInfo.environment["IURUB_TEST_CLIP"],
           let data = Data(base64Encoded: clip), data.count < 250_000 {
            // A real, local H.264 clip carried by the UI test runner, never by the release app.
            html = """
            <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
            <title>Prova controlli video - YouTube</title>
            <div id="movie_player"><video style="width:100%" playsinline preload="auto"
            src="data:video/mp4;base64,\(data.base64EncodedString())"></video></div>
            <button onclick="document.querySelector('video').play()">Riproduci la clip</button>
            <p id="clock">Secondi 0</p><p id="events">Media</p><p id="rate">Velocità effettiva 1</p>
            <script>
            const v=document.querySelector('video');
            const events = [], origin = Math.round(performance.timeOrigin);
            function recordEvent(kind) {
                events.push(kind+'@'+v.currentTime.toFixed(1));
                document.querySelector('#events').textContent='Media '+origin+' '+events.slice(-12).join(' ');
            }
            for(const kind of ['playing','pause','ended','seeking','loadedmetadata','emptied','error'])
                v.addEventListener(kind,()=>recordEvent(kind));
            document.addEventListener('visibilitychange',()=>recordEvent(document.visibilityState));
            v.ontimeupdate=()=>document.querySelector('#clock').textContent='Secondi '+Math.floor(v.currentTime);
            v.onratechange=()=>document.querySelector('#rate').textContent='Velocità effettiva '+v.playbackRate;
            </script>
            """
        }
        hasLoaded = true
        loadError = nil
        lastURL = video.url
        isLoading = true
        webView.loadHTMLString(html, baseURL: video.url)
    }

    private func loadFixture(page requestedPage: StartPage? = nil) {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--summary-fixture"), let onOpenVideo {
            hasLoaded = true
            onOpenVideo(SavedVideo(link: VideoLink(id: "jNQXAC9IVRw", isShort: false), title: "Imparare con piccoli esercizi"), nil)
            return
        }
        let page = requestedPage ?? startPage
        guard let url = Bundle.main.url(forResource: "YouTubeFixture", withExtension: "html"),
              var html = try? String(contentsOf: url, encoding: .utf8) else { return }
        let ids = UserDefaults(suiteName: "it.davidecarpini.iurub.uitests")!.stringArray(forKey: "fixtureAccountIDs") ?? ["M7lc1UVf-VE"]
        let data = try! JSONSerialization.data(withJSONObject: ids)
        html = html.replacingOccurrences(of: "/*IURUB_FIXTURE_ACCOUNT*/", with: "window.fixtureAccountIDs = \(String(decoding: data, as: UTF8.self)); window.fixtureStartPage = '\(page.rawValue)';")
        hasLoaded = true
        webView.loadHTMLString(html, baseURL: page.url)
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
