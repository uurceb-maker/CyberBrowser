import SwiftUI

// MARK: - Main Content View
struct ContentView: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var adBlockEngine: AdBlockEngine
    @EnvironmentObject var extensionManager: ExtensionManager
    
    // WebView store — manages the WKWebView lifecycle
    @StateObject private var webViewStore = WebViewStore()
    
    // UI state
    @State private var showMenu: Bool = false
    @State private var showTabManager: Bool = false
    @State private var displayURL: String = "https://www.google.com"
    
    var body: some View {
        ZStack {
            // Full black background
            Color.cyberBlack.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Ad Block Banner (Top)
                AdBlockBanner()
                    .zIndex(1)
                
                // MARK: - Address Bar
                AddressBar(
                    urlString: $displayURL,
                    isSecure: $webViewStore.isSecure,
                    isLoading: $webViewStore.isLoading,
                    onCommit: { input in
                        webViewStore.loadURLString(input)
                    }
                )
                
                // Loading progress bar
                if webViewStore.isLoading {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.cyberYellow.opacity(0.3),
                                        Color.cyberYellow,
                                        Color.cyberYellow.opacity(0.3)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2)
                            .frame(width: geometry.size.width * 0.6)
                            .offset(x: webViewStore.isLoading ? geometry.size.width * 0.4 : -geometry.size.width * 0.6)
                            .animation(
                                .linear(duration: 1.5).repeatForever(autoreverses: false),
                                value: webViewStore.isLoading
                            )
                    }
                    .frame(height: 2)
                }
                
                // MARK: - Web View
                WebViewContainer(store: webViewStore)
                
                // MARK: - Bottom Navigation Bar
                BottomNavBar(
                    canGoBack: webViewStore.canGoBack,
                    canGoForward: webViewStore.canGoForward,
                    tabCount: tabManager.tabs.count,
                    onBack: {
                        webViewStore.goBack()
                    },
                    onForward: {
                        webViewStore.goForward()
                    },
                    onSearch: {
                        // Focus address bar — noop for now, user can tap it
                    },
                    onTabs: {
                        // Save current tab state before showing tab manager
                        if let url = webViewStore.webView.url {
                            tabManager.updateActiveTab(
                                title: webViewStore.pageTitle,
                                url: url,
                                isSecure: webViewStore.isSecure
                            )
                        }
                        showTabManager = true
                    },
                    onMenu: {
                        showMenu = true
                    }
                )
            }
        }
        .statusBarHidden(false)
        .onAppear {
            // Connect stores
            webViewStore.adBlockEngine = adBlockEngine
            webViewStore.tabManager = tabManager
            webViewStore.extensionManager = extensionManager
            
            // Inject scripts
            webViewStore.injectScripts()
            
            // Load initial URL
            let initialURL = tabManager.activeTab.url
            webViewStore.loadURL(initialURL)
        }
        .onChange(of: webViewStore.currentURLString) { newURL in
            displayURL = newURL
        }
        .onChange(of: tabManager.activeTabIndex) { _ in
            // When tab changes, load the new tab's URL
            let tab = tabManager.activeTab
            webViewStore.loadURL(tab.url)
            displayURL = tab.url.absoluteString
        }
        .fullScreenCover(isPresented: $showTabManager) {
            TabManagerView(
                onTabSelected: { url in
                    webViewStore.loadURL(url)
                    displayURL = url.absoluteString
                },
                onNewTab: { url in
                    webViewStore.loadURL(url)
                    displayURL = url.absoluteString
                }
            )
            .environmentObject(tabManager)
        }
        .sheet(isPresented: $showMenu) {
            MenuView()
                .environmentObject(adBlockEngine)
                .environmentObject(extensionManager)
                .environmentObject(tabManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environmentObject(TabManager())
        .environmentObject(AdBlockEngine())
        .environmentObject(ExtensionManager())
}
