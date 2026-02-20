import SwiftUI
import WebKit

// MARK: - WKWebView Wrapper
struct WebView: UIViewRepresentable {
    @Binding var url: URL
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var pageTitle: String
    @Binding var isSecure: Bool
    
    let goBack: Bool
    let goForward: Bool
    let reload: Bool
    
    @EnvironmentObject var adBlockEngine: AdBlockEngine
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var extensionManager: ExtensionManager
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        
        // Allow inline media playback (important for background audio)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        
        // Setup content controller with ad-block scripts
        let contentController = WKUserContentController()
        
        // Add ad-block scripts
        for script in adBlockEngine.createUserScripts() {
            contentController.addUserScript(script)
        }
        
        // Add extension scripts
        for script in extensionManager.activeUserScripts(for: url) {
            contentController.addUserScript(script)
        }
        
        // Register message handlers
        contentController.add(context.coordinator, name: "adBlocked")
        contentController.add(context.coordinator, name: "extensionAction")
        
        config.userContentController = contentController
        
        // Data store for privacy
        config.websiteDataStore = .default()
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        
        // Custom user agent
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1 CyberBrowser/1.0"
        
        // Load initial URL
        webView.load(URLRequest(url: url))
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Navigate if URL changed
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
        
        // Handle navigation actions
        if goBack && webView.canGoBack {
            webView.goBack()
        }
        if goForward && webView.canGoForward {
            webView.goForward()
        }
        if reload {
            webView.reload()
        }
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        // MARK: - WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "adBlocked" {
                if let body = message.body as? [String: Any] {
                    let count = body["count"] as? Int ?? 1
                    let urlStr = body["url"] as? String ?? ""
                    
                    DispatchQueue.main.async {
                        self.parent.adBlockEngine.handleBlockedAd(count: count, domain: urlStr)
                        self.parent.tabManager.incrementBlockedAds()
                    }
                }
            } else if message.name == "extensionAction" {
                // Handle extension actions
                if let body = message.body as? [String: Any] {
                    let action = body["action"] as? String ?? ""
                    print("[Extension] Action: \(action)")
                }
            }
        }
        
        // MARK: - WKNavigationDelegate
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.canGoBack = webView.canGoBack
                self.parent.canGoForward = webView.canGoForward
                self.parent.pageTitle = webView.title ?? "Sayfa"
                
                if let currentURL = webView.url {
                    self.parent.url = currentURL
                    self.parent.isSecure = currentURL.scheme == "https"
                    self.parent.tabManager.updateActiveTab(
                        title: webView.title,
                        url: currentURL,
                        isSecure: currentURL.scheme == "https"
                    )
                }
                
                // Take snapshot for tab manager
                webView.takeSnapshot(with: nil) { image, _ in
                    if let image = image {
                        DispatchQueue.main.async {
                            self.parent.tabManager.updateActiveTab(snapshot: image)
                        }
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }
        
        // MARK: - Block navigation to ad domains
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            
            let host = url.host?.lowercased() ?? ""
            
            // Check if the URL matches any blocked domain
            if parent.adBlockEngine.isEnabled {
                for domain in AdBlockEngine.blockedDomains {
                    if host.contains(domain.replacingOccurrences(of: "/", with: "")) {
                        decisionHandler(.cancel)
                        parent.adBlockEngine.handleBlockedAd(count: 1, domain: host)
                        return
                    }
                }
            }
            
            // Block pop-ups from opening new windows
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            
            decisionHandler(.allow)
        }
        
        // MARK: - WKUIDelegate — Block unwanted pop-ups
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Load in the same webview instead of opening a new window
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
