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
    enum Role { case browse, player, signIn, sessionCheck }
    static let signInURL = URL(string: "https://m.youtube.com/signin?hl=it&next=%2Fplaylist%3Flist%3DWL")!
    // Google owns the sign-in pages. Only ordinary YouTube content can report
    // whether the current website session is signed in.
    private static let contentHosts = ["m.youtube.com", "www.youtube.com", "youtube.com"]
    #if DEBUG
    private static let isolatedStore = WKWebsiteDataStore.nonPersistent()
    #endif
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
    @Published private(set) var isPlaying = false
    @Published private(set) var videoEnded = false
    @Published private(set) var canGoBack = false
    @Published private(set) var currentVideo: SavedVideo?
    @Published private(set) var loadError: String?
    @Published var notice: String?
    @Published var windowHint: String?
    var onInlineWindow: (() -> Void)?
    private var manualPiPToken: UUID?
    private var manualPiPTask: Task<Void, Never>?
    @Published var externalURL: URL?
    var onPlaylistEdit: ((_ verifyAgainstPlaylist: Bool) -> Void)?
    @Published private(set) var youtubeSavedIDs: Set<String> = []
    @Published private(set) var youtubeRemovedIDs: Set<String> = []
    private(set) var webView: WKWebView!
    var onSave: ((SavedVideo) -> Void)?
    var onYouTubeMembership: ((SavedVideo, Bool) -> Void)?
    var onYouTubeSaved: ((SavedVideo) -> Void)?
    @Published private(set) var signedIn: Bool?
    @Published private(set) var checkingSignIn = false
    private enum CheckPurpose { case passive, error(String), retry }
    private var checkPurpose: CheckPurpose = .passive
    private var accountCheck: BrowserSession?
    private var checkDeadline: Task<Void, Never>?
    private var checkResult: ((Bool?) -> Void)?
    private var latestSignInNavigation: WKNavigation?
    #if DEBUG
    private var fixtureInterrupted = false
    #endif
    @Published private(set) var pageHost = ""
    var onSessionStatus: ((Bool) -> Void)?
    var onSignInRequest: (() -> Void)?
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
    private var departingPlayingID: String?
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
        makeWebView()
    }

    private func makeWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--fixture") || arguments.contains("--guest-live") {
            config.websiteDataStore = Self.isolatedStore
        }
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
                Task { @MainActor [weak self] in if self?.webView === view { self?.isLoading = view.isLoading } }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in if self?.webView === view { self?.canGoBack = view.canGoBack } }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor [weak self] in if self?.webView === view { self?.urlDidChange(view.url) } }
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
        let statusScript = """
        (() => {
          if (location.protocol !== 'https:' || !['m.youtube.com','www.youtube.com','youtube.com'].includes(location.hostname)) return;
          let last;
          const report = () => {
            if (location.pathname === '/signin' || location.pathname === '/signin/') return;
            const value = window.ytcfg?.get?.('LOGGED_IN');
            const header = document.querySelector('ytm-mobile-topbar-renderer, #masthead');
            const signed = typeof value === 'boolean' ? value :
              header?.querySelector('a[href*="/signin"],a[href*="accounts.google.com/ServiceLogin"]') ? false :
              location.pathname === '/playlist' && new URL(location.href).searchParams.get('list') === 'WL' &&
                document.querySelector('ytm-playlist-video-renderer,ytd-playlist-video-renderer') ? true : null;
            if (signed !== null && last !== signed) {
              last = signed;
              window.webkit.messageHandlers.iurub.postMessage({type:'youtubeSession', signed});
            }
          };
          let timer;
          const schedule = () => { if (!timer) timer = setTimeout(() => { timer = null; report(); }, 100); };
          report();
          new MutationObserver(schedule).observe(document.documentElement, {childList:true, subtree:true});
          window.addEventListener('pageshow', report);
          document.addEventListener('yt-navigate-finish', schedule);
        })()
        """
        controller.addUserScript(WKUserScript(source: statusScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        guard role == .browse || role == .player else { return }
        guard let sourceURL = Bundle.main.url(forResource: "YouTubeBridge", withExtension: "js"),
              let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            loadError = "I filtri di iurub non sono disponibili. Reinstalla l’app."
            return
        }
        let script = """
        (() => {
          const host = new URL(document.baseURI).hostname;
          if (!['m.youtube.com','www.youtube.com','youtube.com'].includes(host)) return;
          window.__iurubConfig = \(configurationJSON);
          \(source)
        })();
        """
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    // A Google redirect can fail after YouTube has already accepted the session.
    // Check Watch Later independently, without replacing the form or replaying a POST.
    func verifySignIn() {
        #if DEBUG
        // The live regression test must inject the failed return before the positive probe.
        if ProcessInfo.processInfo.arguments.contains("--live-login-return"), !fixtureInterrupted { return }
        #endif
        checkSignIn(.passive)
    }
    func retrySignIn() { checkSignIn(.retry) }

    func cancelSignInCheck() {
        checkDeadline?.cancel()
        checkDeadline = nil
        accountCheck?.checkResult = nil
        accountCheck?.webView.stopLoading()
        accountCheck = nil
        checkingSignIn = false
    }

    private func checkSignIn(_ purpose: CheckPurpose) {
        guard role == .signIn, signedIn != true else { return }
        if accountCheck != nil {
            switch purpose {
            case .passive: break
            case .error:
                if case .retry = checkPurpose { break }
                checkPurpose = purpose
            case .retry: checkPurpose = purpose
            }
            return
        }
        checkPurpose = purpose
        let probe = BrowserSession(startPage: .watchLater, role: .sessionCheck)
        accountCheck = probe
        checkingSignIn = true
        probe.checkResult = { [weak self, weak probe] signed in
            guard let self, let probe, self.accountCheck === probe else { return }
            let reason = self.checkPurpose
            self.cancelSignInCheck()
            if signed == true {
                self.loadError = nil
                self.signedIn = true
            } else {
                switch reason {
                case .passive: break // Never interrupt a form, passkey or verification code.
                case .error(let message): self.loadError = message
                case .retry: self.startSignIn() // Fresh GET in the same store, only if needed.
                }
            }
        }
        checkDeadline = Task { [weak probe] in
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            probe?.checkResult?(nil)
        }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--fixture") {
            if args.contains("--retry-login-return"), fixtureInterrupted {
                switch purpose {
                case .retry: probe.loadFixture()
                default: probe.checkResult?(nil) // Service temporarily unavailable until the manual retry.
                }
            } else { probe.loadFixture() }
            return
        }
        #endif
        let request = URLRequest(url: StartPage.watchLater.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        probe.webView.load(request)
    }

    func startSignIn() {
        guard role == .signIn else { return }
        cancelSignInCheck()
        signedIn = nil
        loadError = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--fixture") || ProcessInfo.processInfo.arguments.contains("--live-login-return") {
            let page = "<meta name='viewport' content='width=device-width,initial-scale=1'><button onclick=\"window.webkit.messageHandlers.iurub.postMessage({type:'fixtureSignIn'})\">Conferma account di prova</button>"
            hasLoaded = true
            latestSignInNavigation = webView.loadHTMLString(page, baseURL: URL(string: "https://accounts.google.com/"))
            return
        }
        #endif
        load(Self.signInURL)
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
        let navigation = webView.load(URLRequest(url: url, timeoutInterval: role == .signIn ? 25 : 60))
        if role == .signIn { latestSignInNavigation = navigation }
    }

    func loadVideo(_ video: SavedVideo, position: Double) {
        guard VideoLink.validID(video.id), shortsEnabled || !video.isShort else { return }
        cancelManualPiP()
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
        isPlaying = false
        videoEnded = false
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
        cancelManualPiP()
        departingPlayingID = nil
        captureProgress()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.evaluateJavaScript("window.iurub?.pause();", completionHandler: nil)
    }

    /// Discard the watch document and its back stack, but keep the shared YouTube session.
    func discardVideo() {
        observers.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "iurub")
        webView.stopLoading()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.closeAllMediaPresentations(completionHandler: {})
        navigationGeneration = UUID()
        playbackSession = UUID().uuidString
        activePlaybackID = nil
        pendingHistoryAdoption = nil
        resumeTarget = nil
        lastPlayback = nil
        departingPlayingID = nil
        currentVideo = nil
        mediaRate = nil
        isDetached = false
        isPlaying = false
        videoEnded = false
        isLoading = false
        canGoBack = false
        hasLoaded = false
        loadError = nil
        notice = nil
        makeWebView()
    }

    func setMiniPlayer(_ enabled: Bool) {
        webView.evaluateJavaScript("window.iurub?.setMiniPlayer(\(enabled));", completionHandler: nil)
    }

    func returnToWatchPage() {
        webView.evaluateJavaScript("window.iurub?.returnToWatchPage();", completionHandler: nil)
    }

    func prepareBackgroundPlayback(leavingApp: Bool = false) {
        guard role == .player, let id = currentVideo?.id, VideoLink.validID(id) else { return }
        if leavingApp && isPlaying { departingPlayingID = id }
        let wasPlaying = isPlaying || (leavingApp && departingPlayingID == id)
        webView.evaluateJavaScript("window.iurub?.enterBackground('\(id)', \(wasPlaying), \(leavingApp));", completionHandler: nil)
    }

    func endBackgroundHandoff() {
        departingPlayingID = nil
        webView.evaluateJavaScript("window.iurub?.foreground();", completionHandler: nil)
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
        guard manualPiPToken == nil else { return }
        let token = UUID(), generation = navigationGeneration
        manualPiPToken = token
        manualPiPTask = Task { [weak self] in
            guard let self else { return }
            let deadline = ContinuousClock.now + .seconds(12)
            let script = "window.iurub?.manualPiP('\(id)', '\(token.uuidString)');"
            while !Task.isCancelled, navigationGeneration == generation, currentVideo?.id == id {
                let state = try? await webView.evaluateJavaScript(script) as? String
                guard !Task.isCancelled, manualPiPToken == token, navigationGeneration == generation else { return }
                switch state {
                case "requested": return // The actual presentation change (or rejection) finishes the request.
                case "inline": finishManualPiP(inline: true); return
                default:
                    guard ContinuousClock.now < deadline else { finishManualPiP(inline: false); return }
                    try? await Task.sleep(for: .milliseconds(150))
                }
            }
        }
    }

    func cancelManualPiP() {
        manualPiPTask?.cancel()
        manualPiPTask = nil
        manualPiPToken = nil
    }

    private func finishManualPiP(inline: Bool) {
        cancelManualPiP()
        if inline { onInlineWindow?() }
        else { windowHint = "La finestra non è disponibile per questo video." }
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
        pageHost = url?.host?.lowercased() ?? ""
        if role == .sessionCheck { return }
        guard role != .signIn else {
            if let url, pageHost == "accounts.google.com", url.path.lowercased().contains("deniedsignin") || url.path.lowercased().contains("disallowed_useragent") {
                checkSignIn(.error("Google non ha consentito questo accesso. Puoi riprovare qui in iurub."))
            }
            return
        }
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
        guard message.webView === webView else { return }
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if role == .signIn, (args.contains("--fixture") || args.contains("--live-login-return")), message.frameInfo.isMainFrame,
           message.frameInfo.securityOrigin.host == "accounts.google.com",
           (message.body as? [String: String])?["type"] == "fixtureSignIn" {
            if args.contains("--live-login-return") {
                fixtureInterrupted = true
                handle(URLError(.networkConnectionLost))
                return
            }
            let failBefore = args.contains("--interrupt-before-login") && !fixtureInterrupted
            if !failBefore { UserDefaults(suiteName: "it.davidecarpini.iurub.uitests")!.set(true, forKey: "fixtureSignedIn") }
            if args.contains("--stalled-login-return") { return } // Google stays on the last page with no navigation callback.
            if failBefore || args.contains("--interrupt-login-return") || args.contains("--retry-login-return") {
                fixtureInterrupted = true
                handle(URLError(.networkConnectionLost))
            } else { loadFixture(page: .watchLater) }
            return
        }
        #endif
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              VideoLink.isYouTubeHost(message.frameInfo.securityOrigin.host),
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if type == "youtubeSession" {
            guard Self.contentHosts.contains(message.frameInfo.securityOrigin.host),
                  let page = webView.url, page.host?.lowercased() == message.frameInfo.securityOrigin.host,
                  page.scheme == "https", page.path != "/signin",
                  let signed = body["signed"] as? Bool else { return }
            if role == .sessionCheck { checkResult?(signed); return }
            if role == .signIn, signed { cancelSignInCheck(); loadError = nil }
            signedIn = signed
            onSessionStatus?(signed)
            return
        }
        guard role == .browse || role == .player else { return }
        switch type {
        case "requestSignIn": onSignInRequest?()
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
                if let token = manualPiPToken, body["token"] as? String == token.uuidString {
                    finishManualPiP(inline: true)
                }
            } else {
                mediaRate = (body["rate"] as? Double).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
                isDetached = body["detached"] as? Bool ?? false
                if isDetached { cancelManualPiP() }
                isPlaying = body["playing"] as? Bool ?? false
                videoEnded = body["ended"] as? Bool ?? false
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
            case "submitted": onPlaylistEdit?(true)
            case "saved", "removed", "undone": onPlaylistEdit?(false)
            case "alreadySaved", "alreadyRemoved", "failed": break  // YouTube presents the result.
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
        let googleSignIn = host == "accounts.google.com" && ["/servicelogin", "/v3/signin", "/signin", "/accountchooser"].contains { url.path.lowercased().hasPrefix($0) }
        let accountPage = url.scheme == "https" && (googleSignIn ||
            (Self.contentHosts.contains(host) && url.path == "/signin"))
        if role == .sessionCheck {
            // Follow first-party cookie-transfer redirects, but never submit a form
            // or leave the client. Reaching Google's identifier/challenge is a guest result.
            let trusted = Self.contentHosts.contains(host) || ["accounts.youtube.com", "accounts.google.com"].contains(host)
            let googleForm = host == "accounts.google.com" && ["/identifier", "/challenge/", "/accountchooser"].contains { url.path.lowercased().contains($0) }
            if url.scheme == "https", trusted, navigationAction.request.httpMethod == "GET", !googleForm {
                decisionHandler(.allow)
            } else { decisionHandler(.cancel); checkResult?(googleForm ? false : nil) }
            return
        }
        if role == .signIn {
            // Follow the site's own first-party redirects and preserve POST requests.
            let allowed = url.scheme == "https" && (VideoLink.isYouTubeHost(host) ||
                ["accounts.google.com", "consent.google.com", "www.google.com"].contains(host))
            decisionHandler(allowed ? .allow : .cancel)
            if !allowed { checkSignIn(.error("Non è stato possibile completare il ritorno da Google. Puoi riprovare qui in iurub.")) }
            return
        }
        if accountPage, signedIn != true, onSignInRequest != nil {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated { onSignInRequest?() }
            else if startPage == .watchLater && signedIn != true {
                signedIn = false
                onSessionStatus?(false)
            } else { onSignInRequest?() }
            return
        }
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
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if role == .signIn {
            latestSignInNavigation = navigation
            if case .error = checkPurpose { checkPurpose = .passive }
            loadError = nil
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if role == .signIn, navigation !== latestSignInNavigation { return }
        loadError = nil
        urlDidChange(webView.url)
        if (role == .browse || role == .player), Self.contentHosts.contains(pageHost) {
            webView.evaluateJavaScript("window.iurub?.configure(\(configurationJSON));", completionHandler: nil)
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard role != .signIn || navigation === latestSignInNavigation else { return }
        handle(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard role != .signIn || navigation === latestSignInNavigation else { return }
        handle(error)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if role == .sessionCheck { checkResult?(nil); return }
        let message = "La pagina è stata interrotta. Tocca Riprova per riaprirla."
        if role == .signIn { checkSignIn(.error(message)) }
        else { loadError = message }
    }
    private func handle(_ error: Error) {
        let ns = error as NSError
        guard !(ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled) else { return }
        if role == .sessionCheck { checkResult?(nil); return }
        if role == .signIn {
            // WebKit code 102 signals a navigation superseded by a policy decision.
            if ns.domain == "WebKitErrorDomain", ns.code == 102 { verifySignIn(); return }
            checkSignIn(.error("Non è stato possibile confermare l’accesso a YouTube. Riprova: controlleremo prima se sei già collegato."))
            return
        }
        isLoading = false
        loadError = "YouTube non è raggiungibile. Controlla la connessione e riprova."
    }

    #if DEBUG
    /// Geometry only. The opt-in simulator test can verify a visible title and
    /// independently scrolling comments without exporting account or comment text.
    func watchLayoutStatus() async -> String {
        let script = """
        (() => {
          const title = document.querySelector('meta[property="og:title"]')?.content || document.title.replace(/ - YouTube$/, '');
          const titleNode = [...document.querySelectorAll('ytm-slim-video-metadata-section-renderer *,h1')].find(n =>
            n.textContent.trim() === title && n.getBoundingClientRect().height > 0);
          const rect = titleNode?.getBoundingClientRect(), video = document.querySelector('#movie_player video')?.getBoundingClientRect();
          const panel = document.querySelector('ytm-engagement-panel .engagement-panel-comments-section');
          const scroller = panel?.querySelector('.engagement-panel-content-wrapper');
          const threads = Array.from(panel?.querySelectorAll('ytm-comment-thread-renderer') || []);
          const top = Math.max(scroller?.getBoundingClientRect().top || 0, video?.bottom || 0);
          const last = threads.reduce((last, n, i) => {
            const r = n.getBoundingClientRect();
            return r.height > 0 && r.bottom > top && r.top < innerHeight ? i : last;
          }, -1);
          return JSON.stringify({titleVisible:!!(rect && video && rect.top >= video.bottom - 2 && rect.bottom <= innerHeight),
            threads:threads.length,lastVisible:last});
        })()
        """
        return (try? await webView.evaluateJavaScript(script)) as? String ?? ""
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
        let prefs = UserDefaults(suiteName: "it.davidecarpini.iurub.uitests")!
        let fixtureSignedIn = !ProcessInfo.processInfo.arguments.contains("--guest-fixture") || prefs.bool(forKey: "fixtureSignedIn")
        guard let url = Bundle.main.url(forResource: "YouTubeFixture", withExtension: "html"),
              var html = try? String(contentsOf: url, encoding: .utf8) else { return }
        let ids = UserDefaults(suiteName: "it.davidecarpini.iurub.uitests")!.stringArray(forKey: "fixtureAccountIDs") ?? ["M7lc1UVf-VE"]
        let data = try! JSONSerialization.data(withJSONObject: ids)
        let noticeDelay = ProcessInfo.processInfo.arguments.contains("--late-playlist-toast") ? 3200 : 0
        html = html.replacingOccurrences(of: "/*IURUB_FIXTURE_ACCOUNT*/", with: "window.ytcfg = {get: key => key === 'LOGGED_IN' ? \(fixtureSignedIn) : undefined}; window.fixtureNoticeDelay = \(noticeDelay); window.fixtureAccountIDs = \(String(decoding: data, as: UTF8.self)); window.fixtureStartPage = '\(page.rawValue)';")
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
    var hidesWebAccessibility = false
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.accessibilityElementsHidden = hidesWebAccessibility
        uiView.accessibilityIdentifier = session.role == .player ? "youtube-player" : "youtube-" + session.startPage.rawValue
    }
}
#else
struct YouTubeWebView: NSViewRepresentable {
    let session: BrowserSession
    var hidesWebAccessibility = false
    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
