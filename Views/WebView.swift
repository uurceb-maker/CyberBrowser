import SwiftUI
import WebKit
import Combine

// MARK: - Navigation Action
enum WebNavigationAction {
    case loadURL(URL)
    case goBack
    case goForward
    case reload
}

// MARK: - WebView Store (Manages WKWebView lifecycle)
@MainActor
class WebViewStore: ObservableObject {
    static let sharedProcessPool = WKProcessPool()

    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var estimatedProgress: Double = 0
    @Published var pageTitle: String = "Yeni Sekme"
    @Published var isSecure: Bool = true
    @Published var currentURLString: String = "https://www.google.com"
    @Published var isTopBarVisible: Bool = true
    let homeURL = URL(string: "https://www.google.com")!
    
    // The WKWebView instance â€” created once, reused
    private(set) var webView: WKWebView!
    private var coordinator: WebViewCoordinator!
    private var refreshControl: UIRefreshControl?
    
    // Reference to managers (set from outside)
    weak var adBlockEngine: AdBlockEngine?
    weak var tabManager: TabManager?
    weak var extensionManager: ExtensionManager?
    weak var proxyManager: ProxyManager?
    
    private var isNavigatingProgrammatically = false
    
    // Snapshot throttling â€” only take snapshots every 5 seconds max
    private var lastSnapshotTime: TimeInterval = 0
    private let snapshotMinInterval: TimeInterval = 5.0
    private let topChromeInset: CGFloat = 124
    private let bottomChromeInset: CGFloat = 112
    private let chromeScrollThreshold: CGFloat = 14
    private var lastObservedScrollOffset: CGFloat = 0
    private var pendingScrollRestore: CGPoint?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.coordinator = WebViewCoordinator(store: self)
        self.webView = createWebView()
        bindWebViewObservers()
        observeAdBlockUpdates()
        
        // Listen for background EasyList download completion
        NotificationCenter.default.addObserver(
            forName: .adBlockRulesUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[WebView] ğŸ”„ EasyList downloaded â€” re-injecting rules")
            MainActor.assumeIsolated { [weak self] in
                self?.injectScripts()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = Self.sharedProcessPool
        
        // Media playback
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        // Content controller
        let contentController = WKUserContentController()
        contentController.add(coordinator, name: "adBlocked")
        contentController.add(coordinator, name: "extensionAction")
        config.userContentController = contentController
        if let pm = proxyManager, pm.selectedProtocol != .direct {
            config.websiteDataStore = pm.createProxyDataStore()
        } else {
            config.websiteDataStore = .default()
        }
        
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = coordinator
        wv.uiDelegate = coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsLinkPreview = false
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.delegate = coordinator
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.keyboardDismissMode = .onDrag
        
        // Use standard Safari iOS user agent â€” NO custom suffix
        // This prevents Google CAPTCHA/verification loops
        wv.customUserAgent = nil
        
        let refresh = UIRefreshControl()
        refresh.addTarget(coordinator, action: #selector(WebViewCoordinator.handlePullToRefresh(_:)), for: .valueChanged)
        wv.scrollView.refreshControl = refresh
        self.refreshControl = refresh
        applyChromeInsets(to: wv)
        
        return wv
    }

    private func bindWebViewObservers() {
        webView.publisher(for: \.url, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] url in
                guard let self, let url else { return }
                self.currentURLString = url.absoluteString
                self.isSecure = url.scheme?.lowercased() == "https"
                self.tabManager?.updateActiveTab(url: url, isSecure: self.isSecure)
            }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoBack, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canGoBack = value
            }
            .store(in: &cancellables)

        webView.publisher(for: \.canGoForward, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canGoForward = value
            }
            .store(in: &cancellables)

        webView.publisher(for: \.isLoading, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.isLoading = value
                if !value {
                    self.refreshControl?.endRefreshing()
                }
                self.tabManager?.updateActiveTab(isLoading: value)
            }
            .store(in: &cancellables)

        webView.publisher(for: \.estimatedProgress, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.estimatedProgress = value
            }
            .store(in: &cancellables)

        webView.publisher(for: \.title, options: [.new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, let value, !value.isEmpty else { return }
                self.pageTitle = value
                self.tabManager?.updateActiveTab(title: value)
            }
            .store(in: &cancellables)
    }

    private func observeAdBlockUpdates() {
        NotificationCenter.default.publisher(for: .easyListDidUpdate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                print("[WebView] EasyList updated - reloading active page")
                self.applyLatestAdBlockRules(reload: true)
            }
            .store(in: &cancellables)
    }

    private func applyChromeInsets(to webView: WKWebView) {
        let insets = UIEdgeInsets(top: topChromeInset, left: 0, bottom: bottomChromeInset, right: 0)
        webView.scrollView.contentInset = insets
        webView.scrollView.scrollIndicatorInsets = insets
        webView.scrollView.verticalScrollIndicatorInsets = insets
    }

    var currentScrollPosition: CGPoint {
        webView.scrollView.contentOffset
    }

    func applyProxyConfiguration(reload: Bool = false) {
        let config = webView.configuration
        if let pm = proxyManager, pm.selectedProtocol != .direct {
            config.websiteDataStore = pm.createProxyDataStore()
        } else {
            config.websiteDataStore = .default()
        }
        injectScripts()
        if reload {
            self.reload()
        }
    }

    func applyLatestAdBlockRules(reload: Bool) {
        injectScripts()
        guard reload, webView.url != nil else { return }
        webView.reload()
    }
    
    // MARK: - Inject Scripts & Rules
    func injectScripts() {
        let contentController = webView.configuration.userContentController
        contentController.removeAllUserScripts()
        contentController.removeAllContentRuleLists()
        
        // Native ad-block rules + cosmetic scripts (all handled by engine)
        if let engine = adBlockEngine {
            engine.applyRules(to: contentController)
        }
        
        // Extension scripts â€” only inject for main frame by default
        if let extManager = extensionManager {
            let currentURL = webView.url ?? URL(string: "https://www.google.com")!
            for script in extManager.activeUserScripts(for: currentURL) {
                contentController.addUserScript(script)
            }
        }
    }
    
    // MARK: - Compile Native Rules
    func compileAdBlockRules(completion: @escaping () -> Void) {
        adBlockEngine?.compileRules { [weak self] in
            MainActor.assumeIsolated { [weak self] in
                self?.injectScripts()
                completion()
            }
        }
    }

    func reconnectWithProxy() {
        applyProxyConfiguration(reload: true)
    }

    func showTopBar() {
        guard !isTopBarVisible else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
            isTopBarVisible = true
        }
    }

