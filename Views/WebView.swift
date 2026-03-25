import SwiftUI
@preconcurrency import WebKit
import Combine

// MARK: - Navigation Action
enum WebNavigationAction {
    case loadURL(URL)
    case goBack
    case goForward
    case reload
}

// MARK: - WebView Store
@MainActor
final class WebViewStore: ObservableObject {
    enum WebViewMode: Equatable {
        case regular
        case regularProxy
        case privateMode
        case privateProxy
    }

    static let sharedProcessPool = WKProcessPool()
    static let sharedPrivateDataStore = WKWebsiteDataStore.nonPersistent()

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var estimatedProgress: Double = 0
    @Published var pageTitle = "Yeni Sekme"
    @Published var isSecure = true
    @Published var currentURLString = "https://www.google.com"
    @Published var isTopBarVisible = true
    @Published var isAddressBarFocused = false
    @Published var webViewID = UUID()
    @Published var transientMessage: String?

    let homeURL = URL(string: "https://www.google.com")!

    private(set) var webView: WKWebView!
    private var coordinator: WebViewCoordinator!
    private var refreshControl: UIRefreshControl?

    weak var adBlockEngine: AdBlockEngine?
    weak var tabManager: TabManager?
    weak var extensionManager: ExtensionManager?
    weak var proxyManager: ProxyManager?

    private var isNavigatingProgrammatically = false
    private var lastSnapshotTime: TimeInterval = 0
    private let snapshotMinInterval: TimeInterval = 5.0
    private let topChromeInset: CGFloat = 124
    private let bottomChromeInset: CGFloat = 112
    private let hideThreshold: CGFloat = 60
    private let revealHysteresis: CGFloat = 20
    private var lastObservedScrollOffset: CGFloat = 0
    private var pendingScrollRestore: CGPoint?
    private var currentMode: WebViewMode = .regular
    private var webViewCancellables = Set<AnyCancellable>()
    private var globalCancellables = Set<AnyCancellable>()

    init() {
        coordinator = WebViewCoordinator(store: self)
        webView = buildWebView(for: nil)
        bindWebViewObservers()
        observeAdBlockUpdates()
    }

    var currentScrollPosition: CGPoint {
        webView.scrollView.contentOffset
    }

    func applyProxyConfiguration(reload: Bool = false) {
        let activeTab = tabManager?.activeTab
        recreateWebViewIfNeeded(
            for: activeTab,
            targetURL: reload ? (webView.url ?? activeTab?.url ?? homeURL) : nil,
            restoringScrollPosition: reload ? nil : activeTab?.scrollPosition,
            force: true
        )
    }

    func activate(tab: BrowserTab) {
        AudioSessionManager.shared.configureForBrowserPlayback()
        recreateWebViewIfNeeded(
            for: tab,
            targetURL: tab.url,
            restoringScrollPosition: tab.scrollPosition
        )
    }

    func applyLatestAdBlockRules(reload: Bool) {
        injectScripts()
        guard reload, webView.url != nil else { return }
        webView.reload()
    }

    func compileAdBlockRules(completion: @escaping () -> Void) {
        adBlockEngine?.compileRules { [weak self] in
            Task { [weak self] in
                await MainActor.run {
                    self?.injectScripts()
                    completion()
                }
            }
        }
    }

