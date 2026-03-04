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
class WebViewStore: ObservableObject {
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var pageTitle: String = "Yeni Sekme"
    @Published var isSecure: Bool = true
    @Published var currentURLString: String = "https://www.google.com"
    let homeURL = URL(string: "https://www.google.com")!
    
    // The WKWebView instance — created once, reused
    private(set) var webView: WKWebView!
    private var coordinator: WebViewCoordinator!
    private var refreshControl: UIRefreshControl?
    
    // Reference to managers (set from outside)
    weak var adBlockEngine: AdBlockEngine?
    weak var tabManager: TabManager?
    weak var extensionManager: ExtensionManager?
    
    private var isNavigatingProgrammatically = false
    
    // Snapshot throttling — only take snapshots every 5 seconds max
    private var lastSnapshotTime: TimeInterval = 0
    private let snapshotMinInterval: TimeInterval = 5.0
    
    init() {
        self.coordinator = WebViewCoordinator(store: self)
        self.webView = createWebView()
        
        // Listen for background EasyList download completion
        NotificationCenter.default.addObserver(
            forName: .adBlockRulesUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[WebView] 🔄 EasyList downloaded — re-injecting rules")
            self?.injectScripts()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func createWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Media playback
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        
        // Content controller
        let contentController = WKUserContentController()
        contentController.add(coordinator, name: "adBlocked")
        contentController.add(coordinator, name: "extensionAction")
        config.userContentController = contentController
        config.websiteDataStore = .default()
        
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = coordinator
        wv.uiDelegate = coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        
        // Use standard Safari iOS user agent — NO custom suffix
        // This prevents Google CAPTCHA/verification loops
        wv.customUserAgent = nil
        
        let refresh = UIRefreshControl()
        refresh.addTarget(coordinator, action: #selector(WebViewCoordinator.handlePullToRefresh(_:)), for: .valueChanged)
        wv.scrollView.refreshControl = refresh
        self.refreshControl = refresh
        
        return wv
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
        
        // Extension scripts — only inject for main frame by default
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
            self?.injectScripts()
            completion()
        }
    }
    
    // MARK: - Navigation Actions
    func loadURL(_ url: URL) {
        isNavigatingProgrammatically = true
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
    
    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }
    
    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }
    
    func reload() {
        webView.reload()
    }
    
    func stopLoading() {
        webView.stopLoading()
        DispatchQueue.main.async { [weak self] in
            self?.isLoading = false
        }
    }
    
    func goHome() {
        loadURL(homeURL)
    }
    
    // MARK: - State Update (called by coordinator)
    func updateNavigationState() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.canGoBack = self.webView.canGoBack
            self.canGoForward = self.webView.canGoForward
        }
    }
    
    func handlePageFinished() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.refreshControl?.endRefreshing()
            self.canGoBack = self.webView.canGoBack
            self.canGoForward = self.webView.canGoForward
            self.pageTitle = self.webView.title ?? "Sayfa"
            
            if let currentURL = self.webView.url {
                self.currentURLString = currentURL.absoluteString
                self.isSecure = currentURL.scheme == "https"
                
                // Update tab manager
                self.tabManager?.updateActiveTab(
                    title: self.webView.title,
                    url: currentURL,
                    isSecure: currentURL.scheme == "https"
                )
            }
            
            // Throttled snapshot — only take one every 5 seconds
            let now = Date().timeIntervalSince1970
            if now - self.lastSnapshotTime > self.snapshotMinInterval {
                self.lastSnapshotTime = now
                
                // Use smaller snapshot config for memory efficiency
                let snapshotConfig = WKSnapshotConfiguration()
                snapshotConfig.afterScreenUpdates = false
                
                self.webView.takeSnapshot(with: snapshotConfig) { [weak self] image, _ in
                    if let image = image {
                        // Downscale for tab thumbnail (saves memory)
                        let thumbSize = CGSize(width: 200, height: 300)
                        UIGraphicsBeginImageContextWithOptions(thumbSize, true, 1.0)
                        image.draw(in: CGRect(origin: .zero, size: thumbSize))
                        let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
                        UIGraphicsEndImageContext()
                        
                        DispatchQueue.main.async {
                            self?.tabManager?.updateActiveTab(snapshot: thumbnail)
                        }
                    }
                }
            }

            // Re-inject cosmetic scripts for SPA navigation
            self.webView.evaluateJavaScript("""
                if (!window.__cyberAdBlockInjected) {
                    // Script will be re-injected by WKUserScript on next navigation
                } else {
                    // Force re-run hiding for SPA pages
                    window.__cyberAdBlockInjected = false;
                }
            """) { _, _ in }

            // Re-run ad blocking scripts on every page finish
            if let engine = self.adBlockEngine, engine.isEnabled {
                self.webView.evaluateJavaScript(AdBlockEngine.cosmeticFilterScript) { _, _ in }
            }
            
            self.isNavigatingProgrammatically = false
        }
    }
}

// MARK: - WebView Coordinator
class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private weak var store: WebViewStore?
    
    init(store: WebViewStore) {
        self.store = store
    }
    
    @objc func handlePullToRefresh(_ sender: UIRefreshControl) {
        store?.reload()
    }
    
    // MARK: - WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "adBlocked" {
            if let body = message.body as? [String: Any] {
                let count = body["count"] as? Int ?? 1
                let urlStr = body["url"] as? String ?? ""
                
                DispatchQueue.main.async { [weak self] in
                    self?.store?.adBlockEngine?.handleBlockedAd(count: count, domain: urlStr)
                    self?.store?.tabManager?.incrementBlockedAds()
                }
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
        DispatchQueue.main.async { [weak self] in
            self?.store?.isLoading = true
            self?.store?.updateNavigationState()
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        store?.handlePageFinished()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.store?.isLoading = false
            self?.store?.webView.scrollView.refreshControl?.endRefreshing()
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.store?.isLoading = false
            self?.store?.webView.scrollView.refreshControl?.endRefreshing()
        }
    }
    
    // MARK: - Navigation Policy (Layer 2: Domain blocking fallback)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        // Layer 2: Block ad domains at the navigation level
        // This catches requests even if WKContentRuleList failed to compile
        if let engine = store?.adBlockEngine, engine.isEnabled {
            if engine.shouldBlockURL(url) {
                print("[AdBlock] 🛡️ Blocked: \(url.host ?? url.absoluteString)")
                DispatchQueue.main.async {
                    engine.handleBlockedAd(count: 1, domain: url.host ?? "")
                    self.store?.tabManager?.incrementBlockedAds()
                }
                decisionHandler(.cancel)
                return
            }
        }
        
        // Handle links that try to open new windows — load in same webview
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
            return
        }
        
        decisionHandler(.allow)
    }

    // MARK: - Response Policy (catches sub-resource loads)
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
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
            print("[AdBlock] 🛡️ Response blocked: \(url.host ?? "")")
            DispatchQueue.main.async {
                engine.handleBlockedAd(count: 1, domain: url.host ?? "")
                self.store?.tabManager?.incrementBlockedAds()
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
    
    // MARK: - WKUIDelegate
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Load in the same webview instead of opening new window
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
    
    // Handle JavaScript alerts
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}

// MARK: - WebView SwiftUI Wrapper
struct WebViewContainer: UIViewRepresentable {
    @ObservedObject var store: WebViewStore
    
    func makeUIView(context: Context) -> WKWebView {
        return store.webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Nothing to do here — all navigation is handled imperatively via WebViewStore
    }
}