    func handleScroll(offsetY: CGFloat, isInteracting: Bool) {
        let revealThreshold = -webView.scrollView.adjustedContentInset.top + 12

        defer {
            lastObservedScrollOffset = offsetY
        }

        guard isInteracting else {
            if offsetY <= revealThreshold {
                showTopBar()
            }
            return
        }

        if offsetY <= revealThreshold {
            showTopBar()
            return
        }

        let delta = offsetY - lastObservedScrollOffset
        if delta > chromeScrollThreshold, isTopBarVisible {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                isTopBarVisible = false
            }
        } else if delta < -chromeScrollThreshold {
            showTopBar()
        }
    }
    
    // MARK: - Navigation Actions
    func loadURL(_ url: URL, restoringScrollPosition: CGPoint? = nil) {
        showTopBar()
        isNavigatingProgrammatically = true
        pendingScrollRestore = restoringScrollPosition
        currentURLString = url.absoluteString
        webView.load(URLRequest(url: url))
    }
    
    func loadURLString(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // Check if it's a URL
        if trimmed.contains(".") && !trimmed.contains(" ") {
            var urlStr = trimmed
            if !urlStr.hasPrefix("http://") && !urlStr.hasPrefix("https://") {
                urlStr = "https://" + urlStr
            }
            if let url = URL(string: urlStr) {
                loadURL(url)
                return
            }
        }
        
        // Treat as search query
        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        if let searchURL = URL(string: "https://www.google.com/search?q=\(query)") {
            loadURL(searchURL)
        }
    }
    
    @MainActor
    func goBack() {
        if webView.canGoBack {
            showTopBar()
            webView.goBack()
        }
    }
    
    @MainActor
    func goForward() {
        if webView.canGoForward {
            showTopBar()
            webView.goForward()
        }
    }
    
    @MainActor
    func reload() {
        showTopBar()
        webView.reload()
    }
    
    @MainActor
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

    private func restorePendingScrollPositionIfNeeded() {
        guard let targetOffset = pendingScrollRestore else { return }
        pendingScrollRestore = nil

        DispatchQueue.main.async { [weak self] in
            self?.webView.scrollView.setContentOffset(targetOffset, animated: false)
        }
    }
    
    // MARK: - State Update (called by coordinator)
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

            // Update tab manager
            tabManager?.updateActiveTab(
                title: webView.title,
                url: currentURL,
                isSecure: currentURL.scheme == "https",
                scrollPosition: currentScrollPosition,
                isLoading: false
            )
        }

        restorePendingScrollPositionIfNeeded()

        // Throttled snapshot - only take one every 5 seconds
        let now = Date().timeIntervalSince1970
        if now - lastSnapshotTime > snapshotMinInterval {
            lastSnapshotTime = now

            // Use smaller snapshot config for memory efficiency
            let snapshotConfig = WKSnapshotConfiguration()
            snapshotConfig.afterScreenUpdates = false

            webView.takeSnapshot(with: snapshotConfig) { [weak self] image, _ in
                if let image = image {
                    // Downscale for tab thumbnail (saves memory)
                    let thumbSize = CGSize(width: 200, height: 300)
                    UIGraphicsBeginImageContextWithOptions(thumbSize, true, 1.0)
                    image.draw(in: CGRect(origin: .zero, size: thumbSize))
                    let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()

                    Task { @MainActor [weak self] in
                        self?.tabManager?.updateActiveTab(snapshot: thumbnail)
                    }
                }
            }
        }

        // Re-inject cosmetic scripts for SPA navigation
        webView.evaluateJavaScript("""
            if (window.__cyberAdBlockInjected) {
                window.__cyberAdBlockInjected = false;
            }
            if (window.__cyberTRv2) {
                window.__cyberTRv2 = false;
            }
        """) { _, _ in }

        // Re-run ad blocking scripts on every page finish
        if let engine = adBlockEngine, engine.isEnabled {
            webView.evaluateJavaScript(AdBlockEngine.cosmeticFilterScript) { _, _ in }
            webView.evaluateJavaScript(AdBlockEngine.turkishNewsCosmeticScript) { _, _ in }
            webView.evaluateJavaScript(AdBlockEngine.turkishStreamingAdBlockScript) { _, _ in }
        }

        isNavigatingProgrammatically = false
    }
}