    func injectScripts() {
        let contentController = webView.configuration.userContentController
        contentController.removeAllUserScripts()
        contentController.removeAllContentRuleLists()

        let backgroundProtectionScript = WKUserScript(
            source: Self.backgroundPlaybackProtectionScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(backgroundProtectionScript)

        let drmFallbackScript = WKUserScript(
            source: Self.drmFallbackScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        contentController.addUserScript(drmFallbackScript)

        if let engine = adBlockEngine {
            engine.applyRules(to: contentController)
        }

        if let extManager = extensionManager {
            let currentURL = webView.url ?? homeURL
            for script in extManager.activeUserScripts(for: currentURL) {
                contentController.addUserScript(script)
            }
        }
    }

    func showTopBar() {
        guard !isTopBarVisible else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isTopBarVisible = true
        }
    }

    func setAddressBarFocused(_ focused: Bool) {
        isAddressBarFocused = focused
        if focused {
            showTopBar()
        }
    }

    func handleScroll(offsetY: CGFloat, isInteracting: Bool) {
        let revealThreshold = -webView.scrollView.adjustedContentInset.top + 12
        let offsetFromTop = offsetY - revealThreshold
        let delta = offsetY - lastObservedScrollOffset

        defer {
            lastObservedScrollOffset = offsetY
        }

        guard !isAddressBarFocused else {
            showTopBar()
            return
        }

        guard isInteracting else {
            if offsetFromTop <= revealHysteresis {
                showTopBar()
            }
            return
        }

        if offsetFromTop <= revealHysteresis {
            showTopBar()
            return
        }

        if offsetFromTop > hideThreshold, delta > 0, isTopBarVisible {
            withAnimation(.easeInOut(duration: 0.2)) {
                isTopBarVisible = false
            }
        } else if delta < -revealHysteresis {
            showTopBar()
        }
    }

    func loadURL(_ url: URL, restoringScrollPosition: CGPoint? = nil) {
        showTopBar()
        if let tab = tabManager?.activeTab {
            recreateWebViewIfNeeded(for: tab, targetURL: url, restoringScrollPosition: restoringScrollPosition)
        } else {
            performLoad(url, restoringScrollPosition: restoringScrollPosition)
        }
    }

    func loadURLString(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.contains(".") && !trimmed.contains(" ") {
            var urlString = trimmed
            if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
                urlString = "https://" + urlString
            }
            if let url = URL(string: urlString) {
                loadURL(url)
                return
            }
        }

        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        if let searchURL = URL(string: "https://www.google.com/search?q=\(query)") {
            loadURL(searchURL)
        }
    }

    func goBack() {
        guard webView.canGoBack else { return }
        showTopBar()
        AudioSessionManager.shared.configureForBrowserPlayback()
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        showTopBar()
        AudioSessionManager.shared.configureForBrowserPlayback()
        webView.goForward()
    }

    func reload() {
        showTopBar()
        AudioSessionManager.shared.configureForBrowserPlayback()
        webView.reload()
    }

    func stopLoading() {
        webView.stopLoading()
        isLoading = false
    }

    func goHome() {
        loadURL(homeURL)
    }

    func handleCommittedNavigation(url: URL?) {
        updateNavigationState()
        guard let url else { return }
        currentURLString = url.absoluteString
        isSecure = url.scheme?.lowercased() == "https"
        updateNowPlayingMetadata()
        tabManager?.updateActiveTab(
            url: url,
            isSecure: isSecure,
            scrollPosition: currentScrollPosition,
            isLoading: isLoading
        )
    }

    func handleWebContentProcessTermination() {
        let recoveryURL = tabManager?.activeTab.url ?? webView.url ?? homeURL
        pageTitle = "Yeniden yukleniyor..."
        currentURLString = recoveryURL.absoluteString
        isSecure = recoveryURL.scheme?.lowercased() == "https"
        pendingScrollRestore = tabManager?.activeTab.scrollPosition
        tabManager?.updateActiveTab(
            title: pageTitle,
            url: recoveryURL,
            isSecure: isSecure,
            isLoading: true
        )
        webView.load(URLRequest(url: recoveryURL))
    }