// MARK: - WebView Coordinator
@MainActor
class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
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
            absolute.contains("manifest")
    }
    
    // MARK: - WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "adBlocked" {
            if let body = message.body as? [String: Any] {
                let count = body["count"] as? Int ?? 1
                let urlStr = body["url"] as? String ?? ""
                
                store?.adBlockEngine?.handleBlockedAd(count: count, domain: urlStr)
                store?.tabManager?.incrementBlockedAds()
            }
        } else if message.name == "extensionAction" {
            if let body = message.body as? [String: Any] {
                let action = body["action"] as? String ?? ""
                print("[Extension] Action: \(action)")
            }
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
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        store?.isLoading = false
        store?.webView.scrollView.refreshControl?.endRefreshing()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        store?.handleWebContentProcessTermination()
    }
    
    // MARK: - Navigation Policy (Layer 2: Domain blocking fallback)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if isLikelyMediaRequest(url) {
            decisionHandler(.allow)
            return
        }
        
        // Layer 2: Block ad domains at the navigation level
        if let engine = store?.adBlockEngine, engine.isEnabled {
            if engine.shouldBlockURL(url) {
                print("[AdBlock] ğŸ›¡ï¸ Blocked: \(url.host ?? url.absoluteString)")
                engine.handleBlockedAd(count: 1, domain: url.host ?? "")
                store?.tabManager?.incrementBlockedAds()
                decisionHandler(.cancel)
                return
            }
        }
        
        // Block Turkish gambling/betting site redirects
        if let host = url.host?.lowercased() {
            let gamblingPatterns = ["bet", "casino", "bahis", "slot", "jackpot", "spin"]
            if let currentHost = webView.url?.host?.lowercased(),
               currentHost != host {
                let isGambling = gamblingPatterns.contains(where: { host.contains($0) })
                if isGambling {
                    print("[AdBlock] ğŸ° Gambling redirect blocked: \(host)")
                    store?.adBlockEngine?.handleBlockedAd(count: 1, domain: host)
                    store?.tabManager?.incrementBlockedAds()
                    decisionHandler(.cancel)
                    return
                }
            }
        }
        
        // Handle links that try to open new windows
        if navigationAction.targetFrame == nil {
            // Block gambling popup targets
            if let host = url.host?.lowercased() {
                let gamblingPatterns = ["bet", "casino", "bahis", "slot", "jackpot", "spin", "bonus"]
                let isGambling = gamblingPatterns.contains(where: { host.contains($0) })
                if isGambling {
                    print("[AdBlock] ğŸ° Popup to gambling site blocked: \(host)")
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

    // MARK: - Response Policy (catches sub-resource loads)
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        // Don't block video/media content types
        let contentType = navigationResponse.response.mimeType ?? ""
        if contentType.hasPrefix("video/") || contentType.hasPrefix("audio/") || contentType.contains("mpegurl") || contentType.contains("mp2t") {
            decisionHandler(.allow)
            return
        }

        if let url = navigationResponse.response.url,
           let engine = store?.adBlockEngine,
           engine.isEnabled,
           !navigationResponse.isForMainFrame,
           engine.shouldBlockURL(url) {
            print("[AdBlock] ğŸ›¡ï¸ Response blocked: \(url.host ?? "")")
            engine.handleBlockedAd(count: 1, domain: url.host ?? "")
            store?.tabManager?.incrementBlockedAds()
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    
    // MARK: - WKUIDelegate
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Block gambling site popups
        if let url = navigationAction.request.url,
           let host = url.host?.lowercased() {
            let gamblingPatterns = ["bet", "casino", "bahis", "slot", "jackpot", "spin", "bonus", "poker"]
            if gamblingPatterns.contains(where: { host.contains($0) }) {
                print("[AdBlock] ğŸ° Popup blocked: \(host)")
                return nil
            }
        }
        // Load legitimate links in the same webview
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
    
    // Handle JavaScript alerts
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @Sendable () -> Void) {
        completionHandler()
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        completionHandler(true)
    }
}

// MARK: - WebView SwiftUI Wrapper
@MainActor
struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var store: WebViewStore
    
    func makeUIView(context: Context) -> WKWebView {
        return store.webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Nothing to do here â€” all navigation is handled imperatively via WebViewStore
    }
}