    func updateNavigationState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    func handlePageFinished() {
        isLoading = false
        refreshControl?.endRefreshing()
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        pageTitle = webView.title ?? "Sayfa"

        if let currentURL = webView.url {
            currentURLString = currentURL.absoluteString
            isSecure = currentURL.scheme == "https"
            tabManager?.updateActiveTab(
                title: webView.title,
                url: currentURL,
                isSecure: currentURL.scheme == "https",
                scrollPosition: currentScrollPosition,
                isLoading: false
            )
        }

        restorePendingScrollPositionIfNeeded()
        captureSnapshot(force: false)

        webView.evaluateJavaScript("""
        if (window.__cyberAdBlockInjected) { window.__cyberAdBlockInjected = false; }
        if (window.__cyberAdBlockInjectedV2) { window.__cyberAdBlockInjectedV2 = false; }
        if (window.__cyberTRv2) { window.__cyberTRv2 = false; }
        if (window.__cyberGenericVideoAdAutomation) { window.__cyberGenericVideoAdAutomation = false; }
        if (window.__cyberYTv5) { window.__cyberYTv5 = false; }
        if (window.__cyberYTStyleInjected) { window.__cyberYTStyleInjected = false; }
        """) { _, _ in }

        if let engine = adBlockEngine, engine.isEnabled {
            webView.evaluateJavaScript(AdBlockEngine.optimizedCosmeticFilterScript) { _, _ in }
            webView.evaluateJavaScript(AdBlockEngine.turkishNewsCosmeticScript) { _, _ in }
            webView.evaluateJavaScript(AdBlockEngine.turkishStreamingAdBlockScript) { _, _ in }
            webView.evaluateJavaScript(AdBlockEngine.genericVideoAdAutomationScript) { _, _ in }
            webView.evaluateJavaScript(AdBlockEngine.youtubeAdStyleScript) { _, _ in }
            webView.evaluateJavaScript(AdBlockEngine.youtubeAdSkipScriptV3) { _, _ in }
        }

        updateNowPlayingMetadata()
        isNavigatingProgrammatically = false
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            captureSnapshot(force: true)
        case .active:
            AudioSessionManager.shared.configureForBrowserPlayback()
            updateNowPlayingMetadata()
        default:
            break
        }
    }

    func showTransientMessage(_ message: String) {
        transientMessage = message
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if self?.transientMessage == message {
                    self?.transientMessage = nil
                }
            }
        }
    }

    private func observeAdBlockUpdates() {
        NotificationCenter.default.publisher(for: .easyListDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyLatestAdBlockRules(reload: true)
            }
            .store(in: &globalCancellables)
    }

    private func recreateWebViewIfNeeded(
        for tab: BrowserTab?,
        targetURL: URL?,
        restoringScrollPosition: CGPoint?,
        force: Bool = false
    ) {
        let desiredMode = mode(for: tab)
        guard force || desiredMode != currentMode else {
            if let targetURL {
                performLoad(targetURL, restoringScrollPosition: restoringScrollPosition)
            } else if let restoringScrollPosition {
                pendingScrollRestore = restoringScrollPosition
                restorePendingScrollPositionIfNeeded()
            }
            return
        }

        let nextWebView = buildWebView(for: tab)
        webView = nextWebView
        currentMode = desiredMode
        webViewID = UUID()
        bindWebViewObservers()
        injectScripts()

        if let targetURL {
            performLoad(targetURL, restoringScrollPosition: restoringScrollPosition)
        }
    }

    private func performLoad(_ url: URL, restoringScrollPosition: CGPoint?) {
        isNavigatingProgrammatically = true
        pendingScrollRestore = restoringScrollPosition
        currentURLString = url.absoluteString
        AudioSessionManager.shared.configureForBrowserPlayback()
        webView.load(URLRequest(url: url))
    }

    private func mode(for tab: BrowserTab?) -> WebViewMode {
        let usesProxy = proxyManager?.selectedProtocol != .direct
        let isPrivate = tab?.isPrivate == true

        switch (isPrivate, usesProxy) {
        case (false, false):
            return .regular
        case (false, true):
            return .regularProxy
        case (true, false):
            return .privateMode
        case (true, true):
            return .privateProxy
        }
    }

    private func buildWebView(for tab: BrowserTab?) -> WKWebView {
        let configuration = buildConfiguration(for: tab)
        let nextWebView = WKWebView(frame: .zero, configuration: configuration)
        nextWebView.navigationDelegate = coordinator
        nextWebView.uiDelegate = coordinator
        nextWebView.allowsBackForwardNavigationGestures = true
        nextWebView.allowsLinkPreview = false
        nextWebView.isOpaque = false
        nextWebView.backgroundColor = .black
        nextWebView.scrollView.backgroundColor = .black
        nextWebView.scrollView.delegate = coordinator
        nextWebView.scrollView.contentInsetAdjustmentBehavior = .never
        nextWebView.scrollView.keyboardDismissMode = .interactive
        nextWebView.customUserAgent = nil

        let refresh = UIRefreshControl()
        refresh.addTarget(coordinator, action: #selector(WebViewCoordinator.handlePullToRefresh(_:)), for: .valueChanged)
        nextWebView.scrollView.refreshControl = refresh
        refreshControl = refresh

        applyChromeInsets(to: nextWebView)
        AudioSessionManager.shared.attach(webView: nextWebView)
        currentMode = mode(for: tab)
        return nextWebView
    }

    private func buildConfiguration(for tab: BrowserTab?) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = Self.sharedProcessPool
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile

        let pagePreferences = WKWebpagePreferences()
        pagePreferences.preferredContentMode = .mobile
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences

        let contentController = WKUserContentController()
        contentController.add(coordinator, name: "adBlocked")
        contentController.add(coordinator, name: "extensionAction")
        contentController.add(coordinator, name: "mediaNotice")
        configuration.userContentController = contentController
        configuration.websiteDataStore = resolvedDataStore(for: tab)
        return configuration
    }

    private func resolvedDataStore(for tab: BrowserTab?) -> WKWebsiteDataStore {
        if let proxyManager, proxyManager.selectedProtocol != .direct {
            return proxyManager.createProxyDataStore()
        }

        if tab?.isPrivate == true {
            return Self.sharedPrivateDataStore
        }

        return .default()
    }

    private func bindWebViewObservers() {
        webViewCancellables.removeAll()

        webView.publisher(for: \.url, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                guard let self, let url else { return }
                self.currentURLString = url.absoluteString
                self.isSecure = url.scheme?.lowercased() == "https"
                self.tabManager?.updateActiveTab(url: url, isSecure: self.isSecure)
                self.updateNowPlayingMetadata()
            }
            .store(in: &webViewCancellables)

        webView.publisher(for: \.canGoBack, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canGoBack = value
            }
            .store(in: &webViewCancellables)

        webView.publisher(for: \.canGoForward, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canGoForward = value
            }
            .store(in: &webViewCancellables)

        webView.publisher(for: \.isLoading, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.isLoading = value
                if !value {
                    self.refreshControl?.endRefreshing()
                }
                self.tabManager?.updateActiveTab(isLoading: value)
                self.updateNowPlayingMetadata()
            }
            .store(in: &webViewCancellables)

        webView.publisher(for: \.estimatedProgress, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.estimatedProgress = value
            }
            .store(in: &webViewCancellables)

        webView.publisher(for: \.title, options: [.new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, let value, !value.isEmpty else { return }
                self.pageTitle = value
                self.tabManager?.updateActiveTab(title: value)
                self.updateNowPlayingMetadata()
            }
            .store(in: &webViewCancellables)
    }

    private func applyChromeInsets(to webView: WKWebView) {
        let insets = UIEdgeInsets(top: topChromeInset, left: 0, bottom: bottomChromeInset, right: 0)
        webView.scrollView.contentInset = insets
        webView.scrollView.scrollIndicatorInsets = insets
        webView.scrollView.verticalScrollIndicatorInsets = insets
    }

    private func restorePendingScrollPositionIfNeeded() {
        guard let targetOffset = pendingScrollRestore else { return }
        pendingScrollRestore = nil

        DispatchQueue.main.async { [weak self] in
            self?.webView.scrollView.setContentOffset(targetOffset, animated: false)
        }
    }

    private func captureSnapshot(force: Bool) {
        let now = Date().timeIntervalSince1970
        guard force || now - lastSnapshotTime > snapshotMinInterval else { return }
        lastSnapshotTime = now

        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.afterScreenUpdates = false

        webView.takeSnapshot(with: snapshotConfig) { [weak self] image, _ in
            guard let self, let image else { return }
            let thumbSize = CGSize(width: 200, height: 300)
            UIGraphicsBeginImageContextWithOptions(thumbSize, true, 1.0)
            image.draw(in: CGRect(origin: .zero, size: thumbSize))
            let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            Task { [weak self] in
                await MainActor.run {
                    self?.tabManager?.updateActiveTab(snapshot: thumbnail)
                }
            }
        }
    }

    private func updateNowPlayingMetadata() {
        AudioSessionManager.shared.updateNowPlaying(
            title: pageTitle,
            url: webView.url ?? URL(string: currentURLString),
            isPlaying: !isLoading
        )
    }

    fileprivate func handleMediaNotice(_ notice: String) {
        showTransientMessage(notice)
    }

    static let backgroundPlaybackProtectionScript = """
    (function() {
        if (window.__cyberBackgroundPlaybackPatched) return;
        window.__cyberBackgroundPlaybackPatched = true;
        window.__cyberbrowser_bg_play = false;
        window.__cyberbrowser_allow_pause = false;

        document.addEventListener('visibilitychange', function() {
            window.__cyberbrowser_bg_play = document.hidden;
        }, true);

        var originalPause = HTMLMediaElement.prototype.pause;
        HTMLMediaElement.prototype.pause = function() {
            if (window.__cyberbrowser_bg_play && !window.__cyberbrowser_allow_pause) {
                return Promise.resolve();
            }
            window.__cyberbrowser_allow_pause = false;
            return originalPause.apply(this, arguments);
        };
    })();
    """

    static let drmFallbackScript = """
    (function() {
        if (window.__cyberDRMFallback) return;
        window.__cyberDRMFallback = true;

        if (!window.MediaSource) {
            try {
                window.webkit.messageHandlers.mediaNotice.postMessage(
                    'Bu site DRM korumali icerik kullaniyor. Bazi videolar oynayamayabilir.'
                );
            } catch (e) {}
        }

        if (navigator.requestMediaKeySystemAccess) {
            var originalRequest = navigator.requestMediaKeySystemAccess.bind(navigator);
            navigator.requestMediaKeySystemAccess = function(keySystem, configs) {
                return originalRequest(keySystem, configs).catch(function(error) {
                    try {
                        window.webkit.messageHandlers.mediaNotice.postMessage(
                            'Bu site DRM korumali icerik kullaniyor. Bazi videolar oynanamayabilir.'
                        );
                    } catch (e) {}
                    throw error;
                });
            };
        }
    })();
    """
}

// MARK: - WebView Coordinator
@MainActor
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
    private weak var store: WebViewStore?
    private let mediaExtensions: Set<String> = [
        ".m3u8", ".mp4", ".m4v", ".webm", ".mpd", ".ts", ".mov", ".mkv", ".m4a", ".aac", ".mp3"
    ]

    init(store: WebViewStore) {
        self.store = store
    }

    @objc func handlePullToRefresh(_ sender: UIRefreshControl) {
        store?.reload()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        store?.handleScroll(
            offsetY: scrollView.contentOffset.y,
            isInteracting: scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        )
    }

    private func isLikelyMediaRequest(_ url: URL) -> Bool {
        let absolute = url.absoluteString.lowercased()
        let path = url.path.lowercased()

        if mediaExtensions.contains(where: { path.hasSuffix($0) || absolute.contains($0) }) {
            return true
        }

        return absolute.contains("mime=video") ||
            absolute.contains("mime=audio") ||
            absolute.contains("playlist") ||
            absolute.contains("manifest") ||
            absolute.contains("videoplayback")
    }

    private func isProtectedVideoRequest(_ url: URL) -> Bool {
        if isLikelyMediaRequest(url) {
            return true
        }

        guard let engine = store?.adBlockEngine else { return false }
        return engine.isProtectedVideoURL(url)
    }

    private func blockAndCount(_ url: URL, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        store?.adBlockEngine?.handleBlockedAd(count: 1, domain: url.host ?? "")
        store?.tabManager?.incrementBlockedAds()
        decisionHandler(.cancel)
    }

    // MARK: - WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "adBlocked":
            if let body = message.body as? [String: Any] {
                let count = body["count"] as? Int ?? 1
                let urlString = body["url"] as? String ?? ""
                store?.adBlockEngine?.handleBlockedAd(count: count, domain: urlString)
                store?.tabManager?.incrementBlockedAds()
            }

        case "mediaNotice":
            if let notice = message.body as? String {
                store?.handleMediaNotice(notice)
            }

        case "extensionAction":
            break

        default:
            break
        }
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        store?.showTopBar()
        store?.isLoading = true
        store?.updateNavigationState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        store?.handleCommittedNavigation(url: webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        store?.handlePageFinished()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        store?.isLoading = false
        store?.webView.scrollView.refreshControl?.endRefreshing()

        let nsError = error as NSError
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                webView.reload()
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        store?.isLoading = false
        store?.webView.scrollView.refreshControl?.endRefreshing()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        store?.handleWebContentProcessTermination()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if isProtectedVideoRequest(url) {
            decisionHandler(.allow)
            return
        }

        if let engine = store?.adBlockEngine, engine.isVideoAdEndpoint(url) {
            blockAndCount(url, decisionHandler: decisionHandler)
            return
        }

        if let engine = store?.adBlockEngine, engine.shouldBypassBlocking(for: url) {
            decisionHandler(.allow)
            return
        }

        if let engine = store?.adBlockEngine,
           engine.isEnabled,
           engine.shouldBlockURL(url, mainDocumentURL: webView.url) {
            blockAndCount(url, decisionHandler: decisionHandler)
            return
        }

        if let host = url.host?.lowercased() {
            let gamblingPatterns = ["bet", "casino", "bahis", "slot", "jackpot", "spin", "bonus"]
            if let currentHost = webView.url?.host?.lowercased(),
               currentHost != host,
               gamblingPatterns.contains(where: { host.contains($0) }) {
                blockAndCount(url, decisionHandler: decisionHandler)
                return
            }
        }

        if navigationAction.targetFrame == nil {
            if let host = url.host?.lowercased() {
                let gamblingPatterns = ["bet", "casino", "bahis", "slot", "jackpot", "spin", "bonus", "poker"]
                if gamblingPatterns.contains(where: { host.contains($0) }) {
                    decisionHandler(.cancel)
                    return
                }
            }
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void
    ) {
        let contentType = navigationResponse.response.mimeType ?? ""
        if contentType.hasPrefix("video/") ||
            contentType.hasPrefix("audio/") ||
            contentType.contains("mpegurl") ||
            contentType.contains("mp2t") {
            decisionHandler(.allow)
            return
        }

        if let url = navigationResponse.response.url,
           let engine = store?.adBlockEngine,
           engine.isProtectedVideoURL(url) {
            decisionHandler(.allow)
            return
        }

        if let url = navigationResponse.response.url,
           let engine = store?.adBlockEngine,
           engine.isEnabled,
           !navigationResponse.isForMainFrame,
           engine.shouldBlockURL(url, mainDocumentURL: webView.url) {
            engine.handleBlockedAd(count: 1, domain: url.host ?? "")
            store?.tabManager?.incrementBlockedAds()
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url,
           let host = url.host?.lowercased() {
            let gamblingPatterns = ["bet", "casino", "bahis", "slot", "jackpot", "spin", "bonus", "poker"]
            if gamblingPatterns.contains(where: { host.contains($0) }) {
                return nil
            }
        }

        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

// MARK: - WebView SwiftUI Wrapper
@MainActor
struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var store: WebViewStore

    func makeUIView(context: Context) -> WKWebView {
        store.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
